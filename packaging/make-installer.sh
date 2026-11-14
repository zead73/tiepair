#!/bin/sh
# Builds the Windows setup program dist/tiepair-<version>-setup.exe with NSIS (makensis). The program
# is cross-compiled first (build-windows.sh): this script builds it when it is missing or older than the sources.
set -e
cd "$(dirname "$0")/.."
tools/check-version.sh
V=$(sed -n "s/^ *AppVersion = '\(.*\)';.*/\1/p" src/version.pas)
command -v makensis >/dev/null || { echo "makensis (NSIS) is not installed"; exit 1; }
[ build/tiepair.exe -nt src/version.pas ] || ./build-windows.sh
mkdir -p dist
makensis -V2 -DVERSION="$V" packaging/windows/installer.nsi
echo "Built: dist/tiepair-$V-setup.exe"
