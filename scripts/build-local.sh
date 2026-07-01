#!/usr/bin/env bash
# Build package formats locally into ./dist for testing, exactly like CI does
# (same per-format scripts), just without uploading anything.
#
# Usage:
#   scripts/build-local.sh [arch] [format ...]
#     arch     amd64 (default) | arm64
#     format   any of: rpm deb tarball appimage arch   (default: rpm tarball appimage)
#
# Examples:
#   scripts/build-local.sh                 # all formats, amd64
#   scripts/build-local.sh amd64 rpm       # just the x86_64 RPM
#   scripts/build-local.sh arm64 tarball   # aarch64 tarball (cross, no run-test)
#
# Optional local signing: export GPG_PRIVATE_KEY (and GPG_PASSPHRASE) to also
# produce a signed SHA256SUMS.txt.asc, just like the release.
#
# Tooling: rpmbuild (rpm-build), ar (binutils), tar, xz, curl. appimagetool is
# downloaded on demand; zsyncmake (zsync) is only needed for the .zsync delta
# file, which is skipped locally anyway (no update info outside CI). The `deb`
# format additionally needs dpkg-deb; `arch` needs docker (runs makepkg in an
# archlinux container).
set -euo pipefail

ARCH="${1:-amd64}"
shift || true
FORMATS=("$@")
[ "${#FORMATS[@]}" -eq 0 ] && FORMATS=(rpm tarball appimage)

HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="dist"
mkdir -p "$OUT"

# rpm/deb/tarball/appimage all fetch+patch the same official .deb; when more
# than one is requested, do it once here and share it via PAYLOAD_DIR instead
# of repeating the fetch+patch per format (same trick CI uses).
for fmt in "${FORMATS[@]}"; do
  case "$fmt" in rpm|deb|tarball|appimage)
    PAYLOAD_DIR="$(mktemp -d)"
    trap 'rm -rf "$PAYLOAD_DIR"' EXIT
    bash "$HERE/fetch-deb.sh" "$ARCH" "$PAYLOAD_DIR"
    export PAYLOAD_DIR
    break ;;
  esac
done

for fmt in "${FORMATS[@]}"; do
  case "$fmt" in
    rpm)      bash "$HERE/build-rpm.sh"      "$ARCH" "$OUT" ;;
    tarball)  bash "$HERE/build-tarball.sh"  "$ARCH" "$OUT" ;;
    appimage) bash "$HERE/build-appimage.sh" "$ARCH" "$OUT" ;;
    deb)      bash "$HERE/build-deb.sh"      "$ARCH" "$OUT" ;;
    arch)     bash "$HERE/build-arch.sh"     "$ARCH" "$OUT" ;;
    *) echo "build-local: unknown format '$fmt' (use rpm|deb|tarball|appimage|arch)" >&2; exit 1 ;;
  esac
done

# Mirror the release's checksum/signing step (unsigned unless GPG_PRIVATE_KEY set).
bash "$HERE/sign-artifacts.sh" "$OUT" || true

echo
echo "build-local: artifacts in ./$OUT"
ls -lh "$OUT"
