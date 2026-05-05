# Unified Product Backlog (Single Source of Truth)

Last updated: 2026-05-05

This file is the only prioritized backlog reference for product, engineering, and release planning.

## Governance

- `docs/backlog.md` is the unique source of truth for priorities.
- `docs/implementation_roadmap.md`, `docs/features.md`, and `docs/issues_plan.md` are context/reference docs only.
- Any new feature proposal must be added here with: business impact, effort, priority, and target phase.

## Status Legend

- `[x]` done
- `[~]` in progress / partially delivered
- `[ ]` not started

## Current Baseline (Delivered)

- [x] Shared AI in channels with slash commands (`/doc`, `/search`, `/decide`, `/brief`, `/mission`, `/share`)
- [x] Slack/Notion integration flows (connect/disconnect/status/share)
- [x] Core artifact lifecycle backend (comments, versions, status transitions)
- [x] Reliability hardening (validation, requestId propagation, rate-limiting on command-heavy routes)
- [x] Observability stack (health endpoints, SLO thresholds/alerts, smoke script, degraded banner, opt-in telemetry)

## Prioritization Framework

Scoring guidance used for ordering:

- `Impact` (1-5): user/business value
- `Urgency` (1-5): risk reduction / dependency unlock
- `Effort` (1-5): implementation complexity
- Priority score = `(Impact * Urgency) / Effort`

### KPI Impact Requirement (new)

Every new backlog item must declare:

- Primary KPI impacted (one of: activation rate, useful-answer rate, export rate, D7 retention, API reliability)
- Expected directional effect (e.g. `+10% export rate`, `-15% retry rate`)
- Time-to-impact expectation (`<2 weeks`, `2-6 weeks`, `>6 weeks`)

This rule prevents feature sprawl and keeps planning tied to business outcomes.

## Phase Plan (Roadmap)

### Phase A - Stabilization and Operational Sign-off (Now)

Goal: close remaining quality/ops gaps on already shipped capabilities.

1. [~] Flutter widget coverage for artifact review/compare/status and degraded banner
2. [ ] Staging validation for observability dashboards + alert routing
3. [ ] Operator playbook finalization after staging validation

### Phase B - Product Trust and Feedback (Next)

Goal: increase user trust and close the quality loop.

1. [x] Explicit feedback loop (pertinent/moyen/hors-sujet + reason)
2. [x] Trust & explainability blocks (why-this-plan, assumptions, limits, confidence)
3. [ ] Product KPI instrumentation dashboard (TTV, save rate, regenerate rate, feedback score, export rate)

### Phase C - Execution and Packaging (Next+1)

Goal: move from "good answer" to "ready to execute" outputs.

1. [ ] Execution export (Notion/Trello/Asana/CSV)
2. [ ] Output modes (executive one-pager vs team checklist)
3. [ ] Domain template packs v2 (Marketing, Product, Ops, Sales, Agency)

### Phase D - Search Intelligence Expansion (Later)

Goal: improve depth, relevance, and discovery quality.

1. [ ] Transcript fetch + cache layer
2. [ ] Summaries with citations + timestamp links
3. [ ] Automatic chapterization
4. [ ] Hybrid search embeddings + rerank
5. [ ] Entity extraction, related content, diversity/dedup, freshness/safe-search

### Phase E - Absolute Productivity System (New)

Goal: become the daily execution operating system for employees.

1. [~] My Day cockpit (Top 3 priorities, blockers, due today)
2. [ ] Unified Work Inbox (channels/events to actionable queue)
3. [ ] Meeting Copilot (recap -> decisions -> tasks)
4. [~] Auto follow-up engine (nudges, overdue recovery, escalation)
5. [ ] ROI instrumentation pack (time saved, completion, cycle-time)

Reference execution plan: `docs/productivity_absolute_backlog_2026-05-05.md`

## Prioritized Backlog (Master List)

| ID | Item | Status | Priority | Phase | Impact | Effort | Notes |
|---|---|---|---|---|---|---|---|
| BL-001 | Flutter widget tests for artifact review/compare/status | [~] | P0 | A | High | M | Partially landed; finish coverage gaps |
| BL-002 | Validate observability dashboards and alert routing in staging | [~] | P0 | A | High | S | Pre-release gate: deferred for now; local quality gate + observability audit automation are active |
| BL-003 | Update operator runtime playbook | [~] | P0 | A | High | S | Playbook now includes automated audit runbook; final owner names and staging sign-off pending |
| BL-004 | Artifact review UX polish | [ ] | P1 | A | Medium | M | Reduce friction in compare/review flows |
| BL-005 | Explicit feedback loop on AI relevance | [x] | P0 | B | High | M | Backend/UI/instrumentation v1 shipped with tests + KPI baseline evidence |
| BL-006 | Trust & explainability sections in outputs | [x] | P0 | B | High | M | Completed with backend + frontend trust payload/rendering tests |
| BL-007 | Product KPI instrumentation dashboard | [x] | P1 | B | High | M | Enables KPI-driven prioritization |
| BL-008 | Execution export (Notion/Trello/Asana/CSV) | [x] | P0 | C | High | M/L | Turns insight into action |
| BL-009 | Output modes (one-pager vs checklist) | [x] | P1 | C | Medium | M | Persona-fit packaging |
| BL-010 | Domain templates v2 (vertical packs) | [ ] | P1 | C | Medium | M | Quality by domain |
| BL-011 | Additional connectors (Drive/Jira/Asana) | [ ] | P2 | C | Medium | M | Only if priority justifies |
| BL-012 | Transcript fetch + caching layer | [ ] | P1 | D | High | M | Dependency for deep citation quality |
| BL-013 | Summaries with citations and timestamps | [ ] | P1 | D | High | M | Core search trust feature |
| BL-014 | Automatic chapterization | [ ] | P2 | D | Medium | M | Depends on BL-012 |
| BL-015 | Hybrid search embeddings + rerank | [ ] | P2 | D | Medium | L | Later-phase relevance optimization |
| BL-016 | Entity extraction and topic tags | [ ] | P2 | D | Medium | M | Discovery enhancement |
| BL-017 | Related suggestions + diversity/dedupe + freshness/safe-search | [ ] | P2 | D | Medium | M/L | Ranking quality track |
| BL-018 | Accessibility review (contrast, focus, semantics) | [ ] | P1 | A/B | High | M | Quality gate for scaling usage |
| BL-019 | Internationalization (en/fr) | [ ] | P2 | C/D | Medium | M | User expansion |
| BL-020 | Security audit + privacy policy update | [ ] | P1 | A/B | High | M | Compliance and risk reduction |
| BL-021 | My Day cockpit (daily execution center) | [~] | P0 | E | High | M | E1 delivered (API/UI/actions/nudges/reminders); production hardening + E2 extensions pending |
| BL-022 | Unified Work Inbox | [ ] | P0 | E | High | M/L | Primary KPI: intake-to-action time |
| BL-023 | Meeting Copilot (decisions to tasks) | [ ] | P0 | E | High | M/L | Primary KPI: decision-to-task conversion |
| BL-024 | Auto follow-up engine (nudges + escalation) | [~] | P0 | E | High | M | In-app nudges/reminders/snooze shipped; escalation policies and external channels pending |
| BL-025 | Copilot action library (role templates) | [ ] | P1 | E | Medium | M | Primary KPI: time saved per user |
| BL-026 | Team workload risk detection | [ ] | P1 | E | Medium | M | Primary KPI: blocked task duration |
| BL-027 | Persona dashboards with action prompts | [ ] | P2 | E | Medium | M | Primary KPI: WAU by role |
| BL-028 | ROI instrumentation pack | [ ] | P1 | E | High | S/M | Required for adoption proof |

BL-006 closure evidence (2026-04-29):
- Backend: `npm test -- test/room.orchestrator.test.js test/room.trust.v1.test.js` (8/8 pass)
- Frontend: `flutter test test/screens/salon_chat_explainability_v1_test.dart` (+2 pass)

## Sprint 1 Execution Plan (Ready to Build)

Sprint goal: close Phase A operational sign-off and start Phase B product loop.

### Scope Locked

- `BL-002` Validate observability dashboards + alert routing in staging
- `BL-003` Update operator runtime playbook
- `BL-005` Explicit feedback loop on AI relevance (v1)

### Sprint Deliverables

1. Observability validation report with pass/fail evidence for staging
2. Updated operator playbook with runbooks for alert handling
3. Feedback v1 in product: rating + reason capture + event logging

### Ticket Breakdown

#### S1-01 - Staging observability validation run

- Backlog link: `BL-002`
- Type: Ops/QA
- Estimate: `S` (1-2 days)
- Dependencies: staging environment + dashboard access
- Tasks:
	- Execute `docs/observability_staging_checklist.md` end-to-end
	- Validate `/health`, `/health/integrations`, `/health/observability`
	- Validate alert visibility and routing for key codes (`slo_latency_breach`, `ws_fanout_failures`, `persistent_alerts`)
	- Record timestamped evidence (screenshots/logs/links)
- Acceptance criteria:
	- Checklist completed with explicit pass/fail per step
	- No unresolved critical alert routing gaps
	- Validation report linked in release notes

#### S1-02 - Operator playbook finalization

- Backlog link: `BL-003`
- Type: Docs/Ops
- Estimate: `S` (0.5-1 day)
- Dependencies: `S1-01`
- Tasks:
	- Document response actions per alert code and severity
	- Add escalation path + owner matrix
	- Add rollback/degraded-mode decision tree
	- Add quick commands and dashboard links for first-response
- Acceptance criteria:
	- On-call can execute first response in under 10 minutes
	- Playbook reviewed by engineering lead
	- Playbook location linked from this backlog

#### S1-03 - Feedback loop backend contract (v1)

- Backlog link: `BL-005`
- Type: Backend/API
- Estimate: `M` (2-3 days)
- Dependencies: none
- Tasks:
	- Define API payload for relevance feedback (`rating`, `reason`, metadata)
	- Persist events with room/message context
	- Add validation and error envelope consistency
	- Expose simple aggregate endpoint for product analytics seed
- Acceptance criteria:
	- Invalid payloads rejected with standard error contract
	- Events persisted and queryable by date and rating
	- Tests cover happy path + validation failures
- Delivery status:
	- Implemented with validation + aggregate endpoint + tests (`backend/test/room.feedback.v1.test.js`)
	- Status: done

#### S1-04 - Feedback loop UI capture (v1)

- Backlog link: `BL-005`
- Type: Flutter
- Estimate: `M` (2-3 days)
- Dependencies: `S1-03`
- Tasks:
	- Add UI actions for `pertinent`, `moyen`, `hors-sujet`
	- Capture optional reason for low relevance
	- Submit feedback non-blocking (no UX stall on failure)
	- Add user confirmation and retry affordance
- Acceptance criteria:
	- User can submit rating in <=2 taps (without reason)
	- Reason prompt appears for `moyen` and `hors-sujet`
	- Submission failures surface recoverable retry
	- Widget tests cover display and submission states
- Delivery status:
	- Implemented in salon chat flow with widget coverage (`frontend_flutter/test/screens/salon_chat_feedback_v1_test.dart`)
	- Status: done

#### S1-05 - Feedback instrumentation + KPI baseline

- Backlog link: `BL-005`, `BL-007`
- Type: Data/Product analytics
- Estimate: `S` (1 day)
- Dependencies: `S1-03`, `S1-04`
- Tasks:
	- Log events for feedback submitted/retried/failed
	- Create baseline metrics query (feedback rate, rating distribution)
	- Publish initial KPI snapshot in sprint report
- Acceptance criteria:
	- Dashboard/query returns daily feedback volume and split
	- KPI snapshot shared at sprint close
- Evidence:
	- Local baseline snapshot (2026-04-29): `docs/feedback_kpi_baseline_2026-04-29.md`
	- Provider analytics instrumentation tests (`frontend_flutter/test/providers/room_provider_feedback_analytics_test.dart`)
	- Status: done (local baseline captured)

### Sprint Exit Criteria

1. `BL-002` and `BL-003` are marked done with linked evidence.
2. `BL-005` v1 is in production behind a safe rollout switch if needed.
3. At least one week of feedback baseline data is collectible post-release.

### Out of Scope (Do Not Expand)

- Export connectors expansion (`BL-011`)
- Explainability blocks (`BL-006`)
- Search intelligence track (`BL-012` to `BL-017`)

## Sprint 2-3 Product Evolution Plan (Feature-First)

Objective: prioritize product evolution with direct KPI impact and short feedback loops.

### Sprint 2 (2 weeks)

Scope cap: max 3 tickets

1. `BL-007` Product KPI dashboard (v1)
- Primary KPI: activation rate, useful-answer rate, export rate
- Expected effect: +10% faster prioritization cycle (data-driven decisions)
- Time-to-impact: `<2 weeks`
- Deliverables:
	- Daily metrics view: `TTV`, `save rate`, `regenerate rate`, `feedback score`, `export rate`
	- Filter by date range and room/template
	- Baseline snapshot linked in this backlog

2. `BL-008` Execution export (v1: Notion + CSV)
- Primary KPI: export rate
- Expected effect: `+15% export rate`
- Time-to-impact: `2-6 weeks`
- Deliverables:
	- One-click export from decision pack
	- Export history status + retry surface
	- Endpoint and UI tests for success/failure/retry

3. `BL-009` Output modes in decision pack (exec/checklist)
- Primary KPI: useful-answer rate
- Expected effect: `+10% useful-answer rate`
- Time-to-impact: `<2 weeks`
- Deliverables:
	- Mode selector in UI
	- Stable API contract by mode
	- Snapshot tests for both render modes

Sprint 2 exit criteria:
1. KPI dashboard v1 is used in weekly product review.
2. Notion/CSV export completion rate is measurable.
3. At least one active room uses both output modes.

### Sprint 3 (2 weeks)

Scope cap: max 3 tickets

1. `BL-010` Domain templates v2 (2 vertical packs first)
- Primary KPI: activation rate
- Expected effect: `+12% activation rate`
- Time-to-impact: `2-6 weeks`
- Deliverables:
	- Launch first 2 packs: Product + Marketing
	- Template chooser copy + outcome examples
	- Quality benchmark checklist per pack

2. `BL-012` Transcript fetch + caching layer (v1)
- Primary KPI: useful-answer rate
- Expected effect: `-20% timeout/retry on transcript-based flows`
- Time-to-impact: `2-6 weeks`
- Deliverables:
	- Fetch pipeline with bounded cache TTL
	- Fallback behavior when transcript unavailable
	- Latency and failure telemetry

3. `BL-013` Summaries with citations + timestamps (v1)
- Primary KPI: D7 retention
- Expected effect: `+8% D7 retention`
- Time-to-impact: `2-6 weeks`
- Deliverables:
	- Citation blocks in summary outputs
	- Timestamp deep-links in UI
	- Relevance checks in test fixtures

## PA-001 Delivery Plan (My Day cockpit, build-ready)

Goal: deliver a first production version of `My Day` that helps each employee execute daily priorities with less friction.

Backlog links:
- `BL-021` My Day cockpit
- `BL-024` Auto follow-up engine (partial)
- `BL-028` ROI instrumentation pack (baseline)

### Scope (Sprint E1, 2 weeks)

1. Daily priority panel (Top 3)
2. Blockers panel
3. Due-today panel
4. Waiting-for panel
5. In-app follow-up nudges (MVP)
6. Event tracking for DES proxy

### Delivery status (2026-05-05)

- E1-01/E1-02/E1-03 delivered (`fd40fd0`)
- E1-04 delivered (`405f26f`)
- E1-05/E1-06 delivered (`af19c8c`, `5129679`)
- E1-07/E1-08 delivered (`e22878a`)
- Local end-to-end smoke validated with Mongo enabled (`my-day`, `nudges`, `reminders`, `snooze`, `instrumentation` all `200`)

### Ticket Breakdown

#### E1-01 - My Day API contract (aggregated endpoint)

- Type: Backend/API
- Estimate: `M` (2-3 days)
- Dependencies: none
- Tasks:
	- Add `GET /api/rooms/:id/my-day` aggregated endpoint
	- Return typed payload sections: `top3`, `blocked`, `dueToday`, `waitingFor`
	- Include per-item metadata: `id`, `kind`, `title`, `ownerName`, `dueDate`, `priority`, `sourceUrl`
	- Support deterministic ordering and stable response envelope (`ok`, `requestId`)
- Acceptance criteria:
	- Endpoint returns within 400ms p50 (local baseline)
	- Empty state returns valid typed arrays (no null-shape regressions)
	- Contract tests cover success + validation + unauthorized room access

#### E1-02 - My Day prioritization service

- Type: Backend/Domain logic
- Estimate: `M` (2-3 days)
- Dependencies: `E1-01`
- Tasks:
	- Implement scoring for Top 3 priorities (due-date risk, block status, priority weight, dependency count)
	- Add safeguards: never include completed items
	- Add `whyRanked` short explanation per top item
	- Add unit tests for ranking determinism
- Acceptance criteria:
	- Same input set yields same ranked Top 3
	- Overdue blocked item always outranks low-priority non-risk item
	- `whyRanked` is present for each top item

#### E1-03 - My Day screen (Flutter)

- Type: Frontend/Flutter
- Estimate: `M` (2-3 days)
- Dependencies: `E1-01`
- Tasks:
	- Create `my_day_screen.dart` and add entry point in root navigation
	- Render 4 sections with loading/empty/error states
	- Add one-click actions on items: `mark done`, `defer`, `ping owner`, `open context`
	- Add pull-to-refresh and request-id debug affordance in error state
- Acceptance criteria:
	- My Day is reachable in <=1 tap from app home
	- Each item action works in <=2 taps
	- Empty state provides guided CTA ("Generate priorities")
	- Widget tests cover loading/empty/content/error

#### E1-04 - Action handlers and optimistic updates

- Type: Frontend + Backend integration
- Estimate: `M` (2 days)
- Dependencies: `E1-03`
- Tasks:
	- Wire actions to existing task/decision endpoints
	- Add optimistic UI state update and rollback on failure
	- Add retry mechanism for transient errors (`429`, `5xx`)
	- Track action outcomes (`success`, `retry`, `failed`)
- Acceptance criteria:
	- Action latency feels instant (optimistic update <150ms perceived)
	- Rollback path restores consistent state on failure
	- No duplicate action submissions on rapid taps

#### E1-05 - In-app follow-up nudges (MVP)

- Type: Backend + Frontend
- Estimate: `S/M` (1-2 days)
- Dependencies: `E1-01`
- Tasks:
	- Generate nudge candidates for overdue/due-soon/waiting-too-long
	- Show non-intrusive nudge cards in My Day
	- Support `snooze` and `dismiss` actions with reason
	- Persist nudge interactions for analytics
- Acceptance criteria:
	- Nudge rules fire only for actionable items
	- Snooze prevents repeat nudge until expiry
	- Dismiss reason is stored and queryable

#### E1-06 - DES instrumentation baseline

- Type: Analytics/Data
- Estimate: `S` (1 day)
- Dependencies: `E1-03`, `E1-04`
- Tasks:
	- Define event schema: `my_day_opened`, `my_day_action_clicked`, `my_day_action_completed`
	- Compute DES proxy: users completing >=3 priority actions/day
	- Add daily snapshot script and markdown report template
	- Add validation test for event payload schema
- Acceptance criteria:
	- DES proxy is computable daily from captured events
	- Event schema versioning documented
	- First baseline report published after 3 days of data

### Sprint E1 Exit Criteria

1. `My Day` is available in production UI for all active channels.
2. Top 3 priorities are visible and actionable for users with open work.
3. DES proxy is measurable from analytics events.
4. Overdue ratio trend can be compared pre/post rollout.

### Out Of Scope (E1)

1. External notification channels (email/Slack nudges)
2. Role-specific dashboards (`BL-027`)
3. Advanced workload prediction (`BL-026` full)

## PA-004 Delivery Plan (Auto follow-up engine MVP, E1 reminder rules phase)

Goal: deliver reminder rules infrastructure during Sprint 1 to enable task owner nudges across all work items.

### Scope (Sprint E1, weeks 1-2, partial)

1. Reminder rules engine (due-soon, overdue, blocked thresholds)
2. In-app reminder UI (non-intrusive cards/badges)
3. Snooze and dismiss with persistence
4. Event tracking for reminder interactions

### Ticket Breakdown

#### E1-07 - Reminder rules engine

- Type: Backend/Domain logic
- Estimate: `M` (2-3 days)
- Dependencies: task/decision model maturity (pre-existing)
- Tasks:
	- Implement rule evaluator for: `dueIn(N days)`, `overdueBy(N days)`, `blockedDays(N)`
	- Add rule composition: users can create custom rules via settings
	- Compute candidate reminders for all users/rooms on hourly cadence
	- Cache computed reminders in memory with TTL=1h
- Acceptance criteria:
	- Rule engine correctly identifies tasks matching each condition
	- Duplicate reminders across reloads are eliminated
	- Hourly compute completes within 2s for baseline data volume

#### E1-08 - Reminder presentation and interactions

- Type: Frontend + Backend/API
- Estimate: `M` (2 days)
- Dependencies: `E1-07`
- Tasks:
	- Add `GET /api/rooms/:id/reminders` endpoint returning candidates for current user
	- Create reminder notification card component (non-blocking, dismissable)
	- Implement snooze action (options: 1h, 1d, 1w) persisting to user preferences
	- Implement dismiss action with optional reason (pick from: "not ready", "false alarm", "done", "other")
	- Wire dismiss/snooze to analytics for rule quality tracking
- Acceptance criteria:
	- Reminders surface within 2 minutes of condition becoming true
	- Snooze successfully prevents re-trigger until expiry
	- Dismiss reason is queryable for rule tuning

### Sprint E1 Partial Exit (PA-004 MVP)

1. Reminder rules execute hourly for all configured conditions.
2. Users can view and dismiss reminders in-app without breaking focus.

## PA-002 Delivery Plan (Unified Work Inbox, build-ready, E2 scope)

Goal: deliver a single aggregated inbox where users can triage all incoming work requests (channels, task events, integrations) and convert them to actionable tasks.

Backlog links:
- `BL-022` Unified Work Inbox
- `BL-024` Auto follow-up engine (partial)

### Scope (Sprint E2, weeks 3-4)

1. Inbox data model and aggregation API
2. Inbox UI with filters and sorting
3. Convert-to-task and assign-owner flows
4. SLA tracking and visibility
5. Intake-to-action event instrumentation

### Ticket Breakdown

#### E2-01 - Inbox data model and aggregation API

- Type: Backend/API
- Estimate: `M` (2-3 days)
- Dependencies: existing room/task/channel models
- Tasks:
	- Create `InboxItem` entity: `{ id, type (task|decision|message|event), sourceId, title, description, channel, createdBy, createdAt, dueDate, priority, sla }`
	- Implement `GET /api/rooms/:id/inbox` endpoint aggregating: new task mentions, unassigned decisions, channel messages tagged with emoji reactions, task updates
	- Support cursor pagination (1000 items max per page)
	- Return items ordered by SLA risk then creation date
- Acceptance criteria:
	- Inbox query returns <400ms p50 for rooms with <= 500 inbox items
	- Empty inbox returns valid empty array
	- SLA calculation is deterministic (due date relative to creation + priority)

#### E2-02 - Inbox UI and filtering

- Type: Frontend/Flutter
- Estimate: `M` (2-3 days)
- Dependencies: `E2-01`
- Tasks:
	- Create `inbox_screen.dart` with list view of inbox items
	- Render each item with: source icon, title, channel, SLA badge (color-coded: green/yellow/red)
	- Implement filter toggles: `mine`, `team`, `unassigned`, `overdue`
	- Add search field filtering by title/description/channel
	- Implement pull-to-refresh and infinite scroll
- Acceptance criteria:
	- Inbox loads in < 2s for p50 users
	- Filter combinations work without race condition
	- Item swipe action shows context menu (open/assign/convert/snooze)

#### E2-03 - Convert-to-task flow

- Type: Frontend + Backend integration
- Estimate: `M` (2 days)
- Dependencies: `E2-02`
- Tasks:
	- Add "Convert to Task" action on inbox item
	- Show modal: title (pre-filled from inbox item), description, owner dropdown, due-date picker
	- Implement `POST /api/rooms/:id/inbox/:itemId/convert-to-task` endpoint
	- On success, remove item from inbox and open new task in focus
	- Add error retry for transient failures
- Acceptance criteria:
	- Conversion completes < 2s visible latency
	- Converted task is immediately visible in My Day and Kanban
	- Source item is removed from inbox (no duplicate)

#### E2-04 - SLA and intake tracking

- Type: Backend + Analytics
- Estimate: `S/M` (1-2 days)
- Dependencies: `E2-01`
- Tasks:
	- Define intake event schema: `inbox_item_appeared`, `inbox_item_converted`, `inbox_item_dismissed`, `inbox_item_assigned`
	- Compute SLA metrics: median time from appearance to conversion, % converted within SLA
	- Add SLA configuration per room (default: 24h)
	- Add validation test for SLA calculation accuracy
- Acceptance criteria:
	- SLA metrics are queryable by room
	- Intake-to-action median time is visible in weekly report
	- Event schema is backward-compatible

### Sprint E2 Partial Exit (PA-002)

1. Unified inbox is available for all rooms and shows all aggregated work types.
2. Users can convert inbox items to tasks with full attribution.
3. SLA tracking provides visibility into intake hygiene.

## PA-005 Delivery Plan (Copilot Actions library MVP, E2 scope)

Goal: deliver a library of high-value templated actions that employees can run to accelerate repetitive work (briefs, recaps, handoffs, client updates).

Backlog links:
- `BL-025` Copilot Actions library v1

### Scope (Sprint E2, weeks 3-4)

1. Action template model and storage
2. Action execution and output rendering
3. Five starter actions (brief, recap, client update, handoff, standup)
4. Action usage and quality tracking

### Ticket Breakdown

#### E2-05 - Action template model and API

- Type: Backend/API + Domain logic
- Estimate: `M` (2-3 days)
- Dependencies: existing artifact/decision/task models
- Tasks:
	- Create `ActionTemplate` entity: `{ id, name, slug, description, icon, category, inputSchema, outputFormat }`
	- Create `ActionExecution` entity: `{ id, templateId, roomId, userId, inputs, output, status, createdAt, executionTimeMs }`
	- Implement `GET /api/templates` (list all available)
	- Implement `POST /api/templates/:id/execute` with validation against inputSchema
	- Add retry logic for transient execution failures
- Acceptance criteria:
	- Action execution returns within 5s p95 (with AI call)
	- Input validation rejects invalid schemas
	- Execution history is queryable per user/room

#### E2-06 - Copilot Actions UI and template library

- Type: Frontend/Flutter
- Estimate: `M` (2-3 days)
- Dependencies: `E2-05`
- Tasks:
	- Create `copilot_actions_screen.dart` showing action cards in grid (icon, name, description)
	- On tap, show action input form (dynamic based on inputSchema)
	- Show loading state during execution
	- Render output in full-page panel with one-click actions: copy, share, export, regenerate
	- Track which actions user has run (usage heatmap)
- Acceptance criteria:
	- Actions load in < 1s
	- Input form renders all field types (text, dropdown, multi-select, date)
	- Output copy/share/export work without additional modal steps

#### E2-07 - Starter actions implementation

- Type: Backend/AI integration
- Estimate: `L` (3-4 days)
- Dependencies: `E2-05`, existing Gemini integration
- Tasks:
	- Implement 5 actions:
		1. `brief`: summarize decision/artifact for stakeholder audience
		2. `recap`: generate meeting recap from transcript and notes
		3. `client_update`: format decision as client-facing update email
		4. `handoff`: structured handoff notes for next owner
		5. `standup`: compose status update from completed tasks
	- Each action takes context (artifact/meeting/decision ID) and user-selected output format
	- Actions support export to markdown, notion, email draft
	- Add A/B variant tracking for output quality
- Acceptance criteria:
	- All 5 actions execute successfully in sandbox testing
	- Output quality is >3.0 avg self-reported score
	- Export to each format preserves formatting

### Sprint E2 Partial Exit (PA-005)

1. Five templated actions are available in production.
2. Users can run actions in < 30 seconds from discovery to output.
3. Action usage tracking is operational.

## PA-001 Extension (Action controls in My Day, E2 scope)

Goal: extend My Day with full action control suite enabling task state transitions without leaving the screen.

### Ticket Breakdown

#### E2-08 - My Day advanced actions

- Type: Frontend + Backend integration
- Estimate: `M` (2 days)
- Dependencies: `E1-03`, `E1-04`
- Tasks:
	- Extend My Day actions beyond MVP: add `snooze`, `reassign`, `update-priority`, `link-to-decision`, `add-note`
	- Implement action menu on long-press (mobile) or right-click (web)
	- Add optimistic updates for all state transitions
	- Wire state changes to event stream for real-time sync across tabs
- Acceptance criteria:
	- All action types complete within 2s perceived latency
	- Tab synchronization shows updates within 1s
	- No stale state after action completion

### Sprint E2 Full Exit Criteria

1. Unified inbox is live for all teams.
2. Five Copilot actions are in public library.
3. My Day action controls are complete.
4. Intake-to-action pipeline metrics are visible.

## PA-003 Delivery Plan (Meeting Copilot MVP, build-ready, E3 scope)

Goal: deliver an AI-powered meeting assistant that transforms meeting context into structured decisions and auto-creates follow-up tasks without manual rewrite.

Backlog links:
- `BL-023` Meeting Copilot

### Scope (Sprint E3, weeks 5-6)

1. Meeting recap generation from transcript/notes
2. Decision extraction from meeting output
3. Auto-task creation from decisions with owner assignment
4. Meeting Copilot UI (end-meeting flow)
5. Decision-to-task conversion tracking

### Ticket Breakdown

#### E3-01 - Meeting context capture and recap generation

- Type: Backend/AI integration
- Estimate: `M` (2-3 days)
- Dependencies: existing decision/artifact models, Gemini integration
- Tasks:
	- Add `POST /api/rooms/:id/meetings/:meetingId/generate-recap` endpoint
	- Input: meeting transcript/recording transcription, optional meeting notes, attendee list
	- Use Gemini to generate recap (< 500 words) highlighting:
		- Key topics discussed
		- Decisions made
		- Action items (tentative)
		- Questions/blockers raised
	- Return structured output: `{ recap, topicsHighlighted[], decisionsFound[], actionItems[] }`
- Acceptance criteria:
	- Recap generation completes within 20s for 1h meeting
	- Recap accurately reflects meeting content (blind test scoring >= 3/5)
	- No PII leakage in generated recap

#### E3-02 - Decision extraction and structuring

- Type: Backend/Domain logic
- Estimate: `M` (2-3 days)
- Dependencies: `E3-01`
- Tasks:
	- Implement decision entity extraction: statement, owner, priority, due-date inference, affected parties
	- Use Gemini to categorize decision type (go-no-go, design-choice, resource-allocation, policy, other)
	- Add decision confidence scoring (high/medium/low) to indicate extraction certainty
	- Implement endpoint: `POST /api/rooms/:id/decisions/extract-from-recap` with inputs: recap text, attendee list
- Acceptance criteria:
	- Decision extraction identifies 80%+ of decisions mentioned in test set
	- Owner inference matches actual decision maker in 70%+ of cases
	- Low-confidence extractions are flagged for review

#### E3-03 - Auto-create tasks from decisions

- Type: Backend/API
- Estimate: `M` (2 days)
- Dependencies: `E3-02`
- Tasks:
	- Implement bulk task creation endpoint: `POST /api/rooms/:id/decisions/:decisionId/create-tasks`
	- Create task for each action item with: title, owner, due date, linked decision, priority
	- Add validation: owner must be in room members (fallback: unassigned for external stakeholders)
	- Persist decision-to-task linkage for traceability
	- Return list of created task IDs
- Acceptance criteria:
	- All action items are converted to tasks
	- Task owner is correct or flagged for clarification
	- Decision-task link is maintained through lifecycle

#### E3-04 - Meeting Copilot UI (end-meeting flow)

- Type: Frontend/Flutter
- Estimate: `M` (2-3 days)
- Dependencies: `E3-01`, `E3-02`, `E3-03`
- Tasks:
	- Create `meeting_copilot_screen.dart` showing end-meeting flow:
		1. Upload/paste meeting transcript or notes
		2. Show generated recap with edit capability
		3. Show extracted decisions with confidence badges
		4. Show auto-created tasks with owner/due-date review
		5. One-click publish (creates tasks and archivesmeeting record)
	- Add loading states and error recovery with retry
	- Add "skip recap" fast-path for users who just want task creation
- Acceptance criteria:
	- End-meeting flow completes <1 min from transcript upload to publish
	- All decisions are visible for review before task creation
	- Tasks appear in inbox immediately after publish

#### E3-05 - Decision-to-task conversion instrumentation

- Type: Analytics/Data
- Estimate: `S` (1 day)
- Dependencies: `E3-03`
- Tasks:
	- Define event schema: `meeting_recap_generated`, `decisions_extracted`, `tasks_created_from_decisions`, `decision_confirmed`, `decision_rejected`
	- Compute metric: decision-to-task conversion rate (tasks created / decisions extracted)
	- Add confidence score distribution tracking
	- Add A/B variant tracking if recap model changes
- Acceptance criteria:
	- Conversion rate is queryable per room/week
	- Data supports roi validation (time saved vs manual entry)
	- Event schema is versioned

### Sprint E3 Partial Exit (PA-003)

1. Meeting Copilot is available in production.
2. Recap generation and decision extraction are functional.
3. Decision-to-task conversion is tracked and visible.

## PA-004 Extension (Auto follow-up escalation, E3 scope)

Goal: extend reminder system with escalation logic that promotes critical issues to managers while respecting user preferences.

### Ticket Breakdown

#### E3-06 - Escalation rules and routing

- Type: Backend/Domain logic
- Estimate: `M` (2-3 days)
- Dependencies: `E1-07`, `E1-08`, existing team/role models
- Tasks:
	- Implement escalation rules: task overdue > 3 days AND owner unresponsive > 48h, high-priority blocked > 2 days
	- Add escalation routing: to task owner's manager, then room owner, then ops lead (by role)
	- Each escalation includes context: task details, impediments, history, suggested recovery plan
	- Add escalation audit log with: reason, recipient, timestamp, action taken
- Acceptance criteria:
	- Escalation rules fire only for genuine blockers (zero false positives in test set)
	- Escalation recipient respects user role hierarchy
	- Audit trail is queryable for root-cause analysis

#### E3-07 - Escalation notification and response

- Type: Frontend + Backend/API
- Estimate: `M` (2 days)
- Dependencies: `E3-06`
- Tasks:
	- Add `GET /api/rooms/:id/escalations` endpoint returning user's escalations
	- Create escalation notification component with urgency coloring
	- Implement escalation actions: `acknowledge`, `assign-to-me`, `suggest-plan`, `dismiss-with-reason`
	- Wire dismissals back to escalation rules for tuning
- Acceptance criteria:
	- Escalations appear to manager within 15 min of trigger
	- Manager can resolve escalation with single action
	- Dismiss reason enables rule refinement

### Sprint E3 Partial Exit (PA-004 Extension)

1. Escalation rules prevent critical task stalls.
2. Managers receive actionable escalations.

## PA-006 Delivery Plan (Team Workload Risk Detection, E3 scope)

Goal: provide real-time visibility into team capacity risks (overload, dependency chains, stalled work) enabling proactive interventions.

Backlog links:
- `BL-026` Team Workload Risk Detection

### Scope (Sprint E3, weeks 5-6)

1. Workload risk scoring (overload, blocked-chain, stall detection)
2. Risk dashboard visibility (ops/manager view)
3. Automated risk alerts
4. Risk context and suggested actions

### Ticket Breakdown

#### E3-08 - Workload risk calculation engine

- Type: Backend/Domain logic
- Estimate: `L` (3-4 days)
- Dependencies: task graph and team models
- Tasks:
	- Implement risk scoring:
		1. `overload_score`: open task count vs historical avg + team avg
		2. `blocked_chain_score`: detect dependency cycles and deep chains (>3 hops)
		3. `stall_score`: in-progress tasks without status update > max age (config: 3 days)
	- Compute per-user and per-team scores
	- Run hourly batch job to update all risk scores
	- Cache results with TTL=30min for dashboard queries
- Acceptance criteria:
	- Risk scores are computed within 2s per team member
	- Overload detection matches manual spot-checks 100%
	- Dependency cycle detection is recursion-safe

#### E3-09 - Risk dashboard and alerts

- Type: Frontend + Backend/API
- Estimate: `M` (2-3 days)
- Dependencies: `E3-08`
- Tasks:
	- Create `team_workload_dashboard.dart` (ops/manager only) showing:
		1. Team member cards with risk summary (icon + score + top risk)
		2. Risk breakdown: overload, blocked chains, stalls
		3. Suggested actions: reassign, unblock dependency, escalate
	- Implement alert subscription: `POST /api/rooms/:id/alerts/subscribe` with rules (risk_type, threshold, recipient)
	- Add `GET /api/rooms/:id/team-risks` endpoint returning per-member risk snapshot
	- Support role-based visibility (managers see team, ops sees all)
- Acceptance criteria:
	- Dashboard loads in < 2s
	- Alerts trigger within 5 min of risk threshold breach
	- Suggested actions are contextual and actionable

### Sprint E3 Full Exit Criteria

1. Meeting Copilot is live converting decisions to tasks.
2. Escalation rules protect critical work.
3. Team workload visibility is available to managers.
4. Key metrics (decision-to-task rate, overdue ratio, risk scores) are tracked.

## PA-007 Delivery Plan (Persona dashboards, deferred to Phase 2)

PA-007 (Persona dashboards with employee/manager/ops views) is valuable for Phase 2 adoption and is deferred pending delivery of PA-001 through PA-006.

Expected scope: weeks 7-8 (post-6-week sprint, reactive to demand).

## PA-008 Extended Delivery Plan (ROI instrumentation, continue from E1 baseline)

Goal: extend E1-06 instrumentation baseline with deeper ROI tracking: time saved, productivity metrics by persona, cycle-time trends.

### Scope (Sprint E2-E3 continuous)

1. Extend event taxonomy to cover all PA features
2. KPI dashboard for weekly review
3. ROI modeling and reporting

### Ticket Breakdown

#### E2/E3-00 - Event taxonomy expansion

- Type: Analytics/Data
- Estimate: `M` (2-3 days, continuous)
- Dependencies: all feature implementations
- Tasks:
	- Define new events:
		- Inbox: `inbox_item_converted`, `item_tta` (time-to-action)
		- Decision: `decision_created`, `decision_confirmed`, `decision_task_created`, `decision_to_task_time`
		- Meeting: `recap_generated`, `meeting_duration`, `decision_extraction_confidence`
		- Action: `action_executed`, `action_completed`, `action_output_quality`
		- Escalation: `escalation_triggered`, `escalation_resolved`, `escalation_time_to_resolution`
	- Ensure all events include: userId, roomId, feature, timestamp, requestId
	- Add schema versioning for backward compatibility
- Acceptance criteria:
	- All new events are captured in sandbox
	- Data pipeline correctly aggregates events
	- Event payload schema passes validation

#### E2/E3-10 - KPI dashboard v2 (weekly review)

- Type: Frontend + Backend/Analytics
- Estimate: `L` (3-4 days)
- Dependencies: `E2/E3-00`
- Tasks:
	- Create dashboard showing weekly trends:
		1. DES (daily execution success) with cohort trend
		2. Intake-to-action median time
		3. Decision-to-task conversion rate + confidence
		4. Overdue task ratio and escalation rate
		5. Action usage and satisfaction
		6. Team workload risk distribution
	- Add drill-down capability: click metric to see per-user/room breakdown
	- Export to CSV/PDF for stakeholder reports
- Acceptance criteria:
	- Dashboard queries return < 3s for 12-week historical data
	- All KPIs show week-over-week comparison
	- Export produces formatted document

#### E2/E3-11 - ROI estimation and reporting

- Type: Backend/Analytics
- Estimate: `M` (2-3 days, end of E3)
- Dependencies: `E2/E3-10`
- Tasks:
	- Implement time-saved model: est. time per action type (mark-done: 10s, convert-task: 30s, generate-recap: 15min, etc.)
	- Compute aggregate time saved per user/room/feature
	- Create ROI report template (time saved, adoption, quality proxy, recommendations)
	- Add sensitivity analysis: best-case, expected, conservative scenarios
- Acceptance criteria:
	- ROI model is validated against 5 power users (manual time tracking spot-check)
	- Report is generated automatically on demand
	- Scenarios show clear ROI case within 6 weeks

### Sprint E2/E3 Partial Exit (PA-008 extension)

1. Extended event taxonomy is operational.
2. Weekly KPI dashboard shows all productivity metrics.
3. ROI report template is used in product review.

Sprint 3 exit criteria:
1. Two vertical packs available in production.
2. Citation/timestamp summaries enabled for transcript-backed outputs.
3. Weekly KPI trend includes D7 and useful-answer movement.

## Legacy / Archive Items

Historical items from earlier framing remain relevant only if mapped to a `BL-*` entry above.
If a historical item is not mapped, it is not active this cycle.

## Definition of Done (Per Backlog Item)

Each item is considered done only when all are true:

1. User-facing behavior and acceptance criteria are validated.
2. Relevant automated tests are added/updated.
3. Observability and error handling are in place for the changed flow.
4. Documentation updates are reflected in this file.

## References

- Product specification: `codex.md`
- Architecture context: `docs/architecture.md`
- Staging observability validation checklist: `docs/observability_staging_checklist.md`
- Validation report (2026-04-29): `docs/observability_validation_report_2026-04-29.md`
- Operator playbook: `docs/operator_runtime_playbook.md`
- Feedback KPI baseline (local): `docs/feedback_kpi_baseline_2026-04-29.md`
