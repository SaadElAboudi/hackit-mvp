import 'package:hive/hive.dart';
import 'package:json_annotation/json_annotation.dart';

part 'video_model.g.dart';

@HiveType(typeId: 0)
@JsonSerializable()
class VideoModel extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String title;

  @HiveField(2)
  final String description;

  @HiveField(3)
  final String thumbnailUrl;

  @HiveField(4)
  final String channelTitle;

  @HiveField(5)
  final DateTime publishedAt;

  VideoModel({
    required this.id,
    required this.title,
    required this.description,
    required this.thumbnailUrl,
    required this.channelTitle,
    required this.publishedAt,
  });

  factory VideoModel.fromJson(Map<String, dynamic> json) => 
    _$VideoModelFromJson(json);

  Map<String, dynamic> toJson() => _$VideoModelToJson(this);
}