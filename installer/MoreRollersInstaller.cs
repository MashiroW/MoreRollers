// MoreRollers installer: installs the MoreRollers mod into a copy of Buckshot Roulette.
// Copyright (C) 2026 Mash
//
// This program is free software: you can redistribute it and/or modify it under the terms of the
// GNU General Public License as published by the Free Software Foundation, either version 3 of the
// License, or (at your option) any later version.
//
// This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without
// even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
// General Public License for more details.
//
// You should have received a copy of the GNU General Public License along with this program. If
// not, see <https://www.gnu.org/licenses/>.
//
// Built by tools/build_installer.js with the C# compiler that comes with Windows (.NET Framework 4).
// The mod (mod/loader.gd, mod/splitscreen.pck) and the banner are embedded in the exe as resources.
// It does exactly what installer/install.ps1 and installer/uninstall.ps1 do.
//
// Command line, for scripts:
//   MoreRollers-Installer.exe --install   ["<game folder>"] [--quiet]
//   MoreRollers-Installer.exe --uninstall ["<game folder>"] [--quiet]
// Exit code: 0 done, 1 failed, 2 game not found.

using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.IO;
using System.Reflection;
using System.Text;
using System.Text.RegularExpressions;
using System.Windows.Forms;
using Microsoft.Win32;

namespace MoreRollers
{
    /// What the installer does to a game folder, without any UI.
    static class Mod
    {
        public const string FolderName = "splitscreen_mod";
        public const string GameExe = "Buckshot Roulette.exe";
        public const string GameProcess = "Buckshot Roulette";
        public const string CfgName = "override.cfg";
        public const string BackupSuffix = ".before-splitscreen";
        public const string RepoUrl = "https://github.com/MashiroW/MoreRollers";
        public const string DiscordUrl = "https://discord.gg/R4tCHhVJD4";

        static readonly Regex Section = new Regex(@"^\s*\[.*\]\s*$");
        static readonly Regex Comment = new Regex(@"^\s*;");
        static readonly Regex Entry = new Regex(@"^\s*SplitMod\s*=");
        static readonly Regex AutoloadHeader = new Regex(@"^\s*\[autoload\]\s*$");

        // ------------------------------------------------------------ embedded mod

        public static byte[] Resource(string name)
        {
            using (Stream s = Assembly.GetExecutingAssembly().GetManifestResourceStream(name))
            {
                if (s == null) throw new InvalidOperationException("The installer is missing its file " + name + ".");
                MemoryStream m = new MemoryStream();
                s.CopyTo(m);
                return m.ToArray();
            }
        }

        static string loaderText;
        static string LoaderText
        {
            get
            {
                if (loaderText == null) loaderText = Encoding.UTF8.GetString(Resource("loader.gd"));
                return loaderText;
            }
        }

        static string Find(string text, string pattern)
        {
            Match m = Regex.Match(text, pattern);
            return m.Success ? m.Groups[1].Value : null;
        }

        /// Version of the mod in this installer, as written in loader.gd.
        public static string Version { get { return Find(LoaderText, "const MOD_VERSION := \"([^\"]+)\"") ?? "?"; } }

        /// Game version the mod was made for.
        public static string GameVersion { get { return Find(LoaderText, "const GAME_VERSION := \"([^\"]+)\"") ?? "?"; } }

        /// The md5 of every game script the mod replaces, as listed in loader.gd. The mod checks
        /// them at launch and stays off if the game was updated; the installer checks them first.
        static Dictionary<string, string> OriginalMd5()
        {
            Dictionary<string, string> d = new Dictionary<string, string>();
            foreach (Match m in Regex.Matches(LoaderText, "\"(res://[^\"]+)\":\\s*\"([0-9a-f]{32})\""))
                d[m.Groups[1].Value] = m.Groups[2].Value;
            return d;
        }

        // ------------------------------------------------------------ finding the game

        public static bool IsGameDir(string dir)
        {
            return !string.IsNullOrEmpty(dir) && File.Exists(Path.Combine(dir, GameExe));
        }

        /// The folder holding the game's exe, from a folder or exe path typed or picked by the
        /// user (the Steam folder above it works too). Null if there is no game there.
        public static string ResolveGameDir(string given)
        {
            if (string.IsNullOrWhiteSpace(given)) return null;
            given = given.Trim().Trim('"').TrimEnd('\\', '/');
            try
            {
                if (File.Exists(given) && Path.GetFileName(given).Equals(GameExe, StringComparison.OrdinalIgnoreCase))
                    given = Path.GetDirectoryName(given);
                if (IsGameDir(given)) return given;
                string sub = Path.Combine(given, "Buckshot Roulette_windows");
                if (IsGameDir(sub)) return sub;
            }
            catch (ArgumentException) { }
            return null;
        }

        static void AddUnique(List<string> list, string item)
        {
            foreach (string x in list)
                if (string.Equals(x, item, StringComparison.OrdinalIgnoreCase)) return;
            list.Add(item);
        }

        /// Steam install folders, from the registry and libraryfolders.vdf.
        static List<string> SteamLibraries()
        {
            List<string> steams = new List<string>();
            string[,] keys = {
                { @"HKEY_CURRENT_USER\Software\Valve\Steam", "SteamPath" },
                { @"HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Valve\Steam", "InstallPath" },
                { @"HKEY_LOCAL_MACHINE\SOFTWARE\Valve\Steam", "InstallPath" },
            };
            for (int i = 0; i < keys.GetLength(0); i++)
            {
                try
                {
                    string v = Registry.GetValue(keys[i, 0], keys[i, 1], null) as string;
                    if (!string.IsNullOrEmpty(v)) AddUnique(steams, v.Replace('/', '\\'));
                }
                catch (Exception) { }
            }
            AddUnique(steams, @"C:\Program Files (x86)\Steam");
            List<string> libs = new List<string>();
            foreach (string steam in steams)
            {
                AddUnique(libs, steam);
                try
                {
                    string vdf = Path.Combine(steam, @"steamapps\libraryfolders.vdf");
                    if (!File.Exists(vdf)) continue;
                    foreach (Match m in Regex.Matches(File.ReadAllText(vdf), "\"path\"\\s+\"([^\"]+)\""))
                        AddUnique(libs, m.Groups[1].Value.Replace(@"\\", @"\"));
                }
                catch (Exception) { }
            }
            return libs;
        }

        /// The game's folder in any Steam library, or null.
        public static string FindGame()
        {
            foreach (string lib in SteamLibraries())
            {
                foreach (string sub in new string[] { @"steamapps\common\Buckshot Roulette\Buckshot Roulette_windows", @"steamapps\common\Buckshot Roulette" })
                {
                    string dir = Path.Combine(lib, sub);
                    if (IsGameDir(dir)) return dir;
                }
            }
            return null;
        }

        public static bool GameRunning()
        {
            return Process.GetProcessesByName(GameProcess).Length > 0;
        }

        // ------------------------------------------------------------ game version

        /// The md5 of every file in the pack embedded in the game's exe (Godot 4 PCK, format 2:
        /// its file list stores each file's md5), read the same way as tools/pck.js.
        static Dictionary<string, string> GamePackMd5(string exe)
        {
            Dictionary<string, string> d = new Dictionary<string, string>();
            using (FileStream f = new FileStream(exe, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete))
            using (BinaryReader r = new BinaryReader(new BufferedStream(f, 1 << 16)))
            {
                long start = 0;
                f.Seek(-12, SeekOrigin.End);
                long size = r.ReadInt64();
                if (Encoding.ASCII.GetString(r.ReadBytes(4)) == "GDPC") start = f.Length - 12 - size;
                r.BaseStream.Seek(start, SeekOrigin.Begin);
                if (Encoding.ASCII.GetString(r.ReadBytes(4)) != "GDPC") throw new InvalidDataException("no game data found in " + GameExe);
                r.BaseStream.Seek(start + 96, SeekOrigin.Begin);
                int count = r.ReadInt32();
                if (count < 0 || count > 1000000) throw new InvalidDataException("unexpected game data");
                for (int i = 0; i < count; i++)
                {
                    int len = r.ReadInt32();
                    if (len < 0 || len > 4096) throw new InvalidDataException("unexpected game data");
                    string name = Encoding.UTF8.GetString(r.ReadBytes(len)).TrimEnd('\0');
                    r.ReadInt64(); // offset
                    r.ReadInt64(); // size
                    byte[] md5 = r.ReadBytes(16);
                    r.ReadInt32(); // flags
                    d[name] = BitConverter.ToString(md5).Replace("-", "").ToLowerInvariant();
                }
            }
            return d;
        }

        /// Game scripts that differ from the version the mod was made for (empty: supported).
        /// Throws if the game's data can't be read.
        public static List<string> ChangedScripts(string dir)
        {
            Dictionary<string, string> pack = GamePackMd5(Path.Combine(dir, GameExe));
            List<string> changed = new List<string>();
            foreach (KeyValuePair<string, string> kv in OriginalMd5())
            {
                string md5;
                if (!pack.TryGetValue(kv.Key, out md5) || md5 != kv.Value) changed.Add(kv.Key);
            }
            return changed;
        }

        // ------------------------------------------------------------ install state

        static string CfgPath(string dir) { return Path.Combine(dir, CfgName); }
        static string ModDir(string dir) { return Path.Combine(dir, FolderName); }

        /// Version of the mod installed in that folder, "" if its files are there but unreadable,
        /// null if they are not there.
        public static string InstalledVersion(string dir)
        {
            string loader = Path.Combine(ModDir(dir), "loader.gd");
            if (!File.Exists(loader)) return null;
            try { return Find(File.ReadAllText(loader), "const MOD_VERSION := \"([^\"]+)\"") ?? ""; }
            catch (Exception) { return ""; }
        }

        /// Whether override.cfg loads the mod.
        public static bool Registered(string dir)
        {
            return ReadCfg(CfgPath(dir)).Exists(l => Entry.IsMatch(l));
        }

        public static bool AnythingInstalled(string dir)
        {
            return InstalledVersion(dir) != null || Registered(dir) || File.Exists(CfgPath(dir) + BackupSuffix);
        }

        static List<string> ReadCfg(string path)
        {
            List<string> lines = new List<string>();
            if (File.Exists(path)) lines.AddRange(Regex.Split(File.ReadAllText(path), "\r?\n"));
            return lines;
        }

        /// Godot reads override.cfg as UTF-8: written without a BOM.
        static void WriteCfg(string path, List<string> lines)
        {
            File.WriteAllText(path, string.Join("\n", lines).TrimEnd() + "\n", new UTF8Encoding(false));
        }

        static bool IsSetting(string line)
        {
            return line.Trim() != "" && !Section.IsMatch(line) && !Comment.IsMatch(line);
        }

        // ------------------------------------------------------------ install / uninstall

        public static void Install(string dir)
        {
            // 1. Mod files
            string target = ModDir(dir);
            Directory.CreateDirectory(target);
            File.WriteAllBytes(Path.Combine(target, "loader.gd"), Resource("loader.gd"));
            File.WriteAllBytes(Path.Combine(target, "splitscreen.pck"), Resource("splitscreen.pck"));

            // 2. override.cfg: Godot reads it at startup and loads loader.gd as the "SplitMod" autoload
            string cfg = CfgPath(dir);
            string entry = "SplitMod=\"*" + Path.Combine(target, "loader.gd").Replace('\\', '/') + "\"";
            List<string> old = ReadCfg(cfg);
            // Back up an override.cfg that holds settings of its own (not one that only has this mod's line).
            if (old.Exists(l => IsSetting(l) && !Entry.IsMatch(l)) && !File.Exists(cfg + BackupSuffix))
                File.Copy(cfg, cfg + BackupSuffix);
            List<string> lines = old.FindAll(l => !Entry.IsMatch(l));
            int header = lines.FindIndex(l => AutoloadHeader.IsMatch(l));
            if (header >= 0)
            {
                lines.Insert(header + 1, entry);
            }
            else
            {
                if (lines.Count > 0 && lines[lines.Count - 1].Trim() != "") lines.Add("");
                lines.Add("[autoload]");
                lines.Add("");
                lines.Add(entry);
            }
            WriteCfg(cfg, lines);
        }

        public static void Uninstall(string dir)
        {
            // 1. Remove the mod's autoload; delete override.cfg if nothing else is left in it
            string cfg = CfgPath(dir);
            if (File.Exists(cfg))
            {
                List<string> lines = ReadCfg(cfg).FindAll(l => !Entry.IsMatch(l));
                if (!lines.Exists(IsSetting))
                {
                    File.Delete(cfg);
                }
                else
                {
                    // Drop an [autoload] header left without entries.
                    List<string> kept = new List<string>();
                    for (int i = 0; i < lines.Count; i++)
                    {
                        if (AutoloadHeader.IsMatch(lines[i]))
                        {
                            int j = i + 1;
                            while (j < lines.Count && lines[j].Trim() == "") j++;
                            if (j >= lines.Count || Section.IsMatch(lines[j])) { i = j - 1; continue; }
                        }
                        kept.Add(lines[i]);
                    }
                    WriteCfg(cfg, kept);
                }
            }
            if (File.Exists(cfg + BackupSuffix)) File.Delete(cfg + BackupSuffix);

            // 2. Mod files
            string target = ModDir(dir);
            if (Directory.Exists(target)) Directory.Delete(target, true);
        }

        public static bool IsAccessDenied(Exception e)
        {
            return e is UnauthorizedAccessException || (e is IOException && (e.HResult & 0xFFFF) == 5);
        }
    }

    // ================================================================ window

    /// Draws an image scaled to fit, with good filtering (PictureBox scales it roughly).
    class ImagePanel : Panel
    {
        public Image Image;

        public ImagePanel()
        {
            DoubleBuffered = true;
            SetStyle(ControlStyles.ResizeRedraw, true);
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            base.OnPaint(e);
            if (Image == null) return;
            float scale = Math.Min((float)ClientSize.Width / Image.Width, (float)ClientSize.Height / Image.Height);
            float w = Image.Width * scale, h = Image.Height * scale;
            e.Graphics.InterpolationMode = InterpolationMode.HighQualityBicubic;
            e.Graphics.PixelOffsetMode = PixelOffsetMode.HighQuality;
            e.Graphics.DrawImage(Image, (ClientSize.Width - w) / 2, (ClientSize.Height - h) / 2, w, h);
        }
    }

    class InstallerForm : Form
    {
        static readonly Color Back = Color.FromArgb(12, 12, 12);
        static readonly Color Field = Color.FromArgb(28, 28, 28);
        static readonly Color Text1 = Color.FromArgb(235, 235, 235);
        static readonly Color Text2 = Color.FromArgb(150, 150, 150);
        static readonly Color Good = Color.FromArgb(90, 220, 90);
        static readonly Color Warn = Color.FromArgb(255, 190, 70);
        static readonly Color Bad = Color.FromArgb(255, 95, 95);
        static readonly Color Red = Color.FromArgb(180, 22, 22);

        TextBox pathBox;
        Button installButton, uninstallButton;
        FlowLayoutPanel statusPanel;
        string gameDir;
        List<string> changedScripts; // null: version not checked
        float k = 1F; // screen dpi / 96

        public InstallerForm()
        {
            // Laid out at 96 dpi and scaled here to the screen's dpi (fonts, in points, follow on
            // their own). WinForms' own AutoScaleMode scales the size of labels twice.
            using (Graphics g = Graphics.FromHwnd(IntPtr.Zero)) k = g.DpiX / 96F;
#if SNAPSHOT
            string fake = Environment.GetEnvironmentVariable("SNAPSHOT_SCALE");
            if (!string.IsNullOrEmpty(fake)) k = float.Parse(fake, System.Globalization.CultureInfo.InvariantCulture);
#endif
            SuspendLayout();
            Text = "MoreRollers " + Mod.Version + " - installer";
            AutoScaleMode = AutoScaleMode.None;
            Font = new Font("Segoe UI", 9.75F);
            BackColor = Back;
            ForeColor = Text1;
            FormBorderStyle = FormBorderStyle.FixedSingle;
            MaximizeBox = false;
            StartPosition = FormStartPosition.CenterScreen;
            ClientSize = new Size(S(640), S(520));
            try { Icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath); } catch (Exception) { }

            ImagePanel banner = new ImagePanel();
            banner.Bounds = R(10, 8, 620, 186);
            banner.Image = Image.FromStream(new MemoryStream(Mod.Resource("banner.png")));
            Controls.Add(banner);

            Label intro = MakeLabel("Adds LOCAL SPLITSCREEN to Buckshot Roulette: 2 to 4 seats on one PC, each local player with their own view, and CPU players for the empty seats (or play alone against them).", 24, 200, 592, 40);
            intro.ForeColor = Text2;

            MakeLabel("Buckshot Roulette folder", 24, 248, 400, 20);
            pathBox = new TextBox();
            pathBox.Bounds = R(24, 270, 488, 26);
            pathBox.BackColor = Field;
            pathBox.ForeColor = Text1;
            pathBox.BorderStyle = BorderStyle.FixedSingle;
            pathBox.TextChanged += delegate { RefreshState(); };
            Controls.Add(pathBox);
            Button browse = MakeButton("Browse...", 520, 269, 96, 28, Field);
            browse.Click += delegate { Browse(); };

            statusPanel = new FlowLayoutPanel();
            statusPanel.Bounds = R(24, 306, 592, 100);
            statusPanel.FlowDirection = FlowDirection.TopDown;
            statusPanel.WrapContents = false;
            Controls.Add(statusPanel);

            installButton = MakeButton("Install", 24, 414, 290, 44, Red);
            installButton.Font = new Font("Segoe UI Semibold", 12F);
            installButton.Click += delegate { DoInstall(); };
            uninstallButton = MakeButton("Uninstall", 326, 414, 290, 44, Field);
            uninstallButton.Font = new Font("Segoe UI", 12F);
            uninstallButton.Click += delegate { DoUninstall(); };

            LinkLabel github = MakeLink("GitHub page", Mod.RepoUrl, 24, 484);
            MakeLink("Discord", Mod.DiscordUrl, 0, 484).Left = github.Right + S(16);
            Label credits = MakeLabel("v" + Mod.Version + "  -  by Mash  -  GPL-3.0", 316, 486, 300, 20);
            credits.TextAlign = ContentAlignment.MiddleRight;
            credits.ForeColor = Text2;

            ResumeLayout(false);
            PerformLayout();

            string found = Mod.FindGame();
            if (found != null) pathBox.Text = found;
            else RefreshState();
            ActiveControl = installButton.Enabled ? (Control)installButton : browse;
        }

        int S(int v) { return (int)Math.Round(v * k); }
        Rectangle R(int x, int y, int w, int h) { return new Rectangle(S(x), S(y), S(w), S(h)); }

        Label MakeLabel(string text, int x, int y, int w, int h)
        {
            Label l = new Label();
            l.Text = text;
            l.Bounds = R(x, y, w, h);
            Controls.Add(l);
            return l;
        }

        Button MakeButton(string text, int x, int y, int w, int h, Color color)
        {
            Button b = new Button();
            b.Text = text;
            b.Bounds = R(x, y, w, h);
            b.FlatStyle = FlatStyle.Flat;
            b.FlatAppearance.BorderColor = Color.FromArgb(90, 90, 90);
            b.BackColor = color;
            b.ForeColor = Text1;
            b.UseVisualStyleBackColor = false;
            b.Cursor = Cursors.Hand;
            Controls.Add(b);
            return b;
        }

        LinkLabel MakeLink(string text, string url, int x, int y)
        {
            LinkLabel l = new LinkLabel();
            l.Text = text;
            l.AutoSize = true;
            l.Location = new Point(S(x), S(y));
            l.LinkColor = Good;
            l.ActiveLinkColor = Text1;
            l.VisitedLinkColor = Good;
            l.LinkClicked += delegate { Open(url); };
            Controls.Add(l);
            return l;
        }

        void AddStatus(string text, Color color)
        {
            Label l = new Label();
            l.Text = text;
            l.ForeColor = color;
            l.AutoSize = true;
            l.MaximumSize = new Size(statusPanel.ClientSize.Width, 0);
            l.Margin = new Padding(0, 0, 0, S(4));
            statusPanel.Controls.Add(l);
        }

        static void Open(string url)
        {
            try { Process.Start(new ProcessStartInfo(url) { UseShellExecute = true }); } catch (Exception) { }
        }

        void Browse()
        {
            using (OpenFileDialog d = new OpenFileDialog())
            {
                d.Title = "Select Buckshot Roulette.exe";
                d.Filter = "Buckshot Roulette|" + Mod.GameExe + "|Programs (*.exe)|*.exe";
                d.CheckFileExists = true;
                if (Directory.Exists(pathBox.Text)) d.InitialDirectory = pathBox.Text;
                if (d.ShowDialog(this) != DialogResult.OK) return;
                string dir = Mod.ResolveGameDir(d.FileName) ?? Path.GetDirectoryName(d.FileName);
                pathBox.Text = dir;
            }
        }

        /// Reads the folder in the box again and says what the buttons will do.
        void RefreshState()
        {
            statusPanel.SuspendLayout();
            statusPanel.Controls.Clear();
            gameDir = Mod.ResolveGameDir(pathBox.Text);
            changedScripts = null;
            if (gameDir == null)
            {
                if (pathBox.Text.Trim() == "")
                    AddStatus("Buckshot Roulette wasn't found automatically. Click Browse... and select Buckshot Roulette.exe in the game's folder (in Steam: right-click the game > Manage > Browse local files).", Warn);
                else
                    AddStatus("There is no Buckshot Roulette.exe in this folder.", Bad);
                installButton.Text = "Install";
                installButton.Enabled = false;
                uninstallButton.Enabled = false;
                statusPanel.ResumeLayout();
                return;
            }

            try
            {
                changedScripts = Mod.ChangedScripts(gameDir);
                if (changedScripts.Count == 0)
                    AddStatus("Buckshot Roulette " + Mod.GameVersion + " found: supported.", Good);
                else
                    AddStatus("This copy of Buckshot Roulette is not " + Mod.GameVersion + ", the version this mod was made for (the game was probably updated). The mod would stay turned off and the game would run normally. Look for a newer MoreRollers on the GitHub page.", Warn);
            }
            catch (Exception)
            {
                AddStatus("Buckshot Roulette found, but its version couldn't be checked. The mod checks it again at launch.", Warn);
            }

            string installed = Mod.InstalledVersion(gameDir);
            bool registered = Mod.Registered(gameDir);
            if (installed != null && registered)
            {
                AddStatus("MoreRollers " + (installed == "" ? "" : installed + " ") + "is installed. Start the game from Steam: LOCAL SPLITSCREEN is in the main menu, under MULTIPLAYER.", Good);
                installButton.Text = installed == Mod.Version ? "Reinstall" : "Update to " + Mod.Version;
            }
            else if (installed != null || registered)
            {
                AddStatus("MoreRollers is only partly installed: install it again to repair it.", Warn);
                installButton.Text = "Repair";
            }
            else
            {
                AddStatus("MoreRollers is not installed in this copy yet.", Text2);
                installButton.Text = "Install";
            }
            if (Mod.GameRunning())
                AddStatus("Buckshot Roulette is running: close it before installing or uninstalling.", Warn);
            installButton.Enabled = true;
            uninstallButton.Enabled = Mod.AnythingInstalled(gameDir);
            statusPanel.ResumeLayout();
        }

        bool CheckNotRunning()
        {
            if (!Mod.GameRunning()) return true;
            MessageBox.Show(this, "Buckshot Roulette is running. Close the game, then try again.", Text, MessageBoxButtons.OK, MessageBoxIcon.Warning);
            RefreshState();
            return false;
        }

        void DoInstall()
        {
            if (gameDir == null || !CheckNotRunning()) return;
            if (changedScripts != null && changedScripts.Count > 0)
            {
                DialogResult answer = MessageBox.Show(this,
                    "This copy of Buckshot Roulette is not " + Mod.GameVersion + ", the version this mod was made for. " +
                    "The mod would stay turned off: the game would run normally, without LOCAL SPLITSCREEN.\n\nInstall anyway?",
                    Text, MessageBoxButtons.YesNo, MessageBoxIcon.Warning, MessageBoxDefaultButton.Button2);
                if (answer != DialogResult.Yes) return;
            }
            Run("install", delegate { Mod.Install(gameDir); },
                "MoreRollers " + Mod.Version + " is installed.\n\nStart Buckshot Roulette from Steam as usual: LOCAL SPLITSCREEN is in the main menu, right under MULTIPLAYER.");
        }

        void DoUninstall()
        {
            if (gameDir == null || !CheckNotRunning()) return;
            if (MessageBox.Show(this, "Remove MoreRollers from this copy of Buckshot Roulette?", Text, MessageBoxButtons.YesNo, MessageBoxIcon.Question) != DialogResult.Yes)
                return;
            Run("uninstall", delegate { Mod.Uninstall(gameDir); },
                "MoreRollers is uninstalled. The game folder is back to how it was.");
        }

        void Run(string action, MethodInvoker work, string done)
        {
            try
            {
                Cursor = Cursors.WaitCursor;
                work();
                Cursor = Cursors.Default;
                MessageBox.Show(this, done, Text, MessageBoxButtons.OK, MessageBoxIcon.Information);
            }
            catch (Exception e)
            {
                Cursor = Cursors.Default;
                if (Mod.IsAccessDenied(e))
                {
                    DialogResult answer = MessageBox.Show(this,
                        "Windows didn't let the installer write to the game's folder.\n\nTry again as administrator?",
                        Text, MessageBoxButtons.YesNo, MessageBoxIcon.Warning);
                    if (answer == DialogResult.Yes) Program.RunElevated(action, gameDir);
                }
                else
                {
                    MessageBox.Show(this, "The " + action + " failed:\n\n" + e.Message, Text, MessageBoxButtons.OK, MessageBoxIcon.Error);
                }
            }
            RefreshState();
        }

#if SNAPSHOT
        /// Test build only: renders the window to a PNG instead of showing it.
        public void Snapshot(string png)
        {
            string dir = Environment.GetEnvironmentVariable("SNAPSHOT_DIR");
            if (dir != null) pathBox.Text = dir;
            StartPosition = FormStartPosition.Manual;
            Location = new Point(-4000, -4000);
            ShowInTaskbar = false;
            Show();
            Application.DoEvents();
            using (Bitmap b = new Bitmap(Width, Height))
            {
                DrawToBitmap(b, new Rectangle(0, 0, Width, Height));
                b.Save(png, System.Drawing.Imaging.ImageFormat.Png);
            }
            Close();
        }
#endif
    }

    static class Program
    {
        [STAThread]
        static int Main(string[] args)
        {
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);

            string action = null, dir = null;
            bool quiet = false;
            foreach (string a in args)
            {
                if (a == "--install") action = "install";
                else if (a == "--uninstall") action = "uninstall";
                else if (a == "--quiet") quiet = true;
#if SNAPSHOT
                else if (a.StartsWith("--snapshot=")) { new InstallerForm().Snapshot(a.Substring(11)); return 0; }
#endif
                else dir = a;
            }
            if (action == null)
            {
                Application.Run(new InstallerForm());
                return 0;
            }
            return RunCommand(action, dir, quiet);
        }

        /// --install / --uninstall without the window (also used to retry as administrator).
        static int RunCommand(string action, string given, bool quiet)
        {
            string title = "MoreRollers " + Mod.Version + " - installer";
            string dir = given != null ? Mod.ResolveGameDir(given) : Mod.FindGame();
            if (dir == null)
            {
                if (!quiet) MessageBox.Show("Buckshot Roulette wasn't found" + (given != null ? " in " + given : "") + ".", title, MessageBoxButtons.OK, MessageBoxIcon.Error);
                return 2;
            }
            try
            {
                if (Mod.GameRunning()) throw new InvalidOperationException("Buckshot Roulette is running. Close the game, then try again.");
                if (action == "install") Mod.Install(dir);
                else Mod.Uninstall(dir);
                if (!quiet)
                    MessageBox.Show(action == "install"
                        ? "MoreRollers " + Mod.Version + " is installed in:\n" + dir
                        : "MoreRollers is uninstalled from:\n" + dir, title, MessageBoxButtons.OK, MessageBoxIcon.Information);
                return 0;
            }
            catch (Exception e)
            {
                if (!quiet) MessageBox.Show("The " + action + " failed:\n\n" + e.Message, title, MessageBoxButtons.OK, MessageBoxIcon.Error);
                return 1;
            }
        }

        /// Runs the same action again with administrator rights (Windows asks the user first).
        public static void RunElevated(string action, string dir)
        {
            ProcessStartInfo psi = new ProcessStartInfo(Application.ExecutablePath, "--" + action + " \"" + dir + "\"");
            psi.UseShellExecute = true;
            psi.Verb = "runas";
            try
            {
                Process p = Process.Start(psi);
                if (p != null) p.WaitForExit();
            }
            catch (System.ComponentModel.Win32Exception) { } // the user said no
        }
    }
}
