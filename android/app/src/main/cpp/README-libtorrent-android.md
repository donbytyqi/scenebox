# Android libtorrent dependency

The SceneBox Android port uses libtorrent through the Android NDK/CMake toolchain.

## Build contract

Provide a libtorrent build for each ABI under:

```text
$SCENEBOX_LIBTORRENT_ROOT/
  include/
  lib/arm64-v8a/libtorrent-rasterbar.a
  lib/armeabi-v7a/libtorrent-rasterbar.a
  lib/x86_64/libtorrent-rasterbar.a
```

Build libtorrent with C++17 and keep the compile definitions consistent between
libtorrent and SceneBox. The upstream project explicitly warns that mismatched
TORRENT_* / BOOST_* configuration macros can make headers and binaries
incompatible.

For a release Android build, arm64-v8a should be the first target. Additional
ABIs can be enabled after the arm64 build is verified.

The upstream CMake build supports Android and requires C++17. See:
https://libtorrent.org/building.html
