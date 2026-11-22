#!/usr/bin/env python3
"""Minimal text-VDF reader/writer used by 3dmark-helper.

Commands:
  get  FILE KEY/PATH                 print value (string) or exit 1
  set  FILE KEY/PATH VALUE           set string value, creating sections
  compat FILE APPID TOOLNAME         set CompatToolMapping for an app in config.vdf
  launch FILE APPID OPTIONS          set LaunchOptions in localconfig.vdf
  keys FILE KEY/PATH                 list child keys of a section
Path components are matched case-insensitively. A .bak copy is written
before the first modification of a file.
"""
import os
import re
import shutil
import sys

TOKEN = re.compile(r'"((?:[^"\\]|\\.)*)"|([{}])|(//[^\n]*)|\s+')


def tokenize(text):
    pos = 0
    out = []
    while pos < len(text):
        m = TOKEN.match(text, pos)
        if not m:
            # bare word (unquoted) token
            m2 = re.compile(r'[^\s{}"]+').match(text, pos)
            out.append(("s", m2.group(0)))
            pos = m2.end()
            continue
        if m.group(1) is not None:
            out.append(("s", m.group(1)))
        elif m.group(2):
            out.append((m.group(2), None))
        pos = m.end()
    return out


def parse(text):
    toks = tokenize(text)
    i = 0

    def section():
        nonlocal i
        items = []
        while i < len(toks):
            kind, val = toks[i]
            if kind == "}":
                i += 1
                return items
            key = val
            i += 1
            kind2, val2 = toks[i]
            if kind2 == "{":
                i += 1
                items.append([key, section()])
            else:
                i += 1
                items.append([key, val2])
        return items

    return section()


def dump(items, depth=0):
    tab = "\t" * depth
    out = []
    for k, v in items:
        if isinstance(v, list):
            out.append(f'{tab}"{k}"\n{tab}{{\n{dump(v, depth + 1)}{tab}}}\n')
        else:
            out.append(f'{tab}"{k}"\t\t"{v}"\n')
    return "".join(out)


def find(items, key):
    for kv in items:
        if kv[0].lower() == key.lower():
            return kv
    return None


def walk(items, path, create=False):
    cur = items
    for part in path:
        kv = find(cur, part)
        if kv is None:
            if not create:
                return None
            kv = [part, []]
            cur.append(kv)
        if not isinstance(kv[1], list):
            if not create:
                return None
            kv[1] = []
        cur = kv[1]
    return cur


def load(path):
    with open(path, encoding="utf-8", errors="surrogateescape") as f:
        return parse(f.read())


def save(path, items):
    bak = path + ".3dmark-helper.bak"
    if not os.path.exists(bak):
        shutil.copy2(path, bak)
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8", errors="surrogateescape") as f:
        f.write(dump(items))
    os.replace(tmp, path)


def set_value(items, path, value):
    parent = walk(items, path[:-1], create=True)
    kv = find(parent, path[-1])
    if kv is None:
        parent.append([path[-1], value])
    else:
        kv[1] = value


def esc(s):
    return s.replace("\\", "\\\\").replace('"', '\\"')


def main(argv):
    if len(argv) < 3:
        print(__doc__, file=sys.stderr)
        return 2
    cmd, path = argv[1], argv[2]
    items = load(path)
    if cmd == "get":
        parts = argv[3].split("/")
        parent = walk(items, parts[:-1])
        kv = find(parent, parts[-1]) if parent is not None else None
        if kv is None or isinstance(kv[1], list):
            return 1
        print(kv[1])
        return 0
    if cmd == "keys":
        sec = walk(items, argv[3].split("/"))
        if sec is None:
            return 1
        for k, _ in sec:
            print(k)
        return 0
    if cmd == "set":
        set_value(items, argv[3].split("/"), esc(argv[4]))
    elif cmd == "compat":
        appid, tool = argv[3], argv[4]
        base = ["InstallConfigStore", "Software", "Valve", "Steam", "CompatToolMapping", appid]
        set_value(items, base + ["name"], tool)
        set_value(items, base + ["config"], "")
        set_value(items, base + ["priority"], "250")
    elif cmd == "launch":
        appid, opts = argv[3], argv[4]
        base = ["UserLocalConfigStore", "Software", "Valve", "Steam", "apps", appid]
        set_value(items, base + ["LaunchOptions"], esc(opts))
    else:
        print(__doc__, file=sys.stderr)
        return 2
    save(path, items)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
