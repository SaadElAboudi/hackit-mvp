class StreamEvent {
  final String type; // meta | partial | done | error
  final Map<String, dynamic> data;
  const StreamEvent(this.type, this.data);

  factory StreamEvent.fromJson(Map<String, dynamic> json) {
    final type = (json['type'] ?? 'data').toString();
    return StreamEvent(type, json);
  }

  String? get title => data['title'] as String?;
  String? get videoUrl => data['videoUrl'] as String?;
  String? get source => data['source'] as String?;
  String? get step => data['step'] as String?;
  String? get message => data['message'] as String?;
}
