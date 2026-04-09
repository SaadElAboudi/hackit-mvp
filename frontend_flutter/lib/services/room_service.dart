import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/room.dart';
import '../services/api_service.dart';
import '../services/project_service.dart' show ProjectService;

/// REST + WebSocket client for the Salons (Rooms) feature.
/// Mirrors the patterns in ProjectService; shares the same userId identity.
class RoomService {
  final http.Client _http;
  final String _base;

  RoomService({http.Client? client})
      : _http = client ?? http.Client(),
        _base = ApiService.baseUrl;

  // ── Auth headers ─────────────────────────────────────────────────────────────

  Future<Map<String, String>> _headers({String? displayName}) async {
    final userId = await _resolveUserId();
    return {
      'Content-Type': 'application/json',
      'x-user-id': userId,
      if (displayName != null) 'x-display-name': displayName,
    };
  }

  Future<String> _resolveUserId() async {
    // Reuse the same stable per-device identity used across the app.
    // ProjectService.init() is idempotent — safe to call multiple times.
    if (ProjectService.currentUserId == null) {
      await ProjectService.init();
    }
    return ProjectService.currentUserId!;
  }

  // ── HTTP helpers ─────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> _get(String path) async {
    final r = await _http
        .get(Uri.parse('$_base$path'), headers: await _headers())
        .timeout(const Duration(seconds: 15));
    return _parse(r);
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body, {
    String? displayName,
  }) async {
    final r = await _http
        .post(
          Uri.parse('$_base$path'),
          headers: await _headers(displayName: displayName),
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 60));
    return _parse(r);
  }

  Future<Map<String, dynamic>> _patch(
    String path,
    Map<String, dynamic> body,
  ) async {
    final r = await _http
        .patch(
          Uri.parse('$_base$path'),
          headers: await _headers(),
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 15));
    return _parse(r);
  }

  Map<String, dynamic> _parse(http.Response r) {
    final body = jsonDecode(r.body) as Map<String, dynamic>;
    if (r.statusCode >= 400) {
      throw Exception(body['error'] ?? 'HTTP ${r.statusCode}');
    }
    return body;
  }

  // ── Rooms CRUD ────────────────────────────────────────────────────────────────

  Future<List<Room>> listRooms() async {
    final r = await _get('/api/rooms');
    return (r['rooms'] as List)
        .map((j) => Room.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  Future<Room> createRoom({
    required String name,
    String type = 'group',
    List<Map<String, String>> members = const [],
    String? displayName,
  }) async {
    final r = await _post(
      '/api/rooms',
      {'name': name, 'type': type, 'members': members},
      displayName: displayName,
    );
    return Room.fromJson(r['room'] as Map<String, dynamic>);
  }

  // ── Messages ──────────────────────────────────────────────────────────────────

  Future<({List<RoomMessage> messages, Room room})> getMessages(
      String roomId) async {
    final r = await _get('/api/rooms/$roomId/messages');
    return (
      messages: (r['messages'] as List)
          .map((j) => RoomMessage.fromJson(j as Map<String, dynamic>))
          .toList(),
      room: Room.fromJson(r['room'] as Map<String, dynamic>),
    );
  }

  Future<RoomMessage> sendMessage(
    String roomId,
    String content, {
    String? displayName,
  }) async {
    final r = await _post(
      '/api/rooms/$roomId/messages',
      {'content': content},
      displayName: displayName,
    );
    return RoomMessage.fromJson(r['message'] as Map<String, dynamic>);
  }

  Future<void> updateDirectives(String roomId, String directives) async {
    await _patch('/api/rooms/$roomId/directives', {'directives': directives});
  }

  Future<RoomChallenge> addChallenge(
    String roomId,
    String messageId,
    String content, {
    String? displayName,
  }) async {
    final r = await _post(
      '/api/rooms/$roomId/messages/$messageId/challenge',
      {'content': content},
      displayName: displayName,
    );
    return RoomChallenge.fromJson(r['challenge'] as Map<String, dynamic>);
  }

  // ── WebSocket (per room) ──────────────────────────────────────────────────────

  final Map<String, WebSocketChannel> _channels = {};
  final Map<String, StreamController<WsRoomEvent>> _controllers = {};
  final Map<String, Timer> _timers = {};
  final Map<String, int> _reconnectAttempts = {};
  final Map<String, String> _wsUserIds = {};

  /// Subscribe to live events for [roomId].
  /// Auto-reconnects on disconnection with exponential back-off (1 → 30 s).
  Stream<WsRoomEvent> subscribeToRoom(String roomId) {
    if (_controllers.containsKey(roomId)) {
      return _controllers[roomId]!.stream;
    }

    final controller = StreamController<WsRoomEvent>.broadcast();
    _controllers[roomId] = controller;
    _reconnectAttempts[roomId] = 0;

    _resolveUserId().then((uid) {
      _wsUserIds[roomId] = uid;
      _connectWs(roomId);
    });

    // Keepalive ping every 25 s
    _timers[roomId] = Timer.periodic(const Duration(seconds: 25), (_) {
      _channels[roomId]?.sink.add(jsonEncode({'type': 'ping'}));
    });

    return controller.stream;
  }

  void _connectWs(String roomId) {
    if (!_controllers.containsKey(roomId)) return;
    final userId = _wsUserIds[roomId];
    if (userId == null) return;

    try {
      final wsBase = _base
          .replaceFirst('https://', 'wss://')
          .replaceFirst('http://', 'ws://');
      final uri = Uri.parse('$wsBase/ws/rooms/$roomId');
      final channel = WebSocketChannel.connect(uri);
      _channels[roomId] = channel;

      // Identify ourselves
      channel.sink.add(
        jsonEncode({'type': 'join', 'roomId': roomId, 'userId': userId}),
      );

      channel.stream.listen(
        (raw) {
          _reconnectAttempts[roomId] = 0; // reset backoff on any received frame
          try {
            final j = jsonDecode(raw.toString()) as Map<String, dynamic>;
            _controllers[roomId]?.add(WsRoomEvent.fromJson(j));
          } catch (_) {}
        },
        onDone: () => _scheduleReconnect(roomId),
        onError: (_) => _scheduleReconnect(roomId),
        cancelOnError: true,
      );
    } catch (_) {
      _scheduleReconnect(roomId);
    }
  }

  void _scheduleReconnect(String roomId) {
    if (!_controllers.containsKey(roomId)) return;

    final attempt = _reconnectAttempts[roomId] ?? 0;
    _reconnectAttempts[roomId] = attempt + 1;
    final delay = Duration(seconds: min(30, 1 << attempt)); // 1,2,4,8,16,30 s

    // Emit synthetic reconnecting event
    _controllers[roomId]?.add(
      WsRoomEvent(
        type: WsRoomEventType.reconnecting,
        raw: {'type': 'reconnecting'},
      ),
    );

    Future.delayed(delay, () {
      if (_controllers.containsKey(roomId)) _connectWs(roomId);
    });
  }

  void unsubscribeFromRoom(String roomId) {
    _timers.remove(roomId)?.cancel();
    _channels.remove(roomId)?.sink.close();
    _controllers.remove(roomId)?.close();
    _reconnectAttempts.remove(roomId);
    _wsUserIds.remove(roomId);
  }

  void dispose() {
    for (final id in List.of(_controllers.keys)) {
      unsubscribeFromRoom(id);
    }
    _http.close();
  }
}

/// Singleton — one instance shared across the app.
final roomService = RoomService();
