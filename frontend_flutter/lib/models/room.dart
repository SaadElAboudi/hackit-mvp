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
  final String templateId;
  final String templateVersion;
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
    required this.templateId,
    required this.templateVersion,
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
        templateId: j['templateId']?.toString() ?? '',
        templateVersion: j['templateVersion']?.toString() ?? '',
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
  // Feedback: thumbs up/down counts + this user's vote (-1/0/1) and label.
  final int thumbsUp;
  final int thumbsDown;
  final int userRating; // 1, 0, -1
  final String userRatingLabel; // '', 'pertinent', 'moyen', 'hors_sujet'

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
    this.thumbsUp = 0,
    this.thumbsDown = 0,
    this.userRating = 0,
    this.userRatingLabel = '',
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
        thumbsUp: (j['thumbsUp'] as num?)?.toInt() ?? 0,
        thumbsDown: (j['thumbsDown'] as num?)?.toInt() ?? 0,
        userRating: (j['userRating'] as num?)?.toInt() ?? 0,
        userRatingLabel: j['userRatingLabel']?.toString() ?? '',
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
        thumbsUp: thumbsUp,
        thumbsDown: thumbsDown,
        userRating: userRating,
        userRatingLabel: userRatingLabel,
      );

  /// Copy with updated feedback counts (after submitting a vote)
  RoomMessage withFeedback(
          {required int thumbsUp,
          required int thumbsDown,
          required int userRating,
          String? userRatingLabel}) =>
      RoomMessage(
        id: id,
        roomId: roomId,
        senderId: senderId,
        senderName: senderName,
        isAI: isAI,
        content: content,
        type: type,
        documentTitle: documentTitle,
        challenges: challenges,
        data: data,
        createdAt: createdAt,
        thumbsUp: thumbsUp,
        thumbsDown: thumbsDown,
        userRating: userRating,
        userRatingLabel: userRatingLabel ?? this.userRatingLabel,
      );
}

class ArtifactComment {
  final String id;
  final String content;
  final String authorId;
  final String authorName;
  final bool resolved;
  final DateTime createdAt;

  const ArtifactComment({
    required this.id,
    required this.content,
    required this.authorId,
    required this.authorName,
    required this.resolved,
    required this.createdAt,
  });

  factory ArtifactComment.fromJson(Map<String, dynamic> j) => ArtifactComment(
        id: j['_id']?.toString() ?? j['id']?.toString() ?? '',
        content: j['content']?.toString() ?? '',
        authorId: j['authorId']?.toString() ?? '',
        authorName: j['authorName']?.toString() ?? '',
        resolved: (j['resolved'] as bool?) ?? false,
        createdAt: DateTime.tryParse(j['createdAt']?.toString() ?? '') ??
            DateTime.now(),
      );
}

class ArtifactVersion {
  final String id;
  final String artifactId;
  final int number;
  final String content;
  final String status;
  final List<ArtifactComment> comments;
  final DateTime createdAt;
  final String? contentPreview;
  final String changeSummary;
  final String authorName;

  const ArtifactVersion({
    required this.id,
    required this.artifactId,
    required this.number,
    required this.content,
    required this.status,
    required this.comments,
    required this.createdAt,
    this.contentPreview,
    this.changeSummary = '',
    this.authorName = '',
  });

  factory ArtifactVersion.fromJson(Map<String, dynamic> j) => ArtifactVersion(
        id: j['_id']?.toString() ?? j['id']?.toString() ?? '',
        artifactId: j['artifactId']?.toString() ?? '',
        number: int.tryParse(j['number']?.toString() ?? '') ?? 1,
        content: j['content']?.toString() ?? '',
        status: j['status']?.toString() ?? 'draft',
        comments: (j['comments'] as List? ?? [])
            .whereType<Map>()
            .map((c) => ArtifactComment.fromJson(c.cast<String, dynamic>()))
            .toList(),
        createdAt: DateTime.tryParse(j['createdAt']?.toString() ?? '') ??
            DateTime.now(),
        contentPreview: j['contentPreview']?.toString(),
        changeSummary: j['changeSummary']?.toString() ?? '',
        authorName: j['authorName']?.toString() ?? '',
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
  final String agentType;
  final String agentLabel;
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
    required this.agentType,
    required this.agentLabel,
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
        agentType: j['agentType']?.toString() ?? 'auto',
        agentLabel: j['agentLabel']?.toString() ?? 'Agent auto',
        resultMessageId: j['resultMessageId']?.toString(),
        resultArtifactId: j['resultArtifactId']?.toString(),
        promptPreview: j['promptPreview']?.toString(),
        error: j['error']?.toString(),
        createdAt: DateTime.tryParse(j['createdAt']?.toString() ?? '') ??
            DateTime.now(),
      );
}

class WorkspaceDecision {
  final String id;
  final String title;
  final String summary;
  final String sourceType;
  final String sourceId;
  final String createdByName;
  final DateTime createdAt;

  const WorkspaceDecision({
    required this.id,
    required this.title,
    required this.summary,
    required this.sourceType,
    required this.sourceId,
    required this.createdByName,
    required this.createdAt,
  });

  factory WorkspaceDecision.fromJson(Map<String, dynamic> j) =>
      WorkspaceDecision(
        id: j['_id']?.toString() ?? j['id']?.toString() ?? '',
        title: j['title']?.toString() ?? '',
        summary: j['summary']?.toString() ?? '',
        sourceType: j['sourceType']?.toString() ?? 'manual',
        sourceId: j['sourceId']?.toString() ?? '',
        createdByName: j['createdByName']?.toString() ?? 'Anonyme',
        createdAt: DateTime.tryParse(j['createdAt']?.toString() ?? '') ??
            DateTime.now(),
      );
}

class WorkspaceTask {
  final String id;
  final String decisionId;
  final String title;
  final String description;
  final String status;
  final String ownerId;
  final String ownerName;
  final DateTime? dueDate;
  final DateTime updatedAt;

  const WorkspaceTask({
    required this.id,
    required this.decisionId,
    required this.title,
    required this.description,
    required this.status,
    required this.ownerId,
    required this.ownerName,
    required this.dueDate,
    required this.updatedAt,
  });

  factory WorkspaceTask.fromJson(Map<String, dynamic> j) => WorkspaceTask(
        id: j['_id']?.toString() ?? j['id']?.toString() ?? '',
        decisionId: j['decisionId']?.toString() ?? '',
        title: j['title']?.toString() ?? '',
        description: j['description']?.toString() ?? '',
        status: j['status']?.toString() ?? 'todo',
        ownerId: j['ownerId']?.toString() ?? '',
        ownerName: j['ownerName']?.toString() ?? '',
        dueDate: DateTime.tryParse(j['dueDate']?.toString() ?? ''),
        updatedAt: DateTime.tryParse(j['updatedAt']?.toString() ?? '') ??
            DateTime.now(),
      );
}

class DecisionPackPayload {
  final DateTime generatedAt;
  final String roomId;
  final String roomName;
  final int decisionCount;
  final int taskCount;
  final String mode;
  final bool includeOpenTasks;
  final String markdown;

  const DecisionPackPayload({
    required this.generatedAt,
    required this.roomId,
    required this.roomName,
    required this.decisionCount,
    required this.taskCount,
    required this.mode,
    required this.includeOpenTasks,
    required this.markdown,
  });

  factory DecisionPackPayload.fromJson(Map<String, dynamic> j) =>
      DecisionPackPayload(
        generatedAt: DateTime.tryParse(j['generatedAt']?.toString() ?? '') ??
            DateTime.now(),
        roomId: j['roomId']?.toString() ?? '',
        roomName: j['roomName']?.toString() ?? '',
        decisionCount: (j['decisionCount'] as num?)?.toInt() ?? 0,
        taskCount: (j['taskCount'] as num?)?.toInt() ?? 0,
        mode: j['mode']?.toString() ?? 'checklist',
        includeOpenTasks: j['includeOpenTasks'] != false,
        markdown: j['markdown']?.toString() ?? '',
      );
}

class DecisionPackResult {
  final DecisionPackPayload pack;
  final List<WorkspaceDecision> decisions;
  final List<WorkspaceTask> tasks;

  const DecisionPackResult({
    required this.pack,
    required this.decisions,
    required this.tasks,
  });

  factory DecisionPackResult.fromJson(Map<String, dynamic> j) =>
      DecisionPackResult(
        pack: DecisionPackPayload.fromJson(
            (j['pack'] as Map?)?.cast<String, dynamic>() ?? const {}),
        decisions: (j['decisions'] as List? ?? [])
            .whereType<Map>()
            .map((item) =>
                WorkspaceDecision.fromJson(item.cast<String, dynamic>()))
            .toList(),
        tasks: (j['tasks'] as List? ?? [])
            .whereType<Map>()
            .map((item) => WorkspaceTask.fromJson(item.cast<String, dynamic>()))
            .toList(),
      );
}

class DecisionPackAggregate {
  final int sinceDays;
  final DateTime since;
  final int viewed;
  final int shared;
  final int shareFailed;

  const DecisionPackAggregate({
    required this.sinceDays,
    required this.since,
    required this.viewed,
    required this.shared,
    required this.shareFailed,
  });

  factory DecisionPackAggregate.fromJson(Map<String, dynamic> j) {
    final aggregate = (j['aggregate'] as Map?)?.cast<String, dynamic>() ?? const {};
    final events = (aggregate['events'] as Map?)?.cast<String, dynamic>() ?? const {};
    return DecisionPackAggregate(
      sinceDays: (aggregate['sinceDays'] as num?)?.toInt() ?? 7,
      since: DateTime.tryParse(aggregate['since']?.toString() ?? '') ?? DateTime.now(),
      viewed: (events['viewed'] as num?)?.toInt() ?? 0,
      shared: (events['shared'] as num?)?.toInt() ?? 0,
      shareFailed: (events['share_failed'] as num?)?.toInt() ?? 0,
    );
  }
}

class ExtractedTaskDraft {
  final String title;
  final String description;

  const ExtractedTaskDraft({
    required this.title,
    required this.description,
  });

  factory ExtractedTaskDraft.fromJson(Map<String, dynamic> j) =>
      ExtractedTaskDraft(
        title: j['title']?.toString() ?? '',
        description: j['description']?.toString() ?? '',
      );
}

class ExtractedDecisionDraft {
  final String title;
  final String summary;
  final List<ExtractedTaskDraft> tasks;

  const ExtractedDecisionDraft({
    required this.title,
    required this.summary,
    required this.tasks,
  });

  factory ExtractedDecisionDraft.fromJson(Map<String, dynamic> j) =>
      ExtractedDecisionDraft(
        title: j['title']?.toString() ?? '',
        summary: j['summary']?.toString() ?? '',
        tasks: (j['tasks'] as List? ?? [])
            .whereType<Map>()
            .map((task) =>
                ExtractedTaskDraft.fromJson(task.cast<String, dynamic>()))
            .toList(),
      );
}

class DecisionExtractionResult {
  final bool persisted;
  final List<ExtractedDecisionDraft> extracted;
  final List<WorkspaceDecision> decisions;
  final List<WorkspaceTask> tasks;
  final String? missionId;

  const DecisionExtractionResult({
    required this.persisted,
    required this.extracted,
    required this.decisions,
    required this.tasks,
    required this.missionId,
  });

  factory DecisionExtractionResult.fromJson(Map<String, dynamic> j) =>
      DecisionExtractionResult(
        persisted: j['persisted'] == true,
        extracted: (j['extracted'] as List? ?? [])
            .whereType<Map>()
            .map((item) =>
                ExtractedDecisionDraft.fromJson(item.cast<String, dynamic>()))
            .toList(),
        decisions: (j['decisions'] as List? ?? [])
            .whereType<Map>()
            .map((item) =>
                WorkspaceDecision.fromJson(item.cast<String, dynamic>()))
            .toList(),
        tasks: (j['tasks'] as List? ?? [])
            .whereType<Map>()
            .map((item) => WorkspaceTask.fromJson(item.cast<String, dynamic>()))
            .toList(),
        missionId: (j['missionContext'] as Map?)?['missionId']?.toString(),
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

class RoomIntegrationStatus {
  final String provider; // slack | notion
  final bool enabled;
  final bool connected;
  final String connectedBy;
  final DateTime? connectedAt;
  final String channelId;
  final String parentPageId;

  const RoomIntegrationStatus({
    required this.provider,
    required this.enabled,
    required this.connected,
    required this.connectedBy,
    required this.connectedAt,
    required this.channelId,
    required this.parentPageId,
  });

  factory RoomIntegrationStatus.fromJson(
    String provider,
    Map<String, dynamic> j,
  ) =>
      RoomIntegrationStatus(
        provider: provider,
        enabled: j['enabled'] == true,
        connected: j['connected'] == true,
        connectedBy: j['connectedBy']?.toString() ?? '',
        connectedAt: DateTime.tryParse(j['connectedAt']?.toString() ?? ''),
        channelId: j['channelId']?.toString() ?? '',
        parentPageId: j['parentPageId']?.toString() ?? '',
      );
}

class NotionPageOption {
  final String id;
  final String title;
  final String url;

  const NotionPageOption({
    required this.id,
    required this.title,
    required this.url,
  });

  factory NotionPageOption.fromJson(Map<String, dynamic> j) => NotionPageOption(
        id: j['id']?.toString() ?? '',
        title: j['title']?.toString() ?? 'Untitled page',
        url: j['url']?.toString() ?? '',
      );
}

class RoomShareHistoryItem {
  final String id;
  final String target;
  final String status; // pending | success | failed
  final String actorName;
  final String note;
  final String summary;
  final int retries;
  final String errorCode;
  final String errorMessage;
  final String externalId;
  final String externalUrl;
  final DateTime createdAt;

  const RoomShareHistoryItem({
    required this.id,
    required this.target,
    required this.status,
    required this.actorName,
    required this.note,
    required this.summary,
    required this.retries,
    required this.errorCode,
    required this.errorMessage,
    required this.externalId,
    required this.externalUrl,
    required this.createdAt,
  });

  factory RoomShareHistoryItem.fromJson(Map<String, dynamic> j) =>
      RoomShareHistoryItem(
        id: j['_id']?.toString() ?? j['id']?.toString() ?? '',
        target: j['target']?.toString() ?? '',
        status: j['status']?.toString() ?? 'pending',
        actorName: j['actorName']?.toString() ?? 'Anonyme',
        note: j['note']?.toString() ?? '',
        summary: j['summary']?.toString() ?? '',
        retries: int.tryParse(j['retries']?.toString() ?? '') ?? 0,
        errorCode: j['errorCode']?.toString() ?? '',
        errorMessage: j['errorMessage']?.toString() ?? '',
        externalId: j['externalId']?.toString() ?? '',
        externalUrl: j['externalUrl']?.toString() ?? '',
        createdAt: DateTime.tryParse(j['createdAt']?.toString() ?? '') ??
            DateTime.now(),
      );

  bool get isSuccess => status == 'success';
  bool get isFailed => status == 'failed';
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

// ── Domain template (starter pack) ───────────────────────────────────────────

class DomainTemplate {
  final String id;
  final String version;
  final Map<String, int> versionWeights;
  final String name;
  final String emoji;
  final String description;
  final String purpose;

  const DomainTemplate({
    required this.id,
    required this.version,
    required this.versionWeights,
    required this.name,
    required this.emoji,
    required this.description,
    required this.purpose,
  });

  factory DomainTemplate.fromJson(Map<String, dynamic> j) => DomainTemplate(
        id: j['id']?.toString() ?? '',
        version: j['version']?.toString() ?? '',
        versionWeights: (j['versionWeights'] as Map?)?.map(
              (k, v) => MapEntry(
                k.toString(),
                (v as num?)?.toInt() ?? int.tryParse(v.toString()) ?? 0,
              ),
            ) ??
            const {},
        name: j['name']?.toString() ?? '',
        emoji: j['emoji']?.toString() ?? '',
        description: j['description']?.toString() ?? '',
        purpose: j['purpose']?.toString() ?? '',
      );
}

class DomainTemplateStats {
  final String templateId;
  final String templateVersion;
  final String name;
  final String emoji;
  final String description;
  final int roomsCreated;
  final int messagesSent;
  final int feedbackUp;
  final int feedbackDown;
  final double feedbackAverage;
  final bool isLowSample;
  final bool winner;
  final int d1RetainedRooms;
  final int d7RetainedRooms;
  final double d1RetentionRate;
  final double d7RetentionRate;

  const DomainTemplateStats({
    required this.templateId,
    required this.templateVersion,
    required this.name,
    required this.emoji,
    required this.description,
    required this.roomsCreated,
    required this.messagesSent,
    required this.feedbackUp,
    required this.feedbackDown,
    required this.feedbackAverage,
    required this.isLowSample,
    required this.winner,
    required this.d1RetainedRooms,
    required this.d7RetainedRooms,
    required this.d1RetentionRate,
    required this.d7RetentionRate,
  });

  factory DomainTemplateStats.fromJson(Map<String, dynamic> j) =>
      DomainTemplateStats(
        templateId: j['templateId']?.toString() ?? '',
        templateVersion: j['templateVersion']?.toString() ?? '',
        name: j['name']?.toString() ?? '',
        emoji: j['emoji']?.toString() ?? '',
        description: j['description']?.toString() ?? '',
        roomsCreated: (j['roomsCreated'] as num?)?.toInt() ?? 0,
        messagesSent: (j['messagesSent'] as num?)?.toInt() ?? 0,
        feedbackUp: (j['feedbackUp'] as num?)?.toInt() ?? 0,
        feedbackDown: (j['feedbackDown'] as num?)?.toInt() ?? 0,
        feedbackAverage: (j['feedbackAverage'] as num?)?.toDouble() ?? 0,
        isLowSample: j['isLowSample'] == true,
        winner: j['winner'] == true,
        d1RetainedRooms: (j['d1RetainedRooms'] as num?)?.toInt() ?? 0,
        d7RetainedRooms: (j['d7RetainedRooms'] as num?)?.toInt() ?? 0,
        d1RetentionRate: (j['d1RetentionRate'] as num?)?.toDouble() ?? 0,
        d7RetentionRate: (j['d7RetentionRate'] as num?)?.toDouble() ?? 0,
      );
}

class DomainTemplateInsights {
  final DomainTemplateStats? topByFeedback;
  final DomainTemplateStats? topByD7Retention;
  final List<DomainTemplateStats> underperformingTemplates;

  const DomainTemplateInsights({
    required this.topByFeedback,
    required this.topByD7Retention,
    required this.underperformingTemplates,
  });

  factory DomainTemplateInsights.fromJson(Map<String, dynamic> j) =>
      DomainTemplateInsights(
        topByFeedback: j['topByFeedback'] is Map<String, dynamic>
            ? DomainTemplateStats.fromJson(
                j['topByFeedback'] as Map<String, dynamic>)
            : null,
        topByD7Retention: j['topByD7Retention'] is Map<String, dynamic>
            ? DomainTemplateStats.fromJson(
                j['topByD7Retention'] as Map<String, dynamic>)
            : null,
        underperformingTemplates: (j['underperformingTemplates'] as List? ?? [])
            .whereType<Map>()
            .map((e) => DomainTemplateStats.fromJson(e.cast<String, dynamic>()))
            .toList(),
      );
}

class DomainTemplateStatsResponse {
  final List<DomainTemplateStats> stats;
  final DomainTemplateInsights? insights;
  final int? sinceDays;
  final String groupBy;
  final int lowSampleThreshold;

  const DomainTemplateStatsResponse({
    required this.stats,
    required this.insights,
    required this.sinceDays,
    required this.groupBy,
    required this.lowSampleThreshold,
  });

  factory DomainTemplateStatsResponse.fromJson(Map<String, dynamic> j) =>
      DomainTemplateStatsResponse(
        stats: (j['stats'] as List? ?? [])
            .whereType<Map>()
            .map((e) => DomainTemplateStats.fromJson(e.cast<String, dynamic>()))
            .toList(),
        insights: j['insights'] is Map<String, dynamic>
            ? DomainTemplateInsights.fromJson(
                j['insights'] as Map<String, dynamic>)
            : null,
        sinceDays: (j['sinceDays'] as num?)?.toInt(),
        groupBy: j['groupBy']?.toString() ?? 'template',
        lowSampleThreshold: (j['lowSampleThreshold'] as num?)?.toInt() ?? 10,
      );
}
