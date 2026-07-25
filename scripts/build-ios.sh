#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
IOS_ROOT="$ROOT/iOS"
PROJECT="$IOS_ROOT/VibeVoiceMobile.xcodeproj"
SCHEME="VibeVoiceMobile"
DEVICE_TYPE="com.apple.CoreSimulator.SimDeviceType.iPhone-14-Pro-Max"
TASK_CACHE_ROOT="${TMPDIR%/}/vibevoice-ios-0.7.0"
DERIVED_ROOT="$TASK_CACHE_ROOT/DerivedData"
RESULT_ROOT="$TASK_CACHE_ROOT/TestResults"
PACKAGE_ROOT="$TASK_CACHE_ROOT/SourcePackages"

if ! command -v xcodegen >/dev/null 2>&1; then
    print "error: XcodeGen is required. Install it with: brew install xcodegen" >&2
    exit 1
fi

mkdir -p "$DERIVED_ROOT" "$RESULT_ROOT" "$PACKAGE_ROOT"
# Projects stored under Documents may inherit File Provider metadata that
# codesign rejects when it reaches a built keyboard extension. Build products
# therefore live outside that tree.
xcodegen generate --spec "$IOS_ROOT/project.yml" --project "$IOS_ROOT"

typeset -a runtime_prefixes
runtime_prefixes=("17" "18" "26")
typeset -i passed=0
typeset -i skipped=0

for prefix in "${runtime_prefixes[@]}"; do
    runtime_line=$(xcrun simctl list runtimes available \
        | sed -n "/iOS ${prefix}\\./p" \
        | head -n 1)
    if [[ -z "$runtime_line" ]]; then
        print "SKIPPED iOS $prefix — Runtime Missing"
        (( skipped += 1 ))
        continue
    fi

    runtime_name=$(print "$runtime_line" | sed -E 's/^iOS ([0-9.]+).*/\1/')
    runtime_id=$(print "$runtime_line" | sed -E 's/.* - (com\.apple\.CoreSimulator\.SimRuntime\.iOS-[0-9-]+).*/\1/')
    simulator_name="VibeVoice-iPhone14PM-iOS${prefix}"
    simulator_id=$(xcrun simctl list devices available \
        | sed -n "s/^[[:space:]]*${simulator_name} (\([0-9A-F-]*\)).*/\1/p" \
        | head -n 1)

    if [[ -z "$simulator_id" ]]; then
        simulator_id=$(xcrun simctl create "$simulator_name" "$DEVICE_TYPE" "$runtime_id")
    fi

    xcrun simctl boot "$simulator_id" 2>/dev/null || true
    xcrun simctl bootstatus "$simulator_id" -b

    result_bundle="$RESULT_ROOT/iOS${prefix}-$(date +%Y%m%d-%H%M%S).xcresult"
    print "TESTING iOS $runtime_name — $simulator_name ($simulator_id)"
    xcodebuild test \
        -project "$PROJECT" \
        -scheme "$SCHEME" \
        -destination "platform=iOS Simulator,id=$simulator_id" \
        -derivedDataPath "$DERIVED_ROOT/iOS${prefix}" \
        -clonedSourcePackagesDirPath "$PACKAGE_ROOT" \
        -onlyUsePackageVersionsFromResolvedFile \
        -resultBundlePath "$result_bundle" \
        -parallel-testing-enabled NO \
        -test-timeouts-enabled YES \
        -default-test-execution-time-allowance 900 \
        -maximum-test-execution-time-allowance 1200 \
        -only-testing:VibeVoiceMobileTests \
        -only-testing:VibeVoiceMobileUITests

    app_path="$DERIVED_ROOT/iOS${prefix}/Build/Products/Debug-iphonesimulator/VibeVoiceMobile.app"
    xcrun simctl install "$simulator_id" "$app_path"
    xcrun simctl launch --terminate-running-process \
        "$simulator_id" app.vibevoice.oss.ios >/dev/null
    xcrun simctl terminate "$simulator_id" app.vibevoice.oss.ios
    print "SMOKE PASSED iOS $runtime_name — app installed and launched"
    (( passed += 1 ))
done

xcodebuild build \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -destination "generic/platform=iOS" \
    -derivedDataPath "$DERIVED_ROOT/Device" \
    -clonedSourcePackagesDirPath "$PACKAGE_ROOT" \
    -onlyUsePackageVersionsFromResolvedFile \
    CODE_SIGNING_ALLOWED=NO
print "DEVICE BUILD PASSED — generic arm64 iOS"

print "iOS simulator matrix complete: $passed passed, $skipped skipped"
