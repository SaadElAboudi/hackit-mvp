import 'package:hive/hive.dart';
import '../services/security_service.dart';
import 'dart:convert';

class SecureBox<T> {
  final Box<String> _box;
  final SecurityService _securityService;
  final T Function(Map<String, dynamic>) _fromJson;
  final Map<String, dynamic> Function(T) _toJson;

  SecureBox(
    this._box,
    this._securityService,
    this._fromJson,
    this._toJson,
  );

  Future<void> put(String key, T value) async {
    final jsonString = jsonEncode(_toJson(value));
    final encrypted = _securityService.encryptData(jsonString);
    await _box.put(key, encrypted);
  }

  T? get(String key) {
    final encrypted = _box.get(key);
    if (encrypted == null) return null;

    try {
      final decrypted = _securityService.decryptData(encrypted);
      final jsonMap = jsonDecode(decrypted) as Map<String, dynamic>;
      return _fromJson(jsonMap);
    } catch (e) {
      print('Error decrypting data: $e');
      return null;
    }
  }

  Future<void> delete(String key) async {
    await _box.delete(key);
  }

  Future<void> clear() async {
    await _box.clear();
  }

  List<T> values() {
    return _box.values.map((encrypted) {
      try {
        final decrypted = _securityService.decryptData(encrypted);
        final jsonMap = jsonDecode(decrypted) as Map<String, dynamic>;
        return _fromJson(jsonMap);
      } catch (e) {
        print('Error decrypting data: $e');
        return null;
      }
    }).where((element) => element != null).cast<T>().toList();
  }

  Stream<BoxEvent> watch() {
    return _box.watch().map((event) {
      if (event.value == null) return event;
      
      try {
        final decrypted = _securityService.decryptData(event.value as String);
        final jsonMap = jsonDecode(decrypted) as Map<String, dynamic>;
        return BoxEvent(
          event.key,
          _fromJson(jsonMap),
          event.deleted,
        );
      } catch (e) {
        print('Error decrypting watched data: $e');
        return event;
      }
    });
  }

  bool containsKey(String key) {
    return _box.containsKey(key);
  }

  int get length => _box.length;

  bool get isEmpty => _box.isEmpty;
  bool get isNotEmpty => _box.isNotEmpty;

  Iterable<String> get keys => _box.keys.cast<String>();
}