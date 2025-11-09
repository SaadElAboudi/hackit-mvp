## Prioritized Issue Plan (Generated 2025-11-09)

This document converts the feature backlog into a prioritized issue list with suggested milestones. Scoring model: IMPACT (user/business value 1–5) × URGENCY (reduces risk/unblocks others 1–5) ÷ EFFORT (estimated size 1=XS,2=S,3=M,5=L). Higher score ⇒ earlier.

### Scoring Legend
| Effort | Rough estimate | Typical work | Complexity |
|--------|----------------|--------------|------------|
| 1 | < 0.5 day | config / small endpoint | XS |
| 2 | 0.5–1.5 days | single endpoint + tests | S |
| 3 | 2–3 days | multi-flow + UI wiring | M |
| 5 | 4–6+ days | cross-cutting system | L |

### Top Dependencies Map
- Transcripts (T) enable: chapterization, citations, entities, related content.
- Caching layer (C) supports: fallback badges, performance metrics, hybrid search.
- Provider abstraction & failover (P) reduces risk for streaming / reliability features.

### Milestone Overview
| Milestone | Goal | Included High-Score Issues |
|-----------|------|---------------------------|
| 1 (Foundation) | Reliable enriched summaries | Summaries w/ citations, Transcript ingest/cache, Chapterization, Caching + badges, E2E smoke, Error handling hardening |
| 2 (Interaction) | Deep navigation & personalization | Multi-length summaries, Bookmarks/history, Jump-to-moment links, Inline transcript preview, Tone/level settings, Feedback events |
| 3 (Search Intelligence) | Better discovery & ranking | Hybrid embeddings, Entity tags, Related suggestions, Diversity/dedupe, Freshness filters, Rerank relevance/recency |

### Prioritized Issues Table
| ID | Title | Impact | Urgency | Effort | Score | Dependencies | Milestone |
|----|-------|--------|---------|--------|-------|-------------|----------|
| 1 | Summaries with citations & timestamps | 5 | 5 | 2 | 12.5 | T (needs transcript OR minimal heuristics) | 1 |
| 2 | Transcript fetch + caching layer | 5 | 5 | 3 | 8.3 | - | 1 |
| 3 | Automatic chapterization | 4 | 4 | 2 | 8.0 | T | 1 |
| 4 | Caching & fallback badges | 4 | 5 | 2 | 10.0 | C | 1 |
| 5 | E2E smoke test (search→stream→timestamp) | 4 | 4 | 2 | 8.0 | 1,2,3 | 1 |
| 6 | Multi-length summary modes | 4 | 3 | 2 | 6.0 | 1 | 2 |
| 7 | Bookmarks & history | 4 | 3 | 2 | 6.0 | - | 2 |
| 8 | Jump-to-moment deep links | 3 | 4 | 2 | 6.0 | 3 | 2 |
| 9 | Inline transcript preview | 4 | 3 | 3 | 4.0 | 2 | 2 |
| 10 | Tone & expertise settings | 3 | 3 | 2 | 4.5 | 1 | 2 |
| 11 | Feedback & analytics (thumbs + missing prompt) | 3 | 3 | 2 | 4.5 | C | 2 |
| 12 | Hybrid search embeddings | 5 | 2 | 5 | 2.0 | C | 3 |
| 13 | Entity extraction tags | 4 | 2 | 3 | 2.7 | 2 | 3 |
| 14 | Related content suggestions | 4 | 2 | 3 | 2.7 | 2 | 3 |
| 15 | Diversity & deduping | 3 | 3 | 3 | 3.0 | 12 | 3 |
| 16 | Freshness & safe-search filters | 3 | 3 | 2 | 4.5 | - | 3 |
| 17 | Rerank relevance & recency | 4 | 2 | 5 | 1.6 | 12,16 | 3 |

### Detailed Issue Specs

#### 1. Summaries with Citations & Timestamps
Labels: area:backend, area:frontend, type:feature, milestone:1, priority:high
Description: Extend `/api/search` (and stream endpoint) to include `citations[]` each with `{url,startSec,endSec,quote}`. Flutter & RN render citation list; tapping opens deep link at timestamp.
Acceptance Criteria:
1. Response contains `citations` array (≥3 items for sample query).  
2. Timestamp links open YouTube at ±2s of `startSec`.  
3. Streaming path eventually includes citations in final chunk.  
4. Tests: integration verifies schema; frontend snapshot renders list.
Notes: Initial implementation may approximate timestamps by heuristics if transcript not yet available; upgrade when transcript ready.

#### 2. Transcript Fetch + Caching Layer
Labels: area:backend, area:infra, type:feature, milestone:1, priority:high
Description: Endpoint `/api/transcript?videoId=`; attempt caption retrieval then fallback provider (if allowed). Cache transcript (key: videoId) with TTL; add `X-Cache: HIT|MISS` header.
Acceptance Criteria:
1. First request MISS; second HIT within TTL.  
2. Fallback path clearly flagged `source:fallback`.  
3. Error returns structured JSON problem format.  
4. Unit tests: cache service; integration tests: timing difference and header set.

#### 3. Automatic Chapterization
Labels: area:backend, type:feature, milestone:1
Description: Generate chapters from transcript using heuristic+LLM (title + startSec). Store in cache; include in `/api/search` or new `/api/chapters`.
Acceptance Criteria: ≥5 coherent chapters for sample video; startSec ascending; integration test validates ordering.
Dependencies: transcript (Issue 2).

#### 4. Caching & Fallback Badges
Labels: area:backend, area:frontend, type:feature, milestone:1
Description: Expose flags in responses: `mode: REAL|MOCK`, `fallback: true|false`, `cached: true|false`. UI badges appear beside summary.
Acceptance Criteria: All combinations tested; visual badges documented in storybook/golden test (Flutter).

#### 5. E2E Smoke Test Flow
Labels: area:qa, type:test, milestone:1
Description: Playwright (or equivalent) script hits search UI, waits for streaming partials, clicks timestamp link, verifies navigation.
Acceptance Criteria: CI run produces artifact (screenshots) and passes; failure shows network log.

#### 6. Multi-Length Summary Modes
Labels: milestone:2, area:backend, area:frontend
Description: Add query param `summaryLength` (tldr|medium|deep). Backend adjusts prompt constraints (# sentences). UI toggle persists locally.
Acceptance Criteria: Distinct lengths measured by sentence count; tests check length ranges.

#### 7. Bookmarks & History
Labels: milestone:2, area:frontend
Description: Local persistence (IndexedDB / Secure Storage) of saved answers & query history with re-run button.
Acceptance: Bookmark added; appears after app relaunch; re-run triggers same enriched result.

#### 8. Jump-to-Moment Deep Links
Labels: milestone:2, area:frontend
Description: Use chapters/citations to build timestamp deep links; support copy/share.
Acceptance: Link copies properly; mobile opens external app at time.

#### 9. Inline Transcript Preview
Labels: milestone:2, area:frontend
Description: Hover/long-press shows transcript snippet around citation (±5s window).
Acceptance: Preview appears and scroll relation accurate; test uses mock transcript.

#### 10. Tone & Expertise Settings
Labels: milestone:2
Description: Preference store for tone (formal/friendly) and expertise (beginner/expert) affecting prompts.
Acceptance: Changing preference alters lexical complexity (Flesch score difference).

#### 11. Feedback & Analytics
Labels: milestone:2
Description: Up/down vote + missing-pieces prompt; events logged to analytics sink.
Acceptance: Vote persists locally; event appears in telemetry dashboard query.

#### 12. Hybrid Search Embeddings
Labels: milestone:3
Description: Introduce vector store; embed titles/descriptions; combine BM25 + cosine similarity.
Acceptance: Relevance evaluation (small gold set) shows ≥10% improvement in nDCG@5 vs baseline.

#### 13. Entity Extraction Tags
Labels: milestone:3
Description: Extract named entities and keywords; UI tag chips filter.
Acceptance: Entities returned with type; filtering narrows results.

#### 14. Related Content Suggestions
Labels: milestone:3
Description: Recommend diversified related items; incorporate channel diversity.
Acceptance: At least 3 distinct creators; no duplicates; relevance threshold achieved.

#### 15. Diversity & Deduping
Labels: milestone:3
Description: Post-processing to enforce diversity rules and remove near duplicates by URL/videoId & fuzzy title match.
Acceptance: Integration test ensures max one video per channel in top 5 (unless override flag).

#### 16. Freshness & Safe-Search Filters
Labels: milestone:3
Description: Query params dateRange & safeSearch; backend filters & returns counts.
Acceptance: Applying dateRange reduces dataset; safeSearch toggling hides flagged items.

#### 17. Rerank Relevance & Recency
Labels: milestone:3
Description: Secondary scoring (LLM or heuristic) factoring recency, channel trust, and semantic relevance.
Acceptance: Test dataset shows improved precision@3 vs baseline scorer.

### Issue Creation Guidance
For each spec above, create a GitHub Issue with:
1. Title: Use the exact heading.  
2. Labels: `area:*`, `milestone:*`, `priority:*`, `type:*`.  
3. Body: Copy Description + Acceptance Criteria + Dependencies.  
4. Link to related issues when opened (e.g., #2 referenced in #3).  

### Next Steps
Milestone 1 kickoff order:
1. Transcript + caching (#2)  
2. Summaries citations (#1)  
3. Chapterization (#3)  
4. Caching badges (#4)  
5. E2E smoke (#5)  
Parallel: error handling improvements (existing backlog item 9) if bandwidth allows.

Optional automation: Use `gh issue create` CLI in a script iterating over headings; or a short Node script hitting GitHub REST API (requires token `GITHUB_TOKEN`).

---
Generated automatically; adjust scores after validation if estimates shift.