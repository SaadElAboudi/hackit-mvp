import 'package:hive/hive.dart';
import 'package:json_annotation/json_annotation.dart';

part 'search_result.g.dart';

@HiveType(typeId: 1)
@JsonSerializable()
class SearchResult extends HiveObject {
  @HiveField(0)
  final String query;

  @HiveField(1)
  final List<String> videoIds;

  @HiveField(2)
  final DateTime timestamp;

  SearchResult({
    required this.query,
    required this.videoIds,
    required this.timestamp,
  });

  factory SearchResult.fromJson(Map<String, dynamic> json) => 
    _$SearchResultFromJson(json);

  Map<String, dynamic> toJson() => _$SearchResultToJson(this);
}