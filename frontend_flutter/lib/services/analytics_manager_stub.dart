import '../models/base_search_result.dart';

class AnalyticsManager {
  static final AnalyticsManager _instance = AnalyticsManager._internal();
  factory AnalyticsManager() => _instance;

  AnalyticsManager._internal();

  Future<void> logSearch({
    required String query,
    required bool isSuccess,
    String? errorMessage,
  }) async {}

  Future<void> logSearchResult({
    required BaseSearchResult result,
    required int searchDurationMs,
  }) async {}

  Future<void> logVideoInteraction({
    required String videoUrl,
    required String action,
  }) async {}

  Future<void> logScreenView({
    required String screenName,
    Map<String, dynamic>? parameters,
  }) async {}

  Future<void> logPerformanceMetric({
    required String metricName,
    required int durationMs,
    Map<String, dynamic>? extraData,
  }) async {}

  Future<void> logError({
    required String errorType,
    required String message,
    StackTrace? stackTrace,
  }) async {}

  Future<void> logUserProperty({
    required String name,
    required String value,
  }) async {}

  Future<void> logFeatureUsed({
    required String feature,
    Map<String, dynamic>? parameters,
  }) async {}
}
