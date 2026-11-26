#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Mods sync between two OpenSmash Ultimate folders (Nilsix tools, github.com/Nilsix/WindowSmashLauncher).

    mods_sync.py make  --tree <game folder> --out <folder>     your mods -> "Synchro mods - <you>.bat", to send
    mods_sync.py sync  --tree <game folder> --manifest <json>  (run by that .bat) this folder's mods made the sender's
    mods_sync.py check --tree <game folder> --manifest <json>  only say whether they are the same

Online, two games are the same when the mods they report are (runtime/net_relay.c mod_set_make: for each mod of
dump/mods/applied.json, its folder's name and a hash of its files' paths and sizes, plus ARCropolis' code patches when
they are on). The .bat carries this file and a manifest: every mod of the sender's mods/mods.json (name, switch,
GameBanana file, that hash), their order, the code patches' switch, the standard plugins and the set expected online.
sync takes each mod from the friend's own folders (same files, renamed when needed) or from GameBanana (the sender's
file: "update" means the sender's version), turns on what the sender has on and off everything else (the friend's
own mods stay, turned off), applies as the Mods page does, then compares the set with the sender's.
Runs with the OpenSmash folder's Python and its tools (tools/mods.py).
"""
import argparse
import collections
import datetime
import hashlib
import json
import os
import re
import shutil
import sys

FORMAT = "opensmash-mod-list"   # (tools/mods.py LIST_FORMAT: the Mods page's "import a list" reads these "mods" too)
SYNC = 1
META = ("title", "gamebanana", "file_id", "file", "md5", "author", "image", "category")
CODE = "ARCropolis code patches"                                  # (runtime/mod_diff.h MOD_CODE_PATCHES)
CODE_SEED = b"WindowSmash: ARCropolis code patches, 13.0.5\0"     # (net_relay.c hashes 45 bytes: the text and its NUL)
FNV0, PRIME, MASK = 0xCBF29CE484222325, 0x100000001B3, (1 << 64) - 1
NATIVE = (".dll", ".so", ".dylib")
OFF_PLUGINS = "off (mods sync)"   # (skyline/plugins/<this>: a plugin the sender doesn't have; the game reads only *.nro at the top)
MARK = "#@@"                      # (the .bat's parts; built here so no line of this file starts with it)
FR = False


def L(en, fr):
    return fr if FR else en


def say(text=""):
    print(text, flush=True)


def step(label, done=-1, total=0):
    """make's step for OpenSmash.exe's NILSIX TOOLS page (LauncherForm.Nilsix.cs NilsixLine), which shows it in the
    bar at the bottom as OpenSmash's own jobs: "PROGRESS <0..1, or -1 while not known> <label>", not in the log"""
    print(f"PROGRESS {done / total if total else -1:.3f} {label}", flush=True)


# ---- what the game reports online ---------------------------------------------------------------------------------
def fnv64(h, data):
    for b in data:
        h = ((h ^ b) * PRIME) & MASK
    return h


def fold(h):
    return (h ^ (h >> 32)) & 0xFFFFFFFF


def tree_hash(folder):
    """runtime/net_relay.c mod_tree_hash, folded as mod_set_make does: (hash, files). The sum over the folder's files
    of FNV-1a 64 of their path (lower case, '/' between) then of their size (8 bytes, little-endian)."""
    total, files = 0, 0
    stack = [(folder, "", 0)]
    while stack:
        d, rel, depth = stack.pop()
        try:
            entries = list(os.scandir(d))
        except OSError:
            continue
        for e in entries:
            r = rel + "/" + e.name if rel else e.name
            try:
                if e.is_dir():
                    if depth < 16:
                        stack.append((e.path, r, depth + 1))
                    continue
                size = e.stat().st_size
            except OSError:
                continue
            low = e.name.lower()
            if (e.name.startswith(".") or low == "info.toml" or low.startswith(("preview.", "readme."))
                    or any(len(low) > len(x) and low.endswith(x) for x in NATIVE)):
                continue
            total += fnv64(fnv64(FNV0, r.encode("utf-8").lower()), size.to_bytes(8, "little"))
            files += 1
    return fold(total & MASK), files


def online_set(tree, names, code_on, hashes=None):
    """[(name, hash)] sorted: what the game reports for these applied mods (mod_set_make, before its 32-entry cut)"""
    out = [(CODE, fold(fnv64(FNV0, CODE_SEED)))] if code_on else []
    for n in names:
        out.append((n, hashes[n] if hashes and n in hashes else tree_hash(os.path.join(tree.mods, n))[0]))
    return sorted(out, key=lambda e: (e[0].lower(), e[0], e[1]))


def fingerprint(entries):
    h = FNV0
    for name, x in entries:
        h = fnv64(fnv64(h, name.encode("utf-8") + b"\0"), x.to_bytes(4, "big"))
    x = fold(h)
    return f"{x >> 16:04X}-{x & 0xFFFF:04X}"


# ---- the folder -----------------------------------------------------------------------------------------------------
def tools(root):
    sys.path.insert(0, os.path.join(root, "tools"))
    import mods
    import os_mods
    import std_plugins
    return mods, os_mods, std_plugins


def first_line(path):
    try:
        with open(path, encoding="utf-8-sig") as f:
            return (f.readline() or "").strip()
    except OSError:
        return ""


def player(root):
    return first_line(os.path.join(root, "config", "online_name.txt")) or first_line(os.path.join(root, "online_name.txt"))


def version(root):
    return (first_line(os.path.join(root, "tools", "source_version.txt")).split() or [""])[0].lower()


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def plugins(root):
    """{file: sha256} of the standard plugins (skyline/plugins/*.nro: tools/skyline.py standard)"""
    folder = os.path.join(root, "skyline", "plugins")
    out = {}
    if os.path.isdir(folder):
        for n in sorted(os.listdir(folder)):
            if n.lower().endswith(".nro") and os.path.isfile(os.path.join(folder, n)):
                out[n] = sha256(os.path.join(folder, n))
    return out


def real_conflicts(mods, tree):
    """the files two different turned-on mods change (mods.conflicts also counts a mod the order lists twice)"""
    return [c for c in mods.conflicts(tree) if len(set(c["mods"])) > 1]


def free_name(base, taken):
    name, k = base, 2
    while name.lower() in taken:
        name, k = f"{base} {k}", k + 1
    return name


# ---- make: the sender's side ------------------------------------------------------------------------------------
def make(root, out):
    mods, os_mods, _std = tools(root)
    tree = mods.Tree(root)
    state = tree.load()
    hashes, listed = {}, []
    for i, n in enumerate(state["order"]):
        step(L("READING YOUR MODS", "LECTURE DE TES MODS"), i, len(state["order"]))
        if n not in hashes:
            hashes[n] = tree_hash(os.path.join(tree.mods, n))[0]
        m = state["mods"][n]
        e = {"name": n, "enabled": bool(m.get("enabled"))}
        e.update({k: m[k] for k in META if m.get(k) not in (None, "")})
        e["hash"] = hashes[n]
        listed.append(e)
    on = [n for n in state["order"] if state["mods"][n].get("enabled")]
    code = state.get("code_patches") if isinstance(state.get("code_patches"), bool) else None
    expected = online_set(tree, on, os_mods.code_patches_on(tree, state), hashes)
    who = player(root) or "?"
    unique = {e["name"]: e for e in listed}
    say(L(f"{len(unique)} mods ({len(set(on))} on), online set {fingerprint(expected)}",
          f"{len(unique)} mods ({len(set(on))} activés), empreinte en ligne {fingerprint(expected)}"))
    if ((tree.applied() or {}).get("mods") or []) != on:
        say(L("Note: your mods changed since the game last applied them: start the game once, then make this file again.",
              "Note : tes mods ont changé depuis que le jeu les a appliqués : lance le jeu une fois, puis refais ce fichier."))
    manual = [n for n, e in unique.items() if not (e.get("gamebanana") and e.get("file_id"))]
    if manual:
        say(L(f"Not from GameBanana (your friend needs these folders from you, mods\\<name>): {', '.join(manual)}",
              f"Pas de GameBanana (ces dossiers sont à envoyer toi-même, mods\\<nom>) :{', '.join(manual)}"))
    step(L("LOOKING FOR CONFLICTS", "RECHERCHE DES CONFLITS"))
    found = real_conflicts(mods, tree)
    say(L(f"Conflicts: {len(found)} file(s) changed by more than one turned-on mod (the later one in the order wins; "
          "your friend gets the same order)",
          f"Conflits : {len(found)} fichier(s) modifiés par plusieurs mods activés (le dernier dans l'ordre gagne ; "
          "le fichier donne le même ordre)"))
    for c in found[:5]:
        say(f"  {c['path']}: {' > '.join(c['mods'])}")
    say(L("Checking GameBanana for newer files...", "Recherche de versions plus récentes sur GameBanana..."))
    label = L("CHECKING GAMEBANANA", "VÉRIFICATION SUR GAMEBANANA")
    step(label)
    get, asked = getattr(mods, "gamebanana_get", None), [0]
    total = sum(1 for n in state["order"] if state["mods"][n].get("gamebanana") and state["mods"][n].get("file_id"))

    def counted(*a, **k):   # (mods.updates asks GameBanana once per such mod of the order: the bar follows it)
        step(label, asked[0], total)
        asked[0] += 1
        return get(*a, **k)
    if get:
        mods.gamebanana_get = counted
    try:
        ups = list({(u.get("title"), u.get("installed"), u.get("newest")): u for u in mods.updates(tree)}.values())   # (a pack's mods: one line)
        if ups:
            say(L(f"{len(ups)} mod(s) have a newer file on GameBanana; your friend gets YOUR version:",
                  f"{len(ups)} mod(s) ont une version plus récente sur GameBanana ; le fichier donne TA version :"))
            for u in ups:
                say(f"  {u.get('title') or u['name']}: {u.get('installed', '')} -> {u.get('newest', '')}")
            say(L("(the newest for both of you: update them in OpenSmash > Mods, then make this file again)",
                  "(la plus récente pour vous deux : mets-les à jour dans OpenSmash > Mods, puis refais ce fichier)"))
        else:
            say(L("Every GameBanana mod is at its newest file.", "Tous les mods GameBanana sont à leur dernière version."))
    except Exception as ex:   # (no internet, GameBanana down: only a note)
        say(L(f"GameBanana could not be asked ({ex}).", f"GameBanana n'a pas pu être interrogé ({ex})."))
    finally:
        if get:
            mods.gamebanana_get = get
    step(L("WRITING THE FILE", "ÉCRITURE DU FICHIER"), 1, 1)
    manifest = {"format": FORMAT, "version": 1, "sync": SYNC, "from": who,
                "made": datetime.datetime.now().strftime("%Y-%m-%d %H:%M"), "opensmash": version(root),
                "code_patches": code, "mods": listed, "set": [[n, h] for n, h in expected],
                "fingerprint": fingerprint(expected), "plugins": plugins(root), "conflicts": len(found)}
    safe = re.sub(r"[^A-Za-z0-9 _.-]+", "_", who).strip(" ._") or "OpenSmash"
    path = out if out.lower().endswith(".bat") else os.path.join(out, L(f"Mods sync - {safe}.bat", f"Synchro mods - {safe}.bat"))
    with open(path, "w", encoding="utf-8", newline="\r\n") as f:
        f.write(bat_text(manifest, safe))
    say(L(f"Written: {path}", f"Fichier créé : {path}"))
    say(L(f"Send it to your friend: they double-click it (OpenSmash closed). At the end it must say SYNC OK and {manifest['fingerprint']}.",
          f"Envoie-le à la personne qui joue avec toi : OpenSmash fermé, elle double-clique dessus. À la fin, elle doit voir SYNCHRO OK et {manifest['fingerprint']}."))
    print("RESULT " + json.dumps({"ok": True, "file": path, "fingerprint": manifest["fingerprint"]}), flush=True)
    return 0


BAT_HEAD = r"""@echo off
rem Mods sync for OpenSmash Ultimate from @WHO@ (@MADE@). Double-click it with OpenSmash closed: your OpenSmash
rem gets the same mods, turned on and off the same way, at the same versions. Nilsix tools (OpenSmash Ultimate Launcher).
setlocal
set "MS_SELF=%~f0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; try { $t=[IO.File]::ReadAllText($env:MS_SELF); $m=[regex]::Match($t,'(?s)\r?\n@MARK@BEGIN sync\.ps1\r?\n(.*?)\r?\n@MARK@END sync\.ps1'); if(-not $m.Success){ throw 'incomplete file' }; $f=Join-Path $env:TEMP ('mods-sync-'+$PID+'.ps1'); [IO.File]::WriteAllText($f,$m.Groups[1].Value,(New-Object Text.UTF8Encoding $true)); & $f -Self $env:MS_SELF; $rc=$LASTEXITCODE; Remove-Item -LiteralPath $f -ErrorAction SilentlyContinue; exit $rc } catch { Write-Host ('Mods sync error / erreur de la synchro: '+$_.Exception.Message) -ForegroundColor Red; exit 2 }"
set "RC=%ERRORLEVEL%"
echo.
pause
exit /b %RC%
"""

SYNC_PS1 = r"""param([string]$Self = '')
$ErrorActionPreference = 'Stop'
$Fr = (Get-UICulture).TwoLetterISOLanguageName -eq 'fr'
function L([string]$En, [string]$FrText) { if ($Fr) { $FrText } else { $En } }
function Read-First([string]$File) { try { return ([IO.File]::ReadAllLines($File) | Select-Object -First 1).Trim().Trim('"') } catch { return '' } }
function Test-Game([string]$Dir) { try { return [bool]($Dir -and (Test-Path -LiteralPath (Join-Path $Dir 'tools\mods.py'))) } catch { return $false } }
function Get-Python([string]$Dir) {
    # (OpenSmash.Launcher ModManagerProcess.FindPython: deps\venv once its packages are in, else deps\python)
    $venv = Join-Path $Dir 'deps\venv\Scripts\python.exe'
    if ((Test-Path -LiteralPath $venv) -and (Test-Path -LiteralPath (Join-Path $Dir 'deps\venv\.opensmash-ready'))) { return $venv }
    $own = Join-Path $Dir 'deps\python\python.exe'
    if (Test-Path -LiteralPath $own) { return $own }
    return ''
}
$text = [IO.File]::ReadAllText($Self)
function Get-Part([string]$Name) {
    $m = [regex]::Match($text, '(?s)\r?\n@MARK@BEGIN ' + [regex]::Escape($Name) + '\r?\n(.*?)\r?\n@MARK@END ' + [regex]::Escape($Name))
    if (-not $m.Success) { throw "incomplete file ($Name)" }
    return $m.Groups[1].Value
}

# the OpenSmash folder: the one OpenSmash.exe remembers, the kit's, this file's, a desktop shortcut's, the default one
$cands = @((Read-First (Join-Path $env:LOCALAPPDATA 'OpenSmash\project_folder.txt')), (Read-First (Join-Path $env:LOCALAPPDATA 'WindowSmash-setup\repo.txt')), (Split-Path -Parent $Self))
try {
    $sh = New-Object -ComObject WScript.Shell
    foreach ($d in @([Environment]::GetFolderPath('Desktop'), [Environment]::GetFolderPath('CommonDesktopDirectory'))) {
        foreach ($lnk in @(Get-ChildItem -LiteralPath $d -Filter '*.lnk' -ErrorAction SilentlyContinue)) {
            $target = $sh.CreateShortcut($lnk.FullName).TargetPath
            if ($target -and [IO.Path]::GetFileName($target) -ieq 'OpenSmash.exe') { $cands += Split-Path -Parent $target }
        }
    }
} catch { }
$cands += Join-Path $env:USERPROFILE 'Games\OpenSmash-Ultimate'
$Game = $cands | Where-Object { Test-Game $_ } | Select-Object -First 1
if (-not $Game) {
    Add-Type -AssemblyName System.Windows.Forms
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = L 'Choose your OpenSmash folder (the one with OpenSmash.exe)' 'Choisis ton dossier OpenSmash (celui qui contient OpenSmash.exe)'
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK -and (Test-Game $dlg.SelectedPath)) { $Game = $dlg.SelectedPath }
}
if (-not $Game) {
    Write-Host (L 'No OpenSmash folder found: install OpenSmash first (github.com/OpenSmash-Ultimate/OpenSmash-Ultimate).' "Aucun dossier OpenSmash trouvé : installe d'abord OpenSmash (github.com/OpenSmash-Ultimate/OpenSmash-Ultimate).") -ForegroundColor Red
    exit 1
}
$Game = $Game.TrimEnd('\')
Write-Host (L "OpenSmash folder: $Game" "Dossier OpenSmash : $Game")

# nothing of that folder running: the game, OpenSmash, or one of its jobs (a build, shaders)
$running = @(Get-Process -Name ssbu, OpenSmash -ErrorAction SilentlyContinue | Where-Object { $_.Path -and $_.Path.StartsWith($Game + '\', [StringComparison]::OrdinalIgnoreCase) })
$jobs = @(Get-CimInstance Win32_Process -Filter "Name='python.exe' OR Name='pythonw.exe'" -ErrorAction SilentlyContinue | Where-Object { ("$($_.ExecutablePath) $($_.CommandLine)").IndexOf($Game, [StringComparison]::OrdinalIgnoreCase) -ge 0 })
if ($running.Count -or $jobs.Count) {
    Write-Host (L 'Close OpenSmash and the game (and wait for a build to finish), then run this file again.' 'Ferme OpenSmash et le jeu (et attends la fin d''une compilation), puis relance ce fichier.') -ForegroundColor Yellow
    exit 1
}
$py = Get-Python $Game
if (-not $py) {
    Write-Host (L 'This OpenSmash has no Python yet: open OpenSmash once, then run this file again.' "Cet OpenSmash n'a pas encore son Python : ouvre OpenSmash une fois, puis relance ce fichier.") -ForegroundColor Red
    exit 1
}
$dir = Join-Path $env:TEMP ('mods-sync-' + $PID)
if (Test-Path -LiteralPath $dir) { Remove-Item -LiteralPath $dir -Recurse -Force }
New-Item -ItemType Directory -Force -Path $dir | Out-Null
$utf8 = New-Object Text.UTF8Encoding $false
[IO.File]::WriteAllText((Join-Path $dir 'mods_sync.py'), (Get-Part 'mods_sync.py'), $utf8)
[IO.File]::WriteAllText((Join-Path $dir 'manifest.json'), (Get-Part 'manifest.json'), $utf8)
$lang = if ($Fr) { 'fr' } else { 'en' }
& $py -I -X utf8 (Join-Path $dir 'mods_sync.py') sync --tree $Game --manifest (Join-Path $dir 'manifest.json') --lang $lang
$rc = $LASTEXITCODE
Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
$exe = Join-Path $Game 'OpenSmash.exe'
if ($rc -eq 0 -and (Test-Path -LiteralPath $exe)) { Start-Process -FilePath $exe -WorkingDirectory $Game }
exit $rc
"""


def bat_text(manifest, who):
    with open(os.path.abspath(__file__), encoding="utf-8") as f:
        me = f.read()
    head = BAT_HEAD.replace("@WHO@", who).replace("@MADE@", manifest["made"]).replace("@MARK@", MARK)
    assert head.isascii()   # (cmd reads only this part, in the console's code page)
    parts = [head]
    for name, body in (("sync.ps1", SYNC_PS1.replace("@MARK@", MARK)), ("mods_sync.py", me),
                       ("manifest.json", json.dumps(manifest, indent=1, ensure_ascii=True))):
        parts.append(f"{MARK}BEGIN {name}\n{body.rstrip()}\n{MARK}END {name}\n")
    return "".join(parts).replace("\r\n", "\n")   # (written with newline="\r\n": CRLF everywhere)


# ---- sync: the friend's side ------------------------------------------------------------------------------------
def progress():
    last = [-1]

    def p(done, total):
        pct = done * 100 // total if total else -1
        if pct >= 0 and pct // 25 > last[0]:
            last[0] = pct // 25
            say(f"    {pct}%")
    return p


def entry_of(e):
    out = {"enabled": bool(e.get("enabled"))}
    out.update({k: e[k] for k in META if k in e})
    return out


def sync(root, man):
    mods, os_mods, std_plugins = tools(root)
    tree = mods.Tree(root)
    owner = man.get("from") or "?"
    say(L(f"Mods of {owner} ({man.get('made', '')}): {man.get('fingerprint', '')}",
          f"Mods de {owner} ({man.get('made', '')}) : {man.get('fingerprint', '')}"))
    if man.get("opensmash") and version(root) != man["opensmash"]:
        say(L(f"Warning: your OpenSmash is not the version {owner} has ({version(root)[:7] or '?'} here, "
              f"{man['opensmash'][:7]} there). Update both to the latest one (OpenSmash offers it when it starts).",
              f"Attention : ton OpenSmash n'est pas à la même version que celui de {owner} ({version(root)[:7] or '?'} ici, "
              f"{man['opensmash'][:7]} chez {owner}). Mettez-vous tous les deux à jour (OpenSmash le propose au démarrage)."))
    order, want = [], {}
    for e in man.get("mods") or []:
        if isinstance(e, dict) and e.get("name") and isinstance(e.get("hash"), int):
            order.append(e["name"])
            want.setdefault(e["name"], e)
    os.makedirs(tree.mods, exist_ok=True)
    before = tree.load()
    cache = {}

    def h(n):
        if n not in cache:
            cache[n] = tree_hash(os.path.join(tree.mods, n))[0]
        return cache[n]

    # 1. each of the sender's mods from a folder here with the same files: its own name first, else any other
    plan, used = {}, set()
    for n, e in want.items():
        if n in before["mods"] and h(n) == e["hash"]:
            plan[n] = n
            used.add(n)
    for n, e in want.items():
        if n not in plan:
            src = next((f for f in before["order"] if f not in used and h(f) == e["hash"]), None)
            if src:
                plan[n] = src
                used.add(src)
    # 2. the others from GameBanana, the sender's own file, into dump/mods_sync first
    stage = os.path.join(tree.root, "dump", "mods_sync")
    shutil.rmtree(stage, ignore_errors=True)
    groups, problems, staged = {}, [], {}
    for n, e in want.items():
        if n in plan:
            continue
        if e.get("gamebanana") and e.get("file_id"):
            groups.setdefault((str(e["gamebanana"]), str(e["file_id"])), []).append(n)
        else:
            problems.append(L(f"{n}: not from GameBanana: copy the folder mods\\{n} from {owner}'s PC into yours",
                              f"{n} : pas sur GameBanana : copie le dossier mods\\{n} du PC de {owner} dans le tien"))
    say(L(f"{len(plan)} of {len(want)} mods already here; {len(groups)} download(s) from GameBanana",
          f"{len(plan)} mods sur {len(want)} déjà là ; {len(groups)} téléchargement(s) depuis GameBanana"))
    for i, ((gb, fid), names) in enumerate(groups.items(), 1):
        e = want[names[0]]
        say(f"  [{i}/{len(groups)}] {e.get('title') or names[0]} ({e.get('file') or fid})")
        st = mods.Tree(os.path.join(stage, f"{gb}_{fid}"))
        try:
            got = mods.gamebanana_install(st, gb, fid, progress())
        except Exception as ex:   # (mods.Error, the network, the archive: that mod only)
            problems += [L(f"{n}: the download failed ({ex}): run this file again", f"{n} : le téléchargement a échoué ({ex}) : relance ce fichier")
                         for n in names]
            continue
        pool = collections.defaultdict(list)
        for g in got:
            pool[tree_hash(os.path.join(st.mods, g))[0]].append(os.path.join(st.mods, g))
        for n in names:
            if pool.get(want[n]["hash"]):
                staged[n] = pool[want[n]["hash"]].pop(0)
            else:
                problems.append(L(f"{n}: {owner}'s folder is not GameBanana's file (changed by hand?): copy mods\\{n} from {owner}'s PC",
                                  f"{n} : le dossier de {owner} n'est pas le fichier de GameBanana (modifié à la main ?) : copie mods\\{n} depuis son PC"))
    # 3. the folders to their names, in two steps (a folder can hold a name another one goes to); a folder of this
    # PC's own that has a name the sender's mod needs is kept under another name, turned off
    moves = [(f, n) for n, f in plan.items() if f != n]
    sources = {f for f, _n in moves}
    present = {x.lower(): x for x in os.listdir(tree.mods)}
    taken = set(present) | {n.lower() for n in want}
    olds = {}
    for n in list(plan) + list(staged):
        holder = present.get(n.lower())
        if holder is None or holder == plan.get(n) or holder in sources:
            continue
        new = free_name(holder + L(" (old)", " (ancien)"), taken)
        taken.add(new.lower())
        moves.append((holder, new))
        olds[new] = holder
    done = []   # shortcut: a sync killed between the two steps leaves mods\.mods-sync-* (hidden from OpenSmash), to rename back by hand
    try:
        temps = []
        for i, (src, dst) in enumerate(moves):
            tmp = os.path.join(tree.mods, f".mods-sync-{os.getpid()}-{i}")
            os.rename(os.path.join(tree.mods, src), tmp)
            done.append((os.path.join(tree.mods, src), tmp))
            temps.append((tmp, os.path.join(tree.mods, dst)))
        for tmp, dst in temps:
            os.rename(tmp, dst)
            done.append((tmp, dst))
        for n, path in staged.items():
            shutil.move(path, os.path.join(tree.mods, n))
            done.append((path, os.path.join(tree.mods, n)))
    except OSError as ex:
        for a, b in reversed(done):   # (back as they were: nothing half moved)
            try:
                shutil.move(b, a)
            except OSError:
                pass
        shutil.rmtree(stage, ignore_errors=True)
        raise mods.Error(L(f"a mod folder could not be moved ({ex}): close every window open in the mods folder, then run this file again",
                           f"un dossier de mod n'a pas pu être déplacé ({ex}) : ferme les fenêtres ouvertes dans le dossier mods, puis relance ce fichier"))
    shutil.rmtree(stage, ignore_errors=True)
    for old, holder in olds.items():
        say(L(f"  your own {holder} (other files than {owner}'s) is kept as {old}, turned off",
              f"  ton propre {holder} (pas les mêmes fichiers que celui de {owner}) est gardé sous le nom {old}, désactivé"))
    # 4. the switches and the order: the sender's, then this PC's own mods, turned off
    filled = set(plan) | set(staged)
    state = tree.load()
    for n in state["mods"]:
        if n in filled:
            state["mods"][n] = entry_of(want[n])
        else:
            if n in olds:
                state["mods"][n] = dict(before["mods"].get(olds[n], {}))
            if state["mods"][n].get("enabled") and n not in olds:
                say(L(f"  {n}: {owner} doesn't have it: turned off (kept)", f"  {n} : {owner} ne l'a pas : désactivé (gardé)"))
            state["mods"][n]["enabled"] = False
    state["order"] = [n for n in order if n in filled] + [n for n in state["order"] if n not in filled]
    if isinstance(man.get("code_patches"), bool):
        state["code_patches"] = man["code_patches"]
    else:
        state.pop("code_patches", None)
    tree.save(state)   # (every folder is in mods.json now: OpenSmash won't ask to turn one on, LauncherForm ScanForNewMods)
    # 5. the standard plugins: one the sender doesn't have is set aside; a missing or different one is fetched again
    want_p = {k.lower(): v for k, v in (man.get("plugins") or {}).items()}
    folder = os.path.join(root, "skyline", "plugins")
    for n in plugins(root):
        if n.lower() not in want_p:
            os.makedirs(os.path.join(folder, OFF_PLUGINS), exist_ok=True)
            os.replace(os.path.join(folder, n), os.path.join(folder, OFF_PLUGINS, n))
            say(L(f"  plugin {n}: {owner} doesn't have it: moved to skyline\\plugins\\{OFF_PLUGINS}",
                  f"  plugin {n} : {owner} ne l'a pas : déplacé dans skyline\\plugins\\{OFF_PLUGINS}"))
    have_p = {k.lower(): v for k, v in plugins(root).items()}
    for n, sha in (man.get("plugins") or {}).items():
        if have_p.get(n.lower()) != sha and n in std_plugins.PLUGINS:
            try:
                std_plugins.fetch(root, n, lambda t: say("  " + str(t)))
            except (Exception, SystemExit) as ex:   # (fetch says a download that isn't the release with SystemExit)
                say(L(f"  plugin {n}: not downloaded ({ex})", f"  plugin {n} : pas téléchargé ({ex})"))
    # 6. applied as the Mods page does (tools/os_mods.py apply, without its pick rule: the sender's switches as they are)
    say(L("Applying the mods...", "Application des mods..."))
    mods.apply(tree, lambda t: say("  " + str(t)))
    return report(tree, man, mods, os_mods, problems)


def report(tree, man, mods, os_mods, problems=()):
    """the online set here against the sender's, the plugins and the conflicts; 0 when the same"""
    owner = man.get("from") or "?"
    names = (tree.applied() or {}).get("mods") or []
    mine = online_set(tree, names, os_mods.code_patches_on(tree))
    theirs = [(n, x) for n, x in man.get("set") or []]
    a, b = collections.Counter(mine), collections.Counter(theirs)
    lacking, extra = b - a, a - b
    diff = []
    for n, _x in sorted(set(lacking) | set(extra)):
        if n in {m for m, _ in lacking} and n in {m for m, _ in extra}:
            line = L(f"{n}: not the same files as {owner}'s", f"{n} : pas les mêmes fichiers que chez {owner}")
        elif n in {m for m, _ in lacking}:
            line = L(f"{n}: on at {owner}'s, not here", f"{n} : activé chez {owner}, pas ici")
        else:
            line = L(f"{n}: on here, not at {owner}'s", f"{n} : activé ici, pas chez {owner}")
        if line not in diff:
            diff.append(line)
    mine_p = {k.lower(): v for k, v in plugins(tree.root).items()}
    for n, sha in (man.get("plugins") or {}).items():
        if mine_p.get(n.lower()) != sha:
            diff.append(L(f"plugin {n}: not the same as {owner}'s (update OpenSmash, both of you)",
                          f"plugin {n} : pas le même que chez {owner} (mettez OpenSmash à jour tous les deux)"))
    if not diff and names != [e["name"] for e in man.get("mods") or [] if e.get("enabled")]:
        # (the online check doesn't see it, but the later mod's files win a conflict: another order is another game)
        diff.append(L(f"the mods are not in {owner}'s order (the later one wins a conflict)",
                      f"les mods ne sont pas dans l'ordre de {owner} (le dernier gagne un conflit)"))
    conflicts = len(real_conflicts(mods, tree))
    for p in problems:
        say("  " + p)
    on = len(set(names))
    off = len(tree.load()["mods"]) - on
    if not diff:
        say("")
        say(L(f"SYNC OK: the same mods as {owner} ({on} on, {off} off), online set {fingerprint(mine)}; "
              f"{conflicts} conflict(s), as at {owner}'s.",
              f"SYNCHRO OK : les mêmes mods que {owner} ({on} activés, {off} désactivés), empreinte {fingerprint(mine)} ; "
              f"{conflicts} conflit(s), comme chez {owner}."))
        say(L("In OpenSmash, press Play: the first time, it builds the mods' plugins into the game (a few minutes).",
              "Dans OpenSmash, clique sur Jouer : la première fois, il compile les plugins des mods dans le jeu (quelques minutes)."))
        return 0
    say("")
    say(L(f"NOT IN SYNC with {owner} (online set {fingerprint(mine)} here, {man.get('fingerprint', '?')} there):",
          f"PAS SYNCHRO avec {owner} (empreinte {fingerprint(mine)} ici, {man.get('fingerprint', '?')} chez {owner}) :"))
    for line in diff:
        say("  " + line)
    return 1


def main(argv):
    global FR
    ap = argparse.ArgumentParser(description="OpenSmash mods sync (Nilsix tools)")
    ap.add_argument("command", choices=("make", "sync", "check"))
    ap.add_argument("--tree", required=True)
    ap.add_argument("--out", default="")
    ap.add_argument("--manifest", default="")
    ap.add_argument("--lang", default="")
    a = ap.parse_args(argv[1:])
    FR = (a.lang or first_line(os.path.join(os.environ.get("LOCALAPPDATA", ""), "WindowSmash-setup", "lang.txt"))) == "fr"
    root = os.path.abspath(a.tree)
    if not os.path.exists(os.path.join(root, "tools", "mods.py")):
        say(L(f"{root} is not an OpenSmash folder (no tools\\mods.py).", f"{root} n'est pas un dossier OpenSmash (pas de tools\\mods.py)."))
        return 2
    try:
        if a.command == "make":
            return make(root, a.out or os.path.join(os.path.expanduser("~"), "Desktop"))
        with open(a.manifest, encoding="utf-8-sig") as f:
            man = json.load(f)
        if not isinstance(man, dict) or man.get("format") != FORMAT or man.get("sync") != SYNC:
            say(L("This is not a mods sync file of this version.", "Ce n'est pas un fichier de synchro de cette version."))
            return 2
        if a.command == "sync":
            return sync(root, man)
        mods, os_mods, _std = tools(root)
        return report(mods.Tree(root), man, mods, os_mods)
    except Exception as ex:   # (mods.Error is the person's to act on; anything else is said the same way)
        say(L(f"Stopped: {ex}", f"Arrêté : {ex}"))
        if a.command == "make":
            print("RESULT " + json.dumps({"ok": False, "error": str(ex)}), flush=True)
        return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
