import '../torrent/magnet_link.dart';
import '../torrent/torrent_stream.dart';

enum StreamResolutionStatus { idle, resolving, ready, failed }

class ResolvedStream {
  const ResolvedStream({
    required this.url,
    this.isLocalTorrent = false,
    this.magnet,
    this.fileIndex,
  });

  final Uri url;
  final bool isLocalTorrent;
  final MagnetLink? magnet;
  final int? fileIndex;
}

/// Platform-neutral playback coordinator.
///
/// The actual torrent engine and local HTTP server are intentionally supplied
/// by the Android platform implementation. Flutter only coordinates stream
/// resolution and player state.
class StreamCoordinator {
  StreamResolutionStatus _status = StreamResolutionStatus.idle;
  StreamResolutionStatus get status => _status;

  Future<ResolvedStream> resolve(TorrentStream stream) async {
    _status = StreamResolutionStatus.resolving;

    try {
      if (stream.url != null) {
        final resolved = ResolvedStream(url: stream.url!);
        _status = StreamResolutionStatus.ready;
        return resolved;
      }

      final magnet = MagnetLink(
        infoHash: stream.infoHash,
        displayName: stream.displayName,
        trackers: stream.trackers,
      );

      // Native Android TorrentEngine will consume this magnet and expose a
      // local HTTP URL once the selected file is streamable.
      throw UnimplementedError(
        'Android TorrentEngine bridge is required for torrent streams: ${magnet.value}',
      );
    } catch (_) {
      _status = StreamResolutionStatus.failed;
      rethrow;
    }
  }

  void reset() => _status = StreamResolutionStatus.idle;
}
