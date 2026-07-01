#!/usr/bin/env bash
# Print our packaging revision (pkgrel) for a given upstream version.
#
# .pkgrel holds one line "<version> <n>". If it names the given upstream version,
# print n; otherwise print 0 (a new upstream version resets our revision to 0).
# To ship a fix for the same upstream version, bump n in .pkgrel.
set -euo pipefail

UP="${1:?usage: pkgrel.sh <upstream-version>}"
HERE="$(cd "$(dirname "$0")" && pwd)"
FILE="$HERE/../.pkgrel"

if [ -f "$FILE" ]; then
  read -r fv fn _ < "$FILE" || true
  if [ "$fv" = "$UP" ] && printf '%s' "${fn:-}" | grep -qE '^[0-9]+$'; then
    echo "$fn"
    exit 0
  fi
fi
echo 0
