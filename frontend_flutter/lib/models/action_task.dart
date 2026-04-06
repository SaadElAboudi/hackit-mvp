import 'dart:convert';

enum TaskPriority { p0, p1, p2 }

class ActionTask {
  final String id;
  final String title;
  final String? owner;
  final TaskPriority priority;
  final String? dueDate;
  bool done;

  ActionTask({
    required this.id,
    required this.title,
    this.owner,
    this.priority = TaskPriority.p1,
    this.dueDate,
    this.done = false,
  });

  String get priorityLabel {
    switch (priority) {
      case TaskPriority.p0:
        return 'P0';
      case TaskPriority.p1:
        return 'P1';
      case TaskPriority.p2:
        return 'P2';
    }
  }

  ActionTask copyWith({bool? done, String? owner, TaskPriority? priority, String? dueDate}) =>
      ActionTask(
        id: id,
        title: title,
        owner: owner ?? this.owner,
        priority: priority ?? this.priority,
        dueDate: dueDate ?? this.dueDate,
        done: done ?? this.done,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'owner': owner,
        'priority': priority.name,
        'dueDate': dueDate,
        'done': done,
      };

  factory ActionTask.fromJson(Map<String, dynamic> json) => ActionTask(
        id: json['id'] as String,
        title: json['title'] as String,
        owner: json['owner'] as String?,
        priority: TaskPriority.values.firstWhere(
          (p) => p.name == json['priority'],
          orElse: () => TaskPriority.p1,
        ),
        dueDate: json['dueDate'] as String?,
        done: json['done'] as bool? ?? false,
      );

  static String encodeList(List<ActionTask> tasks) =>
      jsonEncode(tasks.map((t) => t.toJson()).toList());

  static List<ActionTask> decodeList(String s) {
    try {
      final raw = jsonDecode(s);
      if (raw is! List) return [];
      return raw
          .whereType<Map>()
          .map((e) => ActionTask.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Infer priority from text markers like 🔴/P0/urgent or green/P2/nice.
  static TaskPriority inferPriority(String text) {
    final t = text.toLowerCase();
    if (t.contains('p0') ||
        t.contains('🔴') ||
        t.contains('urgent') ||
        t.contains('bloquant') ||
        t.contains('critique')) { return TaskPriority.p0; }
    if (t.contains('p2') ||
        t.contains('🟢') ||
        t.contains('nice') ||
        t.contains('optionnel')) { return TaskPriority.p2; }
    return TaskPriority.p1;
  }
}
