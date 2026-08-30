class Episode {
  const Episode({
    required this.id,
    required this.season,
    required this.episode,
    required this.name,
    this.overview,
    this.thumbnailUrl,
    this.released,
  });

  final String id;
  final int season;
  final int episode;
  final String name;
  final String? overview;
  final Uri? thumbnailUrl;
  final DateTime? released;

  String get label => 'S${season}E$episode';
}
