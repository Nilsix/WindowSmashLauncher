# memory.md - full context of the WindowSmash work (for a Claude Code session or a developer)

Written 2026-10-19 by the Claude Code session that set all of this up with the repository owner (Nilsix), from
2026-10-14 to 2026-10-19. It records what was done, why, what was measured, what broke and how it was fixed, and
where everything is. Read it before changing the launcher or the owner's installation. Nothing in here is a key or
game data; the owner's own files (game dumps, `prod.keys`) stay on the owner's PC and are never committed.

Contents:
1. Goal and people
2. The owner's PC (hardware, drives, paths)
3. The game files and their identifiers
4. WindowSmash upstream: what it is, versions, tools, config files
5. How WindowSmash 13.0.4 was set up on the owner's PC (step by step, with commands)
6. Every problem met, its cause and the fix
7. Netplay (LAN mix-up, UPnP, the online lobby, protocol versions)
8. Performance (FPS analysis, shader precompilation, latency, PC checkup)
9. Unlocking every fighter on 13.0.4
10. This repository: the launcher (bootstrap) and the kit
11. Kit reference: steps, error codes, warnings, pinned versions and hashes, test hooks
12. Kit history and the tests that were run
13. Procedures (rebuild, bump the pin, test, release, manual steps)
14. Open items, known gaps, ideas
15. The earlier project: ssbu-recomp (context only)

---

## 1. Goal and people

- The owner (GitHub: Nilsix, writes in French) wants to play Super Smash Bros. Ultimate natively on PC and online
  with friends. Friends do not have Claude Code: they get one file (`WindowSmash Launcher.bat`) that must install
  everything, keep itself up to date, and report errors in a way the owner can paste back to Claude.
- WindowSmash: https://github.com/SNO2207/WindowSmash - a static recompilation of SSBU (AArch64 -> C -> clang-cl ->
  Windows x64) with a Direct3D 11 renderer and a UDP relay that carries the game's Local Wireless mode online.
- Everyone must run **exactly the same WindowSmash build and game version** to see each other online. That is why
  the kit pins one WindowSmash commit and one toolchain, and why the launcher updates itself.
- The owner sometimes runs another Claude Code session (another project) that relaunches a heavy game in a loop
  (~8 GB of RAM). It caused a compiler out-of-memory and a 14-minute link here. Never kill another session's
  processes; build with fewer jobs when memory is short.

## 2. The owner's PC

- CPU AMD Ryzen 7 2700X (8 cores / 16 threads, Zen+), board Gigabyte X470 AORUS ULTRA GAMING.
- RAM 16 GB = 2 x 8 GB Corsair Vengeance LPX CMK16GX4M2D3600C18 (DDR4-3600) **running at 2133 MHz: XMP is off in
  the BIOS** (found 2026-10-19; the owner was told to enable XMP, falling back to 3200 if unstable). On a 2700X this
  is the biggest performance loss. Check `Win32_PhysicalMemory.ConfiguredClockSpeed` before blaming software.
- GPU NVIDIA GeForce RTX 4060 (driver 32.0.16.1088 of 2026-07-22), monitor 1920x1080 at 60 Hz. A "Parsec Virtual
  Display Adapter" also exists (Parsec is installed); it is not used by the game.
- C: = Crucial BX500 500 GB SATA SSD, only ~32 GB free. D: = **WD easystore 1 TB external USB HDD** ("Disque
  Externe"), ~45-49 GB free. Every game folder, WindowSmash and the build data are on D: (slow loads; possible
  hitches when the game streams data.arc). Recommended: an NVMe SSD (the board has M.2 slots).
- Windows 11 Home 25H2 (build 26200), French locale, PowerShell 5.1, power plan "Haute performance".
  The account is not an administrator in the shells Claude runs (UAC prompts would block unattended work).
- Tools present: Git for Windows 2.55, Python 3.14.5 (from the Python install manager:
  `%LOCALAPPDATA%\Python\pythoncore-3.14-64\python.exe`; `python` in PATH is the WindowsApps alias of it),
  Visual Studio Build Tools 2026 (18.5) with the Windows SDK 10.0.26100 and CMake 4.2.3, but **without** the
  "C++ Clang Compiler for Windows" component. No `gh` CLI. GitHub credentials for `Nilsix` are stored in Git
  Credential Manager (pushing to this repository works).

### Paths on the owner's PC

| Path | What |
| :--- | :--- |
| `D:\WindowSmash` | The WindowSmash clone, branch `main` at `adfb154` (see 4). Version folder `v13.0.4\`. |
| `D:\WindowSmash\v13.0.4\` | The 13.0.4 tree: `dump\exefs`, `dump\modules\romfs.cfg` (layered), `romfs.layers`, `romfs_patch.bin` (3.58 GiB), `dump\nro` (98 modules), `dump\fonts`, `dump\shadercache` (45,828 files after precompilation), `build\ssbu.exe` (1,026 MB), `build\play.log`, `save\` (the save, all fighters unlocked), `save_backups\`, `version.txt`, `install.json`. |
| `D:\WindowSmash\dump\base\program_v0.nca` | The cartridge's Program NCA decrypted in place (14,531,444,736 bytes). The base of the layered RomFS. |
| `D:\WindowSmash\dump\modules\romfs.cfg` | Points into `program_v0.nca` at byte 0x1b28000 (plain cfg). |
| `D:\WindowSmash\dump\fonts\` | 7 `.bfttf` firmware fonts (the 6 required + `nintendo_ext2_003.bfttf`). |
| `D:\WindowSmash\.venv\` | Python 3.14 venv with `pycryptodomex` (WindowSmash's tools import `Cryptodome`). |
| `D:\WindowSmash\deps\SDL3` | Junction to `D:\ssbu-recomp-data\deps\SDL3` (SDL3 3.4.18 VC package). |
| `D:\WindowSmash\dump\_setup\llvm-20.1.8`, `...\opus` | Junctions to `D:\ssbu-recomp-data\deps\llvm-20.1.8` and `...\deps\opus`, so the kit finds them where it puts them on a friend's PC. |
| `D:\WindowSmash\build\` | Empty folder; `tools\shader_aot.py` needs it (see 6.8). |
| `D:\WindowSmash\display.ini` | `latency = 1` (the rest is the game's default text). `controllers.ini` also there. |
| `D:\WindowSmash\online_server.txt` | Upstream default `smash.recomps.wtf:39420` (no lobby code set). |
| `D:\ssbu-recomp-data\packages\` | The owner's files: `Super Smash Bros. Ultimate.xci` (base 1.0.0 cartridge dump, 15 GB), `Super Smash Bros Ultimate 13_0_4.nsp` (update), `prod.keys`. |
| `C:\Users\PC\.switch\prod.keys` | Copy of the owner's keys (where the tools look by default; the kit uses `<repo>\keys\`). |
| `D:\ssbu-recomp-data\deps\` | `llvm-20.1.8\` (portable LLVM, clang-cl), `opus\` (libopus 1.5.2 static, `/MT`), `SDL3\`, `src\opus-*` (build trees). |
| `D:\ssbu-recomp-data\downloads\` | LLVM 20.1.8 archive + `.sig`, `release-keys.asc`, opus tarballs + `SHA256SUMS`, SDL3 zip. |
| `D:\ssbu-recomp-data\logs\` | `windowsmash_install*.log`, `shader_aot.log`. |
| `D:\ssbu-recomp-data\windowsmash_prep.py` | First version of the XCI -> plain NCA and fonts extraction (now inside `kit\ws_setup.py`). |
| `D:\ssbu-recomp-data\windowsmash_install.py` | First version of the update.py fix wrapper (now inside `kit\ws_setup.py`). |
| `D:\ssbu-recomp-data\windowsmash-setup-kit\` | The kit before this repository: `src\` (launcher.bat, ws_setup.ps1, ws_setup.py), `build_kit.py` (made one self-extracting .bat), `dist\`. Superseded by this repository (kit 2.0). |
| `%LOCALAPPDATA%\WindowSmash-setup\` | Kit state: `logs\<time>\`, `inputs.json` (paths of the game files chosen last time), `repo.txt` (where WindowSmash is installed: `D:\WindowSmash`), `downloads\`. |
| `%LOCALAPPDATA%\WindowSmashLauncher\` | The launcher's own clone of this repository (managed by the bootstrap; do not edit). |
| Desktop | `Installer WindowSmash.bat` (old single-file kit 1.3, superseded), `Checkup PC - 19-10-2026.txt` (the PC checkup report). |

## 3. The game files and their identifiers

| Item | Value |
| :--- | :--- |
| Base game | Cartridge dump (`.xci`), program title `01006A800016E000`, display version 1.0.0, title version 0, key generation 4, Program NCA `33772dd69ad331de693d936465e2dfce.nca`, 13.53 GiB; secure partition holds the game, the update partition holds a firmware (fonts titles `0100000000000810`-`0814`, TimeZoneBinary `0100000000000818` is a 1-file stub). |
| Update | `.nsp`, update title `01006A800016E800` (in its cnmt; its Program NCA header carries the base id `01006A800016E000`), display version **13.0.4**, title version 1966080 (v1966080), key generation 6, titlekey crypto with a common ticket, RomFS section is BKTR (patch). |
| 13.0.4 main module | NSO build id `3EAE0063B12FD81E99FB5980BA56297049EA94F9`, text size 0x39c7e90. sdk build id `5fd4f531c1195e9e5510c9e73f22cd39612839f8` (text 0x540950). |
| Updated RomFS | 16.39 GiB, 1,074,276 blocks of 16 KiB, data.arc version 13.0.4 (17,600,869,448 bytes when extracted). |
| Save (`system_data.bin`) | 0x5B4AF8 bytes, save format 0x1b at offset 4, offset 8 = version that last wrote it (0xb000 = 11.0.0, 0xd004 = 13.0.4, 0xd005 = 13.0.5). Fighter tables: FLAGS at 0x53FF40 (8 bytes per fighter), RECORDS at 0x54FEA8. |
| prod.keys | Needs `header_key`, `key_area_key_application_XX` and `titlekek_XX` up to generation 6 for these files (the owner's file has 0..21). |

## 4. WindowSmash upstream

- Repository: https://github.com/SNO2207/WindowSmash (no license specified for its own source). Python tools
  (Python 3.14 required: `tools\arc.py` uses `compression.zstd`; `pycryptodomex`), C runtime, Direct3D 11 renderer.
- Branch history seen: `main` (11.0.0 only) -> `multi-version` (5682805, several game versions side by side,
  `tools\install_version.py`, `tools\update.py` applies a Patch NSP as a layered RomFS; tested by upstream with
  13.0.5) -> `linux-port` -> merged into `main`. **The pinned commit is `adfb15452825e18ac908ab229707f5b2aadde5fb`**
  (main, "Merge pull request #4 from SNO2207/multi-version", 2026-10-18): online lobby, direct connections between
  players of a room, SDL3 pads, display options, shader prewarm/AOT, crash reports.
- Key tools: `tools\install_version.py install --tree v13.0.4 --update <nsp> --keys <dir> --jobs N [--dlc <dir>]
  [--force] [--no-build]` (steps exefs, romfs, aoc, nro, extras, version, build; state in `<tree>\install.json`; it
  refuses a tree that has `dump\` but no `install.json` unless `--force`); `tools\update.py` (Patch class, Builder,
  exact patch when the base is the original release stored as a plain NCA); `tools\recomp.py all <exefs> --out
  <build> --tree <tree> --jobs N` (lift + compile + link; modules reused across trees via `tools\modcache.py`);
  `tools\nca.py` (NCA reader; `romfs-cfg`, `romfs-get`, `aoc-cfg`; reads keys from `<dir>\prod.keys` and
  `<dir>\title.keys`); `tools\arc.py` (data.arc; it cannot read the 1.0.0 data.arc's table - zstd "Unknown frame
  descriptor" - which does not matter when the exact patch path is used); `tools\cc.py` (finds clang-cl: `SSBU_CLANG`,
  else VS's Llvm component, else `C:\Program Files\LLVM`; flags `/arch:AVX2 -mfma -mf16c /clang:-ffp-contract=off`;
  optional `SSBU_OPUS_LIBS`, `SSBU_VPX_DIR`, `SSBU_SDL3_DIR` (default `<repo>\deps\SDL3`)); `tools\shader_aot.py`
  (shaders ahead of time); `tools\unlock_all.py` (+ `tools\Unlock-All-Fighters.ps1`); `tools\ssbu_relay.py`
  (relay / lobby server; `--probe host:port`).
- Launchers at the repo root: `Play SSBU.bat` (online by default: reads `online_server.txt`, asks the online name
  once into `online_name.txt`, `online_direct.txt` = `off` keeps all traffic through the lobby), `Play SSBU
  Offline.bat`, `Host SSBU Netplay.bat` / `Join SSBU Netplay.bat` (private relay), `Prepare Shaders.bat` (calls the
  system `python`: fails on a PC where only the venv has pycryptodomex or where `SSBU_CLANG` is not set - the kit
  runs shader_aot itself), `Unlock All Fighters.bat` (refuses 13.0.4), `tools\pick_version.bat` (picks a built
  version folder; remembers it in `last_version.txt`).
- Config files written at the first start in the repo root: `display.ini` (window = windowed|borderless|fullscreen,
  width, height, pacing = clock|vrr|display, latency = 1-3 (default 3), hide_cursor) and `controllers.ini`.
- The game renders at 1920x1080 internally and scales to the window; game logic is fixed at 60 FPS. F1 overlay,
  F2 details, F3 screenshot, F6 sampling profile, F11 / Alt+Enter full screen. `SSBU_HITCH=<ms>` logs what made
  each slow frame late. Crashes/freezes write `reports\`.
- Netplay protocol: 1 at 5682805, **2 at adfb154** (`runtime\net.h` `NET_PROTOCOL`); the public lobby runs 2, so
  the two cannot meet. Lobby `smash.recomps.wtf:39420` (177.7.46.134), ~83 ms from the owner's PC.

## 5. How 13.0.4 was set up on the owner's PC

1. Clone WindowSmash to `D:\WindowSmash` (it was later moved from `multi-version` 5682805 to `main` adfb154).
2. `python -m venv .venv` and `.venv\Scripts\python -m pip install -r requirements.txt` (pycryptodomex 3.24.1).
3. clang-cl: the VS Clang component is missing, so the official LLVM 20.1.8 Windows archive was downloaded
   (`clang+llvm-20.1.8-x86_64-pc-windows-msvc.tar.xz`, signature checked with `release-keys.asc`: good signature
   from Hans Wennborg) and extracted with `C:\Windows\System32\tar.exe -xf ... --strip-components 1`.
   `SSBU_CLANG=D:\ssbu-recomp-data\deps\llvm-20.1.8\bin\clang-cl.exe`. All 31 runtime files compiled first try.
4. Base: the XCI's secure partition Program NCA written decrypted at its original offsets
   (`dump\base\program_v0.nca`; header decrypted with header_key, every section through `Section.read_raw`), then
   `tools\nca.py romfs-cfg dump\base\program_v0.nca --keys <dir> --out dump\modules\romfs.cfg`.
5. Fonts: the font NCAs of the XCI's update partition opened in place, `.bfttf` files copied to `dump\fonts`.
6. `install_version.py install --tree v13.0.4 --update <13.0.4.nsp> --keys <dir> --jobs N --force` through the fix
   of 6.1 (exefs, layered romfs with exact patch, nro: 98 modules, extras: fonts copied, version.txt, build).
7. Build: imports check "0 strong and 415 weak symbols unresolved across 101 modules" (same as upstream's 11.0.0 and
   13.0.5 - a good sign for 13.0.4). First build: OOM with 12 jobs (6.4), resumed with 4 jobs; `ssbu.exe` 1,026 MB
   from 1,611 objects, link 839 s under memory pressure. Rebuild on adfb154: 1,057 s total, 0 stale objects (the
   regenerated C was identical), only the runtime (SDL3 flag) and the link (584 s, 1,614 objects) ran.
8. libopus (music): built from opus 1.5.2 with the VS CMake, static, `/MT`, and passed with
   `SSBU_OPUS_LIBS=...\opus\lib\opus.lib` (the runtime declares the opus prototypes itself; no include path needed).
   Without it, Opus packets decode as silence.
9. SDL3: `deps\SDL3` junction (the runtime loads SDL3.dll at run time; the link copies it beside ssbu.exe).
10. Unlock (9), shader precompilation and latency 1 (8).

## 6. Problems, causes, fixes

1. **update.py cannot open the 13.0.4 update.** `Patch.__init__` reads the update's IVFC level-5 hash table with
   `vread` from the patch alone; in 13.0.4 part of that table maps to original-release bytes, so it raises
   `LookupError: bytes at 0x20080 come from the original release (at 0x1c020)`. Fix (in `kit\ws_setup.py`,
   `cmd_install`): monkeypatch `update.Patch.__init__` to catch the LookupError and keep `hash_at`, then wrap
   `update.apply_romfs` to read the table with `patch.vread(hash_at, blocks*32, lambda ph, n: b.base_read(start+ph, n))`
   where `start = Builder.base_section()` (requires the base to be the original release as a plain NCA). The
   repository is not modified. Result: "the base is the release this update was made for: applying the patch as it
   is", 1,074,276 of 1,074,276 blocks verified, romfs step ~6-10 min.
2. **WindowSmash's tools cannot read an XCI.** `kit\ws_setup.py` parses the gamecard (HEAD at 0x100 or 0x1100,
   HFS0 root, partitions) and opens NCAs at their offsets with `nca.Nca(path, keys, offset)`. For an NSP base with
   titlekey crypto, the plain NCA keeps its rights id, so the title key from the NSP's ticket is appended to
   `<keys>\title.keys` (else `update.Builder.base_section()` cannot open the plain NCA and the exact path is lost).
3. **No clang-cl.** Portable LLVM 20.1.8 (see 5.3). The friends get the same version (same archive hash) so that
   everyone's code generation matches.
4. **Compiler out of memory** (`LLVM ERROR: out of memory`) during `lua2cpp_miifighter` with 12 jobs while the other
   session's game used ~8 GB: resumed with `--jobs 4`. The kit detects OOM text in the build output and retries with
   half the jobs (exit code 3 from the helper). lld-link needs ~4.5 GB.
5. **opus 1.3.1 tarball** lacks `opus_buildtype.cmake` (CMake configure fails): use opus 1.5.2. CMake 4.x needs
   `-DCMAKE_POLICY_DEFAULT_CMP0091=NEW` for `CMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded`. With a busy PC the VS
   generator's configure took 16 minutes once.
6. **Unlock All Fighters refuses 13.0.4** ("knows the save layout of 11.0.0, 13.0.5 only"). See 9.
7. **Prepare Shaders.bat fails here** (system Python has no Cryptodome; no `SSBU_CLANG`): run
   `.venv\Scripts\python.exe tools\shader_aot.py --tree v13.0.4 --jobs N` with `SSBU_CLANG` set.
8. **shader_aot.py stops with `NotADirectoryError [WinError 267]`**: it builds its tool as `<port>\build\shaderaot.exe`
   and runs the compiler with that folder as working directory; with only a version folder built, `<port>\build`
   does not exist. Fix: create the empty folder (git-ignored; no ssbu.exe in it, so the launchers do not list it).
9. **The kit's first test run** failed `plain-nca` with `FileNotFoundError` (disk_usage on a folder not created yet):
   fixed (makedirs first). Other bugs found by tests and fixed: the update's identity check (its NCA header carries
   the base id; the update id is in the cnmt), the report hid the user name "PC" inside other words (now only in
   `\Users\<name>\`), font metadata NCAs (`.cnmt.nca`) gave false warnings, option 5 did not find LLVM on the owner's
   manual layout (now `Ensure-LLVM` reinstalls it), a generated PowerShell line got a backspace character from a
   Python escape (`\b`).
10. **PowerShell 5.1 pitfalls handled in the kit:** native stderr with `2>&1` under `$ErrorActionPreference='Stop'`
    throws (native calls run with 'Continue'); output of a native command inside a function is captured into the
    function's return value (live helpers are piped to `Out-Host`); `Start-Process -ArgumentList` with an empty
    string throws; installers that need elevation must be started without redirection (`Run-Installer`); scripts
    with accents must be UTF-8 with BOM.
11. **Claude Code safety check** refused `rm -rf` on some folders (`D:\WS-kittest`, a variable path): left for the
    owner. `D:\WS-kittest` (~20 GB test clone) may still exist and can be deleted by hand.

## 7. Netplay

- Old way (protocol 1): `Host SSBU Netplay.bat` runs a relay on UDP 39420 and tries UPnP; `Join SSBU Netplay.bat`
  connects to the host's address and room name. A friend hosted with "UPnP unavailable: only same-network friends
  can join (192.168.1.42:39420)" and the owner joined `192.168.1.42` from another home: stuck on "connecting" with 0
  rooms. Both homes use `192.168.1.x`; ARP for 192.168.1.42 was "Incomplete" on the owner's LAN, so the address was
  the friend's private LAN address, unreachable from the internet. Options then: a virtual LAN (Radmin VPN,
  Tailscale), swap hosts, port forwarding (UDP 39420 + an inbound firewall rule; fails under CGNAT).
- New way (protocol 2, adfb154): `Play SSBU.bat` joins the public lobby; Local Wireless lists every room of players
  with the same game version; no port forwarding. Private group: the same lobby code after the address in
  `online_server.txt` on every PC. The overlay (F1) shows `Online: N players, M rooms - you are <name>, ping X ms`.
  Players of a room connect directly by default (they learn each other's internet address); `off` in
  `online_direct.txt` keeps everything through the lobby. The owner's PC network profile is "Public": Windows
  Firewall must allow ssbu.exe on public networks.
- Everyone must match: WindowSmash commit adfb154, game 13.0.4 (main build id above), same toolchain (LLVM 20.1.8).
  A probe of the lobby: `.venv\Scripts\python.exe tools\ssbu_relay.py --probe smash.recomps.wtf:39420`.

## 8. Performance

- FPS drops (26-50 FPS) were **first-use shader compiles**: per 30 s of play.log, FPS fell exactly while the shader
  count grew 192 -> 1,019 (a first match), then 59.8 steady. The CPU was ~13 % busy, nothing else was loaded.
- Shaders precompiled 2026-10-19: 22,652 distinct programs (17,874 vertex, 4,778 pixel) -> 46.9k keys in 14 parts,
  ~39.4k compiled this run, ~7.5k already cached, 5 fxc failures (the game compiles those itself), 3,326 s with 14
  workers. 8 workers used only 50 % of the CPU; priority alone does not help when nothing competes - workers do.
  `shader_aot.py` starts its workers below normal priority; they were raised to AboveNormal by hand.
- `display.ini` latency = 1 (default 3): the RTX 4060 needs ~3 ms per frame, so there is headroom.
- PC checkup (report on the Desktop): Game Mode was off (turned on: `HKCU\Software\Microsoft\GameBar
  AutoGameModeEnabled=1`), Xbox background recording was on (turned off: `HKCU\...\GameDVR AppCaptureEnabled=0,
  HistoricalCaptureEnabled=0`, `HKCU\System\GameConfigStore GameDVR_Enabled=0`), unused apps removed for the user
  (Microsoft.BingSearch, Microsoft.Edge.GameAssist, Microsoft.Windows.DevHome, Microsoft.OutlookForWindows; Teams
  kept because it was used; Xbox components kept), 1.5 GB of temp files older than 2 days deleted (not the
  `%TEMP%\claude` folder). Recommendations left to the owner: XMP, an NVMe SSD, NVIDIA driver update, HAGS,
  uninstall "Avast Update Helper", optional Defender exclusion for the WindowSmash folder. The PC was shut down after.
- Not built: libvpx, so the game's movies (intro, trailers) stay black. The game goes on normally.

## 9. Unlocking every fighter on 13.0.4

`tools\unlock_all.py` (LAYOUTS keyed by main build id) knows 11.0.0 and 13.0.5, which share one layout. The 13.0.4
save was checked before writing: same size 0x5B4AF8, format 0x1b, writer 0xd004, the 8 starters (save_no 0, 1, 2, 3,
5, 6, 7, 8) exactly at FLAGS, valid milestones; the tool's own checks pass in `--dry-run`. It was then run with
`LAYOUTS['3EAE0063B12FD81E99FB5980BA56297049EA94F9'] = ('13.0.4', 0x5B4AF8, 0x53FF40, 0x54FEA8)` added in memory:
66 fighters unlocked (74 base fighters minus the 8 starters; DLC fighters are left to the game), backup
`v13.0.4\save_backups\system_data.bin.before-unlock-20261018_204038`. The kit's menu option 4 does the same
(`ws_setup.py unlock`). The game must be closed (it rewrites its save when quitting), and the save exists only after
a first start.

## 10. This repository

```
WindowSmash Launcher.bat   the bootstrap (one file; the part after "exit /b" is boot.ps1, extracted and run)
kit/ws_setup.ps1           the installer (PowerShell 5.1; UTF-8 with BOM, CRLF - keep it so)
kit/ws_setup.py            the Python helper (run with the WindowSmash venv)
README.md                  for the friends (French)
memory.md                  this file
.gitattributes             *.bat and *.ps1 kept byte for byte (-text)
```

Bootstrap (`WindowSmash Launcher.bat`, boot.ps1):
1. Git: `Find-Git` (PATH, `Program Files\Git\cmd`, `%LOCALAPPDATA%\Programs\Git\cmd`); if missing, `winget install
   -e --id Git.Git --silent`, else the official Git 2.56.0.2 installer (SHA-256 and Authenticode "Johannes
   Schindelin" checked, `/VERYSILENT /NORESTART /NOCANCEL /SP- /SUPPRESSMSGBOXES`, started through the shell so it
   can elevate).
2. The repository clone in `%LOCALAPPDATA%\WindowSmashLauncher`: `git clone` the first time; then `git fetch` and,
   when `@{u}` differs from HEAD, `git reset --hard @{u}` (the folder belongs to the launcher). Offline: carries on.
3. The file the user started (Desktop, Downloads...) is overwritten with the clone's `WindowSmash Launcher.bat` when
   their contents differ (every run, not only after an update), so the user's copy stays current.
4. After a change or the first clone: starts the clone's `WindowSmash Launcher.bat` in a new window
   (`cmd /c ""<bat>" <mode>"`, env `WSL_RELAUNCHED=1` so the new instance does not restart again, `WSL_KITDIR` = the
   folder of the file the user started) and exits with 20 (the old window closes without pausing).
5. Runs `kit\ws_setup.ps1 -KitDir <WSL_KITDIR or the folder of the running file> -Mode <arg>`.
Exit codes seen by the .bat: 0 done, 10 failure already reported (paused), 20 restarted, else it pauses with a
message. Shortcuts created by the kit point to the clone's launcher (`play` argument for the game shortcut), so
every start checks for updates; in `play` mode the kit compares the WindowSmash HEAD with the pinned commit and
offers the update (install flow) when they differ. The kit's report shows the launcher revision (`Launcher (git)`).

**Invariant of the .bat (do not break it):** cmd.exe runs a batch file line by line, reopening it at a byte offset
for each line, but reads a parenthesized block whole before running it. The update (`git reset --hard` in the clone,
or the copy over the user's file) rewrites the very file cmd.exe is running, so everything after the `set`/`title`
lines is ONE block - the PowerShell call plus the exit-code handling - in which every path ends with `exit /b`.
cmd.exe never reads the file again after PowerShell starts. Delayed expansion (`!RC!`) is enabled only after the
`set` lines so that a `!` in the file's path survives. Never put a `goto`/`call :label` after the PowerShell call
(both re-read the file), and keep the header ASCII (`chcp 65001` changes how cmd decodes the following lines).

## 11. Kit reference

Menu / modes: 1 `install` (install or update), 2 `play`, 3 `diag` (report only), 4 `unlock`, 5 `optimize` (latency 1
+ shaders). The mode can be passed as the launcher's first argument.

Install flow (`ws_setup.ps1` main): Probe-System -> Show-Prereqs (one list of what is missing, one confirmation;
then installs without asking: `$Script:AutoInstall`) -> Ensure-Git -> Find-Repo (kit folder inside a WindowSmash
checkout, else `repo.txt`, else asks a folder - default `<local disk with most free space>:\Jeux\WindowSmash`,
refuses OneDrive, non-empty folders, less than 35 GB - and `git clone https://github.com/SNO2207/WindowSmash.git`)
-> disk check -> Ensure-Revision (git: fetch `main`, `checkout --detach <pin>`, refuses tracked changes except
`online_server.txt`; no git: compare normalized SHA-256 of 4 files, else download the commit's zip and robocopy) ->
Ensure-Python (py -3.14 / known paths / PATH; winget `Python.Python.3.14 --scope user`, else python.org 3.14.8,
hash + signature) + venv + pip -> Ensure-VS (vswhere VC.Tools.x86.x64 + Windows SDK `um\x64\d3d11.lib`; else
`vs_BuildTools.exe --passive --wait --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended`, signature
"Microsoft") -> Ensure-LLVM (`<repo>\dump\_setup\llvm-20.1.8`, archive hash) -> Test-Toolchain (compiles and runs a
program using FMA, AVX2, F16C and D3D11CreateDevice: illegal instruction = E21) -> Ask-Inputs (file dialogs; reuse of
`inputs.json`; optional title.keys and DLC folder) -> Check-Inputs (copies keys to `<repo>\keys\`, `ws_setup.py keys`,
`identify --role base`, `identify --role update --expect 13.0.4`) -> Prepare-Base (`plain-nca`, then romfs-cfg) ->
Prepare-Fonts (from the XCI update partition, else a firmware folder: Ryujinx/yuzu/suyu/sudachi/citron/eden
`registered` folders are suggested) -> Ensure-Opus (CMake, VS generator by major version 16/17/18) -> Ensure-SDL3
(zip into `<repo>\deps\SDL3`) -> Build-Game (`ws_setup.py install` with jobs = min(threads, (RAM_GB-4)/1.5); OOM ->
retry with half) -> Set-Latency1 -> optional Precompile-Shaders (jobs = threads - 2) -> Finish (shortcuts, online name,
report, start the game).

Helper (`kit\ws_setup.py`) commands: `probe`, `keys`, `identify`, `plain-nca`, `fonts`, `install` (the 6.1 fix +
OOM/link/disk detection in the build output), `status`, `unlock` (13.0.4 layout added in memory), `shaders` (creates
`<port>\build`, runs shader_aot). Protocol with the PowerShell side: lines `@@JSON {...}`, `@@WARN Wnn text`,
`@@ERROR Enn text` then exit 2 (3 = out of memory, retry with fewer jobs). Every run tees its output to a log.

Report: `WindowSmash-setup-rapport.txt` on the Desktop (steps, warnings, system/tools, version folder status, the
last 80 lines of the failing step's log, the end of the main log); the Windows user name is redacted in paths; no
keys or game data. Logs: `%LOCALAPPDATA%\WindowSmash-setup\logs\<time>\`.

Error codes: E10 not a WindowSmash folder, E11 version/revision (git fetch/checkout, modified files, zip), E12 Git
install, E13 git clone, E15 tools refused, E20 not 64-bit Windows, E21 CPU without AVX2/FMA/F16C, E22 disk space, E23
OneDrive, E30 Python install, E31 venv/pip/pycryptodomex, E32 Build Tools install (1602/5007 = UAC refused), E33
Build Tools incomplete (MSVC or SDK missing), E34 LLVM download/extract, E35 test program fails, E40 file not chosen,
E41 prod.keys (missing, title.keys given instead, header_key, generation too old), E42 base game wrong (an update, not
SSBU), E43 update wrong, E44 ticket personalized or missing (redump with "remove console specific data" or give
title.keys), E45 fonts not found, E50 plain NCA, E51 update step, E52 nro step, E53 other preparation step, E59
internal Python error, E60 compile failed, E61 link failed, E62 ssbu.exe missing after build (antivirus?), E70 game
does not start, E80 unlock, E85 shaders, E99 unexpected PowerShell error.
Warnings: W13 folder choice, W21 Windows says no AVX2, W22 disk, W23 accents in path / OneDrive, W24 low RAM, W32
reboot asked by Build Tools, W42 base not 1.0.0, W43 update not 13.0.4 (netplay mismatch), W45 fonts, W60 low free
memory, W61 OOM retry, W70 D3D11 hardware unavailable, W71 shortcut, W80 Opus not built, W81 SDL3 not installed, W85
shaders not precompiled, W99 test mode.

Pinned versions (`ws_setup.ps1` top):
- WindowSmash `adfb15452825e18ac908ab229707f5b2aadde5fb` (branch fetched: `main`); file hashes (LF-normalized
  SHA-256): install_version.py `6bea66e8...e52da`, update.py `5d6cbe0f...baf03`, recomp.py `606a625b...15a0`,
  nca.py `4736eb17...27a40` (full values in the script).
- LLVM 20.1.8 `f229769f11d6a6edc8ada599c0cda964b7dee6ab1a08c6cf9dd7f513e85b107f`.
- opus 1.5.2 `65c1d2f78b9f2fb20082c38cbe47c951ad5839345876e46941612ee87f9a7ce1` (matches xiph's SHA256SUMS).
- Python 3.14.8 installer `759be887b96e736a3ca886daf8d575f18fcae1a09efab6902f42d59e8999f8ef` (signed PSF).
- Git 2.56.0.2 installer `52188f917b378f00c70ec136bcf090005f30d44fbc4eba0bce759cc6592d60f6` (matches the release
  notes; signed Johannes Schindelin).
- SDL3 3.4.18 VC zip `78d84602ae616cfe26b33a73b7d3b9b6b56e8a6650e53d92c9c6ca938f747acd`.
- Visual Studio Build Tools: `https://aka.ms/vs/17/release/vs_BuildTools.exe` (not pinned; signature checked).

Test hooks (environment): `WS_NO_BUILD=1` (install everything but skip the compile), `WS_STOP_AFTER=repo|revision|
tools`, `WS_NO_NOTEPAD=1`, `WS_REPORT_DIR=<dir>`; bootstrap: `WSL_NO_RELAUNCH=1`, `WSL_REPO_URL=<git url>`.
The kit reads answers from stdin when it is redirected (`printf 'o\r\n...' | cmd //c "...bat" install`).

## 12. Kit history and tests

- 1.0 (2026-10-18): one self-extracting `.bat` (`launcher.bat` header + `ws_setup.ps1` + `ws_setup.py` between
  `#@@BEGIN/#@@END` markers, assembled by `build_kit.py`), pinned 5682805. Two full runs on a fresh clone with
  `WS_NO_BUILD` found the bugs of 6.9; the second run ended "OK" (update verified 1,074,276/1,074,276).
- 1.1: complete installer (prerequisites list, Git install, install folder + git clone, `repo.txt`, Start menu
  shortcut). Tested: fresh clone, rerun detection, play mode without a build.
- 1.2: pin adfb154 (online lobby), SDL3, online name asked before starting. Tested: an install on 5682805 updated
  to adfb154 in place.
- 1.3: latency 1 and shader precompilation after the build, menu option 5, more shader workers. Tested on the owner's
  installation (option 5 end to end, "OK"); the latency setter on three cases (3 -> 1, already 1, no file).
- 2.0 (2026-10-19, this repository): the self-updating bootstrap; the kit runs from the clone; shortcuts go through
  the launcher; play mode offers the update when the pinned commit changed.
- Not tested on a clean PC: the installation of Git, Python and Build Tools (all present on the owner's PC), an NSP
  base with fonts from a firmware folder, a full compile through the kit (the same command as the owner's build).

## 13. Procedures

- Rebuild the owner's installation (from `D:\WindowSmash`, game closed):
  `set SSBU_CLANG=D:\ssbu-recomp-data\deps\llvm-20.1.8\bin\clang-cl.exe`,
  `set SSBU_OPUS_LIBS=D:\ssbu-recomp-data\deps\opus\lib\opus.lib`, then
  `.venv\Scripts\python.exe <launcher>\kit\ws_setup.py --repo . install --tree v13.0.4 --update
  "D:\ssbu-recomp-data\packages\Super Smash Bros Ultimate 13_0_4.nsp" --keys C:\Users\PC\.switch --jobs 8`
  (or simply the launcher's option 1). Use fewer jobs if the other session's game is running.
- Precompile shaders by hand: same environment, `.venv\Scripts\python.exe tools\shader_aot.py --tree v13.0.4 --jobs 14`
  (create `D:\WindowSmash\build` first).
- **Bump the pinned WindowSmash commit** (everyone updates through the launcher):
  1. `git fetch` upstream; `git diff <old> <new> -- tools/update.py tools/install_version.py tools/unlock_all.py
     tools/nca.py tools/cc.py tools/recomp.py tools/shader_aot.py` - the 13.0.4 fixes depend on `update.Patch`
     internals (`sec.fs_header`, `vread`, `blocks`, `l6`), `update.Builder.base_section/base_read`,
     `install_version.subprocess`, `unlock_all.LAYOUTS/SAVE`, shader_aot's `<port>\build` working directory.
  2. Check new build requirements in `docs/BUILDING.md` (new deps like SDL3 became optional deps once).
  3. Rebuild the owner's tree and play-test; compare `runtime\net.h` NET_PROTOCOL (everyone must match).
  4. In `kit\ws_setup.ps1`: `$WS_COMMIT`, `$WS_BRANCH`, `$WS_FILES` (LF-normalized SHA-256:
     `git show <commit>:<path> | tr -d '\r' | sha256sum`), `$KitVersion`.
  5. Commit and push: the friends' launchers pull it at their next start, and play mode offers the rebuild.
- Change the bootstrap: edit `WindowSmash Launcher.bat` (CRLF, ASCII header, the one-block invariant of section 10;
  the boot.ps1 part may contain UTF-8); every launcher copies the repository version over the user's file at its
  next start. Test it before pushing: a broken bootstrap may be unable to fetch its own fix, and then every friend
  must download the file again by hand. Parse check: extract the `#@@BEGIN boot.ps1` part and run it through
  `[Management.Automation.Language.Parser]::ParseInput`.
- Test without touching the owner's install: a fresh clone elsewhere plus `WS_NO_BUILD=1`, `WS_NO_NOTEPAD=1`,
  `WS_REPORT_DIR=<scratch>`, stdin answers; restore `%LOCALAPPDATA%\WindowSmash-setup\repo.txt` afterwards (it must
  point to `D:\WindowSmash`).

## 14. Open items, gaps, ideas

- Upstream issues worth reporting to SNO2207/WindowSmash: 13.0.4 update hash table read (6.1); shader_aot needs
  `<port>\build` (6.8); unlock layouts for 13.0.4 (same as 13.0.5, verified); `Prepare Shaders.bat` uses the system
  Python.
- libvpx (movies) not built: VP9 via `SSBU_VPX_DIR` (include + `lib\Win64\Release\libvpx.lib`); libvpx needs its own
  configure/make or vcpkg.
- Hardware: XMP off, games on a USB HDD (see 2).
- The friends' installs: results unknown so far; their reports (`WindowSmash-setup-rapport.txt`) give the step, the
  error code and the log tail.
- A DLC folder is supported (`--dlc`, aoc.cfg) but was not tested; for netplay everyone should have the same DLC.

## 15. The earlier project: ssbu-recomp (context only)

Before WindowSmash, another recompilation (https://github.com/Denkishi/ssbu-recomp, Vulkan renderer, 13.0.4, no
online) was built for the owner from `D:\ssbu-recomp` with data in `D:\ssbu-recomp-data` (dump from the same XCI +
NSP with `make_dump.py`, build ~1h27 with LLVM 9, `--jobs 12`, `RECOMP_TIME_LIMIT=420`, launcher `SSBU Recomp.bat` on
the Desktop doing git pull + incremental rebuild + start). Its first run spends ~7 minutes indexing data.arc and
translating shaders before the first frames. It is unrelated to this repository; WindowSmash replaced it for online
play.
