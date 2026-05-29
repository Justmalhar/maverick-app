#!/usr/bin/env bash
# Package MaverickAgent (.app for macOS) and MaverickRemote (.app for iOS Simulator).
#
# Outputs:
#   dist/MaverickAgent.app          — drag-to-Applications macOS daemon
#   dist/MaverickAgent.zip          — zipped copy for easy sharing
#   dist/MaverickRemote-Simulator/  — iOS .app folder, install with `xcrun simctl install`
#
# For a real-device IPA, run with:  ./package.sh --device
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED_DATA="$REPO_ROOT/build/DerivedData"
DIST="$REPO_ROOT/dist"
DEVICE_BUILD=0
TEAM_ID="R6G234T379"

for arg in "$@"; do
  [[ "$arg" == "--device" ]] && DEVICE_BUILD=1
done

cd "$REPO_ROOT"

# ── Guards ────────────────────────────────────────────────────────────────────
if ! command -v xcodegen &>/dev/null; then
  echo "xcodegen not found. Install with: brew install xcodegen" >&2; exit 1
fi

# ── Regenerate xcodeproj ──────────────────────────────────────────────────────
echo "→ Regenerating Xcode project…"
xcodegen generate --quiet

mkdir -p "$DIST"

# ────────────────────────────────────────────────────────────────────────────
# 1. MaverickAgent  (macOS, Apple Development signed)
# ────────────────────────────────────────────────────────────────────────────
echo ""
echo "══ Building MaverickAgent (macOS Release) ══"
xcodebuild \
  -scheme MaverickAgent \
  -configuration Release \
  -derivedDataPath "$DERIVED_DATA" \
  -allowProvisioningUpdates \
  CODE_SIGN_STYLE=Automatic \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  build 2>&1 | grep -E "BUILD (SUCCEED|FAIL)|error:" || true

AGENT_BUILD="$DERIVED_DATA/Build/Products/Release/MaverickAgent.app"
if [ ! -d "$AGENT_BUILD" ]; then
  echo "MaverickAgent build product not found at $AGENT_BUILD" >&2; exit 1
fi

# Copy .app into dist/
rm -rf "$DIST/MaverickAgent.app"
cp -R "$AGENT_BUILD" "$DIST/MaverickAgent.app"
echo "✓  dist/MaverickAgent.app"

# Zip for sharing
(cd "$DIST" && zip -qr MaverickAgent.zip MaverickAgent.app)
echo "✓  dist/MaverickAgent.zip"

# ────────────────────────────────────────────────────────────────────────────
# 2. MaverickRemote  (iOS Simulator)
# ────────────────────────────────────────────────────────────────────────────
# Pick the first available iPhone 16 Pro simulator (or fall back to any iPhone)
SIM_ID=$(xcrun simctl list devices available -j \
  | python3 -c "
import sys, json
d = json.load(sys.stdin)['devices']
for runtime, devs in d.items():
  if 'iOS' not in runtime: continue
  for dev in devs:
    if 'iPhone 16 Pro' in dev['name'] and dev['isAvailable']:
      print(dev['udid']); exit()
# fallback: any iPhone
for runtime, devs in d.items():
  if 'iOS' not in runtime: continue
  for dev in devs:
    if 'iPhone' in dev['name'] and dev['isAvailable']:
      print(dev['udid']); exit()
")

if [ -z "$SIM_ID" ]; then
  echo "No available iPhone simulator found." >&2; exit 1
fi
SIM_NAME=$(xcrun simctl list devices available | grep "$SIM_ID" | sed 's/ ([A-Z0-9-]*).*//' | xargs)
echo ""
echo "══ Building MaverickRemote (iOS Simulator — $SIM_NAME) ══"

xcodebuild \
  -scheme MaverickRemote \
  -configuration Release \
  -destination "platform=iOS Simulator,id=$SIM_ID" \
  -derivedDataPath "$DERIVED_DATA" \
  -allowProvisioningUpdates \
  CODE_SIGN_STYLE=Automatic \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  build 2>&1 | grep -E "BUILD (SUCCEED|FAIL)|error:" || true

SIM_APP=$(find "$DERIVED_DATA/Build/Products/Release-iphonesimulator" \
  -maxdepth 1 -name "MaverickRemote.app" 2>/dev/null | head -1)

if [ ! -d "$SIM_APP" ]; then
  echo "MaverickRemote simulator build not found." >&2; exit 1
fi

REMOTE_DEST="$DIST/MaverickRemote-Simulator"
rm -rf "$REMOTE_DEST"
cp -R "$SIM_APP" "$REMOTE_DEST"
echo "✓  dist/MaverickRemote-Simulator  (install: xcrun simctl install booted \"$REMOTE_DEST\")"

# ────────────────────────────────────────────────────────────────────────────
# 3. (Optional) MaverickRemote IPA for real device
# ────────────────────────────────────────────────────────────────────────────
if [ "$DEVICE_BUILD" -eq 1 ]; then
  echo ""
  echo "══ Building MaverickRemote (iOS Device — Apple Development) ══"
  xcodebuild \
    -scheme MaverickRemote \
    -configuration Release \
    -destination "generic/platform=iOS" \
    -derivedDataPath "$DERIVED_DATA" \
    -archivePath "$DIST/MaverickRemote.xcarchive" \
    -allowProvisioningUpdates \
    CODE_SIGN_STYLE=Automatic \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    archive 2>&1 | grep -E "ARCHIVE (SUCCEED|FAIL)|error:" || true

  xcodebuild -exportArchive \
    -archivePath "$DIST/MaverickRemote.xcarchive" \
    -exportOptionsPlist "$REPO_ROOT/scripts/ExportOptions.plist" \
    -exportPath "$DIST/MaverickRemote-IPA" \
    -allowProvisioningUpdates \
    2>&1 | grep -E "EXPORT (SUCCEED|FAIL)|error:" || true

  echo "✓  dist/MaverickRemote-IPA/MaverickRemote.ipa"
fi

# ────────────────────────────────────────────────────────────────────────────
echo ""
echo "┌─────────────────────────────────────────────────────────┐"
echo "│  Package complete  →  dist/                             │"
echo "│                                                         │"
echo "│  MaverickAgent.app    drag to /Applications, then open  │"
echo "│  MaverickAgent.zip    share / distribute                │"
echo "│  MaverickRemote-Simulator/  install into simulator:     │"
echo "│    xcrun simctl install booted dist/MaverickRemote-Sim  │"
echo "└─────────────────────────────────────────────────────────┘"
