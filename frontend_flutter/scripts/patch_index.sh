#!/usr/bin/env bash
set -euo pipefail
# Ensure we run from project root (parent of this scripts dir)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
INDEX="$PROJECT_ROOT/build/web/index.html"

if [ ! -f "$INDEX" ]; then
  echo "[patch] $INDEX not found. Did you run: flutter build web --release ?" >&2
  exit 1
fi

# 1) Inject flutter_bootstrap.js before flutter.js (idempotent)
if ! grep -q "flutter_bootstrap.js" "$INDEX"; then
  echo "[patch] injecting flutter_bootstrap.js into index.html"
  perl -0777 -pi -e 's@<!-- This script adds the flutter initialization JS code -->\n  <script src="flutter.js" defer></script>@  <!-- Bootstrap sets window._flutter.buildConfig (required before loader) -->\n  <script src="flutter_bootstrap.js"></script>\n  <!-- This script adds the flutter initialization JS code -->\n  <script src="flutter.js" defer></script>@' "$INDEX"
else
  echo "[patch] flutter_bootstrap.js already present; skipping injection"
fi

# 2) Inline fallback to set window._flutter.buildConfig if not set (idempotent)
if ! grep -q "window._flutter.buildConfig" "$INDEX"; then
  echo "[patch] injecting inline fallback buildConfig into body"
  perl -0777 -pi -e 's@<body>@<body>\n  <!-- Fallback: define minimal buildConfig if bootstrap race occurs -->\n  <script>if(!window._flutter)window._flutter={};if(!window._flutter.buildConfig){window._flutter.buildConfig={entrypointUrl:"main.dart.js"};}</script>@' "$INDEX"
else
  echo "[patch] inline fallback already present; skipping"
fi

echo "[patch] done."