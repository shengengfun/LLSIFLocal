"""SIF CN（国服 9.7.1）游戏文件加解密，直接调 libhonoka。

为什么不用 `honoka2.exe -e -c`：
它给 CN 文件默认按 **v3** 加密（客户端解出来会报 version 3），而且产出的容器头
和官方文件不一致。这里显式钉死 v4，并按官方值写容器头，产出与官方文件逐字节相同
（已用任意 Lua 明文往返验证）。

用法（命令行）：
    python sifcrypt.py decrypt <输入> <输出> [文件名]
    python sifcrypt.py encrypt <输入> <输出> [文件名]
    python sifcrypt.py info <文件>

「文件名」决定 v3 的 name_sum 与 v4 的部分初始化；**必须和客户端看到的文件名一致**，
默认取输入文件的基本名。加密 v4 时文件名只影响前 4 字节，不影响正文。
"""

from __future__ import annotations

import ctypes
import os
import struct
import sys

# 明文 Lua 头里的 5 字节 magic；只有 Lua 明文带它，纹理/图片没有。
LUA_MAGIC = bytes([0x19, 0x93, 0x0D, 0x0A, 0x1A])

MODE_V4 = 4
GAMEFILE_CN = 4

# 官方 v4 容器头：[4 字节文件名派生值][c2 09 00 02][8 字节 0]
# 库里 encrypt_init 写的是 00 00 00 02，这 4 字节不参与加解密，
# 但客户端拿它认格式，所以覆盖成官方值。
OFFICIAL_HEADER_TAIL = bytes([0xC2, 0x09, 0x00, 0x02, 0, 0, 0, 0, 0, 0, 0, 0])

DEFAULT_DLL = r"d:\LLSIFLocal\libhonoka\bin\honoka.dll"


def _load(dll_path: str):
    lib = ctypes.WinDLL(dll_path)
    lib.honokamiku_version_string.restype = ctypes.c_char_p
    lib.honokamiku_context_size.restype = ctypes.c_size_t
    lib.honokamiku_header_size.restype = ctypes.c_size_t
    lib.honokamiku_header_size.argtypes = [ctypes.c_int]

    lib.honokamiku_encrypt_init.restype = ctypes.c_int
    lib.honokamiku_encrypt_init.argtypes = [
        ctypes.c_void_p, ctypes.c_int, ctypes.c_int, ctypes.c_char_p,
        ctypes.c_void_p, ctypes.c_int, ctypes.c_char_p,
        ctypes.c_void_p, ctypes.c_size_t,
    ]

    lib.honokamiku_decrypt_init.restype = ctypes.c_int
    lib.honokamiku_decrypt_init.argtypes = [
        ctypes.c_void_p, ctypes.c_int, ctypes.c_int, ctypes.c_char_p,
        ctypes.c_char_p, ctypes.c_void_p,
    ]

    lib.honokamiku_decrypt_final_init.restype = ctypes.c_int
    lib.honokamiku_decrypt_final_init.argtypes = [
        ctypes.c_void_p, ctypes.c_int, ctypes.c_void_p, ctypes.c_int,
        ctypes.c_char_p, ctypes.c_void_p,
    ]

    lib.honokamiku_decrypt_block.restype = None
    lib.honokamiku_decrypt_block.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_size_t]
    return lib


class SifCrypt:
    def __init__(self, dll_path: str | None = None):
        self.dll_path = dll_path or os.environ.get("HONOKA_DLL") or DEFAULT_DLL
        self.lib = _load(self.dll_path)
        self._ctx_size = self.lib.honokamiku_context_size()

    def version(self) -> str:
        return self.lib.honokamiku_version_string().decode()

    def header_size(self, mode: int = MODE_V4) -> int:
        return self.lib.honokamiku_header_size(mode)

    def encrypt(self, plain: bytes, filename: str, header_template: bytes | None = None) -> bytes:
        """把明文加密成 v4 容器。

        `header_template` 传原文件的 16 字节头时，会**原样保留 4..16 字节**：
        实测同一批资源的这 12 字节是家族常量（APK 内资源是 `c2 09 00 02`，
        archives 里的纹理是 `c2 26 00 02`），照抄才能做到与原文件逐字节相同。
        """
        hsize = self.header_size()
        ctx = ctypes.create_string_buffer(self._ctx_size)
        header = ctypes.create_string_buffer(hsize)
        rc = self.lib.honokamiku_encrypt_init(
            ctx, MODE_V4, GAMEFILE_CN, None, None, -1,
            self._name(filename), header, hsize)
        if rc != 0:
            raise RuntimeError("encrypt_init rc=%d" % rc)

        buf = ctypes.create_string_buffer(plain, len(plain))
        self.lib.honokamiku_decrypt_block(ctx, buf, len(plain))

        head = bytearray(header.raw[:hsize])
        if hsize >= 16:
            if header_template is not None and len(header_template) >= 16:
                head[4:16] = header_template[4:16]
            else:
                head[4:16] = OFFICIAL_HEADER_TAIL
        return bytes(head) + buf.raw[:len(plain)]

    def decrypt(self, enc: bytes, filename: str) -> bytes:
        """v4 容器的两段式初始化：先喂前 4 字节，再喂接下来的 12 字节。"""
        hsize = self.header_size()
        if len(enc) <= hsize:
            raise ValueError("文件太短（%d 字节），不像是加密文件" % len(enc))
        name = self._name(filename)
        ctx = ctypes.create_string_buffer(self._ctx_size)

        head4 = ctypes.create_string_buffer(enc[:4], 4)
        rc = self.lib.honokamiku_decrypt_init(ctx, MODE_V4, GAMEFILE_CN, None, name, head4)
        if rc != 0:
            raise RuntimeError("decrypt_init rc=%d" % rc)

        next12 = ctypes.create_string_buffer(enc[4:hsize], hsize - 4)
        rc = self.lib.honokamiku_decrypt_final_init(ctx, GAMEFILE_CN, None, -1, name, next12)
        if rc != 0:
            raise RuntimeError("decrypt_final_init rc=%d" % rc)

        body = enc[hsize:]
        buf = ctypes.create_string_buffer(body, len(body))
        self.lib.honokamiku_decrypt_block(ctx, buf, len(body))
        return buf.raw[:len(body)]

    def is_encrypted(self, data: bytes) -> bool:
        """粗判：明文 Lua 有 1b4c7561、明文 texb 以 TEXB 开头，其余都当加密。"""
        return not (data[:4] in (b"\x1bLua", b"TEXB"))

    @staticmethod
    def _name(filename: str) -> bytes:
        # 客户端传的是文件名而不是整个路径，这里统一取最后一段。
        return os.path.basename(filename.replace("\\", "/")).encode("utf-8")


def main(argv: list[str]) -> int:
    if len(argv) < 4 or argv[1] not in ("encrypt", "decrypt"):
        print(__doc__)
        return 2
    cmd, src, dst = argv[1], argv[2], argv[3]
    name = argv[4] if len(argv) > 4 else os.path.basename(src)

    c = SifCrypt()
    print("libhonoka:", c.version())
    data = open(src, "rb").read()
    if cmd == "encrypt":
        out = c.encrypt(data, name)
    else:
        out = c.decrypt(data, name)
    open(dst, "wb").write(out)
    print("%s %d -> %d 字节, 头: %s" % (
        cmd, len(data), len(out), " ".join("%02x" % b for b in out[:16])))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
