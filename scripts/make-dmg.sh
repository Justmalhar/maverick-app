#!/usr/bin/env bash
# Build MaverickAgent (macOS), Developer-ID sign + notarize, and package a
# drag-to-Applications DMG that opens cleanly on anyone else's Mac.
#
# Output:
#   dist/MaverickAgent.dmg   — share freely; no Gatekeeper warning once notarized
#
# Distribution-ready requires two one-time setup steps (see scripts/README.md):
#   1. A "Developer ID Application" certificate in your login keychain.
#   2. A stored notarytool credential profile (default name: maverick-notary).
# If either is missing the script still produces a DMG, but signed only with
# your Apple Development cert (works locally, warns on other Macs).
#
# Usage:
#   ./scripts/make-dmg.sh                 # build, sign, notarize, staple, package
#   ./scripts/make-dmg.sh --no-build      # reuse existing dist/MaverickAgent.app
#   ./scripts/make-dmg.sh --no-notarize   # Developer-ID sign but skip notarization
#
# Override defaults via env:
#   DEV_ID_IDENTITY="Developer ID Application: Name (TEAMID)"
#   NOTARY_PROFILE="maverick-notary"
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED_DATA="$REPO_ROOT/build/DerivedData"
DIST="$REPO_ROOT/dist"
TEAM_ID="R6G234T379"
APP_NAME="MaverickAgent"
VOL_NAME="Maverick Agent"
DMG_PATH="$DIST/${APP_NAME}.dmg"
ENTITLEMENTS="$REPO_ROOT/server/MaverickAgent.entitlements"
NOTARY_PROFILE="${NOTARY_PROFILE:-maverick-notary}"
DO_BUILD=1
DO_NOTARIZE=1

for arg in "$@"; do
  case "$arg" in
    --no-build)    DO_BUILD=0 ;;
    --no-notarize) DO_NOTARIZE=0 ;;
  esac
done

cd "$REPO_ROOT"
mkdir -p "$DIST"

# ── Guards ────────────────────────────────────────────────────────────────────
command -v create-dmg &>/dev/null || { echo "create-dmg not found. Install: brew install create-dmg" >&2; exit 1; }

# ── Resolve Developer ID signing identity (auto-detect if not given) ──────────
DEV_ID_IDENTITY="${DEV_ID_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null \
  | awk -F\" '/Developer ID Application/{print $2; exit}')}"

SIGN_DEV_ID=0
if [ -n "$DEV_ID_IDENTITY" ]; then
  SIGN_DEV_ID=1
  echo "→ Developer ID identity: $DEV_ID_IDENTITY"
else
  echo "⚠  No 'Developer ID Application' certificate found — DMG will be Apple-Development signed only."
  echo "   It runs locally but other Macs will show a Gatekeeper warning. See scripts/README.md."
  DO_NOTARIZE=0
fi

# ── Build MaverickAgent (macOS Release) ───────────────────────────────────────
if [ "$DO_BUILD" -eq 1 ]; then
  command -v xcodegen &>/dev/null || { echo "xcodegen not found. Install: brew install xcodegen" >&2; exit 1; }

  echo "→ Regenerating Xcode project…"
  xcodegen generate --quiet

  AGENT_BUILD="$DERIVED_DATA/Build/Products/Release/${APP_NAME}.app"
  # Remove any prior product so a failed build can never ship a stale app.
  rm -rf "$AGENT_BUILD"

  echo "══ Building ${APP_NAME} (macOS Release) ══"
  set +e
  xcodebuild \
    -scheme "$APP_NAME" \
    -configuration Release \
    -derivedDataPath "$DERIVED_DATA" \
    -allowProvisioningUpdates \
    CODE_SIGN_STYLE=Automatic \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    CODE_SIGN_ALLOW_ENTITLEMENTS_MODIFICATION=YES \
    build 2>&1 | tee "$DERIVED_DATA/build.log" | grep -E "BUILD (SUCCEEDED|FAILED)|error:"
  BUILD_RC=${PIPESTATUS[0]}
  set -e
  if [ "$BUILD_RC" -ne 0 ]; then
    echo "✗  Build failed (rc=$BUILD_RC). Last errors:" >&2
    grep -E "error:|FAILED" "$DERIVED_DATA/build.log" | tail -20 >&2
    exit 1
  fi
  [ -d "$AGENT_BUILD" ] || { echo "${APP_NAME} build product not found at $AGENT_BUILD" >&2; exit 1; }

  rm -rf "$DIST/${APP_NAME}.app"
  cp -R "$AGENT_BUILD" "$DIST/${APP_NAME}.app"
  echo "✓  dist/${APP_NAME}.app"
fi

APP_PATH="$DIST/${APP_NAME}.app"
[ -d "$APP_PATH" ] || { echo "No ${APP_NAME}.app in dist/. Run without --no-build first." >&2; exit 1; }

# ── Re-sign with Developer ID + hardened runtime (required for notarization) ──
if [ "$SIGN_DEV_ID" -eq 1 ]; then
  echo ""
  echo "══ Signing ${APP_NAME}.app with Developer ID (hardened runtime) ══"
  # Sign nested code inside-out first, then the app bundle.
  while IFS= read -r -d '' nested; do
    codesign --force --timestamp --options runtime \
      --sign "$DEV_ID_IDENTITY" "$nested"
  done < <(find "$APP_PATH/Contents" \( -name "*.dylib" -o -name "*.framework" \) -print0 2>/dev/null)

  ENT_ARG=()
  [ -f "$ENTITLEMENTS" ] && ENT_ARG=(--entitlements "$ENTITLEMENTS")
  codesign --force --timestamp --options runtime "${ENT_ARG[@]}" \
    --sign "$DEV_ID_IDENTITY" "$APP_PATH"

  codesign --verify --strict --verbose=2 "$APP_PATH" 2>&1 | tail -2
  echo "✓  signed"
fi

# ── Confirm notary credentials before any (slow) notarization work ────────────
if [ "$DO_NOTARIZE" -eq 1 ]; then
  if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" &>/dev/null; then
    echo ""
    echo "⚠  Notary profile '$NOTARY_PROFILE' not found — skipping notarization."
    echo "   Set it up once with:"
    echo "     xcrun notarytool store-credentials \"$NOTARY_PROFILE\" \\"
    echo "       --apple-id <your-apple-id> --team-id $TEAM_ID --password <app-specific-password>"
    DO_NOTARIZE=0
  fi
fi

# ── Notarize + staple the APP itself, so it is self-contained ─────────────────
# Stapling the app (not just the DMG) means a recipient who drags it to
# /Applications gets a notarized app that verifies even on first launch offline.
if [ "$DO_NOTARIZE" -eq 1 ]; then
  echo ""
  echo "══ Notarizing ${APP_NAME}.app (this can take a few minutes) ══"
  APP_ZIP="$DIST/${APP_NAME}-notarize.zip"
  /usr/bin/ditto -c -k --keepParent "$APP_PATH" "$APP_ZIP"
  xcrun notarytool submit "$APP_ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
  rm -f "$APP_ZIP"

  echo "→ Stapling ticket to the app…"
  xcrun stapler staple "$APP_PATH"
  xcrun stapler validate "$APP_PATH"
  echo "✓  app notarized + stapled"
fi

# ── Stage the app so the DMG only contains the app + Applications link ────────
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
  || true   # create-dmg exits non-zero when it skips its own signing; verify below

[ -f "$DMG_PATH" ] || { echo "DMG was not created at $DMG_PATH" >&2; exit 1; }

# Sign the DMG itself so the container carries a valid signature too.
if [ "$SIGN_DEV_ID" -eq 1 ]; then
  codesign --force --timestamp --sign "$DEV_ID_IDENTITY" "$DMG_PATH"
fi

# ── Notarize + staple the DMG, so the container opens cleanly offline too ─────
if [ "$DO_NOTARIZE" -eq 1 ]; then
  echo ""
  echo "══ Notarizing ${APP_NAME}.dmg (this can take a few minutes) ══"
  xcrun notarytool submit "$DMG_PATH" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait

  echo "→ Stapling ticket to the DMG…"
  xcrun stapler staple "$DMG_PATH"
  xcrun stapler validate "$DMG_PATH"
  echo "✓  DMG notarized + stapled"
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
if [ "$DO_NOTARIZE" -eq 1 ]; then
  STATUS="signed + notarized + stapled — opens cleanly on any Mac"
elif [ "$SIGN_DEV_ID" -eq 1 ]; then
  STATUS="Developer-ID signed, NOT notarized — Gatekeeper may still warn"
else
  STATUS="Apple-Development signed only — for local use"
fi
echo "┌─────────────────────────────────────────────────────────┐"
echo "│  DMG ready  →  dist/${APP_NAME}.dmg"
echo "│  $STATUS"
echo "│  Open it, drag the app onto Applications, then share it.  │"
echo "└─────────────────────────────────────────────────────────┘"
