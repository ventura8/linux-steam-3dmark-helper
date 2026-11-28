#!/usr/bin/env python3
"""Toggle UL SystemInfo in a 3DMark / PCMark app-settings.json.

usage: appsettings.py FILE on|off
Under Proton the Futuremark SystemInfo service cannot run (its RpcSs start fails),
so scanning only adds 60-90 s timeouts (and hangs runs on Proton 11). Results are
not validated online either way.
"""
import json, sys
p = sys.argv[1]; v = sys.argv[2] == "on"
d = json.load(open(p, encoding="utf-8"))
for e in d:
    for k in ("SCAN_SYSTEM_INFO", "HARDWARE_MONITORING"):
        if k in e: e[k] = v
json.dump(d, open(p, "w", encoding="utf-8"), ensure_ascii=False, separators=(",", ":"))
print([ (k, e[k]) for e in d for k in ("SCAN_SYSTEM_INFO","HARDWARE_MONITORING") if k in e])
