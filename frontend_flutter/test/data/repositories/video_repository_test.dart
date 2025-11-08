import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:dartz/dartz.dart';
import 'package:hackit_mvp_flutter/features/search/data/repository/search_repository_impl.dart';
import 'package:hackit_mvp_flutter/data/cache/cache_manager.dart';
import 'package:hackit_mvp_flutter/services/api_service.dart';
import 'package:hackit_mvp_flutter/core/network/network_info.dart';
import 'package:hackit_mvp_flutter/data/models/video_model.dart';
import 'package:hackit_mvp_flutter/shared/domain/models/video.dart';
import 'package:hackit_mvp_flutter/core/error/failures.dart';

@GenerateMocks([ApiService, CacheManager, NetworkInfo])
void main() {
  late VideoRepositoryImpl repository;
  late MockApiService mockApiService;
  late MockCacheManager mockCacheManager;
  late MockNetworkInfo mockNetworkInfo;

  setUp(() {
    mockApiService = MockApiService();
    mockCacheManager = MockCacheManager();
    mockNetworkInfo = MockNetworkInfo();
    repository = VideoRepositoryImpl(
      mockApiService,
      mockCacheManager,
      mockNetworkInfo,
    );
  });

  group('searchVideos', () {
    const query = 'test query';
    final testVideos = [
      VideoModel(
        id: '1',
        title: 'Test Video',
        description: 'Test Description',
        thumbnailUrl: 'https://example.com/thumb.jpg',
        channelTitle: 'Test Channel',
        publishedAt: DateTime.now(),
      ),
    ];

    test('should return cached videos when available', () async {
      // arrange
      when(mockCacheManager.getSearchResult(query)).thenReturn(
        SearchResult(
          query: query,
          videoIds: ['1'],
          timestamp: DateTime.now(),
        ),
      );
      when(mockCacheManager.getVideos(['1'])).thenReturn(testVideos);

      // act
      final result = await repository.searchVideos(query);

      // assert
      expect(result, Right(testVideos));
      verify(mockCacheManager.getSearchResult(query));
      verify(mockCacheManager.getVideos(['1']));
      verifyZero(mockApiService.searchVideos(any));
    });

    test('should fetch from API when cache is empty', () async {
      // arrange
      when(mockCacheManager.getSearchResult(query)).thenReturn(null);
      when(mockNetworkInfo.isConnected).thenAnswer((_) async => true);
      when(mockApiService.searchVideos(query)).thenAnswer((_) async => testVideos);

      // act
      final result = await repository.searchVideos(query);

      // assert
      expect(result, Right(testVideos));
      verify(mockApiService.searchVideos(query));
      verify(mockCacheManager.cacheVideos(testVideos));
      verify(mockCacheManager.cacheSearchResult(any));
    });

    test('should return NetworkFailure when offline and no cache', () async {
      // arrange
      when(mockCacheManager.getSearchResult(query)).thenReturn(null);
      when(mockNetworkInfo.isConnected).thenAnswer((_) async => false);

      // act
      final result = await repository.searchVideos(query);

      // assert
      expect(result, Left(NetworkFailure()));
      verifyZero(mockApiService.searchVideos(any));
    });

    test('should return ServerFailure when API call fails', () async {
      // arrange
      when(mockCacheManager.getSearchResult(query)).thenReturn(null);
      when(mockNetworkInfo.isConnected).thenAnswer((_) async => true);
      when(mockApiService.searchVideos(query)).thenThrow(Exception());

      // act
      final result = await repository.searchVideos(query);

      // assert
      expect(result, Left(ServerFailure()));
    });
  });

  group('getVideoById', () {
    const videoId = '1';
    final testVideo = VideoModel(
      id: '1',
      title: 'Test Video',
      description: 'Test Description',
      thumbnailUrl: 'https://example.com/thumb.jpg',
      channelTitle: 'Test Channel',
      publishedAt: DateTime.now(),
    );

    test('should return cached video when available', () async {
      // arrange
      when(mockCacheManager.getVideo(videoId)).thenReturn(testVideo);

      // act
      final result = await repository.getVideoById(videoId);

      // assert
      expect(result, Right(testVideo));
      verify(mockCacheManager.getVideo(videoId));
      verifyZero(mockApiService.getVideoById(any));
    });

    test('should fetch from API when cache is empty', () async {
      // arrange
      when(mockCacheManager.getVideo(videoId)).thenReturn(null);
      when(mockNetworkInfo.isConnected).thenAnswer((_) async => true);
      when(mockApiService.getVideoById(videoId))
          .thenAnswer((_) async => testVideo);

      // act
      final result = await repository.getVideoById(videoId);

      // assert
      expect(result, Right(testVideo));
      verify(mockApiService.getVideoById(videoId));
      verify(mockCacheManager.cacheVideo(testVideo));
    });
  });
}