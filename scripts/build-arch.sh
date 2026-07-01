#!/usr/bin/env bash
# Build an Arch .pkg.tar.zst from the official .deb (patched), using makepkg
# inside an archlinux container so no Arch host is needed.
#
# Usage: build-arch.sh <amd64|arm64> [out-dir]
# Requires: docker. For arm64, qemu-user-static/binfmt must be registered on the
# host (CI does this via docker/setup-qemu-action).
set -euo pipefail

DEB_ARCH="${1:?usage: build-arch.sh <amd64|arm64> [out-dir]}"
OUTDIR="${2:-dist}"
HERE="$(cd "$(dirname "$0")" && pwd)"

# The Arch package is pure data (the .deb's usr/ tree, no compilation), so the
# aarch64 package can be built on an x86 host by overriding CARCH - no qemu.
case "$DEB_ARCH" in
  amd64) CARCH=x86_64; SUFFIX="" ;;
  arm64) CARCH=aarch64; SUFFIX="-aarch64" ;;
  *) echo "build-arch: unknown arch '$DEB_ARCH' (use amd64|arm64)" >&2; exit 1 ;;
esac
IMAGE="archlinux:latest"
command -v docker >/dev/null 2>&1 || { echo "build-arch: docker is required" >&2; exit 1; }

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK" 2>/dev/null || true' EXIT
PKGREL="${PKGREL:-0}"

# 1. Reuse an already-built tarball if one is present in OUTDIR (CI builds it
#    moments earlier), else build it now (fetch official .deb + patch + package).
if ls "$OUTDIR"/claude-desktop-repack-*-linux"${SUFFIX}".tar.gz >/dev/null 2>&1; then
  TARBALL="$(ls "$OUTDIR"/claude-desktop-repack-*-linux"${SUFFIX}".tar.gz)"
  echo "build-arch: reusing $TARBALL"
else
  PKGREL="$PKGREL" bash "$HERE/build-tarball.sh" "$DEB_ARCH" "$WORK/tarball"
  TARBALL="$(ls "$WORK"/tarball/claude-desktop-repack-*-linux"${SUFFIX}".tar.gz)"
fi
BASENAME="$(basename "$TARBALL")"
VERSION="$(printf '%s' "$BASENAME" | sed -E 's/^claude-desktop-repack-([0-9.]+)-[0-9]+-linux.*/\1/')"

# 2. Stage a makepkg build dir: local PKGBUILD (source = the tarball) + .install.
BUILD="$WORK/build"; mkdir -p "$BUILD"
cp "$TARBALL" "$BUILD/"
cp "$HERE/../packaging/arch/claude-desktop-repack.install" "$BUILD/"
sed -e "s/{{VERSION}}/$VERSION/g" \
    -e "s/{{PKGREL}}/$PKGREL/g" \
    -e "s#{{REPO}}#${GITHUB_REPOSITORY:-boommasterxd/claude-desktop-repack}#g" \
    -e "s#{{SRC_X64}}#$BASENAME#g" \
    -e "s#{{SRC_AARCH64}}#$BASENAME#g" \
    -e "s/{{SHA_X64}}/SKIP/g" \
    -e "s/{{SHA_AARCH64}}/SKIP/g" \
    "$HERE/../packaging/arch/PKGBUILD.in" > "$BUILD/PKGBUILD"

# 3. Build with makepkg (as a non-root user; base-devel provides fakeroot).
#    --nodeps: package() only copies files, no build/runtime deps needed here.
docker run --rm -e TARGET_CARCH="$CARCH" -e HOST_UID="$(id -u)" -e HOST_GID="$(id -g)" \
    -v "$BUILD":/build "$IMAGE" bash -c '
  set -e
  pacman -Sy --noconfirm --needed archlinux-keyring >/dev/null 2>&1 || true
  pacman -S  --noconfirm --needed base-devel >/dev/null 2>&1
  # Cross-target aarch64 on an x86 host: the package only copies files, so
  # overriding CARCH yields a correct aarch64 (data-only) package without qemu.
  sed -i "s/^CARCH=.*/CARCH=\"$TARGET_CARCH\"/" /etc/makepkg.conf
  useradd -m builder 2>/dev/null || true
  chown -R builder:builder /build
  su builder -c "cd /build && makepkg -f --nodeps --noconfirm --skipinteg"
  # Hand the build dir back to the host user: files created in-container are
  # owned by a uid the host runner cannot delete, which would fail its cleanup.
  chown -R "$HOST_UID:$HOST_GID" /build
'

# 4. Collect the package.
mkdir -p "$OUTDIR"
cp "$BUILD"/*.pkg.tar.zst "$OUTDIR/"
echo "build-arch: wrote $(ls "$OUTDIR"/claude-desktop-repack-*-"${CARCH}".pkg.tar.zst)"
