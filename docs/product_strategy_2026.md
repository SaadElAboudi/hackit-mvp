# Hackit Product Strategy 2026 (Execution Plan)

## 1) Value Proposition (single sentence)
Hackit helps users get an actionable, trustworthy video-based answer in under 30 seconds, with timestamps, citations, and a clear next step.

## 2) Product Pillars
1. **Speed to first value**: show useful content fast (streaming + fallback transparency).
2. **Trust and clarity**: citations, chapters, “why this result”, safety labels.
3. **Personal progress**: history, favorites, progress tracking, personalized recommendations.
4. **Reliability by design**: measurable SLOs, alerting, graceful degradation.

## 3) North-star and KPI Tree
- **North-star**: Weekly Useful Answers (WUA)
  - A useful answer = user receives answer + clicks a citation OR watches recommended segment OR gives positive feedback.

### KPI Tree
- Acquisition: search starts/day, activation rate (first useful answer in first session).
- Core value: time-to-first-value p50/p95, useful-answer rate, fallback rate, no-result rate.
- Engagement: D1/D7 retention, lessons resumed/session, recommendation CTR.
- Quality: thumbs-up ratio, completion rate, average rating.
- Reliability: API p95 latency, 5xx rate, Gemini timeout rate, YouTube error rate.

## 4) Roadmap by Phase

## Phase A (0–4 weeks): Stabilize and make value visible
- Add reliability badges (`REAL`, `CACHED`, `FALLBACK`) in API and UI.
- Add `requestId` propagation front/back for complete traceability.
- Finalize observability dashboard and alerts (5xx spike, timeout spike, breaker too long).
- Add quick feedback in result view (thumb up/down + “missing info”).
- Add baseline product analytics for funnel (search -> result -> click).

**Exit criteria**
- TTFV p50 < 8s in mock mode and < 15s in real mode.
- 5xx < 1% on `/api/search` over 24h.
- Feedback event coverage > 60% of search results displayed.

## Phase B (4–8 weeks): Differentiate answer quality
- Add multi-depth answer modes (TL;DR / Standard / Deep).
- Add follow-up queries with conversation context.
- Add “why this result” explanation and source trust score.
- Add improved ranking signals (freshness + relevance + diversity).

**Exit criteria**
- Useful-answer rate +20% vs Phase A baseline.
- Retry search rate -20%.

## Phase C (8–12 weeks): Personalization and learning loop
- Personalized recommendations from history/favorites + topic embeddings.
- Learning journey: progress state, reminders, “continue where I left off”.
- Saved playbooks and export/share (markdown/public link).

**Exit criteria**
- Recommendation CTR > 15%.
- D7 retention +15%.

## 5) Functional Additions (Prioritized)

### Must-have now
- Search quality feedback loop.
- TTFV instrumentation endpoint + dashboard.
- Retry with backoff + visible fallback reason.
- Endpoint contract consistency (typed shape for result and errors).

### Should-have next
- Conversation threads and context memory.
- Topic tags and semantic suggestions.
- User controls: language, expertise level, output tone.

### Could-have later
- Collaborative learning lists.
- Playlist ingestion + semantic recall.
- Creator subscriptions and proactive alerts.

## 6) Technical Hardening Plan
- Define SLOs: `/api/search` p95 latency, 5xx budget, provider timeout budget.
- Add structured error taxonomy (`code`, `detail`, `suggestedAction`).
- Add contract tests for all public API routes.
- Add chaos tests for provider outages (Gemini/YouTube).
- Enforce feature flags for risky capabilities (reformulation, personalization, reranker).

## 7) UX Improvements with strong perceived value
- Search templates by intent (learn/repair/compare/explain).
- Step-by-step mode with completion checkbox per step.
- “Jump to exact moment” CTA prominence for each citation.
- Empty states with guided actions (retry, alternative query, ask follow-up).

## 8) Go-to-market packaging
- Positioning: “From question to action in 30 seconds”.
- Showcase metrics in landing page: average TTFV, citation click-through, success rate.
- Vertical launch packs: DIY, study, coding, cooking.

## 9) Delivery cadence and ownership
- Weekly release train: one reliability item + one user-facing value item.
- Product review each Friday with KPI trend + top incidents + top user pain points.
- Monthly roadmap adjustment based on telemetry and qualitative feedback.
