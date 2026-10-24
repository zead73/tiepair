#!/bin/sh
# Packs assets/cards/*.png, assets/win/*.png, assets/vampires/*.png, assets/shopkeeper/*.png, assets/specials/*.png, assets/house/*.png and assets/story/*.ini into app/cards.res (embedded in the exe as RCDATA),
# plus the program icon assets/icon/tiepair.ico (MAINICON: what Windows shows for the exe, and
# TIEPAIR_ICO: the same file as data, for the window icon the program sets itself).
# Resource names are the file names in upper case, e.g. CARD_HEARTS_01, WIN_SCREEN, STORY.
set -e
cd "$(dirname "$0")"
RC=app/cards.rc
: > "$RC"
for f in assets/cards/card_*.png assets/win/*.png assets/vampires/*.png assets/shopkeeper/*.png assets/specials/*.png assets/house/*.png assets/story/*.ini; do
  n=$(basename "$f"); n=${n%.*}; n=$(echo "$n" | tr 'a-z' 'A-Z')
  echo "$n RCDATA \"../$f\"" >> "$RC"
done
echo 'MAINICON ICON "../assets/icon/tiepair.ico"' >> "$RC"
# the same icon as plain data, so the program can set its own window icon on Linux
echo 'TIEPAIR_ICO RCDATA "../assets/icon/tiepair.ico"' >> "$RC"
N=$(wc -l < "$RC")
# the version (src/version.pas is the one place it is written): the exe's file properties on Windows
V=$(sed -n "s/^ *AppVersion = '\(.*\)';.*/\1/p" src/version.pas)
[ -n "$V" ] || { echo "no AppVersion in src/version.pas"; exit 1; }
VC=$(echo "$V" | tr . ,),0
{
  echo '1 VERSIONINFO'
  echo "FILEVERSION $VC"
  echo "PRODUCTVERSION $VC"
  echo 'BEGIN'
  echo '  BLOCK "StringFileInfo"'
  echo '  BEGIN'
  echo '    BLOCK "040904E4"'
  echo '    BEGIN'
  echo '      VALUE "FileDescription", "Tiepair, a gothic Pyramid solitaire"'
  echo "      VALUE \"FileVersion\", \"$V\""
  echo '      VALUE "ProductName", "Tiepair"'
  echo "      VALUE \"ProductVersion\", \"$V\""
  echo '      VALUE "LegalCopyright", "MIT licence"'
  echo '    END'
  echo '  END'
  echo '  BLOCK "VarFileInfo"'
  echo '  BEGIN'
  echo '    VALUE "Translation", 0x0409, 1252'
  echo '  END'
  echo 'END'
} >> "$RC"
fpcres -of res -o app/cards.res "$RC"
echo "Resources: app/cards.res ($N entries, version $V)"
