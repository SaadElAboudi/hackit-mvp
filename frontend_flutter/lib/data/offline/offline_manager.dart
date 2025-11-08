import 'package:injectable/injectable.dart';
import 'package:rxdart/rxdart.dart';
import '../models/pending_action.dart';
import '../core/network_info.dart';
import '../cache/cache_manager.dart';

@singleton
class OfflineManager {
  final NetworkInfo _networkInfo;
  final CacheManager _cacheManager;
  final _pendingActions = BehaviorSubject<List<PendingAction>>();
  final _isOnline = BehaviorSubject<bool>.seeded(true);

  OfflineManager(this._networkInfo, this._cacheManager) {
    _init();
  }

  Future<void> _init() async {
    // Initialiser l'état de la connexion
    _updateConnectionStatus();

    // Charger les actions en attente
    await _loadPendingActions();

    // Écouter les changements de connectivité
    _networkInfo.onConnectivityChanged.listen((isConnected) {
      _isOnline.add(isConnected);
      if (isConnected) {
        _processPendingActions();
      }
    });
  }

  Future<void> _updateConnectionStatus() async {
    final isConnected = await _networkInfo.isConnected;
    _isOnline.add(isConnected);
  }

  Future<void> _loadPendingActions() async {
    final actions = _cacheManager.getPendingActions();
    _pendingActions.add(actions);
  }

  Future<void> addPendingAction(PendingAction action) async {
    final currentActions = [..._pendingActions.value];
    currentActions.add(action);
    _pendingActions.add(currentActions);
    await _cacheManager.savePendingAction(action);
  }

  Future<void> _processPendingActions() async {
    if (!_isOnline.value) return;

    final actions = [..._pendingActions.value];
    if (actions.isEmpty) return;

    for (final action in actions) {
      try {
        await _processAction(action);
        await _cacheManager.removePendingAction(action);
      } catch (e) {
        // Si l'action échoue, on la laisse dans la file d'attente
        continue;
      }
    }

    // Mettre à jour la liste des actions en attente
    final remainingActions = await _cacheManager.getPendingActions();
    _pendingActions.add(remainingActions);
  }

  Future<void> _processAction(PendingAction action) async {
    switch (action.type) {
      case ActionType.search:
        // Traiter une recherche en attente
        await _processSearchAction(action);
        break;
      case ActionType.addToFavorites:
        // Traiter l'ajout aux favoris
        await _processFavoriteAction(action, add: true);
        break;
      case ActionType.removeFromFavorites:
        // Traiter la suppression des favoris
        await _processFavoriteAction(action, add: false);
        break;
    }
  }

  Future<void> _processSearchAction(PendingAction action) async {
    final query = action.data['query'] as String;
    // Exécuter la recherche et mettre à jour le cache
    await _cacheManager.clearSearchResult(query);
    // La recherche sera ré-exécutée naturellement lors de la prochaine requête
  }

  Future<void> _processFavoriteAction(
    PendingAction action, {
    required bool add,
  }) async {
    final videoId = action.data['videoId'] as String;
    if (add) {
      // Synchroniser l'ajout aux favoris avec le serveur
      await _cacheManager.addToFavorites(videoId);
    } else {
      // Synchroniser la suppression des favoris avec le serveur
      await _cacheManager.removeFromFavorites(videoId);
    }
  }

  // API publique
  Stream<bool> get isOnline => _isOnline.stream;
  Stream<List<PendingAction>> get pendingActions => _pendingActions.stream;

  Future<void> queueSearch(String query) async {
    final action = PendingAction(
      type: ActionType.search,
      data: {'query': query},
      timestamp: DateTime.now(),
    );
    await addPendingAction(action);
  }

  Future<void> queueAddToFavorites(String videoId) async {
    final action = PendingAction(
      type: ActionType.addToFavorites,
      data: {'videoId': videoId},
      timestamp: DateTime.now(),
    );
    await addPendingAction(action);
  }

  Future<void> queueRemoveFromFavorites(String videoId) async {
    final action = PendingAction(
      type: ActionType.removeFromFavorites,
      data: {'videoId': videoId},
      timestamp: DateTime.now(),
    );
    await addPendingAction(action);
  }

  void dispose() {
    _pendingActions.close();
    _isOnline.close();
  }
}