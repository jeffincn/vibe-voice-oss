#!/bin/zsh
# Refresh an already-registered VibeVoice input method in place.
#
# First-time install still needs the .pkg (writes to /Library/Input Methods and
# registers with Text Input Sources). After that, every `zsh scripts/build-app.sh`
# calls this script so a code change reaches the live input method without
# opening Installer again.
#
# The source bundle is already signed by build-app.sh. This script only
# overwrites the installed copy and restarts the process — it does not re-sign
# under sudo, because the admin context cannot see the user's code-signing
# keychain.
set -euo pipefail

ROOT="${0:A:h:h}"
INPUT_METHOD_BUNDLE_NAME="VibeVoiceInputMethod.app"
INSTALLED_IMK="/Library/Input Methods/${INPUT_METHOD_BUNDLE_NAME}"
USER_IMK="${HOME}/Library/Input Methods/${INPUT_METHOD_BUNDLE_NAME}"
VERIFY_DIR=""
PRIVILEGED=""

cleanup() {
    [[ -n "$VERIFY_DIR" ]] && rm -rf "$VERIFY_DIR"
    [[ -n "$PRIVILEGED" ]] && rm -f "$PRIVILEGED"
}
trap cleanup EXIT

SOURCE_IMK="${1:-}"
if [[ -z "$SOURCE_IMK" ]]; then
    # Prefer /Applications: dist/ under Documents can pick up File Provider
    # xattrs that make codesign --verify fail even though the payload is fine.
    for candidate in \
        "/Applications/Vibe Voice OSS.app/Contents/Library/Input Methods/${INPUT_METHOD_BUNDLE_NAME}" \
        "$ROOT/dist/Vibe Voice OSS.app/Contents/Library/Input Methods/${INPUT_METHOD_BUNDLE_NAME}"
    do
        if [[ -d "$candidate" ]]; then
            SOURCE_IMK="$candidate"
            break
        fi
    done
fi

if [[ -z "$SOURCE_IMK" || ! -d "$SOURCE_IMK" ]]; then
    echo "error: no built input-method bundle found; run zsh scripts/build-app.sh first" >&2
    exit 1
fi

# Verify an xattr-free view when File Provider has tagged the on-disk bundle.
if ! /usr/bin/codesign --verify --deep --strict "$SOURCE_IMK" 2>/dev/null; then
    VERIFY_DIR=$(mktemp -d)
    VERIFY_BUNDLE="$VERIFY_DIR/${INPUT_METHOD_BUNDLE_NAME}"
    /usr/bin/ditto --norsrc "$SOURCE_IMK" "$VERIFY_BUNDLE"
    /usr/bin/xattr -cr "$VERIFY_BUNDLE"
    /usr/bin/codesign --verify --deep --strict "$VERIFY_BUNDLE"
    # Use the clean copy as the refresh source so /Library does not inherit
    # Documents-side File Provider metadata.
    SOURCE_IMK="$VERIFY_BUNDLE"
fi

if [[ ! -d "$INSTALLED_IMK" && ! -d "$USER_IMK" ]]; then
    echo "Input method is not installed yet."
    echo "  First-time: open dist/VibeVoiceInputMethod.pkg once."
    echo "  After that: zsh scripts/build-app.sh refreshes it automatically."
    exit 0
fi

if [[ -d "$INSTALLED_IMK" ]]; then
    DESTINATION="$INSTALLED_IMK"
    NEEDS_ROOT=1
else
    DESTINATION="$USER_IMK"
    NEEDS_ROOT=0
fi

# Stop the live server first so ditto is not replacing a mapped executable.
/usr/bin/killall VibeVoiceInputMethod 2>/dev/null || true
sleep 0.2

echo "Refreshing input method → $DESTINATION"

# Privileged work lives in a temp script so paths with spaces (Input Methods,
# Vibe Voice OSS.app) never go through osascript string escaping.
PRIVILEGED=$(mktemp)
{
    echo 'set -euo pipefail'
    echo "SOURCE=$(printf %q "$SOURCE_IMK")"
    echo "DEST=$(printf %q "$DESTINATION")"
    echo 'mkdir -p "$(dirname "$DEST")"'
    echo '/usr/bin/ditto "$SOURCE" "$DEST"'
} > "$PRIVILEGED"
chmod 700 "$PRIVILEGED"

if [[ "$NEEDS_ROOT" == 1 ]]; then
    if /usr/bin/sudo -n true 2>/dev/null; then
        /usr/bin/sudo /bin/zsh "$PRIVILEGED"
    else
        /usr/bin/osascript <<EOF
do shell script "/bin/zsh $(printf %q "$PRIVILEGED")" with administrator privileges
EOF
    fi
else
    /bin/zsh "$PRIVILEGED"
fi

/usr/bin/codesign --verify --deep --strict "$DESTINATION"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$DESTINATION/Contents/Info.plist")
# Menu icon / localized name changes need the menu agents restarted.
/usr/bin/killall TextInputMenuAgent 2>/dev/null || true
/usr/bin/killall TextInputSwitcher 2>/dev/null || true
echo "Input method refreshed (CFBundleVersion $VERSION). Next keystroke relaunches it."
