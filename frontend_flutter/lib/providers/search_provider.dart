import 'package:flutter/foundation.dart';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import 'history_favorites_provider.dart';
import '../services/cache_manager.dart';
import '../services/analytics_manager.dart';
import '../models/base_search_result.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../models/chat_message.dart';
import 'dart:math' show Random, pow;

// Error taxonomy to tailor user-facing messages.
enum ErrorType {
  network,
  timeout,
  quota,
  validation,
  server,
  unexpected,
  unknown
}

String errorTypeToMessage(ErrorType type) {
  switch (type) {
    case ErrorType.network:
      return 'Problème de connexion réseau.';
    case ErrorType.timeout:
      return 'Délai dépassé, veuillez réessayer.';
    case ErrorType.quota:
      return 'Quota / limite de requêtes atteint.';
    case ErrorType.validation:
      return 'Requête invalide.';
    case ErrorType.server:
      return 'Erreur serveur. Réessayez plus tard.';
    case ErrorType.unexpected:
      return 'Erreur inattendue.';
    case ErrorType.unknown:
      return 'Erreur inconnue.';
  }
}

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
  bool _draftRestored = false;

  final bool _testMode;

  final HistoryFavoritesProvider? _historyFavs;

  SearchProvider({
    ApiService? api,
    CacheManager? cacheManager,
    SharedPreferences? prefs,
    HistoryFavoritesProvider? historyFavorites,
    bool testMode = false,
  })  : _api = api ?? ApiService.create(),
        _cacheManager = cacheManager,
        _prefs = prefs,
        _historyFavs = historyFavorites,
        _testMode = testMode {
    if (!_testMode) {
      _initConnectivity();
    }
    _loadMessages();
  }

  bool get hasError => error != null;
  bool get hasResult => result != null;
  bool get isOffline => _isOffline;
  bool get isStale =>
      lastUpdated == null ||
      DateTime.now().difference(lastUpdated!) > const Duration(minutes: 5);
  String? get draftText => _draftText;
  bool get draftRestored => _draftRestored;
  String? _lastTemplate;
  String? get lastTemplate => _lastTemplate;

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

  ErrorType _classifyError(Object e) {
    if (e is ApiException) {
      final msg = e.message.toLowerCase();
      final code = e.statusCode;
      if (msg.contains('timeout')) return ErrorType.timeout;
      if (msg.contains('socketexception') || msg.contains('failed host')) {
        return ErrorType.network;
      }
      if (code == 429 || msg.contains('quota') || msg.contains('rate limit')) {
        return ErrorType.quota;
      }
      if (code == 400 || msg.contains('validation')) {
        return ErrorType.validation;
      }
      if (code != null && code >= 500) return ErrorType.server;
      return ErrorType.unexpected;
    }
    if (e is TimeoutException) return ErrorType.timeout;
    return ErrorType.unknown;
  }

  bool _isTransient(ErrorType type) {
    return type == ErrorType.network || type == ErrorType.timeout;
  }

  Future<void> search(String query) async {
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

    // Try cached first
    if (_cacheManager != null) {
      final cached = await _cacheManager.getCachedResult(query);
      if (cached != null) {
        result = cached;
        lastUpdated = DateTime.now();
        loading = false;
        notifyListeners();
        if (_isOffline) return; // offline short-circuit
      }
    }

    if (_isOffline) {
      error = 'Mode hors ligne - Pas de résultat en cache';
      _appendError(error!);
      loading = false;
      notifyListeners();
      return;
    }

    const maxRetries = 2; // 1–2 automatic retries requirement
    int attempt = 0;
    Object? lastErr;
    ErrorType? lastType;
    while (attempt <= maxRetries) {
      try {
        final r = await _api.searchVideos(query);
        result = r;
        lastUpdated = DateTime.now();
        error = null;
        stopwatch.stop();
        await analytics.logSearch(query: query, isSuccess: true);
        await analytics.logSearchResult(
          result: r,
          searchDurationMs: stopwatch.elapsedMilliseconds,
        );
        if (_cacheManager != null) {
          await _cacheManager.cacheSearchResult(query, r);
        }
        _appendAssistantFromResult(r);
        // record history entry
        _historyFavs?.addHistory(
          query: query,
          title: r.title,
          videoUrl: r.videoUrl,
          source: r.source,
          resultCount: r.steps.length,
        );
        loading = false;
        notifyListeners();
        return; // success -> exit
      } catch (e, stack) {
        lastErr = e;
        lastType = _classifyError(e);
        await analytics.logError(
          errorType: 'search_attempt_error',
          message: e.toString(),
          stackTrace: stack,
        );
        final canRetry = attempt < maxRetries && _isTransient(lastType);
        if (canRetry) {
          attempt++;
          // Exponential backoff with jitter (base 500ms)
          final base = 500 * pow(2, attempt - 1);
          final jitter = Random().nextInt(250); // 0-250ms
          final delay = Duration(milliseconds: (base + jitter).toInt());
          await Future.delayed(delay);
          continue; // retry
        }
        break; // no retry path
      }
    }
    // Final failure
    final et = lastType ?? ErrorType.unknown;
    final msg = errorTypeToMessage(et);
    error = msg;
    _appendError(msg);
    await analytics.logSearch(
      query: query,
      isSuccess: false,
      errorMessage: lastErr.toString(),
    );
    loading = false;
    notifyListeners();
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
          case 'final':
            if (evt.citations.isNotEmpty) {
              _push(ChatMessage.assistantCitations(
                  _newId(), evt.citations.map((c) => c.toMap()).toList()));
            }
            if (evt.chapters.isNotEmpty && currentVideo != null) {
              _push(ChatMessage.assistantChapters(
                  _newId(), evt.chapters.map((c) => c.toMap()).toList(),
                  videoUrl: currentVideo));
            }
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
            // record history entry after stream completes
            if ((currentTitle ?? '').isNotEmpty &&
                (currentVideo ?? '').isNotEmpty) {
              _historyFavs?.addHistory(
                query: lastQuery!,
                title: currentTitle!,
                videoUrl: currentVideo!,
                source: currentSource,
                resultCount: partialSteps.length,
              );
            }
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
      _historyFavs?.addHistory(
        query: q,
        title: newResult.title,
        videoUrl: newResult.videoUrl,
        source: newResult.source,
        resultCount: newResult.steps.length,
      );
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
    try {
      _prefs?.setString(_draftKey, text);
    } catch (_) {}
    notifyListeners();
  }

  void clearDraft() {
    _draftText = null;
    _draftRestored = false;
    try {
      _prefs?.remove(_draftKey);
    } catch (_) {}
    notifyListeners();
  }

  void consumeDraftRestoredFlag() {
    if (_draftRestored) {
      _draftRestored = false;
      notifyListeners();
    }
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
      _historyFavs?.addHistory(
        query: q,
        title: newResult.title,
        videoUrl: newResult.videoUrl,
        source: newResult.source,
        resultCount: newResult.steps.length,
      );
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
    if (r.citations.isNotEmpty) {
      _push(ChatMessage.assistantCitations(
          _newId(), r.citations.map((c) => c.toMap()).toList()));
    }
    if (r.chapters.isNotEmpty) {
      _push(ChatMessage.assistantChapters(
          _newId(), r.chapters.map((c) => c.toMap()).toList(),
          videoUrl: r.videoUrl));
    }
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

  // Removed old timestamp formatter (no longer used in text summaries)

  // Legacy helper removed (structured message kinds now used for citations & chapters)

  void _loadMessages() {
    try {
      final raw = _prefs?.getString(_messagesKey);
      if (raw != null && raw.isNotEmpty) {
        messages = ChatMessage.decodeList(raw);
      }
      _lastTemplate = _prefs?.getString(_lastTemplateKey);
      final d = _prefs?.getString(_draftKey);
      if (d != null && d.isNotEmpty) {
        _draftText = d;
        _draftRestored = true;
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

  static const _lastTemplateKey = 'last_template_id';
  static const _draftKey = 'draft_text';
  Future<void> setLastTemplate(String? id) async {
    _lastTemplate = id;
    if (id == null) {
      await _prefs?.remove(_lastTemplateKey);
    } else {
      await _prefs?.setString(_lastTemplateKey, id);
    }
    notifyListeners();
  }

  // Apply a prompt template to the provided text.
  // Supported ids: 'resume', 'tutoriel', 'eli5', 'fr2en', 'en2fr'
  String applyTemplateText(String id, String current) {
    final base = current.trim();
    switch (id) {
      case 'resume':
        return base.isEmpty ? 'Résume ce contenu:' : 'Résume: $base';
      case 'tutoriel':
        return base.isEmpty
            ? 'Fais un tutoriel étape par étape sur …'
            : 'Fais un tutoriel étape par étape sur: $base';
      case 'eli5':
        return base.isEmpty
            ? "Explique comme si j'avais 5 ans:"
            : "Explique comme si j'avais 5 ans: $base";
      case 'fr2en':
        return base.isEmpty
            ? 'Translate to English:'
            : 'Translate to English: $base';
      case 'en2fr':
        return base.isEmpty
            ? 'Traduire en français:'
            : 'Traduire en français: $base';
      default:
        return current;
    }
  }
}
