#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
APP_NAME="${VIBE_VOICE_APP_NAME:-Vibe Voice OSS}"
EXECUTABLE_NAME="VibeVoiceOSS"
ICON_NAME="VibeVoiceOSS"

# The name is interpolated into paths that get rm -rf'd, including one under
# /Applications, so it has to stay a plain bundle name.
if [[ -z "$APP_NAME" || "$APP_NAME" == */* || "$APP_NAME" == .* ]]; then
    echo "error: VIBE_VOICE_APP_NAME must be a plain bundle name, got '$APP_NAME'" >&2
    exit 1
fi

APP="$ROOT/dist/${APP_NAME}.app"
IDENTITY="${CODESIGN_IDENTITY:-}"
LOCAL_SIGNING_IDENTITY="Vibe Voice OSS Local Code Signing"
STAGING_DIR=$(mktemp -d)
STAGED_APP="$STAGING_DIR/${APP_NAME}.app"
trap 'rm -rf "$STAGING_DIR"' EXIT

cd "$ROOT"
swift build -c release
swift "$ROOT/scripts/generate-icon.swift" "$ROOT/Resources/${ICON_NAME}.icns"

# Compile MLX Metal shaders into default.metallib (required by MLX GPU runtime).
METALLIB="$ROOT/.build/release/default.metallib"
if [[ ! -f "$METALLIB" ]] || [[ "$ROOT/.build/checkouts/mlx-swift/Package.swift" -nt "$METALLIB" ]]; then
    echo "Compiling MLX Metal shaders..."
    CMLX="$ROOT/.build/checkouts/mlx-swift/Source/Cmlx"
    METAL_DIR="$CMLX/mlx-generated/metal"
    KERNEL_INCLUDE="$CMLX/mlx/mlx/backend/metal/kernels"
    STEEL_INCLUDE="$CMLX/mlx/mlx/backend/metal/kernels/steel"
    MLX_INCLUDE="$CMLX/mlx"
    AIR_DIR=$(mktemp -d)
    trap 'rm -rf "$AIR_DIR" "$STAGING_DIR"' EXIT
    metal_count=0
    air_count=0
    for f in "$METAL_DIR"/*.metal(N); do
        metal_count=$((metal_count + 1))
        base=$(basename "$f" .metal)
        xcrun metal -c -I "$KERNEL_INCLUDE" -I "$STEEL_INCLUDE" -I "$MLX_INCLUDE" \
            -std=metal3.2 -target air64-apple-macos15.0 \
            "$f" -o "$AIR_DIR/$base.air"
        air_count=$((air_count + 1))
    done
    if (( metal_count == 0 )); then
        echo "error: no .metal sources under $METAL_DIR" >&2
        exit 1
    fi
    if (( air_count == 0 )); then
        echo "error: Metal compile produced no .air files (is Metal Toolchain installed?)" >&2
        echo "  Install with: xcodebuild -downloadComponent MetalToolchain" >&2
        exit 1
    fi
    xcrun metallib "$AIR_DIR"/*.air -o "$METALLIB"
    rm -rf "$AIR_DIR"
    echo "MLX metallib compiled: $(du -h "$METALLIB" | cut -f1)"
fi

mkdir -p "$STAGED_APP/Contents/MacOS" "$STAGED_APP/Contents/Resources"
cp "$ROOT/.build/release/${EXECUTABLE_NAME}" "$STAGED_APP/Contents/MacOS/${EXECUTABLE_NAME}"
# Place metallib inside a flat .bundle matching SWIFTPM_BUNDLE ("mlx-swift_Cmlx")
# so MLX's load_swiftpm_library() finds it via NS::Bundle::mainBundle()->bundleURL().
MLX_BUNDLE="$STAGED_APP/Contents/Resources/mlx-swift_Cmlx.bundle"
mkdir -p "$MLX_BUNDLE"
cp "$METALLIB" "$MLX_BUNDLE/default.metallib"
cp "$ROOT/Resources/Info.plist" "$STAGED_APP/Contents/Info.plist"
cp "$ROOT/Resources/${ICON_NAME}.icns" "$STAGED_APP/Contents/Resources/${ICON_NAME}.icns"

xattr -cr "$STAGED_APP"
if [[ -z "$IDENTITY" ]]; then
    IDENTITY=$(security find-identity -v -p codesigning \
        | sed -n "s/.*\"\(${LOCAL_SIGNING_IDENTITY}\)\".*/\1/p" \
        | head -n 1)
fi
if [[ -z "$IDENTITY" ]]; then
    # Sort so the same certificate is always picked when several are installed;
    # a drifting identity re-triggers Keychain/Accessibility permission prompts.
    IDENTITY=$(security find-identity -v -p codesigning \
        | sed -n 's/.*"\(Apple Development:[^"]*\)".*/\1/p' \
        | sort \
        | head -n 1)
fi

# --deep is deprecated for signing (it is still the right flag for verification).
# There is no nested Mach-O code in the bundle, so a plain signature seals
# everything; the metallib is sealed as a resource.
SIGN_ARGS=(--force --timestamp=none)
ENTITLEMENTS="$ROOT/Resources/${EXECUTABLE_NAME}.entitlements"
if [[ -z "${VIBE_VOICE_SKIP_HARDENED_RUNTIME:-}" ]]; then
    # The hardened runtime stops other processes from injecting code into the app
    # or reading the memory that holds decrypted API keys, and is a prerequisite
    # for notarization. It also denies the microphone and Apple Events unless the
    # entitlements request them. Set VIBE_VOICE_SKIP_HARDENED_RUNTIME=1 to bisect
    # a launch failure back to this.
    if [[ ! -f "$ENTITLEMENTS" ]]; then
        echo "error: missing entitlements file: $ENTITLEMENTS" >&2
        exit 1
    fi
    SIGN_ARGS+=(--options runtime --entitlements "$ENTITLEMENTS")
    echo "Hardened runtime: enabled"
else
    echo "Hardened runtime: disabled (VIBE_VOICE_SKIP_HARDENED_RUNTIME set)"
fi

if [[ -n "$IDENTITY" ]]; then
    codesign "${SIGN_ARGS[@]}" --sign "$IDENTITY" "$STAGED_APP"
    echo "Signed with: $IDENTITY"
else
    codesign "${SIGN_ARGS[@]}" --sign - "$STAGED_APP"
    echo "Warning: no persistent code-signing identity found; permissions may reset after rebuild."
fi
codesign --verify --deep --strict "$STAGED_APP"

rm -rf "$APP"
mkdir -p "${APP:h}"
ditto "$STAGED_APP" "$APP"

# CI packaging only needs dist/; set VIBE_VOICE_SKIP_INSTALL=1 to skip /Applications.
if [[ -n "${VIBE_VOICE_SKIP_INSTALL:-}" ]]; then
    xattr -cr "$APP"
    codesign --verify --deep --strict "$APP"
    echo "$APP"
    exit 0
fi

# Keep /Applications copy in sync for Launch-at-Login and menu-bar daily use.
APPLICATIONS_APP="/Applications/${APP_NAME}.app"
if [[ -d "$APPLICATIONS_APP" || -L "$APPLICATIONS_APP" ]]; then
    rm -rf "$APPLICATIONS_APP"
fi
ditto "$APP" "$APPLICATIONS_APP"
xattr -cr "$APPLICATIONS_APP"
if [[ -n "$IDENTITY" ]]; then
    codesign "${SIGN_ARGS[@]}" --sign "$IDENTITY" "$APPLICATIONS_APP"
else
    codesign "${SIGN_ARGS[@]}" --sign - "$APPLICATIONS_APP"
fi

# Documents may be managed by File Provider, which can attach Finder metadata
# immediately after copying. Remove it and verify the sealed bundle before returning.
for bundle in "$APP" "$APPLICATIONS_APP"; do
    for attempt in 1 2 3; do
        xattr -cr "$bundle"
        if codesign --verify --deep --strict "$bundle" 2>/dev/null; then
            break
        fi
        if [[ "$attempt" == 3 ]]; then
            codesign --verify --deep --strict --verbose=2 "$bundle"
        fi
        sleep 0.2
    done
done
echo "$APP"
echo "$APPLICATIONS_APP"
