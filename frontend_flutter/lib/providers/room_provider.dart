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
  }) async {
    try {
      final room = await _svc.createRoom(
        name: name,
        type: type,
        displayName: displayName,
      );
      rooms.insert(0, room);
      notifyListeners();
      return room;
    } catch (e) {
      return null;
    }
  }

  // ── Current room chat ─────────────────────────────────────────────────────────

  Room? currentRoom;
  List<RoomMessage> messages = [];
  List<RoomArtifact> artifacts = [];
  List<RoomMemory> memoryItems = [];
  List<RoomMission> missions = [];
  bool loadingMessages = false;
  String? messagesError;

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
      ]);
      artifacts = contextResults[0] as List<RoomArtifact>;
      memoryItems = contextResults[1] as List<RoomMemory>;
      missions = contextResults[2] as List<RoomMission>;
      debugPrint('$_tag openRoom: loaded ${messages.length} messages');
    } catch (e) {
      debugPrint('$_tag openRoom: error loading messages — $e');
      messagesError = e.toString().replaceFirst('Exception: ', '');
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
      sendError = e.toString().replaceFirst('Exception: ', '');
      sendingMessage = false;
      notifyListeners();
      return false;
    }
  }

  // ── AI Directives ─────────────────────────────────────────────────────────────

  Future<bool> updateDirectives(String directives) async {
    final room = currentRoom;
    if (room == null) return false;
    try {
      await _svc.updateDirectives(room.id, directives);
      currentRoom = Room(
        id: room.id,
        name: room.name,
        type: room.type,
        purpose: room.purpose,
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
    } catch (_) {
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
    } catch (_) {
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
    } catch (_) {
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
    } catch (_) {
      return false;
    }
  }

  Future<bool> reviseArtifact(
    String artifactId,
    String instructions,
  ) async {
    final room = currentRoom;
    if (room == null) return false;
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
    } catch (_) {
      return false;
    }
  }

  Future<bool> addMemory(String content, {String type = 'fact'}) async {
    final room = currentRoom;
    if (room == null) return false;
    try {
      await _svc.addMemory(room.id, content: content, type: type);
      memoryItems = await _svc.listMemory(room.id);
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> createMission(String prompt) async {
    final room = currentRoom;
    if (room == null) return false;
    try {
      await _svc.postMission(room.id, prompt);
      aiThinking = true;
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  // ── Invite link ────────────────────────────────────────────────────────────────

  Future<String?> getInviteLink() async {
    final room = currentRoom;
    if (room == null) return null;
    try {
      return await _svc.getInviteLink(room.id);
    } catch (_) {
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
}
