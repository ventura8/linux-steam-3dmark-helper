#!/usr/bin/env python3
"""Fetch a game's CD key from Steam's "CD Keys" dialog with no user input.

usage: cdkey.py APPID [--steam-cmd "snap run steam"] [--timeout 60]
Prints the key on stdout (exit 0) or exits 1.

How: open steam://cdkeys/APPID, screenshot the X display (Steam is an X11/XWayland
client on every desktop), OCR it with tesseract to *locate* the key cell, the
"Don't show me this again" checkbox and the Close button, click the key so Steam
copies the exact text to the clipboard, read it back, tick the checkbox (so the
dialog no longer blocks every launch) and close the dialog. OCR is only used for
coordinates, never for the key text itself.
Needs: xdotool, imagemagick (import/convert), tesseract-ocr, xclip or xsel.
"""
import argparse
import os
import re
import shlex
import subprocess
import sys
import tempfile
import time

KEY_RE = re.compile(r"^[0-9A-Z]{2,6}(-[0-9A-Z]{3,6}){3,6}$")
KEYISH = re.compile(r"^[0-9A-Z]{2,6}-[0-9A-Z]{2,}")


def run(cmd, **kw):
    return subprocess.run(cmd, capture_output=True, text=True, **kw)


def clipboard():
    for cmd in (["xclip", "-o", "-selection", "clipboard"], ["xsel", "-ob"]):
        try:
            r = run(cmd, timeout=5)
            if r.returncode == 0:
                return re.sub(r"\s", "", r.stdout)
        except (FileNotFoundError, subprocess.TimeoutExpired):
            pass
    return ""


def set_clipboard(text):
    for cmd in (["xclip", "-selection", "clipboard"], ["xsel", "-ib"]):
        try:
            subprocess.run(cmd, input=text, text=True, timeout=5, check=True)
            return
        except (FileNotFoundError, subprocess.CalledProcessError, subprocess.TimeoutExpired):
            pass


def steam_window():
    """Steam's main client window (works on X11 and on Wayland via XWayland)."""
    r = run(["xprop", "-root", "_NET_CLIENT_LIST"])
    for wid in re.findall(r"0x[0-9a-f]+", r.stdout):
        p = run(["xprop", "-id", wid, "WM_CLASS", "_NET_WM_NAME"]).stdout
        if "steamwebhelper" in p and '"Steam"' in p:
            return wid
    return None


def ocr_words(tmp, wid):
    raw, shot, pre = (os.path.join(tmp, n) for n in ("s.xwd", "s.png", "p.png"))
    # xwd captures a single window even under rootless XWayland (GNOME/KDE Wayland)
    if run(["xwd", "-silent", "-id", wid, "-out", raw]).returncode != 0:
        return []
    run(["convert", "xwd:" + raw, shot])
    width = int(run(["identify", "-format", "%w", shot]).stdout or 0)
    scale = 1 if width >= 2500 else 2  # HiDPI windows are already large enough
    run(["convert", shot, "-colorspace", "Gray", "-resize", f"{scale * 100}%",
         "-negate", "-threshold", "55%", pre])
    r = run(["tesseract", pre, "-", "--psm", "11", "tsv"])
    words = []
    for line in r.stdout.splitlines()[1:]:
        f = line.split("\t")
        if len(f) == 12 and f[11].strip():
            x, y, w, h = (int(v) // scale for v in f[6:10])
            words.append((f[11].strip(), x + w // 2, y + h // 2, x, y))
    return words


def open_from_launch_popup(tmp):
    """The launch-time CD key prompt hides behind the "Launching..." popup:
    press its "Open Steam" button so the dialog shows in the main window."""
    global WID
    r = run(["xprop", "-root", "_NET_CLIENT_LIST"])
    for wid in re.findall(r"0x[0-9a-f]+", r.stdout):
        if "Launching" in run(["xprop", "-id", wid, "_NET_WM_NAME"]).stdout:
            words = ocr_words(tmp, wid)
            btn = [w for w in words if w[0] == "Open"]
            if btn:
                WID = wid
                click(btn[0][1], btn[0][2])
                time.sleep(2)
            return


def find(words, pred):
    return [w for w in words if pred(w[0])]


WID = None


def click(x, y):
    # coordinates are relative to the Steam window
    run(["xdotool", "windowactivate", "--sync", WID])
    run(["xdotool", "mousemove", "--window", WID, str(x), str(y), "click", "1"])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("appid")
    ap.add_argument("--steam-cmd", default="steam")
    ap.add_argument("--timeout", type=int, default=60)
    ap.add_argument("--no-open", action="store_true",
                    help="the dialog is already showing (launch-time CD key prompt)")
    a = ap.parse_args()

    set_clipboard("")
    if not a.no_open:
        subprocess.Popen(shlex.split(a.steam_cmd) + [f"steam://cdkeys/{a.appid}"],
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    global WID
    with tempfile.TemporaryDirectory() as tmp:
        deadline = time.time() + a.timeout
        while time.time() < deadline:
            time.sleep(3)
            open_from_launch_popup(tmp)
            WID = steam_window()
            if not WID:
                continue
            words = ocr_words(tmp, WID)
            title = find(words, lambda t: t == "Keys")
            close = find(words, lambda t: t == "Close")
            if not (title and close):
                continue
            # the key cell: first key-shaped word between the title and the Close button
            cells = [w for w in find(words, KEYISH.match) if title[0][2] < w[2] < close[0][2]]
            if not cells:
                continue
            click(cells[0][1], cells[0][2])
            time.sleep(1)
            key = clipboard()
            if not KEY_RE.match(key):
                continue
            show = find(words, lambda t: t == "show")
            if show:  # checkbox sits left of "Don't show me this again"
                dont = [w for w in words if w[0].startswith("Don") and abs(w[2] - show[0][2]) < 10]
                left = (dont[0] if dont else show[0])[3]
                click(left - 18, show[0][2])
                time.sleep(0.5)
            click(close[0][1], close[0][2])
            print(key)
            return 0
    print("CD key dialog not found", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
