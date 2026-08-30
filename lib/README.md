# SceneBox Flutter Android Port

This directory is the beginning of the Flutter/Dart Android implementation of SceneBox.

The original Swift/SwiftUI implementation remains untouched under `WatchBox/`.

## Porting architecture

- `lib/core/` — shared domain, networking, catalog, playback and torrent abstractions.
- `lib/features/` — Flutter UI and feature state.
- `android/` — Android-native Media3 and libtorrent/JNI integration.

Native torrent and playback code is intentionally kept out of Dart where Android-native APIs provide better lifecycle, performance and background-execution behavior.
