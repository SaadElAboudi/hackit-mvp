import 'package:equatable/equatable.dart';

/// Base class for all failures in the application
abstract class Failure extends Equatable {
  final String message;
  final String? code;
  final dynamic details;

  const Failure(this.message, {this.code, this.details});

  @override
  List<Object?> get props => [message, code, details];
}

/// Network related failures
class NetworkFailure extends Failure {
  const NetworkFailure(super.message, {super.code, super.details});
}

/// Server related failures
class ServerFailure extends Failure {
  const ServerFailure(super.message, {super.code, super.details});
}

/// Cache related failures
class CacheFailure extends Failure {
  const CacheFailure(super.message, {super.code, super.details});
}

/// Search related failures
class SearchFailure extends Failure {
  const SearchFailure(super.message, {super.code, super.details});
}

/// Video related failures
class VideoFailure extends Failure {
  const VideoFailure(super.message, {super.code, super.details});
}

/// Validation related failures
class ValidationFailure extends Failure {
  const ValidationFailure(super.message, {super.code, super.details});
}