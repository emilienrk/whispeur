#!/usr/bin/env bash
# Packages the built app into a laid-out DMG: background, icon positions and
# window size, instead of the Finder defaults.
#
# The layout is written by the Finder over AppleScript, so the first run asks
# for permission to control the Finder — grant it or the DMG falls back to an
# unstyled window.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP="build/DerivedData/Build/Products/Release/Whispeur.app"
VOLUME="Whispeur"
OUTPUT="Whispeur.dmg"
STAGING="$(mktemp -d)"
RW_DMG="$(mktemp -u).dmg"

# Must match the geometry baked into scripts/assets/dmg-background.tiff.
WINDOW_WIDTH=600
WINDOW_HEIGHT=400
ICON_Y=170

[ -d "$APP" ] || { echo "❌ App introuvable : $APP — lance 'make build' d'abord."; exit 1; }

cleanup() {
    hdiutil detach "/Volumes/$VOLUME" -quiet -force 2>/dev/null || true
    rm -rf "$STAGING" "$RW_DMG"
}
trap cleanup EXIT

# A stale mount from an interrupted run would steal the volume name.
hdiutil detach "/Volumes/$VOLUME" -quiet -force 2>/dev/null || true

cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
mkdir -p "$STAGING/.background"
cp scripts/assets/dmg-background.tiff "$STAGING/.background/"

# UDRW first: the Finder needs a writable volume to store the layout.
hdiutil create -volname "$VOLUME" -srcfolder "$STAGING" -ov -format UDRW \
    -fs HFS+ "$RW_DMG" >/dev/null
hdiutil attach "$RW_DMG" -readwrite -noverify -noautoopen >/dev/null

# The Finder shows these next to the app when the user has hidden files turned on.
chflags hidden "/Volumes/$VOLUME/.background"

osascript <<APPLESCRIPT
tell application "Finder"
    tell disk "$VOLUME"
        open
        delay 1
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set options to the icon view options of container window
        set arrangement of options to not arranged
        set icon size of options to 128
        set text size of options to 13
        set background picture of options to file ".background:dmg-background.tiff"
        set the bounds of container window to {200, 120, $((200 + WINDOW_WIDTH)), $((120 + WINDOW_HEIGHT))}
        delay 1
        -- Placed last and re-applied after a reopen: setting the icon size
        -- makes the Finder relayout, which drags freshly set positions along.
        set position of item "Whispeur.app" of container window to {150, $ICON_Y}
        set position of item "Applications" of container window to {450, $ICON_Y}
        -- Parked below the window: hidden-file mode still reveals it, so at
        -- least keep it from landing on top of the app icon.
        set position of item ".background" of container window to {150, 800}
        delay 1
        close
        open
        delay 1
        set the bounds of container window to {200, 120, $((200 + WINDOW_WIDTH)), $((120 + WINDOW_HEIGHT))}
        set position of item "Whispeur.app" of container window to {150, $ICON_Y}
        set position of item "Applications" of container window to {450, $ICON_Y}
        -- Parked below the window: hidden-file mode still reveals it, so at
        -- least keep it from landing on top of the app icon.
        set position of item ".background" of container window to {150, 800}
        delay 1
        close
    end tell
end tell
APPLESCRIPT

# Give the Finder a moment to flush .DS_Store before the volume goes away.
sync
sleep 2

# Recreated on every mount of a writable volume — it has no business shipping.
rm -rf "/Volumes/$VOLUME/.fseventsd"

hdiutil detach "/Volumes/$VOLUME" -quiet
rm -f "$OUTPUT"
hdiutil convert "$RW_DMG" -format UDZO -imagekey zlib-level=9 -o "$OUTPUT" >/dev/null

echo "✅ $OUTPUT ($(du -h "$OUTPUT" | cut -f1))"
