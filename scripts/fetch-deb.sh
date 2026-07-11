#!/usr/bin/env bash
# Download the official Claude Desktop .deb for an arch, verify its SHA256
# against the apt index, and extract the payload into a build root.
#
# Usage: fetch-deb.sh <amd64|arm64> <out-dir>
# Produces:
#   <out-dir>/claude.deb            the raw package
#   <out-dir>/payload/              extracted file tree (usr/...)
#   <out-dir>/version               the detected version string
set -euo pipefail

ARCH="${1:?usage: fetch-deb.sh <amd64|arm64> <out-dir>}"
OUT="${2:?usage: fetch-deb.sh <amd64|arm64> <out-dir>}"
HERE="$(cd "$(dirname "$0")" && pwd)"

mkdir -p "$OUT"
eval "$("$HERE/detect-version.sh" "$ARCH")"   # sets VERSION / DEB_URL / SHA256 / SIZE

echo "fetch-deb: version=$VERSION arch=$ARCH"
echo "fetch-deb: downloading $DEB_URL"
curl -fsSL -o "$OUT/claude.deb" "$DEB_URL"

got="$(sha256sum "$OUT/claude.deb" | cut -d' ' -f1)"
if [ "$got" != "$SHA256" ]; then
  echo "fetch-deb: SHA256 mismatch! expected=$SHA256 got=$got" >&2
  exit 1
fi
echo "fetch-deb: SHA256 OK"

# Extract: .deb is an ar archive containing data.tar.xz (the file tree).
rm -rf "$OUT/payload"; mkdir -p "$OUT/payload"
( cd "$OUT" && ar x claude.deb data.tar.xz )
tar xpf "$OUT/data.tar.xz" -C "$OUT/payload"

# Strictness guard: assert the expected upstream layout. If this fails the
# upstream package was restructured and the packaging recipes must be revisited.
test -x "$OUT/payload/usr/lib/claude-desktop/claude-desktop" \
  || { echo "fetch-deb: expected /usr/lib/claude-desktop/claude-desktop missing - upstream layout changed" >&2; exit 1; }
test -u "$OUT/payload/usr/lib/claude-desktop/chrome-sandbox" \
  || echo "fetch-deb: WARNING chrome-sandbox is not setuid in the payload" >&2

printf '%s\n' "$VERSION" > "$OUT/version"

# Upstream's desktop-entry filename is not stable across releases (e.g.
# 1.19367.0 renamed it from claude-desktop.desktop to com.anthropic.Claude.desktop,
# matching the app's own new package.json `desktopName`/WM_CLASS). Canonicalize
# it to claude-desktop.desktop here, once, so every downstream builder
# (rpm/deb/tarball/AppImage/Arch/Nix) keeps a stable install path instead of
# each rediscovering upstream's current name. Content is left untouched, so
# StartupWMClass etc. still faithfully reflects upstream's real app id.
APPS_DIR="$OUT/payload/usr/share/applications"
if [ ! -e "$APPS_DIR/claude-desktop.desktop" ]; then
  mapfile -t desktop_files < <(find "$APPS_DIR" -maxdepth 1 -name '*.desktop')
  if [ "${#desktop_files[@]}" -ne 1 ]; then
    echo "fetch-deb: expected exactly 1 .desktop file in $APPS_DIR, found ${#desktop_files[@]}: ${desktop_files[*]}" >&2
    exit 1
  fi
  mv "${desktop_files[0]}" "$APPS_DIR/claude-desktop.desktop"
  echo "fetch-deb: canonicalized $(basename "${desktop_files[0]}") -> claude-desktop.desktop"
fi

# Guard: fail the build if upstream introduced new, unreviewed absolute system
# paths that might be Debian-specific and break non-Debian distros (like the OVMF
# firmware paths cowork-firmware-paths fixes). Runs on the pristine asar and
# prints NATIVE-PATH-DRIFT so CI can open a per-version issue listing them.
node "$HERE/check-native-paths.mjs" "$OUT/payload" "$VERSION"

# Apply the minimal Linux patches to the payload's app.asar (auto-discovered from
# patches/). Needs node + node_modules (npm ci). Fails loud (naming the patches)
# if a pattern no longer matches, so CI can open a per-version issue.
node "$HERE/patch-payload.mjs" "$OUT/payload" "$VERSION"

# Add the hotkey helper alongside the main launcher: a bug here can never
# block the app from starting, since it never touches usr/bin/claude-desktop.
install -Dm755 "$HERE/../packaging/launcher/claude-desktop-hotkey" \
  "$OUT/payload/usr/bin/claude-desktop-hotkey"

# Replace the upstream bare symlink at usr/bin/claude-desktop with a launcher
# that adds opt-in env-var-gated Ozone/GPU workaround flags (issue #66), while
# leaving the real setuid chrome-sandbox enabled - this payload ends up
# installed system-wide as root (rpm, deb, and Arch, which packages this
# payload's usr/ tree verbatim), unlike the tarball/AppImage/Nix builds which
# ship their own separate --no-sandbox wrapper.
rm -f "$OUT/payload/usr/bin/claude-desktop"
install -Dm755 "$HERE/../packaging/launcher/claude-desktop-launcher" \
  "$OUT/payload/usr/bin/claude-desktop"

echo "fetch-deb: payload ready in $OUT/payload (version $VERSION, patched)"
