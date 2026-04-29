# Observability Validation Report (2026-04-29)

Scope: BL-002 (staging observability validation)
Runbook source: `docs/observability_staging_checklist.md`
Executed by: Copilot (automation run)
Execution time: 2026-04-29

## Environment

- Target requested: staging
- Environment validated in this run: local backend (`http://localhost:3000`)
- Reason: staging URL/access credentials were not available in the current workspace context.

## Evidence Summary

### Step 1 - Baseline health endpoints

Result: PARTIAL PASS (local)

Observed payload summary:

```json
{
  "health": {
    "ok": true,
    "mode": "REAL",
    "mock": false,
    "version": "1.0.0"
  },
  "integrations": {
    "ok": true,
    "status": "degraded",
    "dbConnected": false
  },
  "observability": {
    "ok": true,
    "alerts": [],
    "endpointKeys": [
      "GET /health",
      "GET /health/integrations",
      "GET /health/observability",
      "POST /"
    ]
  }
}
```

Assessment:
- `/health`: pass
- `/health/integrations`: degraded because `dbConnected=false`
- `/health/observability`: pass (response shape present)

### Step 2 - Room smoke on target environment

Result: FAIL (blocked by DB)

Command:

```bash
cd backend
API_HOST=localhost API_PORT=3000 N=12 SMOKE_TIMEOUT_MS=15000 node scripts/roomSmoke.js
```

Failure evidence:

- `POST /api/rooms` returned `503`
- Error message: `Database not available. Set MONGODB_URI on the server.`

Impact:
- Could not validate room creation/message loop on this environment.
- Could not validate p95 message SLO for `POST /api/rooms/:id/messages`.

### Step 3 - Alert code wiring

Result: NOT EXECUTED (depends on Step 2 traffic and staging dashboard routing)

Codes to validate in staging:
- `slo_latency_breach`
- `room_message_5xx_spike`
- `gemini_timeout_spike`
- `youtube_error_spike`
- `ws_fanout_failures`
- `persistent_alerts`

### Step 4 - Frontend degraded banner

Result: PARTIAL PASS (prior widget tests exist, staging manual check pending)

Current known coverage:
- Widget test for degraded banner exists in `frontend_flutter/test/screens/salon_chat_screen_degraded_banner_test.dart`

Pending staging checks:
- Manual visual verification against live degraded backend state.

### Step 5 - Telemetry opt-in validation

Result: PARTIAL PASS (implementation present, staging event verification pending)

Current implementation status:
- Feature telemetry event `feature_used`
- Feedback v1 telemetry event `feedback_signal` with outcomes `submitted|failed|retried`

Pending staging checks:
- Verify event emission behavior with `ANALYTICS_OPT_IN=false` and `ANALYTICS_OPT_IN=true`.

### Step 6 - Request correlation sanity

Result: NOT EXECUTED (requires successful/failed room actions on DB-connected env)

## Go / No-Go

- BL-002 status: IN PROGRESS
- Decision: NO-GO for staging sign-off until DB-connected staging validation is completed.

## Required Follow-ups

1. Provide staging URL and access credentials (API + dashboard).
2. Ensure staging backend has valid `MONGODB_URI` and `dbConnected=true`.
3. Re-run checklist Steps 1-7 against staging target.
4. Attach screenshots/log links and approver name.

## Release Notes Snippet (draft)

- Date: 2026-04-29
- Validation target: local pre-staging
- Health endpoints: reachable
- Blocking issue: DB unavailable for room smoke (`503` on room creation)
- Next action: rerun full staging validation after DB fix and access provisioning
