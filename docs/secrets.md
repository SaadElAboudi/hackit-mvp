## Secrets & Environment Configuration

This document explains which secrets / environment variables you may set, where to store them, and what each does.

### Storage Locations

| Context | Where to put it | Visibility | Notes |
|---------|-----------------|------------|-------|
| Local backend dev | `backend/.env` | Only you (gitignored) | Create from `backend/.env.example` |
| GitHub Actions (monorepo + real smoke) | Repo Settings → Secrets and variables → Actions | Encrypted | Use repository **Secrets** (not variables) for API keys |
| CI-only non‑sensitive toggles | Workflow `env:` / normal vars | Public | Avoid putting secrets there |

### Core Variables

| Name | Required? | Purpose | Typical Values |
|------|-----------|---------|----------------|
| `PORT` | No | Backend listen port | `3000` |
| `MOCK_MODE` | No | Force mock search / summaries (no external calls) | `true` / `false` |
| `ALLOW_FALLBACK` | No | Permit fallback to mock results if primary fails | `true` |
| `YT_API_KEY` | For real YouTube path | Official YouTube Data API v3 key | (your key) |
| `USE_GEMINI` | Optional | Enable Gemini for summaries | `true` / `false` |
| `USE_GEMINI_REFORMULATION` | Optional | Secondary reformulation pass | `false` (default) |
| `GEMINI_API_KEY` | If `USE_GEMINI=true` | Gemini API key | (your key) |
| `GEMINI_MODEL` | Optional | Model used for generation | `models/gemini-2.0-flash-lite-001` |
| `GEMINI_TIMEOUT_MS` | Optional | Timeout for Gemini calls | `3500` |
| `PROJECT_ID` | Optional | Internal / analytics reference | (string) |

### GitHub Actions Secrets

Add these under: Repository → Settings → Secrets and variables → Actions → New repository secret

| Secret | Used By | Why |
|--------|---------|-----|
| `YT_API_KEY` | `backend-real-ci.yml` | Enables scheduled real YouTube smoke test |
| `GEMINI_API_KEY` | (future real summaries) | Needed when enabling real Gemini summarization in CI |
| `CODECOV_TOKEN` | Coverage aggregation job (private repos) | Only required if repo is private or uploads fail without it |

### Rotating Exposed Keys

If an API key is accidentally committed:
1. Revoke / rotate it in the provider console (YouTube, Gemini, etc.).
2. Remove it from git history (e.g., `git filter-repo` or BFG) if necessary.
3. Force-push only if you truly need to purge history (coordinate with collaborators).
4. Commit updated `.env.example` (without secrets) & ensure `.gitignore` covers real files.

### Local Development Scenarios

| Scenario | Minimal Vars |
|----------|--------------|
| Pure mock dev | `MOCK_MODE=true` |
| Real YouTube only | `MOCK_MODE=false`, `YT_API_KEY=<key>` |
| Gemini summaries (no YouTube key) | `MOCK_MODE=false`, `USE_GEMINI=true`, `GEMINI_API_KEY=<key>` |
| Full real path | `MOCK_MODE=false`, `YT_API_KEY=<key>`, `USE_GEMINI=true`, `GEMINI_API_KEY=<key>` |

### Troubleshooting

| Symptom | Likely Cause | Fix |
|---------|--------------|-----|
| CI real smoke job only shows notice | Missing `YT_API_KEY` secret | Add secret & re-run workflow |
| Gemini calls timing out | Too low timeout | Increase `GEMINI_TIMEOUT_MS` (e.g. 6000) |
| Fallback always triggered | `MOCK_MODE=true` or primary provider failing | Set `MOCK_MODE=false`; inspect logs |
| Coverage job has only backend data | Frontend / Flutter tests weren’t triggered | Confirm changed paths or force run via workflow_dispatch |

### Security Reminders
Never commit real API keys. `.env`, `*.env`, and `backend/.env` are already ignored. Use secrets for CI.

---
Last updated: $(date -u +'%Y-%m-%d')