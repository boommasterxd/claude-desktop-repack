#!/usr/bin/env bash
# Sign the release artifacts in a directory:
#   - embed a GPG signature in every RPM (so dnf / rpm --checksig verify natively)
#   - write SHA256SUMS.txt and a detached, armored SHA256SUMS.txt.asc (the
#     universal anchor that also covers the AppImages and tarballs)
#   - export the public key as RELEASE-PUBKEY.asc
#
# Driven by env:
#   GPG_PRIVATE_KEY   ASCII-armored private key (required to sign; if empty the
#                     script only writes SHA256SUMS.txt and exits 0 unsigned)
#   GPG_PASSPHRASE    optional; omit for a passphraseless CI key (recommended)
#
# Usage: sign-artifacts.sh [dist-dir]
set -euo pipefail

DIST="${1:-dist}"
cd "$DIST"

list_assets() { ls -1 | grep -vE '^(SHA256SUMS\.txt(\.asc)?|RELEASE-PUBKEY\.asc)$' || true; }

if [ -z "${GPG_PRIVATE_KEY:-}" ]; then
  echo "sign: GPG_PRIVATE_KEY not set -> producing unsigned SHA256SUMS.txt only"
  sha256sum $(list_assets) > SHA256SUMS.txt
  exit 0
fi

export GNUPGHOME="$(mktemp -d)"
chmod 700 "$GNUPGHOME"
# Each GitHub Actions step runs in its own shell, so a plain `export` here is
# invisible to later steps (e.g. "Build Pages site", which re-derives
# GPG_KEY_ID and re-signs the pacman/apt repo metadata with this same key).
# Persist it job-wide via $GITHUB_ENV so those steps' gpg finds the imported
# secret key instead of a fresh, empty keyring.
[ -n "${GITHUB_ENV:-}" ] && echo "GNUPGHOME=$GNUPGHOME" >> "$GITHUB_ENV"
printf '%s\n' "$GPG_PRIVATE_KEY" | gpg --batch --import
KEYID="$(gpg --list-secret-keys --with-colons | awk -F: '/^sec:/{print $5; exit}')"
[ -n "$KEYID" ] || { echo "sign: no secret key imported" >&2; exit 1; }
echo "sign: signing with key $KEYID"
gpg --batch --yes --armor --export "$KEYID" > RELEASE-PUBKEY.asc

PASS_ARGS=()
[ -n "${GPG_PASSPHRASE:-}" ] && PASS_ARGS=(--pinentry-mode loopback --passphrase "$GPG_PASSPHRASE")

# 1. Embed signatures into the RPMs.
if ls *.rpm >/dev/null 2>&1; then
  command -v rpmsign >/dev/null 2>&1 || {
    echo "sign: rpmsign not found - install it (Debian/Ubuntu: package 'rpm'; Fedora: 'rpm-sign')" >&2
    exit 1
  }
  cat > "$HOME/.rpmmacros" <<EOF
%_gpg_name $KEYID
EOF
  if [ -n "${GPG_PASSPHRASE:-}" ]; then
    cat >> "$HOME/.rpmmacros" <<EOF
%__gpg_sign_cmd %{__gpg} gpg --batch --no-armor --pinentry-mode loopback --passphrase '$GPG_PASSPHRASE' --no-secmem-warning -u "%{_gpg_name}" --sign --detach-sign --output %{__signature_filename} %{__plaintext_filename}
EOF
  fi
  rpmsign --addsign *.rpm
fi

# 2. Checksums over the final assets (RPMs changed after signing) + sign them.
sha256sum $(list_assets) > SHA256SUMS.txt
gpg --batch --yes "${PASS_ARGS[@]}" --armor --detach-sign --output SHA256SUMS.txt.asc SHA256SUMS.txt

echo "sign: done -> SHA256SUMS.txt, SHA256SUMS.txt.asc, RELEASE-PUBKEY.asc"
