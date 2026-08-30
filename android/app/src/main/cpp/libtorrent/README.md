# Android libtorrent integration

This directory is reserved for the Android build of libtorrent and its JNI adapter.

SceneBox's existing native artifact is an Apple/iOS XCFramework and cannot be linked into an Android APK. Android must build libtorrent with the Android NDK/CMake toolchain.

Recommended target ABIs for the first Android release:

- arm64-v8a
- x86_64 (emulator/testing)

The libtorrent build must use C++17 or newer and must keep its TORRENT/Boost configuration consistent between the library and JNI consumer. The upstream project documents CMake-based builds and cross-compilation requirements.

Do not commit generated `.so` files or downloaded third-party source here. Use a reproducible build step (Gradle/CMake or CI) to obtain the native dependency.
