# Hackit MVP - Flutter Frontend

Ce dossier contient la migration Flutter du frontend ainsi que l'architecture de streaming enrichie (étapes, vidéo, citations, chapitres) pour les résultats de recherche.

## Prérequis
* Flutter SDK (channel stable, ≥ 3.2.0)
* Dart >= 3.2.0 < 4.0.0
* Backend lancé sur `http://localhost:3000`

## Démarrage rapide
```bash
flutter pub get
flutter run
```
Web (release) + patch bootstrap:
```bash
flutter build web --release
./scripts/patch_index.sh
python3 -m http.server -d build/web 8081
```

## Streaming & ChatKinds
Le flux de recherche (SSE) envoie plusieurs événements jusqu'au résultat final :

| Kind | Description | Widget / Handling |
|------|-------------|-------------------|
| `steps` | Titre + liste d'étapes générées progressivement | `SummaryView` |
| `video` | Carte de la vidéo principale liée au résultat | `VideoCard` |
| `citations` | Liste (limitée) de timestamps avec extraits pertinents | `CitationsView` |
| `chapters` | Découpage en chapitres avec timestamp de début | `ChaptersView` |
| `text` | Message libre (notes, infos supplémentaires) | Simple `Text` |
| `error` | Erreur de flux ou backend | Style rouge + bouton réessayer |

L'ordre arrive par append dans `SearchProvider.messages`. Les widgets sont rendus par `HomeScreen` via un switch sur `ChatKind`.

### Cycle SSE simplifié
1. `user` envoie la requête.
2. Événements `meta` / `partial` (interne) alimentent les étapes (`steps`).
3. Événement `final` inclut `citations`, `chapters`, `videoUrl`.
4. Événement `done` termine le flux; loader retiré.

## Citations & Chapitres
Les structures sont parsées via `BaseSearchResult.fromMap` :
```dart
class Citation { String url; int startSec; int endSec; String quote; }
class Chapter { int index; int startSec; String title; }
```
`CitationsView` affiche jusqu'à 6 timestamps (format mm:ss). `ChaptersView` utilise un `ExpansionTile` listant chaque chapitre.

## Seeking temporel (`VideoSeekService`)
Pour déclencher un seek depuis un timestamp (citation ou chapitre) sans dépendre directement du player, on utilise un service singleton :
```dart
VideoSeekService.instance.register((Duration d) {
	// Implémentation de seek (ex: controller.seekTo(d)) ou ouverture URL
}, baseUrl: videoUrl);

VideoSeekService.instance.seekOrQueue(startSeconds);
```
* Si le player n'est pas prêt lors d'un clic, la valeur est mise en queue et rejouée après `register`.
* `VideoCard` propose un bouton "Activer le seek" qui enregistre un handler ouvrant l'URL avec le paramètre `t=<seconds>`.
* Les chapitres et citations invoquent `seekOrQueue`.

## Scripts post-build Web
| Script | Rôle |
|--------|------|
| `scripts/patch_index.sh` | Injecte `<script src="flutter_bootstrap.js">` + fallback `window._flutter.buildConfig` si absent (idempotent). |
| `scripts/serve_web.sh` | Libère le port (par défaut 8081) et lance un serveur HTTP simple pour le dossier build. |

Usage rapide :
```bash
flutter build web --release
./scripts/patch_index.sh
./scripts/serve_web.sh 8081
```

## Personnalisation backend
Endpoint par défaut configuré dans `lib/services/api_service.dart`. Mettre à jour l'URL si vous déployez le backend ailleurs.

## Prochaines extensions (roadmap courte)
* Historique & favoris (persistences + endpoints `/api/history`, `/api/favorites`).
* Feedback par étape (UI + POST `/api/search/feedback`).
* Optimisation du seek pour players natifs web/mobile (intégration controller).

## Dépannage
| Problème | Cause probable | Action |
|----------|----------------|--------|
| Erreur `_flutter.buildConfig` manquante | Script bootstrap non injecté après build | Exécuter `scripts/patch_index.sh` |
| Timestamps ne sautent pas | `VideoSeekService` non enregistré | Cliquer "Activer le seek" sur la carte vidéo |
| Citations/chapitres absents | Backend n'a pas pu extraire | Vérifier logs backend / données source |

## Licence
Usage interne MVP (non publié). Ajouter détails de licence si distribution externe.

