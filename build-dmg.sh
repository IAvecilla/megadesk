#!/bin/bash
set -euo pipefail

PROJECT="/Users/saugon/lambda/megadesk-v2/Megadesk.xcodeproj"
DERIVED="/tmp/megadesk-build"
APP_PATH="$DERIVED/Build/Products/Release/Megadesk.app"
DMG_OUT="/Users/saugon/lambda/megadesk-v2/megadesk.dmg"
TMP_DMG="/tmp/megadesk-tmp.dmg"
VOLUME="Megadesk"

echo "→ Building..."
xcodebuild \
  -project "$PROJECT" \
  -scheme Megadesk \
  -configuration Release \
  -derivedDataPath "$DERIVED" \
  clean build \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  | grep -E "^(error:|warning: |BUILD)"

echo "→ Creating DMG..."
rm -f "$TMP_DMG" "$DMG_OUT"
hdiutil create -size 20m -fs HFS+ -volname "$VOLUME" "$TMP_DMG" -quiet

MOUNT=$(hdiutil attach "$TMP_DMG" -readwrite -noverify -noautoopen | grep "Apple_HFS" | awk '{print $NF}')
echo "  Mounted at $MOUNT"

cp -r "$APP_PATH" "$MOUNT/"
ln -s /Applications "$MOUNT/Applications"
sync
sleep 3

osascript <<APPLESCRIPT
tell application "Finder"
  tell disk "$VOLUME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set bounds of container window to {200, 100, 680, 400}
    set viewOptions to the icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 100
    delay 1
    set position of item "Megadesk" of container window to {130, 145}
    set position of item "Applications" of container window to {350, 145}
    update without registering applications
    delay 2
    close
  end tell
end tell
APPLESCRIPT

hdiutil detach "$MOUNT" -force -quiet
hdiutil convert "$TMP_DMG" -format UDZO -imagekey zlib-level=9 -o "$DMG_OUT" -quiet
rm -f "$TMP_DMG"

VERSION=$(defaults read "$APP_PATH/Contents/Info.plist" CFBundleShortVersionString)
SIZE=$(du -sh "$DMG_OUT" | cut -f1)
echo "✓ megadesk.dmg v$VERSION ($SIZE)"
