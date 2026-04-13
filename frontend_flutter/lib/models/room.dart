/// Dart models for the Salons (Rooms) feature.
/// A Room is a collaborative chat space (DM or group) where an AI colleague
/// participates as a peer alongside human members.
library room_models;

// ─── Room ─────────────────────────────────────────────────────────────────────

class RoomMember {
  final String userId;
  final String displayName;
  final String role;

  const RoomMember({
    required this.userId,
    required this.displayName,
    required this.role,
  });

  factory RoomMember.fromJson(Map<String, dynamic> j) => RoomMember(
        userId: j['userId']?.toString() ?? '',
        displayName: j['displayName']?.toString() ?? 'Anonyme',
        role: j['role']?.toString() ?? 'member',
      );
}

class Room {
  final String id;
  final String name;
  final String type; // 'dm' | 'group'
  final String purpose;
  final String visibility;
  final String ownerId;
  final List<RoomMember> members;
  final String aiDirectives;
  final String? pinnedArtifactId;
  final DateTime lastActivityAt;
  final DateTime updatedAt;

  const Room({
    required this.id,
    required this.name,
    required this.type,
    required this.purpose,
    required this.visibility,
    required this.ownerId,
    required this.members,
    required this.aiDirectives,
    required this.pinnedArtifactId,
    required this.lastActivityAt,
    required this.updatedAt,
  });

  factory Room.fromJson(Map<String, dynamic> j) => Room(
        id: j['_id']?.toString() ?? j['id']?.toString() ?? '',
        name: j['name']?.toString() ?? 'Channel',
        type: j['type']?.toString() ?? 'group',
        purpose: j['purpose']?.toString() ?? '',
        visibility: j['visibility']?.toString() ?? 'invite_only',
        ownerId: j['ownerId']?.toString() ?? '',
        members: (j['members'] as List? ?? [])
            .map((m) => RoomMember.fromJson(m as Map<String, dynamic>))
            .toList(),
        aiDirectives: j['aiDirectives']?.toString() ?? '',
        pinnedArtifactId: j['pinnedArtifactId']?.toString(),
        lastActivityAt:
            DateTime.tryParse(j['lastActivityAt']?.toString() ?? '') ??
                DateTime.now(),
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
  final Map<String, dynamic> data;
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
    required this.data,
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
        data: (j['data'] as Map?)?.cast<String, dynamic>() ?? const {},
        createdAt: DateTime.tryParse(j['createdAt']?.toString() ?? '') ??
            DateTime.now(),
      );

  bool get isDocument => type == 'document' || type == 'artifact';
  bool get isArtifact => type == 'artifact';
  bool get isResearch => type == 'research';
  bool get isDecision => type == 'decision';
  bool get isSystem => type == 'system';

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
        data: data,
        createdAt: createdAt,
      );
}

class ArtifactVersion {
  final String id;
  final String artifactId;
  final int number;
  final String content;
  final String status;
  final List<Map<String, dynamic>> comments;
  final DateTime createdAt;
  final String? contentPreview;

  const ArtifactVersion({
    required this.id,
    required this.artifactId,
    required this.number,
    required this.content,
    required this.status,
    required this.comments,
    required this.createdAt,
    this.contentPreview,
  });

  factory ArtifactVersion.fromJson(Map<String, dynamic> j) => ArtifactVersion(
        id: j['_id']?.toString() ?? j['id']?.toString() ?? '',
        artifactId: j['artifactId']?.toString() ?? '',
        number: int.tryParse(j['number']?.toString() ?? '') ?? 1,
        content: j['content']?.toString() ?? '',
        status: j['status']?.toString() ?? 'draft',
        comments: (j['comments'] as List? ?? [])
            .whereType<Map>()
            .map((comment) => comment.cast<String, dynamic>())
            .toList(),
        createdAt: DateTime.tryParse(j['createdAt']?.toString() ?? '') ??
            DateTime.now(),
        contentPreview: j['contentPreview']?.toString(),
      );
}

class RoomArtifact {
  final String id;
  final String roomId;
  final String title;
  final String kind;
  final String status;
  final String? currentVersionId;
  final ArtifactVersion? currentVersion;
  final DateTime updatedAt;

  const RoomArtifact({
    required this.id,
    required this.roomId,
    required this.title,
    required this.kind,
    required this.status,
    required this.currentVersionId,
    required this.currentVersion,
    required this.updatedAt,
  });

  factory RoomArtifact.fromJson(Map<String, dynamic> j) => RoomArtifact(
        id: j['_id']?.toString() ?? j['id']?.toString() ?? '',
        roomId: j['roomId']?.toString() ?? '',
        title: j['title']?.toString() ?? 'Canvas partagé',
        kind: j['kind']?.toString() ?? 'canvas',
        status: j['status']?.toString() ?? 'draft',
        currentVersionId: j['currentVersionId']?.toString(),
        currentVersion: j['currentVersion'] is Map<String, dynamic>
            ? ArtifactVersion.fromJson(
                j['currentVersion'] as Map<String, dynamic>)
            : null,
        updatedAt: DateTime.tryParse(j['updatedAt']?.toString() ?? '') ??
            DateTime.now(),
      );
}

class RoomMission {
  final String id;
  final String prompt;
  final String status;
  final String requestedBy;
  final String requestedByName;
  final String? resultMessageId;
  final String? resultArtifactId;
  final String? promptPreview;
  final String? error;
  final DateTime createdAt;

  const RoomMission({
    required this.id,
    required this.prompt,
    required this.status,
    required this.requestedBy,
    required this.requestedByName,
    required this.resultMessageId,
    required this.resultArtifactId,
    required this.promptPreview,
    required this.error,
    required this.createdAt,
  });

  factory RoomMission.fromJson(Map<String, dynamic> j) => RoomMission(
        id: j['_id']?.toString() ?? j['id']?.toString() ?? '',
        prompt: j['prompt']?.toString() ?? '',
        status: j['status']?.toString() ?? 'queued',
        requestedBy: j['requestedBy']?.toString() ?? '',
        requestedByName: j['requestedByName']?.toString() ?? 'Anonyme',
        resultMessageId: j['resultMessageId']?.toString(),
        resultArtifactId: j['resultArtifactId']?.toString(),
        promptPreview: j['promptPreview']?.toString(),
        error: j['error']?.toString(),
        createdAt: DateTime.tryParse(j['createdAt']?.toString() ?? '') ??
            DateTime.now(),
      );
}

class RoomMemory {
  final String id;
  final String type;
  final String content;
  final bool pinned;
  final String createdByName;
  final DateTime createdAt;

  const RoomMemory({
    required this.id,
    required this.type,
    required this.content,
    required this.pinned,
    required this.createdByName,
    required this.createdAt,
  });

  factory RoomMemory.fromJson(Map<String, dynamic> j) => RoomMemory(
        id: j['_id']?.toString() ?? j['id']?.toString() ?? '',
        type: j['type']?.toString() ?? 'fact',
        content: j['content']?.toString() ?? '',
        pinned: j['pinned'] == true,
        createdByName: j['createdByName']?.toString() ?? 'Anonyme',
        createdAt: DateTime.tryParse(j['createdAt']?.toString() ?? '') ??
            DateTime.now(),
      );
}

// ─── WebSocket events ─────────────────────────────────────────────────────────

enum WsRoomEventType {
  joined,
  message,
  messageChunk, // streaming partial AI response
  typing,
  challenge,
  artifactCreated,
  artifactVersionCreated,
  missionStatus,
  decisionCreated,
  researchAttached,
  synthesisSuggested,
  briefSuggested,
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
      'message_chunk' => WsRoomEventType.messageChunk,
      'typing' => WsRoomEventType.typing,
      'challenge' => WsRoomEventType.challenge,
      'artifact_created' => WsRoomEventType.artifactCreated,
      'artifact_version_created' => WsRoomEventType.artifactVersionCreated,
      'mission_status' => WsRoomEventType.missionStatus,
      'decision_created' => WsRoomEventType.decisionCreated,
      'research_attached' => WsRoomEventType.researchAttached,
      'synthesis_suggested' => WsRoomEventType.synthesisSuggested,
      'brief_suggested' => WsRoomEventType.briefSuggested,
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

  /// For messageChunk events: the streaming temp ID and cumulative content so far.
  String? get tempId => raw['tempId']?.toString();
  String? get delta => raw['delta']?.toString();

  List<String> get userIds =>
      (raw['userIds'] as List? ?? []).map((u) => u.toString()).toList();

  String? get messageId => raw['messageId']?.toString();

  RoomChallenge? get challenge {
    final c = raw['challenge'];
    if (c == null) return null;
    return RoomChallenge.fromJson(c as Map<String, dynamic>);
  }

  RoomArtifact? get artifact {
    final a = raw['artifact'];
    if (a == null) return null;
    return RoomArtifact.fromJson(a as Map<String, dynamic>);
  }

  ArtifactVersion? get version {
    final v = raw['version'];
    if (v == null) return null;
    return ArtifactVersion.fromJson(v as Map<String, dynamic>);
  }

  String? get artifactId => raw['artifactId']?.toString();

  RoomMission? get mission {
    final m = raw['mission'];
    if (m == null) return null;
    return RoomMission.fromJson(m as Map<String, dynamic>);
  }
}
