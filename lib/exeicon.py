#!/usr/bin/env python3
"""Extract the largest icon from a Windows PE (.exe) and save it as PNG.

usage: exeicon.py FILE.exe OUT.png [SIZE]
Pure python (struct) for the PE resource walk; Pillow for decoding.
"""
import io
import struct
import sys

RT_ICON, RT_GROUP_ICON = 3, 14


def rva_to_off(sections, rva):
    for va, vsize, raw, rsize in sections:
        if va <= rva < va + max(vsize, rsize):
            return rva - va + raw
    raise ValueError("rva not in a section")


def read_resources(data):
    pe = struct.unpack_from("<I", data, 0x3C)[0]
    assert data[pe:pe + 4] == b"PE\0\0"
    nsec, = struct.unpack_from("<H", data, pe + 6)
    optsize, = struct.unpack_from("<H", data, pe + 20)
    opt = pe + 24
    magic, = struct.unpack_from("<H", data, opt)
    dd = opt + (96 if magic == 0x10B else 112)
    res_rva, _ = struct.unpack_from("<II", data, dd + 2 * 8)
    sections = []
    so = opt + optsize
    for i in range(nsec):
        vsize, va, rsize, raw = struct.unpack_from("<IIII", data, so + i * 40 + 8)
        sections.append((va, vsize, raw, rsize))
    base = rva_to_off(sections, res_rva)

    def directory(off):
        named, ids = struct.unpack_from("<HH", data, off + 12)
        for i in range(named + ids):
            name, ptr = struct.unpack_from("<II", data, off + 16 + i * 8)
            yield name, ptr

    res = {}
    for typ, p1 in directory(base):
        if not p1 & 0x80000000:
            continue
        for rid, p2 in directory(base + (p1 & 0x7FFFFFFF)):
            if not p2 & 0x80000000:
                continue
            for _lang, p3 in directory(base + (p2 & 0x7FFFFFFF)):
                rva, size = struct.unpack_from("<II", data, base + p3)
                off = rva_to_off(sections, rva)
                res.setdefault(typ, {})[rid] = data[off:off + size]
                break
    return res


def best_icon(path):
    data = open(path, "rb").read()
    res = read_resources(data)
    icons, groups = res.get(RT_ICON, {}), res.get(RT_GROUP_ICON, {})
    if not groups:
        raise SystemExit("no icon group in " + path)
    grp = next(iter(groups.values()))
    _, _, count = struct.unpack_from("<HHH", grp, 0)
    entries = []
    for i in range(count):
        w, h, cc, _, planes, bpp, size, nid = struct.unpack_from("<BBBBHHIH", grp, 6 + i * 14)
        entries.append(((w or 256), bpp, nid, w, h, cc, planes, size))
    entries.sort(reverse=True)
    w_px, bpp, nid, w, h, cc, planes, size = entries[0]
    img = icons[nid]
    if img[:8] == b"\x89PNG\r\n\x1a\n":
        return img
    # Wrap the raw DIB in a one-entry .ico so Pillow can decode it.
    ico = struct.pack("<HHH", 0, 1, 1) + struct.pack("<BBBBHHII", w, h, cc, 0, planes, bpp, len(img), 22) + img
    return ico


def main():
    from PIL import Image
    src, out = sys.argv[1], sys.argv[2]
    size = int(sys.argv[3]) if len(sys.argv) > 3 else 256
    im = Image.open(io.BytesIO(best_icon(src)))
    if hasattr(im, "ico"):
        im = im.ico.getimage(max(im.ico.sizes()))
    im = im.convert("RGBA")
    if im.width != size:
        im = im.resize((size, size), Image.LANCZOS)
    im.save(out)


if __name__ == "__main__":
    main()
