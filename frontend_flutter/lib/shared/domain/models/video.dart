import 'package:freezed_annotation/freezed_annotation.dart';

part 'video.freezed.dart';
part 'video.g.dart';

@freezed
class Video with _$Video {
  const factory Video({
    required String id,
    required String title,
    required String description,
    required String thumbnailUrl,
    required String videoUrl,
    required String channelTitle,
    DateTime? publishedAt,
    int? viewCount,
    int? likeCount,
    @Default(false) bool isFavorite,
    Map<String, dynamic>? additionalInfo,
  }) = _Video;

  factory Video.fromJson(Map<String, dynamic> json) => _$VideoFromJson(json);
}

@freezed
class SearchResult with _$SearchResult {
  const factory SearchResult({
    required String query,
    required List<Video> videos,
    required List<String> steps,
    String? summary,
    String? nextPageToken,
    String? prevPageToken,
    @Default(0) int totalResults,
    @Default(10) int resultsPerPage,
    @Default({}) Map<String, dynamic> metadata,
  }) = _SearchResult;

  factory SearchResult.fromJson(Map<String, dynamic> json) =>
      _$SearchResultFromJson(json);
}