#!/bin/bash
# Builds a signed, notarized RED SNAPPER release in dist/: a .zip and a .dmg, both containing
# the notarized app with Apple's ticket stapled to it.
#
#   scripts/release.sh                 test, archive, sign, notarize, package, verify
#   scripts/release.sh --no-notarize   stop after packaging a signed but un-notarized build
#
# Signing and notarization use the Apple Developer account Xcode is signed in to
# (Xcode → Settings → Accounts); no passwords are needed.
# Optional: with a notarytool keychain profile (NOTARY_PROFILE, default RedSnapperNotary)
# the .dmg wrapper is notarized and stapled too.
#
# Notarized builds are also signed for Sparkle (private key in your keychain, account
# "red-snapper") and added to appcast.xml. Publish with:
#   gh release create v<version> dist/RED-SNAPPER-<version>.zip dist/RED-SNAPPER-<version>.dmg
#   git add appcast.xml && git commit -m "Release <version>" && git push
# Push appcast.xml only *after* the release exists, or apps will try to download a missing file.
set -euo pipefail
cd "$(dirname "$0")/.."

PROFILE="${NOTARY_PROFILE:-RedSnapperNotary}"
NOTARIZE=1
[[ "${1:-}" == "--no-notarize" ]] && NOTARIZE=0

ARCHIVE=build/RedSnapper.xcarchive
SIGNED=build/export
NOTARIZED=build/notarized

echo "▸ Generating project"
xcodegen generate --quiet --use-cache   # only rewrites the project when project.yml changed

echo "▸ Running tests"
xcodebuild -project RedSnapper.xcodeproj -scheme "RED SNAPPER" -derivedDataPath build/tests \
  -destination "platform=macOS,arch=arm64" build-for-testing -quiet
# Run the bundle with xctest directly: `xcodebuild test` launched from this script fails to
# load the freshly built bundle ("Failed to create a bundle instance") on macOS 26.
xcrun xctest build/tests/Build/Products/Debug/SnapCoreTests.xctest > build/tests/xctest.log 2>&1 \
  || { cat build/tests/xctest.log; echo "✗ Tests failed"; exit 1; }
tail -1 build/tests/xctest.log

echo "▸ Archiving (Release, universal)"
rm -rf "$ARCHIVE" "$SIGNED" "$NOTARIZED" build/notarize-upload
xcodebuild -project RedSnapper.xcodeproj -scheme "RED SNAPPER" -configuration Release \
  -derivedDataPath build -destination "generic/platform=macOS" -archivePath "$ARCHIVE" archive -quiet

if [[ $NOTARIZE -eq 1 ]]; then
  echo "▸ Submitting to Apple for notarization"
  xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist scripts/ExportOptions-notarize.plist \
    -exportPath build/notarize-upload -allowProvisioningUpdates -quiet

  echo "▸ Waiting for Apple (usually 1–5 minutes)"
  for attempt in $(seq 1 90); do
    if xcodebuild -exportNotarizedApp -archivePath "$ARCHIVE" -exportPath "$NOTARIZED" > build/notarize.log 2>&1; then
      break
    fi
    if grep -qiE "invalid|rejected" build/notarize.log; then
      cat build/notarize.log; echo "✗ Apple rejected the build"; exit 1
    fi
    [[ $attempt -eq 90 ]] && { cat build/notarize.log; echo "✗ Timed out waiting for notarization"; exit 1; }
    sleep 20
  done
  APP="$NOTARIZED/RED SNAPPER.app"
  xcrun stapler validate "$APP" > /dev/null
else
  echo "▸ Exporting with Developer ID (not notarized)"
  xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist scripts/ExportOptions.plist \
    -exportPath "$SIGNED" -allowProvisioningUpdates -quiet
  APP="$SIGNED/RED SNAPPER.app"
fi
codesign --verify --deep --strict "$APP"

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$APP/Contents/Info.plist")
ZIP="dist/RED-SNAPPER-$VERSION.zip"
DMG="dist/RED-SNAPPER-$VERSION.dmg"
mkdir -p dist
rm -f "$ZIP" "$DMG"

echo "▸ Packaging version $VERSION (build $BUILD)"
ditto -c -k --keepParent "$APP" "$ZIP"
STAGING=$(mktemp -d)
trap 'rm -rf "$STAGING"' EXIT
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "RED SNAPPER" -srcfolder "$STAGING" -fs HFS+ -format UDZO -ov "$DMG" -quiet

if [[ $NOTARIZE -eq 1 ]] && xcrun notarytool history --keychain-profile "$PROFILE" > /dev/null 2>&1; then
  echo "▸ Notarizing the .dmg wrapper too (profile $PROFILE)"
  xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
  xcrun stapler staple "$DMG"
fi

if [[ $NOTARIZE -eq 1 ]]; then
  echo "▸ Verifying with Gatekeeper"
  spctl --assess --type execute --verbose "$APP"

  echo "▸ Signing the update and adding it to appcast.xml"
  SPARKLE_BIN=$(find build/SourcePackages/artifacts/sparkle -type d -name bin | head -1)
  SIGNATURE=$("$SPARKLE_BIN/sign_update" --account red-snapper "$ZIP")
  scripts/update_appcast.py "$VERSION" "$BUILD" \
    "https://github.com/cesarroger/red-snapper/releases/download/v$VERSION/$(basename "$ZIP")" "$SIGNATURE"
fi
echo "✓ Release ready: $ZIP and $DMG"
