import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/collab.dart';
import '../services/api_service.dart';

/// REST + WebSocket client for the collaboration backend.
///
/// All HTTP calls forward authentication via the JWT stored in shared prefs
/// (same mechanism as ApiService).
class ProjectService {
  final http.Client _http;
  final String _base;

  // Active WebSocket subscriptions keyed by threadId
  final Map<String, WebSocketChannel> _channels = {};
  final Map<String, StreamController<WsEvent>> _controllers = {};
  final Map<String, Timer> _timers = {};
  final Map<String, int> _reconnectAttempts = {};
  final Map<String, String> _wsUserIds = {};

  ProjectService({http.Client? client})
      : _http = client ?? http.Client(),
        _base = ApiService.baseUrl;

  // ── Auth header ─────────────────────────────────────────────────────────────
  // Identity: reuses the stable per-device UUID written by LessonsService under
  // 'hackit:v1:userId'. If it doesn't exist yet (first launch before any lesson),
  // we generate and persist it here so collab works independently.

  static const _kUserIdKey = 'hackit:v1:userId';

  Future<Map<String, String>> _headers() async {
    final userId = await _resolveUserId();
    return {
      'Content-Type': 'application/json',
      'x-user-id': userId,
    };
  }

  /// Returns the stable per-device userId, creating it on first call if needed.
  Future<String> _resolveUserId() async {
    if (_cachedUserId != null) return _cachedUserId!;
    try {
      final prefs = await SharedPreferences.getInstance();
      String? id = prefs.getString(_kUserIdKey);
      if (id == null || id.isEmpty) {
        id = _generateUserId();
        await prefs.setString(_kUserIdKey, id);
      }
      _cachedUserId = id;
      return id;
    } catch (_) {
      // Fallback: use an in-memory id for this session
      _cachedUserId ??= _generateUserId();
      return _cachedUserId!;
    }
  }

  static String _generateUserId() {
    final rnd = Random();
    final ts = DateTime.now().millisecondsSinceEpoch;
    final salt = List.generate(6, (_) => rnd.nextInt(36))
        .map((n) => n.toRadixString(36))
        .join();
    return 'u_${ts}_$salt';
  }

  static String? _cachedUserId;

  /// Pre-warm the cache (call once at app startup).
  static Future<void> init() async {
    await projectService._resolveUserId();
  }

  static void clearUserId() {
    _cachedUserId = null;
  }

  /// Returns the cached userId for WS presence tracking.
  static String? get currentUserId => _cachedUserId;

  // ── HTTP helpers ─────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> _get(String path) async {
    final r = await _http
        .get(
          Uri.parse('$_base$path'),
          headers: await _headers(),
        )
        .timeout(const Duration(seconds: 15));
    return _parse(r);
  }

  Future<Map<String, dynamic>> _post(
      String path, Map<String, dynamic> body) async {
    final r = await _http
        .post(
          Uri.parse('$_base$path'),
          headers: await _headers(),
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 60));
    return _parse(r);
  }

  Future<Map<String, dynamic>> _patch(
      String path, Map<String, dynamic> body) async {
    final r = await _http
        .patch(
          Uri.parse('$_base$path'),
          headers: await _headers(),
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 15));
    return _parse(r);
  }

  Future<Map<String, dynamic>> _delete(String path) async {
    final r = await _http
        .delete(
          Uri.parse('$_base$path'),
          headers: await _headers(),
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

  // ── Projects ─────────────────────────────────────────────────────────────────

  Future<CollabProject> createProject({
    required String title,
    String description = '',
    bool isPublic = false,
  }) async {
    final r = await _post('/api/projects', {
      'title': title,
      'description': description,
      'isPublic': isPublic,
    });
    return CollabProject.fromJson(r['project'] as Map<String, dynamic>);
  }

  Future<List<CollabProject>> listProjects() async {
    final r = await _get('/api/projects');
    return (r['projects'] as List)
        .map((p) => CollabProject.fromJson(p as Map<String, dynamic>))
        .toList();
  }

  Future<CollabProject> getProject(String slug) async {
    final r = await _get('/api/projects/$slug');
    return CollabProject.fromJson(r['project'] as Map<String, dynamic>);
  }

  Future<CollabProject> updateProject(
    String slug, {
    String? title,
    String? description,
    bool? isPublic,
  }) async {
    final body = <String, dynamic>{};
    if (title != null) body['title'] = title;
    if (description != null) body['description'] = description;
    if (isPublic != null) body['isPublic'] = isPublic;
    final r = await _patch('/api/projects/$slug', body);
    return CollabProject.fromJson(r['project'] as Map<String, dynamic>);
  }

  Future<void> archiveProject(String slug) => _delete('/api/projects/$slug');

  // ── Invite ────────────────────────────────────────────────────────────────────

  Future<String> regenerateInvite(String slug) async {
    final r = await _post('/api/projects/$slug/invite/regenerate', {});
    return r['inviteToken'] as String;
  }

  Future<CollabProject> joinProject(String token) async {
    final r = await _post('/api/projects/join/$token', {});
    return CollabProject.fromJson(r['project'] as Map<String, dynamic>);
  }

  // ── Threads ───────────────────────────────────────────────────────────────────

  Future<CollabThread> createThread(
    String slug, {
    String title = 'Conversation',
    String? mode,
    Map<String, dynamic>? context,
  }) async {
    final r = await _post('/api/projects/$slug/threads', {
      'title': title,
      if (mode != null) 'mode': mode,
      if (context != null) 'context': context,
    });
    return CollabThread.fromJson(r['thread'] as Map<String, dynamic>);
  }

  Future<List<CollabThread>> listThreads(String slug) async {
    final r = await _get('/api/projects/$slug/threads');
    return (r['threads'] as List)
        .map((t) => CollabThread.fromJson(t as Map<String, dynamic>))
        .toList();
  }

  Future<CollabThread> getThread(String slug, String threadId) async {
    final r = await _get('/api/projects/$slug/threads/$threadId');
    return CollabThread.fromJson(r['thread'] as Map<String, dynamic>);
  }

  // ── Messages (Gemini) ─────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> sendMessage(
    String slug,
    String threadId, {
    required String prompt,
    bool pin = false,
    String? versionLabel,
  }) async {
    return _post('/api/projects/$slug/threads/$threadId/messages', {
      'prompt': prompt,
      'pin': pin,
      if (versionLabel != null) 'versionLabel': versionLabel,
    });
  }

  // ── Versions ──────────────────────────────────────────────────────────────────

  Future<List<CollabVersion>> listVersions(String slug, String threadId) async {
    final r = await _get('/api/projects/$slug/threads/$threadId/versions');
    return (r['versions'] as List)
        .map((v) => CollabVersion.fromJson(v as Map<String, dynamic>))
        .toList();
  }

  Future<CollabVersion> getVersion(
      String slug, String threadId, String versionId) async {
    final r =
        await _get('/api/projects/$slug/threads/$threadId/versions/$versionId');
    return CollabVersion.fromJson(r['version'] as Map<String, dynamic>);
  }

  Future<CollabVersion> approveVersion(
    String slug,
    String threadId,
    String versionId, {
    required String decision,
    String comment = '',
  }) async {
    final r = await _post(
      '/api/projects/$slug/threads/$threadId/versions/$versionId/approve',
      {'decision': decision, 'comment': comment},
    );
    return CollabVersion.fromJson(r['version'] as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>> addComment(
    String slug,
    String threadId,
    String versionId, {
    required String text,
    String? sectionAnchor,
  }) async {
    return _post(
      '/api/projects/$slug/threads/$threadId/versions/$versionId/comments',
      {
        'text': text,
        if (sectionAnchor != null) 'sectionAnchor': sectionAnchor,
      },
    );
  }

  // ── WebSocket (room) ──────────────────────────────────────────────────────────

  /// Connect to a thread room. Returns a broadcast [Stream<WsEvent>].
  /// Auto-reconnects on disconnect with exponential backoff (1s → 30s).
  /// Calling again with the same [threadId] returns the existing stream.
  Stream<WsEvent> subscribeToThread(String threadId, String userId) {
    if (_controllers.containsKey(threadId)) {
      return _controllers[threadId]!.stream;
    }

    final controller = StreamController<WsEvent>.broadcast();
    _controllers[threadId] = controller;
    _wsUserIds[threadId] = userId;
    _reconnectAttempts[threadId] = 0;

    _connectWs(threadId);

    // Keepalive ping every 25s (reuses the latest channel)
    _timers[threadId] = Timer.periodic(const Duration(seconds: 25), (_) {
      final ch = _channels[threadId];
      if (ch == null || !_controllers.containsKey(threadId)) return;
      try {
        ch.sink.add(jsonEncode({'type': 'ping'}));
      } catch (_) {}
    });

    return controller.stream;
  }

  /// Internal: open a WebSocket connection for [threadId] and wire listeners.
  void _connectWs(String threadId) {
    if (!_controllers.containsKey(threadId)) return;
    final userId = _wsUserIds[threadId];
    if (userId == null) return;

    try {
      final wsBase = _base
          .replaceFirst('https://', 'wss://')
          .replaceFirst('http://', 'ws://');
      final uri = Uri.parse('$wsBase/ws/threads/$threadId');
      final channel = WebSocketChannel.connect(uri);
      _channels[threadId] = channel;

      // Identify ourselves immediately after connection
      channel.sink.add(
          jsonEncode({'type': 'join', 'threadId': threadId, 'userId': userId}));

      channel.stream.listen(
        (raw) {
          // Any received frame means the connection is healthy — reset backoff
          _reconnectAttempts[threadId] = 0;
          try {
            final json =
                jsonDecode(raw.toString()) as Map<String, dynamic>;
            _controllers[threadId]?.add(WsEvent.fromJson(json));
          } catch (_) {}
        },
        onDone: () => _scheduleReconnect(threadId),
        onError: (_) => _scheduleReconnect(threadId),
        cancelOnError: true,
      );
    } catch (_) {
      _scheduleReconnect(threadId);
    }
  }

  /// Schedule a reconnection with exponential backoff, notify stream consumers.
  void _scheduleReconnect(String threadId) {
    _channels.remove(threadId);
    final ctrl = _controllers[threadId];
    if (ctrl == null || ctrl.isClosed) return;

    final attempts = _reconnectAttempts[threadId] ?? 0;
    _reconnectAttempts[threadId] = attempts + 1;
    const delays = [1, 2, 4, 8, 16, 30];
    final seconds = delays[attempts.clamp(0, delays.length - 1)];

    // Emit a synthetic reconnecting event so the UI can show a banner
    ctrl.add(const WsEvent(
        type: WsEventType.reconnecting, payload: {}));
    Future.delayed(
        Duration(seconds: seconds), () => _connectWs(threadId));
  }

  void unsubscribeFromThread(String threadId) {
    _cleanupChannel(threadId);
  }

  void _cleanupChannel(String threadId) {
    _channels[threadId]?.sink.close();
    _channels.remove(threadId);
    _timers[threadId]?.cancel();
    _timers.remove(threadId);
    _reconnectAttempts.remove(threadId);
    _wsUserIds.remove(threadId);
    _controllers[threadId]?.close();
    _controllers.remove(threadId);
  }

  void dispose() {
    for (final id in _channels.keys.toList()) {
      _cleanupChannel(id);
    }
    _http.close();
  }
}

/// Singleton accessor — same pattern as ApiService
final projectService = ProjectService();
