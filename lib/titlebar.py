#!/usr/bin/env python3
"""Ask the window manager to draw a normal title bar (minimise / maximise / close)
on the borderless 3DMark / 3DMark 11 / PCMark windows (WM_CLASS steam_app_<id>).

usage: titlebar.py kde     KWINRULESRC   # KDE Plasma (KWin, X11 + Wayland)
       titlebar.py openbox RC_XML        # LXQt on X11 (~/.config/openbox/lxqt-rc.xml)
       titlebar.py labwc   RC_XML        # LXQt on Wayland (~/.config/labwc/rc.xml)
Idempotent; prints "changed" or "unchanged". GNOME/Mutter has no equivalent and XFCE
(xfwm4) already decorates these windows.
"""
import configparser
import os
import sys
import xml.etree.ElementTree as ET

CLASS_RE = r"steam_app_(223850|205270|524390)"
CLASS_GLOB = "steam_app_*"
RULE_ID = "3dmark-helper-titlebar"


def kde(path):
    cp = configparser.ConfigParser(interpolation=None)
    cp.optionxform = str  # KWin keys are case-sensitive
    if os.path.exists(path):
        cp.read(path, encoding="utf-8")
    if cp.has_section(RULE_ID):
        return False
    if not cp.has_section("General"):
        cp.add_section("General")
    rules = [r for r in cp.get("General", "rules", fallback="").split(",") if r]
    rules.append(RULE_ID)
    cp.set("General", "rules", ",".join(rules))
    cp.set("General", "count", str(len(rules)))
    cp.add_section(RULE_ID)
    for k, v in (("Description", "3DMark / PCMark: show title bar (linux-steam-3dmark-helper)"),
                 ("wmclass", CLASS_RE), ("wmclassmatch", "3"),       # 3 = regex
                 ("noborder", "false"), ("noborderrule", "2")):       # 2 = force
        cp.set(RULE_ID, k, v)
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        cp.write(f, space_around_delimiters=False)
    return True


def _xml(path, default_root):
    if os.path.exists(path):
        tree = ET.parse(path)
    else:
        tree = ET.ElementTree(ET.fromstring(default_root))
    return tree


def _ns(root):
    return root.tag[: root.tag.index("}") + 1] if root.tag.startswith("{") else ""


def openbox(path):
    tree = _xml(path, '<openbox_config xmlns="http://openbox.org/3.4/rc"/>')
    root = tree.getroot()
    ns = _ns(root)
    if ns:
        ET.register_namespace("", ns.strip("{}"))
    apps = root.find(f"{ns}applications")
    if apps is None:
        apps = ET.SubElement(root, f"{ns}applications")
    for a in apps.findall(f"{ns}application"):
        if a.get("class") == CLASS_GLOB:
            return False
    app = ET.SubElement(apps, f"{ns}application", {"class": CLASS_GLOB})
    ET.SubElement(app, f"{ns}decor").text = "yes"
    _write(tree, path)
    return True


def labwc(path):
    tree = _xml(path, "<labwc_config/>")
    root = tree.getroot()
    rules = root.find("windowRules")
    if rules is None:
        rules = ET.SubElement(root, "windowRules")
    for r in rules.findall("windowRule"):
        if r.get("identifier") == CLASS_GLOB:
            return False
    ET.SubElement(rules, "windowRule", {"identifier": CLASS_GLOB, "serverDecoration": "yes"})
    _write(tree, path)
    return True


def _write(tree, path):
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    if os.path.exists(path) and not os.path.exists(path + ".3dmark-helper.bak"):
        with open(path, "rb") as s, open(path + ".3dmark-helper.bak", "wb") as d:
            d.write(s.read())
    ET.indent(tree)
    tree.write(path, encoding="utf-8", xml_declaration=True)


def main(a):
    if len(a) != 3 or a[1] not in ("kde", "openbox", "labwc"):
        print(__doc__, file=sys.stderr)
        return 2
    changed = {"kde": kde, "openbox": openbox, "labwc": labwc}[a[1]](a[2])
    print("changed" if changed else "unchanged")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
