#!/usr/bin/env python3
"""Edit a Wine registry file (user.reg / system.reg) as text, without running Wine.

usage:
  winereg.py set  FILE 'Software\\Wine\\DllOverrides' NAME VALUE
  winereg.py get  FILE 'Software\\Wine\\DllOverrides' NAME
  winereg.py mirror-wow64 FILE MATCH   copy 32-bit-only COM classes mentioning MATCH to the 64-bit view

Why: protontricks/winetricks cannot drive Proton Experimental (11.x) Wine, and every
Wine call is slow. Wine keeps the registry as plain text and rewrites it when the
wineserver exits, so edits are only safe while no process uses the prefix — the
caller must make sure of that. A .bak copy is made before the first change.

Key paths are written with single backslashes on the command line (as in regedit);
VALUE is the string to store, or dword:XXXXXXXX for a REG_DWORD. The value (may be read from the env var WINEREG_VALUE
instead, so secrets never appear in the process list: pass VALUE as "-").
"""
import os
import re
import shutil
import sys
import time


def esc_key(path):
    return path.replace("\\", "\\\\")


def esc_str(v):
    return v.replace("\\", "\\\\").replace('"', '\\"')


def load(p):
    with open(p, encoding="utf-8", errors="surrogateescape") as f:
        return f.read().split("\n")


def section_range(lines, key):
    head = re.compile(r"^\[" + re.escape(esc_key(key)) + r"\](\s+\d+)?\s*$", re.I)
    for i, line in enumerate(lines):
        if head.match(line):
            j = i + 1
            while j < len(lines) and not lines[j].startswith("["):
                j += 1
            return i, j
    return None


def get(lines, key, name):
    r = section_range(lines, key)
    if not r:
        return None
    pat = re.compile('^' + re.escape(qname(name)) + r'=(?:"(.*)"|(dword:[0-9a-f]{8}))\s*$', re.I)
    for line in lines[r[0] + 1:r[1]]:
        m = pat.match(line)
        if m:
            if m.group(2):
                return m.group(2).lower()
            return m.group(1).replace('\\"', '"').replace("\\\\", "\\")
    return None


def qname(name):
    return "@" if name == "@" else f'"{esc_str(name)}"'


def fmt(name, value):
    # "dword:00000002" is written raw (REG_DWORD); everything else as REG_SZ
    if re.fullmatch(r"dword:[0-9a-fA-F]{8}", value):
        return f'{qname(name)}={value.lower()}'
    return f'{qname(name)}="{esc_str(value)}"'


def set_(lines, key, name, value):
    entry = fmt(name, value)
    r = section_range(lines, key)
    if not r:
        # append a new section before the trailing empty line
        stamp = int(time.time())
        block = ["", f"[{esc_key(key)}] {stamp}", f"#time={stamp:x}", entry]
        while lines and lines[-1] == "":
            lines.pop()
        lines.extend(block + [""])
        return lines
    pat = re.compile('^' + re.escape(qname(name)) + '=', re.I)
    for k in range(r[0] + 1, r[1]):
        if pat.match(lines[k]):
            lines[k] = entry
            return lines
    end = r[1]
    while end - 1 > r[0] and lines[end - 1].strip() == "":
        end -= 1
    lines.insert(end, entry)
    return lines


def mirror_wow64(lines, match):
    """Copy 32-bit-only COM registrations (Wow6432Node\\CLSID|Interface|TypeLib) whose
    contents mention `match` into the 64-bit view, like Windows makes them visible.
    Returns number of sections added."""
    sec_re = re.compile(r"^\[(Software\\\\Classes\\\\)Wow6432Node\\\\((CLSID|Interface)\\\\\{[0-9A-Fa-f-]+\})(.*)\](.*)$")
    # pass 1: which top-level GUID keys mention `match` anywhere in their subtree
    blocks, cur = {}, None
    for i, line in enumerate(lines):
        m = sec_re.match(line)
        if line.startswith("["):
            cur = m.group(2).lower() if m else None
        if cur:
            blocks.setdefault(cur, []).append(i)
    wanted = {k for k, idx in blocks.items() if any(match.lower() in lines[j].lower() for j in idx)}
    # interfaces whose typelib/proxy points at a wanted class's typelib
    libs = set()
    for k in wanted:
        for j in blocks[k]:
            t = re.search(r'\{[0-9A-Fa-f-]{36}\}', lines[j]) if "TypeLib" in lines[j - 2:j + 1][0] else None
            if t:
                libs.add(t.group(0).lower())
    for k, idx in blocks.items():
        if k.startswith("interface") and any(l in lines[j].lower() for j in idx for l in libs):
            wanted.add(k)
    existing = {l.split("]")[0].lower() for l in lines if l.startswith("[")}
    out, added = [], 0
    for i, line in enumerate(lines):
        m = sec_re.match(line)
        if m and m.group(2).lower() in wanted:
            new_head = "[" + m.group(1) + m.group(2) + m.group(4) + "]" + m.group(5)
            if new_head.split("]")[0].lower() not in existing:
                j = i + 1
                body = []
                while j < len(lines) and not lines[j].startswith("["):
                    body.append(lines[j]); j += 1
                out.append([new_head] + body)
                added += 1
    while lines and lines[-1] == "":
        lines.pop()
    for block in out:
        if block[-1] != "":
            block.append("")
        lines.append("")
        lines.extend(block[:-1] if block[-1] == "" else block)
    lines.append("")
    return added


def main(a):
    if len(a) == 4 and a[1] == "mirror-wow64":
        path = a[2]; lines = load(path)
        n = mirror_wow64(lines, a[3])
        if n:
            bak = path + ".3dmark-helper.bak"
            if not os.path.exists(bak):
                shutil.copy2(path, bak)
            with open(path + ".tmp", "w", encoding="utf-8", errors="surrogateescape") as f:
                f.write("\n".join(lines))
            os.replace(path + ".tmp", path)
        print(n)
        return 0
    if len(a) < 5 or a[1] not in ("get", "set"):
        print(__doc__, file=sys.stderr)
        return 2
    cmd, path, key, name = a[1:5]
    lines = load(path)
    if cmd == "get":
        v = get(lines, key, name)
        if v is None:
            return 1
        print(v)
        return 0
    value = a[5] if len(a) > 5 else "-"
    if value == "-":
        value = os.environ.get("WINEREG_VALUE", "")
    if get(lines, key, name) == value:
        return 0
    bak = path + ".3dmark-helper.bak"
    if not os.path.exists(bak):
        shutil.copy2(path, bak)
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8", errors="surrogateescape") as f:
        f.write("\n".join(set_(lines, key, name, value)))
    os.replace(tmp, path)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
