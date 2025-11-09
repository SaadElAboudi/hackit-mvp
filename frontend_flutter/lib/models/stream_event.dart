import 'base_search_result.dart';

class StreamEvent {
  final String type; // meta | partial | final | done | error
  final Map<String, dynamic> raw;
  final Citation? citation; // for potential future streaming per-citation
  final List<Citation> citations;
  final List<Chapter> chapters;
  const StreamEvent({
    required this.type,
    required this.raw,
    this.citation,
    this.citations = const [],
    this.chapters = const [],
  });

  factory StreamEvent.fromJson(Map<String, dynamic> json) {
    final type = (json['type'] ?? 'data').toString();
    final citations = (json['citations'] as List<dynamic>? ?? [])
        .map((e) => Citation.fromMap(e as Map<String, dynamic>))
        .toList();
    final chapters = (json['chapters'] as List<dynamic>? ?? [])
        .map((e) => Chapter.fromMap(e as Map<String, dynamic>))
        .toList();
    return StreamEvent(
      type: type,
      raw: json,
      citations: citations,
      chapters: chapters,
    );
  }

  String? get title => raw['title'] as String?;
  String? get videoUrl => raw['videoUrl'] as String?;
  String? get source => raw['source'] as String?;
  String? get step => raw['step'] as String?;
  String? get message => raw['message'] as String?;
}
