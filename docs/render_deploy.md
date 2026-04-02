# Deploy Render (Backend + Frontend)

This repository includes a full-stack Render Blueprint that deploys:

- `hackit-backend` (Node web service)
- `hackit-frontend` (Render static site)

The backend runs health + smoke checks on each deploy, and the frontend is published from `frontend_flutter/gh-pages`.

## What is included

- `render.yaml` blueprint for both services
- Backend health check on `/health`
- Automatic backend post-deploy smoke test (`npm run test:smoke`)
- Frontend SPA rewrite (`/* -> /index.html`)
- Automatic frontend API URL wiring from backend Render URL

## One-time setup

1. Push this repository to GitHub.
2. In Render Dashboard: `New +` -> `Blueprint`.
3. Select this repository.
4. Confirm both services are detected:
	- `hackit-backend`
	- `hackit-frontend`
5. Click `Apply`.

## Required environment variables (backend)

Set these on `hackit-backend` in Render:

- `MONGODB_URI`: your MongoDB connection string (Atlas recommended)
- `YT_API_KEY`: optional (required only for real YouTube mode)
- `GEMINI_API_KEY`: optional
- `USE_GEMINI`: `true` or `false`
- `USE_GEMINI_REFORMULATION`: `true` or `false`

Defaults already in blueprint:

- `MOCK_MODE=true` for stable smoke deploys without external APIs
- `ALLOW_FALLBACK=true`

## How frontend API URL is set

During frontend build, the blueprint copies `frontend_flutter/gh-pages` and replaces `http://localhost:3000` with the backend public Render URL.

This value comes from:

- `API_BASE_URL <- hackit-backend / RENDER_EXTERNAL_URL`

This avoids local-only API endpoints in production.

## Automatic checks on each backend deploy

Render runs:

```bash
API_HOST=127.0.0.1 API_PORT=$PORT npm run test:smoke
```

If smoke fails, deployment is marked failed.

## After first deploy

1. Open `hackit-backend` and verify `/health` is green.
2. Open `hackit-frontend` URL and validate search/chat flow.
3. If browser CORS errors appear, verify `FRONTEND_ORIGIN` on backend matches frontend Render URL.
