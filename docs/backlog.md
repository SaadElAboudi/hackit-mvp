# Hackit MVP Backlog

Status legend: [ ] not-started · [~] in-progress · [x] completed

## Product & UX
- [ ] (1) Clarify MVP Scope — Define core user journey: ask question → AI summary → video list → detail view across web/mobile/flutter.
- [ ] (25) Accessibility Review — Audit color contrast, semantics, focus order; fix issues; add tests.
- [ ] (26) Dark Mode Support — Implement theme switching for RN and Flutter; persist preference.
- [ ] (31) Error UX Improvements — User-friendly retry + fallback suggestions on provider failures.
- [ ] (33) Monetization Placeholder — Optional ad-slot/subscription gating placeholder (no billing yet).

## Backend (Node/Express)
- [ ] (2) Backend Env Standardization — Create `.env.example` with OPENAI, GEMINI, YT, MOCK_MODE, REAL_MODE, CACHE_TTL, RATE_LIMIT.
- [ ] (3) Rate Limiting — Protect `/api/search` with express-rate-limit.
- [ ] (4) Request Logging — Add pino/winston with correlation IDs; log latency and external API calls.
- [ ] (5) Services Abstraction — Unified AI provider interface (OpenAI/Gemini) with fallback + circuit breaker.
- [ ] (6) YouTube Pagination — Support `nextPageToken` and multiple pages.
- [ ] (7) Video Transcript Ingestion — Endpoint to fetch/summarize transcripts; cache transcripts.
- [ ] (8) Caching Layer — In-memory + optional Redis cache with configurable TTL.
- [ ] (9) Error Handling Middleware — Map errors to structured JSON problem format.
- [ ] (18) Unit Tests — Tests for gemini.js, openai.js, youtube.js using nock; target 70% coverage.
- [ ] (19) Integration Smoke (REAL) — Hit `/api/search` with live YouTube; verify non-mock path.
- [ ] (21) Input Validation — zod/joi schemas for request bodies.
- [ ] (22) Observability Metrics — Basic metrics: request_count, latency, cache_hit, provider_failures.
- [ ] (23) Performance Profiling — Baseline average search latency; optimize parallel provider calls.
- [ ] (32) Video Platform Expansion — Add TikTok/alt provider behind abstraction; flag source in response.
- [ ] (34) Feature Flags — Lightweight flag config (JSON + env) for experimental providers.
- [ ] (35) Refactor searchController — Extract pure functions; improve testability.
- [ ] (39) OpenAI Cost Guard — Token usage estimation + soft hourly cap.
- [ ] (40) Gemini/OpenAI Failover — Timeout >2s triggers fallback; record usage stats.

## Frontend (React Native)
- [ ] (10) Navigation — Ensure stack navigation + deep linking (question → results → video).
- [ ] (11) Offline State — Offline detection banner; queue queries until connectivity returns.
- [ ] (31) Error UX — Friendly retry flows and diagnostics in UI.

## Frontend (Flutter)
- [ ] (12) State Management — Introduce Bloc or Riverpod for search feature; test scaffolding (`search_bloc_test`).
- [ ] (13) Search Feature Completion — Search screen, results list, video detail, summary widget calling backend API.
- [ ] (24) Internationalization — i18n (en/fr); externalize strings; language switch.
- [ ] (37) Golden Tests — Add golden tests for summary widget and result list.

## Shared Contracts & Types
- [ ] (14) Shared Type Definitions — Consolidate search result/summary types in `shared/types`; generate from OpenAPI.
- [ ] (15) API Contract Spec — OpenAPI 3 spec for search + transcript endpoints; publish JSON.

## CI/CD
- [ ] (16) Lint Gates — ESLint + TS checks; Dart analyze + format checks in Flutter CI.
- [ ] (17) Test Matrix — Unit + integration tests across Node versions and Flutter channels.
- [ ] (38) Dependency Updates — Configure Dependabot for npm + pub weekly.

## Security & Privacy
- [ ] (20) Security Audit — Address npm audit/pub outdated issues; add resolutions.
- [ ] (28) Privacy Policy — Draft markdown explaining data usage, retention, third-party APIs.

## Analytics & Metrics
- [ ] (27) Analytics Instrumentation — Event tracking (query_submitted, result_clicked) with privacy toggle.

## Docs & Architecture
- [ ] (29) README Feature List — Populate README features with current capabilities; link diagram.
- [ ] (30) Architecture Diagram — High-level diagram (frontends → backend → providers) in `docs/`.

---

### Suggested Near-Term Priorities (first 2 sprints)
1. (2) Env standardization, (9) error handling, (21) input validation
2. (5) Provider abstraction with (40) failover and (3) rate limiting
3. (13) Flutter search feature + (12) state management
4. (18) Backend unit tests + (16) CI lint gates

### Acceptance Criteria Example
- (3) Rate Limiting: Requests to `/api/search` exceeding 60/min from same IP receive 429 with `Retry-After`; included unit test and configuration via env.
- (13) Flutter Search: Given a query and reachable backend, results list shows ≥1 item with title, summary snippet, and playable link; error state and loading skeleton covered by tests.
