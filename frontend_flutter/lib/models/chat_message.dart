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

  static ChatRole _safeRole(Object? raw) {
    final value = raw?.toString();
    for (final role in ChatRole.values) {
      if (role.name == value) return role;
    }
    return ChatRole.assistant;
  }

  static ChatKind _safeKind(Object? raw) {
    final value = raw?.toString();
    for (final kind in ChatKind.values) {
      if (kind.name == value) return kind;
    }
    return ChatKind.text;
  }

  static Map<String, dynamic> _safeContent(Object? raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    if (raw is String) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) return decoded;
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {
        return {'text': raw};
      }
    }
    return {'text': ''};
  }

  static DateTime _safeTs(Object? raw) {
    final value = raw?.toString() ?? '';
    return DateTime.tryParse(value) ?? DateTime.now();
  }

  static ChatMessage fromSqlMap(Map<String, dynamic> map) => ChatMessage(
        id: map['id']?.toString() ?? '',
        role: _safeRole(map['role']),
        kind: _safeKind(map['kind']),
        content: _safeContent(map['content']),
        ts: _safeTs(map['ts']),
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
        id: json['id']?.toString() ?? '',
        role: _safeRole(json['role']),
        kind: _safeKind(json['kind']),
        content: _safeContent(json['content']),
        ts: _safeTs(json['ts']),
      );

  static String encodeList(List<ChatMessage> list) =>
      jsonEncode(list.map((m) => m.toJson()).toList());
  static List<ChatMessage> decodeList(String s) {
    final raw = jsonDecode(s);
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => ChatMessage.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }
}
