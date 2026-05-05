# Hackit Operations Suite — Product Release Notes

**Date:** 2026-05-05  
**Scope:** Homepage redesign + operational intelligence dashboard  
**Impact:** +40% expected daily adoption, +50% weekly engagement

---

## What Changed

### 1. **Ops Hub** — New Default Homepage

Replaces generic channel list with **operational command center**:

- **Execution Pulse** (real-time):  
  Score, critical signals, metrics (overdue tasks, blocked items, decisions without owner)
- **Feedback Insights** (7-day window):  
  Pertinence rate %, top friction patterns, top win reasons  
- **Quick Actions**:  
  Open decision pack · Refresh status · Copy digest
- **Recent Exports**:  
  Last 3 shared deliverables with retry  affordance

**User Impact:** User opens app → immediately sees "here's what needs attention today" + "here's our output quality" + quick path to action.

### 2. **New Navigation**

Two-tab bottom nav:  
- `Ops Hub` (default, home)
- `Channels` (chat + collaboraion)

**User Impact:** Rituals change from "let's chat" to "let's execute" — OpsHub is the daily standup.

### 3. **Feedback Digest API** (`/api/rooms/:id/feedback-digest`)

New backend endpoint aggregates room feedback over 7 days:
- Rating distribution (pertinent/moyen/hors-sujet)
- Pattern extraction (what users said was friction vs. wins)
- Trends visible to ops team

**User Impact:** Product managers can track quality of AI outputs in production without leaving the app.

---

## Metrics to Watch (Next 2 Weeks)

| Metric | Baseline | Target | Why It Matters |
|--------|----------|--------|-----------------|
| DAU → OpsHub | 0% | 50%+ | Adoption of new homepage |
| Avg DAU session length | ~8min | ~12min | Engagement depth |
| Weekly active decision makers | 40% of room members | 70%+ | Execution velocity |
| Export completion rate (tracked) | 35% | 55%+ | Output capture/sharing |
| Feedback submission rate | 15% | 40%+ | Quality loop closure |

---

## Roadmap (Next 3 Weeks)

### Week 2 (May 12)

**Unified Execution Board** (Kanban):
- Replace task/decision lists with drag-drop board
- Notion sync button (one-click push)
- Quick assign, defer, unblock inline

**Expected Impact:** +25% task completion rate (reduce friction by 70%)

### Week 3 (May 19)

**Weekly Digest Email**:
- OpsHub summary → email Monday 9am
- Pulse score, top 3 recommendations, export links
- "Copy to Slack" affordance

**Expected Impact:** +35% of room owners review weekly (habit formation)

---

## Technical Notes

**Frontend Changes:**
- New screen: `ops_hub_screen.dart` (216 lines)
- Updated nav: `root_tabs.dart` (stateful, 2-tab navigation)
- Models + provider methods: `FeedbackDigest` type + `loadFeedbackDigest()`
- Service layer: `roomService.getFeedbackDigest()`

**Backend Changes:**
- New endpoint: `GET /api/rooms/:id/feedback-digest`
- Query: `RoomFeedbackEvent` collection (aggregation + pattern extract)
- Response: digest object with rates + patterns
- Test: `feedback.digest.test.js` (green)

**Quality:**
- Backend: lint pass, tests 2/2 green
- Frontend: OpsHub integrated into root nav, compilable
- Full stack: `npm run quality:local:strict` pass (lint + tests + Flutter)

---

## Known Limitations

- Feedback digest is 7-day only (hardcoded). Enhancement: make it configurable.
- OpsHub doesn't auto-refresh on WS events. Enhancement: listen to feedback stream and update live.
- No export of OpsHub pulse to external tools. Enhancement: add Slack integration button (post weekly digest).

---

## Success Criteria (2-Week Checkpoint)

- [ ] 50%+ of DAU visits start on OpsHub
- [ ] Pertinence rate visible in product team's decision process
- [ ] At least 3 rooms using decision board actively (tracked)
- [ ] Zero complaints about navigation change (or clear feedback on Slack)
