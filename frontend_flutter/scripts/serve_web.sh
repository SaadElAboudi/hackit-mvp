#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
WEB_DIR="$PROJECT_ROOT/build/web"
PORT="${1:-8081}"
HOST="127.0.0.1"

if [ ! -d "$WEB_DIR" ]; then
  echo "[serve] Web build not found. Run: flutter build web --release" >&2
  exit 1
fi

# Free port
if lsof -ti:"$PORT" >/dev/null 2>&1; then
  echo "[serve] freeing port $PORT"
  lsof -ti:"$PORT" | xargs -r kill -9 || true
fi

cd "$WEB_DIR"
echo "[serve] Serving $WEB_DIR at http://$HOST:$PORT"
python3 -m http.server "$PORT" --bind "$HOST"