# Observability Staging Checklist (Phase 8)

Last updated: 2026-04-29

This checklist validates the Phase 8 rollout in a staging environment.

## Scope

Validate the following shipped capabilities:
- Backend observability endpoints: `/health/observability`, `/health/integrations`
- Alerting signals from `backend/src/utils/observability.js`
- Room load smoke (`backend/scripts/roomSmoke.js`)
- Frontend degraded banner in `salon_chat_screen.dart`
- Opt-in feature telemetry (`ANALYTICS_OPT_IN`, event name `feature_used`)

## Preconditions

1. Staging backend is reachable and has a valid database connection (`MONGODB_URI` set).
2. At least one staging app instance is running with WebSocket enabled.
3. If telemetry validation is required, run a frontend build with `ANALYTICS_OPT_IN=true`.
4. You have credentials for staging log/monitoring dashboards.

## Step 1: Baseline Health Endpoints

Run:

```bash
curl -sS "$STAGING_URL/health" | jq .
curl -sS "$STAGING_URL/health/integrations" | jq .
curl -sS "$STAGING_URL/health/observability" | jq .
```

Pass criteria:
- `/health` returns `ok=true`.
- `/health/integrations` returns `ok=true` and provider readiness payload.
- `/health/observability` returns `ok=true` and includes `snapshot`, `alerts`, `status`.

## Step 2: Run Room Smoke on Staging

Run from `backend/`:

```bash
API_HOST=<staging-host-without-protocol> API_PORT=443 N=12 SMOKE_TIMEOUT_MS=15000 node scripts/roomSmoke.js
```

Notes:
- Use `API_PORT=443` only if staging terminates TLS at 443 and accepts direct host-based requests.
- If staging requires a custom port or proxy path, use the correct host/port pair.

Pass criteria:
- Script exits with code `0`.
- Room creation succeeds.
- Message send loop succeeds.
- `p95` for `POST /api/rooms/:id/messages` is under `2000ms`.
- No `critical` alerts are returned by `/health/observability` during run.

## Step 3: Verify Alert Codes and Threshold Wiring

From `/health/observability`, verify alert codes are correctly surfaced when triggered:
- `slo_latency_breach`
- `room_message_5xx_spike`
- `gemini_timeout_spike`
- `youtube_error_spike`
- `ws_fanout_failures`
- `persistent_alerts`

Pass criteria:
- Alerts in response payload match the expected codes from backend logic.
- Severity values match implementation (`medium`, `high`, `critical` as defined).
- Dashboard queries can filter these alert codes without transformation.

## Step 4: Frontend Degraded Banner Behavior

In Flutter staging app (`salon_chat_screen.dart`):

1. Force a degraded backend state (for example by making one integration not ready).
2. Open a channel screen.
3. Confirm a non-blocking banner appears and does not prevent sending messages.

Pass criteria:
- Banner appears only when backend is degraded.
- Banner message is informative and non-blocking.
- Core room actions still function while banner is shown.

## Step 5: Telemetry Opt-In Validation

Build/run frontend twice:

1. `ANALYTICS_OPT_IN=false` (default)
2. `ANALYTICS_OPT_IN=true`

Trigger these actions in a room:
- AI command in message composer (`@ia`, `/doc`, `/mission`, etc.)
- Mission creation
- Share to integration
- Connect Slack/Notion

Pass criteria:
- With opt-in disabled: no `feature_used` telemetry events emitted.
- With opt-in enabled: `feature_used` events emitted for above actions.
- Event payload includes expected fields (`feature`, optional parameters like provider/command).

## Step 6: Request Correlation Sanity

For one failing and one successful room action:
- Capture `X-Request-Id` in API response.
- Verify same ID appears in error/debug UI surfaces where applicable.
- Verify request ID appears in backend logs for diagnosis.

Pass criteria:
- Request ID is stable and traceable across response + logs.

## Step 7: Sign-off Record

Record in release notes:
- Date/time of validation
- Environment URL/version
- Smoke output summary (passed/failed)
- Any active non-critical alerts
- Dashboard links used
- Approver name

## Known Failure Modes

- `503 Database not available. Set MONGODB_URI on the server.`
  - Cause: backend has no DB connection.
  - Action: fix staging runtime env before re-running smoke.

- Smoke can pass health checks but fail room creation:
  - Cause: health endpoint is up while DB dependency is degraded.
  - Action: rely on full smoke pass for go/no-go, not health-only checks.
