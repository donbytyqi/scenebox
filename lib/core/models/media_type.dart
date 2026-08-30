enum MediaType {
  movie,
  series,
  anime;

  String get value => switch (this) {
        MediaType.movie => 'movie',
        MediaType.series => 'series',
        MediaType.anime => 'anime',
      };

  String get browseTitle => switch (this) {
        MediaType.movie => 'Movies',
        MediaType.series => 'TV Shows',
        MediaType.anime => 'Anime',
      };

  static MediaType fromValue(String? value) => switch (value) {
        'series' => MediaType.series,
        'anime' => MediaType.anime,
        _ => MediaType.movie,
      };
}
