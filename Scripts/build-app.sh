#!/bin/bash
#
# Assembles Islet.app from the SwiftPM build and signs it.
#
# A bundle is not cosmetic: notifications (UNUserNotificationCenter) and the
# login item (SMAppService) both require a bundle identifier and are inert
# without one.
#
#   ./Scripts/build-app.sh            # release build
#   CONFIG=debug ./Scripts/build-app.sh
#
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${CONFIG:-release}"
APP="build/Islet.app"

echo "==> building ($CONFIG)"
swift build -c "$CONFIG"
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

echo "==> assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Islet" "$APP/Contents/MacOS/Islet"
cp Resources/Info.plist "$APP/Contents/Info.plist"
if [ -f Resources/Islet.icns ]; then
	cp Resources/Islet.icns "$APP/Contents/Resources/Islet.icns"
else
	echo "    (no icon — run ./Scripts/make-icon.sh)"
fi

# Optional custom chimes. Without them Islet uses system sounds, so their
# absence is a fallback, never a failure. Audio only — the notes in that folder
# have no business inside the bundle.
SOUNDS=$(find Resources/Sounds -maxdepth 1 -type f \
	\( -iname '*.wav' -o -iname '*.aiff' -o -iname '*.aif' \
	-o -iname '*.caf' -o -iname '*.m4a' -o -iname '*.mp3' \) 2>/dev/null || true)
if [ -n "$SOUNDS" ]; then
	mkdir -p "$APP/Contents/Resources/Sounds"
	echo "$SOUNDS" | while read -r file; do
		cp "$file" "$APP/Contents/Resources/Sounds/"
	done
	echo "    bundled sounds: $(echo "$SOUNDS" | xargs -n1 basename | tr '\n' ' ')"
else
	echo "    no custom sounds — falling back to system chimes"
fi

echo "==> signing"
IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
	| awk '/Apple Development/ { print $2; exit }')"
if [ -n "${IDENTITY:-}" ]; then
	echo "    identity $IDENTITY"
	codesign --force --options runtime --sign "$IDENTITY" "$APP"
else
	echo "    no Developer ID found — signing ad-hoc (fine for local use)"
	codesign --force --sign - "$APP"
fi
codesign --verify --verbose=1 "$APP"

echo
echo "built $(pwd)/$APP"
echo "  run     open $APP"
echo "  install cp -R $APP /Applications/"
