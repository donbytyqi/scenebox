# Android torrent native layer

The Android torrent engine is intentionally split into two layers:

1. JNI adapter (`torrent_engine_jni.cpp`) — owns the Java/native boundary.
2. libtorrent session — supplied by an Android NDK build of libtorrent.

The iOS XCFramework shipped with SceneBox cannot be linked into an Android APK. The Android build must therefore provide libtorrent for each supported ABI and expose it to this target through CMake.

## Supported target ABIs

- arm64-v8a
- armeabi-v7a
- x86_64

## Integration contract

The native adapter must eventually expose metadata, torrent files, piece availability, piece deadlines/priorities, statistics, resume data, pause/resume and stop. Until the Android libtorrent dependency is linked, the JNI bootstrap deliberately does not claim torrent playback is functional.
