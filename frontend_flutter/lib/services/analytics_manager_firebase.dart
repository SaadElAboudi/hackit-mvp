import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';

import '../models/base_search_result.dart';

const bool _analyticsOptIn =
    bool.fromEnvironment('ANALYTICS_OPT_IN', defaultValue: false);

class AnalyticsManager {
  static final AnalyticsManager _instance = AnalyticsManager._internal();
  factory AnalyticsManager() => _instance;

  FirebaseAnalytics? _analytics;
  bool _initialized = false;
  bool _enabled = _analyticsOptIn;

  AnalyticsManager._internal();

  Future<void> _ensureInitialized() async {
    if (_initialized || !_enabled) return;
    try {
      await Firebase.initializeApp();
      _analytics = FirebaseAnalytics.instance;
      _initialized = true;
    } catch (_) {
      _enabled = false;
      _initialized = true;
    }
  }

  Future<void> logSearch({
    required String query,
    required bool isSuccess,
    String? errorMessage,
  }) async {
    await _ensureInitialized();
    if (!_enabled || _analytics == null) return;
    await _analytics!.logEvent(
      name: 'search_performed',
      parameters: {
        'query': query,
        'success': isSuccess,
        'error_message': errorMessage,
        'timestamp': DateTime.now().toIso8601String(),
      },
    );
  }

  Future<void> logSearchResult({
    required BaseSearchResult result,
    required int searchDurationMs,
  }) async {
    await _ensureInitialized();
    if (!_enabled || _analytics == null) return;
    await _analytics!.logEvent(
      name: 'search_result_viewed',
      parameters: {
        'title': result.title,
        'has_video': result.videoUrl.isNotEmpty,
        'steps_count': result.steps.length,
        'source': result.source,
        'duration_ms': searchDurationMs,
      },
    );
  }

  Future<void> logVideoInteraction({
    required String videoUrl,
    required String action,
  }) async {
    await _ensureInitialized();
    if (!_enabled || _analytics == null) return;
    await _analytics!.logEvent(
      name: 'video_interaction',
      parameters: {
        'video_url': videoUrl,
        'action': action,
        'timestamp': DateTime.now().toIso8601String(),
      },
    );
  }

  Future<void> logScreenView({
    required String screenName,
    Map<String, dynamic>? parameters,
  }) async {
    await _ensureInitialized();
    if (!_enabled || _analytics == null) return;
    await _analytics!.logScreenView(
      screenName: screenName,
      screenClass: screenName,
      parameters: parameters,
    );
  }

  Future<void> logPerformanceMetric({
    required String metricName,
    required int durationMs,
    Map<String, dynamic>? extraData,
  }) async {
    await _ensureInitialized();
    if (!_enabled || _analytics == null) return;
    await _analytics!.logEvent(
      name: 'performance_metric',
      parameters: {
        'metric_name': metricName,
        'duration_ms': durationMs,
        'timestamp': DateTime.now().toIso8601String(),
        if (extraData != null) ...extraData,
      },
    );
  }

  Future<void> logError({
    required String errorType,
    required String message,
    StackTrace? stackTrace,
  }) async {
    await _ensureInitialized();
    if (!_enabled || _analytics == null) return;
    await _analytics!.logEvent(
      name: 'app_error',
      parameters: {
        'error_type': errorType,
        'message': message,
        'stack_trace': stackTrace?.toString(),
        'timestamp': DateTime.now().toIso8601String(),
      },
    );
  }

  Future<void> logUserProperty({
    required String name,
    required String value,
  }) async {
    await _ensureInitialized();
    if (!_enabled || _analytics == null) return;
    await _analytics!.setUserProperty(
      name: name,
      value: value,
    );
  }

  Future<void> logFeatureUsed({
    required String feature,
    Map<String, dynamic>? parameters,
  }) async {
    await _ensureInitialized();
    if (!_enabled || _analytics == null) return;
    await _analytics!.logEvent(
      name: 'feature_used',
      parameters: {
        'feature': feature,
        'timestamp': DateTime.now().toIso8601String(),
        if (parameters != null) ...parameters,
      },
    );
  }
}
