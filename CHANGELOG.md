# Changelog

Format: [Keep a Changelog](https://keepachangelog.com/), versions: [SemVer](https://semver.org/).

## [Unreleased]
### Added
- KDE Plasma (Kubuntu) and LXQt (Lubuntu) support: menu cache refresh, Klipper clipboard, per-desktop window shortcuts.
- Launch Steam with the desktop session environment when run over SSH/TTY (fixes Steam with no window).
- ARCHITECTURE.md (Mermaid diagrams), CONTRIBUTING.md, SECURITY.md, CHANGELOG.md.

## [0.1.0] - 2026-11-22
### Added
- `install`, `doctor`, `deps`, `install-steam`, `login`, `install-apps`, `setup`, `prefix`, `key`, `shortcuts`, `launch-options`, `logs`.
- Dialog-free app installs via stub manifests; Proton 10 pinned before download.
- Per-GPU launch options (NVIDIA hybrid/desktop, AMD, Intel).
- Automatic amd64/i386 multiarch version alignment.
- CD key via `steam://cdkeys` + clipboard; EULA detection.
- App-menu entries with icons extracted from the game executables.
