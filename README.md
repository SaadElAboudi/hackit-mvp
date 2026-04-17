# Hackit MVP

[![Monorepo CI](https://github.com/SaadElAboudi/hackit-mvp/actions/workflows/monorepo-ci.yml/badge.svg)](https://github.com/SaadElAboudi/hackit-mvp/actions/workflows/monorepo-ci.yml)
[![Backend REAL CI](https://github.com/SaadElAboudi/hackit-mvp/actions/workflows/backend-real-ci.yml/badge.svg)](https://github.com/SaadElAboudi/hackit-mvp/actions/workflows/backend-real-ci.yml)
[![Coverage Status](https://codecov.io/gh/SaadElAboudi/hackit-mvp/branch/main/graph/badge.svg)](https://codecov.io/gh/SaadElAboudi/hackit-mvp)

Hackit is a collaborative AI workspace where a channel ("Salon") is the core unit: team members chat in real time, trigger AI actions with mentions and slash commands, and produce shared outputs (documents, decisions, briefs, research cards, and missions).

Current product direction is documented here:
- `codex.md` (product specification and completed roadmap phases)
- `docs/architecture.md` (system architecture and module boundaries)
- `docs/implementation_roadmap.md` (next implementation phases with concrete deliverables)

## What Is Working Today

- Real-time collaborative channels (`Salons`) with WebSocket updates.
- Shared AI orchestration via `@ia` and slash commands.
- Commands implemented in production paths:
  - `/doc` to create shared artifacts.
  - `/search` to attach research outputs.
  - `/decide` to extract decisions and next steps.
  - `/brief` for pre-meeting summaries (manual and proactive suggestions).
  - `/mission` for specialized mission agents.
  - `/share slack|notion` for external sharing.
- Room-scoped integrations:
  - Slack connect/disconnect/status/share.
  - Notion connect/disconnect/status/export.
- Mission specialization profiles (`auto`, `strategist`, `researcher`, `facilitator`, `analyst`, `writer`).
- Backend and integration tests covering orchestrator, WebSocket flows, and sharing integrations.

## Tech Stack

- Frontend: Flutter (web and desktop targets in this repo).
- Backend: Node.js (Express-style API + WebSocket room hub).
- Database: MongoDB Atlas models for rooms, messages, artifacts, missions, memory.
- AI: Gemini-based orchestration with resilient fallbacks.
- Deployment:
  - Backend on Render (see `render.yaml`).
  - Static web build via `frontend_flutter/gh-pages`.

## Repository Structure

```text
hackit-mvp/
  backend/            # Node API, orchestrator, models, tests
  frontend_flutter/   # Flutter app (channels UI, providers, services)
  shared/             # Shared config/types
  docs/               # Architecture, roadmap, strategy, guides
  codex.md            # Product spec + phase tracking
```

## Local Setup

### Backend

```bash
cd backend
npm ci
cp .env.example .env
npm run dev
```

### Frontend (Flutter web)

```bash
cd frontend_flutter
flutter pub get
flutter run -d chrome --web-port 8080
```

Secrets and environment setup:
- `docs/secrets.md`

## Test Commands

```bash
# backend
cd backend && npm test

# backend coverage
cd backend && npm run test:coverage

# flutter analyze and tests
cd frontend_flutter && flutter analyze
cd frontend_flutter && flutter test -r compact
```

## Deployment Notes

- Render blueprint and guide:
  - `render.yaml`
  - `docs/render_deploy.md`
- GitHub Pages static frontend (if enabled in repository settings):
  - `https://saadelaboudi.github.io/hackit-mvp/`

## Contributing

- Keep commits focused and explicit.
- Add or update tests for backend behavior changes.
- Update docs when product behavior or API contracts change.

## License

MIT (see repository license information).