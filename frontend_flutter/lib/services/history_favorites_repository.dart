import 'package:shared_preferences/shared_preferences.dart';
import '../models/history_favorites.dart';

/// Repository handling local-first storage for search history & favorites.
/// Uses SharedPreferences across mobile/web; keys are prefixed with hackit:v1.
class HistoryFavoritesRepository {
  static const _historyKey = 'hackit:v1:history';
  static const _favoritesKey = 'hackit:v1:favorites';
  static const maxHistory = 50;
  static const maxFavorites = 50;

  final SharedPreferences prefs;

  HistoryFavoritesRepository(this.prefs);

  List<SearchEntry> loadHistory() {
    final raw = prefs.getStringList(_historyKey) ?? const [];
    return raw.map((e) => SearchEntry.fromJson(e)).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  List<FavoriteItem> loadFavorites() {
    final raw = prefs.getStringList(_favoritesKey) ?? const [];
    return raw.map((e) => FavoriteItem.fromJson(e)).toList()
      ..sort((a, b) => b.addedAt.compareTo(a.addedAt));
  }

  Future<void> saveHistory(List<SearchEntry> entries) async {
    // prune extra beyond maxHistory (LRU: keep most recent by createdAt desc)
    final sorted = [...entries]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final pruned = sorted.take(maxHistory).toList();
    await prefs.setStringList(
        _historyKey, pruned.map((e) => e.toJson()).toList());
  }

  Future<void> saveFavorites(List<FavoriteItem> items) async {
    final sorted = [...items]..sort((a, b) => b.addedAt.compareTo(a.addedAt));
    final pruned = sorted.take(maxFavorites).toList();
    await prefs.setStringList(
        _favoritesKey, pruned.map((e) => e.toJson()).toList());
  }

  Future<void> addHistory(SearchEntry entry) async {
    final current = loadHistory();
    current.insert(0, entry);
    await saveHistory(current);
  }

  Future<void> addFavorite(FavoriteItem item) async {
    final current = loadFavorites();
    if (current.any((f) => f.id == item.id)) return; // ignore duplicate
    current.insert(0, item);
    await saveFavorites(current);
  }

  Future<void> removeFavorite(String id) async {
    final current = loadFavorites().where((f) => f.id != id).toList();
    await saveFavorites(current);
  }

  bool isFavorite(String id) => loadFavorites().any((f) => f.id == id);
}
