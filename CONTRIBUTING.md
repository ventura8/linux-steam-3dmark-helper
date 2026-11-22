# Contributing

Thanks for helping make 3DMark work on Linux!

## Report a test result (most valuable!)
1. Run `./3dmark-helper.sh logs` after trying a benchmark.
2. Open an issue with: distro + desktop, GPU + driver, Proton version, which tests worked/failed, scores if any, and attach the tarball.

## Develop
```bash
sudo apt install shellcheck bats
bats tests/ && shellcheck -S warning 3dmark-helper.sh
```
- Bash: `set -euo pipefail`, shellcheck-clean, functions named `cmd_*` for subcommands.
- Python helpers: standard library only (Pillow optional), run with `python3 -I`.
- Never edit Steam config while Steam runs (`stop_steam` first).
- Never redistribute or patch 3DMark binaries.
- Keep it automatic: prompts only when `--ask` is passed.
- See [ARCHITECTURE.md](ARCHITECTURE.md) before larger changes.

## Pull requests
Small, focused PRs with a line in [CHANGELOG.md](CHANGELOG.md) under *Unreleased*.
