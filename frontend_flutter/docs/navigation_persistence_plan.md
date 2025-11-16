# Plan d'amélioration navigation & persistance Flutter

## 1. Navigation (UX fluide, sans perte d'état)
- Utiliser un `IndexedStack` avec un `Navigator` dédié par onglet (pattern "nested navigators").
- Chaque tab conserve sa propre pile de navigation (push/pop indépendants).
- Le retour arrière (back) pop la pile de l'onglet courant, puis sort de l'app si on est à la racine.
- Utiliser des `PageStorageKey` pour préserver le scroll/état de chaque tab.
- Packages recommandés :
  - `provider` (déjà utilisé)
  - (optionnel) `go_router` ou `auto_route` pour navigation avancée

## 2. Persistance locale (état utilisateur)
- Utiliser `sqflite` (déjà migré) pour les messages du chat.
- Utiliser `SharedPreferences` pour les préférences simples (ex: dernier onglet ouvert, brouillon en cours).
- Sauvegarder/restaurer :
  - Messages du chat (déjà fait)
  - Dernier onglet sélectionné
  - Brouillon de message (si utile)

## 3. Correctifs immédiats à appliquer
- Corriger l'auto-scroll du chat (mettre à jour `_lastCount` après scroll).
- Refactorer `RootTabs` pour utiliser un `Navigator` par tab (nested navigators).
- Gérer le retour arrière proprement (pop la pile de l'onglet courant, sinon sortir).
- Sauvegarder/restaurer le dernier onglet sélectionné avec `SharedPreferences`.

---

**Étapes suivantes :**
1. Corriger l'auto-scroll du chat.
2. Refactorer la navigation avec nested navigators.
3. Sauvegarder/restaurer le dernier onglet.
4. (Optionnel) Persister le brouillon de chat.
