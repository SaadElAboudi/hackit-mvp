import 'package:dartz/dartz.dart';
import 'package:injectable/injectable.dart';
import '../../../../core/error/failures.dart';
import '../../../../services/api_service.dart';
import '../../../../core/network/network_info.dart';
import '../../domain/repository/search_repository.dart';
import '../../../../shared/domain/models/video.dart';
import '../../../../data/cache/cache_manager.dart';

@Singleton(as: SearchRepository)
class SearchRepositoryImpl implements SearchRepository {
  final ApiService apiService;
  final CacheManager cacheManager;
  final NetworkInfo networkInfo;

  SearchRepositoryImpl(
    this.apiService,
    this.cacheManager,
    this.networkInfo,
  );

  @override
  Future<Either<Failure, SearchResult>> search(String query) async {
    if (await networkInfo.isConnected) {
      try {
        final result = await apiService.search(query);
        await cacheResult(query, result);
        return Right(result);
      } catch (e) {
        return Left(ServerFailure(
          message: 'Failed to search videos',
          code: 'SEARCH_FAILED',
          details: e.toString(),
        ));
      }
    } else {
      final cachedResult = await getCachedResult(query);
      if (cachedResult.isRight()) {
        final result = cachedResult.getOrElse(() => null);
        if (result != null) {
          return Right(result);
        }
      }
      return Left(NetworkFailure(
        message: 'No internet connection',
        code: 'NO_CONNECTION',
      ));
    }
  }

  @override
  Future<void> cacheResult(String query, SearchResult result) async {
    try {
      await cacheManager.saveSearchResult(query, result);
    } catch (e) {
      // Log error but don't throw
      print('Failed to cache search result: $e');
    }
  }

  @override
  Future<Either<Failure, SearchResult?>> getCachedResult(String query) async {
    try {
      final result = await cacheManager.getSearchResult(query);
      return Right(result);
    } catch (e) {
      return Left(CacheFailure(
        message: 'Failed to get cached result',
        code: 'CACHE_READ_FAILED',
        details: e.toString(),
      ));
    }
  }
}