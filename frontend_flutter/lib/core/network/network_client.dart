import 'package:dio/dio.dart';
import 'package:injectable/injectable.dart';
import '../error/exceptions.dart';
import 'package:logger/logger.dart';

@singleton
class NetworkClient {
  late final Dio _dio;
  final Logger _logger;

  NetworkClient() : _logger = Logger() {
    _dio = Dio()
      ..options = BaseOptions(
        baseUrl: 'http://localhost:3000',
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 3),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      )
      ..interceptors.addAll([
        _LoggerInterceptor(_logger),
        _ErrorInterceptor(),
      ]);
  }

  Dio get dio => _dio;
}

class _LoggerInterceptor extends Interceptor {
  final Logger logger;

  _LoggerInterceptor(this.logger);

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    logger.i('Request: ${options.method} ${options.uri}');
    logger.d('Headers: ${options.headers}');
    logger.d('Data: ${options.data}');
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    logger.i('Response: ${response.statusCode} ${response.requestOptions.uri}');
    logger.d('Data: ${response.data}');
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    logger.e('Error: ${err.message}');
    logger.e('Data: ${err.response?.data}');
    handler.next(err);
  }
}

class _ErrorInterceptor extends Interceptor {
  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    switch (err.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        throw NetworkException(
          'Connection timeout',
          code: 'TIMEOUT',
          details: err.message,
          stackTrace: err.stackTrace,
        );
      case DioExceptionType.badResponse:
        final statusCode = err.response?.statusCode;
        if (statusCode != null) {
          if (statusCode >= 500) {
            throw ServerException(
              'Server error',
              code: 'SERVER_ERROR',
              details: err.response?.data,
              stackTrace: err.stackTrace,
            );
          } else if (statusCode == 404) {
            throw ServerException(
              'Resource not found',
              code: 'NOT_FOUND',
              details: err.response?.data,
              stackTrace: err.stackTrace,
            );
          } else if (statusCode == 401) {
            throw ServerException(
              'Unauthorized',
              code: 'UNAUTHORIZED',
              details: err.response?.data,
              stackTrace: err.stackTrace,
            );
          }
        }
        throw ServerException(
          'Server error',
          code: 'UNKNOWN',
          details: err.response?.data,
          stackTrace: err.stackTrace,
        );
      default:
        throw NetworkException(
          'Network error',
          code: 'NETWORK_ERROR',
          details: err.message,
          stackTrace: err.stackTrace,
        );
    }
  }
}