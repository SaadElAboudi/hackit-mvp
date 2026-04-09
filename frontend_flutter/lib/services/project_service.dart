import 'dart:math';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Manages the stable per-device anonymous user identity.
/// Used by the Salons (rooms) feature for consistent identity across sessions.
class ProjectService {
  static const _userIdKey = 'hackit:v1:userId';
  static String? _userId;

  static String? get currentUserId => _userId;

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
  }

  static String _randomSalt(int length) {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final rand = Random.secure();
    return List.generate(length, (_) => chars[rand.nextInt(chars.length)])
        .join();
  }
}
