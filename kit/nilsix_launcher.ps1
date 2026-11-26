# Nilsix tools in OpenSmash.exe (kit 5.4), dot-sourced by ws_setup.ps1: the release's launcher with one more page,
# NILSIX TOOLS (kit\nilsix\LauncherForm.Nilsix.cs, with kit\mods_sync.py inside it). Built from the game folder's own
# sources once they are the release's (tools\source_version.txt names the release's commit), with the release's
# version number, so OpenSmash sees itself up to date. ssbu.exe is not touched: nothing changes online, friends who
# play with the release's OpenSmash.exe stay in sync. Needs a .NET SDK 8 or newer; without one, while the folder waits
# for its update, or when the build fails, the kit puts the release's OpenSmash.exe as before.
# Built in %LOCALAPPDATA%\WindowSmash-setup\nilsix-launcher; nilsix-launcher\record.json says what OpenSmash.exe is, so a
# start with nothing new builds nothing. An update of OpenSmash puts the release's OpenSmash.exe back (or rebuilds its
# own): the next start of the kit builds this one again. This file must stay UTF-8 with a BOM and CRLF.

function Get-NilsixDotnet {
    # dotnet when it has an SDK 8 or newer (the project is net8.0-windows), else $null
    $cmd = Get-Command dotnet -ErrorAction SilentlyContinue
    if (-not $cmd) { return $null }
    $ErrorActionPreference = 'Continue'
    $sdks = @(& $cmd.Source --list-sdks 2>$null)
    if ($sdks | Where-Object { $_ -match '^\s*(\d+)\.' -and [int]$Matches[1] -ge 8 }) { return $cmd.Source }
    return $null
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

function Install-NilsixLauncher([string]$Game, [string]$Base, [string]$State, [string]$KitDir) {
    # $true when $Game\OpenSmash.exe is this release's launcher with the NILSIX TOOLS page
    $exe = Join-Path $Game 'OpenSmash.exe'
    if (-not (Test-Path -LiteralPath (Join-Path $Game 'OpenSmash.Launcher\OpenSmash.Launcher.csproj'))) { return $false }
    $dotnet = Get-NilsixDotnet
    if (-not $dotnet) { return $false }   # (most players: the release's OpenSmash.exe)
    $work = Join-Path $State 'nilsix-launcher'
    New-Item -ItemType Directory -Force -Path $work | Out-Null
    try {
        Get-Text "$Base/opensmash-release.json" (Join-Path $work 'release.json')
        $release = [IO.File]::ReadAllText((Join-Path $work 'release.json')) | ConvertFrom-Json
    } catch { return $false }
    $version = [string]$release.version; $commit = ([string]$release.commit).ToLower()
    if ($version -notmatch '^\d+\.\d+\.\d+' -or $commit -notmatch '^[0-9a-f]{40}$') { return $false }
    $installed = ''
    try { $installed = (([IO.File]::ReadAllText((Join-Path $Game 'tools\source_version.txt'))).Trim() -split '\s+')[0].ToLower() } catch { }
    if ($installed -ne $commit) {
        Write-Host (L "  Nilsix tools: after OpenSmash's update to $version (accept it), at the next start" `
                      "  Nilsix tools : après la mise à jour d'OpenSmash en $version (accepte-la), au prochain lancement")
        return $false
    }
    $kit = (@('nilsix\LauncherForm.Nilsix.cs', 'mods_sync.py', 'nilsix_launcher.ps1') | ForEach-Object { Get-Sha256 (Join-Path $KitDir $_) }) -join ' '
    $recordFile = Join-Path $work 'record.json'
    $record = $null
    try { $record = [IO.File]::ReadAllText($recordFile) | ConvertFrom-Json } catch { }
    if ($record -and $record.commit -eq $commit -and $record.version -eq $version -and $record.kit -eq $kit -and
        (Test-Path -LiteralPath $exe) -and (Get-Sha256 $exe) -eq $record.sha) {
        Write-Host (L "  Nilsix tools: in OpenSmash.exe $version" "  Nilsix tools : dans OpenSmash.exe $version")
        return $true
    }

    Write-Host (L "Building OpenSmash.exe $version with the NILSIX TOOLS page (one to a few minutes)..." `
                  "Compilation d'OpenSmash.exe $version avec la page NILSIX TOOLS (une à quelques minutes)...")
    try {
        $src = Join-Path $work 'src'
        if (Test-Path -LiteralPath $src) { Remove-Item -LiteralPath $src -Recurse -Force }
        foreach ($d in 'OpenSmash.Launcher', 'OpenSmash.Core') {
            $null = & robocopy.exe (Join-Path $Game $d) (Join-Path $src $d) /E /XD bin obj /R:1 /W:1 /NFL /NDL /NJH /NJS /NP
            if ($LASTEXITCODE -ge 8) { throw "the copy of $d failed (robocopy $LASTEXITCODE)" }
        }
        Copy-Item -LiteralPath (Join-Path $Game 'locales') -Destination (Join-Path $src 'locales') -Recurse
        New-Item -ItemType Directory -Force -Path (Join-Path $src 'media') | Out-Null
        Copy-Item -LiteralPath (Join-Path $Game 'media\opensmash.ico') -Destination (Join-Path $src 'media')
        $ui = Join-Path $src 'OpenSmash.Launcher'
        Add-NilsixHook (Join-Path $ui 'LauncherForm.Paint.cs') 'case "yuzu": PaintYuzuRoom(g, W, H); break;' `
            'case "nilsix": PaintNilsix(g, W, H); break;   case "yuzu": PaintYuzuRoom(g, W, H); break;' 1
        Add-NilsixHook (Join-Path $ui 'LauncherForm.Paint.cs') 'new[] { ("nav:settings", "SETTINGS"),' `
            'new[] { ("nav:settings", "SETTINGS"), ("nav:nilsix", "NILSIX TOOLS"),' 2
        Add-NilsixHook (Join-Path $ui 'LauncherForm.Paint.cs') '_view == "competitive" ? "nav:competitive" : "nav:mods";' `
            '_view == "competitive" ? "nav:competitive" : _view == "nilsix" ? "nav:nilsix" : "nav:mods";' 1
        Add-NilsixHook (Join-Path $ui 'LauncherForm.cs') 'if (ActivateCompetitiveHit(id)) return;' `
            'if (ActivateCompetitiveHit(id)) return;   if (ActivateNilsixHit(id)) return;' 1
        Add-NilsixHook (Join-Path $ui 'OpenSmash.Launcher.csproj') '<EmbeddedResource Include="Assets\emblem-white.png" LogicalName="emblem.png" />' `
            '<EmbeddedResource Include="Assets\emblem-white.png" LogicalName="emblem.png" /><EmbeddedResource Include="Nilsix\mods_sync.py" LogicalName="Nilsix.mods_sync.py" />' 1
        Copy-Item -LiteralPath (Join-Path $KitDir 'nilsix\LauncherForm.Nilsix.cs') -Destination $ui
        New-Item -ItemType Directory -Force -Path (Join-Path $ui 'Nilsix') | Out-Null
        Copy-Item -LiteralPath (Join-Path $KitDir 'mods_sync.py') -Destination (Join-Path $ui 'Nilsix')

        $out = Join-Path $work 'out'
        if (Test-Path -LiteralPath $out) { Remove-Item -LiteralPath $out -Recurse -Force }
        $log = Join-Path $work 'build.log'
        $env:DOTNET_NOLOGO = '1'; $env:DOTNET_CLI_TELEMETRY_OPTOUT = '1'
        # (as the release workflow builds it, .github/workflows/release.yml "Build OpenSmash.exe"; no compiler server left
        # running beside the game)
        $p = Start-Process -FilePath $dotnet -NoNewWindow -Wait -PassThru -RedirectStandardOutput $log -RedirectStandardError "$log.err" -ArgumentList @(
            'publish', "`"$(Join-Path $ui 'OpenSmash.Launcher.csproj')`"", '-c', 'Release', '-o', "`"$out`"", "-p:Version=$version", '--nologo', '--disable-build-servers')
        $built = Join-Path $out 'OpenSmash.exe'
        if ($p.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $built)) {
            $why = @(Get-Content -LiteralPath $log -ErrorAction SilentlyContinue | Where-Object { $_ -match ' error ' } | Select-Object -First 2) -join ' '
            throw "dotnet publish stopped (code $($p.ExitCode)) $why (log: $log)"
        }
        $sha = Get-Sha256 $built
        if (Test-Path -LiteralPath $exe) {   # (an OpenSmash.exe that runs can be renamed, not replaced; OpenSmash deletes the .old)
            Remove-Item -LiteralPath "$exe.old" -Force -ErrorAction SilentlyContinue
            Rename-Item -LiteralPath $exe -NewName 'OpenSmash.exe.old'
        }
        Copy-Item -LiteralPath $built -Destination $exe
        $record = @{ commit = $commit; version = $version; kit = $kit; sha = $sha }
        [IO.File]::WriteAllText($recordFile, ($record | ConvertTo-Json))
        Remove-Item -LiteralPath $src, $out -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host (L "  Nilsix tools: OpenSmash.exe $version built, with its NILSIX TOOLS page" `
                      "  Nilsix tools : OpenSmash.exe $version compilé, avec sa page NILSIX TOOLS")
        return $true
    } catch {
        Write-Host (L "  Nilsix tools: not built ($($_.Exception.Message)); the release's OpenSmash.exe instead" `
                      "  Nilsix tools : pas compilé ($($_.Exception.Message)) ; l'OpenSmash.exe de la version publiée à la place") -ForegroundColor Yellow
        if (-not (Test-Path -LiteralPath $exe) -and (Test-Path -LiteralPath "$exe.old")) { Rename-Item -LiteralPath "$exe.old" -NewName 'OpenSmash.exe' }
        return $false
    }
}
