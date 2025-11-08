import 'package:dartz/dartz.dart';
import 'package:injectable/injectable.dart';
import '../../../core/error/failures.dart';
import '../../../shared/domain/models/video.dart';
import '../repository/search_repository.dart';

@injectable
class SearchUseCase {
  final SearchRepository _repository;

  SearchUseCase(this._repository);

  Future<Either<Failure, SearchResult>> execute(String query) async {
    // Validate query
    if (query.trim().isEmpty) {
      return Left(ValidationFailure(
        message: 'Search query cannot be empty',
        code: 'EMPTY_QUERY',
      ));
    }

    if (query.trim().length < 3) {
      return Left(ValidationFailure(
        message: 'Search query must be at least 3 characters long',
        code: 'QUERY_TOO_SHORT',
      ));
    }

    // Special characters validation
    final RegExp validChars = RegExp(r'^[a-zA-Z0-9\s\-_.,!?]+$');
    if (!validChars.hasMatch(query)) {
      return Left(ValidationFailure(
        message: 'Search query contains invalid characters',
        code: 'INVALID_CHARS',
      ));
    }

    return _repository.search(query);
  }
}