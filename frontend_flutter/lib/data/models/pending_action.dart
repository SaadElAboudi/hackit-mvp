import 'package:hive/hive.dart';

@HiveType(typeId: 3)
enum ActionType {
  @HiveField(0)
  search,
  @HiveField(1)
  addToFavorites,
  @HiveField(2)
  removeFromFavorites,
}

@HiveType(typeId: 4)
class PendingAction extends HiveObject {
  @HiveField(0)
  final ActionType type;

  @HiveField(1)
  final Map<String, dynamic> data;

  @HiveField(2)
  final DateTime timestamp;

  PendingAction({
    required this.type,
    required this.data,
    required this.timestamp,
  });
}