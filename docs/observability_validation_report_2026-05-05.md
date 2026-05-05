# Observability Validation Report (2026-05-05)

Scope: BL-002 (staging observability validation)
Runbook source: `docs/observability_staging_checklist.md`
Executed by: observabilityAudit.js
Execution time: 2026-05-05T08:05:51.470Z

## Environment

- Target URL: http://127.0.0.1:3000
- RUN_ROOM_SMOKE: false
- ROOM_SMOKE_N: 12
- ROOM_SMOKE_TIMEOUT_MS: 15000

## Evidence Summary

### Step 1 - Baseline health endpoints

Result: BLOCKED

Observed payload summary:

```json
{
  "health": {
    "status": 0,
    "error": "fetch failed"
  },
  "integrations": {
    "status": 0,
    "error": "fetch failed"
  },
  "observability": {
    "status": 0,
    "error": "fetch failed",
    "hasSnapshot": false,
    "alerts": null,
    "endpointKeys": []
  }
}
```

### Step 2 - Room smoke on target environment

Result: SKIPPED

- Skipped because `RUN_ROOM_SMOKE=false`.

### Step 3 - Alert code wiring

Result: PARTIAL PASS

- Expected codes: slo_latency_breach, room_message_5xx_spike, gemini_timeout_spike, youtube_error_spike, ws_fanout_failures, persistent_alerts
- Codes currently active: (none active)
- Full code-path validation still requires induced staging traffic/fault scenarios.

## Go / No-Go

- BL-002 status: IN PROGRESS
- Decision: NO-GO until smoke pass and critical signals are validated in staging.

## Required Follow-ups

1. Complete checklist Steps 4-6 manually in staging (banner, telemetry, request correlation).
2. Attach dashboard screenshots/links and approver name.
3. Re-run this script after any observability-related deploy to keep evidence fresh.

