#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""LLSIF CN `.texb` 纹理容器的读写工具。

用途：把客户端里的卡面/封面纹理导出成 PNG 看清内容，或把自定义 PNG
重新封装成 `.texb`（再加密、替换进 AppAssets.zip）以导入第三方卡面。

容器结构（已用真实样本 tx_u_normal_icon_11011001.texb 验证）：

    TEXB | u32BE 数据区长度 | u16BE 名称长度 | 名称
         | u16BE x6（宽, 高, …）
         | TIMG | u16BE … | u16BE 名称长度 | 名称（指向同名 .png.imag）
         | 96 字节 IMG 头
         | zlib 流（0x78 0x9C …）

实测该资源为 128x128、zlib 解压后 32768 字节 = 128*128*2，即 RGB565 小端、
无 Alpha、无 mipmap。

注意：`.texb` 在 SIF CN 里是 honoka v4 加密的，本工具只处理**已解密**的明文；
加解密请用 libhonoka 的 honoka2.exe：

    honoka2.exe -b <真实文件名> <加密文件> <明文输出>       # 解密
    honoka2.exe -e -c -b <真实文件名> <明文> <加密输出>      # 加密
"""

from __future__ import annotations

import argparse
import os
import struct
import zlib

ZLIB_MAGIC = b"\x78\x9c"
# zlib 头第二字节随压缩级别变化（0x01/0x5E/0x9C/0xDA），不能只认 0x789C。
ZLIB_CMF = 0x78
IMG_HEADER_LEN = 96


class TexbError(Exception):
    pass


def _find_zlib(data: bytes, start: int) -> int:
    """定位 zlib 流起点。

    实测样本里 zlib 紧跟在 body_at + 96 字节 IMG 头之后，优先按该偏移取；
    取不到再退回按 CMF 字节扫描，兼容 IMG 头长度不同的资源。
    """
    candidate = start + IMG_HEADER_LEN
    if candidate + 1 < len(data) and data[candidate] == ZLIB_CMF:
        return candidate

    for pos in range(start, len(data) - 1):
        if data[pos] == ZLIB_CMF:
            return pos
    raise TexbError("找不到 zlib 数据流，可能不是 texb 或未解密")


def parse(data: bytes) -> dict:
    """解析明文 texb，返回尺寸与各段偏移。"""
    if data[:4] != b"TEXB":
        raise TexbError("magic 不是 TEXB，文件可能仍处于加密状态")

    payload_len = struct.unpack_from(">I", data, 4)[0]
    name_len = struct.unpack_from(">H", data, 8)[0]
    name = data[10 : 10 + name_len].decode("latin1")
    pos = 10 + name_len

    dims = [struct.unpack_from(">H", data, pos + 2 * i)[0] for i in range(6)]
    pos += 12

    if data[pos : pos + 4] != b"TIMG":
        raise TexbError("缺少 TIMG 子块")
    timg_at = pos
    timg_field = struct.unpack_from(">H", data, pos + 4)[0]
    inner_name_len = struct.unpack_from(">H", data, pos + 6)[0]
    inner_name = data[pos + 8 : pos + 8 + inner_name_len].decode("latin1")
    body_at = pos + 8 + inner_name_len

    zlib_at = _find_zlib(data, body_at)
    return {
        "payload_len": payload_len,
        "name": name,
        "dims": dims,
        "width": dims[0],
        "height": dims[1],
        "timg_at": timg_at,
        "timg_field": timg_field,
        "inner_name": inner_name,
        "body_at": body_at,
        "img_header": data[body_at:body_at + IMG_HEADER_LEN],
        "zlib_at": zlib_at,
        "zlib_len": len(data) - zlib_at,
    }


def decode_rgb565(raw: bytes, width: int, height: int):
    """把 RGB565 小端字节解成 (r,g,b) 元组列表。"""
    from PIL import Image

    need = width * height * 2
    if len(raw) < need:
        raise TexbError(f"像素数据不足：需要 {need} 字节，实际 {len(raw)}")

    img = Image.new("RGB", (width, height))
    px = img.load()
    for y in range(height):
        row = y * width
        for x in range(width):
            v = struct.unpack_from("<H", raw, (row + x) * 2)[0]
            r = ((v >> 11) & 0x1F) * 255 // 31
            g = ((v >> 5) & 0x3F) * 255 // 63
            b = (v & 0x1F) * 255 // 31
            px[x, y] = (r, g, b)
    return img


def to_rgb565(img) -> bytes:
    """把 PIL 图片转成 RGB565 小端字节串。

    量化用「解码的逆映射」ceil(c*31/255)，这样 decode -> encode 能逐像素还原；
    若改用四舍五入会让往返结果在低比特上有 ±9 的漂移。
    """
    img = img.convert("RGB")
    width, height = img.size
    out = bytearray(width * height * 2)
    px = img.load()
    for y in range(height):
        for x in range(width):
            r, g, b = px[x, y]
            r5 = (r * 31 + 254) // 255
            g6 = (g * 63 + 254) // 255
            b5 = (b * 31 + 254) // 255
            v = (r5 << 11) | (g6 << 5) | b5
            struct.pack_into("<H", out, (y * width + x) * 2, v)
    return bytes(out)


def extract_png(plain_texb: bytes, out_png: str) -> dict:
    """解出 texb 内的位图并保存为 PNG。"""
    info = parse(plain_texb)
    raw = zlib.decompress(plain_texb[info["zlib_at"] :])
    img = decode_rgb565(raw, info["width"], info["height"])
    img.save(out_png)

    expected = info["width"] * info["height"] * 2
    info.update(
        decompressed_len=len(raw),
        expected_rgb565=expected,
        exact_match=len(raw) == expected,
        out_png=out_png,
    )
    return info


def rebuild(template_plain: bytes, img, out_plain_texb: str) -> dict:
    """用 template 的头部结构，把新图封装成明文 texb。

    尺寸沿用模板（卡面图标位是固定尺寸，改尺寸客户端不会重新排布）。
    """
    info = parse(template_plain)
    width, height = info["width"], info["height"]

    if img.size != (width, height):
        img = img.resize((width, height))

    raw = to_rgb565(img)
    packed = zlib.compress(raw, 9)

    header = bytearray(template_plain[: info["zlib_at"]])
    # 数据区长度 = 原长度 - 原 zlib 长度 + 新 zlib 长度
    new_payload = info["payload_len"] - info["zlib_len"] + len(packed)
    struct.pack_into(">I", header, 4, new_payload)

    with open(out_plain_texb, "wb") as f:
        f.write(bytes(header))
        f.write(packed)

    return {
        "width": width,
        "height": height,
        "out": out_plain_texb,
        "new_payload": new_payload,
        "zlib_len": len(packed),
        "file_size": len(header) + len(packed),
    }


def main() -> int:
    ap = argparse.ArgumentParser(description="LLSIF CN texb 读写工具")
    sub = ap.add_subparsers(dest="cmd", required=True)

    d = sub.add_parser("decode", help="明文 texb -> PNG")
    d.add_argument("texb")
    d.add_argument("png")

    e = sub.add_parser("encode", help="PNG -> 明文 texb（用模板头部结构）")
    e.add_argument("png")
    e.add_argument("--template", required=True, help="同尺寸的现有明文 texb")
    e.add_argument("--out", required=True)

    i = sub.add_parser("info", help="打印容器信息")
    i.add_argument("texb")

    args = ap.parse_args()

    if args.cmd == "decode":
        with open(args.texb, "rb") as f:
            data = f.read()
        info = extract_png(data, args.png)
        print(f"{info['name']}")
        print(f"  尺寸      : {info['width']}x{info['height']}")
        print(f"  解压字节  : {info['decompressed_len']} (期望 {info['expected_rgb565']})")
        print(f"  RGB565 匹配: {info['exact_match']}")
        print(f"  内层资源  : {info['inner_name']}")
        print(f"  输出      : {info['out_png']}")
        if not info["exact_match"]:
            print("  警告: 数据长度不是 宽*高*2，可能不是纯 RGB565（或含 mipmap）")
        return 0

    if args.cmd == "encode":
        from PIL import Image

        with open(args.template, "rb") as f:
            template = f.read()
        result = rebuild(template, Image.open(args.png), args.out)
        print(f"已写出 {result['out']}")
        print(f"  尺寸    : {result['width']}x{result['height']}")
        print(f"  zlib 长 : {result['zlib_len']}")
        print(f"  文件大小: {result['file_size']}")
        return 0

    with open(args.texb, "rb") as f:
        data = f.read()
    info = parse(data)
    print(f"name       : {info['name']}")
    print(f"inner      : {info['inner_name']}")
    print(f"dims(u16x6): {info['dims']}")
    print(f"payload    : {info['payload_len']}  文件 {len(data)}")
    print(f"IMG 头     : {info['img_header'].hex()}")
    raw = zlib.decompress(data[info["zlib_at"] :])
    print(f"解压       : {len(raw)} 字节 (宽*高*2 = {info['width'] * info['height'] * 2})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
