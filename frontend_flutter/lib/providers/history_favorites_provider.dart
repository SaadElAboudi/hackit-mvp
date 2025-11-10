import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/history_favorites.dart';
import '../services/history_favorites_repository.dart';

class HistoryFavoritesProvider extends ChangeNotifier {
  final HistoryFavoritesRepository _repo;
  List<SearchEntry> _history = [];
  List<FavoriteItem> _favorites = [];

  HistoryFavoritesProvider(SharedPreferences prefs)
      : _repo = HistoryFavoritesRepository(prefs) {
    _load();
  }

  List<SearchEntry> get history => _history;
  List<FavoriteItem> get favorites => _favorites;
  bool isFavorite(String id) => _favorites.any((f) => f.id == id);

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
    notifyListeners();
  }
}
