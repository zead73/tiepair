#!/bin/bash
# Runs INSIDE the build container (see Dockerfile): compiles the Lazarus (Qt5) program, assembles the
# AppDir with the Qt5 libraries and plugins it needs, and packs dist/tiepair-<version>-x86_64.AppImage.
# Start it with ./build-appimage.sh, which builds the image and mounts this folder at /src.
set -euo pipefail
cd /src
V=$(sed -n "s/^ *AppVersion = '\(.*\)';.*/\1/p" src/version.pas)
APPDIR=/src/build/appimage/Tiepair.AppDir
OUT=/src/dist/tiepair-$V-x86_64.AppImage
LIBDIR=$APPDIR/usr/lib
PLUGDIR=$APPDIR/usr/plugins

# 1. compile, in a copy, so that the units built here (Debian's compiler) never mix with the host's
rm -rf /work && mkdir -p /work/build
cp -a app src /work/
cd /work
lazbuild --primary-config-path=/tmp/lazcfg --ws=qt5 app/tiepair.lpi 2>&1 | grep -E "Error|Fatal|Linking|lines compiled" || true
[ -x build/tiepair ] || { echo "the build failed" >&2; exit 1; }
strip --strip-unneeded build/tiepair
cd /src

# 2. the AppDir
rm -rf "$APPDIR"
mkdir -p "$APPDIR/usr/bin" "$LIBDIR" "$PLUGDIR/platforms" "$APPDIR/usr/share/doc/tiepair"
cp /work/build/tiepair "$APPDIR/usr/bin/tiepair"
# qt.conf next to the program confines Qt to the plugins and libraries in this AppImage. Without it Qt also searches the folder that
# was built into it (/usr/lib/x86_64-linux-gnu/qt5/plugins), loads the plugins of the computer's own Qt (libqsvg, the GLX integration,
# ...) into the bundled one, and two different Qt copies in one process end in "realloc(): invalid pointer" on any computer that has
# another Qt 5 installed. (QT_PLUGIN_PATH only adds a folder, it does not remove that one.)
printf '[Paths]\nPrefix=..\nPlugins=plugins\nLibraries=lib\n' > "$APPDIR/usr/bin/qt.conf"
cp LICENSE README.md CHANGELOG.md "$APPDIR/usr/share/doc/tiepair/"
cp assets/cards_src/CREDITS.txt assets/cards_src/LICENSE.txt "$APPDIR/usr/share/doc/tiepair/" 2>/dev/null || true

# libraries tied to the kernel and glibc, or to the machine's own graphics, come from the host
is_host() {
  case "$1" in
    libc.so.*|libm.so.*|libdl.so.*|libpthread.so.*|librt.so.*|libutil.so.*|libresolv.so.*|libnsl.so.*) return 0 ;;
    ld-linux*|linux-vdso*) return 0 ;;
    libGL.so.*|libGLX.so.*|libGLdispatch.so.*|libEGL.so.*|libOpenGL.so.*|libgbm.so.*|libdrm.so.*) return 0 ;;
    libfontconfig.so.*|libfreetype.so.*|libexpat.so.*) return 0 ;;
  esac
  return 1
}
deps() { ldd "$1" 2>/dev/null | awk '/=>/ && $3 ~ /^\// {print $3}'; }
QTPLUG=$(qmake -query QT_INSTALL_PLUGINS 2>/dev/null || true)
[ -d "$QTPLUG" ] || QTPLUG=$(dirname "$(find /usr/lib -name libqxcb.so | head -1)")/..
QTPLUG=$(readlink -f "$QTPLUG")
cp "$QTPLUG/platforms/libqxcb.so" "$PLUGDIR/platforms/"
# (the game draws with plain Qt painting and uses no OpenGL: without the xcbglintegrations plugin Qt does not go looking
# for a GLX visual, which is what filled the terminal with "No XVisualInfo for format" warnings)
for extra in imageformats; do
  [ -d "$QTPLUG/$extra" ] && cp -r "$QTPLUG/$extra" "$PLUGDIR/"
done
# everything the program and the plugins link against (repeated until nothing new turns up)
for pass in 1 2 3 4; do
  for seed in "$APPDIR/usr/bin/tiepair" "$PLUGDIR"/*/*.so "$LIBDIR"/*.so*; do
    [ -e "$seed" ] || continue
    for dep in $(deps "$seed"); do
      base=$(basename "$dep")
      is_host "$base" && continue
      [ -e "$LIBDIR/$base" ] || cp -L "$dep" "$LIBDIR/$base"
    done
  done
done
# the plugins find the Qt libraries next to them
for so in "$PLUGDIR"/*/*.so; do patchelf --set-rpath '$ORIGIN/../../lib' "$so"; done

install -m 755 packaging/appimage/AppRun "$APPDIR/AppRun"
install -m 644 packaging/appimage/tiepair.desktop "$APPDIR/tiepair.desktop"
install -m 644 assets/icon/tiepair.png "$APPDIR/tiepair.png"
ln -s tiepair.png "$APPDIR/.DirIcon"
desktop-file-validate "$APPDIR/tiepair.desktop"

# 3. pack it
mkdir -p dist
ARCH=x86_64 appimagetool "$APPDIR" "$OUT"

echo; echo "bundled libraries: $(ls -1 "$LIBDIR" | wc -l), $(du -sh "$LIBDIR" | cut -f1)"
echo "glibc floor: $(objdump -T "$APPDIR/usr/bin/tiepair" "$LIBDIR"/*.so* "$PLUGDIR"/*/*.so 2>/dev/null \
  | grep -oE 'GLIBC_[0-9.]+' | sort -uV | tail -1)"
[ -n "${HOST_UID:-}" ] && chown -R "$HOST_UID:${HOST_GID:-$HOST_UID}" /src/dist /src/build/appimage || true
echo "built $OUT"
