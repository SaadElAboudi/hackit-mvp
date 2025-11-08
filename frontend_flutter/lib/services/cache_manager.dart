import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/base_search_result.dart';

class CacheManager {
  static const String _cacheKey = 'search_cache';
  static const Duration _cacheDuration = Duration(hours: 24);
  final SharedPreferences _prefs;

  CacheManager(this._prefs);

  Future<void> cacheSearchResult(String query, BaseSearchResult result) async {
    final cache = _getCache();
    cache[query] = {
      'result': result.toMap(),
      'timestamp': DateTime.now().toIso8601String(),
    };
    await _saveCache(cache);
  }

  Future<BaseSearchResult?> getCachedResult(String query) async {
    final cache = _getCache();
    final cached = cache[query];
    if (cached == null) return null;

    final timestamp = DateTime.parse(cached['timestamp'] as String);
    if (DateTime.now().difference(timestamp) > _cacheDuration) {
      // Cache expired
      await _removeFromCache(query);
      return null;
    }

    return BaseSearchResult.fromMap(cached['result'] as Map<String, dynamic>);
  }

  Future<void> clearCache() async {
    await _prefs.remove(_cacheKey);
  }

  Map<String, dynamic> _getCache() {
    final String? cached = _prefs.getString(_cacheKey);
    if (cached == null) return {};
    return json.decode(cached) as Map<String, dynamic>;
  }

  Future<void> _saveCache(Map<String, dynamic> cache) async {
    await _prefs.setString(_cacheKey, json.encode(cache));
  }

  Future<void> _removeFromCache(String query) async {
    final cache = _getCache();
    cache.remove(query);
    await _saveCache(cache);
  }
}