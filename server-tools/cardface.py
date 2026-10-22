#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""自定义卡面：把任意 PNG 换成游戏里的卡面/图标纹理。

链路（全部已验证，不依赖 apktool、不重签 APK）：

    服务端 archives (*.zip)
      └ assets/image/units/tx_<kind>_<unit_id>.texb   ← honoka v4 加密
            ↓ sifcrypt 解密
          TEXB 明文（RGB565 + zlib，尺寸随资源而定）
            ↓ texb.rebuild 换像素
          新明文 texb
            ↓ sifcrypt 加密（保留原文件 4..16 字节头，逐字节可复现）
          新 texb

落地有两种：
  * `push`   —— adb push 到客户端 `files/install/assets/image/units/`（快，立刻生效）
  * `server` —— 就地改写服务端 archives 里的条目（备份后可回滚），适合"重新下载也生效"

用法：
    python cardface.py list   --unit 11011001
    python cardface.py extract --unit 11011001 --out-dir out
    python cardface.py build  --unit 11011001 --png my.png --out-dir out [--kind icon]
    python cardface.py server --unit 11011001 --png my.png [--kind icon] [--yes]
    python cardface.py push   --unit 11011001 --png my.png [--kind icon] [--adb ...]
    python cardface.py restore --unit 11011001

`--kind` 取值：icon / rankup_icon / card / rankup_card / navi / 全部（默认全部）。
"""

from __future__ import annotations

import argparse
import glob
import io
import json
import os
import re
import shutil
import subprocess
import sys
import time
import zipfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sifcrypt  # noqa: E402
import texb  # noqa: E402

ROOT = r"d:\LLSIFLocal"
SERVER_ROOT = os.path.join(ROOT, "honoka-chan-dev")
ARCHIVES = os.path.join(SERVER_ROOT, "static", "Android", "archives")
BACKUP_DIR = os.path.join(SERVER_ROOT, "assets", "cardface_backups")
CACHE = os.path.join(SERVER_ROOT, "temp", "cardface_index.json")
ADB = os.path.join(ROOT, "android-sdk", "platform-tools", "adb.exe")
PKG = "klb.android.lovelivecn"
INSTALL_UNITS = "files/install/assets/image/units"

UNIT_TEXB = re.compile(r"^assets/image/units/(tx_(?P<kind>.+?)_(?P<unit>\d+)(?P<signed>_signed)?)\.texb$")


def kinds_for(kind_filter: list[str] | None) -> list[str] | None:
    """不加 --kind 时匹配全部层（u_normal_icon / u_rankup_card / b_normal …）。"""
    return kind_filter or None


class Index:
    """unit_id + kind → (archive_path, entry) 的索引。

    全量扫 9260 个 zip 的中央目录约 10 秒，可接受；有缓存时直接读。
    """

    def __init__(self, use_cache: bool = True):
        self.rows: list[dict] = []
        if use_cache and os.path.exists(CACHE):
            try:
                self.rows = json.load(open(CACHE, encoding="utf-8"))
                return
            except Exception:
                self.rows = []
        self.build()

    def build(self):
        t0 = time.time()
        files = sorted(glob.glob(os.path.join(ARCHIVES, "*.zip")))
        for f in files:
            try:
                with zipfile.ZipFile(f) as z:
                    for name in z.namelist():
                        m = UNIT_TEXB.match(name)
                        if not m:
                            continue
                        self.rows.append({
                            "archive": os.path.basename(f),
                            "entry": name,
                            "unit": int(m.group("unit")),
                            "kind": m.group("kind"),
                            "signed": bool(m.group("signed")),
                        })
            except Exception:
                continue
        os.makedirs(os.path.dirname(CACHE), exist_ok=True)
        json.dump(self.rows, open(CACHE, "w", encoding="utf-8"), ensure_ascii=False)
        print("[index] %d 条纹理，用时 %.1fs" % (len(self.rows), time.time() - t0), file=sys.stderr)

    def find(self, unit: int, kinds: list[str] | None = None) -> list[dict]:
        kf = kinds_for(kinds)
        return [r for r in self.rows
                if r["unit"] == unit and (kf is None or r["kind"] in kf)]

    def units(self) -> list[int]:
        return sorted({r["unit"] for r in self.rows})


class Rewriter:
    def __init__(self):
        self.crypt = sifcrypt.SifCrypt()

    # ---------------------------------------------------------------- 读
    def read_entry(self, archive: str, entry: str) -> bytes:
        with zipfile.ZipFile(os.path.join(ARCHIVES, archive)) as z:
            return z.read(entry)

    def extract_png(self, rec: dict, out_png: str) -> dict:
        enc = self.read_entry(rec["archive"], rec["entry"])
        plain = self.crypt.decrypt(enc, rec["entry"])
        info = texb.parse(plain)
        raw_zlib = plain[info["zlib_at"]:]
        info = texb.extract_png(plain, out_png)
        info["archive"] = rec["archive"]
        info["entry"] = rec["entry"]
        info["enc_size"] = len(enc)
        info["plain_size"] = len(plain)
        return info

    # ---------------------------------------------------------------- 写
    def build_entry(self, rec: dict, png_path: str) -> bytes:
        """按模板重建该条目，返回可直接写回 zip 的加密字节。"""
        from PIL import Image

        enc = self.read_entry(rec["archive"], rec["entry"])
        plain = self.crypt.decrypt(enc, rec["entry"])
        tmp_out = os.path.join(BACKUP_DIR, "_tmp.texb")
        os.makedirs(BACKUP_DIR, exist_ok=True)
        texb.rebuild(plain, Image.open(png_path), tmp_out)
        new_plain = open(tmp_out, "rb").read()
        os.remove(tmp_out)
        # 保留原文件头 4..16 字节 → 与原文件同族，客户端一定认
        return self.crypt.encrypt(new_plain, rec["entry"], header_template=enc[:16])

    def rewrite_archive(self, archive: str, replacements: dict[str, bytes]) -> str:
        """就地改写 zip 里的若干条目，返回备份路径。"""
        src = os.path.join(ARCHIVES, archive)
        os.makedirs(BACKUP_DIR, exist_ok=True)
        stamp = time.strftime("%Y%m%d-%H%M%S")
        bak = os.path.join(BACKUP_DIR, "%s.%s.bak" % (archive, stamp))
        if not os.path.exists(bak):
            shutil.copy2(src, bak)

        tmp = src + ".tmp"
        with zipfile.ZipFile(src) as zin, zipfile.ZipFile(tmp, "w") as zout:
            for info in zin.infolist():
                data = replacements.get(info.filename)
                if data is None:
                    data = zin.read(info.filename)
                zi = zipfile.ZipInfo(info.filename, date_time=info.date_time)
                zi.compress_type = info.compress_type
                zi.external_attr = info.external_attr
                zout.writestr(zi, data)
        os.replace(tmp, src)
        return bak

    # ---------------------------------------------------------------- 落地
    def push(self, rec: dict, data: bytes, adb: str = ADB) -> bool:
        name = os.path.basename(rec["entry"])
        tmp = os.path.join(BACKUP_DIR, "_push_" + name)
        os.makedirs(BACKUP_DIR, exist_ok=True)
        open(tmp, "wb").write(data)
        remote = "/data/local/tmp/_cf_" + name
        r = subprocess.run([adb, "push", tmp, remote], capture_output=True, text=True)
        if r.returncode != 0:
            print("  push 失败:", r.stderr.strip(), file=sys.stderr)
            return False
        # 设备上目录可能还不存在（客户端还没解出纹理），先 mkdir -p
        subprocess.run([adb, "shell", "run-as %s mkdir -p %s" % (PKG, INSTALL_UNITS)],
                       capture_output=True, text=True)
        cmd = ("cat %s | run-as %s sh -c 'cat > %s/%s'" % (remote, PKG, INSTALL_UNITS, name))
        r = subprocess.run([adb, "shell", cmd], capture_output=True, text=True)
        subprocess.run([adb, "shell", "rm -f " + remote], capture_output=True, text=True)
        os.remove(tmp)
        if r.returncode != 0:
            print("  写入设备失败:", r.stderr.strip(), file=sys.stderr)
            return False
        return True


# -------------------------------------------------------------------- 命令

def cmd_list(args):
    idx = Index(use_cache=not args.no_cache)
    rows = idx.find(args.unit)
    if not rows:
        print("unit %d 没有可替换的纹理（可用 unit 数：%d）" % (args.unit, len(idx.units())))
        return 1
    print("unit %d 共 %d 个纹理条目：" % (args.unit, len(rows)))
    w = Rewriter()
    for r in rows:
        enc = w.read_entry(r["archive"], r["entry"])
        try:
            info = texb.parse(w.crypt.decrypt(enc, r["entry"]))
            dims = "%dx%d" % (info["width"], info["height"])
        except Exception as e:
            dims = "解析失败(%s)" % e
        print("  %-8s %-46s %-12s %s" % (r["kind"] + ("_signed" if r["signed"] else ""),
                                         r["entry"].split("/")[-1], dims, r["archive"]))
    return 0


def cmd_extract(args):
    idx = Index(use_cache=not args.no_cache)
    rows = idx.find(args.unit, args.kind)
    if not rows:
        print("没有匹配的条目")
        return 1
    os.makedirs(args.out_dir, exist_ok=True)
    w = Rewriter()
    for r in rows:
        png = os.path.join(args.out_dir, "%s.png" % os.path.basename(r["entry"])[:-5])
        info = w.extract_png(r, png)
        print("  %-46s %dx%d -> %s" % (r["entry"].split("/")[-1], info["width"], info["height"], png))
    return 0


def cmd_build(args):
    idx = Index(use_cache=not args.no_cache)
    rows = idx.find(args.unit, args.kind)
    if not rows:
        print("没有匹配的条目")
        return 1
    os.makedirs(args.out_dir, exist_ok=True)
    w = Rewriter()
    for r in rows:
        data = w.build_entry(r, args.png)
        out = os.path.join(args.out_dir, os.path.basename(r["entry"]))
        open(out, "wb").write(data)
        # 自检：解回来再解一张 PNG，确认像素是新的
        plain = w.crypt.decrypt(data, r["entry"])
        chk = out + ".check.png"
        texb.extract_png(plain, chk)
        print("  %-46s -> %s (%d 字节) 自检 %s" %
              (r["entry"].split("/")[-1], out, len(data), chk))
    return 0


def cmd_server(args):
    idx = Index(use_cache=not args.no_cache)
    rows = idx.find(args.unit, args.kind)
    if not rows:
        print("没有匹配的条目")
        return 1
    print("将改写 %d 个条目（会先备份到 %s）" % (len(rows), BACKUP_DIR))
    if not args.yes:
        print("加 --yes 才会真正写入")
        return 2
    w = Rewriter()
    by_archive: dict[str, dict[str, bytes]] = {}
    for r in rows:
        by_archive.setdefault(r["archive"], {})[r["entry"]] = w.build_entry(r, args.png)
    for archive, repl in by_archive.items():
        bak = w.rewrite_archive(archive, repl)
        print("  %-16s 替换 %d 条，备份 %s" % (archive, len(repl), os.path.basename(bak)))
    return 0


def cmd_push(args):
    idx = Index(use_cache=not args.no_cache)
    rows = idx.find(args.unit, args.kind)
    if not rows:
        print("没有匹配的条目")
        return 1
    w = Rewriter()
    ok = 0
    for r in rows:
        data = w.build_entry(r, args.png)
        name = os.path.basename(r["entry"])
        if w.push(r, data, args.adb):
            print("  -> %s/%s" % (INSTALL_UNITS, name))
            ok += 1
    print("成功 %d / %d" % (ok, len(rows)))
    print("提示：重启游戏（或清客户端缓存）后生效。")
    return 0 if ok == len(rows) else 1


def cmd_restore(args):
    idx = Index(use_cache=False)
    rows = idx.find(args.unit)
    archives = {r["archive"] for r in rows}
    names = set()
    if os.path.isdir(BACKUP_DIR):
        names = {n.split(".")[0] + ".zip" for n in os.listdir(BACKUP_DIR) if n.endswith(".bak")}
    targets = sorted(archives & names) if archives else sorted(names)
    if not targets:
        print("没有可恢复的备份")
        return 1
    for archive in targets:
        baks = sorted(glob.glob(os.path.join(BACKUP_DIR, archive + ".*.bak")), reverse=True)
        if not baks:
            continue
        shutil.copy2(baks[0], os.path.join(ARCHIVES, archive))
        print("  已恢复 %s <- %s" % (archive, os.path.basename(baks[0])))
    return 0


def main(argv):
    ap = argparse.ArgumentParser(description="LLSIF 自定义卡面工具")
    ap.add_argument("--no-cache", action="store_true", help="忽略索引缓存重新扫描")
    sub = ap.add_subparsers(dest="cmd", required=True)

    def add(name, fn, help_text):
        p = sub.add_parser(name, help=help_text)
        p.add_argument("--unit", type=int, required=True)
        p.add_argument("--kind", action="append", help="只处理某类（可重复）")
        p.set_defaults(func=fn)
        return p

    add("list", cmd_list, "列出可替换的纹理")
    p = add("extract", cmd_extract, "导出为 PNG")
    p.add_argument("--out-dir", default=os.path.join(SERVER_ROOT, "temp", "cardface_out"))

    p = add("build", cmd_build, "用 PNG 生成新的加密 texb（不落地）")
    p.add_argument("--png", required=True)
    p.add_argument("--out-dir", default=os.path.join(SERVER_ROOT, "temp", "cardface_out"))

    p = add("server", cmd_server, "就地改写服务端 archives（先备份）")
    p.add_argument("--png", required=True)
    p.add_argument("--yes", action="store_true")

    p = add("push", cmd_push, "直接推到已连接的客户端")
    p.add_argument("--png", required=True)
    p.add_argument("--adb", default=ADB)

    p = add("restore", cmd_restore, "从备份恢复 archives")

    args = ap.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
