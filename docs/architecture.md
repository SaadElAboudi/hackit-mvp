# Architecture Hackit MVP

```
Flutter Web (GitHub Pages)
         │
         │  HTTP REST + SSE
         ▼
Node.js Backend (Render)
         │
   ┌─────┴─────────────┬──────────────────┐
   ▼                   ▼                  ▼
Gemini API         YouTube API       MongoDB Atlas
(AI provider)     (video search)    (rooms, messages)
         │
         │  WebSocket /ws/rooms/:roomId
         │
         ▼
Flutter Web (Salons — realtime team chat)
```

## Components

### Frontend — Flutter Web
- **2 tabs**: Recherche (AI search) and Salons (realtime team rooms)
- Deployed to GitHub Pages via CI on every push to `main`
- Anonymous identity: `u_<ts>_<salt6>` generated once, stored in SharedPreferences
- No login required

### Backend — Node.js 20 ESM
- Express API deployed on Render (free tier)
- Gemini 2.0 Flash- Gemini 2.0 Flash- Gemini 2.0 Flash- Gemini 2.0 Flash- Gemini 2.0 Flash- Gemini 2.0 Flash- er + heuristic fallback when Gemini is degraded or rate-limited
- YouTube Data API v3 for video search (with `yt-search` fallback)
- WebSocket per room for Salons realtime (`threadRooms.js`)

### Database — MongoDB Atlas
- `rooms` — room metadata (name, directive, pinned document)
- `roommessages` — message history per room
- `users` — anonymous user records

### Shared
- `shared/types/` — TypeScript type definitions used by backend
- `shared/config/` — shared configuration constants
