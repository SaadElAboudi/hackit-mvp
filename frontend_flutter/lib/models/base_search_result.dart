class BaseSearchResult {
  final String title;
  final List<String> steps;
  final String videoUrl;
  final String source;
  final String? summary;
  final Map<String, dynamic> metadata;
  final List<Citation> citations;
  final List<Chapter> chapters;

  const BaseSearchResult({
    required this.title,
    required this.steps,
    required this.videoUrl,
    required this.source,
    this.summary,
    this.metadata = const {},
    this.citations = const [],
    this.chapters = const [],
  });

  factory BaseSearchResult.fromMap(Map<String, dynamic> map) {
    return BaseSearchResult(
      title: map['title'] as String? ?? '',
      steps:
          (map['steps'] as List<dynamic>?)?.map((e) => e.toString()).toList() ??
              [],
      videoUrl: map['videoUrl'] as String? ?? '',
      source: map['source'] as String? ?? '',
      summary: map['summary'] as String?,
      metadata: map['metadata'] as Map<String, dynamic>? ?? {},
      citations: (map['citations'] as List<dynamic>? ?? [])
          .map((e) => Citation.fromMap(e as Map<String, dynamic>))
          .toList(),
      chapters: (map['chapters'] as List<dynamic>? ?? [])
          .map((e) => Chapter.fromMap(e as Map<String, dynamic>))
          .toList(),
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
