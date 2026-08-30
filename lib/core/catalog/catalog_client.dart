import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/catalog_feed.dart';
import '../models/episode.dart';
import '../models/media_detail.dart';
import '../models/media_result.dart';
import '../models/media_type.dart';

class CatalogException implements Exception {
  const CatalogException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Cinemeta/Kitsu catalog implementation ported from SceneBox's MediaCatalog.
class CatalogClient {
  CatalogClient({http.Client? client}) : _client = client ?? http.Client();

  static const cinemetaBase = 'https://v3-cinemeta.strem.io';
  static const kitsuBase = 'https://anime-kitsu.strem.fun';
  final http.Client _client;

  Future<List<MediaResult>> catalog({
    required MediaType type,
    CatalogFeed feed = CatalogFeed.popular,
    String? genre,
    int skip = 0,
  }) async {
    final anime = type == MediaType.anime;
    final base = anime ? kitsuBase : cinemetaBase;
    final catalog = anime ? feed.kitsuCatalog : feed.value;
    var path = 'catalog/${anime ? 'anime' : type.value}/$catalog';
    final extras = <String>[];
    if (genre != null && genre.isNotEmpty) {
      extras.add('genre=${Uri.encodeComponent(genre)}');
    }
    if (skip > 0) extras.add('skip=$skip');
    if (extras.isNotEmpty) path += '/${extras.join('&')}';

    final uri = Uri.parse('$base/$path.json');
    final json = await _getJson(uri);
    final metas = json['metas'];
    if (metas is! List) return const [];

    return metas.whereType<Map>().map((meta) {
      return _parseResult(
        Map<String, dynamic>.from(meta),
        anime ? MediaType.series : type,
      );
    }).whereType<MediaResult>().toList();
  }

  Future<MediaDetail> detail({
    required String id,
    required MediaType type,
  }) async {
    final kitsu = id.startsWith('kitsu:');
    final base = kitsu ? kitsuBase : cinemetaBase;
    final typePath = kitsu ? 'anime' : type.value;
    final uri = Uri.parse(
      '$base/meta/$typePath/${Uri.encodeComponent(id)}.json',
    );
    final json = await _getJson(uri);
    final raw = json['meta'];
    if (raw is! Map) throw CatalogException('No metadata for $id.');
    return _parseDetail(Map<String, dynamic>.from(raw), type);
  }

  Future<Map<String, dynamic>> _getJson(Uri uri) async {
    final response = await _client.get(uri, headers: {
      'User-Agent': 'SceneBox-Android/1.0',
      'Accept': 'application/json',
    });
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw CatalogException('Catalog request failed (${response.statusCode}).');
    }
    if (response.body.isEmpty) throw const CatalogException('Empty catalog response.');
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) throw const CatalogException('Catalog returned invalid JSON.');
    return Map<String, dynamic>.from(decoded);
  }

  MediaResult? _parseResult(Map<String, dynamic> meta, MediaType fallback) {
    final id = meta['id'];
    final name = meta['name'];
    if (id is! String || name is! String) return null;
    final rawType = meta['type'];
    return MediaResult(
      id: id,
      type: MediaType.fromValue(rawType is String ? rawType : null),
      name: name,
      year: meta['releaseInfo']?.toString() ?? _stringValue(meta['year']),
      posterUrl: _uri(meta['poster']),
      description: meta['description']?.toString(),
    );
  }

  MediaDetail _parseDetail(Map<String, dynamic> meta, MediaType fallback) {
    final type = MediaType.fromValue(meta['type'] is String ? meta['type'] as String : fallback.value);
    final videos = meta['videos'] is List ? meta['videos'] as List : const [];
    return MediaDetail(
      id: meta['id']?.toString() ?? meta['imdb_id']?.toString() ?? '',
      type: type,
      name: meta['name']?.toString() ?? 'Untitled',
      year: meta['releaseInfo']?.toString() ?? _stringValue(meta['year']),
      posterUrl: _uri(meta['poster']),
      backdropUrl: _uri(meta['background']),
      logoUrl: _uri(meta['logo']),
      description: meta['description']?.toString(),
      cast: _stringList(meta['cast']),
      directors: _stringList(meta['director']),
      writers: _stringList(meta['writer']),
      genres: _stringList(meta['genres'] ?? meta['genre']),
      imdbRating: _doubleValue(meta['imdbRating']),
      runtime: meta['runtime']?.toString(),
      released: _date(meta['released']),
      country: meta['country']?.toString(),
      awards: meta['awards']?.toString(),
      episodes: videos.whereType<Map>().map((v) => _episode(Map<String, dynamic>.from(v))).whereType<Episode>().toList(),
      moviedbId: _intValue(meta['moviedb_id']),
      trailerYouTubeIds: _trailerIds(meta['trailers']),
    );
  }

  Episode? _episode(Map<String, dynamic> video) {
    final id = video['id'];
    final number = _intValue(video['episode']) ?? _intValue(video['number']);
    if (id is! String || number == null) return null;
    return Episode(
      id: id,
      season: _intValue(video['season']) ?? 0,
      episode: number,
      name: video['name']?.toString() ?? 'Episode $number',
      overview: (video['overview'] ?? video['description'])?.toString(),
      thumbnailUrl: _uri(video['thumbnail']),
      released: _date(video['released'] ?? video['firstAired']),
    );
  }

  List<String> _trailerIds(dynamic value) {
    if (value is! List) return const [];
    final trailers = <String>[];
    final others = <String>[];
    for (final entry in value.whereType<Map>()) {
      final source = entry['source'];
      if (source is! String || source.isEmpty) continue;
      if (entry['type']?.toString().toLowerCase() == 'trailer') {
        trailers.add(source);
      } else {
        others.add(source);
      }
    }
    return [...trailers, ...others];
  }

  static Uri? _uri(dynamic value) {
    if (value is! String || value.isEmpty) return null;
    return Uri.tryParse(value);
  }

  static String? _stringValue(dynamic value) => value == null ? null : value.toString();
  static int? _intValue(dynamic value) => value is int ? value : int.tryParse(value?.toString() ?? '');
  static double? _doubleValue(dynamic value) => value is num ? value.toDouble() : double.tryParse(value?.toString() ?? '');
  static DateTime? _date(dynamic value) => value is String ? DateTime.tryParse(value) : null;

  static List<String> _stringList(dynamic value) {
    if (value is List) return value.whereType<String>().toList();
    if (value is String) return [value];
    return const [];
  }
}
