import 'package:flutter/foundation.dart';
import '../services/api_service.dart';
import '../services/cache_manager.dart';
import '../services/analytics_manager.dart';
import '../models/base_search_result.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

class SearchProvider extends ChangeNotifier {
  final ApiService _api;
  final CacheManager? _cacheManager;
  final Connectivity _connectivity = Connectivity();
  bool loading = false;
  String? error;
  BaseSearchResult? result;
  DateTime? lastUpdated;
  bool _isOffline = false;

  SearchProvider({
    ApiService? api,
    CacheManager? cacheManager,
  })  : _api = api ?? ApiService.create(),
        _cacheManager = cacheManager {
    _initConnectivity();
  }

  bool get hasError => error != null;
  bool get hasResult => result != null;
  bool get isOffline => _isOffline;
  bool get isStale =>
      lastUpdated == null ||
      DateTime.now().difference(lastUpdated!) > const Duration(minutes: 5);

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
    } catch (e, stackTrace) {
      error = 'Une erreur inattendue est survenue';
      await analytics.logError(
        errorType: 'unexpected_error',
        message: e.toString(),
        stackTrace: stackTrace,
      );
      result ??= null;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> retry() async {
    if (!hasError || loading) return;
    error = null;
    notifyListeners();
    await search(result?.title ?? '');
  }

  void reset() {
    loading = false;
    error = null;
    result = null;
    lastUpdated = null;
    notifyListeners();
  }
}
