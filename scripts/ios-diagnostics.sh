#!/bin/zsh
set -euo pipefail

# Read what happened on a device, from a Mac, without Xcode attached.
#
# macOS `log stream` dropped support for iOS devices, so there is no live
# os_log feed from the command line any more. That is survivable because the
# events this project emits are also written to a JSON Lines file in the App
# Group container, and `devicectl device copy from` can read that container
# whenever the device is unlocked. The practical consequence is better than a
# live stream: the phone does not have to be tethered while the bug happens.
#
# Usage:
#   zsh scripts/ios-diagnostics.sh [pull|watch|state|crashes|clear]
#
# Environment:
#   VIBEVOICE_DEVICE   device name, UDID or identifier. Defaults to the only
#                      connected iPhone.

ROOT="${0:A:h:h}"
APP_ID="app.vibevoice.oss.ios"
KEYBOARD_ID="app.vibevoice.oss.ios.keyboard"
APP_GROUP="group.app.vibevoice.oss.shared"
BRIDGE_NOTIFICATION="app.vibevoice.oss.shared.voice-bridge-changed"
COMMAND="${1:-pull}"
WORK_DIR="${TMPDIR%/}/vibevoice-ios-diagnostics"
# The X's have to be trailing: BSD mktemp leaves a template alone when anything
# follows them, so `foo.XXXXXX.json` yields that name literally and every run
# collides on it. A private directory sidesteps the naming rule entirely.
SCRATCH_DIR=$(mktemp -d)
trap 'rm -rf "$SCRATCH_DIR"' EXIT
DEVICE_JSON="$SCRATCH_DIR/devices.json"

if ! command -v jq >/dev/null 2>&1; then
    print "error: jq is required. Install it with: brew install jq" >&2
    exit 1
fi

xcrun devicectl list devices --json-output "$DEVICE_JSON" >/dev/null
device_query='[.result.devices[]
    | select(.hardwareProperties.platform == "iOS")
    | select(.connectionProperties.tunnelState != "unavailable")]'
# Braces are required: zsh reads a bare `$name[` as an array subscript.
if [[ -n "${VIBEVOICE_DEVICE:-}" ]]; then
    device_id=$(jq -r --arg wanted "$VIBEVOICE_DEVICE" \
        "first(${device_query}[]
            | select(.deviceProperties.name == \$wanted
                or .hardwareProperties.udid == \$wanted
                or .identifier == \$wanted)).identifier" "$DEVICE_JSON")
else
    device_id=$(jq -r "first(${device_query}[]).identifier" "$DEVICE_JSON")
fi
if [[ -z "$device_id" || "$device_id" == "null" ]]; then
    print "error: no connected iPhone was found." >&2
    exit 2
fi
device_name=$(jq -r --arg id "$device_id" \
    "first(${device_query}[] | select(.identifier == \$id)).deviceProperties.name" "$DEVICE_JSON")

# Renders the merged event stream. Both processes append to their own file, so
# ordering only exists once the two are interleaved by timestamp here.
render_events() {
    setopt local_options null_glob
    local files=()
    local directory
    for directory in "$@"; do
        files+=("$directory"/*.jsonl)
    done
    if (( ${#files} == 0 )); then
        print "No event files were found. The app has not run since the" >&2
        print "diagnostics layer was installed, or the device was locked." >&2
        return 1
    fi
    # Events are stored in UTC. They are rendered in the Mac's local time so
    # they line up with crash reports and with what the person holding the
    # phone says the clock read, which is where correlation actually happens.
    cat "${files[@]}" | jq -rs '
        sort_by(.timestamp)[]
        | (.timestamp | sub("\\.[0-9]+"; "")
           | fromdateiso8601 | strflocaltime("%H:%M:%S"))
          + " " + .process + "/" + .area
          + (if .channel then " [" + .channel + "]" else "" end)
          + " " + .name
          + " " + (.fields | to_entries | sort_by(.key)
                   | map(.key + "=" + .value) | join(" "))
    '
}

case "$COMMAND" in
pull)
    rm -rf "$WORK_DIR"
    # `copy from` unpacks the *contents* of --source into --destination, so the
    # events land directly here and there is no Diagnostics/ level underneath.
    events_dir="$WORK_DIR/events"
    mkdir -p "$events_dir"
    print "PULLING diagnostics from $device_name"
    # A missing directory is itself a finding, and a different one from an empty
    # directory, so it gets its own explanation rather than a raw error code.
    if ! xcrun devicectl device copy from \
        --device "$device_id" \
        --domain-type appGroupDataContainer \
        --domain-identifier "$APP_GROUP" \
        --source Diagnostics \
        --destination "$events_dir" >/dev/null 2>"$SCRATCH_DIR/copy.err"; then
        print "" >&2
        print "There is no Diagnostics directory in the App Group container." >&2
        print "Either the instrumented build has not run on this device yet:" >&2
        print "    zsh scripts/debug-ios-device.sh   # then open the app once" >&2
        print "or the device is locked, which hides the container." >&2
        print "" >&2
        cat "$SCRATCH_DIR/copy.err" >&2
        exit 3
    fi
    # Without Full Access the keyboard cannot write to the shared container, so
    # its events fall back to its own sandbox. That is the configuration most
    # worth reading, so it is not optional — but it is also normal for this
    # directory not to exist, which is why a failure here is not reported.
    private_dir="$WORK_DIR/keyboard-private"
    mkdir -p "$private_dir"
    xcrun devicectl device copy from \
        --device "$device_id" \
        --domain-type appDataContainer \
        --domain-identifier "$KEYBOARD_ID" \
        --source "Library/Application Support/Diagnostics" \
        --destination "$private_dir" >/dev/null 2>&1 || true

    print ""
    render_events "$events_dir" "$private_dir"
    print ""
    print "raw: $events_dir"
    if [[ -n "$(print -rn -- "$private_dir"/*.jsonl(N))" ]]; then
        print "     $private_dir  (keyboard without Full Access)"
    fi
    ;;

watch)
    # The bridge signal is a Darwin notification, and devicectl can observe
    # those directly. It carries no payload, so this shows the timing of every
    # handoff between the app and the keyboard without touching either process.
    print "OBSERVING $BRIDGE_NOTIFICATION on $device_name — Ctrl-C to stop"
    xcrun devicectl device notification observe \
        --device "$device_id" \
        --name "$BRIDGE_NOTIFICATION" \
        --session-timeout 3600 \
        --timeout 3601
    ;;

state)
    print "APP GROUP CONTAINER — $device_name"
    # The bridge state file itself is written with complete file protection and
    # cannot be copied off the device; its presence and size still say whether
    # the two processes ever met.
    xcrun devicectl device info files \
        --device "$device_id" \
        --domain-type appGroupDataContainer \
        --domain-identifier "$APP_GROUP" \
        --subdirectory . 2>&1 | grep -v '^[0-9][0-9]:'
    print ""
    # A Rime tree here rather than in the shared container above means the
    # keyboard fell back to its own sandbox, which is what happens when Full
    # Access is off: the shared container is readable but not writable.
    print "KEYBOARD EXTENSION CONTAINER — $device_name"
    xcrun devicectl device info files \
        --device "$device_id" \
        --domain-type appDataContainer \
        --domain-identifier "$KEYBOARD_ID" \
        --subdirectory . 2>&1 | grep -v '^[0-9][0-9]:'
    ;;

crashes)
    rm -rf "$WORK_DIR/crashes"
    mkdir -p "$WORK_DIR/crashes"
    print "LISTING crash reports on $device_name"
    # Copying the whole directory fails: it holds system reports the file
    # service cannot read, and one refusal aborts the entire transfer. So the
    # listing is filtered first and each report is fetched on its own.
    reports=("${(@f)$(xcrun devicectl device info files \
        --device "$device_id" \
        --domain-type systemCrashLogs \
        --filter "Name CONTAINS 'VibeVoice'" 2>/dev/null \
        | sed -n 's/^\(VibeVoice[^[:space:]]*\).*/\1/p')}")
    reports=("${(@)reports:#}")
    if (( ${#reports} == 0 )); then
        print "No VibeVoice crash reports. That is the good outcome."
        exit 0
    fi
    for report in "${reports[@]}"; do
        if xcrun devicectl device copy from \
            --device "$device_id" \
            --domain-type systemCrashLogs \
            --source "$report" \
            --destination "$WORK_DIR/crashes/$report" >/dev/null 2>&1; then
            print "  pulled $report"
        else
            print "  unreadable $report (device locked?)" >&2
        fi
    done
    print ""
    print "raw: $WORK_DIR/crashes"
    ;;

clear)
    print "error: clear the log from the app's Diagnostics screen." >&2
    print "The file service can read the container but not delete from it." >&2
    exit 1
    ;;

*)
    print "usage: zsh scripts/ios-diagnostics.sh [pull|watch|state|crashes]" >&2
    exit 64
    ;;
esac
