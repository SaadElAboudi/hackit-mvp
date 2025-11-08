import 'package:dartz/dartz.dart';
import 'package:injectable/injectable.dart';
import '../../domain/repositories/search_repository.dart';
import '../../../../core/error/failures.dart';
import '../../../../core/network/network_info.dart';
import '../../../../data/cache/cache_manager.dart';
import '../../../../services/api_service.dart';
import '../../../../shared/domain/models/video.dart';

@Singleton(as: SearchRepository)
class SearchRepositoryImpl implements SearchRepository {
  final ApiService _apiService;
  final CacheManager _cacheManager;
  final NetworkInfo _networkInfo;

  SearchRepositoryImpl(
    this._apiService,
    this._cacheManager,
    this._networkInfo,
  );

  @override
  Future<Either<Failure, SearchResult>> search(String query) async {
    try {
      if (await _networkInfo.isConnected) {
        try {
          final result = await _apiService.searchVideos(query);
          await _cacheResult(query, result);
          return Right(result);
        } catch (e) {
          final cachedResult = await _getCachedResult(query);
          return cachedResult.fold(
            (failure) => Left(ServerFailure(
              message: 'Failed to search videos and no cache available',
              code: 'SEARCH_FAILED',
              details: e.toString(),
            )),
            (result) => Right(result),
          );
        }
      } else {
        final cachedResult = await _getCachedResult(query);
        return cachedResult.fold(
          (failure) => Left(NetworkFailure(
            message: 'No internet connection and no cache available',
            code: 'NO_CONNECTION',
          )),
          (result) => Right(result),
        );
      }
    } catch (e) {
      return Left(ServerFailure(
        message: 'Unexpected error during search',
        code: 'UNEXPECTED_ERROR',
        details: e.toString(),
      ));
    }
  }

  Future<void> _cacheResult(String query, SearchResult result) async {
    try {
      await _cacheManager.saveSearchResult(query, result);
    } catch (e) {
      // Log error but don't throw
      print('Failed to cache search result: $e');
    }
  }

  Future<Either<Failure, SearchResult>> _getCachedResult(String query) async {
    try {
      final result = await _cacheManager.getSearchResult(query);
      if (result != null) {
        return Right(result);
      }
      return Left(CacheFailure(
        message: 'No cached result found',
        code: 'CACHE_MISS',
      ));
    } catch (e) {
      return Left(CacheFailure(
        message: 'Failed to get cached result',
        code: 'CACHE_READ_FAILED',
        details: e.toString(),
      ));
    }
  }
}