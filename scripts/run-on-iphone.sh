#!/bin/bash
# Build Sage, install it on the iPhone plugged into this Mac, and launch it.
#
#   ./scripts/run-on-iphone.sh
#
# Optional overrides:
#   BUNDLE_ID=com.you.sage TEAM_ID=ABCDE12345 DEVICE=<udid> ./scripts/run-on-iphone.sh
set -euo pipefail
cd "$(dirname "$0")/.."

say()  { printf '\n\033[1;32m▸ %s\033[0m\n' "$*"; }
fail() { printf '\n\033[1;31m✗ %s\033[0m\n' "$*" >&2; exit 1; }

# 1. Xcode ------------------------------------------------------------------
say "Checking Xcode"
xcodebuild -version >/dev/null 2>&1 || fail "Xcode isn't installed or selected. Install it from the App Store, then run:
    sudo xcode-select -s /Applications/Xcode.app"
xcodebuild -version | head -1
if ! xcodebuild -checkFirstLaunchStatus >/dev/null 2>&1; then
  say "Finishing Xcode's first-launch setup (needs your Mac password)"
  sudo xcodebuild -license accept
  sudo xcodebuild -runFirstLaunch
fi
if ! xcodebuild -showsdks 2>/dev/null | grep -q iphoneos; then
  say "Downloading the iOS platform (one time, several GB)"
  xcodebuild -downloadPlatform iOS
fi

# 2. Signing team -------------------------------------------------------------
TEAM_ID="${TEAM_ID:-}"
if [ -z "$TEAM_ID" ]; then
  # Teams for Apple IDs added in Xcode › Settings › Accounts.
  TEAM_ID=$(defaults read com.apple.dt.Xcode IDEProvisioningTeamByIdentifier 2>/dev/null \
    | sed -nE 's/.*teamID = "?([A-Z0-9]{10})"?;.*/\1/p' | head -1 || true)
fi
if [ -z "$TEAM_ID" ]; then
  # Fall back to an existing Apple Development certificate in the keychain.
  TEAM_ID=$(security find-certificate -a -c "Apple Development" -p 2>/dev/null \
    | openssl x509 -noout -subject 2>/dev/null \
    | sed -nE 's/.*OU ?= ?([A-Z0-9]{10}).*/\1/p' | head -1 || true)
fi
if [ -z "$TEAM_ID" ]; then
  open -a Xcode
  fail "No signing team found. In Xcode (just opened): Settings › Accounts › + › Apple ID, sign in, quit Xcode, then run this again."
fi
say "Signing team: $TEAM_ID"

USER_SLUG=$(id -un | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9')
BUNDLE_ID="${BUNDLE_ID:-com.${USER_SLUG:-me}.sage}"
say "Bundle ID: $BUNDLE_ID"

# 3. iPhone -----------------------------------------------------------------
DEVICE="${DEVICE:-}"
if [ -z "$DEVICE" ]; then
  say "Looking for your iPhone (plug it in and unlock it)"
  JSON=$(mktemp)
  xcrun devicectl list devices --json-output "$JSON" >/dev/null 2>&1 || true
  DEVICE=$(/usr/bin/python3 - "$JSON" <<'PY'
import json, sys
try:
    devices = json.load(open(sys.argv[1]))["result"]["devices"]
except Exception:
    devices = []
for d in devices:
    hw = d.get("hardwareProperties", {})
    if hw.get("platform") == "iOS" and hw.get("reality") != "virtual" and hw.get("udid"):
        print(hw["udid"], d.get("deviceProperties", {}).get("name", "iPhone"), sep="\t")
        break
PY
)
  rm -f "$JSON"
  [ -n "$DEVICE" ] || fail "No iPhone found. Plug it in, unlock it, tap Trust, then run this again."
  NAME=$(printf '%s' "$DEVICE" | cut -f2)
  DEVICE=$(printf '%s' "$DEVICE" | cut -f1)
  say "Found $NAME ($DEVICE)"
fi

# 4. Build --------------------------------------------------------------------
say "Building (first build takes a minute or two)"
xcodebuild \
  -project Sage.xcodeproj -scheme Sage -configuration Debug \
  -destination "id=$DEVICE" \
  -derivedDataPath build \
  -allowProvisioningUpdates -allowProvisioningDeviceRegistration \
  DEVELOPMENT_TEAM="$TEAM_ID" PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" CODE_SIGN_STYLE=Automatic \
  -quiet build \
  || fail "Build failed. Copy the error lines above and send them to Claude."

APP=build/Build/Products/Debug-iphoneos/Sage.app
[ -d "$APP" ] || fail "Build finished but $APP is missing."

# 5. Install and launch -------------------------------------------------------
say "Installing on the iPhone"
xcrun devicectl device install app --device "$DEVICE" "$APP" \
  || fail "Install failed. If the iPhone mentions Developer Mode: Settings › Privacy & Security › Developer Mode › On (it restarts), then run this again."

say "Launching"
if ! xcrun devicectl device process launch --device "$DEVICE" "$BUNDLE_ID" >/dev/null 2>&1; then
  printf '\nInstalled, but iOS blocked the first launch. On the iPhone:\n'
  printf '  Settings › General › VPN & Device Management › your Apple ID › Trust\n'
  printf 'then tap the Sage icon (or run this script again).\n'
  exit 0
fi
say "Done — Sage is open on your iPhone."
