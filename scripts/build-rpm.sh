#!/usr/bin/env bash
# Build a Claude Desktop RPM from the official .deb for the given arch.
#
# Usage: build-rpm.sh <amd64|arm64> [out-dir]
# Requires: rpmbuild, curl, tar, xz, ar (binutils), coreutils.
# If PAYLOAD_DIR is set, it must already contain a fetch-deb.sh output (claude.deb
# + payload/ + version) and is used as-is instead of fetching/patching again -
# lets a caller building several formats share one fetch+patch across all of them.
set -euo pipefail

DEB_ARCH="${1:?usage: build-rpm.sh <amd64|arm64> [out-dir]}"
OUTDIR="${2:-dist}"
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"

case "$DEB_ARCH" in
  amd64) RPM_ARCH=x86_64 ;;
  arm64) RPM_ARCH=aarch64 ;;
  *) echo "build-rpm: unknown arch '$DEB_ARCH' (use amd64|arm64)" >&2; exit 1 ;;
esac

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# 1. Fetch + verify + extract the official .deb, unless a caller already did
#    this once and points us at the result via PAYLOAD_DIR (avoids re-fetching
#    and re-patching the same payload once per output format).
FETCHED="${PAYLOAD_DIR:-$WORK}"
if [ -z "${PAYLOAD_DIR:-}" ]; then
  "$HERE/fetch-deb.sh" "$DEB_ARCH" "$FETCHED"
fi
VERSION="$(cat "$FETCHED/version")"
PKGREL="${PKGREL:-0}"

# 2. Build the RPM with rpmbuild (cross-arch is fine: we only package files).
#    Version = upstream, Release = our pkgrel (so a fix rebuild is an upgrade).
RB="$WORK/rpmbuild"
mkdir -p "$RB"/{BUILD,RPMS,SOURCES,SPECS,BUILDROOT}
rpmbuild -bb \
  --target "$RPM_ARCH" \
  --define "_topdir $RB" \
  --define "_claude_version $VERSION" \
  --define "_pkgrel $PKGREL" \
  --define "_claude_payload $FETCHED/payload" \
  "$ROOT/packaging/rpm/claude-desktop-repack.spec"

# 3. Collect the artifact.
mkdir -p "$OUTDIR"
find "$RB/RPMS" -name '*.rpm' -exec cp -v {} "$OUTDIR/" \;
echo "build-rpm: done -> $OUTDIR (version $VERSION-$PKGREL, $RPM_ARCH)"
