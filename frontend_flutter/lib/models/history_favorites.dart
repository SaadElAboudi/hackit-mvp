import 'dart:convert';

class SearchEntry {
  final String id; // unique id (timestamp-based)
  final String query;
  final String? title;
  final String? videoUrl;
  final String? source; // e.g., youtube
  final DateTime createdAt;
  final int? resultCount;
  final int? durationMs;

  SearchEntry({
    required this.id,
    required this.query,
    required this.createdAt,
    this.title,
    this.videoUrl,
    this.source,
    this.resultCount,
    this.durationMs,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'query': query,
        'title': title,
        'videoUrl': videoUrl,
        'source': source,
        'createdAt': createdAt.toIso8601String(),
        'resultCount': resultCount,
        'durationMs': durationMs,
      };

  factory SearchEntry.fromMap(Map<String, dynamic> map) => SearchEntry(
        id: map['id'] as String,
        query: map['query'] as String,
        title: map['title'] as String?,
        videoUrl: map['videoUrl'] as String?,
        source: map['source'] as String?,
        createdAt: DateTime.tryParse(map['createdAt'] as String? ?? '') ??
            DateTime.now(),
        resultCount: map['resultCount'] as int?,
        durationMs: map['durationMs'] as int?,
      );

  String toJson() => jsonEncode(toMap());
  static SearchEntry fromJson(String s) =>
      SearchEntry.fromMap(jsonDecode(s) as Map<String, dynamic>);
}

class FavoriteItem {
  final String id; // video key (prefer videoUrl or canonical id)
  final String title;
  final String? channel;
  final String? videoUrl;
  final DateTime addedAt;

  FavoriteItem({
    required this.id,
    required this.title,
    required this.addedAt,
    this.channel,
    this.videoUrl,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'channel': channel,
        'videoUrl': videoUrl,
        'addedAt': addedAt.toIso8601String(),
      };

  factory FavoriteItem.fromMap(Map<String, dynamic> map) => FavoriteItem(
        id: map['id'] as String,
        title: map['title'] as String? ?? '',
        channel: map['channel'] as String?,
        videoUrl: map['videoUrl'] as String?,
        addedAt: DateTime.tryParse(map['addedAt'] as String? ?? '') ??
            DateTime.now(),
      );

  String toJson() => jsonEncode(toMap());
  static FavoriteItem fromJson(String s) =>
      FavoriteItem.fromMap(jsonDecode(s) as Map<String, dynamic>);
}
