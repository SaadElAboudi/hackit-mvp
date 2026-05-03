import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/room.dart';
import '../services/api_service.dart';
import '../services/project_service.dart' show ProjectService;

const _svcTag = '[RoomService]';

class RoomServiceException implements Exception {
  final int statusCode;
  final String message;
  final String? code;
  final String? requestId;
  final int? retryAfterSec;

  const RoomServiceException({
    required this.statusCode,
    required this.message,
    this.code,
    this.requestId,
    this.retryAfterSec,
  });

  bool get isRateLimited => statusCode == 429 || code == 'RATE_LIMITED';

  bool get isRetryable {
    if (isRateLimited) return true;
    if (statusCode == 408 || statusCode == 425) return true;
    if (statusCode >= 500) return true;
    if (code == 'INTERNAL_ERROR') return true;
    return false;
  }

  @override
  String toString() {
    final parts = <String>[message];
    if (code != null && code!.isNotEmpty) {
      parts.add('code: $code');
    }
    if (requestId != null && requestId!.isNotEmpty) {
      parts.add('requestId: $requestId');
    }
    if (retryAfterSec != null && retryAfterSec! > 0) {
      parts.add('retryAfterSec: $retryAfterSec');
    }
    return parts.join(' | ');
  }
}

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

  Future<Map<String, dynamic>> _delete(String path) async {
    final r = await _http
        .delete(Uri.parse('$_base$path'), headers: await _headers())
        .timeout(const Duration(seconds: 15));
    return _parse(r);
  }

  Map<String, dynamic> _parse(http.Response r) {
    Map<String, dynamic> body;
    try {
      body = r.body.isNotEmpty
          ? jsonDecode(r.body) as Map<String, dynamic>
          : <String, dynamic>{};
    } catch (_) {
      body = <String, dynamic>{};
    }
    if (r.statusCode >= 400) {
      final message =
          (body['message'] ?? body['error'] ?? 'HTTP ${r.statusCode}')
              .toString();
      final code = body['code']?.toString();
      final requestId =
          body['requestId']?.toString() ?? r.headers['x-request-id'];
      final retryAfterHeader = int.tryParse(r.headers['retry-after'] ?? '');
      final retryAfterBody = body['details'] is Map<String, dynamic>
          ? int.tryParse(
              ((body['details'] as Map<String, dynamic>)['retryAfterSec'] ?? '')
                  .toString(),
            )
          : null;
      throw RoomServiceException(
        statusCode: r.statusCode,
        message: message,
        code: code,
        requestId: requestId,
        retryAfterSec: retryAfterHeader ?? retryAfterBody,
      );
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

  Future<List<DomainTemplate>> fetchTemplates() async {
    final r = await _get('/api/rooms/templates');
    return (r['templates'] as List)
        .map((j) => DomainTemplate.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  Future<DomainTemplateStatsResponse> fetchTemplateStats(
      {int? sinceDays, String groupBy = 'template'}) async {
    final queryParts = <String>[];
    if (sinceDays != null) queryParts.add('sinceDays=$sinceDays');
    if (groupBy.isNotEmpty) queryParts.add('groupBy=$groupBy');
    final query = queryParts.isEmpty ? '' : '?${queryParts.join('&')}';
    final r = await _get('/api/rooms/templates/stats$query');
    return DomainTemplateStatsResponse.fromJson(r);
  }

  Future<ProductKpiDashboard> fetchProductKpiDashboard({
    int sinceDays = 30,
  }) async {
    final normalizedDays = [7, 30, 90].contains(sinceDays) ? sinceDays : 30;
    final r = await _get('/api/rooms/kpi/dashboard?sinceDays=$normalizedDays');
    return ProductKpiDashboard.fromJson(r);
  }

  Future<Room> createRoom({
    required String name,
    String type = 'group',
    List<Map<String, String>> members = const [],
    String? displayName,
    String? templateId,
    String? templateVersion,
    String? purpose,
  }) async {
    final body = <String, dynamic>{
      'name': name,
      'type': type,
      'members': members,
      if (templateId != null) 'templateId': templateId,
      if (templateVersion != null) 'templateVersion': templateVersion,
      if (purpose != null) 'purpose': purpose,
    };
    final r = await _post('/api/rooms', body, displayName: displayName);
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
    debugPrint(
        '$_svcTag sendMessage HTTP POST: room=$roomId content="${content.substring(0, content.length.clamp(0, 60))}"');
    final r = await _post(
      '/api/rooms/$roomId/messages',
      {'content': content},
      displayName: displayName,
    );
    final msg = RoomMessage.fromJson(r['message'] as Map<String, dynamic>);
    debugPrint('$_svcTag sendMessage HTTP POST: response id=${msg.id}');
    return msg;
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

  // ── Members ───────────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getMembers(String roomId) async {
    final r = await _get('/api/rooms/$roomId/members');
    return (r['members'] as List).cast<Map<String, dynamic>>();
  }

  Future<void> addMember(String roomId, String userId,
      {String? displayName}) async {
    await _post(
      '/api/rooms/$roomId/members',
      {'userId': userId, if (displayName != null) 'displayName': displayName},
    );
  }

  Future<void> removeMember(String roomId, String userId) async {
    await _delete('/api/rooms/$roomId/members/$userId');
  }

  // ── Invite link ───────────────────────────────────────────────────────────────

  Future<String> getInviteLink(String roomId) async {
    final r = await _get('/api/rooms/$roomId/invite');
    return r['link'] as String;
  }

  Future<Room> joinRoom(String roomId) async {
    final r = await _post('/api/rooms/$roomId/join', const {});
    return Room.fromJson(r['room'] as Map<String, dynamic>);
  }

  // ── Document upload ───────────────────────────────────────────────────────────

  Future<RoomMessage> uploadDocument(
    String roomId,
    String content, {
    String? title,
    String? displayName,
  }) async {
    final r = await _post(
      '/api/rooms/$roomId/documents',
      {'content': content, if (title != null) 'title': title},
      displayName: displayName,
    );
    return RoomMessage.fromJson(r['message'] as Map<String, dynamic>);
  }

  Future<List<RoomArtifact>> listArtifacts(String roomId) async {
    final r = await _get('/api/rooms/$roomId/artifacts');
    return (r['artifacts'] as List? ?? [])
        .map((j) => RoomArtifact.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  Future<List<RoomMemory>> listMemory(String roomId) async {
    final r = await _get('/api/rooms/$roomId/memory');
    return (r['memory'] as List? ?? [])
        .map((j) => RoomMemory.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  Future<List<RoomMission>> listMissions(String roomId) async {
    final r = await _get('/api/rooms/$roomId/missions');
    return (r['missions'] as List? ?? [])
        .map((j) => RoomMission.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  Future<List<WorkspaceDecision>> listDecisions(String roomId) async {
    final r = await _get('/api/rooms/$roomId/decisions');
    return (r['decisions'] as List? ?? [])
        .map((j) => WorkspaceDecision.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  Future<WorkspaceDecision> createDecision(
    String roomId, {
    required String title,
    String summary = '',
    String sourceType = 'manual',
  }) async {
    final body = <String, dynamic>{
      'title': title,
      'summary': summary,
      'sourceType': sourceType,
    };
    final r = await _post('/api/rooms/$roomId/decisions', body);
    return WorkspaceDecision.fromJson(r['decision'] as Map<String, dynamic>);
  }

  Future<List<WorkspaceTask>> listTasks(String roomId) async {
    final r = await _get('/api/rooms/$roomId/tasks');
    return (r['tasks'] as List? ?? [])
        .map((j) => WorkspaceTask.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  Future<WorkspaceTask> createTask(
    String roomId, {
    required String title,
    String description = '',
    String ownerId = '',
    String ownerName = '',
    DateTime? dueDate,
  }) async {
    final body = <String, dynamic>{
      'title': title,
      'description': description,
      'ownerId': ownerId,
      'ownerName': ownerName,
      if (dueDate != null) 'dueDate': dueDate.toIso8601String(),
    };
    final r = await _post('/api/rooms/$roomId/tasks', body);
    return WorkspaceTask.fromJson(r['task'] as Map<String, dynamic>);
  }

  Future<WorkspaceTask> updateTask(
    String roomId,
    String taskId, {
    String? title,
    String? description,
    String? status,
    String? ownerId,
    String? ownerName,
    DateTime? dueDate,
    bool clearDueDate = false,
  }) async {
    final body = <String, dynamic>{
      if (title != null) 'title': title,
      if (description != null) 'description': description,
      if (status != null) 'status': status,
      if (ownerId != null) 'ownerId': ownerId,
      if (ownerName != null) 'ownerName': ownerName,
      if (clearDueDate)
        'dueDate': null
      else if (dueDate != null)
        'dueDate': dueDate.toIso8601String(),
    };
    final r = await _patch('/api/rooms/$roomId/tasks/$taskId', body);
    return WorkspaceTask.fromJson(r['task'] as Map<String, dynamic>);
  }

  Future<DecisionExtractionResult> extractMissionDecisions(
    String roomId,
    String missionId, {
    bool persist = false,
    int recentLimit = 20,
  }) async {
    final r = await _post(
      '/api/rooms/$roomId/missions/$missionId/extract',
      {
        'persist': persist,
        'recentLimit': recentLimit,
      },
    );
    return DecisionExtractionResult.fromJson(r);
  }

  /// AI-extract decisions + tasks directly from recent chat messages.
  /// [persist] = false → preview only; true → saves to DB.
  Future<DecisionExtractionResult> extractDecisionsFromChat(
    String roomId, {
    bool persist = false,
    int recentLimit = 30,
    int maxDecisions = 8,
    int maxTasksPerDecision = 4,
  }) async {
    final r = await _post(
      '/api/rooms/$roomId/decisions/extract',
      {
        'persist': persist,
        'recentLimit': recentLimit,
        'maxDecisions': maxDecisions,
        'maxTasksPerDecision': maxTasksPerDecision,
      },
    );
    return DecisionExtractionResult.fromJson(r);
  }

  /// Convert a single decision into concrete tasks via
  /// POST /api/rooms/:id/decisions/:decisionId/convert
  Future<List<WorkspaceTask>> convertDecisionToTasks(
    String roomId,
    String decisionId, {
    required List<Map<String, dynamic>> tasks,
  }) async {
    final r = await _post(
      '/api/rooms/$roomId/decisions/$decisionId/convert',
      {'tasks': tasks},
    );
    return (r['tasks'] as List? ?? [])
        .map((j) => WorkspaceTask.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  Future<void> postMission(String roomId, String prompt,
      {String agentType = 'auto'}) async {
    await _post('/api/rooms/$roomId/missions', {
      'prompt': prompt,
      'agentType': agentType,
    });
  }

  Future<RoomArtifact> createArtifact(
    String roomId, {
    required String title,
    required String content,
    String kind = 'canvas',
  }) async {
    final r = await _post('/api/rooms/$roomId/artifacts', {
      'title': title,
      'content': content,
      'kind': kind,
    });
    return RoomArtifact.fromJson(r['artifact'] as Map<String, dynamic>);
  }

  Future<RoomArtifact> reviseArtifact(
    String roomId,
    String artifactId, {
    required String instructions,
  }) async {
    final r = await _post(
      '/api/rooms/$roomId/artifacts/$artifactId/revise',
      {'instructions': instructions},
    );
    return RoomArtifact.fromJson(r['artifact'] as Map<String, dynamic>);
  }

  Future<List<ArtifactVersion>> fetchArtifactVersions(
      String roomId, String artifactId) async {
    final r = await _get('/api/rooms/$roomId/artifacts/$artifactId/versions');
    return (r['versions'] as List? ?? [])
        .map((j) => ArtifactVersion.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  Future<ArtifactVersion> approveArtifactVersion(
      String roomId, String artifactId, String versionId) async {
    final r = await _post(
      '/api/rooms/$roomId/artifacts/$artifactId/versions/$versionId/approve',
      const {},
    );
    return ArtifactVersion.fromJson(r['version'] as Map<String, dynamic>);
  }

  Future<ArtifactVersion> commentArtifactVersion(
    String roomId,
    String artifactId,
    String versionId, {
    required String content,
    String? displayName,
  }) async {
    final r = await _post(
      '/api/rooms/$roomId/artifacts/$artifactId/versions/$versionId/comment',
      {'content': content},
      displayName: displayName,
    );
    return ArtifactVersion.fromJson(r['version'] as Map<String, dynamic>);
  }

  Future<ArtifactVersion> rejectArtifactVersion(
    String roomId,
    String artifactId,
    String versionId, {
    String reason = '',
  }) async {
    final body = reason.trim().isNotEmpty
        ? {'reason': reason.trim()}
        : const <String, dynamic>{};
    final r = await _post(
      '/api/rooms/$roomId/artifacts/$artifactId/versions/$versionId/reject',
      body,
    );
    return ArtifactVersion.fromJson(r['version'] as Map<String, dynamic>);
  }

  Future<ArtifactVersion> resolveArtifactComment(
    String roomId,
    String artifactId,
    String versionId,
    String commentId, {
    bool resolved = true,
  }) async {
    final r = await _patch(
      '/api/rooms/$roomId/artifacts/$artifactId/versions/$versionId/comments/$commentId/resolve',
      {'resolved': resolved},
    );
    return ArtifactVersion.fromJson(r['version'] as Map<String, dynamic>);
  }

  Future<RoomArtifact> updateArtifactStatus(
    String roomId,
    String artifactId,
    String status,
  ) async {
    final r = await _patch(
      '/api/rooms/$roomId/artifacts/$artifactId/status',
      {'status': status},
    );
    return RoomArtifact.fromJson(r['artifact'] as Map<String, dynamic>);
  }

  Future<void> addMemory(
    String roomId, {
    required String content,
    String type = 'fact',
    bool pinned = true,
  }) async {
    await _post('/api/rooms/$roomId/memory', {
      'content': content,
      'type': type,
      'pinned': pinned,
    });
  }

  Future<void> sendSearchFeedback({
    String requestId = '',
    bool clicked = false,
    bool completed = false,
    int? rating,
  }) async {
    await _post('/api/search/feedback', {
      'requestId': requestId,
      'clicked': clicked,
      'completed': completed,
      if (rating != null) 'rating': rating,
    });
  }

  Future<RoomIntegrationStatus> getSlackIntegrationStatus(String roomId) async {
    final r = await _get('/api/rooms/$roomId/integrations/slack');
    return RoomIntegrationStatus.fromJson('slack', r);
  }

  Future<void> connectSlackIntegration(
    String roomId, {
    required String botToken,
    required String channelId,
  }) async {
    await _post('/api/rooms/$roomId/integrations/slack', {
      'botToken': botToken,
      'channelId': channelId,
    });
  }

  Future<void> disconnectSlackIntegration(String roomId) async {
    await _delete('/api/rooms/$roomId/integrations/slack');
  }

  Future<RoomIntegrationStatus> getNotionIntegrationStatus(
      String roomId) async {
    final r = await _get('/api/rooms/$roomId/integrations/notion');
    return RoomIntegrationStatus.fromJson('notion', r);
  }

  Future<List<NotionPageOption>> discoverNotionPages(
    String roomId, {
    required String apiToken,
    String query = '',
    int limit = 20,
  }) async {
    final r = await _post('/api/rooms/$roomId/integrations/notion/pages', {
      'apiToken': apiToken,
      'query': query,
      'limit': limit.clamp(1, 50),
    });
    return (r['pages'] as List? ?? [])
        .map((j) => NotionPageOption.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  Future<void> connectNotionIntegration(
    String roomId, {
    required String apiToken,
    required String parentPageId,
  }) async {
    await _post('/api/rooms/$roomId/integrations/notion', {
      'apiToken': apiToken,
      'parentPageId': parentPageId,
    });
  }

  Future<void> disconnectNotionIntegration(String roomId) async {
    await _delete('/api/rooms/$roomId/integrations/notion');
  }

  Future<void> shareToIntegration(
    String roomId, {
    required String target,
    String note = '',
  }) async {
    await _post('/api/rooms/$roomId/share', {
      'target': target,
      if (note.trim().isNotEmpty) 'note': note.trim(),
    });
  }

  Future<List<RoomShareHistoryItem>> listShareHistory(
    String roomId, {
    String? target,
    String? status,
    int limit = 20,
  }) async {
    final qp = <String, String>{
      'limit': '${limit.clamp(1, 100)}',
      if (target != null && target.trim().isNotEmpty) 'target': target.trim(),
      if (status != null && status.trim().isNotEmpty) 'status': status.trim(),
    };
    final uri = Uri.parse('$_base/api/rooms/$roomId/share/history')
        .replace(queryParameters: qp);
    final r = await _http
        .get(uri, headers: await _headers())
        .timeout(const Duration(seconds: 15));
    final json = _parse(r);
    return (json['history'] as List? ?? [])
        .map((j) => RoomShareHistoryItem.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  Future<DecisionPackResult> getDecisionPack(
    String roomId, {
    String mode = 'checklist',
    bool includeOpenTasks = true,
    int limit = 10,
  }) async {
    final qp = <String, String>{
      'mode': mode,
      'includeOpenTasks': includeOpenTasks ? 'true' : 'false',
      'limit': '${limit.clamp(1, 50)}',
    };
    final uri = Uri.parse('$_base/api/rooms/$roomId/decision-pack')
        .replace(queryParameters: qp);
    final r = await _http
        .get(uri, headers: await _headers())
        .timeout(const Duration(seconds: 20));
    return DecisionPackResult.fromJson(_parse(r));
  }

  Future<DecisionPackShareResult> shareDecisionPack(
    String roomId, {
    required String target,
    String mode = 'executive',
    String note = '',
  }) async {
    final uri = Uri.parse('$_base/api/rooms/$roomId/decision-pack/share');
    final res = await _http
        .post(
          uri,
          headers: await _headers(),
          body: jsonEncode({
            'target': target,
            'mode': mode,
            if (note.trim().isNotEmpty) 'note': note.trim(),
          }),
        )
        .timeout(const Duration(seconds: 20));
    return DecisionPackShareResult.fromJson(_parse(res));
  }

  Future<DecisionPackReadiness> getDecisionPackReadiness(String roomId) async {
    final uri = Uri.parse('$_base/api/rooms/$roomId/decision-pack/readiness');
    final res = await _http
        .get(uri, headers: await _headers())
        .timeout(const Duration(seconds: 15));
    return DecisionPackReadiness.fromJson(_parse(res));
  }

  Future<void> trackDecisionPackEvent(
    String roomId, {
    required String eventType,
    required String mode,
    String target = '',
    Map<String, dynamic>? metadata,
  }) async {
    await _post('/api/rooms/$roomId/decision-pack/events', {
      'eventType': eventType,
      'mode': mode,
      if (target.trim().isNotEmpty) 'target': target.trim(),
      if (metadata != null) 'metadata': metadata,
    });
  }

  Future<DecisionPackAggregate> getDecisionPackAggregate(
    String roomId, {
    int sinceDays = 7,
  }) async {
    final uri = Uri.parse('$_base/api/rooms/$roomId/decision-pack/aggregate')
        .replace(queryParameters: {
      'sinceDays': '${sinceDays.clamp(1, 90)}',
    });
    final res = await _http
        .get(uri, headers: await _headers())
        .timeout(const Duration(seconds: 15));
    return DecisionPackAggregate.fromJson(_parse(res));
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
      debugPrint('$_svcTag WS connecting: $uri (userId=$userId)');
      final channel = WebSocketChannel.connect(uri);
      _channels[roomId] = channel;

      // Identify ourselves
      channel.sink.add(
        jsonEncode({
          'type': 'join',
          'roomId': roomId,
          'userId': userId,
          'displayName': ProjectService.currentDisplayName,
        }),
      );

      channel.stream.listen(
        (raw) {
          _reconnectAttempts[roomId] = 0; // reset backoff on any received frame
          debugPrint(
              '$_svcTag WS frame received room=$roomId: ${raw.toString().substring(0, raw.toString().length.clamp(0, 120))}');
          try {
            final j = jsonDecode(raw.toString()) as Map<String, dynamic>;
            _controllers[roomId]?.add(WsRoomEvent.fromJson(j));
          } catch (_) {}
        },
        onDone: () {
          debugPrint(
              '$_svcTag WS closed (onDone) room=$roomId → scheduling reconnect');
          _scheduleReconnect(roomId);
        },
        onError: (e) {
          debugPrint(
              '$_svcTag WS error room=$roomId: $e → scheduling reconnect');
          _scheduleReconnect(roomId);
        },
        cancelOnError: true,
      );
    } catch (_) {
      debugPrint(
          '$_svcTag WS connect exception room=$roomId: $_ → scheduling reconnect');
      _scheduleReconnect(roomId);
    }
  }

  void _scheduleReconnect(String roomId) {
    if (!_controllers.containsKey(roomId)) return;

    final attempt = _reconnectAttempts[roomId] ?? 0;
    _reconnectAttempts[roomId] = attempt + 1;
    final delay = Duration(seconds: min(30, 1 << attempt)); // 1,2,4,8,16,30 s

    debugPrint(
        '$_svcTag WS scheduleReconnect room=$roomId attempt=$attempt delay=${delay.inSeconds}s');
    // Emit synthetic reconnecting event
    _controllers[roomId]?.add(
      const WsRoomEvent(
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

  /// Submit v1 relevance feedback on an AI message.
  Future<Map<String, dynamic>> submitMessageFeedback({
    required String roomId,
    required String messageId,
    required int rating,
    String? reason,
    Map<String, dynamic>? metadata,
  }) async {
    final payload = <String, dynamic>{
      'rating': rating,
    };
    if ((reason ?? '').trim().isNotEmpty) {
      payload['reason'] = reason!.trim();
    }
    if (metadata != null && metadata.isNotEmpty) {
      payload['metadata'] = metadata;
    }

    final res = await _http.post(
      Uri.parse('$_base/api/rooms/$roomId/messages/$messageId/feedback'),
      headers: await _headers(),
      body: jsonEncode(payload),
    );
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 200) {
      throw Exception(
          data['message'] ?? data['error'] ?? 'Failed to submit feedback');
    }
    return data;
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
