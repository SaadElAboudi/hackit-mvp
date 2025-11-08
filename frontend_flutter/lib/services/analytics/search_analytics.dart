import 'package:firebase_analytics/firebase_analytics.dart';

extension SearchAnalytics on FirebaseAnalytics {
  Future<void> logSearch({
    required String query,
    required bool isSuccess,
    String? errorMessage,
    int? resultCount,
    double? latency,
  }) async {
    await logEvent(
      name: 'search',
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

  Future<void> logSearchResultClick({
    required String query,
    required String videoId,
    required int position,
    String? videoTitle,
  }) async {
    await logEvent(
      name: 'search_result_click',
      parameters: {
        'query': query,
        'video_id': videoId,
        'position': position,
        'video_title': videoTitle ?? '',
      },
    );
  }

  Future<void> logSearchFilters({
    required String query,
    Map<String, dynamic> filters = const {},
  }) async {
    await logEvent(
      name: 'search_filters_applied',
      parameters: {
        'query': query,
        'filters': filters.toString(),
      },
    );
  }
}