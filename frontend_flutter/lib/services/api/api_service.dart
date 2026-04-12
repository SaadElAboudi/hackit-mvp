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
