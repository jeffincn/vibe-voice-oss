#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
APP_NAME="${VIBE_VOICE_APP_NAME:-Vibe Voice}"
APP="$ROOT/dist/${APP_NAME}.app"
IDENTITY="${CODESIGN_IDENTITY:-}"
STAGING_DIR=$(mktemp -d)
STAGED_APP="$STAGING_DIR/${APP_NAME}.app"
trap 'rm -rf "$STAGING_DIR"' EXIT

cd "$ROOT"
swift build -c release
swift "$ROOT/scripts/generate-icon.swift" "$ROOT/Resources/VibeVoice.icns"

mkdir -p "$STAGED_APP/Contents/MacOS" "$STAGED_APP/Contents/Resources"
cp "$ROOT/.build/release/VibeVoice" "$STAGED_APP/Contents/MacOS/VibeVoice"
cp "$ROOT/Resources/Info.plist" "$STAGED_APP/Contents/Info.plist"
cp "$ROOT/Resources/VibeVoice.icns" "$STAGED_APP/Contents/Resources/VibeVoice.icns"

xattr -cr "$STAGED_APP"
if [[ -z "$IDENTITY" ]]; then
    IDENTITY=$(security find-identity -v -p codesigning \
        | sed -n 's/.*"\(Apple Development:[^"]*\)".*/\1/p' \
        | head -n 1)
fi

if [[ -n "$IDENTITY" ]]; then
    codesign --force --deep --sign "$IDENTITY" --timestamp=none "$STAGED_APP"
    echo "Signed with: $IDENTITY"
else
    codesign --force --deep --sign - "$STAGED_APP"
    echo "Warning: no Apple Development identity found; accessibility permission may reset after rebuild."
fi
codesign --verify --deep --strict "$STAGED_APP"

rm -rf "$APP"
mkdir -p "${APP:h}"
ditto "$STAGED_APP" "$APP"

# Keep /Applications copy in sync for Launch-at-Login and menu-bar daily use.
APPLICATIONS_APP="/Applications/${APP_NAME}.app"
if [[ -d "$APPLICATIONS_APP" || -L "$APPLICATIONS_APP" ]]; then
    rm -rf "$APPLICATIONS_APP"
fi
ditto "$APP" "$APPLICATIONS_APP"
xattr -cr "$APPLICATIONS_APP"
if [[ -n "$IDENTITY" ]]; then
    codesign --force --deep --sign "$IDENTITY" --timestamp=none "$APPLICATIONS_APP" || true
else
    codesign --force --deep --sign - "$APPLICATIONS_APP" || true
fi

# Documents may be managed by File Provider, which can attach Finder metadata
# immediately after copying. Remove it and verify the sealed bundle before returning.
for attempt in 1 2 3; do
    xattr -cr "$APP"
    if codesign --verify --deep --strict "$APP" 2>/dev/null; then
        break
    fi
    if [[ "$attempt" == 3 ]]; then
        codesign --verify --deep --strict --verbose=2 "$APP"
    fi
    sleep 0.2
done
echo "$APP"
echo "$APPLICATIONS_APP"
