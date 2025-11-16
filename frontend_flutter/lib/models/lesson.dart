class Lesson {
  final String id;
  final String userId;
  final String title;
  final String summary;
  final List<String> steps;
  final String videoUrl;
  final bool favorite;
  final int views;
  final DateTime? lastViewedAt;
  final DateTime createdAt;
  final int progress;
  final String? reminder;
  final String? guestPrompt;

  Lesson({
    required this.id,
    required this.userId,
    required this.title,
    required this.summary,
    required this.steps,
    required this.videoUrl,
    required this.favorite,
    required this.views,
    required this.lastViewedAt,
    required this.createdAt,
    this.progress = 0,
    this.reminder,
    this.guestPrompt,
  });

  factory Lesson.fromMap(Map<String, dynamic> m, {String? userIdFallback}) {
    return Lesson(
      id: m['id'] as String,
      userId: (m['userId'] as String?) ?? userIdFallback ?? '',
      title: (m['title'] as String?) ?? '',
      summary: (m['summary'] as String?) ?? '',
      steps:
          (m['steps'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      videoUrl: (m['videoUrl'] as String?) ?? '',
      favorite: (m['favorite'] as bool?) ?? false,
      views: (m['views'] as int?) ?? 0,
      lastViewedAt: m['lastViewedAt'] != null
          ? DateTime.tryParse(m['lastViewedAt'] as String)
          : null,
      createdAt: DateTime.tryParse((m['createdAt'] as String?) ?? '') ??
          DateTime.now(),
      progress: (m['progress'] as int?) ?? 0,
      reminder: m['reminder'] as String?,
      guestPrompt: m['guestPrompt'] as String?,
    );
  }
}
