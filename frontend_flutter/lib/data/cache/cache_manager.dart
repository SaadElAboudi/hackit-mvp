import 'package:hive_flutter/hive_flutter.dart';
import 'package:injectable/injectable.dart';
import '../../shared/domain/models/video.dart';

@singleton
class CacheManager {
  static const String videoBoxName = 'videos';
  static const String searchResultsBoxName = 'searchResults';

  late Box<Video> videoBox;
  late Box<SearchResult> searchResultBox;
  final Duration _cacheExpiry = const Duration(hours: 24);

  @postConstruct
  Future<void> init() async {
    await Hive.initFlutter();

    // Register adapters
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(VideoAdapter());
    }
    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(SearchResultAdapter());
    }

    await _initBoxes();
  }

  Future<void> _initBoxes() async {
    videoBox = await Hive.openBox<Video>(videoBoxName);
    searchResultBox = await Hive.openBox<SearchResult>(searchResultsBoxName);
  }

  // Video methods
  Future<void> saveVideo(Video video) async {
    await videoBox.put(video.id, video);
  }

  Future<void> saveVideos(List<Video> videos) async {
    final Map<String, Video> videosMap = {
      for (var video in videos) video.id: video
    };
    await videoBox.putAll(videosMap);
  }

  Video? getVideo(String id) {
    return videoBox.get(id);
  }

  List<Video> getVideos(List<String> ids) {
    return ids.map((id) => videoBox.get(id)).whereType<Video>().toList();
  }

  // Core methods
  Future<void> saveSearchResult(SearchResult result) async {
    final now = DateTime.now();
    // Update metadata with timestamp
    final updatedResult = result.copyWith(
      metadata: {
        ...result.metadata,
        'timestamp': now.toIso8601String(),
      },
    );
    await searchResultBox.put(updatedResult.query, updatedResult);
  }

  Future<SearchResult?> getSearchResult(String query) async {
    final result = searchResultBox.get(query);
    if (result == null) return null;

    // Check if result is expired
    if (result.metadata.containsKey('timestamp')) {
      final timestamp = DateTime.tryParse(result.metadata['timestamp']);
      if (timestamp != null &&
          DateTime.now().difference(timestamp) >= _cacheExpiry) {
        await searchResultBox.delete(query);
        return null;
      }
    }
    return result;
  }

  Future<void> saveVideo(Video video) async {
    await videoBox.put(video.id, video);
  }

  Future<Video?> getVideo(String id) async {
    return videoBox.get(id);
  }

  // Cleanup methods
  Future<void> clearOldCache() async {
    final now = DateTime.now();

    // Remove expired search results
    final allResults = searchResultBox.values.toList();
    for (final result in allResults) {
      final metadata = result.metadata;
      if (metadata.containsKey('timestamp')) {
        final timestamp = DateTime.tryParse(metadata['timestamp']);
        if (timestamp != null &&
            now.difference(timestamp) >= _cacheExpiry) {
          await searchResultBox.delete(result.query);
        }
      }
    }

    // Remove unreferenced videos
    final activeVideoIds = searchResultBox.values
        .expand((result) => result.videos)
        .map((video) => video.id)
        .toSet();
    
    final storedVideoIds = videoBox.keys.cast<String>().toSet();
    final videosToDelete = storedVideoIds.difference(activeVideoIds);
    
    for (final id in videosToDelete) {
      await videoBox.delete(id);
    }
  }

  Future<void> clearCache() async {
    await videoBox.clear();
    await searchResultBox.clear();
  }
}