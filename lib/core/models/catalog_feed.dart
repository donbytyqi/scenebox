enum CatalogFeed {
  popular('top', 'Popular', 'flame', 'kitsu-anime-popular'),
  newRelease('year', 'New', 'sparkles', 'kitsu-anime-airing'),
  featured('imdbRating', 'Featured', 'star', 'kitsu-anime-rating');

  const CatalogFeed(this.value, this.title, this.systemIcon, this.kitsuCatalog);

  final String value;
  final String title;
  final String systemIcon;
  final String kitsuCatalog;
}
