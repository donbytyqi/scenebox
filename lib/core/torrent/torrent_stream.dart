import '../models/media_type.dart';

class TorrentStream {
  const TorrentStream({
    required this.id,
    required this.title,
    required this.displayName,
    required this.infoHash,
    this.fileIndex,
    this.trackers = const [],
    this.seeders,
    this.sizeText,
    this.resolution,
    this.url,
  });

  final String id;
  final String title;
  final String displayName;
  final String infoHash;
  final int? fileIndex;
  final List<String> trackers;
  final int? seeders;
  final String? sizeText;
  final String? resolution;
  final Uri? url;

  bool get isDebrid => url != null;

  String get magnet {
    final params = <String>['xt=urn:btih:$infoHash'];
    if (displayName.isNotEmpty) {
      params.add('dn=${Uri.encodeComponent(displayName)}');
    }
    params.addAll(trackers.map((tracker) => 'tr=${Uri.encodeComponent(tracker)}'));
    return 'magnet:?${params.join('&')}';
  }
}
