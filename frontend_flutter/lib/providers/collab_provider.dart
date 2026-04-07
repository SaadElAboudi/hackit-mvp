import 'package:flutter/foundation.dart';
import '../models/collab.dart';
import '../services/project_service.dart';

enum CollabLoadState { idle, loading, loaded, error }

/// Provider for the collaboration workspace (shared projects, threads, versions).
/// Deliberately named CollabProvider to avoid conflict with the existing
/// ProjectProvider (which manages single-user ClientProject context).
class CollabProvider extends ChangeNotifier {
  final ProjectService _svc;

  CollabProvider({ProjectService? service}) : _svc = service ?? projectService;

  // ── Projects list ─────────────────────────────────────────────────────────────

  CollabLoadState projectsState = CollabLoadState.idle;
  List<CollabProject> projects = [];
  String? projectsError;

  Future<void> loadProjects() async {
    projectsState = CollabLoadState.loading;
    projectsError = null;
    notifyListeners();
    try {
      projects = await _svc.listProjects();
      projectsState = CollabLoadState.loaded;
    } catch (e) {
      projectsError = e.toString();
      projectsState = CollabLoadState.error;
    }
    notifyListeners();
  }

  Future<CollabProject?> createProject({
    required String title,
    String description = '',
  }) async {
    try {
      final p =
          await _svc.createProject(title: title, description: description);
      projects = [p, ...projects];
      notifyListeners();
      return p;
    } catch (e) {
      projectsError = e.toString();
      notifyListeners();
      return null;
    }
  }

  Future<CollabProject?> joinByToken(String token) async {
    try {
      final p = await _svc.joinProject(token);
      if (!projects.any((x) => x.id == p.id)) {
        projects = [p, ...projects];
        notifyListeners();
      }
      return p;
    } catch (e) {
      projectsError = e.toString();
      notifyListeners();
      return null;
    }
  }

  // ── Active project & threads ──────────────────────────────────────────────────

  CollabProject? activeProject;
  CollabLoadState threadsState = CollabLoadState.idle;
  List<CollabThread> threads = [];
  String? threadsError;

  Future<void> openProject(String slug) async {
    threadsState = CollabLoadState.loading;
    threadsError = null;
    notifyListeners();
    try {
      activeProject = await _svc.getProject(slug);
      threads = await _svc.listThreads(slug);
      threadsState = CollabLoadState.loaded;
    } catch (e) {
      threadsError = e.toString();
      threadsState = CollabLoadState.error;
    }
    notifyListeners();
  }

  Future<CollabThread?> createThread(
    String slug, {
    String title = 'Conversation',
    String? mode,
  }) async {
    try {
      final t = await _svc.createThread(slug, title: title, mode: mode);
      threads = [t, ...threads];
      notifyListeners();
      return t;
    } catch (e) {
      threadsError = e.toString();
      notifyListeners();
      return null;
    }
  }

  // ── Active thread (chat) ──────────────────────────────────────────────────────

  CollabThread? activeThread;
  CollabLoadState threadState = CollabLoadState.idle;
  bool sendingMessage = false;
  String? threadError;
  List<String> presenceUserIds = [];
  /// True when a remote participant triggered a Gemini call (typing indicator).
  bool remoteTyping = false;
  /// True while the WebSocket is reconnecting.
  bool wsReconnecting = false;

  Future<void> openThread(String slug, String threadId) async {
    threadState = CollabLoadState.loading;
    threadError = null;
    notifyListeners();
    try {
      activeThread = await _svc.getThread(slug, threadId);
      threadState = CollabLoadState.loaded;
    } catch (e) {
      threadError = e.toString();
      threadState = CollabLoadState.error;
    }
    notifyListeners();
  }

  Future<bool> sendMessage(
    String slug,
    String threadId, {
    required String prompt,
    bool pin = false,
  }) async {
    sendingMessage = true;
    threadError = null;

    // Optimistic user message
    final tmpId = 'tmp_${DateTime.now().millisecondsSinceEpoch}';
    final optimistic = ThreadMessage(
      id: tmpId,
      role: 'user',
      content: prompt,
      createdAt: DateTime.now(),
    );
    activeThread = _appendMessage(activeThread, optimistic);
    notifyListeners();

    try {
      final r =
          await _svc.sendMessage(slug, threadId, prompt: prompt, pin: pin);
      final userMsg =
          ThreadMessage.fromJson(r['userMessage'] as Map<String, dynamic>);
      final aiMsg =
          ThreadMessage.fromJson(r['aiMessage'] as Map<String, dynamic>);

      // Remove optimistic placeholder AND any WS-pre-received copies of these
      // two messages (race: WS broadcast can arrive before the HTTP response).
      final msgs = List<ThreadMessage>.from(activeThread?.messages ?? []);
      msgs.removeWhere(
          (m) => m.id == tmpId || m.id == userMsg.id || m.id == aiMsg.id);
      msgs.add(userMsg);
      msgs.add(aiMsg);

      activeThread = _rebuildThread(activeThread!, msgs);
      sendingMessage = false;
      notifyListeners();
      return true;
    } catch (e) {
      threadError = e.toString();
      // Remove the orphaned optimistic user message
      final msgs = List<ThreadMessage>.from(activeThread?.messages ?? []);
      msgs.removeWhere((m) => m.id == tmpId);
      if (activeThread != null) activeThread = _rebuildThread(activeThread!, msgs);
      sendingMessage = false;
      notifyListeners();
      return false;
    }
  }

  /// Called when a WebSocket broadcast arrives for a message.
  void onWsNewMessage(ThreadMessage msg) {
    if (activeThread == null) return;
    if (activeThread!.messages.any((m) => m.id == msg.id)) return;
    // When an AI message arrives, the remote typing indicator is no longer needed
    if (msg.isAi) remoteTyping = false;
    activeThread = _appendMessage(activeThread, msg);
    notifyListeners();
  }

  void onWsPresence(List<String> userIds) {
    presenceUserIds = userIds;
    notifyListeners();
  }

  /// Called when backend broadcasts that a user triggered a Gemini call.
  void onWsTyping(String? fromUserId) {
    // Only show for other participants (sender has their own sendingMessage flag)
    if (fromUserId != null &&
        fromUserId != ProjectService.currentUserId) {
      remoteTyping = true;
      notifyListeners();
    }
  }

  /// Called when the WS connection is lost and a reconnect attempt starts.
  void onWsReconnecting() {
    wsReconnecting = true;
    notifyListeners();
  }

  /// Called when the WS reconnects successfully (joined frame received).
  void onWsConnected() {
    wsReconnecting = false;
    remoteTyping = false; // clear stale typing indicator from before disconnect
    notifyListeners();
  }

  // ── Versions ──────────────────────────────────────────────────────────────────

  List<CollabVersion> versions = [];
  CollabLoadState versionsState = CollabLoadState.idle;

  Future<void> loadVersions(String slug, String threadId) async {
    versionsState = CollabLoadState.loading;
    notifyListeners();
    try {
      versions = await _svc.listVersions(slug, threadId);
      versionsState = CollabLoadState.loaded;
    } catch (e) {
      versionsState = CollabLoadState.error;
    }
    notifyListeners();
  }

  Future<void> voteVersion(
    String slug,
    String threadId,
    String versionId,
    String decision,
  ) async {
    try {
      final updated = await _svc.approveVersion(
        slug,
        threadId,
        versionId,
        decision: decision,
      );
      versions = versions.map((v) => v.id == updated.id ? updated : v).toList();
      notifyListeners();
    } catch (_) {}
  }

  void clearThread() {
    activeThread = null;
    versions = [];
    presenceUserIds = [];
    threadState = CollabLoadState.idle;
    notifyListeners();
  }

  void clearAll() {
    activeProject = null;
    threads = [];
    clearThread();
    projects = [];
    projectsState = CollabLoadState.idle;
    notifyListeners();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────────

  CollabThread? _appendMessage(CollabThread? t, ThreadMessage msg) {
    if (t == null) return null;
    return _rebuildThread(t, [...t.messages, msg]);
  }

  CollabThread _rebuildThread(CollabThread t, List<ThreadMessage> msgs) =>
      CollabThread(
        id: t.id,
        projectId: t.projectId,
        title: t.title,
        mode: t.mode,
        messages: msgs,
        activeVersionId: t.activeVersionId,
        parentThreadId: t.parentThreadId,
        createdAt: t.createdAt,
      );
}
