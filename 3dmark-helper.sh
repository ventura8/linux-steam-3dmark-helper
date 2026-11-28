#!/usr/bin/env bash
# linux-steam-3dmark-helper — get Steam 3DMark (223850), 3DMark 11 (205270) and
# PCMark 10 (524390) running under Proton on Ubuntu-family distros.
# https://github.com/ventura8/linux-steam-3dmark-helper
set -euo pipefail

VERSION=0.2.0
HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
VDF="python3 $HERE/lib/vdfedit.py"

APP_3DMARK=223850
APP_3DMARK11=205270
APP_PCMARK10=524390
APP_PROTON10=3658110   # "Proton 10.0" tool app
APP_PROTON_EXP=1493710 # "Proton - Experimental"
APP_SLR3=1628350       # Steam Linux Runtime 3.0 (sniper), required by Proton 10

# ---------- output helpers ----------
if [[ -t 1 ]]; then
  C_G=$'\e[32m'
  C_R=$'\e[31m'
  C_Y=$'\e[33m'
  C_B=$'\e[1m'
  C_0=$'\e[0m'
else
  C_G=
  C_R=
  C_Y=
  C_B=
  C_0=
fi
ok() { printf '  %s[ OK ]%s %s\n' "$C_G" "$C_0" "$*"; }
bad() {
  printf '  %s[FAIL]%s %s\n' "$C_R" "$C_0" "$*"
  FAILS=$((FAILS + 1))
}
warn() { printf '  %s[WARN]%s %s\n' "$C_Y" "$C_0" "$*"; }
info() { printf '%s==>%s %s\n' "$C_B" "$C_0" "$*"; }
die() {
  printf '%sERROR:%s %s\n' "$C_R" "$C_0" "$*" >&2
  exit 1
}
FAILS=0
ASSUME_YES=${ASSUME_YES:-1} # automagic by default; --ask to confirm each step
confirm() {
  [[ $ASSUME_YES == 1 ]] && return 0
  read -r -p "$1 [Y/n] " a
  [[ -z $a || $a =~ ^[Yy] ]]
}

app_id() {
  case "${1:-}" in
    3dmark | 223850) echo $APP_3DMARK ;;
    3dmark11 | 205270) echo $APP_3DMARK11 ;;
    pcmark10 | 524390) echo $APP_PCMARK10 ;;
    *) die "unknown app '$1' (use 3dmark, 3dmark11 or pcmark10)" ;;
  esac
}

# Per-app facts. Key locations come from Steam's appinfo (legacykeyregistrylocation);
# newer 3DMark builds also read Software\UL\3DMark.
ALL_APPS=(3dmark 3dmark11 pcmark10)
app_name() { case $1 in "$APP_3DMARK") echo 3DMark ;; "$APP_3DMARK11") echo "3DMark 11" ;; "$APP_PCMARK10") echo "PCMark 10" ;; esac }
app_exe() { case $1 in "$APP_3DMARK") echo "3DMark/bin/x64/3DMark.exe" ;; "$APP_3DMARK11") echo "3DMark 11/bin/x64/3DMark11.exe" ;; "$APP_PCMARK10") echo "PCMark 10/bin/x64/PCMark10.exe" ;; esac }
app_proc() { case $1 in "$APP_3DMARK") echo '[b]in.x64.3DMark.exe' ;; "$APP_3DMARK11") echo '[b]in.x64.3DMark11.exe' ;; "$APP_PCMARK10") echo '[b]in.x64.PCMark10.exe' ;; esac }
app_keyreg() {
  case $1 in
    "$APP_3DMARK") printf '%s\n' 'HKEY_CURRENT_USER\Software\Futuremark\3DMark' 'HKEY_CURRENT_USER\Software\UL\3DMark' ;;
    "$APP_3DMARK11") printf '%s\n' 'HKEY_CURRENT_USER\Software\Futuremark\3DMark11' ;;
    *) ;; # PCMark 10 on Steam has no legacy CD key: ownership comes from Steam
  esac
}
app_verbs() { echo "d3dcompiler_47"; }
app_desc() { case $1 in "$APP_3DMARK") echo "GPU and CPU benchmark by UL" ;; "$APP_3DMARK11") echo "DirectX 11 benchmark by UL" ;; "$APP_PCMARK10") echo "PC performance benchmark by UL" ;; esac }
owns_app() {
  local f
  for f in $(user_configs); do grep -q "\"$1\"" "$f" && return 0; done
  [[ -d $STEAM_ROOT/appcache/librarycache/$1 ]]
}
app_running() { ! no_proc && pgrep -f "$(app_proc "$1")" >/dev/null; }

# ---------- Steam detection ----------
STEAM_KIND=""
STEAM_ROOT=""
detect_steam() {
  local c
  for c in "$HOME/.local/share/Steam:deb" "$HOME/.steam/debian-installation:deb" \
    "$HOME/snap/steam/common/.local/share/Steam:snap" \
    "$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam:flatpak"; do
    if [[ -f ${c%:*}/config/config.vdf || -d ${c%:*}/steamapps ]]; then
      STEAM_ROOT=${c%:*}
      STEAM_KIND=${c##*:}
      return 0
    fi
  done
  if snap list steam &>/dev/null; then
    STEAM_KIND=snap
    STEAM_ROOT="$HOME/snap/steam/common/.local/share/Steam"
    return 1
  fi
  if flatpak info com.valvesoftware.Steam &>/dev/null; then
    STEAM_KIND=flatpak
    STEAM_ROOT="$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam"
    return 1
  fi
  if command -v steam &>/dev/null; then
    STEAM_KIND=deb
    STEAM_ROOT="$HOME/.local/share/Steam"
    return 1
  fi
  return 1
}

# When run over SSH/TTY, borrow the logged-in desktop session's environment;
# without D-Bus/XDG/Xauthority Steam starts but never shows its window.
import_session_env() {
  [[ -n ${DBUS_SESSION_BUS_ADDRESS:-} && -n ${DISPLAY:-}${WAYLAND_DISPLAY:-} ]] && return 0
  local p pid
  for p in gnome-shell plasmashell kwin_wayland kwin_x11 ksmserver xfce4-panel xfce4-session lxqt-panel lxqt-session openbox labwc; do
    pid=$(pgrep -u "$(id -u)" -x "$p" | head -1) && [[ -n $pid ]] && break
  done
  [[ -n ${pid:-} && -r /proc/$pid/environ ]] || return 1
  local line
  while IFS= read -r -d '' line; do
    case $line in
      DISPLAY=* | WAYLAND_DISPLAY=* | XAUTHORITY=* | DBUS_SESSION_BUS_ADDRESS=* | XDG_RUNTIME_DIR=* | XDG_CURRENT_DESKTOP=* | XDG_SESSION_TYPE=*)
        export "${line?}"
        ;;
    esac
  done <"/proc/$pid/environ"
}

steam_cmd() {
  no_proc && return 0
  import_session_env || true
  case $STEAM_KIND in
    snap) snap run steam "$@" ;;
    flatpak) flatpak run com.valvesoftware.Steam "$@" ;;
    *) steam "$@" ;;
  esac
}

# Tests set STEAM_HELPER_NO_PROCESS_CONTROL=1: never look at or signal real processes.
no_proc() { [[ ${STEAM_HELPER_NO_PROCESS_CONTROL:-0} == 1 ]]; }
steam_running() {
  no_proc && return 1
  pgrep -x steam >/dev/null || pgrep -f 'ubuntu12_32/steam' >/dev/null
}

stop_steam() {
  no_proc && return 0
  steam_running || return 0
  info "Closing Steam (config files are only safe to edit while it is closed)"
  steam_cmd -shutdown &>/dev/null || true
  for _ in $(seq 45); do
    steam_running || return 0
    sleep 1
  done
  # leftover steam.sh wrappers restart the client after a shutdown: stop them first
  pkill -TERM -f '[s]team\.sh( |$)' 2>/dev/null || true
  pkill -TERM -x steam 2>/dev/null || true
  for _ in $(seq 30); do
    steam_running || return 0
    sleep 1
  done
  die "Steam is still running; close it manually and retry."
}

library_dirs() {
  local f="$STEAM_ROOT/steamapps/libraryfolders.vdf"
  echo "$STEAM_ROOT"
  [[ -f $f ]] && grep -oP '"path"\s+"\K[^"]+' "$f" | grep -vxF "$STEAM_ROOT" || true
}

app_manifest() {
  local d
  for d in $(library_dirs); do [[ -f $d/steamapps/appmanifest_$1.acf ]] && {
    echo "$d/steamapps/appmanifest_$1.acf"
    return 0
  }; done
  return 1
}
# Installed = StateFlags 4 AND real content (a Windows-only app with no Proton mapping
# "installs" with 0 depots and an empty folder).
app_installed() {
  local m
  m=$(app_manifest "$1") || return 1
  grep -qP '"StateFlags"\s+"4"' "$m" || return 1
  python3 -c 'import re,sys; t=open(sys.argv[1]).read(); m=re.search(r"\"InstalledDepots\"\s*\{\s*\"\d+",t); sys.exit(0 if m else 1)' "$m"
}
app_prefix() {
  local d
  for d in $(library_dirs); do [[ -d $d/steamapps/compatdata/$1/pfx ]] && {
    echo "$d/steamapps/compatdata/$1/pfx"
    return 0
  }; done
  return 1
}

user_configs() { ls "$STEAM_ROOT"/userdata/*/config/localconfig.vdf 2>/dev/null || true; }

logged_in() {
  [[ -f $STEAM_ROOT/config/loginusers.vdf ]] && grep -q '"7656' "$STEAM_ROOT/config/loginusers.vdf" && [[ -n $(user_configs) ]]
}

proton_tool() {
  # Tested 2026-11-28 (Experimental 11.0-20261123b): Time Spy +10 % vs Proton 10 and Steel
  # Nomad runs (it crashes in Proton 10's vkd3d-proton). The May 2026 Proton 11 DX12 refusal
  # (Proton#4034) is gone in this build. PROTON_TOOL=proton_10 falls back.
  if [[ -n ${PROTON_TOOL:-} ]]; then
    echo "$PROTON_TOOL"
    return
  fi
  if app_installed $APP_PROTON_EXP; then echo proton_experimental; else echo proton_10; fi
}

# ---------- GPU detection ----------
GPU_VENDORS=""
detect_gpus() {
  GPU_VENDORS=$(lspci -nn | grep -iE 'vga|3d controller|display' | grep -oE '\[(10de|1002|8086):' | tr -d '[:' | sort -u | tr '\n' ' ')
}
has_gpu() { [[ " $GPU_VENDORS " == *" $1 "* ]]; }
nvidia_ver() { nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -1 | cut -d. -f1; }

# The wrapper lives inside the Steam folder so Snap/Flatpak Steam can execute it.
install_wrapper() {
  [[ -n $STEAM_ROOT && -d $STEAM_ROOT ]] || return 1
  install -m755 "$HERE/lib/launch-wrapper.sh" "$STEAM_ROOT/3dmark-helper-launch.sh" 2>/dev/null && echo "$STEAM_ROOT/3dmark-helper-launch.sh"
}

launch_options() {
  local app=$1 env=()
  detect_gpus
  if has_gpu 10de; then
    env+=(PROTON_ENABLE_NVAPI=1 DXVK_ENABLE_NVAPI=1)
    # Hybrid laptop: make sure the dGPU renders.
    if has_gpu 8086 || has_gpu 1002; then
      env+=(__NV_PRIME_RENDER_OFFLOAD=1 __GLX_VENDOR_LIBRARY_NAME=nvidia __VK_LAYER_NV_optimus=NVIDIA_only)
    fi
  elif has_gpu 1002 && has_gpu 8086; then
    env+=(DRI_PRIME=1)
  fi
  [[ $app == "$APP_3DMARK" ]] && env+=("VKD3D_CONFIG=dxr,dxr11")
  [[ ${OSMESA:-0} == 1 ]] && {
    local p="${env[*]}"
    echo "${p:+$p }%command% --use-gl=osmesa"
    return
  }
  local wrap=""
  [[ ${NO_WRAPPER:-0} == 1 ]] || wrap=$(install_wrapper || true)
  [[ -n $wrap ]] && env+=("APP_PROC='$(app_proc "$app")'")
  local pre="${env[*]}"
  echo "${pre:+$pre }${wrap:+\"$wrap\" }%command%"
}

# ---------- commands ----------
cmd_doctor() {
  FAILS=0
  info "System"
  # shellcheck source=/dev/null
  . /etc/os-release
  ok "desktop profile: $(detect_desktop)"
  ok "$PRETTY_NAME, kernel $(uname -r), desktop ${XDG_CURRENT_DESKTOP:-?} (${XDG_SESSION_TYPE:-?})"
  detect_gpus
  while read -r l; do ok "GPU: $l"; done < <(lspci | grep -iE 'vga|3d controller|display' | cut -d: -f3-)
  info "Drivers / Vulkan"
  dpkg --print-foreign-architectures | grep -qx i386 && ok "i386 architecture enabled" || bad "i386 architecture not enabled (run: $0 deps)"
  for p in libvulkan1:i386 mesa-vulkan-drivers:i386; do
    dpkg -s "$p" &>/dev/null && ok "$p" || bad "$p missing (launcher will not start without 32-bit Vulkan)"
  done
  if has_gpu 10de; then
    local v
    v=$(nvidia_ver)
    [[ -n $v ]] && ok "NVIDIA driver $v" || bad "NVIDIA GPU present but nvidia-smi not working"
    [[ -n $v ]] && { dpkg -s "libnvidia-gl-$v:i386" &>/dev/null && ok "libnvidia-gl-$v:i386" || bad "libnvidia-gl-$v:i386 missing"; }
  fi
  command -v vulkaninfo &>/dev/null && { vulkaninfo --summary 2>/dev/null | grep -E 'deviceName' | sed 's/^ */  /' || true; } || warn "vulkan-tools not installed"
  command -v tesseract &>/dev/null && ok "tesseract (automatic CD keys on X11)" || warn "tesseract-ocr missing: CD keys need one click (run: $0 deps)"
  info "Steam"
  if detect_steam; then ok "Steam ($STEAM_KIND) at $STEAM_ROOT"; else
    bad "Steam not installed / never started"
    return 1
  fi
  logged_in && ok "a Steam account is logged in" || bad "no Steam login yet"
  for t in $APP_SLR3:"Steam Linux Runtime 3.0 (sniper)" $APP_PROTON10:"Proton 10" $APP_PROTON_EXP:"Proton Experimental"; do
    app_installed "${t%%:*}" && ok "${t#*:} installed" || warn "${t#*:} not installed"
  done
  ok "Proton tool that will be used: $(proton_tool)"
  local id name app
  for app in "${ALL_APPS[@]}"; do
    id=$(app_id "$app")
    name=$(app_name "$id")
    if app_installed "$id"; then
      ok "$name installed ($(app_manifest "$id" | xargs dirname))"
    elif owns_app "$id"; then
      bad "$name ($id) owned but not installed"
      continue
    else continue; fi
    local tool
    tool=$($VDF get "$STEAM_ROOT/config/config.vdf" "InstallConfigStore/Software/Valve/Steam/CompatToolMapping/$id/name" 2>/dev/null || true)
    [[ -n $tool ]] && ok "$name compat tool: $tool" || warn "$name: no forced Proton version (run setup)"
    local lo
    lo=$(for f in $(user_configs); do $VDF get "$f" "UserLocalConfigStore/Software/Valve/Steam/apps/$id/LaunchOptions" 2>/dev/null || true; done | head -1)
    [[ -n $lo ]] && ok "$name launch options: $lo" || warn "$name: no launch options set"
    if app_prefix "$id" >/dev/null; then
      prefix_ready "$id" && ok "$name prefix on $(prefix_proton_version "$id")" || warn "$name prefix not yet upgraded to $(proton_tool) (run: $0 prefix $app)"
      local v
      for v in $(app_verbs "$id"); do has_override "$id" "$v" && ok "$name $v native" || bad "$name: $v missing (run: $0 prefix $app)"; done
      if [[ -n $(app_keyreg "$id") ]]; then has_key "$id" && ok "$name CD key registered" || bad "$name: no CD key → demo mode (run: $0 key $app)"; fi
    else warn "$name: no prefix yet (run: $0 prefix $app)"; fi
    eula_accepted "$id" || warn "$name: EULA not accepted yet — Steam will ask on first launch"
  done
  if app_installed $APP_3DMARK; then
    local dir
    dir="$(dirname "$(app_manifest $APP_3DMARK)")/common/3DMark/dlc"
    [[ -d $dir ]] && ok "3DMark test DLCs present: $(find "$dir" -mindepth 1 -maxdepth 1 -type d -printf '%f ' | sort)" || warn "no 3DMark test DLC folders found (install them in Steam → 3DMark → DLC)"
  fi
  echo
  [[ $FAILS == 0 ]] && info "${C_G}All checks passed${C_0}" || info "${C_R}$FAILS problem(s)${C_0} — run: $0 install"
}

cmd_deps() {
  info "Installing system dependencies (needs sudo)"
  detect_gpus
  local pkgs=(libvulkan1 libvulkan1:i386 mesa-vulkan-drivers mesa-vulkan-drivers:i386 vulkan-tools python3 curl python3-pil pciutils xclip xsel wl-clipboard xdotool x11-apps imagemagick tesseract-ocr)
  if has_gpu 10de; then
    local v
    v=$(nvidia_ver)
    if [[ -n $v ]]; then pkgs+=("libnvidia-gl-$v:i386"); else warn "NVIDIA GPU found but no working driver — install one with: sudo ubuntu-drivers install"; fi
  fi
  echo "  packages: ${pkgs[*]}"
  confirm "Enable i386 and install these?" || return 1
  dpkg --print-foreign-architectures | grep -qx i386 || sudo dpkg --add-architecture i386
  sudo apt-get update
  local extra=() out
  # Multiarch skew: an amd64 lib installed at a version with no matching i386 build
  # (e.g. from a removed PPA) blocks every :i386 package. Detect and align versions.
  for _ in 1 2 3 4 5; do
    out=$(LC_ALL=C apt-get install -s "${pkgs[@]}" "${extra[@]}" 2>&1) && break
    local fix
    fix=$(sed -nE 's/.* ([^ ]+):i386 Breaks [^ ]+ \(!= ([^)]+)\).*/\1 \2/p' <<<"$out" | sort -u | head -5)
    [[ -z $fix ]] && break
    local name ver
    local src b
    while read -r name ver; do
      src=$(dpkg-query -W -f='${source:Package}' "$name" 2>/dev/null)
      warn "multiarch mismatch in source '$src' ($name): aligning to $ver (downgrade)"
      # every installed binary from the same source at the orphaned version must move together
      while read -r b _; do
        [[ " ${extra[*]} " == *" $b=$ver "* ]] || extra+=("$b=$ver")
      done < <(dpkg-query -W -f='${source:Package} ${Package} ${Version} ${db:Status-Abbrev}\n' 2>/dev/null |
        awk -v s="$src" -v v="$ver" '$1==s && $3!=v && $4 ~ /^ii/ {print $2, $3}')
      extra+=("$name:i386=$ver")
    done <<<"$fix"
  done
  if ((${#extra[@]})); then confirm "Apply version alignment: ${extra[*]}?" || return 1; fi
  sudo apt-get install -y --allow-downgrades "${pkgs[@]}" "${extra[@]}"
}

cmd_install_steam() {
  if detect_steam || [[ -n $STEAM_KIND ]]; then
    ok "Steam already installed ($STEAM_KIND)"
    return 0
  fi
  info "Installing Steam (official Valve installer package from Ubuntu multiverse)"
  confirm "Install steam-installer via apt?" || return 1
  sudo add-apt-repository -y multiverse >/dev/null 2>&1 || true
  sudo apt-get update
  sudo apt-get install -y steam-installer steam-devices
  STEAM_KIND=deb
  STEAM_ROOT="$HOME/.local/share/Steam"
}

# Headless boxes (VNC, no monitor): Steam's UI refuses to create windows when X has
# no connected output ("Failed to create popup"). Force the first HDMI/DP connector on.
cmd_headless() {
  import_session_env || true
  [[ ${XDG_SESSION_TYPE:-x11} == x11 && -n ${DISPLAY:-} ]] || return 0
  command -v xrandr &>/dev/null || return 0
  if xrandr 2>/dev/null | grep -q ' connected'; then return 0; fi
  local c
  c=$(compgen -G '/sys/class/drm/card*-HDMI-A-1' || compgen -G '/sys/class/drm/card*-DP-1' || true)
  c=${c%%$'\n'*}
  [[ -n $c ]] || {
    warn "headless and no HDMI/DP connector found — plug in a monitor or HDMI dummy plug"
    return 0
  }
  warn "No monitor connected (headless/VNC). Forcing ${c##*/} on so Steam can open windows (sudo)."
  echo on | sudo tee "$c/status" >/dev/null || return 1
  sleep 2
  local out
  out=$(xrandr | awk '/ connected/{print $1; exit}')
  [[ -n $out ]] && xrandr --output "$out" --auto
  ok "virtual display active on $out (lost on reboot; for permanent: HDMI dummy plug or kernel arg video=${c##*card?-}:1920x1080@60e)"
}

cmd_login() {
  detect_steam || true
  if logged_in && steam_running; then
    ok "Steam is running and logged in"
    return 0
  fi
  cmd_headless || true
  info "Starting Steam — log in with your account in the Steam window (first start downloads ~400 MB)"
  import_session_env || true
  [[ -z ${DISPLAY:-}${WAYLAND_DISPLAY:-} ]] && die "No graphical session (DISPLAY/WAYLAND_DISPLAY unset). Run this from the desktop."
  (steam_cmd &>/tmp/3dmark-helper-steam.log &)
  for _ in $(seq 1800); do
    detect_steam || true
    if logged_in; then
      ok "Login detected"
      sleep 5
      return 0
    fi
    sleep 2
  done
  die "Timed out waiting for Steam login"
}

wait_installed() {
  local id=$1 name=$2
  info "Waiting for $name to finish downloading (watch progress in Steam → Downloads)"
  for _ in $(seq 7200); do
    app_installed "$id" && {
      ok "$name installed"
      return 0
    }
    sleep 3
  done
  die "$name did not finish installing"
}

install_dir_of() {
  case $1 in "$APP_PROTON10") echo "Proton 10.0" ;; "$APP_PROTON_EXP") echo "Proton - Experimental" ;; "$APP_SLR3") echo "SteamLinuxRuntime_sniper" ;; *) app_name "$1" ;; esac
}

# Queue a download without any Steam dialog: Steam picks up an appmanifest with
# StateFlags 1026 (update required + update started) on its next start.
write_stub_manifest() {
  local id=$1 dir
  dir=$(install_dir_of "$id")
  cat >"$STEAM_ROOT/steamapps/appmanifest_$id.acf" <<EOM
"AppState"
{
	"appid"		"$id"
	"Universe"		"1"
	"name"		"$dir"
	"StateFlags"		"1026"
	"installdir"		"$dir"
	"LastUpdated"		"0"
	"SizeOnDisk"		"0"
	"buildid"		"0"
	"BytesToDownload"		"0"
	"BytesDownloaded"		"0"
	"AutoUpdateBehavior"		"0"
	"AllowOtherDownloadsWhileRunning"		"1"
	"ScheduledAutoUpdate"		"0"
}
EOM
}

cmd_install_apps() {
  detect_steam || die "Steam not found"
  logged_in || cmd_login
  local id want=()
  for id in $APP_SLR3 $APP_PROTON_EXP $APP_PROTON10 $APP_3DMARK $APP_3DMARK11 $APP_PCMARK10; do
    [[ $id == "$APP_3DMARK11" && ${SKIP_3DMARK11:-0} == 1 ]] && continue
    if [[ $id == "$APP_PCMARK10" || $id == "$APP_3DMARK11" ]] && ! owns_app "$id"; then
      continue # only install what the account owns
    fi
    app_installed "$id" && {
      ok "$(install_dir_of "$id") already installed"
      continue
    }
    want+=("$id")
  done
  ((${#want[@]})) || return 0
  # Install Proton 10 first so the apps can be mapped to it (not Experimental).
  local tools=() x
  for x in "${want[@]}"; do [[ $x == "$APP_PROTON10" || $x == "$APP_PROTON_EXP" || $x == "$APP_SLR3" ]] && tools+=("$x"); done
  if ((${#tools[@]})); then
    stop_steam
    for x in "${tools[@]}"; do write_stub_manifest "$x"; done
    (steam_cmd -silent &>/tmp/3dmark-helper-steam.log &)
    for x in "${tools[@]}"; do wait_installed "$x" "$(install_dir_of "$x")"; done
    local rest=()
    for x in "${want[@]}"; do [[ $x != "$APP_PROTON10" && $x != "$APP_PROTON_EXP" && $x != "$APP_SLR3" ]] && rest+=("$x"); done
    want=("${rest[@]}")
    ((${#want[@]})) || return 0
  fi
  stop_steam
  for id in "${want[@]}"; do
    # Windows-only apps need a Proton mapping BEFORE download or Steam fetches 0 depots.
    [[ $id != "$APP_PROTON10" ]] && $VDF compat "$STEAM_ROOT/config/config.vdf" "$id" "$(proton_tool)"
    write_stub_manifest "$id"
  done
  info "Queued: ${want[*]} — starting Steam in the background to download"
  (steam_cmd -silent &>/tmp/3dmark-helper-steam.log &)
  for id in "${want[@]}"; do wait_installed "$id" "$(install_dir_of "$id")"; done
  info "3DMark test DLCs download with the base game when owned; check Steam → 3DMark → Manage → DLC if a test is missing."
}

cmd_setup() {
  local id
  id=$(app_id "${1:-3dmark}")
  detect_steam || die "Steam not found"
  stop_steam
  local tool
  tool=$(proton_tool)
  info "Setting $id → $tool"
  $VDF compat "$STEAM_ROOT/config/config.vdf" "$id" "$tool"
  local lo
  lo=$(launch_options "$id")
  local f
  for f in $(user_configs); do $VDF launch "$f" "$id" "$lo"; done
  ok "Launch options: $lo"
}

# Steam blocks the first launch on the publisher EULA; that needs a human click.
eula_pending() {
  local log="$STEAM_ROOT/logs/console_log.txt"
  [[ -f $log ]] || return 1
  tail -n 400 "$log" | grep "AppID $1, " | tail -1 | grep -q 'waiting for user response to ShowEula'
}

cdkey_prompt_pending() {
  local log="$STEAM_ROOT/logs/console_log.txt"
  [[ -f $log ]] && tail -n 400 "$log" | grep "AppID $1, " | tail -1 | grep -q 'waiting for user response to ShowCDKey'
}

# Steam shows the CD key on launch until "Don't show me this again" is ticked; it blocks
# the launch. X11: handled automatically (and the key is kept). Wayland: one click by the user.
LAUNCH_KEY=""
handle_cdkey_prompt() {
  local id=$1 sc=steam k
  case $STEAM_KIND in snap) sc="snap run steam" ;; flatpak) sc="flatpak run com.valvesoftware.Steam" ;; esac
  if [[ ${XDG_SESSION_TYPE:-x11} != wayland ]] && command -v tesseract &>/dev/null; then
    k=$(python3 -I "$HERE/lib/cdkey.py" "$id" --no-open --steam-cmd "$sc" --timeout 60 2>/dev/null) && LAUNCH_KEY=$k
  else
    warn "Steam shows your $(app_name "$id") CD key: click the key once, tick \"Don't show me this again\", then Close." >&2
    k=$(wait_clipboard_key 300) && LAUNCH_KEY=$k
  fi
  for _ in $(seq 150); do
    cdkey_prompt_pending "$id" || return 0
    sleep 2
  done
}

eula_accepted() {
  local f
  for f in $(user_configs); do grep -q "\"${1}_eula_" "$f" && return 0; done
  return 1
}

launch_app() {
  local id=$1
  steam_cmd "steam://rungameid/$id" &>/dev/null &
  sleep 5
  if pgrep -f '[s]treaming_client' >/dev/null; then
    pkill -f '[s]treaming_client' || true
    die "Steam started Remote Play: $(app_name "$id") is running on another PC with this account. Close it there and retry."
  fi
  for _ in $(seq 20); do
    sleep 2
    if cdkey_prompt_pending "$id"; then handle_cdkey_prompt "$id"; fi
    if tail -n 200 "$STEAM_ROOT/logs/console_log.txt" 2>/dev/null | grep "AppID $id, " | tail -1 | grep -q 'waiting for user response to KickingOtherSession'; then
      die "Steam allows one running app per account: something (see Steam) is running on another PC with this account. Close it there, dismiss the prompt in Steam, and retry."
    fi
    if eula_pending "$id"; then
      warn "Steam is showing the license agreement (EULA) for app $id — accept it in the Steam window. Waiting..."
      for _ in $(seq 600); do
        eula_pending "$id" || return 0
        sleep 2
      done
      die "EULA was not accepted"
    fi
  done
}

# The prefix must already have run under the final Proton version: the first launch
# under a new version upgrades the prefix and drops earlier registry edits.
prefix_proton_version() {
  local p
  p=$(app_prefix "$1") || return 1
  cat "$p/../version" 2>/dev/null
}
# prefix format, e.g. 10.1000-105 (Proton 10) / 11.0-100 (Experimental, 11-based)
tool_version() {
  local d="$STEAM_ROOT/steamapps/common/Proton 10.0"
  [[ $(proton_tool) == proton_experimental ]] && d="$STEAM_ROOT/steamapps/common/Proton - Experimental"
  sed -n 's/^CURRENT_PREFIX_VERSION="\(.*\)"/\1/p' "$d/proton" 2>/dev/null | head -1
}
# wineserver pid serving this app's prefix (if any)
prefix_wineserver() {
  no_proc && return 1
  local p
  for p in $(pgrep -f '[w]ineserver' 2>/dev/null); do
    tr '\0' '\n' <"/proc/$p/environ" 2>/dev/null | grep -q "^WINEPREFIX=.*compatdata/$1/pfx" && {
      echo "$p"
      return 0
    }
  done
  return 1
}
stop_app() {
  local id=$1 ws exe
  if app_running "$id"; then
    pkill -f "$(app_proc "$id")" || true
    for _ in $(seq 30); do
      app_running "$id" || break
      sleep 2
    done
  fi
  # UL SystemInfo's scanner outlives the app under Wine and keeps the session (and Steam's
  # "running" state) alive: end the prefix's wineserver cleanly.
  sleep 3
  if ws=$(prefix_wineserver "$id"); then
    exe=$(readlink -f "/proc/$ws/exe")
    WINEPREFIX="$(app_prefix "$id")" "$exe" -k 2>/dev/null || true
    for _ in $(seq 20); do
      prefix_wineserver "$id" >/dev/null || return 0
      sleep 1
    done
  fi
  return 0
}
prefix_ready() {
  local id=$1 want
  want=$(tool_version)
  app_prefix "$id" >/dev/null && [[ -z $want || $(prefix_proton_version "$id") == "$want" ]]
}
ensure_prefix() {
  local id=$1
  prefix_ready "$id" && return 0
  local have want
  have=$(prefix_proton_version "$id" || true)
  want=$(tool_version)
  if [[ -n $have && -n $want ]] && [[ $(printf '%s\n%s\n' "$have" "$want" | sort -V | tail -1) == "$have" ]]; then
    # made by a newer Proton (e.g. 11): Proton can't downgrade it — move it aside, never delete
    local pfxdir
    pfxdir=$(dirname "$(app_prefix "$id")")
    stop_app "$id"
    mv "$pfxdir" "$pfxdir.bak-$(date +%Y%m%d%H%M%S)"
    warn "$(app_name "$id") prefix was made by Proton $have; moved it aside (backup kept) to recreate it with $want"
  fi
  info "Launching $(app_name "$id") once so Proton creates/upgrades its prefix"
  launch_app "$id"
  for _ in $(seq 150); do
    prefix_ready "$id" && app_running "$id" && break
    sleep 2
  done
  sleep 15
  stop_app "$id"
  sleep 3
  prefix_ready "$id" || die "prefix for $(app_name "$id") was not created"
}
user_reg() { echo "$(app_prefix "$1")/user.reg"; }
has_override() { grep -A60 'DllOverrides\]' "$(user_reg "$1")" 2>/dev/null | grep -q "\"\*$2\"=\"native"; }
# true when every key location holds a real key
has_key() {
  local id=$1 path sec
  [[ -z $(app_keyreg "$id") ]] && return 0
  while read -r path; do
    sec=${path#HKEY_CURRENT_USER\\}
    sec=${sec//\\/\\\\}
    grep -A3 -F "[$sec]" "$(user_reg "$id")" 2>/dev/null | grep -qE '"KeyCode"="[0-9A-Z]{2,6}(-[0-9A-Z]{3,6}){3,}"' || return 1
  done < <(app_keyreg "$id")
}
# a real key already present in any location (reused instead of asking Steam again)
existing_key() {
  # shellcheck disable=SC1003 # literal backslashes of the .reg format
  grep -A3 -E '^\[Software\\\\(UL|Futuremark)\\\\' "$(user_reg "$1")" 2>/dev/null |
    grep -oE '"KeyCode"="[0-9A-Z]{2,6}(-[0-9A-Z]{3,6}){3,}"' | head -1 | cut -d'"' -f4
}

# Wine rewrites user.reg when its wineserver exits: only edit an idle prefix.
wait_prefix_idle() {
  no_proc && return 0
  local id=$1 p busy
  for _ in $(seq 60); do
    busy=0
    for p in $(pgrep -f '[w]ineserver' 2>/dev/null); do
      tr '\0' '\n' <"/proc/$p/environ" 2>/dev/null | grep -q "^WINEPREFIX=.*compatdata/$id/pfx" && busy=1
    done
    ((busy)) || return 0
    sleep 2
  done
  die "$(app_name "$id") prefix is still in use; close the app and retry"
}
reg_set() { WINEREG_VALUE=$4 python3 -I "$HERE/lib/winereg.py" set "$1" "$2" "$3" -; }

# Native d3dcompiler_47 (the builtin one can't compile 3DMark's SM5.1 shaders).
# Same files and checksums as winetricks; installed without running Wine.
D3DC47_64=(https://raw.githubusercontent.com/mozilla/fxc2/master/dll/d3dcompiler_47.dll 4432bbd1a390874f3f0a503d45cc48d346abc3a8c0213c289f4b615bf0ee84f3)
D3DC47_32=(https://raw.githubusercontent.com/mozilla/fxc2/master/dll/d3dcompiler_47_32.dll 2ad0d4987fc4624566b190e747c9d95038443956ed816abfd1e2d389b5ec0851)
fetch() { # url sha256 -> cached path
  local cache="$HOME/.cache/3dmark-helper" f
  f="$cache/$(basename "$1")"
  mkdir -p "$cache"
  for c in "$f" "$HOME/.cache/winetricks/d3dcompiler_47/$(basename "$1")"; do
    [[ -f $c ]] && echo "$2  $c" | sha256sum -c --status && {
      echo "$c"
      return 0
    }
  done
  curl -fsSL --retry 3 -o "$f.part" "$1" && echo "$2  $f.part" | sha256sum -c --status && mv "$f.part" "$f" && echo "$f"
}
install_dll() {
  local id=$1 dll=$2 pfx src64 src32
  [[ $dll == d3dcompiler_47 ]] || die "unknown dll $dll"
  pfx=$(app_prefix "$id")
  src64=$(fetch "${D3DC47_64[@]}") && src32=$(fetch "${D3DC47_32[@]}") || die "could not download d3dcompiler_47"
  install -m644 "$src64" "$pfx/drive_c/windows/system32/d3dcompiler_47.dll"
  install -m644 "$src32" "$pfx/drive_c/windows/syswow64/d3dcompiler_47.dll"
  reg_set "$pfx/user.reg" 'Software\Wine\DllOverrides' '*d3dcompiler_47' 'native,builtin'
  info "$(app_name "$id"): installed native d3dcompiler_47"
}

cmd_prefix() {
  local id
  id=$(app_id "${1:-3dmark}")
  detect_steam || die "Steam not found"
  ensure_prefix "$id"
  stop_app "$id"
  wait_prefix_idle "$id"
  local verbs v
  verbs=$(app_verbs "$id")
  for v in $verbs; do has_override "$id" "$v" || install_dll "$id" "$v"; done
  for v in $verbs; do has_override "$id" "$v" || die "$v override missing after install ($(app_name "$id"))"; done
  ok "$(app_name "$id") prefix ready ($(prefix_proton_version "$id"), native ${verbs// /, })"
}

# Fetch the CD key without asking: X11 sessions read it from Steam's CD-key dialog
# (OCR locates the key, a click copies it). Wayland blocks synthetic input, so there
# the dialog is opened and the user's single click on the key is picked up.
get_key() {
  local id=$1 key
  [[ -n ${CDKEY:-} ]] && {
    echo "$CDKEY"
    return 0
  }
  import_session_env || true
  if [[ ${XDG_SESSION_TYPE:-x11} != wayland ]] && command -v tesseract &>/dev/null; then
    local sc=steam
    case $STEAM_KIND in snap) sc="snap run steam" ;; flatpak) sc="flatpak run com.valvesoftware.Steam" ;; esac
    key=$(python3 -I "$HERE/lib/cdkey.py" "$id" --steam-cmd "$sc" --timeout 60 2>/dev/null) && {
      echo "$key"
      return 0
    }
  fi
  warn "Click your $(app_name "$id") key in the Steam window that just opened (one click copies it)." >&2
  steam_cmd "steam://cdkeys/$id" &>/dev/null &
  wait_clipboard_key 300
}

cmd_key() {
  local id
  id=$(app_id "${1:-3dmark}")
  detect_steam || die "Steam not found"
  [[ -z $(app_keyreg "$id") ]] && {
    ok "$(app_name "$id") uses Steam ownership (no CD key needed)"
    return 0
  }
  ensure_prefix "$id"
  if has_key "$id"; then
    ok "$(app_name "$id") key already registered"
    return 0
  fi
  local key
  key=${2:-}
  [[ -n $key ]] || key=$(existing_key "$id" || true)
  [[ -n $key ]] || key=$LAUNCH_KEY
  [[ -n $key ]] || key=$(get_key "$id") || true
  [[ $key =~ ^[0-9A-Z]{2,6}(-[0-9A-Z]{3,6}){3,6}$ ]] || {
    warn "no CD key obtained for $(app_name "$id") — it will open in demo mode"
    return 0
  }
  stop_app "$id"
  wait_prefix_idle "$id"
  local pfx path
  pfx=$(app_prefix "$id")
  while read -r path; do
    reg_set "$pfx/user.reg" "${path#HKEY_CURRENT_USER\\}" KeyCode "$key" # value via env, never in ps
  done < <(app_keyreg "$id")
  has_key "$id" && ok "$(app_name "$id") key registered" || die "could not write the $(app_name "$id") key into the prefix"
}

clipboard() {
  # Steam runs under X11/XWayland, so its copy lands in the X clipboard; Wayland
  # compositors (Mutter, KWin, labwc) sync it to the Wayland one as well.
  local c=""
  command -v xclip &>/dev/null && c=$(xclip -o -selection clipboard 2>/dev/null)
  [[ -z $c ]] && command -v xsel &>/dev/null && c=$(xsel -ob 2>/dev/null)
  [[ -z $c && -n ${WAYLAND_DISPLAY:-} ]] && command -v wl-paste &>/dev/null && c=$(wl-paste -n 2>/dev/null)
  [[ -z $c ]] && command -v qdbus &>/dev/null && c=$(qdbus org.kde.klipper /klipper getClipboardContents 2>/dev/null)
  [[ -z $c ]] && command -v qdbus6 &>/dev/null && c=$(qdbus6 org.kde.klipper /klipper getClipboardContents 2>/dev/null)
  printf '%s' "$c"
}
# A real key looks like 3DM-ICF-XXXXX-XXXXX-XXXXX-XXXXX (older: 4-char groups).
wait_clipboard_key() {
  local t=$1 c
  for _ in $(seq "$t"); do
    c=$(clipboard | tr -d '[:space:]') || true
    [[ $c =~ ^[0-9A-Z]{2,4}(-[0-9A-Z]{3,6}){3,6}$ ]] && {
      echo "$c"
      return 0
    }
    sleep 1
  done
  return 1
}

# App-menu entries + taskbar icon. Proton windows carry WM_CLASS steam_app_<id>,
# so StartupWMClass makes GNOME/XFCE docks show the right icon for the running app.
cmd_shortcuts() {
  detect_steam || die "Steam not found"
  local id name exe desc dir steam_exec
  case $STEAM_KIND in
    snap) steam_exec="snap run steam" ;;
    flatpak) steam_exec="flatpak run com.valvesoftware.Steam" ;;
    *) steam_exec="steam" ;;
  esac
  local appsdir="$HOME/.local/share/applications" icondir="$HOME/.local/share/icons/hicolor/256x256/apps"
  mkdir -p "$appsdir" "$icondir"
  local app
  for app in "${ALL_APPS[@]}"; do
    id=$(app_id "$app")
    name=$(app_name "$id")
    exe=$(app_exe "$id")
    desc="$(app_desc "$id") (Steam, Proton)"
    app_installed "$id" || continue
    dir="$(dirname "$(app_manifest "$id")")/common"
    python3 -I "$HERE/lib/exeicon.py" "$dir/$exe" "$icondir/steam_icon_$id.png" 256 2>/dev/null ||
      warn "could not extract icon for $name"
    cat >"$appsdir/3dmark-helper-$id.desktop" <<EOD
[Desktop Entry]
Type=Application
Name=$name
Comment=$desc
Exec=$steam_exec steam://rungameid/$id
Icon=steam_icon_$id
Terminal=false
Categories=Game;
Keywords=benchmark;gpu;cpu;3dmark;pcmark;ul;futuremark;
StartupWMClass=steam_app_$id
StartupNotify=true
EOD
    chmod +x "$appsdir/3dmark-helper-$id.desktop"
    ok "menu entry: $name"
  done
  update-desktop-database "$appsdir" &>/dev/null || true
  gtk-update-icon-cache -f -t "$HOME/.local/share/icons/hicolor" &>/dev/null || true
  # KDE Plasma caches menus in ksycoca; GNOME/XFCE/LXQt watch the XDG dirs directly.
  local k
  for k in kbuildsycoca6 kbuildsycoca5; do command -v "$k" &>/dev/null && {
    "$k" &>/dev/null || true
    break
  }; done
  xdg-desktop-menu forceupdate &>/dev/null || true
}

# 3DMark tests are Steam DLC that the app normally installs one by one from its UI.
# Steam keeps that selection in appmanifest UserConfig/optionaldlc, so preselect them all.
# IDs from the Steam store (appdetails "dlc" of 223850). Storage Benchmark (30 GB) only with STORAGE=1.
DLC_3DMARK=(
  402290  # Fire Strike, Extreme, Ultra
  496100  # Time Spy
  496101  # Time Spy upgrade (Extreme)
  496102  # Night Raid
  496103  # Port Royal
  2019730 # Speed Way
  2695340 # Steel Nomad, Steel Nomad Light
  1654370 # CPU Profile
  393480  # Sky Diver
  406960  # Cloud Gate
  406950  # Ice Storm
  1276160 # Wild Life, Wild Life Extreme
  2313300 # Solar Bay
  3941790 # Solar Bay Extreme
  407080  # API Overhead feature test
  1498800 # Mesh Shader feature test
  496104  # PCI Express feature test
  1498801 # Sampler Feedback feature test
  556150  # VRS feature test
)
DLC_3DMARK_STORAGE=1322770

cmd_tests() {
  detect_steam || die "Steam not found"
  local m
  m=$(app_manifest $APP_3DMARK) || die "3DMark not installed"
  local want=("${DLC_3DMARK[@]}")
  [[ ${STORAGE:-0} == 1 ]] && want+=("$DLC_3DMARK_STORAGE")
  local cur
  cur=$($VDF get "$m" AppState/UserConfig/optionaldlc 2>/dev/null || true)
  local all
  local cur_ids
  IFS=, read -r -a cur_ids <<<"$cur"
  all=$(printf '%s\n' "${cur_ids[@]}" "${want[@]}" | grep -E '^[0-9]+$' | sort -un | paste -sd,)
  if [[ $all == "$cur" ]]; then ok "all 3DMark tests already selected"; else
    stop_steam
    $VDF set "$m" AppState/UserConfig/optionaldlc "$all"
    sed -i -E 's/("StateFlags"\s+)"4"/\1"6"/' "$m" # 4|2 = installed + update required
    info "Selected ${#want[@]} 3DMark tests for download — starting Steam"
    (steam_cmd -silent &>/tmp/3dmark-helper-steam.log &)
  fi
  # wait for the update to start (StateFlags != 4) and then settle back to 4 (installed)
  local started=0 stable=0 f
  no_proc && return 0 # tests: Steam isn't running, nothing to wait for
  for _ in $(seq 7200); do
    f=$($VDF get "$m" AppState/StateFlags 2>/dev/null || echo 0)
    if [[ $f != 4 ]]; then
      started=1
      stable=0
    else stable=$((stable + 1)); fi
    { [[ $started == 1 ]] || [[ $all == "$cur" ]]; } && ((stable >= 6)) && break
    sleep 5
  done
  ok "3DMark tests installed: $(find "$(dirname "$m")/common/3DMark/dlc" -mindepth 1 -maxdepth 1 -type d -printf '%f ' 2>/dev/null)"
}

# UL SystemInfo under Proton. Out of the box its COM service (FMSISvc) can't be reached:
#  1. its class is registered only in the 32-bit view (Wow6432Node) -> 64-bit apps get
#     "class not registered" (3DMark 11: "SystemInfo initialization failed");
#  2. when started on demand it asks the SCM to start RpcSs from inside its own start
#     and Wine fails that nested start;
#  3. the typelib used for 32/64-bit marshaling has only a win32 entry.
# fix: mirror the classes to the 64-bit view, auto-start RpcSs, add the win64 typelib entry.
SI_TYPELIB='Software\Classes\Typelib\{0E985ACA-E998-460F-B705-8436E606F78C}\1.0\0'
si_fix_prefix() {
  local id=$1 pfx sys W="python3 -I $HERE/lib/winereg.py"
  pfx=$(app_prefix "$id") || return 0
  [[ -d "$pfx/drive_c/Program Files (x86)/Futuremark/SystemInfo" ]] || return 0
  sys="$pfx/system.reg"
  stop_app "$id"
  wait_prefix_idle "$id"
  $W set "$sys" 'System\ControlSet001\Services\RpcSs' Start dword:00000002
  $W mirror-wow64 "$sys" 'Futuremark\SystemInfo' >/dev/null
  local lib
  lib=$($W get "$sys" "$SI_TYPELIB\\win32" @ 2>/dev/null || true)
  [[ -n $lib ]] && $W set "$sys" "$SI_TYPELIB\\win64" @ "$lib"
  ok "$(app_name "$id"): SystemInfo service made reachable"
}
settings_file() {
  local pfx
  pfx=$(app_prefix "$1") || return 1
  case $1 in
    "$APP_PCMARK10") echo "$pfx/drive_c/users/steamuser/AppData/Local/UL/PCMark 10/app-settings.json" ;;
    "$APP_3DMARK") echo "$pfx/drive_c/users/steamuser/AppData/Local/UL/3DMark/app-settings.json" ;;
    *) return 1 ;;
  esac
}
cmd_systeminfo() {
  local si_mode=${1:-fix} app id f
  [[ $si_mode =~ ^(fix|on|off)$ ]] || die "usage: systeminfo fix|on|off"
  detect_steam || die "Steam not found"
  for app in "${ALL_APPS[@]}"; do
    id=$(app_id "$app")
    app_installed "$id" || continue
    si_fix_prefix "$id"
    [[ $si_mode == fix ]] && continue
    f=$(settings_file "$id") || continue
    [[ -f $f ]] || {
      warn "$(app_name "$id"): settings not created yet (launch it once)"
      continue
    }
    stop_app "$id"
    python3 -I "$HERE/lib/appsettings.py" "$f" "$si_mode" >/dev/null && ok "$(app_name "$id"): SystemInfo scan $si_mode"
  done
}

# Real title bars where the window manager can be told to override the app's
# borderless window: KDE (KWin rule), LXQt X11 (Openbox), LXQt Wayland (labwc).
# GNOME/Mutter can't; XFCE (xfwm4) already does it.
detect_desktop() {
  import_session_env || true
  local d=${XDG_CURRENT_DESKTOP:-}
  case ${d,,} in
    *kde* | *plasma*) echo kde ;;
    *lxqt*) if [[ ${XDG_SESSION_TYPE:-} == wayland ]] || pgrep -x labwc >/dev/null; then echo lxqt-labwc; else echo lxqt-openbox; fi ;;
    *xfce*) echo xfce ;;
    *gnome* | *unity* | *ubuntu*) echo gnome ;;
    *) pgrep -x openbox >/dev/null && echo lxqt-openbox || echo other ;;
  esac
}
cmd_titlebar() {
  local de r
  de=$(detect_desktop)
  case $de in
    kde)
      r=$(python3 -I "$HERE/lib/titlebar.py" kde "${XDG_CONFIG_HOME:-$HOME/.config}/kwinrulesrc")
      { qdbus6 org.kde.KWin /KWin reconfigure || qdbus org.kde.KWin /KWin reconfigure ||
        dbus-send --session --type=method_call --dest=org.kde.KWin /KWin org.kde.KWin.reconfigure; } &>/dev/null || true
      ok "KDE: KWin rule forces a title bar on 3DMark/PCMark windows ($r)"
      ;;
    lxqt-openbox)
      r=$(python3 -I "$HERE/lib/titlebar.py" openbox "${XDG_CONFIG_HOME:-$HOME/.config}/openbox/lxqt-rc.xml")
      openbox --reconfigure &>/dev/null || true
      ok "LXQt (Openbox): title bar rule added ($r)"
      ;;
    lxqt-labwc)
      r=$(python3 -I "$HERE/lib/titlebar.py" labwc "${XDG_CONFIG_HOME:-$HOME/.config}/labwc/rc.xml")
      labwc --reconfigure &>/dev/null || true
      ok "LXQt (labwc): title bar rule added ($r)"
      ;;
    xfce) ok "XFCE: xfwm4 already draws title bars" ;;
    gnome) warn "GNOME can't add a title bar to 3DMark's borderless window: Super+H minimise, Super+↑ maximise, Alt+F4 close" ;;
    *) warn "unknown desktop '${XDG_CURRENT_DESKTOP:-?}': no title-bar rule written" ;;
  esac
}

cmd_logs() {
  detect_steam || die "Steam not found"
  local out
  out="$HOME/3dmark-helper-logs-$(date +%Y%m%d-%H%M%S).tar.gz"
  local tmp
  tmp=$(mktemp -d)
  cmd_doctor >"$tmp/doctor.txt" 2>&1 || true
  cp "$HOME"/steam-$APP_3DMARK.log "$HOME"/steam-$APP_3DMARK11.log "$tmp/" 2>/dev/null || true
  local id pfx
  for id in $APP_3DMARK $APP_3DMARK11 $APP_PCMARK10; do
    pfx=$(app_prefix "$id") || continue
    find "$pfx/drive_c/users" \( -path '*3DMark*' -o -path '*PCMark*' \) \( -name '*.log' -o -name '*.txt' -o -name '*.xml' \) -size -5M -exec cp --parents {} "$tmp/" \; 2>/dev/null || true
  done
  tar -C "$tmp" -czf "$out" . && rm -rf "$tmp"
  ok "logs: $out   (set PROTON_LOG=1 in launch options to get steam-<appid>.log in ~)"
}

cmd_install() {
  cmd_deps
  cmd_install_steam
  cmd_login
  cmd_install_apps
  app_installed $APP_3DMARK && cmd_tests
  local app id
  for app in "${ALL_APPS[@]}"; do
    id=$(app_id "$app")
    app_installed "$id" || continue
    cmd_setup "$app"
    cmd_prefix "$app"
    cmd_key "$app"
  done
  cmd_systeminfo off # service fix for all + scan off (3DMark otherwise blocks Time Spy: "CPU lacks SSSE3")
  cmd_shortcuts
  cmd_titlebar
  cmd_doctor || true
  info "Done. Start 3DMark / PCMark from your app menu or Steam. Working tests: Fire Strike, Time Spy, Port Royal (RT GPUs), Night Raid, Sky Diver, Cloud Gate, Ice Storm, CPU Profile, feature tests. See README for the full matrix."
}

usage() {
  cat <<EOF
Usage: $0 [--ask] <command> [args]   (default: fully automatic)
  install                 full guided flow: deps, Steam, login, install apps, configure
  doctor                  check everything and print a pass/fail report
  deps                    install 32-bit Vulkan, OCR/X tools, etc. (sudo)
  install-steam           install Steam if missing
  login                   start Steam and wait for you to log in
  install-apps            install Proton 10 + every owned app (3DMark, 3DMark 11, PCMark 10)
  setup <app>             pin Proton version + set launch options (closes Steam)
  prefix <app>            create Proton prefix + d3dcompiler_43/47
  key <app> [KEY]         fetch the CD key from Steam automatically and register it
  launch-options <app>    print recommended launch options for this machine
  headless                force a display output on monitor-less (VNC) machines so Steam can show windows
  systeminfo fix|on|off   make UL SystemInfo reachable under Proton (always) and toggle 3DMark/PCMark scanning.
                          install uses "off": with scanning on, 3DMark wrongly blocks Time Spy/Night Raid
                          ("CPU does not support SSSE3") because Wine hides the CPU feature flags
  tests                   download every 3DMark test that works on Linux (STORAGE=1 adds the 30 GB storage test)
  titlebar                real title bars on KDE (KWin rule) and LXQt (Openbox / labwc rule)
  shortcuts               add 3DMark / 3DMark 11 to the app menu with proper icons
  logs                    bundle diagnostics into ~/3dmark-helper-logs-*.tar.gz
Apps: 3dmark, 3dmark11, pcmark10
Env: PROTON_TOOL=proton_experimental  OSMESA=1 (blank launcher fix)  SKIP_3DMARK11=1  ASSUME_YES=1
EOF
}

main() {
  [[ ${1:-} == -y ]] && {
    ASSUME_YES=1
    shift
  }
  [[ ${1:-} == --ask ]] && {
    ASSUME_YES=0
    shift
  }
  local c=${1:-install}
  shift || true
  case $c in
    install) cmd_install ;;
    doctor) cmd_doctor ;;
    deps) cmd_deps ;;
    install-steam) cmd_install_steam ;;
    login) cmd_login ;;
    install-apps) cmd_install_apps ;;
    setup) cmd_setup "$@" ;;
    prefix) cmd_prefix "$@" ;;
    key) cmd_key "$@" ;;
    launch-options)
      detect_steam || true
      launch_options "$(app_id "${1:-3dmark}")"
      ;;
    logs) cmd_logs ;;
    tests) cmd_tests ;;
    systeminfo) cmd_systeminfo "$@" ;;
    shortcuts) cmd_shortcuts ;;
    titlebar) cmd_titlebar ;;
    headless) cmd_headless ;;
    -V | --version | version) echo "linux-steam-3dmark-helper $VERSION" ;;
    -h | --help | help) usage ;;
    *)
      usage
      exit 2
      ;;
  esac
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then main "$@"; fi
