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

1. [ ] My Day cockpit (Top 3 priorities, blockers, due today)
2. [ ] Unified Work Inbox (channels/events to actionable queue)
3. [ ] Meeting Copilot (recap -> decisions -> tasks)
4. [ ] Auto follow-up engine (nudges, overdue recovery, escalation)
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
| BL-021 | My Day cockpit (daily execution center) | [ ] | P0 | E | High | M | Primary KPI: DES, D7 retention |
| BL-022 | Unified Work Inbox | [ ] | P0 | E | High | M/L | Primary KPI: intake-to-action time |
| BL-023 | Meeting Copilot (decisions to tasks) | [ ] | P0 | E | High | M/L | Primary KPI: decision-to-task conversion |
| BL-024 | Auto follow-up engine (nudges + escalation) | [ ] | P0 | E | High | M | Primary KPI: overdue ratio |
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
