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
  [ "$output" = " %command%" ] || [ "$output" = "%command%" ]
}

@test "proton 11 is never auto-picked" {
  source "$ROOT/3dmark-helper.sh"
  app_installed() { return 1; }
  run proton_tool
  [ "$output" = proton_experimental ]
}
