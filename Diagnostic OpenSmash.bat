@echo off
rem OpenSmash diagnostic (Nilsix tools, github.com/Nilsix/WindowSmashLauncher). Double-click it when OpenSmash, its
rem launcher or the game does not work: it writes "Diagnostic OpenSmash.txt" on the desktop, to send to whoever helps
rem you. It changes nothing, and reads no keys, no game file, no account or Discord login.
setlocal
set "DG_SELF=%~f0"
title OpenSmash diagnostic
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; try { $t=[IO.File]::ReadAllText($env:DG_SELF); $m=[regex]::Match($t,'(?s)\r?\n#@@BEGIN diag\.ps1\r?\n(.*?)\r?\n#@@END diag\.ps1'); if(-not $m.Success){ throw 'incomplete file' }; $f=Join-Path $env:TEMP ('opensmash-diag-'+$PID+'.ps1'); [IO.File]::WriteAllText($f,$m.Groups[1].Value,(New-Object Text.UTF8Encoding $true)); & $f; $rc=$LASTEXITCODE; Remove-Item -LiteralPath $f -ErrorAction SilentlyContinue; exit $rc } catch { Write-Host ('Diagnostic error / erreur du diagnostic: '+$_.Exception.Message) -ForegroundColor Red; exit 2 }"
set "RC=%ERRORLEVEL%"
echo.
pause
exit /b %RC%
#@@BEGIN diag.ps1
# OpenSmash diagnostic (Nilsix tools), run by "Diagnostic OpenSmash.bat": what helps to see why OpenSmash, its launcher
# or the game does not work on a PC, in one text file on the desktop, with what looks wrong at its top. It changes
# nothing. It never reads the keys (prod.keys, title.keys), the game's files, the account or Discord login
# (config\discord_token.txt, config\session.dat, build\cache\online_pass.txt, netplay_id.txt), the memory dumps (.dmp)
# nor the online name. In what it writes, the Windows user name and the PC's name are replaced, and so are public IP
# addresses in the logs (a friend's). Windows PowerShell 5.1.
# Tests: OPENSMASH_DIAG_OUT = another report file, OPENSMASH_DIAG_QUIET = 1: no Explorer window at the end.
$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch { }
$Fr = (Get-UICulture).TwoLetterISOLanguageName -eq 'fr'
function L([string]$En, [string]$FrText) { if ($Fr) { $FrText } else { $En } }
$Lines = New-Object System.Collections.Generic.List[string]
$Notes = New-Object System.Collections.Generic.List[string]
function Add-Line([string]$Text = '') { $Lines.Add($Text) }
function Add-Note([string]$Text) { $Notes.Add($Text) }
function Write-Section([string]$Title, [scriptblock]$Body) {
    Write-Host "  $Title"
    Add-Line ''; Add-Line "--- $Title"
    try { & $Body } catch { Add-Line "  (stopped here: $($_.Exception.Message))" }
}
function Test-There([string]$Path) { try { return [bool]($Path -and (Test-Path -LiteralPath $Path)) } catch { return $false } }
function Test-Game([string]$Dir) { return [bool]($Dir -and ((Test-There "$Dir\OpenSmash.exe") -or (Test-There "$Dir\tools\mods.py"))) }
function Read-First([string]$File) {
    # (the first line that is neither empty nor a comment)
    try { return ([string](@([IO.File]::ReadAllLines($File)) | Where-Object { $_ -notmatch '^\s*([#;]|$)' } | Select-Object -First 1)).Trim() } catch { return '' }
}
function Get-Sha256([string]$File) { try { return (Get-FileHash -LiteralPath $File -Algorithm SHA256).Hash.ToLower() } catch { return '' } }
function Get-Short([string]$Text, [int]$Count = 10) { if ($Text.Length -gt $Count) { return $Text.Substring(0, $Count) } return $Text }
function Show-File([string]$Label, [string]$File) {
    if (Test-There $File) { $i = Get-Item -LiteralPath $File; Add-Line ("  {0,-22} {1:N0} bytes, {2:yyyy-MM-dd HH:mm}" -f $Label, $i.Length, $i.LastWriteTime) }
    else { Add-Line ("  {0,-22} missing" -f $Label) }
}
function Hide-Ip([string]$Text) {
    # public IPv4 addresses out (a friend's); the LAN's stay, they show a LAN mix-up
    return [regex]::Replace($Text, '(?<![\d.])(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})(?![\d.])', {
        param($m)
        $a = [int]$m.Groups[1].Value; $b = [int]$m.Groups[2].Value
        if ($a -in 0, 10, 127 -or ($a -eq 192 -and $b -eq 168) -or ($a -eq 172 -and $b -ge 16 -and $b -le 31) -or ($a -eq 169 -and $b -eq 254)) { $m.Value } else { '<public IP>' }
    })
}
function Hide-Private([string]$Text) {
    if ($env:USERPROFILE) { $Text = $Text -replace [regex]::Escape($env:USERPROFILE), '%USERPROFILE%' }
    if ($env:USERNAME) { $Text = $Text -replace ('(?<=[\\/]Users[\\/])' + [regex]::Escape($env:USERNAME) + '(?=[\\/\s]|$)'), '<user>' }
    if ($env:COMPUTERNAME -and $env:COMPUTERNAME.Length -ge 4) { $Text = $Text -replace ('\b' + [regex]::Escape($env:COMPUTERNAME) + '\b'), '<pc>' }
    foreach ($dom in @('<pc>', $env:USERDOMAIN) | Where-Object { $_ }) {   # (DOMAIN\user, in the install log's transcript)
        if ($env:USERNAME) { $Text = $Text -replace ('(?<=' + [regex]::Escape($dom) + '\\)' + [regex]::Escape($env:USERNAME) + '\b'), '<user>' }
    }
    $Text = $Text -replace '[\w.+-]+@[\w-]+(\.[\w-]+)+', '<email>'
    $Text = $Text -replace 'eyJ[\w-]{10,}\.[\w-]{10,}\.[\w-]{10,}', '<token>'        # (a web token)
    $Text = $Text -replace '[\w-]{24,28}\.[\w-]{6,7}\.[\w-]{27,}', '<token>'         # (a Discord token)
    return $Text
}
function Show-Tail([string]$File, [int]$Count, [string]$Skip = '') {
    if (-not (Test-There $File)) { Add-Line "  $File`: none"; return }
    $i = Get-Item -LiteralPath $File
    Add-Line ("  {0} ({1:N0} bytes, {2:yyyy-MM-dd HH:mm}), its last lines:" -f $i.FullName, $i.Length, $i.LastWriteTime)
    $tail = @(Get-Content -LiteralPath $File -Tail ([Math]::Max(200, $Count * 4)) -Encoding UTF8 -ErrorAction Stop)
    if ($Skip) { $tail = @($tail | Where-Object { $_ -notmatch $Skip }) }
    foreach ($l in @($tail | Select-Object -Last $Count)) { Add-Line ('    ' + (Hide-Ip $l)) }
}
function Test-Url([string]$Url) {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    try {
        $r = Invoke-WebRequest -UseBasicParsing -Method Head -TimeoutSec 10 -Headers @{ 'User-Agent' = 'OpenSmash-Diagnostic' } -Uri $Url -ErrorAction Stop
        return "HTTP $([int]$r.StatusCode), $($sw.ElapsedMilliseconds) ms"
    } catch {
        $resp = $null
        try { $resp = $_.Exception.Response } catch { }
        if ($resp) { return "HTTP $([int]$resp.StatusCode), $($sw.ElapsedMilliseconds) ms" }   # (an answer: reached)
        return "NOT REACHED ($($_.Exception.Message))"
    }
}

Write-Host (L 'OpenSmash diagnostic (about a minute):' 'Diagnostic OpenSmash (environ une minute) :')
$Out = if ($env:OPENSMASH_DIAG_OUT) { $env:OPENSMASH_DIAG_OUT } else { Join-Path ([Environment]::GetFolderPath('Desktop')) 'Diagnostic OpenSmash.txt' }
$State = "$env:LOCALAPPDATA\WindowSmash-setup"
$Work = "$State\nilsix-launcher"

# the OpenSmash folder: the one OpenSmash.exe remembers, the kit's, a shortcut's, the default one
$Cands = New-Object System.Collections.Generic.List[string]
foreach ($f in @("$env:LOCALAPPDATA\OpenSmash\project_folder.txt", "$State\repo.txt")) { $v = (Read-First $f).Trim('"').TrimEnd('\'); if ($v) { $Cands.Add($v) } }
$Links = New-Object System.Collections.Generic.List[string]
try {
    $sh = New-Object -ComObject WScript.Shell
    $menu = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs"
    foreach ($d in @([Environment]::GetFolderPath('Desktop'), $menu, "$menu\OpenSmash")) {
        foreach ($f in @(Get-ChildItem -LiteralPath $d -Filter '*.lnk' -ErrorAction SilentlyContinue)) {
            try { $l = $sh.CreateShortcut($f.FullName) } catch { continue }
            $leaf = [IO.Path]::GetFileName($l.TargetPath)
            if ($leaf -ieq 'OpenSmash.exe' -or $leaf -like '*Launcher.bat') {
                $Links.Add(("  {0} -> {1} {2}" -f $f.FullName, $l.TargetPath, $l.Arguments).TrimEnd())
                if ($leaf -ieq 'OpenSmash.exe') { $Cands.Add((Split-Path -Parent $l.TargetPath)) }
            }
        }
    }
} catch { }
$Cands.Add("$env:USERPROFILE\Games\OpenSmash-Ultimate")
$Game = @($Cands | Where-Object { Test-Game $_ }) | Select-Object -First 1
$Rel = $null; $RelSha = ''; $ExeSha = ''

Write-Section 'PC' {
    $os = Get-CimInstance Win32_OperatingSystem
    $cs = Get-CimInstance Win32_ComputerSystem
    $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
    Add-Line "  Windows                $($os.Caption) $($os.Version) ($($os.OSArchitecture)), $((Get-UICulture).Name)"
    Add-Line "  processor              $($cpu.Name.Trim()), $($cpu.NumberOfCores) cores, $($cpu.NumberOfLogicalProcessors) threads"
    $ram = [math]::Round($cs.TotalPhysicalMemory / 1GB, 1)
    Add-Line ("  RAM                    {0} GB, {1} GB free" -f $ram, [math]::Round($os.FreePhysicalMemory / 1MB, 1))
    if ($ram -lt 8) { Add-Note (L "only $ram GB of RAM: the game and its builds need 8 or more" "seulement $ram Go de RAM : le jeu et ses compilations en demandent 8 ou plus") }
    foreach ($v in @(Get-CimInstance Win32_VideoController)) { Add-Line ("  graphics card          {0}, driver {1} of {2:yyyy-MM-dd}" -f $v.Name, $v.DriverVersion, $v.DriverDate) }
    try {
        Add-Type -Namespace OpenSmashDiag -Name Cpu -MemberDefinition '[DllImport("kernel32.dll")] public static extern bool IsProcessorFeaturePresent(uint f);' -ErrorAction Stop
        Add-Line "  AVX2                   $([OpenSmashDiag.Cpu]::IsProcessorFeaturePresent(40))"
    } catch { }
    foreach ($d in @(Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=2 OR DriveType=3')) {
        Add-Line ("  disk {0}                {1} GB free of {2} GB, {3}" -f $d.DeviceID, [math]::Round($d.FreeSpace / 1GB, 1), [math]::Round($d.Size / 1GB), $d.FileSystem)
    }
    Add-Line "  PowerShell             $($PSVersionTable.PSVersion)"
}

Write-Section (L 'OpenSmash folder' 'Dossier OpenSmash') {
    foreach ($c in @($Cands | Select-Object -Unique)) {
        Add-Line ("  candidate              {0}: {1}" -f $c, $(if (Test-Game $c) { 'OpenSmash' } elseif (Test-There $c) { 'not OpenSmash' } else { 'not there' }))
    }
    if (-not $Game) {
        Add-Note (L 'no OpenSmash folder found (OpenSmash never installed the game here, or its drive is not plugged in)' "aucun dossier OpenSmash trouvé (OpenSmash n'a jamais installé le jeu ici, ou son disque n'est pas branché)")
        return
    }
    Add-Line "  folder                 $Game"
    try {
        $d = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$($Game.Substring(0, 2))'"
        $free = [math]::Round($d.FreeSpace / 1GB, 1)
        if ($free -lt 15) { Add-Note (L "only $free GB free on $($d.DeviceID), the game's drive: an update and its build need about 15" "seulement $free Go libres sur $($d.DeviceID), le disque du jeu : une mise à jour et sa compilation en demandent environ 15") }
        if ($d.FileSystem -and $d.FileSystem -notmatch '^(NTFS|ReFS)$') { Add-Note (L "the game's drive is $($d.FileSystem), not NTFS: builds can fail there" "le disque du jeu est en $($d.FileSystem), pas en NTFS : les compilations peuvent y échouer") }
    } catch { }
    $src = Read-First "$Game\tools\source_version.txt"
    $channel = Read-First "$Game\config\update_channel.txt"
    if (-not $channel) { $channel = 'stable' }
    Add-Line "  source version         $src"
    Add-Line "  update channel         $channel"
    foreach ($n in '.git', '.git-kit4') { if (Test-There "$Game\$n") { Add-Line ("  {0,-22} there" -f $n) } }
    $exe = "$Game\OpenSmash.exe"
    $exeVersion = ''
    Show-File 'OpenSmash.exe' $exe
    if (Test-There $exe) {
        $exeVersion = ([string](Get-Item -LiteralPath $exe).VersionInfo.ProductVersion -split '\+')[0]
        $Script:ExeSha = Get-Sha256 $exe
        Add-Line "  OpenSmash.exe          version $exeVersion, sha256 $Script:ExeSha"
    } else { Add-Note (L "no OpenSmash.exe in $Game" "pas d'OpenSmash.exe dans $Game") }
    foreach ($n in 'build\ssbu.exe', 'build\ssbu_game.dll', 'build\ssbu.exe.old') { if ($n -eq 'build\ssbu.exe' -or (Test-There "$Game\$n")) { Show-File $n "$Game\$n" } }
    if (-not (Test-There "$Game\build\ssbu.exe")) { Add-Note (L 'the game is not built (build\ssbu.exe missing): OpenSmash builds it after its install or an update' "le jeu n'est pas compilé (build\ssbu.exe manquant) : OpenSmash le compile après son installation ou une mise à jour") }
    if (Test-There "$Game\config\update-game-build.pending") { Add-Note (L "the game's build after the last update did not finish (config\update-game-build.pending): OpenSmash retries it at Play" "la compilation du jeu après la dernière mise à jour n'a pas fini (config\update-game-build.pending) : OpenSmash la relance quand tu cliques sur Jouer") }
    try {
        # the latest release, as OpenSmash's update check sees it
        $r = Invoke-WebRequest -UseBasicParsing -TimeoutSec 20 -Headers @{ 'User-Agent' = 'OpenSmash-Diagnostic' } -ErrorAction Stop `
            -Uri 'https://github.com/OpenSmash-Ultimate/OpenSmash-Ultimate/releases/latest/download/opensmash-release.json'
        $text = $r.Content
        if ($text -is [byte[]]) { $text = [Text.Encoding]::UTF8.GetString($text) }
        $Script:Rel = $text | ConvertFrom-Json
        $Script:RelSha = [string]$Script:Rel.launcher.'windows-x64'.sha256
    } catch { Add-Line "  latest release         not read ($($_.Exception.Message))" }
    if ($Script:Rel) {
        $rel = $Script:Rel
        Add-Line "  latest release         $($rel.version) ($(Get-Short ([string]$rel.commit)), $($rel.channel))"
        $at = ($src -split '\s+')[0]
        if ($channel -eq 'stable' -and $at -and $at -ne $rel.commit) { Add-Note (L "the game folder is at $(Get-Short $at), not at the latest release $($rel.version): open OpenSmash and accept its update" "le dossier du jeu est en $(Get-Short $at), pas à la dernière version $($rel.version) : ouvre OpenSmash et accepte sa mise à jour") }
        if ($channel -eq 'stable' -and $exeVersion -and $exeVersion -ne $rel.version) { Add-Note (L "OpenSmash.exe is $exeVersion, the latest release is $($rel.version): open it and accept its update" "OpenSmash.exe est en $exeVersion, la dernière version est $($rel.version) : ouvre-le et accepte sa mise à jour") }
    }
}

Write-Section 'NILSIX TOOLS' {
    $rec = $null
    try { $rec = [IO.File]::ReadAllText("$Work\record.json") | ConvertFrom-Json } catch { }
    $dn = Get-Command dotnet -ErrorAction SilentlyContinue
    $sdks = if ($dn) { @(& $dn.Source --list-sdks 2>$null) } else { @() }
    Add-Line "  .NET SDKs              $(if ($sdks.Count) { $sdks -join '; ' } else { 'none' })"
    $own = "$State\dotnet\dotnet.exe"   # (kit 5.7: the one the kit downloads when the PC has none)
    $ownSdks = if (Test-There $own) { @(& $own --list-sdks 2>$null) } else { @() }
    Add-Line "  the kit's own SDK      $(if ($ownSdks.Count) { $ownSdks -join '; ' } elseif (Test-There $own) { 'there, but it does not start' } else { 'none' })"
    if (-not $rec) { Add-Line "  no build of OpenSmash.exe with the NILSIX TOOLS tab here (record.json missing): the release's OpenSmash.exe" }
    else {
        Add-Line "  built                  OpenSmash.exe $($rec.version) ($(Get-Short ([string]$rec.commit))), kit $(Get-Short ([string]$rec.kit) 12)"
        if ($Script:ExeSha -and $Script:ExeSha -eq $rec.sha) { Add-Line '  OpenSmash.exe          that build, with the NILSIX TOOLS tab' }
        elseif ($Script:ExeSha -and $Script:ExeSha -eq $Script:RelSha) { Add-Line "  OpenSmash.exe          the release's, without the NILSIX TOOLS tab" }
        elseif ($Script:ExeSha) { Add-Line "  OpenSmash.exe          neither that build nor the latest release's" }
    }
    $log = "$Work\update.log"
    if (Test-There $log) {
        $last = @(Select-String -LiteralPath $log -Pattern '^code (-?\d+)\s*$' -ErrorAction SilentlyContinue | Select-Object -Last 1)
        if ($last.Count -and $last[0].Matches[0].Groups[1].Value -eq '1') { Add-Note (L 'the last NILSIX TOOLS update failed (update.log, in the NILSIX TOOLS part below)' 'la dernière mise à jour de NILSIX TOOLS a échoué (update.log, dans la partie NILSIX TOOLS plus bas)') }
    }
    Show-Tail $log 40
    if (Test-There "$Work\build.log") {
        $errs = @(Select-String -LiteralPath "$Work\build.log" -Pattern ' error ' -ErrorAction SilentlyContinue | Select-Object -First 10)
        if ($errs.Count) { Add-Line '  build.log errors:'; foreach ($e in $errs) { Add-Line "    $($e.Line.Trim())" } }
    }
    if (Test-There "$Work\shortcuts.txt") { Add-Line "  shortcuts.txt          $(@([IO.File]::ReadAllLines("$Work\shortcuts.txt")).Count) shortcut(s) the kit changed" }
}

Write-Section (L 'Launcher kit and shortcuts' 'Kit du launcher et raccourcis') {
    Add-Line "  repo.txt               $(Read-First "$State\repo.txt")"
    Add-Line "  lang.txt               $(Read-First "$State\lang.txt")"
    $clone = "$env:LOCALAPPDATA\WindowSmashLauncher"
    if (Test-There "$clone\.git") {
        $head = Read-First "$clone\.git\HEAD"
        if ($head -match '^ref:\s*(\S+)') {
            $ref = $Matches[1]
            $commit = Read-First "$clone\.git\$($ref.Replace('/', '\'))"
            if (-not $commit -and (Test-There "$clone\.git\packed-refs")) {
                $p = @(Select-String -LiteralPath "$clone\.git\packed-refs" -Pattern (' ' + [regex]::Escape($ref) + '$') | Select-Object -First 1)
                if ($p.Count) { $commit = ($p[0].Line -split ' ')[0] }
            }
            $head = "$ref $commit"
        }
        Add-Line "  launcher clone         $head"
        $kv = @(Select-String -LiteralPath "$clone\kit\ws_setup.ps1" -Pattern '^\$KitVersion\s*=\s*''([^'']+)''' -ErrorAction SilentlyContinue | Select-Object -First 1)
        if ($kv.Count) { Add-Line "  kit version            $($kv[0].Matches[0].Groups[1].Value)" }
    } else { Add-Line '  launcher clone         none' }
    if ($Links.Count) { Add-Line '  shortcuts:'; foreach ($l in $Links) { Add-Line "  $l" } } else { Add-Line '  no shortcut to OpenSmash.exe or the launcher (desktop, Start menu)' }
}

Write-Section (L 'Python and Git' 'Python et Git') {
    $found = $false
    foreach ($py in @("$Game\deps\venv\Scripts\python.exe", "$Game\deps\python\python.exe")) {
        if ($Game -and (Test-There $py)) { $found = $true; Add-Line ("  {0}  {1}" -f $py, ((& $py --version 2>&1) -join ' ')) }
    }
    if ($Game) {
        Add-Line "  deps\venv ready        $(Test-There "$Game\deps\venv\.opensmash-ready")"
        if (-not $found) { Add-Note (L "OpenSmash has no Python yet (deps\python): open OpenSmash once; its Mods page and the mods sync need it" "OpenSmash n'a pas encore son Python (deps\python) : ouvre OpenSmash une fois ; sa page Mods et la synchro des mods en ont besoin") }
    }
    $g = Get-Command git -ErrorAction SilentlyContinue
    Add-Line "  git                    $(if ($g) { (& $g.Source --version) -join ' ' } else { 'not found' })"
    $pyl = Get-Command py -ErrorAction SilentlyContinue
    if ($pyl) { Add-Line "  py -0p                 $((& $pyl.Source -0p 2>&1) -join '; ')" }
}

if ($Game) {
    Write-Section (L 'Settings' 'Réglages') {
        foreach ($n in 'online_server.txt', 'online_direct.txt', 'server_region.txt', 'server_region_auto.txt', 'update_channel.txt', 'crash_reports.txt', 'telemetry.txt', 'launch_mode.txt', 'save_disk.txt', 'build_location.txt') {
            foreach ($p in @("$Game\config\$n", "$Game\$n")) { if (Test-There $p) { Add-Line ("  {0,-30} {1}" -f $p.Substring($Game.Length + 1), (Hide-Ip (Read-First $p))); break } }
        }
        foreach ($n in 'display.ini', 'graphics.ini', 'controllers.ini') {
            $p = "$Game\config\$n"
            if (Test-There $p) {
                $set = @([IO.File]::ReadAllLines($p) | Where-Object { $_ -notmatch '^\s*([#;]|$)' } | Select-Object -First 40)
                Add-Line "  config\$n`: $($set -join ' | ')"
            }
        }
        $sc = "$Game\dump\shadercache"
        Add-Line "  shader cache           complete.txt $(Test-There "$sc\complete.txt"), vulkan_ready.txt $(Test-There "$sc\vulkan_ready.txt"), vulkan_auto_trial.txt '$(Read-First "$sc\vulkan_auto_trial.txt")'"
    }

    Write-Section 'Mods' {
        $j = "$Game\mods\mods.json"
        if (Test-There $j) {
            $state = [IO.File]::ReadAllText($j) | ConvertFrom-Json
            $names = @($state.order | Select-Object -Unique)
            $on = @($names | Where-Object { $state.mods.$_.enabled })
            Add-Line "  mods\mods.json         $($names.Count) mods, $($on.Count) on"
            if ($on.Count) { Add-Line "  on: $(($on | Select-Object -First 80) -join ', ')" }
        } else { Add-Line '  mods\mods.json         none' }
        if (Test-There "$Game\dump\mods\applied.json") {
            $applied = [IO.File]::ReadAllText("$Game\dump\mods\applied.json") | ConvertFrom-Json
            Add-Line "  dump\mods\applied.json $(@($applied.mods).Count) mods applied (the game plays these)"
        }
        $nro = @(Get-ChildItem -LiteralPath "$Game\skyline\plugins" -Filter '*.nro' -ErrorAction SilentlyContinue | ForEach-Object { $_.Name })
        Add-Line "  skyline\plugins        $(if ($nro.Count) { $nro -join ', ' } else { 'none' })"
    }
}

Write-Section (L 'Running now' 'En cours') {
    $procs = @(Get-Process -Name OpenSmash, ssbu, dotnet, python, pythonw -ErrorAction SilentlyContinue)
    if (-not $procs.Count) { Add-Line '  none of OpenSmash, ssbu, dotnet, python' }
    foreach ($p in $procs) { Add-Line ("  {0} (pid {1}, {2:N0} MB) {3}" -f $p.ProcessName, $p.Id, ($p.WorkingSet64 / 1MB), $p.Path) }
}

Write-Section (L 'Network' 'Réseau') {
    $bad = @()
    foreach ($u in 'https://api.github.com/', 'https://github.com/OpenSmash-Ultimate/OpenSmash-Ultimate/releases/latest', 'https://objects.githubusercontent.com/',
                   'https://release-assets.githubusercontent.com/', 'https://raw.githubusercontent.com/Nilsix/WindowSmashLauncher/main/README.md',
                   'https://codeload.github.com/', 'https://api.nuget.org/v3/index.json', 'https://builds.dotnet.microsoft.com/dotnet/release-metadata/8.0/releases.json',
                   'https://gamebanana.com/') {
        $res = Test-Url $u
        if ($res -like 'NOT REACHED*') { $bad += ([uri]$u).Host }
        Add-Line ("  {0,-46} {1}" -f ([uri]$u).Host, $res)
    }
    if ($bad.Count) { Add-Note (L "not reached: $($bad -join ', ') (internet, a firewall, an antivirus or a VPN): updates and downloads need them" "pas joignable : $($bad -join ', ') (internet, un pare-feu, un antivirus ou un VPN) : les mises à jour et téléchargements en ont besoin") }
}

Write-Section (L 'Windows Firewall' 'Pare-feu Windows') {
    $rules = @(Get-NetFirewallRule -ErrorAction Stop | Where-Object { $_.DisplayName -match 'OpenSmash|WindowSmash|ssbu' })
    $in = $false
    foreach ($r in $rules) {
        $prog = ''
        try { $prog = ($r | Get-NetFirewallApplicationFilter -ErrorAction Stop).Program } catch { }
        if ($r.Direction -eq 'Inbound' -and $r.Action -eq 'Allow' -and [string]$r.Enabled -eq 'True') { $in = $true }
        Add-Line ("  {0}: {1} {2} {3}, profile {4}, {5}" -f $r.DisplayName, $r.Direction, $r.Action, $(if ([string]$r.Enabled -eq 'True') { 'on' } else { 'off' }), $r.Profile, $prog)
    }
    if (-not $rules.Count) { Add-Line '  no rule for OpenSmash or ssbu.exe' }
    if (-not $in) { Add-Line '  no rule lets the game in: LAN games and direct connections to this PC can be blocked (the official lobby goes through its relay)' }
}

Write-Section (L 'Windows: crashes of the last 7 days' 'Windows : plantages des 7 derniers jours') {
    $ev = @()
    try {
        $ev = @(Get-WinEvent -FilterHashtable @{ LogName = 'Application'; ProviderName = 'Application Error', '.NET Runtime'; StartTime = (Get-Date).AddDays(-7) } -MaxEvents 300 -ErrorAction Stop |
            Where-Object { $_.Message -match 'ssbu|OpenSmash|python|dotnet' } | Select-Object -First 6)
    } catch { }
    if (-not $ev.Count) { Add-Line '  none for ssbu, OpenSmash, python or dotnet' }
    foreach ($e in $ev) {
        Add-Line ("  {0:yyyy-MM-dd HH:mm} {1}:" -f $e.TimeCreated, $e.ProviderName)
        foreach ($l in @($e.Message -split "`r?`n" | Where-Object { $_.Trim() } | Select-Object -First 12)) { Add-Line "    $($l.Trim())" }
    }
}

if ($Game) {
    Write-Section (L "OpenSmash's reports and logs" "Rapports et journaux d'OpenSmash") {
        $reports = @(Get-ChildItem -LiteralPath "$Game\reports" -Filter '*.txt' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)
        Add-Line "  reports\               $($reports.Count) report(s) (.txt; the .dmp memory dumps are not read)"
        foreach ($r in @($reports | Select-Object -First 8)) { Add-Line ("    {0} ({1:N0} bytes, {2:yyyy-MM-dd HH:mm})" -f $r.Name, $r.Length, $r.LastWriteTime) }
        if ($reports.Count) {
            Add-Line "  $($reports[0].Name), its first lines:"
            foreach ($l in @(Get-Content -LiteralPath $reports[0].FullName -TotalCount 20 -Encoding UTF8)) { Add-Line ('    ' + (Hide-Ip $l)) }
        }
        Show-Tail "$Game\build\launcher_update.log" 25
        Show-Tail "$Game\build\play.log" 60 'Failed to find filepath index'
        Show-Tail "$Game\build\play.prev.log" 25 'Failed to find filepath index'
        Show-Tail "$Game\install.log" 30
        Show-Tail "$env:TEMP\os_update.log" 20
    }
}

$head = @('OPENSMASH DIAGNOSTIC (Nilsix tools, Diagnostic OpenSmash.bat, version 1)', "Date: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')", '',
          '--- What looks wrong')
if ($Notes.Count) { $head += @($Notes | ForEach-Object { "  - $_" }) } else { $head += '  nothing obvious: see below' }
$text = Hide-Private ((@($head) + @($Lines)) -join "`r`n")
try { [IO.File]::WriteAllText($Out, $text + "`r`n", (New-Object Text.UTF8Encoding $true)) }
catch {   # (a desktop that cannot be written to)
    $Out = Join-Path $env:TEMP 'Diagnostic OpenSmash.txt'
    [IO.File]::WriteAllText($Out, $text + "`r`n", (New-Object Text.UTF8Encoding $true))
}

Write-Host ''
if ($Notes.Count) {
    Write-Host (L 'What looks wrong:' 'Ce qui semble ne pas aller :') -ForegroundColor Yellow
    foreach ($n in $Notes) { Write-Host "  - $(Hide-Private $n)" -ForegroundColor Yellow }
} else { Write-Host (L 'Nothing obvious found.' "Rien d'évident trouvé.") -ForegroundColor Green }
Write-Host ''
Write-Host (L "Report written: $Out" "Rapport écrit : $Out") -ForegroundColor Green
Write-Host (L 'Send that file to whoever helps you (Nilsix, on Discord...).' "Envoie ce fichier à la personne qui t'aide (Nilsix, sur Discord...).") -ForegroundColor Green
if (-not $env:OPENSMASH_DIAG_QUIET) { try { Start-Process explorer.exe -ArgumentList "/select,`"$Out`"" } catch { } }
exit 0
#@@END diag.ps1
