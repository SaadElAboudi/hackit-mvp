# Hackit MVP

[![Monorepo CI](https://github.com/SaadElAboudi/hackit-mvp/actions/workflows/monorepo-ci.yml/badge.svg)](https://github.com/SaadElAboudi/hackit-mvp/actions/workflows/monorepo-ci.yml)
[![Backend REAL CI](https://github.com/SaadElAboudi/hackit-mvp/actions/workflows/backend-real-ci.yml/badge.svg)](https://github.com/SaadElAboudi/hackit-mvp/actions/workflows/backend-real-ci.yml)
[![Coverage Status](https://codecov.io/gh/SaadElAboudi/hackit-mvp/branch/main/graph/badge.svg)](https://codecov.io/gh/SaadElAboudi/hackit-mvp)

> Secrets & environment setup: see [docs/secrets.md](docs/secrets.md) for configuring `YT_API_KEY`, `GEMINI_API_KEY`, and local `.env` modes.

## Description
Hackit MVP is a project designed to provide users with quick and clear answers to their questions through a chat interface. The application leverages AI to summarize information and find relevant video content from platforms like YouTube and TikTok.

## Features

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

## Contributing
Contributions are welcome! Please submit a pull request or open an issue for any enhancements or bug fixes.

## License
This project is licensed under the MIT License.