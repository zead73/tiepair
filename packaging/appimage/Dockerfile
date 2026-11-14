# Build environment for the Tiepair AppImage: Debian 12 (glibc 2.36), so the result runs on
# Debian 12 / Ubuntu 22.04 and anything newer. The program is the Lazarus (Qt5) desktop build; fpc
# and Lazarus come from the distribution, and so do Qt5 and libQt5Pas, which the build script bundles.
FROM debian:12

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
         fpc fpc-source lazarus-ide-qt5 lcl-qt5 lcl-units lcl-utils libqt5pas-dev libqt5pas1 \
         binutils build-essential curl ca-certificates file patchelf desktop-file-utils \
    && rm -rf /var/lib/apt/lists/*

# appimagetool 1.9.1 (static ELF, so no FUSE is needed to package), checked against the
# digest GitHub publishes for that release asset
ARG APPIMAGETOOL_SHA=ed4ce84f0d9caff66f50bcca6ff6f35aae54ce8135408b3fa33abfc3cb384eb0
RUN curl -fL -o /usr/local/bin/appimagetool \
      https://github.com/AppImage/appimagetool/releases/download/1.9.1/appimagetool-x86_64.AppImage \
    && echo "$APPIMAGETOOL_SHA  /usr/local/bin/appimagetool" | sha256sum -c - \
    && chmod +x /usr/local/bin/appimagetool

# appimagetool is itself an AppImage and a container has no FUSE: self-extract and run
ENV APPIMAGE_EXTRACT_AND_RUN=1

WORKDIR /src
ENTRYPOINT ["packaging/appimage/build.sh"]
