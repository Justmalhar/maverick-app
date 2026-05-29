#!/usr/bin/env bash
# Archive, export, and upload MaverickRemote to TestFlight.
#
# Requires:
#   ~/.appstoreconnect/private_keys/AuthKey_5R5X237JY7.p8
#   ASC_ISSUER_ID env var  (or pass as first argument)
#
# Usage:
#   ASC_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx ./scripts/testflight.sh
#   ./scripts/testflight.sh xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED_DATA="$REPO_ROOT/build/DerivedData"
DIST="$REPO_ROOT/dist"
TEAM_ID="R6G234T379"
KEY_ID="5R5X237JY7"
KEY_PATH="$HOME/.appstoreconnect/private_keys/AuthKey_${KEY_ID}.p8"
ARCHIVE_PATH="$DIST/MaverickRemote.xcarchive"
EXPORT_PATH="$DIST/MaverickRemote-AppStore"

# ── Resolve Issuer ID ─────────────────────────────────────────────────────────
ISSUER_ID="${1:-${ASC_ISSUER_ID:-}}"
if [ -z "$ISSUER_ID" ]; then
  echo "Error: Issuer ID required." >&2
  echo "  Pass it as an argument or set ASC_ISSUER_ID env var." >&2
  echo "  Find it at: App Store Connect → Users and Access → Integrations → Team Keys" >&2
  exit 1
fi

# ── Guards ────────────────────────────────────────────────────────────────────
if ! command -v xcodegen &>/dev/null; then
  echo "xcodegen not found. Install with: brew install xcodegen" >&2; exit 1
fi
if [ ! -f "$KEY_PATH" ]; then
  echo "API key not found at $KEY_PATH" >&2; exit 1
fi

cd "$REPO_ROOT"
mkdir -p "$DIST"

# ── Regenerate xcodeproj ──────────────────────────────────────────────────────
echo "→ Regenerating Xcode project…"
xcodegen generate --quiet

# ── Archive ───────────────────────────────────────────────────────────────────
echo ""
echo "══ Archiving MaverickRemote ══"
rm -rf "$ARCHIVE_PATH"
xcodebuild archive \
  -scheme MaverickRemote \
  -configuration Release \
  -destination "generic/platform=iOS" \
  -derivedDataPath "$DERIVED_DATA" \
  -archivePath "$ARCHIVE_PATH" \
  -allowProvisioningUpdates \
  CODE_SIGN_STYLE=Automatic \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  2>&1 | grep -E "ARCHIVE (SUCCEED|FAIL)|error:" || true

if [ ! -d "$ARCHIVE_PATH" ]; then
  echo "Archive failed — run without grep filter to see full output." >&2; exit 1
fi
echo "✓  Archive: $ARCHIVE_PATH"

# ── Export IPA ────────────────────────────────────────────────────────────────
echo ""
echo "══ Exporting IPA (App Store) ══"
rm -rf "$EXPORT_PATH"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportOptionsPlist "$REPO_ROOT/scripts/ExportOptions-AppStore.plist" \
  -exportPath "$EXPORT_PATH" \
  -allowProvisioningUpdates \
  2>&1 | grep -E "EXPORT (SUCCEED|FAIL)|error:" || true

IPA_PATH=$(find "$EXPORT_PATH" -name "*.ipa" | head -1)
if [ -z "$IPA_PATH" ]; then
  echo "Export failed — IPA not found in $EXPORT_PATH." >&2; exit 1
fi
echo "✓  IPA: $IPA_PATH"

# ── Upload to TestFlight ──────────────────────────────────────────────────────
echo ""
echo "══ Uploading to App Store Connect / TestFlight ══"
xcrun altool --upload-app \
  --type ios \
  --file "$IPA_PATH" \
  --apiKey "$KEY_ID" \
  --apiIssuer "$ISSUER_ID" \
  --verbose 2>&1 | grep -E "No errors|error:|Upload|Success|CID" || true

echo ""
echo "┌────────────────────────────────────────────────────────────┐"
echo "│  Upload complete.                                          │"
echo "│  Check TestFlight in App Store Connect — build appears     │"
echo "│  under 'iOS Builds' within ~10 minutes after processing.  │"
echo "└────────────────────────────────────────────────────────────┘"
