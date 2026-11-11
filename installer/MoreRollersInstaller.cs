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
// The mod (mod/loader.gd, mod/splitscreen.pck) and the window's font are embedded in the exe as
// resources. It does exactly what installer/install.ps1 and installer/uninstall.ps1 do; its window
// is in TerminalWindow.cs.
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

    static class Program
    {
        /// Buckshot Roulette on Steam, for the PLAY button.
        public const int SteamAppId = 2835570;

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
                else if (a.StartsWith("--snapshot=")) { TerminalWindow.Snapshot(a.Substring(11)); return 0; }
#endif
                else dir = a;
            }
            if (action == null)
            {
                Application.Run(new TerminalWindow());
                return 0;
            }
            return RunCommand(action, dir, quiet);
        }

        /// --install / --uninstall without the window (also used to retry as administrator).
        static int RunCommand(string action, string given, bool quiet)
        {
            string title = "MoreRollers " + Mod.Version + " installer";
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
        /// Returns its exit code, or -1 if the user said no.
        public static int RunElevated(string action, string dir)
        {
            ProcessStartInfo psi = new ProcessStartInfo(Application.ExecutablePath, "--" + action + " \"" + dir + "\" --quiet");
            psi.UseShellExecute = true;
            psi.Verb = "runas";
            try
            {
                Process p = Process.Start(psi);
                if (p == null) return 1;
                p.WaitForExit();
                return p.ExitCode;
            }
            catch (System.ComponentModel.Win32Exception)
            {
                return -1;
            }
        }
    }
}
