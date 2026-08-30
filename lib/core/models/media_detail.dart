import 'episode.dart';
import 'media_type.dart';

class MediaDetail {
  MediaDetail({
    required this.id,
    required this.type,
    required this.name,
    this.year,
    this.posterUrl,
    this.backdropUrl,
    this.logoUrl,
    this.description,
    this.cast = const [],
    this.directors = const [],
    this.writers = const [],
    this.genres = const [],
    this.imdbRating,
    this.runtime,
    this.released,
    this.country,
    this.awards,
    this.episodes = const [],
    this.moviedbId,
    this.trailerYouTubeIds = const [],
  });

  final String id;
  final MediaType type;
  final String name;
  final String? year;
  final Uri? posterUrl;
  final Uri? backdropUrl;
  final Uri? logoUrl;
  final String? description;
  final List<String> cast;
  final List<String> directors;
  final List<String> writers;
  final List<String> genres;
  final double? imdbRating;
  final String? runtime;
  final DateTime? released;
  final String? country;
  final String? awards;
  final List<Episode> episodes;
  final int? moviedbId;
  final List<String> trailerYouTubeIds;

  Uri? get trailerUrl => trailerYouTubeIds.isEmpty
      ? null
      : Uri.parse('https://www.youtube.com/watch?v=${trailerYouTubeIds.first}');

  List<int> get seasons => {
        for (final episode in episodes)
          if (episode.season > 0) episode.season,
      }.toList()
        ..sort();

  List<Episode> episodesInSeason(int season) => episodes
      .where((episode) => episode.season == season)
      .toList()
    ..sort((a, b) => a.episode.compareTo(b.episode));

  String get summaryLine => [
        year,
        runtime,
        if (genres.isNotEmpty) genres.take(3).join(', '),
      ].whereType<String>().where((value) => value.isNotEmpty).join('  ·  ');
}
