#!/bin/bash
# Builds Rin for distribution: Developer ID signature, notarized and stapled app, and a signed,
# notarized DMG in build/release/.
#
#   scripts/release.sh
#
# Needs the "Developer ID Application" certificate in the keychain and notary credentials saved
# with `xcrun notarytool store-credentials rin-notary --apple-id … --team-id …`. Both can be
# overridden: RIN_SIGN_IDENTITY, RIN_TEAM_ID, RIN_NOTARY_PROFILE.
set -euo pipefail

cd "$(dirname "$0")/.."

TEAM_ID="${RIN_TEAM_ID:-46CXX35BTH}"
IDENTITY="${RIN_SIGN_IDENTITY:-Developer ID Application: Junchen Zhao ($TEAM_ID)}"
PROFILE="${RIN_NOTARY_PROFILE:-rin-notary}"

OUT=build/release
DERIVED="$OUT/DerivedData"
APP="$DERIVED/Build/Products/Release/Rin.app"

step() { printf '\n==> %s\n' "$1"; }

step "Checking the signing identity"
security find-identity -v -p codesigning | grep -F "\"$IDENTITY\"" >/dev/null || {
    echo "No \"$IDENTITY\" in the keychain." >&2
    exit 1
}

step "Building Release"
rm -rf "$OUT"
mkdir -p "$OUT"
xcodegen generate --quiet
# Ad-hoc local builds get the debugger entitlement (get-task-allow); notarization rejects it.
xcodebuild -project Rin.xcodeproj -scheme Rin -configuration Release -derivedDataPath "$DERIVED" \
    CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$IDENTITY" DEVELOPMENT_TEAM="$TEAM_ID" \
    CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO OTHER_CODE_SIGN_FLAGS="--timestamp" \
    build -quiet

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$APP/Contents/Info.plist")
DMG="$OUT/Rin-$VERSION.dmg"

step "Verifying the app's signature"
codesign --verify --deep --strict --verbose=2 "$APP"
if codesign -d --entitlements - --xml "$APP" 2>/dev/null | grep -q "get-task-allow"; then
    echo "The app still carries get-task-allow." >&2
    exit 1
fi

step "Notarizing the app"
ditto -c -k --keepParent "$APP" "$OUT/Rin.zip"
xcrun notarytool submit "$OUT/Rin.zip" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$APP"
rm "$OUT/Rin.zip"

step "Making the DMG"
STAGE="$OUT/dmg"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/Rin.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Rin" -srcfolder "$STAGE" -ov -format UDZO "$DMG" -quiet
rm -rf "$STAGE"
codesign --sign "$IDENTITY" --timestamp "$DMG"

step "Notarizing the DMG"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$DMG"

step "Checking with Gatekeeper"
spctl --assess --type execute --verbose=2 "$APP"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"

step "Done"
echo "Rin $VERSION ($BUILD)"
echo "$DMG"
shasum -a 256 "$DMG"
