#!/usr/bin/env bash
# linux-steam-3dmark-helper — get Steam 3DMark (223850) and 3DMark 11 (205270)
# running under Proton on Ubuntu / Xubuntu (and other Debian-based distros).
# https://github.com/ventura8/linux-steam-3dmark-helper
set -euo pipefail

VERSION=0.1.1
HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
VDF="python3 $HERE/lib/vdfedit.py"

APP_3DMARK=223850
APP_3DMARK11=205270
APP_PROTON10=3658110        # "Proton 10.0" tool app
APP_PROTON_EXP=1493710      # "Proton - Experimental"

# ---------- output helpers ----------
if [[ -t 1 ]]; then C_G=$'\e[32m'; C_R=$'\e[31m'; C_Y=$'\e[33m'; C_B=$'\e[1m'; C_0=$'\e[0m'; else C_G=; C_R=; C_Y=; C_B=; C_0=; fi
ok()   { printf '  %s[ OK ]%s %s\n' "$C_G" "$C_0" "$*"; }
bad()  { printf '  %s[FAIL]%s %s\n' "$C_R" "$C_0" "$*"; FAILS=$((FAILS+1)); }
warn() { printf '  %s[WARN]%s %s\n' "$C_Y" "$C_0" "$*"; }
info() { printf '%s==>%s %s\n' "$C_B" "$C_0" "$*"; }
die()  { printf '%sERROR:%s %s\n' "$C_R" "$C_0" "$*" >&2; exit 1; }
FAILS=0
ASSUME_YES=${ASSUME_YES:-1}   # automagic by default; --ask to confirm each step
confirm() { [[ $ASSUME_YES == 1 ]] && return 0; read -r -p "$1 [Y/n] " a; [[ -z $a || $a =~ ^[Yy] ]]; }

app_id() {
  case "${1:-}" in
    3dmark|223850) echo $APP_3DMARK ;;
    3dmark11|205270) echo $APP_3DMARK11 ;;
    *) die "unknown app '$1' (use 3dmark or 3dmark11)" ;;
  esac
}

# ---------- Steam detection ----------
STEAM_KIND=""; STEAM_ROOT=""
detect_steam() {
  local c
  for c in "$HOME/.local/share/Steam:deb" "$HOME/.steam/debian-installation:deb" \
           "$HOME/snap/steam/common/.local/share/Steam:snap" \
           "$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam:flatpak"; do
    if [[ -f ${c%:*}/config/config.vdf || -d ${c%:*}/steamapps ]]; then
      STEAM_ROOT=${c%:*}; STEAM_KIND=${c##*:}; return 0
    fi
  done
  if snap list steam &>/dev/null; then STEAM_KIND=snap; STEAM_ROOT="$HOME/snap/steam/common/.local/share/Steam"; return 1; fi
  if flatpak info com.valvesoftware.Steam &>/dev/null; then STEAM_KIND=flatpak; STEAM_ROOT="$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam"; return 1; fi
  if command -v steam &>/dev/null; then STEAM_KIND=deb; STEAM_ROOT="$HOME/.local/share/Steam"; return 1; fi
  return 1
}

# When run over SSH/TTY, borrow the logged-in desktop session's environment;
# without D-Bus/XDG/Xauthority Steam starts but never shows its window.
import_session_env() {
  [[ -n ${DBUS_SESSION_BUS_ADDRESS:-} && -n ${DISPLAY:-}${WAYLAND_DISPLAY:-} ]] && return 0
  local p pid
  for p in gnome-shell plasmashell xfce4-panel lxqt-panel xfce4-session lxqt-session ksmserver; do
    pid=$(pgrep -u "$(id -u)" -x "$p" | head -1) && [[ -n $pid ]] && break
  done
  [[ -n ${pid:-} && -r /proc/$pid/environ ]] || return 1
  local line
  while IFS= read -r -d '' line; do
    case $line in
      DISPLAY=*|WAYLAND_DISPLAY=*|XAUTHORITY=*|DBUS_SESSION_BUS_ADDRESS=*|XDG_RUNTIME_DIR=*|XDG_CURRENT_DESKTOP=*|XDG_SESSION_TYPE=*)
        export "${line?}" ;;
    esac
  done < "/proc/$pid/environ"
}

steam_cmd() {
  import_session_env || true
  case $STEAM_KIND in
    snap) snap run steam "$@" ;;
    flatpak) flatpak run com.valvesoftware.Steam "$@" ;;
    *) steam "$@" ;;
  esac
}

steam_running() { pgrep -x steam >/dev/null || pgrep -f 'ubuntu12_32/steam' >/dev/null; }

stop_steam() {
  steam_running || return 0
  info "Closing Steam (config files are only safe to edit while it is closed)"
  steam_cmd -shutdown &>/dev/null || true
  for _ in $(seq 60); do steam_running || return 0; sleep 1; done
  die "Steam is still running; close it manually and retry."
}

library_dirs() {
  local f="$STEAM_ROOT/steamapps/libraryfolders.vdf"
  echo "$STEAM_ROOT"
  [[ -f $f ]] && grep -oP '"path"\s+"\K[^"]+' "$f" | grep -vxF "$STEAM_ROOT" || true
}

app_manifest() { local d; for d in $(library_dirs); do [[ -f $d/steamapps/appmanifest_$1.acf ]] && { echo "$d/steamapps/appmanifest_$1.acf"; return 0; }; done; return 1; }
# Installed = StateFlags 4 AND real content (a Windows-only app with no Proton mapping
# "installs" with 0 depots and an empty folder).
app_installed() {
  local m; m=$(app_manifest "$1") || return 1
  grep -qP '"StateFlags"\s+"4"' "$m" || return 1
  python3 -c 'import re,sys; t=open(sys.argv[1]).read(); m=re.search(r"\"InstalledDepots\"\s*\{\s*\"\d+",t); sys.exit(0 if m else 1)' "$m"
}
app_prefix() { local d; for d in $(library_dirs); do [[ -d $d/steamapps/compatdata/$1/pfx ]] && { echo "$d/steamapps/compatdata/$1/pfx"; return 0; }; done; return 1; }

user_configs() { ls "$STEAM_ROOT"/userdata/*/config/localconfig.vdf 2>/dev/null || true; }

logged_in() {
  [[ -f $STEAM_ROOT/config/loginusers.vdf ]] && grep -q '"7656' "$STEAM_ROOT/config/loginusers.vdf" && [[ -n $(user_configs) ]]
}

proton_tool() {
  # Proton 11 currently breaks every DX12 test (Proton#4034, May 2026) -> prefer 10, then Experimental.
  if [[ -n ${PROTON_TOOL:-} ]]; then echo "$PROTON_TOOL"; return; fi
  if app_installed $APP_PROTON10; then echo proton_10; else echo proton_experimental; fi
}

# ---------- GPU detection ----------
GPU_VENDORS=""
detect_gpus() {
  GPU_VENDORS=$(lspci -nn | grep -iE 'vga|3d controller|display' | grep -oE '\[(10de|1002|8086):' | tr -d '[:' | sort -u | tr '\n' ' ')
}
has_gpu() { [[ " $GPU_VENDORS " == *" $1 "* ]]; }
nvidia_ver() { nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -1 | cut -d. -f1; }

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
  [[ ${OSMESA:-0} == 1 ]] && { echo "${env[*]} %command% --use-gl=osmesa"; return; }
  echo "${env[*]} %command%"
}

# ---------- commands ----------
cmd_doctor() {
  FAILS=0
  info "System"
  . /etc/os-release; ok "$PRETTY_NAME, kernel $(uname -r), desktop ${XDG_CURRENT_DESKTOP:-?} (${XDG_SESSION_TYPE:-?})"
  detect_gpus
  while read -r l; do ok "GPU: $l"; done < <(lspci | grep -iE 'vga|3d controller|display' | cut -d: -f3-)
  info "Drivers / Vulkan"
  dpkg --print-foreign-architectures | grep -qx i386 && ok "i386 architecture enabled" || bad "i386 architecture not enabled (run: $0 deps)"
  for p in libvulkan1:i386 mesa-vulkan-drivers:i386; do
    dpkg -s "$p" &>/dev/null && ok "$p" || bad "$p missing (launcher will not start without 32-bit Vulkan)"
  done
  if has_gpu 10de; then
    local v; v=$(nvidia_ver)
    [[ -n $v ]] && ok "NVIDIA driver $v" || bad "NVIDIA GPU present but nvidia-smi not working"
    [[ -n $v ]] && { dpkg -s "libnvidia-gl-$v:i386" &>/dev/null && ok "libnvidia-gl-$v:i386" || bad "libnvidia-gl-$v:i386 missing"; }
  fi
  command -v vulkaninfo &>/dev/null && { vulkaninfo --summary 2>/dev/null | grep -E 'deviceName' | sed 's/^ */  /' || true; } || warn "vulkan-tools not installed"
  command -v protontricks &>/dev/null && ok "protontricks $(protontricks --version 2>/dev/null | head -1)" || bad "protontricks missing"
  info "Steam"
  if detect_steam; then ok "Steam ($STEAM_KIND) at $STEAM_ROOT"; else bad "Steam not installed / never started"; return 1; fi
  logged_in && ok "a Steam account is logged in" || bad "no Steam login yet"
  for t in $APP_PROTON10:"Proton 10" $APP_PROTON_EXP:"Proton Experimental"; do
    app_installed "${t%%:*}" && ok "${t#*:} installed" || warn "${t#*:} not installed"
  done
  ok "Proton tool that will be used: $(proton_tool)"
  local id name
  for id in $APP_3DMARK $APP_3DMARK11; do
    name=$([[ $id == "$APP_3DMARK" ]] && echo 3DMark || echo "3DMark 11")
    if app_installed "$id"; then ok "$name installed ($(app_manifest "$id" | xargs dirname))"
    else bad "$name ($id) not installed"; continue; fi
    local tool; tool=$($VDF get "$STEAM_ROOT/config/config.vdf" "InstallConfigStore/Software/Valve/Steam/CompatToolMapping/$id/name" 2>/dev/null || true)
    [[ -n $tool ]] && ok "$name compat tool: $tool" || warn "$name: no forced Proton version (run setup)"
    [[ $tool == proton_11* ]] && bad "$name forced to Proton 11 — DX12 tests break there"
    local lo; lo=$(for f in $(user_configs); do $VDF get "$f" "UserLocalConfigStore/Software/Valve/Steam/apps/$id/LaunchOptions" 2>/dev/null; done | head -1)
    [[ -n $lo ]] && ok "$name launch options: $lo" || warn "$name: no launch options set"
    app_prefix "$id" >/dev/null && ok "$name Proton prefix exists" || warn "$name: no prefix yet (launch once)"
  done
  if app_installed $APP_3DMARK; then
    local dir; dir="$(dirname "$(app_manifest $APP_3DMARK)")/common/3DMark/dlc"
    [[ -d $dir ]] && ok "3DMark test DLCs present: $(ls "$dir" | tr '\n' ' ')" || warn "no 3DMark test DLC folders found (install them in Steam → 3DMark → DLC)"
  fi
  echo; [[ $FAILS == 0 ]] && info "${C_G}All checks passed${C_0}" || info "${C_R}$FAILS problem(s)${C_0} — run: $0 install"
}

cmd_deps() {
  info "Installing system dependencies (needs sudo)"
  detect_gpus
  local pkgs=(libvulkan1 libvulkan1:i386 mesa-vulkan-drivers mesa-vulkan-drivers:i386 vulkan-tools protontricks winetricks python3 pciutils xclip wl-clipboard)
  if has_gpu 10de; then
    local v; v=$(nvidia_ver)
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
    local fix; fix=$(sed -nE 's/.* ([^ ]+):i386 Breaks [^ ]+ \(!= ([^)]+)\).*/\1 \2/p' <<<"$out" | sort -u | head -5)
    [[ -z $fix ]] && break
    local name ver
    local src b
    while read -r name ver; do
      src=$(dpkg-query -W -f='${source:Package}' "$name" 2>/dev/null)
      warn "multiarch mismatch in source '$src' ($name): aligning to $ver (downgrade)"
      # every installed binary from the same source at the orphaned version must move together
      while read -r b _; do
        [[ " ${extra[*]} " == *" $b=$ver "* ]] || extra+=("$b=$ver")
      done < <(dpkg-query -W -f='${source:Package} ${Package} ${Version} ${db:Status-Abbrev}\n' 2>/dev/null \
                 | awk -v s="$src" -v v="$ver" '$1==s && $3!=v && $4 ~ /^ii/ {print $2, $3}')
      extra+=("$name:i386=$ver")
    done <<<"$fix"
  done
  if ((${#extra[@]})); then confirm "Apply version alignment: ${extra[*]}?" || return 1; fi
  sudo apt-get install -y --allow-downgrades "${pkgs[@]}" "${extra[@]}"
}

cmd_install_steam() {
  if detect_steam || [[ -n $STEAM_KIND ]]; then ok "Steam already installed ($STEAM_KIND)"; return 0; fi
  info "Installing Steam (official Valve installer package from Ubuntu multiverse)"
  confirm "Install steam-installer via apt?" || return 1
  sudo add-apt-repository -y multiverse >/dev/null 2>&1 || true
  sudo apt-get update
  sudo apt-get install -y steam-installer steam-devices
  STEAM_KIND=deb; STEAM_ROOT="$HOME/.local/share/Steam"
}

# Headless boxes (VNC, no monitor): Steam's UI refuses to create windows when X has
# no connected output ("Failed to create popup"). Force the first HDMI/DP connector on.
cmd_headless() {
  import_session_env || true
  [[ ${XDG_SESSION_TYPE:-x11} == x11 && -n ${DISPLAY:-} ]] || return 0
  command -v xrandr &>/dev/null || return 0
  if xrandr 2>/dev/null | grep -q ' connected'; then return 0; fi
  local c; c=$(ls -d /sys/class/drm/card*-HDMI-A-1 /sys/class/drm/card*-DP-1 2>/dev/null | head -1)
  [[ -n $c ]] || { warn "headless and no HDMI/DP connector found — plug in a monitor or HDMI dummy plug"; return 0; }
  warn "No monitor connected (headless/VNC). Forcing ${c##*/} on so Steam can open windows (sudo)."
  echo on | sudo tee "$c/status" >/dev/null || return 1
  sleep 2
  local out; out=$(xrandr | awk '/ connected/{print $1; exit}')
  [[ -n $out ]] && xrandr --output "$out" --auto
  ok "virtual display active on $out (lost on reboot; for permanent: HDMI dummy plug or kernel arg video=${c##*card?-}:1920x1080@60e)"
}

cmd_login() {
  detect_steam || true
  if logged_in && steam_running; then ok "Steam is running and logged in"; return 0; fi
  cmd_headless || true
  info "Starting Steam — log in with your account in the Steam window (first start downloads ~400 MB)"
  import_session_env || true
  [[ -z ${DISPLAY:-}${WAYLAND_DISPLAY:-} ]] && die "No graphical session (DISPLAY/WAYLAND_DISPLAY unset). Run this from the desktop."
  (steam_cmd &>/tmp/3dmark-helper-steam.log &)
  for _ in $(seq 1800); do
    detect_steam || true
    if logged_in; then ok "Login detected"; sleep 5; return 0; fi
    sleep 2
  done
  die "Timed out waiting for Steam login"
}

wait_installed() {
  local id=$1 name=$2
  info "Waiting for $name to finish downloading (watch progress in Steam → Downloads)"
  for _ in $(seq 7200); do app_installed "$id" && { ok "$name installed"; return 0; }; sleep 3; done
  die "$name did not finish installing"
}

install_dir_of() {
  case $1 in "$APP_3DMARK") echo 3DMark ;; "$APP_3DMARK11") echo "3DMark 11" ;; "$APP_PROTON10") echo "Proton 10.0" ;; esac
}

# Queue a download without any Steam dialog: Steam picks up an appmanifest with
# StateFlags 1026 (update required + update started) on its next start.
write_stub_manifest() {
  local id=$1 dir; dir=$(install_dir_of "$id")
  cat > "$STEAM_ROOT/steamapps/appmanifest_$id.acf" <<EOM
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
  for id in $APP_PROTON10 $APP_3DMARK $APP_3DMARK11; do
    [[ $id == "$APP_3DMARK11" && ${SKIP_3DMARK11:-0} == 1 ]] && continue
    app_installed "$id" && { ok "$(install_dir_of "$id") already installed"; continue; }
    want+=("$id")
  done
  ((${#want[@]})) || return 0
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
  local id; id=$(app_id "${1:-3dmark}")
  detect_steam || die "Steam not found"
  stop_steam
  local tool; tool=$(proton_tool)
  info "Setting $id → $tool"
  $VDF compat "$STEAM_ROOT/config/config.vdf" "$id" "$tool"
  local lo; lo=$(launch_options "$id")
  local f; for f in $(user_configs); do $VDF launch "$f" "$id" "$lo"; done
  ok "Launch options: $lo"
}

proton_run() {
  # protontricks wrapper that works for deb/snap/flatpak Steam
  local id=$1; shift
  STEAM_DIR="$STEAM_ROOT" protontricks "$@" "$id"
}

# Steam blocks the first launch on the publisher EULA; that needs a human click.
eula_pending() {
  local log="$STEAM_ROOT/logs/console_log.txt"
  [[ -f $log ]] || return 1
  tail -n 400 "$log" | grep "AppID $1, " | tail -1 | grep -q 'waiting for user response to ShowEula'
}

launch_app() {
  local id=$1
  steam_cmd "steam://rungameid/$id" &>/dev/null &
  for _ in $(seq 20); do
    sleep 2
    if eula_pending "$id"; then
      warn "Steam is showing the license agreement (EULA) for app $id — accept it in the Steam window. Waiting..."
      for _ in $(seq 600); do eula_pending "$id" || return 0; sleep 2; done
      die "EULA was not accepted"
    fi
  done
}

cmd_prefix() {
  local id; id=$(app_id "${1:-3dmark}")
  detect_steam || die "Steam not found"
  if ! app_prefix "$id" >/dev/null; then
    info "No Proton prefix yet — launching once so Steam creates it. Close the app window when it appears."
    launch_app "$id"
    for _ in $(seq 300); do app_prefix "$id" >/dev/null && break; sleep 2; done
    app_prefix "$id" >/dev/null || die "prefix was not created"
    sleep 20; pkill -f '3DMark' || true; sleep 3
  fi
  info "Installing d3dcompiler_43 / d3dcompiler_47 into the prefix (needed for Time Spy)"
  STEAM_DIR="$STEAM_ROOT" protontricks --no-bwrap "$id" -q d3dcompiler_43 d3dcompiler_47 || \
    STEAM_DIR="$STEAM_ROOT" protontricks "$id" -q d3dcompiler_43 d3dcompiler_47
  ok "prefix ready"
}

cmd_key() {
  local id; id=$(app_id "${1:-3dmark}"); local key=${2:-}
  detect_steam || die "Steam not found"
  if [[ -z $key ]]; then
    echo "Steam on Linux does not pass your CD key to the game (steam-for-linux#6436), so it opens in demo mode."
    echo "Opening Steam's CD key dialog — click the key to copy it (or paste it here)."
    steam_cmd "steam://cdkeys/$id" &>/dev/null &
    if ! key=$(wait_clipboard_key 120); then
      [[ $ASSUME_YES == 1 ]] && key="" || read -r -p "Paste key (empty to skip): " key
    fi
  fi
  [[ -z $key ]] && { warn "skipped key"; return 0; }
  app_prefix "$id" >/dev/null || die "launch the app once first (no prefix)"
  local paths=('HKCU\Software\UL\3DMark' 'HKCU\Software\Futuremark\3DMark')
  [[ $id == "$APP_3DMARK11" ]] && paths=('HKCU\Software\Futuremark\3DMark 11' 'HKLM\Software\Futuremark\3DMark 11')
  local p; for p in "${paths[@]}"; do
    STEAM_DIR="$STEAM_ROOT" protontricks -c "wine reg add '$p' /v KeyCode /t REG_SZ /d '$key' /f" "$id" >/dev/null
  done
  ok "key written to the prefix registry"
}

clipboard() {
  if [[ -n ${WAYLAND_DISPLAY:-} ]] && command -v wl-paste &>/dev/null; then wl-paste -n 2>/dev/null
  elif command -v xclip &>/dev/null; then xclip -o -selection clipboard 2>/dev/null
  elif command -v xsel &>/dev/null; then xsel -ob 2>/dev/null
  elif command -v qdbus &>/dev/null; then qdbus org.kde.klipper /klipper getClipboardContents 2>/dev/null; fi
}
# A real key looks like 3DM-ICF-XXXXX-XXXXX-XXXXX-XXXXX (older: 4-char groups).
wait_clipboard_key() {
  local t=$1 c
  for _ in $(seq "$t"); do
    c=$(clipboard | tr -d '[:space:]') || true
    [[ $c =~ ^[0-9A-Z]{2,4}(-[0-9A-Z]{3,6}){3,6}$ ]] && { echo "$c"; return 0; }
    sleep 1
  done
  return 1
}

# App-menu entries + taskbar icon. Proton windows carry WM_CLASS steam_app_<id>,
# so StartupWMClass makes GNOME/XFCE docks show the right icon for the running app.
cmd_shortcuts() {
  detect_steam || die "Steam not found"
  local id name exe desc dir steam_exec pair
  case $STEAM_KIND in
    snap) steam_exec="snap run steam" ;;
    flatpak) steam_exec="flatpak run com.valvesoftware.Steam" ;;
    *) steam_exec="steam" ;;
  esac
  local appsdir="$HOME/.local/share/applications" icondir="$HOME/.local/share/icons/hicolor/256x256/apps"
  mkdir -p "$appsdir" "$icondir"
  for pair in "$APP_3DMARK|3DMark|3DMark/bin/x64/3DMark.exe|GPU and CPU benchmark by UL (Steam, Proton)" \
              "$APP_3DMARK11|3DMark 11|3DMark 11/bin/x64/3DMark11.exe|DirectX 11 benchmark by UL (Steam, Proton)"; do
    IFS='|' read -r id name exe desc <<<"$pair"
    app_installed "$id" || continue
    dir="$(dirname "$(app_manifest "$id")")/common"
    python3 -I "$HERE/lib/exeicon.py" "$dir/$exe" "$icondir/steam_icon_$id.png" 256 2>/dev/null \
      || warn "could not extract icon for $name"
    cat > "$appsdir/3dmark-helper-$id.desktop" <<EOD
[Desktop Entry]
Type=Application
Name=$name
Comment=$desc
Exec=$steam_exec steam://rungameid/$id
Icon=steam_icon_$id
Terminal=false
Categories=Game;
Keywords=benchmark;gpu;3dmark;ul;futuremark;
StartupWMClass=steam_app_$id
StartupNotify=true
EOD
    chmod +x "$appsdir/3dmark-helper-$id.desktop"
    ok "menu entry: $name"
  done
  update-desktop-database "$appsdir" &>/dev/null || true
  gtk-update-icon-cache -f -t "$HOME/.local/share/icons/hicolor" &>/dev/null || true
  # KDE Plasma caches menus in ksycoca; GNOME/XFCE/LXQt watch the XDG dirs directly.
  local k; for k in kbuildsycoca6 kbuildsycoca5; do command -v "$k" &>/dev/null && { "$k" &>/dev/null || true; break; }; done
  xdg-desktop-menu forceupdate &>/dev/null || true
}

cmd_logs() {
  detect_steam || die "Steam not found"
  local out; out="$HOME/3dmark-helper-logs-$(date +%Y%m%d-%H%M%S).tar.gz"
  local tmp; tmp=$(mktemp -d)
  cmd_doctor > "$tmp/doctor.txt" 2>&1 || true
  cp "$HOME"/steam-$APP_3DMARK.log "$HOME"/steam-$APP_3DMARK11.log "$tmp/" 2>/dev/null || true
  local id pfx; for id in $APP_3DMARK $APP_3DMARK11; do
    pfx=$(app_prefix "$id") || continue
    find "$pfx/drive_c/users" -path '*3DMark*' \( -name '*.log' -o -name '*.txt' -o -name '*.xml' \) -size -5M -exec cp --parents {} "$tmp/" \; 2>/dev/null || true
  done
  tar -C "$tmp" -czf "$out" . && rm -rf "$tmp"
  ok "logs: $out   (set PROTON_LOG=1 in launch options to get steam-<appid>.log in ~)"
}

cmd_install() {
  cmd_deps
  cmd_install_steam
  cmd_login
  cmd_install_apps
  local app
  for app in 3dmark 3dmark11; do
    [[ $app == 3dmark11 && ${SKIP_3DMARK11:-0} == 1 ]] && continue
    cmd_setup "$app"
    cmd_prefix "$app"
    cmd_key "$app" ""
  done
  cmd_shortcuts
  cmd_doctor || true
  info "Done. Start 3DMark from Steam. Working tests: Fire Strike, Time Spy, Port Royal (RT GPUs), Night Raid, Sky Diver, Cloud Gate, Ice Storm, CPU Profile, feature tests. See README for the full matrix."
}

usage() {
  cat <<EOF
Usage: $0 [--ask] <command> [args]   (default: fully automatic)
  install                 full guided flow: deps, Steam, login, install apps, configure
  doctor                  check everything and print a pass/fail report
  deps                    install 32-bit Vulkan, protontricks, etc. (sudo)
  install-steam           install Steam if missing
  login                   start Steam and wait for you to log in
  install-apps            install Proton 10, 3DMark, 3DMark 11 via Steam
  setup <3dmark|3dmark11> pin Proton version + set launch options (closes Steam)
  prefix <app>            create Proton prefix + d3dcompiler_43/47
  key <app> [KEY]         write CD key so the app is not in demo mode
  launch-options <app>    print recommended launch options for this machine
  headless                force a display output on monitor-less (VNC) machines so Steam can show windows
  shortcuts               add 3DMark / 3DMark 11 to the app menu with proper icons
  logs                    bundle diagnostics into ~/3dmark-helper-logs-*.tar.gz
Env: PROTON_TOOL=proton_experimental  OSMESA=1 (blank launcher fix)  SKIP_3DMARK11=1  ASSUME_YES=1
EOF
}

main() {
  [[ ${1:-} == -y ]] && { ASSUME_YES=1; shift; }
  [[ ${1:-} == --ask ]] && { ASSUME_YES=0; shift; }
  local c=${1:-install}; shift || true
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
    launch-options) detect_steam || true; launch_options "$(app_id "${1:-3dmark}")" ;;
    logs) cmd_logs ;;
    shortcuts) cmd_shortcuts ;;
    headless) cmd_headless ;;
    -V|--version|version) echo "linux-steam-3dmark-helper $VERSION" ;;
    -h|--help|help) usage ;;
    *) usage; exit 2 ;;
  esac
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then main "$@"; fi
