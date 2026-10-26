# WindowSmash setup kit - the orchestrator (Windows PowerShell 5.1). It lives in the repository
# github.com/Nilsix/WindowSmashLauncher (kit\ws_setup.ps1, next to kit\ws_setup.py) and is started by
# "WindowSmash Launcher.bat", which keeps a clone of that repository up to date in %LOCALAPPDATA%\WindowSmashLauncher.
# This file must stay UTF-8 with a BOM (Windows PowerShell 5.1 reads a BOM-less file as ANSI).
# A complete installer: it installs what is missing (Git, Python 3.14, Visual Studio Build Tools, LLVM, Opus), clones
# WindowSmash, prepares the user's own game files and builds the game.
# Every failure stops with a code (E..), an explanation and a report on the Desktop
# (WindowSmash-setup-report.txt) that can be sent back as it is: it holds no key and no game data.
# The player sees English, or French when chosen (menu 7, kept in %LOCALAPPDATA%\WindowSmash-setup\lang.txt): every
# message is written as L 'English' 'French'. The report and the log stay in English.
# Test-only environment: WS_NO_BUILD (skip the compile), WS_STOP_AFTER=<step>, WS_NO_NOTEPAD, WS_REPORT_DIR.
param([string]$KitDir = '', [string]$Mode = '')

$ErrorActionPreference = 'Stop'
$KitVersion = '3.3 (2026-10-26)'

# ---- what the host's build was made from: the friend's must match it for netplay ------------
# (the project moved from github.com/SNO2207 to github.com/OpenSmash-Ultimate on 2026-10-21; the old address forwards)
$WS_GIT_URL  = 'https://github.com/OpenSmash-Ultimate/WindowSmash.git'
$WS_COMMIT   = '8025b483b0443adb5668395eca31f9250e8c8efb'   # main, 2026-10-24: game 13.0.5 only, built by tools\build_game.py in the WindowSmash folder itself
$WS_BRANCH   = 'main'
$WS_ZIP      = "https://codeload.github.com/OpenSmash-Ultimate/WindowSmash/zip/$WS_COMMIT"
$WS_FILES    = @{   # SHA-256 (line ends as LF) of files of that commit: a copy without git is checked with them
    'tools\build_game.py' = 'f152e4e3a5b32b147e383a94a091e7328a1256b9b2cd0365e3f5e679a72fe4e1'
    'tools\update.py'     = '895ce9ee48621a194613ad60fe48ce6aa19db54b1832ce040531c0f04ff687d2'
    'tools\recomp.py'     = 'da89c88b19baa137e63957a753befb359fea3c878dd7d3415e165700333d6cf4'
    'tools\nca.py'        = 'dff2b794c2f773b06eb8fd391ad01e933c23de692a752333e48e268c834392cf'
}
$EXPECT_VERSION = '13.0.5'      # the only game version WindowSmash builds and plays since its commit ec8a8b5
$OLD_TREE       = 'v13.0.4'     # where kit 2.x built 13.0.4 (a version folder): its save comes over, then it can go
$LLVM_VER  = '20.1.8'
$LLVM_URL  = 'https://github.com/llvm/llvm-project/releases/download/llvmorg-20.1.8/clang%2Bllvm-20.1.8-x86_64-pc-windows-msvc.tar.xz'
$LLVM_SHA  = 'f229769f11d6a6edc8ada599c0cda964b7dee6ab1a08c6cf9dd7f513e85b107f'
$OPUS_URL  = 'https://downloads.xiph.org/releases/opus/opus-1.5.2.tar.gz'
$OPUS_SHA  = '65c1d2f78b9f2fb20082c38cbe47c951ad5839345876e46941612ee87f9a7ce1'
$PY_URL    = 'https://www.python.org/ftp/python/3.14.8/python-3.14.8-amd64.exe'
$PY_SHA    = '759be887b96e736a3ca886daf8d575f18fcae1a09efab6902f42d59e8999f8ef'
$VS_URL    = 'https://aka.ms/vs/17/release/vs_BuildTools.exe'
$GIT_URL   = 'https://github.com/git-for-windows/git/releases/download/v2.56.0.windows.2/Git-2.56.0.2-64-bit.exe'
$GIT_SHA   = '52188f917b378f00c70ec136bcf090005f30d44fbc4eba0bce759cc6592d60f6'
$SDL3_URL  = 'https://github.com/libsdl-org/SDL/releases/download/release-3.4.18/SDL3-devel-3.4.18-VC.zip'
$SDL3_SHA  = '78d84602ae616cfe26b33a73b7d3b9b6b56e8a6650e53d92c9c6ca938f747acd'
$NEED_GB   = 35

# ---- language --------------------------------------------------------------------------------
$LangTxt = Join-Path $env:LOCALAPPDATA 'WindowSmash-setup\lang.txt'
$Script:Lang = 'en'
try { if ((Get-Content -LiteralPath $LangTxt -Raw -ErrorAction Stop).Trim() -eq 'fr') { $Script:Lang = 'fr' } } catch {}
$env:WS_LANG = $Script:Lang      # (ws_setup.py speaks the same language)
function L([string]$en, [string]$fr) { if ($Script:Lang -eq 'fr') { return $fr } return $en }

function Set-Language([string]$lang) {
    $Script:Lang = $lang; $env:WS_LANG = $lang
    try { New-Item -ItemType Directory -Force (Split-Path $LangTxt -Parent) | Out-Null; Set-Content -LiteralPath $LangTxt -Value $lang -Encoding ASCII } catch {}
}

function Hint([string]$code) {
    switch ($code) {
        'E10' { L "The folder is not WindowSmash: it must hold README.md, tools and runtime." "Le dossier n'est pas WindowSmash : il doit contenir README.md, tools et runtime." }
        'E11' { L "WindowSmash could not be set to the right version. Check the internet connection. If you changed files in the folder, download it again." "Impossible de mettre WindowSmash à la bonne version. Vérifie internet. Si tu as modifié des fichiers du dossier, retélécharge-le." }
        'E12' { L "Git could not be installed. Install it from git-scm.com (default options), then start again." "Git n'a pas pu être installé. Installe-le depuis git-scm.com (options par défaut) puis relance." }
        'E13' { L "Cloning WindowSmash failed. Check the internet connection (is github.com reachable?), then start again." "Le clonage de WindowSmash a échoué. Vérifie internet (github.com accessible ?) puis relance." }
        'E15' { L "The tools needed were not installed (refused). Start again and answer Y to install them." "Les outils nécessaires n'ont pas été installés (refusé). Relance et réponds O pour les installer." }
        'E20' { L "Windows 10 or 11, 64-bit, is needed." "Il faut Windows 10 ou 11 en 64 bits." }
        'E21' { L "Your processor lacks the AVX2/FMA/F16C instructions: the game cannot run on this PC." "Ton processeur n'a pas les instructions AVX2/FMA/F16C : le jeu ne peut pas tourner sur ce PC." }
        'E22' { L "Not enough disk space. Free some (about $NEED_GB GB on the WindowSmash folder's disk), then start again." "Pas assez d'espace disque. Libère de la place (environ $NEED_GB Go sur le disque du dossier WindowSmash) puis relance." }
        'E23' { L "The WindowSmash folder is in OneDrive: move it elsewhere (for example C:\Games\WindowSmash), then start again." "Le dossier WindowSmash est dans OneDrive : déplace-le ailleurs (par exemple C:\Jeux\WindowSmash) puis relance." }
        'E30' { L "Python 3.14 could not be installed. Install it from python.org (tick 'Add python.exe to PATH'), then start again." "Python 3.14 n'a pas pu être installé. Installe-le depuis python.org (coche 'Add python.exe to PATH') puis relance." }
        'E31' { L "The Python environment failed (pip downloads pycryptodomex: check the internet connection), then start again." "L'environnement Python a échoué (pip télécharge pycryptodomex : vérifie internet) puis relance." }
        'E32' { L "Microsoft's build tools (Build Tools) did not install. Accept the administrator window when it appears, then start again." "Les outils de compilation Microsoft (Build Tools) ne se sont pas installés. Accepte la fenêtre administrateur quand elle apparaît, puis relance." }
        'E33' { L "Build Tools incomplete: open 'Visual Studio Installer', Modify, tick 'Desktop development with C++' (with the Windows SDK), then start again." "Build Tools incomplets : ouvre 'Visual Studio Installer', Modifier, coche 'Développement Desktop en C++' (avec le SDK Windows), puis relance." }
        'E34' { L "Downloading LLVM (the compiler, 900 MB) failed or the file is damaged. Start again." "Le téléchargement de LLVM (le compilateur, 900 Mo) a échoué ou est abîmé. Relance." }
        'E35' { L "The compiler does not work (compile test). Send the report." "Le compilateur ne marche pas (test de compilation). Envoie le rapport." }
        'E40' { L "A file that was asked for was not chosen. Start again and choose it." "Un fichier demandé n'a pas été choisi. Relance et choisis-le." }
        'E41' { L "Problem with prod.keys: it must be the one dumped from YOUR up-to-date console (Lockpick_RCM)." "Problème avec prod.keys : il faut celui dumpé de TA console à jour (Lockpick_RCM)." }
        'E42' { L "The base game is not right: it must be Super Smash Bros. Ultimate 1.0.0 (.xci or .nsp), not an update." "Le jeu de base ne convient pas : il faut Super Smash Bros. Ultimate 1.0.0 (.xci ou .nsp), pas une mise à jour." }
        'E43' { L "The update is not right: WindowSmash needs Smash Ultimate's $EXPECT_VERSION update (.nsp), dumped from your up-to-date Switch." "La mise à jour ne convient pas : WindowSmash demande l'update $EXPECT_VERSION de Smash Ultimate (.nsp), dumpée de ta Switch à jour." }
        'E44' { L "Ticket missing or tied to your console: dump again with nxdumptool, ticking 'remove console specific data', or give a title.keys." "Ticket manquant ou lié à ta console : redumpe avec nxdumptool en cochant 'remove console specific data', ou donne un title.keys." }
        'E45' { L "Firmware fonts not found: choose your console's firmware folder or an emulator's (.nca files)." "Polices du firmware introuvables : choisis le dossier du firmware de ta console ou d'un émulateur (fichiers .nca)." }
        'E50' { L "The decrypted copy of the base game failed (disk full? damaged file?)." "La copie déchiffrée du jeu de base a échoué (disque plein ? fichier abîmé ?)." }
        'E51' { L "Applying the update failed." "L'application de la mise à jour a échoué." }
        'E52' { L "Extracting the fighter modules failed." "L'extraction des modules de combattants a échoué." }
        'E53' { L "A preparation step failed." "Une étape de préparation a échoué." }
        'E59' { L "Internal error of the Python script: send the report." "Erreur interne du script Python : envoie le rapport." }
        'E60' { L "The compile failed." "La compilation a échoué." }
        'E61' { L "Making ssbu.exe failed: close the game if it is running, then start again." "La création de ssbu.exe a échoué : ferme le jeu s'il tourne et relance." }
        'E62' { L "ssbu.exe vanished after the compile: your antivirus may have removed it (add an exclusion for the WindowSmash folder)." "ssbu.exe a disparu après la compilation : ton antivirus l'a peut-être supprimé (ajoute une exclusion pour le dossier WindowSmash)." }
        'E70' { L "The game did not start." "Le jeu ne s'est pas lancé." }
        'E85' { L "Shader precompilation stopped: close the game, then start WindowSmash Launcher again and choose 5)." "La précompilation des shaders s'est arrêtée : ferme le jeu, puis relance WindowSmash Launcher et choisis 5)." }
        'E80' { L "Unlocking the fighters failed: start the game once up to the menu, close it, then choose option 4 again." "Déblocage des personnages impossible : lance le jeu une fois jusqu'au menu, ferme-le, puis relance l'option 4." }
        'E99' { L "Unexpected error of the script: send the report." "Erreur inattendue du script : envoie le rapport." }
        default { $null }
    }
}

# ---- paths ----------------------------------------------------------------------------------
$HomeDir  = Join-Path $env:LOCALAPPDATA 'WindowSmash-setup'
$Stamp    = Get-Date -Format 'yyyyMMdd-HHmmss'
$LogDir   = Join-Path $HomeDir "logs\$Stamp"
$MainLog  = Join-Path $LogDir 'setup.log'
$Desktop  = [Environment]::GetFolderPath('Desktop')
$ReportDir = if ($env:WS_REPORT_DIR) { $env:WS_REPORT_DIR } else { $Desktop }   # (tests: elsewhere)
$Report   = Join-Path $ReportDir 'WindowSmash-setup-report.txt'
$Helper   = Join-Path $PSScriptRoot 'ws_setup.py'
$InputsJs = Join-Path $HomeDir 'inputs.json'
$RepoTxt  = Join-Path $HomeDir 'repo.txt'          # where WindowSmash was installed, for the next runs
New-Item -ItemType Directory -Force $LogDir | Out-Null
$Script:AutoInstall = $false; $Script:Git = $null
# display.ini as the game writes it at its first start (WindowSmash 8025b48), with latency 1
$DisplayIni = @'
; display.ini: the game's window and the pacing of its frames. Read when the game starts; the
; settings menu (Esc in the game) changes it too.
; Delete this file to get it written again with the defaults. A line starting with ';' is a comment.

; window = windowed | borderless | fullscreen
;   windowed:   a normal window, kept 16:9 while you resize it.
;   borderless: no frame, covering the monitor the window is on.
;   fullscreen: borderless and always on top (the monitor keeps its resolution).
; F11 or Alt+Enter switches between the window and full screen while playing.
window = windowed
; width, height: the window's inside, at 100% display scaling (scaled with Windows' setting).
width = 1280
height = 720

; pacing = clock | vrr | display
;   clock:   a steady 60 frames a second; each is shown at the monitor's next refresh.
;   vrr:     for G-Sync / FreeSync monitors: each frame is shown the moment it is ready, so every
;            frame stays on screen exactly 16.7 ms. Best with window = borderless. Tears without VRR.
;   display: follow the monitor's refreshes (60, 120 or 240 Hz only; else as clock). The game then
;            runs at the monitor's exact rate, e.g. 59.94 frames a second.
pacing = clock
; latency = 1-3: how many frames the graphics card may work ahead. Lower is more responsive.
latency = 1
; hide_cursor = 1: hide the mouse pointer over the game after 2 seconds without moving it.
hide_cursor = 1
; overlay = 1: show the frame rate in the corner from the start (F1 shows or hides it while playing).
overlay = 1

; render_scale = 1 | auto | a number from 0.5 to 4
;   The game draws its pictures at 1920x1080. render_scale draws them this many times as wide and
;   as tall: sharper on a bigger screen, more work for the graphics card (2 = four times the pixels).
;   auto: as many pixels as the picture has in the window when the game starts (1.33 on a 2560x1440
;   monitor with window = borderless), at least 1. A bigger picture than the window is shrunk to fit.
render_scale = 1

; gpu = auto, or part of a graphics card's name (e.g. nvidia, radeon, intel)
;   auto: the fastest card. On a laptop with two, the NVIDIA or AMD one, not the processor's own.
;   The game's log (build\play.log) lists the cards it found at its start.
gpu = auto
'@

$Script:Repo = $null; $Script:VenvPy = $null; $Script:SysPy = $null; $Script:Deps = $null
$Script:Steps = New-Object System.Collections.Specialized.OrderedDictionary
$Script:Info = [ordered]@{}; $Script:Warnings = New-Object System.Collections.ArrayList
$Script:LastLog = $null; $Script:Inputs = @{}

try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}
$env:PYTHONIOENCODING = 'utf-8'; $env:PYTHONUNBUFFERED = '1'

# ---- output ---------------------------------------------------------------------------------
function Log([string]$t) { Add-Content -LiteralPath $MainLog -Value ("{0:HH:mm:ss} {1}" -f (Get-Date), $t) -Encoding UTF8 }
function Say([string]$t)  { Write-Host $t; Log $t }
function Ok([string]$t)   { Write-Host "  [OK] $t" -ForegroundColor Green; Log "[OK] $t" }
function Warn([string]$t) { Write-Host "  [!] $t" -ForegroundColor Yellow; Log "[WARN] $t"; [void]$Script:Warnings.Add($t) }
function Title([string]$t) { Write-Host ''; Write-Host "=== $t ===" -ForegroundColor Cyan; Log "=== $t" }

function Redact([string]$t) {
    # The Windows user name, in paths only: a short name ("PC") would otherwise be replaced inside other words.
    if (-not $t) { return $t }
    $t = $t -replace [regex]::Escape($env:USERPROFILE), '%USERPROFILE%'
    if ($env:USERNAME) { $t = $t -replace ('(?<=\\Users\\)' + [regex]::Escape($env:USERNAME) + '(?=\\|$)'), '<user>' }
    return $t
}

function Ask-YesNo([string]$q, [bool]$default = $true, [switch]$Install) {
    if ($Install -and $Script:AutoInstall) { Say "$q -> $(L 'yes (accepted at the start)' 'oui (accepté au début)')"; return $true }
    $s = if ($default) { L '[Y/n]' '[O/n]' } else { L '[y/N]' '[o/N]' }
    while ($true) {
        $a = Read-Host "$q $s"
        if (-not $a) { return $default }
        if ($a -match '^(o|oui|y|yes)$') { return $true }
        if ($a -match '^(n|non|no)$') { return $false }
    }
}

function Pick-File([string]$title, [string]$filter, [string]$initial) {
    Say $title
    try {
        Add-Type -AssemblyName System.Windows.Forms
        $d = New-Object System.Windows.Forms.OpenFileDialog
        $d.Title = $title; $d.Filter = $filter; $d.Multiselect = $false
        if ($initial -and (Test-Path -LiteralPath (Split-Path $initial -Parent))) { $d.InitialDirectory = Split-Path $initial -Parent }
        $owner = New-Object System.Windows.Forms.Form -Property @{ TopMost = $true }
        $r = $d.ShowDialog($owner); $owner.Dispose()
        if ($r -eq [System.Windows.Forms.DialogResult]::OK) { return $d.FileName }
        return $null
    } catch {
        $p = Read-Host (L '  Path of the file (or Enter to cancel)' '  Chemin du fichier (ou Entrée pour annuler)')
        if ($p) { return $p.Trim('"') }
        return $null
    }
}

function Pick-Folder([string]$title) {
    Say $title
    try {
        Add-Type -AssemblyName System.Windows.Forms
        $d = New-Object System.Windows.Forms.FolderBrowserDialog
        $d.Description = $title; $d.ShowNewFolderButton = $false
        $owner = New-Object System.Windows.Forms.Form -Property @{ TopMost = $true }
        $r = $d.ShowDialog($owner); $owner.Dispose()
        if ($r -eq [System.Windows.Forms.DialogResult]::OK) { return $d.SelectedPath }
        return $null
    } catch {
        $p = Read-Host (L '  Path of the folder (or Enter to cancel)' '  Chemin du dossier (ou Entrée pour annuler)')
        if ($p) { return $p.Trim('"') }
        return $null
    }
}

function Set-Step([string]$name, [string]$status, [string]$detail = '') {
    $Script:Steps[$name] = "{0,-8} {1}" -f $status, $detail
    Log "STEP $name = $status $detail"
}

function Tail([string]$path, [int]$n = 80) {
    if ($path -and (Test-Path -LiteralPath $path)) { return (Get-Content -LiteralPath $path -Tail $n -Encoding UTF8) -join "`r`n" }
    return '(no log)'
}

# ---- report ---------------------------------------------------------------------------------
function Write-Report([string]$status, [string]$code = '', [string]$message = '') {
    $L = New-Object System.Collections.ArrayList
    $add = { param($x) [void]$L.Add([string]$x) }
    & $add "WINDOWSMASH SETUP REPORT - kit $KitVersion (language: $Script:Lang)"
    & $add ("Date: {0}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
    & $add "Result: $status"
    if ($code) {
        & $add "Code: $code"
        & $add "Message: $message"
        if (Hint $code) { & $add "What to do: $(Hint $code)" }
    }
    & $add ''
    & $add '--- Steps'
    foreach ($k in $Script:Steps.Keys) { & $add ("  {0,-22} {1}" -f $k, $Script:Steps[$k]) }
    if ($Script:Warnings.Count) { & $add ''; & $add '--- Warnings'; foreach ($w in $Script:Warnings) { & $add "  $w" } }
    & $add ''
    & $add '--- System and tools'
    foreach ($k in $Script:Info.Keys) { & $add ("  {0,-22} {1}" -f $k, (Redact ([string]$Script:Info[$k]))) }
    if ($Script:Repo -and $Script:VenvPy -and (Test-Path -LiteralPath $Script:VenvPy)) {
        try {
            $st = Invoke-Helper @('status')
            if ($st.Json) { & $add ''; & $add '--- The game in the WindowSmash folder'; & $add (Redact ($st.Json | ConvertTo-Json -Compress -Depth 4)) }
        } catch {}
    }
    if ($Script:LastLog) {
        & $add ''
        & $add "--- End of the step's log ($(Redact $Script:LastLog))"
        & $add (Redact (Tail $Script:LastLog 80))
    }
    & $add ''
    & $add '--- End of the main log'
    & $add (Redact (Tail $MainLog 40))
    & $add ''
    & $add "Full logs: $(Redact $LogDir)"
    [IO.File]::WriteAllLines($Report, [string[]]$L, (New-Object Text.UTF8Encoding $true))
}

function Fail([string]$code, [string]$message, [string]$log = '') {
    if ($log) { $Script:LastLog = $log }
    Write-Host ''
    Write-Host "  $(L 'FAILED' 'ÉCHEC') [$code] $message" -ForegroundColor Red
    if (Hint $code) { Write-Host "  -> $(Hint $code)" -ForegroundColor Yellow }
    Log "FAIL $code $message"
    Write-Report "FAILED" $code $message
    Write-Host ''
    Write-Host (L "  Report written on the Desktop: WindowSmash-setup-report.txt" "  Rapport écrit sur le Bureau : WindowSmash-setup-report.txt") -ForegroundColor Cyan
    Write-Host (L "  Send this file as it is (it holds no keys and no game files)." "  Envoie ce fichier tel quel (il ne contient ni clés ni fichiers du jeu).") -ForegroundColor Cyan
    if (-not $env:WS_NO_NOTEPAD) { try { Start-Process notepad.exe -ArgumentList "`"$Report`"" } catch {} }
    Write-Host ''
    Read-Host (L 'Press Enter to close' 'Appuie sur Entrée pour fermer')
    exit 10      # handled: the launcher does not pause again
}

# ---- running things -------------------------------------------------------------------------
function Quote([string]$a) { if ($a -match '[\s"]' -or $a -eq '') { '"' + ($a -replace '"', '\"') + '"' } else { $a } }

function Run-Logged([string]$exe, [string[]]$argv, [string]$name) {
    # A tool whose output goes to logs\<name>.out/.err; returns the exit code.
    $out = Join-Path $LogDir "$name.out.txt"; $err = Join-Path $LogDir "$name.err.txt"
    $Script:LastLog = $out
    Log "RUN $exe $($argv -join ' ')"
    $sp = @{ FilePath = $exe; NoNewWindow = $true; Wait = $true; PassThru = $true; RedirectStandardOutput = $out; RedirectStandardError = $err }
    if ($argv -and $argv.Count) { $sp.ArgumentList = (($argv | ForEach-Object { Quote $_ }) -join ' ') }
    $p = Start-Process @sp
    if ((Test-Path $err) -and (Get-Item $err).Length) { Add-Content -LiteralPath $out -Value (Get-Content -LiteralPath $err -Encoding UTF8) -Encoding UTF8 }
    $code = $p.ExitCode
    if ($null -eq $code) { $code = -999 }
    Log "EXIT $code"
    return $code
}

function Run-Installer([string]$exe, [string[]]$argv, [string]$name) {
    # An installer started through the shell, so that it can ask for administrator rights (UAC); returns its exit code.
    Log "INSTALL $exe $($argv -join ' ')"
    $sp = @{ FilePath = $exe; Wait = $true; PassThru = $true }
    if ($argv -and $argv.Count) { $sp.ArgumentList = (($argv | ForEach-Object { Quote $_ }) -join ' ') }
    try { $p = Start-Process @sp } catch { Log "INSTALL error: $($_.Exception.Message)"; return -998 }
    $code = $p.ExitCode
    if ($null -eq $code) { $code = -999 }
    Log "EXIT $code"
    Add-Content -LiteralPath (Join-Path $LogDir "$name.out.txt") -Value "$exe $($argv -join ' ') -> exit $code" -Encoding UTF8
    $Script:LastLog = Join-Path $LogDir "$name.out.txt"
    return $code
}

function Run-Native([scriptblock]$sb) { $ErrorActionPreference = 'Continue'; & $sb }

function Stop-Test([string]$step) {
    if ($env:WS_STOP_AFTER -and $env:WS_STOP_AFTER -eq $step) {   # (tests only)
        Write-Report "TEST (stopped after $step)"; Say "  [test] stopped after $step"; Read-Host (L 'Enter to close' 'Entrée pour fermer'); exit 0
    }
}

function Invoke-Helper([string[]]$hargs, [switch]$Live, [string]$name = '') {
    $py = if ($Script:VenvPy -and (Test-Path -LiteralPath $Script:VenvPy)) { $Script:VenvPy } else { $Script:SysPy }
    $repoArg = if ($Script:Repo) { $Script:Repo } else { '.' }
    $ErrorActionPreference = 'Continue'
    if ($Live) {
        $log = Join-Path $LogDir "$name.txt"; $Script:LastLog = $log
        Log "HELPER $($hargs -join ' ') (log $log)"
        & $py -u $Helper --repo $repoArg --log $log @hargs | Out-Host     # shown as it comes; the helper keeps the log
        $code = $LASTEXITCODE
        $lines = if (Test-Path -LiteralPath $log) { @(Get-Content -LiteralPath $log -Encoding UTF8) } else { @() }
    } else {
        Log "HELPER $($hargs -join ' ')"
        $lines = @(& $py -u $Helper --repo $repoArg @hargs 2>&1 | ForEach-Object { "$_" })
        $code = $LASTEXITCODE
        foreach ($l in $lines) { Log "  | $l" }
    }
    $err = $lines | Where-Object { $_ -like '@@ERROR *' } | Select-Object -Last 1
    $js = $lines | Where-Object { $_ -like '@@JSON *' } | Select-Object -Last 1
    foreach ($w in ($lines | Where-Object { $_ -like '@@WARN *' })) { Warn $w.Substring(7) }
    $obj = $null
    if ($js) { try { $obj = $js.Substring(7) | ConvertFrom-Json } catch {} }
    $ecode = $null; $etext = $null
    if ($err) { $parts = $err.Substring(8).Split(' ', 2); $ecode = $parts[0]; if ($parts.Count -gt 1) { $etext = $parts[1] } }
    return [pscustomobject]@{ Code = $code; Lines = $lines; ErrCode = $ecode; ErrText = $etext; Json = $obj }
}

function Helper-OrFail([string[]]$hargs, [string]$code, [switch]$Live, [string]$name = '') {
    $r = Invoke-Helper $hargs -Live:$Live -name $name
    if ($r.Code -ne 0) {
        $c = if ($r.ErrCode) { $r.ErrCode } else { $code }
        $t = if ($r.ErrText) { $r.ErrText } else { L "the Python script stopped (code $($r.Code))" "le script Python s'est arrêté (code $($r.Code))" }
        if (-not $Live) { $tmp = Join-Path $LogDir "helper-$code.txt"; $r.Lines | Set-Content -LiteralPath $tmp -Encoding UTF8; $Script:LastLog = $tmp }
        Fail $c $t
    }
    return $r
}

function Get-FileSha256([string]$path) { (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLower() }

function Get-NormalizedSha256([string]$path) {
    $b = [IO.File]::ReadAllBytes($path)
    $ms = New-Object IO.MemoryStream
    foreach ($x in $b) { if ($x -ne 13) { $ms.WriteByte($x) } }
    $h = [Security.Cryptography.SHA256]::Create().ComputeHash($ms.ToArray())
    return (($h | ForEach-Object { $_.ToString('x2') }) -join '')
}

function Download-Fail([string]$code, [string]$msg) { if ($code -like 'W*') { throw $msg } else { Fail $code $msg } }

function Download([string]$url, [string]$dest, [string]$sha, [string]$label, [string]$code) {
    if ((Test-Path -LiteralPath $dest) -and $sha -and ((Get-FileSha256 $dest) -eq $sha)) { Ok (L "$label already downloaded" "$label déjà téléchargé"); return }
    Say (L "  Downloading: $label" "  Téléchargement : $label")
    New-Item -ItemType Directory -Force (Split-Path $dest -Parent) | Out-Null
    $curl = Join-Path $env:SystemRoot 'System32\curl.exe'
    $done = $false
    if (Test-Path $curl) {
        Run-Native { & $curl -L --fail --retry 3 --retry-delay 5 -o "$dest.part" $url }
        $done = ($LASTEXITCODE -eq 0)
    }
    if (-not $done) {
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            $ProgressPreference = 'SilentlyContinue'
            Invoke-WebRequest -Uri $url -OutFile "$dest.part" -UseBasicParsing
            $done = $true
        } catch { Log "download error: $($_.Exception.Message)" }
    }
    if (-not $done) { Download-Fail $code (L "download failed: $url" "téléchargement impossible : $url") }
    if ($sha) {
        $got = Get-FileSha256 "$dest.part"
        if ($got -ne $sha) { Remove-Item -LiteralPath "$dest.part" -Force; Download-Fail $code (L "downloaded file damaged (${label}: SHA-256 $got instead of $sha)" "fichier téléchargé corrompu ($label : SHA-256 $got au lieu de $sha)") }
    }
    Move-Item -LiteralPath "$dest.part" -Destination $dest -Force
    Ok (L "$label downloaded" "$label téléchargé")
}

# ---- probes ---------------------------------------------------------------------------------
function Probe-System {
    Title (L 'Checking the PC' 'Vérification du PC')
    $os = Get-CimInstance Win32_OperatingSystem
    $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
    $ram = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 1)
    $Script:Info['Kit'] = $KitVersion
    $lr = Split-Path $PSScriptRoot -Parent; $lg = Find-Git     # the launcher's clone of its repository: which revision ran
    if ($lg -and (Test-Path -LiteralPath (Join-Path $lr '.git'))) { $Script:Info['Launcher (git)'] = (Run-Native { & $lg -C $lr log -1 '--format=%h %cs' }) | Select-Object -First 1 }
    $Script:Info['Windows'] ="$($os.Caption) $($os.Version) ($($os.OSArchitecture))"
    $Script:Info['Processor'] = "$($cpu.Name.Trim()) - $($cpu.NumberOfCores) cores / $($cpu.NumberOfLogicalProcessors) threads"
    $Script:Info['RAM'] = "$ram GB (free {0} GB, free virtual memory {1} GB)" -f [math]::Round($os.FreePhysicalMemory / 1MB, 1), [math]::Round($os.FreeVirtualMemory / 1MB, 1)
    $gpus = Get-CimInstance Win32_VideoController | ForEach-Object { "$($_.Name) (driver $($_.DriverVersion))" }
    $Script:Info['Graphics card'] = ($gpus -join ' ; ')
    $Script:Info['PowerShell'] = $PSVersionTable.PSVersion.ToString()
    try {
        Add-Type -Namespace WsSetup -Name Cpu -MemberDefinition '[DllImport("kernel32.dll")] public static extern bool IsProcessorFeaturePresent(uint f);' -ErrorAction SilentlyContinue
        $Script:Info['AVX2 (Windows)'] = [WsSetup.Cpu]::IsProcessorFeaturePresent(40)
    } catch { $Script:Info['AVX2 (Windows)'] = 'unknown' }
    Say "  $($Script:Info['Windows'])"
    Say "  $($Script:Info['Processor']), RAM $ram $(L 'GB' 'Go')"
    Say "  $($Script:Info['Graphics card'])"
    if ($os.OSArchitecture -notmatch '64') { Set-Step 'PC' 'FAILED' 'Windows 32-bit'; Fail 'E20' (L 'Windows 32-bit' 'Windows 32 bits') }
    if ($Script:Info['AVX2 (Windows)'] -eq $false) { Warn (L "W21 Windows says the processor lacks AVX2: the compiler test will tell" "W21 Windows dit que le processeur n'a pas AVX2 : le test du compilateur confirmera") }
    if ($ram -lt 12) { Warn (L "W24 only $ram GB of RAM: the compile will be slow (fewer jobs at a time)" "W24 seulement $ram Go de RAM : la compilation sera lente (moins de tâches en parallèle)") }
    Set-Step 'PC' 'OK'
}

# ---- Git ------------------------------------------------------------------------------------
function Find-Git {
    $g = Get-Command git -ErrorAction SilentlyContinue
    if ($g) { return $g.Source }
    foreach ($p in @("$env:ProgramFiles\Git\cmd\git.exe", "${env:ProgramFiles(x86)}\Git\cmd\git.exe", "$env:LOCALAPPDATA\Programs\Git\cmd\git.exe")) {
        if (Test-Path -LiteralPath $p) { return $p }
    }
    return $null
}

# Git refuses a repository it cannot prove the user owns ("detected dubious ownership"): one on a drive whose file
# system records no owner (exFAT or FAT32, as big external disks often are) or one made by another account. The kit's
# own WindowSmash folder is declared safe for the git commands the kit starts (and their children) through
# GIT_CONFIG_*: command-scope configuration, where safe.directory counts, so the player's git settings stay as they are.
function Set-GitSafeRepo {
    if (-not $Script:Repo) { return }
    $dir = $Script:Repo -replace '\\', '/'
    $n = if ($env:GIT_CONFIG_COUNT -match '^\d+$') { [int]$env:GIT_CONFIG_COUNT } else { 0 }
    for ($i = 0; $i -lt $n; $i++) {
        if ([Environment]::GetEnvironmentVariable("GIT_CONFIG_KEY_$i") -eq 'safe.directory' -and
            [Environment]::GetEnvironmentVariable("GIT_CONFIG_VALUE_$i") -eq $dir) { return }
    }
    [Environment]::SetEnvironmentVariable("GIT_CONFIG_KEY_$n", 'safe.directory')
    [Environment]::SetEnvironmentVariable("GIT_CONFIG_VALUE_$n", $dir)
    $env:GIT_CONFIG_COUNT = "$($n + 1)"
}

# git's own reason for a failure, from its captured output: its last "fatal:" or "error:" line, else its last line.
function Get-GitError($lines) {
    $l = @($lines | ForEach-Object { "$_".Trim() } | Where-Object { $_ })
    $why = @($l | Where-Object { $_ -match '^(fatal|error):' }) | Select-Object -Last 1
    if (-not $why) { $why = $l | Select-Object -Last 1 }
    foreach ($x in $l) { Log "GIT $x" }
    return "$why"
}

# The decrypted base game: in dump\game_files since kit 3.2 (where the game reads it), in dump\base before.
function Test-PlainBase {
    return (Test-Path -LiteralPath (Join-Path $Script:Repo 'dump\game_files\program_v0.nca')) -or
           (Test-Path -LiteralPath (Join-Path $Script:Repo 'dump\base\program_v0.nca'))
}

function Ensure-Git {
    Title 'Git'
    $Script:Git = Find-Git
    if (-not $Script:Git) {
        if (-not (Ask-YesNo (L '  Git (to download WindowSmash) is not installed. Install it?' '  Git (pour télécharger WindowSmash) n''est pas installé. Je l''installe ?') -Install)) { Set-Step 'Git' 'FAILED' 'refused'; Fail 'E12' (L 'Git install refused' 'installation de Git refusée') }
        $wg = Get-Command winget -ErrorAction SilentlyContinue
        if ($wg) {
            Say (L '  Installing Git with winget (an administrator window may open: accept it)...' '  Installation de Git par winget (une fenêtre administrateur peut s''ouvrir : accepte-la)...')
            $rc = Run-Logged $wg.Source @('install', '-e', '--id', 'Git.Git', '--silent', '--accept-package-agreements', '--accept-source-agreements') 'winget-git'
            Log "winget git exit $rc"
            $Script:Git = Find-Git
        }
        if (-not $Script:Git) {
            $inst = Join-Path $HomeDir 'downloads\Git-2.56.0.2-64-bit.exe'
            Download $GIT_URL $inst $GIT_SHA 'Git 2.56.0 (65 MB)' 'E12'
            $sig = Get-AuthenticodeSignature -LiteralPath $inst
            if ($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch 'Johannes Schindelin') { Fail 'E12' (L "the Git installer's signature is not valid ($($sig.Status))" "signature de l'installateur Git invalide ($($sig.Status))") }
            Say (L '  Installing Git (an administrator window will open: accept it)...' '  Installation de Git (une fenêtre administrateur va s''ouvrir : accepte-la)...')
            $rc = Run-Installer $inst @('/VERYSILENT', '/NORESTART', '/NOCANCEL', '/SP-', '/SUPPRESSMSGBOXES') 'git-install'
            if ($rc -ne 0) { Set-Step 'Git' 'FAILED' "installer $rc"; Fail 'E12' (L "the Git installer failed (code $rc)" "l'installateur de Git a échoué (code $rc)") }
            $Script:Git = Find-Git
        }
        if (-not $Script:Git) { Set-Step 'Git' 'FAILED' 'not found'; Fail 'E12' (L 'Git not found after the install' 'Git introuvable après installation') }
    }
    $ver = (Run-Native { & $Script:Git --version }) | Select-Object -First 1
    $Script:Info['Git'] = "$ver ($($Script:Git))"
    Ok "$ver"
    Set-Step 'Git' 'OK' "$ver"
}

# ---- what is missing, said once ---------------------------------------------------------------
function Show-Prereqs {
    Title (L 'What will be installed' 'Ce qui va être installé')
    $repo = Get-RememberedRepo
    if (-not $repo) { foreach ($c in @($KitDir, (Split-Path $KitDir -Parent))) { if ($c -and (Test-RepoDir $c)) { $repo = $c } } }
    $deps = if ($repo) { Join-Path $repo 'dump\_setup' } else { $null }
    $vs = Get-VS; $sdk = Get-SdkLib
    $rows = @(
        @('Git', [bool](Find-Git), (L '65 MB' '65 Mo')),
        @('Python 3.14', [bool](Find-Python), (L '30 MB' '30 Mo')),
        @((L 'Microsoft Build Tools (C++, Windows SDK, CMake)' 'Outils Microsoft Build Tools (C++, SDK Windows, CMake)'), [bool]($vs -and $sdk), (L '3 to 6 GB, administrator window' '3 à 6 Go, fenêtre administrateur')),
        @((L "LLVM compiler $LLVM_VER" "Compilateur LLVM $LLVM_VER"), [bool]($deps -and (Test-Path -LiteralPath (Join-Path $deps "llvm-$LLVM_VER\bin\clang-cl.exe"))), (L '900 MB' '900 Mo')),
        @((L 'Opus audio library' 'Bibliothèque audio Opus'), [bool]($deps -and (Test-Path -LiteralPath (Join-Path $deps 'opus\lib\opus.lib'))), (L '1 MB, built here' '1 Mo, compilée sur place')),
        @((L 'SDL3 controller library' 'Bibliothèque manettes SDL3'), [bool]($repo -and (Test-Path -LiteralPath (Join-Path $repo 'deps\SDL3\include\SDL3\SDL_gamepad.h'))), (L '7 MB' '7 Mo')),
        @('WindowSmash (git clone)', [bool]$repo, (L '2 MB' '2 Mo'))
    )
    $missing = 0
    foreach ($r in $rows) {
        if ($r[1]) { Write-Host ("  [OK] {0}" -f $r[0]) -ForegroundColor Green }
        else { Write-Host ((L "  [ ] {0} - to install ({1})" "  [ ] {0} - à installer ({1})") -f $r[0], $r[2]) -ForegroundColor Yellow; $missing++ }
        Log ("PREREQ {0} = {1}" -f $r[0], $r[1])
    }
    $Script:Info['winget'] = if (Get-Command winget -ErrorAction SilentlyContinue) { 'yes' } else { 'no (direct downloads)' }
    Say (L "  Then: copy of your game, $EXPECT_VERSION update, compile (1 to 3 hours)." "  Ensuite : copie de ton jeu, mise à jour $EXPECT_VERSION, compilation (1 à 3 heures).")
    if ($missing) {
        if (-not (Ask-YesNo (L "  Install what is missing ($missing item(s)), then all the rest, without asking again?" "  J'installe ce qui manque ($missing élément(s)) puis tout le reste, sans reposer de question ?"))) {
            Set-Step 'Tools' 'FAILED' 'refused'; Fail 'E15' (L 'tools install refused' 'installation des outils refusée')
        }
        $Script:AutoInstall = $true
    }
    Set-Step 'Tools' 'OK' "$missing to install"
}

# ---- repository -----------------------------------------------------------------------------
function Test-RepoDir([string]$d) { return ($d -and (Test-Path -LiteralPath (Join-Path $d 'tools\recomp.py')) -and (Test-Path -LiteralPath (Join-Path $d 'runtime'))) }

function Get-RepoZip([string]$target) {
    $zip = Join-Path $HomeDir "downloads\WindowSmash-$WS_COMMIT.zip"
    Download $WS_ZIP $zip '' 'WindowSmash (source)' 'E11'
    $tmp = Join-Path $HomeDir "unzip-$Stamp"
    try { Expand-Archive -LiteralPath $zip -DestinationPath $tmp -Force } catch { Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue; Fail 'E11' (L "WindowSmash archive unreadable: $($_.Exception.Message)" "archive WindowSmash illisible : $($_.Exception.Message)") }
    $src = Get-ChildItem -LiteralPath $tmp -Directory | Select-Object -First 1
    New-Item -ItemType Directory -Force $target | Out-Null
    $rc = Run-Logged (Join-Path $env:SystemRoot 'System32\robocopy.exe') @($src.FullName, $target, '/E', '/NFL', '/NDL', '/NJH', '/NJS', '/NP', '/R:2', '/W:2') 'robocopy-repo'
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    if ($rc -ge 8) { Fail 'E11' (L "copying the WindowSmash files failed (robocopy $rc)" "copie des fichiers WindowSmash impossible (robocopy $rc)") }
}

function Get-RememberedRepo {
    if (Test-Path -LiteralPath $RepoTxt) { $p = (Get-Content -LiteralPath $RepoTxt -Raw).Trim(); if (Test-RepoDir $p) { return $p } }
    return $null
}

function Get-DefaultInstallDir {
    # the local disk with the most free space: the game and its build take about 35 GB
    $best = Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' | Sort-Object FreeSpace -Descending | Select-Object -First 1
    $root = if ($best) { $best.DeviceID + '\' } else { 'C:\' }
    return (Join-Path $root 'Jeux\WindowSmash')
}

function Clone-Repo([string]$target) {
    New-Item -ItemType Directory -Force (Split-Path $target -Parent) | Out-Null
    Say (L "  Cloning WindowSmash into $target ..." "  Clonage de WindowSmash dans $target ...")
    Log "git clone $WS_GIT_URL $target"
    Run-Native { & $Script:Git clone $WS_GIT_URL $target }
    if ($LASTEXITCODE -ne 0 -or -not (Test-RepoDir $target)) { Set-Step 'Folder' 'FAILED' 'git clone'; Fail 'E13' (L "git clone failed (code $LASTEXITCODE)" "git clone a échoué (code $LASTEXITCODE)") }
    Ok (L 'repository cloned' 'dépôt cloné')
}

function Find-Repo([bool]$allowClone) {
    Title (L 'WindowSmash folder' 'Dossier WindowSmash')
    foreach ($c in @($KitDir, (Split-Path $KitDir -Parent))) {
        if ($c -and (Test-RepoDir $c)) { $Script:Repo = (Resolve-Path -LiteralPath $c).Path; Say (L '  This file is in a WindowSmash folder: using it.' '  Ce fichier est dans un dossier WindowSmash : je l''utilise.'); break }
    }
    if (-not $Script:Repo) { $r = Get-RememberedRepo; if ($r) { $Script:Repo = $r; Say (L "  Previous install found: $r" "  Installation précédente trouvée : $r") } }
    if (-not $Script:Repo) {
        if (-not $allowClone) { Say (L '  WindowSmash is not installed on this PC yet.' '  WindowSmash n''est pas encore installé sur ce PC.'); return $null }
        $def = Get-DefaultInstallDir
        while (-not $Script:Repo) {
            Say (L "  Where to install WindowSmash? About $NEED_GB GB free are needed, outside OneDrive." "  Où installer WindowSmash ? Il faut environ $NEED_GB Go libres, hors OneDrive.")
            $a = Read-Host (L "  Folder [$def] (Enter = OK, B = browse, or type a path)" "  Dossier [$def] (Entrée = OK, P = parcourir, ou tape un chemin)")
            if (-not $a) { $t = $def }
            elseif ($a -match '^[pPbB]$') {
                $f = Pick-Folder (L 'Choose where to install (a WindowSmash folder is made there)' 'Choisis où installer (un dossier WindowSmash y sera créé)')
                if (-not $f) { continue }
                $t = Join-Path $f 'WindowSmash'
            } else { $t = $a.Trim().Trim('"') }
            try { $t = [IO.Path]::GetFullPath($t) } catch { Warn (L "W13 invalid path: $t" "W13 chemin invalide : $t"); continue }
            if ($t -match 'OneDrive') { Warn (L 'W23 not in OneDrive: choose another folder' 'W23 pas dans OneDrive : choisis un autre dossier'); continue }
            if (Test-RepoDir $t) { $Script:Repo = $t; break }          # a WindowSmash folder already there: used as it is
            if ((Test-Path -LiteralPath $t) -and (Get-ChildItem -LiteralPath $t -Force | Select-Object -First 1)) {
                Warn (L "W13 $t already exists and is not empty: choose another folder" "W13 $t existe déjà et n'est pas vide : choisis un autre dossier"); continue
            }
            try { $free = (New-Object IO.DriveInfo ([IO.Path]::GetPathRoot($t))).AvailableFreeSpace / 1GB } catch { Warn (L "W13 no disk found for $t" "W13 disque introuvable pour $t"); continue }
            if ($free -lt $NEED_GB) { Warn ((L "W22 only {0:N0} GB free on {1}: choose another disk" "W22 seulement {0:N0} Go libres sur {1} : choisis un autre disque") -f $free, [IO.Path]::GetPathRoot($t)); continue }
            Clone-Repo $t
            $Script:Repo = $t
        }
    }
    Set-Content -LiteralPath $RepoTxt -Value $Script:Repo -Encoding UTF8
    $Script:Deps = Join-Path $Script:Repo 'dump\_setup'
    $Script:Info['WindowSmash folder'] = $Script:Repo
    Say "  $($Script:Repo)"
    if ($Script:Repo -match 'OneDrive') { Set-Step 'Folder' 'FAILED' 'in OneDrive'; Fail 'E23' (L "the folder is in OneDrive: $($Script:Repo)" "le dossier est dans OneDrive : $($Script:Repo)") }
    if ($Script:Repo -match '[^\x20-\x7E]') { Warn (L "W23 the folder's path holds accents or special characters: if something fails, move it to C:\Games\WindowSmash" "W23 le chemin du dossier contient des accents ou caractères spéciaux : en cas d'erreur, déplace-le vers C:\Jeux\WindowSmash") }
    $drive = (Get-Item -LiteralPath $Script:Repo).PSDrive
    $freeGB = [math]::Round($drive.Free / 1GB, 1)
    $Script:Info['Free disk'] = "$freeGB GB on $($drive.Name):"
    Set-GitSafeRepo
    Set-Step 'Folder' 'OK' $Script:Repo
    return $freeGB
}

# online_server.txt is the one file of the repository a player edits: a lobby code after the address
# (docs/MULTIPLAYER.md), by hand or, since WindowSmash 9c1b250, through the launcher window and the game's settings menu.
# git does not check out a version that changes it over such an edit, and the zip copy would erase it, so the player's
# file is set aside first. On the public lobby the code goes back after the new version's address (its port moved
# once, 39420 -> 39421, and players on two ports do not see each other); anything else (an own server, "off") gets the
# player's file back as it was.
function Get-ServerLine([string]$text) {
    foreach ($l in ($text -split "`n")) { $t = $l.Trim(); if ($t -and -not $t.StartsWith('#')) { return $t } }
    return $null
}

function Save-OnlineServer {
    $p = Join-Path $Script:Repo 'online_server.txt'
    if (Test-Path -LiteralPath $p) { return [IO.File]::ReadAllText($p) }
    return $null
}

function Restore-OnlineServer([string]$mine) {
    $p = Join-Path $Script:Repo 'online_server.txt'
    if (-not $mine -or -not (Test-Path -LiteralPath $p)) { return }
    $new = [IO.File]::ReadAllText($p)
    if ($mine -eq $new) { return }
    if ((Get-ServerLine $mine) -match '^smash\.recomps\.wtf:\d+(\s+(?<code>.+))?$') {
        if (-not $Matches['code']) { return }      # no lobby code: the new version's file as it is
        $re = New-Object Text.RegularExpressions.Regex '(?m)^(?![ \t]*#)([ \t]*[^\s#][^\r\n]*?)[ \t]*(?=\r?$)'
        $text = $re.Replace($new, '$1 ' + $Matches['code'].Replace('$', '$$'), 1)
    } else {
        $text = $mine
    }
    [IO.File]::WriteAllText($p, $text, (New-Object Text.UTF8Encoding $false))
    Say (L "  online_server.txt: your setting is kept ($(Get-ServerLine $text))" "  online_server.txt : ton réglage est gardé ($(Get-ServerLine $text))")
}

function Ensure-Revision {
    Title (L 'WindowSmash version' 'Version de WindowSmash')
    if (-not $Script:Git) { $Script:Git = Find-Git }
    if ($Script:Git -and (Test-Path -LiteralPath (Join-Path $Script:Repo '.git'))) {
        Set-GitSafeRepo
        $out = @(Run-Native { & $Script:Git -C $Script:Repo rev-parse HEAD 2>&1 })
        if ($LASTEXITCODE) { Set-Step 'Version' 'FAILED' 'git'; Fail 'E11' "$(L 'git cannot read the WindowSmash folder' 'git ne peut pas lire le dossier WindowSmash') : $(Get-GitError $out)" }
        $head = "$($out | Select-Object -First 1)".Trim()
        $Script:Info['WindowSmash (git)'] = "$head"
        if ($head -eq $WS_COMMIT) { Ok (L "already the right version ($($WS_COMMIT.Substring(0,7)))" "déjà à la bonne version ($($WS_COMMIT.Substring(0,7)))"); Set-Step 'Version' 'OK' 'git'; return }
        $dirty = @(Run-Native { & $Script:Git -C $Script:Repo status --porcelain --untracked-files=no }) | Where-Object { $_ -notmatch 'online_server\.txt$' }
        if ($dirty) { Set-Step 'Version' 'FAILED' 'files changed'; Fail 'E11' "$(L 'files of the folder were changed (git status)' 'des fichiers du dossier ont été modifiés (git status)') : $(($dirty | Select-Object -First 5) -join ', ')" }
        Say (L "  Moving to version $($WS_COMMIT.Substring(0,7)) (branch $WS_BRANCH)..." "  Passage à la version $($WS_COMMIT.Substring(0,7)) (branche $WS_BRANCH)...")
        $out = @(Run-Native { & $Script:Git -C $Script:Repo fetch origin $WS_BRANCH 2>&1 })
        if ($LASTEXITCODE) { Set-Step 'Version' 'FAILED' 'git fetch'; Fail 'E11' "$(L 'git fetch failed' 'git fetch a échoué') : $(Get-GitError $out)" }
        $mine = Save-OnlineServer
        Run-Native { & $Script:Git -C $Script:Repo checkout -- online_server.txt }   # (an edit there would block the checkout)
        $out = @(Run-Native { & $Script:Git -C $Script:Repo -c advice.detachedHead=false checkout --detach $WS_COMMIT 2>&1 })
        $rc = $LASTEXITCODE
        Restore-OnlineServer $mine
        if ($rc) { Set-Step 'Version' 'FAILED' 'git checkout'; Fail 'E11' "git checkout $WS_COMMIT $(L 'failed' 'a échoué') : $(Get-GitError $out)" }
        $Script:Info['WindowSmash (git)'] = "$WS_COMMIT (was $head)"
        Ok (L 'version updated' 'version mise à jour'); Set-Step 'Version' 'OK' 'git checkout'; return
    }
    $bad = @()
    foreach ($f in $WS_FILES.Keys) {
        $p = Join-Path $Script:Repo $f
        if (-not (Test-Path -LiteralPath $p) -or (Get-NormalizedSha256 $p) -ne $WS_FILES[$f]) { $bad += $f }
    }
    if (-not $bad) { Ok (L 'files at the right version' 'fichiers à la bonne version'); Set-Step 'Version' 'OK' 'files checked'; $Script:Info['WindowSmash'] = "copy without git, = $($WS_COMMIT.Substring(0,7))"; return }
    Say (L "  Not the right version ($($bad -join ', ')): updating the files..." "  Pas la bonne version ($($bad -join ', ')) : je mets les fichiers à jour...")
    $mine = Save-OnlineServer
    Get-RepoZip $Script:Repo
    Restore-OnlineServer $mine
    foreach ($f in $WS_FILES.Keys) {
        if ((Get-NormalizedSha256 (Join-Path $Script:Repo $f)) -ne $WS_FILES[$f]) { Set-Step 'Version' 'FAILED' $f; Fail 'E11' (L "$f is not the right version even after the update" "$f n'a pas la bonne version même après mise à jour") }
    }
    $Script:Info['WindowSmash'] = "copy without git, updated to $($WS_COMMIT.Substring(0,7))"
    Ok (L 'files updated' 'fichiers mis à jour'); Set-Step 'Version' 'OK' 'archive'
}

# ---- Python ---------------------------------------------------------------------------------
function Find-Python {
    $cands = New-Object System.Collections.ArrayList
    if (Get-Command py -ErrorAction SilentlyContinue) { [void]$cands.Add(@('py', '-3.14')) }
    foreach ($p in @("$env:LOCALAPPDATA\Programs\Python\Python314\python.exe", "$env:LOCALAPPDATA\Python\pythoncore-3.14-64\python.exe",
                     "$env:ProgramFiles\Python314\python.exe")) { if (Test-Path -LiteralPath $p) { [void]$cands.Add(@($p)) } }
    $pc = Get-Command python -ErrorAction SilentlyContinue -All
    foreach ($c in $pc) { [void]$cands.Add(@($c.Source)) }
    foreach ($c in $cands) {
        $exe = $c[0]; $pre = @($c | Select-Object -Skip 1)
        $r = Run-Native { & $exe @pre -c "import sys, compression.zstd; print(sys.executable)" 2>$null }
        if ($LASTEXITCODE -eq 0 -and $r) { return ($r | Select-Object -Last 1).Trim() }
    }
    return $null
}

function Ensure-Python {
    Title 'Python 3.14'
    $py = Find-Python
    if (-not $py) {
        Say (L '  Python 3.14 is needed (for the WindowSmash tools) and is not installed.' '  Python 3.14 est nécessaire (pour les outils de WindowSmash) et n''est pas installé.')
        if (-not (Ask-YesNo (L '  Install it now?' '  Je l''installe maintenant ?') -Install)) { Set-Step 'Python' 'FAILED' 'refused'; Fail 'E30' (L 'Python install refused' 'installation de Python refusée') }
        $wg = Get-Command winget -ErrorAction SilentlyContinue
        if ($wg) {
            Say (L '  Installing with winget...' '  Installation par winget...')
            $rc = Run-Logged $wg.Source @('install', '-e', '--id', 'Python.Python.3.14', '--scope', 'user', '--silent', '--accept-package-agreements', '--accept-source-agreements') 'winget-python'
            Log "winget python exit $rc"
            $py = Find-Python
        }
        if (-not $py) {
            $inst = Join-Path $HomeDir 'downloads\python-3.14.8-amd64.exe'
            Download $PY_URL $inst $PY_SHA 'Python 3.14.8' 'E30'
            $sig = Get-AuthenticodeSignature -LiteralPath $inst
            if ($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch 'Python Software Foundation') { Fail 'E30' (L "the Python installer's signature is not valid ($($sig.Status))" "signature de l'installateur Python invalide ($($sig.Status))") }
            Say (L '  Installing Python 3.14.8 (a minute)...' '  Installation de Python 3.14.8 (une minute)...')
            $rc = Run-Installer $inst @('/quiet', 'InstallAllUsers=0', 'PrependPath=1', 'Include_launcher=1', 'Include_test=0', 'Include_doc=0') 'python-install'
            if ($rc -ne 0) { Set-Step 'Python' 'FAILED' "installer $rc"; Fail 'E30' (L "the Python installer failed (code $rc)" "l'installateur Python a échoué (code $rc)") }
            $py = Find-Python
        }
        if (-not $py) { Set-Step 'Python' 'FAILED' 'not found after the install'; Fail 'E30' (L 'Python 3.14 not found after the install' 'Python 3.14 introuvable après installation') }
    }
    $Script:SysPy = $py
    $Script:Info['Python'] = $py
    Ok "Python : $py"
    $venv = Join-Path $Script:Repo '.venv'
    $Script:VenvPy = Join-Path $venv 'Scripts\python.exe'
    if (-not (Test-Path -LiteralPath $Script:VenvPy)) {
        Say (L '  Making the folder''s Python environment (.venv)...' '  Création de l''environnement Python du dossier (.venv)...')
        $rc = Run-Logged $py @('-m', 'venv', $venv) 'venv'
        if ($rc -ne 0) { Set-Step 'Python' 'FAILED' 'venv'; Fail 'E31' (L "python -m venv failed (code $rc)" "python -m venv a échoué (code $rc)") }
    }
    $probe = Invoke-Helper @('probe')
    if (-not $probe.Json -or -not $probe.Json.cryptodome) {
        Say (L '  Installing pycryptodomex (pip)...' '  Installation de pycryptodomex (pip)...')
        $rc = Run-Logged $Script:VenvPy @('-m', 'pip', 'install', '--disable-pip-version-check', '-r', (Join-Path $Script:Repo 'requirements.txt')) 'pip'
        if ($rc -ne 0) { Set-Step 'Python' 'FAILED' 'pip'; Fail 'E31' (L "pip install failed (code $rc)" "pip install a échoué (code $rc)") }
        $probe = Helper-OrFail @('probe') 'E31'
        if (-not $probe.Json.cryptodome) { Set-Step 'Python' 'FAILED' 'pycryptodomex'; Fail 'E31' (L 'pycryptodomex missing after pip install' 'pycryptodomex absent après pip install') }
    }
    $Script:Info['Folder Python'] = "$($probe.Json.python), pycryptodomex $($probe.Json.cryptodome)"
    Ok (L 'Python environment ready' 'environnement Python prêt')
    Set-Step 'Python' 'OK' $probe.Json.python
}

# ---- Visual Studio Build Tools ----------------------------------------------------------------
function Get-VS {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (-not (Test-Path -LiteralPath $vswhere)) { return $null }
    $j = Run-Native { & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -format json 2>$null }
    try { $vs = ($j -join "`n") | ConvertFrom-Json } catch { return $null }
    if (-not $vs) { return $null }
    return @($vs)[0]
}

function Get-SdkLib {
    $kits = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\Lib'
    if (-not (Test-Path -LiteralPath $kits)) { return $null }
    return Get-ChildItem -LiteralPath $kits -Directory | Sort-Object Name -Descending | Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'um\x64\d3d11.lib') } | Select-Object -First 1
}

function Ensure-VS {
    Title (L 'Microsoft build tools (Build Tools)' 'Outils de compilation Microsoft (Build Tools)')
    $vs = Get-VS; $sdk = Get-SdkLib
    if (-not $vs -or -not $sdk) {
        Say (L '  Visual Studio''s "Build Tools" are needed (C++ compiler and Windows SDK): about 3 to 6 GB,' '  Il faut les "Build Tools" de Visual Studio (compilateur C++ et SDK Windows) : environ 3 à 6 Go,')
        Say (L '  10 to 30 minutes. An administrator window (UAC) will open: accept it.' '  10 à 30 minutes. Une fenêtre administrateur (UAC) va s''ouvrir : accepte-la.')
        if (-not (Ask-YesNo (L '  Install them now?' '  Je les installe maintenant ?') -Install)) { Set-Step 'Build Tools' 'FAILED' 'refused'; Fail 'E32' (L 'Build Tools install refused' 'installation des Build Tools refusée') }
        $boot = Join-Path $HomeDir 'downloads\vs_BuildTools.exe'
        Remove-Item -LiteralPath $boot -Force -ErrorAction SilentlyContinue
        Download $VS_URL $boot '' 'Visual Studio Build Tools (installer)' 'E32'
        $sig = Get-AuthenticodeSignature -LiteralPath $boot
        if ($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch 'Microsoft') { Fail 'E32' (L "the Microsoft installer's signature is not valid ($($sig.Status))" "signature de l'installateur Microsoft invalide ($($sig.Status))") }
        Say (L '  Installing (a Microsoft progress window shows)...' '  Installation en cours (une fenêtre de progression Microsoft s''affiche)...')
        $rc = Run-Installer $boot @('--passive', '--wait', '--norestart', '--nocache', '--add', 'Microsoft.VisualStudio.Workload.VCTools', '--includeRecommended') 'vs-buildtools'
        Log "vs_BuildTools exit $rc"
        if ($rc -eq 1602 -or $rc -eq 5007) { Set-Step 'Build Tools' 'FAILED' "cancelled ($rc)"; Fail 'E32' (L "install cancelled (code $rc): the administrator window must be accepted" "installation annulée (code $rc) : il faut accepter la fenêtre administrateur") }
        if ($rc -ne 0 -and $rc -ne 3010) { Set-Step 'Build Tools' 'FAILED' "code $rc"; Fail 'E32' (L "the Build Tools installer failed (code $rc)" "l'installateur des Build Tools a échoué (code $rc)") }
        if ($rc -eq 3010) { Warn (L 'W32 Windows asks for a restart after the Build Tools (not needed to go on)' 'W32 Windows demande un redémarrage après les Build Tools (pas obligatoire pour continuer)') }
        $vs = Get-VS; $sdk = Get-SdkLib
    }
    if (-not $vs) { Set-Step 'Build Tools' 'FAILED' 'no MSVC'; Fail 'E33' (L 'C++ compiler (MSVC x64) not found' 'compilateur C++ (MSVC x64) introuvable') }
    if (-not $sdk) { Set-Step 'Build Tools' 'FAILED' 'no SDK'; Fail 'E33' (L 'Windows SDK (d3d11.lib) not found' 'SDK Windows (d3d11.lib) introuvable') }
    $Script:VS = $vs
    $Script:Info['Visual Studio'] = "$($vs.displayName) $($vs.installationVersion) - $($vs.installationPath)"
    $Script:Info['Windows SDK'] = $sdk.Name
    $cmake = Join-Path $vs.installationPath 'Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe'
    $Script:CMake = if (Test-Path -LiteralPath $cmake) { $cmake } else { $null }
    $Script:Info['CMake'] = if ($Script:CMake) { $Script:CMake } else { 'missing (no music)' }
    Ok "$($vs.displayName) $($vs.installationVersion), SDK $($sdk.Name)"
    Set-Step 'Build Tools' 'OK' $vs.installationVersion
}

# ---- LLVM (clang-cl, the compiler the host's build used) ---------------------------------------
function Ensure-LLVM {
    Title (L "LLVM compiler $LLVM_VER" "Compilateur LLVM $LLVM_VER")
    $dir = Join-Path $Script:Deps "llvm-$LLVM_VER"
    $clang = Join-Path $dir 'bin\clang-cl.exe'
    $ver = if (Test-Path -LiteralPath $clang) { (Run-Native { & $clang --version 2>$null }) | Select-Object -First 1 } else { '' }
    if ($ver -notmatch [regex]::Escape($LLVM_VER)) {
        $arch = Join-Path $Script:Deps "downloads\clang+llvm-$LLVM_VER-x86_64-pc-windows-msvc.tar.xz"
        Download $LLVM_URL $arch $LLVM_SHA "LLVM $LLVM_VER (900 MB)" 'E34'
        Say (L '  Unpacking (a few minutes)...' '  Décompression (quelques minutes)...')
        if (Test-Path -LiteralPath $dir) { Remove-Item -LiteralPath $dir -Recurse -Force }
        New-Item -ItemType Directory -Force $dir | Out-Null
        $rc = Run-Logged (Join-Path $env:SystemRoot 'System32\tar.exe') @('-xf', $arch, '-C', $dir, '--strip-components', '1') 'llvm-extract'
        if ($rc -ne 0 -or -not (Test-Path -LiteralPath $clang)) { Set-Step 'LLVM' 'FAILED' "tar $rc"; Fail 'E34' (L "unpacking LLVM failed (tar $rc)" "décompression de LLVM impossible (tar $rc)") }
        $ver = (Run-Native { & $clang --version 2>$null }) | Select-Object -First 1
    }
    $Script:Clang = $clang
    $Script:Info['clang-cl'] = "$ver"
    Ok "$ver"
    Set-Step 'LLVM' 'OK' $LLVM_VER
}

function Test-Toolchain {
    Title (L 'Testing the compiler and the processor' 'Test du compilateur et du processeur')
    $t = Join-Path $LogDir 'toolchain-test'
    New-Item -ItemType Directory -Force $t | Out-Null
    $src = Join-Path $t 'test.c'
    @'
#include <windows.h>
#include <d3d11.h>
#include <immintrin.h>
#include <stdio.h>
int main(void) {
    __m256 r = _mm256_fmadd_ps(_mm256_set1_ps(1.5f), _mm256_set1_ps(2.0f), _mm256_set1_ps(0.25f));   /* FMA */
    __m256i i = _mm256_add_epi32(_mm256_set1_epi32(1), _mm256_set1_epi32(2));                          /* AVX2 */
    unsigned short h = _cvtss_sh(3.25f, 0);                                                            /* F16C */
    float f[8]; int n[8]; D3D_FEATURE_LEVEL level = 0;
    _mm256_storeu_ps(f, r); _mm256_storeu_si256((__m256i *)n, i);
    HRESULT hr = D3D11CreateDevice(NULL, D3D_DRIVER_TYPE_HARDWARE, NULL, 0, NULL, 0, D3D11_SDK_VERSION, NULL, &level, NULL);
    printf("cpu %g %d %#x d3d11 hr=%#lx level=%#x\n", f[0], n[0], h, (unsigned long)hr, (unsigned)level);
    return (f[0] == 3.25f && n[0] == 3 && h == 0x4280) ? (SUCCEEDED(hr) ? 0 : 3) : 2;
}
'@ | Set-Content -LiteralPath $src -Encoding ASCII
    $exe = Join-Path $t 'test.exe'
    $rc = Run-Logged $Script:Clang @('/nologo', '/O2', '/arch:AVX2', '-mfma', '-mf16c', '-fuse-ld=lld', $src, "/Fe$exe", '/link', 'd3d11.lib') 'toolchain-compile'
    if ($rc -ne 0 -or -not (Test-Path -LiteralPath $exe)) { Set-Step 'Compiler test' 'FAILED' "clang-cl $rc"; Fail 'E35' (L "the test program does not compile (clang-cl $rc)" "le programme de test ne compile pas (clang-cl $rc)") }
    $rc = Run-Logged $exe @() 'toolchain-run'
    $outText = (Get-Content -LiteralPath (Join-Path $LogDir 'toolchain-run.out.txt') -ErrorAction SilentlyContinue) -join ' '
    $Script:Info['Test CPU/D3D11'] = "code $rc : $outText"
    if ($rc -eq -1073741795 -or $rc -eq 3221225501) { Set-Step 'Compiler test' 'FAILED' 'illegal instruction'; Fail 'E21' (L 'the processor cannot run AVX2/FMA/F16C' 'le processeur ne sait pas exécuter AVX2/FMA/F16C') }
    if ($rc -eq 2) { Set-Step 'Compiler test' 'FAILED' 'wrong result'; Fail 'E35' (L "wrong results in the AVX2/FMA/F16C test: $outText" "résultats faux au test AVX2/FMA/F16C : $outText") }
    if ($rc -eq 3) { Warn (L "W70 hardware Direct3D 11 unavailable ($outText): update the graphics card driver" "W70 Direct3D 11 matériel indisponible ($outText) : mets à jour le pilote de la carte graphique") }
    elseif ($rc -ne 0) { Set-Step 'Compiler test' 'FAILED' "code $rc"; Fail 'E35' (L "the test program stopped (code $rc): $outText" "le programme de test s'est arrêté (code $rc) : $outText") }
    Ok (L "compiler OK, processor AVX2/FMA/F16C OK, Direct3D 11 OK" "compilateur OK, processeur AVX2/FMA/F16C OK, Direct3D 11 OK")
    Set-Step 'Compiler test' 'OK'
}

# ---- the game files ---------------------------------------------------------------------------
function Load-Inputs { if (Test-Path -LiteralPath $InputsJs) { try { return (Get-Content -LiteralPath $InputsJs -Raw | ConvertFrom-Json) } catch {} }; return $null }
function Save-Inputs { $Script:Inputs | ConvertTo-Json | Set-Content -LiteralPath $InputsJs -Encoding UTF8 }

function Ask-Inputs {
    Title (L 'Game files (yours, dumped from your console)' 'Fichiers du jeu (les tiens, dumpés de ta console)')
    $prev = Load-Inputs
    $have = { param($p) $p -and (Test-Path -LiteralPath $p) }
    if ($prev -and (& $have $prev.base) -and (& $have $prev.prodkeys)) {
        # (an update checked as the version needed now is reused; kit 2.x's 13.0.4 one is not: the new one is asked)
        $upd = if ((& $have $prev.update) -and $prev.update_version -eq $EXPECT_VERSION) { $prev.update } else { $null }
        Say (L "  Files chosen last time:" "  Fichiers choisis la dernière fois :")
        Say "    $(L 'base game  ' 'jeu de base') : $($prev.base)"
        if ($upd) { Say "    $(L 'update     ' 'mise à jour') : $upd" }
        Say "    prod.keys   : $($prev.prodkeys)"
        if ($prev.dlc) { Say "    DLC         : $($prev.dlc)" }
        if (Ask-YesNo (L '  Use them again?' '  Je les réutilise ?')) {
            $Script:Inputs = @{ base = $prev.base; update = $upd; prodkeys = $prev.prodkeys; titlekeys = $prev.titlekeys; dlc = $prev.dlc; firmware = $prev.firmware; update_version = $prev.update_version }
            if (-not $upd) {
                Say (L "  WindowSmash now needs the game's $EXPECT_VERSION update (dumped from your up-to-date Switch)." "  WindowSmash demande maintenant la mise à jour $EXPECT_VERSION du jeu (dumpée de ta Switch à jour).")
                $u = Pick-File (L "Choose Smash Ultimate's $EXPECT_VERSION UPDATE (.nsp)" "Choisis la MISE À JOUR $EXPECT_VERSION de Smash Ultimate (.nsp)") (L 'Update (*.nsp)|*.nsp|All files|*.*' 'Mise à jour (*.nsp)|*.nsp|Tous les fichiers|*.*') $prev.base
                if (-not $u) { Fail 'E40' (L "$EXPECT_VERSION update not chosen" "mise à jour $EXPECT_VERSION non choisie") }
                $Script:Inputs.update = $u; $Script:Inputs.update_version = $null
                Save-Inputs
            }
            return
        }
    }
    $Script:Inputs = @{}
    $k = Pick-File (L '1/3 - Choose your prod.keys file' '1/3 - Choisis ton fichier prod.keys') (L 'Keys (prod.keys)|prod.keys;*.keys|All files|*.*' 'Clés (prod.keys)|prod.keys;*.keys|Tous les fichiers|*.*') ''
    if (-not $k) { Fail 'E40' (L 'prod.keys not chosen' 'prod.keys non choisi') }
    $Script:Inputs.prodkeys = $k
    $b = Pick-File (L '2/3 - Choose the Smash Ultimate BASE GAME (version 1.0.0, .xci or .nsp)' '2/3 - Choisis le JEU DE BASE de Smash Ultimate (version 1.0.0, .xci ou .nsp)') (L 'Switch game (*.xci;*.nsp)|*.xci;*.nsp|All files|*.*' 'Jeu Switch (*.xci;*.nsp)|*.xci;*.nsp|Tous les fichiers|*.*') $k
    if (-not $b) { Fail 'E40' (L 'base game not chosen' 'jeu de base non choisi') }
    $Script:Inputs.base = $b
    $u = Pick-File (L "3/3 - Choose Smash Ultimate's $EXPECT_VERSION UPDATE (.nsp)" "3/3 - Choisis la MISE À JOUR $EXPECT_VERSION de Smash Ultimate (.nsp)") (L 'Update (*.nsp)|*.nsp|All files|*.*' 'Mise à jour (*.nsp)|*.nsp|Tous les fichiers|*.*') $b
    if (-not $u) { Fail 'E40' (L 'update not chosen' 'mise à jour non choisie') }
    $Script:Inputs.update = $u
    if (Ask-YesNo (L '  Do you also have a title.keys (only if you were asked for one)?' '  As-tu aussi un title.keys (seulement si on te l''a demandé) ?') $false) {
        $t = Pick-File (L 'Choose title.keys' 'Choisis title.keys') (L 'title.keys|*.keys;*.txt|All files|*.*' 'title.keys|*.keys;*.txt|Tous les fichiers|*.*') $k
        if ($t) { $Script:Inputs.titlekeys = $t }
    }
    if (Ask-YesNo (L '  Do you have DLC (fighters) as .nsp files in a folder? (optional; for netplay, have the same ones)' '  As-tu des DLC (combattants) en .nsp dans un dossier ? (optionnel ; pour le netplay, ayez les mêmes)') $false) {
        $d = Pick-Folder (L 'Choose the folder that holds the DLC (.nsp)' 'Choisis le dossier qui contient les DLC (.nsp)')
        if ($d) { $Script:Inputs.dlc = $d }
    }
    Save-Inputs
}

function Check-Inputs {
    Title (L 'Checking the files' 'Vérification des fichiers')
    $keys = Join-Path $Script:Repo 'keys'
    New-Item -ItemType Directory -Force $keys | Out-Null
    Copy-Item -LiteralPath $Script:Inputs.prodkeys -Destination (Join-Path $keys 'prod.keys') -Force
    if ($Script:Inputs.titlekeys) { Copy-Item -LiteralPath $Script:Inputs.titlekeys -Destination (Join-Path $keys 'title.keys') -Force }
    $Script:Keys = $keys
    $r = Helper-OrFail @('keys', '--keys', $keys) 'E41'
    $Script:Info['prod.keys'] = "{0} keys, generations key_area 0..{1}, titlekek 0..{2}" -f $r.Json.count, (($r.Json.kak_application | Measure-Object -Maximum).Maximum), (($r.Json.titlekek | Measure-Object -Maximum).Maximum)
    Ok (L "prod.keys: $($r.Json.count) keys" "prod.keys : $($r.Json.count) clés")
    $b = Helper-OrFail @('identify', $Script:Inputs.base, '--keys', $keys, '--role', 'base') 'E42'
    $Script:Base = $b.Json
    $Script:Info['Base game'] = "{0} ({1:N1} GB): {2} title {3} version {4}" -f (Split-Path $Script:Inputs.base -Leaf), ((Get-Item -LiteralPath $Script:Inputs.base).Length / 1GB), $b.Json.kind, $b.Json.program, $b.Json.display
    Ok "$(L 'base game' 'jeu de base') : $($b.Json.kind.ToUpper()) version $($b.Json.display)"
    $u = Helper-OrFail @('identify', $Script:Inputs.update, '--keys', $keys, '--role', 'update', '--expect', $EXPECT_VERSION) 'E43'
    $Script:Info['Update'] = "{0} ({1:N1} GB): version {2} (v{3})" -f (Split-Path $Script:Inputs.update -Leaf), ((Get-Item -LiteralPath $Script:Inputs.update).Length / 1GB), $u.Json.display, $u.Json.title_version
    if ($u.Json.display -ne $EXPECT_VERSION) {   # (WindowSmash builds and plays this version only)
        Set-Step 'Files' 'FAILED' "update $($u.Json.display)"
        Fail 'E43' (L "update $($u.Json.display): WindowSmash needs $EXPECT_VERSION" "mise à jour $($u.Json.display) : WindowSmash demande la $EXPECT_VERSION")
    }
    Ok "$(L 'update' 'mise à jour') : version $($u.Json.display)"
    $Script:Inputs.update_version = $u.Json.display; Save-Inputs
    # space: the decrypted base (unless it is there already), the update's data (~4 GB), the build (~10 GB)
    $free = (Get-Item -LiteralPath $Script:Repo).PSDrive.Free
    $need = 16GB + $(if (Test-PlainBase) { 0 } else { [int64]$b.Json.program_size })
    if ($free -lt $need -and -not (Test-Path -LiteralPath (Join-Path $Script:Repo 'build\ssbu.exe'))) {
        $hint = if (Test-Path -LiteralPath (Join-Path $Script:Repo $OLD_TREE)) { L " (the old $OLD_TREE folder can be deleted: copy its save folder first)" " (l'ancien dossier $OLD_TREE peut être supprimé : copie d'abord son dossier save)" } else { '' }
        Set-Step 'Files' 'FAILED' 'disk'; Fail 'E22' ((L "{0:N0} GB free are needed, there are {1:N0}{2}" "il faut {0:N0} Go libres, il y en a {1:N0}{2}") -f ($need / 1GB), ($free / 1GB), $hint)
    }
    Set-Step 'Files' 'OK' "$($b.Json.kind) $($b.Json.display) + update $($u.Json.display)"
}

function Prepare-Base {
    Title (L 'Decrypted copy of the base game (about 15 GB, 5 to 15 minutes)' 'Copie déchiffrée du jeu de base (environ 15 Go, 5 à 15 minutes)')
    # (where the game reads it: dump\game_files, also on a disk without hard links; kit 3.0/3.1's dump\base copy is kept)
    $out = Join-Path $Script:Repo 'dump\base\program_v0.nca'
    if (-not (Test-Path -LiteralPath $out)) { $out = Join-Path $Script:Repo 'dump\game_files\program_v0.nca' }
    Helper-OrFail @('plain-nca', $Script:Inputs.base, $out, '--keys', $Script:Keys) 'E50' -Live -name 'plain-nca' | Out-Null
    Ok (L 'base game ready (WindowSmash reads it in place: no second copy)' 'jeu de base prêt (WindowSmash le lit sur place : pas de seconde copie)')
    Set-Step 'Base game' 'OK'
}

function Prepare-Fonts {
    Title (L 'Firmware fonts' 'Polices du firmware')
    $fonts = Join-Path $Script:Repo 'dump\fonts'
    $need = @('nintendo_udsg-r_std_003.bfttf', 'nintendo_udsg-r_org_zh-cn_003.bfttf', 'nintendo_udsg-r_ext_zh-cn_003.bfttf',
              'nintendo_udjxh-db_zh-tw_003.bfttf', 'nintendo_udsg-r_ko_003.bfttf', 'nintendo_ext_003.bfttf')
    $missing = { @($need | Where-Object { -not (Test-Path -LiteralPath (Join-Path $fonts $_)) }) }
    if (-not (& $missing).Count) { Ok (L 'fonts already there' 'polices déjà là'); Set-Step 'Fonts' 'OK' 'already there'; return }
    if ($Script:Base.kind -eq 'xci' -and $Script:Base.xci_update_partition) {
        $r = Invoke-Helper @('fonts', $Script:Inputs.base, $fonts, '--keys', $Script:Keys) -Live -name 'fonts-xci'
        if ($r.Code -eq 0) { Ok (L 'fonts taken from the XCI' 'polices extraites du XCI'); Set-Step 'Fonts' 'OK' 'XCI'; return }
        Warn (L 'W45 no fonts in the XCI: the firmware folder is needed' 'W45 pas de polices dans le XCI : il faut le dossier du firmware')
    }
    $suggest = @("$env:APPDATA\Ryujinx\bis\system\Contents\registered", "$env:APPDATA\yuzu\nand\system\Contents\registered",
                 "$env:APPDATA\suyu\nand\system\Contents\registered", "$env:APPDATA\sudachi\nand\system\Contents\registered",
                 "$env:APPDATA\citron\nand\system\Contents\registered", "$env:APPDATA\eden\nand\system\Contents\registered") |
               Where-Object { Test-Path -LiteralPath $_ }
    $src = $Script:Inputs.firmware
    if (-not ($src -and (Test-Path -LiteralPath $src))) {
        if ($suggest) {
            Say (L "  Emulator firmware found: $($suggest[0])" "  Firmware d'émulateur trouvé : $($suggest[0])")
            if (Ask-YesNo (L '  Take the fonts from it?' '  Je prends les polices dedans ?')) { $src = $suggest[0] }
        }
        if (-not $src) { $src = Pick-Folder (L 'Choose your console''s FIRMWARE folder (.nca files: a firmware dump, or an emulator''s registered folder)' 'Choisis le dossier du FIRMWARE de ta console (fichiers .nca : dump du firmware, ou dossier registered d''un émulateur)') }
        if (-not $src) { Set-Step 'Fonts' 'FAILED' 'no firmware'; Fail 'E45' (L 'firmware folder not chosen' 'dossier du firmware non choisi') }
        $Script:Inputs.firmware = $src; Save-Inputs
    }
    Helper-OrFail @('fonts', $src, $fonts, '--keys', $Script:Keys) 'E45' -Live -name 'fonts-firmware' | Out-Null
    Ok (L 'fonts taken from the firmware' 'polices extraites du firmware')
    Set-Step 'Fonts' 'OK' 'firmware'
}

# ---- libopus (music): best effort -------------------------------------------------------------
function Ensure-Opus {
    Title (L 'Opus audio library (music)' 'Bibliothèque audio Opus (musique)')
    $lib = Join-Path $Script:Deps 'opus\lib\opus.lib'
    if (Test-Path -LiteralPath $lib) { $env:SSBU_OPUS_LIBS = $lib; Ok (L 'already built' 'déjà compilée'); Set-Step 'Opus' 'OK' 'already there'; return }
    if (-not $Script:CMake) { Warn (L 'W80 no CMake: the game will have no music' 'W80 CMake absent : le jeu sera sans musique'); Set-Step 'Opus' 'SKIPPED' 'no CMake'; return }
    try {
        $arch = Join-Path $Script:Deps 'downloads\opus-1.5.2.tar.gz'
        Download $OPUS_URL $arch $OPUS_SHA 'Opus 1.5.2' 'W80'
        $src = Join-Path $Script:Deps 'src'
        New-Item -ItemType Directory -Force $src | Out-Null
        if ((Run-Logged (Join-Path $env:SystemRoot 'System32\tar.exe') @('-xzf', $arch, '-C', $src) 'opus-extract') -ne 0) { throw 'tar' }
        $major = [int]($Script:VS.installationVersion.Split('.')[0])
        $gen = @{ 16 = 'Visual Studio 16 2019'; 17 = 'Visual Studio 17 2022'; 18 = 'Visual Studio 18 2026' }[$major]
        if (-not $gen) { throw "unknown Visual Studio version $major" }
        $bld = Join-Path $Script:Deps 'src\opus-build'
        $rc = Run-Logged $Script:CMake @('-S', (Join-Path $src 'opus-1.5.2'), '-B', $bld, '-G', $gen, '-A', 'x64', '-DCMAKE_POLICY_DEFAULT_CMP0091=NEW',
            '-DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded', '-DBUILD_SHARED_LIBS=OFF', '-DOPUS_BUILD_PROGRAMS=OFF', '-DOPUS_BUILD_TESTING=OFF',
            '-DBUILD_TESTING=OFF', "-DCMAKE_INSTALL_PREFIX=$(Join-Path $Script:Deps 'opus')") 'opus-configure'
        if ($rc -ne 0) { throw "cmake configure $rc" }
        if ((Run-Logged $Script:CMake @('--build', $bld, '--config', 'Release', '--parallel', '4') 'opus-build') -ne 0) { throw 'cmake build' }
        if ((Run-Logged $Script:CMake @('--install', $bld, '--config', 'Release') 'opus-install') -ne 0) { throw 'cmake install' }
        if (-not (Test-Path -LiteralPath $lib)) { throw 'no opus.lib' }
        $env:SSBU_OPUS_LIBS = $lib
        Ok (L 'Opus built' 'Opus compilée')
        Set-Step 'Opus' 'OK'
    } catch {
        Warn (L "W80 Opus not built ($($_.Exception.Message)): the game will have no music" "W80 Opus non compilée ($($_.Exception.Message)) : le jeu sera sans musique")
        Set-Step 'Opus' 'SKIPPED' "$($_.Exception.Message)"
    }
}

# ---- SDL3 (pads other than Xbox): best effort -------------------------------------------------
function Ensure-SDL3 {
    Title (L 'Controller library (SDL3)' 'Bibliothèque des manettes (SDL3)')
    $dst = Join-Path $Script:Repo 'deps\SDL3'
    if (Test-Path -LiteralPath (Join-Path $dst 'include\SDL3\SDL_gamepad.h')) { Ok (L 'already there' 'déjà là'); Set-Step 'SDL3' 'OK' 'already there'; return }
    try {
        $zip = Join-Path $Script:Deps 'downloads\SDL3-devel-3.4.18-VC.zip'
        Download $SDL3_URL $zip $SDL3_SHA 'SDL3 3.4.18' 'W81'
        $tmp = Join-Path $Script:Deps "sdl3-$Stamp"
        Expand-Archive -LiteralPath $zip -DestinationPath $tmp -Force
        $src = Get-ChildItem -LiteralPath $tmp -Directory | Select-Object -First 1
        New-Item -ItemType Directory -Force (Split-Path $dst -Parent) | Out-Null
        if (Test-Path -LiteralPath $dst) { Remove-Item -LiteralPath $dst -Recurse -Force }
        Move-Item -LiteralPath $src.FullName -Destination $dst
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
        if (-not (Test-Path -LiteralPath (Join-Path $dst 'lib\x64\SDL3.dll'))) { throw 'no SDL3.dll' }
        Ok (L 'SDL3 ready (PlayStation, Switch Pro controllers and more)' 'SDL3 prête (manettes PlayStation, Switch Pro, etc.)')
        Set-Step 'SDL3' 'OK'
    } catch {
        Warn (L "W81 SDL3 not installed ($($_.Exception.Message)): only Xbox controllers will work" "W81 SDL3 non installée ($($_.Exception.Message)) : seules les manettes Xbox marcheront")
        Set-Step 'SDL3' 'SKIPPED' "$($_.Exception.Message)"
    }
}

# ---- the build ----------------------------------------------------------------------------------
function Build-Game([string]$Label = (L "$EXPECT_VERSION update and compile of the game (1 to 3 hours depending on the PC)" "Mise à jour $EXPECT_VERSION et compilation du jeu (1 à 3 heures selon le PC)")) {
    Title $Label
    $os = Get-CimInstance Win32_OperatingSystem
    $ram = (Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB
    $cpu = (Get-CimInstance Win32_Processor | Measure-Object NumberOfLogicalProcessors -Sum).Sum
    $jobs = [int][math]::Max(1, [math]::Min($cpu, [math]::Floor(($ram - 4) / 1.5)))
    $freeVirt = [math]::Round($os.FreeVirtualMemory / 1MB, 1)
    if ($freeVirt -lt 8) { Warn (L "W60 only $freeVirt GB of free memory: close games and browsers during the compile" "W60 seulement $freeVirt Go de mémoire libre : ferme les jeux et navigateurs pendant la compilation") }
    Say (L '  Leave the PC on. If it stops, start WindowSmash Launcher again: it carries on where it was.' '  Laisse le PC allumé. Tu peux relancer WindowSmash Launcher si ça s''arrête : ça reprend où ça en était.')
    $env:SSBU_CLANG = $Script:Clang
    $Script:Info['Compilation'] = "jobs $jobs, SSBU_OPUS_LIBS=$([bool]$env:SSBU_OPUS_LIBS)"
    $hargs = @('install', '--update', $Script:Inputs.update, '--keys', $Script:Keys)
    if ($Script:Inputs.dlc) { $hargs += @('--dlc', $Script:Inputs.dlc) }
    if ($env:WS_NO_BUILD) { $hargs += '--no-build'; Warn 'W99 test: compile skipped (WS_NO_BUILD)' }   # (tests only)
    $attempt = 0
    while ($true) {
        $attempt++
        Say (L "  Attempt $attempt with $jobs job(s) at a time..." "  Tentative $attempt avec $jobs tâche(s) en parallèle...")
        $r = Invoke-Helper ($hargs + @('--jobs', "$jobs")) -Live -name "install-$attempt"
        if ($r.Code -eq 0) { break }
        if ($r.Code -eq 3 -and $jobs -gt 1) {
            $jobs = [int][math]::Max(1, [math]::Floor($jobs / 2))
            Warn (L "W61 out of memory during the compile: trying again with $jobs job(s)" "W61 mémoire insuffisante pendant la compilation : nouvel essai avec $jobs tâche(s)")
            $Script:Info['Compilation'] = "jobs cut to $jobs after running out of memory"
            continue
        }
        $c = if ($r.ErrCode) { $r.ErrCode } else { 'E60' }
        $t = if ($r.ErrText) { $r.ErrText } else { L "stopped (code $($r.Code))" "arrêt (code $($r.Code))" }
        Set-Step 'Compilation' 'FAILED' "$c"
        Fail $c $t
    }
    $exe = Join-Path $Script:Repo 'build\ssbu.exe'
    if ($env:WS_NO_BUILD) { Set-Step 'Compilation' 'TEST' 'skipped (WS_NO_BUILD)'; return }
    if (-not (Test-Path -LiteralPath $exe)) { Set-Step 'Compilation' 'FAILED' 'no exe'; Fail 'E62' (L "$exe not found" "$exe introuvable") }
    $Script:Info['ssbu.exe'] = "{0:N0} MB" -f ((Get-Item -LiteralPath $exe).Length / 1MB)
    Ok (L "game built: $exe" "jeu compilé : $exe")
    Set-Step 'Compilation' 'OK' "$attempt attempt(s)"
}

# Kit 2.x built 13.0.4 in a version folder; once 13.0.5 is built, that folder only takes space (its build alone is
# several GB). Its save came over at the build (ws_setup.py install); a copy of it goes to save_backups first, so no
# save is lost even where the two differ. A folder holding a junction or link is kept: deleting it with PowerShell 5.1
# could go into what the link points to.
function Remove-OldTree {
    $old = Join-Path $Script:Repo $OLD_TREE
    if ($env:WS_NO_BUILD -or -not (Test-Path -LiteralPath $old) -or -not (Test-Path -LiteralPath (Join-Path $Script:Repo 'build\ssbu.exe'))) { return }
    Title (L "Old $OLD_TREE folder" "Ancien dossier $OLD_TREE")
    $files = @(Get-ChildItem -LiteralPath $old -Recurse -Force -ErrorAction SilentlyContinue)
    if ($files | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint }) { Say (L "  Kept (it holds a link): you can delete $old by hand." "  Gardé (il contient un lien) : tu peux supprimer $old à la main."); return }
    $size = ($files | Where-Object { -not $_.PSIsContainer } | Measure-Object Length -Sum).Sum / 1GB
    Say ((L "  It holds the 13.0.4 game ({0:N1} GB), no longer used: your save was taken over into the WindowSmash folder." "  Il contient le jeu en 13.0.4 ({0:N1} Go), qui ne sert plus : ta sauvegarde a été reprise dans le dossier WindowSmash.") -f $size)
    if (-not (Ask-YesNo (L '  Delete it? (a copy of its old save stays in save_backups)' '  Je le supprime ? (une copie de son ancienne sauvegarde reste dans save_backups)'))) { Say (L "  Kept: you can delete $old by hand." "  Gardé : tu peux supprimer $old à la main."); return }
    $oldSave = Join-Path $old 'save'
    if (Test-Path -LiteralPath $oldSave) {
        $bk = Join-Path $Script:Repo "save_backups\$OLD_TREE-save-$Stamp"
        New-Item -ItemType Directory -Force $bk | Out-Null
        Copy-Item -Path (Join-Path $oldSave '*') -Destination $bk -Recurse -Force
        $n1 = @(Get-ChildItem -LiteralPath $oldSave -Recurse -File -Force).Count
        $n2 = @(Get-ChildItem -LiteralPath $bk -Recurse -File -Force).Count
        if ($n2 -lt $n1) { Warn (L "W13 copy of the old save incomplete ($n2 files of $n1): $old kept" "W13 copie de l'ancienne sauvegarde incomplète ($n2 fichiers sur $n1) : $old gardé"); return }
        Ok (L "old save copied into $bk" "ancienne sauvegarde copiée dans $bk")
    }
    try {
        Remove-Item -LiteralPath $old -Recurse -Force
        Ok ((L "{0} deleted ({1:N1} GB freed)" "{0} supprimé ({1:N1} Go libérés)") -f $OLD_TREE, $size)
    } catch { Warn (L "W22 $OLD_TREE not fully deleted ($($_.Exception.Message)): delete it by hand" "W22 $OLD_TREE pas entièrement supprimé ($($_.Exception.Message)) : supprime-le à la main") }
}

function Finish {
    Title (L 'Done' 'Terminé')
    $play = Join-Path $Script:Repo 'Play SSBU.bat'
    if (Ask-YesNo (L '  Make the shortcuts (Desktop and Start menu) to start the game?' '  Je crée les raccourcis (Bureau et menu Démarrer) pour lancer le jeu ?')) {
        $launcher = Join-Path $env:LOCALAPPDATA 'WindowSmashLauncher\WindowSmash Launcher.bat'
        $exe = Join-Path $Script:Repo 'build\ssbu.exe'
        foreach ($dir in @($Desktop, [Environment]::GetFolderPath('Programs'))) {
            try {
                $sh = New-Object -ComObject WScript.Shell
                $lnk = $sh.CreateShortcut((Join-Path $dir 'Smash Ultimate (WindowSmash).lnk'))
                if (Test-Path -LiteralPath $launcher) {       # through the launcher: updates checked at every start
                    $lnk.TargetPath = $launcher; $lnk.Arguments = 'play'; $lnk.WorkingDirectory = (Split-Path $launcher -Parent)
                } else {
                    $lnk.TargetPath = $play; $lnk.WorkingDirectory = $Script:Repo
                }
                if (Test-Path -LiteralPath $exe) { $lnk.IconLocation = "$exe,0" }
                $lnk.Save()
                if (Test-Path -LiteralPath $launcher) {
                    $l2 = $sh.CreateShortcut((Join-Path $dir 'WindowSmash Launcher.lnk'))
                    $l2.TargetPath = $launcher; $l2.WorkingDirectory = (Split-Path $launcher -Parent)
                    $l2.Save()
                }
                Ok (L "shortcuts made: $dir" "raccourcis créés : $dir")
            } catch { Warn (L "W71 shortcut not made in $dir ($($_.Exception.Message))" "W71 raccourci non créé dans $dir ($($_.Exception.Message))") }
        }
    }
    Write-Report 'OK'
    Say ''
    if ($Script:Lang -eq 'fr') {
        Say "  Pour jouer : le raccourci 'Smash Ultimate (WindowSmash)' (il vérifie les mises à jour à chaque lancement)."
        Say "  Menu (installer, débloquer, optimiser, diagnostic, DLC, langue) : le raccourci 'WindowSmash Launcher'."
        Say '  Au lancement, une fenêtre WindowSmash montre la version et les réglages (affichage, en ligne, manettes) :'
        Say '  bouton Play pour jouer. Pendant le jeu, Échap ouvre le menu des réglages.'
        Say '  En ligne : le lobby public ; dans le jeu, Local Wireless liste les rooms de tous les joueurs de la même'
        Say '  version (aucun port à ouvrir), et Online > Smash > Quickplay cherche des adversaires (nouveau, en test).'
        Say '  Rooms entre amis seulement : dans la fenêtre WindowSmash, "Private lobby" et le même code chez tout le monde.'
        Say '  Hors ligne : "Offline" dans la même fenêtre.'
        Say '  FPS : si les shaders n''ont pas été précompilés, relance WindowSmash Launcher et choisis 5).'
        Say '  Clavier : flèches = stick, Z/X/C/V = A/B/X/Y, A/S = L/R, Q/W = ZL/ZR, Entrée = +, F1 = infos.'
        Say '  Tous les personnages : lance le jeu une fois, ferme-le, puis relance WindowSmash Launcher et choisis 4).'
        Say "  Un rapport (réussite) est sur le Bureau : WindowSmash-setup-report.txt"
    } else {
        Say "  To play: the 'Smash Ultimate (WindowSmash)' shortcut (it checks for updates at every start)."
        Say "  Menu (install, unlock, optimize, diagnosis, DLC, language): the 'WindowSmash Launcher' shortcut."
        Say '  At start, a WindowSmash window shows the version and the settings (display, online, controllers):'
        Say '  Play button to play. While playing, Esc opens the settings menu.'
        Say '  Online: the public lobby; in the game, Local Wireless lists the rooms of every player of the same'
        Say '  version (no port to open), and Online > Smash > Quickplay looks for opponents (new, being tested).'
        Say '  Rooms for friends only: in the WindowSmash window, "Private lobby" and the same code for everyone.'
        Say '  Offline: "Offline" in the same window.'
        Say '  FPS: if the shaders were not precompiled, start WindowSmash Launcher again and choose 5).'
        Say '  Keyboard: arrows = stick, Z/X/C/V = A/B/X/Y, A/S = L/R, Q/W = ZL/ZR, Enter = +, F1 = info.'
        Say '  Every fighter: start the game once, close it, then start WindowSmash Launcher again and choose 4).'
        Say "  A report (success) is on the Desktop: WindowSmash-setup-report.txt"
    }
    if (Ask-YesNo (L '  Start the game now?' '  Je lance le jeu maintenant ?')) { Start-Game }
}

# ---- smoother play: display latency 1, shaders compiled ahead of time ---------------------------
function Set-Latency1 {
    $f = Join-Path $Script:Repo 'display.ini'
    if (Test-Path -LiteralPath $f) {
        $text = [IO.File]::ReadAllText($f)
        if ($text -match '(?m)^latency\s*=\s*1\s*$') { Ok (L 'display latency already 1' 'latence d''affichage déjà à 1'); Set-Step 'Latency' 'OK' 'already 1'; return }
        if ($text -match '(?m)^latency\s*=') { $text = [regex]::Replace($text, '(?m)^latency\s*=[^\r\n]*', 'latency = 1') }
        else { $text = $text.TrimEnd() + "`nlatency = 1`n" }
    } else {
        $text = ($DisplayIni -replace "`r`n", "`n") + "`n"
    }
    [IO.File]::WriteAllText($f, $text, (New-Object Text.UTF8Encoding $false))
    Ok (L 'display latency set to 1 (display.ini): more responsive controls' 'latence d''affichage à 1 (display.ini) : commandes plus réactives')
    Set-Step 'Latency' 'OK' '1'
}

function Precompile-Shaders([bool]$fatal) {
    Title (L 'Shader precompilation (30 min to 2 h, at low priority)' 'Précompilation des shaders (30 min à 2 h, en priorité basse)')
    Say (L '  Without it, the game compiles each effect the first time it shows: that is what drops the FPS.' '  Sans elle, le jeu compile chaque effet la première fois qu''il apparaît : c''est ce qui fait tomber les FPS.')
    Say (L '  You can close the window to stop: start WindowSmash Launcher again and choose 5) to carry on.' '  Tu peux fermer la fenêtre pour arrêter : relance WindowSmash Launcher et choisis 5) pour reprendre où ça en était.')
    if (Get-Process ssbu -ErrorAction SilentlyContinue) {
        $m = L 'the game is running: close it during the precompilation' 'le jeu tourne : ferme-le pendant la précompilation'
        if ($fatal) { Fail 'E85' $m } else { Warn "W85 $m $(L '(option 5 later)' '(option 5 plus tard)')"; Set-Step 'Shaders' 'SKIPPED' 'game open'; return }
    }
    $env:SSBU_CLANG = $Script:Clang
    $cpu = (Get-CimInstance Win32_Processor | Measure-Object NumberOfLogicalProcessors -Sum).Sum
    $jobs = [int][math]::Max(1, $cpu - 2)      # one worker per thread, two left for the PC (Discord, the system)
    $r = Invoke-Helper @('shaders', '--jobs', "$jobs") -Live -name 'shaders'
    if ($r.Code -ne 0) {
        $m = if ($r.ErrText) { $r.ErrText } else { "code $($r.Code)" }
        Set-Step 'Shaders' 'FAILED' $m
        if ($fatal) { Fail 'E85' $m } else { Warn "W85 $m $(L '(run option 5 again later)' "(relance l'option 5 plus tard)")"; return }
    }
    Ok (L 'shaders precompiled' 'shaders précompilés')
    Set-Step 'Shaders' 'OK'
}

function Optimize-Only {
    Title (L 'Optimizing: latency 1 and precompiled shaders' 'Optimisation : latence 1 et shaders précompilés')
    $null = Find-Repo $false
    if (-not $Script:Repo -or -not (Test-Path -LiteralPath (Join-Path $Script:Repo 'build\ssbu.exe'))) { Say (L "  The game is not installed in $EXPECT_VERSION yet: choose 1) Install." "  Le jeu n'est pas encore installé en $EXPECT_VERSION : choisis 1) Installer."); return }
    $Script:VenvPy = Join-Path $Script:Repo '.venv\Scripts\python.exe'
    if (-not (Test-Path -LiteralPath $Script:VenvPy)) { Fail 'E85' (L 'Python environment not found: run 1) Install again' 'environnement Python introuvable : relance 1) Installer') }
    Ensure-LLVM      # the compiler shader_aot needs: already there, or downloaded again
    Set-Latency1
    Precompile-Shaders $true
}

function Unlock-Fighters {
    Title (L 'Unlocking every fighter' 'Déblocage de tous les personnages')
    $null = Find-Repo $false
    if (-not $Script:Repo -or -not (Test-Path -LiteralPath (Join-Path $Script:Repo 'build\ssbu.exe'))) { Say (L "  The game is not installed in $EXPECT_VERSION yet: choose 1) Install." "  Le jeu n'est pas encore installé en $EXPECT_VERSION : choisis 1) Installer."); return }
    if (Get-Process ssbu -ErrorAction SilentlyContinue) { Fail 'E80' (L 'the game is running: close it first (it rewrites its save when it quits)' 'le jeu tourne : ferme-le d''abord (il réécrit sa sauvegarde en quittant)') }
    $Script:VenvPy = Join-Path $Script:Repo '.venv\Scripts\python.exe'
    $r = Invoke-Helper @('unlock')
    foreach ($l in $r.Lines) { if ($l -notlike '@@*') { Say "  $l" } }
    if ($r.Code -ne 0) { $t = if ($r.ErrText) { $r.ErrText } else { "code $($r.Code)" }; Fail 'E80' $t }
    Ok (L 'fighters unlocked (a copy of the save from before is in save_backups)' 'personnages débloqués (une copie de la sauvegarde d''avant est dans save_backups)')
    Set-Step 'Unlock' 'OK'
}

# The DLC a player bought, dumped from their own Switch (nxdumptool: .nsp files): their folder goes to the build as the
# game folder's dlc\, and build_game.py's step 7 lists them in dump\modules\aoc.cfg, which the game reads. The fighters'
# code is in every 13.0.5 build already (data.arc holds it), so nothing is compiled again. Only the DLC in the folder
# count: nothing here unlocks one that isn't there.
function Add-DLC {
    Title (L 'Add your DLC (dumped from your Switch)' 'Ajouter tes DLC (dumpés de ta Switch)')
    $null = Find-Repo $false
    if (-not $Script:Repo -or -not (Test-Path -LiteralPath (Join-Path $Script:Repo 'build\ssbu.exe'))) { Say (L "  The game is not installed in $EXPECT_VERSION yet: choose 1) Install." "  Le jeu n'est pas encore installé en $EXPECT_VERSION : choisis 1) Installer."); return }
    if (Get-Process ssbu -ErrorAction SilentlyContinue) { Fail 'E53' (L 'the game is running: close it first' 'le jeu tourne : ferme-le d''abord') }
    $prev = Load-Inputs
    if (-not ($prev -and $prev.update -and (Test-Path -LiteralPath $prev.update) -and $prev.update_version -eq $EXPECT_VERSION)) {
        Fail 'E40' (L "the $EXPECT_VERSION update chosen at the install is not found: choose 1) Install" "la mise à jour $EXPECT_VERSION choisie à l'installation est introuvable : choisis 1) Installer")
    }
    $Script:Keys = Join-Path $Script:Repo 'keys'
    $Script:VenvPy = Join-Path $Script:Repo '.venv\Scripts\python.exe'
    if (-not (Test-Path -LiteralPath (Join-Path $Script:Keys 'prod.keys')) -or -not (Test-Path -LiteralPath $Script:VenvPy)) { Fail 'E40' (L 'install incomplete: choose 1) Install' 'installation incomplète : choisis 1) Installer') }
    Say (L '  The DLC (fighters, outfits, spirits) are the ones you bought, dumped from your Switch with nxdumptool' '  Les DLC (combattants, costumes, esprits) sont ceux que tu as achetés, dumpés de ta Switch avec nxdumptool')
    Say (L '  (.nsp files). To play online together, have the same DLC.' '  (fichiers .nsp). Pour jouer en ligne ensemble, ayez les mêmes DLC.')
    $d = Pick-Folder (L 'Choose the folder that holds your DLC (.nsp dumped from your Switch)' 'Choisis le dossier qui contient tes DLC (.nsp dumpés de ta Switch)')
    if (-not $d) { Fail 'E40' (L 'DLC folder not chosen' 'dossier des DLC non choisi') }
    # (-Include does nothing with -LiteralPath in PowerShell 5.1: the extension is tested instead)
    if (-not (Get-ChildItem -LiteralPath $d -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.Extension -in '.nsp', '.nca' } | Select-Object -First 1)) { Fail 'E40' (L "no .nsp file in $d" "pas de fichier .nsp dans $d") }
    $Script:Inputs = @{ base = $prev.base; update = $prev.update; prodkeys = $prev.prodkeys; titlekeys = $prev.titlekeys; dlc = $d; firmware = $prev.firmware; update_version = $prev.update_version }
    Save-Inputs
    Ensure-LLVM; Ensure-Opus; Ensure-SDL3      # (the build's environment as at the install: the game stays as it is)
    Build-Game (L 'The DLC into the game (a few minutes)' 'Les DLC dans le jeu (quelques minutes)')
    $cfg = Join-Path $Script:Repo 'dump\modules\aoc.cfg'
    $n = if (Test-Path -LiteralPath $cfg) { @(Get-Content -LiteralPath $cfg | Where-Object { $_ -and -not $_.StartsWith('#') }).Count } else { 0 }
    $Script:Info['DLC'] = "$n in $d"
    if (-not $n) { Set-Step 'DLC' 'FAILED' 'none'; Fail 'E53' (L "no Smash Ultimate DLC recognised in $d (DLC .nsp files dumped from your Switch?)" "aucun DLC de Smash Ultimate reconnu dans $d (des .nsp de DLC dumpés de ta Switch ?)") }
    Ok (L "$n DLC added: they show at the next start of the game" "$n DLC ajoutés : ils apparaissent au prochain lancement du jeu")
    Set-Step 'DLC' 'OK' "$n"
}

function Ensure-OnlineName {
    $f = Join-Path $Script:Repo 'online_name.txt'
    if (Test-Path -LiteralPath $f) { return }
    $def = 'Player' + (Get-Random -Minimum 1000 -Maximum 9999)
    $n = Read-Host (L "  Your online name (seen by the other players) [$def]" "  Ton pseudo en ligne (vu par les autres joueurs) [$def]")
    if (-not $n) { $n = $def }
    $n = ($n -replace '[^A-Za-z0-9_\- ]', '').Trim()
    if (-not $n) { $n = $def }
    [IO.File]::WriteAllText($f, "$n`r`n", (New-Object Text.ASCIIEncoding))
    Ok (L "name: $n (can be changed in online_name.txt)" "pseudo : $n (modifiable dans online_name.txt)")
}

# Since WindowSmash 9c1b250, Play SSBU.bat first opens the game's own window (tools\launcher.ps1: game version,
# display, online and controller settings); the game starts when Play is clicked there, so it may start long after
# this call, and the window can also be closed without playing (exit code 0, nothing started). With "start the game
# directly" ticked in it, or when it cannot open, the game starts at once as before. Whether the game was started is
# told by its log: every way of starting it writes <version folder>\build\play.log anew.
function Start-Game {
    $play = Join-Path $Script:Repo 'Play SSBU.bat'
    $log = Join-Path $Script:Repo 'build\play.log'
    Ensure-OnlineName
    try {
        $t0 = Get-Date
        $p = Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\cmd.exe') -ArgumentList '/c', "`"$play`"" -WorkingDirectory $Script:Repo -PassThru
        $null = $p.Handle      # (Windows PowerShell 5.1 loses the exit code of a process whose handle was never asked for)
        Say (L '  The WindowSmash window opens (game version, display, online, controllers): click Play to play.' '  La fenêtre WindowSmash s''ouvre (version du jeu, affichage, en ligne, manettes) : clique sur Play pour jouer.')
        while (-not $p.HasExited -and -not (Get-Process ssbu -ErrorAction SilentlyContinue)) { Start-Sleep -Milliseconds 500 }
        for ($i = 0; $i -lt 10 -and -not (Get-Process ssbu -ErrorAction SilentlyContinue); $i++) { Start-Sleep -Seconds 1 }
        if (-not (Get-Process ssbu -ErrorAction SilentlyContinue)) {
            if ((Test-Path -LiteralPath $log) -and (Get-Item -LiteralPath $log).LastWriteTime -ge $t0) { Fail 'E70' (L 'the game closed at once' "le jeu s'est fermé tout de suite") $log }
            if ($p.HasExited -and $p.ExitCode -eq 0) { Say (L '  Window closed without starting the game.' '  Fenêtre fermée sans lancer le jeu.'); return }
            $rc = if ($p.HasExited) { "code $($p.ExitCode)" } else { L 'still open' 'toujours ouvert' }
            Fail 'E70' (L "the game did not start (Play SSBU.bat: $rc)" "le jeu n'a pas démarré (Play SSBU.bat : $rc)") $log
        }
        Start-Sleep -Seconds 15
        if (-not (Get-Process ssbu -ErrorAction SilentlyContinue)) { Fail 'E70' (L 'the game closed at once' "le jeu s'est fermé tout de suite") $log }
        Ok (L 'game started (the first time, the screen may stay black during the intro movie)' 'jeu lancé (la première fois, l''écran peut rester noir pendant la vidéo d''intro)')
    } catch { Fail 'E70' "$($_.Exception.Message)" }
}

# ---- main ------------------------------------------------------------------------------------
try {
    $header = {
        Clear-Host
        Write-Host (L "WindowSmash setup (native Super Smash Bros. Ultimate) - kit $KitVersion" "Installation de WindowSmash (Super Smash Bros. Ultimate natif) - kit $KitVersion") -ForegroundColor Cyan
        Write-Host (L 'This program installs everything: the tools needed (Git, Python, Microsoft tools, compiler),' 'Ce programme installe tout : les outils nécessaires (Git, Python, outils Microsoft, compilateur),')
        Write-Host (L 'WindowSmash, then the game from YOUR files: base game 1.0.0 (.xci or .nsp),' 'WindowSmash, puis le jeu à partir de TES fichiers : jeu de base 1.0.0 (.xci ou .nsp),')
        Write-Host (L "update $EXPECT_VERSION (.nsp) and prod.keys, dumped from your console." "mise à jour $EXPECT_VERSION (.nsp) et prod.keys, dumpés de ta console.")
    }
    & $header
    Log "kit $KitVersion, KitDir=$KitDir, Mode=$Mode"
    if (-not $KitDir) { $KitDir = (Get-Location).Path }
    if ($KitDir.Length -gt 3) { $KitDir = $KitDir.TrimEnd('\') }
    while (-not $Mode) {
        Write-Host ''
        Write-Host (L '  1) Install / carry on with the install' '  1) Installer / reprendre l''installation')
        Write-Host (L '  2) Start the game (online, installed already)' '  2) Lancer le jeu (en ligne, déjà installé)')
        Write-Host (L '  3) Diagnosis only (makes the report, installs nothing)' '  3) Diagnostic seulement (crée le rapport sans rien installer)')
        Write-Host (L '  4) Unlock every fighter (after starting the game once)' '  4) Débloquer tous les personnages (après avoir lancé le jeu une fois)')
        Write-Host (L '  5) Optimize: precompile the shaders and latency 1 (steady FPS)' '  5) Optimiser : précompiler les shaders et latence 1 (FPS stables)')
        Write-Host (L '  6) Add my DLC (dumped from my Switch, .nsp files)' '  6) Ajouter mes DLC (dumpés de ma Switch, fichiers .nsp)')
        Write-Host (L '  7) Français (passer le launcher en français)' '  7) English (switch the launcher to English)')
        $m = "$(Read-Host (L '  Your choice [1]' '  Ton choix [1]'))".Trim()   # (no input at all: the default)
        if ($m -eq '7') { Set-Language $(if ($Script:Lang -eq 'fr') { 'en' } else { 'fr' }); Log "language $Script:Lang"; & $header; continue }
        $Mode = @{ '2' = 'play'; '3' = 'diag'; '4' = 'unlock'; '5' = 'optimize'; '6' = 'dlc' }[$m]
        if (-not $Mode) { $Mode = 'install' }
    }
    Probe-System
    if ($Mode -eq 'play') {
        $null = Find-Repo $false
        $built = $Script:Repo -and ((Test-Path -LiteralPath (Join-Path $Script:Repo 'build\ssbu.exe')) -or (Test-Path -LiteralPath (Join-Path $Script:Repo "$OLD_TREE\build\ssbu.exe")))
        if (-not $built) { Say (L '  The game is not installed yet: choose 1) Install.' '  Le jeu n''est pas encore installé : choisis 1) Installer.'); Read-Host (L 'Enter to close' 'Entrée pour fermer'); exit 1 }
        $g = Find-Git
        $head = if ($g -and (Test-Path -LiteralPath (Join-Path $Script:Repo '.git'))) { (Run-Native { & $g -C $Script:Repo rev-parse HEAD }) | Select-Object -First 1 } else { $null }
        if ($head -and $head -ne $WS_COMMIT) {
            Say (L "  New WindowSmash version ($($head.Substring(0,7)) -> $($WS_COMMIT.Substring(0,7))): to play online, you need the same as your friends." "  Nouvelle version de WindowSmash ($($head.Substring(0,7)) -> $($WS_COMMIT.Substring(0,7))) : pour jouer en ligne, il faut la même que tes amis.")
            if (-not (Test-Path -LiteralPath (Join-Path $Script:Repo 'build\ssbu.exe'))) {   # (from kit 2.x's 13.0.4)
                Say (L "  It needs the game's $EXPECT_VERSION update, dumped from your up-to-date Switch. If you don't have it yet," "  Elle demande la mise à jour $EXPECT_VERSION du jeu, dumpée de ta Switch à jour. Si tu ne l'as pas encore,")
                Say (L '  answer n: the current game stays playable meanwhile.' '  réponds n : le jeu actuel reste jouable en attendant.')
            }
            if (Ask-YesNo (L '  Update now? (recompile: 20 min to 2 h depending on the version and the PC)' '  Je fais la mise à jour maintenant ? (recompilation : 20 min à 2 h selon la version et le PC)')) { $Mode = 'install' }
        }
        if ($Mode -eq 'play') { Start-Game; exit 0 }
    }
    if ($Mode -eq 'unlock') { Unlock-Fighters; Read-Host (L 'Enter to close' 'Entrée pour fermer'); exit 0 }
    if ($Mode -eq 'optimize') { Optimize-Only; Write-Report 'OK (optimisation)'; Read-Host (L 'Enter to close' 'Entrée pour fermer'); exit 0 }
    if ($Mode -eq 'dlc') { Add-DLC; Write-Report 'OK (DLC)'; Read-Host (L 'Enter to close' 'Entrée pour fermer'); exit 0 }
    if ($Mode -eq 'diag') {
        $null = Find-Repo $false
        $Script:SysPy = Find-Python
        $Script:Info['Python'] = if ($Script:SysPy) { $Script:SysPy } else { 'missing' }
        $g = Find-Git; $Script:Info['Git'] = if ($g) { $g } else { 'missing' }
        $vs = Get-VS; $Script:Info['Visual Studio'] = if ($vs) { "$($vs.displayName) $($vs.installationVersion)" } else { 'missing' }
        $sdk = Get-SdkLib; $Script:Info['Windows SDK'] = if ($sdk) { $sdk.Name } else { 'missing' }
        if ($Script:Repo) {
            $v = Join-Path $Script:Repo '.venv\Scripts\python.exe'; if (Test-Path -LiteralPath $v) { $Script:VenvPy = $v }
            $c = Join-Path $Script:Repo "dump\_setup\llvm-$LLVM_VER\bin\clang-cl.exe"; $Script:Info['clang-cl'] = if (Test-Path -LiteralPath $c) { $c } else { 'missing' }
            if ($g -and (Test-Path -LiteralPath (Join-Path $Script:Repo '.git'))) { $Script:Info['WindowSmash (git)'] = (Run-Native { & $g -C $Script:Repo rev-parse HEAD }) | Select-Object -First 1 }
        }
        Write-Report 'DIAGNOSTIC'
        Say (L "  Report written on the Desktop: WindowSmash-setup-report.txt" "  Rapport écrit sur le Bureau : WindowSmash-setup-report.txt")
        if (-not $env:WS_NO_NOTEPAD) { try { Start-Process notepad.exe -ArgumentList "`"$Report`"" } catch {} }
        Read-Host (L 'Enter to close' 'Entrée pour fermer'); exit 0
    }
    Show-Prereqs
    Ensure-Git
    $freeGB = Find-Repo $true
    if ($freeGB -lt $NEED_GB -and -not (Test-PlainBase)) {
        Set-Step 'Disk' 'FAILED' "$freeGB GB"; Fail 'E22' (L "$freeGB GB free, about $NEED_GB are needed" "$freeGB Go libres, il en faut environ $NEED_GB")
    }
    Stop-Test 'repo'
    # Coming from kit 2.x's 13.0.4: the 13.0.5 update is asked and checked while WindowSmash is still at the version
    # that plays 13.0.4, so that a player without it yet (no file chosen, a wrong one) keeps a game that starts.
    $venv = Join-Path $Script:Repo '.venv\Scripts\python.exe'
    $migrating = (Test-Path -LiteralPath (Join-Path $Script:Repo "$OLD_TREE\build\ssbu.exe")) -and
                 -not (Test-Path -LiteralPath (Join-Path $Script:Repo 'build\ssbu.exe')) -and (Test-Path -LiteralPath $venv)
    if ($migrating) { $Script:VenvPy = $venv; Ask-Inputs; Check-Inputs }
    Ensure-Revision
    Stop-Test 'revision'
    Ensure-Python
    Ensure-VS
    Ensure-LLVM
    Test-Toolchain
    Stop-Test 'tools'
    if (-not $migrating) { Ask-Inputs; Check-Inputs }
    Prepare-Base
    Prepare-Fonts
    Ensure-Opus
    Ensure-SDL3
    Build-Game
    Remove-OldTree
    Set-Latency1
    if (Ask-YesNo (L '  Precompile the shaders now? (recommended: steady FPS from the first match; 30 min to 2 h)' '  Je précompile les shaders maintenant ? (recommandé : FPS stables dès le premier match ; 30 min à 2 h)')) { Precompile-Shaders $false }
    else { Say (L '  Later: start WindowSmash Launcher again and choose 5).' '  Plus tard : relance WindowSmash Launcher et choisis 5).') }
    Finish
    Read-Host (L 'Enter to close' 'Entrée pour fermer')
    exit 0
} catch {
    $e = $_
    Log "UNEXPECTED $($e.Exception.GetType().FullName): $($e.Exception.Message)`r`n$($e.ScriptStackTrace)"
    $Script:Info['PowerShell error'] = "$($e.Exception.Message) | $($e.InvocationInfo.PositionMessage -replace '\s+', ' ')"
    Fail 'E99' "$($e.Exception.Message)"
}
