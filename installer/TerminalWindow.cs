// MoreRollers installer: its window.
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
// The window is drawn by hand in the green of the game's online lobby: the VT323 font (SIL Open
// Font License, installer/fonts/OFL.txt), a phosphor glow, scanlines, and the checks typed out
// like a terminal. Everything it changes goes through the Mod class.

using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Drawing.Text;
using System.IO;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace MoreRollers
{
    class TerminalWindow : Form
    {
        static readonly Color Bg = Color.FromArgb(1, 5, 1);
        static readonly Color Green = Color.FromArgb(61, 255, 106);
        static readonly Color Hot = Color.FromArgb(200, 255, 210);
        static readonly Color Mid = Color.FromArgb(43, 191, 79);
        static readonly Color Dim = Color.FromArgb(31, 143, 59);
        static readonly Color Frame = Color.FromArgb(15, 58, 22);
        static readonly Color Amber = Color.FromArgb(255, 186, 56);
        static readonly Color Red = Color.FromArgb(255, 84, 64);
        static readonly Color Ink = Color.FromArgb(2, 16, 4);

        // Layout in pixels at 96 dpi; everything is scaled by k when drawn.
        const int W = 600, H = 540, Pad = 30, TitleH = 34;
        const int LogTop = 186, LineH = 26, MaxLines = 8, FooterY = 494;
        const int StatusCol = 35; // column where "FOUND", "SUPPORTED"... start
        const string Searching = "SEARCHING STEAM LIBRARIES", Checking = "CHECKING THE GAME FOLDER";

        class Seg
        {
            public string Text; public Color Color;
            public Seg(string text, Color color) { Text = text; Color = color; }
        }

        class Line
        {
            public List<Seg> Segs = new List<Seg>();
            public int Length { get { int n = 0; foreach (Seg s in Segs) n += s.Text.Length; return n; } }
        }

        class Choice
        {
            public string Label; public MethodInvoker Run; public RectangleF Rect;
            public Choice(string label, MethodInvoker run) { Label = label; Run = run; }
        }

        readonly float k = 1F; // screen dpi / 96
        readonly PrivateFontCollection fonts = new PrivateFontCollection();
        readonly FontFamily family;
        readonly Dictionary<float, Font> fontCache = new Dictionary<float, Font>();
        readonly Dictionary<float, float> widthCache = new Dictionary<float, float>();
        readonly StringFormat format;
        readonly float logPx = 24F;
        readonly Timer timer = new Timer();

        readonly List<Line> lines = new List<Line>();
        List<Choice> choices = new List<Choice>();
        int selected;
        int revealed; // characters of the log typed so far
        bool cursorOn = true;
        int blinkTicks;
        string hover; // "min", "close", "discord", "github" or null
        RectangleF minRect, closeRect, discordRect, githubRect;
        Bitmap layer, glowNear, glowFar, overlay;
        string gameDir;

        public TerminalWindow()
        {
            using (Graphics g = Graphics.FromHwnd(IntPtr.Zero)) k = g.DpiX / 96F;
#if SNAPSHOT
            string fake = Environment.GetEnvironmentVariable("SNAPSHOT_SCALE");
            if (!string.IsNullOrEmpty(fake)) k = float.Parse(fake, System.Globalization.CultureInfo.InvariantCulture);
#endif
            byte[] font = Mod.Resource("VT323-Regular.ttf");
            IntPtr memory = Marshal.AllocCoTaskMem(font.Length); // kept: GDI+ reads it as long as the font is used
            Marshal.Copy(font, 0, memory, font.Length);
            fonts.AddMemoryFont(memory, font.Length);
            family = fonts.Families[0];
            format = (StringFormat)StringFormat.GenericTypographic.Clone();
            format.FormatFlags |= StringFormatFlags.MeasureTrailingSpaces | StringFormatFlags.NoWrap;
            // The longest status line has to fit.
            while (StatusCol + 13 > (W - 2 * Pad) / CharWidth(logPx) && logPx > 14F) logPx -= 0.5F;

            Text = "MoreRollers " + Mod.Version + " installer";
            FormBorderStyle = FormBorderStyle.None;
            MaximizeBox = false;
            StartPosition = FormStartPosition.CenterScreen;
            AutoScaleMode = AutoScaleMode.None;
            ClientSize = new Size(S(W), S(H));
            BackColor = Bg;
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
            try { Icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath); } catch (Exception) { }

            timer.Interval = 15;
            timer.Tick += delegate { Tick(); };
            timer.Start();

            gameDir = Mod.FindGame();
            Scan(Searching, true);
        }

        int S(int v) { return (int)Math.Round(v * k); }

        // ------------------------------------------------------------ what the log says

        /// Checks the game folder, writes what it finds and offers what can be done.
        void Scan(string search, bool clear)
        {
            if (clear) Clear();
            if (gameDir == null)
            {
                Row(search, "NOT FOUND", Amber);
                Say("> SELECT BUCKSHOT ROULETTE.EXE WITH CHANGE FOLDER", Green);
                Say("  IN STEAM: RIGHT-CLICK THE GAME > MANAGE > BROWSE LOCAL FILES", Dim);
                Offer(new Choice("CHANGE FOLDER", ChangeFolder));
                return;
            }
            Row(search, "FOUND", Green);
            Say("  " + ShortPath(gameDir), Dim);
            bool supported = true;
            try
            {
                if (Mod.ChangedScripts(gameDir).Count == 0)
                {
                    Row("GAME VERSION " + Mod.GameVersion, "SUPPORTED", Green);
                }
                else
                {
                    supported = false;
                    Row("GAME VERSION", "UPDATED", Amber);
                    Say("  THE MOD WAS MADE FOR " + Mod.GameVersion + ": IT WOULD STAY OFF", Amber);
                }
            }
            catch (Exception)
            {
                Row("GAME VERSION", "UNKNOWN", Amber);
            }

            string installed = Mod.InstalledVersion(gameDir);
            bool registered = Mod.Registered(gameDir);
            if (installed != null && registered && installed == Mod.Version)
            {
                Row("MOREROLLERS " + installed, "INSTALLED", Green);
                Say("> LOCAL SPLITSCREEN IS IN THE MAIN MENU", Green);
                Offer(new Choice("PLAY", Play), new Choice("UNINSTALL", AskUninstall), new Choice("CHANGE FOLDER", ChangeFolder));
            }
            else if (installed != null && registered)
            {
                Row("MOREROLLERS " + (installed == "" ? "?" : installed), "INSTALLED", Green);
                Say("> THIS INSTALLER HAS MOREROLLERS " + Mod.Version, Green);
                Offer(new Choice("UPDATE", Install), new Choice("UNINSTALL", AskUninstall), new Choice("CHANGE FOLDER", ChangeFolder));
            }
            else if (installed != null || registered)
            {
                Row("MOREROLLERS", "INCOMPLETE", Amber);
                Say("> INSTALL IT AGAIN TO REPAIR IT", Green);
                Offer(new Choice("REPAIR", Install), new Choice("UNINSTALL", AskUninstall), new Choice("CHANGE FOLDER", ChangeFolder));
            }
            else
            {
                Row("MOREROLLERS", "NOT INSTALLED", Green);
                Say("> READY", Green);
                Offer(new Choice(supported ? "INSTALL" : "INSTALL ANYWAY", Install), new Choice("CHANGE FOLDER", ChangeFolder));
            }
            if (Mod.GameRunning()) Say("> BUCKSHOT ROULETTE IS RUNNING: CLOSE IT FIRST", Amber);
        }

        void Clear()
        {
            lines.Clear();
            revealed = 0;
        }

        void Add(Line line)
        {
            lines.Add(line);
            while (lines.Count > MaxLines)
            {
                revealed = Math.Max(0, revealed - lines[0].Length);
                lines.RemoveAt(0);
            }
            Invalidate();
        }

        /// "> LABEL ........ STATUS"
        void Row(string label, string status, Color statusColor)
        {
            string head = "> " + label + " ";
            Line line = new Line();
            line.Segs.Add(new Seg(head + new string('.', Math.Max(3, StatusCol - head.Length - 1)) + " ", Green));
            line.Segs.Add(new Seg(status, statusColor));
            Add(line);
        }

        /// A line of text, wrapped to the log's width (continuation lines are indented).
        void Say(string text, Color color)
        {
            int max = (int)((W - 2 * Pad) / CharWidth(logPx));
            while (text.Length > max)
            {
                int cut = text.LastIndexOf(' ', max);
                if (cut <= 2) cut = max;
                Line part = new Line();
                part.Segs.Add(new Seg(text.Substring(0, cut), color));
                Add(part);
                text = "  " + text.Substring(cut).TrimStart();
            }
            Line line = new Line();
            line.Segs.Add(new Seg(text, color));
            Add(line);
        }

        void Offer(params Choice[] list)
        {
            choices = new List<Choice>(list);
            selected = 0;
            Invalidate();
        }

        int Total()
        {
            int n = 0;
            foreach (Line l in lines) n += l.Length;
            return n;
        }

        bool Typed() { return revealed >= Total(); }

        void FinishTyping()
        {
            revealed = Total();
            Invalidate();
        }

        string ShortPath(string dir)
        {
            int max = (int)((W - 2 * Pad) / CharWidth(logPx)) - 2;
            string s = dir.ToUpperInvariant();
            if (s.Length <= max) return s;
            string[] parts = s.Split('\\');
            if (parts.Length > 3)
            {
                string t = parts[0] + "\\...\\" + parts[parts.Length - 2] + "\\" + parts[parts.Length - 1];
                if (t.Length <= max) return t;
                t = "...\\" + parts[parts.Length - 1];
                if (t.Length <= max) return t;
            }
            return "..." + s.Substring(s.Length - (max - 3));
        }

        // ------------------------------------------------------------ actions

        void Install()
        {
            if (Mod.GameRunning())
            {
                Say("> BUCKSHOT ROULETTE IS RUNNING: CLOSE IT FIRST", Amber);
                return;
            }
            try
            {
                Mod.Install(gameDir);
                Clear();
                Row("INSTALLING MOREROLLERS " + Mod.Version, "DONE", Green);
                Scan(Checking, false);
            }
            catch (Exception e)
            {
                Failed("install", e);
            }
        }

        void AskUninstall()
        {
            Say("> REMOVE MOREROLLERS FROM THIS COPY OF THE GAME?", Amber);
            Offer(new Choice("NO", delegate { Scan(Checking, true); }), new Choice("YES, UNINSTALL", Uninstall));
        }

        void Uninstall()
        {
            if (Mod.GameRunning())
            {
                Say("> BUCKSHOT ROULETTE IS RUNNING: CLOSE IT FIRST", Amber);
                return;
            }
            try
            {
                Mod.Uninstall(gameDir);
                Clear();
                Row("UNINSTALLING MOREROLLERS", "DONE", Green);
                Say("  THE GAME FOLDER IS BACK TO HOW IT WAS", Dim);
                Scan(Checking, false);
            }
            catch (Exception e)
            {
                Failed("uninstall", e);
            }
        }

        void Failed(string action, Exception e)
        {
            if (Mod.IsAccessDenied(e))
            {
                Say("> WINDOWS REFUSED TO WRITE TO THE GAME FOLDER", Red);
                Offer(new Choice("RETRY AS ADMIN", delegate { Elevate(action); }), new Choice("CANCEL", delegate { Scan(Checking, true); }));
            }
            else
            {
                Say("> ERROR: " + e.Message.ToUpperInvariant(), Red);
            }
        }

        void Elevate(string action)
        {
            Say("> ASKING WINDOWS FOR ADMINISTRATOR RIGHTS...", Green);
            FinishTyping();
            Update();
            int code = Program.RunElevated(action, gameDir);
            if (code == 0)
            {
                Clear();
                Row(action == "install" ? "INSTALLING MOREROLLERS " + Mod.Version : "UNINSTALLING MOREROLLERS", "DONE", Green);
                Scan(Checking, false);
            }
            else
            {
                Say(code == -1 ? "> CANCELLED" : "> IT FAILED AS ADMINISTRATOR TOO", code == -1 ? Amber : Red);
                Offer(new Choice("RETRY AS ADMIN", delegate { Elevate(action); }), new Choice("CANCEL", delegate { Scan(Checking, true); }));
            }
        }

        void Play()
        {
            try
            {
                Process.Start(new ProcessStartInfo("steam://rungameid/" + Program.SteamAppId) { UseShellExecute = true });
                Say("> STARTING BUCKSHOT ROULETTE THROUGH STEAM...", Green);
            }
            catch (Exception)
            {
                try
                {
                    Process.Start(new ProcessStartInfo(Path.Combine(gameDir, Mod.GameExe)) { WorkingDirectory = gameDir, UseShellExecute = true });
                    Say("> STARTING BUCKSHOT ROULETTE...", Green);
                }
                catch (Exception e)
                {
                    Say("> COULDN'T START THE GAME: " + e.Message.ToUpperInvariant(), Red);
                }
            }
        }

        void ChangeFolder()
        {
            using (OpenFileDialog d = new OpenFileDialog())
            {
                d.Title = "Select Buckshot Roulette.exe";
                d.Filter = "Buckshot Roulette|" + Mod.GameExe + "|Programs (*.exe)|*.exe";
                if (gameDir != null) d.InitialDirectory = gameDir;
                if (d.ShowDialog(this) != DialogResult.OK) return;
                gameDir = Mod.ResolveGameDir(d.FileName);
                Scan(Checking, true);
            }
        }

        static void Open(string url)
        {
            try { Process.Start(new ProcessStartInfo(url) { UseShellExecute = true }); } catch (Exception) { }
        }

        // ------------------------------------------------------------ input

        void Tick()
        {
            if (!Typed())
            {
                revealed = Math.Min(Total(), revealed + 3);
                cursorOn = true;
                blinkTicks = 0;
                Invalidate();
                return;
            }
            if (++blinkTicks * timer.Interval >= 530)
            {
                blinkTicks = 0;
                cursorOn = !cursorOn;
                Invalidate();
            }
        }

        void RunChoice(int i)
        {
            if (!Typed() || i < 0 || i >= choices.Count) return;
            choices[i].Run();
        }

        void MoveSelection(int dir)
        {
            if (choices.Count == 0) return;
            selected = (selected + dir + choices.Count) % choices.Count;
            Invalidate();
        }

        protected override bool ProcessCmdKey(ref Message msg, Keys keyData)
        {
            switch (keyData)
            {
                case Keys.Left: case Keys.Up: case Keys.Shift | Keys.Tab:
                    MoveSelection(-1); return true;
                case Keys.Right: case Keys.Down: case Keys.Tab:
                    MoveSelection(1); return true;
                case Keys.Enter: case Keys.Space:
                    if (Typed()) RunChoice(selected); else FinishTyping();
                    return true;
                case Keys.Escape:
                    Close(); return true;
            }
            return base.ProcessCmdKey(ref msg, keyData);
        }

        PointF Unscale(Point p) { return new PointF(p.X / k, p.Y / k); }

        int ChoiceAt(PointF p)
        {
            if (!Typed()) return -1;
            for (int i = 0; i < choices.Count; i++)
                if (choices[i].Rect.Contains(p)) return i;
            return -1;
        }

        protected override void OnMouseMove(MouseEventArgs e)
        {
            base.OnMouseMove(e);
            PointF p = Unscale(e.Location);
            string h = minRect.Contains(p) ? "min" : closeRect.Contains(p) ? "close"
                : discordRect.Contains(p) ? "discord" : githubRect.Contains(p) ? "github" : null;
            int c = ChoiceAt(p);
            if (c >= 0 && c != selected) { selected = c; Invalidate(); }
            Cursor = h != null || c >= 0 ? Cursors.Hand : Cursors.Default;
            if (h != hover) { hover = h; Invalidate(); }
        }

        protected override void OnMouseLeave(EventArgs e)
        {
            base.OnMouseLeave(e);
            if (hover != null) { hover = null; Invalidate(); }
        }

        protected override void OnMouseClick(MouseEventArgs e)
        {
            base.OnMouseClick(e);
            if (e.Button != MouseButtons.Left) return;
            PointF p = Unscale(e.Location);
            if (minRect.Contains(p)) WindowState = FormWindowState.Minimized;
            else if (closeRect.Contains(p)) Close();
            else if (discordRect.Contains(p)) Open(Mod.DiscordUrl);
            else if (githubRect.Contains(p)) Open(Mod.RepoUrl);
            else if (!Typed()) FinishTyping();
            else RunChoice(ChoiceAt(p));
        }

        // ------------------------------------------------------------ window

        [DllImport("dwmapi.dll")]
        static extern int DwmSetWindowAttribute(IntPtr hwnd, int attribute, ref int value, int size);

        protected override CreateParams CreateParams
        {
            get
            {
                CreateParams cp = base.CreateParams;
                cp.ClassStyle |= 0x20000; // CS_DROPSHADOW
                cp.Style |= 0x20000;      // WS_MINIMIZEBOX: the taskbar button can minimize it
                return cp;
            }
        }

        protected override void OnHandleCreated(EventArgs e)
        {
            base.OnHandleCreated(e);
            try { int round = 2; DwmSetWindowAttribute(Handle, 33, ref round, 4); } catch (Exception) { } // rounded corners on Windows 11
        }

        /// The title bar moves the window.
        protected override void WndProc(ref Message m)
        {
            base.WndProc(ref m);
            if (m.Msg == 0x84 && m.Result == (IntPtr)1) // WM_NCHITTEST over the client area
            {
                long lp = m.LParam.ToInt64();
                PointF p = Unscale(PointToClient(new Point(unchecked((short)(lp & 0xFFFF)), unchecked((short)((lp >> 16) & 0xFFFF)))));
                if (p.Y < TitleH && !minRect.Contains(p) && !closeRect.Contains(p)) m.Result = (IntPtr)2; // HTCAPTION
            }
        }

        // ------------------------------------------------------------ drawing

        Font F(float px)
        {
            Font f;
            if (!fontCache.TryGetValue(px, out f)) fontCache[px] = f = new Font(family, px, FontStyle.Regular, GraphicsUnit.Pixel);
            return f;
        }

        /// VT323 is monospaced: every character has this width.
        float CharWidth(float px)
        {
            float w;
            if (widthCache.TryGetValue(px, out w)) return w;
            using (Bitmap b = new Bitmap(1, 1))
            using (Graphics g = Graphics.FromImage(b))
            {
                g.TextRenderingHint = TextRenderingHint.AntiAlias;
                w = g.MeasureString("MMMMMMMMMMMMMMMMMMMM", F(px), PointF.Empty, format).Width / 20F;
            }
            widthCache[px] = w;
            return w;
        }

        void Text_(Graphics g, string text, float px, Color color, float x, float y)
        {
            using (SolidBrush b = new SolidBrush(color)) g.DrawString(text, F(px), b, x, y, format);
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            Size size = ClientSize;
            if (size.Width < 1 || size.Height < 1) return;
            EnsureBitmaps(size);
            using (Graphics g = Graphics.FromImage(layer))
            {
                g.Clear(Color.Transparent);
                g.ScaleTransform(k, k);
                g.SmoothingMode = SmoothingMode.AntiAlias;
                g.TextRenderingHint = TextRenderingHint.AntiAlias;
                DrawContent(g);
            }
            Graphics o = e.Graphics;
            o.Clear(Bg);
            Bloom(o, glowFar, 0.85F);
            Bloom(o, glowNear, 0.9F);
            o.DrawImageUnscaled(layer, 0, 0);
            o.DrawImageUnscaled(overlay, 0, 0);
            using (Pen p = new Pen(Frame, Math.Max(1F, (float)Math.Round(k))))
            {
                o.DrawLine(p, 0, TitleH * k, size.Width, TitleH * k);
                o.DrawRectangle(p, 0, 0, size.Width - 1, size.Height - 1);
            }
        }

        void DrawContent(Graphics g)
        {
            // Title bar
            Text_(g, "MORE ROLLERS :: INSTALLER", 20, Mid, 16, 7);
            float tw = 3 * CharWidth(20);
            closeRect = new RectangleF(W - 16 - tw - 6, 2, tw + 12, TitleH - 4);
            minRect = new RectangleF(closeRect.X - tw - 20, 2, tw + 12, TitleH - 4);
            Text_(g, "[_]", 20, hover == "min" ? Hot : Mid, minRect.X + 6, 7);
            Text_(g, "[X]", 20, hover == "close" ? Hot : Mid, closeRect.X + 6, 7);

            // Logo
            GraphicsState state = g.Save();
            g.TranslateTransform(Pad - 3, 38);
            g.ScaleTransform(1F, 1.15F);
            Text_(g, "MORE ROLLERS", 88, Green, 0, 0);
            g.Restore(state);
            Text_(g, "LOCAL SPLITSCREEN FOR BUCKSHOT ROULETTE - v" + Mod.Version, 24, Mid, Pad, 140);

            // Log, typed out
            float cw = CharWidth(logPx);
            int left = revealed;
            float cursorX = Pad, cursorY = LogTop;
            for (int i = 0; i < lines.Count && left > 0; i++)
            {
                float x = Pad, y = LogTop + i * LineH;
                foreach (Seg s in lines[i].Segs)
                {
                    if (left <= 0) break;
                    string t = s.Text.Length <= left ? s.Text : s.Text.Substring(0, left);
                    left -= t.Length;
                    Text_(g, t, logPx, s.Color, x, y);
                    x += t.Length * cw;
                }
                cursorX = x;
                cursorY = y;
            }
            if (cursorOn) Text_(g, "_", logPx, Green, cursorX, cursorY);

            // Choices, once everything is typed
            foreach (Choice c in choices) c.Rect = RectangleF.Empty;
            if (Typed() && choices.Count > 0)
            {
                float px = 30, choicesY = LogTop + lines.Count * LineH + 20;
                while (px > 20 && ChoicesWidth(px) > W - 2 * Pad) px -= 1;
                float ccw = CharWidth(px), x = Pad;
                for (int i = 0; i < choices.Count; i++)
                {
                    bool on = i == selected;
                    string t = (on ? "> " : "  ") + choices[i].Label + (on ? " <" : "  ");
                    RectangleF r = new RectangleF(x, choicesY, t.Length * ccw, 38);
                    choices[i].Rect = r;
                    if (on)
                    {
                        using (SolidBrush b = new SolidBrush(Green)) g.FillRectangle(b, r.X, r.Y + 3, r.Width, r.Height - 6);
                        Text_(g, t, px, Ink, x, choicesY + (38 - px) / 2 - 1);
                    }
                    else
                    {
                        Text_(g, t, px, Green, x, choicesY + (38 - px) / 2 - 1);
                    }
                    x += r.Width + 12;
                }
            }

            // Footer: the Discord link squeezed like the one in the game's lobby
            float fcw = CharWidth(22);
            Color dc = hover == "discord" ? Hot : Green;
            state = g.Save();
            g.TranslateTransform(Pad, FooterY);
            g.ScaleTransform(0.8F, 1F);
            Text_(g, "MOREROLLERS DISCORD", 22, dc, 0, 0);
            DrawDiscordIcon(g, dc, 19 * fcw + 7, 0, 22);
            g.Restore(state);
            discordRect = new RectangleF(Pad, FooterY - 2, (19 * fcw + 7 + 22) * 0.8F, 26);
            float gx = discordRect.Right + 26;
            Text_(g, "GITHUB", 22, hover == "github" ? Hot : Green, gx, FooterY);
            githubRect = new RectangleF(gx, FooterY - 2, 6 * fcw, 26);
            string meta = "GPL-3.0 - BY MASH";
            Text_(g, meta, 22, Dim, W - Pad - meta.Length * fcw, FooterY);
        }

        float ChoicesWidth(float px)
        {
            int chars = 0;
            foreach (Choice c in choices) chars += c.Label.Length + 4;
            return chars * CharWidth(px) + 12 * (choices.Count - 1);
        }

        /// A filled Discord logo, drawn in a 24-unit box.
        static void DrawDiscordIcon(Graphics g, Color color, float x, float y, float size)
        {
            float s = size / 24F;
            PointF[] body = {
                new PointF(3.0F, 17.0F), new PointF(2.2F, 12.0F), new PointF(4.2F, 6.0F), new PointF(8.8F, 4.6F),
                new PointF(9.6F, 5.9F), new PointF(14.4F, 5.9F), new PointF(15.2F, 4.6F), new PointF(19.8F, 6.0F),
                new PointF(21.8F, 12.0F), new PointF(21.0F, 17.0F), new PointF(17.6F, 19.2F), new PointF(16.2F, 17.2F),
                new PointF(12.0F, 17.8F), new PointF(7.8F, 17.2F), new PointF(6.4F, 19.2F),
            };
            for (int i = 0; i < body.Length; i++) body[i] = new PointF(x + body[i].X * s, y + body[i].Y * s);
            using (GraphicsPath p = new GraphicsPath())
            using (SolidBrush b = new SolidBrush(color))
            using (SolidBrush eye = new SolidBrush(Bg))
            {
                p.AddClosedCurve(body, 0.35F);
                g.FillPath(b, p);
                g.FillEllipse(eye, x + 7.2F * s, y + 10.3F * s, 3.4F * s, 3.8F * s);
                g.FillEllipse(eye, x + 13.4F * s, y + 10.3F * s, 3.4F * s, 3.8F * s);
            }
        }

        void EnsureBitmaps(Size size)
        {
            if (layer != null && layer.Size == size) return;
            foreach (Bitmap b in new Bitmap[] { layer, glowNear, glowFar, overlay }) if (b != null) b.Dispose();
            layer = new Bitmap(size.Width, size.Height, PixelFormat.Format32bppPArgb);
            glowNear = new Bitmap(Math.Max(1, size.Width / 4), Math.Max(1, size.Height / 4), PixelFormat.Format32bppPArgb);
            glowFar = new Bitmap(Math.Max(1, size.Width / 10), Math.Max(1, size.Height / 10), PixelFormat.Format32bppPArgb);
            overlay = BuildOverlay(size);
        }

        /// The glow: the drawing shrunk (which blurs it) then stretched back under the sharp one.
        void Bloom(Graphics o, Bitmap small, float alpha)
        {
            using (Graphics s = Graphics.FromImage(small))
            {
                s.Clear(Color.Transparent);
                s.InterpolationMode = InterpolationMode.HighQualityBilinear;
                s.PixelOffsetMode = PixelOffsetMode.HighQuality;
                s.DrawImage(layer, new Rectangle(0, 0, small.Width, small.Height));
            }
            ColorMatrix cm = new ColorMatrix();
            cm.Matrix33 = alpha;
            using (ImageAttributes ia = new ImageAttributes())
            {
                ia.SetColorMatrix(cm);
                ia.SetWrapMode(WrapMode.TileFlipXY);
                o.InterpolationMode = InterpolationMode.HighQualityBilinear;
                o.PixelOffsetMode = PixelOffsetMode.HighQuality;
                o.DrawImage(small, new Rectangle(0, 0, layer.Width, layer.Height), 0, 0, small.Width, small.Height, GraphicsUnit.Pixel, ia);
            }
        }

        /// Scanlines and a dark vignette, like an old screen.
        Bitmap BuildOverlay(Size size)
        {
            Bitmap b = new Bitmap(size.Width, size.Height, PixelFormat.Format32bppPArgb);
            using (Graphics g = Graphics.FromImage(b))
            {
                int step = Math.Max(3, (int)Math.Round(3 * k));
                int thick = Math.Max(1, step / 3);
                using (SolidBrush line = new SolidBrush(Color.FromArgb(80, 0, 0, 0)))
                    for (int y = 0; y < size.Height; y += step) g.FillRectangle(line, 0, y, size.Width, thick);
                using (GraphicsPath p = new GraphicsPath())
                {
                    p.AddEllipse(-size.Width * 0.25F, -size.Height * 0.25F, size.Width * 1.5F, size.Height * 1.5F);
                    using (PathGradientBrush pg = new PathGradientBrush(p))
                    {
                        ColorBlend blend = new ColorBlend(3);
                        blend.Colors = new Color[] { Color.FromArgb(170, 0, 0, 0), Color.FromArgb(0, 0, 0, 0), Color.FromArgb(0, 0, 0, 0) };
                        blend.Positions = new float[] { 0F, 0.5F, 1F };
                        pg.InterpolationColors = blend;
                        g.FillRectangle(pg, 0, 0, size.Width, size.Height);
                    }
                }
            }
            return b;
        }

#if SNAPSHOT
        /// Test build only: renders the window in a given state to a PNG.
        ///   SNAPSHOT_DIR=<folder>    check that folder instead of the one found through Steam
        ///   SNAPSHOT_ACTION=uninstall|denied   show the uninstall question / the access-denied answer
        ///   SNAPSHOT_ACTION=do-install|do-uninstall   really install / uninstall, through the window
        ///   SNAPSHOT_SELECT=<n>, SNAPSHOT_HOVER=discord|github|min|close
        public static void Snapshot(string png)
        {
            TerminalWindow w = new TerminalWindow();
            string dir = Environment.GetEnvironmentVariable("SNAPSHOT_DIR");
            if (dir != null) { w.gameDir = Mod.ResolveGameDir(dir); w.Scan(Environment.GetEnvironmentVariable("SNAPSHOT_SEARCH") == "1" ? Searching : Checking, true); }
            string action = Environment.GetEnvironmentVariable("SNAPSHOT_ACTION");
            if (action == "uninstall") w.AskUninstall();
            if (action == "denied") w.Failed("install", new UnauthorizedAccessException());
            if (action == "do-install") w.Install();
            if (action == "do-uninstall") w.Uninstall();
            string select = Environment.GetEnvironmentVariable("SNAPSHOT_SELECT");
            if (select != null) w.selected = int.Parse(select);
            w.hover = Environment.GetEnvironmentVariable("SNAPSHOT_HOVER");
            w.revealed = w.Total();
            w.cursorOn = true;
            w.timer.Stop();
            w.StartPosition = FormStartPosition.Manual;
            w.Location = new Point(-4000, -4000);
            w.ShowInTaskbar = false;
            w.Show();
            Application.DoEvents();
            using (Bitmap b = new Bitmap(w.Width, w.Height))
            {
                w.DrawToBitmap(b, new Rectangle(0, 0, w.Width, w.Height));
                b.Save(png, ImageFormat.Png);
            }
            w.Close();
        }
#endif
    }
}
