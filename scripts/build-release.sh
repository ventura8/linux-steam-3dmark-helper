#!/usr/bin/env bash
# Build the release tarball + SHA256SUMS into dist/ (used by CI and the release workflow).
set -euo pipefail
cd "$(dirname "$0")/.."
version=$(tr -d '[:space:]' <VERSION)
name="linux-steam-3dmark-helper-$version"
rm -rf dist && mkdir -p "dist/$name"
# only tracked, shippable files (no tests, CI config or dev tooling)
git ls-files -z -- 3dmark-helper.sh lib VERSION LICENSE README.md ARCHITECTURE.md CHANGELOG.md \
  CONTRIBUTING.md SECURITY.md docs |
  tar --null -T - -cf - | tar -xf - -C "dist/$name"
tar --sort=name --owner=0 --group=0 --numeric-owner --mtime="@${SOURCE_DATE_EPOCH:-0}" \
  -C dist -czf "dist/$name.tar.gz" "$name"
cp 3dmark-helper.sh "dist/3dmark-helper.sh"
(cd dist && sha256sum "$name.tar.gz" 3dmark-helper.sh >SHA256SUMS && sha256sum -c SHA256SUMS)
rm -rf "dist/$name"
ls -l dist
