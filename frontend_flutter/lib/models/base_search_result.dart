class BaseSearchResult {
  final String title;
  final List<String> steps;
  final String videoUrl;
  final String source;
  final String? summary;
  final Map<String, dynamic> metadata;
  final List<Citation> citations;
  final List<Chapter> chapters;
  final List<String> keyTakeaways;
  final List<Map<String, dynamic>> quiz;

  const BaseSearchResult({
    required this.title,
    required this.steps,
    required this.videoUrl,
    required this.source,
    this.summary,
    this.metadata = const {},
    this.citations = const [],
    this.chapters = const [],
    this.keyTakeaways = const [],
    this.quiz = const [],
  });

  factory BaseSearchResult.fromMap(Map<String, dynamic> map) {
    final rawMetadata = map['metadata'];
    final metadata = rawMetadata is Map<String, dynamic>
      ? rawMetadata
      : (rawMetadata is Map ? Map<String, dynamic>.from(rawMetadata) : <String, dynamic>{});

    final rawCitations = map['citations'];
    final citations = rawCitations is List
      ? rawCitations
        .whereType<Map>()
        .map((e) => Citation.fromMap(Map<String, dynamic>.from(e)))
        .toList()
      : <Citation>[];

    final rawChapters = map['chapters'];
    final chapters = rawChapters is List
      ? rawChapters
        .whereType<Map>()
        .map((e) => Chapter.fromMap(Map<String, dynamic>.from(e)))
        .toList()
      : <Chapter>[];

    final rawQuiz = map['quiz'];
    final quiz = rawQuiz is List
      ? rawQuiz.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
      : <Map<String, dynamic>>[];

    return BaseSearchResult(
      title: map['title'] as String? ?? '',
      steps: (map['steps'] is List)
        ? (map['steps'] as List).map((e) => e.toString()).toList()
        : const [],
      videoUrl: map['videoUrl'] as String? ?? '',
      source: map['source'] as String? ?? '',
      summary: map['summary'] as String?,
      metadata: metadata,
      citations: citations,
      chapters: chapters,
      keyTakeaways: (map['keyTakeaways'] is List)
        ? (map['keyTakeaways'] as List).map((e) => e.toString()).toList()
        : const [],
      quiz: quiz,
    );
  }

  Map<String, dynamic> toMap() => {
        'title': title,
        'steps': steps,
        'videoUrl': videoUrl,
        'source': source,
        'summary': summary,
        'metadata': metadata,
        'citations': citations.map((c) => c.toMap()).toList(),
        'chapters': chapters.map((c) => c.toMap()).toList(),
        'keyTakeaways': keyTakeaways,
        'quiz': quiz,
      };
}

class Citation {
  final String url;
  final int startSec;
  final int endSec;
  final String quote;
  const Citation(
      {required this.url,
      required this.startSec,
      required this.endSec,
      required this.quote});
  factory Citation.fromMap(Map<String, dynamic> map) => Citation(
        url: map['url'] as String? ?? '',
        startSec: (map['startSec'] as num?)?.toInt() ?? 0,
        endSec: (map['endSec'] as num?)?.toInt() ?? 0,
        quote: map['quote'] as String? ?? '',
      );
  Map<String, dynamic> toMap() => {
        'url': url,
        'startSec': startSec,
        'endSec': endSec,
        'quote': quote,
      };
}

class Chapter {
  final int index;
  final int startSec;
  final String title;
  const Chapter(
      {required this.index, required this.startSec, required this.title});
  factory Chapter.fromMap(Map<String, dynamic> map) => Chapter(
        index: (map['index'] as num?)?.toInt() ?? 0,
        startSec: (map['startSec'] as num?)?.toInt() ?? 0,
        title: map['title'] as String? ?? '',
      );
  Map<String, dynamic> toMap() => {
        'index': index,
        'startSec': startSec,
        'title': title,
      };
}
