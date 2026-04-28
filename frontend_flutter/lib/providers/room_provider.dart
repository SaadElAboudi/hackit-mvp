import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/room.dart';
import '../services/room_service.dart';
import '../services/project_service.dart' show ProjectService;

const _tag = '[RoomProvider]';

/// State management for the Salons (Rooms) feature.
class RoomProvider extends ChangeNotifier {
  final RoomService _svc;

  RoomProvider({RoomService? service}) : _svc = service ?? roomService;

  // ── Rooms list ────────────────────────────────────────────────────────────────

  List<Room> rooms = [];
  bool loadingRooms = false;
  String? roomsError;

  // ── Domain templates ──────────────────────────────────────────────────────────

  List<DomainTemplate> templates = [];
  bool loadingTemplates = false;
  List<DomainTemplateStats> templateStats = [];
  DomainTemplateInsights? templateInsights;
  int templateStatsSinceDays = 30;
  String templateStatsGroupBy = 'template';
  bool loadingTemplateStats = false;

  Future<void> loadTemplates() async {
    if (templates.isNotEmpty) return; // already cached
    loadingTemplates = true;
    notifyListeners();
    try {
      templates = await _svc.fetchTemplates();
    } catch (_) {
      // non-fatal — templates optional
    } finally {
      loadingTemplates = false;
      notifyListeners();
    }
  }

  Future<void> loadTemplateStats({
    bool force = false,
    int? sinceDays,
    String? groupBy,
  }) async {
    if (loadingTemplateStats) return;
    if (sinceDays != null) templateStatsSinceDays = sinceDays;
    if (groupBy != null) templateStatsGroupBy = groupBy;
    if (!force && templateStats.isNotEmpty) return;
    loadingTemplateStats = true;
    notifyListeners();
    try {
      final payload = await _svc.fetchTemplateStats(
        sinceDays: templateStatsSinceDays,
        groupBy: templateStatsGroupBy,
      );
      templateStats = payload.stats;
      templateInsights = payload.insights;
      templateStatsGroupBy = payload.groupBy;
    } catch (_) {
      // Non-blocking for channels list view.
    } finally {
      loadingTemplateStats = false;
      notifyListeners();
    }
  }

  Future<void> loadRooms() async {
    loadingRooms = true;
    roomsError = null;
    notifyListeners();
    try {
      rooms = await _svc.listRooms();
    } catch (e) {
      roomsError = e.toString().replaceFirst('Exception: ', '');
    } finally {
      loadingRooms = false;
      notifyListeners();
    }
  }

  Future<Room?> createRoom({
    required String name,
    String type = 'group',
    String? displayName,
    String? templateId,
  }) async {
    try {
      final room = await _svc.createRoom(
        name: name,
        type: type,
        displayName: displayName,
        templateId: templateId,
      );
      rooms.insert(0, room);
      notifyListeners();
      return room;
    } catch (e) {
      return null;
    }
  }

  Future<Room?> joinRoomById(String roomId) async {
    try {
      final room = await _svc.joinRoom(roomId);
      final idx = rooms.indexWhere((r) => r.id == room.id);
      if (idx >= 0) {
        rooms[idx] = room;
      } else {
        rooms.insert(0, room);
      }
      notifyListeners();
      return room;
    } catch (e) {
      actionError = _errorMessage(e);
      notifyListeners();
      return null;
    }
  }

  // ── Current room chat ─────────────────────────────────────────────────────────

  Room? currentRoom;
  List<RoomMessage> messages = [];
  List<RoomArtifact> artifacts = [];
  List<RoomMemory> memoryItems = [];
  List<RoomMission> missions = [];
  List<WorkspaceDecision> decisions = [];
  List<WorkspaceTask> tasks = [];
  List<RoomShareHistoryItem> shareHistory = [];
  RoomIntegrationStatus? slackIntegration;
  RoomIntegrationStatus? notionIntegration;
  bool loadingNotionPages = false;
  bool loadingShareHistory = false;
  bool loadingIntegrations = false;
  bool loadingMessages = false;
  String? messagesError;
  String? actionError;

  String _errorMessage(Object e) {
    if (e is RoomServiceException) {
      if (e.isRateLimited) {
        return 'Trop de requetes. Reessayez dans quelques secondes.';
      }
      if (e.requestId != null && e.requestId!.isNotEmpty) {
        return '${e.message} (id: ${e.requestId})';
      }
      return e.message;
    }
    return e.toString().replaceFirst('Exception: ', '');
  }

  /// WS state
  bool aiThinking = false; // AI is currently generating a response
  bool wsReconnecting = false; // WS reconnect in progress
  StreamSubscription<WsRoomEvent>? _wsSub;

  /// Online user IDs received from WS presence events
  List<String> onlineUserIds = [];

  String? get myUserId => ProjectService.currentUserId;

  Future<void> openRoom(Room room) async {
    debugPrint('$_tag openRoom: ${room.id} ("${room.name}")');
    // Close previous WS subscription
    await _wsSub?.cancel();
    _wsSub = null;
    aiThinking = false;
    wsReconnecting = false;
    onlineUserIds = [];
    currentRoom = room;
    messages = [];
    messagesError = null;
    loadingMessages = true;
    notifyListeners();

    try {
      final result = await _svc.getMessages(room.id);
      currentRoom = result.room;
      messages = result.messages;
      final contextResults = await Future.wait([
        _svc.listArtifacts(room.id),
        _svc.listMemory(room.id),
        _svc.listMissions(room.id),
        _svc.listDecisions(room.id),
        _svc.listTasks(room.id),
      ]);
      artifacts = contextResults[0] as List<RoomArtifact>;
      memoryItems = contextResults[1] as List<RoomMemory>;
      missions = contextResults[2] as List<RoomMission>;
      decisions = contextResults[3] as List<WorkspaceDecision>;
      tasks = contextResults[4] as List<WorkspaceTask>;

      // Keep integration/status loading best-effort so chat load never fails
      // due to optional side panels.
      try {
        final slackFuture = _svc.getSlackIntegrationStatus(room.id);
        final notionFuture = _svc.getNotionIntegrationStatus(room.id);
        final historyFuture = _svc.listShareHistory(room.id, limit: 12);
        slackIntegration = await slackFuture;
        notionIntegration = await notionFuture;
        shareHistory = await historyFuture;
      } catch (_) {
        slackIntegration = null;
        notionIntegration = null;
        shareHistory = [];
      }
      debugPrint('$_tag openRoom: loaded ${messages.length} messages');
    } catch (e) {
      debugPrint('$_tag openRoom: error loading messages — $e');
      messagesError = _errorMessage(e);
    } finally {
      loadingMessages = false;
      notifyListeners();
    }

    // Subscribe to WS
    final stream = _svc.subscribeToRoom(room.id);
    _wsSub = stream.listen(_onWsEvent);
  }

  void _onWsEvent(WsRoomEvent event) {
    switch (event.type) {
      case WsRoomEventType.joined:
        wsReconnecting = false;
        aiThinking = false;
        notifyListeners();

      case WsRoomEventType.message:
        final msg = event.message;
        if (msg == null) return;

        // Remove streaming placeholder if this final message carries a tempId
        final tempId = event.raw['message']?['tempId']?.toString();
        if (tempId != null) {
          messages.removeWhere((m) => m.id == tempId);
        }

        // The sender receives their own message via the HTTP response in
        // sendMessage(). Silently ignore the WS echo so there is never a
        // race between the two paths. We still update in-place if HTTP has
        // already placed the message in the list (no-op otherwise).
        if (!msg.isAI && myUserId != null && msg.senderId == myUserId) {
          final idx = messages.indexWhere((m) => m.id == msg.id);
          if (idx >= 0) messages[idx] = msg;
          return; // do NOT notifyListeners — HTTP will do it
        }

        // Messages from other participants and AI: add or update in-place.
        final idx = messages.indexWhere((m) => m.id == msg.id);
        if (idx >= 0) {
          messages[idx] = msg;
        } else {
          messages.add(msg);
        }
        if (msg.isAI) aiThinking = false;
        notifyListeners();

      case WsRoomEventType.typing:
        // AI starts typing — show indicator
        if (event.userId == 'ai') {
          aiThinking = true;
          notifyListeners();
        }

      case WsRoomEventType.messageChunk:
        // Streaming partial AI response — accumulate into a placeholder bubble
        final tempId = event.tempId;
        final delta = event.delta; // cumulative content so far
        if (tempId == null || delta == null) return;
        final idx = messages.indexWhere((m) => m.id == tempId);
        if (idx >= 0) {
          // Update existing placeholder in-place with more content
          final existing = messages[idx];
          messages[idx] = RoomMessage(
            id: existing.id,
            roomId: existing.roomId,
            senderId: existing.senderId,
            senderName: existing.senderName,
            isAI: true,
            content: delta,
            type: 'ai',
            documentTitle: null,
            challenges: const [],
            data: const {},
            createdAt: existing.createdAt,
          );
        } else {
          // First chunk — create a streaming placeholder
          messages.add(RoomMessage(
            id: tempId,
            roomId: currentRoom?.id ?? '',
            senderId: 'ai',
            senderName: 'IA',
            isAI: true,
            content: delta,
            type: 'ai',
            documentTitle: null,
            challenges: const [],
            data: const {},
            createdAt: DateTime.now(),
          ));
        }
        aiThinking = false; // replace spinner with live text
        notifyListeners();

      case WsRoomEventType.challenge:
        final challenge = event.challenge;
        final msgId = event.messageId;
        if (challenge == null || msgId == null) return;
        final idx = messages.indexWhere((m) => m.id == msgId);
        if (idx >= 0) {
          messages[idx] = messages[idx].withChallenge(challenge);
          notifyListeners();
        }

      case WsRoomEventType.artifactCreated:
        final artifact = event.artifact;
        if (artifact == null) return;
        final idx = artifacts.indexWhere((a) => a.id == artifact.id);
        if (idx >= 0) {
          artifacts[idx] = artifact;
        } else {
          artifacts.insert(0, artifact);
        }
        notifyListeners();

      case WsRoomEventType.artifactVersionCreated:
        final artifactId = event.artifactId;
        final version = event.version;
        if (artifactId == null || version == null) return;
        final idx = artifacts.indexWhere((a) => a.id == artifactId);
        if (idx >= 0) {
          final current = artifacts[idx];
          artifacts[idx] = RoomArtifact(
            id: current.id,
            roomId: current.roomId,
            title: current.title,
            kind: current.kind,
            status: current.status,
            currentVersionId: version.id,
            currentVersion: version,
            updatedAt: DateTime.now(),
          );
          notifyListeners();
        }

      case WsRoomEventType.missionStatus:
        final mission = event.mission;
        if (mission == null) return;
        final idx = missions.indexWhere((m) => m.id == mission.id);
        if (idx >= 0) {
          missions[idx] = mission;
        } else {
          missions.insert(0, mission);
        }
        notifyListeners();

      case WsRoomEventType.decisionCreated:
      case WsRoomEventType.researchAttached:
      case WsRoomEventType.synthesisSuggested:
      case WsRoomEventType.briefSuggested:
        final msg = event.message;
        if (msg == null) return;
        final idx = messages.indexWhere((m) => m.id == msg.id);
        if (idx >= 0) {
          messages[idx] = msg;
        } else {
          messages.add(msg);
        }
        notifyListeners();

      case WsRoomEventType.presence:
        onlineUserIds = event.userIds;
        notifyListeners();

      case WsRoomEventType.reconnecting:
        wsReconnecting = true;
        notifyListeners();

      default:
        break;
    }
  }

  // ── Sending a message ─────────────────────────────────────────────────────────

  bool sendingMessage = false;
  String? sendError;

  Future<bool> sendMessage(String content, {String? displayName}) async {
    final room = currentRoom;
    if (room == null) return false;

    sendingMessage = true;
    sendError = null;
    notifyListeners();

    try {
      final saved =
          await _svc.sendMessage(room.id, content, displayName: displayName);

      // Add the confirmed message. Own messages are excluded from the WS
      // broadcast handler, so this is the sole place they enter the list.
      messages.add(saved);

      // Shared AI commands should show the thinking indicator immediately.
      if (RegExp(r'(@ia\b|^/doc\b|^/mission\b|^/search\b|^/decide\b)',
              caseSensitive: false)
          .hasMatch(content)) {
        aiThinking = true;
      }

      sendingMessage = false;
      notifyListeners();
      return true;
    } catch (e) {
      sendError = _errorMessage(e);
      sendingMessage = false;
      notifyListeners();
      return false;
    }
  }

  // ── AI Directives ─────────────────────────────────────────────────────────────

  Future<bool> updateDirectives(String directives) async {
    final room = currentRoom;
    if (room == null) return false;
    actionError = null;
    try {
      await _svc.updateDirectives(room.id, directives);
      currentRoom = Room(
        id: room.id,
        name: room.name,
        type: room.type,
        purpose: room.purpose,
        templateId: room.templateId,
        templateVersion: room.templateVersion,
        visibility: room.visibility,
        ownerId: room.ownerId,
        members: room.members,
        aiDirectives: directives,
        pinnedArtifactId: room.pinnedArtifactId,
        lastActivityAt: room.lastActivityAt,
        updatedAt: DateTime.now(),
      );
      notifyListeners();
      return true;
    } catch (e) {
      actionError = _errorMessage(e);
      return false;
    }
  }

  // ── Challenges ────────────────────────────────────────────────────────────────

  Future<bool> addChallenge(
    String messageId,
    String content, {
    String? displayName,
  }) async {
    final room = currentRoom;
    if (room == null) return false;
    actionError = null;
    try {
      final challenge = await _svc.addChallenge(
        room.id,
        messageId,
        content,
        displayName: displayName,
      );
      final idx = messages.indexWhere((m) => m.id == messageId);
      if (idx >= 0) {
        messages[idx] = messages[idx].withChallenge(challenge);
        notifyListeners();
      }
      return true;
    } catch (e) {
      actionError = _errorMessage(e);
      return false;
    }
  }

  // ── Document upload ────────────────────────────────────────────────────────────

  Future<bool> uploadDocument(
    String content, {
    String? title,
    String? displayName,
  }) async {
    final room = currentRoom;
    if (room == null) return false;
    actionError = null;
    try {
      final msg = await _svc.uploadDocument(
        room.id,
        content,
        title: title,
        displayName: displayName,
      );
      // WS will broadcast it; only add if WS is slow / not connected
      final idx = messages.indexWhere((m) => m.id == msg.id);
      if (idx < 0) {
        messages.add(msg);
        notifyListeners();
      }
      return true;
    } catch (e) {
      actionError = _errorMessage(e);
      return false;
    }
  }

  Future<bool> createArtifact(
    String title,
    String content, {
    String kind = 'canvas',
  }) async {
    final room = currentRoom;
    if (room == null) return false;
    actionError = null;
    try {
      final artifact = await _svc.createArtifact(
        room.id,
        title: title,
        content: content,
        kind: kind,
      );
      final idx = artifacts.indexWhere((a) => a.id == artifact.id);
      if (idx >= 0) {
        artifacts[idx] = artifact;
      } else {
        artifacts.insert(0, artifact);
      }
      notifyListeners();
      return true;
    } catch (e) {
      actionError = _errorMessage(e);
      return false;
    }
  }

  Future<bool> reviseArtifact(
    String artifactId,
    String instructions,
  ) async {
    final room = currentRoom;
    if (room == null) return false;
    actionError = null;
    try {
      final artifact = await _svc.reviseArtifact(
        room.id,
        artifactId,
        instructions: instructions,
      );
      final idx = artifacts.indexWhere((a) => a.id == artifact.id);
      if (idx >= 0) {
        artifacts[idx] = artifact;
      } else {
        artifacts.insert(0, artifact);
      }
      notifyListeners();
      return true;
    } catch (e) {
      actionError = _errorMessage(e);
      return false;
    }
  }

  Future<List<ArtifactVersion>> fetchVersions(String artifactId) async {
    final room = currentRoom;
    if (room == null) return [];
    actionError = null;
    try {
      return await _svc.fetchArtifactVersions(room.id, artifactId);
    } catch (e) {
      actionError = _errorMessage(e);
      return [];
    }
  }

  Future<bool> approveVersion(String artifactId, String versionId) async {
    final room = currentRoom;
    if (room == null) return false;
    actionError = null;
    try {
      await _svc.approveArtifactVersion(room.id, artifactId, versionId);
      await _refreshArtifact(room.id, artifactId);
      return true;
    } catch (e) {
      actionError = _errorMessage(e);
      return false;
    }
  }

  Future<bool> rejectVersion(
    String artifactId,
    String versionId, {
    String reason = '',
  }) async {
    final room = currentRoom;
    if (room == null) return false;
    actionError = null;
    try {
      await _svc.rejectArtifactVersion(room.id, artifactId, versionId,
          reason: reason);
      await _refreshArtifact(room.id, artifactId);
      return true;
    } catch (e) {
      actionError = _errorMessage(e);
      return false;
    }
  }

  Future<bool> updateArtifactStatus(String artifactId, String status) async {
    final room = currentRoom;
    if (room == null) return false;
    actionError = null;
    try {
      final updated =
          await _svc.updateArtifactStatus(room.id, artifactId, status);
      final idx = artifacts.indexWhere((a) => a.id == artifactId);
      if (idx >= 0) artifacts[idx] = updated;
      notifyListeners();
      return true;
    } catch (e) {
      actionError = _errorMessage(e);
      return false;
    }
  }

  Future<ArtifactVersion?> addComment(
    String artifactId,
    String versionId,
    String content, {
    String? displayName,
  }) async {
    final room = currentRoom;
    if (room == null) return null;
    actionError = null;
    try {
      final version = await _svc.commentArtifactVersion(
        room.id,
        artifactId,
        versionId,
        content: content,
        displayName: displayName,
      );
      return version;
    } catch (e) {
      actionError = _errorMessage(e);
      return null;
    }
  }

  Future<ArtifactVersion?> resolveComment(
    String artifactId,
    String versionId,
    String commentId, {
    bool resolved = true,
  }) async {
    final room = currentRoom;
    if (room == null) return null;
    actionError = null;
    try {
      return await _svc.resolveArtifactComment(
        room.id,
        artifactId,
        versionId,
        commentId,
        resolved: resolved,
      );
    } catch (e) {
      actionError = _errorMessage(e);
      return null;
    }
  }

  Future<void> _refreshArtifact(String roomId, String artifactId) async {
    final list = await _svc.listArtifacts(roomId);
    final updated = list.firstWhere(
      (a) => a.id == artifactId,
      orElse: () => artifacts.firstWhere(
        (a) => a.id == artifactId,
        orElse: () => artifacts.first,
      ),
    );
    final idx = artifacts.indexWhere((a) => a.id == artifactId);
    if (idx >= 0) artifacts[idx] = updated;
    notifyListeners();
  }

  Future<bool> addMemory(String content, {String type = 'fact'}) async {
    final room = currentRoom;
    if (room == null) return false;
    actionError = null;
    try {
      await _svc.addMemory(room.id, content: content, type: type);
      memoryItems = await _svc.listMemory(room.id);
      notifyListeners();
      return true;
    } catch (e) {
      actionError = _errorMessage(e);
      return false;
    }
  }

  Future<bool> createMission(String prompt, {String agentType = 'auto'}) async {
    final room = currentRoom;
    if (room == null) return false;
    actionError = null;
    try {
      await _svc.postMission(room.id, prompt, agentType: agentType);
      aiThinking = true;
      notifyListeners();
      return true;
    } catch (e) {
      actionError = _errorMessage(e);
      return false;
    }
  }

  Future<DecisionExtractionResult?> previewMissionExtraction(
    String missionId,
  ) async {
    final room = currentRoom;
    if (room == null) return null;
    actionError = null;
    try {
      return await _svc.extractMissionDecisions(
        room.id,
        missionId,
        persist: false,
      );
    } catch (e) {
      actionError = _errorMessage(e);
      notifyListeners();
      return null;
    }
  }

  Future<DecisionExtractionResult?> persistMissionExtraction(
    String missionId,
  ) async {
    final room = currentRoom;
    if (room == null) return null;
    actionError = null;
    try {
      final result = await _svc.extractMissionDecisions(
        room.id,
        missionId,
        persist: true,
      );
      decisions = await _svc.listDecisions(room.id);
      tasks = await _svc.listTasks(room.id);
      notifyListeners();
      return result;
    } catch (e) {
      actionError = _errorMessage(e);
      notifyListeners();
      return null;
    }
  }

  Future<WorkspaceDecision?> createDecision({
    required String title,
    String summary = '',
    String sourceType = 'manual',
  }) async {
    final room = currentRoom;
    if (room == null) return null;
    actionError = null;
    try {
      final created = await _svc.createDecision(
        room.id,
        title: title,
        summary: summary,
        sourceType: sourceType,
      );
      decisions.insert(0, created);
      notifyListeners();
      return created;
    } catch (e) {
      actionError = _errorMessage(e);
      notifyListeners();
      return null;
    }
  }

  Future<WorkspaceTask?> updateTask(
    WorkspaceTask task, {
    String? title,
    String? description,
    String? status,
    String? ownerId,
    String? ownerName,
    DateTime? dueDate,
    bool clearDueDate = false,
  }) async {
    final room = currentRoom;
    if (room == null) return null;
    actionError = null;
    try {
      final updated = await _svc.updateTask(
        room.id,
        task.id,
        title: title,
        description: description,
        status: status,
        ownerId: ownerId,
        ownerName: ownerName,
        dueDate: dueDate,
        clearDueDate: clearDueDate,
      );
      final idx = tasks.indexWhere((item) => item.id == updated.id);
      if (idx >= 0) {
        tasks[idx] = updated;
      } else {
        tasks.insert(0, updated);
      }
      notifyListeners();
      return updated;
    } catch (e) {
      actionError = _errorMessage(e);
      notifyListeners();
      return null;
    }
  }

  Future<WorkspaceTask?> createTask({
    required String title,
    String description = '',
    String ownerId = '',
    String ownerName = '',
    DateTime? dueDate,
  }) async {
    final room = currentRoom;
    if (room == null) return null;
    actionError = null;
    try {
      final created = await _svc.createTask(
        room.id,
        title: title,
        description: description,
        ownerId: ownerId,
        ownerName: ownerName,
        dueDate: dueDate,
      );
      tasks.insert(0, created);
      notifyListeners();
      return created;
    } catch (e) {
      actionError = _errorMessage(e);
      notifyListeners();
      return null;
    }
  }

  Future<void> refreshIntegrationStatus() async {
    final room = currentRoom;
    if (room == null) return;
    loadingIntegrations = true;
    notifyListeners();
    try {
      final results = await Future.wait<RoomIntegrationStatus>([
        _svc.getSlackIntegrationStatus(room.id),
        _svc.getNotionIntegrationStatus(room.id),
      ]);
      slackIntegration = results[0];
      notionIntegration = results[1];
    } catch (e) {
      actionError = _errorMessage(e);
    } finally {
      loadingIntegrations = false;
      notifyListeners();
    }
  }

  Future<bool> connectSlackIntegration({
    required String botToken,
    required String channelId,
  }) async {
    final room = currentRoom;
    if (room == null) return false;
    actionError = null;
    notifyListeners();
    try {
      await _svc.connectSlackIntegration(
        room.id,
        botToken: botToken,
        channelId: channelId,
      );
      await refreshIntegrationStatus();
      return true;
    } catch (e) {
      actionError = _errorMessage(e);
      notifyListeners();
      return false;
    }
  }

  Future<bool> disconnectSlackIntegration() async {
    final room = currentRoom;
    if (room == null) return false;
    actionError = null;
    notifyListeners();
    try {
      await _svc.disconnectSlackIntegration(room.id);
      await refreshIntegrationStatus();
      return true;
    } catch (e) {
      actionError = _errorMessage(e);
      notifyListeners();
      return false;
    }
  }

  Future<bool> connectNotionIntegration({
    required String apiToken,
    required String parentPageId,
  }) async {
    final room = currentRoom;
    if (room == null) return false;
    actionError = null;
    notifyListeners();
    try {
      await _svc.connectNotionIntegration(
        room.id,
        apiToken: apiToken,
        parentPageId: parentPageId,
      );
      await refreshIntegrationStatus();
      return true;
    } catch (e) {
      actionError = _errorMessage(e);
      notifyListeners();
      return false;
    }
  }

  Future<List<NotionPageOption>> discoverNotionPages({
    required String apiToken,
    String query = '',
    int limit = 20,
  }) async {
    final room = currentRoom;
    if (room == null) return const [];
    actionError = null;
    loadingNotionPages = true;
    notifyListeners();
    try {
      return await _svc.discoverNotionPages(
        room.id,
        apiToken: apiToken,
        query: query,
        limit: limit,
      );
    } catch (e) {
      actionError = _errorMessage(e);
      return const [];
    } finally {
      loadingNotionPages = false;
      notifyListeners();
    }
  }

  Future<bool> disconnectNotionIntegration() async {
    final room = currentRoom;
    if (room == null) return false;
    actionError = null;
    notifyListeners();
    try {
      await _svc.disconnectNotionIntegration(room.id);
      await refreshIntegrationStatus();
      return true;
    } catch (e) {
      actionError = _errorMessage(e);
      notifyListeners();
      return false;
    }
  }

  Future<void> refreshShareHistory({
    String? target,
    String? status,
    int limit = 12,
  }) async {
    final room = currentRoom;
    if (room == null) return;
    loadingShareHistory = true;
    notifyListeners();
    try {
      shareHistory = await _svc.listShareHistory(
        room.id,
        target: target,
        status: status,
        limit: limit,
      );
    } catch (e) {
      actionError = _errorMessage(e);
    } finally {
      loadingShareHistory = false;
      notifyListeners();
    }
  }

  Future<bool> shareToIntegration({
    required String target,
    String note = '',
  }) async {
    final room = currentRoom;
    if (room == null) return false;
    actionError = null;
    notifyListeners();
    try {
      await _svc.shareToIntegration(
        room.id,
        target: target,
        note: note,
      );
      await refreshShareHistory(limit: 12);
      return true;
    } catch (e) {
      actionError = _errorMessage(e);
      notifyListeners();
      return false;
    }
  }

  // ── Invite link ────────────────────────────────────────────────────────────────

  Future<String?> getInviteLink() async {
    final room = currentRoom;
    if (room == null) return null;
    actionError = null;
    try {
      return await _svc.getInviteLink(room.id);
    } catch (e) {
      actionError = _errorMessage(e);
      return null;
    }
  }

  // ── Cleanup ───────────────────────────────────────────────────────────────────

  Future<void> closeRoom() async {
    await _wsSub?.cancel();
    _wsSub = null;
    if (currentRoom != null) {
      _svc.unsubscribeFromRoom(currentRoom!.id);
    }
    currentRoom = null;
    messages = [];
    artifacts = [];
    memoryItems = [];
    missions = [];
    decisions = [];
    tasks = [];
    shareHistory = [];
    slackIntegration = null;
    notionIntegration = null;
    loadingNotionPages = false;
    loadingShareHistory = false;
    loadingIntegrations = false;
    aiThinking = false;
    wsReconnecting = false;
    onlineUserIds = [];
    notifyListeners();
  }

  @override
  void dispose() {
    _wsSub?.cancel();
    super.dispose();
  }

  /// Submit thumbs up (+1) or down (-1) on an AI message.
  /// Optimistically updates the message in the local list.
  Future<void> submitMessageFeedback({
    required String messageId,
    required int rating,
  }) async {
    final room = currentRoom;
    if (room == null) return;

    // Optimistic update
    final idx = messages.indexWhere((m) => m.id == messageId);
    if (idx >= 0) {
      final msg = messages[idx];
      final prevRating = msg.userRating;
      final newThumbsUp =
          msg.thumbsUp + (rating == 1 ? 1 : 0) - (prevRating == 1 ? 1 : 0);
      final newThumbsDown =
          msg.thumbsDown + (rating == -1 ? 1 : 0) - (prevRating == -1 ? 1 : 0);
      messages[idx] = msg.withFeedback(
        thumbsUp: newThumbsUp.clamp(0, 99999),
        thumbsDown: newThumbsDown.clamp(0, 99999),
        userRating: rating,
      );
      notifyListeners();
    }

    try {
      final result = await _svc.submitMessageFeedback(
        roomId: room.id,
        messageId: messageId,
        rating: rating,
      );
      // Reconcile with server truth
      if (idx >= 0) {
        messages[idx] = messages[idx].withFeedback(
          thumbsUp:
              (result['thumbsUp'] as num?)?.toInt() ?? messages[idx].thumbsUp,
          thumbsDown: (result['thumbsDown'] as num?)?.toInt() ??
              messages[idx].thumbsDown,
          userRating: rating,
        );
        notifyListeners();
      }
    } catch (e) {
      // Revert optimistic on failure
      if (idx >= 0) {
        final msg = messages[idx];
        messages[idx] = msg.withFeedback(
          thumbsUp: msg.thumbsUp,
          thumbsDown: msg.thumbsDown,
          userRating: 0,
        );
        notifyListeners();
      }
      actionError = _errorMessage(e);
      notifyListeners();
    }
  }
}
