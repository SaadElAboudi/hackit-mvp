import 'package:dartz/dartz.dart';
import '../../../core/error/failures.dart';
import '../../../shared/domain/models/video.dart';

abstract class SearchRepository {
  Future<Either<Failure, SearchResult>> search(String query);
  Future<void> cacheResult(String query, SearchResult result);
  Future<Either<Failure, SearchResult?>> getCachedResult(String query);
}