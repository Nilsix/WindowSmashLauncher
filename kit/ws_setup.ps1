# OpenSmash Ultimate Launcher's kit 5.0: hands over to OpenSmash.exe, the official launcher of
# github.com/OpenSmash-Ultimate/OpenSmash-Ultimate, which installs, updates and plays the game.
# Kits 1.x to 4.x built the game themselves at a pinned commit so that every friend had the same build. Since v0.4.0
# (2026-11-17) the project ships versioned releases and OpenSmash.exe updates every copy to the latest one, which is
# that same job; v0.4.0 also removed Play SSBU.bat and moved Python to deps\venv, which kit 4 relied on.
# What this does at every start (any mode: old shortcuts pass play, diag, os-play...):
# 1. Finds the game folder: kit 4's repo.txt, else the one OpenSmash.exe remembers. A folder kit 4 made is a git
#    checkout detached at its pin, and OpenSmash.exe's Update only pulls a checkout of main (to main's newest commit,
#    not the release). So its .git is renamed to .git-kit4 (kept: rename it back to get git again) and
#    tools\source_version.txt names the commit it is on: the folder then updates like a release ZIP.
#    Its installer becomes the latest release's: an older one would take that first update to main, not the release.
# 2. Puts the latest release's OpenSmash.exe in that folder (checked against its .sha256), or in Downloads when there
#    is no folder yet (its first-start screen then sets one up), and starts it.
# Game files, builds, save and settings stay. This file must stay UTF-8 with a BOM and CRLF.
# Kit 5.1 (522ff00) brought kit 4.4's dual boot back (2 = ssbu-recomp, kit-opensmash\os_kit.ps1); 5.2 removes it again.
# 5.3: since v0.5.0 the installer to check is tools\install_opensmash.ps1 (install_windowsmash.ps1 forwards to it).
# 5.4: on a PC with a .NET SDK, OpenSmash.exe is the release's with a NILSIX TOOLS page (kit\nilsix_launcher.ps1).
# 5.5: that OpenSmash.exe keeps itself and the page up to date, so the kit's shortcuts open it directly from then on.
# 5.6: one shortcut per folder (the others the kit made are removed), the page's jobs in OpenSmash's bar at the bottom.
# 5.7: a PC without a .NET SDK 8+ gets Microsoft's own, for the kit alone (WindowSmash-setup\dotnet): the page everywhere.
param([string]$KitDir = '', [string]$Mode = '')

$ErrorActionPreference = 'Stop'
$KitVersion = '5.15 (2026-11-27)'
$Repo = 'OpenSmash-Ultimate/OpenSmash-Ultimate'
$OldPin = '1a819b81b35b8ec3c0f4b0c6df3dab60eaf2244a'   # kit 4.5's pin
$State = Join-Path $env:LOCALAPPDATA 'WindowSmash-setup'
$Fr = $false
try { $Fr = ([IO.File]::ReadAllText((Join-Path $State 'lang.txt'))).Trim() -eq 'fr' } catch { }
function L([string]$En, [string]$FrText) { if ($Fr) { $FrText } else { $En } }
function Fail([string]$En, [string]$FrText) {
    Write-Host ''
    Write-Host (L $En $FrText) -ForegroundColor Red
    Read-Host (L 'Press Enter to close' 'Appuie sur Entrée pour fermer') | Out-Null
    exit 10
}
function Test-Project([string]$Dir) { [bool]($Dir -and (Test-Path -LiteralPath (Join-Path $Dir 'tools\install_windowsmash.ps1'))) }
function Read-FirstLine([string]$File) {
    try { return ([IO.File]::ReadAllLines($File) | Select-Object -First 1).Trim().Trim('"') } catch { return '' }
}
function Get-Text([string]$Url, [string]$OutFile) {
    Invoke-WebRequest -UseBasicParsing -Headers @{ 'User-Agent' = 'OpenSmash-Ultimate-Launcher' } -Uri $Url -OutFile $OutFile
}
function Get-Sha256([string]$File) { (Get-FileHash -LiteralPath $File -Algorithm SHA256).Hash.ToLower() }

Write-Host "OpenSmash Ultimate Launcher - kit $KitVersion"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$ProgressPreference = 'SilentlyContinue'
New-Item -ItemType Directory -Force -Path $State | Out-Null

# ---- the game folder
$Game = Read-FirstLine (Join-Path $State 'repo.txt')
if ($Game -and -not (Test-Path -LiteralPath ([IO.Path]::GetPathRoot($Game)))) {
    Fail "The disk of your game folder ($Game) is not plugged in. Plug it in, then start the launcher again." `
         "Le disque de ton dossier de jeu ($Game) n'est pas branché. Branche-le, puis relance le launcher."
}
if (-not (Test-Project $Game)) { $Game = Read-FirstLine (Join-Path $env:LOCALAPPDATA 'OpenSmash\project_folder.txt') }
if (-not (Test-Project $Game)) { $Game = '' }

# ---- the latest release
$Tag = $null
try { $Tag = (Invoke-RestMethod -UseBasicParsing -Headers @{ 'User-Agent' = 'OpenSmash-Ultimate-Launcher' } "https://api.github.com/repos/$Repo/releases/latest").tag_name } catch { }
if (-not $Tag) {   # (the API's hourly limit): github.com's releases/latest page redirects to the release's tag
    try {
        $req = [Net.WebRequest]::Create("https://github.com/$Repo/releases/latest"); $req.Method = 'HEAD'
        $resp = $req.GetResponse(); $path = $resp.ResponseUri.AbsolutePath; $resp.Close()
        if ($path -match '/releases/tag/([^/]+)$') { $Tag = [uri]::UnescapeDataString($Matches[1]) }
    } catch { }
}
if (-not $Tag) {
    Fail 'GitHub did not answer (no internet?). Start the launcher again in a moment.' `
         "GitHub n'a pas répondu (pas d'internet ?). Relance le launcher dans un moment."
}
Write-Host (L "Latest OpenSmash Ultimate: $Tag" "Dernière version d'OpenSmash Ultimate : $Tag")

# ---- 1. a kit 4 folder becomes a folder OpenSmash.exe updates
if ($Game) {
    Write-Host (L "Game folder: $Game" "Dossier du jeu : $Game")
    $dotGit = Join-Path $Game '.git'
    $sourceVersion = Join-Path $Game 'tools\source_version.txt'
    if (Test-Path -LiteralPath $dotGit) {
        $head = ''
        try {
            $head = Read-FirstLine (Join-Path $dotGit 'HEAD')
            if ($head -match '^ref:\s*(\S+)$') { $head = Read-FirstLine (Join-Path $dotGit $Matches[1]) }
        } catch { }
        # shortcut: a branch only in packed-refs reads as kit 4.5's pin; Update compares files by content anyway,
        # only files that commit and the release both lack would stay behind
        if ($head -notmatch '^[0-9a-fA-F]{40}$') { $head = $OldPin }
        $to = '.git-kit4'; $i = 2
        while (Test-Path -LiteralPath (Join-Path $Game $to)) { $to = ".git-kit4-$i"; $i++ }
        try { Rename-Item -LiteralPath $dotGit -NewName $to -Force }
        catch {
            Fail "Could not rename $dotGit ($($_.Exception.Message)). Close the game, VS Code and any window open in that folder, then start the launcher again." `
                 "Impossible de renommer $dotGit ($($_.Exception.Message)). Ferme le jeu, VS Code et toute fenêtre ouverte dans ce dossier, puis relance le launcher."
        }
        [IO.File]::WriteAllText($sourceVersion, "$($head.ToLower())`n")
        Write-Host (L "  git checkout at $($head.Substring(0, 7)): now updated by OpenSmash.exe (git kept in $to)" `
                      "  copie git en $($head.Substring(0, 7)) : désormais mise à jour par OpenSmash.exe (git gardé dans $to)")
    } elseif (-not (Test-Path -LiteralPath $sourceVersion) -or ([IO.File]::ReadAllText($sourceVersion) -notmatch '[0-9a-fA-F]{40}')) {
        [IO.File]::WriteAllText($sourceVersion, "$OldPin`n")   # a kit 4 copy without git: built at the kit's pin
    }
    # Kit 4 put LLVM in dump\_setup\llvm-<version>, where upstream does not look (tools\cc.py: deps\llvm, with the
    # Visual Studio C runtime kit 4 installed): without it the update's rebuild stops at "the game compiler is not ready".
    $llvm = Join-Path $Game 'deps\llvm'
    if (-not (Test-Path -LiteralPath $llvm)) {
        $kitLlvm = Get-ChildItem -LiteralPath (Join-Path $Game 'dump\_setup') -Directory -Filter 'llvm-*' -ErrorAction SilentlyContinue |
            Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'bin\clang-cl.exe') } | Sort-Object Name -Descending | Select-Object -First 1
        if ($kitLlvm) {
            New-Item -ItemType Directory -Force -Path (Join-Path $Game 'deps') | Out-Null
            Move-Item -LiteralPath $kitLlvm.FullName -Destination $llvm   # (a junction moves as the link itself)
            Write-Host (L "  compiler: dump\_setup\$($kitLlvm.Name) moved to deps\llvm" "  compilateur : dump\_setup\$($kitLlvm.Name) déplacé dans deps\llvm")
        }
    }
    # Since v0.5.0 the installer is install_opensmash.ps1; install_windowsmash.ps1 only forwards to it (older
    # OpenSmash.exe start it by that name).
    $installer = Join-Path $Game 'tools\install_windowsmash.ps1'
    $setup = Join-Path $Game 'tools\install_opensmash.ps1'
    $current = if (Test-Path -LiteralPath $setup) { $setup } else { $installer }
    if (-not (Select-String -LiteralPath $current -Pattern 'function Get-UpdateRef' -SimpleMatch -Quiet)) {
        $raw = "https://raw.githubusercontent.com/$Repo/$([uri]::EscapeDataString($Tag))/tools"
        try { Get-Text "$raw/install_windowsmash.ps1" "$installer.new"; Get-Text "$raw/install_opensmash.ps1" "$setup.new" } catch {
            Remove-Item -LiteralPath "$installer.new", "$setup.new" -Force -ErrorAction SilentlyContinue
            Fail "Could not download the $Tag installer ($($_.Exception.Message)). Start the launcher again in a moment." `
                 "Impossible de télécharger l'installeur de $Tag ($($_.Exception.Message)). Relance le launcher dans un moment."
        }
        $forward = [IO.File]::ReadAllText("$installer.new"); $text = [IO.File]::ReadAllText("$setup.new")
        if (-not $forward.Contains("`$RepoName = 'OpenSmash-Ultimate'") -or -not $forward.Contains('install_opensmash.ps1') -or
            $text -notmatch '\[switch\]\s*\$UpdateOnly\b' -or -not $text.Contains("`$RepoName = 'OpenSmash-Ultimate'") -or -not $text.Contains('function Get-UpdateRef')) {
            Remove-Item -LiteralPath "$installer.new", "$setup.new" -Force
            Fail 'The installer GitHub sent is not the one expected; nothing was changed.' `
                 "L'installeur envoyé par GitHub n'est pas celui attendu ; rien n'a été changé."
        }
        Move-Item -LiteralPath "$setup.new" -Destination $setup -Force
        Move-Item -LiteralPath "$installer.new" -Destination $installer -Force
        Write-Host (L "  installer: $Tag's (updates follow the releases)" "  installeur : celui de $Tag (les mises à jour suivent les versions publiées)")
    }
}

# ---- 2. the release's OpenSmash.exe, then start it
if ($Game) { $dir = $Game } else {
    $dir = ''
    try { $dir = (New-Object -ComObject Shell.Application).NameSpace('shell:Downloads').Self.Path } catch { }
    if (-not $dir) { $dir = Join-Path $env:USERPROFILE 'Downloads' }
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
}
$exe = Join-Path $dir 'OpenSmash.exe'
$base = "https://github.com/$Repo/releases/download/$([uri]::EscapeDataString($Tag))"
# with the NILSIX TOOLS page when this PC can build it, else the release's own
$nilsix = $false
if ($Game) {
    try {
        . (Join-Path $PSScriptRoot 'nilsix_launcher.ps1')
        $nilsix = Install-NilsixLauncher $Game $base $State $PSScriptRoot
    }
    catch { $nilsix = $false; Write-Host "  Nilsix tools: $($_.Exception.Message)" -ForegroundColor Yellow }   # (the release's then)
    # (the shortcuts open the OpenSmash.exe that updates itself with the page, else this .bat again)
    try { if ($nilsix) { Set-NilsixShortcuts $Game $State } else { Restore-NilsixShortcuts $State } } catch { }
}
if (-not $nilsix) {
    $shaFile = Join-Path $State 'OpenSmash.exe.sha256'
    try { Get-Text "$base/OpenSmash.exe.sha256" $shaFile } catch {
        Fail "Could not download OpenSmash.exe.sha256 ($($_.Exception.Message)). Start the launcher again in a moment." `
             "Impossible de télécharger OpenSmash.exe.sha256 ($($_.Exception.Message)). Relance le launcher dans un moment."
    }
    $want = ([regex]::Match([IO.File]::ReadAllText($shaFile), '[0-9a-fA-F]{64}')).Value.ToLower()
    if (-not $want) { Fail 'OpenSmash.exe.sha256 holds no checksum.' "OpenSmash.exe.sha256 ne contient pas d'empreinte." }
    if (-not (Test-Path -LiteralPath $exe) -or (Get-Sha256 $exe) -ne $want) {
        Write-Host (L "Downloading OpenSmash.exe $Tag (70 MB)..." "Téléchargement d'OpenSmash.exe $Tag (70 Mo)...")
        $part = "$exe.download"
        try { Get-Text "$base/OpenSmash.exe" $part } catch {
            Fail "Could not download OpenSmash.exe ($($_.Exception.Message)). Start the launcher again in a moment." `
                 "Impossible de télécharger OpenSmash.exe ($($_.Exception.Message)). Relance le launcher dans un moment."
        }
        if ((Get-Sha256 $part) -ne $want) {
            Remove-Item -LiteralPath $part -Force
            Fail 'The downloaded OpenSmash.exe does not match its checksum; it was deleted. Start the launcher again.' `
                 "L'OpenSmash.exe téléchargé ne correspond pas à son empreinte ; il a été supprimé. Relance le launcher."
        }
        try { Move-Item -LiteralPath $part -Destination $exe -Force }
        catch {
            Remove-Item -LiteralPath $part -Force -ErrorAction SilentlyContinue
            if (-not (Test-Path -LiteralPath $exe)) { Fail "Could not write $exe ($($_.Exception.Message))." "Impossible d'écrire $exe ($($_.Exception.Message))." }
            Write-Host (L '  (OpenSmash is open: it keeps its version until it is closed and the launcher started again)' `
                          "  (OpenSmash est ouvert : il garde sa version jusqu'à ce qu'il soit fermé et le launcher relancé)") -ForegroundColor Yellow
        }
    }
}
Write-Host (L 'Starting OpenSmash. If it offers an update, accept it: it updates the game and rebuilds it.' `
              "Lancement d'OpenSmash. S'il propose une mise à jour, accepte-la : il met le jeu à jour et le recompile.")
Start-Process -FilePath $exe -WorkingDirectory $dir
exit 0
