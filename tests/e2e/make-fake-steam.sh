#!/usr/bin/env bash
# Build a fake but structurally real Steam installation under $1 (used as $HOME):
# deb-style Steam root, logged-in user, 3DMark + 3DMark 11 + PCMark 10 + Proton
# Experimental installed, Proton prefixes with Wine registry files and UL SystemInfo.
set -euo pipefail
H=$1
S="$H/.local/share/Steam"
mkdir -p "$S/config" "$S/userdata/12345/config" "$S/steamapps/common"

cat >"$S/config/config.vdf" <<'V'
"InstallConfigStore"
{
	"Software"
	{
		"Valve"
		{
			"Steam"
			{
				"AutoUpdateWindowEnabled"		"0"
			}
		}
	}
}
V
cat >"$S/config/loginusers.vdf" <<'V'
"users"
{
	"76561190000000000"
	{
		"AccountName"		"tester"
		"MostRecent"		"1"
	}
}
V
cat >"$S/userdata/12345/config/localconfig.vdf" <<'V'
"UserLocalConfigStore"
{
	"Software"
	{
		"Valve"
		{
			"Steam"
			{
				"apps"
				{
					"223850"
					{
						"223850_eula_0"		"1"
					}
					"205270"
					{
						"205270_eula_0"		"1"
					}
					"524390"
					{
						"Playtime"		"1"
					}
				}
			}
		}
	}
}
V
printf '"libraryfolders"\n{\n\t"0"\n\t{\n\t\t"path"\t\t"%s"\n\t}\n}\n' "$S" >"$S/steamapps/libraryfolders.vdf"

manifest() { # id installdir depot
  cat >"$S/steamapps/appmanifest_$1.acf" <<V
"AppState"
{
	"appid"		"$1"
	"name"		"$2"
	"StateFlags"		"4"
	"installdir"		"$2"
	"InstalledDepots"
	{
		"$3"
		{
			"manifest"		"1"
			"size"		"1"
		}
	}
	"UserConfig"
	{
	}
}
V
  mkdir -p "$S/steamapps/common/$2"
}
manifest 223850 3DMark 223851
manifest 205270 "3DMark 11" 205271
manifest 524390 "PCMark 10" 524391
manifest 1493710 "Proton - Experimental" 1493711
manifest 1628350 SteamLinuxRuntime_sniper 1628351
printf 'CURRENT_PREFIX_VERSION="11.0-100"\n' >"$S/steamapps/common/Proton - Experimental/proton"
mkdir -p "$S/steamapps/common/3DMark/dlc/fire-strike-test" "$S/steamapps/common/3DMark/bin/x64"

prefix() { # id
  local p="$S/steamapps/compatdata/$1/pfx"
  mkdir -p "$p/drive_c/windows/system32" "$p/drive_c/windows/syswow64" \
    "$p/drive_c/Program Files (x86)/Futuremark/SystemInfo"
  echo "11.0-100" >"$S/steamapps/compatdata/$1/version"
  cat >"$p/user.reg" <<'R'
WINE REGISTRY Version 2
;; All keys relative to \\User\\S-1-5-21-0-0-0-1000

#arch=win64

[Software\\Wine\\DllOverrides] 1795000000
#time=1dd7f51a1945e5c
"*d3dcompiler_47"="native,builtin"

R
  cat >"$p/system.reg" <<'R'
WINE REGISTRY Version 2
;; All keys relative to \\Machine

#arch=win64

[Software\\Classes\\Typelib\\{0E985ACA-E998-460F-B705-8436E606F78C}\\1.0\\0\\win32] 1795881647
#time=1dd7f51a19473ec
@="C:\\Program Files (x86)\\Futuremark\\SystemInfo\\FMSISvc.exe"

[Software\\Classes\\Wow6432Node\\CLSID\\{F9C82199-B002-41B4-8B00-0F1ECA89425F}] 1795881647
#time=1dd7f51a1945e5c
@="Futuremark SystemInfo v2 Class"
"AppID"="{1BF1C030-CE12-4A8A-A4E1-EDDCE7176799}"

[Software\\Classes\\Wow6432Node\\CLSID\\{F9C82199-B002-41B4-8B00-0F1ECA89425F}\\LocalService] 1795881647
#time=1dd7f51a1945c90
@="\"C:\\Program Files (x86)\\Futuremark\\SystemInfo\\FMSISvc.exe\""

[System\\ControlSet001\\Services\\RpcSs] 1795000000
#time=1dd7f51a1945c90
"Start"=dword:00000003

R
}
prefix 223850
prefix 205270
prefix 524390
s="$S/steamapps/compatdata/223850/pfx/drive_c/users/steamuser/AppData/Local/UL/3DMark"
mkdir -p "$s"
printf '[{"SCAN_SYSTEM_INFO":true,"mutable":true},{"HARDWARE_MONITORING":true}]' >"$s/app-settings.json"
