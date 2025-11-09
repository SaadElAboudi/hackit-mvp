# Changelog

All notable changes to this project will be documented in this file.

## v0.2.1 — 2025-11-09

- Frontend Flutter (web): hide prompt template chips by default for a cleaner prompt.
- Health endpoints: structured JSON with mode (MOCK/REAL), uptimeSeconds, version, Gemini operational flags.
- Frontend HealthBadge: integrated and reflects backend health; minor UI polish.
- Build: production web build generated and published to gh-pages.
- Tag: v0.2.1 created and pushed.

## v0.2.0 — 2025-11-07

- Backend: REAL mode working with YouTube + Gemini summary fallback.
- Search API: returns title, steps, videoUrl with mock fallback on failure.
- Scripts: batch GitHub issues creation script improved (dry-run, labels, milestones).

## v0.1.0 — 2025-11-03

- Initial monorepo setup (backend, frontend_flutter, shared docs).
- Basic CI and project scaffolding.