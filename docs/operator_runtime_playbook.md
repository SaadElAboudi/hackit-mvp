# Operator Runtime Playbook

Last updated: 2026-05-05
Backlog links: BL-003, S1-02

## Purpose

Provide first-response guidance for observability alerts in less than 10 minutes.

## Scope

- Backend health and observability endpoints
- Room messaging SLOs
- External provider reliability (Gemini, YouTube)
- WebSocket fanout reliability

## First 10 Minutes Checklist

1. Confirm service reachability:
   - `GET /health`
   - `GET /health/integrations`
   - `GET /health/observability`
2. Capture current alert list and severities.
3. Check whether any `critical` alert is active.
4. Determine blast radius:
   - Room messaging impacted?
   - Search impacted?
   - External provider only?
5. Apply mitigation from the matrix below.
6. Post incident update in ops channel with request IDs and current status.

## Alert Matrix

| Alert code | Severity | Trigger condition | Immediate action | Escalation |
|---|---|---|---|---|
| `slo_latency_breach` | medium | p95 exceeds route SLO budget | Check p95 route in `/health/observability`; reduce load and inspect recent deployments | Escalate to backend engineer if >15 min |
| `room_message_5xx_spike` | high | Room message 5xx rate exceeds 2% | Validate DB connectivity, inspect room route logs, temporarily reduce command-heavy usage if needed | Escalate immediately to backend on-call |
| `gemini_timeout_spike` | high | Gemini timeout rate >10% | Verify Gemini key/quota, timeout settings, and breaker state; rely on fallback behavior | Escalate to AI integration owner |
| `youtube_error_spike` | medium | YouTube error rate >15% | Check YT API key quota and upstream errors; switch to fallback source where possible | Escalate if >30 min |
| `ws_fanout_failures` | high | WS fanout failure rate >5% (>=30 attempts) | Check WS server health, connection churn, and hub-specific failures | Escalate to realtime owner |
| `persistent_alerts` | critical | Alerts active for 3 consecutive windows | Declare incident, assign incident commander, start rollback/degraded decision tree | Page engineering lead immediately |

## Severity Response Targets

- medium: acknowledge within 15 min, mitigate within 60 min
- high: acknowledge within 10 min, mitigate within 30 min
- critical: acknowledge within 5 min, incident bridge immediately

## Escalation Path and Owner Matrix

| Area | Primary owner | Secondary owner | Escalate when |
|---|---|---|---|
| Backend API and DB | Backend on-call | Engineering lead | Any high/critical backend alert |
| AI providers (Gemini) | AI integration owner | Backend on-call | Timeout/error spikes persist >15 min |
| YouTube provider | Search owner | Backend on-call | Error spike persists >30 min |
| WebSocket/realtime | Realtime owner | Backend on-call | Fanout failures sustained >10 min |
| Product comms | Product lead | Engineering lead | User-visible degradation >30 min |

Note: replace owner roles with named people in your internal ops roster.

## Rollback / Degraded-Mode Decision Tree

1. Is `critical` active (`persistent_alerts`)?
   - Yes: freeze non-essential deploys, start rollback assessment immediately.
2. Is failure isolated to one provider (Gemini/YouTube)?
   - Yes: continue in degraded mode with fallback path and monitor user impact.
3. Is room messaging failing (`room_message_5xx_spike` or DB unavailable)?
   - Yes: prioritize DB/connectivity recovery first; this is core workflow impact.
4. After mitigation, verify:
   - Alert clears from `/health/observability`
   - Core user flows pass smoke checks

## Quick Commands

Health snapshot:

```bash
curl -sS "$TARGET_URL/health"
curl -sS "$TARGET_URL/health/integrations"
curl -sS "$TARGET_URL/health/observability"
```

Automated observability audit report:

```bash
cd backend
TARGET_URL=https://<staging-url> \
SMOKE_API_HOST=<internal-http-host> \
SMOKE_API_PORT=<internal-http-port> \
npm run ops:observability-audit
```

Expected outcome:
- command exits `0`
- report generated in `docs/observability_validation_report_<YYYY-MM-DD>.md`
- include report link in incident/release notes

Room smoke check:

```bash
cd backend
API_HOST=<host-without-protocol> API_PORT=<port> N=12 SMOKE_TIMEOUT_MS=15000 node scripts/roomSmoke.js
```

Feedback KPI baseline:

```bash
cd backend
API_BASE=$TARGET_URL ROOM_ID=<roomId> X_USER_ID=<memberUserId> DAYS=7 npm run kpi:feedback
```

Decision Pack KPI baseline:

```bash
cd backend
API_BASE=$TARGET_URL ROOM_ID=<roomId> X_USER_ID=<memberUserId> DAYS=14 node scripts/decisionPackKpiBaseline.js
```

## Dashboard Links

- Observability overview: `<add-dashboard-link>`
- Alerts view filtered by code: `<add-alerts-link>`
- Logs explorer with requestId search: `<add-logs-link>`

## Incident Log Template

- Time detected:
- Alert code(s):
- Severity:
- Impact summary:
- Request IDs sampled:
- Mitigation applied:
- Escalated to:
- Recovery confirmed at:
- Follow-up actions:

## Exit Criteria for Incident Closure

1. No `critical` alerts active.
2. Alerting condition remains stable for at least 2 windows.
3. Smoke checks pass for impacted flow.
4. Incident summary posted with root cause and follow-ups.

## Decision Pack KPI Review (weekly)

Review this KPI set weekly in product + ops sync:

- `viewed` (adoption volume)
- `shared` (execution handoff volume)
- `share_failed` (integration reliability)
- `conversion%` = `shared / viewed`

Suggested guardrails:

- conversion `< 20%` => review pack quality and call-to-action UX
- share_failed `> 0` for 2 consecutive weeks => connector reliability hardening ticket
