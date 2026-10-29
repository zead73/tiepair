#!/bin/sh
# Builds the web version into web/dist (static files you can put on any website).
# Needs pas2js 3.x with its runtime library: set PAS2JS_DIR to the unpacked
# pas2js-linux-x86_64-<version> folder (see the Tiecards README). Then test it with
#     cd web/dist && python3 -m http.server 8767
# and open http://127.0.0.1:8767/ (open it through a server, not as a file).
set -e
cd "$(dirname "$0")/.."
tools/check-version.sh
PAS2JS_DIR=${PAS2JS_DIR:-$HOME/.local/share/tiecards-pas2js/pas2js-linux-x86_64-3.0.1}
P="$PAS2JS_DIR/bin/pas2js"
[ -x "$P" ] || { echo "pas2js not found at $PAS2JS_DIR (set PAS2JS_DIR)"; exit 1; }
D=web/dist
rm -rf "$D"
mkdir -p "$D/assets/cards" "$D/assets/vampires" "$D/assets/win" "$D/assets/shopkeeper" "$D/assets/specials" "$D/assets/house" "$D/icons"
"$P" -Tbrowser -Jc -Fusrc -Fuweb/src -FE"$D" -Jirtl.js web/src/tiepairweb.pas
cp web/index.html web/glue.js web/vr.js web/vr-main.js web/vr-table.js web/vr-room.js web/manifest.webmanifest "$D/"
# the VR files are loaded with ?v=<a fingerprint of them>, so that a browser which kept an old copy
# (the Quest's does) fetches the new one; the same fingerprint is shown in the toolbar
python3 - <<'PY'
import hashlib
names = ['web/vr.js', 'web/vr-main.js', 'web/vr-table.js', 'web/vr-room.js', 'web/vendor/three.module.min.js']
h = hashlib.sha256()
for n in names:
    h.update(open(n, 'rb').read())
build = h.hexdigest()[:8]
for n in ['web/dist/vr.js', 'web/dist/vr-main.js', 'web/dist/vr-table.js', 'web/dist/vr-room.js', 'web/dist/index.html']:
    t = open(n, encoding='utf-8').read().replace('__BUILD__', build)
    open(n, 'w', encoding='utf-8').write(t)
print('vr build', build)
PY
mkdir -p "$D/vendor"
cp web/vendor/three.module.min.js web/vendor/three.LICENSE "$D/vendor/"
cp assets/cards/*.png "$D/assets/cards/"
cp assets/vampires/*.png "$D/assets/vampires/"
cp assets/win/win_screen.png "$D/assets/win/"
cp assets/shopkeeper/*.png "$D/assets/shopkeeper/"
cp assets/specials/*.png "$D/assets/specials/"
cp assets/house/*.png "$D/assets/house/"
cp web/icons/*.png "$D/icons/"
# the story text, embedded as a script (no fetch, so it also works from a file)
python3 - <<'PY'
import json
text = open('assets/story/story.ini', encoding='utf-8').read()
open('web/dist/story.js', 'w', encoding='utf-8').write('window.TC_STORY = ' + json.dumps(text) + ';\n')
PY
# the service worker (offline play): a fingerprint of every file, and the file list
python3 - <<'PY'
import hashlib, os
root = 'web/dist'
files = []
for d, _, names in os.walk(root):
    for n in names:
        rel = os.path.relpath(os.path.join(d, n), root).replace(os.sep, '/')
        if rel != 'sw.js':
            files.append(rel)
files.sort()
h = hashlib.sha256()
for rel in files:
    h.update(rel.encode())
    h.update(open(os.path.join(root, rel), 'rb').read())
version = h.hexdigest()[:16]
listing = ['./'] + files
src = open('web/sw.template.js', encoding='utf-8').read()
src = src.replace('__VERSION__', version).replace('__FILES__', '[' + ', '.join('"%s"' % f for f in listing) + ']')
open(os.path.join(root, 'sw.js'), 'w', encoding='utf-8').write(src)
print('service worker: %d files, version %s' % (len(listing), version))
PY
echo "Built: $D (open through a web server, e.g. cd $D && python3 -m http.server 8767)"
