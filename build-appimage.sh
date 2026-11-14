#!/bin/sh
# Builds the Linux AppImage dist/tiepair-<version>-x86_64.AppImage. The program is compiled and packed in a
# Debian 12 container (packaging/appimage/Dockerfile), so that it runs on Debian 12 / Ubuntu 22.04 and newer.
# Needs docker; the first run builds the image (a few minutes and ~1 GB of downloads).
set -e
cd "$(dirname "$0")"
tools/check-version.sh
./make-resources.sh >/dev/null
docker build -q -t tiepair-appimage packaging/appimage >/dev/null
docker run --rm -v "$PWD":/src -e HOST_UID="$(id -u)" -e HOST_GID="$(id -g)" tiepair-appimage
