import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';
import 'session_analytics.dart';
import 'search_analytics.dart';
import 'performance_analytics.dart';

class AnalyticsManager {
  static final AnalyticsManager instance = AnalyticsManager._();
  final FirebaseAnalytics _analytics = FirebaseAnalytics.instance;
  DateTime _sessionStartTime = DateTime.now();

  AnalyticsManager._();

  Future<void> initializeAnalytics() async {
    _sessionStartTime = DateTime.now();
    await _analytics.logSessionStart();
    await _logAppStart();
  }

  Future<void> trackScreenView({
    required String screenName,
    String? screenClass,
  }) async {
    await _analytics.logScreenView(
      screenName: screenName,
      screenClass: screenClass,
    );
  }

  Future<void> _logAppStart() async {
    final endTime = DateTime.now();
    final startupTime = endTime.difference(_sessionStartTime).inMilliseconds.toDouble();
    
    await _analytics.logAppStartup(
      coldStartMs: startupTime,
      isColdStart: true,
    );
  }

  // Search Analytics
  Future<void> trackSearch({
    required String query,
    required bool isSuccess,
    String? errorMessage,
    int? resultCount,
    double? latency,
  }) async {
    await _analytics.logSearch(
      query: query,
      isSuccess: isSuccess,
      errorMessage: errorMessage,
      resultCount: resultCount,
      latency: latency,
    );
  }

  Future<void> trackSearchResultClick({
    required String query,
    required String videoId,
    required int position,
    String? videoTitle,
  }) async {
    await _analytics.logSearchResultClick(
      query: query,
      videoId: videoId,
      position: position,
      videoTitle: videoTitle,
    );
  }

  // Performance Analytics
  Future<void> trackApiLatency({
    required String endpoint,
    required double latencyMs,
    bool isSuccess = true,
    String? errorMessage,
  }) async {
    await _analytics.logApiLatency(
      endpoint: endpoint,
      latencyMs: latencyMs,
      isSuccess: isSuccess,
      errorMessage: errorMessage,
    );
  }

  void startPerformanceMonitoring() {
    // Start periodic memory usage tracking
    Future.delayed(const Duration(minutes: 1), _trackMemoryUsage);
  }

  Future<void> _trackMemoryUsage() async {
    if (!kReleaseMode) return;

    try {
      // This is a simplified version. In production, you'd want to use
      // a proper memory tracking package
      await _analytics.logMemoryUsage(
        memoryMb: 0, // Replace with actual memory usage
        screen: 'current_screen',
      );
    } finally {
      // Schedule next tracking
      Future.delayed(const Duration(minutes: 1), _trackMemoryUsage);
    }
  }

  Future<void> trackError({
    required String errorType,
    required String message,
    StackTrace? stackTrace,
  }) async {
    await _analytics.logEvent(
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