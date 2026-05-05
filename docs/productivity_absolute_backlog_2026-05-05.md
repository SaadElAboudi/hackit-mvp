# Productivity Absolute Backlog (Execution-Ready)

Last updated: 2026-05-05
Owner: Product + Engineering
Horizon: 6 weeks

## Objective

Transform Hackit from a collaboration tool into a daily execution system that employees depend on to plan, act, and follow through.

## North Star

Daily Execution Success (DES): number of users who complete at least 3 priority actions/day with tracked outcomes.

## Key Gaps To Close

1. No personal daily cockpit (`My Day`) with prioritized tasks and blockers.
2. No unified intake for work requests across channels/messages/integrations.
3. AI assists analysis but does not execute enough repetitive work actions.
4. Decision and meeting outputs are not consistently converted into follow-up actions.
5. Weak adoption/ROI instrumentation by team and persona.

## Prioritization Model

RICE score = (Reach x Impact x Confidence) / Effort

Scale:
- Reach: users/week impacted
- Impact: 0.25 / 0.5 / 1 / 2 / 3
- Confidence: 50 / 70 / 85 / 100
- Effort: engineering-weeks

## Master Backlog (6-week target)

| ID | Feature | Reach | Impact | Confidence | Effort | RICE | Priority | Primary KPI |
|---|---|---:|---:|---:|---:|---:|---|---|
| PA-001 | My Day cockpit (Top 3 priorities, blockers, due today, follow-ups) | 220 | 3 | 85 | 2.5 | 224 | P0 | DES, D7 retention |
| PA-002 | Unified Work Inbox (Slack/messages/tasks/events -> actionable queue) | 180 | 3 | 80 | 3.0 | 144 | P0 | Intake-to-action time |
| PA-003 | Meeting Copilot (agenda -> notes -> decisions -> tasks auto-create) | 140 | 3 | 80 | 3.0 | 112 | P0 | Decision-to-task conversion |
| PA-004 | Auto follow-up engine (owner nudges, overdue recovery, escalation) | 200 | 2 | 85 | 2.0 | 170 | P0 | Overdue ratio |
| PA-005 | Copilot Actions library (brief, client update, recap, handoff) | 160 | 2 | 80 | 2.0 | 128 | P1 | Time saved/user/day |
| PA-006 | Team Workload Risk Detection (overload, dependency, stall alerts) | 120 | 2 | 70 | 2.5 | 67 | P1 | Blocked task duration |
| PA-007 | Persona dashboards (employee, manager, ops) with action prompts | 100 | 1 | 75 | 2.0 | 38 | P2 | Weekly active channels |
| PA-008 | ROI instrumentation pack (time saved, completion, cycle-time trends) | 220 | 1 | 90 | 1.5 | 132 | P1 | Adoption + ROI proof |

## User Stories And Acceptance Criteria

### PA-001 My Day cockpit

User stories:
1. As an employee, I can open one page to see what to do now, what is blocked, and what is due today.
2. As a manager, I can verify each team member has a clear daily plan.

Acceptance criteria:
1. `My Day` loads in < 2s p50 for users with <= 200 open tasks.
2. Page always shows: Top 3 priorities, blockers, due today, waiting-for list.
3. Each item has one-click actions: mark done, defer, ping owner, open source context.
4. If no priorities exist, user gets guided actions to generate a plan.

### PA-002 Unified Work Inbox

User stories:
1. As an employee, I can triage all incoming work requests in one queue.
2. As an ops lead, I can ensure no request is dropped.

Acceptance criteria:
1. Inbox aggregates at least channels + internal task events in MVP.
2. Each entry supports convert-to-task and assign-owner in <= 2 clicks.
3. SLA label is visible (today, tomorrow, late).
4. Queue supports filters: mine, team, unassigned, overdue.

### PA-003 Meeting Copilot

User stories:
1. As a meeting host, I can generate recap + decisions + actions without manual rewrite.
2. As a participant, I can trust that decisions become tracked tasks.

Acceptance criteria:
1. End-meeting flow generates recap + decisions in <= 15s.
2. User can confirm/edit before publish.
3. Publish creates linked tasks with owner + due date checks.
4. Decision-to-task conversion rate is tracked.

### PA-004 Auto follow-up engine

User stories:
1. As an owner, I receive reminders before and after due date.
2. As a manager, I get escalation only for real risks.

Acceptance criteria:
1. Rules support due-soon, overdue, blocked > X days.
2. Reminder channels support in-app first; external connectors optional in phase 2.
3. Escalation includes context and suggested recovery plan.
4. Users can snooze reminders with reason.

### PA-005 Copilot Actions library

User stories:
1. As an employee, I can run high-value workflows from templates.
2. As an admin, I can standardize best-practice outputs by function.

Acceptance criteria:
1. Minimum 5 actions available in MVP.
2. Output supports one-click insert/share/export.
3. Each action logs usage and completion.
4. Action quality feedback is captured.

## 6-Week Delivery Plan

### Sprint 1 (Weeks 1-2)

Scope:
1. PA-001 foundations (data model + My Day UI skeleton)
2. PA-008 instrumentation baseline
3. PA-004 reminder rules MVP (in-app)

Definition of done:
1. Users can see Top 3 priorities + blockers.
2. Basic reminders trigger on overdue tasks.
3. KPI dashboard shows DES proxy and overdue ratio.

### Sprint 2 (Weeks 3-4)

Scope:
1. PA-002 Unified Work Inbox MVP
2. PA-005 Copilot Actions v1 (3 actions)
3. PA-001 action controls (done/defer/ping)

Definition of done:
1. Intake-to-action in <= 2 clicks for core flows.
2. Copilot actions produce reusable output with tracking.

### Sprint 3 (Weeks 5-6)

Scope:
1. PA-003 Meeting Copilot MVP
2. PA-004 escalation logic
3. PA-006 risk detection (blocked/dependency heuristics)

Definition of done:
1. Meeting recap -> decisions -> tasks flow is live.
2. Escalations are actionable and measurable.

## Technical Dependencies

1. Stable room/task/decision APIs and WS event reliability.
2. Event taxonomy for KPI tracking (`created`, `assigned`, `completed`, `nudged`, `escalated`).
3. Role-based views (`employee`, `manager`, `ops`) from existing room/member model.

## Risks And Mitigations

1. Risk: feature bloat in first sprint.
Mitigation: keep Sprint 1 to My Day + reminders + KPI baseline.
2. Risk: poor recommendation quality harms trust.
Mitigation: keep user override controls and explainability cues.
3. Risk: notification fatigue.
Mitigation: digest/snooze settings and priority thresholds.

## Exit Criteria (Product-Indispensable Check)

1. >= 60% weekly active users open `My Day` at least 3 days/week.
2. >= 40% tasks completed through suggested priorities.
3. >= 25% reduction in overdue tasks within 4 weeks post-launch.
4. Measured median time-saved >= 20 minutes/user/day (self-reported + event proxy).
