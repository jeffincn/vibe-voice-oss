#!/bin/zsh
# Checks the committed librime static archives against their recorded digests.
#
# The XCFramework is a binary that is committed rather than built from source
# during a normal build, so nothing else in the tree can tell whether it is
# still the artefact scripts/prepare-librime-ios.sh produced.
set -euo pipefail

ROOT="${0:A:h:h}"
VENDOR="$ROOT/iOS/Vendor"
MANIFEST="$VENDOR/librime.xcframework.sha256"

if [[ ! -f "$MANIFEST" ]]; then
    print "error: missing $MANIFEST" >&2
    print "note: run scripts/prepare-librime-ios.sh to rebuild and record it" >&2
    exit 1
fi

if ! (cd "$VENDOR" && shasum -a 256 --check --status "$MANIFEST"); then
    print "error: vendored librime archives do not match their recorded digests" >&2
    print "note: expected contents are listed in $MANIFEST" >&2
    (cd "$VENDOR" && shasum -a 256 --check "$MANIFEST") >&2 || true
    exit 1
fi

print "librime archives verified against $MANIFEST"
