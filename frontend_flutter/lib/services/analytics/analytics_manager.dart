import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';

// Lightweight facade to avoid hard dependency on Firebase initialization in tests
abstract class Analytics {
  Future<void> logEvent(
      {required String name, Map<String, Object?>? parameters});
  Future<void> logScreenView({required String screenName, String? screenClass});
  Future<void> logSessionStart();
  Future<void> logAppStartup(
      {required double coldStartMs, required bool isColdStart});
  Future<void> logApiLatency(
      {required String endpoint,
      required double latencyMs,
      bool isSuccess,
      String? errorMessage});
  Future<void> logSessionDuration({required int durationSeconds});
}

class _FirebaseAnalyticsAdapter implements Analytics {
  FirebaseAnalytics get _fa => FirebaseAnalytics.instance;

  @override
  Future<void> logEvent(
      {required String name, Map<String, Object?>? parameters}) {
    return _fa.logEvent(name: name, parameters: parameters);
  }

  @override
  Future<void> logScreenView(
      {required String screenName, String? screenClass}) {
    return _fa.logEvent(name: 'screen_view', parameters: {
      'screen_name': screenName,
      'screen_class': screenClass ?? '',
    });
  }

  @override
  Future<void> logSessionStart() {
    return _fa.logEvent(name: 'session_start', parameters: {
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  @override
  Future<void> logAppStartup(
      {required double coldStartMs, required bool isColdStart}) {
    return _fa.logEvent(name: 'app_startup', parameters: {
      'duration_ms': coldStartMs,
      'is_cold_start': isColdStart,
    });
  }

  @override
  Future<void> logApiLatency(
      {required String endpoint,
      required double latencyMs,
      bool isSuccess = true,
      String? errorMessage}) {
    return _fa.logEvent(name: 'api_latency', parameters: {
      'endpoint': endpoint,
      'latency_ms': latencyMs,
      'success': isSuccess,
      'error_message': errorMessage ?? '',
    });
  }

  @override
  Future<void> logSessionDuration({required int durationSeconds}) {
    return _fa.logEvent(name: 'session_duration', parameters: {
      'duration_seconds': durationSeconds,
    });
  }
}

class _NoopAnalytics implements Analytics {
  @override
  Future<void> logAppStartup(
      {required double coldStartMs, required bool isColdStart}) async {}
  @override
  Future<void> logApiLatency(
      {required String endpoint,
      required double latencyMs,
      bool isSuccess = true,
      String? errorMessage}) async {}
  @override
  Future<void> logEvent(
      {required String name, Map<String, Object?>? parameters}) async {}
  @override
  Future<void> logScreenView(
      {required String screenName, String? screenClass}) async {}
  @override
  Future<void> logSessionStart() async {}
  @override
  Future<void> logSessionDuration({required int durationSeconds}) async {}
}

class AnalyticsManager {
  static final AnalyticsManager instance = AnalyticsManager._();
  Analytics? _analytics;
  DateTime _sessionStartTime = DateTime.now();

  AnalyticsManager._();

  Analytics get _a {
    // Lazy init; if Firebase isn't available (tests), fall back to noop
    return _analytics ??= _tryCreateAdapter();
  }

  Analytics _tryCreateAdapter() {
    try {
      // Touching FirebaseAnalytics.instance can throw if Firebase isn't initialized
      // Adapter defers to Firebase under the hood
      return _FirebaseAnalyticsAdapter();
    } catch (_) {
      return _NoopAnalytics();
    }
  }

  Future<void> initializeAnalytics() async {
    _sessionStartTime = DateTime.now();
    await _a.logSessionStart();
    await _logAppStart();
  }

  Future<void> trackScreenView({
    required String screenName,
    String? screenClass,
  }) async {
    await _a.logScreenView(screenName: screenName, screenClass: screenClass);
  }

  Future<void> _logAppStart() async {
    final endTime = DateTime.now();
    final startupTime =
        endTime.difference(_sessionStartTime).inMilliseconds.toDouble();

    await _a.logAppStartup(
      coldStartMs: startupTime,
      isColdStart: true,
    );
  }

  Future<void> disposeSession() async {
    final seconds = DateTime.now().difference(_sessionStartTime).inSeconds;
    await _a.logSessionDuration(durationSeconds: seconds);
  }

  // Search Analytics
  Future<void> trackSearch({
    required String query,
    required bool isSuccess,
    String? errorMessage,
    int? resultCount,
    double? latency,
  }) async {
    // Use a custom event name to avoid conflicts with FirebaseAnalytics built-in logSearch signature.
    await _a.logEvent(
      name: 'app_search',
      parameters: {
        'query': query,
        'success': isSuccess,
        'error_message': errorMessage ?? '',
        'result_count': resultCount ?? 0,
        'latency_ms': latency ?? 0.0,
        'timestamp': DateTime.now().toIso8601String(),
      },
    );
  }

  Future<void> trackSearchResultClick({
    required String query,
    required String videoId,
    required int position,
    String? videoTitle,
  }) async {
    await _a.logEvent(
      name: 'app_search_result_click',
      parameters: {
        'query': query,
        'video_id': videoId,
        'position': position,
        'video_title': videoTitle ?? '',
        'timestamp': DateTime.now().toIso8601String(),
      },
    );
  }

  // Performance Analytics
  Future<void> trackApiLatency({
    required String endpoint,
    required double latencyMs,
    bool isSuccess = true,
    String? errorMessage,
  }) async {
    await _a.logApiLatency(
      endpoint: endpoint,
      latencyMs: latencyMs,
      isSuccess: isSuccess,
      errorMessage: errorMessage,
    );
  }

  void startPerformanceMonitoring() {
    // Avoid scheduling timers in tests / debug to prevent pending timer test failures
    if (kReleaseMode) {
      Future.delayed(const Duration(minutes: 1), _trackMemoryUsage);
    }
  }

  Future<void> _trackMemoryUsage() async {
    if (!kReleaseMode) return; // Extra guard

    try {
      // This is a simplified version. In production, you'd want to use
      // a proper memory tracking package
      await _a.logEvent(name: 'memory_usage', parameters: {
        'memory_mb': 0,
        'screen': 'current_screen',
      });
    } finally {
      // Schedule next tracking
      if (kReleaseMode) {
        Future.delayed(const Duration(minutes: 1), _trackMemoryUsage);
      }
    }
  }

  Future<void> trackError({
    required String errorType,
    required String message,
    StackTrace? stackTrace,
  }) async {
    await _a.logEvent(
      name: 'app_error',
      parameters: {
        'error_type': errorType,
        'message': message,
        'stack_trace': stackTrace?.toString() ?? '',
        'timestamp': DateTime.now().toIso8601String(),
      },
    );
  }
}
