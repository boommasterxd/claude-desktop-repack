#!/usr/bin/env bash
# Build a signed apt repository under <site>/deb/ for GitHub Pages. apt needs the
# packages reachable relative to the repo base, so the .deb files are hosted on
# Pages too (latest only, so two files). The Release file is GPG-signed (InRelease
# + Release.gpg); users add the key via signed-by= in their sources list.
#
# Usage: build-apt-repo.sh <dist-dir-with-debs> <site-dir>
# Requires: dpkg-scanpackages (dpkg-dev), apt-ftparchive (apt-utils), gzip, gpg
# (GPG_KEY_ID for signing; unsigned Release if empty).
set -euo pipefail

DIST="${1:?usage: build-apt-repo.sh <dist> <site>}"
SITE="${2:?site dir}"
DEB="$SITE/deb"
POOL="pool/main/c/claude-desktop-repack"

rm -rf "$DEB"; mkdir -p "$DEB/$POOL"
cp "$DIST"/claude-desktop-repack_*_*.deb "$DEB/$POOL/"

cd "$DEB"
for arch in amd64 arm64; do
  d="dists/stable/main/binary-$arch"
  mkdir -p "$d"
  # Filename in Packages is relative to the repo base (= <pages>/deb).
  dpkg-scanpackages --arch "$arch" pool > "$d/Packages" 2>/dev/null
  gzip -9kf "$d/Packages"
done

apt-ftparchive \
  -o APT::FTPArchive::Release::Origin="claude-desktop-repack" \
  -o APT::FTPArchive::Release::Label="claude-desktop-repack" \
  -o APT::FTPArchive::Release::Suite="stable" \
  -o APT::FTPArchive::Release::Codename="stable" \
  -o APT::FTPArchive::Release::Components="main" \
  -o APT::FTPArchive::Release::Architectures="amd64 arm64" \
  release dists/stable > dists/stable/Release

if [ -n "${GPG_KEY_ID:-}" ]; then
  gpg --batch --yes --local-user "$GPG_KEY_ID" --clearsign -o dists/stable/InRelease dists/stable/Release
  gpg --batch --yes --local-user "$GPG_KEY_ID" -abs -o dists/stable/Release.gpg dists/stable/Release
fi

echo "build-apt-repo: wrote $DEB (pool + dists, $([ -n "${GPG_KEY_ID:-}" ] && echo signed || echo unsigned))"
