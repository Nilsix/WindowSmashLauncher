#!/usr/bin/env python3
"""WindowSmash setup kit, Python side. ws_setup.ps1 runs it with the repository's own Python environment.

    ws_setup.py [--repo DIR] [--log FILE] <command> ...

  probe                                     Python version, compression.zstd, pycryptodomex
  keys      --keys DIR                      prod.keys: the keys this setup needs, which generations are there
  identify  FILE --keys DIR --role base|update [--expect VERSION]
                                            what a package is (XCI / NSP / NCA), its title and version
  plain-nca BASE OUT --keys DIR             the base game's Program NCA, decrypted in place (WindowSmash's update.py
                                            applies an update exactly over the original release stored so)
  fonts     SOURCE OUTDIR --keys DIR        the firmware's shared fonts (.bfttf): from an XCI's update partition or a
                                            folder of firmware NCAs (a dump, yuzu/suyu nand, Ryujinx bis)
  install   --update NSP --keys DIR --jobs N [--dlc DIR] [--no-build]
                                            the game built in the WindowSmash folder by its tools/build_game.py,
                                            from the decrypted base (plain-nca) and the 13.0.5 update (below)
  status                                    the game's state in the WindowSmash folder, for the report
  unlock    [--dry-run]                     every fighter unlocked in the save (tools/unlock_all.py)
  shaders   [--jobs N]                      the game's shaders compiled ahead of time (tools/shader_aot.py)

Lines for ws_setup.ps1: "@@JSON {...}", "@@WARN <code> <text>", "@@ERROR <code> <text>" (then exit 2; exit 3 is
"the compiler ran out of memory": the caller retries with fewer jobs). Key values are never printed.

Since commit ec8a8b5 WindowSmash plays game version 13.0.5 only, built in its own folder (dump/, build/, save/) by
tools/build_game.py; kit 2.x built 13.0.4 in a version folder (v13.0.4/) with tools/install_version.py, which is gone.
build_game.py reads the game from one folder: `install` gives it dump/game_files, holding the base decrypted by
plain-nca (a hard link) and the update (a hard link, or a junction to its folder on another disk), so nothing big is
copied and the base is not decrypted twice. A version folder's save and prepared shaders come over first, and before
the build the build folders of the modules that are the same files in 13.0.5 (every one but main), so that a player
coming from 13.0.4 recompiles main only.
"""
import argparse
import json
import os
import re
import shutil
import struct
import subprocess
import sys
import time
import traceback

SSBU_BASE = 0x01006A800016E000
SSBU_UPDATE = SSBU_BASE | 0x800
FONT_TITLES = set(range(0x0100000000000810, 0x0100000000000815))
FONTS_NEEDED = ["nintendo_udsg-r_std_003.bfttf", "nintendo_udsg-r_org_zh-cn_003.bfttf",
                "nintendo_udsg-r_ext_zh-cn_003.bfttf", "nintendo_udjxh-db_zh-tw_003.bfttf",
                "nintendo_udsg-r_ko_003.bfttf", "nintendo_ext_003.bfttf"]
CHUNK = 64 << 20
OOM_MARKS = ("out of memory", "allocation failed", "memoryerror", "out of heap space", "bad_alloc")
DISK_MARKS = ("no space left on device", "not enough space on the disk", "espace insuffisant sur le disque")


class Problem(Exception):
    def __init__(self, code, text, exit_code=2):
        super().__init__(text)
        self.code, self.text, self.exit_code = code, text, exit_code


class Tee:
    """Everything printed goes to the console and to the log."""
    def __init__(self, stream, path):
        self.s = stream
        self.f = open(path, "a", encoding="utf-8", errors="replace")
        self.last_step = None

    def write(self, text):
        self.s.write(text)
        self.f.write(text)
        for line in text.splitlines():
            if line.startswith("[") and "]" in line and " " not in line.split("]")[0]:
                self.last_step = line[1:line.index("]")]
        return len(text)

    def flush(self):
        self.s.flush()
        self.f.flush()


def out(kind, payload):
    print(f"@@{kind} {payload}", flush=True)


def tools(repo):
    t = os.path.join(repo, "tools")
    if not os.path.isfile(os.path.join(t, "nca.py")):
        raise Problem("E10", f"{repo}: pas de tools\\nca.py (ce n'est pas le dossier WindowSmash)")
    if t not in sys.path:
        sys.path.insert(0, t)
    try:
        import nca  # noqa: F401
    except ImportError as e:
        raise Problem("E31", f"module manquant dans l'environnement Python: {e}")


# ---- containers ---------------------------------------------------------------------------
def hfs0(f, base):
    f.seek(base)
    magic, count, strings_size, _ = struct.unpack("<4sIII", f.read(16))
    if magic != b"HFS0":
        raise Problem("E42", f"partition HFS0 attendue a {base:#x}: XCI abime ou incomplet")
    entries = [struct.unpack_from("<QQI", f.read(0x40)) for _ in range(count)]
    strings = f.read(strings_size)
    data = base + 16 + 0x40 * count + strings_size
    return {strings[n:strings.index(b"\0", n)].decode(): (data + off, size) for off, size, n in entries}


def xci_partitions(path):
    with open(path, "rb") as f:
        for head in (0x100, 0x1100):
            f.seek(head)
            if f.read(4) == b"HEAD":
                break
        else:
            return None
        f.seek(head + 0x30)
        root, = struct.unpack("<Q", f.read(8))
        parts = hfs0(f, root + head - 0x100)
        return {name: hfs0(f, off) for name, (off, _size) in parts.items()}


def container(path):
    """('xci'|'nsp'|'nca', {partition or '': {name: (offset, size)}})."""
    with open(path, "rb") as f:
        magic = f.read(4)
    if magic == b"PFS0":
        from nca import pfs0_files
        return "nsp", {"": {n: (o, s) for n, o, s in pfs0_files(path)}}
    parts = xci_partitions(path)
    if parts is not None:
        return "xci", parts
    return "nca", {"": {os.path.basename(path): (0, os.path.getsize(path))}}


def tickets(path, files):
    """(common title keys, personalized ticket count) of an NSP."""
    from nca import TICKET_SIG, nsp_title_keys
    common = nsp_title_keys(path)
    personal = 0
    with open(path, "rb") as f:
        for name, (off, size) in files.items():
            if name.endswith(".tik"):
                f.seek(off)
                t = f.read(size)
                body = TICKET_SIG.get(struct.unpack_from("<I", t)[0])
                if body is not None and t[body + 0x141] != 0:
                    personal += 1
    return common, personal


def header_info(path, off, prod):
    from nca import xts_decrypt
    with open(path, "rb") as f:
        f.seek(off)
        raw = f.read(0xC00)
    hdr = raw if raw[0x200:0x204] == b"NCA3" else xts_decrypt(prod["header_key"], raw)
    if hdr[0x200:0x204] != b"NCA3":
        return None
    gen = max(hdr[0x206], hdr[0x220])
    return {"type": hdr[0x205], "kaek": hdr[0x207], "title": struct.unpack_from("<Q", hdr, 0x210)[0],
            "key_gen": gen - 1 if gen else 0, "rights": hdr[0x230:0x240].hex(), "plain": raw[0x200:0x204] == b"NCA3"}


def check_nca_keys(info, prod, title_keys, personal):
    """Raise the precise problem when an NCA cannot be opened with these keys."""
    g = info["key_gen"]
    if int(info["rights"], 16):
        if f"titlekek_{g:02x}" not in prod:
            raise Problem("E41", f"prod.keys trop ancien: il manque titlekek_{g:02x} (generation {g}). "
                                 "Redumpe tes cles (Lockpick_RCM) depuis ta console a jour.")
        if info["rights"] not in title_keys:
            if personal:
                raise Problem("E44", "le ticket du paquet est personnalise (lie a une console): redumpe le jeu avec "
                                     "nxdumptool option 'remove console specific data', ou fournis un title.keys.")
            raise Problem("E44", "pas de ticket dans le paquet pour sa cle de titre: fournis un title.keys ou un dump "
                                 "avec ticket.")
    else:
        name = ("application", "ocean", "system")[info["kaek"] if info["kaek"] < 3 else 0]
        if f"key_area_key_{name}_{g:02x}" not in prod:
            raise Problem("E41", f"prod.keys trop ancien: il manque key_area_key_{name}_{g:02x} (generation {g}).")


def open_ncas(path, keys, partition=None, with_meta=False):
    """[(name, Nca)] of a package (the 'secure' partition of an XCI), keys checked first."""
    from nca import Nca, load_keys
    prod = load_keys(os.path.join(keys, "prod.keys"))
    title_keys = load_keys(os.path.join(keys, "title.keys"))
    kind, parts = container(path)
    files = parts.get(partition or ("secure" if kind == "xci" else ""))
    if files is None:
        raise Problem("E42", f"{os.path.basename(path)}: pas de partition {partition or 'secure'}")
    tks, personal = ({}, 0)
    if kind == "nsp":
        tks, personal = tickets(path, files)
        title_keys = {**title_keys, **{k: v for k, v in tks.items()}}
    result = []
    for name, (off, size) in sorted(files.items()):
        if not name.endswith(".nca") or (name.endswith(".cnmt.nca") and not with_meta):
            continue
        info = header_info(path, off, prod)
        if info is None:
            raise Problem("E41", "l'en-tete d'un NCA ne se dechiffre pas: header_key fausse dans prod.keys?")
        check_nca_keys(info, prod, {k.lower(): v for k, v in title_keys.items()}, personal)
        tk = {k: v for k, v in tks.items()}
        result.append((name, Nca(path, keys, off, tk or None), info))
    return kind, result


def display_version(ncas):
    from nca import romfs_entries
    for _name, nca, info in ncas:
        if info["type"] != 2:
            continue
        try:
            sec = nca.section(0)
            for path, off, _size in romfs_entries(sec):
                if path.endswith("control.nacp"):
                    return sec.read(off + 0x3060, 0x10).split(b"\0")[0].decode("utf-8", "replace") or None
        except Exception:   # noqa: BLE001 - a version we cannot read is reported as unknown
            continue
    return None


def title_version(ncas):
    from nca import pfs0_entries
    for name, nca, info in ncas:
        if info["type"] != 1:
            continue
        try:
            sec = nca.section(1)
            for n, off, _size in pfs0_entries(sec):
                if n.endswith(".cnmt"):
                    return struct.unpack_from("<QI", sec.read(off, 0x10))
        except Exception:   # noqa: BLE001
            continue
    return None, None


# ---- commands -----------------------------------------------------------------------------
def cmd_probe(a):
    info = {"python": sys.version.split()[0], "executable": sys.executable, "zstd": False, "cryptodome": None}
    try:
        import compression.zstd  # noqa: F401
        info["zstd"] = True
    except ImportError:
        pass
    try:
        import Cryptodome
        info["cryptodome"] = Cryptodome.__version__
    except ImportError:
        pass
    out("JSON", json.dumps(info))
    if sys.version_info < (3, 14) or not info["zstd"]:
        raise Problem("E30", f"Python {info['python']} sans compression.zstd: il faut Python 3.14")


def cmd_keys(a):
    path = os.path.join(a.keys, "prod.keys")
    if not os.path.isfile(path):
        raise Problem("E41", f"prod.keys introuvable ({path})")
    names, bad = {}, 0
    with open(path, encoding="utf-8", errors="ignore") as f:
        for line in f:
            if "=" not in line:
                continue
            k, v = line.split("=", 1)
            try:
                names[k.strip().lower()] = len(bytes.fromhex(v.strip()))
            except ValueError:
                bad += 1
    if not names:
        raise Problem("E41", "prod.keys vide ou illisible")
    hexchars = set("0123456789abcdef")
    if all(len(k) == 32 and set(k) <= hexchars for k in names):
        raise Problem("E41", "ce fichier est un title.keys, pas un prod.keys")
    kak = sorted(int(k[-2:], 16) for k in names if k.startswith("key_area_key_application_") and len(k) == 27)
    tkek = sorted(int(k[-2:], 16) for k in names if k.startswith("titlekek_") and len(k) == 11)
    out("JSON", json.dumps({"count": len(names), "unreadable_lines": bad, "header_key": names.get("header_key") == 32,
                            "kak_application": kak, "titlekek": tkek}))
    if names.get("header_key") != 32:
        raise Problem("E41", "header_key manquante ou invalide dans prod.keys")
    if not kak or not tkek:
        raise Problem("E41", "prod.keys incomplet (key_area_key_application_xx / titlekek_xx manquantes)")


def cmd_identify(a):
    tools(a.repo)
    kind, ncas = open_ncas(a.file, a.keys, with_meta=True)
    programs = [(nca.size, n, nca, i) for n, nca, i in ncas if i["type"] == 0]
    if not programs:
        raise Problem("E42" if a.role == "base" else "E43", f"{os.path.basename(a.file)}: pas de NCA programme")
    _size, name, prog, pinfo = max(programs, key=lambda p: p[0])
    romfs = prog.section(0)
    patch = romfs is not None and romfs.enc_type == 4
    tid, tver = title_version(ncas)
    disp = display_version(ncas)
    has_fonts = False
    if kind == "xci":
        upd = container(a.file)[1].get("update", {})
        has_fonts = any(n.endswith(".nca") for n in upd)
    # an update's program NCA carries the application's id in its header; the update's own id (..800) is its cnmt's
    res = {"kind": kind, "program": f"{pinfo['title']:016X}", "meta_title": f"{tid:016X}" if tid is not None else None,
           "display": disp, "title_version": tver, "key_gen": max(i["key_gen"] for _n, _c, i in ncas), "patch": patch,
           "xci_update_partition": has_fonts, "program_size": prog.size, "titlekey": bool(int(pinfo["rights"], 16))}
    out("JSON", json.dumps(res))
    if pinfo["title"] not in (SSBU_BASE, SSBU_UPDATE):
        raise Problem("E42" if a.role == "base" else "E43", f"ce n'est pas Super Smash Bros. Ultimate (titre {pinfo['title']:016X})")
    if a.role == "base":
        if patch or tid == SSBU_UPDATE:
            raise Problem("E42", "ce fichier est une MISE A JOUR, pas le jeu de base (il faut le .xci/.nsp du jeu 1.0.0)")
        if disp and disp != "1.0.0":
            out("WARN", f"W42 jeu de base en version {disp} (1.0.0 attendue): l'update s'appliquera plus lentement, "
                        "et peut echouer")
    else:
        if not patch or (tid is not None and tid != SSBU_UPDATE):
            raise Problem("E43", "ce fichier n'est pas une mise a jour de Smash Ultimate (il faut l'update .nsp)")
        if a.expect and disp != a.expect:
            out("WARN", f"W43 update en version {disp}, {a.expect} attendue: le netplay demande la meme version que "
                        "l'hote")


def write_plain(path, off, size, nca, prod, out_path):
    from nca import xts_decrypt
    src = open(path, "rb")
    src.seek(off)
    header = xts_decrypt(prod["header_key"], src.read(0xC00))
    os.makedirs(os.path.dirname(os.path.abspath(out_path)), exist_ok=True)
    t0, done, shown = time.time(), 0, -5
    with open(out_path + ".part", "wb") as o:
        o.write(header)
        pos = 0xC00
        for sec in sorted(nca.sections, key=lambda s: s.start):
            src.seek(off + pos)
            o.write(src.read(sec.start - pos))
            rel = 0
            while rel < sec.end - sec.start:
                n = min(CHUNK, sec.end - sec.start - rel)
                o.write(sec.read_raw(rel, n))
                rel += n
                done += n
                pct = 100.0 * done / size
                if pct - shown >= 5:     # a line every 5 %: the caller shows lines as they come
                    shown = pct
                    print(f"  {pct:5.1f}%  {done / 2 ** 20 / max(time.time() - t0, 0.01):.0f} Mo/s", flush=True)
            pos = sec.end
        src.seek(off + pos)
        o.write(src.read(size - pos))
        if o.tell() != size:
            raise Problem("E50", f"ecrit {o.tell()} octets au lieu de {size}")
    os.replace(out_path + ".part", out_path)
    print(f"  ecrit en {time.time() - t0:.0f} s", flush=True)


def cmd_plain_nca(a):
    tools(a.repo)
    from nca import Nca, load_keys
    prod = load_keys(os.path.join(a.keys, "prod.keys"))
    kind, parts = container(a.base)
    files = parts.get("secure" if kind == "xci" else "")
    kind, ncas = open_ncas(a.base, a.keys)
    programs = [(nca.size, n, nca, i) for n, nca, i in ncas if i["type"] == 0]
    if not programs:
        raise Problem("E42", "pas de NCA programme dans le jeu de base")
    size, name, nca, info = max(programs, key=lambda p: p[0])
    off, entry_size = files[name]
    if nca.size != entry_size:
        raise Problem("E42", f"{name}: taille {nca.size} dans l'en-tete, {entry_size} dans le paquet (dump abime?)")
    if int(info["rights"], 16):   # the plain NCA keeps its rights id: WindowSmash opens it with the title key
        enc = (tickets(a.base, files)[0] if kind == "nsp" else {}).get(info["rights"])
        if enc:
            tpath = os.path.join(a.keys, "title.keys")
            have = open(tpath, encoding="utf-8", errors="ignore").read() if os.path.exists(tpath) else ""
            if info["rights"] not in have.lower():
                with open(tpath, "a", encoding="utf-8") as f:
                    f.write(f"{info['rights']} = {enc.hex()}\n")
    if os.path.exists(a.out) and os.path.getsize(a.out) == size:
        try:
            if Nca(a.out, a.keys).plaintext:
                print(f"  {a.out}: deja la (dechiffre), garde", flush=True)
                return
        except SystemExit:
            pass
    print(f"  NCA programme {name}: {size / 2 ** 30:.2f} Go -> {a.out}", flush=True)
    os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
    free = __import__("shutil").disk_usage(os.path.dirname(os.path.abspath(a.out))).free
    if free < size + (1 << 30):
        raise Problem("E22", f"pas assez de place: {size / 2 ** 30:.1f} Go a ecrire, {free / 2 ** 30:.1f} Go libres")
    write_plain(a.base, off, size, nca, prod, a.out)
    check = Nca(a.out, a.keys)
    if not check.plaintext or check.title_id != info["title"]:
        raise Problem("E50", "le NCA ecrit ne se relit pas comme un NCA dechiffre")


def nca_files(folder):
    for dp, dirs, files in os.walk(folder):
        for f in files:
            p = os.path.join(dp, f)
            if f.lower().endswith(".nca") or (f == "00" and dp.lower().endswith(".nca")):
                yield p


def cmd_fonts(a):
    tools(a.repo)
    from nca import Nca, copy_out, romfs_entries
    os.makedirs(a.outdir, exist_ok=True)
    found = 0
    if os.path.isdir(a.source):
        cands = [(p, 0) for p in nca_files(a.source)]
        print(f"  {len(cands)} fichiers NCA dans {a.source}", flush=True)
    else:
        kind, parts = container(a.source)
        if kind != "xci" or not parts.get("update"):
            raise Problem("E45", "ce fichier n'a pas de partition 'update' (firmware): donne le dossier du firmware")
        cands = [(a.source, off) for n, (off, _s) in sorted(parts["update"].items()) if n.endswith(".nca")]
    for path, off in cands:
        try:
            nca = Nca(path, a.keys, off)
        except (SystemExit, OSError, ValueError, struct.error):
            continue
        if nca.title_id not in FONT_TITLES or nca.content_type == 1:   # (a font title's metadata NCA has no RomFS)
            continue
        sec = nca.section(0)
        if sec is None:
            continue
        try:
            for p, foff, fsize in romfs_entries(sec):
                if p.endswith(".bfttf"):
                    copy_out(sec, foff, fsize, os.path.join(a.outdir, os.path.basename(p)))
                    print(f"  {os.path.basename(p)}", flush=True)
                    found += 1
        except Exception as e:   # noqa: BLE001
            out("WARN", f"W45 archive de polices illisible ({e})")
    missing = [f for f in FONTS_NEEDED if not os.path.exists(os.path.join(a.outdir, f))]
    out("JSON", json.dumps({"written": found, "missing": missing}))
    if missing:
        raise Problem("E45", "polices manquantes: " + ", ".join(missing))


STAGE = os.path.join("dump", "game_files")     # the game folder build_game.py is given (made by stage_game_files)
PLAIN_BASE = os.path.join("dump", "base", "program_v0.nca")
# build_game.py's steps ("[4/9] ..."), for the error a failure in each gets
STEP_CODES = {1: "E35", 2: "E31", 3: "E53", 4: "E43", 5: "E45", 6: "E51", 7: "E53", 8: "E52", 9: "E60"}


def migrate_version_folders(repo):
    """Kit 2.x played from a version folder (v13.0.4\\): its save and prepared shaders come over to the WindowSmash
    folder itself, where the game is built and played since 13.0.5 (the game upgrades an older save at its first
    start). Nothing is done where the folder has its own already."""
    trees = sorted(d for d in os.listdir(repo) if re.fullmatch(r"v\d+(\.\d+)*", d) and os.path.isdir(os.path.join(repo, d)))
    for tree in trees:
        save, root_save = os.path.join(repo, tree, "save"), os.path.join(repo, "save")
        if os.path.isdir(save) and not os.path.exists(root_save):
            shutil.copytree(save, root_save)
            print(f"  {tree}\\save -> save (ta sauvegarde, reprise par la 13.0.5)", flush=True)
        cache, root_cache = os.path.join(repo, tree, "dump", "shadercache"), os.path.join(repo, "dump", "shadercache")
        if os.path.isdir(cache) and not os.path.exists(root_cache):
            os.makedirs(os.path.dirname(root_cache), exist_ok=True)
            shutil.move(cache, root_cache)
            print(f"  {tree}\\dump\\shadercache -> dump\\shadercache (les shaders deja prepares)", flush=True)


def drop_base_only_cfg(repo):
    """Kit 2.x wrote dump\\modules\\romfs.cfg for the base game's data alone (1.0.0): build_game.py would take it as
    its step 6 done. It goes; build_game.py writes the one with the update applied."""
    cfg = os.path.join(repo, "dump", "modules", "romfs.cfg")
    if not os.path.isfile(cfg):
        return
    with open(cfg, encoding="utf-8-sig") as f:
        first = f.readline().strip()
    if first != "layered" and os.path.normcase(os.path.abspath(first)) == os.path.normcase(os.path.join(repo, PLAIN_BASE)):
        os.remove(cfg)
        print("  dump\\modules\\romfs.cfg du jeu de base seul (kit 2.x) retire", flush=True)


def is_junction(path):
    return os.path.isjunction(path) if hasattr(os.path, "isjunction") else False


def make_junction(link, target):
    """A directory junction (no administrator rights needed, other disks allowed)."""
    try:
        import _winapi
        _winapi.CreateJunction(os.path.abspath(target), os.path.abspath(link))
    except (ImportError, AttributeError, OSError):
        r = subprocess.run(["cmd", "/c", "mklink", "/J", os.path.abspath(link), os.path.abspath(target)],
                           capture_output=True, text=True)
        if r.returncode or not os.path.isdir(link):
            raise Problem("E53", f"lien vers {target} impossible: {(r.stdout + r.stderr).strip()}")


def clear_stage(stage):
    """Empties the game folder of last time without ever going into what it points to: a hard link is a second name of
    the player's file (the file stays), a junction a pointer to the player's folder (the folder stays)."""
    if not os.path.isdir(stage):
        return
    for n in os.listdir(stage):
        p = os.path.join(stage, n)
        if is_junction(p) or (os.path.islink(p) and os.path.isdir(p)):
            os.rmdir(p)   # (the junction itself: what it points to is not touched)
        elif os.path.islink(p) or os.path.isfile(p):
            os.remove(p)
        else:
            raise Problem("E53", f"{p}: dossier inattendu dans {stage} (rien n'a ete efface)")


def stage_game_files(repo, update, dlc):
    """dump\\game_files, the game folder build_game.py reads: the decrypted base and the update, by hard links (same
    disk) or junctions to their folders (another disk), and the DLC folder as its dlc\\ (a junction)."""
    stage = os.path.join(repo, STAGE)
    clear_stage(stage)
    os.makedirs(stage, exist_ok=True)
    base = os.path.join(repo, PLAIN_BASE)
    if not os.path.isfile(base):
        raise Problem("E50", f"{base} manque: la copie dechiffree du jeu de base n'est pas faite")
    for src, name, folder in ((base, "program_v0.nca", "base"), (os.path.abspath(update), os.path.basename(update), "update")):
        try:
            os.link(src, os.path.join(stage, name))
        except OSError:   # (another disk, or one without hard links)
            make_junction(os.path.join(stage, folder), os.path.dirname(src))
    if dlc:
        make_junction(os.path.join(stage, "dlc"), dlc)
    return stage


def same_content(a, b):
    import filecmp
    return os.path.isfile(a) and os.path.isfile(b) and filecmp.cmp(a, b, shallow=False)


def seed_from_old_tree(repo):
    """Kit 2.x's 13.0.4 build compiled every module, and the 98 fighter modules, sdk and subsdk0 are the very same
    files in 13.0.5 (only main differs): their build folders (the generated C and its objects) move over to the new
    build before it starts. recomp.py then writes the same C again, leaves those files as they are (same bytes) and
    compiles what differs only: main, some minutes instead of hours. A module comes over only when its input is
    byte-identical in both versions and the new build has no folder of its own for it yet; main never does."""
    new_build = os.path.join(repo, "build")
    for tree in sorted(d for d in os.listdir(repo) if re.fullmatch(r"v\d+(\.\d+)*", d)):
        old_build = os.path.join(repo, tree, "build")
        if not os.path.isdir(old_build):
            continue
        pairs = []
        old_nro, new_nro = os.path.join(repo, tree, "dump", "nro"), os.path.join(repo, "dump", "nro")
        if os.path.isdir(old_nro):
            for n in sorted(os.listdir(old_nro)):
                if n.endswith(".nro") and same_content(os.path.join(old_nro, n), os.path.join(new_nro, n)):
                    pairs.append((os.path.join(old_build, "nro", n[:-4]), os.path.join(new_build, "nro", n[:-4])))
        for name in ("sdk", "subsdk0"):
            if same_content(os.path.join(repo, tree, "dump", "exefs", name), os.path.join(repo, "dump", "exefs", name)):
                pairs.append((os.path.join(old_build, name), os.path.join(new_build, name)))
        moved = 0
        for src, dst in pairs:
            if os.path.isdir(src) and not os.path.exists(dst):
                try:
                    os.makedirs(os.path.dirname(dst), exist_ok=True)
                    os.replace(src, dst)   # (one disk: a rename)
                    moved += 1
                except OSError:            # (in use: that module is compiled again, that's all)
                    pass
        for n in os.listdir(old_build):    # the modules' images, named by build id: the same for the same module
            if n.startswith("image-") and n.endswith(".img") and not os.path.exists(os.path.join(new_build, n)):
                try:
                    os.replace(os.path.join(old_build, n), os.path.join(new_build, n))
                except OSError:
                    pass
        if moved:
            print(f"  {moved} modules repris de {tree}\\build (identiques en 13.0.5 : pas recompiles)", flush=True)


def cmd_install(a):
    tools(a.repo)
    os.chdir(a.repo)
    migrate_version_folders(a.repo)
    drop_base_only_cfg(a.repo)
    if a.dlc:   # (a DLC folder given now: build_game.py's step 7 reads it again, whatever it found before)
        for n in ("aoc.cfg", "aoc.none"):
            if os.path.exists(os.path.join(a.repo, "dump", "modules", n)):
                os.remove(os.path.join(a.repo, "dump", "modules", n))
    stage = stage_game_files(a.repo, a.update, a.dlc)
    cmd = [sys.executable, "-u", os.path.join("tools", "build_game.py"), "--game", stage, "--keys", a.keys,
           "--jobs", str(a.jobs)]
    # the game files first (steps 1 to 8), then the modules a 13.0.4 build already compiled, then the build
    run_build_game(cmd + ["--prepare-only"])
    if not a.no_build:
        seed_from_old_tree(a.repo)
        run_build_game(cmd)


def run_build_game(cmd):
    """tools/build_game.py, its output shown and kept, and its failure told as the kit's error code."""
    seen = {"oom": False, "link": False, "disk": False, "step": 0, "error": []}
    p = subprocess.Popen(cmd, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
                         encoding="utf-8", errors="replace", bufsize=1,
                         env=dict(os.environ, PYTHONUNBUFFERED="1", PYTHONIOENCODING="utf-8"))   # (a path like "Bros.™")
    for line in p.stdout:
        sys.stdout.write(line)
        low = line.lower()
        m = re.match(r"\[(\d)/9\]", line.strip())
        if m:
            seen["step"] = int(m.group(1))
        if any(k in low for k in OOM_MARKS):
            seen["oom"] = True
        if any(k in low for k in DISK_MARKS):
            seen["disk"] = True
        if "link failed" in low or "could not link" in low or "lld-link: error" in low:
            seen["link"] = True
        if line.startswith("ERROR: ") or seen["error"]:
            seen["error"].append(line.rstrip())
    p.wait()
    if p.returncode == 0:
        return
    text = " ".join(seen["error"]).replace("ERROR: ", "", 1).strip() or f"build_game.py: code {p.returncode}"
    step = seen["step"]
    if seen["disk"]:
        raise Problem("E22", "disque plein: libere de la place et relance")
    if step == 9:
        if seen["oom"]:
            raise Problem("E60", "le compilateur a manque de memoire", exit_code=3)
        if seen["link"]:
            raise Problem("E61", "l'edition de liens a echoue (voir le log)")
    raise Problem(STEP_CODES.get(step, "E59"), f"etape {step}/9: {text}")


def cmd_unlock(a):
    """tools/unlock_all.py on the WindowSmash folder's save (13.0.5's layout is the tool's own)."""
    tools(a.repo)
    os.chdir(a.repo)
    import unlock_all
    save = os.path.join(a.repo, unlock_all.SAVE)
    if not os.path.exists(save):
        raise Problem("E80", "pas encore de sauvegarde: lance le jeu une fois jusqu'au menu, ferme-le, puis recommence")
    sys.argv = ["unlock_all.py"] + (["--dry-run"] if a.dry_run else [])
    try:
        unlock_all.main()
    except SystemExit as e:
        if e.code not in (None, 0):
            raise Problem("E80", str(e.code))


def cmd_shaders(a):
    """tools/shader_aot.py on the WindowSmash folder: every shader of data.arc compiled ahead of time into its cache,
    so that a first use loads it instead of compiling it during play (the FPS drops of a first match)."""
    tools(a.repo)
    cmd = [sys.executable, "-u", os.path.join(a.repo, "tools", "shader_aot.py"), "--jobs", str(a.jobs)]
    env = dict(os.environ, PYTHONUNBUFFERED="1", PYTHONIOENCODING="utf-8")
    p = subprocess.Popen(cmd, cwd=a.repo, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
                         encoding="utf-8", errors="replace", bufsize=1)
    for line in p.stdout:
        sys.stdout.write(line)
    p.wait()
    if p.returncode:
        raise Problem("E85", f"la precompilation des shaders s'est arretee (code {p.returncode})")


def cmd_status(a):
    tree = a.repo
    st = {"folder": tree, "old_version_folders": [d for d in os.listdir(tree) if re.fullmatch(r"v\d+(\.\d+)*", d)]}
    p = os.path.join(tree, "dump", "game_source.txt")
    if os.path.exists(p):
        st["game_source"] = open(p, encoding="utf-8", errors="replace").readline().strip()
    for rel in ("dump/exefs/main", "dump/modules/romfs.cfg", "dump/modules/romfs_patch.bin", "build/ssbu.exe", "version.txt",
                PLAIN_BASE.replace(os.sep, "/")):
        f = os.path.join(tree, rel)
        st[rel] = os.path.getsize(f) if os.path.exists(f) else None
    nro = os.path.join(tree, "dump", "nro")
    st["nro_modules"] = len([f for f in os.listdir(nro) if f.endswith(".nro")]) if os.path.isdir(nro) else 0
    fonts = os.path.join(tree, "dump", "fonts")
    st["fonts"] = sorted(os.listdir(fonts)) if os.path.isdir(fonts) else []
    unv = os.path.join(tree, "dump", "modules", "romfs.unverified.txt")
    st["romfs_unverified"] = os.path.exists(unv)
    if os.path.exists(os.path.join(tree, "version.txt")):
        st["version"] = open(os.path.join(tree, "version.txt"), encoding="utf-8").read().splitlines()[:4]
    out("JSON", json.dumps(st))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", default=os.environ.get("WS_REPO", "."))
    ap.add_argument("--log")
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("probe")
    p = sub.add_parser("keys")
    p.add_argument("--keys", required=True)
    p = sub.add_parser("identify")
    p.add_argument("file")
    p.add_argument("--keys", required=True)
    p.add_argument("--role", choices=["base", "update"], required=True)
    p.add_argument("--expect")
    p = sub.add_parser("plain-nca")
    p.add_argument("base")
    p.add_argument("out")
    p.add_argument("--keys", required=True)
    p = sub.add_parser("fonts")
    p.add_argument("source")
    p.add_argument("outdir")
    p.add_argument("--keys", required=True)
    p = sub.add_parser("install")
    p.add_argument("--update", required=True)
    p.add_argument("--keys", required=True)
    p.add_argument("--jobs", type=int, required=True)
    p.add_argument("--dlc")
    p.add_argument("--no-build", action="store_true")
    sub.add_parser("status")
    p = sub.add_parser("unlock")
    p.add_argument("--dry-run", action="store_true")
    p = sub.add_parser("shaders")
    p.add_argument("--jobs", type=int, default=6)
    a = ap.parse_args()
    a.repo = os.path.abspath(a.repo)
    sys.stderr = sys.stdout                     # one stream: the caller reads it, the log keeps it
    if a.log:
        os.makedirs(os.path.dirname(os.path.abspath(a.log)), exist_ok=True)
        sys.stdout = sys.stderr = Tee(sys.__stdout__, a.log)
    run = {"probe": cmd_probe, "keys": cmd_keys, "identify": cmd_identify, "plain-nca": cmd_plain_nca,
           "fonts": cmd_fonts, "install": cmd_install, "status": cmd_status, "unlock": cmd_unlock,
           "shaders": cmd_shaders}[a.cmd]
    try:
        run(a)
    except Problem as p:
        out("ERROR", f"{p.code} {p.text}")
        sys.stdout.flush()
        sys.exit(p.exit_code)
    except SystemExit:
        raise
    except BaseException as e:   # noqa: BLE001 - anything else: the traceback goes to the report
        traceback.print_exc(file=sys.stdout)
        out("ERROR", f"E59 erreur interne ({type(e).__name__}: {e})")
        sys.stdout.flush()
        sys.exit(2)


if __name__ == "__main__":
    main()
