# Hackit Implementation Roadmap (2026)

Last updated: 2026-04-29

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

## Delivery Status

## Phase 5: Reliability and Governance (2 weeks) ✅ complete

### Backend
- Strict request schema validation added on room write routes.
- Standardized room error format with `code`, `message`, `details`, `requestId`.
- Correlation `requestId` propagated from API to logs and WS events.
- Rate limiting added for command-heavy endpoints.

### Frontend
- Recoverable error states and contextual retries added for channel actions.
- `requestId` surfaced in the support/debug panel for diagnostics.

### Verification
- Validation failure and error envelope consistency tests added.
- Regression coverage added for invalid room payload behavior.

## Phase 6: Artifact Workflow Maturity (2-3 weeks) [~] mostly complete

### Backend
- Artifact comments endpoints with role-aware permissions are implemented.
- Artifact version metadata includes author and change summary.
- Artifact status transitions (`draft`, `review`, `validated`, `archived`) are implemented.

### Frontend
- Artifact review UX exists in Flutter and is usable in channel flows.
- Version compare / review affordances exist but still need UX tightening.
- Validation workflow actions are available for privileged roles.

### Verification
- Backend integration coverage exists for core artifact lifecycle.
- Remaining gap: widget coverage for review, compare, and status rendering in Flutter.

## Phase 7: Enterprise Integrations Expansion (2 weeks) ✅ complete

### Backend
- Connector abstraction is in place for export targets (`slack`, `notion`, future providers).
- Retries and idempotency keys are implemented for share/export jobs.
- Share history is persisted per room and per artifact.

### Frontend
- Integration status center exposes readiness, last sync, and last failure reason.
- Share history cards are available in the channel context panel.

### Verification
- Connector retry / fallback behavior is covered.
- Share history listing and filtering are covered by API tests.

## Phase 8: Observability and Operations (1-2 weeks) [~] code complete, rollout validation pending

### Backend
- Metrics added for command latency, AI fallback rate, and WS fanout failures.
- Health endpoints include integration readiness and observability snapshots.
- SLOs and alert thresholds are defined for key routes.

### Frontend
- Lightweight opt-in telemetry events are implemented for key room actions.
- Non-blocking status banner exists for degraded backend modes.

### Verification
- Room messaging / command load smoke script exists and passes local verification.
- Remaining gap: validate dashboard and alert wiring in staging.

## Remaining Delivery Focus

- Finish Flutter widget coverage for artifact review, compare flows, and status rendering.
- Tighten artifact review UX where compare/review affordances are still rough.
- Validate observability dashboards and alert routing in staging.
- Update operator playbook / runtime docs when alert wiring is confirmed.
- Add additional export connectors (`drive`, `jira`, `asana`) when product priority justifies them.

## Detailed Backlog by Area

## Backend Services
- `backend/src/routes/rooms.js`
  - Maintain validation and requestId consistency as new routes are added.
- `backend/src/services/roomOrchestrator.js`
  - Harden command parser edge cases.
  - Keep share/export orchestration aligned with connector abstraction.
- `backend/src/services/roomWS.js`
  - Add event-level guards for malformed payloads.
- `backend/src/services/exportConnectors.js`
  - Add future providers (`drive`, `jira`, `asana`) behind the same retry/idempotency contract.

## Frontend Flutter
- `frontend_flutter/lib/screens/salon_chat_screen.dart`
  - Continue polishing artifact review and compare affordances.
- `frontend_flutter/lib/providers/room_provider.dart`
  - Preserve requestId-aware error handling as room flows expand.
- `frontend_flutter/lib/services/room_service.dart`
  - Extend typed error mapping for any new connectors or review flows.
- `frontend_flutter/lib/models/room.dart`
  - Extend models only when new review/export features are added.

## Test and CI
- Backend:
  - Maintain coverage for validation, idempotency, and observability payloads as routes evolve.
- Flutter:
  - Add widget tests for review flows, compare UI, and degraded banner behavior.
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