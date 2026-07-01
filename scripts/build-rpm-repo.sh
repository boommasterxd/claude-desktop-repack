#!/usr/bin/env bash
# Generate a signed dnf/zypper repository for GitHub Pages. Only the (tiny)
# repodata + the .repo file live on Pages; the packages themselves stay on the
# GitHub Release (free, unlimited bandwidth) - createrepo_c writes their location
# as the absolute release URL, so dnf downloads metadata from Pages and packages
# from the Release.
#
# Usage: build-rpm-repo.sh <dist-dir-with-rpms> <version> <pkgrel> <owner/repo> <site-dir>
# Produces: <site-dir>/rpm/repodata/... , <site-dir>/rpm/claude-desktop-repack.repo
# Requires: createrepo_c. If GPG_KEY_ID is set (and the key is in the gpg keyring),
# repomd.xml is detach-signed to repomd.xml.asc and the .repo enables repo_gpgcheck.
set -euo pipefail

DIST="${1:?usage: build-rpm-repo.sh <dist> <version> <pkgrel> <owner/repo> <site>}"
V="${2:?version}"; REL="${3:?pkgrel}"; REPO="${4:?owner/repo}"; SITE="${5:?site dir}"

OWNER="${REPO%%/*}"; NAME="${REPO##*/}"
PAGES_URL="https://${OWNER}.github.io/${NAME}"
REL_PREFIX="https://github.com/${REPO}/releases/download/v${V}-${REL}/"

RPMDIR="$SITE/rpm"
rm -rf "$RPMDIR"; mkdir -p "$RPMDIR"

# createrepo_c hashes the local rpms (so dnf can verify) but records the release
# URL as their location. We then drop the rpms - only repodata ships on Pages.
staging="$(mktemp -d)"; trap 'rm -rf "$staging"' EXIT
cp "$DIST"/claude-desktop-repack-*.rpm "$staging/"
createrepo_c --location-prefix "$REL_PREFIX" --revision "${V}-${REL}" "$staging" >/dev/null
cp -r "$staging/repodata" "$RPMDIR/repodata"

# Optional GPG signature over the metadata (repo_gpgcheck).
REPO_GPGCHECK=0
if [ -n "${GPG_KEY_ID:-}" ]; then
  gpg --batch --yes --local-user "$GPG_KEY_ID" --armor --detach-sign \
      --output "$RPMDIR/repodata/repomd.xml.asc" "$RPMDIR/repodata/repomd.xml"
  REPO_GPGCHECK=1
fi

# The .repo file users drop into /etc/yum.repos.d/. baseurl = the Pages repodata;
# packages resolve to the release via the absolute locations in the metadata.
cat > "$RPMDIR/claude-desktop-repack.repo" <<EOF
[claude-desktop-repack]
name=Claude Desktop (repack)
baseurl=${PAGES_URL}/rpm
enabled=1
gpgcheck=1
repo_gpgcheck=${REPO_GPGCHECK}
gpgkey=${PAGES_URL}/RELEASE-PUBKEY.asc
metadata_expire=6h
EOF

echo "build-rpm-repo: wrote $RPMDIR (repodata + .repo), packages point at the release"
echo "  install: sudo dnf config-manager --add-repo ${PAGES_URL}/rpm/claude-desktop-repack.repo"
