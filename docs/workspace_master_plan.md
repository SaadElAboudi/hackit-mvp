# Workspace Master Plan (Notion-Grade + AI Ops)

Last updated: 2026-04-27
Owner: Product + Engineering
Status: Ready for implementation

## 1) Product Objective

Build the next-generation Hackit workspace where teams can:
- collaborate in real time,
- transform discussion into decisions/tasks/deliverables,
- run specialized AI workflows with quality controls,
- and sync outcomes to external tools.

North Star:
- Weekly Actionable Outputs (WAO)

Definition of Actionable Output:
- a decision, task, deliverable, or mission result that is assigned and trackable.

## 2) Scope and Principles

Principles:
- Action over chat: every important exchange can become execution.
- Reliability first: graceful fallback, typed errors, requestId traceability.
- Human-in-the-loop: review/approval workflow for high-impact outputs.
- Incremental shipping: 2-week phases, measurable outcomes each phase.

Non-goals (phase 1-3):
- Building a full generic docs editor competitor.
- Multi-tenant enterprise SSO and compliance certifications.

## 3) Target Architecture (High-level)

Core domains:
- Workspace/Room Collaboration
- Documents (Pages/Blocks)
- Decisions and Tasks
- Missions and AI Workflows
- Integrations and Sync
- Observability and Operations

Primary runtime components:
- Node backend (existing) as orchestration/control plane.
- Flutter frontend (existing) as collaborative workspace client.
- MongoDB as source of truth.
- WebSocket for collaboration and live status.

## 4) Delivery Phases (24 weeks)

## Phase 0 (Weeks 1-2): Foundations and Contracts

### Features
- Product contract baseline
- API and data contract baseline
- Delivery governance baseline

### Backend Deliverables
- Define and document canonical error envelope for all new routes:
  - `ok`, `code`, `message`, `details`, `requestId`
- Define schema versioning strategy for workspace entities.
- Add feature flags for risky features:
  - `workspace_blocks`, `workspace_tasks`, `workspace_realtime_edit`, `workspace_ai_autoplan`

### Frontend Deliverables
- Add reusable error panel component with retry and requestId rendering.
- Add debug diagnostics section (hidden behind dev mode).

### Verification
- Contract tests for error envelope.
- CI guard: fail if modified route skips validation middleware.

### Exit Criteria
- 100% new routes return standardized envelopes.
- requestId visible in API responses and linked logs.

## Phase 1 (Weeks 3-6): Workspace Docs Core

### Features
- Pages and blocks
- Minimal database table view
- Linkable knowledge graph primitives

### Backend Deliverables
- Models:
  - `WorkspacePage`
  - `WorkspaceBlock`
  - `WorkspaceDatabase`
  - `WorkspaceDatabaseRow`
- API:
  - create/list/get/update/delete page
  - create/update/reorder/delete block
  - create/list rows for table databases
- Versioning:
  - page revision metadata (`author`, `changeSummary`, `createdAt`)

### Frontend Deliverables
- Page view and block renderer:
  - text, heading, checklist, callout, quote
- Create/edit page flow from room context.
- Simple table database view with sortable columns.

### Verification
- Integration tests for CRUD + auth checks.
- Widget tests for page rendering states.

### Exit Criteria
- Team can create and edit pages in workspace.
- Page/block edits persisted and replayable.

## Phase 2 (Weeks 7-10): Realtime Collaboration

### Features
- Live presence, cursors, and comments
- Inline review collaboration

### Backend Deliverables
- WS events:
  - `presence.updated`
  - `page.block.updated`
  - `comment.created`
  - `comment.resolved`
- Add optimistic concurrency token on block updates.
- Recovery strategy for stale clients (lastVersion reconciliation).

### Frontend Deliverables
- Presence indicators on page and room context.
- Inline comments timeline with resolve/reopen.
- Conflict hint UI for stale edit states.

### Verification
- Multi-client WS tests.
- Reconnection/resync regression tests.

### Exit Criteria
- Two or more users collaborate with consistent live state.
- p95 WS propagation under 400ms in staging tests.

## Phase 3 (Weeks 11-14): Decision-to-Task Engine

### Features
- Decision extraction and task conversion
- Execution board views

### Backend Deliverables
- Models:
  - `WorkspaceDecision`
  - `WorkspaceTask`
  - `WorkspaceMilestone`
- APIs:
  - convert decision into task set
  - task lifecycle transitions (`todo`, `in_progress`, `blocked`, `done`)
  - assignment and due date updates
- AI extraction route:
  - robust parser from room discussion/mission outputs

### Frontend Deliverables
- Kanban + list view for tasks.
- "Convert to tasks" action on decision and mission cards.
- Task owner, due date, status controls.

### Verification
- Integration tests for conversion pipeline.
- Widget tests for status transitions and assignment.

### Exit Criteria
- Decisions can be converted to tracked tasks in one action.
- Measured reduction in manual coordination steps.

## Phase 4 (Weeks 15-18): AI Workspace Agents

### Features
- Specialized agents with quality gates
- Review-first mission deliverables

### Backend Deliverables
- Agent orchestration profiles:
  - strategist, researcher, writer, facilitator, analyst
- Mission quality gate:
  - detect generic outputs
  - force repair prompt pass
  - fallback to structured actionable template
- Add mission output scoring metadata:
  - specificity score
  - actionability score
  - confidence signal

### Frontend Deliverables
- Agent launch panel with prompt templates.
- Mission review panel with score + improve actions.
- Approve/reject/publish workflow for mission outputs.

### Verification
- Prompt benchmark suite per profile.
- Regression tests for generic-output suppression.

### Exit Criteria
- Mission outputs pass quality checks by default.
- Generic fallback response rate below 5%.

## Phase 5 (Weeks 19-22): Integrations and Sync

### Features
- Bidirectional sync for core tools
- Operational integration center

### Backend Deliverables
- Connector layer expansion:
  - Slack, Notion, (extensible to Drive/Jira)
- Job queue for export/sync with:
  - retries
  - idempotency keys
  - dead-letter handling
- Sync history model with filters and replay metadata.

### Frontend Deliverables
- Integration health center:
  - last sync
  - failures
  - retry action
- History and audit cards in room/workspace context.

### Verification
- Integration tests for retries/idempotency.
- Failure simulation tests (429/5xx/timeouts).

### Exit Criteria
- Sync success rate above 98% for healthy connectors.
- No duplicate external write on retry scenarios.

## Phase 6 (Weeks 23-24): Industrialization and Ops

### Features
- Admin-grade controls and observability
- Runbooks for reliability

### Backend Deliverables
- Audit log coverage for critical actions.
- Permission hardening and role matrix enforcement.
- Operational runbooks:
  - incident handling
  - rollback
  - backup/restore

### Frontend Deliverables
- Workspace activity log UI.
- Degraded mode banner with non-blocking UX.

### Verification
- Load smoke for room + tasks + mission endpoints.
- Alert rules validated in staging.

### Exit Criteria
- Stable operation with clear on-call visibility.
- Incidents diagnosable via requestId and metrics.

## 5) Feature-by-Feature Backlog (Ordered)

Tier A (build first):
1. Workspace page/block models and APIs
2. Block editor and page renderer
3. Realtime presence and comments
4. Decision-to-task conversion
5. Kanban/list task views

Tier B (scale value):
6. Agent launch panel and profile templates
7. Mission quality scoring and repair pipeline
8. Review/approval flow for AI deliverables

Tier C (scale adoption):
9. Integration center and sync history
10. Audit logs and workspace admin controls

## 6) Team Setup (Best Conditions)

Recommended squad structure:
- 1 Product lead
- 1 Tech lead backend
- 1 Tech lead frontend
- 2 full-stack engineers
- 1 QA engineer
- 1 part-time designer

Cadence:
- Sprint length: 2 weeks
- Weekly product review (KPI + top incidents)
- End-of-sprint demo with acceptance checklist

Definition of Done (for every feature):
- Validation middleware and typed errors
- Tests updated and passing
- Metrics/logging added for new critical flows
- Docs updated in `docs/`
- Feature gated if production risk exists

## 7) KPI Framework

Core KPIs:
- Weekly Actionable Outputs (North Star)
- % decisions converted into tasks
- Mission approval rate without major rewrite
- Time-to-first-deliverable
- Workspace D7 retention

Reliability KPIs:
- `/api/search` and room command p95 latency
- AI fallback rate
- 5xx rate and WS fanout failure rate
- breaker active duration

## 8) Immediate 7-Day Kickoff Plan

Day 1:
- Freeze contracts: page/block/task/decision schemas.
- Create issue templates for each phase.

Day 2:
- Implement `WorkspacePage` + `WorkspaceBlock` models.
- Add CRUD route skeletons with validation.

Day 3:
- Add integration tests for page/block CRUD and permissions.

Day 4:
- Build Flutter page list + page detail renderer MVP.

Day 5:
- Hook WS events for block updates and presence.

Day 6:
- Add observability points and health checks for new routes.

Day 7:
- End-to-end demo in staging and phase-1 go/no-go review.

## 9) Risks and Mitigations

Risk: scope explosion in editor UX.
- Mitigation: strict block subset in phase 1.

Risk: AI quality inconsistency.
- Mitigation: quality gate + repair pass + structured fallback.

Risk: connector instability.
- Mitigation: queue, retries, idempotency, health center visibility.

Risk: team context fragmentation.
- Mitigation: single source docs and strict sprint acceptance criteria.

## 10) Next Document Links

- `docs/implementation_roadmap.md`
- `docs/product_strategy_2026.md`
- `docs/features.md`
- `docs/architecture.md`
