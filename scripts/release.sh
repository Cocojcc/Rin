#!/bin/bash
# Builds Rin for distribution: Developer ID signature, notarized and stapled app, a signed,
# notarized DMG, and the appcast that offers it as an update, all in build/release/.
#
#   scripts/release.sh
#
# Needs the "Developer ID Application" certificate in the keychain, notary credentials saved with
# `xcrun notarytool store-credentials rin-notary --apple-id … --team-id …`, and the private update
# key in the keychain (see CONTRIBUTING.md). The first two can be overridden: RIN_SIGN_IDENTITY,
# RIN_TEAM_ID, RIN_NOTARY_PROFILE.
set -euo pipefail

cd "$(dirname "$0")/.."

TEAM_ID="${RIN_TEAM_ID:-46CXX35BTH}"
IDENTITY="${RIN_SIGN_IDENTITY:-Developer ID Application: Junchen Zhao ($TEAM_ID)}"
PROFILE="${RIN_NOTARY_PROFILE:-rin-notary}"
REPO=https://github.com/Cocojcc/Rin
# Sparkle's account for Rin's private key in the keychain; the public half goes into the app.
KEY_ACCOUNT=com.zoro.rin

OUT=build/release
DERIVED="$OUT/DerivedData"
APP="$DERIVED/Build/Products/Release/Rin.app"
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
SPARKLE_BIN="$DERIVED/SourcePackages/artifacts/sparkle/Sparkle/bin"

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
    CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO OTHER_CODE_SIGN_FLAGS="--timestamp" ENABLE_HARDENED_RUNTIME=YES \
    RIN_UPDATE_FEED="$REPO/releases/latest/download/appcast.xml" \
    build -quiet

step "Checking the update key"
# Before the long wait for notarization: an update signed with any other key would be refused.
if [ "$("$SPARKLE_BIN/generate_keys" --account "$KEY_ACCOUNT" -p)" != "$(/usr/libexec/PlistBuddy -c "Print SUPublicEDKey" "$APP/Contents/Info.plist")" ]; then
    echo "The update key in the keychain doesn't match SUPublicEDKey in Info.plist." >&2
    exit 1
fi

step "Signing Sparkle's helpers"
# A plain build signs the framework but not the helpers inside it. Rin isn't sandboxed, so Sparkle's
# XPC services go unused. The order matters: inside out, and the app last.
rm -rf "$SPARKLE/Versions/B/XPCServices" "$SPARKLE/XPCServices"
for item in "$SPARKLE/Versions/B/Autoupdate" "$SPARKLE/Versions/B/Updater.app" "$SPARKLE"; do
    codesign --force --sign "$IDENTITY" --options runtime --timestamp "$item"
done
codesign --force --sign "$IDENTITY" --options runtime --timestamp --entitlements Rin/Support/Rin.entitlements "$APP"

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

step "Writing the appcast"
# Published as an asset of each release, so the feed and its disk image appear together.
SIGNATURE=$("$SPARKLE_BIN/sign_update" --account "$KEY_ACCOUNT" "$DMG")
cat > "$OUT/appcast.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Rin</title>
    <item>
      <title>Rin $VERSION</title>
      <link>$REPO/releases/tag/v$VERSION</link>
      <sparkle:version>$BUILD</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$(/usr/libexec/PlistBuddy -c "Print LSMinimumSystemVersion" "$APP/Contents/Info.plist")</sparkle:minimumSystemVersion>
      <pubDate>$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")</pubDate>
      <enclosure url="$REPO/releases/download/v$VERSION/Rin-$VERSION.dmg" $SIGNATURE type="application/octet-stream"/>
    </item>
  </channel>
</rss>
EOF
xmllint --noout "$OUT/appcast.xml"

step "Done"
echo "Rin $VERSION ($BUILD)"
echo "$DMG"
shasum -a 256 "$DMG"
