import 'package:shared_preferences/shared_preferences.dart';
import 'package:injectable/injectable.dart';
import 'package:flutter/foundation.dart';

@singleton
class CacheManager {
  late SharedPreferences _prefs;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  Future<T?> get<T>(String key) async {
    try {
      return _prefs.get(key) as T?;
    } catch (e) {
      debugPrint('Error getting cached value: $e');
      return null;
    }
  }

  Future<void> put<T>(String key, T value) async {
    try {
      if (value is String) {
        await _prefs.setString(key, value);
      } else if (value is int) {
        await _prefs.setInt(key, value);
      } else if (value is double) {
        await _prefs.setDouble(key, value);
      } else if (value is bool) {
        await _prefs.setBool(key, value);
      } else if (value is List<String>) {
        await _prefs.setStringList(key, value);
      }
    } catch (e) {
      debugPrint('Error caching value: $e');
    }
  }

  Future<void> delete(String key) async {
    try {
      await _prefs.remove(key);
    } catch (e) {
      debugPrint('Error deleting cached value: $e');
    }
  }

  Future<void> clear() async {
    try {
      await _prefs.clear();
    } catch (e) {
      debugPrint('Error clearing cache: $e');
    }
  }
}
