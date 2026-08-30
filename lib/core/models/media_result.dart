import 'media_type.dart';

class MediaResult {
  const MediaResult({
    required this.id,
    required this.type,
    required this.name,
    this.year,
    this.posterUrl,
    this.description,
  });

  final String id;
  final MediaType type;
  final String name;
  final String? year;
  final Uri? posterUrl;
  final String? description;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is MediaResult && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
