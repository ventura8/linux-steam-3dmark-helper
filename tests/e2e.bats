#!/usr/bin/env bats
# End-to-end: run the real helper commands against a fake Steam installation.
# No Steam, GPU or network needed (d3dcompiler is pre-registered in the fixture).

setup() {
  ROOT="$BATS_TEST_DIRNAME/.."
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  "$ROOT/tests/e2e/make-fake-steam.sh" "$HOME"
  S="$HOME/.local/share/Steam"
  H="$ROOT/3dmark-helper.sh"
  # never touch a real desktop session / Steam from tests
  export XDG_CURRENT_DESKTOP=XFCE XDG_SESSION_TYPE=x11 DISPLAY= WAYLAND_DISPLAY= DBUS_SESSION_BUS_ADDRESS=unix:path=/dev/null
  W="python3 $ROOT/lib/winereg.py"
  export STEAM_HELPER_NO_PROCESS_CONTROL=1
}

@test "doctor finds the fake Steam, all three apps and their prefixes" {
  run "$H" doctor
  [[ $output == *"Steam (deb) at $S"* ]]
  [[ $output == *"a Steam account is logged in"* ]]
  [[ $output == *"3DMark installed"* ]]
  [[ $output == *"3DMark 11 installed"* ]]
  [[ $output == *"PCMark 10 installed"* ]]
  [[ $output == *"Proton tool that will be used: proton_experimental"* ]]
  [[ $output == *"3DMark prefix on 11.0-100"* ]]
  [[ $output == *"3DMark d3dcompiler_47 native"* ]]
  [[ $output == *"3DMark: no CD key"* ]]
  [[ $output == *"PCMark 10: EULA not accepted yet"* ]]
}

@test "setup pins Proton Experimental and writes launch options with the wrapper" {
  run "$H" setup 3dmark11
  [ "$status" -eq 0 ]
  run python3 "$ROOT/lib/vdfedit.py" get "$S/config/config.vdf" InstallConfigStore/Software/Valve/Steam/CompatToolMapping/205270/name
  [ "$output" = proton_experimental ]
  run python3 "$ROOT/lib/vdfedit.py" get "$S/userdata/12345/config/localconfig.vdf" UserLocalConfigStore/Software/Valve/Steam/apps/205270/LaunchOptions
  [[ $output == *"APP_PROC='[b]in.x64.3DMark11.exe'"* ]]
  [[ $output == *"3dmark-helper-launch.sh"* ]]
  [[ $output == *"%command%" ]]
  [ -x "$S/3dmark-helper-launch.sh" ]
}

@test "key: given key is registered at every location Steam uses, then reused" {
  run "$H" key 3dmark 3DM-ICF-AAAAA-BBBBB-CCCCC-DDDDD
  [ "$status" -eq 0 ]
  [[ $output == *"3DMark key registered"* ]]
  R="$S/steamapps/compatdata/223850/pfx/user.reg"
  run $W get "$R" 'Software\Futuremark\3DMark' KeyCode
  [ "$output" = 3DM-ICF-AAAAA-BBBBB-CCCCC-DDDDD ]
  run $W get "$R" 'Software\UL\3DMark' KeyCode
  [ "$output" = 3DM-ICF-AAAAA-BBBBB-CCCCC-DDDDD ]
  run "$H" key 3dmark
  [[ $output == *"already registered"* ]]
}

@test "key: 3DMark 11 uses Futuremark\\3DMark11, PCMark 10 needs no key" {
  run "$H" key 3dmark11 3D11-ADV-AAAA-BBBB-CCCC-DDDD-EEEE
  [ "$status" -eq 0 ]
  run $W get "$S/steamapps/compatdata/205270/pfx/user.reg" 'Software\Futuremark\3DMark11' KeyCode
  [ "$output" = 3D11-ADV-AAAA-BBBB-CCCC-DDDD-EEEE ]
  run "$H" key pcmark10
  [[ $output == *"uses Steam ownership"* ]]
}

@test "systeminfo off: COM class mirrored to 64-bit, RpcSs auto-start, typelib win64, scan off" {
  run "$H" systeminfo off
  [ "$status" -eq 0 ]
  R="$S/steamapps/compatdata/205270/pfx/system.reg"
  run $W get "$R" 'System\ControlSet001\Services\RpcSs' Start
  [ "$output" = dword:00000002 ]
  run $W get "$R" 'Software\Classes\CLSID\{F9C82199-B002-41B4-8B00-0F1ECA89425F}\LocalService' @
  [[ $output == *"FMSISvc.exe"* ]]
  run $W get "$R" 'Software\Classes\Typelib\{0E985ACA-E998-460F-B705-8436E606F78C}\1.0\0\win64' @
  [[ $output == *"FMSISvc.exe"* ]]
  grep -q '"SCAN_SYSTEM_INFO":false' "$S/steamapps/compatdata/223850/pfx/drive_c/users/steamuser/AppData/Local/UL/3DMark/app-settings.json"
  # no malformed (double-escaped) keys were created
  ! grep -q '^\[[^]]*\\\\\\\\' "$R"
  # idempotent
  run "$H" systeminfo off
  [ "$status" -eq 0 ]
  [ "$(grep -cF '[Software\\Classes\\CLSID\\{F9C82199-B002-41B4-8B00-0F1ECA89425F}]' "$R")" -eq 1 ]
}

@test "tests: preselects every Linux-capable 3DMark test DLC" {
  run timeout 60 "$H" tests
  [ "$status" -eq 0 ]
  run python3 "$ROOT/lib/vdfedit.py" get "$S/steamapps/appmanifest_223850.acf" AppState/UserConfig/optionaldlc
  [[ $output == *402290* && $output == *496100* && $output == *2695340* ]]
  [[ $output != *1322770* ]]
}

@test "shortcuts: XDG menu entries with StartupWMClass" {
  run "$H" shortcuts
  [ "$status" -eq 0 ]
  f="$HOME/.local/share/applications/3dmark-helper-223850.desktop"
  [ -f "$f" ]
  grep -q '^StartupWMClass=steam_app_223850$' "$f"
  grep -q '^Exec=steam steam://rungameid/223850$' "$f"
}
