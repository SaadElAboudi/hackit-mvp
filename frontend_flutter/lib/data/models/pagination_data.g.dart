// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'pagination_data.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

PaginationData _$PaginationDataFromJson(Map<String, dynamic> json) =>
    PaginationData(
      nextPageToken: json['nextPageToken'] as String,
      totalResults: (json['totalResults'] as num).toInt(),
      currentPage: (json['currentPage'] as num).toInt(),
      timestamp: DateTime.parse(json['timestamp'] as String),
    );

Map<String, dynamic> _$PaginationDataToJson(PaginationData instance) =>
    <String, dynamic>{
      'nextPageToken': instance.nextPageToken,
      'totalResults': instance.totalResults,
      'currentPage': instance.currentPage,
      'timestamp': instance.timestamp.toIso8601String(),
    };
