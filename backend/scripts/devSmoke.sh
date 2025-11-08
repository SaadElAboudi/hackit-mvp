#!/usr/bin/env bash
set -euo pipefail

PORT="${PORT:-3000}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "[devSmoke] Killing port $PORT if in use..."
lsof -ti:"$PORT" | xargs -r kill -9 || true

echo "[devSmoke] Starting backend on port $PORT..."
npm run dev > /tmp/hackit-backend.log 2>&1 &
APP_PID=$!
echo "[devSmoke] Backend PID: $APP_PID (logs: /tmp/hackit-backend.log)"

# Wait for health to become available (max ~10s)
tries=0
until curl -s "http://localhost:$PORT/health" >/dev/null; do
  tries=$((tries+1))
  if [[ $tries -ge 50 ]]; then
    echo "[devSmoke] Timeout waiting for /health"
    kill $APP_PID || true
    exit 1
  fi
  sleep 0.2
done

echo "[devSmoke] /health:" && curl -s "http://localhost:$PORT/health" | sed -n '1,120p'

echo "[devSmoke] /api/search:" && curl -s -H 'Content-Type: application/json' \
  -d '{"query":"how to clean a fridge"}' \
  "http://localhost:$PORT/api/search" | sed -n '1,200p'

echo "[devSmoke] Stopping backend (PID $APP_PID)..."
kill $APP_PID || true
sleep 0.5
echo "[devSmoke] Done."
