# OpenSmash setup kit - the orchestrator (Windows PowerShell 5.1) for OpenSmash (github.com/OpenSmash-Ultimate/ssbu-recomp,
# native Super Smash Bros. Ultimate with an experimental rollback netcode). It lives in github.com/Nilsix/WindowSmashLauncher
# (kit-opensmash\os_setup.ps1) and is started by "OpenSmash Launcher.bat", which keeps a clone of that repository up to
# date in %LOCALAPPDATA%\WindowSmashLauncher (the same clone as the WindowSmash launcher's).
# This file must stay UTF-8 with a BOM and CRLF (Windows PowerShell 5.1 reads a BOM-less file as ANSI).
#
# OpenSmash has its own one-click installer, which always takes the newest version of the project. Players on different
# versions cannot play together (its rollback needs the same version on both sides), so this kit pins one commit for
# everyone ($OS_COMMIT, a commit whose installer names its prebuilt runtime) and runs OpenSmash's installer with
# --no-self-update. OpenSmash's own "Install SSBU.bat" and "SSBU native" shortcuts are not used: they would update it.
#
# Steps: Git (installed by the bootstrap) -> the OpenSmash folder (cloned, or one already there) -> the pinned version ->
# OpenSmash's private Python (its scripts\bootstrap.ps1 -NoLaunch) -> the game files (inputs.json, shared with the
# WindowSmash kit) -> its scripts\install.py --prepare-only (the unpacked game) -> the game program must be 13.0.5's (its
# build id) -> install.py again (the build) -> shortcuts through the launcher (play mode checks the version at every
# start) -> the game, always with the rollback netcode on (the owner's choice, 2026-10-26: the launcher offers no start
# without it and writes rollback = on before every start).
# After a version change the build repeats from the step OpenSmash's own self-update would repeat (scripts\update.py's
# rebuild_advice on the changed files, passed with install.py's --reexec), counted from the oldest version not built yet
# (opensmash-rebuild.txt), so an update stopped half way is finished at the next start.
# Messages: English, or French when chosen (menu 5, kept in %LOCALAPPDATA%\WindowSmash-setup\lang.txt, the same file as
# the WindowSmash kit's): every message is written as L 'English' 'French'. The report and the log stay in English.
# Modes (-Mode, the launcher's argument): install, play, diag, dlc (menu 4: add my DLC); none: the menu.
# Test-only environment: WS_STOP_AFTER=repo|revision|python|prepare, WS_NO_NOTEPAD, WS_REPORT_DIR, WS_INPUTS_JSON
# (another inputs.json).
param([string]$KitDir = '', [string]$Mode = '')

$ErrorActionPreference = 'Stop'
$KitVersion = '1.0 (2026-10-26)'

# ---- the version everyone plays --------------------------------------------------------------------------------------
$OS_GIT_URL = 'https://github.com/OpenSmash-Ultimate/ssbu-recomp.git'
$OS_COMMIT  = 'fea28c18b785372b5024ece0a2ea52e860b1fa04'   # main, 2026-10-26: "Installer: prebuilt runtime 6de107d"
$OS_BRANCH  = 'main'
$EXPECT_VERSION = '13.0.5'   # OpenSmash takes 13.0.4 or 13.0.5; the group plays 13.0.5, as with WindowSmash
# the game program's (exefs\main's) build id -> its update
$BUILD_IDS = @{ '21450C647B8C5940ED5B68218EA128FD3C5D597D' = '13.0.5'; '3EAE0063B12FD81E99FB5980BA56297049EA94F9' = '13.0.4' }
$SETUP_STEPS = @('deps', 'stage', 'convert', 'modules', 'tables', 'lift', 'sdk', 'compile', 'nro', 'link', 'check')   # scripts\setup.py's

# ---- paths ----------------------------------------------------------------------------------------------------------
$HomeDir  = Join-Path $env:LOCALAPPDATA 'WindowSmash-setup'          # (shared with the WindowSmash kit: lang.txt, inputs.json)
$Stamp    = Get-Date -Format 'yyyyMMdd-HHmmss'
$LogDir   = Join-Path $HomeDir "logs\opensmash-$Stamp"
$MainLog  = Join-Path $LogDir 'setup.log'
$Desktop  = [Environment]::GetFolderPath('Desktop')
$ReportDir = if ($env:WS_REPORT_DIR) { $env:WS_REPORT_DIR } else { $Desktop }
$Report   = Join-Path $ReportDir 'OpenSmash-setup-report.txt'
$InputsJs = if ($env:WS_INPUTS_JSON) { $env:WS_INPUTS_JSON } else { Join-Path $HomeDir 'inputs.json' }
$RepoTxt  = Join-Path $HomeDir 'opensmash-repo.txt'                   # where OpenSmash is, for the next runs
$RebuildTxt = Join-Path $HomeDir 'opensmash-rebuild.txt'              # the oldest OpenSmash commit not built yet
$WsRepoTxt = Join-Path $HomeDir 'repo.txt'                            # (the WindowSmash kit's: OpenSmash goes next to it)
$LangTxt  = Join-Path $HomeDir 'lang.txt'
$NEED_GB  = 30
New-Item -ItemType Directory -Force $LogDir | Out-Null
$Script:Repo = $null; $Script:Git = $null; $Script:Py = $null; $Script:Inputs = @{}
$Script:Steps = New-Object System.Collections.Specialized.OrderedDictionary
$Script:Info = [ordered]@{}; $Script:Warnings = New-Object System.Collections.ArrayList
$Script:LastLog = $null
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}
$env:PYTHONIOENCODING = 'utf-8'; $env:PYTHONUNBUFFERED = '1'

# ---- language -------------------------------------------------------------------------------------------------------
$Script:Lang = 'en'
try { if ((Get-Content -LiteralPath $LangTxt -Raw -ErrorAction Stop).Trim() -eq 'fr') { $Script:Lang = 'fr' } } catch {}
function L([string]$en, [string]$fr) { if ($Script:Lang -eq 'fr') { return $fr } return $en }

function Set-Language([string]$lang) {
    $Script:Lang = $lang
    try { New-Item -ItemType Directory -Force $HomeDir | Out-Null; Set-Content -LiteralPath $LangTxt -Value $lang -Encoding ASCII } catch {}
}

function Hint([string]$code) {
    switch ($code) {
        'E11' { L "OpenSmash could not be set to the right version. Check the internet connection. If you changed files in its folder, delete the folder and install again." "Impossible de mettre OpenSmash à la bonne version. Vérifie internet. Si tu as modifié des fichiers de son dossier, supprime le dossier et réinstalle." }
        'E12' { L "Git is missing: start the launcher again (it installs Git)." "Git manque : relance le launcher (il installe Git)." }
        'E13' { L "Cloning OpenSmash failed. Check the internet connection (is github.com reachable?), then start again." "Le clonage d'OpenSmash a échoué. Vérifie internet (github.com accessible ?) puis relance." }
        'E23' { L "The OpenSmash folder is in OneDrive: choose another place." "Le dossier OpenSmash est dans OneDrive : choisis un autre endroit." }
        'E31' { L "OpenSmash's private Python could not be set up (it is downloaded from python.org): check the internet connection, then start again." "Le Python privé d'OpenSmash n'a pas pu être installé (téléchargé depuis python.org) : vérifie internet puis relance." }
        'E40' { L "A file that was asked for was not chosen. Start again and choose it." "Un fichier demandé n'a pas été choisi. Relance et choisis-le." }
        'E44' { L "The DLC folder holds no .nsp file: choose the folder of the DLC dumped from your Switch." "Le dossier des DLC ne contient aucun fichier .nsp : choisis le dossier des DLC dumpés de ta Switch." }
        'E43' { L "The update is not right: the group plays the $EXPECT_VERSION update (.nsp), dumped from your up-to-date Switch. Start again: the launcher asks for it." "La mise à jour ne convient pas : le groupe joue avec l'update $EXPECT_VERSION (.nsp), dumpée de ta Switch à jour. Relance : le launcher te la demande." }
        'E60' { L "OpenSmash's installer stopped: the end of its log is in the report. Start the launcher again: it carries on where it stopped." "L'installateur d'OpenSmash s'est arrêté : la fin de son log est dans le rapport. Relance le launcher : il reprend où il en était." }
        'E70' { L "The game did not start." "Le jeu ne s'est pas lancé." }
        'E99' { L "Unexpected error of the script: send the report." "Erreur inattendue du script : envoie le rapport." }
        default { $null }
    }
}

# ---- output ---------------------------------------------------------------------------------------------------------
function Log([string]$t) { Add-Content -LiteralPath $MainLog -Value ("{0:HH:mm:ss} {1}" -f (Get-Date), $t) -Encoding UTF8 }
function Say([string]$t)  { Write-Host $t; Log $t }
function Ok([string]$t)   { Write-Host "  [OK] $t" -ForegroundColor Green; Log "[OK] $t" }
function Warn([string]$t) { Write-Host "  [!] $t" -ForegroundColor Yellow; Log "[WARN] $t"; [void]$Script:Warnings.Add($t) }
function Title([string]$t) { Write-Host ''; Write-Host "=== $t ===" -ForegroundColor Cyan; Log "=== $t" }

function Redact([string]$t) {
    if (-not $t) { return $t }
    $t = $t -replace [regex]::Escape($env:USERPROFILE), '%USERPROFILE%'
    if ($env:USERNAME) { $t = $t -replace ('(?<=\\Users\\)' + [regex]::Escape($env:USERNAME) + '(?=\\|$)'), '<user>' }
    return $t
}

function Ask-YesNo([string]$q, [bool]$default = $true) {
    $s = if ($default) { L '[Y/n]' '[O/n]' } else { L '[y/N]' '[o/N]' }
    while ($true) {
        $a = "$(Read-Host "$q $s")".Trim()
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
        $d.Description = $title; $d.ShowNewFolderButton = $true
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

function Write-Report([string]$status, [string]$code = '', [string]$message = '') {
    $R = New-Object System.Collections.ArrayList
    $add = { param($x) [void]$R.Add([string]$x) }
    & $add "OPENSMASH SETUP REPORT - kit $KitVersion (language: $Script:Lang)"
    & $add ("Date: {0}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
    & $add "Result: $status"
    if ($code) { & $add "Code: $code"; & $add "Message: $message"; if (Hint $code) { & $add "What to do: $(Hint $code)" } }
    & $add ''
    & $add '--- Steps'
    foreach ($k in $Script:Steps.Keys) { & $add ("  {0,-22} {1}" -f $k, $Script:Steps[$k]) }
    if ($Script:Warnings.Count) { & $add ''; & $add '--- Warnings'; foreach ($w in $Script:Warnings) { & $add "  $w" } }
    & $add ''
    & $add '--- System and tools'
    foreach ($k in $Script:Info.Keys) { & $add ("  {0,-22} {1}" -f $k, (Redact ([string]$Script:Info[$k]))) }
    if ($Script:LastLog) { & $add ''; & $add "--- End of the step's log ($(Redact $Script:LastLog))"; & $add (Redact (Tail $Script:LastLog 80)) }
    & $add ''
    & $add '--- End of the main log'
    & $add (Redact (Tail $MainLog 40))
    & $add ''
    & $add "Full logs: $(Redact $LogDir)"
    [IO.File]::WriteAllLines($Report, [string[]]$R, (New-Object Text.UTF8Encoding $true))
}

function Fail([string]$code, [string]$message, [string]$log = '') {
    if ($log) { $Script:LastLog = $log }
    Write-Host ''
    Write-Host "  $(L 'FAILED' 'ÉCHEC') [$code] $message" -ForegroundColor Red
    if (Hint $code) { Write-Host "  -> $(Hint $code)" -ForegroundColor Yellow }
    Log "FAIL $code $message"
    Write-Report 'FAILED' $code $message
    Write-Host ''
    Write-Host (L '  Report written on the Desktop: OpenSmash-setup-report.txt' '  Rapport écrit sur le Bureau : OpenSmash-setup-report.txt') -ForegroundColor Cyan
    Write-Host (L '  Send this file as it is (it holds no keys and no game files).' '  Envoie ce fichier tel quel (il ne contient ni clés ni fichiers du jeu).') -ForegroundColor Cyan
    if (-not $env:WS_NO_NOTEPAD) { try { Start-Process notepad.exe -ArgumentList "`"$Report`"" } catch {} }
    Write-Host ''
    Read-Host (L 'Press Enter to close' 'Appuie sur Entrée pour fermer')
    exit 10      # handled: the launcher does not pause again
}

function Stop-Test([string]$step) {
    if ($env:WS_STOP_AFTER -and $env:WS_STOP_AFTER -eq $step) { Write-Report "TEST (stopped after $step)"; Say "  [test] stopped after $step"; exit 0 }
}

function Run-Native([scriptblock]$sb) { $ErrorActionPreference = 'Continue'; & $sb }

# A program whose output is shown as it comes and kept in logs\<name>.txt; returns the exit code.
function Run-Shown([string]$exe, [string[]]$argv, [string]$name) {
    $log = Join-Path $LogDir "$name.txt"; $Script:LastLog = $log
    Log "RUN $exe $($argv -join ' ') (log $log)"
    $ErrorActionPreference = 'Continue'
    & $exe @argv 2>&1 | ForEach-Object { $l = "$_"; Write-Host $l; Add-Content -LiteralPath $log -Value $l -Encoding UTF8 }
    $code = $LASTEXITCODE
    Log "EXIT $code"
    return $code
}

# ---- git ------------------------------------------------------------------------------------------------------------
function Find-Git {
    $g = Get-Command git -ErrorAction SilentlyContinue
    if ($g) { return $g.Source }
    foreach ($p in @("$env:ProgramFiles\Git\cmd\git.exe", "${env:ProgramFiles(x86)}\Git\cmd\git.exe", "$env:LOCALAPPDATA\Programs\Git\cmd\git.exe")) {
        if (Test-Path -LiteralPath $p) { return $p }
    }
    return $null
}

# The folder declared safe for git (an exFAT or FAT32 disk records no owner, and git then refuses it), without touching
# the player's git settings: GIT_CONFIG_* is command-scope configuration, where safe.directory counts.
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

function Get-GitError($lines) {
    $l = @($lines | ForEach-Object { "$_".Trim() } | Where-Object { $_ })
    $why = @($l | Where-Object { $_ -match '^(fatal|error):' }) | Select-Object -Last 1
    if (-not $why) { $why = $l | Select-Object -Last 1 }
    foreach ($x in $l) { Log "GIT $x" }
    return "$why"
}

function Get-Head {
    if (-not ($Script:Git -and $Script:Repo -and (Test-Path -LiteralPath (Join-Path $Script:Repo '.git')))) { return $null }
    Set-GitSafeRepo
    $out = @(Run-Native { & $Script:Git -C $Script:Repo rev-parse HEAD 2>&1 })
    if ($LASTEXITCODE) { return $null }
    return "$($out | Select-Object -First 1)".Trim()
}

# ---- the OpenSmash folder -------------------------------------------------------------------------------------------
function Test-RepoDir([string]$d) { return ($d -and (Test-Path -LiteralPath (Join-Path $d 'scripts\install.py')) -and (Test-Path -LiteralPath (Join-Path $d 'runtime'))) }

function Get-RememberedRepo {
    if (Test-Path -LiteralPath $RepoTxt) { $p = (Get-Content -LiteralPath $RepoTxt -Raw).Trim(); if (Test-RepoDir $p) { return $p } }
    return $null
}

function Get-DefaultInstallDir {
    # next to WindowSmash when it is installed, else on the local disk with the most free space
    if (Test-Path -LiteralPath $WsRepoTxt) {
        $ws = (Get-Content -LiteralPath $WsRepoTxt -Raw).Trim()
        if ($ws -and (Test-Path -LiteralPath $ws)) { return (Join-Path (Split-Path $ws -Parent) 'OpenSmash') }
    }
    $best = Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' | Sort-Object FreeSpace -Descending | Select-Object -First 1
    $root = if ($best) { $best.DeviceID + '\' } else { 'C:\' }
    return (Join-Path $root 'Games\OpenSmash')
}

# The folder of a previous install, or (when $allowClone) one chosen now: OpenSmash cloned into it, or an OpenSmash
# folder that is already there used as it is.
function Find-Repo([bool]$allowClone) {
    Title (L 'OpenSmash folder' 'Dossier OpenSmash')
    $Script:Repo = Get-RememberedRepo
    if ($Script:Repo) { Say (L "  Previous install found: $($Script:Repo)" "  Installation précédente trouvée : $($Script:Repo)") }
    if (-not $Script:Repo) {
        if (-not $allowClone) { Say (L '  OpenSmash is not installed on this PC yet.' '  OpenSmash n''est pas encore installé sur ce PC.'); return $null }
        $def = Get-DefaultInstallDir
        while (-not $Script:Repo) {
            Say (L "  Where to install OpenSmash? About $NEED_GB GB free are needed, outside OneDrive. An OpenSmash folder you already have works too." "  Où installer OpenSmash ? Il faut environ $NEED_GB Go libres, hors OneDrive. Un dossier OpenSmash que tu as déjà marche aussi.")
            $a = "$(Read-Host (L "  Folder [$def] (Enter = OK, B = browse, or type a path)" "  Dossier [$def] (Entrée = OK, P = parcourir, ou tape un chemin)"))".Trim()
            if (-not $a) { $t = $def }
            elseif ($a -match '^[bBpP]$') { $f = Pick-Folder (L 'Choose where to install OpenSmash' 'Choisis où installer OpenSmash'); if (-not $f) { continue }; $t = $f }
            else { $t = $a.Trim('"') }
            try { $t = [IO.Path]::GetFullPath($t) } catch { Warn (L "W13 invalid path: $t" "W13 chemin invalide : $t"); continue }
            if ($t -match 'OneDrive') { Warn (L 'W23 not in OneDrive: choose another folder' 'W23 pas dans OneDrive : choisis un autre dossier'); continue }
            if (Test-RepoDir $t) { $Script:Repo = $t; break }
            if ((Test-Path -LiteralPath $t) -and (Get-ChildItem -LiteralPath $t -Force | Select-Object -First 1)) {
                $t = Join-Path $t 'OpenSmash'                         # (a folder with other things in it: OpenSmash goes inside)
                if (Test-RepoDir $t) { $Script:Repo = $t; break }
                if ((Test-Path -LiteralPath $t) -and (Get-ChildItem -LiteralPath $t -Force | Select-Object -First 1)) {
                    Warn (L "W13 $t already exists and is not empty: choose another folder" "W13 $t existe déjà et n'est pas vide : choisis un autre dossier"); continue
                }
            }
            try { $free = (New-Object IO.DriveInfo ([IO.Path]::GetPathRoot($t))).AvailableFreeSpace / 1GB } catch { Warn (L "W13 no disk found for $t" "W13 disque introuvable pour $t"); continue }
            if ($free -lt $NEED_GB) { Warn ((L "W22 only {0:N0} GB free on {1}: choose another disk" "W22 seulement {0:N0} Go libres sur {1} : choisis un autre disque") -f $free, [IO.Path]::GetPathRoot($t)); continue }
            New-Item -ItemType Directory -Force (Split-Path $t -Parent) | Out-Null
            Say (L "  Cloning OpenSmash into $t ..." "  Clonage d'OpenSmash dans $t ...")
            $out = @(Run-Native { & $Script:Git clone $OS_GIT_URL $t 2>&1 })
            if ($LASTEXITCODE -ne 0 -or -not (Test-RepoDir $t)) { Set-Step 'Folder' 'FAILED' 'git clone'; Fail 'E13' "git clone $(L 'failed' 'a échoué') : $(Get-GitError $out)" }
            Ok (L 'OpenSmash cloned' 'OpenSmash cloné')
            $Script:Repo = $t
        }
    }
    if ($Script:Repo -match 'OneDrive') { Set-Step 'Folder' 'FAILED' 'in OneDrive'; Fail 'E23' $Script:Repo }
    New-Item -ItemType Directory -Force $HomeDir | Out-Null
    Set-Content -LiteralPath $RepoTxt -Value $Script:Repo -Encoding UTF8
    $Script:Info['OpenSmash folder'] = $Script:Repo
    $Script:Info['Free disk'] = "{0:N1} GB" -f ((Get-Item -LiteralPath $Script:Repo).PSDrive.Free / 1GB)
    Set-GitSafeRepo
    Set-Step 'Folder' 'OK' $Script:Repo
    return $Script:Repo
}

# The pinned commit, checked out detached. The settings players edit (config\graphics.ini) are not tracked: they stay.
function Ensure-Revision {
    Title (L 'OpenSmash version' 'Version d''OpenSmash')
    if (-not (Test-Path -LiteralPath (Join-Path $Script:Repo '.git'))) { Set-Step 'Version' 'FAILED' 'not a git checkout'; Fail 'E11' (L "$($Script:Repo) is not a git checkout (a ZIP download?): delete it and let the launcher clone OpenSmash" "$($Script:Repo) n'est pas un dépôt git (un ZIP téléchargé ?) : supprime-le et laisse le launcher cloner OpenSmash") }
    Set-GitSafeRepo
    $out = @(Run-Native { & $Script:Git -C $Script:Repo rev-parse HEAD 2>&1 })
    if ($LASTEXITCODE) { Set-Step 'Version' 'FAILED' 'git'; Fail 'E11' "$(L 'git cannot read the OpenSmash folder' 'git ne peut pas lire le dossier OpenSmash') : $(Get-GitError $out)" }
    $head = "$($out | Select-Object -First 1)".Trim()
    $Script:Info['OpenSmash (git)'] = $head
    if ($head -eq $OS_COMMIT) { Ok (L "already the right version ($($OS_COMMIT.Substring(0,7)))" "déjà à la bonne version ($($OS_COMMIT.Substring(0,7)))"); Set-Step 'Version' 'OK' 'git'; return }
    $dirty = @(Run-Native { & $Script:Git -C $Script:Repo status --porcelain --untracked-files=no })
    if ($dirty) { Set-Step 'Version' 'FAILED' 'files changed'; Fail 'E11' "$(L 'files of the folder were changed (git status)' 'des fichiers du dossier ont été modifiés (git status)') : $(($dirty | Select-Object -First 5) -join ', ')" }
    Say (L "  Moving to version $($OS_COMMIT.Substring(0,7))..." "  Passage à la version $($OS_COMMIT.Substring(0,7))...")
    $out = @(Run-Native { & $Script:Git -C $Script:Repo fetch origin $OS_BRANCH 2>&1 })
    if ($LASTEXITCODE) { Set-Step 'Version' 'FAILED' 'git fetch'; Fail 'E11' "$(L 'git fetch failed' 'git fetch a échoué') : $(Get-GitError $out)" }
    $null = Run-Native { & $Script:Git -C $Script:Repo cat-file -e "$OS_COMMIT^{commit}" 2>&1 }
    if ($LASTEXITCODE) {        # (no longer on the branch: fetched by its id)
        $out = @(Run-Native { & $Script:Git -C $Script:Repo fetch origin $OS_COMMIT 2>&1 })
        if ($LASTEXITCODE) { Set-Step 'Version' 'FAILED' 'git fetch'; Fail 'E11' "git fetch $OS_COMMIT $(L 'failed' 'a échoué') : $(Get-GitError $out)" }
    }
    $out = @(Run-Native { & $Script:Git -C $Script:Repo -c advice.detachedHead=false checkout --detach $OS_COMMIT 2>&1 })
    if ($LASTEXITCODE) { Set-Step 'Version' 'FAILED' 'git checkout'; Fail 'E11' "git checkout $OS_COMMIT $(L 'failed' 'a échoué') : $(Get-GitError $out)" }
    if (-not (Test-Path -LiteralPath $RebuildTxt)) { Set-Content -LiteralPath $RebuildTxt -Value $head -Encoding ASCII }   # (the oldest version not built)
    $Script:Info['OpenSmash (git)'] = "$OS_COMMIT (was $head)"
    Ok (L 'version updated' 'version mise à jour'); Set-Step 'Version' 'OK' "git checkout (was $($head.Substring(0,7)))"
}

# OpenSmash's own private Python (deps\python, the python.org embeddable package) through its scripts\bootstrap.ps1.
function Ensure-Python {
    Title (L "OpenSmash's private Python" 'Python privé d''OpenSmash')
    $py = Join-Path $Script:Repo 'deps\python\python.exe'
    if (-not (Test-Path -LiteralPath $py)) {
        Say (L '  Setting it up inside the OpenSmash folder (nothing is installed in Windows; a minute or two)...' '  Installation dans le dossier OpenSmash (rien n''est installé dans Windows ; une ou deux minutes)...')
        $rc = Run-Shown (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $Script:Repo 'scripts\bootstrap.ps1'), '-NoLaunch') 'bootstrap'
        if ($rc -ne 0 -or -not (Test-Path -LiteralPath $py)) { Set-Step 'Python' 'FAILED' "bootstrap $rc"; Fail 'E31' (L "OpenSmash's bootstrap stopped (code $rc)" "le bootstrap d'OpenSmash s'est arrêté (code $rc)") }
    }
    $Script:Py = $py
    $Script:Info['Python'] = "$((Run-Native { & $py --version 2>&1 }) | Select-Object -First 1)"
    Ok (L 'private Python ready' 'Python privé prêt')
    Set-Step 'Python' 'OK'
}

# ---- the game files (inputs.json, shared with the WindowSmash kit) ---------------------------------------------------
function Load-Inputs { if (Test-Path -LiteralPath $InputsJs) { try { return (Get-Content -LiteralPath $InputsJs -Raw -Encoding UTF8 | ConvertFrom-Json) } catch {} }; return $null }
function Save-Inputs { $Script:Inputs | ConvertTo-Json | Set-Content -LiteralPath $InputsJs -Encoding UTF8 }

# $quiet (after menu 4): the files of last time are reused without asking when they are all there.
function Ask-Inputs([bool]$quiet = $false) {
    Title (L 'Game files (yours, dumped from your console)' 'Fichiers du jeu (les tiens, dumpés de ta console)')
    $prev = Load-Inputs
    $have = { param($p) $p -and (Test-Path -LiteralPath $p) }
    if ($prev -and (& $have $prev.base) -and (& $have $prev.prodkeys)) {
        # (an update of another version, found by this kit or checked by the WindowSmash kit, is not reused)
        $upd = if ((& $have $prev.update) -and (-not $prev.update_version -or $prev.update_version -eq $EXPECT_VERSION)) { $prev.update } else { $null }
        if ($quiet -and $upd) {
            $Script:Inputs = @{ base = $prev.base; update = $upd; prodkeys = $prev.prodkeys; titlekeys = $prev.titlekeys; dlc = $prev.dlc; firmware = $prev.firmware; update_version = $prev.update_version }
            Ok (L 'the game files of last time' 'les fichiers du jeu de la dernière fois')
            return
        }
        Say (L '  Files chosen last time (by this launcher or the WindowSmash launcher):' '  Fichiers choisis la dernière fois (par ce launcher ou le launcher WindowSmash) :')
        Say "    $(L 'base game  ' 'jeu de base') : $($prev.base)"
        if ($upd) { Say "    $(L 'update     ' 'mise à jour') : $upd" }
        Say "    prod.keys   : $($prev.prodkeys)"
        if ($prev.dlc) { Say "    DLC         : $($prev.dlc)" }
        if (Ask-YesNo (L '  Use them again?' '  Je les réutilise ?')) {
            $Script:Inputs = @{ base = $prev.base; update = $upd; prodkeys = $prev.prodkeys; titlekeys = $prev.titlekeys; dlc = $prev.dlc; firmware = $prev.firmware; update_version = $prev.update_version }
            if (-not $upd) {
                Say (L "  The group plays the game's $EXPECT_VERSION update (dumped from your up-to-date Switch)." "  Le groupe joue avec la mise à jour $EXPECT_VERSION du jeu (dumpée de ta Switch à jour).")
                $u = Pick-File (L "Choose Smash Ultimate's $EXPECT_VERSION UPDATE (.nsp)" "Choisis la MISE À JOUR $EXPECT_VERSION de Smash Ultimate (.nsp)") (L 'Update (*.nsp)|*.nsp|All files|*.*' 'Mise à jour (*.nsp)|*.nsp|Tous les fichiers|*.*') $prev.base
                if (-not $u) { Fail 'E40' (L "$EXPECT_VERSION update not chosen" "mise à jour $EXPECT_VERSION non choisie") }
                $Script:Inputs.update = $u; $Script:Inputs.update_version = $null
                Save-Inputs
            }
            return
        }
    }
    $Script:Inputs = @{}
    if ($prev) { $Script:Inputs.titlekeys = $prev.titlekeys; $Script:Inputs.firmware = $prev.firmware }   # (the WindowSmash kit's, kept)
    $k = Pick-File (L '1/3 - Choose your prod.keys file' '1/3 - Choisis ton fichier prod.keys') (L 'Keys (prod.keys)|prod.keys;*.keys|All files|*.*' 'Clés (prod.keys)|prod.keys;*.keys|Tous les fichiers|*.*') ''
    if (-not $k) { Fail 'E40' (L 'prod.keys not chosen' 'prod.keys non choisi') }
    $Script:Inputs.prodkeys = $k
    $b = Pick-File (L '2/3 - Choose the Smash Ultimate BASE GAME (version 1.0.0, .xci or .nsp)' '2/3 - Choisis le JEU DE BASE de Smash Ultimate (version 1.0.0, .xci ou .nsp)') (L 'Switch game (*.xci;*.nsp)|*.xci;*.nsp|All files|*.*' 'Jeu Switch (*.xci;*.nsp)|*.xci;*.nsp|Tous les fichiers|*.*') $k
    if (-not $b) { Fail 'E40' (L 'base game not chosen' 'jeu de base non choisi') }
    $Script:Inputs.base = $b
    $u = Pick-File (L "3/3 - Choose Smash Ultimate's $EXPECT_VERSION UPDATE (.nsp)" "3/3 - Choisis la MISE À JOUR $EXPECT_VERSION de Smash Ultimate (.nsp)") (L 'Update (*.nsp)|*.nsp|All files|*.*' 'Mise à jour (*.nsp)|*.nsp|Tous les fichiers|*.*') $b
    if (-not $u) { Fail 'E40' (L 'update not chosen' 'mise à jour non choisie') }
    $Script:Inputs.update = $u
    if (Ask-YesNo (L '  Do you have DLC (fighters) as .nsp files in a folder? (optional; for netplay, have the same ones)' '  As-tu des DLC (combattants) en .nsp dans un dossier ? (optionnel ; pour le netplay, ayez les mêmes)') $false) {
        $d = Pick-Folder (L 'Choose the folder that holds the DLC (.nsp)' 'Choisis le dossier qui contient les DLC (.nsp)')
        if ($d) { $Script:Inputs.dlc = $d }
    }
    Save-Inputs
}

# The DLC the player dumped from their own Switch: the .nsp files of the DLC folder chosen with either launcher.
function Get-DlcFiles {
    if (-not ($Script:Inputs.dlc -and (Test-Path -LiteralPath $Script:Inputs.dlc))) { return @() }
    return @(Get-ChildItem -LiteralPath $Script:Inputs.dlc -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.Extension -eq '.nsp' } | ForEach-Object { $_.FullName })
}

# Menu 4: the folder of the DLC the player bought, dumped from their own Switch (.nsp files; the WindowSmash launcher's
# option 6 uses the same folder, kept in inputs.json). The install flow then runs: OpenSmash's installer (its step 7)
# lists their add-on ids, read from the file names, in build\config\dlc.txt; the DLC fighters' data is in the game
# update and the game reads only that list, so nothing is recompiled.
function Add-DLC {
    Title (L 'Add my DLC (bought, dumped from your Switch)' 'Ajouter mes DLC (achetés, dumpés de ta Switch)')
    Say (L '  Choose the folder that holds your DLC: the .nsp files dumped from your Switch, with their names as dumped (they hold the [0100...] id). For netplay, have the same DLC as your friends.' '  Choisis le dossier qui contient tes DLC : les fichiers .nsp dumpés de ta Switch, avec leur nom d''origine (il contient l''identifiant [0100...]). En ligne, ayez les mêmes DLC que vos amis.')
    $d = Pick-Folder (L 'Choose the folder that holds your DLC (.nsp)' 'Choisis le dossier qui contient tes DLC (.nsp)')
    if (-not $d) { Fail 'E40' (L 'DLC folder not chosen' 'dossier des DLC non choisi') }
    $prev = Load-Inputs
    $Script:Inputs = @{}
    if ($prev) { foreach ($k in 'base', 'update', 'prodkeys', 'titlekeys', 'firmware', 'update_version') { $Script:Inputs[$k] = $prev.$k } }
    $Script:Inputs.dlc = $d
    $n = @(Get-DlcFiles).Count
    if (-not $n) { Set-Step 'DLC' 'FAILED' 'no .nsp'; Fail 'E44' (L "no .nsp file in $d" "aucun fichier .nsp dans $d") }
    Save-Inputs
    Ok (L "$n DLC package(s) in $d" "$n DLC dans $d")
    Set-Step 'DLC' 'OK' "$n package(s)"
}

# The game program's build id (an NSO's module id, bytes 0x40-0x53 of its header) says which update it comes from.
function Get-MainVersion([string]$main) {
    if (-not (Test-Path -LiteralPath $main)) { return $null }
    $fs = [IO.File]::OpenRead($main)
    try { $h = New-Object byte[] 0x60; [void]$fs.Read($h, 0, 0x60) } finally { $fs.Dispose() }
    if ([Text.Encoding]::ASCII.GetString($h, 0, 4) -ne 'NSO0') { return 'not an NSO' }
    $id = -join ($h[0x40..0x53] | ForEach-Object { $_.ToString('X2') })
    $Script:Info['Game program build id'] = $id
    if ($BUILD_IDS.ContainsKey($id)) { return $BUILD_IDS[$id] }
    return "unknown ($($id.Substring(0, 8)))"
}

# OpenSmash's install location: <repo>\build, or the folder written in build_location.txt (scripts\build_location.py).
function Get-BuildDir {
    $loc = Join-Path $Script:Repo 'build_location.txt'
    if (Test-Path -LiteralPath $loc) {
        $p = "$(Get-Content -LiteralPath $loc -TotalCount 1 -Encoding UTF8)".Trim().Trim('"')
        if ($p) {
            $p = [Environment]::ExpandEnvironmentVariables($p)
            if (-not [IO.Path]::IsPathRooted($p)) { $p = Join-Path $Script:Repo $p }
            return $p
        }
    }
    return (Join-Path $Script:Repo 'build')
}

function Get-Exe { return (Join-Path (Get-BuildDir) 'work\ssbu_native.exe') }

# The update the build folder was last built from (setup.py's state.json), or $null.
function Get-BuiltVersion {
    try { return (Get-Content -LiteralPath (Join-Path (Get-BuildDir) 'state.json') -Raw | ConvertFrom-Json).game_version } catch { return $null }
}

function Min-Step([string]$a, [string]$b) {
    $ia = [array]::IndexOf($SETUP_STEPS, $a); $ib = [array]::IndexOf($SETUP_STEPS, $b)
    if ($ia -lt 0) { return $b }
    if ($ib -lt 0 -or $ia -le $ib) { return $a }
    return $b
}

# The setup.py step the build must repeat from ('-': none forced; setup.py then redoes what its sources made old), as
# OpenSmash's own self-update decides it: scripts\update.py's rebuild_advice on the files changed since the oldest
# version not built yet.
function Get-RebuildStep {
    if (-not (Test-Path -LiteralPath $RebuildTxt)) { return '-' }
    $old = (Get-Content -LiteralPath $RebuildTxt -Raw).Trim()
    $files = @(Run-Native { & $Script:Git -C $Script:Repo diff --name-only $old HEAD 2>&1 })
    if ($LASTEXITCODE) { Log "git diff from $old impossible: $($files -join ' | ')"; return '-' }
    $list = Join-Path $LogDir 'changed-files.txt'
    [IO.File]::WriteAllLines($list, [string[]]$files)
    $code = "import re, sys; sys.path.insert(0, sys.argv[1]); import update; m = [re.search(r'--from (\w+)', x) for x in update.rebuild_advice([p.strip() for p in open(sys.argv[2], encoding='utf-8-sig') if p.strip()])]; m = [x.group(1) for x in m if x]; print(m[0] if m else '-')"
    $out = @(Run-Native { & $Script:Py -I -c $code (Join-Path $Script:Repo 'scripts') $list 2>&1 })
    $step = "$($out | Select-Object -Last 1)".Trim()
    Log "changed since $($old.Substring(0, 7)): $($files.Count) files -> setup step '$step' (exit $LASTEXITCODE)"
    if ($LASTEXITCODE -or ($step -ne '-' -and $SETUP_STEPS -notcontains $step)) { return '-' }
    return $step
}

# OpenSmash's own installer, never updating itself and making no shortcuts of its own (they would bypass the launcher).
# -> the exit code
function Invoke-OsInstall([string[]]$extra, [string]$name) {
    $argv = @('-u', (Join-Path $Script:Repo 'scripts\install.py'), '--no-gui', '--no-self-update', '--no-shortcuts',
              '--base', $Script:Inputs.base, '--update', $Script:Inputs.update, '--keys', $Script:Inputs.prodkeys)
    foreach ($f in (Get-DlcFiles)) { $argv += @('--dlc', $f) }
    if ($Script:Inputs.firmware -and (Test-Path -LiteralPath $Script:Inputs.firmware -PathType Container)) { $argv += @('--firmware', $Script:Inputs.firmware) }
    return (Run-Shown $Script:Py ($argv + $extra) $name)
}

# A game unpacked earlier from another update (an OpenSmash install made with 13.0.4) is removed, so that install.py
# makes it again from the files given. -> $true when removed
function Remove-StaleDump([string]$dump) {
    $v0 = Get-MainVersion (Join-Path $dump 'exefs\main')
    if (-not $v0 -or $v0 -eq $EXPECT_VERSION) { return $false }
    Say (L "  The game unpacked earlier is $v0 : it is made again from your files." "  Le jeu décompressé avant est en $v0 : il est refait avec tes fichiers.")
    if ((Get-Item -LiteralPath $dump -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { [IO.Directory]::Delete($dump, $false) }   # (a link: only the link goes)
    else { Remove-Item -LiteralPath $dump -Recurse -Force }
    return $true
}

function Install-Game {
    Title (L "The game files (OpenSmash's installer: the update, the unpacked game)" 'Les fichiers du jeu (installateur d''OpenSmash : la mise à jour, le jeu décompressé)')
    $dlc = @(Get-DlcFiles)
    $Script:Info['DLC'] = "$($dlc.Count) package(s)$(if ($Script:Inputs.dlc) { " in $($Script:Inputs.dlc)" })"
    $force = '-'
    $dump = Join-Path (Get-BuildDir) 'dump'
    if (Remove-StaleDump $dump) { $force = 'convert' }
    $rc = Invoke-OsInstall @('--prepare-only') 'install-prepare'
    if ($rc -ne 0) { Set-Step 'Files' 'FAILED' "install.py $rc"; Fail 'E60' (L "OpenSmash's installer stopped (code $rc)" "l'installateur d'OpenSmash s'est arrêté (code $rc)") }
    $v = Get-MainVersion (Join-Path $dump 'exefs\main')
    $Script:Info['Game version'] = "$v"
    if ($v -ne $EXPECT_VERSION) {
        if ($v -match '^\d+\.\d+\.\d+$') { $Script:Inputs.update_version = $v; Save-Inputs }     # (asked for again at the next start)
        Set-Step 'Files' 'FAILED' "game $v"
        Fail 'E43' (L "the game made from these files is $v, the group plays $EXPECT_VERSION" "le jeu fait avec ces fichiers est en $v, le groupe joue en $EXPECT_VERSION")
    }
    $Script:Inputs.update_version = $v; Save-Inputs
    Ok (L "game $v" "jeu en $v")
    if ($dlc.Count) {
        $list = Join-Path (Get-BuildDir) 'config\dlc.txt'
        $rows = @(if (Test-Path -LiteralPath $list) { Get-Content -LiteralPath $list | Where-Object { $_ -match '^\s*(0x[0-9a-fA-F]+|\d+)' } })
        $Script:Info['DLC listed'] = "$($rows.Count) add-on content(s) in $list"
        if ($rows.Count) { Ok (L "DLC: $($rows.Count) add-on content(s) listed" "DLC : $($rows.Count) contenus additionnels listés") }
        else { Warn (L "W44 none of the $($dlc.Count) DLC file names holds its [0100...] id: give them back their names as dumped" "W44 aucun des $($dlc.Count) noms de fichiers DLC ne contient son identifiant [0100...] : remets-leur leur nom d'origine") }
    }
    Set-Step 'Files' 'OK' "$v, DLC $($dlc.Count)"
    Stop-Test 'prepare'

    Title (L 'The game build (OpenSmash, 1 to 3 hours the first time)' 'La compilation du jeu (OpenSmash, 1 à 3 heures la première fois)')
    $built = Get-BuiltVersion
    if ($built -and $built -ne $EXPECT_VERSION) { $force = 'convert' }    # (built from another update: every step again)
    $step = Min-Step $force (Get-RebuildStep)
    $os = Get-CimInstance Win32_OperatingSystem
    $ram = (Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB
    $cpu = (Get-CimInstance Win32_Processor | Measure-Object NumberOfLogicalProcessors -Sum).Sum
    $jobs = [int][math]::Max(1, [math]::Min($cpu, [math]::Floor(($ram - 4) / 1.5)))
    $freeVirt = [math]::Round($os.FreeVirtualMemory / 1MB, 1)
    if ($freeVirt -lt 8) { Warn (L "W60 only $freeVirt GB of free memory: close games and browsers during the compile" "W60 seulement $freeVirt Go de mémoire libre : ferme les jeux et navigateurs pendant la compilation") }
    Say (L '  Leave the PC on. If it stops, start the OpenSmash Launcher again: it carries on where it was.' '  Laisse le PC allumé. Si ça s''arrête, relance OpenSmash Launcher : ça reprend où ça en était.')
    for ($attempt = 1; ; $attempt++) {
        $extra = @('--jobs', "$jobs")
        if ($step -ne '-') { $extra += @('--reexec', $step) }       # (install.py's way to make setup.py repeat from a step)
        $Script:Info['Build'] = "jobs $jobs, from step $step, built before: $(if ($built) { $built } else { 'nothing' })"
        Say (L "  Attempt $attempt with $jobs job(s) at a time$(if ($step -ne '-') { ", from step $step" })..." "  Tentative $attempt avec $jobs tâche(s) en parallèle$(if ($step -ne '-') { ", depuis l'étape $step" })...")
        $rc = Invoke-OsInstall $extra "install-build-$attempt"
        if ($rc -eq 0) { break }
        $oom = Select-String -LiteralPath $Script:LastLog -Pattern 'out of memory|bad_alloc|not enough memory|paging file is too small' -Quiet
        if ($oom -and $jobs -gt 1) {
            $jobs = [int][math]::Max(1, [math]::Floor($jobs / 2))
            Warn (L "W61 out of memory during the compile: trying again with $jobs job(s)" "W61 mémoire insuffisante pendant la compilation : nouvel essai avec $jobs tâche(s)")
            continue
        }
        Set-Step 'Build' 'FAILED' "install.py $rc"
        Fail 'E60' (L "OpenSmash's installer stopped (code $rc)" "l'installateur d'OpenSmash s'est arrêté (code $rc)")
    }
    if (-not (Test-Path -LiteralPath (Get-Exe))) { Set-Step 'Build' 'FAILED' 'no exe'; Fail 'E60' (L "the build ended without $(Get-Exe)" "la compilation s'est terminée sans $(Get-Exe)") }
    Remove-Item -LiteralPath $RebuildTxt -Force -ErrorAction SilentlyContinue
    Ok (L 'game built' 'jeu compilé')
    Set-Step 'Build' 'OK' "jobs $jobs"
}

# Shortcuts through this launcher (play mode checks the version first). OpenSmash's own shortcuts of this folder start
# the game without that check ("SSBU native") or would update OpenSmash ("SSBU native - Installer"): they go.
function Set-Shortcuts {
    $launcher = Join-Path $env:LOCALAPPDATA 'WindowSmashLauncher\OpenSmash Launcher.bat'
    if (-not (Test-Path -LiteralPath $launcher)) { Warn (L 'W71 the launcher''s own copy is missing: no shortcuts' 'W71 la copie du launcher manque : pas de raccourcis'); return }
    $exe = Get-Exe
    $sh = New-Object -ComObject WScript.Shell
    foreach ($dir in @($Desktop, [Environment]::GetFolderPath('Programs'))) {
        try {
            foreach ($n in @('SSBU native.lnk', 'SSBU native - Installer.lnk')) {
                $p = Join-Path $dir $n
                if ((Test-Path -LiteralPath $p) -and ($sh.CreateShortcut($p).TargetPath -like "$($Script:Repo)\*")) { Remove-Item -LiteralPath $p -Force; Log "removed $p" }
            }
            $lnk = $sh.CreateShortcut((Join-Path $dir 'Smash Ultimate (OpenSmash).lnk'))
            $lnk.TargetPath = $launcher; $lnk.Arguments = 'play'; $lnk.WorkingDirectory = (Split-Path $launcher -Parent)
            if (Test-Path -LiteralPath $exe) { $lnk.IconLocation = "$exe,0" }
            $lnk.Save()
            $l2 = $sh.CreateShortcut((Join-Path $dir 'OpenSmash Launcher.lnk'))
            $l2.TargetPath = $launcher; $l2.WorkingDirectory = (Split-Path $launcher -Parent)
            $l2.Save()
            Ok (L "shortcuts made: $dir" "raccourcis créés : $dir")
        } catch { Warn (L "W71 shortcut not made in $dir ($($_.Exception.Message))" "W71 raccourci non créé dans $dir ($($_.Exception.Message))") }
    }
}

# rollback = on / off in the build's config\graphics.ini: scripts\run.py reads it to start the game with the rollback
# netcode (SSBU_RB_NET), and the game's F1 menu shows and changes it. Written the way the game writes it (gfx_ini_set:
# the first "rollback =" line replaced, else one added; CRLF, no BOM). A file made here holds only that line: the game
# writes its documented defaults only when the file is missing, and reads the defaults for every key it lacks.
function Set-Rollback([bool]$on) {
    $ini = Join-Path (Get-BuildDir) 'config\graphics.ini'
    $v = if ($on) { 'on' } else { 'off' }
    try {
        New-Item -ItemType Directory -Force (Split-Path $ini -Parent) | Out-Null
        $text = if (Test-Path -LiteralPath $ini) { [IO.File]::ReadAllText($ini) } else { "; graphics.ini made by the OpenSmash Launcher for the rollback setting; the other settings keep their defaults (F1 in the game changes them).`r`n" }
        $done = $false
        $out = foreach ($ln in [regex]::Split($text, '(?<=\n)')) {
            if (-not $done -and $ln -match '^[ \t]*rollback[ \t]*=') { $done = $true; "rollback = $v`r`n" } else { $ln }
        }
        $t = -join $out
        if (-not $done) { if ($t -and -not $t.EndsWith("`n")) { $t += "`r`n" }; $t += "rollback = $v`r`n" }
        [IO.File]::WriteAllText($ini, $t, (New-Object Text.UTF8Encoding $false))
        Log "rollback = $v in $ini"
        return $true
    } catch { Warn (L "W72 rollback setting not written ($($_.Exception.Message))" "W72 réglage du rollback non écrit ($($_.Exception.Message))"); return $false }
}

# Play SSBU.bat (scripts\run.py --play), rollback on. The game must still run 15 s after it appeared (the WindowSmash
# kit's check); a failure's report holds the end of the newest build\logs\game_*.log (run.py's game log).
function Start-Game {
    $play = Join-Path $Script:Repo 'Play SSBU.bat'
    if (Set-Rollback $true) { Say (L '  Rollback netcode: ON (1-on-1 Local Wireless rooms where both players have it on; other fights as usual).' '  Rollback : ON (rooms Local Wireless à 2 où les deux joueurs l''ont ; les autres combats comme d''habitude).') }
    $gameLog = { Get-ChildItem -LiteralPath (Join-Path (Get-BuildDir) 'logs') -Filter 'game_*.log' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime | Select-Object -Last 1 | ForEach-Object { $_.FullName } }
    try {
        $p = Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\cmd.exe') -ArgumentList '/c', "`"$play`"" -WorkingDirectory $Script:Repo -PassThru
        $null = $p.Handle      # (Windows PowerShell 5.1 loses the exit code of a process whose handle was never asked for)
        for ($i = 0; $i -lt 120 -and -not $p.HasExited -and -not (Get-Process ssbu_native -ErrorAction SilentlyContinue); $i++) { Start-Sleep -Milliseconds 500 }
        if (-not (Get-Process ssbu_native -ErrorAction SilentlyContinue)) {
            if ($p.HasExited) { Fail 'E70' ((L 'Play SSBU.bat ended (code {0}) without the game' 'Play SSBU.bat s''est terminé (code {0}) sans le jeu') -f $p.ExitCode) (& $gameLog) }
            Say (L '  The game is still starting (see the Play SSBU window).' '  Le jeu démarre encore (voir la fenêtre Play SSBU).')
            return
        }
        Start-Sleep -Seconds 15
        if (-not (Get-Process ssbu_native -ErrorAction SilentlyContinue)) { Fail 'E70' (L 'the game closed at once' 'le jeu s''est fermé tout de suite') (& $gameLog) }
        Ok (L 'game started (F1 in the game: settings)' 'jeu lancé (F1 dans le jeu : réglages)')
    } catch { Fail 'E70' "$($_.Exception.Message)" }
}

# ---- main -----------------------------------------------------------------------------------------------------------
try {
    $header = {
        Clear-Host
        Write-Host (L "OpenSmash Launcher (native Super Smash Bros. Ultimate, with rollback) - kit $KitVersion" "OpenSmash Launcher (Super Smash Bros. Ultimate natif, avec rollback) - kit $KitVersion") -ForegroundColor Cyan
        Write-Host (L "Everyone gets the same OpenSmash version ($($OS_COMMIT.Substring(0,7))) and game $EXPECT_VERSION, so you can play together." "Tout le monde a la même version d'OpenSmash ($($OS_COMMIT.Substring(0,7))) et le jeu en $EXPECT_VERSION : vous pouvez jouer ensemble.")
    }
    & $header
    Log "kit $KitVersion, KitDir=$KitDir, Mode=$Mode"
    $Script:Git = Find-Git
    if (-not $Script:Git) { Fail 'E12' (L 'Git not found' 'Git introuvable') }
    while (-not $Mode) {
        Write-Host ''
        Write-Host (L '  1) Install / update' '  1) Installer / mettre à jour')
        Write-Host (L '  2) Start the game (rollback ON)' '  2) Lancer le jeu (rollback ON)')
        Write-Host (L '  3) Diagnosis only (makes the report, installs nothing)' '  3) Diagnostic seulement (crée le rapport sans rien installer)')
        Write-Host (L '  4) Add my DLC (bought, dumped from your Switch)' '  4) Ajouter mes DLC (achetés, dumpés de ta Switch)')
        Write-Host (L '  5) Français (passer le launcher en français)' '  5) English (switch the launcher to English)')
        $m = "$(Read-Host (L '  Your choice [1]' '  Ton choix [1]'))".Trim()
        if ($m -eq '5') { Set-Language $(if ($Script:Lang -eq 'fr') { 'en' } else { 'fr' }); Log "language $Script:Lang"; & $header; continue }
        $Mode = @{ '2' = 'play'; '3' = 'diag'; '4' = 'dlc' }[$m]
        if (-not $Mode) { $Mode = 'install' }
    }
    $quietInputs = $false
    if ($Mode -eq 'dlc') { Add-DLC; $quietInputs = $true; $Mode = 'install' }     # (then the install flow: quick once built)
    $Script:Info['Kit'] = $KitVersion
    $Script:Info['Git'] = $Script:Git
    $lr = Split-Path $PSScriptRoot -Parent     # the launcher's clone of its repository: which revision ran
    if (Test-Path -LiteralPath (Join-Path $lr '.git')) { $Script:Info['Launcher (git)'] = (Run-Native { & $Script:Git -C $lr log -1 '--format=%h %cs' }) | Select-Object -First 1 }
    if ($Mode -eq 'play') {
        if (Find-Repo $false) {
            $head = Get-Head
            if (-not (Test-Path -LiteralPath (Get-Exe))) { Say (L '  The game is not built yet: the install starts.' '  Le jeu n''est pas encore compilé : l''installation démarre.'); $Mode = 'install' }
            elseif ($head -ne $OS_COMMIT -or (Test-Path -LiteralPath $RebuildTxt)) {
                $h7 = if ($head) { $head.Substring(0,7) } else { '?' }
                if ($head -ne $OS_COMMIT) { Say (L "  New OpenSmash version ($h7 -> $($OS_COMMIT.Substring(0,7))): to play online, you need the same as your friends." "  Nouvelle version d'OpenSmash ($h7 -> $($OS_COMMIT.Substring(0,7))) : pour jouer en ligne, il faut la même que tes amis.") }
                else { Say (L '  The last update was not finished.' '  La dernière mise à jour n''a pas été terminée.') }
                if (Ask-YesNo (L '  Update now? (recompile: minutes to an hour)' '  Je fais la mise à jour maintenant ? (recompilation : quelques minutes à une heure)')) { $Mode = 'install' }
            }
            if ($Mode -eq 'play') { Start-Game; exit 0 }
        } else { $Mode = 'install' }
    }
    if ($Mode -eq 'diag') {
        if (Find-Repo $false) {
            $Script:Info['OpenSmash (git)'] = "$(Get-Head) (pinned: $OS_COMMIT)"
            $Script:Info['Game version'] = "unpacked: $(Get-MainVersion (Join-Path (Get-BuildDir) 'dump\exefs\main')); built: $(Get-BuiltVersion)"
            $Script:Info['Game exe'] = "$(Get-Exe) $(if (Test-Path -LiteralPath (Get-Exe)) { 'present' } else { 'missing' })"
        }
        Write-Report 'DIAGNOSTIC'
        Say (L '  Report written on the Desktop: OpenSmash-setup-report.txt' '  Rapport écrit sur le Bureau : OpenSmash-setup-report.txt')
        if (-not $env:WS_NO_NOTEPAD) { try { Start-Process notepad.exe -ArgumentList "`"$Report`"" } catch {} }
        Read-Host (L 'Enter to close' 'Entrée pour fermer'); exit 0
    }
    $null = Find-Repo $true
    Stop-Test 'repo'
    Ensure-Revision
    Stop-Test 'revision'
    Ensure-Python
    Stop-Test 'python'
    Ask-Inputs $quietInputs
    Install-Game
    Title (L 'Done' 'Terminé')
    Set-Shortcuts
    Write-Report 'OK'
    Say (L "  To play: the 'Smash Ultimate (OpenSmash)' shortcut (it checks the version at every start, rollback ON)." "  Pour jouer : le raccourci 'Smash Ultimate (OpenSmash)' (il vérifie la version à chaque lancement, rollback ON).")
    Say (L '  Rollback plays 1-on-1 Local Wireless rooms where both players have it on; other rooms and local fights play as usual.' '  Le rollback sert dans les rooms Local Wireless à 2 où les deux joueurs l''ont ; les autres rooms et les combats locaux jouent comme d''habitude.')
    Say (L '  The launcher turns rollback on at every start. In the game: F1 = settings.' '  Le launcher active le rollback à chaque lancement. Dans le jeu : F1 = réglages.')
    Say (L '  Do not use OpenSmash''s own "Install SSBU.bat": it would update OpenSmash past your friends'' version.' '  N''utilise pas le "Install SSBU.bat" d''OpenSmash : il mettrait OpenSmash à jour au-delà de la version de tes amis.')
    if (Ask-YesNo (L '  Start the game now?' '  Je lance le jeu maintenant ?')) { Start-Game }
    Read-Host (L 'Enter to close' 'Entrée pour fermer')
    exit 0
} catch {
    $e = $_
    Log "UNEXPECTED $($e.Exception.GetType().FullName): $($e.Exception.Message)`r`n$($e.ScriptStackTrace)"
    $Script:Info['PowerShell error'] = "$($e.Exception.Message) | $($e.InvocationInfo.PositionMessage -replace '\s+', ' ')"
    Fail 'E99' "$($e.Exception.Message)"
}
