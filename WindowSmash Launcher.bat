@echo off
rem WindowSmash Launcher : installe, met a jour et lance WindowSmash (Super Smash Bros. Ultimate natif) avec TES fichiers.
rem Au premier lancement il installe Git s'il manque et telecharge le launcher (github.com/Nilsix/WindowSmashLauncher)
rem dans %LOCALAPPDATA%\WindowSmashLauncher. A chaque lancement il se met a jour (git pull) et, s'il a change, il se
rem ferme et se relance dans sa nouvelle version. Il lance ensuite le kit (kit\ws_setup.ps1 du depot).
rem Argument optionnel : install | play | diag | unlock | optimize (sans argument : menu).
setlocal
set "WSL_SELF=%~f0"
set "WSL_DIR=%~dp0"
set "WSL_MODE=%~1"
chcp 65001 >nul
title WindowSmash Launcher
rem Keep everything below up to "#@@BEGIN" ONE block in which every path ends with "exit": cmd.exe reads a batch file
rem line by line at byte offsets, and reads a whole block before running it, so it never reads this file again while
rem the update replaces it (here or in the repository copy). Delayed expansion is switched on only after the "set"
rem lines above, so a "!" in the path of this file stays as it is.
setlocal EnableDelayedExpansion
(
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; try { $t=[IO.File]::ReadAllText($env:WSL_SELF,[Text.Encoding]::UTF8); $m=[regex]::Match($t,'(?s)\r?\n#@@BEGIN boot\.ps1\r?\n(.*?)\r?\n#@@END boot\.ps1'); if(-not $m.Success){ throw 'launcher incomplet' }; $d=Join-Path $env:LOCALAPPDATA 'WindowSmashLauncher-boot'; New-Item -ItemType Directory -Force $d | Out-Null; $f=Join-Path $d ('boot-'+$PID+'.ps1'); [IO.File]::WriteAllText($f,$m.Groups[1].Value,(New-Object Text.UTF8Encoding $true)); & $f -Self $env:WSL_SELF -KitDir $env:WSL_DIR -Mode $env:WSL_MODE; $rc=$LASTEXITCODE; Remove-Item -LiteralPath $f -ErrorAction SilentlyContinue; exit $rc } catch { Write-Host ('Erreur au demarrage du launcher : '+$_.Exception.Message) -ForegroundColor Red; exit 2 }"
set "RC=!ERRORLEVEL!"
if "!RC!"=="0" exit /b 0
if "!RC!"=="10" exit /b 10
if "!RC!"=="20" exit /b 0
echo.
echo Le launcher s'est arrete avec le code !RC!. Envoie une capture d'ecran de cette fenetre.
pause
exit /b !RC!
)
#@@BEGIN boot.ps1
# WindowSmash Launcher - the bootstrap (Windows PowerShell 5.1), extracted from "WindowSmash Launcher.bat" and run by it.
# 1. Git: found, or installed (winget, else the official Git for Windows installer, its SHA-256 and signature checked).
# 2. The launcher repository, kept in %LOCALAPPDATA%\WindowSmashLauncher: cloned the first time, updated every time
#    (fetch + reset to the remote branch: that folder belongs to the launcher, nothing in it is edited by hand).
# 3. The file the user started (Desktop, Downloads...) is kept identical to the repository's copy.
# 4. After a change (and after the first clone), the window closes and the repository's copy of this file starts in a
#    new window (WSL_RELAUNCHED stops a second restart).
# 5. kit\ws_setup.ps1 of the repository does the rest (install, play, diag, unlock, optimize).
# Exit codes for the .bat: 0 done, 10 a failure already reported (it paused), 20 restarted in a new window.
# Test-only environment: WSL_NO_RELAUNCH=1 (carry on in the same window after an update), WSL_REPO_URL (another remote),
# WSL_CLONE_DIR (another clone folder; never fake LOCALAPPDATA instead, see memory.md).
param([string]$Self = '', [string]$KitDir = '', [string]$Mode = '')

$ErrorActionPreference = 'Stop'
$LauncherUrl = if ($env:WSL_REPO_URL) { $env:WSL_REPO_URL } else { 'https://github.com/Nilsix/WindowSmashLauncher.git' }
$Clone   = if ($env:WSL_CLONE_DIR) { $env:WSL_CLONE_DIR } else { Join-Path $env:LOCALAPPDATA 'WindowSmashLauncher' }
$GIT_URL = 'https://github.com/git-for-windows/git/releases/download/v2.56.0.windows.2/Git-2.56.0.2-64-bit.exe'
$GIT_SHA = '52188f917b378f00c70ec136bcf090005f30d44fbc4eba0bce759cc6592d60f6'
$env:GIT_TERMINAL_PROMPT = '0'      # a public repository: fail with a message instead of asking for a login
$env:GCM_INTERACTIVE = 'never'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}

function Stop-Boot([string]$msg) {
    Write-Host ''
    Write-Host "  ÉCHEC du launcher : $msg" -ForegroundColor Red
    Write-Host '  Vérifie ta connexion internet puis relance. Si ça continue, envoie une capture de cette fenêtre.' -ForegroundColor Yellow
    Read-Host 'Appuie sur Entrée pour fermer'
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
    Write-Host '  Git n''est pas installé : je l''installe (il sert à télécharger et mettre à jour WindowSmash).' -ForegroundColor Yellow
    Write-Host '  Une fenêtre administrateur peut s''ouvrir : accepte-la.'
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
        Write-Host '  Téléchargement de Git 2.56.0 (65 Mo)...'
        $curl = Join-Path $env:SystemRoot 'System32\curl.exe'
        if (Test-Path -LiteralPath $curl) {
            $ErrorActionPreference = 'Continue'; & $curl -L --fail --retry 3 -o "$inst.part" $GIT_URL; $ErrorActionPreference = 'Stop'
        } else {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            $ProgressPreference = 'SilentlyContinue'
            try { Invoke-WebRequest -Uri $GIT_URL -OutFile "$inst.part" -UseBasicParsing } catch {}
        }
        if (-not (Test-Path -LiteralPath "$inst.part")) { Stop-Boot 'téléchargement de Git impossible' }
        if ((Get-FileHash -LiteralPath "$inst.part" -Algorithm SHA256).Hash.ToLower() -ne $GIT_SHA) { Remove-Item -LiteralPath "$inst.part" -Force; Stop-Boot 'installateur de Git téléchargé abîmé (empreinte SHA-256 différente)' }
        Move-Item -LiteralPath "$inst.part" -Destination $inst -Force
    }
    $sig = Get-AuthenticodeSignature -LiteralPath $inst
    if ($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch 'Johannes Schindelin') { Stop-Boot "signature de l'installateur de Git invalide ($($sig.Status))" }
    Write-Host '  Installation de Git...'
    try { $p = Start-Process -FilePath $inst -ArgumentList '/VERYSILENT /NORESTART /NOCANCEL /SP- /SUPPRESSMSGBOXES' -Wait -PassThru }
    catch { Stop-Boot "installation de Git annulée ou impossible ($($_.Exception.Message))" }
    $git = Find-Git
    if (-not $git) { Stop-Boot "Git introuvable après son installation (code $($p.ExitCode)) : installe-le depuis git-scm.com puis relance" }
    return $git
}

function Run-Git([string[]]$a) {
    $ErrorActionPreference = 'Continue'
    $out = & $Script:Git @a 2>&1 | ForEach-Object { "$_" }
    $Script:GitCode = $LASTEXITCODE
    return $out
}

Write-Host 'WindowSmash Launcher' -ForegroundColor Cyan
$Script:Git = Ensure-Git
$updated = $false
if (-not (Test-Path -LiteralPath (Join-Path $Clone '.git')) -or -not (Test-Path -LiteralPath (Join-Path $Clone 'kit\ws_setup.ps1'))) {
    Write-Host '  Premier lancement : téléchargement du launcher...'
    if (Test-Path -LiteralPath $Clone) {       # an attempt that stopped half way, or a damaged copy: emptied (the folder itself may be in use)
        try { Get-ChildItem -LiteralPath $Clone -Force | Remove-Item -Recurse -Force } catch { Stop-Boot "impossible de vider $Clone ($($_.Exception.Message))" }
    }
    $ErrorActionPreference = 'Continue'; & $Script:Git clone --quiet $LauncherUrl $Clone | Out-Host; $code = $LASTEXITCODE; $ErrorActionPreference = 'Stop'
    if ($code -ne 0 -or -not (Test-Path -LiteralPath (Join-Path $Clone 'kit\ws_setup.ps1'))) { Stop-Boot "git clone de $LauncherUrl a échoué (code $code)" }
    $updated = $true
} else {
    $before = (Run-Git @('-C', $Clone, 'rev-parse', 'HEAD')) | Select-Object -First 1
    $null = Run-Git @('-C', $Clone, 'fetch', '--quiet', 'origin')
    if ($Script:GitCode -ne 0) {
        Write-Host '  Pas de connexion au dépôt du launcher : je continue avec la version déjà là.' -ForegroundColor Yellow
    } else {
        $after = (Run-Git @('-C', $Clone, 'rev-parse', '@{u}')) | Select-Object -First 1
        if ($Script:GitCode -eq 0 -and $after -and $after -ne $before) {
            $null = Run-Git @('-C', $Clone, 'reset', '--hard', '--quiet', $after)
            if ($Script:GitCode -ne 0) { Stop-Boot 'mise à jour du launcher impossible (git reset)' }
            $b7 = if ($before) { $before.Substring(0, 7) } else { '?' }
            Write-Host "  Launcher mis à jour ($b7 -> $($after.Substring(0, 7)))." -ForegroundColor Green
            $updated = $true
        }
    }
}

# The file the user started (Desktop, Downloads...) is refreshed with the repository's copy. Safe while that file is
# running: cmd.exe has already read the whole block that started this script and does not read the file again.
$repoBat = Join-Path $Clone 'WindowSmash Launcher.bat'
if ($Self -and (Test-Path -LiteralPath $Self) -and (Test-Path -LiteralPath $repoBat)) {
    try {
        $own = (Resolve-Path -LiteralPath $Self).Path
        if ($own -ne (Resolve-Path -LiteralPath $repoBat).Path -and (Get-FileHash -LiteralPath $own).Hash -ne (Get-FileHash -LiteralPath $repoBat).Hash) {
            Copy-Item -LiteralPath $repoBat -Destination $own -Force
            Write-Host "  $(Split-Path $own -Leaf) mis à jour."
        }
    } catch { Write-Host "  (copie du launcher non mise à jour : $($_.Exception.Message))" -ForegroundColor Yellow }
}

if ($updated -and -not $env:WSL_RELAUNCHED -and -not $env:WSL_NO_RELAUNCH) {
    Write-Host '  Redémarrage dans la nouvelle version...'
    $env:WSL_RELAUNCHED = '1'
    $env:WSL_KITDIR = $KitDir
    Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\cmd.exe') -ArgumentList @('/c', ('""' + $repoBat + '" ' + $Mode + '"')) -WorkingDirectory $Clone
    exit 20
}

$kitDir = if ($env:WSL_KITDIR) { $env:WSL_KITDIR } else { $KitDir }
& (Join-Path $Clone 'kit\ws_setup.ps1') -KitDir $kitDir -Mode $Mode
exit $LASTEXITCODE
#@@END boot.ps1
