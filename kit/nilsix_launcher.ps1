# Nilsix tools in OpenSmash.exe (kit 5.4 to 5.6): the release's launcher with one more page, NILSIX TOOLS
# (kit\nilsix\LauncherForm.Nilsix.cs, with kit\mods_sync.py inside it), built here from the release's own sources (the
# source archive of its commit, as GitHub serves it) with the release's version number, so OpenSmash sees itself up to
# date. ssbu.exe is not touched: nothing changes online, friends who play with the release's OpenSmash.exe stay in sync.
# Needs a .NET SDK 8 or newer: this PC's, else (kit 5.7) Microsoft's own, downloaded once into WindowSmash-setup\dotnet
# (Install-NilsixDotnet); when that or the build fails, the release's OpenSmash.exe as before.
# Two callers:
# - ws_setup.ps1 (the kit's .bat) dot-sources this file: Install-NilsixLauncher for the latest release, then
#   Set-NilsixShortcuts (the kit's shortcuts open OpenSmash.exe from then on, one per folder);
# - OpenSmash.exe itself (LauncherForm.Nilsix.cs) runs it as a script, from a folder with the newest kit files of GitHub:
#   at each start (a kit update: the same release, built again) and in place of its own self-update (a new release: built
#   for it, then the game's update goes on). So once built, the launcher keeps itself and this page up to date, and the
#   kit's .bat is only needed to install. When a new release's build fails, OpenSmash puts the release's launcher (no
#   page) and the shortcuts open the .bat again, which tries the build at each start (Restore-NilsixShortcuts); else
#   they open OpenSmash.exe (Set-NilsixShortcuts again: nothing changes when they already do).
# nilsix-launcher\record.json says what OpenSmash.exe is: a start with nothing new builds nothing.
# This file must stay UTF-8 with a BOM and CRLF.

function Get-NilsixDotnet([string]$State = '') {
    # dotnet when it has an SDK 8 or newer (the project is net8.0-windows): this PC's, else the kit's own
    # ($State\dotnet, Install-NilsixDotnet), else $null
    $ErrorActionPreference = 'Continue'
    foreach ($d in @((Get-Command dotnet -ErrorAction SilentlyContinue).Source) + @($(if ($State) { Join-Path $State 'dotnet\dotnet.exe' }))) {
        if (-not $d -or -not (Test-Path -LiteralPath $d)) { continue }
        $sdks = @(try { & $d --list-sdks 2>$null } catch { })   # (a dotnet.exe that does not start: none)
        if ($sdks | Where-Object { $_ -match '^\s*(\d+)\.' -and [int]$Matches[1] -ge 8 }) { return $d }
    }
    return $null
}

function Install-NilsixDotnet([string]$State) {
    # kit 5.7: no SDK 8+ on this PC (most players): Microsoft's own .NET SDK zip, for the kit alone, in $State\dotnet (no
    # admin rights, nothing put in PATH or the registry; about 300 MB downloaded once, 800 MB on disk), checked against
    # the SHA-512 of Microsoft's release list. Its dotnet.exe, else an exception that says why.
    # shortcut: channel 8.0 fixed, as the release workflow builds it (.github/workflows/release.yml, setup-dotnet
    # 8.0.x); follow it when upstream moves to another .NET
    $dir = Join-Path $State 'dotnet'
    $root = [IO.Path]::GetPathRoot($State)
    if ((New-Object IO.DriveInfo $root).AvailableFreeSpace -lt 2GB) { throw "the .NET SDK needs 2 GB free on $root" }
    Write-Host (L "  Nilsix tools: no .NET SDK on this PC: downloading Microsoft's, once, for this kit only (about 300 MB, a few minutes)..." `
                  "  Nilsix tools : pas de SDK .NET sur ce PC : téléchargement de celui de Microsoft, une seule fois, pour ce kit seulement (environ 300 Mo, quelques minutes)...")
    $list = Join-Path $State 'dotnet-releases.json'
    Get-Text 'https://builds.dotnet.microsoft.com/dotnet/release-metadata/8.0/releases.json' $list
    $file = @(([IO.File]::ReadAllText($list) | ConvertFrom-Json).releases[0].sdk.files | Where-Object { $_.name -eq 'dotnet-sdk-win-x64.zip' })[0]
    Remove-Item -LiteralPath $list -Force
    if (-not $file -or $file.url -notmatch '^https://([a-z0-9-]+\.)+microsoft\.com/' -or $file.hash -notmatch '^[0-9a-fA-F]{128}$') {
        throw "Microsoft's .NET release list names no SDK zip for Windows x64"
    }
    $zip = Join-Path $State 'dotnet-sdk.zip'
    $part = "$dir.part"
    try {
        Get-Text $file.url $zip
        if ((Get-FileHash -LiteralPath $zip -Algorithm SHA512).Hash -ne $file.hash) { throw 'the .NET SDK download is damaged (its SHA-512 differs)' }
        foreach ($d in $part, $dir) {   # (left by a download that stopped, or an SDK that no longer starts)
            if (-not (Test-Path -LiteralPath $d)) { continue }
            if ((Get-Item -LiteralPath $d -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "$d is a link: not deleted, so no .NET SDK" }
            Remove-Item -LiteralPath $d -Recurse -Force
        }
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [IO.Compression.ZipFile]::ExtractToDirectory($zip, $part)
        Rename-Item -LiteralPath $part -NewName (Split-Path -Leaf $dir)
    } finally { Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue }
    $dotnet = Join-Path $dir 'dotnet.exe'
    if ((Get-NilsixDotnet $State) -ne $dotnet) { throw "the .NET SDK in $dir does not start" }
    Write-Host (L "  Nilsix tools: .NET SDK $($file.url -replace '^.*/dotnet-sdk-([^/]+)-win-x64\.zip$', '$1') in $dir" `
                  "  Nilsix tools : SDK .NET $($file.url -replace '^.*/dotnet-sdk-([^/]+)-win-x64\.zip$', '$1') dans $dir")
    return $dotnet
}

function Add-NilsixHook([string]$File, [string]$Anchor, [string]$With, [int]$Count) {
    # $Anchor (found $Count times, else upstream changed: no page rather than a broken one) becomes $With, the file
    # keeping its encoding (a BOM or none)
    $bytes = [IO.File]::ReadAllBytes($File)
    $bom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    $text = [IO.File]::ReadAllText($File)
    $found = [regex]::Matches($text, [regex]::Escape($Anchor)).Count
    if ($found -ne $Count) { throw "$(Split-Path -Leaf $File) has changed ($found x '$Anchor', $Count expected): the kit needs an update" }
    [IO.File]::WriteAllText($File, $text.Replace($Anchor, $With), (New-Object Text.UTF8Encoding $bom))
}

function Test-NilsixHook([string]$File, [string]$Anchor, [int]$Count) {
    [regex]::Matches([IO.File]::ReadAllText($File), [regex]::Escape($Anchor)).Count -eq $Count
}

function Add-NilsixPage([string]$Ui, [string]$KitDir) {
    # the release's launcher sources in $Ui (its OpenSmash.Launcher folder) with the NILSIX TOOLS page: the hooks into
    # its files, then LauncherForm.Nilsix.cs and mods_sync.py (embedded) beside them
    Add-NilsixHook (Join-Path $Ui 'LauncherForm.Paint.cs') 'case "yuzu": PaintYuzuRoom(g, W, H); break;' `
        'case "nilsix": PaintNilsix(g, W, H); break;   case "yuzu": PaintYuzuRoom(g, W, H); break;' 1
    Add-NilsixHook (Join-Path $Ui 'LauncherForm.Paint.cs') 'new[] { ("nav:settings", "SETTINGS"),' `
        'new[] { ("nav:settings", "SETTINGS"), ("nav:nilsix", "NILSIX TOOLS"),' 2
    Add-NilsixHook (Join-Path $Ui 'LauncherForm.Paint.cs') '_view == "competitive" ? "nav:competitive" : "nav:mods";' `
        '_view == "competitive" ? "nav:competitive" : _view == "nilsix" ? "nav:nilsix" : "nav:mods";' 1
    # (the page's jobs in the bar at the bottom, as on the MODS page, rather than the home page's strip: SetLoad)
    Add-NilsixHook (Join-Path $Ui 'LauncherForm.Paint.cs') 'if (_loadOn && _view != "mods") PaintLoad(g, W, H);' `
        'if (_loadOn && _view != "mods" && _view != "nilsix") PaintLoad(g, W, H);' 1
    Add-NilsixHook (Join-Path $Ui 'LauncherForm.Paint.cs') 'if (_loadOn && _view == "mods")' `
        'if (_loadOn && (_view == "mods" || _view == "nilsix"))' 1
    Add-NilsixHook (Join-Path $Ui 'LauncherForm.cs') 'if (ActivateCompetitiveHit(id)) return;' `
        'if (ActivateCompetitiveHit(id)) return;   if (ActivateNilsixHit(id)) return;' 1
    # (OpenSmash's self-update builds the next release's launcher with this page: LauncherForm.Nilsix.cs)
    Add-NilsixHook (Join-Path $Ui 'LauncherForm.Release.cs') 'await Updater.ReplaceLauncherAsync(_release, default, null, atRoot);' `
        'await NilsixReplaceLauncherAsync(_release, atRoot);' 1
    Add-NilsixHook (Join-Path $Ui 'OpenSmash.Launcher.csproj') '<EmbeddedResource Include="Assets\emblem-white.png" LogicalName="emblem.png" />' `
        '<EmbeddedResource Include="Assets\emblem-white.png" LogicalName="emblem.png" /><EmbeddedResource Include="Nilsix\mods_sync.py" LogicalName="Nilsix.mods_sync.py" />' 1
    # (kit 5.11, the MODS page's search and ALL / ON / OFF filter: its three hooks or none, so that a change of that page
    # upstream leaves the rest of NILSIX TOOLS working)
    $search = @(
        @((Join-Path $Ui 'LauncherForm.cs'), 'var lines = new List<ModLine>();', 'var lines = new List<ModLine>(); var _mods = NilsixModsShown();'),
        @((Join-Path $Ui 'LauncherForm.Paint.cs'), 'Theme.Label(g, $"INSTALLED  ({packages})", hf, A(Theme.Dim), x, top - 26 * s, 20 * s, sp);',
          'Theme.Label(g, NilsixInstalled(packages), hf, A(Theme.Dim), x, top - 26 * s, 20 * s, sp); PaintNilsixModSearch(g, x, top, cw, sizeR);'),
        @((Join-Path $Ui 'LauncherForm.Paint.cs'), 'PaintHeader(g, W, H);', 'NilsixSearchPlace(); PaintHeader(g, W, H);'))
    if (@($search | Where-Object { -not (Test-NilsixHook $_[0] $_[1] 1) }).Count) {
        Write-Host (L '  Nilsix tools: the MODS page changed in this release, so no search on it' '  Nilsix tools : la page MODS a changé dans cette version, donc pas de recherche dessus')
    } else { foreach ($h in $search) { Add-NilsixHook $h[0] $h[1] $h[2] 1 } }
    Copy-Item -LiteralPath (Join-Path $KitDir 'nilsix\LauncherForm.Nilsix.cs') -Destination $Ui
    New-Item -ItemType Directory -Force -Path (Join-Path $Ui 'Nilsix') | Out-Null
    Copy-Item -LiteralPath (Join-Path $KitDir 'mods_sync.py') -Destination (Join-Path $Ui 'Nilsix')
}

function Install-NilsixLauncher([string]$Game, [string]$Base, [string]$State, [string]$KitDir, [string]$Version = '', [string]$Commit = '') {
    # $true when $Game\OpenSmash.exe is the launcher of release $Version ($Commit; without them, the release $Base
    # describes) with the NILSIX TOOLS page; $Script:NilsixBuilt says whether it was built just now
    $Script:NilsixBuilt = $false
    $exe = Join-Path $Game 'OpenSmash.exe'
    if (-not (Test-Path -LiteralPath (Join-Path $Game 'tools'))) { return $false }
    # (an OpenSmash.exe a build here replaced while it ran: deleted once it no longer runs)
    Get-ChildItem -LiteralPath $Game -Filter 'OpenSmash.exe.nilsix-*.old' -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
    $work = Join-Path $State 'nilsix-launcher'
    New-Item -ItemType Directory -Force -Path $work | Out-Null
    if (-not $Version) {
        try {
            Get-Text "$Base/opensmash-release.json" (Join-Path $work 'release.json')
            $release = [IO.File]::ReadAllText((Join-Path $work 'release.json')) | ConvertFrom-Json
            $Version = [string]$release.version; $Commit = [string]$release.commit
        } catch { return $false }
    }
    $Commit = $Commit.ToLower()
    if ($Version -notmatch '^\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?$' -or $Commit -notmatch '^[0-9a-f]{40}$') { return $false }
    $kit = (@('nilsix\LauncherForm.Nilsix.cs', 'mods_sync.py', 'nilsix_launcher.ps1') | ForEach-Object { Get-Sha256 (Join-Path $KitDir $_) }) -join ' '
    $recordFile = Join-Path $work 'record.json'
    $isBuilt = {
        $record = $null
        try { $record = [IO.File]::ReadAllText($recordFile) | ConvertFrom-Json } catch { }
        [bool]($record -and $record.commit -eq $Commit -and $record.version -eq $Version -and $record.kit -eq $kit -and
               (Test-Path -LiteralPath $exe) -and (Get-Sha256 $exe) -eq $record.sha)
    }
    if (& $isBuilt) {
        Write-Host (L "  Nilsix tools: in OpenSmash.exe $Version" "  Nilsix tools : dans OpenSmash.exe $Version")
        return $true
    }

    # one build at a time (OpenSmash's start and the kit's .bat can both get here)
    $lock = $null; $moved = $null
    for ($i = 0; -not $lock -and $i -lt 120; $i++) {
        try { $lock = [IO.File]::Open((Join-Path $work 'build.lock'), 'OpenOrCreate', 'ReadWrite', 'None') } catch { Start-Sleep -Seconds 5 }
    }
    if (-not $lock) { return $false }
    try {
        if (& $isBuilt) { return $true }   # (the other one has just built it)
        $dotnet = Get-NilsixDotnet $State
        if (-not $dotnet) { $dotnet = Install-NilsixDotnet $State }
        Write-Host (L "Building OpenSmash.exe $Version with the NILSIX TOOLS page (one to a few minutes)..." `
                      "Compilation d'OpenSmash.exe $Version avec la page NILSIX TOOLS (une à quelques minutes)...")
        # the release's sources: the folders the launcher is built from, out of its commit's source archive
        $src = Join-Path $work 'src'
        if (Test-Path -LiteralPath $src) { Remove-Item -LiteralPath $src -Recurse -Force }
        $zip = Join-Path $work 'source.zip'
        Get-Text "https://codeload.github.com/OpenSmash-Ultimate/OpenSmash-Ultimate/zip/$Commit" $zip
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $z = [IO.Compression.ZipFile]::OpenRead($zip)
        try {
            foreach ($e in $z.Entries) {
                $rel = $e.FullName.Substring($e.FullName.IndexOf('/') + 1)   # (under the archive's one top folder)
                if (-not $e.Name -or $rel -notmatch '^(OpenSmash\.Launcher|OpenSmash\.Core|locales|media)/') { continue }
                if ($rel -match '(^|/)\.\.(/|$)|:|\\') { throw "unsafe path in the source archive: $($e.FullName)" }
                $dst = Join-Path $src ($rel.Replace('/', '\'))
                New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dst) | Out-Null
                [IO.Compression.ZipFileExtensions]::ExtractToFile($e, $dst, $true)
            }
        } finally { $z.Dispose() }
        $ui = Join-Path $src 'OpenSmash.Launcher'
        if (-not (Test-Path -LiteralPath (Join-Path $ui 'OpenSmash.Launcher.csproj'))) { throw "the source archive of $Commit has no OpenSmash.Launcher" }
        Add-NilsixPage $ui $KitDir

        $out = Join-Path $work 'out'
        if (Test-Path -LiteralPath $out) { Remove-Item -LiteralPath $out -Recurse -Force }
        $log = Join-Path $work 'build.log'
        $env:DOTNET_NOLOGO = '1'; $env:DOTNET_CLI_TELEMETRY_OPTOUT = '1'
        # (and the SDK's first use leaves the user's certificates and PATH alone)
        $env:DOTNET_GENERATE_ASPNET_CERTIFICATE = 'false'; $env:DOTNET_ADD_GLOBAL_TOOLS_TO_PATH = 'false'
        # (as the release workflow builds it, .github/workflows/release.yml "Build OpenSmash.exe"; no compiler server left
        # running beside the game)
        $p = Start-Process -FilePath $dotnet -NoNewWindow -Wait -PassThru -RedirectStandardOutput $log -RedirectStandardError "$log.err" -ArgumentList @(
            'publish', "`"$(Join-Path $ui 'OpenSmash.Launcher.csproj')`"", '-c', 'Release', '-o', "`"$out`"", "-p:Version=$Version", '--nologo', '--disable-build-servers')
        $built = Join-Path $out 'OpenSmash.exe'
        if ($p.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $built)) {
            $why = @(Get-Content -LiteralPath $log -ErrorAction SilentlyContinue | Where-Object { $_ -match ' error ' } | Select-Object -First 2) -join ' '
            throw "dotnet publish stopped (code $($p.ExitCode)) $why (log: $log)"
        }
        $sha = Get-Sha256 $built
        $builtVersion = (Get-Item -LiteralPath $built).VersionInfo.ProductVersion
        if ($builtVersion -ne $Version) { throw "the build says $builtVersion, not $Version" }   # (else OpenSmash would update itself again and again)
        if (Test-Path -LiteralPath $exe) {
            # an OpenSmash.exe that runs can be renamed, not replaced or deleted: this name until a run here deletes it
            # (OpenSmash.exe.old is left to OpenSmash's own self-update, which fails when a running exe has that name)
            $moved = Join-Path $Game ('OpenSmash.exe.nilsix-{0:yyyyMMddHHmmss}.old' -f (Get-Date))
            Rename-Item -LiteralPath $exe -NewName (Split-Path -Leaf $moved)
        }
        Copy-Item -LiteralPath $built -Destination $exe
        if ($moved) { Remove-Item -LiteralPath $moved -Force -ErrorAction SilentlyContinue }   # (at once when it does not run)
        $record = @{ commit = $Commit; version = $Version; kit = $kit; sha = $sha }
        [IO.File]::WriteAllText($recordFile, ($record | ConvertTo-Json))
        Remove-Item -LiteralPath $src, $out, $zip -Recurse -Force -ErrorAction SilentlyContinue
        $Script:NilsixBuilt = $true
        Write-Host (L "  Nilsix tools: OpenSmash.exe $Version built, with its NILSIX TOOLS page" `
                      "  Nilsix tools : OpenSmash.exe $Version compilé, avec sa page NILSIX TOOLS")
        return $true
    } catch {
        Write-Host (L "  Nilsix tools: not built ($($_.Exception.Message)); the release's OpenSmash.exe instead" `
                      "  Nilsix tools : pas compilé ($($_.Exception.Message)) ; l'OpenSmash.exe de la version publiée à la place") -ForegroundColor Yellow
        if (-not (Test-Path -LiteralPath $exe) -and $moved -and (Test-Path -LiteralPath $moved)) { Rename-Item -LiteralPath $moved -NewName 'OpenSmash.exe' }
        return $false
    } finally { $lock.Dispose() }
}

function Set-NilsixShortcuts([string]$Game, [string]$State, [string[]]$Dirs = @([Environment]::GetFolderPath('Desktop'), (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'))) {
    # once OpenSmash.exe keeps itself up to date with this page, the kit's .bat is only needed to install: this user's
    # shortcuts to it (the desktop's, the Start menu's) open OpenSmash.exe directly, one per folder. The kit's other
    # ones (play, os-play: since kit 5.0 they opened the launcher too) are removed, and all of them when the folder has
    # a shortcut of its own to OpenSmash.exe (OpenSmash's, in it or in its OpenSmash folder, or the user's). What they
    # were is kept in nilsix-launcher\shortcuts.txt (path, target, arguments, folder, icon, then "removed" for a removed
    # one; tab-separated) for Restore-NilsixShortcuts. Run again at each OpenSmash start, it changes nothing more.
    $exe = Join-Path $Game 'OpenSmash.exe'
    $saved = Join-Path $State 'nilsix-launcher\shortcuts.txt'
    $lines = @()
    try { $lines = @([IO.File]::ReadAllLines($saved)) } catch { }
    $shell = New-Object -ComObject WScript.Shell
    foreach ($dir in $Dirs) {
        $kit = @(); $own = $null
        foreach ($f in @(Get-ChildItem -LiteralPath $dir, "$dir\OpenSmash" -Filter '*.lnk' -ErrorAction SilentlyContinue)) {
            try {
                $l = $shell.CreateShortcut($f.FullName)
                $was = @($lines | Where-Object { ($_ -split "`t")[0] -eq $f.FullName -and ($_ -split "`t")[5] -ne 'removed' })   # (one removed, made again since: not the kit's)
                $top = $f.DirectoryName -eq $dir
                if ($top -and [IO.Path]::GetFileName($l.TargetPath) -in 'OpenSmash Ultimate Launcher.bat', 'OpenSmash Launcher.bat', 'WindowSmash Launcher.bat') {
                    $kit += [pscustomobject]@{ File = $f; Lnk = $l; Bat = $true; Keep = $false
                                               Line = @($f.FullName, $l.TargetPath, $l.Arguments, $l.WorkingDirectory, $l.IconLocation) -join "`t" }
                } elseif ($top -and $was.Count -and $l.TargetPath -ieq $exe) {   # (one this function set before)
                    $kit += [pscustomobject]@{ File = $f; Lnk = $l; Bat = $false; Keep = $false; Line = (@($was[0] -split "`t")[0..4] -join "`t") }
                } elseif ($l.TargetPath -ieq $exe -and -not $l.Arguments) { $own = $f.BaseName }
            } catch { }
        }
        if (-not $kit.Count) { continue }
        # (kept: the one that had no arguments, the launcher's)
        if (-not $own) { ($kit | Sort-Object { [bool]($_.Line -split "`t")[2] }, { $_.File.Name } | Select-Object -First 1).Keep = $true }
        if (-not @($kit | Where-Object { $_.Bat -or -not $_.Keep }).Count) { continue }   # (already one, set before)
        foreach ($k in $kit) {
            $lines = @($lines | Where-Object { ($_ -split "`t")[0] -ne $k.File.FullName }) + ($k.Line + $(if ($k.Keep) { '' } else { "`tremoved" }))
        }
        [IO.File]::WriteAllLines($saved, [string[]]$lines)   # (before the shortcuts change)
        $same = if ($own) { $own } else { ($kit | Where-Object { $_.Keep }).File.BaseName }
        foreach ($k in $kit) {
            try {
                if (-not $k.Keep) {
                    Remove-Item -LiteralPath $k.File.FullName -Force
                    Write-Host (L "  shortcut '$($k.File.BaseName)': removed, '$same' does the same" "  raccourci « $($k.File.BaseName) » : supprimé, « $same » fait la même chose")
                } elseif ($k.Bat) {
                    $icon = ($k.Lnk.IconLocation -split ',')[0]
                    $k.Lnk.TargetPath = $exe; $k.Lnk.Arguments = ''; $k.Lnk.WorkingDirectory = $Game
                    if (-not $icon -or -not (Test-Path -LiteralPath $icon)) { $k.Lnk.IconLocation = "$exe,0" }
                    $k.Lnk.Save()
                    Write-Host (L "  shortcut '$($k.File.BaseName)': opens OpenSmash.exe from now on" "  raccourci « $($k.File.BaseName) » : ouvre OpenSmash.exe désormais")
                }
            } catch { }
        }
    }
}

function Restore-NilsixShortcuts([string]$State) {
    # OpenSmash.exe is the release's again (a build failed): Set-NilsixShortcuts's shortcuts open the kit's .bat again
    # (the ones it removed are made again), which tries the build at each start until it works, then sets them again
    $saved = Join-Path $State 'nilsix-launcher\shortcuts.txt'
    if (-not (Test-Path -LiteralPath $saved)) { return }
    $shell = New-Object -ComObject WScript.Shell
    foreach ($line in [IO.File]::ReadAllLines($saved)) {
        $v = $line -split "`t"
        if ($v.Count -lt 5 -or -not (Test-Path -LiteralPath $v[1])) { continue }
        $removed = $v.Count -gt 5 -and $v[5] -eq 'removed'
        if ((Test-Path -LiteralPath $v[0]) -eq $removed) { continue }   # (a removed one made again since, a set one deleted since)
        try {
            $l = $shell.CreateShortcut($v[0])
            if (-not $removed -and [IO.Path]::GetFileName($l.TargetPath) -ne 'OpenSmash.exe') { continue }   # (changed since: left as it is)
            $l.TargetPath = $v[1]; $l.Arguments = $v[2]; $l.WorkingDirectory = $v[3]; $l.IconLocation = $v[4]
            $l.Save()
        } catch { }
    }
    Remove-Item -LiteralPath $saved -Force
}

if ($MyInvocation.InvocationName -ne '.') {
    # OpenSmash.exe's call (LauncherForm.Nilsix.cs NilsixKit): nilsix_launcher.ps1 <game folder> [<version> <commit>], in
    # a folder with the newest kit files; without a version, the release OpenSmash.exe was built for (record.json).
    # Exit code: 0 = OpenSmash.exe is already that one, 10 = built and put in place, 1 = not built.
    $ErrorActionPreference = 'Stop'
    try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }
    $State = Join-Path $env:LOCALAPPDATA 'WindowSmash-setup'
    $Fr = $false
    try { $Fr = ([IO.File]::ReadAllText((Join-Path $State 'lang.txt'))).Trim() -eq 'fr' } catch { }
    function L([string]$En, [string]$FrText) { if ($Fr) { $FrText } else { $En } }
    function Get-Text([string]$Url, [string]$OutFile) {
        Invoke-WebRequest -UseBasicParsing -Headers @{ 'User-Agent' = 'OpenSmash-Ultimate-Launcher' } -Uri $Url -OutFile $OutFile
    }
    function Get-Sha256([string]$File) { (Get-FileHash -LiteralPath $File -Algorithm SHA256).Hash.ToLower() }
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $ProgressPreference = 'SilentlyContinue'
    $code = 1
    try {
        $v = [string]$args[1]; $c = [string]$args[2]
        if (-not $v) {
            $r = [IO.File]::ReadAllText((Join-Path $State 'nilsix-launcher\record.json')) | ConvertFrom-Json
            $v = [string]$r.version; $c = [string]$r.commit
        }
        if (Install-NilsixLauncher ([string]$args[0]) '' $State $PSScriptRoot $v $c) { $code = if ($Script:NilsixBuilt) { 10 } else { 0 } }
    } catch { Write-Host $_.Exception.Message }
    # the shortcuts follow: OpenSmash.exe with this page, they open it (one per folder); a new release not built (OpenSmash
    # puts the release's launcher instead, without this page), they open the .bat again
    try {
        if ($code -ne 1) { Set-NilsixShortcuts ([string]$args[0]) $State }
        elseif ($args[1]) { Restore-NilsixShortcuts $State }
    } catch { Write-Host $_.Exception.Message }
    exit $code
}
