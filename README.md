# Hackit MVP

[![Monorepo CI](https://github.com/SaadElAboudi/hackit-mvp/actions/workflows/monorepo-ci.yml/badge.svg)](https://github.com/SaadElAboudi/hackit-mvp/actions/workflows/monorepo-ci.yml)
[![Backend REAL CI](https://github.com/SaadElAboudi/hackit-mvp/actions/workflows/backend-real-ci.yml/badge.svg)](https://github.com/SaadElAboudi/hackit-mvp/actions/workflows/backend-real-ci.yml)
[![Coverage Status](https://codecov.io/gh/SaadElAboudi/hackit-mvp/branch/main/graph/badge.svg)](https://codecov.io/gh/SaadElAboudi/hackit-mvp)

> Secrets & environment setup: see [docs/secrets.md](docs/secrets.md) for configuring `YT_API_KEY`, `GEMINI_API_KEY`, and local `.env` modes.

## Description
Hackit MVP is a project designed to provide users with quick and clear answers to their questions through a chat interface. The application leverages AI to summarize information and find relevant video content from platforms like YouTube and TikTok.


## Features
- **UX/UI premium et moderne** : headers cohérents (icône, titre premium, ligne décorative), cards arrondies, typographie bold, couleurs modernes.
- **Streaming chat UI (SSE)** : réponses structurées (étapes, vidéo, citations, chapitres, texte, erreur).
- **Favoris & Historique local** : gestion locale (SharedPreferences, LRU 50), badge AppBar, suppression rapide, SnackBar feedback.
- **Navigation simplifiée** : accès direct aux écrans Home, Leçons, Favoris, Historique.
- **Mode invité et démo** : userId anonyme, sauvegarde locale, JWT pour le user demo.
- **Citations & chapitres** : timestamp seek via `VideoSeekService`.
- **API Gemini fallback** : gestion des erreurs et bascule automatique.
## Nouveautés UX/UI
- Refonte complète des headers sur tous les écrans (icône, titre premium, ligne verte).
- Cards arrondies, ombrées, avec typographie bold et couleurs premium.
- Feedback utilisateur amélioré (SnackBar, suppression, favoris).
- Navigation fluide et cohérente.
## Mode invité & démo
- L’application gère un userId anonyme pour le mode invité (stocké localement).
- Le user demo utilise un JWT pour tester toutes les fonctionnalités sans inscription.
## Conventions & contribution
- Respecter la structure du projet (frontend_flutter, backend, shared, docs).
- Utiliser des noms explicites pour les commits et les branches.
- Suivre les conventions de code Dart/Flutter et Node.js.
- Pour contribuer : fork, pull request, description claire, tests si possible.
## Screenshots & démo
Vous pouvez ajouter des captures d’écran dans le dossier `docs/` ou en README pour illustrer la nouvelle interface.

## Tech Stack

## Project Structure
```
hackit-mvp
├── frontend          # Frontend application
├── backend           # Backend API
├── shared            # Shared types and configurations
├── .gitignore        # Files to ignore in version control
├── package.json      # Project metadata and dependencies
└── README.md         # Project documentation
```

## Setup Instructions

### Frontend (Flutter)
1. Navigate to the `frontend_flutter` directory.
2. Install dependencies:
   ```bash
   flutter pub get
   ```
3. Run analyzer and tests (widgets subset):
   ```bash
   flutter analyze
   flutter test -r compact test/widgets
   ```
4. Run on web (dev):
   ```bash
   flutter run -d chrome
   ```

### Backend
1. Navigate to the `backend` directory.
2. Install dependencies:
   ```
   npm ci
   ```
3. Create a `.env` file based on `.env.example` and add your API keys.
4. Start the server:
   ```bash
   npm start
   ```
5. Smoke test locally:
   ```bash
   npm run test:smoke
   ```

### Coverage (local)
Backend:
```bash
cd backend && npm run test:coverage
```
Flutter smoke only:
```bash
cd frontend_flutter && flutter test --coverage test/smoke_main_test.dart
```
Frontend (Jest, if tests added):
```bash
npm test -- --coverage
```

Aggregated coverage is uploaded automatically by the CI coverage job (merges backend + flutter + frontend lcov files).

### Real-mode CI (YouTube Data API)
To exercise the production YouTube API path daily, a scheduled workflow `backend-real-ci.yml` runs the backend with `MOCK_MODE=false` and performs the smoke test with `REAL_MODE=true`.

Setup steps:
1. In your GitHub repo settings, add a secret `YT_API_KEY` containing a valid YouTube Data API v3 key.
2. (Optional) Adjust the cron schedule inside `.github/workflows/backend-real-ci.yml`.
3. Manually trigger via the Actions tab ("Run workflow") if you want an immediate check.

The REAL smoke will fail if the response still indicates a mock source, ensuring keys are wired correctly and fallback logic doesn’t silently mask issues.

## Usage
- Open the frontend application and enter your question in the chat interface.
- The application will return a summarized answer along with a relevant video link.

## Releases

- Latest: v0.2.1 (2025-11-09)
   - Frontend web: prompt template chips hidden by default for a cleaner input.
   - Backend health: structured JSON (mode, uptimeSeconds, version, Gemini operational).
   - HealthBadge integrated on Flutter frontend.
   - Production web build published to GitHub Pages.
   - See full notes in [CHANGELOG.md](CHANGELOG.md).

GitHub Pages (if enabled in Settings → Pages): https://saadelaboudi.github.io/hackit-mvp/

## Contributing
Contributions are welcome! Please submit a pull request or open an issue for any enhancements or bug fixes.

## License
This project is licensed under the MIT License.