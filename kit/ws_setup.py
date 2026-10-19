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
  install   --tree T --update NSP --keys DIR --jobs N [--dlc DIR] [--no-build]
                                            tools/install_version.py install, with the fix below
  status    --tree T                        the version folder's state, for the report
  unlock    --tree T [--dry-run]            every fighter unlocked in the save (tools/unlock_all.py, 13.0.4 added)
  shaders   --tree T [--jobs N]             the game's shaders compiled ahead of time (tools/shader_aot.py)

Lines for ws_setup.ps1: "@@JSON {...}", "@@WARN <code> <text>", "@@ERROR <code> <text>" (then exit 2; exit 3 is
"the compiler ran out of memory": the caller retries with fewer jobs). Key values are never printed.

The fix: WindowSmash's update.py (branch multi-version, commit 5682805) reads the update's hash table (IVFC level 5)
from the patch alone. In the 13.0.4 update part of that table is original-release data, so Patch() fails with
"bytes at 0x20080 come from the original release". Here the Patch starts without the table, and the table is read,
before the RomFS step, with the base's bytes taken from the plain base NCA - the bytes the exact patch path uses.
"""
import argparse
import json
import os
import struct
import subprocess
import sys
import time
import traceback
import types

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


def cmd_install(a):
    tools(a.repo)
    os.chdir(a.repo)
    os.environ["PYTHONUNBUFFERED"] = "1"
    import install_version
    import update

    init = update.Patch.__init__

    def patch_init(self, nsp, keydir):
        try:
            init(self, nsp, keydir)
        except LookupError as e:
            print(f"update: table de hachage en partie dans le jeu de base ({e}); lue depuis la base", flush=True)
            self.hashes = None
            levels = [struct.unpack_from("<QQI", self.sec.fs_header[0x08:0x100], 0x10 + i * 0x18) for i in range(6)]
            self.hash_at = levels[4][0]
            self.l6, self.l6size, blocklog = levels[5]
            self.block = 1 << blocklog
            self.blocks = (self.l6size + self.block - 1) // self.block

    apply_romfs = update.apply_romfs

    def patched_apply_romfs(patch, base_cfg, keydir, tree):
        if getattr(patch, "hashes", True) is None:
            b = update.Builder(patch, base_cfg, keydir)
            start = b.base_section()
            if start is None:
                raise Problem("E51", "la table de hachage de l'update a besoin du jeu de base ORIGINAL (1.0.0) en NCA "
                                     "dechiffre: le jeu de base fourni n'est pas celui-la")
            patch.hashes = patch.vread(patch.hash_at, patch.blocks * 32, lambda ph, n: b.base_read(start + ph, n))
            print(f"update: table de hachage lue ({patch.blocks:,} blocs)", flush=True)
        return apply_romfs(patch, base_cfg, keydir, tree)

    update.Patch.__init__ = patch_init
    update.apply_romfs = patched_apply_romfs

    seen = {"oom": False, "link": False, "disk": False}

    def tee_run(cmd, **kw):
        p = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, encoding="utf-8",
                             errors="replace", bufsize=1)
        for line in p.stdout:
            sys.stdout.write(line)
            low = line.lower()
            if any(m in low for m in OOM_MARKS):
                seen["oom"] = True
            if any(m in low for m in DISK_MARKS):
                seen["disk"] = True
            if "link failed" in low or "could not link" in low or "lld-link: error" in low:
                seen["link"] = True
        p.wait()
        return subprocess.CompletedProcess(cmd, p.returncode)

    install_version.subprocess = types.SimpleNamespace(run=tee_run)
    argv = ["install", "--tree", a.tree, "--update", a.update, "--keys", a.keys, "--jobs", str(a.jobs), "--force"]
    if a.dlc:
        argv += ["--dlc", a.dlc]
    if a.no_build:
        argv.append("--no-build")
    sys.argv = [os.path.join(a.repo, "tools", "install_version.py")] + argv
    step = lambda: getattr(sys.stdout, "last_step", None) or "?"  # noqa: E731
    try:
        install_version.main()
    except SystemExit as e:
        if e.code in (None, 0):
            return
        text = str(e.code)
        if "build failed" in text:
            if seen["disk"]:
                raise Problem("E22", "disque plein pendant la compilation: libere de la place et relance")
            if seen["oom"]:
                raise Problem("E60", "le compilateur a manque de memoire", exit_code=3)
            if seen["link"]:
                raise Problem("E61", "l'edition de liens a echoue (voir le log)")
            raise Problem("E60", "la compilation a echoue (voir le log)")
        code = {"exefs": "E51", "romfs": "E51", "aoc": "E53", "nro": "E52", "extras": "E53", "version": "E53"}.get(step(), "E59")
        raise Problem(code, f"etape [{step()}]: {text}")
    except MemoryError:
        raise Problem("E60", "Python a manque de memoire", exit_code=3)


def cmd_unlock(a):
    """tools/unlock_all.py on the version folder, with 13.0.4 added to the save layouts it knows.

    unlock_all.py (commit 5682805) knows 11.0.0 and 13.0.5, which share one save layout, and refuses 13.0.4. A 13.0.4
    save checked on 2026-10-18 has the same size (0x5B4AF8), the same save format (0x1b at offset 4; 0xd004 at offset
    8, the version that wrote it), the eight starters exactly at the FLAGS offsets and valid milestones: the tool's own
    checks pass, and they run here again on every save before anything is written."""
    tools(a.repo)
    os.chdir(a.repo)
    import unlock_all
    unlock_all.LAYOUTS.setdefault("3EAE0063B12FD81E99FB5980BA56297049EA94F9", ("13.0.4", 0x5B4AF8, 0x53FF40, 0x54FEA8))
    save = os.path.join(a.repo, a.tree, unlock_all.SAVE)
    if not os.path.exists(save):
        raise Problem("E80", "pas encore de sauvegarde: lance le jeu une fois jusqu'au menu, ferme-le, puis recommence")
    sys.argv = ["unlock_all.py", "--tree", os.path.join(a.repo, a.tree)] + (["--dry-run"] if a.dry_run else [])
    try:
        unlock_all.main()
    except SystemExit as e:
        if e.code not in (None, 0):
            raise Problem("E80", str(e.code))


def cmd_shaders(a):
    """tools/shader_aot.py on the version folder: every shader of data.arc compiled ahead of time into its cache, so
    that a first use loads it instead of compiling it during play (the FPS drops of a first match).

    shader_aot.py (commit adfb154) builds its compiler tool as <port>/build/shaderaot.exe and runs the compiler with
    that folder as working directory; with only a version folder built, <port>/build does not exist and it stops with
    "NotADirectoryError [WinError 267]". The folder is made here first (it is ignored by git, and holds no ssbu.exe,
    so the launchers do not list it as a version)."""
    tools(a.repo)
    os.makedirs(os.path.join(a.repo, "build"), exist_ok=True)
    cmd = [sys.executable, "-u", os.path.join(a.repo, "tools", "shader_aot.py"), "--tree", os.path.join(a.repo, a.tree),
           "--jobs", str(a.jobs)]
    env = dict(os.environ, PYTHONUNBUFFERED="1")
    p = subprocess.Popen(cmd, cwd=a.repo, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
                         encoding="utf-8", errors="replace", bufsize=1)
    for line in p.stdout:
        sys.stdout.write(line)
    p.wait()
    if p.returncode:
        raise Problem("E85", f"la precompilation des shaders s'est arretee (code {p.returncode})")


def cmd_status(a):
    tree = os.path.join(a.repo, a.tree)
    st = {"tree": tree, "exists": os.path.isdir(tree)}
    p = os.path.join(tree, "install.json")
    if os.path.exists(p):
        try:
            st["install_steps"] = sorted(json.load(open(p)).keys())
        except ValueError:
            st["install_steps"] = "illisible"
    for rel in ("dump/exefs/main", "dump/modules/romfs.cfg", "dump/modules/romfs_patch.bin", "build/ssbu.exe", "version.txt"):
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
    p.add_argument("--tree", required=True)
    p.add_argument("--update", required=True)
    p.add_argument("--keys", required=True)
    p.add_argument("--jobs", type=int, required=True)
    p.add_argument("--dlc")
    p.add_argument("--no-build", action="store_true")
    p = sub.add_parser("status")
    p.add_argument("--tree", required=True)
    p = sub.add_parser("unlock")
    p.add_argument("--tree", required=True)
    p.add_argument("--dry-run", action="store_true")
    p = sub.add_parser("shaders")
    p.add_argument("--tree", required=True)
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
