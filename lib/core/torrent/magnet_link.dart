class MagnetLink {
  const MagnetLink({
    required this.infoHash,
    this.displayName,
    this.trackers = const [],
  });

  final String infoHash;
  final String? displayName;
  final List<String> trackers;

  Uri get uri => Uri(
        scheme: 'magnet',
        queryParameters: {
          'xt': 'urn:btih:$infoHash',
          if (displayName != null && displayName!.isNotEmpty) 'dn': displayName!,
          for (var i = 0; i < trackers.length; i++) 'tr$i': trackers[i],
        },
      );

  String get value => uri.toString();

  static MagnetLink? parse(String input) {
    final uri = Uri.tryParse(input.trim());
    if (uri == null || uri.scheme.toLowerCase() != 'magnet') return null;

    final xt = uri.queryParameters['xt'];
    if (xt == null) return null;

    const prefix = 'urn:btih:';
    final index = xt.toLowerCase().indexOf(prefix);
    if (index < 0) return null;

    final hash = xt.substring(index + prefix.length).trim();
    if (hash.isEmpty) return null;

    final trackers = uri.queryParametersAll['tr'];
    return MagnetLink(
      infoHash: hash,
      displayName: uri.queryParameters['dn'],
      trackers: List.unmodifiable(trackers),
    );
  }
}
