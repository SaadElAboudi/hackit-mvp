# Hackit Implementation Roadmap (2026)

Last updated: 2026-04-17

This document turns product direction into concrete engineering deliverables for the current repository.

## Goal

Ship a production-grade collaborative AI workspace where teams can:
- collaborate in real time inside channels,
- invoke shared AI reliably,
- generate and version outputs,
- and export/share outcomes to external tools.

## Current Baseline

Already implemented in code:
- Shared channel AI with mention and slash commands.
- Core commands: `/doc`, `/search`, `/decide`, `/brief`, `/share`, `/mission`.
- Proactive suggestions: synthesis and pre-meeting brief.
- Integrations: Slack and Notion connect/disconnect/share/export.
- Mission specialist profiles and mission metadata in backend and Flutter.

## Next Delivery Phases

## Phase 5: Reliability and Governance (2 weeks)

### Backend
- Add strict request schema validation on all room write routes.
- Standardize error format (`code`, `message`, `details`, `requestId`).
- Add correlation `requestId` propagation from API to logs and WS events.
- Add rate limiting for command-heavy endpoints.

### Frontend
- Display recoverable error states with contextual retries for channel actions.
- Surface `requestId` in debug panel for support diagnostics.

### Verification
- Add tests for validation failures and error envelope consistency.
- Add regression tests for WS behavior under invalid payloads.

## Phase 6: Artifact Workflow Maturity (2-3 weeks)

### Backend
- Add artifact comments endpoint with role-aware permissions.
- Add artifact version diff metadata (author, change summary).
- Support artifact status transitions (`draft`, `review`, `validated`).

### Frontend
- Add artifact review panel with comments timeline.
- Add version compare UI (summary-first, full diff on demand).
- Add validation workflow actions for owners/moderators.

### Verification
- Add integration tests for artifact review lifecycle.
- Add widget tests for version and status rendering.

## Phase 7: Enterprise Integrations Expansion (2 weeks)

### Backend
- Add connector abstraction for export targets (`slack`, `notion`, future `drive`, `jira`).
- Implement retries and idempotency key for share/export jobs.
- Persist share history per room and per artifact.

### Frontend
- Add integration status center (health, last sync, last failure reason).
- Add share history cards in channel context panel.

### Verification
- Add tests for connector fallback behavior and retry policy.
- Add API tests for share history listing and filtering.

## Phase 8: Observability and Operations (1-2 weeks)

### Backend
- Add metrics: command latency, AI fallback rate, WS fanout failures.
- Add health endpoints for integration readiness checks.
- Define SLOs and alert thresholds for key routes.

### Frontend
- Add lightweight telemetry events for feature usage (opt-in safe mode).
- Add non-blocking status banner for degraded backend modes.

### Verification
- Run load smoke on room messaging and command routes.
- Validate dashboard and alert wiring in staging.

## Detailed Backlog by Area

## Backend Services
- `backend/src/routes/rooms.js`
  - Validation middleware per route.
  - Error envelope and requestId propagation.
- `backend/src/services/roomOrchestrator.js`
  - Harden command parser edge cases.
  - Add idempotency hooks for share operations.
- `backend/src/services/roomWS.js`
  - Include requestId in relevant emitted events.
  - Add event-level guards for malformed payloads.
- `backend/src/services/slack.js`
  - Retry and idempotency controls.
- `backend/src/services/notion.js`
  - Export retries and normalized provider errors.

## Frontend Flutter
- `frontend_flutter/lib/screens/salon_chat_screen.dart`
  - Error/retry affordances and integration status UI.
  - Artifact review and compare affordances.
- `frontend_flutter/lib/providers/room_provider.dart`
  - RequestId-aware error state pipeline.
  - Share history state and synchronization.
- `frontend_flutter/lib/services/room_service.dart`
  - Typed error mapping and idempotent retry handling.
- `frontend_flutter/lib/models/room.dart`
  - Additional models for comments, share history, and status transitions.

## Test and CI
- Backend:
  - Add suites for validation, idempotency, and observability payloads.
- Flutter:
  - Add widget tests for new cards, banners, and review flows.
- CI:
  - Fail builds on schema drift and lint violations for touched files.

## Definition of Done

A phase is complete when all are true:
- Features shipped behind stable API contracts.
- Tests added and passing in CI for changed behavior.
- Docs updated (`README.md`, `docs/architecture.md`, this file).
- Operator playbook updated when runtime behavior changes.

## Tracking

Use `codex.md` for high-level product phase state.
Use this file for implementation-level sequencing and engineering scope.