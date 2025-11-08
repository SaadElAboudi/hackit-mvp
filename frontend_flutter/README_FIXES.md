# Frontend Flutter Cleanup (Temporary Suppression)

## Pourquoi le dossier était rouge ?
Des centaines d'erreurs d'analyse (imports cassés, tests obsolètes, refactor incomplet). Pour rendre l'environnement à nouveau exploitable, on a temporairement exclu les dossiers saturés d'erreurs dans `analysis_options.yaml`.

## Ce qui a été fait
- Ajout d'exclusions analyzer pour: `test/`, `integration_test/`, et modules legacy (`lib/features`, `lib/domain`, etc.).
- Objectif: faire tourner un noyau minimal (ex: `lib/main.dart`, providers basiques) sans bruit.

## Étapes de restauration (proposées)
1. Retirer d'abord `lib/theme`, `lib/providers`, `lib/utils` de la liste quand leurs imports sont corrigés.
2. Corriger les imports `package:hackit_mvp/...` → `package:hackit_mvp_flutter/...` dans chaque fichier avant de retirer son dossier des exclusions.
3. Réparer les classes manquantes (ex: `SearchBloc`, `SearchResult`) ou supprimer leur utilisation.
4. Réactiver tests graduellement:
   - Supprimer de l'exclusion `test/**`.
   - Lancer `flutter test` et corriger ce qui reste.
5. Réintroduire intégration: retirer `integration_test/**` puis exécuter `flutter test integration_test`.

## Bonnes pratiques de progression
- Enlever une exclusion à la fois, commit, puis corriger erreurs.
- Ajouter éventuellement des dossiers `legacy/` pour code non migré afin de mieux isoler.

## Prochaines actions suggérées
- Vérifier que `main.dart` ne dépend pas de dossiers exclus critiques (sinon le build échouera).
- Créer un mini service API propre (`lib/services/api_service.dart`) ou adapter le existant si présent.

## Avertissement
Les exclusions ne réparent pas le runtime; elles cachent uniquement les diagnostics. Chaque dossier réactivé doit compiler sans erreurs pour garantir la stabilité.

