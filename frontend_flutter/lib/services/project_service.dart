import 'dart:math';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Manages the stable per-device anonymous user identity and display name.
/// Used by the Salons (rooms) feature for consistent identity across sessions.
class ProjectService {
  static const _userIdKey = 'hackit:v1:userId';
  static const _displayNameKey = 'hackit:v1:displayName';
  static String? _userId;
  static String? _displayName;

  static String? get currentUserId => _userId;

  /// The user-chosen display name, or null if not yet set.
  static String? get currentDisplayName => _displayName;

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
  }

  /// Persists a user-chosen display name. Trims whitespace.
  static Future<void> setDisplayName(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final prefs = GetIt.instance<SharedPreferences>();
    _displayName = trimmed;
    await prefs.setString(_displayNameKey, trimmed);
  }

  static String _randomSalt(int length) {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final rand = Random.secure();
    return List.generate(length, (_) => chars[rand.nextInt(chars.length)])
        .join();
  }
}
