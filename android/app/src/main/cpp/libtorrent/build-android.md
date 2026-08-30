# Building libtorrent for SceneBox Android

SceneBox keeps the third-party torrent library separate from the application source. Build a pinned libtorrent release with the Android NDK/CMake toolchain and expose an imported `libtorrent` target to `libtorrent/CMakeLists.txt`.

Required release ABI:

- `arm64-v8a`

Recommended test ABI:

- `x86_64`

The resulting native library must be built with the same C++ runtime configuration as the JNI module. Do not mix incompatible libc++ variants or compiler settings.

After the target is available, the parent CMake configuration should link:

```cmake
target_link_libraries(scenebox_torrent PRIVATE libtorrent)
```

The JNI adapter should then replace its bootstrap state with a real `libtorrent::session`, magnet metadata handling, torrent handle lifecycle, piece scheduling and streaming reader.

Do not commit generated `.so` files. Pin the upstream version and build it in CI or Gradle/CMake so releases are reproducible.
