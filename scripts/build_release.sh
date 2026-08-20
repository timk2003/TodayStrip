#!/bin/zsh
#
# Builds a signed, notarized TodayStrip.dmg ready for a GitHub release.
#
# Authenticate once and the script picks the profile up:
#   xcrun notarytool store-credentials todaystrip-notary \
#     --key AuthKey_XXXX.p8 --key-id <KEY_ID> --issuer <ISSUER_ID>
#
# Or pass NOTARY_KEY_PATH / NOTARY_KEY_ID / NOTARY_ISSUER instead.
#
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

SCHEME="TodayStrip"
CONFIGURATION="Release"
TEAM_ID="${DEVELOPMENT_TEAM:-WZ5SB4MMHN}"
NOTARY_PROFILE="${NOTARY_PROFILE:-todaystrip-notary}"
IDENTITY="Developer ID Application"

BUILD_DIR="$PROJECT_DIR/build"
ARCHIVE="$BUILD_DIR/TodayStrip.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
STAGING="$BUILD_DIR/dmg"

VERSION="$(xcodebuild -project TodayStrip.xcodeproj -scheme "$SCHEME" -configuration "$CONFIGURATION" -showBuildSettings 2>/dev/null \
  | awk -F' = ' '/ MARKETING_VERSION / { print $2; exit }')"
: "${VERSION:?could not read MARKETING_VERSION}"
DMG="$BUILD_DIR/TodayStrip-$VERSION.dmg"

if [ -n "${NOTARY_KEY_PATH:-}" ]; then
  notary_args=(--key "$NOTARY_KEY_PATH" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER")
else
  notary_args=(--keychain-profile "$NOTARY_PROFILE")
fi

# Checked before anything is built. Notarisation is the last step of a five-minute pipeline, and
# discovering there that the credentials are missing means doing all of it again.
echo "==> Checking notary credentials"
if ! xcrun notarytool history "${notary_args[@]}" >/dev/null 2>&1; then
  cat <<EOF >&2
No usable notary credentials for profile "$NOTARY_PROFILE".

Create one:
  xcrun notarytool store-credentials $NOTARY_PROFILE \\
    --key AuthKey_XXXX.p8 --key-id <KEY_ID> --issuer <ISSUER_ID>

Or point at an existing profile:
  NOTARY_PROFILE=<name> $0
EOF
  exit 1
fi

# The tests are the gate. Shipping is the one moment where "I'll check it later" is expensive,
# so a red suite stops the release before anything gets signed.
if [ "${SKIP_TESTS:-0}" != "1" ]; then
  echo "==> Running tests"
  xcodebuild test \
    -project TodayStrip.xcodeproj \
    -scheme "$SCHEME" \
    -destination 'platform=macOS' \
    -quiet
fi

echo "==> Building TodayStrip $VERSION"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# No sandbox and no entitlements beyond the hardened runtime, so Developer ID signing works
# without a provisioning profile.
xcodebuild archive \
  -project TodayStrip.xcodeproj \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -archivePath "$ARCHIVE" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$IDENTITY" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  OTHER_CODE_SIGN_FLAGS="--timestamp"

echo "==> Exporting"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportOptionsPlist scripts/ExportOptions.plist \
  -exportPath "$EXPORT_DIR"

APP="$EXPORT_DIR/TodayStrip.app"
[ -d "$APP" ] || { echo "export produced no TodayStrip.app"; exit 1; }

echo "==> Verifying signature"
codesign --verify --deep --strict --verbose=2 "$APP"

# The app is notarized and stapled first, so that a copy dragged out of the disk image carries
# its own ticket and validates without a network round trip.
echo "==> Notarizing the app"
ditto -c -k --keepParent "$APP" "$BUILD_DIR/TodayStrip.zip"
xcrun notarytool submit "$BUILD_DIR/TodayStrip.zip" "${notary_args[@]}" --wait
xcrun stapler staple "$APP"
rm "$BUILD_DIR/TodayStrip.zip"

echo "==> Building disk image"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "TodayStrip" -srcfolder "$STAGING" -ov -format UDZO "$DMG"
codesign --sign "$IDENTITY" --timestamp "$DMG"

echo "==> Notarizing the disk image"
xcrun notarytool submit "$DMG" "${notary_args[@]}" --wait
xcrun stapler staple "$DMG"

echo "==> Verifying Gatekeeper acceptance"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
spctl --assess --type execute --verbose=2 "$APP"
xcrun stapler validate "$APP"
xcrun stapler validate "$DMG"

echo
echo "Ready: $DMG"
