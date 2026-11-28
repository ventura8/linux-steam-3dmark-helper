#!/usr/bin/env python3
"""Keep VERSION, 3dmark-helper.sh and CHANGELOG.md in sync.

usage: sync-version.py --check      fail if they disagree (CI, release)
       sync-version.py X.Y.Z        set VERSION and the script's VERSION= line
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCRIPT = ROOT / "3dmark-helper.sh"
SCRIPT_RE = re.compile(r"^VERSION=(\S+)$", re.MULTILINE)


def versions():
    file_v = (ROOT / "VERSION").read_text(encoding="utf-8").strip()
    m = SCRIPT_RE.search(SCRIPT.read_text(encoding="utf-8"))
    script_v = m.group(1) if m else None
    changelog = (ROOT / "CHANGELOG.md").read_text(encoding="utf-8")
    in_changelog = f"## [{file_v}]" in changelog
    return file_v, script_v, in_changelog


def main(argv):
    if len(argv) == 2 and argv[1] == "--check":
        file_v, script_v, in_changelog = versions()
        ok = True
        if not re.fullmatch(r"\d+\.\d+\.\d+", file_v):
            print(f"VERSION '{file_v}' is not X.Y.Z", file=sys.stderr)
            ok = False
        if script_v != file_v:
            print(f"3dmark-helper.sh VERSION={script_v} != VERSION {file_v}", file=sys.stderr)
            ok = False
        if not in_changelog:
            print(f"CHANGELOG.md has no '## [{file_v}]' section", file=sys.stderr)
            ok = False
        print(f"version {file_v}: {'in sync' if ok else 'OUT OF SYNC'}")
        return 0 if ok else 1
    if len(argv) == 2 and re.fullmatch(r"\d+\.\d+\.\d+", argv[1]):
        v = argv[1]
        (ROOT / "VERSION").write_text(v + "\n", encoding="utf-8")
        SCRIPT.write_text(SCRIPT_RE.sub(f"VERSION={v}", SCRIPT.read_text(encoding="utf-8")), encoding="utf-8")
        print(f"set {v}; add a '## [{v}]' section to CHANGELOG.md and docs/releases/v{v}.md")
        return 0
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
