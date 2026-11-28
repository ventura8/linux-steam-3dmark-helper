#!/usr/bin/env bats
setup() {
  ROOT="$BATS_TEST_DIRNAME/.."
  TMP="$BATS_TEST_TMPDIR"
  cp "$ROOT"/tests/fixtures/*.vdf "$TMP/"
  VDF="python3 $ROOT/lib/vdfedit.py"
}

@test "compat mapping is created and readable" {
  $VDF compat "$TMP/config.vdf" 223850 proton_10
  run $VDF get "$TMP/config.vdf" InstallConfigStore/Software/Valve/Steam/CompatToolMapping/223850/name
  [ "$output" = proton_10 ]
  [ -f "$TMP/config.vdf.3dmark-helper.bak" ]
}

@test "existing keys are preserved" {
  $VDF compat "$TMP/config.vdf" 205270 proton_experimental
  run $VDF get "$TMP/config.vdf" InstallConfigStore/Software/Valve/Steam/AutoUpdateWindowEnabled
  [ "$output" = 0 ]
}

@test "launch options set case-insensitively under existing app" {
  $VDF launch "$TMP/localconfig.vdf" 223850 'VKD3D_CONFIG=dxr,dxr11 %command%'
  run $VDF get "$TMP/localconfig.vdf" UserLocalConfigStore/Software/Valve/Steam/apps/223850/LaunchOptions
  [ "$output" = 'VKD3D_CONFIG=dxr,dxr11 %command%' ]
  run $VDF get "$TMP/localconfig.vdf" UserLocalConfigStore/Software/Valve/Steam/apps/223850/Playtime
  [ "$output" = 10 ]
  [ "$(grep -ci '"valve"' "$TMP/localconfig.vdf")" = 1 ]
}

@test "launch options with quotes are escaped" {
  $VDF launch "$TMP/localconfig.vdf" 205270 'FOO="a b" %command%'
  run $VDF get "$TMP/localconfig.vdf" UserLocalConfigStore/Software/Valve/Steam/apps/205270/LaunchOptions
  [ "$output" = 'FOO=\"a b\" %command%' ]
}

@test "launch-options: NVIDIA hybrid gets PRIME offload" {
  source "$ROOT/3dmark-helper.sh"
  detect_gpus() { GPU_VENDORS="8086 10de"; }
  run launch_options 223850
  [[ $output == *__NV_PRIME_RENDER_OFFLOAD=1* ]]
  [[ $output == *VKD3D_CONFIG=dxr,dxr11* ]]
}

@test "launch-options: AMD only has no NVIDIA vars" {
  source "$ROOT/3dmark-helper.sh"
  detect_gpus() { GPU_VENDORS="1002"; }
  run launch_options 205270
  [ "$output" = "%command%" ]
}

@test "Experimental is preferred, Proton 10 is the fallback, PROTON_TOOL overrides" {
  source "$ROOT/3dmark-helper.sh"
  app_installed() { [[ $1 == 1493710 ]]; }
  run proton_tool; [ "$output" = proton_experimental ]
  app_installed() { return 1; }
  run proton_tool; [ "$output" = proton_10 ]
  PROTON_TOOL=proton_10 run proton_tool; [ "$output" = proton_10 ]
}

@test "app table: key locations come from Steam appinfo" {
  source "$ROOT/3dmark-helper.sh"
  run app_keyreg 205270; [ "$output" = 'HKEY_CURRENT_USER\Software\Futuremark\3DMark11' ]
  run app_keyreg 524390; [ -z "$output" ]
  run app_id pcmark10; [ "$output" = 524390 ]
}

@test "systeminfo toggle edits app-settings.json" {
  printf '[{"SCAN_SYSTEM_INFO":true,"mutable":true},{"HARDWARE_MONITORING":true}]' > "$TMP/s.json"
  python3 "$ROOT/lib/appsettings.py" "$TMP/s.json" off
  run python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));print(d[0]["SCAN_SYSTEM_INFO"],d[1]["HARDWARE_MONITORING"])' "$TMP/s.json"
  [ "$output" = "False False" ]
}

@test "winereg: set into existing section, create new section, read back" {
  printf 'WINE REGISTRY Version 2\n\n[Software\\\\Wine\\\\DllOverrides] 1700000000\n#time=1\n"*d3d9"="native"\n\n' > "$TMP/u.reg"
  python3 "$ROOT/lib/winereg.py" set "$TMP/u.reg" 'Software\Wine\DllOverrides' '*d3dcompiler_47' 'native,builtin'
  WINEREG_VALUE='3DM-ICF-AAAAA-BBBBB-CCCCC-DDDDD' python3 "$ROOT/lib/winereg.py" set "$TMP/u.reg" 'Software\Futuremark\3DMark11' KeyCode -
  run python3 "$ROOT/lib/winereg.py" get "$TMP/u.reg" 'Software\Wine\DllOverrides' '*d3dcompiler_47'; [ "$output" = native,builtin ]
  run python3 "$ROOT/lib/winereg.py" get "$TMP/u.reg" 'Software\Wine\DllOverrides' '*d3d9'; [ "$output" = native ]
  run python3 "$ROOT/lib/winereg.py" get "$TMP/u.reg" 'Software\Futuremark\3DMark11' KeyCode; [ "$output" = 3DM-ICF-AAAAA-BBBBB-CCCCC-DDDDD ]
  grep -q '^\[Software\\\\Futuremark\\\\3DMark11\] ' "$TMP/u.reg"
}

@test "titlebar: KDE KWin rule is added once and keeps existing rules" {
  printf '[General]\ncount=1\nrules=abc\n\n[abc]\nDescription=mine\n' > "$TMP/kwinrulesrc"
  run python3 "$ROOT/lib/titlebar.py" kde "$TMP/kwinrulesrc"; [ "$output" = changed ]
  run python3 "$ROOT/lib/titlebar.py" kde "$TMP/kwinrulesrc"; [ "$output" = unchanged ]
  grep -q '^rules=abc,3dmark-helper-titlebar$' "$TMP/kwinrulesrc"
  grep -q '^count=2$' "$TMP/kwinrulesrc"
  grep -q '^noborderrule=2$' "$TMP/kwinrulesrc"
  grep -q '^Description=mine$' "$TMP/kwinrulesrc"
}

@test "titlebar: Openbox (LXQt) application rule in existing namespaced rc.xml" {
  printf '<?xml version="1.0"?>\n<openbox_config xmlns="http://openbox.org/3.4/rc"><theme><name>Clearlooks</name></theme><applications/></openbox_config>\n' > "$TMP/lxqt-rc.xml"
  run python3 "$ROOT/lib/titlebar.py" openbox "$TMP/lxqt-rc.xml"; [ "$output" = changed ]
  run python3 "$ROOT/lib/titlebar.py" openbox "$TMP/lxqt-rc.xml"; [ "$output" = unchanged ]
  python3 -c 'import xml.etree.ElementTree as E,sys; r=E.parse(sys.argv[1]).getroot(); n="{http://openbox.org/3.4/rc}"; a=r.find(n+"applications/"+n+"application"); assert a.get("class")=="steam_app_*" and a.find(n+"decor").text=="yes"; assert r.find(n+"theme/"+n+"name").text=="Clearlooks"' "$TMP/lxqt-rc.xml"
}

@test "titlebar: labwc window rule created from scratch" {
  run python3 "$ROOT/lib/titlebar.py" labwc "$TMP/labwc/rc.xml"; [ "$output" = changed ]
  grep -q 'identifier="steam_app_\*"' "$TMP/labwc/rc.xml"
  grep -q 'serverDecoration="yes"' "$TMP/labwc/rc.xml"
}

@test "detect_desktop maps XDG_CURRENT_DESKTOP" {
  source "$ROOT/3dmark-helper.sh"
  import_session_env() { :; }
  pgrep() { return 1; }
  XDG_CURRENT_DESKTOP=KDE run detect_desktop; [ "$output" = kde ]
  XDG_CURRENT_DESKTOP=LXQt XDG_SESSION_TYPE=x11 run detect_desktop; [ "$output" = lxqt-openbox ]
  XDG_CURRENT_DESKTOP=LXQt XDG_SESSION_TYPE=wayland run detect_desktop; [ "$output" = lxqt-labwc ]
  XDG_CURRENT_DESKTOP=ubuntu:GNOME run detect_desktop; [ "$output" = gnome ]
  XDG_CURRENT_DESKTOP=XFCE run detect_desktop; [ "$output" = xfce ]
}
