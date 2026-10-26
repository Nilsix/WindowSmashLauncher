@echo off
rem OpenSmash Launcher: installs, updates and starts OpenSmash (native Super Smash Bros. Ultimate with rollback,
rem github.com/OpenSmash-Ultimate/ssbu-recomp) from YOUR files, at the version pinned for the whole group.
rem On the first start it installs Git if missing and downloads the launcher (github.com/Nilsix/WindowSmashLauncher)
rem into %LOCALAPPDATA%\WindowSmashLauncher. At every start it updates itself (git) and, when it changed, closes and
rem starts again in its new version. Then it runs the kit (kit-opensmash\os_setup.ps1 of the repository).
rem Optional argument: install | play | diag | dlc (none: the menu). English, or French (menu 5).
setlocal
set "WSL_SELF=%~f0"
set "WSL_DIR=%~dp0"
set "WSL_MODE=%~1"
chcp 65001 >nul
title OpenSmash Launcher
rem Keep everything below up to "#@@BEGIN" ONE block in which every path ends with "exit": cmd.exe reads a batch file
rem line by line at byte offsets, and reads a whole block before running it, so it never reads this file again while
rem the update replaces it (here or in the repository copy). Delayed expansion is switched on only after the "set"
rem lines above, so a "!" in the path of this file stays as it is.
setlocal EnableDelayedExpansion
(
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; try { $t=[IO.File]::ReadAllText($env:WSL_SELF,[Text.Encoding]::UTF8); $m=[regex]::Match($t,'(?s)\r?\n#@@BEGIN boot\.ps1\r?\n(.*?)\r?\n#@@END boot\.ps1'); if(-not $m.Success){ throw 'launcher incomplet' }; $d=Join-Path $env:LOCALAPPDATA 'WindowSmashLauncher-boot'; New-Item -ItemType Directory -Force $d | Out-Null; $f=Join-Path $d ('boot-'+$PID+'.ps1'); [IO.File]::WriteAllText($f,$m.Groups[1].Value,(New-Object Text.UTF8Encoding $true)); & $f -Self $env:WSL_SELF -KitDir $env:WSL_DIR -Mode $env:WSL_MODE; $rc=$LASTEXITCODE; Remove-Item -LiteralPath $f -ErrorAction SilentlyContinue; exit $rc } catch { Write-Host ('Launcher start error / erreur au demarrage du launcher: '+$_.Exception.Message) -ForegroundColor Red; exit 2 }"
set "RC=!ERRORLEVEL!"
if "!RC!"=="0" exit /b 0
if "!RC!"=="10" exit /b 10
if "!RC!"=="20" exit /b 0
echo.
echo The launcher stopped with code !RC!. Send a screenshot of this window. / Le launcher s'est arrete, code !RC! : envoie une capture de cette fenetre.
pause
exit /b !RC!
)
#@@BEGIN boot.ps1
# OpenSmash Launcher - the bootstrap (Windows PowerShell 5.1), extracted from "OpenSmash Launcher.bat" and run by it.
# The same as the one of "WindowSmash Launcher.bat" but for the names; both use the same clone of the repository.
# 1. Git: found, or installed (winget, else the official Git for Windows installer, its SHA-256 and signature checked).
# 2. The launcher repository, kept in %LOCALAPPDATA%\WindowSmashLauncher: cloned the first time, updated every time
#    (fetch + reset to the remote branch: that folder belongs to the launcher, nothing in it is edited by hand).
# 3. The file the user started (Desktop, Downloads...) is kept identical to the repository's copy.
# 4. After a change (and after the first clone), the window closes and the repository's copy of this file starts in a
#    new window (WSL_RELAUNCHED stops a second restart).
# 5. kit-opensmash\os_setup.ps1 of the repository does the rest (install, play, diag, dlc).
# Exit codes for the .bat: 0 done, 10 a failure already reported (it paused), 20 restarted in a new window.
# Test-only environment: WSL_NO_RELAUNCH=1 (carry on in the same window after an update), WSL_REPO_URL (another remote),
# WSL_CLONE_DIR (another clone folder; never fake LOCALAPPDATA instead).
# Messages: English, or French when %LOCALAPPDATA%\WindowSmash-setup\lang.txt says fr (the kits' language option writes it).
param([string]$Self = '', [string]$KitDir = '', [string]$Mode = '')

$Lang = 'en'
try { if ((Get-Content -LiteralPath (Join-Path $env:LOCALAPPDATA 'WindowSmash-setup\lang.txt') -Raw -ErrorAction Stop).Trim() -eq 'fr') { $Lang = 'fr' } } catch {}
function L([string]$en, [string]$fr) { if ($Lang -eq 'fr') { return $fr } return $en }

$ErrorActionPreference = 'Stop'
$LauncherUrl = if ($env:WSL_REPO_URL) { $env:WSL_REPO_URL } else { 'https://github.com/Nilsix/WindowSmashLauncher.git' }
$Clone   = if ($env:WSL_CLONE_DIR) { $env:WSL_CLONE_DIR } else { Join-Path $env:LOCALAPPDATA 'WindowSmashLauncher' }
$GIT_URL = 'https://github.com/git-for-windows/git/releases/download/v2.56.0.windows.2/Git-2.56.0.2-64-bit.exe'
$GIT_SHA = '52188f917b378f00c70ec136bcf090005f30d44fbc4eba0bce759cc6592d60f6'
$env:GIT_TERMINAL_PROMPT = '0'      # a public repository: fail with a message instead of asking for a login
$env:GCM_INTERACTIVE = 'never'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}
try {       # boot files left behind by windows closed with their X button
    Get-ChildItem -LiteralPath (Split-Path $PSCommandPath -Parent) -Filter 'boot-*.ps1' |
        Where-Object { $_.FullName -ne $PSCommandPath -and $_.LastWriteTime -lt (Get-Date).AddDays(-1) } | Remove-Item -Force
} catch {}

function Stop-Boot([string]$msg) {
    Write-Host ''
    Write-Host "  $(L 'Launcher FAILED' 'ÉCHEC du launcher') : $msg" -ForegroundColor Red
    Write-Host (L '  Check your internet connection, then start again. If it goes on, send a screenshot of this window.' '  Vérifie ta connexion internet puis relance. Si ça continue, envoie une capture de cette fenêtre.') -ForegroundColor Yellow
    Read-Host (L 'Press Enter to close' 'Appuie sur Entrée pour fermer')
    exit 10
}

function Find-Git {
    $g = Get-Command git -ErrorAction SilentlyContinue
    if ($g) { return $g.Source }
    foreach ($p in @("$env:ProgramFiles\Git\cmd\git.exe", "${env:ProgramFiles(x86)}\Git\cmd\git.exe", "$env:LOCALAPPDATA\Programs\Git\cmd\git.exe")) {
        if (Test-Path -LiteralPath $p) { return $p }
    }
    return $null
}

function Ensure-Git {
    $git = Find-Git
    if ($git) { return $git }
    Write-Host (L '  Git is not installed: installing it (it downloads and updates OpenSmash).' '  Git n''est pas installé : je l''installe (il sert à télécharger et mettre à jour OpenSmash).') -ForegroundColor Yellow
    Write-Host (L '  An administrator window may open: accept it.' '  Une fenêtre administrateur peut s''ouvrir : accepte-la.')
    $wg = Get-Command winget -ErrorAction SilentlyContinue
    if ($wg) {
        $ErrorActionPreference = 'Continue'
        & $wg.Source install -e --id Git.Git --silent --accept-package-agreements --accept-source-agreements | Out-Host
        $ErrorActionPreference = 'Stop'
        $git = Find-Git
        if ($git) { return $git }
    }
    $dir = Join-Path $env:LOCALAPPDATA 'WindowSmash-setup\downloads'
    New-Item -ItemType Directory -Force $dir | Out-Null
    $inst = Join-Path $dir 'Git-2.56.0.2-64-bit.exe'
    if (-not (Test-Path -LiteralPath $inst) -or (Get-FileHash -LiteralPath $inst -Algorithm SHA256).Hash.ToLower() -ne $GIT_SHA) {
        Write-Host (L '  Downloading Git 2.56.0 (65 MB)...' '  Téléchargement de Git 2.56.0 (65 Mo)...')
        $curl = Join-Path $env:SystemRoot 'System32\curl.exe'
        if (Test-Path -LiteralPath $curl) {
            $ErrorActionPreference = 'Continue'; & $curl -L --fail --retry 3 -o "$inst.part" $GIT_URL; $ErrorActionPreference = 'Stop'
        } else {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            $ProgressPreference = 'SilentlyContinue'
            try { Invoke-WebRequest -Uri $GIT_URL -OutFile "$inst.part" -UseBasicParsing } catch {}
        }
        if (-not (Test-Path -LiteralPath "$inst.part")) { Stop-Boot (L 'Git download failed' 'téléchargement de Git impossible') }
        if ((Get-FileHash -LiteralPath "$inst.part" -Algorithm SHA256).Hash.ToLower() -ne $GIT_SHA) { Remove-Item -LiteralPath "$inst.part" -Force; Stop-Boot (L 'downloaded Git installer damaged (different SHA-256)' 'installateur de Git téléchargé abîmé (empreinte SHA-256 différente)') }
        Move-Item -LiteralPath "$inst.part" -Destination $inst -Force
    }
    $sig = Get-AuthenticodeSignature -LiteralPath $inst
    if ($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch 'Johannes Schindelin') { Stop-Boot (L "the Git installer's signature is not valid ($($sig.Status))" "signature de l'installateur de Git invalide ($($sig.Status))") }
    Write-Host (L '  Installing Git...' '  Installation de Git...')
    try { $p = Start-Process -FilePath $inst -ArgumentList '/VERYSILENT /NORESTART /NOCANCEL /SP- /SUPPRESSMSGBOXES' -Wait -PassThru }
    catch { Stop-Boot (L "Git install cancelled or impossible ($($_.Exception.Message))" "installation de Git annulée ou impossible ($($_.Exception.Message))") }
    $git = Find-Git
    if (-not $git) { Stop-Boot (L "Git not found after its install (code $($p.ExitCode)): install it from git-scm.com, then start again" "Git introuvable après son installation (code $($p.ExitCode)) : installe-le depuis git-scm.com puis relance") }
    return $git
}

function Run-Git([string[]]$a) {
    $ErrorActionPreference = 'Continue'
    $out = & $Script:Git @a 2>&1 | ForEach-Object { "$_" }
    $Script:GitCode = $LASTEXITCODE
    return $out
}

Write-Host 'OpenSmash Launcher' -ForegroundColor Cyan
$Script:Git = Ensure-Git
$updated = $false
# (a clone made by the WindowSmash launcher before kit-opensmash existed is not cloned again: the update below brings it)
if (-not (Test-Path -LiteralPath (Join-Path $Clone '.git')) -or -not ((Test-Path -LiteralPath (Join-Path $Clone 'kit-opensmash\os_setup.ps1')) -or (Test-Path -LiteralPath (Join-Path $Clone 'kit\ws_setup.ps1')))) {
    Write-Host (L '  First start: downloading the launcher...' '  Premier lancement : téléchargement du launcher...')
    if (Test-Path -LiteralPath $Clone) {       # an attempt that stopped half way, or a damaged copy: emptied (the folder itself may be in use)
        try { Get-ChildItem -LiteralPath $Clone -Force | Remove-Item -Recurse -Force } catch { Stop-Boot (L "cannot empty $Clone ($($_.Exception.Message))" "impossible de vider $Clone ($($_.Exception.Message))") }
    }
    $ErrorActionPreference = 'Continue'; & $Script:Git clone --quiet $LauncherUrl $Clone | Out-Host; $code = $LASTEXITCODE; $ErrorActionPreference = 'Stop'
    if ($code -ne 0 -or -not (Test-Path -LiteralPath (Join-Path $Clone 'kit-opensmash\os_setup.ps1'))) { Stop-Boot (L "git clone of $LauncherUrl failed (code $code)" "git clone de $LauncherUrl a échoué (code $code)") }
    $updated = $true
} else {
    $before = (Run-Git @('-C', $Clone, 'rev-parse', 'HEAD')) | Select-Object -First 1
    $null = Run-Git @('-C', $Clone, 'fetch', '--quiet', 'origin')
    if ($Script:GitCode -ne 0) {
        Write-Host (L '  No connection to the launcher repository: carrying on with the version already here.' '  Pas de connexion au dépôt du launcher : je continue avec la version déjà là.') -ForegroundColor Yellow
    } else {
        $after = (Run-Git @('-C', $Clone, 'rev-parse', '@{u}')) | Select-Object -First 1
        if ($Script:GitCode -eq 0 -and $after -and $after -ne $before) {
            $null = Run-Git @('-C', $Clone, 'reset', '--hard', '--quiet', $after)
            if ($Script:GitCode -ne 0) { Stop-Boot (L 'launcher update impossible (git reset)' 'mise à jour du launcher impossible (git reset)') }
            $b7 = if ($before) { $before.Substring(0, 7) } else { '?' }
            Write-Host "  $(L 'Launcher updated' 'Launcher mis à jour') ($b7 -> $($after.Substring(0, 7)))." -ForegroundColor Green
            $updated = $true
        }
    }
}

# cmd.exe misreads a batch file whose lines end with a bare LF (a test with such a copy ran fragments of its lines as
# commands): a repository copy like that, or one without its boot part, is neither copied nor started.
$repoBat = Join-Path $Clone 'OpenSmash Launcher.bat'
$repoOk = $false
try {
    $rt = [IO.File]::ReadAllText($repoBat)
    $repoOk = -not [regex]::IsMatch($rt, '(?<!\r)\n') -and $rt.Contains("`r`n#@@BEGIN boot.ps1`r`n") -and $rt.Contains("`r`n#@@END boot.ps1")
} catch {}
if (-not $repoOk) { Write-Host (L '  (the launcher copy in the repository is damaged: keeping this one and carrying on)' '  (la copie du launcher dans le dépôt est abîmée : je garde celle-ci et je continue)') -ForegroundColor Yellow }

# The file the user started (Desktop, Downloads...) is refreshed with the repository's copy. Safe while that file is
# running: cmd.exe has already read the whole block that started this script and does not read the file again.
if ($repoOk -and $Self -and (Test-Path -LiteralPath $Self)) {
    try {
        $own = (Resolve-Path -LiteralPath $Self).Path
        if ($own -ne (Resolve-Path -LiteralPath $repoBat).Path -and (Get-FileHash -LiteralPath $own).Hash -ne (Get-FileHash -LiteralPath $repoBat).Hash) {
            Copy-Item -LiteralPath $repoBat -Destination $own -Force
            Write-Host "  $(Split-Path $own -Leaf) $(L 'updated' 'mis à jour')."
        }
    } catch { Write-Host "  ($(L 'launcher copy not updated' 'copie du launcher non mise à jour') : $($_.Exception.Message))" -ForegroundColor Yellow }
}

if ($repoOk -and $updated -and -not $env:WSL_RELAUNCHED -and -not $env:WSL_NO_RELAUNCH) {
    Write-Host (L '  Restarting in the new version...' '  Redémarrage dans la nouvelle version...')
    $env:WSL_RELAUNCHED = '1'
    $env:WSL_KITDIR = $KitDir
    Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\cmd.exe') -ArgumentList @('/c', ('""' + $repoBat + '" ' + $Mode + '"')) -WorkingDirectory $Clone
    exit 20
}

$kitDir = if ($env:WSL_KITDIR) { $env:WSL_KITDIR } else { $KitDir }
$osKit = Join-Path $Clone 'kit-opensmash\os_setup.ps1'
if (-not (Test-Path -LiteralPath $osKit)) { Stop-Boot (L 'the launcher could not download its OpenSmash part' 'le launcher n''a pas pu télécharger sa partie OpenSmash') }
& $osKit -KitDir $kitDir -Mode $Mode
exit $LASTEXITCODE
#@@END boot.ps1
