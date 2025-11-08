class BaseSearchResult {
  final String title;
  final List<String> steps;
  final String videoUrl;
  final String source;
  final String? summary;
  final Map<String, dynamic> metadata;

  const BaseSearchResult({
    required this.title,
    required this.steps,
    required this.videoUrl,
    required this.source,
    this.summary,
    this.metadata = const {},
  });

  factory BaseSearchResult.fromMap(Map<String, dynamic> map) {
    return BaseSearchResult(
      title: map['title'] as String? ?? '',
      steps: (map['steps'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      videoUrl: map['videoUrl'] as String? ?? '',
      source: map['source'] as String? ?? '',
      summary: map['summary'] as String?,
      metadata: map['metadata'] as Map<String, dynamic>? ?? {},
    );
  }

  Map<String, dynamic> toMap() => {
    'title': title,
    'steps': steps,
    'videoUrl': videoUrl,
    'source': source,
    'summary': summary,
    'metadata': metadata,
  };
}