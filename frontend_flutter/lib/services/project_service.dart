import 'dart:math';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Manages the stable per-device identity, display name and personal Gemini
/// API key. Nothing here is ever sent to the backend.
class ProjectService {
  static const _userIdKey = 'hackit:v1:userId';
  static const _displayNameKey = 'hackit:v1:displayName';
  static const _geminiKeyKey = 'hackit:v1:geminiKey';

  static String? _userId;
  static String? _displayName;
  static String? _geminiKey;

  static String? get currentUserId => _userId;
  static String? get currentDisplayName => _displayName;

  /// The user's personal Gemini API key, stored only in SharedPreferences.
  /// Never transmitted to the backend.
  static String? get geminiKey => _geminiKey;

  /// True only when both name and key are set — onboarding is complete.
  static bool get isOnboarded =>
      _displayName != null &&
      _displayName!.isNotEmpty &&
      _geminiKey != null &&
      _geminiKey!.isNotEmpty;

  static Future<void> init() async {
    if (_userId != null) return;
    final prefs = GetIt.instance<SharedPreferences>();
    var id = prefs.getString(_userIdKey);
    if (id == null) {
      final ts = DateTime.now().millisecondsSinceEpoch;
      final salt = _randomSalt(6);
      id = 'u_${ts}_$salt';
      await prefs.setString(_userIdKey, id);
    }
    _userId = id;
    _displayName = prefs.getString(_displayNameKey);
    _geminiKey = prefs.getString(_geminiKeyKey);
  }

  static Future<void> setDisplayName(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final prefs = GetIt.instance<SharedPreferences>();
    _displayName = trimmed;
    await prefs.setString(_displayNameKey, trimmed);
  }

  static Future<void> setGeminiKey(String key) async {
    final trimmed = key.trim();
    final prefs = GetIt.instance<SharedPreferences>();
    _geminiKey = trimmed.isEmpty ? null : trimmed;
    if (trimmed.isEmpty) {
      await prefs.remove(_geminiKeyKey);
    } else {
      await prefs.setString(_geminiKeyKey, trimmed);
    }
  }

  static String _randomSalt(int length) {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final rand = Random.secure();
    return List.generate(length, (_) => chars[rand.nextInt(chars.length)])
        .join();
  }
}
