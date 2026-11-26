using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.Json;

namespace OpenSmash.Launcher
{
    // NILSIX TOOLS (top menu, between COMPETITIVE and SETTINGS): the tools of github.com/Nilsix/WindowSmashLauncher. That
    // kit builds this launcher from the release's own sources with this page added (kit\nilsix_launcher.ps1); the game
    // is the release's, so nothing here changes what is played online.
    // Mods sync: MAKE THE FILE runs mods_sync.py make (embedded, Nilsix.mods_sync.py) with the folder's Python. It writes
    // "Synchro mods - <name>.bat" (English: "Mods sync - <name>.bat") on the desktop; a friend double-clicks it and their
    // mods become these: the same folders, switches, order and versions, then checked against the set the game reports
    // online.
    public partial class LauncherForm
    {
        Process? _nilsixProc;
        readonly List<string> _nilsixLog = new();
        string? _nilsixFile, _nilsixPrint;
        bool _nilsixFailed;

        static bool NilsixFr => UiLocale.Language.StartsWith("fr", StringComparison.OrdinalIgnoreCase);
        static string NT(string en, string fr) => NilsixFr ? fr : en;

        bool ActivateNilsixHit(string id)
        {
            switch (id)
            {
                case "nav:nilsix": GoView("nilsix"); return true;
                case "nilsix:sync-make": NilsixMakeSync(); return true;
                case "nilsix:sync-open":
                    if (_nilsixFile != null && File.Exists(_nilsixFile))
                        try { Process.Start(new ProcessStartInfo("explorer.exe", "/select,\"" + _nilsixFile + "\"") { UseShellExecute = false }); }
                        catch (System.ComponentModel.Win32Exception) { }
                    return true;
            }
            return false;
        }

        void NilsixMakeSync()
        {
            if (_nilsixProc != null) return;
            lock (_nilsixLog) _nilsixLog.Clear();
            _nilsixFile = _nilsixPrint = null;
            _nilsixFailed = false;
            try
            {
                string dir = Path.Combine(Path.GetTempPath(), "opensmash-nilsix");
                Directory.CreateDirectory(dir);
                string script = Path.Combine(dir, "mods_sync.py");
                using (var res = typeof(LauncherForm).Assembly.GetManifestResourceStream("Nilsix.mods_sync.py")
                                 ?? throw new InvalidOperationException("mods_sync.py is not in this launcher"))
                using (var f = File.Create(script))
                    res.CopyTo(f);
                var psi = new ProcessStartInfo(ModManagerProcess.FindPython(_repo, _buildDir))
                {
                    UseShellExecute = false, CreateNoWindow = true, WorkingDirectory = _repo,
                    RedirectStandardOutput = true, RedirectStandardError = true,
                    StandardOutputEncoding = Encoding.UTF8, StandardErrorEncoding = Encoding.UTF8,
                };
                foreach (string a in new[] { "-I", "-X", "utf8", script, "make", "--tree", _repo,
                                             "--out", Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory),
                                             "--lang", NilsixFr ? "fr" : "en" })
                    psi.ArgumentList.Add(a);
                var p = new Process { StartInfo = psi, EnableRaisingEvents = true };
                p.OutputDataReceived += (_, e) => NilsixLine(e.Data);
                p.ErrorDataReceived += (_, e) => NilsixLine(e.Data);
                p.Exited += (_, _) =>
                {
                    int code = -1;
                    try { p.WaitForExit(); code = p.ExitCode; } catch (InvalidOperationException) { }   // (the output read to its end first)
                    try
                    {
                        BeginInvoke(new Action(() =>
                        {
                            _nilsixFailed = code != 0 || _nilsixFile == null;
                            _nilsixProc = null;
                            p.Dispose();
                            Invalidate();
                        }));
                    }
                    catch (InvalidOperationException) { }   // (the window closed meanwhile)
                };
                _nilsixProc = p;
                p.Start();
                p.BeginOutputReadLine();
                p.BeginErrorReadLine();
            }
            catch (Exception e) when (e is IOException or UnauthorizedAccessException or InvalidOperationException or System.ComponentModel.Win32Exception)
            {
                _nilsixProc = null;
                _nilsixFailed = true;
                NilsixLine(NT("Could not start the tool: ", "Impossible de lancer l'outil : ") + e.Message);
            }
            Invalidate();
        }

        void NilsixLine(string? line)
        {
            if (line == null) return;
            if (line.StartsWith("RESULT ", StringComparison.Ordinal))   // (mods_sync.py's last line: the file and its fingerprint)
            {
                try
                {
                    using var doc = JsonDocument.Parse(line.Substring(7));
                    if (doc.RootElement.TryGetProperty("file", out var f)) _nilsixFile = f.GetString();
                    if (doc.RootElement.TryGetProperty("fingerprint", out var fp)) _nilsixPrint = fp.GetString();
                }
                catch (JsonException) { }
                return;
            }
            lock (_nilsixLog)
            {
                _nilsixLog.Add(line);
                if (_nilsixLog.Count > 400) _nilsixLog.RemoveAt(0);
            }
            try { BeginInvoke(new Action(Invalidate)); } catch (InvalidOperationException) { }
        }

        void PaintNilsix(Graphics g, int W, int H)
        {
            float s = _s, x = Gutter * s, cw = W - 2 * x;
            PaintSectionHead(g, "04 / NILSIX TOOLS", "NILSIX TOOLS");
            bool running = _nilsixProc != null;

            // the mods sync card: what it does, the main button and the file's folder
            float cy = ContentTop * s, ch = 132 * s, cut = 22 * s, pad = 24 * s;
            {
                var st = PushReveal(g, 0);
                using (var path = Theme.CutCorner(x, cy, cw, ch, cut))
                {
                    using (var b = new SolidBrush(A(Theme.Bg2))) g.FillPath(b, path);
                    using (var pen = new Pen(A(Theme.Line), Math.Max(1, s))) g.DrawPath(pen, path);
                }
                using (var pen = new Pen(A(Theme.Dim), Math.Max(1, 1.5f * s))) g.DrawLine(pen, x + cw - cut, cy, x + cw, cy + cut);
                float bw = 236 * s, bx = x + cw - pad - bw - 18 * s, maxW = bx - x - pad - 24 * s;
                Badge(g, NT("MODS SYNC", "SYNCHRO DES MODS"), x + pad, cy + 20 * s, Theme.Accent, Color.White);
                string title = NT("THE SAME MODS AS YOUR FRIENDS", "LES MÊMES MODS QUE TES AMIS");
                float titlePx = 30 * s;
                while (titlePx > 18 * s && Theme.TextWidth(g, title, FD(titlePx), 0.3f * s) > maxW) titlePx -= 1 * s;
                Theme.Label(g, title, FD(titlePx), A(Theme.Text), x + pad, cy + 52 * s, 26 * s, 0.3f * s);
                Theme.DrawText(g, NT("Makes a file for a friend: it installs your mods, turns on and off the same ones, in your order, at your versions.",
                                     "Crée un fichier pour un ami : il installe tes mods, active et désactive les mêmes, dans ton ordre, à tes versions."),
                    FB(14 * s), A(Theme.Muted), x + pad, cy + 84 * s, maxW, 20 * s);
                Theme.DrawText(g, NT("They double-click it with OpenSmash closed. SYNC OK and the same code as here: the same game online.",
                                     "Il double-clique dessus, OpenSmash fermé. SYNCHRO OK et le même code qu'ici : le même jeu en ligne."),
                    FB(14 * s), A(Theme.Muted), x + pad, cy + 106 * s, maxW, 20 * s);
                Theme.ButtonAnimated(g, NT("MAKE THE FILE", "CRÉER LE FICHIER"), bx, cy + 22 * s, bw, 38 * s, s, primary: true,
                    Hov("nilsix:sync-make", !running && _hover == "nilsix:sync-make"), !running, 13 * s, _alpha, press: Press("nilsix:sync-make"));
                if (!running) AddHit("nilsix:sync-make", bx, cy + 22 * s, bw, 38 * s);
                bool canOpen = !running && _nilsixFile != null;
                Theme.ButtonAnimated(g, NT("SHOW THE FILE", "VOIR LE FICHIER"), bx, cy + 70 * s, bw, 32 * s, s, primary: false,
                    Hov("nilsix:sync-open", canOpen && _hover == "nilsix:sync-open"), canOpen, 12 * s, _alpha, press: Press("nilsix:sync-open"));
                if (canOpen) AddHit("nilsix:sync-open", bx, cy + 70 * s, bw, 32 * s);
                PopFade(g, st);
            }

            // what the tool says: its last lines, under the result
            float top = cy + ch + 34 * s, bottom = H - StatusH * s - 24 * s;
            {
                var st = PushReveal(g, 1);
                bool done = !running && !_nilsixFailed && _nilsixPrint != null;
                string head = running ? NT("WORKING...", "EN COURS...")
                    : done ? NT("FILE ON THE DESKTOP  ·  CODE ", "FICHIER SUR LE BUREAU  ·  CODE ") + _nilsixPrint
                    : _nilsixFailed ? NT("STOPPED", "ARRÊTÉ") : NT("LOG", "JOURNAL");
                Theme.Label(g, head, FM(12 * s, true), A(done ? Theme.Ready : _nilsixFailed ? Theme.Bad : Theme.Dim), x, top, 20 * s, 12 * s * 0.14f);
                HLine(g, x, x + cw, top + 28 * s);
                string[] lines;
                lock (_nilsixLog) lines = _nilsixLog.ToArray();
                float lh = 19 * s, ly = top + 38 * s;
                int fit = Math.Max(0, (int)((bottom - ly) / lh));
                if (lines.Length == 0 && !running)
                    Theme.DrawText(g, NT("Nothing yet: press MAKE THE FILE.", "Rien pour l'instant : clique sur CRÉER LE FICHIER."),
                        FB(14 * s), A(Theme.Dim), x, ly, cw, 22 * s);
                foreach (string line in lines.Skip(Math.Max(0, lines.Length - fit)))
                {
                    bool sub = line.StartsWith("  ", StringComparison.Ordinal);
                    Theme.DrawText(g, line.Trim(), FM(12 * s), A(sub ? Theme.Dim : Theme.Muted), x + (sub ? 18 * s : 0), ly, cw - (sub ? 18 * s : 0), lh, localize: false);
                    ly += lh;
                }
                PopFade(g, st);
            }
        }
    }
}
