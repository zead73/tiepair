#!/bin/sh
# Usage: tools/set-version.sh MAJOR.MINOR.PATCH
# Writes the version into src/version.pas, and stops if CHANGELOG.md has no
# "## <version>" heading yet (write that first: it is the record of what changed).
set -e
cd "$(dirname "$0")/.."
V="$1"
case "$V" in
  [0-9]*.[0-9]*.[0-9]*) ;;
  *) echo "usage: $0 MAJOR.MINOR.PATCH"; exit 1 ;;
esac
grep -q "^## $V\b" CHANGELOG.md || { echo "Add a '## $V' section to CHANGELOG.md first."; exit 1; }
sed -i "s/^\( *AppVersion = '\).*\(';.*\)/\1$V\2/" src/version.pas
tools/check-version.sh
