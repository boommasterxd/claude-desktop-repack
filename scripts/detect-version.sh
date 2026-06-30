#!/usr/bin/env bash
# Detect the latest official Claude Desktop .deb from Anthropic's apt repository.
# Prints VERSION / DEB_URL / SHA256 / SIZE for the given arch (amd64|arm64).
#
# The apt repo is the stable, machine-readable source of truth:
#   dists/stable/main/binary-<arch>/Packages  lists every published version
#   with Version, Filename, SHA256 and Size.
set -euo pipefail

ARCH="${1:-amd64}"
BASE="https://downloads.claude.ai/claude-desktop/apt/stable"

PKG="$(curl -fsSL "$BASE/dists/stable/main/binary-$ARCH/Packages")"

# Parse every stanza, keep the highest Version (dpkg/semver-ish, `sort -V` is fine).
latest="$(printf '%s\n' "$PKG" | awk -v RS='' '
  /Package: claude-desktop/ {
    v=""; f=""; s=""; sz=""
    n = split($0, lines, "\n")
    for (i = 1; i <= n; i++) {
      if (lines[i] ~ /^Version: /)  v  = substr(lines[i], 10)
      if (lines[i] ~ /^Filename: /) f  = substr(lines[i], 11)
      if (lines[i] ~ /^SHA256: /)   s  = substr(lines[i], 9)
      if (lines[i] ~ /^Size: /)     sz = substr(lines[i], 7)
    }
    print v "\t" f "\t" s "\t" sz
  }' | sort -V | tail -1)"

VERSION="$(cut -f1 <<<"$latest")"
FILE="$(cut -f2 <<<"$latest")"
SHA="$(cut -f3 <<<"$latest")"
SIZE="$(cut -f4 <<<"$latest")"

[ -n "$VERSION" ] || { echo "detect-version: no claude-desktop stanza found for arch=$ARCH" >&2; exit 1; }

echo "VERSION=$VERSION"
echo "DEB_URL=$BASE/$FILE"
echo "SHA256=$SHA"
echo "SIZE=$SIZE"
