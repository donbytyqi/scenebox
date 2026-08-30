#!/usr/bin/env bash
set -euo pipefail

# Reproducible build entry point for Android libtorrent.
# Pin the source ref before publishing a release; do not build from a moving
# branch in production CI.

: "${ANDROID_NDK_HOME:?Set ANDROID_NDK_HOME}"
: "${ANDROID_ABI:=arm64-v8a}"
: "${LIBTORRENT_REF:=v2.0.13}"
: "${LIBTORRENT_SRC:=third_party/libtorrent}"
: "${PREFIX:=$PWD/prebuilt/$ANDROID_ABI}"

if [[ ! -d "$LIBTORRENT_SRC/.git" ]]; then
  git clone --recurse-submodules https://github.com/arvidn/libtorrent.git "$LIBTORRENT_SRC"
fi

git -C "$LIBTORRENT_SRC" fetch --tags --quiet
git -C "$LIBTORRENT_SRC" checkout --detach "$LIBTORRENT_REF"
git -C "$LIBTORRENT_SRC" submodule update --init --recursive

cmake -S "$LIBTORRENT_SRC" -B build-libtorrent-android \
  -DCMAKE_TOOLCHAIN_FILE="$ANDROID_NDK_HOME/build/cmake/android.toolchain.cmake" \
  -DANDROID_ABI="$ANDROID_ABI" \
  -DANDROID_PLATFORM=android-23 \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
  -DBUILD_SHARED_LIBS=OFF \
  -Dbuild_tests=OFF \
  -Dbuild_examples=OFF \
  -Dbuild_tools=OFF \
  -Dpython-bindings=OFF \
  -Dwebtorrent=OFF \
  -DCMAKE_INSTALL_PREFIX="$PREFIX"

cmake --build build-libtorrent-android --config Release --parallel
cmake --install build-libtorrent-android --config Release

echo "libtorrent Android build installed at: $PREFIX"
