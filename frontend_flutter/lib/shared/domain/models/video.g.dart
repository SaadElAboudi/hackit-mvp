// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'video.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$VideoImpl _$$VideoImplFromJson(Map<String, dynamic> json) => _$VideoImpl(
      id: json['id'] as String,
      title: json['title'] as String,
      description: json['description'] as String,
      thumbnailUrl: json['thumbnailUrl'] as String,
      videoUrl: json['videoUrl'] as String,
      channelTitle: json['channelTitle'] as String,
      publishedAt: json['publishedAt'] == null
          ? null
          : DateTime.parse(json['publishedAt'] as String),
      viewCount: (json['viewCount'] as num?)?.toInt(),
      likeCount: (json['likeCount'] as num?)?.toInt(),
      isFavorite: json['isFavorite'] as bool? ?? false,
      additionalInfo: json['additionalInfo'] as Map<String, dynamic>?,
    );

Map<String, dynamic> _$$VideoImplToJson(_$VideoImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'title': instance.title,
      'description': instance.description,
      'thumbnailUrl': instance.thumbnailUrl,
      'videoUrl': instance.videoUrl,
      'channelTitle': instance.channelTitle,
      'publishedAt': instance.publishedAt?.toIso8601String(),
      'viewCount': instance.viewCount,
      'likeCount': instance.likeCount,
      'isFavorite': instance.isFavorite,
      'additionalInfo': instance.additionalInfo,
    };

_$SearchResultImpl _$$SearchResultImplFromJson(Map<String, dynamic> json) =>
    _$SearchResultImpl(
      query: json['query'] as String,
      videos: (json['videos'] as List<dynamic>)
          .map((e) => Video.fromJson(e as Map<String, dynamic>))
          .toList(),
      steps: (json['steps'] as List<dynamic>).map((e) => e as String).toList(),
      summary: json['summary'] as String?,
      nextPageToken: json['nextPageToken'] as String?,
      prevPageToken: json['prevPageToken'] as String?,
      totalResults: (json['totalResults'] as num?)?.toInt() ?? 0,
      resultsPerPage: (json['resultsPerPage'] as num?)?.toInt() ?? 10,
      metadata: json['metadata'] as Map<String, dynamic>? ?? const {},
    );

Map<String, dynamic> _$$SearchResultImplToJson(_$SearchResultImpl instance) =>
    <String, dynamic>{
      'query': instance.query,
      'videos': instance.videos,
      'steps': instance.steps,
      'summary': instance.summary,
      'nextPageToken': instance.nextPageToken,
      'prevPageToken': instance.prevPageToken,
      'totalResults': instance.totalResults,
      'resultsPerPage': instance.resultsPerPage,
      'metadata': instance.metadata,
    };
