# Unified Product Backlog (Single Source of Truth)

Last updated: 2026-04-29

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

## Phase Plan (Roadmap)

### Phase A - Stabilization and Operational Sign-off (Now)

Goal: close remaining quality/ops gaps on already shipped capabilities.

1. [~] Flutter widget coverage for artifact review/compare/status and degraded banner
2. [ ] Staging validation for observability dashboards + alert routing
3. [ ] Operator playbook finalization after staging validation

### Phase B - Product Trust and Feedback (Next)

Goal: increase user trust and close the quality loop.

1. [ ] Explicit feedback loop (pertinent/moyen/hors-sujet + reason)
2. [ ] Trust & explainability blocks (why-this-plan, assumptions, limits, confidence)
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

## Prioritized Backlog (Master List)

| ID | Item | Status | Priority | Phase | Impact | Effort | Notes |
|---|---|---|---|---|---|---|---|
| BL-001 | Flutter widget tests for artifact review/compare/status | [~] | P0 | A | High | M | Partially landed; finish coverage gaps |
| BL-002 | Validate observability dashboards and alert routing in staging | [ ] | P0 | A | High | S | Required for Phase 8 operational sign-off |
| BL-003 | Update operator runtime playbook | [ ] | P0 | A | High | S | Depends on BL-002 |
| BL-004 | Artifact review UX polish | [ ] | P1 | A | Medium | M | Reduce friction in compare/review flows |
| BL-005 | Explicit feedback loop on AI relevance | [ ] | P0 | B | High | M | Top product-value lever |
| BL-006 | Trust & explainability sections in outputs | [ ] | P0 | B | High | M | Essential for team adoption |
| BL-007 | Product KPI instrumentation dashboard | [ ] | P1 | B | High | M | Enables KPI-driven prioritization |
| BL-008 | Execution export (Notion/Trello/Asana/CSV) | [ ] | P0 | C | High | M/L | Turns insight into action |
| BL-009 | Output modes (one-pager vs checklist) | [ ] | P1 | C | Medium | M | Persona-fit packaging |
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
