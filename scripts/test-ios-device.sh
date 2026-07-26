#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
IOS_ROOT="$ROOT/iOS"
PROJECT="$IOS_ROOT/VibeVoiceMobile.xcodeproj"
SCHEME="VibeVoiceMobile"
EXPECTED_MODEL="iPhone 14 Pro Max"
EXPECTED_OS_PREFIX="26."
TASK_CACHE_ROOT="${TMPDIR%/}/vibevoice-ios-0.7.0"
DERIVED_ROOT="$TASK_CACHE_ROOT/DerivedData/PhysicalDevice"
RESULT_ROOT="$TASK_CACHE_ROOT/DeviceTestResults"
PACKAGE_ROOT="$TASK_CACHE_ROOT/SourcePackages"
DEVICE_JSON=$(mktemp /tmp/vibevoice-device-list.XXXXXX.json)
trap 'rm -f "$DEVICE_JSON"' EXIT

if ! command -v xcodegen >/dev/null 2>&1; then
    print "error: XcodeGen is required. Install it with: brew install xcodegen" >&2
    exit 1
fi
if ! command -v jq >/dev/null 2>&1; then
    print "error: jq is required. Install it with: brew install jq" >&2
    exit 1
fi

zsh "$ROOT/scripts/verify-librime-ios.sh"

xcrun devicectl list devices --json-output "$DEVICE_JSON" >/dev/null
device_record=$(jq -c --arg model "$EXPECTED_MODEL" '
    first(.result.devices[] | select(.hardwareProperties.marketingName == $model))
' "$DEVICE_JSON")
if [[ -z "$device_record" || "$device_record" == "null" ]]; then
    print "error: paired $EXPECTED_MODEL was not found." >&2
    exit 2
fi

device_name=$(print "$device_record" | jq -r '.deviceProperties.name')
device_os=$(print "$device_record" | jq -r '.deviceProperties.osVersionNumber')
device_state=$(print "$device_record" | jq -r '.connectionProperties.tunnelState')
device_udid=$(print "$device_record" | jq -r '.hardwareProperties.udid')
developer_mode=$(print "$device_record" | jq -r '.deviceProperties.developerModeStatus')

print "DEVICE $device_name — $EXPECTED_MODEL — iOS $device_os — $device_state"
if [[ "$device_os" != ${EXPECTED_OS_PREFIX}* ]]; then
    print "error: expected iOS 26.x, found $device_os." >&2
    exit 3
fi
if [[ "$developer_mode" != "enabled" ]]; then
    print "error: Developer Mode is not enabled on $device_name." >&2
    exit 4
fi
if [[ "$device_state" == "unavailable" ]]; then
    print "error: unlock and connect $device_name by USB or paired Wi-Fi, then retry." >&2
    exit 5
fi

identity=$(security find-identity -v -p codesigning \
    | sed -n 's/.*"\(Apple Development:[^"]*\)".*/\1/p' \
    | head -n 1)
if [[ -z "$identity" ]]; then
    print "error: no Apple Development signing identity was found." >&2
    exit 6
fi
team_id=$(security find-certificate -c "$identity" -p \
    | openssl x509 -noout -subject \
    | sed -n 's/.*OU=\([^,]*\).*/\1/p')
if [[ -z "$team_id" ]]; then
    print "error: could not read Team ID from $identity." >&2
    exit 7
fi

mkdir -p "$DERIVED_ROOT" "$RESULT_ROOT" "$PACKAGE_ROOT"
xcodegen generate --spec "$IOS_ROOT/project.yml" --project "$IOS_ROOT"
result_bundle="$RESULT_ROOT/${device_name//[^[:alnum:]]/_}-iOS${device_os}-$(date +%Y%m%d-%H%M%S).xcresult"

print "SIGNING $identity — Team $team_id"
xcodebuild test \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -destination "platform=iOS,id=$device_udid" \
    -derivedDataPath "$DERIVED_ROOT" \
    -clonedSourcePackagesDirPath "$PACKAGE_ROOT" \
    -onlyUsePackageVersionsFromResolvedFile \
    -resultBundlePath "$result_bundle" \
    -allowProvisioningUpdates \
    -allowProvisioningDeviceRegistration \
    -parallel-testing-enabled NO \
    -test-timeouts-enabled YES \
    -default-test-execution-time-allowance 900 \
    -maximum-test-execution-time-allowance 1200 \
    -only-testing:VibeVoiceMobileTests \
    -only-testing:VibeVoiceMobileUITests \
    DEVELOPMENT_TEAM="$team_id" \
    CODE_SIGN_STYLE=Automatic

xcrun xcresulttool get test-results summary \
    --path "$result_bundle"
print "PHYSICAL DEVICE TEST PASSED — evidence: $result_bundle"
print "Complete docs/ios-device-acceptance.md before final acceptance."
