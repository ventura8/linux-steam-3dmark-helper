#!/bin/bash
# Steam launch wrapper installed by linux-steam-3dmark-helper.
# Launch options: APP_PROC='<pgrep pattern of the game exe>' <this file> %command%
#
# Under Proton, UL SystemInfo's scanner (FMSIScan.exe) keeps running after 3DMark /
# 3DMark 11 / PCMark exits. That keeps the Wine session alive, so Steam still shows the
# game as running (and, since an account runs one app at a time, blocks the next launch).
# On Windows the SystemInfo service stops the scanner; here we end the session once the
# game's own executable has exited.
"$@" &
child=$!
pattern=${APP_PROC:-}
prefix=${STEAM_COMPAT_DATA_PATH:+$STEAM_COMPAT_DATA_PATH/pfx}

if [[ -n $pattern && -n $prefix ]]; then
  # wait for the game exe to show up (launchers/EULA can take a while), then to exit
  for _ in $(seq 600); do
    pgrep -f "$pattern" >/dev/null && break
    kill -0 "$child" 2>/dev/null || break
    sleep 1
  done
  while pgrep -f "$pattern" >/dev/null; do sleep 2; done
  sleep 5
  for ws in $(pgrep -f '[w]ineserver'); do
    if tr '\0' '\n' <"/proc/$ws/environ" 2>/dev/null | grep -q "^WINEPREFIX=$prefix/\?$"; then
      WINEPREFIX="$prefix" "$(readlink -f "/proc/$ws/exe")" -k 2>/dev/null || true
    fi
  done
fi
wait "$child"
