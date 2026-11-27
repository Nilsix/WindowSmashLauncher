using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.Json;
using System.Threading.Tasks;
using OpenSmash.Core;

namespace OpenSmash.Launcher
{
    // NILSIX TOOLS (top menu, between COMPETITIVE and SETTINGS): the tools of github.com/Nilsix/WindowSmashLauncher. That
    // kit builds this launcher from the release's own sources with this page added (kit\nilsix_launcher.ps1); the game
    // is the release's, so nothing here changes what is played online.
    // Mods sync: MAKE THE FILE runs mods_sync.py make (embedded, Nilsix.mods_sync.py) with the folder's Python. It writes
    // "Synchro mods - <name>.bat" (English: "Mods sync - <name>.bat") on the desktop; a friend double-clicks it and their
    // mods become these: the same folders, switches, order and versions, then checked against the set the game reports
    // online. Its steps show in the bar at the bottom (SetLoad), as OpenSmash's own jobs do on the MODS page.
    // MAKE A FUSION FILE runs make --fuse: "Fusion mods - <name>.bat" ("Mods fusion - <name>.bat") adds the mods turned
    // on here to the friend's, none of theirs turned off, and writes on their desktop the sync file they send back.
    // Updates: this launcher keeps itself and this page up to date (the kit's .bat is only needed to install). At each
    // start, kit\nilsix_launcher.ps1 with the newest kit files of GitHub, in the background: when they changed, this
    // release's launcher is built again with them, and (kit 5.9) this one closes and the new one starts, as soon as
    // nothing would be cut (NilsixRestartTick). And OpenSmash's self-update builds the new release's launcher with this
    // page instead of downloading the release's (NilsixReplaceLauncherAsync); the release's own when that fails, as before.
    public partial class LauncherForm
    {
        Process? _nilsixProc;
        readonly List<string> _nilsixLog = new();
        string? _nilsixFile, _nilsixPrint;
        bool _nilsixFailed, _nilsixWatch, _nilsixFuse;

        static bool NilsixFr => UiLocale.Language.StartsWith("fr", StringComparison.OrdinalIgnoreCase);
        static string NT(string en, string fr) => NilsixFr ? fr : en;

        // (NILSIX_KIT_URL: another place for the kit files, for tests: file:///D:/WindowSmashLauncher/kit/)
        static string NilsixKitUrl => Environment.GetEnvironmentVariable("NILSIX_KIT_URL") is { Length: > 0 } u ? u
            : "https://raw.githubusercontent.com/Nilsix/WindowSmashLauncher/main/kit/";
        static readonly string[] NilsixKitFiles = { "nilsix_launcher.ps1", "nilsix/LauncherForm.Nilsix.cs", "mods_sync.py" };
        static string NilsixWork => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "WindowSmash-setup", "nilsix-launcher");
        static Task<int>? s_nilsixKit;   // (the start's check; an update waits for it: one build at a time)
        readonly bool _nilsixBoot = NilsixBoot();
        static System.Windows.Forms.Timer? s_nilsixRestartTimer;
        static LauncherForm? s_nilsixForm;
        static bool s_nilsixRestarting;

        static bool NilsixBoot()
        {
            // (not with OPENSMASH_UPDATE=off, nor in a git checkout: no update there; record.json: the kit built this exe)
            string repo = Path.GetDirectoryName(Updater.ExePath) ?? "";
            if (Updater.Off || s_nilsixKit != null || Directory.Exists(Path.Combine(repo, ".git"))
                || !File.Exists(Path.Combine(NilsixWork, "record.json"))) return false;
            s_nilsixKit = Task.Run(() => NilsixKit(repo, null));
            // (not in the launcher a restart started: one restart per update, never a loop)
            if (Environment.GetEnvironmentVariable("NILSIX_RESTARTED") != "1")
            {
                s_nilsixRestartTimer = new System.Windows.Forms.Timer { Interval = 1000 };
                s_nilsixRestartTimer.Tick += (_, _) => NilsixRestartTick();
                s_nilsixRestartTimer.Start();
            }
            return true;
        }

        // Each second on the window's thread, until the start's check ends: when it built the kit's update (10), this
        // launcher restarts with it once nothing would be cut. (The check is static and knows no window: the first
        // LauncherForm open, remembered before the game can hide it.)
        static void NilsixRestartTick()
        {
            s_nilsixForm ??= System.Windows.Forms.Application.OpenForms.OfType<LauncherForm>().FirstOrDefault();
            if (s_nilsixKit is not { IsCompleted: true } kit || s_nilsixForm == null) return;
            bool built = kit.IsCompletedSuccessfully && kit.Result == 10 && !s_nilsixForm.IsDisposed;
            if (built && !s_nilsixForm.NilsixIdle) return;
            s_nilsixRestartTimer?.Stop();
            s_nilsixRestartTimer?.Dispose();
            s_nilsixRestartTimer = null;
            if (built) s_nilsixForm.NilsixRestart();
        }

        // nothing a restart would cut: no game, no job (Busy: the bar at the bottom, a build, an install...), no question
        // or setting being answered, no sign-in; the window shown (minimized, it waits: no window popping up over a game)
        bool NilsixIdle => Visible && WindowState != System.Windows.Forms.FormWindowState.Minimized && !Busy && !_waitingForGame
            && !NilsixRuns(_gameProcess) && !NilsixRuns(_shaderProc) && !NilsixRuns(_maintenanceProcess) && _nilsixProc == null
            && _prepInflight is not { IsCompleted: false } && _editingKey == null && !_accountBusy && !_discordBusy
            && !(_newModsPrompt || _updatePrompt || _shaderPrompt || _pluginPrompt || _rebuildPrompt || _sharePrompt || _checkModsPrompt || _showSetupPrompt);

        static bool NilsixRuns(Process? p)
        {
            try { return p != null && !p.HasExited; }
            catch (InvalidOperationException) { return false; }   // (no process behind it)
            catch (System.ComponentModel.Win32Exception) { return true; }
        }

        // the bar at the bottom says it (Busy then: nothing else starts) for 2.5 s, then the folder's OpenSmash.exe (the one
        // just built) starts once this one has closed; when that cannot start, this one stays open (from the next start)
        void NilsixRestart()
        {
            s_nilsixRestarting = true;
            SetLoad(NT("NILSIX TOOLS UPDATED: THE LAUNCHER STARTS AGAIN", "NILSIX TOOLS MIS À JOUR : LE LAUNCHER REDÉMARRE"), -1);
            Invalidate();
            var wait = new System.Windows.Forms.Timer { Interval = 2500 };
            wait.Tick += (_, _) =>
            {
                wait.Stop();
                wait.Dispose();
                if (NilsixStartAgain()) { Close(); return; }
                s_nilsixRestarting = false;
                ClearLoad();
                Invalidate();
            };
            wait.Start();
        }

        // A hidden PowerShell that waits for this process to end (Program.cs's single-instance mutex would turn the new one
        // away) and then starts OpenSmash.exe as its shortcut does. Not with --updated: that would apply a pending release
        // update by itself (MaybeShowBootPrompts). NILSIX_RESTARTED: the new one does not restart again.
        static bool NilsixStartAgain()
        {
            try
            {
                var psi = new ProcessStartInfo("powershell.exe") { UseShellExecute = false, CreateNoWindow = true };
                foreach (string a in new[] { "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", NilsixStartAgainPs1 })
                    psi.ArgumentList.Add(a);
                psi.Environment["NILSIX_RESTARTED"] = "1";
                psi.Environment["NILSIX_WAIT_PID"] = Environment.ProcessId.ToString(System.Globalization.CultureInfo.InvariantCulture);
                psi.Environment["NILSIX_EXE"] = Path.Combine(Path.GetDirectoryName(Updater.ExePath) ?? "", "OpenSmash.exe");
                using var p = Process.Start(psi);
                if (p == null) return false;
                NilsixAllowForeground(-1);   // (ASFW_ANY: this window is in front, the new one may come in front too)
                return true;
            }
            catch (Exception e) when (e is System.ComponentModel.Win32Exception or InvalidOperationException or IOException) { return false; }
        }

        const string NilsixStartAgainPs1 =
            "$p = Get-Process -Id ([int]$env:NILSIX_WAIT_PID) -ErrorAction SilentlyContinue; if ($p) { [void]$p.WaitForExit(60000) }; " +
            "$exe = $env:NILSIX_EXE; Remove-Item Env:NILSIX_WAIT_PID, Env:NILSIX_EXE; " +
            "Start-Process -FilePath $exe -WorkingDirectory (Split-Path -Parent $exe)";

        [System.Runtime.InteropServices.DllImport("user32.dll", EntryPoint = "AllowSetForegroundWindow")]
        static extern bool NilsixAllowForeground(int processId);

        // kit\nilsix_launcher.ps1 with the newest kit files, for release r (null: the one this exe was built for). 0 =
        // OpenSmash.exe is already that one, 10 = built and put in place, 1 = not built (GitHub out of reach too).
        static async Task<int> NilsixKit(string repo, Release? r)
        {
            var text = new StringBuilder(DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss ") + (r == null ? "start" : "update to " + r.Version) + Environment.NewLine);
            int code = 1;
            try
            {
                var files = new List<(string Name, byte[] Bytes)>();   // (all three first: never a build from two kits)
                foreach (string f in NilsixKitFiles) files.Add((f, await Releases.GetAsync(NilsixKitUrl + f)));
                string dir = Path.Combine(NilsixWork, "kit");
                foreach (var (name, bytes) in files)
                {
                    string dst = Path.Combine(dir, name.Replace('/', Path.DirectorySeparatorChar));
                    Directory.CreateDirectory(Path.GetDirectoryName(dst)!);
                    File.WriteAllBytes(dst, bytes);
                }
                var psi = new ProcessStartInfo("powershell.exe")
                {
                    UseShellExecute = false, CreateNoWindow = true, WorkingDirectory = dir,
                    RedirectStandardOutput = true, RedirectStandardError = true,
                    StandardOutputEncoding = Encoding.UTF8, StandardErrorEncoding = Encoding.UTF8,
                };
                foreach (string a in new[] { "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", Path.Combine(dir, "nilsix_launcher.ps1"), repo })
                    psi.ArgumentList.Add(a);
                if (r != null) { psi.ArgumentList.Add(r.Version.ToString()); psi.ArgumentList.Add(r.Commit); }
                using var p = Process.Start(psi) ?? throw new InvalidOperationException("PowerShell did not start");
                try { p.PriorityClass = ProcessPriorityClass.BelowNormal; } catch (Exception e) when (e is InvalidOperationException or System.ComponentModel.Win32Exception) { }   // (dotnet too: beside the game)
                var err = p.StandardError.ReadToEndAsync();
                text.Append(await p.StandardOutput.ReadToEndAsync()).Append(await err);
                await p.WaitForExitAsync();
                code = p.ExitCode;
            }
            catch (Exception e) { text.AppendLine(e.Message); }
            text.AppendLine("code " + code);
            try
            {
                string log = Path.Combine(NilsixWork, "update.log");
                if (File.Exists(log) && new FileInfo(log).Length > 256 * 1024) File.Delete(log);
                File.AppendAllText(log, text.ToString());
            }
            catch (Exception e) when (e is IOException or UnauthorizedAccessException) { }
            return code;
        }

        // SelfUpdateLauncherAsync's download, in this launcher: the new release's launcher built here with this page. The
        // release's own when that fails, or when this exe is not the folder's: StartUpdated starts this exe again, which
        // must then be the new release's, else it would update itself again and again (0 or 10: the script checked the
        // built exe's version; FileVersionInfo here would read this running exe's, the path's file being the new one).
        async Task NilsixReplaceLauncherAsync(Release r, string atRoot)
        {
            if (string.Equals(Path.GetFullPath(Updater.ExePath), Path.GetFullPath(atRoot), StringComparison.OrdinalIgnoreCase)
                && File.Exists(Path.Combine(NilsixWork, "record.json")))
            {
                SetLoad(NT("BUILDING THE LAUNCHER WITH NILSIX TOOLS", "COMPILATION DU LAUNCHER AVEC NILSIX TOOLS"), -1);
                if (s_nilsixKit != null) await s_nilsixKit;
                int code = await Task.Run(() => NilsixKit(_repo, r));
                if (code == 0 || code == 10)
                {
                    Updater.Log(_repo, "launcher " + r.Version + " built with NILSIX TOOLS");
                    return;
                }
                Updater.Log(_repo, $"NILSIX TOOLS: launcher {r.Version} not built (code {code}): the release's instead");
                SetLoad("UPDATING THE LAUNCHER", -1);
            }
            await Updater.ReplaceLauncherAsync(r, default, null, atRoot);
        }

        bool ActivateNilsixHit(string id)
        {
            switch (id)
            {
                case "nav:nilsix": GoView("nilsix"); return true;
                case "nilsix:sync-make": NilsixMakeSync(false); return true;
                case "nilsix:sync-fuse": NilsixMakeSync(true); return true;
                case "nilsix:sync-open":
                    if (_nilsixFile != null && File.Exists(_nilsixFile))
                        try { Process.Start(new ProcessStartInfo("explorer.exe", "/select,\"" + _nilsixFile + "\"") { UseShellExecute = false }); }
                        catch (System.ComponentModel.Win32Exception) { }
                    return true;
            }
            return false;
        }

        void NilsixMakeSync(bool fuse)
        {
            if (_nilsixProc != null) return;
            lock (_nilsixLog) _nilsixLog.Clear();
            _nilsixFile = _nilsixPrint = null;
            _nilsixFailed = false;
            _nilsixFuse = fuse;
            SetLoad(fuse ? NT("MAKING THE FUSION FILE", "CRÉATION DU FICHIER DE FUSION") : NT("MAKING THE FILE", "CRÉATION DU FICHIER"), -1);   // (the bar at the bottom; mods_sync.py's steps then)
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
                if (fuse) psi.ArgumentList.Add("--fuse");
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
                            ClearLoad();
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
                ClearLoad();
                NilsixLine(NT("Could not start the tool: ", "Impossible de lancer l'outil : ") + e.Message);
            }
            Invalidate();
        }

        void NilsixLine(string? line)
        {
            if (line == null) return;
            if (line.StartsWith("PROGRESS ", StringComparison.Ordinal))   // (mods_sync.py's step: "PROGRESS <0..1 or -1> <label>")
            {
                string[] p = line.Split(' ', 3);
                if (p.Length == 3 && float.TryParse(p[1], System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out float f))
                    SetLoad(p[2], f);
                return;
            }
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
            bool running = _nilsixProc != null, canMake = !running && !Busy;   // (Busy: another job has the bar at the bottom)

            // the mods sync card: what it does, the main button and the file's folder
            float cy = ContentTop * s, ch = 174 * s, cut = 22 * s, pad = 24 * s;
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
                                     "Crée un fichier à envoyer : il installe tes mods, active et désactive les mêmes, dans ton ordre, à tes versions."),
                    FB(14 * s), A(Theme.Muted), x + pad, cy + 84 * s, maxW, 20 * s);
                Theme.DrawText(g, NT("They double-click it with OpenSmash closed. SYNC OK and the same code as here: the same game online.",
                                     "Double-clic dessus, OpenSmash fermé. SYNCHRO OK et le même code qu'ici : le même jeu en ligne."),
                    FB(14 * s), A(Theme.Muted), x + pad, cy + 106 * s, maxW, 20 * s);
                Theme.DrawText(g, NT("Fusion: your turned-on mods join theirs (nothing is turned off), then a file comes back to you.",
                                     "Fusion : tes mods activés s'ajoutent aux siens (rien n'est désactivé), puis un fichier te revient."),
                    FB(14 * s), A(Theme.Muted), x + pad, cy + 128 * s, maxW, 20 * s);
                Theme.ButtonAnimated(g, NT("MAKE THE FILE", "CRÉER LE FICHIER"), bx, cy + 22 * s, bw, 38 * s, s, primary: true,
                    Hov("nilsix:sync-make", canMake && _hover == "nilsix:sync-make"), canMake, 13 * s, _alpha, press: Press("nilsix:sync-make"));
                if (canMake) AddHit("nilsix:sync-make", bx, cy + 22 * s, bw, 38 * s);
                Theme.ButtonAnimated(g, NT("MAKE A FUSION FILE", "CRÉER UNE FUSION"), bx, cy + 70 * s, bw, 32 * s, s, primary: false,
                    Hov("nilsix:sync-fuse", canMake && _hover == "nilsix:sync-fuse"), canMake, 12 * s, _alpha, press: Press("nilsix:sync-fuse"));
                if (canMake) AddHit("nilsix:sync-fuse", bx, cy + 70 * s, bw, 32 * s);
                bool canOpen = !running && _nilsixFile != null;
                Theme.ButtonAnimated(g, NT("SHOW THE FILE", "VOIR LE FICHIER"), bx, cy + 112 * s, bw, 32 * s, s, primary: false,
                    Hov("nilsix:sync-open", canOpen && _hover == "nilsix:sync-open"), canOpen, 12 * s, _alpha, press: Press("nilsix:sync-open"));
                if (canOpen) AddHit("nilsix:sync-open", bx, cy + 112 * s, bw, 32 * s);
                PopFade(g, st);
            }

            // what the tool says: its last lines, under the result
            float top = cy + ch + 34 * s, bottom = H - StatusH * s - 24 * s;
            {
                var st = PushReveal(g, 1);
                bool done = !running && !_nilsixFailed && _nilsixPrint != null;
                string head = running ? NT("WORKING...", "EN COURS...")
                    : done && _nilsixFuse ? NT("FUSION FILE ON THE DESKTOP", "FICHIER DE FUSION SUR LE BUREAU")   // (the fused set's code comes with the file sent back)
                    : done ? NT("FILE ON THE DESKTOP  ·  CODE ", "FICHIER SUR LE BUREAU  ·  CODE ") + _nilsixPrint
                    : _nilsixFailed ? NT("STOPPED", "ARRÊTÉ") : NT("LOG", "JOURNAL");
                Theme.Label(g, head, FM(12 * s, true), A(done ? Theme.Ready : _nilsixFailed ? Theme.Bad : Theme.Dim), x, top, 20 * s, 12 * s * 0.14f);
                if (_nilsixBoot && s_nilsixKit is { } kit)   // (the start's update check, on the right when it fits)
                {
                    string state = !kit.IsCompleted ? NT("NILSIX TOOLS: LOOKING FOR AN UPDATE...", "NILSIX TOOLS : RECHERCHE DE MISE À JOUR...")
                        : kit.Result == 10 && (s_nilsixRestartTimer != null || s_nilsixRestarting)   // (restarting, or once nothing runs)
                            ? NT("NILSIX TOOLS UPDATED: THE LAUNCHER RESTARTS", "NILSIX TOOLS MIS À JOUR : LE LAUNCHER REDÉMARRE")
                        : kit.Result == 10 ? NT("NILSIX TOOLS UPDATED: FROM THE NEXT START", "NILSIX TOOLS MIS À JOUR : AU PROCHAIN DÉMARRAGE")
                        : kit.Result == 0 ? NT("NILSIX TOOLS UP TO DATE", "NILSIX TOOLS À JOUR")
                        : NT("NILSIX TOOLS: UPDATE FAILED (update.log)", "NILSIX TOOLS : ÉCHEC DE LA MISE À JOUR (update.log)");
                    if (Theme.TextWidth(g, head, FM(12 * s, true), 12 * s * 0.14f, false) + Theme.TextWidth(g, state, FM(12 * s, true), 12 * s * 0.14f, false) + 32 * s < cw)
                        Theme.Label(g, state, FM(12 * s, true), A(kit.IsCompleted && kit.Result is not (0 or 10) ? Theme.Bad : Theme.Dim), x, top, 20 * s, 12 * s * 0.14f, StringAlignment.Far, cw);
                    if (!kit.IsCompleted && !_nilsixWatch)
                    {
                        _nilsixWatch = true;
                        kit.ContinueWith(_ => { try { BeginInvoke(new Action(Invalidate)); } catch (InvalidOperationException) { } });
                    }
                }
                HLine(g, x, x + cw, top + 28 * s);
                string[] lines;
                lock (_nilsixLog) lines = _nilsixLog.ToArray();
                float lh = 19 * s, ly = top + 38 * s;
                int fit = Math.Max(0, (int)((bottom - ly) / lh));
                if (lines.Length == 0 && !running)
                    Theme.DrawText(g, NT("Nothing yet: press MAKE THE FILE or MAKE A FUSION FILE.", "Rien pour l'instant : clique sur CRÉER LE FICHIER ou CRÉER UNE FUSION."),
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
