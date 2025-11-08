import 'package:injectable/injectable.dart';
import 'package:rxdart/rxdart.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../cache/cache_manager.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';

@singleton
class AppStateManager {
  final SharedPreferences _prefs;
  final CacheManager _cacheManager;
  final Map<String, BehaviorSubject> _stateStreams = {};
  final Map<String, Timer> _cacheTimers = {};
  final Duration _defaultCacheDuration = const Duration(minutes: 15);

  AppStateManager(this._prefs) : _cacheManager = CacheManager();

  // Obtenir un stream pour un état spécifique
  Stream<T> getStateStream<T>(String key, {bool cache = true}) {
    if (!_stateStreams.containsKey(key)) {
      _stateStreams[key] = BehaviorSubject<T>();
      if (cache) {
        _loadFromCache<T>(key);
      }
    }
    return _stateStreams[key]!.stream.cast<T>();
  }

  // Mettre à jour un état
  void updateState<T>(String key, T value, {Duration? cacheDuration}) {
    if (!_stateStreams.containsKey(key)) {
      _stateStreams[key] = BehaviorSubject<T>();
    }
    _stateStreams[key]!.add(value);
    _updateCache(key, value, cacheDuration);
  }

  // Combiner plusieurs états
  Stream<R> combineStates<R>({
    required List<String> keys,
    required R Function(List<dynamic>) combiner,
  }) {
    final streams = keys.map((key) => getStateStream(key));
    return Rx.combineLatest(streams.toList(), combiner);
  }

  // Transformer un état
  Stream<R> transformState<T, R>(
    String key,
    R Function(T) transformer,
  ) {
    return getStateStream<T>(key).map(transformer);
  }

  // Filtrer un état
  Stream<T> filterState<T>(
    String key,
    bool Function(T) predicate,
  ) {
    return getStateStream<T>(key).where(predicate);
  }

  // Gérer les états dérivés
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

  // Charger depuis le cache
  Future<void> _loadFromCache<T>(String key) async {
    try {
      final cachedValue = await _cacheManager.get<T>(key);
      if (cachedValue != null) {
        _stateStreams[key]!.add(cachedValue);
      }
    } catch (e) {
      debugPrint('Error loading from cache: $e');
    }
  }

  // Mettre à jour le cache
  void _updateCache<T>(String key, T value, [Duration? duration]) {
    // Annuler le timer existant s'il y en a un
    _cacheTimers[key]?.cancel();

    // Sauvegarder dans le cache
    _cacheManager.put(key, value);

    // Configurer le timer d'expiration
    _cacheTimers[key] = Timer(
      duration ?? _defaultCacheDuration,
      () => _cacheManager.delete(key),
    );
  }

  // Vider le cache pour une clé
  Future<void> invalidateCache(String key) async {
    await _cacheManager.delete(key);
    _cacheTimers[key]?.cancel();
    _cacheTimers.remove(key);
  }

  // Vider tout le cache
  Future<void> clearAllCache() async {
    await _cacheManager.clear();
    for (var timer in _cacheTimers.values) {
      timer.cancel();
    }
    _cacheTimers.clear();
  }

  // Gestion de la mémoire
  void _cleanupUnusedStreams() {
    _stateStreams.removeWhere((key, subject) => !subject.hasListener);
  }

  // Optimisation de la mémoire
  void optimizeMemoryUsage() {
    _cleanupUnusedStreams();
    // Light preference introspection to ensure _prefs isn't optimized away and to monitor growth.
    final keyCount = _prefs.getKeys().length;
    if (keyCount > 500) {
      debugPrint('Preference key count high: $keyCount');
    }
  }

  // Gestionnaire d'erreurs centralisé
  void handleError(String key, dynamic error) {
    if (_stateStreams.containsKey(key)) {
      _stateStreams[key]!.addError(error);
    }
  }

  // Nettoyage des ressources
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
