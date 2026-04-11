import 'dart:math';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Manages the stable per-device identity and display name.
class ProjectService {
  static const _userIdKey = 'hackit:v1:userId';
  static const _displayNameKey = 'hackit:v1:displayName';

  static String? _userId;
  static String? _displayName;

  static String? get currentUserId => _userId;
  static String? get currentDisplayName => _displayName;

  /// True once the user has set a display name.
  static bool get isOnboarded =>
      _displayName != null && _displayName!.isNotEmpty;

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
