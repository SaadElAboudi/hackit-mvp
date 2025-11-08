import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:injectable/injectable.dart';
import 'package:rxdart/rxdart.dart';
import 'package:shared_preferences/shared_preferences.dart';

@singleton
class AppStateManager {
  final SharedPreferences _prefs;
  final Map<String, BehaviorSubject> _stateStreams = {};
  final Map<String, Timer> _cacheTimers = {};
  static const _defaultCacheDuration = Duration(minutes: 15);

  AppStateManager(this._prefs);

  Stream<T> getStateStream<T>(String key, {bool cache = true}) {
    if (!_stateStreams.containsKey(key)) {
      _stateStreams[key] = BehaviorSubject<T>();
      if (cache) {
        _loadFromCache<T>(key);
      }
    }
    return _stateStreams[key]!.stream.cast<T>();
  }

  void updateState<T>(String key, T value, {Duration? cacheDuration}) {
    if (!_stateStreams.containsKey(key)) {
      _stateStreams[key] = BehaviorSubject<T>();
    }
    _stateStreams[key]!.add(value);
    _updateCache(key, value, cacheDuration);
  }

  Stream<R> combineStates<R>({
    required List<String> keys,
    required R Function(List<dynamic>) combiner,
  }) {
    final streams = keys.map((key) => getStateStream(key));
    return Rx.combineLatestList(streams).map(combiner);
  }

  Stream<R> transformState<T, R>(
    String key,
    R Function(T) transformer,
  ) {
    return getStateStream<T>(key).map(transformer);
  }

  Stream<T> filterState<T>(
    String key,
    bool Function(T) predicate,
  ) {
    return getStateStream<T>(key).where(predicate);
  }

  Stream<R> createDerivedState<T, R>({
    required String sourceKey,
    required R Function(T) derivation,
    bool cache = true,
  }) {
    final derivedKey = '${sourceKey}_derived';
    final stream = getStateStream<T>(sourceKey).map(derivation);

    if (cache) {
      stream.listen((value) {
        _updateCache(derivedKey, value);
      });
    }

    return stream;
  }

  Future<void> _loadFromCache<T>(String key) async {
    try {
      final value = _prefs.get(key);
      if (value != null) {
        _stateStreams[key]!.add(value);
      }
    } catch (e) {
      debugPrint('Error loading from cache: $e');
    }
  }

  void _updateCache<T>(String key, T value, [Duration? duration]) {
    _cacheTimers[key]?.cancel();

    if (value is String) {
      _prefs.setString(key, value);
    } else if (value is int) {
      _prefs.setInt(key, value);
    } else if (value is double) {
      _prefs.setDouble(key, value);
    } else if (value is bool) {
      _prefs.setBool(key, value);
    } else if (value is List<String>) {
      _prefs.setStringList(key, value);
    }

    _cacheTimers[key] = Timer(
      duration ?? _defaultCacheDuration,
      () => _prefs.remove(key),
    );
  }

  Future<void> invalidateCache(String key) async {
    await _prefs.remove(key);
    _cacheTimers[key]?.cancel();
    _cacheTimers.remove(key);
  }

  Future<void> clearAllCache() async {
    await _prefs.clear();
    for (var timer in _cacheTimers.values) {
      timer.cancel();
    }
    _cacheTimers.clear();
  }

  void _cleanupUnusedStreams() {
    _stateStreams.removeWhere((key, subject) => !subject.hasListener);
  }

  void optimizeMemoryUsage() {
    _cleanupUnusedStreams();
  }

  void handleError(String key, dynamic error) {
    if (_stateStreams.containsKey(key)) {
      _stateStreams[key]!.addError(error);
    }
  }

  void dispose() {
    for (var subject in _stateStreams.values) {
      subject.close();
    }
    _stateStreams.clear();

    for (var timer in _cacheTimers.values) {
      timer.cancel();
    }
    _cacheTimers.clear();
  }
}
