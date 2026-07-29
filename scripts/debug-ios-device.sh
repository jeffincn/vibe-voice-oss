#!/bin/zsh
set -euo pipefail

# Build a Debug bundle and put it on a connected iPhone.
#
# scripts/test-ios-device.sh is an acceptance gate: it runs the whole test
# suite, including the WhisperKit download, before it will install anything.
# That is the right shape for proving a release and the wrong shape for
# debugging, where the loop needs to be "change one line, get it onto the
# device, use the keyboard in a real app". This script is that loop.
#
# Environment:
#   VIBEVOICE_DEVICE   device name, UDID or identifier. Defaults to the only
#                      connected iPhone; required when more than one is paired.
#   VIBEVOICE_LAUNCH   set to 0 to install without launching.

ROOT="${0:A:h:h}"
IOS_ROOT="$ROOT/iOS"
PROJECT="$IOS_ROOT/VibeVoiceMobile.xcodeproj"
SCHEME="VibeVoiceMobile"
APP_ID="app.vibevoice.oss.ios"
TASK_CACHE_ROOT="${TMPDIR%/}/vibevoice-ios-0.7.0"
DERIVED_ROOT="$TASK_CACHE_ROOT/DerivedData/DebugDevice"
PACKAGE_ROOT="$TASK_CACHE_ROOT/SourcePackages"
# Trailing X's only; see scripts/ios-diagnostics.sh for what BSD mktemp does
# with a suffix after them.
SCRATCH_DIR=$(mktemp -d)
trap 'rm -rf "$SCRATCH_DIR"' EXIT
DEVICE_JSON="$SCRATCH_DIR/devices.json"

for tool in xcodegen jq; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        print "error: $tool is required. Install it with: brew install $tool" >&2
        exit 1
    fi
done

zsh "$ROOT/scripts/verify-librime-ios.sh"
zsh "$ROOT/scripts/verify-rime-data.sh"

xcrun devicectl list devices --json-output "$DEVICE_JSON" >/dev/null
# Anything not "unavailable" can still be woken by the install itself, so the
# filter is on the platform rather than on the tunnel being up right now.
device_query='[.result.devices[]
    | select(.hardwareProperties.platform == "iOS")
    | select(.connectionProperties.tunnelState != "unavailable")]'
# Braces are required: zsh reads a bare `$name[` as an array subscript.
if [[ -n "${VIBEVOICE_DEVICE:-}" ]]; then
    device_record=$(jq -c --arg wanted "$VIBEVOICE_DEVICE" \
        "first(${device_query}[]
            | select(.deviceProperties.name == \$wanted
                or .hardwareProperties.udid == \$wanted
                or .identifier == \$wanted))" "$DEVICE_JSON")
else
    device_record=$(jq -c "first(${device_query}[])" "$DEVICE_JSON")
    if [[ $(jq "${device_query} | length" "$DEVICE_JSON") -gt 1 ]]; then
        print "error: more than one iPhone is connected. Set VIBEVOICE_DEVICE." >&2
        jq -r "${device_query}[] | \"  \" + .deviceProperties.name" "$DEVICE_JSON" >&2
        exit 2
    fi
fi
if [[ -z "$device_record" || "$device_record" == "null" ]]; then
    print "error: no connected iPhone was found." >&2
    exit 2
fi

device_name=$(print "$device_record" | jq -r '.deviceProperties.name')
device_os=$(print "$device_record" | jq -r '.deviceProperties.osVersionNumber')
device_udid=$(print "$device_record" | jq -r '.hardwareProperties.udid')
device_id=$(print "$device_record" | jq -r '.identifier')
developer_mode=$(print "$device_record" | jq -r '.deviceProperties.developerModeStatus')

print "DEVICE $device_name — iOS $device_os"
if [[ "$developer_mode" != "enabled" ]]; then
    print "error: Developer Mode is not enabled on $device_name." >&2
    exit 4
fi

source "$ROOT/scripts/ios-signing.zsh"
vibevoice_resolve_signing "$APP_ID"
identity="$VIBEVOICE_SIGN_IDENTITY"
team_id="$VIBEVOICE_SIGN_TEAM"

mkdir -p "$DERIVED_ROOT" "$PACKAGE_ROOT"
xcodegen generate --spec "$IOS_ROOT/project.yml" --project "$IOS_ROOT"

print "BUILDING Debug"
xcodebuild build \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Debug \
    -destination "platform=iOS,id=$device_udid" \
    -derivedDataPath "$DERIVED_ROOT" \
    -clonedSourcePackagesDirPath "$PACKAGE_ROOT" \
    -onlyUsePackageVersionsFromResolvedFile \
    -allowProvisioningUpdates \
    -allowProvisioningDeviceRegistration \
    DEVELOPMENT_TEAM="$team_id" \
    CODE_SIGN_STYLE=Automatic

app_path="$DERIVED_ROOT/Build/Products/Debug-iphoneos/VibeVoiceMobile.app"
if [[ ! -d "$app_path" ]]; then
    print "error: expected a built app at $app_path." >&2
    exit 8
fi

# The keyboard extension is embedded in the app, so this installs both. iOS
# keeps the extension enabled across reinstalls, but Full Access is tied to the
# signature and can be revoked when the signing identity changes.
print "INSTALLING $app_path"
xcrun devicectl device install app --device "$device_id" "$app_path"

if [[ "${VIBEVOICE_LAUNCH:-1}" == "1" ]]; then
    # A locked device rejects the launch with CoreDeviceError 10002, which says
    # nothing about the passcode. Ask for the thing that actually needs doing.
    if xcrun devicectl device info lockState --device "$device_id" 2>/dev/null \
        | grep -q 'passcodeRequired: true'; then
        print "SKIPPED launch — $device_name is locked. Unlock it and run:"
        print "  xcrun devicectl device process launch --device $device_id $APP_ID"
    else
        print "LAUNCHING $APP_ID"
        xcrun devicectl device process launch \
            --device "$device_id" \
            --terminate-existing \
            "$APP_ID"
    fi
fi

print ""
print "INSTALLED on $device_name."
print "Next:"
print "  1. Open the app once so Rime deploys and the shared container exists."
print "  2. Diagnostics → name the channel, then switch to the app under test."
print "  3. zsh scripts/ios-diagnostics.sh pull"
