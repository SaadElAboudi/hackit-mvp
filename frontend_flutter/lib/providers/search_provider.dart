import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../services/cache_manager.dart';
import '../services/analytics_manager.dart';
import '../models/base_search_result.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../models/chat_message.dart';

class SearchProvider extends ChangeNotifier {
  final ApiService _api;
  final CacheManager? _cacheManager;
  final Connectivity _connectivity = Connectivity();
  bool loading = false;
  String? error;
  BaseSearchResult? result;
  DateTime? lastUpdated;
  bool _isOffline = false;
  String? lastQuery;
  final SharedPreferences? _prefs;
  List<ChatMessage> messages = [];
  // Draft prompt temporarily set when user chooses to edit a previous message.
  String? _draftText;

  SearchProvider({
    ApiService? api,
    CacheManager? cacheManager,
    SharedPreferences? prefs,
  })  : _api = api ?? ApiService.create(),
        _cacheManager = cacheManager,
        _prefs = prefs {
    _initConnectivity();
    _loadMessages();
  }

  bool get hasError => error != null;
  bool get hasResult => result != null;
  bool get isOffline => _isOffline;
  bool get isStale =>
      lastUpdated == null ||
      DateTime.now().difference(lastUpdated!) > const Duration(minutes: 5);
  String? get draftText => _draftText;

  Future<void> _initConnectivity() async {
    try {
      final result = await _connectivity.checkConnectivity();
      _updateConnectionStatus(result);
    } catch (_) {
      _isOffline = true;
      notifyListeners();
    }

    _connectivity.onConnectivityChanged.listen(_updateConnectionStatus);
  }

  void _updateConnectionStatus(ConnectivityResult result) {
    _isOffline = result == ConnectivityResult.none;
    notifyListeners();
  }

  Future<void> search(String query) async {
    // Use the singleton AnalyticsManager (legacy MVP version) via factory.
    final analytics = AnalyticsManager();
    final stopwatch = Stopwatch()..start();

    if (query.trim().isEmpty) {
      error = 'Veuillez entrer une requête';
      await analytics.logError(
        errorType: 'validation_error',
        message: 'Empty search query',
      );
      notifyListeners();
      return;
    }

    lastQuery = query.trim();
    _appendUser(lastQuery!);
    loading = true;
    error = null;
    notifyListeners();

    // Try to get cached result first
    if (_cacheManager != null) {
      final cached = await _cacheManager.getCachedResult(query);
      if (cached != null) {
        result = cached;
        lastUpdated = DateTime.now();
        loading = false;
        notifyListeners();

        // If we're offline, stop here
        if (_isOffline) return;
      }
    }

    // If we're offline and have no cache, show error
    if (_isOffline) {
      error = 'Mode hors ligne - Pas de résultat en cache';
      _appendError(error!);
      loading = false;
      notifyListeners();
      return;
    }

    try {
      result = await _api.searchVideos(query);
      lastUpdated = DateTime.now();
      error = null;

      // Log successful search
      stopwatch.stop();
      await analytics.logSearch(
        query: query,
        isSuccess: true,
      );
      await analytics.logSearchResult(
        result: result!,
        searchDurationMs: stopwatch.elapsedMilliseconds,
      );

      // Cache the new result
      if (_cacheManager != null) {
        await _cacheManager.cacheSearchResult(query, result!);
      }

      // Append assistant messages (steps + video)
      _appendAssistantFromResult(result!);
    } on ApiException catch (e) {
      error = e.message;
      await analytics.logSearch(
        query: query,
        isSuccess: false,
        errorMessage: e.message,
      );
      await analytics.logError(
        errorType: 'api_error',
        message: e.message,
      );
      // Keep cached result if available
      result ??= null;
      _appendError(error!);
    } catch (e, stackTrace) {
      error = 'Une erreur inattendue est survenue';
      await analytics.logError(
        errorType: 'unexpected_error',
        message: e.toString(),
        stackTrace: stackTrace,
      );
      result ??= null;
      _appendError(error!);
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  // Streaming variant: progressively updates steps, then appends video at the end.
  Future<void> searchStreaming(String query) async {
    final analytics = AnalyticsManager();
    final stopwatch = Stopwatch()..start();

    if (query.trim().isEmpty) {
      error = 'Veuillez entrer une requête';
      await analytics.logError(
        errorType: 'validation_error',
        message: 'Empty search query',
      );
      notifyListeners();
      return;
    }

    lastQuery = query.trim();
    _appendUser(lastQuery!);
    loading = true;
    error = null;
    notifyListeners();

    // If offline, fail fast (we could stream cache, but not implemented yet)
    if (_isOffline) {
      error = 'Mode hors ligne - Pas de résultat en cache';
      _appendError(error!);
      loading = false;
      notifyListeners();
      return;
    }

    // Quick reachability ping to backend to provide clearer error if server is down.
    final health = await _api.pingHealth(timeout: const Duration(seconds: 2));
    if (health['ok'] != true) {
      error =
          'Serveur indisponible. Vérifiez que le backend tourne sur ${ApiService.baseUrl}';
      _appendError(error!);
      loading = false;
      notifyListeners();
      return;
    }

    List<String> partialSteps = [];
    String? currentTitle;
    String? currentVideo;
    String? currentSource;
    int?
        stepsMsgIndex; // index in messages list for the streaming steps message

    try {
      final stream = _api.searchVideosStream(lastQuery!);
      await for (final evt in stream) {
        switch (evt.type) {
          case 'meta':
            currentTitle = evt.title ?? '';
            currentVideo = evt.videoUrl ?? '';
            currentSource = evt.source ?? '';
            // create initial assistant steps message with empty steps
            final msg = ChatMessage.assistantSteps(
              _newId(),
              currentTitle,
              const [],
              source: currentSource.isNotEmpty ? currentSource : null,
            );
            messages = [...messages, msg];
            stepsMsgIndex = messages.length - 1;
            _saveMessages();
            notifyListeners();
            break;
          case 'partial':
            final step = evt.step;
            if (step != null && step.trim().isNotEmpty) {
              partialSteps = [...partialSteps, step.trim()];
              if (stepsMsgIndex != null &&
                  stepsMsgIndex >= 0 &&
                  stepsMsgIndex < messages.length) {
                final m = messages[stepsMsgIndex];
                final updated = m.copyWith(
                  content: {
                    ...m.content,
                    'steps': partialSteps,
                  },
                );
                messages = [
                  ...messages.sublist(0, stepsMsgIndex),
                  updated,
                  ...messages.sublist(stepsMsgIndex + 1),
                ];
                _saveMessages();
                notifyListeners();
              }
            }
            break;
          case 'error':
            error = evt.message ?? 'Erreur de flux';
            _appendError(error!);
            loading = false;
            notifyListeners();
            return;
          case 'done':
            // append video message now that we have title/video
            if ((currentTitle ?? '').isNotEmpty &&
                (currentVideo ?? '').isNotEmpty) {
              final videoMsg = ChatMessage.assistantVideo(
                _newId(),
                currentTitle!,
                currentVideo!,
                source: currentSource,
              );
              messages = [...messages, videoMsg];
              _saveMessages();
            }
            stopwatch.stop();
            await analytics.logSearch(
              query: lastQuery!,
              isSuccess: true,
            );
            loading = false;
            notifyListeners();
            return;
          default:
            break;
        }
      }
    } catch (e, stack) {
      error = 'Une erreur inattendue est survenue';
      await analytics.logError(
        errorType: 'unexpected_error',
        message: e.toString(),
        stackTrace: stack,
      );
      _appendError(error!);
      loading = false;
      notifyListeners();
    }
  }

  Future<void> retry() async {
    if (!hasError || loading) return;
    error = null;
    notifyListeners();
    await search((lastQuery ?? result?.title ?? '').trim());
  }

  Future<void> regenerateLast() async {
    if (loading) return;
    final q = (lastQuery ?? '').trim();
    if (q.isEmpty) return;

    final analytics = AnalyticsManager();
    final stopwatch = Stopwatch()..start();

    loading = true;
    error = null;
    notifyListeners();

    // If offline and no cache, fail fast
    if (_isOffline) {
      error = 'Mode hors ligne - Regénération impossible';
      _appendError(error!);
      loading = false;
      notifyListeners();
      return;
    }

    try {
      final newResult = await _api.searchVideos(q);
      result = newResult;
      lastUpdated = DateTime.now();
      error = null;

      stopwatch.stop();
      await analytics.logSearch(
        query: q,
        isSuccess: true,
      );
      await analytics.logSearchResult(
        result: newResult,
        searchDurationMs: stopwatch.elapsedMilliseconds,
      );

      // Cache
      if (_cacheManager != null) {
        await _cacheManager.cacheSearchResult(q, newResult);
      }

      // Append assistant response only (pas de bulle user en plus)
      _appendAssistantFromResult(newResult);
    } on ApiException catch (e) {
      error = e.message;
      await analytics.logSearch(
        query: q,
        isSuccess: false,
        errorMessage: e.message,
      );
      await analytics.logError(
        errorType: 'api_error',
        message: e.message,
      );
      _appendError(error!);
    } catch (e, stackTrace) {
      error = 'Une erreur inattendue est survenue';
      await analytics.logError(
        errorType: 'unexpected_error',
        message: e.toString(),
        stackTrace: stackTrace,
      );
      _appendError(error!);
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  void reset() {
    loading = false;
    error = null;
    result = null;
    lastUpdated = null;
    // Keep lastQuery so we can display previous prompt in the chat view context
    notifyListeners();
  }

  // Set a draft from an existing user message to allow editing in the input field.
  void setDraft(String text) {
    _draftText = text;
    notifyListeners();
  }

  void clearDraft() {
    _draftText = null;
    notifyListeners();
  }

  // Regenerate using an arbitrary previous prompt without re-adding a user bubble.
  Future<void> regenerateFor(String query) async {
    if (loading) return;
    final q = query.trim();
    if (q.isEmpty) return;
    final analytics = AnalyticsManager();
    final stopwatch = Stopwatch()..start();
    loading = true;
    error = null;
    notifyListeners();
    if (_isOffline) {
      error = 'Mode hors ligne - Regénération impossible';
      _appendError(error!);
      loading = false;
      notifyListeners();
      return;
    }
    try {
      final newResult = await _api.searchVideos(q);
      result = newResult;
      lastUpdated = DateTime.now();
      error = null;
      stopwatch.stop();
      await analytics.logSearch(
        query: q,
        isSuccess: true,
      );
      await analytics.logSearchResult(
        result: newResult,
        searchDurationMs: stopwatch.elapsedMilliseconds,
      );
      if (_cacheManager != null) {
        await _cacheManager.cacheSearchResult(q, newResult);
      }
      _appendAssistantFromResult(newResult);
    } on ApiException catch (e) {
      error = e.message;
      await analytics.logSearch(
        query: q,
        isSuccess: false,
        errorMessage: e.message,
      );
      await analytics.logError(
        errorType: 'api_error',
        message: e.message,
      );
      _appendError(error!);
    } catch (e, stackTrace) {
      error = 'Une erreur inattendue est survenue';
      await analytics.logError(
        errorType: 'unexpected_error',
        message: e.toString(),
        stackTrace: stackTrace,
      );
      _appendError(error!);
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  // --- Messages helpers & persistence ---
  static const _messagesKey = 'chat_messages';

  void _appendUser(String text) {
    final msg = ChatMessage.userText(_newId(), text);
    _push(msg);
  }

  void _appendAssistantFromResult(BaseSearchResult r) {
    final stepsMsg = ChatMessage.assistantSteps(
      _newId(),
      r.title,
      r.steps,
      source: r.source,
    );
    _push(stepsMsg);
    final videoMsg = ChatMessage.assistantVideo(
      _newId(),
      r.title,
      r.videoUrl,
      source: r.source,
    );
    _push(videoMsg);
  }

  void _appendError(String message) {
    final err = ChatMessage.assistantError(_newId(), message);
    _push(err);
  }

  void _push(ChatMessage m) {
    messages = [...messages, m];
    if (messages.length > 20) {
      messages = messages.sublist(messages.length - 20);
    }
    _saveMessages();
  }

  String _newId() => DateTime.now().microsecondsSinceEpoch.toString();

  void _loadMessages() {
    try {
      final raw = _prefs?.getString(_messagesKey);
      if (raw != null && raw.isNotEmpty) {
        messages = ChatMessage.decodeList(raw);
      }
    } catch (_) {
      messages = [];
    }
  }

  Future<void> _saveMessages() async {
    try {
      await _prefs?.setString(_messagesKey, ChatMessage.encodeList(messages));
    } catch (_) {}
  }
}
