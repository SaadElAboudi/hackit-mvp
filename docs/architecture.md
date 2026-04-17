# Hackit MVP Architecture

## System Overview

```text
Flutter client (web/desktop)
      -> REST API (/api/rooms, /api/search, integrations)
      -> WebSocket (/ws/rooms/:roomId)

Node backend (orchestrator + routes + services)
      -> Gemini provider (generation/streaming)
      -> External integrations (Slack, Notion)
      -> Search providers (YouTube and fallbacks)
      -> MongoDB Atlas (rooms, messages, artifacts, missions, memory)
```

## Product-Centric Modules

### Channels Layer ("Salons")
- Product naming is `Channels`/`Salons` in UI.
- Backend keeps `rooms` naming for API and persistence compatibility.
- Core entities are room-scoped: messages, artifacts, missions, memory, decisions.

### AI Orchestration Layer
- Main entry point: `backend/src/services/roomOrchestrator.js`.
- Responsibilities:
      - Parse mention and slash command intents.
      - Execute command handlers (`/doc`, `/search`, `/decide`, `/brief`, `/share`, `/mission`).
      - Manage proactive suggestions (synthesis and brief) with cooldown and thresholds.
      - Apply mission agent profile behavior.
      - Emit channel-safe system messages and outputs.

### Real-Time Layer
- Main hub: `backend/src/services/roomWS.js`.
- Broadcasts normalized events for messages, chunks, mission status, artifacts, and integration results.
- Frontend applies these events in `frontend_flutter/lib/providers/room_provider.dart`.

### Integrations Layer
- Slack service: `backend/src/services/slack.js`.
- Notion service: `backend/src/services/notion.js`.
- Room-scoped credentials/config in `Room.integrations.*`.
- Trigger path:
      - Direct REST endpoints for connect/disconnect/status.
      - Command path via `/share slack|notion` in orchestrator.

### Data Layer (MongoDB)
- `Room`: metadata, visibility, purpose, integration configs.
- `RoomMessage`: persisted conversation stream and structured system events.
- `RoomArtifact` and `ArtifactVersion`: shared docs/canvas and revision history.
- `RoomMission`: mission lifecycle and selected agent profile.
- `RoomMemory`: explicit reusable context facts/decisions.

## Frontend Architecture (Flutter)

- Screen composition centers around `salon_chat_screen.dart` for channel collaboration.
- Data flow:
      - `room_service.dart` for REST calls.
      - `room_provider.dart` for state management and WS event reconciliation.
      - `room.dart` for typed models and WS event enums.
- UX primitives in current scope:
      - Streaming AI responses.
      - Artifact/research/brief/synthesis cards in channel timeline.
      - Mission creation with agent profile selection.

## Deployment Topology

- Backend:
      - Render service (Node runtime) using `render.yaml`.
- Frontend:
      - Flutter web build published from `frontend_flutter/gh-pages`.
      - GitHub Pages hosting for static assets.

## Quality and Verification

- Backend has automated test coverage for:
      - Orchestrator command flows.
      - WebSocket event behavior.
      - Slack and Notion integration services.
- Flutter validation is done via analyzer and widget/integration tests in `frontend_flutter/test` and `frontend_flutter/integration_test`.

## Current Boundaries

- Private AI draft mode is not yet the primary path; shared channel AI is the first-class mode.
- Product and docs are standardizing around channel collaboration; legacy search-only language should be considered deprecated.
