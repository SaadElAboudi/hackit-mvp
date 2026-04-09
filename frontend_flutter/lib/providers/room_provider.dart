import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/room.dart';
import '../services/room_service.dart';
import '../services/project_service.dart' show ProjectService;

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
  bool loadingMessages = false;
  String? messagesError;

  /// WS state
  bool aiThinking = false; // AI is currently generating a response
  bool wsReconnecting = false; // WS reconnect in progress
  StreamSubscription<WsRoomEvent>? _wsSub;

  String? get myUserId => ProjectService.currentUserId;

  Future<void> openRoom(Room room) async {
    // Close previous WS subscription
    await _wsSub?.cancel();
    _wsSub = null;
    aiThinking = false;
    wsReconnecting = false;
    currentRoom = room;
    messages = [];
    loadingMessages = true;
    notifyListeners();

    try {
      final result = await _svc.getMessages(room.id);
      currentRoom = result.room;
      messages = result.messages;
    } catch (e) {
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
        // Dedup: replace if same id already present (e.g. from optimistic insert)
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

    // Optimistic insert so the sender sees their message immediately
    final tmpId = 'tmp_${DateTime.now().millisecondsSinceEpoch}';
    final optimistic = RoomMessage(
      id: tmpId,
      roomId: room.id,
      senderId: myUserId ?? '',
      senderName: displayName ?? 'Moi',
      isAI: false,
      content: content,
      type: 'text',
      challenges: [],
      createdAt: DateTime.now(),
    );
    messages.add(optimistic);
    notifyListeners();

    try {
      final saved =
          await _svc.sendMessage(room.id, content, displayName: displayName);
      // Replace optimistic with persisted version
      final idx = messages.indexWhere((m) => m.id == tmpId);
      if (idx >= 0) {
        messages[idx] = saved;
      } else {
        messages.add(saved);
      }

      // If @ia was mentioned, show AI thinking indicator
      if (RegExp(r'@ia\b', caseSensitive: false).hasMatch(content)) {
        aiThinking = true;
      }

      sendingMessage = false;
      notifyListeners();
      return true;
    } catch (e) {
      // Remove optimistic message on failure
      messages.removeWhere((m) => m.id == tmpId);
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
        members: room.members,
        aiDirectives: directives,
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

  // ── Cleanup ───────────────────────────────────────────────────────────────────

  Future<void> closeRoom() async {
    await _wsSub?.cancel();
    _wsSub = null;
    if (currentRoom != null) {
      _svc.unsubscribeFromRoom(currentRoom!.id);
    }
    currentRoom = null;
    messages = [];
    aiThinking = false;
    wsReconnecting = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _wsSub?.cancel();
    super.dispose();
  }
}
