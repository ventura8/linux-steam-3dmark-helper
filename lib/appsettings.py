#!/usr/bin/env python3
"""Toggle UL SystemInfo scanning in a 3DMark / PCMark app-settings.json.

usage: appsettings.py FILE on|off

With scanning on, 3DMark misreads the CPU under Wine and blocks Time Spy /
Night Raid ("CPU does not support SSSE3"), so the helper keeps it off by default.
"""

import json
import sys

KEYS = ("SCAN_SYSTEM_INFO", "HARDWARE_MONITORING")


def main(argv):
    if len(argv) != 3 or argv[2] not in ("on", "off"):
        print(__doc__, file=sys.stderr)
        return 2
    path, value = argv[1], argv[2] == "on"
    with open(path, encoding="utf-8") as f:
        settings = json.load(f)
    for entry in settings:
        for key in KEYS:
            if key in entry:
                entry[key] = value
    with open(path, "w", encoding="utf-8") as f:
        json.dump(settings, f, ensure_ascii=False, separators=(",", ":"))
    print([(k, e[k]) for e in settings for k in KEYS if k in e])
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
