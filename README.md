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
./3dmark-helper.sh            # = install: deps → Steam → login → apps → configure
```

What `install` does:
1. Enables i386 and installs 32-bit Vulkan (`mesa-vulkan-drivers:i386`, `libnvidia-gl-<ver>:i386` on NVIDIA), `vulkan-tools`, `protontricks`. Without the 32-bit Vulkan driver the 3DMark launcher silently never starts.
2. Installs Steam (`steam-installer`) if no deb/Snap/Flatpak Steam exists.
3. Starts Steam and waits for you to log in.
4. Installs Proton 10, 3DMark and 3DMark 11 through `steam://install/…` (confirm the dialogs).
5. Closes Steam, pins **Proton 10** (fallback Experimental — never Proton 11, see below) and writes GPU-specific launch options.
6. Creates the prefix and installs `d3dcompiler_43` + `d3dcompiler_47` (required for Time Spy).
7. Adds **3DMark** and **3DMark 11** to the app menu with their real icons (taskbar shows the right icon too).
8. Writes your CD key into the prefix registry (Steam on Linux doesn't, so 3DMark opens in demo mode). Find the key in Steam → right-click app → Manage → CD Keys.

Then install the test DLCs: Library → 3DMark → Manage → DLC.

## Commands
| Command | Purpose |
|---|---|
| `doctor` | pass/fail report of the whole stack |
| `deps`, `install-steam`, `login`, `install-apps` | individual install steps |
| `setup <3dmark\|3dmark11>` | pin Proton + launch options (closes Steam) |
| `prefix <app>` | create prefix + d3dcompiler verbs |
| `key <app> [KEY]` | write CD key |
| `launch-options <app>` | print what would be set for this GPU |
| `shortcuts` | app-menu entries + icons |
| `logs` | diagnostics tarball for bug reports |

Env: `PROTON_TOOL=proton_experimental`, `OSMESA=1` (adds `--use-gl=osmesa` for a blank/white launcher), `SKIP_3DMARK11=1`, `ASSUME_YES=1` / `-y`.

### Launch options written
| GPU | Options |
|---|---|
| NVIDIA + iGPU (laptop) | `PROTON_ENABLE_NVAPI=1 DXVK_ENABLE_NVAPI=1 __NV_PRIME_RENDER_OFFLOAD=1 __GLX_VENDOR_LIBRARY_NAME=nvidia __VK_LAYER_NV_optimus=NVIDIA_only VKD3D_CONFIG=dxr,dxr11 %command%` |
| NVIDIA desktop | `PROTON_ENABLE_NVAPI=1 DXVK_ENABLE_NVAPI=1 VKD3D_CONFIG=dxr,dxr11 %command%` |
| AMD / Intel | `VKD3D_CONFIG=dxr,dxr11 %command%` (`DRI_PRIME=1` on AMD+Intel hybrids) |

AMD tip: if Time Spy hangs or shows artifacts on older Mesa, add `RADV_DEBUG=syncshaders` (costs ~20 %).

## Test status (Proton 10 / Experimental, late 2025 – 2026)
| Test | API | Status |
|---|---|---|
| Fire Strike / Extreme / Ultra | DX11 → DXVK | ✅ works |
| Time Spy / Extreme | DX12 → vkd3d-proton | ⚠️ works for many with d3dcompiler_43/47; others report black screen → "An error occurred", or an SSSE3 "CPU not supported" gate. Vendor/version dependent |
| Night Raid | DX12 | ✅ |
| Port Royal | DXR | ✅ on RT-capable GPUs (Proton 10) |
| Sky Diver, Cloud Gate, Ice Storm | DX11/DX10 | ✅ |
| CPU Profile | — | ✅ |
| Feature tests: DXR, mesh shader, VRS, PCIe, API overhead | | ✅ |
| Sampler feedback | DX12U | ❓ untested on recent vkd3d |
| Speed Way | DX12 Ultimate | ❌ fails to start |
| Steel Nomad / Light (DX12 + Vulkan) | | ❌ |
| Wild Life / Extreme | Vulkan | ❌ crash before loading |
| Solar Bay | Vulkan RT | ❌ |
| FSR / XeSS feature tests | | ❌ |
| 3DMark 11 Basic / Performance / Extreme | DX11 | ❓ being verified by this project |

**Proton 11 regression (May 2026):** every DX12 test reports "You need a DirectX 12 compatible GPU" ([Proton#4034](https://github.com/ValveSoftware/Proton/issues/4034)). The helper therefore pins Proton 10.

Per-machine results (filled as we test):
| Machine | GPU | Distro | Result |
|---|---|---|---|
| Laptop | RTX 3080 Mobile + Intel UHD | Ubuntu 26.10, Snap Steam | in progress |
| NUC | Intel Arc 140T | Xubuntu 26.10 | in progress |
| Desktop | NVIDIA | Xubuntu 26.10 | pending |
| Desktop | AMD | Xubuntu 26.10 | pending |
| any | any | Kubuntu 26.10 (KDE Plasma) | pending |
| any | any | Lubuntu 26.10 (LXQt) | pending |

Report yours: run `./3dmark-helper.sh logs` and open an issue.

## What still needs you
Everything is automatic except what only you can do: your **sudo password**, **Steam login**, accepting the **3DMark EULA**, and installing the individual tests from 3DMark's **Benchmarks** tab (Time Spy, Fire Strike, … are fetched in-app).

## Troubleshooting
- **No title-bar buttons** → 3DMark draws its own borderless window (same on Windows). Use the keyboard or the taskbar entry:

  | Desktop | Minimise | Maximise | Close | Move |
  |---|---|---|---|---|
  | GNOME (Ubuntu) | Super+H | Super+↑ | Alt+F4 | Super+drag |
  | XFCE (Xubuntu) | click taskbar entry | Alt+F10 | Alt+F4 | Alt+drag |
  | KDE Plasma (Kubuntu) | Meta+PgDn | Meta+PgUp | Alt+F4 | Meta+drag |
  | LXQt (Lubuntu, Openbox) | click taskbar entry / Alt+Space menu | Alt+Space → Maximize | Alt+F4 | Alt+drag |
- **Steam starts but no window appears (headless / VNC box)** → X has no connected monitor, so Steam's UI can't create windows ("Failed to create popup" in `logs/webhelper_js.txt`). `./3dmark-helper.sh headless` forces the HDMI connector on (sudo). Permanent: HDMI dummy plug or kernel arg `video=HDMI-A-1:1920x1080@60e`.
- **Steam started over SSH shows no window** → the helper borrows your desktop session's environment automatically; start it via the helper or from the desktop.
- **"System information not available"** → Futuremark SystemInfo can't read hardware under Proton; benchmarks still run.
- **Apt "Unable to satisfy dependencies … :i386 Breaks"** → handled automatically by `deps` (aligns amd64/i386 versions of the same source package).
- **Launcher never opens, no log** → 32-bit Vulkan missing: `./3dmark-helper.sh deps`.
- **Demo mode / only Basic Edition** → `./3dmark-helper.sh key 3dmark`.
- **Blank white launcher** → `OSMESA=1 ./3dmark-helper.sh setup 3dmark`.
- **"DirectX 12 compatible GPU" error** → you are on Proton 11: `./3dmark-helper.sh setup 3dmark`.
- **Tests greyed out / missing** → install the DLCs in Steam.
- **Wrong GPU used on laptop** → check `doctor`; on NVIDIA hybrids the PRIME vars are set automatically.
- Logs: add `PROTON_LOG=1` to launch options → `~/steam-223850.log`.

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
