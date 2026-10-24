#!/bin/sh
# Fails if the newest heading in CHANGELOG.md is not the version in src/version.pas
# (the one place the version is written).
cd "$(dirname "$0")/.."
V=$(sed -n "s/^ *AppVersion = '\(.*\)';.*/\1/p" src/version.pas)
[ -n "$V" ] || { echo "check-version: no AppVersion in src/version.pas"; exit 1; }
L=$(sed -n 's/^## \([0-9][0-9.]*\).*/\1/p' CHANGELOG.md | head -1)
if [ "$L" != "$V" ]; then
  echo "check-version: CHANGELOG.md says '$L', src/version.pas says '$V'"
  echo "Write the '## $V' section in CHANGELOG.md, or fix the version with tools/set-version.sh"
  exit 1
fi
echo "version $V"
