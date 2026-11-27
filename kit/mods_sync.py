#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Mods sync between two OpenSmash Ultimate folders (Nilsix tools, github.com/Nilsix/WindowSmashLauncher).

    mods_sync.py make  --tree <game folder> --out <folder>     your mods -> "Synchro mods - <you>.bat", to send
    mods_sync.py make  ... --fuse                             a fusion file: "Fusion mods - <you>.bat"
    mods_sync.py sync  --tree <game folder> --manifest <json>  (run by that .bat) this folder's mods made the sender's
                       [--out <folder>]                        (a fusion: the file to send back goes there)
    mods_sync.py check --tree <game folder> --manifest <json>  only say whether they are the same

Online, two games are the same when the mods they report are (runtime/net_relay.c mod_set_make: for each mod of
dump/mods/applied.json, its folder's name and a hash of its files' paths and sizes, plus ARCropolis' code patches when
they are on). The .bat carries this file and a manifest: every mod of the sender's mods/mods.json (name, switch,
GameBanana file, that hash), their order, the code patches' switch, the standard plugins and the set expected online.
sync takes each mod from the friend's own folders (same files, renamed when needed) or from GameBanana (the sender's
file: "update" means the sender's version), turns on what the sender has on and off everything else (the friend's
own mods stay, turned off; its older version of one of the sender's GameBanana mods is replaced), applies as the Mods
page does, then compares the set with the sender's.
make first updates the sender's GameBanana mods that have a newer file of their own (newer_file: not another file of
the page, an add-on or a variant), in place: same folder names, switches and order; then the game applies them. So the
file gives both the newest.
A fusion (make --fuse) adds the sender's mods to the friend's instead of turning the friend's off. Only the mods that
are turned on travel. On the friend's PC, sync first updates the friend's own turned-on GameBanana mods (as make does
for the sender's). It then takes each mod of the sender's as above, and keeps the friend's own mods with their
switches. A mod on at either side is on, and the friend's own mods follow the sender's in the order, so they win a
conflict. A friend's mod that is another version of one of the sender's is turned off, and the plugins are the union.
At the end, sync writes the file the friend sends back: an ordinary sync file of the fused set (its turned-on mods).
With it, the sender gets the same mods and the same code.
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
BAR = True   # (make's PROGRESS and RESULT lines, for the NILSIX TOOLS page; sync runs in the .bat's console: off)


def L(en, fr):
    return fr if FR else en


def say(text=""):
    print(text, flush=True)


def step(label, done=-1, total=0):
    """make's step for OpenSmash.exe's NILSIX TOOLS page (LauncherForm.Nilsix.cs NilsixLine), which shows it in the
    bar at the bottom as OpenSmash's own jobs: "PROGRESS <0..1, or -1 while not known> <label>", not in the log"""
    if BAR:
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


# ---- GameBanana updates -----------------------------------------------------------------------------------------
VERSION = r"(?:^|_)v?(\d+(?:_\d+)*)(?=_|$)"   # (a version in a file's name: v21, v3_2, 1_2; not sl2 or arcropolisv11)
GAME = r"(?:^|_)((?:9|1[0-3])_0_\d+)(?=_|$)"  # (13_0_4: the game's version a file is built for, part of what it is)


def norm(name):
    """a file's name in lower case without its extension, GameBanana's mark of a name uploaded again (_ and 5 hex
    digits, one a digit at least: not a word such as _faded) and punctuation (one _ between words)"""
    s = os.path.splitext(os.path.basename(str(name)).lower())[0]
    s = re.sub(r"_(?=[a-f]{0,4}\d)[0-9a-f]{5}$", "", s)
    return re.sub(r"[^a-z0-9]+", "_", s).strip("_")


def parts(name):
    """(stem, version): what stays from one version of a file to the next, and its version (a tuple, or None).
    moveset_cuphead_6f5db.zip, moveset_cuphead_b7db9.zip -> moveset_cuphead; paper_mario_moveset_1_2.rar -> (
    paper_mario_moveset, (1, 2)); x_moveset_13_0_4.rar -> x_moveset_13_0_4 (another game's build, not a newer x_moveset)"""
    s = norm(name)
    games = re.findall(GAME, s)
    s = re.sub(GAME, "", s)
    version = tuple(int(x) for v in re.findall(VERSION, s) for x in v.split("_")) or None
    return re.sub(VERSION, "", s).strip("_") + "".join("_" + g for g in games), version


def stem(name):
    return parts(name)[0]


def version_of(name):
    return parts(name)[1]


def lineage(e):
    """a mod's (GameBanana page, stem of its file): the same from one of its files to the next; None without a page"""
    return (str(e["gamebanana"]), stem(e.get("file") or "")) if e.get("gamebanana") else None


def newer_file(files, file_id, file_name, installed):
    """the file of a GameBanana page (its _aFiles) that replaces the installed one, else None: the newest with the
    same stem, uploaded after it (any time when the page no longer has it), not a lower version, not installed itself
    (installed: the page's file ids installed here). Another stem is another file of the page: an add-on (Knuckles'
    track list), a variant (Cuphead without UI) or an older game's build (Mega Man X's moveset_x for 13.0.4)."""
    mine = next((f for f in files if str(f.get("_idRow")) == str(file_id)), None)
    name = mine.get("_sFile", "") if mine else file_name
    key, ver = stem(name), version_of(name)
    after = (mine.get("_tsDateAdded") or 0) if mine else -1
    best = None
    for f in files if key else ():
        when, v = f.get("_tsDateAdded") or 0, version_of(f.get("_sFile", ""))
        if (str(f.get("_idRow")) in installed or stem(f.get("_sFile", "")) != key or when <= after
                or (ver and v and v < ver)):
            continue
        if best is None or when > (best.get("_tsDateAdded") or 0):
            best = f
    return best


def files_of(folder):
    out = set()
    for dp, _dirs, files in os.walk(folder):
        out.update(os.path.relpath(os.path.join(dp, n), folder).replace(os.sep, "/").lower() for n in files)
    return out


def pair(olds, news):
    """{old folder: new folder}: one each, else each old one with the new one sharing most of its files (a pack's
    parts); None when an old one has none (the author changed the pack: that one is updated by hand)"""
    if len(olds) == 1 and len(news) == 1:
        return {olds[0]: news[0]}
    sets = {p: files_of(p) for p in olds + news}
    scored = sorted(((len(sets[o] & sets[n]) / len(sets[o] | sets[n]), o, n) for o in olds for n in news
                     if sets[o] & sets[n]), reverse=True)
    out = {}
    for _score, o, n in scored:
        if o not in out and n not in out.values():
            out[o] = n
    return out if len(out) == len(olds) else None


def game_running(tree):
    """this folder's game runs (Windows keeps a running exe from being opened for writing)"""
    try:
        with open(os.path.join(tree.root, "build", "ssbu.exe"), "r+b"):
            return False
    except FileNotFoundError:
        return False
    except OSError:
        return True


def bar(label):
    """a download's progress in the bar at the bottom (gamebanana_install's progress(done, total)), once a percent"""
    last = [None]

    def p(done, total):
        x = done * 100 // total if total else -1
        if x != last[0]:
            last[0] = x
            step(label, x, 100 if x >= 0 else 0)
    return p


def update(mods, os_mods, tree, state, only=None, apply=True):
    """make's first step: each GameBanana mod with a newer file of its own (newer_file) gets it in place - the same
    folder names, switches and order - then the game applies them (apply). Asks each page once. Returns the state.
    only: the folders to look at (a fusion's sync: this PC's own turned-on mods), else all of them."""
    groups = {}   # (gamebanana, file_id): the folders installed from that file (a pack has several)
    for n in dict.fromkeys(state["order"]):
        m = state["mods"][n]
        if m.get("gamebanana") and m.get("file_id"):
            groups.setdefault((str(m["gamebanana"]), str(m["file_id"])), []).append(n)
    every = dict(groups)
    if only is not None:   # (a pack's file whole, when one of its folders is asked for)
        groups = {k: names for k, names in groups.items() if only & set(names)}
    if not groups:
        return state
    say(L("Checking GameBanana for newer files...", "Recherche de versions plus récentes sur GameBanana..."))
    label = L("CHECKING GAMEBANANA", "VÉRIFICATION SUR GAMEBANANA")
    gbs = list(dict.fromkeys(gb for gb, _fid in groups))
    pages, failed = {}, []
    for i, gb in enumerate(gbs):
        step(label, i, len(gbs))
        try:
            pages[gb] = mods.gamebanana_get(f"/Mod/{int(gb)}?_csvProperties=_aFiles")[0].get("_aFiles") or []
        except Exception as ex:   # (no internet, GameBanana down, a page taken off: those mods as they are)
            failed.append(ex)
            if not pages and len(failed) == 3:   # (three in a row from the start: no internet, not worth 30 s a page)
                break
    if not pages:
        say(L(f"GameBanana could not be asked ({failed[0]}): the file gives your mods as they are.",
              f"GameBanana n'a pas pu être interrogé ({failed[0]}) : le fichier donne tes mods tels quels."))
        return state
    todo = []
    for (gb, fid), names in groups.items():
        e = state["mods"][names[0]]
        title = e.get("title") or names[0]
        if gb not in pages:
            say(L(f"  {title}: its GameBanana page could not be read (not checked)",
                  f"  {title} : sa page GameBanana n'a pas pu être lue (pas vérifié)"))
            continue
        new = newer_file(pages[gb], fid, e.get("file", ""), {f for g, f in every if g == gb})
        if new:
            todo.append((gb, fid, names, title, new))
        elif not any(str(f.get("_idRow")) == fid for f in pages[gb]):
            say(L(f"  {title}: its file ({e.get('file') or fid}) is no longer on GameBanana: send the folder mods\\{names[0]} yourself",
                  f"  {title} : son fichier ({e.get('file') or fid}) n'est plus sur GameBanana : envoie toi-même le dossier mods\\{names[0]}"))
    if not todo:
        say(L("Every GameBanana mod is at its newest file.", "Tous les mods GameBanana sont à leur dernière version."))
        return state
    say(L(f"{len(todo)} mod(s) have a newer file on GameBanana:", f"{len(todo)} mod(s) ont une version plus récente sur GameBanana :"))
    for _gb, fid, names, title, new in todo:
        say(f"  {title}: {state['mods'][names[0]].get('file') or fid} -> {new.get('_sFile')}")
    try:
        building = bool(os_mods.recomp_busy(tree.root))
    except Exception:   # (upstream's check changed: the game's lock still says whether it runs)
        building = False
    if game_running(tree) or building:
        say(L("The game (or a build of it) is running: close it, then make this file again to update them. "
              "This file gives your versions.",
              "Le jeu (ou sa compilation) tourne : ferme-le, puis refais ce fichier pour les mettre à jour. "
              "Ce fichier donne tes versions."))
        return state
    stage = os.path.join(tree.root, "dump", "mods_update")
    done = 0
    for k, (gb, fid, names, title, new) in enumerate(todo, 1):
        say(L(f"Updating {title} ({k}/{len(todo)})...", f"Mise à jour de {title} ({k}/{len(todo)})..."))
        shutil.rmtree(stage, ignore_errors=True)
        st = mods.Tree(os.path.join(stage, f"{gb}_{new['_idRow']}"))
        try:
            got = mods.gamebanana_install(st, gb, new["_idRow"], bar(L("UPDATING ", "MISE À JOUR : ") + title.upper()) if BAR else progress())
        except Exception as ex:   # (mods.Error, the network, the archive: that mod stays as it is)
            say(L(f"  not updated, the download failed ({ex}): the file gives your version",
                  f"  pas mis à jour, le téléchargement a échoué ({ex}) : le fichier donne ta version"))
            continue
        staged = st.load()["mods"]
        olds = [os.path.join(tree.mods, n) for n in names]
        pairs = pair(olds, [os.path.join(st.mods, g) for g in got])
        if pairs is None:
            say(L("  not updated, its new version is laid out differently (update it by hand): the file gives your version",
                  "  pas mis à jour, sa nouvelle version est organisée autrement (à mettre à jour à la main) : le fichier donne ta version"))
            continue
        extra = [g for g in got if os.path.join(st.mods, g) not in pairs.values()]   # (a part the new version adds)
        taken = {x.lower() for x in os.listdir(tree.mods)}
        moved, added = [], []
        try:   # (the old folders aside under hidden names, the new ones to their names; the old ones go at the end)
            for i, o in enumerate(olds):
                tmp = os.path.join(tree.mods, f".mods-update-{os.getpid()}-{k}-{i}")
                os.rename(o, tmp)
                moved.append((o, tmp))
            for o, n in pairs.items():
                shutil.move(n, o)
                moved.append((n, o))
            for g in extra:
                name = free_name(g, taken)
                taken.add(name.lower())
                shutil.move(os.path.join(st.mods, g), os.path.join(tree.mods, name))
                moved.append((os.path.join(st.mods, g), os.path.join(tree.mods, name)))
                added.append((name, g))
        except OSError as ex:
            for a, b in reversed(moved):   # (back as they were: nothing half updated)
                try:
                    shutil.move(b, a)
                except OSError:
                    pass
            say(L(f"  not updated, a folder could not be moved ({ex}): close the windows open in the mods folder; the file gives your version",
                  f"  pas mis à jour, un dossier n'a pas pu être déplacé ({ex}) : ferme les fenêtres ouvertes dans le dossier mods ; le fichier donne ta version"))
            continue
        for _o, tmp in moved[:len(olds)]:
            shutil.rmtree(tmp, ignore_errors=True)
        for o, n in pairs.items():   # (GameBanana's details of the new file; the switch and anything else as they were)
            name = os.path.basename(o)
            state["mods"][name] = dict(state["mods"][name], **{x: v for x, v in staged[os.path.basename(n)].items() if x != "enabled"})
        at = max(i for i, x in enumerate(state["order"]) if x in names) + 1
        for name, g in added:
            state["mods"][name] = staged[g]
        state["order"][at:at] = [name for name, _g in added]
        tree.save(state)
        done += 1
        say(L(f"  updated: {new.get('_sFile')}", f"  mis à jour : {new.get('_sFile')}"))
    shutil.rmtree(stage, ignore_errors=True)
    if not done or not apply:
        return tree.load()
    step(L("APPLYING THE MODS", "APPLICATION DES MODS"))
    say(L("Applying the mods...", "Application des mods..."))
    try:
        mods.apply(tree, lambda t: say("  " + str(t)))
    except Exception as ex:   # (the game applies them at its next start)
        os_mods.apply_pending(tree)
        say(L(f"  not applied now ({ex}): start the game once, then make this file again",
              f"  pas appliqués maintenant ({ex}) : lance le jeu une fois, puis refais ce fichier"))
    return tree.load()


# ---- make: the sender's side ------------------------------------------------------------------------------------
def make(root, out, fuse=False):
    mods, os_mods, _std = tools(root)
    tree = mods.Tree(root)
    return write(root, out, mods, os_mods, tree, update(mods, os_mods, tree, tree.load()), fuse)


def write(root, out, mods, os_mods, tree, state, fuse=False, back_to="", others=frozenset()):
    """the file to send: every mod of this folder; only the turned-on ones in a fusion's file (fuse) and in the one
    sent back after it (back_to: the sender's name; others: the sender's mods)"""
    hashes, listed = {}, []
    for i, n in enumerate(state["order"]):
        step(L("READING YOUR MODS", "LECTURE DE TES MODS"), i, len(state["order"]))
        m = state["mods"][n]
        if (fuse or back_to) and not m.get("enabled"):
            continue
        if n not in hashes:
            hashes[n] = tree_hash(os.path.join(tree.mods, n))[0]
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
    manual = [n for n, e in unique.items() if not (e.get("gamebanana") and e.get("file_id")) and n not in others]
    if manual:
        say(L(f"Not from GameBanana (your friend needs these folders from you, mods\\<name>): {', '.join(manual)}",
              f"Pas de GameBanana (ces dossiers sont à envoyer toi-même, mods\\<nom>) : {', '.join(manual)}"))
    step(L("LOOKING FOR CONFLICTS", "RECHERCHE DES CONFLITS"))
    found = real_conflicts(mods, tree)
    cross = [c for c in found if set(c["mods"]) & others and set(c["mods"]) - others]   # (after a fusion: yours against theirs)
    say(L(f"Conflicts: {len(found)} file(s) changed by more than one turned-on mod (the later one in the order wins; "
          "your friend gets the same order)",
          f"Conflits : {len(found)} fichier(s) modifiés par plusieurs mods activés (le dernier dans l'ordre gagne ; "
          "le fichier donne le même ordre)"))
    if cross:
        say(L(f"  {len(cross)} of them between your mods and {back_to}'s: yours come later, so they win",
              f"  dont {len(cross)} entre tes mods et ceux de {back_to} : les tiens passent après, ils gagnent"))
    for c in (cross + [c for c in found if c not in cross])[:5]:
        say(f"  {c['path']}: {' > '.join(c['mods'])}")
    step(L("WRITING THE FILE", "ÉCRITURE DU FICHIER"), 1, 1)
    manifest = {"format": FORMAT, "version": 1, "sync": SYNC, "from": who,
                "made": datetime.datetime.now().strftime("%Y-%m-%d %H:%M"), "opensmash": version(root),
                "code_patches": code, "mods": listed, "set": [[n, h] for n, h in expected],
                "fingerprint": fingerprint(expected), "plugins": plugins(root), "conflicts": len(found)}
    if fuse:
        manifest["mode"] = "fuse"
    safe = re.sub(r"[^A-Za-z0-9 _.-]+", "_", who).strip(" ._") or "OpenSmash"
    name = (L(f"Mods fusion - {safe}.bat", f"Fusion mods - {safe}.bat") if fuse
            else L(f"Mods sync - {safe}.bat", f"Synchro mods - {safe}.bat"))
    path = out if out.lower().endswith(".bat") else os.path.join(out, name)
    with open(path, "w", encoding="utf-8", newline="\r\n") as f:
        f.write(bat_text(manifest, safe))
    say(L(f"Written: {path}", f"Fichier créé : {path}"))
    fp = manifest["fingerprint"]
    if back_to:
        say(L(f"Send it back to {back_to}: with OpenSmash closed, {back_to} double-clicks it. At the end it must say SYNC OK and {fp}, as here.",
              f"Renvoie-le à {back_to} : OpenSmash fermé, {back_to} double-clique dessus. À la fin, {back_to} doit voir SYNCHRO OK et {fp}, comme ici."))
    elif fuse:
        say(L("Send it to your friend: they double-click it (OpenSmash closed). Their mods stay and yours are added. At the end it says "
              "FUSION OK and writes a file on their desktop: they send it back to you, you double-click it, and you both have the same mods.",
              "Envoie-le à la personne qui joue avec toi : OpenSmash fermé, elle double-clique dessus. Ses mods restent, les tiens s'ajoutent. "
              "À la fin, elle voit FUSION OK et un fichier apparaît sur son bureau : elle te le renvoie, tu double-cliques dessus, et vous avez les mêmes mods."))
    else:
        say(L(f"Send it to your friend: they double-click it (OpenSmash closed). At the end it must say SYNC OK and {fp}.",
              f"Envoie-le à la personne qui joue avec toi : OpenSmash fermé, elle double-clique dessus. À la fin, elle doit voir SYNCHRO OK et {fp}."))
    if BAR:
        print("RESULT " + json.dumps({"ok": True, "file": path, "fingerprint": fp}), flush=True)
    return 0


ABOUT = r"""rem Mods sync for OpenSmash Ultimate from @WHO@ (@MADE@). Double-click it with OpenSmash closed: your OpenSmash
rem gets the same mods, turned on and off the same way, at the same versions. Nilsix tools (OpenSmash Ultimate Launcher)."""
ABOUT_FUSE = r"""rem Mods fusion for OpenSmash Ultimate from @WHO@ (@MADE@). Double-click it with OpenSmash closed: your OpenSmash
rem gets the mods @WHO@ has on and keeps yours. At the end, a file to send back to @WHO@ is written on your desktop.
rem Nilsix tools (OpenSmash Ultimate Launcher)."""

BAT_HEAD = r"""@echo off
@ABOUT@
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
$desk = [Environment]::GetFolderPath('Desktop'); if (-not $desk) { $desk = $env:USERPROFILE }   # (a fusion writes the file to send back there)
& $py -I -X utf8 (Join-Path $dir 'mods_sync.py') sync --tree $Game --manifest (Join-Path $dir 'manifest.json') --lang $lang --out $desk
$rc = $LASTEXITCODE
Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
$exe = Join-Path $Game 'OpenSmash.exe'
if ($rc -eq 0 -and (Test-Path -LiteralPath $exe)) { Start-Process -FilePath $exe -WorkingDirectory $Game }
exit $rc
"""


def bat_text(manifest, who):
    with open(os.path.abspath(__file__), encoding="utf-8") as f:
        me = f.read()
    head = (BAT_HEAD.replace("@ABOUT@", ABOUT_FUSE if manifest.get("mode") == "fuse" else ABOUT)
            .replace("@WHO@", who).replace("@MADE@", manifest["made"]).replace("@MARK@", MARK))
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


def sync(root, man, out=""):
    mods, os_mods, std_plugins = tools(root)
    tree = mods.Tree(root)
    owner = man.get("from") or "?"
    fuse = man.get("mode") == "fuse"
    say(L(f"Mods of {owner} ({man.get('made', '')}): {man.get('fingerprint', '')}",
          f"Mods de {owner} ({man.get('made', '')}) : {man.get('fingerprint', '')}"))
    if fuse:
        say(L(f"Fusion: the mods {owner} has on are added to yours, and none of yours is turned off.",
              f"Fusion : les mods activés de {owner} s'ajoutent aux tiens, aucun des tiens n'est désactivé."))
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
    versions = collections.defaultdict(set)   # (lineage: the sender's files of it; another file of it is another version)
    for e in want.values():
        if lineage(e):
            versions[lineage(e)].add(str(e.get("file_id")))

    def other_version(m):
        return lineage(m) in versions and str(m.get("file_id")) not in versions[lineage(m)]

    if fuse:   # (this PC's own turned-on GameBanana mods at their newest first, as make does for the sender's)
        low = {n.lower() for n in want}
        before = update(mods, os_mods, tree, before, {n for n in before["order"] if before["mods"][n].get("enabled")
                        and n.lower() not in low and not other_version(before["mods"][n])}, apply=False)
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
    # PC's own that has a name the sender's mod needs is kept under another name, turned off (a fusion: its switch)
    moves = [(f, n) for n, f in plan.items() if f != n]
    sources = {f for f, _n in moves}
    present = {x.lower(): x for x in os.listdir(tree.mods)}
    taken = set(present) | {n.lower() for n in want}
    olds, drops = {}, []
    for n in list(plan) + list(staged):
        holder = present.get(n.lower())
        if holder is None or holder == plan.get(n) or holder in sources:
            continue
        gb = before["mods"].get(holder, {}).get("gamebanana")
        if gb and str(gb) == str(want[n].get("gamebanana")):   # (this PC's other version of the sender's mod: replaced)
            drops.append((holder, f".mods-sync-{os.getpid()}-old-{len(drops)}"))
            moves.append(drops[-1])
            continue
        new = free_name(holder if fuse else holder + L(" (old)", " (ancien)"), taken)   # (a fusion: "<name> 2")
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
    for holder, hidden in drops:
        shutil.rmtree(os.path.join(tree.mods, hidden), ignore_errors=True)
        say(L(f"  your {holder} (another version of {owner}'s mod) is replaced by {owner}'s",
              f"  ton {holder} (une autre version du mod de {owner}) est remplacé par celui de {owner}"))
    off = "" if fuse else L(", turned off", ", désactivé")
    for old, holder in olds.items():
        say(L(f"  your own {holder} (other files than {owner}'s) is kept as {old}{off}",
              f"  ton propre {holder} (pas les mêmes fichiers que celui de {owner}) est gardé sous le nom {old}{off}"))
    # 4. the switches and the order: the sender's, then this PC's own mods, turned off (a fusion keeps their
    # switches, except for another version of one of the sender's mods); so this PC's own win a conflict
    filled = set(plan) | set(staged)
    state = tree.load()
    for n in state["mods"]:
        if n in filled:
            state["mods"][n] = entry_of(want[n])
            continue
        if n in olds:
            state["mods"][n] = dict(before["mods"].get(olds[n], {}))
        m = state["mods"][n]
        if fuse and m.get("enabled") and other_version(m):
            say(L(f"  {n}: another version of one of {owner}'s mods: turned off (kept)",
                  f"  {n} : une autre version d'un mod de {owner} : désactivé (gardé)"))
        elif fuse:
            continue
        elif m.get("enabled") and n not in olds:
            say(L(f"  {n}: {owner} doesn't have it: turned off (kept)", f"  {n} : {owner} ne l'a pas : désactivé (gardé)"))
        m["enabled"] = False
    state["order"] = [n for n in order if n in filled] + [n for n in state["order"] if n not in filled]
    code = man.get("code_patches") if isinstance(man.get("code_patches"), bool) else None
    if fuse:   # (on when on at either side, else automatic when automatic at either side)
        mine = before.get("code_patches") if isinstance(before.get("code_patches"), bool) else None
        code = True if True in (code, mine) else None if None in (code, mine) else False
    if code is None:
        state.pop("code_patches", None)
    else:
        state["code_patches"] = code
    tree.save(state)   # (every folder is in mods.json now: OpenSmash won't ask to turn one on, LauncherForm ScanForNewMods)
    # 5. the standard plugins: one the sender doesn't have is set aside (a fusion keeps it); a missing or different
    # one is fetched again
    want_p = {k.lower(): v for k, v in (man.get("plugins") or {}).items()}
    folder = os.path.join(root, "skyline", "plugins")
    for n in plugins(root):
        if n.lower() not in want_p and not fuse:
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
    rc = report(tree, man, mods, os_mods, problems, fuse)
    if fuse and rc == 0:   # (the file to send back: the fused mods, for the sender to get them the same way)
        say("")
        rc = write(root, out, mods, os_mods, tree, tree.load(), back_to=owner, others=set(want))
    return rc


def report(tree, man, mods, os_mods, problems=(), fuse=False):
    """the online set here against the sender's, the plugins and the conflicts; 0 when the same (fuse: when all of
    the sender's are here, beside this PC's own)"""
    owner = man.get("from") or "?"
    names = (tree.applied() or {}).get("mods") or []
    mine = online_set(tree, names, os_mods.code_patches_on(tree))
    theirs = [(n, x) for n, x in man.get("set") or []]
    a, b = collections.Counter(mine), collections.Counter(theirs)
    lacking, extra = b - a, a - b
    diff = []
    for n, _x in sorted(set(lacking) | (set() if fuse else set(extra))):
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
    want_on = [e["name"] for e in man.get("mods") or [] if e.get("enabled")]
    if not diff and [n for n in names if not fuse or n in want_on] != want_on:
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
        if fuse:
            say(L(f"FUSION OK: {owner}'s mods are added to yours ({on} on, {off} off), online set {fingerprint(mine)}; "
                  f"{conflicts} conflict(s).",
                  f"FUSION OK : les mods de {owner} sont ajoutés aux tiens ({on} activés, {off} désactivés), empreinte "
                  f"{fingerprint(mine)} ; {conflicts} conflit(s)."))
        else:
            say(L(f"SYNC OK: the same mods as {owner} ({on} on, {off} off), online set {fingerprint(mine)}; "
                  f"{conflicts} conflict(s), as at {owner}'s.",
                  f"SYNCHRO OK : les mêmes mods que {owner} ({on} activés, {off} désactivés), empreinte {fingerprint(mine)} ; "
                  f"{conflicts} conflit(s), comme chez {owner}."))
        say(L("In OpenSmash, press Play: the first time, it builds the mods' plugins into the game (a few minutes).",
              "Dans OpenSmash, clique sur Jouer : la première fois, il compile les plugins des mods dans le jeu (quelques minutes)."))
        return 0
    say("")
    if fuse:
        say(L(f"FUSION NOT FINISHED with {owner}:", f"FUSION PAS FINIE avec {owner} :"))
    else:
        say(L(f"NOT IN SYNC with {owner} (online set {fingerprint(mine)} here, {man.get('fingerprint', '?')} there):",
              f"PAS SYNCHRO avec {owner} (empreinte {fingerprint(mine)} ici, {man.get('fingerprint', '?')} chez {owner}) :"))
    for line in diff:
        say("  " + line)
    if fuse:
        say(L(f"Fix that, then run this file again: the file to send back to {owner} is written at the end.",
              f"Corrige ça, puis relance ce fichier : le fichier à renvoyer à {owner} est créé à la fin."))
    return 1


def main(argv):
    global FR, BAR
    ap = argparse.ArgumentParser(description="OpenSmash mods sync (Nilsix tools)")
    ap.add_argument("command", choices=("make", "sync", "check"))
    ap.add_argument("--tree", required=True)
    ap.add_argument("--out", default="")
    ap.add_argument("--manifest", default="")
    ap.add_argument("--lang", default="")
    ap.add_argument("--fuse", action="store_true")
    a = ap.parse_args(argv[1:])
    FR = (a.lang or first_line(os.path.join(os.environ.get("LOCALAPPDATA", ""), "WindowSmash-setup", "lang.txt"))) == "fr"
    BAR = a.command == "make"
    root = os.path.abspath(a.tree)
    out = a.out or os.path.join(os.path.expanduser("~"), "Desktop")
    if not os.path.exists(os.path.join(root, "tools", "mods.py")):
        say(L(f"{root} is not an OpenSmash folder (no tools\\mods.py).", f"{root} n'est pas un dossier OpenSmash (pas de tools\\mods.py)."))
        return 2
    try:
        if a.command == "make":
            return make(root, out, a.fuse)
        with open(a.manifest, encoding="utf-8-sig") as f:
            man = json.load(f)
        if not isinstance(man, dict) or man.get("format") != FORMAT or man.get("sync") != SYNC:
            say(L("This is not a mods sync file of this version.", "Ce n'est pas un fichier de synchro de cette version."))
            return 2
        if a.command == "sync":
            return sync(root, man, out)
        mods, os_mods, _std = tools(root)
        return report(mods.Tree(root), man, mods, os_mods, fuse=man.get("mode") == "fuse")
    except Exception as ex:   # (mods.Error is the person's to act on; anything else is said the same way)
        say(L(f"Stopped: {ex}", f"Arrêté : {ex}"))
        if a.command == "make":
            print("RESULT " + json.dumps({"ok": False, "error": str(ex)}), flush=True)
        return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
