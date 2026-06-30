#!/usr/bin/env bash
# Build an AppImage (+ .zsync delta-update file) from the official .deb.
#
# Usage: build-appimage.sh <amd64|arm64> [out-dir]
# Update info (for the .zsync transport) is derived from $GITHUB_REPOSITORY
# (owner/repo) so nothing is hardcoded to any particular repository. When that
# env var is unset (local builds) the AppImage is built without update info and
# no .zsync is produced.
#
# Requires: curl, tar, xz, ar (binutils), zsyncmake (zsync). appimagetool is
# downloaded if missing. Set APPIMAGE_EXTRACT_AND_RUN=1 on FUSE-less CI runners.
set -euo pipefail

DEB_ARCH="${1:?usage: build-appimage.sh <amd64|arm64> [out-dir]}"
OUTDIR="${2:-dist}"
HERE="$(cd "$(dirname "$0")" && pwd)"
HOST_ARCH="$(uname -m)"
export APPIMAGE_EXTRACT_AND_RUN="${APPIMAGE_EXTRACT_AND_RUN:-1}"

case "$DEB_ARCH" in
  amd64) APP_ARCH=x86_64 ;;
  arm64) APP_ARCH=aarch64 ;;
  *) echo "build-appimage: unknown arch '$DEB_ARCH'" >&2; exit 1 ;;
esac

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
"$HERE/fetch-deb.sh" "$DEB_ARCH" "$WORK"
VERSION="$(cat "$WORK/version")"

APPDIR="$WORK/AppDir"
mkdir -p "$APPDIR"
cp -a "$WORK/payload/usr" "$APPDIR/usr"

# AppImages are mounted nosuid, so chrome-sandbox cannot be setuid here; run with
# --no-sandbox (standard for portable Electron apps).
cat > "$APPDIR/AppRun" <<'EOF'
#!/bin/sh
HERE="$(dirname "$(readlink -f "$0")")"
exec "$HERE/usr/lib/claude-desktop/claude-desktop" --no-sandbox "$@"
EOF
chmod +x "$APPDIR/AppRun"

# appimagetool wants a top-level .desktop + icon.
cp "$APPDIR/usr/share/applications/claude-desktop.desktop" "$APPDIR/claude-desktop.desktop"
cp "$APPDIR/usr/share/icons/hicolor/256x256/apps/claude-desktop.png" "$APPDIR/claude-desktop.png"

# appimagetool runs on the build HOST architecture (it only writes the target runtime).
TOOL="appimagetool"
if ! command -v appimagetool >/dev/null 2>&1; then
  TOOL="$WORK/appimagetool"
  curl -fsSL -o "$TOOL" \
    "https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-${HOST_ARCH}.AppImage"
  chmod +x "$TOOL"
fi

mkdir -p "$OUTDIR"
OUT="$OUTDIR/claude-desktop-repack-${VERSION}-${APP_ARCH}.AppImage"

ARGS=()
if [ -n "${GITHUB_REPOSITORY:-}" ]; then
  OWNER="${GITHUB_REPOSITORY%%/*}"; REPO="${GITHUB_REPOSITORY##*/}"
  ARGS+=( -u "gh-releases-zsync|${OWNER}|${REPO}|latest|claude-desktop-repack-*-${APP_ARCH}.AppImage.zsync" )
else
  echo "build-appimage: GITHUB_REPOSITORY unset - building without update info (.zsync skipped)" >&2
fi

ARCH="$APP_ARCH" "$TOOL" "${ARGS[@]}" "$APPDIR" "$OUT"
echo "build-appimage: wrote $OUT"
ls -1 "$OUTDIR"/claude-desktop-repack-"${VERSION}"-"${APP_ARCH}".AppImage* 2>/dev/null || true
