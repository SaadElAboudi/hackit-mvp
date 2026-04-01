import 'package:injectable/injectable.dart';
import 'package:dartz/dartz.dart';
import '../../domain/repositories/video_repository.dart';
import '../models/video_model.dart';
import '../models/search_result.dart';
import '../core/failure.dart';
import '../cache/cache_manager.dart';
import '../../services/api_service.dart';
import '../core/network_info.dart';
import '../../shared/domain/models/video.dart' as shared;

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

  VideoModel _toVideoModel(shared.Video video) {
    return VideoModel(
      id: video.id,
      title: video.title,
      description: video.description,
      thumbnailUrl: video.thumbnailUrl,
      channelTitle: video.channelTitle,
      publishedAt: video.publishedAt ?? DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  shared.Video _toSharedVideo(VideoModel video, {String? videoUrl}) {
    return shared.Video(
      id: video.id,
      title: video.title,
      description: video.description,
      thumbnailUrl: video.thumbnailUrl,
      videoUrl: videoUrl ?? 'https://www.youtube.com/watch?v=${video.id}',
      channelTitle: video.channelTitle,
      publishedAt: video.publishedAt,
    );
  }

  String _extractVideoId(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return '';
    if (uri.host.contains('youtu.be')) {
      return uri.pathSegments.isNotEmpty ? uri.pathSegments.first : '';
    }
    return uri.queryParameters['v'] ?? '';
  }

  SearchResult _toSearchResult(shared.SearchResult result) {
    final tsRaw = result.metadata['timestamp']?.toString();
    final timestamp = DateTime.tryParse(tsRaw ?? '') ?? DateTime.now();
    return SearchResult(
      query: result.query,
      videoIds: result.videos.map((v) => v.id).toList(),
      timestamp: timestamp,
    );
  }

  @override
  Future<Either<Failure, List<VideoModel>>> searchVideos(String query) async {
    try {
      final cachedResult = await _cacheManager.getSearchResult(query);
      if (cachedResult != null && cachedResult.videos.isNotEmpty) {
        return Right(cachedResult.videos.map(_toVideoModel).toList());
      }

      if (!await _networkInfo.isConnected) {
        return Left(NetworkFailure());
      }

      final result = await _apiService.searchVideos(query);
      final videoId = _extractVideoId(result.videoUrl);
      final video = VideoModel(
        id: videoId.isNotEmpty ? videoId : result.videoUrl,
        title: result.title,
        description: result.summary ?? result.steps.join('\n'),
        thumbnailUrl: '',
        channelTitle: result.source,
        publishedAt: DateTime.now(),
      );

      final sharedVideo = _toSharedVideo(video, videoUrl: result.videoUrl);
      await _cacheManager.saveVideos([sharedVideo]);
      await _cacheManager.saveSearchResult(
        shared.SearchResult(
          query: query,
          videos: [sharedVideo],
          steps: result.steps,
          summary: result.summary,
          metadata: {'timestamp': DateTime.now().toIso8601String()},
        ),
      );

      return Right([video]);
    } on ApiException {
      return Left(ServerFailure());
    } catch (e) {
      return Left(ServerFailure());
    }
  }

  @override
  Future<Either<Failure, VideoModel>> getVideoById(String id) async {
    try {
      final cachedVideo = await _cacheManager.getVideo(id);
      if (cachedVideo != null) {
        return Right(_toVideoModel(cachedVideo));
      }

      if (!await _networkInfo.isConnected) {
        return Left(NetworkFailure());
      }

      // No dedicated endpoint in current API. Use search fallback and ensure id match.
      final result = await _apiService.searchVideos(id);
      final foundId = _extractVideoId(result.videoUrl);
      if (foundId.isEmpty || foundId != id) {
        return Left(ServerFailure());
      }
      final video = VideoModel(
        id: foundId,
        title: result.title,
        description: result.summary ?? result.steps.join('\n'),
        thumbnailUrl: '',
        channelTitle: result.source,
        publishedAt: DateTime.now(),
      );
      await _cacheManager.saveVideo(_toSharedVideo(video, videoUrl: result.videoUrl));
      return Right(video);
    } on ApiException {
      return Left(ServerFailure());
    } catch (e) {
      return Left(ServerFailure());
    }
  }

  @override
  Future<Either<Failure, List<VideoModel>>> getVideosByIds(
    List<String> ids,
  ) async {
    try {
      final cachedVideos = _cacheManager.getVideos(ids);
      final cachedMap = {for (final v in cachedVideos) v.id: v};
      final missingIds = ids
          .where((id) => !cachedMap.containsKey(id))
          .toList();

      if (missingIds.isEmpty) {
        return Right(cachedVideos.map(_toVideoModel).toList());
      }

      if (!await _networkInfo.isConnected) {
        return Left(NetworkFailure());
      }

      final fetched = <VideoModel>[];
      for (final id in missingIds) {
        final one = await getVideoById(id);
        one.fold((_) {}, (video) => fetched.add(video));
      }

      await _cacheManager.saveVideos(fetched.map(_toSharedVideo).toList());

      final all = <VideoModel>[
        ...cachedVideos.map(_toVideoModel),
        ...fetched,
      ];
      return Right(all);
    } on ApiException {
      return Left(ServerFailure());
    } catch (e) {
      return Left(ServerFailure());
    }
  }

  @override
  Future<Either<Failure, List<SearchResult>>> getSearchHistory() async {
    try {
      final results = _cacheManager.searchResultBox.values.toList()
        ..sort((a, b) {
          final aTs = DateTime.tryParse(a.metadata['timestamp']?.toString() ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
          final bTs = DateTime.tryParse(b.metadata['timestamp']?.toString() ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
          return bTs.compareTo(aTs);
        });
      return Right(results.map(_toSearchResult).toList());
    } catch (e) {
      return Left(CacheFailure());
    }
  }

  @override
  Future<Either<Failure, void>> clearSearchHistory() async {
    try {
      await _cacheManager.clearCache();
      return const Right(null);
    } catch (e) {
      return Left(CacheFailure());
    }
  }
}