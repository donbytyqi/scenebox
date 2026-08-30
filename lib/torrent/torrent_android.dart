import 'package:flutter/services.dart';

/// Flutter API for the Android torrent engine.
class TorrentAndroid {
  static const MethodChannel _channel = MethodChannel('scenebox/torrent');

  static Future<void> start(String magnet) async {
    await _channel.invokeMethod('torrent.start', {'magnet': magnet});
  }

  static Future<void> stop() async {
    await _channel.invokeMethod('torrent.stop');
  }

  static Future<Map<Object?, Object?>?> status() async {
    return _channel.invokeMapMethod<Object?, Object?>('torrent.status');
  }

  static Future<String> streamUrl({
    required int fileIndex,
    required String path,
    required int offset,
    required int length,
  }) async {
    final url = await _channel.invokeMethod<String>('torrent.streamUrl', {
      'fileIndex': fileIndex,
      'path': path,
      'offset': offset,
      'length': length,
    });
    if (url == null || url.isEmpty) {
      throw PlatformException(
        code: 'STREAM_URL_UNAVAILABLE',
        message: 'Android torrent server did not provide a stream URL',
      );
    }
    return url;
  }
}
