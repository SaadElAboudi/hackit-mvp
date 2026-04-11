import 'dart:async';
import 'package:dio/dio.dart';

class ApiService {
  final Dio _dio;

  /// Base URL resolution priority:
  /// 1. --dart-define=API_BASE_URL=...
  /// 2. Fallback localhost (web & native dev)
  static final String _baseUrl = (() {
    final fromDefine =
        const String.fromEnvironment('API_BASE_URL', defaultValue: '').trim();
    if (fromDefine.isNotEmpty) return fromDefine;
    return 'http://localhost:3000';
  })();

  String get baseUrl => _baseUrl;
  static String get staticBaseUrl => _baseUrl;

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

  Future<Response> get(String path,
      {Map<String, dynamic>? queryParameters}) async {
    return _dio.get(path, queryParameters: queryParameters);
  }

  Future<Response> post(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
  }) async {
    return _dio.post(path, data: data, queryParameters: queryParameters);
  }

  // ---- Lesson persistence endpoints ----
  Future<Response> createLesson({
    required String userId,
    required String title,
    required List<String> steps,
    required String videoUrl,
    String? summary,
  }) async {
    return post('/api/lessons', data: {
      'userId': userId,
      'title': title,
      'steps': steps,
      'videoUrl': videoUrl,
      if (summary != null) 'summary': summary,
    });
  }

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
    return _dio
        .patch('/api/lessons/$lessonId/favorite', data: {'favorite': favorite});
  }

  Future<Response> recordView({required String lessonId}) async {
    return _dio.post('/api/lessons/$lessonId/view');
  }

  Future<Response> deleteLesson({required String lessonId}) async {
    return _dio.delete('/api/lessons/$lessonId');
  }

  /// Pings /health to wake the Render backend on cold start (fire-and-forget).
  /// Creates its own Dio with extended timeouts so the cold-start window (~60s)
  /// doesn't trip the default 20-30 s limits. All errors are swallowed.
  Future<void> pingHealth({
    Duration timeout = const Duration(seconds: 90),
  }) async {
    final warmupDio = Dio(BaseOptions(
      baseUrl: _baseUrl,
      connectTimeout: timeout,
      receiveTimeout: timeout,
    ));
    try {
      await warmupDio.get('/health');
    } catch (_) {
      // Best-effort: ignore timeouts / connection errors.
    }
  }
}
