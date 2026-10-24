#!/bin/sh
# Builds the web version into web/dist (static files you can put on any website).
# Needs pas2js 3.x with its runtime library: set PAS2JS_DIR to the unpacked
# pas2js-linux-x86_64-<version> folder (see the Tiecards README). Then test it with
#     cd web/dist && python3 -m http.server 8766
# and open http://127.0.0.1:8766/ (open it through a server, not as a file).
set -e
cd "$(dirname "$0")/.."
tools/check-version.sh
PAS2JS_DIR=${PAS2JS_DIR:-$HOME/.local/share/tiecards-pas2js/pas2js-linux-x86_64-3.0.1}
P="$PAS2JS_DIR/bin/pas2js"
[ -x "$P" ] || { echo "pas2js not found at $PAS2JS_DIR (set PAS2JS_DIR)"; exit 1; }
D=web/dist
rm -rf "$D"
mkdir -p "$D/assets/cards" "$D/assets/house" "$D/icons"
"$P" -Tbrowser -Jc -Fusrc -Fuweb/src -FE"$D" -Jirtl.js web/src/tiepairweb.pas
cp web/index.html web/glue.js web/manifest.webmanifest "$D/"
cp assets/cards/*.png "$D/assets/cards/"
cp assets/house/house.png "$D/assets/house/"
cp web/icons/*.png "$D/icons/"
echo "Built: $D (open through a web server, e.g. cd web/dist && python3 -m http.server 8766)"
