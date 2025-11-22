import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/history_favorites.dart';
import '../services/history_favorites_repository.dart';
import 'lessons_provider.dart';

class HistoryFavoritesProvider extends ChangeNotifier {
  Future<void> removeHistory(String id) async {
    await _repo.removeHistory(id);
    _history = _repo.loadHistory();
    notifyListeners();
  }

  final HistoryFavoritesRepository _repo;
  List<SearchEntry> _history = [];
  List<FavoriteItem> _favorites = [];
  LessonsProvider? _lessons; // optional link for migration

  HistoryFavoritesProvider(SharedPreferences prefs)
      : _repo = HistoryFavoritesRepository(prefs) {
    _load();
  }

  List<SearchEntry> get history => _history;
  List<FavoriteItem> get favorites => _favorites;
  bool isFavorite(String id) => _favorites.any((f) => f.id == id);

  void linkLessons(LessonsProvider lessons) {
    _lessons = lessons;
    // Sync remote favorites into local store if not yet present
    final remoteFavs = lessons.lessons.where((l) => l.favorite).toList();
    bool changed = false;
    for (final l in remoteFavs) {
      if (!_favorites.any((f) => f.id == l.videoUrl)) {
        _favorites.insert(
          0,
          FavoriteItem(
            id: l.videoUrl,
            title: l.title,
            videoUrl: l.videoUrl,
            addedAt: DateTime.now(),
          ),
        );
        changed = true;
      }
    }
    if (changed) {
      // Persist merged favorites
      _repo.saveFavorites(_favorites);
      notifyListeners();
    }
  }

  void _load() {
    _history = _repo.loadHistory();
    _favorites = _repo.loadFavorites();
  }

  Future<void> addHistory({
    required String query,
    String? title,
    String? videoUrl,
    String? source,
    int? resultCount,
    int? durationMs,
  }) async {
    final entry = SearchEntry(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      query: query,
      title: title,
      videoUrl: videoUrl,
      source: source,
      createdAt: DateTime.now(),
      resultCount: resultCount,
      durationMs: durationMs,
    );
    await _repo.addHistory(entry);
    _history = _repo.loadHistory();
    notifyListeners();
  }

  Future<void> toggleFavorite({
    required String videoId,
    required String title,
    String? channel,
    String? videoUrl,
  }) async {
    if (isFavorite(videoId)) {
      await _repo.removeFavorite(videoId);
    } else {
      await _repo.addFavorite(FavoriteItem(
        id: videoId,
        title: title,
        channel: channel,
        videoUrl: videoUrl,
        addedAt: DateTime.now(),
      ));
    }
    _favorites = _repo.loadFavorites();
    // Propagate to lessons if linked (mark favorite on existing lesson matching videoUrl)
    if (_lessons != null && videoUrl != null) {
      for (final l in _lessons!.lessons) {
        if (l.videoUrl == videoId) {
          _lessons!.toggleFavorite(l.id);
          break;
        }
      }
    }
    notifyListeners();
  }
}
