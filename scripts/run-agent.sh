#!/usr/bin/env bash
# Run MaverickAgent — builds if needed, kills any running instance, then launches.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED_DATA="$REPO_ROOT/build/DerivedData"
TEAM_ID="R6G234T379"
APP_PATH="$DERIVED_DATA/Build/Products/Release/MaverickAgent.app"

cd "$REPO_ROOT"

# ── Ensure xcodegen is available ────────────────────────────────────────────
if ! command -v xcodegen &>/dev/null; then
  echo "xcodegen not found. Install with: brew install xcodegen" >&2
  exit 1
fi

# ── Regenerate xcodeproj ─────────────────────────────────────────────────────
echo "→ Regenerating Xcode project…"
xcodegen generate --quiet

# ── Build ─────────────────────────────────────────────────────────────────────
echo "→ Building MaverickAgent (Release)…"
xcodebuild \
  -scheme MaverickAgent \
  -configuration Release \
  -derivedDataPath "$DERIVED_DATA" \
  -allowProvisioningUpdates \
  CODE_SIGN_STYLE=Automatic \
  DEVELOPMENT_TEAM=R6G234T379 \
  build 2>&1 | grep -E "BUILD (SUCCEED|FAIL)|error:" || true

if ! find "$DERIVED_DATA/Build/Products/Release" -maxdepth 1 -name "MaverickAgent.app" | grep -q .; then
  echo "Build failed." >&2
  exit 1
fi

# ── Kill any running instance ────────────────────────────────────────────────
if pgrep -x MaverickAgent &>/dev/null; then
  echo "→ Stopping running MaverickAgent…"
  pkill -x MaverickAgent || true
  sleep 0.5
fi

# ── Launch ────────────────────────────────────────────────────────────────────
echo "→ Launching $APP_PATH"
open "$APP_PATH"
echo "✓ MaverickAgent is running (check the menu bar)."
