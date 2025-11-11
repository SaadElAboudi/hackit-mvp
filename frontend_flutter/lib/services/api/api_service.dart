import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../analytics/analytics_manager.dart';

class ApiService {
  final Dio _dio;
  final AnalyticsManager _analytics = AnalyticsManager.instance;

  /// Base URL resolution priority:
  /// 1. --dart-define=API_BASE_URL=...
  /// 2. Fallback localhost (web & native dev)
  static final String _baseUrl = (() {
    final fromDefine =
        const String.fromEnvironment('API_BASE_URL', defaultValue: '').trim();
    if (fromDefine.isNotEmpty) return fromDefine;
    // In dev we assume backend runs on 3000.
    return 'http://localhost:3000';
  })();

  String get baseUrl => _baseUrl;

  ApiService(this._dio);

  /// Convenience factory to build a default Dio client with baseUrl.
  static ApiService create() {
    final dio = Dio(BaseOptions(
      baseUrl: _baseUrl,
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 30),
    ));
    return ApiService(dio);
  }

  Future<T> _trackApiCall<T>({
    required String endpoint,
    required Future<T> Function() apiCall,
  }) async {
    final stopwatch = Stopwatch()..start();
    try {
      final result = await apiCall();
      stopwatch.stop();

      await _analytics.trackApiLatency(
        endpoint: endpoint,
        latencyMs: stopwatch.elapsedMilliseconds.toDouble(),
        isSuccess: true,
      );

      return result;
    } catch (e) {
      stopwatch.stop();

      await _analytics.trackApiLatency(
        endpoint: endpoint,
        latencyMs: stopwatch.elapsedMilliseconds.toDouble(),
        isSuccess: false,
        errorMessage: e.toString(),
      );

      rethrow;
    }
  }

  Future<Response> get(String path,
      {Map<String, dynamic>? queryParameters}) async {
    return _trackApiCall(
      endpoint: path,
      apiCall: () => _dio.get(path, queryParameters: queryParameters),
    );
  }

  Future<Response> post(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
  }) async {
    return _trackApiCall(
      endpoint: path,
      apiCall: () =>
          _dio.post(path, data: data, queryParameters: queryParameters),
    );
  }

  // ---- Lesson persistence endpoints ----
  Future<Response> generateLesson(
      {required String query,
      required String userId,
      bool useGemini = true}) async {
    return post('/api/generateLesson', data: {
      'query': query,
      'userId': userId,
      'useGemini': useGemini,
    });
  }

  Future<Response> listLessons(
      {required String userId,
      bool? favorite,
      String sort = 'createdAt',
      String order = 'desc',
      int limit = 50,
      int offset = 0}) async {
    return get('/api/lessons', queryParameters: {
      'userId': userId,
      if (favorite != null) 'favorite': favorite.toString(),
      'sort': sort,
      'order': order,
      'limit': limit.toString(),
      'offset': offset.toString(),
    });
  }

  Future<Response> setFavorite(
      {required String lessonId, required bool favorite}) async {
    return _trackApiCall(
      endpoint: '/api/lessons/:id/favorite',
      apiCall: () => _dio.patch('/api/lessons/$lessonId/favorite',
          data: {'favorite': favorite}),
    );
  }

  Future<Response> recordView({required String lessonId}) async {
    return _trackApiCall(
      endpoint: '/api/lessons/:id/view',
      apiCall: () => _dio.post('/api/lessons/$lessonId/view'),
    );
  }
}
