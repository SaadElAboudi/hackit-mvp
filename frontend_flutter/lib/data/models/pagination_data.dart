import 'package:hive/hive.dart';
import 'package:json_annotation/json_annotation.dart';

part 'pagination_data.g.dart';

@HiveType(typeId: 2)
@JsonSerializable()
class PaginationData extends HiveObject {
  @HiveField(0)
  final String nextPageToken;

  @HiveField(1)
  final int totalResults;

  @HiveField(2)
  final int currentPage;

  @HiveField(3)
  final DateTime timestamp;

  PaginationData({
    required this.nextPageToken,
    required this.totalResults,
    required this.currentPage,
    required this.timestamp,
  });

  factory PaginationData.fromJson(Map<String, dynamic> json) => 
    _$PaginationDataFromJson(json);

  Map<String, dynamic> toJson() => _$PaginationDataToJson(this);

  PaginationData copyWith({
    String? nextPageToken,
    int? totalResults,
    int? currentPage,
    DateTime? timestamp,
  }) {
    return PaginationData(
      nextPageToken: nextPageToken ?? this.nextPageToken,
      totalResults: totalResults ?? this.totalResults,
      currentPage: currentPage ?? this.currentPage,
      timestamp: timestamp ?? this.timestamp,
    );
  }
}