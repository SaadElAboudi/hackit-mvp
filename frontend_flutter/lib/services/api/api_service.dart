import 'dart:async';
import 'package:dio/dio.dart';
import '../analytics/analytics_manager.dart';

class ApiService {
  final Dio _dio;
  final AnalyticsManager _analytics = AnalyticsManager.instance;

  ApiService(this._dio);

  /// Convenience factory to build a default Dio client.
  static ApiService create() {
    final dio = Dio(BaseOptions(
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

  Future<dynamic> get(String path,
      {Map<String, dynamic>? queryParameters}) async {
    return _trackApiCall(
      endpoint: path,
      apiCall: () => _dio.get(path, queryParameters: queryParameters),
    );
  }

  Future<dynamic> post(
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
}
