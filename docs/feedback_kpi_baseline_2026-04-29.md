# Feedback KPI Baseline - 2026-04-29

Scope: Sprint 1 / `S1-05` (`BL-005`, `BL-007`)

## Context

A local KPI baseline run was executed to validate the end-to-end feedback KPI extraction flow (`backend/scripts/feedbackKpiBaseline.js`) and verify output format for sprint reporting.

Because current backend startup blocks localhost Mongo URIs by default, local run used explicit opt-in:

- `ALLOW_LOCAL_MONGODB=true`
- `MONGODB_URI=mongodb://127.0.0.1:27017/hackit`
- Backend on `http://localhost:3201`

## Seed Dataset

A deterministic dataset was seeded for one room:

- 3 AI messages
- 3 feedback events
- Ratings split: `pertinent`, `moyen`, `hors_sujet`

Seed identifiers used for KPI run:

- `ROOM_ID=69f25ab364d5609a8a5f775c`
- `X_USER_ID=kpi-u1-1777490611532`
- `DAYS=7`

## Command

```bash
cd backend
API_BASE=http://localhost:3201 \
ROOM_ID=69f25ab364d5609a8a5f775c \
X_USER_ID=kpi-u1-1777490611532 \
DAYS=7 \
node scripts/feedbackKpiBaseline.js
```

## Output Snapshot

- Window: `2026-04-22T19:23:36.963Z` -> `2026-04-29T19:23:36.963Z` (`7d`)
- Total feedback events: `3`
- Average daily volume: `0.43`
- Split:
  - `pertinent=1 (33.3%)`
  - `moyen=1 (33.3%)`
  - `hors_sujet=1 (33.3%)`
- Daily timeline:
  - `2026-04-29: total=3 | pertinent=1, moyen=1, hors_sujet=1`

## Notes

- This is a local validation baseline, not a production KPI snapshot.
- For sprint close, rerun on the target environment and archive the output with release evidence.
