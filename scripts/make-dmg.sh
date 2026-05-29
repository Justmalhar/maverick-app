#!/usr/bin/env bash
# Build MaverickAgent (macOS) and package it into a drag-to-Applications DMG.
#
# Output:
#   dist/MaverickAgent.dmg   — open, drag the app onto the Applications alias, share freely
#
# Usage:
#   ./scripts/make-dmg.sh            # build Release, then make the DMG
#   ./scripts/make-dmg.sh --no-build # reuse an existing dist/MaverickAgent.app
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED_DATA="$REPO_ROOT/build/DerivedData"
DIST="$REPO_ROOT/dist"
TEAM_ID="R6G234T379"
APP_NAME="MaverickAgent"
VOL_NAME="Maverick Agent"
DMG_PATH="$DIST/${APP_NAME}.dmg"
DO_BUILD=1

for arg in "$@"; do
  [[ "$arg" == "--no-build" ]] && DO_BUILD=0
done

cd "$REPO_ROOT"
mkdir -p "$DIST"

# ── Guards ────────────────────────────────────────────────────────────────────
command -v create-dmg &>/dev/null || { echo "create-dmg not found. Install: brew install create-dmg" >&2; exit 1; }

# ── Build MaverickAgent (macOS Release) ───────────────────────────────────────
if [ "$DO_BUILD" -eq 1 ]; then
  command -v xcodegen &>/dev/null || { echo "xcodegen not found. Install: brew install xcodegen" >&2; exit 1; }

  echo "→ Regenerating Xcode project…"
  xcodegen generate --quiet

  echo "══ Building ${APP_NAME} (macOS Release) ══"
  xcodebuild \
    -scheme "$APP_NAME" \
    -configuration Release \
    -derivedDataPath "$DERIVED_DATA" \
    -allowProvisioningUpdates \
    CODE_SIGN_STYLE=Automatic \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    build 2>&1 | grep -E "BUILD (SUCCEEDED|FAILED)|error:" || true

  AGENT_BUILD="$DERIVED_DATA/Build/Products/Release/${APP_NAME}.app"
  [ -d "$AGENT_BUILD" ] || { echo "${APP_NAME} build product not found at $AGENT_BUILD" >&2; exit 1; }

  rm -rf "$DIST/${APP_NAME}.app"
  cp -R "$AGENT_BUILD" "$DIST/${APP_NAME}.app"
  echo "✓  dist/${APP_NAME}.app"
fi

APP_PATH="$DIST/${APP_NAME}.app"
[ -d "$APP_PATH" ] || { echo "No ${APP_NAME}.app in dist/. Run without --no-build first." >&2; exit 1; }

# ── Stage the app in a clean folder so the DMG only contains the app ──────────
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP_PATH" "$STAGE/${APP_NAME}.app"

# ── Build the DMG ─────────────────────────────────────────────────────────────
echo ""
echo "══ Creating ${APP_NAME}.dmg ══"
rm -f "$DMG_PATH"

create-dmg \
  --volname "$VOL_NAME" \
  --window-pos 200 120 \
  --window-size 600 380 \
  --icon-size 110 \
  --icon "${APP_NAME}.app" 150 180 \
  --app-drop-link 450 180 \
  --no-internet-enable \
  "$DMG_PATH" \
  "$STAGE" \
  || true   # create-dmg returns non-zero if codesign-of-dmg is skipped; verify below

[ -f "$DMG_PATH" ] || { echo "DMG was not created at $DMG_PATH" >&2; exit 1; }

echo ""
echo "┌─────────────────────────────────────────────────────────┐"
echo "│  DMG ready  →  dist/${APP_NAME}.dmg"
echo "│  Open it, drag the app onto Applications, then share it.  │"
echo "└─────────────────────────────────────────────────────────┘"
