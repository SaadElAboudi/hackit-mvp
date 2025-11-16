import 'dart:convert';

enum ChatRole { user, assistant }

enum ChatKind { text, steps, video, citations, chapters, error }

class ChatMessage {
  Map<String, dynamic> toSqlMap() => {
        'id': id,
        'role': role.name,
        'kind': kind.name,
        'content': jsonEncode(content),
        'ts': ts.toIso8601String(),
      };

  static ChatMessage fromSqlMap(Map<String, dynamic> map) => ChatMessage(
        id: map['id'] as String,
        role: ChatRole.values.firstWhere((e) => e.name == map['role']),
        kind: ChatKind.values.firstWhere((e) => e.name == map['kind']),
        content: jsonDecode(map['content'] as String) as Map<String, dynamic>,
        ts: DateTime.parse(map['ts'] as String),
      );
  final String id;
  final ChatRole role;
  final ChatKind kind;
  final Map<String, dynamic> content;
  final DateTime ts;

  const ChatMessage({
    required this.id,
    required this.role,
    required this.kind,
    required this.content,
    required this.ts,
  });

  factory ChatMessage.userText(String id, String text) => ChatMessage(
        id: id,
        role: ChatRole.user,
        kind: ChatKind.text,
        content: {"text": text},
        ts: DateTime.now(),
      );

  factory ChatMessage.assistantText(String id, String text) => ChatMessage(
        id: id,
        role: ChatRole.assistant,
        kind: ChatKind.text,
        content: {"text": text},
        ts: DateTime.now(),
      );

  factory ChatMessage.assistantSteps(
          String id, String title, List<String> steps,
          {String? source}) =>
      ChatMessage(
        id: id,
        role: ChatRole.assistant,
        kind: ChatKind.steps,
        content: {
          "title": title,
          "steps": steps,
          if (source != null) "source": source,
        },
        ts: DateTime.now(),
      );

  factory ChatMessage.assistantVideo(String id, String title, String videoUrl,
          {String? source}) =>
      ChatMessage(
        id: id,
        role: ChatRole.assistant,
        kind: ChatKind.video,
        content: {
          "title": title,
          "videoUrl": videoUrl,
          if (source != null) "source": source,
        },
        ts: DateTime.now(),
      );

  factory ChatMessage.assistantCitations(
          String id, List<Map<String, dynamic>> citations) =>
      ChatMessage(
        id: id,
        role: ChatRole.assistant,
        kind: ChatKind.citations,
        content: {"citations": citations},
        ts: DateTime.now(),
      );

  factory ChatMessage.assistantChapters(
          String id, List<Map<String, dynamic>> chapters,
          {required String videoUrl}) =>
      ChatMessage(
        id: id,
        role: ChatRole.assistant,
        kind: ChatKind.chapters,
        content: {"chapters": chapters, "videoUrl": videoUrl},
        ts: DateTime.now(),
      );

  factory ChatMessage.assistantError(String id, String message) => ChatMessage(
        id: id,
        role: ChatRole.assistant,
        kind: ChatKind.error,
        content: {"message": message},
        ts: DateTime.now(),
      );

  ChatMessage copyWith({
    String? id,
    ChatRole? role,
    ChatKind? kind,
    Map<String, dynamic>? content,
    DateTime? ts,
  }) =>
      ChatMessage(
        id: id ?? this.id,
        role: role ?? this.role,
        kind: kind ?? this.kind,
        content: content ?? this.content,
        ts: ts ?? this.ts,
      );

  Map<String, dynamic> toJson() => {
        "id": id,
        "role": role.name,
        "kind": kind.name,
        "content": content,
        "ts": ts.toIso8601String(),
      };

  static ChatMessage fromJson(Map<String, dynamic> json) => ChatMessage(
        id: json["id"] as String,
        role: ChatRole.values.firstWhere((e) => e.name == json["role"]),
        kind: ChatKind.values.firstWhere((e) => e.name == json["kind"]),
        content: Map<String, dynamic>.from(json["content"] as Map),
        ts: DateTime.parse(json["ts"] as String),
      );

  static String encodeList(List<ChatMessage> list) =>
      jsonEncode(list.map((m) => m.toJson()).toList());
  static List<ChatMessage> decodeList(String s) {
    final raw = jsonDecode(s) as List;
    return raw
        .map((e) => ChatMessage.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }
}
