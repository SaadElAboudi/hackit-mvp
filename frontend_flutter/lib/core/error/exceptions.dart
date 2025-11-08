import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

class AppException implements Exception {
  final String message;
  final String? code;
  final dynamic details;
  final StackTrace? stackTrace;

  AppException(
    this.message, {
    this.code,
    this.details,
    this.stackTrace,
  }) {
    _logException();
  }

  void _logException() {
    if (kReleaseMode) {
      Sentry.captureException(
        this,
        stackTrace: stackTrace,
      );
    } else {
      debugPrint('AppException: $message');
      debugPrint('Code: $code');
      debugPrint('Details: $details');
      if (stackTrace != null) {
        debugPrint('StackTrace: $stackTrace');
      }
    }
  }

  @override
  String toString() => 'AppException: $message (code: $code)';
}

class NetworkException extends AppException {
  NetworkException(
    super.message, {
    super.code,
    super.details,
    super.stackTrace,
  });
}

class ServerException extends AppException {
  ServerException(
    super.message, {
    super.code,
    super.details,
    super.stackTrace,
  });
}

class CacheException extends AppException {
  CacheException(
    super.message, {
    super.code,
    super.details,
    super.stackTrace,
  });
}

class ValidationException extends AppException {
  ValidationException(
    super.message, {
    super.code,
    super.details,
    super.stackTrace,
  });
}