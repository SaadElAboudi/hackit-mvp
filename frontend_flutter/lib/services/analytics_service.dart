import 'package:firebase_analytics/firebase_analytics.dart';

class AnalyticsService {
  static final AnalyticsService _instance = AnalyticsService._internal();
  factory AnalyticsService() => _instance;
  AnalyticsService._internal();

  late FirebaseAnalytics _analytics;
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    _analytics = FirebaseAnalytics.instance;
    _initialized = true;
  }

  Future<void> logSearch(String query) async {
    await _analytics.logSearch(searchTerm: query);
  }

  Future<void> logVideoView(String videoId, String title) async {
    await _analytics.logEvent(
      name: 'video_view',
      parameters: {
        'video_id': videoId,
        'title': title,
      },
    );
  }

  Future<void> logError(String error, {StackTrace? stackTrace}) async {
    await _analytics.logEvent(
      name: 'app_error',
      parameters: {
        'error_message': error,
        'stack_trace': stackTrace?.toString(),
        'timestamp': DateTime.now().toIso8601String(),
      },
    );
  }

  Future<void> logPerformanceMetric(String name, int durationMs) async {
    await _analytics.logEvent(
      name: 'performance_metric',
      parameters: {
        'metric_name': name,
        'duration_ms': durationMs,
        'timestamp': DateTime.now().toIso8601String(),
      },
    );
  }

  Future<void> logScreenView(String screenName) async {
    // setCurrentScreen deprecated; use logScreenView
    await _analytics.logScreenView(screenName: screenName);
  }
}
