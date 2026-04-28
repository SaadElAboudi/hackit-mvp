# Authentification Google (OAuth)

Pour activer l’authentification Google côté backend :

1. Installez les dépendances nécessaires :
  ```bash
  npm install passport passport-google-oauth20 express-session
  ```

2. Configurez un projet Google Cloud et récupérez un client ID/secret OAuth2.
3. Ajoutez les variables d’environnement suivantes dans `.env` :
  ```env
  GOOGLE_CLIENT_ID=xxx
  GOOGLE_CLIENT_SECRET=yyy
  GOOGLE_CALLBACK_URL=http://localhost:3000/auth/google/callback
  SESSION_SECRET=un_secret_long
  ```

4. Ajoutez la configuration Passport et les routes d’authentification dans `src/index.js`.

5. Protégez les endpoints nécessitant un userId authentifié.
# Hackit MVP Backend

Backend HTTP API that searches YouTube for a how-to video and returns a concise 5-step summary. It supports mock mode, official YouTube API, a yt-search fallback, and optional Gemini reformulation/summary.

## Requirements

- Node.js 20.x (project pins to `.nvmrc` 20.19.0). Older Node versions are not supported.
- npm 10.x recommended (Volta config is provided via `.volta.json`).

## Quick start

```
# At repo root (uses .nvmrc)
nvm use
cd backend
npm ci

# Mock mode (no API keys required)
MOCK_MODE=true npm start
# -> http://localhost:3000/health
```

## Environment

- YT_API_KEY: optional. When set, uses the YouTube Data API first.
- USE_GEMINI: optional flag ("true"/"false").
- USE_GEMINI_REFORMULATION: optional flag to enable reformulation before search.
- GEMINI_API_KEY: required only if USE_GEMINI is true.
- GEMINI_MODEL: defaults to models/gemini-2.0-flash-lite.
- GEMINI_TIMEOUT_MS: defaults to 4000.
- MOCK_MODE: when true, always returns a deterministic mock response.
- ALLOW_FALLBACK: when true (default), degrades to mock if all providers fail.

## Run & dev

```
# Start (Node version check enforced)
npm start

# Dev with hot reload (Node >= 20 enforced)
npm run dev
```

## Endpoints

- POST /api/search
  - Body: `{ "query": "changer un pneu" }`
  - Response: `{ title, steps: string[], videoUrl, source }`

- GET /api/search/stream?query=...
  - Server-Sent Events stream of `{type: 'meta'|'partial'|'done'|'error', ...}`

- GET /health and /health/extended

## Tests

```
npm test
npm run test:coverage
npm run test:smoke
npm run test:e2e-smoke
```

`npm run test:e2e-smoke` validates the streaming search flow end-to-end (SSE meta/partial/final/done + timestamp citations) and writes a network log artifact to `backend/artifacts/e2e-smoke/`.

## Notes

- On Node >= 20 without YT_API_KEY, the service uses `yt-search` as a fallback.
- SSE endpoint simulates token streaming by splitting summary lines.