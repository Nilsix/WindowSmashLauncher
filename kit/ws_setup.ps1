# OpenSmash Ultimate Launcher - the kit's orchestrator (Windows PowerShell 5.1). It lives in the repository
# github.com/Nilsix/WindowSmashLauncher (kit\ws_setup.ps1, next to kit\ws_setup.py) and is started by
# "OpenSmash Ultimate Launcher.bat", which keeps a clone of that repository up to date in %LOCALAPPDATA%\WindowSmashLauncher.
# Kit 4.0 (2026-11-04): WindowSmash and OpenSmash (ssbu-recomp) merged into github.com/OpenSmash-Ultimate/OpenSmash-Ultimate
# on 2026-11-03, and the two launchers into this one. A player's "WindowSmash Launcher.bat" or "OpenSmash Launcher.bat"
# is renamed and their shortcuts made again (Update-LauncherFiles), a WindowSmash folder moves to the merged repository
# with git (Ensure-Revision), and an OpenSmash install gets a new one, its save taken over (Import-OpenSmashSave).
# kit-opensmash\os_setup.ps1 only passes on to this file.
# Kit 4.1: the migration's corner cases (an old OpenSmash build folder holding other files, game files kept inside it,
# an update stopped before its compile, game files gone since the last build, no firmware, a copy without git), the
# install folder on an SSD by default, and the players' own shortcuts to an old launcher file.
# Kit 4.3: OpenSmash Ultimate 6c38207, whose rollback netcode is on by default online (Quickplay and 1-on-1 Local Wireless
# room matches, when both games have it; Esc > Online > Rollback netcode turns it off): one "Start the game" option, the
# menu renumbered (kits 4.0-4.2's option 3, rollback through the room, is gone).
# Kit 4.4: a dual boot. OpenSmash (ssbu-recomp, pinned at its last commit) is back beside OpenSmash Ultimate as menu 8 and
# the os-* modes, run by kit-opensmash\os_kit.ps1 (kit-opensmash 1.14 with the launcher's new names) in a PowerShell of
# its own; an OpenSmash install is no longer offered for deletion, and its old play shortcut starts it again (os-play).
# Kit 4.4.1: an install folder directly under a drive root (D:\OpenSmash, or Browse to D:\) no longer stops with E99
# (New-Item -Force on a root throws in PowerShell 5.1).
# Kit 4.4.2: pin 078e055 (rollback on by default in private rooms too). Install folders: Enter says when the default is
# next to OpenSmash Ultimate; typed paths must be whole ("D:" = that disk, %VARS% expanded), never a network folder or
# [ ]; a write test before git clone (a folder, then a file: C:\ takes only folders); OpenSmash at a drive root no longer
# breaks the default folder; repo.txt on an unplugged disk is W14/E14, never "not installed". OpenSmash: game files on
# an unplugged disk are W15/E15, the DLC folder is kept when the files are chosen again, install.py gets the DLC folder
# plus one package per Smash DLC id (bounded), an empty crash report no longer stops the diagnosis.
# This file must stay UTF-8 with a BOM (Windows PowerShell 5.1 reads a BOM-less file as ANSI).
# A complete installer: it installs what is missing (Git, Python 3.14, Visual Studio Build Tools, LLVM, Opus), clones
# OpenSmash Ultimate, prepares the user's own game files and builds the game.
# Every failure stops with a code (E..), an explanation and a report on the Desktop
# (OpenSmash-Ultimate-setup-report.txt) that can be sent back as it is: it holds no key and no game data.
# The player sees English, or French when chosen (menu 7, kept in %LOCALAPPDATA%\WindowSmash-setup\lang.txt): every
# message is written as L 'English' 'French'. The report and the log stay in English.
# Modes (-Mode, the launcher's argument): install, play, diag, unlock, optimize, dlc; none: the menu. play-rollback and
# play-norollback (older launchers' names) are play.
# OpenSmash's (kit-opensmash\os_kit.ps1): os (its menu), os-install, os-play, os-play-rollback, os-play-norollback, os-diag,
# os-dlc, os-unlock, os-lowspec.
# Test-only environment: WS_NO_BUILD (skip the compile), WS_STOP_AFTER=<step>, WS_NO_NOTEPAD, WS_REPORT_DIR,
# WS_INPUTS_JSON (another inputs.json), WS_DESKTOP_DIR (another Desktop; Downloads then not looked at).
param([string]$KitDir = '', [string]$Mode = '')

$ErrorActionPreference = 'Stop'
$KitVersion = '4.4.2 (2026-11-05)'

# ---- what the host's build was made from: the friend's must match it for netplay ------------
# (WindowSmash, github.com/OpenSmash-Ultimate/WindowSmash, pinned at 8025b48 by kits 3.x, and OpenSmash merged on
# 2026-11-03 into one repository whose history goes on from WindowSmash's: a WindowSmash folder moves to it with git)
$WS_GIT_URL  = 'https://github.com/OpenSmash-Ultimate/OpenSmash-Ultimate.git'
$WS_OLD_URL  = '(?i)github\.com[/:](SNO2207|OpenSmash-Ultimate)/WindowSmash(\.git)?/?$'   # where kits 1.x to 3.x cloned WindowSmash from
$WS_COMMIT   = '078e05533d53100ce89186a9cff61630420e6429'   # main, 2026-11-05: rollback on by default in private rooms too (#148); setup link (#157)
$WS_BRANCH   = 'main'
$WS_ZIP      = "https://codeload.github.com/OpenSmash-Ultimate/OpenSmash-Ultimate/zip/$WS_COMMIT"
$WS_FILES    = @{   # SHA-256 (line ends as LF) of files of that commit: a copy without git is checked with them
    'tools\build_game.py' = '8740c8c8aef2190eeb96d0b8fd4c6d1542061cfe2140ad593fe18b93a5d5d6eb'
    'tools\update.py'     = '895ce9ee48621a194613ad60fe48ce6aa19db54b1832ce040531c0f04ff687d2'
    'tools\recomp.py'     = '32c090ddbe23a379a1f59bbe8d68a448299c464c2143f8c154fc744380935b29'
    'tools\nca.py'        = 'dff2b794c2f773b06eb8fd391ad01e933c23de692a752333e48e268c834392cf'
}
$EXPECT_VERSION = '13.0.5'      # the only game version it builds and plays (since WindowSmash's commit ec8a8b5)
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
# the launcher's names: kit 4.0's, and the two launchers' before it (players' copies and the kits' shortcuts)
$NEW_BAT   = 'OpenSmash Ultimate Launcher.bat'
$OLD_BATS  = @('WindowSmash Launcher.bat', 'OpenSmash Launcher.bat')
$PLAY_LNK  = 'Smash Ultimate (OpenSmash Ultimate).lnk'
$MENU_LNK  = 'OpenSmash Ultimate Launcher.lnk'
$OLD_LNKS  = @(@('Smash Ultimate (WindowSmash).lnk', $true), @('Smash Ultimate (OpenSmash).lnk', $true),
               @('WindowSmash Launcher.lnk', $false), @('OpenSmash Launcher.lnk', $false))   # (name, plays)
$SAVE_DIR  = 'save\0123456789abcdeffedcba9876543210'   # the game's save in its folder (runtime/hle_fs.c, tools/unlock_all.py)
$BUILD_MARK = 'build\kit_build.txt'   # written after a compile: the pinned commit it built, and the exe's time
$OS_MODES  = @('os', 'os-install', 'os-play', 'os-play-rollback', 'os-play-norollback', 'os-diag', 'os-dlc', 'os-unlock', 'os-lowspec')   # (kit-opensmash\os_kit.ps1's)

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
        'E10' { L "The folder is not OpenSmash Ultimate: it must hold tools and runtime." "Le dossier n'est pas OpenSmash Ultimate : il doit contenir tools et runtime." }
        'E11' { L "OpenSmash Ultimate could not be set to the right version. Check the internet connection. If you changed files in the folder, download it again." "Impossible de mettre OpenSmash Ultimate à la bonne version. Vérifie internet. Si tu as modifié des fichiers du dossier, retélécharge-le." }
        'E12' { L "Git could not be installed. Install it from git-scm.com (default options), then start again." "Git n'a pas pu être installé. Installe-le depuis git-scm.com (options par défaut) puis relance." }
        'E13' { L "Cloning OpenSmash Ultimate failed. Check the internet connection (is github.com reachable?), then start again." "Le clonage d'OpenSmash Ultimate a échoué. Vérifie internet (github.com accessible ?) puis relance." }
        'E14' { L "Plug in the disk OpenSmash Ultimate is on (a USB disk?), then start the launcher again." "Branche le disque où est OpenSmash Ultimate (un disque USB ?), puis relance le launcher." }
        'E15' { L "The tools needed were not installed (refused). Start again and answer Y to install them." "Les outils nécessaires n'ont pas été installés (refusé). Relance et réponds O pour les installer." }
        'E20' { L "Windows 10 or 11, 64-bit, is needed." "Il faut Windows 10 ou 11 en 64 bits." }
        'E21' { L "Your processor lacks the AVX2/FMA/F16C instructions: the game cannot run on this PC." "Ton processeur n'a pas les instructions AVX2/FMA/F16C : le jeu ne peut pas tourner sur ce PC." }
        'E22' { L "Not enough disk space. Free some (about $NEED_GB GB on the OpenSmash Ultimate folder's disk), then start again." "Pas assez d'espace disque. Libère de la place (environ $NEED_GB Go sur le disque du dossier OpenSmash Ultimate) puis relance." }
        'E23' { L "The OpenSmash Ultimate folder is in OneDrive: move it elsewhere (for example C:\Games\OpenSmash-Ultimate), then start again." "Le dossier OpenSmash Ultimate est dans OneDrive : déplace-le ailleurs (par exemple C:\Jeux\OpenSmash-Ultimate) puis relance." }
        'E30' { L "Python 3.14 could not be installed. Install it from python.org (tick 'Add python.exe to PATH'), then start again." "Python 3.14 n'a pas pu être installé. Installe-le depuis python.org (coche 'Add python.exe to PATH') puis relance." }
        'E31' { L "The Python environment failed (pip downloads pycryptodomex: check the internet connection), then start again." "L'environnement Python a échoué (pip télécharge pycryptodomex : vérifie internet) puis relance." }
        'E32' { L "Microsoft's build tools (Build Tools) did not install. Accept the administrator window when it appears, then start again." "Les outils de compilation Microsoft (Build Tools) ne se sont pas installés. Accepte la fenêtre administrateur quand elle apparaît, puis relance." }
        'E33' { L "Build Tools incomplete: open 'Visual Studio Installer', Modify, tick 'Desktop development with C++' (with the Windows SDK), then start again." "Build Tools incomplets : ouvre 'Visual Studio Installer', Modifier, coche 'Développement Desktop en C++' (avec le SDK Windows), puis relance." }
        'E34' { L "Downloading LLVM (the compiler, 900 MB) failed or the file is damaged. Start again." "Le téléchargement de LLVM (le compilateur, 900 Mo) a échoué ou est abîmé. Relance." }
        'E35' { L "The compiler does not work (compile test). Send the report." "Le compilateur ne marche pas (test de compilation). Envoie le rapport." }
        'E40' { L "A file that was asked for was not chosen. Start again and choose it." "Un fichier demandé n'a pas été choisi. Relance et choisis-le." }
        'E41' { L "Problem with prod.keys: it must be the one dumped from YOUR up-to-date console (Lockpick_RCM)." "Problème avec prod.keys : il faut celui dumpé de TA console à jour (Lockpick_RCM)." }
        'E42' { L "The base game is not right: it must be Super Smash Bros. Ultimate 1.0.0 (.xci or .nsp), not an update." "Le jeu de base ne convient pas : il faut Super Smash Bros. Ultimate 1.0.0 (.xci ou .nsp), pas une mise à jour." }
        'E43' { L "The update is not right: OpenSmash Ultimate needs Smash Ultimate's $EXPECT_VERSION update (.nsp), dumped from your up-to-date Switch." "La mise à jour ne convient pas : OpenSmash Ultimate demande l'update $EXPECT_VERSION de Smash Ultimate (.nsp), dumpée de ta Switch à jour." }
        'E44' { L "Ticket missing or tied to your console: dump again with nxdumptool, ticking 'remove console specific data', or give a title.keys." "Ticket manquant ou lié à ta console : redumpe avec nxdumptool en cochant 'remove console specific data', ou donne un title.keys." }
        'E45' { L "Firmware fonts not found: choose your console's firmware folder or an emulator's (.nca files)." "Polices du firmware introuvables : choisis le dossier du firmware de ta console ou d'un émulateur (fichiers .nca)." }
        'E50' { L "The decrypted copy of the base game failed (disk full? damaged file?)." "La copie déchiffrée du jeu de base a échoué (disque plein ? fichier abîmé ?)." }
        'E51' { L "Applying the update failed." "L'application de la mise à jour a échoué." }
        'E52' { L "Extracting the fighter modules failed." "L'extraction des modules de combattants a échoué." }
        'E53' { L "A preparation step failed." "Une étape de préparation a échoué." }
        'E54' { L "No DLC recognised: choose the folder of the DLC dumped from your Switch (nxdumptool or DBI), the .nsp/.nsz files with their names as dumped: the name holds the DLC id (01006A800016F...)." "Aucun DLC reconnu : choisis le dossier des DLC dumpés de ta Switch (nxdumptool ou DBI), les fichiers .nsp/.nsz avec leur nom de dump : il contient l'identifiant du DLC (01006A800016F...)." }
        'E59' { L "Internal error of the Python script: send the report." "Erreur interne du script Python : envoie le rapport." }
        'E60' { L "The compile failed." "La compilation a échoué." }
        'E61' { L "Making ssbu.exe failed: close the game if it is running, then start again." "La création de ssbu.exe a échoué : ferme le jeu s'il tourne et relance." }
        'E62' { L "ssbu.exe vanished after the compile: your antivirus may have removed it (add an exclusion for the OpenSmash Ultimate folder)." "ssbu.exe a disparu après la compilation : ton antivirus l'a peut-être supprimé (ajoute une exclusion pour le dossier OpenSmash Ultimate)." }
        'E70' { L "The game did not start." "Le jeu ne s'est pas lancé." }
        'E85' { L "Shader precompilation stopped: close the game, then start OpenSmash Ultimate Launcher again and choose 5)." "La précompilation des shaders s'est arrêtée : ferme le jeu, puis relance OpenSmash Ultimate Launcher et choisis 5)." }
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
$Desktop  = if ($env:WS_DESKTOP_DIR) { $env:WS_DESKTOP_DIR } else { [Environment]::GetFolderPath('Desktop') }   # (tests: elsewhere)
$Downloads = $null      # (where browsers save the launcher file: the shell's own setting, the folder moved or not)
if (-not $env:WS_DESKTOP_DIR) { try { $Downloads = [Environment]::ExpandEnvironmentVariables((Get-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders' -ErrorAction Stop).'{374DE290-123F-4565-9164-39C4925E467B}') } catch {} }
$TaskbarPins = Join-Path $env:APPDATA 'Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar'
$ReportDir = if ($env:WS_REPORT_DIR) { $env:WS_REPORT_DIR } else { $Desktop }   # (tests: elsewhere)
$Report   = Join-Path $ReportDir 'OpenSmash-Ultimate-setup-report.txt'
$Helper   = Join-Path $PSScriptRoot 'ws_setup.py'
$InputsJs = if ($env:WS_INPUTS_JSON) { $env:WS_INPUTS_JSON } else { Join-Path $HomeDir 'inputs.json' }   # (shared with the OpenSmash launcher's kit)
$RepoTxt  = Join-Path $HomeDir 'repo.txt'          # where the game was installed, for the next runs
$OsRepoTxt  = Join-Path $HomeDir 'opensmash-repo.txt'   # the OpenSmash install (kit-opensmash 1.x, then os_kit.ps1: menu 8)
$OsSaveKeep = Join-Path $HomeDir 'opensmash-save'       # its save, kept here by kits 4.0-4.2 when they deleted its folder before a build
New-Item -ItemType Directory -Force $LogDir | Out-Null
$Script:AutoInstall = $false; $Script:Git = $null
# display.ini as the game writes it at its first start (runtime/gpu_display.c's DEFAULT_INI at the pinned commit, Windows), with latency 1
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
; low_latency = 1: the game starts each frame later, as late as it can and still be ready for the next
;   refresh, so it reads the controller later: up to most of a frame less input delay. 0: at the refresh.
low_latency = 1
; hide_cursor = 1: hide the mouse pointer over the game after 2 seconds without moving it.
hide_cursor = 1
; runahead = 0-3: in fights, show each frame this many frames ahead (less input delay; the settings menu's
;   Display page: off, 1, 2). 1 shows the real frame one frame sooner, 2 also predicts one frame on the
;   controls held now. Each frame ahead costs a frame of the game's work more per frame shown, and a savestate.
runahead = 0
; overlay = 1: show the frame rate in the corner from the start (F1 shows or hides it while playing).
overlay = 1
; volume = 0-100: the game's whole sound, over its own sound settings (0 is silent). The settings menu changes it while playing.
volume = 100
; overlay_scale = 0.25-2: the overlay's size (0.5: half as big, out of the way of the game).
overlay_scale = 1

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

; renderer = d3d11 | vulkan
;   d3d11:  Direct3D 11, the renderer the game is played and tested with.
;   vulkan: the Vulkan renderer, in development. Until it can draw the game, the game checks Vulkan
;           on this PC at its start, says what it found in its log, and draws as before.
renderer = d3d11
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
    & $add "OPENSMASH ULTIMATE SETUP REPORT - kit $KitVersion (language: $Script:Lang)"
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
            if ($st.Json) { & $add ''; & $add '--- The game in its folder'; & $add (Redact ($st.Json | ConvertTo-Json -Compress -Depth 4)) }
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
    Write-Host (L "  Report written on the Desktop: OpenSmash-Ultimate-setup-report.txt" "  Rapport écrit sur le Bureau : OpenSmash-Ultimate-setup-report.txt") -ForegroundColor Cyan
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
# own game folder is declared safe for the git commands the kit starts (and their children) through
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

# The folder's version: its git HEAD; for a copy without git (or without git on the PC), $WS_COMMIT when the files the
# kit checks are that commit's, else 'other'. $null when git cannot read it.
function Get-RepoVersion {
    $g = if ($Script:Git) { $Script:Git } else { Find-Git }
    if ($g -and (Test-Path -LiteralPath (Join-Path $Script:Repo '.git'))) {
        Set-GitSafeRepo
        $h = "$(@(Run-Native { & $g -C $Script:Repo rev-parse HEAD 2>$null }) | Select-Object -First 1)".Trim()
        if ($h -match '^[0-9a-f]{40}$') { return $h }
        return $null
    }
    foreach ($f in $WS_FILES.Keys) {
        $p = Join-Path $Script:Repo $f
        if (-not (Test-Path -LiteralPath $p) -or (Get-NormalizedSha256 $p) -ne $WS_FILES[$f]) { return 'other' }
    }
    return $WS_COMMIT
}

# $true when build\ssbu.exe was compiled from the folder's current version. An update checks the new version out first
# and compiles it last: one stopped in between (a file not chosen, the window closed, the PC off) leaves the new version
# with the old game, which does not play online with the others. The kit writes $BUILD_MARK after each compile; a game
# built without it (before kit 4.1, or by hand) counts as current unless runtime\ has files newer than it (a checkout
# rewrites the files it changes).
function Test-BuildCurrent([string]$version) {
    $exe = Join-Path $Script:Repo 'build\ssbu.exe'
    if (-not (Test-Path -LiteralPath $exe)) { return $false }
    $ticks = "$((Get-Item -LiteralPath $exe).LastWriteTimeUtc.Ticks)"
    $mark = Join-Path $Script:Repo $BUILD_MARK
    if (Test-Path -LiteralPath $mark) {
        $l = @(Get-Content -LiteralPath $mark -TotalCount 2)
        if ($l.Count -ge 2 -and "$($l[1])".Trim() -eq $ticks) { return ("$($l[0])".Trim() -eq $version) }
    }
    $t = (Get-Item -LiteralPath $exe).LastWriteTimeUtc
    $newer = Get-ChildItem -LiteralPath (Join-Path $Script:Repo 'runtime') -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTimeUtc -gt $t } | Select-Object -First 1
    return (-not $newer)
}

function Ensure-Git {
    Title 'Git'
    $Script:Git = Find-Git
    if (-not $Script:Git) {
        if (-not (Ask-YesNo (L '  Git (to download OpenSmash Ultimate) is not installed. Install it?' '  Git (pour télécharger OpenSmash Ultimate) n''est pas installé. Je l''installe ?') -Install)) { Set-Step 'Git' 'FAILED' 'refused'; Fail 'E12' (L 'Git install refused' 'installation de Git refusée') }
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
        @('OpenSmash Ultimate (git clone)', [bool]$repo, (L '15 MB' '15 Mo'))
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
function Test-RepoDir([string]$d) {      # (never Join-Path: it fails on a drive that is not there, an unplugged USB disk)
    if (-not $d) { return $false }
    try { return ((Test-Path -LiteralPath ([IO.Path]::Combine($d, 'tools\recomp.py'))) -and (Test-Path -LiteralPath ([IO.Path]::Combine($d, 'runtime')))) } catch { return $false }
}

# A folder path as the kits keep it: trimmed, without a last backslash ("D:\My Games\x\" would reach git as
# "D:\My Games\x\"" and its \" would swallow the closing quote), a drive root kept as 'D:\'.
function Get-CleanFolder([string]$p) {
    $p = "$p".Trim().Trim('"')
    if ($p -match '^[A-Za-z]:[\\/]*$') { return $p.Substring(0, 2) + '\' }
    return $p.TrimEnd('\', '/')
}

# The root of a path's disk when that disk is not connected now (an unplugged USB disk), else $null
function Get-MissingRoot([string]$p) {
    if (-not $p) { return $null }
    try { $r = [IO.Path]::GetPathRoot($p) } catch { return $null }
    if ($r -match '^[A-Za-z]:\\?$' -and -not (Test-Path -LiteralPath ($r.Substring(0, 2) + '\'))) { return $r.Substring(0, 2) + '\' }
    return $null
}

# The install folder the player typed, browsed to or took by default, as a full path; $null after a W13 that says why.
# Never relative (it would land in the launcher's own folder), never a network folder, never [ ] (PowerShell reads them
# as wildcards).
function Get-InstallFolder([string]$t, [bool]$typed) {
    if ($typed) {
        $t = [Environment]::ExpandEnvironmentVariables("$t".Trim().Trim('"'))
        if ($t -match '^[A-Za-z]:$') { $t += '\' }      # ("D:" alone: that disk, never its current folder)
        if ($t -notmatch '^([A-Za-z]:[\\/]|\\\\|//)') { Warn (L "W13 type a whole path, with its disk (for example D:\Games\OpenSmash-Ultimate): $t" "W13 tape un chemin complet, avec son disque (par exemple D:\Jeux\OpenSmash-Ultimate) : $t"); return $null }
    }
    try { $t = [IO.Path]::GetFullPath($t) } catch { Warn (L "W13 invalid path: $t" "W13 chemin invalide : $t"); return $null }
    if ($t.StartsWith('\\')) { Warn (L "W13 a network folder cannot be used: choose a folder on a disk of this PC ($t)" "W13 un dossier réseau ne convient pas : choisis un dossier sur un disque de ce PC ($t)"); return $null }
    if ($t -match '[\[\]]') { Warn (L "W13 no [ or ] in the folder's path, please: choose another folder ($t)" "W13 pas de [ ni de ] dans le chemin du dossier : choisis un autre dossier ($t)"); return $null }
    return (Get-CleanFolder $t)
}

# $true when git clone can work there: a folder made in it, a file in that folder (a protected folder would fail the
# clone with an unclear message). Never a file in the folder itself: a drive root such as C:\ takes folders from a
# standard user, not files.
function Test-Writable([string]$d) {
    if (-not $d -or -not [IO.Directory]::Exists($d)) { return $false }      # (CreateDirectory would make the missing folders on the way)
    $p = [IO.Path]::Combine($d, ".write-test-$PID")
    try { [void][IO.Directory]::CreateDirectory($p); [IO.File]::WriteAllText([IO.Path]::Combine($p, 'x.tmp'), 'x'); return $true }
    catch { return $false }
    finally { try { if ([IO.Directory]::Exists($p)) { [IO.Directory]::Delete($p, $true) } } catch { } }
}

# $true when a folder holds anything, or cannot be read (then it is not used as an empty one)
function Test-NotEmpty([string]$d) { try { return [bool](Get-ChildItem -LiteralPath $d -Force -ErrorAction Stop | Select-Object -First 1) } catch { return $true } }

function Get-RepoZip([string]$target) {
    $zip = Join-Path $HomeDir "downloads\OpenSmash-Ultimate-$WS_COMMIT.zip"
    Download $WS_ZIP $zip '' 'OpenSmash Ultimate (source)' 'E11'
    $tmp = Join-Path $HomeDir "unzip-$Stamp"
    try { Expand-Archive -LiteralPath $zip -DestinationPath $tmp -Force } catch { Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue; Fail 'E11' (L "OpenSmash Ultimate archive unreadable: $($_.Exception.Message)" "archive OpenSmash Ultimate illisible : $($_.Exception.Message)") }
    $src = Get-ChildItem -LiteralPath $tmp -Directory | Select-Object -First 1
    New-Item -ItemType Directory -Force $target | Out-Null
    $rc = Run-Logged (Join-Path $env:SystemRoot 'System32\robocopy.exe') @($src.FullName, $target, '/E', '/NFL', '/NDL', '/NJH', '/NJS', '/NP', '/R:2', '/W:2') 'robocopy-repo'
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    if ($rc -ge 8) { Fail 'E11' (L "copying the OpenSmash Ultimate files failed (robocopy $rc)" "copie des fichiers OpenSmash Ultimate impossible (robocopy $rc)") }
}

function Get-RememberedRepo {
    if (Test-Path -LiteralPath $RepoTxt) { $p = Get-CleanFolder "$(Get-Content -LiteralPath $RepoTxt -Raw)"; if (Test-RepoDir $p) { return $p } }
    return $null
}

# $true when $path is $dir or inside it (full paths, any case)
function Test-Under([string]$path, [string]$dir) {
    if (-not $path -or -not $dir) { return $false }
    try { $p = [IO.Path]::GetFullPath($path).TrimEnd('\') + '\'; $d = [IO.Path]::GetFullPath($dir).TrimEnd('\') + '\' } catch { return $false }
    return $p.StartsWith($d, [StringComparison]::OrdinalIgnoreCase)
}

# The drive roots ('C:\') on an internal SSD (not USB): the game reads its data and its shader cache from the disk while
# it plays, and a USB hard disk makes it stall. Empty when Windows does not say (no admin rights are needed for this).
function Get-SsdRoots {
    $roots = @()
    try {
        $ssd = @(Get-PhysicalDisk -ErrorAction Stop | Where-Object { ($_.MediaType -eq 'SSD' -or $_.BusType -eq 'NVMe') -and $_.BusType -ne 'USB' } | ForEach-Object { "$($_.DeviceId)" })
        foreach ($d in @(Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3')) {
            try { $n = "$((Get-Partition -DriveLetter $d.DeviceID.Substring(0, 1) -ErrorAction Stop | Select-Object -First 1).DiskNumber)" } catch { continue }
            if ($ssd -contains $n) { $roots += ($d.DeviceID + '\') }
        }
    } catch { Log "disk types unknown: $($_.Exception.Message)" }
    return $roots
}

function Get-DefaultInstallDir {
    # an internal SSD with room (the game and its build take about 35 GB), else next to the OpenSmash install (menu 8)
    # when there is one, else the local disk with the most free space. Never inside the OpenSmash install's folders.
    $os = Get-OldOpenSmash
    $disks = @(Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' | Sort-Object FreeSpace -Descending)
    $ssd = Get-SsdRoots
    $fast = $disks | Where-Object { $ssd -contains ($_.DeviceID + '\') -and $_.FreeSpace / 1GB -ge $NEED_GB } | Select-Object -First 1
    $root = if ($fast) { $fast.DeviceID + '\' } else { $null }
    $ok = { param($t) $t -and -not ($os -and ((Test-Under $t $os.Repo) -or (Test-Under $t $os.Build))) }     # (Find-Repo refuses OpenSmash's folders)
    if ($os -and (-not $root -or $root -eq [IO.Path]::GetPathRoot("$($os.Repo)\"))) {
        $p = try { [IO.Path]::GetDirectoryName($os.Repo) } catch { $null }      # ($null for a drive root: never Split-Path, which throws on 'E:')
        if ($p) { $t = [IO.Path]::Combine($p, 'OpenSmash-Ultimate'); if (& $ok $t) { return $t } }
        if (-not $root) { $root = [IO.Path]::GetPathRoot("$($os.Repo)\") }
    }
    if (-not $root) { $root = if ($disks) { $disks[0].DeviceID + '\' } else { 'C:\' } }
    foreach ($r in @($root) + @($disks | ForEach-Object { $_.DeviceID + '\' })) {
        $t = [IO.Path]::Combine($r, 'Jeux\OpenSmash-Ultimate')
        if (& $ok $t) { return $t }
    }
    return $null      # (Find-Repo: Enter then browses)
}

function Clone-Repo([string]$target) {
    $parent = [IO.Path]::GetDirectoryName($target)      # (D:\OpenSmash-Ultimate: D:\, which New-Item -Force cannot "create" in PowerShell 5.1)
    if ($parent -and -not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Force $parent | Out-Null }
    Say (L "  Cloning OpenSmash Ultimate into $target ..." "  Clonage d'OpenSmash Ultimate dans $target ...")
    Log "git clone $WS_GIT_URL $target"
    Run-Native { & $Script:Git clone $WS_GIT_URL $target }
    if ($LASTEXITCODE -ne 0 -or -not (Test-RepoDir $target)) { Set-Step 'Folder' 'FAILED' 'git clone'; Fail 'E13' (L "git clone failed (code $LASTEXITCODE)" "git clone a échoué (code $LASTEXITCODE)") }
    Ok (L 'repository cloned' 'dépôt cloné')
}

function Find-Repo([bool]$allowClone) {
    Title (L 'OpenSmash Ultimate folder' 'Dossier OpenSmash Ultimate')
    foreach ($c in @($KitDir, (Split-Path $KitDir -Parent))) {
        if ($c -and (Test-RepoDir $c)) { $Script:Repo = (Resolve-Path -LiteralPath $c).Path; Say (L '  This file is in an OpenSmash Ultimate folder: using it.' '  Ce fichier est dans un dossier OpenSmash Ultimate : je l''utilise.'); break }
    }
    if (-not $Script:Repo) { $r = Get-RememberedRepo; if ($r) { $Script:Repo = $r; Say (L "  Previous install found: $r" "  Installation précédente trouvée : $r") } }
    if (-not $Script:Repo -and (Test-Path -LiteralPath $RepoTxt)) {      # (its disk unplugged: never "not installed" without a word)
        $was = Get-CleanFolder "$(Get-Content -LiteralPath $RepoTxt -Raw)"
        $gone = Get-MissingRoot $was
        if ($gone) {
            Warn (L "W14 OpenSmash Ultimate is installed in $was, on a disk that is not connected now ($gone)" "W14 OpenSmash Ultimate est installé dans $was, sur un disque qui n'est pas branché ($gone)")
            if ($Mode -eq 'diag') { return $null }      # (the report says so)
            if ((-not $allowClone -or -not (Ask-YesNo (L '  Install OpenSmash Ultimate again somewhere else? (n = stop here, plug the disk in and start again)' '  Réinstaller OpenSmash Ultimate ailleurs ? (n = arrêter ici, brancher le disque et relancer)') $false))) {
                Set-Step 'Folder' 'FAILED' 'disk not connected'; Fail 'E14' (L "OpenSmash Ultimate's disk ($gone) is not connected" "le disque d'OpenSmash Ultimate ($gone) n'est pas branché")
            }
        }
    }
    if (-not $Script:Repo) {
        if (-not $allowClone) { Say (L '  OpenSmash Ultimate is not installed on this PC yet.' '  OpenSmash Ultimate n''est pas encore installé sur ce PC.'); return $null }
        $def = Get-DefaultInstallDir
        while (-not $Script:Repo) {
            Say (L "  Where to install OpenSmash Ultimate? About $NEED_GB GB free are needed, outside OneDrive." "  Où installer OpenSmash Ultimate ? Il faut environ $NEED_GB Go libres, hors OneDrive.")
            $a = "$(Read-Host (L "  Folder [$def] (Enter = OK, B = browse, or type a path)" "  Dossier [$def] (Entrée = OK, P = parcourir, ou tape un chemin)"))".Trim()
            if (-not $a -and -not $def) { $a = 'B' }      # (no default: Browse)
            if (-not $a) { $t = Get-InstallFolder $def $false }
            elseif ($a -match '^[pPbB]$') {
                $f = Pick-Folder (L 'Choose where to install (an OpenSmash-Ultimate folder is made there)' 'Choisis où installer (un dossier OpenSmash-Ultimate y sera créé)')
                if (-not $f) { continue }
                $t = if (Test-RepoDir $f) { $f } else { [IO.Path]::Combine($f, 'OpenSmash-Ultimate') }     # (an OpenSmash Ultimate folder chosen: that one)
                $t = Get-InstallFolder $t $false
            } else { $t = Get-InstallFolder $a $true }
            if (-not $t) { continue }
            if ([IO.Path]::GetPathRoot($t) -eq $t) { $t = [IO.Path]::Combine($t, 'OpenSmash-Ultimate') }     # (a disk typed: a folder on it, as Browse does)
            if ($t -match 'OneDrive') { Warn (L 'W23 not in OneDrive: choose another folder' 'W23 pas dans OneDrive : choisis un autre dossier'); continue }
            $os = Get-OldOpenSmash      # (OpenSmash's folders are its own: never install into them)
            if ($os -and ((Test-Under $t $os.Repo) -or (Test-Under $t $os.Build))) { Warn (L "W13 $t is inside the OpenSmash install (menu 8): choose another folder" "W13 $t est dans l'installation OpenSmash (menu 8) : choisis un autre dossier"); continue }
            if (Test-RepoDir $t) { $Script:Repo = $t; break }          # an OpenSmash Ultimate folder already there: used as it is
            if ((Test-Path -LiteralPath $t) -and (Test-NotEmpty $t)) {
                Warn (L "W13 $t already exists and is not empty: choose another folder" "W13 $t existe déjà et n'est pas vide : choisis un autre dossier"); continue
            }
            try { $free = (New-Object IO.DriveInfo ([IO.Path]::GetPathRoot($t))).AvailableFreeSpace / 1GB } catch { Warn (L "W13 no disk found for $t" "W13 disque introuvable pour $t"); continue }
            if ($free -lt $NEED_GB) { Warn ((L "W22 only {0:N0} GB free on {1}: choose another disk" "W22 seulement {0:N0} Go libres sur {1} : choisis un autre disque") -f $free, [IO.Path]::GetPathRoot($t)); continue }
            $parent = [IO.Path]::GetDirectoryName($t)
            if ($parent -and -not (Test-Path -LiteralPath $parent)) {
                try { New-Item -ItemType Directory -Force $parent -ErrorAction Stop | Out-Null } catch { Warn (L "W13 $parent cannot be made ($($_.Exception.Message)): choose another folder" "W13 impossible de créer $parent ($($_.Exception.Message)) : choisis un autre dossier"); continue }
            }
            $w = if (Test-Path -LiteralPath $t) { $t } else { $parent }
            if ($w -and -not (Test-Writable $w)) { Warn (L "W13 files cannot be written in $w (a protected folder?): choose another folder" "W13 impossible d'écrire dans $w (un dossier protégé ?) : choisis un autre dossier"); continue }
            Clone-Repo $t
            $Script:Repo = $t
        }
    }
    Set-Content -LiteralPath $RepoTxt -Value $Script:Repo -Encoding UTF8
    $Script:Deps = Join-Path $Script:Repo 'dump\_setup'
    $Script:Info['OpenSmash Ultimate folder'] = $Script:Repo
    Say "  $($Script:Repo)"
    if ($Script:Repo -match 'OneDrive') { Set-Step 'Folder' 'FAILED' 'in OneDrive'; Fail 'E23' (L "the folder is in OneDrive: $($Script:Repo)" "le dossier est dans OneDrive : $($Script:Repo)") }
    if ($Script:Repo -match '[^\x20-\x7E]') { Warn (L "W23 the folder's path holds accents or special characters: if something fails, move it to C:\Games\OpenSmash-Ultimate" "W23 le chemin du dossier contient des accents ou caractères spéciaux : en cas d'erreur, déplace-le vers C:\Jeux\OpenSmash-Ultimate") }
    $drive = (Get-Item -LiteralPath $Script:Repo).PSDrive
    if ($drive -and $null -ne $drive.Free) { $freeGB = [math]::Round($drive.Free / 1GB, 1); $Script:Info['Free disk'] = "$freeGB GB on $($drive.Name):" }
    else { $freeGB = [double]::MaxValue; $Script:Info['Free disk'] = 'unknown (no drive letter)' }      # (never a false E22)
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
    Title (L 'OpenSmash Ultimate version' 'Version d''OpenSmash Ultimate')
    if (-not $Script:Git) { $Script:Git = Find-Git }
    if ($Script:Git -and (Test-Path -LiteralPath (Join-Path $Script:Repo '.git'))) {
        Set-GitSafeRepo
        $out = @(Run-Native { & $Script:Git -C $Script:Repo rev-parse HEAD 2>&1 })
        if ($LASTEXITCODE) { Set-Step 'Version' 'FAILED' 'git'; Fail 'E11' "$(L 'git cannot read the OpenSmash Ultimate folder' 'git ne peut pas lire le dossier OpenSmash Ultimate') : $(Get-GitError $out)" }
        $head = "$($out | Select-Object -First 1)".Trim()
        $Script:Info['OpenSmash Ultimate (git)'] = "$head"
        if ($head -eq $WS_COMMIT) { Ok (L "already the right version ($($WS_COMMIT.Substring(0,7)))" "déjà à la bonne version ($($WS_COMMIT.Substring(0,7)))"); Set-Step 'Version' 'OK' 'git'; return }
        $dirty = @(Run-Native { & $Script:Git -C $Script:Repo status --porcelain --untracked-files=no }) | Where-Object { $_ -notmatch 'online_server\.txt$' }
        if ($dirty) { Set-Step 'Version' 'FAILED' 'files changed'; Fail 'E11' "$(L 'files of the folder were changed (git status)' 'des fichiers du dossier ont été modifiés (git status)') : $(($dirty | Select-Object -First 5) -join ', ')" }
        # A WindowSmash folder (kits 1.x to 3.x): its origin becomes the merged repository, where its history goes on.
        # The pinned commit is fetched from $WS_GIT_URL itself, whatever origin is.
        $url = "$(@(Run-Native { & $Script:Git -C $Script:Repo remote get-url origin 2>$null }) | Select-Object -First 1)".Trim()
        if ($url -match $WS_OLD_URL) {
            Say (L '  WindowSmash is now OpenSmash Ultimate: this folder moves to it (your save and settings stay).' '  WindowSmash est maintenant OpenSmash Ultimate : ce dossier passe dessus (ta sauvegarde et tes réglages restent).')
            $out = @(Run-Native { & $Script:Git -C $Script:Repo remote set-url origin $WS_GIT_URL 2>&1 })
            if ($LASTEXITCODE) { Warn "W11 git remote set-url: $(Get-GitError $out)" } else { $Script:Info['git origin'] = "$url -> $WS_GIT_URL" }
        }
        Say (L "  Moving to version $($WS_COMMIT.Substring(0,7)) (branch $WS_BRANCH)..." "  Passage à la version $($WS_COMMIT.Substring(0,7)) (branche $WS_BRANCH)...")
        $out = @(Run-Native { & $Script:Git -C $Script:Repo fetch $WS_GIT_URL $WS_BRANCH 2>&1 })
        if ($LASTEXITCODE) { Set-Step 'Version' 'FAILED' 'git fetch'; Fail 'E11' "$(L 'git fetch failed' 'git fetch a échoué') : $(Get-GitError $out)" }
        $mine = Save-OnlineServer
        Run-Native { & $Script:Git -C $Script:Repo checkout -- online_server.txt }   # (an edit there would block the checkout)
        $out = @(Run-Native { & $Script:Git -C $Script:Repo -c advice.detachedHead=false checkout --detach $WS_COMMIT 2>&1 })
        $rc = $LASTEXITCODE
        Restore-OnlineServer $mine
        if ($rc) { Set-Step 'Version' 'FAILED' 'git checkout'; Fail 'E11' "git checkout $WS_COMMIT $(L 'failed' 'a échoué') : $(Get-GitError $out)" }
        $Script:Info['OpenSmash Ultimate (git)'] = "$WS_COMMIT (was $head)"
        Ok (L 'version updated' 'version mise à jour'); Set-Step 'Version' 'OK' 'git checkout'; return
    }
    $bad = @()
    foreach ($f in $WS_FILES.Keys) {
        $p = Join-Path $Script:Repo $f
        if (-not (Test-Path -LiteralPath $p) -or (Get-NormalizedSha256 $p) -ne $WS_FILES[$f]) { $bad += $f }
    }
    if (-not $bad) { Ok (L 'files at the right version' 'fichiers à la bonne version'); Set-Step 'Version' 'OK' 'files checked'; $Script:Info['OpenSmash Ultimate'] = "copy without git, = $($WS_COMMIT.Substring(0,7))"; return }
    Say (L "  Not the right version ($($bad -join ', ')): updating the files..." "  Pas la bonne version ($($bad -join ', ')) : je mets les fichiers à jour...")
    $mine = Save-OnlineServer
    Get-RepoZip $Script:Repo
    Restore-OnlineServer $mine
    foreach ($f in $WS_FILES.Keys) {
        if ((Get-NormalizedSha256 (Join-Path $Script:Repo $f)) -ne $WS_FILES[$f]) { Set-Step 'Version' 'FAILED' $f; Fail 'E11' (L "$f is not the right version even after the update" "$f n'a pas la bonne version même après mise à jour") }
    }
    $Script:Info['OpenSmash Ultimate'] = "copy without git, updated to $($WS_COMMIT.Substring(0,7))"
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
        Say (L '  Python 3.14 is needed (for the OpenSmash Ultimate tools) and is not installed.' '  Python 3.14 est nécessaire (pour les outils d''OpenSmash Ultimate) et n''est pas installé.')
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

# What a built folder holds of the game files (kits 3.x on): keys\prod.keys, the decrypted base game (dump\game_files or
# dump\base) and the update staged in dump\game_files (a hard link or a copy of the player's .nsp). An update of the game
# needs nothing else, so a player whose original files are gone since (moved, deleted, on an unplugged disk) is not asked
# for them again. $null when something is missing.
function Get-LocalInputs {
    if (-not $Script:Repo) { return $null }
    $k = Join-Path $Script:Repo 'keys\prod.keys'
    if (-not (Test-Path -LiteralPath $k) -or -not (Test-PlainBase)) { return $null }
    $u = Get-ChildItem -LiteralPath (Join-Path $Script:Repo 'dump\game_files') -File -Filter '*.nsp' -ErrorAction SilentlyContinue | Sort-Object Length -Descending | Select-Object -First 1
    if (-not $u) { return $null }
    $t = Join-Path $Script:Repo 'keys\title.keys'
    return @{ update = $u.FullName; prodkeys = $k; titlekeys = $(if (Test-Path -LiteralPath $t) { $t } else { $null }) }
}

function Ask-Inputs {
    Title (L 'Game files (yours, dumped from your console)' 'Fichiers du jeu (les tiens, dumpés de ta console)')
    $prev = Load-Inputs
    $have = { param($p) $p -and (Test-Path -LiteralPath $p) }
    $local = Get-LocalInputs
    if ($local -and -not ($prev -and (& $have $prev.base) -and (& $have $prev.prodkeys))) {
        Say (L "  The game files chosen before are no longer where they were, but this folder holds what the update needs" "  Les fichiers du jeu choisis avant ne sont plus à leur place, mais ce dossier contient ce qu'il faut pour la mise à jour")
        Say (L "  (prod.keys, the decrypted base game, the $EXPECT_VERSION update): using them." "  (prod.keys, le jeu de base déchiffré, la mise à jour $EXPECT_VERSION) : je les utilise.")
        $Script:Inputs = @{ base = $null; update = $local.update; prodkeys = $local.prodkeys; titlekeys = $local.titlekeys
                            dlc = $(if ($prev -and (& $have $prev.dlc)) { $prev.dlc } else { $null }); firmware = $(if ($prev) { $prev.firmware } else { $null }); update_version = $null }
        Log "game files: the folder's own ($($local.update))"
        return
    }
    if ($prev -and (& $have $prev.base) -and (& $have $prev.prodkeys)) {
        # (an update checked as the version needed now is reused; kit 2.x's 13.0.4 one is not: the new one is asked)
        $upd = if ((& $have $prev.update) -and $prev.update_version -eq $EXPECT_VERSION) { $prev.update } else { $null }
        if (-not $upd -and $local) { $upd = $local.update }      # (the one staged at the last build, checked again below)
        Say (L "  Files chosen last time:" "  Fichiers choisis la dernière fois :")
        Say "    $(L 'base game  ' 'jeu de base') : $($prev.base)"
        if ($upd) { Say "    $(L 'update     ' 'mise à jour') : $upd" }
        Say "    prod.keys   : $($prev.prodkeys)"
        if ($prev.dlc) { Say "    DLC         : $($prev.dlc)" }
        if (Ask-YesNo (L '  Use them again?' '  Je les réutilise ?')) {
            $Script:Inputs = @{ base = $prev.base; update = $upd; prodkeys = $prev.prodkeys; titlekeys = $prev.titlekeys; dlc = $prev.dlc; firmware = $prev.firmware; update_version = $prev.update_version }
            if (-not $upd) {
                Say (L "  OpenSmash Ultimate now needs the game's $EXPECT_VERSION update (dumped from your up-to-date Switch)." "  OpenSmash Ultimate demande maintenant la mise à jour $EXPECT_VERSION du jeu (dumpée de ta Switch à jour).")
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
    if (Ask-YesNo (L '  Do you have DLC (fighters) as .nsp/.nsz files in a folder? (optional; for netplay, have the same ones)' '  As-tu des DLC (combattants) en .nsp/.nsz dans un dossier ? (optionnel ; pour le netplay, ayez les mêmes)') $false) {
        $d = Pick-Folder (L 'Choose the folder that holds the DLC (.nsp/.nsz, named as dumped)' 'Choisis le dossier qui contient les DLC (.nsp/.nsz, avec leur nom de dump)')
        if ($d) { $Script:Inputs.dlc = $d }
    }
    Save-Inputs
}

function Check-Inputs {
    Title (L 'Checking the files' 'Vérification des fichiers')
    $keys = Join-Path $Script:Repo 'keys'
    New-Item -ItemType Directory -Force $keys | Out-Null
    $same = { param($a, $b) [IO.Path]::GetFullPath($a) -eq [IO.Path]::GetFullPath($b) }    # (the folder's own keys: no copy over itself)
    if (-not (& $same $Script:Inputs.prodkeys (Join-Path $keys 'prod.keys'))) { Copy-Item -LiteralPath $Script:Inputs.prodkeys -Destination (Join-Path $keys 'prod.keys') -Force }
    if ($Script:Inputs.titlekeys -and -not (& $same $Script:Inputs.titlekeys (Join-Path $keys 'title.keys'))) { Copy-Item -LiteralPath $Script:Inputs.titlekeys -Destination (Join-Path $keys 'title.keys') -Force }
    $Script:Keys = $keys
    $r = Helper-OrFail @('keys', '--keys', $keys) 'E41'
    $Script:Info['prod.keys'] = "{0} keys, generations key_area 0..{1}, titlekek 0..{2}" -f $r.Json.count, (($r.Json.kak_application | Measure-Object -Maximum).Maximum), (($r.Json.titlekek | Measure-Object -Maximum).Maximum)
    Ok (L "prod.keys: $($r.Json.count) keys" "prod.keys : $($r.Json.count) clés")
    foreach ($f in @($Script:Inputs.base, $Script:Inputs.update)) {
        if ($f -and [IO.Path]::GetExtension($f) -in '.nsz', '.xcz') { Set-Step 'Files' 'FAILED' 'compressed'; Fail 'E42' (L "$(Split-Path $f -Leaf) is compressed (.nsz/.xcz): give the uncompressed .nsp/.xci (decompress it with nsz, or dump it again)" "$(Split-Path $f -Leaf) est compressé (.nsz/.xcz) : donne le .nsp/.xci non compressé (décompresse-le avec nsz, ou dumpe-le à nouveau)") }
    }
    $b = $null; $Script:Base = $null
    if ($Script:Inputs.base) {
        $b = Helper-OrFail @('identify', $Script:Inputs.base, '--keys', $keys, '--role', 'base') 'E42'
        $Script:Base = $b.Json
        $Script:Info['Base game'] = "{0} ({1:N1} GB): {2} title {3} version {4}" -f (Split-Path $Script:Inputs.base -Leaf), ((Get-Item -LiteralPath $Script:Inputs.base).Length / 1GB), $b.Json.kind, $b.Json.program, $b.Json.display
        Ok "$(L 'base game' 'jeu de base') : $($b.Json.kind.ToUpper()) version $($b.Json.display)"
    } else {      # (Get-LocalInputs: the decrypted copy made at the last build)
        $Script:Info['Base game'] = 'the decrypted copy in the folder (original file not found)'
        Ok (L 'base game: the decrypted copy in the folder' 'jeu de base : la copie déchiffrée du dossier')
    }
    $u = Helper-OrFail @('identify', $Script:Inputs.update, '--keys', $keys, '--role', 'update', '--expect', $EXPECT_VERSION) 'E43'
    $Script:Info['Update'] = "{0} ({1:N1} GB): version {2} (v{3})" -f (Split-Path $Script:Inputs.update -Leaf), ((Get-Item -LiteralPath $Script:Inputs.update).Length / 1GB), $u.Json.display, $u.Json.title_version
    if ($u.Json.display -ne $EXPECT_VERSION) {   # (OpenSmash Ultimate builds and plays this version only)
        Set-Step 'Files' 'FAILED' "update $($u.Json.display)"
        Fail 'E43' (L "update $($u.Json.display): OpenSmash Ultimate needs $EXPECT_VERSION" "mise à jour $($u.Json.display) : OpenSmash Ultimate demande la $EXPECT_VERSION")
    }
    Ok "$(L 'update' 'mise à jour') : version $($u.Json.display)"
    $Script:Inputs.update_version = $u.Json.display; Save-Inputs
    # space: the decrypted base (unless it is there already), the update's data (~4 GB), the build (~10 GB)
    $drive = (Get-Item -LiteralPath $Script:Repo).PSDrive
    $free = if ($drive) { $drive.Free } else { $null }
    $need = 16GB + $(if (Test-PlainBase) { 0 } else { [int64]$b.Json.program_size })
    if ($null -ne $free -and $free -lt $need -and -not (Test-Path -LiteralPath (Join-Path $Script:Repo 'build\ssbu.exe'))) {
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
    if (-not $Script:Inputs.base -and (Test-PlainBase)) { Ok (L 'base game already decrypted in the folder' 'jeu de base déjà déchiffré dans le dossier'); Set-Step 'Base game' 'OK' 'already there'; return }
    Helper-OrFail @('plain-nca', $Script:Inputs.base, $out, '--keys', $Script:Keys) 'E50' -Live -name 'plain-nca' | Out-Null
    Ok (L 'base game ready (OpenSmash Ultimate reads it in place: no second copy)' 'jeu de base prêt (OpenSmash Ultimate le lit sur place : pas de seconde copie)')
    Set-Step 'Base game' 'OK'
}

function Prepare-Fonts {
    Title (L 'Firmware fonts' 'Polices du firmware')
    $fonts = Join-Path $Script:Repo 'dump\fonts'
    $need = @('nintendo_udsg-r_std_003.bfttf', 'nintendo_udsg-r_org_zh-cn_003.bfttf', 'nintendo_udsg-r_ext_zh-cn_003.bfttf',
              'nintendo_udjxh-db_zh-tw_003.bfttf', 'nintendo_udsg-r_ko_003.bfttf', 'nintendo_ext_003.bfttf')
    $missing = { @($need | Where-Object { -not (Test-Path -LiteralPath (Join-Path $fonts $_)) }) }
    if (-not (& $missing).Count) { Ok (L 'fonts already there' 'polices déjà là'); Set-Step 'Fonts' 'OK' 'already there'; return }
    # Without a firmware the game uses the open fonts of third_party\fonts_open; dump\fonts.none says so, and the build
    # (tools\build_game.py, run without --firmware) then does not ask for one.
    $none = "$fonts.none"
    $openFonts = {
        Warn (L 'W45 no firmware: the game uses open fonts in place of the console''s (other typefaces for Latin text, no Chinese, Japanese or Korean text). Fights are not affected.' 'W45 pas de firmware : le jeu utilise des polices libres à la place de celles de la console (autres polices pour le texte latin, pas de texte chinois, japonais ou coréen). Les combats ne changent pas.')
        New-Item -ItemType Directory -Force (Split-Path $fonts -Parent) | Out-Null
        [IO.File]::WriteAllText($none, "no firmware was given: the game uses the open fonts of third_party/fonts_open; give --firmware to take your firmware's`n")
        Set-Step 'Fonts' 'OK' 'open fonts (no firmware)'
    }
    if ((Test-Path -LiteralPath $none) -and -not ($Script:Inputs.firmware -and (Test-Path -LiteralPath $Script:Inputs.firmware))) {
        Ok (L 'no firmware: the open fonts (as at the last install)' 'pas de firmware : les polices libres (comme à la dernière installation)'); Set-Step 'Fonts' 'OK' 'open fonts'; return
    }
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
        if (-not $src) {
            Say (L '  The game''s fonts come from your console''s firmware (optional: without it, open fonts are used; cancel the window then).' '  Les polices du jeu viennent du firmware de ta console (facultatif : sans lui, des polices libres sont utilisées ; annule la fenêtre dans ce cas).')
            $src = Pick-Folder (L 'Choose your console''s FIRMWARE folder (.nca files: a firmware dump, or an emulator''s registered folder). Cancel: open fonts' 'Choisis le dossier du FIRMWARE de ta console (fichiers .nca : dump du firmware, ou dossier registered d''un émulateur). Annuler : polices libres')
        }
        if (-not $src) { & $openFonts; return }
        $Script:Inputs.firmware = $src; Save-Inputs
    }
    $r = Invoke-Helper @('fonts', $src, $fonts, '--keys', $Script:Keys) -Live -name 'fonts-firmware'
    if ($r.Code -ne 0) {      # (most often a firmware newer than the keys: the build goes on with the open fonts)
        Warn (L "W45 fonts not read from $src ($($r.ErrText))" "W45 polices non lues dans $src ($($r.ErrText))")
        & $openFonts; return
    }
    if (Test-Path -LiteralPath $none) { Remove-Item -LiteralPath $none -Force }
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
    Say (L '  Leave the PC on. If it stops, start OpenSmash Ultimate Launcher again: it carries on where it was.' '  Laisse le PC allumé. Tu peux relancer OpenSmash Ultimate Launcher si ça s''arrête : ça reprend où ça en était.')
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
    if ($Script:Inputs.dlc) {      # (the DLC folder: listed by ws_setup.py after build_game.py, see Add-DLC)
        $n = Get-DlcCount $r
        $Script:Info['DLC'] = "$n in $($Script:Inputs.dlc)"
        if ($n) { Ok (L "$n DLC listed" "$n DLC listés"); Set-Step 'DLC' 'OK' "$n" } else { Set-Step 'DLC' 'SKIPPED' 'none recognised' }
    }
    $exe = Join-Path $Script:Repo 'build\ssbu.exe'
    if ($env:WS_NO_BUILD) { Set-Step 'Compilation' 'TEST' 'skipped (WS_NO_BUILD)'; return }
    if (-not (Test-Path -LiteralPath $exe)) { Set-Step 'Compilation' 'FAILED' 'no exe'; Fail 'E62' (L "$exe not found" "$exe introuvable") }
    try { [IO.File]::WriteAllText((Join-Path $Script:Repo $BUILD_MARK), "$(Get-RepoVersion)`r`n$((Get-Item -LiteralPath $exe).LastWriteTimeUtc.Ticks)`r`n") } catch { Log "build marker: $($_.Exception.Message)" }
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
    Say ((L "  It holds the 13.0.4 game ({0:N1} GB), no longer used: your save was taken over into the OpenSmash Ultimate folder." "  Il contient le jeu en 13.0.4 ({0:N1} Go), qui ne sert plus : ta sauvegarde a été reprise dans le dossier OpenSmash Ultimate.") -f $size)
    if (-not (Ask-YesNo (L '  Delete it? (a copy of its old save stays in save_backups)' '  Je le supprime ? (une copie de son ancienne sauvegarde reste dans save_backups)'))) { Say (L "  Kept: you can delete $old by hand." "  Gardé : tu peux supprimer $old à la main."); return }
    $oldSave = Join-Path $old 'save'
    if (Test-Path -LiteralPath $oldSave) {
        $bk = Join-Path $Script:Repo "save_backups\$OLD_TREE-save-$Stamp"
        New-Item -ItemType Directory -Force $bk | Out-Null
        Get-ChildItem -LiteralPath $oldSave -Force | Copy-Item -Destination $bk -Recurse -Force
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
        $launcher = Join-Path (Split-Path $PSScriptRoot -Parent) $NEW_BAT
        $exe = Join-Path $Script:Repo 'build\ssbu.exe'
        foreach ($dir in @($Desktop, [Environment]::GetFolderPath('Programs'))) {
            try {
                $sh = New-Object -ComObject WScript.Shell
                $lnk = $sh.CreateShortcut((Join-Path $dir $PLAY_LNK))
                if (Test-Path -LiteralPath $launcher) {       # through the launcher: updates checked at every start
                    $lnk.TargetPath = $launcher; $lnk.Arguments = 'play'; $lnk.WorkingDirectory = (Split-Path $launcher -Parent)
                } else {
                    $lnk.TargetPath = $play; $lnk.WorkingDirectory = $Script:Repo
                }
                if (Test-Path -LiteralPath $exe) { $lnk.IconLocation = "$exe,0" }
                $lnk.Save()
                if (Test-Path -LiteralPath $launcher) {
                    $l2 = $sh.CreateShortcut((Join-Path $dir $MENU_LNK))
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
        Say "  Pour jouer : le raccourci 'Smash Ultimate (OpenSmash Ultimate)' (il vérifie les mises à jour à chaque lancement)."
        Say "  Menu (installer, jouer, diagnostic, débloquer, optimiser, DLC, langue) : le raccourci 'OpenSmash Ultimate Launcher'."
        Say '  Au lancement, une fenêtre montre la version du jeu et les réglages (affichage, en ligne, manettes) :'
        Say '  bouton Play pour jouer. Pendant le jeu, Échap ouvre le menu des réglages.'
        Say '  En ligne : le lobby public ; dans le jeu, Local Wireless liste les rooms de tous les joueurs de la même'
        Say '  version (aucun port à ouvrir), et Online > Smash > Quickplay cherche des adversaires (en test).'
        Say '  Rollback : activé par défaut en ligne (Quickplay et rooms Local Wireless à 2, quand l''autre joueur l''a aussi) ;'
        Say '  sans rollback : Échap > Online > Rollback netcode off.'
        Say '  Rooms entre amis seulement : dans la fenêtre du jeu, "Private lobby" et le même code chez tout le monde.'
        Say '  FPS : si les shaders n''ont pas été précompilés, relance OpenSmash Ultimate Launcher et choisis 5).'
        Say '  Clavier : flèches = stick, Z/X/C/V = A/B/X/Y, A/S = L/R, Q/W = ZL/ZR, Entrée = +, F1 = infos.'
        Say '  Tous les personnages sont débloqués par le launcher (dès la fin de la première partie : laisse sa fenêtre ouverte).'
        Say "  Un rapport (réussite) est sur le Bureau : OpenSmash-Ultimate-setup-report.txt"
    } else {
        Say "  To play: the 'Smash Ultimate (OpenSmash Ultimate)' shortcut (it checks for updates at every start)."
        Say "  Menu (install, play, diagnosis, unlock, optimize, DLC, language): the 'OpenSmash Ultimate Launcher' shortcut."
        Say '  At start, a window shows the game version and the settings (display, online, controllers):'
        Say '  Play button to play. While playing, Esc opens the settings menu.'
        Say '  Online: the public lobby; in the game, Local Wireless lists the rooms of every player of the same'
        Say '  version (no port to open), and Online > Smash > Quickplay looks for opponents (being tested).'
        Say '  Rollback: on by default online (Quickplay and 1-on-1 Local Wireless rooms, when the other player has it too);'
        Say '  without it: Esc > Online > Rollback netcode off.'
        Say '  Rooms for friends only: in the game window, "Private lobby" and the same code for everyone.'
        Say '  FPS: if the shaders were not precompiled, start OpenSmash Ultimate Launcher again and choose 5).'
        Say '  Keyboard: arrows = stick, Z/X/C/V = A/B/X/Y, A/S = L/R, Q/W = ZL/ZR, Enter = +, F1 = info.'
        Say '  Every fighter is unlocked by the launcher (from the end of the first game: leave its window open).'
        Say "  A report (success) is on the Desktop: OpenSmash-Ultimate-setup-report.txt"
    }
    if (Ask-YesNo (L '  Start the game now?' '  Je lance le jeu maintenant ?')) { Start-Game }
}

# ---- smoother play: display latency 1, shaders compiled ahead of time ---------------------------
# Where the game reads a settings file (runtime/config_folder.h; tools/launcher.ps1's Get-ConfigPath): config\ once the
# game has made it (config\version.ini, at the first start of a build that has it, which copies the old files in), else
# the game folder; online_server.txt is config\'s only once there is one there.
function Get-ConfigPath([string]$name) {
    $cfg = Join-Path $Script:Repo 'config'
    $in = Join-Path $cfg $name
    if (-not (Test-Path -LiteralPath (Join-Path $cfg 'version.ini') -PathType Leaf) -or
        ($name -eq 'online_server.txt' -and -not (Test-Path -LiteralPath $in -PathType Leaf))) { return (Join-Path $Script:Repo $name) }
    return $in
}

function Set-Latency1 {
    $f = Get-ConfigPath 'display.ini'
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
    Say (L '  You can close the window to stop: start OpenSmash Ultimate Launcher again and choose 5) to carry on.' '  Tu peux fermer la fenêtre pour arrêter : relance OpenSmash Ultimate Launcher et choisis 5) pour reprendre où ça en était.')
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

# Every fighter unlocked in the game's save (tools/unlock_all.py, through ws_setup.py): by hand (menu 4), or by itself
# ($auto) after the install and around every start of the game. unlock_all adds only what is missing and keeps a copy of
# the save from before in save_backups when it changes it, so running it every time costs nothing. Without a save yet,
# Start-Game waits for the game's end (the first start writes the save) and unlocks then. $auto never stops the kit.
function Unlock-Fighters([bool]$auto = $false) {
    if (-not $auto) { Title (L 'Unlocking every fighter' 'Déblocage de tous les personnages'); $null = Find-Repo $false }
    if (-not $Script:Repo -or -not (Test-Path -LiteralPath (Join-Path $Script:Repo 'build\ssbu.exe'))) {
        if (-not $auto) { Say (L "  The game is not installed in $EXPECT_VERSION yet: choose 1) Install." "  Le jeu n'est pas encore installé en $EXPECT_VERSION : choisis 1) Installer.") }
        return
    }
    $Script:VenvPy = Join-Path $Script:Repo '.venv\Scripts\python.exe'
    if ($auto) {
        if ($env:WS_NO_BUILD -or -not (Test-Path -LiteralPath (Join-Path $Script:Repo "$SAVE_DIR\save_data\system_data.bin")) -or
            -not (Test-Path -LiteralPath $Script:VenvPy) -or (Get-Process ssbu -ErrorAction SilentlyContinue)) { return }
        $r = Invoke-Helper @('unlock')
        if ($r.Code -ne 0) { Log "auto unlock: code $($r.Code) $($r.ErrText)"; return }
        if ($r.Lines | Where-Object { $_ -match '^unlocking \d+' }) {
            foreach ($l in $r.Lines) { if ($l -notlike '@@*' -and $l -notmatch '^game version') { Say "  $l" } }
            Ok (L 'every fighter unlocked (a copy of the save from before is in save_backups)' 'tous les personnages débloqués (une copie de la sauvegarde d''avant est dans save_backups)')
        }
        return
    }
    if (Get-Process ssbu -ErrorAction SilentlyContinue) { Fail 'E80' (L 'the game is running: close it first (it rewrites its save when it quits)' 'le jeu tourne : ferme-le d''abord (il réécrit sa sauvegarde en quittant)') }
    $r = Invoke-Helper @('unlock')
    foreach ($l in $r.Lines) { if ($l -notlike '@@*') { Say "  $l" } }
    if ($r.Code -ne 0) { $t = if ($r.ErrText) { $r.ErrText } else { "code $($r.Code)" }; Fail 'E80' $t }
    Ok (L 'fighters unlocked (a copy of the save from before is in save_backups)' 'personnages débloqués (une copie de la sauvegarde d''avant est dans save_backups)')
    Set-Step 'Unlock' 'OK'
}

# The DLC a player bought, dumped from their own Switch. As the OpenSmash launcher did, each DLC's id is read from its
# file name as dumped ("... [01006A800016F041][v0].nsp": nxdumptool, DBI; .nsz too) and the DLC are listed in
# dump\modules\aoc.cfg, which the game reads at its start (ws_setup.py dlc; the packages' metadata adds a renamed one
# where prod.keys opens it). No key, ticket or update is needed and nothing is compiled: the DLC's fighters, stages and
# outfits are in every 13.0.5 build already (data.arc). Kits 3.0-4.1 rebuilt the game and had build_game.py read the
# packages' metadata only: a dump it could not open counted for nothing ("no Smash Ultimate DLC recognised"). Only the
# DLC in the folders given count: nothing here unlocks one that isn't there. A second folder adds to the list (as the
# OpenSmash launcher's did). The last folder is kept in inputs.json, so that a later build lists it again.
function Add-DLC {
    Title (L 'Add your DLC (dumped from your Switch)' 'Ajouter tes DLC (dumpés de ta Switch)')
    $null = Find-Repo $false
    if (-not $Script:Repo -or -not (Test-Path -LiteralPath (Join-Path $Script:Repo 'build\ssbu.exe'))) { Say (L "  The game is not installed in $EXPECT_VERSION yet: choose 1) Install." "  Le jeu n'est pas encore installé en $EXPECT_VERSION : choisis 1) Installer."); return }
    $Script:Keys = Join-Path $Script:Repo 'keys'
    $Script:VenvPy = Join-Path $Script:Repo '.venv\Scripts\python.exe'
    if (-not (Test-Path -LiteralPath $Script:VenvPy)) { Fail 'E40' (L 'install incomplete: choose 1) Install' 'installation incomplète : choisis 1) Installer') }
    Say (L '  The DLC (fighters, outfits, spirits) are the ones you bought, dumped from your Switch (nxdumptool, DBI):' '  Les DLC (combattants, costumes, esprits) sont ceux que tu as achetés, dumpés de ta Switch (nxdumptool, DBI) :')
    Say (L '  .nsp or .nsz files, named as dumped (the name holds the DLC id, 01006A800016F...). To play online together, have the same DLC.' '  fichiers .nsp ou .nsz, avec leur nom de dump (il contient l''identifiant du DLC, 01006A800016F...). Pour jouer en ligne ensemble, ayez les mêmes DLC.')
    $d = Pick-Folder (L 'Choose the folder that holds your DLC (.nsp dumped from your Switch)' 'Choisis le dossier qui contient tes DLC (.nsp dumpés de ta Switch)')
    if (-not $d) { Say (L '  No folder chosen: nothing changed.' '  Aucun dossier choisi : rien n''a changé.'); return }
    $r = Invoke-Helper @('dlc', '--dir', $d, '--keys', $Script:Keys) -Live -name 'dlc'
    if ($r.Code -ne 0) {
        $c = if ($r.ErrCode) { $r.ErrCode } else { 'E54' }
        $t = if ($r.ErrText) { $r.ErrText } else { L "stopped (code $($r.Code))" "arrêt (code $($r.Code))" }
        Set-Step 'DLC' 'FAILED' $c
        Fail $c $t
    }
    $n = Get-DlcCount $r
    $prev = Load-Inputs
    $Script:Inputs = @{}
    if ($prev) { foreach ($p in $prev.PSObject.Properties) { $Script:Inputs[$p.Name] = $p.Value } }
    $Script:Inputs['dlc'] = $d
    Save-Inputs
    $Script:Info['DLC'] = "$n in $d"
    Ok (L "DLC added: $n in the list, they show at the next start of the game" "DLC ajoutés : $n dans la liste, ils apparaissent au prochain lancement du jeu")
    if (Get-Process ssbu -ErrorAction SilentlyContinue) { Say (L '  The game is running: close it and start it again to see them.' '  Le jeu tourne : ferme-le et relance-le pour les voir.') }
    Set-Step 'DLC' 'OK' "$n"
}

# The number of DLC ws_setup.py listed ("@@DLC <n>"), 0 when it listed none.
function Get-DlcCount($r) {
    $l = $r.Lines | Where-Object { $_ -like '@@DLC *' } | Select-Object -Last 1
    if ($l -and $l.Substring(6).Trim() -match '^\d+$') { return [int]$Matches[0] }
    return 0
}

function Ensure-OnlineName {
    $f = Get-ConfigPath 'online_name.txt'
    if (Test-Path -LiteralPath $f) { return }
    $def = 'Player' + (Get-Random -Minimum 1000 -Maximum 9999)
    $n = Read-Host (L "  Your online name (seen by the other players) [$def]" "  Ton pseudo en ligne (vu par les autres joueurs) [$def]")
    if (-not $n) { $n = $def }
    $n = ($n -replace '[^A-Za-z0-9_\- ]', '').Trim()
    if (-not $n) { $n = $def }
    [IO.File]::WriteAllText($f, "$n`r`n", (New-Object Text.ASCIIEncoding))
    Ok (L "name: $n (can be changed in online_name.txt)" "pseudo : $n (modifiable dans online_name.txt)")
}

# The game folder's tools\launcher.ps1 (since WindowSmash 9c1b250) opens the game's own window first (game version,
# display, online and controller settings); the game starts when Play is clicked there, so it may start long after this
# call, and the window can also be closed without playing (exit code 0, nothing started). With "start the game directly"
# ticked in it the game starts at once; when the window cannot open (exit code 2) the game is started here, as
# Play SSBU.bat does. The kit starts that window itself, not Play SSBU.bat: since the merge, Play SSBU.bat starts
# OpenSmash.exe instead when the folder has one (upstream's own launcher, which updates the game past the group's
# version). Whether the game was started is told by its log: every way of starting it writes build\play.log anew.
# Rollback: since 6c38207 the game started online (--online, as the window starts it) plays Quickplay and 1-on-1 Local
# Wireless room matches with rollback when both games have it (runtime/hle_rb_core.c, net_relay.c net_rollback_default),
# unless online_rollback.txt says off (Esc > Online > Rollback netcode). Every SSBU_RB* variable goes, so that this
# default and that setting count (kits 4.0-4.2's option 3 set SSBU_RB=1, SSBU_RB_NET=relay, SSBU_RB_NET_LIVE=1), and the
# netplay variables Play SSBU.bat clears go too.
function Test-VisibleWindow([int]$id) {
    <# Whether process $id shows a top-level window, owned or not (Process.MainWindowHandle skips owned ones); $true
       when this cannot be told, so that nothing is stopped on a guess. #>
    try {
        if (-not ('WsSetup.Win' -as [type])) {
            Add-Type -Namespace WsSetup -Name Win -MemberDefinition @'
[DllImport("user32.dll")] static extern IntPtr FindWindowEx(IntPtr parent, IntPtr after, string cls, string title);
[DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
[DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
public static bool Shows(int id) {
    IntPtr h = IntPtr.Zero;
    while ((h = FindWindowEx(IntPtr.Zero, h, null, null)) != IntPtr.Zero) {
        uint p; GetWindowThreadProcessId(h, out p);
        if (p == (uint)id && IsWindowVisible(h)) return true;
    }
    return false;
}
'@
        }
        return [WsSetup.Win]::Shows($id)
    } catch { return $true }
}

function Start-Game {
    $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $log = Join-Path $Script:Repo 'build\play.log'
    Ensure-OnlineName
    $hadSave = Test-Path -LiteralPath (Join-Path $Script:Repo "$SAVE_DIR\save_data\system_data.bin")
    Unlock-Fighters $true
    foreach ($v in @('SSBU_DATA_ROOT', 'SSBU_INPUT', 'SSBU_NET_HOST', 'SSBU_NET_RELAY', 'SSBU_NET_BIND', 'SSBU_NET_ROOM', 'SSBU_NET_NAME', 'SSBU_NET_DIRECT', 'SSBU_NET_PORT')) {
        Remove-Item -LiteralPath "Env:$v" -ErrorAction SilentlyContinue
    }
    foreach ($v in @(Get-ChildItem Env: | Where-Object { $_.Name -like 'SSBU_RB*' } | ForEach-Object { $_.Name })) { Remove-Item -LiteralPath "Env:$v" }
    Say (L '  Rollback netcode: on by default online (Quickplay and 1-on-1 Local Wireless rooms, when the other player has it too; Esc > Online > Rollback netcode turns it off).' '  Rollback : activé par défaut en ligne (Quickplay et rooms Local Wireless à 2, quand l''autre joueur l''a aussi ; Échap > Online > Rollback netcode le désactive).')
    Log 'start'
    $launcher = Join-Path $Script:Repo 'tools\launcher.ps1'
    try {
        $t0 = Get-Date
        $watch = Test-Path -LiteralPath $launcher
        if ($watch) {
            # No console and no show flag. Kit 4.1 started it with -WindowStyle Hidden: Windows then opens the process's
            # first window hidden too, so launcher.ps1's window stayed invisible on every PC without show_launcher = 0
            # and the game never started (Play SSBU.bat, from a visible console, worked).
            $si = New-Object Diagnostics.ProcessStartInfo
            $si.FileName = $ps
            $si.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + $launcher + '" -Auto'
            $si.WorkingDirectory = $Script:Repo
            $si.UseShellExecute = $false
            $si.CreateNoWindow = $true
            $p = [Diagnostics.Process]::Start($si)
        } else {      # (a folder still at kit 2.0-2.2's WindowSmash, 13.0.4: its Play SSBU.bat picks the version folder)
            $p = Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\cmd.exe') -ArgumentList '/c', ('""' + (Join-Path $Script:Repo 'Play SSBU.bat') + '""') -WorkingDirectory ([Management.Automation.WildcardPattern]::Escape($Script:Repo)) -PassThru
        }
        $null = $p.Handle      # (Windows PowerShell 5.1 loses the exit code of a process whose handle was never asked for)
        Say (L '  The game window opens (game version, display, online, controllers): click Play to play.' '  La fenêtre du jeu s''ouvre (version du jeu, affichage, en ligne, manettes) : clique sur Play pour jouer.')
        $noWindow = $false
        while (-not $p.HasExited -and -not (Get-Process ssbu -ErrorAction SilentlyContinue)) {
            Start-Sleep -Milliseconds 500
            if (-not $watch) { continue }
            if (Test-VisibleWindow $p.Id) { $watch = $false; continue }      # (its window is up: the player takes their time)
            if (((Get-Date) - $t0).TotalSeconds -ge 60) {      # (no window after a minute: the game starts as Play SSBU.bat starts it without one)
                try { $p.Kill() } catch { }
                $noWindow = $true
                break
            }
        }
        if ($noWindow -or ($p.HasExited -and $p.ExitCode -eq 2 -and (Test-Path -LiteralPath $launcher))) {      # (the window could not open: the game as Play SSBU.bat then starts it)
            Log "launcher.ps1: no window ($(if ($noWindow) { 'none after 60 s' } else { 'exit 2' })): the game started directly"
            Say (L '  The game window did not open: the game starts directly (your last settings).' '  La fenêtre du jeu ne s''est pas ouverte : le jeu démarre directement (tes derniers réglages).')
            $t0 = Get-Date
            Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\cmd.exe') -ArgumentList '/c', 'build\ssbu.exe dump\modules --status 30 --online > build\play.log 2>&1' -WorkingDirectory ([Management.Automation.WildcardPattern]::Escape($Script:Repo)) -WindowStyle Minimized
        }
        for ($i = 0; $i -lt 10 -and -not (Get-Process ssbu -ErrorAction SilentlyContinue); $i++) { Start-Sleep -Seconds 1 }
        if (-not (Get-Process ssbu -ErrorAction SilentlyContinue)) {
            if ((Test-Path -LiteralPath $log) -and (Get-Item -LiteralPath $log).LastWriteTime -ge $t0) { Fail 'E70' (L 'the game closed at once' "le jeu s'est fermé tout de suite") $log }
            if ($p.HasExited -and $p.ExitCode -eq 0) { Say (L '  Window closed without starting the game.' '  Fenêtre fermée sans lancer le jeu.'); return }
            $rc = if ($p.HasExited) { "code $($p.ExitCode)" } else { L 'still open' 'toujours ouvert' }
            Fail 'E70' (L "the game did not start (tools\launcher.ps1: $rc)" "le jeu n'a pas démarré (tools\launcher.ps1 : $rc)") $log
        }
        Start-Sleep -Seconds 15
        if (-not (Get-Process ssbu -ErrorAction SilentlyContinue)) { Fail 'E70' (L 'the game closed at once' "le jeu s'est fermé tout de suite") $log }
        Ok (L 'game started (the first time, the screen may stay black during the intro movie)' 'jeu lancé (la première fois, l''écran peut rester noir pendant la vidéo d''intro)')
    } catch { Fail 'E70' "$($_.Exception.Message)" }
    if (-not $hadSave -and (Test-Path -LiteralPath (Join-Path $Script:Repo 'build\ssbu.exe'))) {     # (the first start writes the save: every fighter unlocked in it once the game is closed)
        Say (L '  Leave this window open: when you close the game, every fighter gets unlocked in its new save.' '  Laisse cette fenêtre ouverte : quand tu fermeras le jeu, tous les personnages seront débloqués dans sa nouvelle sauvegarde.')
        while (Get-Process ssbu -ErrorAction SilentlyContinue) { Start-Sleep -Seconds 2 }
        Start-Sleep -Seconds 2
        Unlock-Fighters $true
    }
}

# ---- the OpenSmash install (OpenSmash = ssbu-recomp: kit-opensmash 1.x, then kit-opensmash\os_kit.ps1, menu 8) -------
# Its folder (opensmash-repo.txt) is a clone of github.com/OpenSmash-Ultimate/ssbu-recomp; its game is in <folder>\build
# or in the folder build_location.txt names. The game's save there is <build>\saves\save\save_data: the same files as
# save\<user>\save_data here (both are the game's own, 13.0.5). It comes over to a new install that has no save. Kits
# 4.0-4.2 offered to delete that install (keeping its save in save_backups\opensmash-save-* or $OsSaveKeep); since 4.4
# it stays beside OpenSmash Ultimate.
function Get-OldOpenSmash {
    if (-not (Test-Path -LiteralPath $OsRepoTxt)) { return $null }
    $r = "$(Get-Content -LiteralPath $OsRepoTxt -TotalCount 1 -Encoding UTF8)".Trim()
    if (-not $r -or -not (Test-Path -LiteralPath ([IO.Path]::Combine($r, 'scripts\install.py')))) { return $null }   # (Join-Path fails on a drive that is not there)
    $b = [IO.Path]::Combine($r, 'build')
    $loc = [IO.Path]::Combine($r, 'build_location.txt')
    if (Test-Path -LiteralPath $loc) {
        $p = "$(Get-Content -LiteralPath $loc -TotalCount 1 -Encoding UTF8)".Trim().Trim('"')
        if ($p) { $p = [Environment]::ExpandEnvironmentVariables($p); if (-not [IO.Path]::IsPathRooted($p)) { $p = [IO.Path]::Combine($r, $p) }; $b = $p }
    }
    $b = if ($b -match '^[A-Za-z]:\\*$') { $b.Substring(0, 2) + '\' } else { $b.TrimEnd('\') }    # (a drive root stays 'D:\', never 'D:')
    return [pscustomobject]@{ Repo = (Get-CleanFolder $r); Build = $b; Save = [IO.Path]::Combine($b, 'saves\save') }   # (Join-Path fails on a drive that is not there)
}

# $true when the old install's build folder lies on a disk that is not there now (an unplugged USB disk)
function Test-OldBuildGone($os) { return -not (Test-Path -LiteralPath ([IO.Path]::GetPathRoot($os.Build))) }

# $true when OpenSmash is installed and its game built (os_kit.ps1's Get-Exe)
function Test-OpenSmashBuilt {
    $os = Get-OldOpenSmash
    if (-not $os -or (Test-OldBuildGone $os)) { return $false }
    return (Test-Path -LiteralPath ([IO.Path]::Combine($os.Build, 'work\ssbu_native.exe')))
}

# OpenSmash's kit (kit-opensmash\os_kit.ps1) for an os* mode, in a PowerShell of its own in this console (its functions
# and settings share many names with this file's). -> its exit code: 0, 10 (a failure it reported), 3 (back to the menu)
# Started as a process that inherits this console's handles: '& powershell.exe' inside a function whose output is
# assigned would capture the child's whole screen (its menu would only show once it ended), and Start-Process -Wait
# would also wait for the game it starts.
function Invoke-OsKit([string]$mode) {
    $kit = Join-Path (Split-Path $PSScriptRoot -Parent) 'kit-opensmash\os_kit.ps1'
    if (-not (Test-Path -LiteralPath $kit -PathType Leaf)) {      # (an antivirus may have taken it: the clone's git has it)
        $lc = Split-Path $PSScriptRoot -Parent; $g = Find-Git
        if ($g -and (Test-Path -LiteralPath (Join-Path $lc '.git'))) { $out = @(Run-Native { & $g -C $lc checkout -- 'kit-opensmash/os_kit.ps1' 2>&1 }); Log "OpenSmash kit missing, git checkout: $($out -join ' ')" }
        if (-not (Test-Path -LiteralPath $kit -PathType Leaf)) { Log "OpenSmash kit missing: $kit"; Fail 'E99' (L "OpenSmash's part of the launcher is missing ($kit; an antivirus may have removed it): send the report." "La partie OpenSmash du launcher manque ($kit ; un antivirus l'a peut-être supprimée) : envoie le rapport.") }
    }
    $sub = $mode -replace '^os-?', ''
    Log "OpenSmash: $kit -Mode '$sub'"
    $argv = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $kit, '-KitVersion', $KitVersion, '-KitDir', $KitDir)
    if ($sub) { $argv += @('-Mode', $sub) }
    $q = foreach ($a in $argv) {      # (the command line rules: a quoted argument's backslashes before a quote are doubled)
        if ($a -and $a -notmatch '[\s"]') { $a } else { '"' + (($a -replace '(\\*)"', '$1$1\"') -replace '(\\+)$', '$1$1') + '"' }
    }
    $psi = New-Object Diagnostics.ProcessStartInfo (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe')
    $psi.Arguments = $q -join ' '
    $psi.UseShellExecute = $false
    $psi.WorkingDirectory = (Get-Location).Path
    try { $p = [Diagnostics.Process]::Start($psi); $p.WaitForExit(); $rc = $p.ExitCode }
    catch { Log "OpenSmash kit not started: $($_.Exception.Message)"; Fail 'E99' (L "OpenSmash's part did not start: $($_.Exception.Message)" "La partie OpenSmash n'a pas démarré : $($_.Exception.Message)") }
    Log "OpenSmash kit: exit $rc"
    return $rc
}

# A save folder copied whole, then counted: $true when every file came over.
function Copy-Save([string]$from, [string]$to) {
    New-Item -ItemType Directory -Force $to | Out-Null
    Get-ChildItem -LiteralPath $from -Force | Copy-Item -Destination $to -Recurse -Force
    $n1 = @(Get-ChildItem -LiteralPath $from -Recurse -File -Force).Count
    $n2 = @(Get-ChildItem -LiteralPath $to -Recurse -File -Force).Count
    return ($n2 -ge $n1)
}

function Import-OpenSmashSave {
    $dst = Join-Path $Script:Repo $SAVE_DIR
    if (Test-Path -LiteralPath (Join-Path $dst 'save_data\system_data.bin')) { return }       # a save of its own: kept
    $os = Get-OldOpenSmash; $src = $null
    if ($os -and (Test-OldBuildGone $os)) {
        Warn (L "W90 the OpenSmash game folder $($os.Build) is not reachable (its disk is unplugged?): its save is not taken over yet. Plug the disk in and choose 1) Install again." "W90 le dossier du jeu OpenSmash $($os.Build) est inaccessible (son disque est débranché ?) : sa sauvegarde n'est pas encore reprise. Branche le disque et choisis à nouveau 1) Installer.")
        return
    }
    if ($os -and (Test-Path -LiteralPath (Join-Path $os.Save 'save_data\system_data.bin'))) {
        if (Test-Path -LiteralPath "$($os.Save).commit") {      # (its game stopped while writing it: the save is half old, half new)
            Warn (L "W90 the OpenSmash save was being written when its game stopped: not taken over (it stays in $($os.Save))" "W90 la sauvegarde OpenSmash était en cours d'écriture quand son jeu s'est arrêté : pas reprise (elle reste dans $($os.Save))")
            return
        }
        $src = $os.Save
    } elseif (Test-Path -LiteralPath (Join-Path $OsSaveKeep 'save_data\system_data.bin')) { $src = $OsSaveKeep }
    if (-not $src) { return }
    Title (L 'Your OpenSmash save' 'Ta sauvegarde OpenSmash')
    if (-not (Copy-Save $src $dst)) { Warn (L "W90 the OpenSmash save did not fully come over: it stays in $src" "W90 la sauvegarde OpenSmash n'a pas été entièrement reprise : elle reste dans $src"); return }
    Ok (L "save taken over from OpenSmash (fighters, Miis, spirits, stages): $src" "sauvegarde reprise d'OpenSmash (personnages, Mii, esprits, stages) : $src")
    Set-Step 'OpenSmash save' 'OK' 'taken over'
}

# ---- the launcher's own files: kit 4.0 renamed the launcher --------------------------------------------------------
# The launcher file cmd.exe is running (WSL_SELF, set by the .bat) cannot be deleted while it runs: cmd.exe opens it
# again at each "exit /b" of its block and, finding it gone, prints "The batch file cannot be found" and carries on into
# the error lines. A hidden PowerShell deletes it once that cmd.exe (the parent of this PowerShell: the bootstrap and
# this kit run inside the PowerShell the .bat started) has closed, and only if it still holds the new launcher.
function Remove-WhenClosed([string]$path, [string]$sha) {
    $cmdPid = [int](Get-CimInstance Win32_Process -Filter "ProcessId=$PID" -ErrorAction Stop).ParentProcessId
    if (-not $cmdPid) { throw 'no parent process' }
    # (the path goes through the environment, not the script text: any quote or character in a folder name is safe)
    $s = "try { Wait-Process -Id $cmdPid -ErrorAction Stop } catch {}; Start-Sleep -Seconds 1; `$q = `$env:WSL_DELETE; " +
         "if ((Test-Path -LiteralPath `$q -PathType Leaf) -and (Get-FileHash -LiteralPath `$q -Algorithm SHA256).Hash -eq '$sha') { Remove-Item -LiteralPath `$q -Force }"
    $enc = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($s))
    $env:WSL_DELETE = $path
    try { Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') -ArgumentList @('-NoProfile', '-NonInteractive', '-WindowStyle', 'Hidden', '-EncodedCommand', $enc) -WindowStyle Hidden }
    finally { Remove-Item Env:WSL_DELETE -ErrorAction SilentlyContinue }
    Log "launcher file deleted once cmd.exe $cmdPid has closed: $path"
}

# The players' launcher file was "WindowSmash Launcher.bat" or "OpenSmash Launcher.bat", in a folder of their own
# (Desktop, Downloads...); since kit 4.0 it is "OpenSmash Ultimate Launcher.bat". An old copy's bootstrap refreshes it in
# place with the repository's file of the same name (which the repository keeps, as a copy of the new file), then runs
# this kit with -KitDir = that copy's folder: there any other name holding the new file ("WindowSmash Launcher (1).bat"
# too) becomes the new name. A file that differs (one its update could not refresh) stays as it is. An old launcher file
# on the Desktop or in Downloads that did not start this run (the player used a shortcut) is replaced by the new file
# under the new name. The clone of the repository keeps every name. The shortcuts the kits made (Desktop, Start menu) on
# the clone's old names are made again on the new one, under the new names; the player's own shortcuts to a renamed file
# (Desktop, Start menu, taskbar) are pointed at its new name.
function Update-LauncherFiles {
    $clone = (Split-Path $PSScriptRoot -Parent).TrimEnd('\')
    $new = Join-Path $clone $NEW_BAT
    if (-not (Test-Path -LiteralPath $new -PathType Leaf)) { return }
    $want = Get-FileSha256 $new
    $renamed = @{}      # old full path -> new full path
    $rename = {
        param([string]$p, [string]$dir)
        $dst = Join-Path $dir $NEW_BAT
        if (-not (Test-Path -LiteralPath $dst -PathType Leaf) -or (Get-FileSha256 $dst) -ne $want) { Copy-Item -LiteralPath $new -Destination $dst -Force }
        if ($env:WSL_SELF -and [IO.Path]::GetFullPath($env:WSL_SELF) -eq [IO.Path]::GetFullPath($p)) { Remove-WhenClosed $p (Get-FileSha256 $p).ToUpper() }
        else { Remove-Item -LiteralPath $p -Force }
        $renamed[[IO.Path]::GetFullPath($p)] = $dst
        Say (L "  Launcher renamed: $(Split-Path $p -Leaf) -> $NEW_BAT ($dir)" "  Launcher renommé : $(Split-Path $p -Leaf) -> $NEW_BAT ($dir)")
    }
    $kitDirFull = $null
    if ($KitDir -and (Test-Path -LiteralPath $KitDir -PathType Container)) {
        $dir = (Resolve-Path -LiteralPath $KitDir).Path.TrimEnd('\')
        if ($dir -ne $clone) {
            $kitDirFull = $dir
            $newLen = (Get-Item -LiteralPath $new).Length
            foreach ($f in @(Get-ChildItem -LiteralPath $dir -File -Filter '*.bat' -ErrorAction SilentlyContinue)) {
                if ($f.Name -eq $NEW_BAT) { continue }
                if ($OLD_BATS -notcontains $f.Name -and $f.Length -ne $newLen) { continue }
                if ((Get-FileSha256 $f.FullName) -ne $want) { if ($OLD_BATS -contains $f.Name) { Log "launcher file kept (not the new file): $($f.FullName)" }; continue }
                try { & $rename $f.FullName $dir } catch { Log "launcher file not renamed: $($f.FullName) ($($_.Exception.Message))" }
            }
        }
    }
    foreach ($dir in @(@($Desktop, $Downloads) | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Container) })) {
        $dir = (Resolve-Path -LiteralPath $dir).Path.TrimEnd('\')
        if ($dir -eq $clone -or $dir -eq $kitDirFull) { continue }
        foreach ($old in $OLD_BATS) {
            $p = Join-Path $dir $old
            if (-not (Test-Path -LiteralPath $p -PathType Leaf) -or (Get-Item -LiteralPath $p).Length -gt 1MB) { continue }
            $text = [IO.File]::ReadAllText($p)
            if ($text -notmatch '#@@BEGIN boot\.ps1' -or $text -notmatch 'WindowSmashLauncher') { Log "launcher file kept (not a launcher): $p"; continue }
            try { & $rename $p $dir } catch { Log "launcher file not renamed: $p ($($_.Exception.Message))" }
        }
    }
    $sh = New-Object -ComObject WScript.Shell
    $programs = [Environment]::GetFolderPath('Programs')
    if ($renamed.Count) {      # the player's own shortcuts to a renamed file
        $lnks = @(foreach ($d in @($Desktop, $TaskbarPins)) { if ($d -and (Test-Path -LiteralPath $d)) { Get-ChildItem -LiteralPath $d -Filter '*.lnk' -File -ErrorAction SilentlyContinue } }) +
                @(if ($programs -and (Test-Path -LiteralPath $programs)) { Get-ChildItem -LiteralPath $programs -Filter '*.lnk' -File -Recurse -ErrorAction SilentlyContinue })
        foreach ($l in $lnks) {
            try {
                $s = $sh.CreateShortcut($l.FullName)
                $t = if ($s.TargetPath) { try { [IO.Path]::GetFullPath($s.TargetPath) } catch { $s.TargetPath } } else { '' }
                $hit = $renamed.Keys | Where-Object { $_ -eq $t -or ($s.Arguments -and $s.Arguments.IndexOf($_, [StringComparison]::OrdinalIgnoreCase) -ge 0) } | Select-Object -First 1
                if (-not $hit) { continue }
                if ($hit -eq $t) { $s.TargetPath = $renamed[$hit] }
                else { $s.Arguments = [regex]::Replace($s.Arguments, [regex]::Escape($hit), $renamed[$hit].Replace('$', '$$'), 'IgnoreCase') }
                $s.Save()
                Log "shortcut $($l.FullName): $hit -> $($renamed[$hit])"
            } catch { Log "shortcut not updated: $($l.FullName) ($($_.Exception.Message))" }
        }
    }
    $cloneOld = @($OLD_BATS | ForEach-Object { Join-Path $clone $_ })
    $icon = $null; $rr = Get-RememberedRepo      # (the play shortcut's icon: the game's, never OpenSmash's)
    if ($rr -and (Test-Path -LiteralPath (Join-Path $rr 'build\ssbu.exe'))) { $icon = (Join-Path $rr 'build\ssbu.exe') + ',0' }
    $os = Get-OldOpenSmash
    $osPlays = Test-OpenSmashBuilt
    $osAway = $false      # (OpenSmash recorded on a disk that is not connected now: its old shortcut waits for it)
    if (-not $osPlays -and (Test-Path -LiteralPath $OsRepoTxt)) {
        $osTxt = "$(Get-Content -LiteralPath $OsRepoTxt -TotalCount 1 -Encoding UTF8)".Trim()
        $osRoot = try { [IO.Path]::GetPathRoot($osTxt) } catch { '' }
        $osAway = [bool](($osRoot -and -not (Test-Path -LiteralPath $osRoot)) -or ($os -and (Test-OldBuildGone $os)))
    }
    $Script:OsAway = $osAway      # (the main block: that old shortcut's click goes to OpenSmash, which says to plug the disk in)
    $moved = 0; $movedStart = 0; $made = @()
    foreach ($d in @($Desktop, $programs)) {
        if (-not $d -or -not (Test-Path -LiteralPath $d)) { continue }
        foreach ($o in $OLD_LNKS) {
            $p = Join-Path $d $o[0]
            if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { continue }
            try {
                $old = $sh.CreateShortcut($p)
                if ($cloneOld -notcontains $old.TargetPath) { Log "shortcut left alone (not the launcher's): $p"; continue }
                if ($o[0] -eq 'Smash Ultimate (OpenSmash).lnk' -and $osAway) { Log "shortcut left for later (OpenSmash's disk is not connected): $p"; continue }
                if ($o[0] -eq 'Smash Ultimate (OpenSmash).lnk' -and $osPlays) {     # (since kit 4.4 OpenSmash plays again: menu 8)
                    $old.TargetPath = $new; $old.WorkingDirectory = $clone; $old.Arguments = 'os-play'
                    $old.Save()
                    Log "shortcut $p -> $NEW_BAT os-play"
                    continue
                }
                $name = if ($o[1]) { $PLAY_LNK } else { $MENU_LNK }
                $n = $sh.CreateShortcut((Join-Path $d $name))
                $n.TargetPath = $new; $n.WorkingDirectory = $clone
                if ($o[1]) { $n.Arguments = 'play' }
                $oldIcon = $old.IconLocation -replace ',-?\d+$', ''
                if ($o[1] -and $icon) { $n.IconLocation = $icon }
                elseif ($oldIcon -and -not ($os -and ((Test-Under $oldIcon $os.Repo) -or (Test-Under $oldIcon $os.Build)))) { $n.IconLocation = $old.IconLocation }
                $n.Save()
                if ($made -notcontains $name) { $made += $name }
                Remove-Item -LiteralPath $p -Force
                Log "shortcut $p -> $name"
                $moved++; if ($d -eq $programs) { $movedStart++ }
            } catch { Log "shortcut not moved: $p ($($_.Exception.Message))" }
        }
    }
    if ($osPlays) {
        # A player's own shortcut to the clone's old OpenSmash file with a play mode (taskbar, a Start menu folder): OpenSmash's
        # again (the bootstrap restarts as the new file after an update, so the old name would not tell the kit any more).
        $oldOs = Join-Path $clone 'OpenSmash Launcher.bat'
        $lnks = @(if ($Desktop -and (Test-Path -LiteralPath $Desktop)) { Get-ChildItem -LiteralPath $Desktop -Filter '*.lnk' -File -Recurse -Depth 3 -ErrorAction SilentlyContinue }) +
                @(if ($TaskbarPins -and (Test-Path -LiteralPath $TaskbarPins)) { Get-ChildItem -LiteralPath $TaskbarPins -Filter '*.lnk' -File -ErrorAction SilentlyContinue }) +
                @(if ($programs -and (Test-Path -LiteralPath $programs)) { Get-ChildItem -LiteralPath $programs -Filter '*.lnk' -File -Recurse -ErrorAction SilentlyContinue })
        $inArgs = '(?i)"?' + [regex]::Escape($oldOs) + '"?\s+(play|play-rollback|play-norollback)(?=\s|"|$)'     # (cmd.exe /c "<file>" play: how a .bat is pinned)
        foreach ($l in $lnks) {
            try {
                $s = $sh.CreateShortcut($l.FullName)
                $a = [Environment]::ExpandEnvironmentVariables("$($s.Arguments)")
                if ($s.TargetPath -eq $oldOs -and $a -match '^\s*(play|play-rollback|play-norollback)\s*$') {
                    $arg = 'os-' + $Matches[1]; $s.TargetPath = $new; $s.WorkingDirectory = $clone; $s.Arguments = $arg
                } elseif ($a -match $inArgs) {
                    $arg = 'os-' + $Matches[1]; $s.Arguments = $a.Replace($Matches[0], '"' + $new + '" ' + $arg)
                } else { continue }
                $s.Save()
                Log "shortcut $($l.FullName) -> $NEW_BAT $arg"
            } catch { Log "shortcut not updated: $($l.FullName) ($($_.Exception.Message))" }
        }
        # Kits 4.0-4.3 turned 'Smash Ultimate (OpenSmash)' into OpenSmash Ultimate's shortcut and deleted it: back once.
        $mark = Join-Path $HomeDir 'opensmash-lnk.txt'
        if (-not (Test-Path -LiteralPath $mark)) {
            $osLnk = if ($Desktop) { [IO.Path]::Combine($Desktop, 'Smash Ultimate (OpenSmash).lnk') } else { $null }
            if ($osLnk -and (Test-Path -LiteralPath $Desktop) -and -not (Test-Path -LiteralPath $osLnk)) {
                try {
                    $n = $sh.CreateShortcut($osLnk); $n.TargetPath = $new; $n.WorkingDirectory = $clone; $n.Arguments = 'os-play'
                    $ex = [IO.Path]::Combine($os.Build, 'work\ssbu_native.exe'); if (Test-Path -LiteralPath $ex) { $n.IconLocation = "$ex,0" }
                    $n.Save()
                    Log "shortcut made again: $osLnk (os-play)"
                    Say (L "  OpenSmash (ssbu-recomp) is back on the Desktop: the 'Smash Ultimate (OpenSmash)' shortcut, or choice 8 of the menu." "  OpenSmash (ssbu-recomp) revient sur le Bureau : le raccourci 'Smash Ultimate (OpenSmash)', ou le choix 8 du menu.")
                } catch { Log "OpenSmash shortcut not made: $($_.Exception.Message)" }
            }
            try { New-Item -ItemType Directory -Force $HomeDir | Out-Null; Set-Content -LiteralPath $mark -Value "kit $KitVersion" -Encoding UTF8 } catch {}
        }
    }
    if ($made.Count) { $list = ($made | ForEach-Object { "'" + ($_ -replace '\.lnk$', '') + "'" }) -join ', '; Say (L "  Shortcuts renamed: $list." "  Raccourcis renommés : $list.") }
    if ($movedStart) { Say (L '  (a tile pinned to Start under the old name is gone: pin the new one again from the Start menu)' '  (une vignette épinglée sur Démarrer sous l''ancien nom a disparu : épingle à nouveau la nouvelle depuis le menu Démarrer)') }
}

# ---- main ------------------------------------------------------------------------------------
try {
    $header = {
        Clear-Host
        Write-Host (L "OpenSmash Ultimate Launcher (native Super Smash Bros. Ultimate) - kit $KitVersion" "OpenSmash Ultimate Launcher (Super Smash Bros. Ultimate natif) - kit $KitVersion") -ForegroundColor Cyan
        Write-Host (L 'Two games: OpenSmash Ultimate (choices 1 to 7) and OpenSmash, ssbu-recomp (choice 8), each with its own lobby.' 'Deux jeux : OpenSmash Ultimate (choix 1 à 7) et OpenSmash, ssbu-recomp (choix 8), chacun avec son lobby.') -ForegroundColor Cyan
        Write-Host (L 'This program installs everything: the tools needed (Git, Python, Microsoft tools, compiler),' 'Ce programme installe tout : les outils nécessaires (Git, Python, outils Microsoft, compilateur),')
        Write-Host (L 'OpenSmash Ultimate, then the game from YOUR files: base game 1.0.0 (.xci or .nsp),' 'OpenSmash Ultimate, puis le jeu à partir de TES fichiers : jeu de base 1.0.0 (.xci ou .nsp),')
        Write-Host (L "update $EXPECT_VERSION (.nsp) and prod.keys, dumped from your console." "mise à jour $EXPECT_VERSION (.nsp) et prod.keys, dumpés de ta console.")
    }
    & $header
    Log "kit $KitVersion, KitDir=$KitDir, Mode=$Mode"
    if (-not $KitDir) { $KitDir = (Get-Location).Path }
    if ($KitDir.Length -gt 3) { $KitDir = $KitDir.TrimEnd('\') }
    try { Update-LauncherFiles } catch { Log "launcher files: $($_.Exception.Message)" }
    # The first click of an old 'Smash Ultimate (OpenSmash)' shortcut since kit 4.4 (Update-LauncherFiles has just pointed
    # it at os-play) or an old OpenSmash launcher file started by kit-opensmash\os_setup.ps1: OpenSmash, when it is built
    # (or recorded on a disk that is not connected: its kit says to plug it in).
    if ($Mode -in 'play', 'play-rollback', 'play-norollback' -and $env:WSL_SELF -and (Split-Path $env:WSL_SELF -Leaf) -eq 'OpenSmash Launcher.bat' -and ((Test-OpenSmashBuilt) -or $Script:OsAway)) { $Mode = "os-$Mode"; Log "an old OpenSmash launcher file: mode $Mode" }
    if ($Mode -in 'play-rollback', 'play-norollback') { $Mode = 'play' }       # (older launchers' names: one way to play since 4.3)
    if ($Mode -and $Mode -notin (@('install', 'play', 'diag', 'unlock', 'optimize', 'dlc') + $OS_MODES)) { Log "mode '$Mode' unknown (an old launcher's): the menu"; $Mode = '' }
    while ($true) {
        while (-not $Mode) {
            Write-Host ''
            Write-Host (L '  1) Install / update' '  1) Installer / mettre à jour')
            Write-Host (L '  2) Start the game (online, rollback netcode by default)' '  2) Lancer le jeu (en ligne, rollback par défaut)')
            Write-Host (L '  3) Diagnosis only (makes the report, installs nothing)' '  3) Diagnostic seulement (crée le rapport sans rien installer)')
            Write-Host (L '  4) Unlock every fighter (the launcher also does it by itself)' '  4) Débloquer tous les personnages (le launcher le fait aussi tout seul)')
            Write-Host (L '  5) Optimize: precompile the shaders and latency 1 (steady FPS)' '  5) Optimiser : précompiler les shaders et latence 1 (FPS stables)')
            Write-Host (L '  6) Add my DLC (dumped from my Switch, .nsp files)' '  6) Ajouter mes DLC (dumpés de ma Switch, fichiers .nsp)')
            Write-Host (L '  7) Français (passer le launcher en français)' '  7) English (switch the launcher to English)')
            Write-Host (L '  8) OpenSmash (ssbu-recomp, the other game): install, play, rollback...' '  8) OpenSmash (ssbu-recomp, l''autre jeu) : installer, jouer, rollback...') -ForegroundColor Cyan
            $m = "$(Read-Host (L '  Your choice [1]' '  Ton choix [1]'))".Trim()   # (no input at all: the default)
            if ($m -eq '7') { Set-Language $(if ($Script:Lang -eq 'fr') { 'en' } else { 'fr' }); Log "language $Script:Lang"; & $header; continue }
            $Mode = @{ '2' = 'play'; '3' = 'diag'; '4' = 'unlock'; '5' = 'optimize'; '6' = 'dlc'; '8' = 'os' }[$m]
            if (-not $Mode) { $Mode = 'install' }
        }
        if ($OS_MODES -notcontains $Mode) { break }
        $rc = Invoke-OsKit $Mode
        if ($rc -ne 3) { exit $rc }
        $Mode = ''      # (its 0: back to this menu, in the language its own menu's 8 may have changed)
        $l = 'en'; try { if ((Get-Content -LiteralPath $LangTxt -Raw -ErrorAction Stop).Trim() -eq 'fr') { $l = 'fr' } } catch {}
        if ($l -ne $Script:Lang) { Set-Language $l }
        & $header
    }
    Probe-System
    if ($Mode -eq 'play') {
        $null = Find-Repo $false
        $built = $Script:Repo -and ((Test-Path -LiteralPath (Join-Path $Script:Repo 'build\ssbu.exe')) -or (Test-Path -LiteralPath (Join-Path $Script:Repo "$OLD_TREE\build\ssbu.exe")))
        if (-not $built) {
            if (Get-OldOpenSmash) {      # (an OpenSmash player: OpenSmash Ultimate is a new install for them)
                Say (L '  OpenSmash Ultimate is not installed yet (1 to 3 hours; your save and the game files you gave come over).' '  OpenSmash Ultimate n''est pas encore installé (1 à 3 heures ; ta sauvegarde et les fichiers du jeu déjà donnés sont repris).')
                $osOk = Test-OpenSmashBuilt
                if ($osOk) { Say (L '  Your OpenSmash (ssbu-recomp) stays: choice 8 of the menu starts it.' '  Ton OpenSmash (ssbu-recomp) reste : le choix 8 du menu le lance.') }
                else { Say (L '  Your OpenSmash (ssbu-recomp) stays, but its game is not built or its disk is not connected: 8 > 1 finishes it.' '  Ton OpenSmash (ssbu-recomp) reste, mais son jeu n''est pas compilé ou son disque n''est pas branché : 8 > 1 le termine.') }
                if (Ask-YesNo $(if ($osOk) { L '  Install OpenSmash Ultimate now? (n = start OpenSmash instead)' '  J''installe OpenSmash Ultimate maintenant ? (n = lancer OpenSmash à la place)' } else { L '  Install OpenSmash Ultimate now?' '  J''installe OpenSmash Ultimate maintenant ?' })) { $Mode = 'install' }
                elseif ($osOk) { exit (Invoke-OsKit 'os-play') }
                else { Say (L '  Later: choose 1) Install, or 8) for OpenSmash.' '  Plus tard : choisis 1) Installer, ou 8) pour OpenSmash.'); Read-Host (L 'Enter to close' 'Entrée pour fermer'); exit 0 }
            } elseif ($Script:Repo) {      # (the folder is there, its game not built yet: an install that stopped)
                Say (L '  The install did not finish: the game is not compiled yet.' '  L''installation n''est pas finie : le jeu n''est pas encore compilé.')
                if (Ask-YesNo (L '  Carry on with the install now? (it resumes where it was)' '  Je reprends l''installation maintenant ? (elle reprend où elle en était)')) { $Mode = 'install' }
                else { Say (L '  Later: choose 1) Install.' '  Plus tard : choisis 1) Installer.'); Read-Host (L 'Enter to close' 'Entrée pour fermer'); exit 0 }
            } else { Say (L '  The game is not installed yet: choose 1) Install.' '  Le jeu n''est pas encore installé : choisis 1) Installer.'); Read-Host (L 'Enter to close' 'Entrée pour fermer'); exit 0 }
        } else {
            # A new pinned version (a git HEAD or, for a copy without git, the files the kit checks), or the last update
            # stopped between its checkout and its compile: either way the game is not the group's and an update is offered.
            $ver = Get-RepoVersion
            $offer = $false
            if ($ver -and $ver -ne $WS_COMMIT) {
                $g = Find-Git
                $url = if ($g -and (Test-Path -LiteralPath (Join-Path $Script:Repo '.git'))) { "$(@(Run-Native { & $g -C $Script:Repo remote get-url origin 2>$null }) | Select-Object -First 1)".Trim() } else { '' }
                if ($url -match $WS_OLD_URL) {
                    Say (L '  WindowSmash is now OpenSmash Ultimate, and the group moves to it: your' '  WindowSmash est maintenant OpenSmash Ultimate, et le groupe passe dessus : ton')
                    Say (L "  WindowSmash folder becomes OpenSmash Ultimate ($($WS_COMMIT.Substring(0,7))), your save and settings kept. To play online, you need it." "  dossier WindowSmash devient OpenSmash Ultimate ($($WS_COMMIT.Substring(0,7))), sauvegarde et réglages gardés. Pour jouer en ligne, il le faut.")
                } else {
                    $from = if ($ver -match '^[0-9a-f]{40}$') { "$($ver.Substring(0,7)) -> " } else { '' }
                    Say (L "  New OpenSmash Ultimate version ($from$($WS_COMMIT.Substring(0,7))): to play online, you need the same as your friends." "  Nouvelle version d'OpenSmash Ultimate ($from$($WS_COMMIT.Substring(0,7))) : pour jouer en ligne, il faut la même que tes amis.")
                }
                if (-not (Test-Path -LiteralPath (Join-Path $Script:Repo 'build\ssbu.exe'))) {   # (from kit 2.x's 13.0.4)
                    Say (L "  It needs the game's $EXPECT_VERSION update, dumped from your up-to-date Switch. If you don't have it yet," "  Elle demande la mise à jour $EXPECT_VERSION du jeu, dumpée de ta Switch à jour. Si tu ne l'as pas encore,")
                    Say (L '  answer n: the current game stays playable meanwhile.' '  réponds n : le jeu actuel reste jouable en attendant.')
                }
                $offer = $true
            } elseif ($ver -eq $WS_COMMIT -and -not (Test-BuildCurrent $ver)) {
                Say (L "  The last update stopped before the game was compiled: the game is still the old one, which does not play online with the others." "  La dernière mise à jour s'est arrêtée avant la compilation du jeu : le jeu est encore l'ancien, qui ne joue pas en ligne avec les autres.")
                $offer = $true
            }
            if ($offer -and (Ask-YesNo (L '  Update now? (recompile: 20 min to 2 h depending on the version and the PC)' '  Je fais la mise à jour maintenant ? (recompilation : 20 min à 2 h selon la version et le PC)'))) { $Mode = 'install' }
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
        $os = Get-OldOpenSmash; if ($os) { $Script:Info['OpenSmash (menu 8)'] = "$($os.Repo) (game in $($os.Build), $(if (Test-OpenSmashBuilt) { 'built' } else { 'not built' }))" }
        if ($Script:Repo) {
            $v = Join-Path $Script:Repo '.venv\Scripts\python.exe'; if (Test-Path -LiteralPath $v) { $Script:VenvPy = $v }
            $c = Join-Path $Script:Repo "dump\_setup\llvm-$LLVM_VER\bin\clang-cl.exe"; $Script:Info['clang-cl'] = if (Test-Path -LiteralPath $c) { $c } else { 'missing' }
            if ($g -and (Test-Path -LiteralPath (Join-Path $Script:Repo '.git'))) { $Script:Info['OpenSmash Ultimate (git)'] = (Run-Native { & $g -C $Script:Repo rev-parse HEAD }) | Select-Object -First 1 }
        }
        Write-Report 'DIAGNOSTIC'
        Say (L "  Report written on the Desktop: OpenSmash-Ultimate-setup-report.txt" "  Rapport écrit sur le Bureau : OpenSmash-Ultimate-setup-report.txt")
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
    # Coming from kit 2.x's 13.0.4, or updating a game built already: the game files are asked and checked while the
    # folder is still at the version its game was built from, so that a player who stops there (no file chosen, a wrong
    # one, the 13.0.5 update not dumped yet) keeps a game that starts and still matches its folder.
    $venv = Join-Path $Script:Repo '.venv\Scripts\python.exe'
    $builtNow = Test-Path -LiteralPath (Join-Path $Script:Repo 'build\ssbu.exe')
    $migrating = (Test-Path -LiteralPath (Join-Path $Script:Repo "$OLD_TREE\build\ssbu.exe")) -and -not $builtNow -and (Test-Path -LiteralPath $venv)
    $early = ($migrating -or $builtNow) -and (Test-Path -LiteralPath $venv)
    if ($early) { $Script:VenvPy = $venv; Ask-Inputs; Check-Inputs }
    Ensure-Revision
    Stop-Test 'revision'
    Ensure-Python
    Ensure-VS
    Ensure-LLVM
    Test-Toolchain
    Stop-Test 'tools'
    if (-not $early) { Ask-Inputs; Check-Inputs }
    Prepare-Base
    Prepare-Fonts
    Ensure-Opus
    Ensure-SDL3
    Build-Game
    Import-OpenSmashSave
    Remove-OldTree
    Unlock-Fighters $true      # (a save there already; a new one gets them at its first start's end, see Start-Game)
    Set-Latency1
    if (Ask-YesNo (L '  Precompile the shaders now? (recommended: steady FPS from the first match; 30 min to 2 h)' '  Je précompile les shaders maintenant ? (recommandé : FPS stables dès le premier match ; 30 min à 2 h)')) { Precompile-Shaders $false }
    else { Say (L '  Later: start OpenSmash Ultimate Launcher again and choose 5).' '  Plus tard : relance OpenSmash Ultimate Launcher et choisis 5).') }
    Finish
    Read-Host (L 'Enter to close' 'Entrée pour fermer')
    exit 0
} catch {
    $e = $_
    Log "UNEXPECTED $($e.Exception.GetType().FullName): $($e.Exception.Message)`r`n$($e.ScriptStackTrace)"
    $Script:Info['PowerShell error'] = "$($e.Exception.Message) | $($e.InvocationInfo.PositionMessage -replace '\s+', ' ')"
    Fail 'E99' "$($e.Exception.Message)"
}
