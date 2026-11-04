# OpenSmash launcher's kit (kit-opensmash 1.x, for OpenSmash = github.com/OpenSmash-Ultimate/ssbu-recomp): replaced on
# 2026-11-04 by kit 4.0. WindowSmash and OpenSmash merged into github.com/OpenSmash-Ultimate/OpenSmash-Ultimate, which
# kit\ws_setup.ps1 installs (an OpenSmash install gets a new one there, its save taken over). An old
# "OpenSmash Launcher.bat" runs this file itself when the launcher's repository was up to date already (no restart into
# the new bootstrap): it passes on to the new kit with the same folder and the matching mode.
# This file must stay UTF-8 with a BOM and CRLF.
param([string]$KitDir = '', [string]$Mode = '')

# kit-opensmash's modes -> kit 4.0's (lowspec and anything else: the menu)
$map = @{ 'install' = 'install'; 'play' = 'play'; 'play-norollback' = 'play'; 'play-rollback' = 'play-rollback'; 'diag' = 'diag'; 'dlc' = 'dlc'; 'unlock' = 'unlock' }
$m = if ($Mode -and $map.ContainsKey($Mode)) { $map[$Mode] } else { '' }
& (Join-Path (Split-Path $PSScriptRoot -Parent) 'kit\ws_setup.ps1') -KitDir $KitDir -Mode $m
exit $LASTEXITCODE
