/// Dart models for the Salons (Rooms) feature.
/// A Room is a collaborative chat space (DM or group) where an AI colleague
/// participates as a peer alongside human members.
library room_models;

// ─── Room ─────────────────────────────────────────────────────────────────────

class RoomMember {
  final String userId;
  final String displayName;

  const RoomMember({required this.userId, required this.displayName});

  factory RoomMember.fromJson(Map<String, dynamic> j) => RoomMember(
        userId: j['userId']?.toString() ?? '',
        displayName: j['displayName']?.toString() ?? 'Anonyme',
      );
}

class Room {
  final String id;
  final String name;
  final String type; // 'dm' | 'group'
  final List<RoomMember> members;
  final String aiDirectives;
  final DateTime updatedAt;

  const Room({
    required this.id,
    required this.name,
    required this.type,
    required this.members,
    required this.aiDirectives,
    required this.updatedAt,
  });

  factory Room.fromJson(Map<String, dynamic> j) => Room(
        id: j['_id']?.toString() ?? j['id']?.toString() ?? '',
        name: j['name']?.toString() ?? 'Salon',
        type: j['type']?.toString() ?? 'group',
        members: (j['members'] as List? ?? [])
            .map((m) => RoomMember.fromJson(m as Map<String, dynamic>))
            .toList(),
        aiDirectives: j['aiDirectives']?.toString() ?? '',
        updatedAt: DateTime.tryParse(j['updatedAt']?.toString() ?? '') ??
            DateTime.now(),
      );

  bool get isDm => type == 'dm';
  int get memberCount => members.length;
}

// ─── RoomMessage ──────────────────────────────────────────────────────────────

class RoomChallenge {
  final String userId;
  final String userName;
  final String content;
  final DateTime? createdAt;

  const RoomChallenge({
    required this.userId,
    required this.userName,
    required this.content,
    this.createdAt,
  });

  factory RoomChallenge.fromJson(Map<String, dynamic> j) => RoomChallenge(
        userId: j['userId']?.toString() ?? '',
        userName: j['userName']?.toString() ?? 'Anonyme',
        content: j['content']?.toString() ?? '',
        createdAt: DateTime.tryParse(j['createdAt']?.toString() ?? ''),
      );
}

class RoomMessage {
  final String id;
  final String roomId;
  final String senderId;
  final String senderName;
  final bool isAI;
  final String content;
  final String type; // 'text' | 'document'
  final String? documentTitle;
  final List<RoomChallenge> challenges;
  final DateTime createdAt;

  const RoomMessage({
    required this.id,
    required this.roomId,
    required this.senderId,
    required this.senderName,
    required this.isAI,
    required this.content,
    required this.type,
    this.documentTitle,
    required this.challenges,
    required this.createdAt,
  });

  factory RoomMessage.fromJson(Map<String, dynamic> j) => RoomMessage(
        id: j['_id']?.toString() ?? j['id']?.toString() ?? '',
        roomId: j['roomId']?.toString() ?? '',
        senderId: j['senderId']?.toString() ?? '',
        senderName: j['senderName']?.toString() ?? 'Anonyme',
        isAI: j['isAI'] == true,
        content: j['content']?.toString() ?? '',
        type: j['type']?.toString() ?? 'text',
        documentTitle: j['documentTitle']?.toString(),
        challenges: (j['challenges'] as List? ?? [])
            .map((c) => RoomChallenge.fromJson(c as Map<String, dynamic>))
            .toList(),
        createdAt: DateTime.tryParse(j['createdAt']?.toString() ?? '') ??
            DateTime.now(),
      );

  bool get isDocument => type == 'document';

  /// Copy with updated challenges (after a challenge is broadcast via WS)
  RoomMessage withChallenge(RoomChallenge c) => RoomMessage(
        id: id,
        roomId: roomId,
        senderId: senderId,
        senderName: senderName,
        isAI: isAI,
        content: content,
        type: type,
        documentTitle: documentTitle,
        challenges: [...challenges, c],
        createdAt: createdAt,
      );
}

// ─── WebSocket events ─────────────────────────────────────────────────────────

enum WsRoomEventType {
  joined,
  message,
  typing,
  challenge,
  presence,
  pong,
  error,
  reconnecting, // synthetic — emitted locally on reconnect attempt
  unknown,
}

class WsRoomEvent {
  final WsRoomEventType type;
  final Map<String, dynamic> raw;

  const WsRoomEvent({required this.type, required this.raw});

  factory WsRoomEvent.fromJson(Map<String, dynamic> j) {
    final t = switch (j['type']?.toString()) {
      'joined' => WsRoomEventType.joined,
      'message' => WsRoomEventType.message,
      'typing' => WsRoomEventType.typing,
      'challenge' => WsRoomEventType.challenge,
      'presence' => WsRoomEventType.presence,
      'pong' => WsRoomEventType.pong,
      'error' => WsRoomEventType.error,
      _ => WsRoomEventType.unknown,
    };
    return WsRoomEvent(type: t, raw: j);
  }

  // Convenience getters
  RoomMessage? get message {
    final m = raw['message'];
    if (m == null) return null;
    return RoomMessage.fromJson(m as Map<String, dynamic>);
  }

  String? get userId => raw['userId']?.toString();

  List<String> get userIds =>
      (raw['userIds'] as List? ?? []).map((u) => u.toString()).toList();

  String? get messageId => raw['messageId']?.toString();

  RoomChallenge? get challenge {
    final c = raw['challenge'];
    if (c == null) return null;
    return RoomChallenge.fromJson(c as Map<String, dynamic>);
  }
}
