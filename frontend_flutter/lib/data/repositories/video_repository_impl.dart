import 'package:injectable/injectable.dart';
import 'package:dartz/dartz.dart';
import '../../domain/repositories/video_repository.dart';
import '../models/video_model.dart';
import '../models/search_result.dart';
import '../core/failure.dart';
import '../cache/cache_manager.dart';
import '../services/api_service.dart';
import '../core/network_info.dart';

@Singleton(as: VideoRepository)
class VideoRepositoryImpl implements VideoRepository {
  final ApiService _apiService;
  final CacheManager _cacheManager;
  final NetworkInfo _networkInfo;

  VideoRepositoryImpl(
    this._apiService,
    this._cacheManager,
    this._networkInfo,
  );

  @override
  Future<Either<Failure, List<VideoModel>>> searchVideos(String query) async {
    try {
      // Vérifier d'abord le cache
      final cachedResult = _cacheManager.getSearchResult(query);
      final cachedVideos = _cacheManager.getVideos(cachedResult.videoIds);
      if (cachedVideos.isNotEmpty) {
        return Right(cachedVideos);
      }
    
      // Si pas de cache valide et pas de connexion
      if (!await _networkInfo.isConnected) {
        return Left(NetworkFailure());
      }

      // Faire la requête API
      final videos = await _apiService.searchVideos(query);
      
      // Mettre en cache les résultats
      await _cacheManager.cacheVideos(videos);
      await _cacheManager.cacheSearchResult(
        SearchResult(
          query: query,
          videoIds: videos.map((v) => v.id).toList(),
          timestamp: DateTime.now(),
        ),
      );

      return Right(videos);
    } catch (e) {
      return Left(ServerFailure());
    }
  }

  @override
  Future<Either<Failure, VideoModel>> getVideoById(String id) async {
    try {
      // Vérifier d'abord le cache
      final cachedVideo = _cacheManager.getVideo(id);
      return Right(cachedVideo);
    
      // Si pas de cache et pas de connexion
      if (!await _networkInfo.isConnected) {
        return Left(NetworkFailure());
      }

      // Faire la requête API
      final video = await _apiService.getVideoById(id);
      
      // Mettre en cache
      await _cacheManager.cacheVideo(video);

      return Right(video);
    } catch (e) {
      return Left(ServerFailure());
    }
  }

  @override
  Future<Either<Failure, List<VideoModel>>> getVideosByIds(
    List<String> ids,
  ) async {
    try {
      // Vérifier d'abord le cache
      final cachedVideos = _cacheManager.getVideos(ids);
      final missingIds = ids
          .where((id) => !cachedVideos.any((v) => v.id == id))
          .toList();

      if (missingIds.isEmpty) {
        return Right(cachedVideos);
      }

      // Si des vidéos manquent et pas de connexion
      if (!await _networkInfo.isConnected) {
        return Left(NetworkFailure());
      }

      // Récupérer les vidéos manquantes
      final newVideos = await _apiService.getVideosByIds(missingIds);
      
      // Mettre en cache
      await _cacheManager.cacheVideos(newVideos);

      // Combiner les résultats
      return Right([...cachedVideos, ...newVideos]);
    } catch (e) {
      return Left(ServerFailure());
    }
  }

  @override
  Future<Either<Failure, List<SearchResult>>> getSearchHistory() async {
    try {
      final results = _cacheManager.searchResultBox.values.toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return Right(results);
    } catch (e) {
      return Left(CacheFailure());
    }
  }

  @override
  Future<Either<Failure, void>> clearSearchHistory() async {
    try {
      await _cacheManager.clearAll();
      return const Right(null);
    } catch (e) {
      return Left(CacheFailure());
    }
  }
}