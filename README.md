# linux-steam-3dmark-helper

One script that takes a fresh Ubuntu / Xubuntu / Kubuntu / Lubuntu (26.10; GNOME, XFCE, KDE Plasma, LXQt) machine to a working **Steam 3DMark** (app 223850) and **3DMark 11** (app 205270) under Proton — on Intel, AMD and NVIDIA (including hybrid laptops).

> ### 🙏 Tribute to 3DMark and UL
> **3DMark** is the world's most popular GPU benchmark, created by **Futuremark** (Finland, founded 1997) and developed today by **[UL Solutions — UL Benchmarks](https://benchmarks.ul.com/)**. For more than 25 years — from 3DMark99 through 3DMark 11, Fire Strike, Time Spy, Port Royal, Speed Way and Steel Nomad — their work has been the common yardstick that gamers, overclockers, reviewers and hardware makers use to compare graphics performance. This project exists because we love their software and want to run it on Linux too; UL has said a native Linux version is planned, and we look forward to it.
>
> **This helper does not include, crack or redistribute any 3DMark files.** You need your own legitimate copy:
>
> - 🛒 **Buy 3DMark on Steam:** <https://store.steampowered.com/app/223850/3DMark/>
> - 🛒 **Buy 3DMark 11 on Steam:** <https://store.steampowered.com/app/205270/3DMark_11/>
> - 🛒 **Buy directly from UL:** <https://benchmarks.ul.com/3dmark>
>
> ### 🙏 Tribute to Valve and Steam
> None of this would be possible without **[Valve](https://www.valvesoftware.com/)** and **[Steam](https://store.steampowered.com/)**. Through **[Proton](https://github.com/ValveSoftware/Proton)** — built on Wine, DXVK and vkd3d-proton, with years of work by Valve, CodeWeavers and open-source contributors such as Hans-Kristian Arntzen and Philip Rebohle — plus the Steam Linux Runtime and the Steam Deck, Valve turned Linux into a real gaming platform. Thank you.
>
> 3DMark, Time Spy, Fire Strike, Port Royal, Night Raid, Speed Way, Steel Nomad and related names are trademarks of UL Solutions Inc. Steam, Proton and Steam Deck are trademarks of Valve Corporation. This is an unofficial community project, not affiliated with or endorsed by UL Solutions or Valve.

```bash
git clone https://github.com/ventura8/linux-steam-3dmark-helper
cd linux-steam-3dmark-helper
./3dmark-helper.sh            # = install: deps → Steam → login → apps → tests → configure
```

Supported apps: **3DMark** (223850), **3DMark 11** (205270), **PCMark 10** (524390) — whatever your Steam account owns.

What `install` does, with no questions asked:
1. Installs dependencies (sudo): 32-bit Vulkan (`mesa-vulkan-drivers:i386`, `libnvidia-gl-<ver>:i386` on NVIDIA), OCR/X tools for automatic CD keys, and fixes amd64/i386 version skew in apt.
2. Installs Steam if missing, opens it, waits for your login (on a monitor-less VNC box it first forces a display output on).
3. Installs Steam Linux Runtime 3.0, **Proton Experimental**, Proton 10 and every owned app — no Steam dialogs.
4. Downloads **every 3DMark test that works on Linux** in one go (Fire Strike, Time Spy, Port Royal, Steel Nomad, …).
5. Pins Proton, writes per-GPU launch options and a small launch wrapper.
6. Builds each prefix under that Proton, installs native `d3dcompiler_47` (no protontricks needed).
7. Fetches and registers your **CD keys** (Steam on Linux never does → demo mode).
8. Makes **UL SystemInfo** work under Proton (needed by 3DMark 11) — see below.
9. Adds menu entries with the real icons; prints a `doctor` report.

## Commands
| Command | Purpose |
|---|---|
| `doctor` | pass/fail report: Proton, prefix version, d3dcompiler, CD keys, EULAs, tests |
| `deps`, `install-steam`, `login`, `install-apps`, `headless` | individual install steps |
| `tests` | download all Linux-capable 3DMark tests (`STORAGE=1` adds the 30 GB storage test) |
| `setup <app>` | pin Proton + launch options (closes Steam) |
| `prefix <app>` | create/upgrade prefix, native d3dcompiler_47 |
| `key <app> [KEY]` | fetch the CD key from Steam automatically and register it |
| `systeminfo fix\|on\|off` | SystemInfo service fix (always) + scan on/off |
| `shortcuts` | app-menu entries + icons |
| `launch-options <app>`, `logs` | inspect / bug-report bundle |

Apps: `3dmark`, `3dmark11`, `pcmark10`. Env: `PROTON_TOOL=proton_10`, `OSMESA=1`, `STORAGE=1`, `NO_WRAPPER=1`, `--ask` (confirm each step).

### Launch options written
| GPU | Options (plus `APP_PROC=… <Steam>/3dmark-helper-launch.sh %command%`) |
|---|---|
| NVIDIA + iGPU (laptop) | `PROTON_ENABLE_NVAPI=1 DXVK_ENABLE_NVAPI=1 __NV_PRIME_RENDER_OFFLOAD=1 __GLX_VENDOR_LIBRARY_NAME=nvidia __VK_LAYER_NV_optimus=NVIDIA_only VKD3D_CONFIG=dxr,dxr11` |
| NVIDIA desktop | `PROTON_ENABLE_NVAPI=1 DXVK_ENABLE_NVAPI=1 VKD3D_CONFIG=dxr,dxr11` |
| AMD / Intel | `VKD3D_CONFIG=dxr,dxr11` (`DRI_PRIME=1` on AMD+Intel hybrids) |

AMD tip: if Time Spy hangs or shows artifacts on older Mesa, add `RADV_DEBUG=syncshaders` (costs ~20 %).

## Results (measured by this project, Nov 2026)
NUC — Xubuntu 26.10 (XFCE, X11), Intel Core Ultra 7 255H / **Intel Arc 140T**, Mesa 26.2:

| Test | API | Proton 10 | Proton Experimental (11) |
|---|---|---|---|
| 3DMark CPU Profile | — | ✅ 5858 (max threads) | |
| 3DMark Fire Strike | DX11 | ✅ 5664 | |
| 3DMark Time Spy | DX12 | ✅ 1933 | ✅ **2138** |
| 3DMark Night Raid | DX12 | ✅ 12459 | |
| 3DMark Port Royal | DXR | ✅ 787 | |
| 3DMark Steel Nomad | DX12 | ❌ crash at start (vkd3d-proton 3.0) | ✅ **541** |
| 3DMark 11 Performance | DX11 | | ✅ **P7820** (SystemInfo detects CPU/GPU) |
| PCMark 10 | mixed | | testing |

Laptop — Ubuntu 26.10 (GNOME, Wayland), RTX 3080 Mobile + Intel UHD, Snap Steam: testing.

Why Experimental is the default: in the current build (`experimental-11.0-20261123b`) the May 2026 "You need a DirectX 12 compatible GPU" regression ([Proton#4034](https://github.com/ValveSoftware/Proton/issues/4034)) is gone, Time Spy scores ~10 % higher and Steel Nomad runs. `PROTON_TOOL=proton_10` switches back.

Report yours: `./3dmark-helper.sh logs` and open an issue.

## UL SystemInfo under Proton (solved)
UL's hardware detector never worked under Wine/Proton — 3DMark 11 refuses to start ("SystemInfo initialization failed"), 3DMark shows "System information not available". Root causes found here:
1. SystemInfo's COM classes are registered only in the 32-bit registry view (`Wow6432Node`); 64-bit apps get "class not registered".
2. Its service (FMSISvc) starts Wine's RPC service from inside its own start-up; Wine's service manager can't do that nested start, so FMSISvc dies.
3. The type library used to marshal calls between the 32-bit service and 64-bit apps has only a `win32` entry.
4. Its scanner keeps running after the app exits, so Steam keeps showing the app as running.

The helper mirrors the classes to the 64-bit view, sets RpcSs to auto-start, adds the `win64` typelib entry, and its launch wrapper ends the leftover session. Result: 3DMark 11 runs and uploads results; 3DMark shows the GPU and CPU.

One catch: with the **scan** enabled, 3DMark wrongly blocks Time Spy and Night Raid with "Your CPU does not support SSSE3" (Wine hides the CPU feature flags from SystemInfo). So `install` keeps 3DMark/PCMark's scan **off** (`systeminfo on` to enable). Results are not validated online either way.

## Desktop support (GNOME, XFCE, KDE Plasma, LXQt)
| | GNOME (Ubuntu) | XFCE (Xubuntu) | KDE Plasma (Kubuntu) | LXQt (Lubuntu) |
|---|---|---|---|---|
| Session | Wayland | X11 | Wayland (default) or X11 | X11 |
| CD key | 1 click (Wayland blocks synthetic input) | automatic (OCR + click) | Wayland: 1 click · X11: automatic | automatic |
| Menu entry + taskbar icon | ✅ `StartupWMClass=steam_app_<id>` | ✅ | ✅ (+ `kbuildsycoca6` refresh) | ✅ |
| Clipboard | wl-paste | xclip/xsel | wl-paste / Klipper | xclip/xsel |
| 3DMark title bar | none (app draws its own frame) | ✅ drawn by xfwm4 | KWin: Alt+F3 menu | Openbox: Alt+Space menu |
| Status | ✅ laptop | ✅ NUC | needs testers | needs testers |

Everything the helper does is desktop-neutral (XDG `.desktop`, hicolor icons, X11/XWayland window capture); the differences above are only in how the CD-key dialog is clicked and how windows are managed.

## What still needs you
Your **sudo password**, your **Steam login**, accepting each app's **EULA** in Steam, and — on Wayland only — one click on your CD key when Steam shows it.

## Troubleshooting
- **No title-bar buttons (GNOME)** → 3DMark draws its own borderless window. Use the keyboard or the taskbar entry:

  | Desktop | Minimise | Maximise | Close | Move |
  |---|---|---|---|---|
  | GNOME (Ubuntu) | Super+H | Super+↑ | Alt+F4 | Super+drag |
  | XFCE (Xubuntu) | title bar / taskbar | Alt+F10 | Alt+F4 | Alt+drag |
  | KDE Plasma (Kubuntu) | Meta+PgDn | Meta+PgUp | Alt+F4 | Meta+drag |
  | LXQt (Lubuntu, Openbox) | Alt+Space menu | Alt+Space → Maximize | Alt+F4 | Alt+drag |
- **"Your CPU does not support SSSE3" on Time Spy / Night Raid** → SystemInfo scan is on: `./3dmark-helper.sh systeminfo off`.
- **3DMark 11: "SystemInfo initialization failed"** → `./3dmark-helper.sh systeminfo fix`.
- **App still "running" in Steam after closing / next launch says another session is running** → old launch options without the wrapper: `./3dmark-helper.sh setup <app>`. Steam allows one running app per account across all your PCs.
- **Steel Nomad "No result produced"** → you are on Proton 10: `./3dmark-helper.sh setup 3dmark` (Experimental).
- **Steam starts but no window (headless / VNC)** → `./3dmark-helper.sh headless`; permanent: HDMI dummy plug or kernel arg `video=HDMI-A-1:1920x1080@60e`.
- **Demo mode** → `./3dmark-helper.sh key 3dmark`.
- **CPU Profile / Time Spy "D3DCompile2 … not yet implemented"** → native d3dcompiler missing: `./3dmark-helper.sh prefix 3dmark`.
- **Launcher never opens, no log** → 32-bit Vulkan missing: `./3dmark-helper.sh deps`.
- **Apt "… :i386 Breaks …"** → handled by `deps` (aligns amd64/i386 versions).
- **Blank white launcher** → `OSMESA=1 ./3dmark-helper.sh setup 3dmark`.
- Logs: `PROTON_LOG=1` in launch options → `~/steam-<appid>.log`; `./3dmark-helper.sh logs` bundles everything.

## Competition / prior art
| Project | What it does | Gap |
|---|---|---|
| [daniellog/3dmark_proton_registration](https://github.com/daniellog/3dmark_proton_registration) (closest, Nov 2026) | installs 223850, CD key via `steam://cdkeys` + clipboard, patches launcher jar to skip a bogus SSSE3 gate on Time Spy/Night Raid | 3DMark only (no 3DMark 11), no deps/32-bit Vulkan, no Steam install/login, no Proton pin, no GPU-specific launch options |
| [Lutris 3dmark-proton](https://lutris.net/games/install/16682/view) | launches Steam 223850 via Proton | no key fix, verbs, Proton pin, 3DMark 11 |
| [z0z0z/mf-install](https://github.com/z0z0z/mf-install) | generic Media Foundation installer | not 3DMark-specific |
| [GamingOnLinux thread](https://www.gamingonlinux.com/forum/topic/5936/), [Steam Community](https://steamcommunity.com/app/223850/discussions/0/5586172045660180811), [Proton#4034](https://github.com/ValveSoftware/Proton/issues/4034) | manual steps | scattered, manual, partly outdated |
| [ProtonDB](https://www.protondb.com/app/223850) | user reports | no automation |
| protontricks, ProtonUp-Qt, umu-launcher, Bottles, Heroic | generic building blocks | no 3DMark knowledge |
| [Phoronix Test Suite](https://openbenchmarking.org/test/pts/3dmark), Unigine, vkmark, glmark2 | native benchmarks | not 3DMark scores |
| UL native Linux 3DMark | [announced June 2025](https://www.gamingonlinux.com/2025/06/3dmark-are-planning-a-linux-version-but-no-date-for-it-yet) | not public |

No umu-protonfixes / GE protonfixes entry exists for 223850 or 205270, and the AUR has no package. This project is the only one covering the full path from a bare system to a running 3DMark and 3DMark 11.

## Docs
[Architecture](ARCHITECTURE.md) · [Contributing](CONTRIBUTING.md) · [Changelog](CHANGELOG.md) · [Security](SECURITY.md)

## Development
```bash
bats tests/ && shellcheck 3dmark-helper.sh
```
