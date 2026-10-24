#!/bin/sh
# Checks that the game's rules code still works as JavaScript (for a web version):
#  1. every UI-free unit in src/ compiles with pas2js, and so does the web page's
#     own code (web/src);
#  2. every test program in tests/ compiles with pas2js and passes under Node.
# Needs pas2js 3.x with its runtime library (the Arch fpc package has no runtime
# library) and Node. Point PAS2JS_DIR at the unpacked
# pas2js-linux-x86_64-<version> folder; see TODO.md. Skips (exit 0) if it is not there.
cd "$(dirname "$0")/.." || exit 1
PAS2JS_DIR=${PAS2JS_DIR:-$HOME/.local/share/tiecards-pas2js/pas2js-linux-x86_64-3.0.1}
P="$PAS2JS_DIR/bin/pas2js"
if [ ! -x "$P" ] || ! command -v node >/dev/null 2>&1; then
  echo "pas2js check skipped: no pas2js at $PAS2JS_DIR (set PAS2JS_DIR) or no node"
  exit 0
fi
OUT=$(mktemp -d) || exit 1
trap 'rm -rf "${OUT:?}"' EXIT
fail=0
for f in src/*.pas; do
  u=$(basename "$f" .pas)
  if ! "$P" -Tnodejs -Fusrc -FE"$OUT" -Jc- "$f" >"$OUT/log" 2>&1; then
    echo "FAIL compile src/$u.pas"; grep -E "Error|Fatal" "$OUT/log" | head -3; fail=1
  fi
done
for f in tests/test*.pas; do
  t=$(basename "$f" .pas)
  if ! "$P" -Tnodejs -Fusrc -Futests/js -FE"$OUT" "$f" >"$OUT/log" 2>&1; then
    echo "FAIL compile $f"; grep -E "Error|Fatal" "$OUT/log" | head -3; fail=1; continue
  fi
  res=$(node "$OUT/$t.js" 2>&1 | tail -1)
  case "$res" in
    *PASSED*|OK:*) echo "ok   $t: $res" ;;
    *) echo "FAIL $t: $res"; fail=1 ;;
  esac
done
# the web front end (web/src) must compile for the browser too
if ! "$P" -Tbrowser -Jc -Fusrc -Fuweb/src -FE"$OUT" -Jirtl.js web/src/tiepairweb.pas >"$OUT/log" 2>&1; then
  echo "FAIL compile web/src/tiepairweb.pas"; grep -E "Error|Fatal" "$OUT/log" | head -3; fail=1
else
  echo "ok   web front end compiles for the browser"
fi
[ $fail = 0 ] && echo "pas2js check: all good" || echo "pas2js check: PROBLEMS"
exit $fail
