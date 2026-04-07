/// Dart models mirroring the backend Project / Thread / Version schemas.
library collab_models;

// ─── CollabProject ────────────────────────────────────────────────────────────

class CollabMember {
  final String userId;
  final String role; // owner | editor | viewer
  final DateTime joinedAt;

  const CollabMember({
    required this.userId,
    required this.role,
    required this.joinedAt,
  });

  factory CollabMember.fromJson(Map<String, dynamic> j) => CollabMember(
        userId: j['userId']?.toString() ?? '',
        role: j['role']?.toString() ?? 'editor',
        joinedAt: DateTime.tryParse(j['joinedAt']?.toString() ?? '') ?? DateTime.now(),
      );
}

class CollabProject {
  final String id;
  final String title;
  final String description;
  final String slug;
  final String? inviteToken; // only visible to owner
  final List<CollabMember> members;
  final bool isPublic;
  final DateTime createdAt;
  final DateTime updatedAt;

  const CollabProject({
    required this.id,
    required this.title,
    required this.description,
    required this.slug,
    this.inviteToken,
    required this.members,
    required this.isPublic,
    required this.createdAt,
    required this.updatedAt,
  });

  factory CollabProject.fromJson(Map<String, dynamic> j) => CollabProject(
        id: j['_id']?.toString() ?? j['id']?.toString() ?? '',
        title: j['title']?.toString() ?? '',
        description: j['description']?.toString() ?? '',
        slug: j['slug']?.toString() ?? '',
        inviteToken: j['inviteToken']?.toString(),
        members: (j['members'] as List? ?? [])
            .map((m) => CollabMember.fromJson(m as Map<String, dynamic>))
            .toList(),
        isPublic: j['isPublic'] == true,
        createdAt: DateTime.tryParse(j['createdAt']?.toString() ?? '') ?? DateTime.now(),
        updatedAt: DateTime.tryParse(j['updatedAt']?.toString() ?? '') ?? DateTime.now(),
      );

  int get memberCount => members.length;

  String get inviteUrl {
    if (inviteToken == null) return '';
    // Will be updated with the real frontend URL
    return '$_kFrontendBase/join/$inviteToken';
  }

  static const _kFrontendBase = 'https://hackit-frontend.onrender.com';
}

// ─── CollabThread ─────────────────────────────────────────────────────────────

class ThreadMessage {
  final String id;
  final String role; // user | ai | system
  final String content;
  final String? authorId;
  final DateTime createdAt;
  final String? versionRef;

  const ThreadMessage({
    required this.id,
    required this.role,
    required this.content,
    this.authorId,
    required this.createdAt,
    this.versionRef,
  });

  bool get isAi => role == 'ai';
  bool get isUser => role == 'user';

  factory ThreadMessage.fromJson(Map<String, dynamic> j) => ThreadMessage(
        id: j['_id']?.toString() ?? j['id']?.toString() ?? '',
        role: j['role']?.toString() ?? 'user',
        content: j['content']?.toString() ?? '',
        authorId: j['authorId']?.toString(),
        createdAt: DateTime.tryParse(j['createdAt']?.toString() ?? '') ?? DateTime.now(),
        versionRef: j['versionRef']?.toString(),
      );
}

class CollabThread {
  final String id;
  final String projectId;
  final String title;
  final String? mode;
  final List<ThreadMessage> messages;
  final String? activeVersionId;
  final String? parentThreadId;
  final DateTime createdAt;

  const CollabThread({
    required this.id,
    required this.projectId,
    required this.title,
    this.mode,
    required this.messages,
    this.activeVersionId,
    this.parentThreadId,
    required this.createdAt,
  });

  factory CollabThread.fromJson(Map<String, dynamic> j) => CollabThread(
        id: j['_id']?.toString() ?? j['id']?.toString() ?? '',
        projectId: j['projectId']?.toString() ?? '',
        title: j['title']?.toString() ?? 'Conversation',
        mode: j['mode']?.toString(),
        messages: (j['messages'] as List? ?? [])
            .map((m) => ThreadMessage.fromJson(m as Map<String, dynamic>))
            .toList(),
        activeVersionId: j['activeVersionId']?.toString(),
        parentThreadId: j['parentThreadId']?.toString(),
        createdAt: DateTime.tryParse(j['createdAt']?.toString() ?? '') ?? DateTime.now(),
      );
}

// ─── CollabVersion ────────────────────────────────────────────────────────────

class VersionApproval {
  final String userId;
  final String decision; // approved | rejected
  final String comment;

  const VersionApproval({
    required this.userId,
    required this.decision,
    required this.comment,
  });

  factory VersionApproval.fromJson(Map<String, dynamic> j) => VersionApproval(
        userId: j['userId']?.toString() ?? '',
        decision: j['decision']?.toString() ?? '',
        comment: j['comment']?.toString() ?? '',
      );
}

class CollabVersion {
  final String id;
  final String threadId;
  final String projectId;
  final int number;
  final String? label;
  final String? content; // null in list responses
  final String prompt;
  final String createdBy;
  final String status; // draft | approved | rejected | merged
  final List<VersionApproval> approvals;
  final DateTime createdAt;

  const CollabVersion({
    required this.id,
    required this.threadId,
    required this.projectId,
    required this.number,
    this.label,
    this.content,
    required this.prompt,
    required this.createdBy,
    required this.status,
    required this.approvals,
    required this.createdAt,
  });

  int get approvedCount => approvals.where((a) => a.decision == 'approved').length;
  int get rejectedCount => approvals.where((a) => a.decision == 'rejected').length;

  factory CollabVersion.fromJson(Map<String, dynamic> j) => CollabVersion(
        id: j['_id']?.toString() ?? j['id']?.toString() ?? '',
        threadId: j['threadId']?.toString() ?? '',
        projectId: j['projectId']?.toString() ?? '',
        number: (j['number'] as num?)?.toInt() ?? 0,
        label: j['label']?.toString(),
        content: j['content']?.toString(),
        prompt: j['prompt']?.toString() ?? '',
        createdBy: j['createdBy']?.toString() ?? '',
        status: j['status']?.toString() ?? 'draft',
        approvals: (j['approvals'] as List? ?? [])
            .map((a) => VersionApproval.fromJson(a as Map<String, dynamic>))
            .toList(),
        createdAt: DateTime.tryParse(j['createdAt']?.toString() ?? '') ?? DateTime.now(),
      );
}

// ─── WebSocket events ─────────────────────────────────────────────────────────

enum WsEventType { joined, message, version, approval, presence, typing, reconnecting, pong, error, unknown }

class WsEvent {
  final WsEventType type;
  final Map<String, dynamic> payload;

  const WsEvent({required this.type, required this.payload});

  factory WsEvent.fromJson(Map<String, dynamic> j) {
    final t = j['type']?.toString();
    final type = switch (t) {
      'joined' => WsEventType.joined,
      'message' => WsEventType.message,
      'version' => WsEventType.version,
      'approval' => WsEventType.approval,
      'presence' => WsEventType.presence,
      'typing' => WsEventType.typing,
      'pong' => WsEventType.pong,
      'error' => WsEventType.error,
      _ => WsEventType.unknown,
    };
    return WsEvent(type: type, payload: j);
  }
}
