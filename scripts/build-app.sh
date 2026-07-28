#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
APP_NAME="${VIBE_VOICE_APP_NAME:-Vibe Voice OSS}"
EXECUTABLE_NAME="VibeVoiceOSS"
INPUT_METHOD_EXECUTABLE="VibeVoiceInputMethod"
INPUT_METHOD_BUNDLE_NAME="VibeVoiceInputMethod.app"
INPUT_METHOD_BUNDLE_ID="app.vibevoice.oss.inputmethod.pinyin"
INPUT_METHOD_PKG_ID="$INPUT_METHOD_BUNDLE_ID"
INPUT_METHOD_PKG="$ROOT/dist/VibeVoiceInputMethod.pkg"
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
swift build -c release --disable-automatic-resolution --product "$EXECUTABLE_NAME"
swift build -c release --disable-automatic-resolution --product "$INPUT_METHOD_EXECUTABLE"
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
if [[ -d "$ROOT/Resources/Lexicon" ]]; then
    ditto "$ROOT/Resources/Lexicon" "$STAGED_APP/Contents/Resources/Lexicon"
fi

# Bundle the InputMethodKit server inside the app and also install it at the
# user-level input-method location. The nested executable is signed separately
# before the outer application is sealed (codesign --deep is never used to sign).
IMK_STAGED="$STAGED_APP/Contents/Library/Input Methods/$INPUT_METHOD_BUNDLE_NAME"
mkdir -p "$IMK_STAGED/Contents/MacOS" "$IMK_STAGED/Contents/Resources"
cp "$ROOT/.build/release/${INPUT_METHOD_EXECUTABLE}" "$IMK_STAGED/Contents/MacOS/${INPUT_METHOD_EXECUTABLE}"
cp "$ROOT/Sources/VibeVoiceInputMethod/InputMethodInfo.plist" "$IMK_STAGED/Contents/Info.plist"
printf 'APPL????' > "$IMK_STAGED/Contents/PkgInfo"
cp "$ROOT/Resources/${ICON_NAME}.icns" "$IMK_STAGED/Contents/Resources/VibeVoice.icns"
# Menu-bar / input-source list icons must be template PDFs. A full-color .icns
# is what made Vibe Type look out of place next to ABC / Squirrel / Apple Pinyin.
swift "$ROOT/scripts/generate-input-method-menu-icon.swift" "$ROOT/Resources/VibeTypeMenu.pdf"
cp "$ROOT/Resources/VibeTypeMenu.pdf" "$IMK_STAGED/Contents/Resources/VibeTypeMenu.pdf"
# Without these the input source list falls back to showing the raw mode identifier.
for lproj in "$ROOT/Sources/VibeVoiceInputMethod"/*.lproj(N); do
    ditto "$lproj" "$IMK_STAGED/Contents/Resources/${lproj:t}"
done
if [[ -d "$ROOT/Resources/RimeData" ]]; then
    ditto "$ROOT/Resources/RimeData" "$IMK_STAGED/Contents/Resources/RimeData"
fi
if [[ -d "$ROOT/Resources/Lexicon" ]]; then
    ditto "$ROOT/Resources/Lexicon" "$IMK_STAGED/Contents/Resources/Lexicon"
fi
# The Core ML candidate reranker. Without it the input method still works and
# falls back to Rime's own order, so a missing model is a warning, not a stop.
if [[ -d "$ROOT/Resources/CandidateRanker/VibeCandidateRanker.mlmodelc" ]]; then
    # Only the compiled model is loadable at runtime; the .mlmodel spec and the
    # manifest stay in the repo rather than inside a sealed bundle.
    ditto "$ROOT/Resources/CandidateRanker/VibeCandidateRanker.mlmodelc" \
        "$IMK_STAGED/Contents/Resources/CandidateRanker/VibeCandidateRanker.mlmodelc"
else
    echo "warning: VibeCandidateRanker.mlmodelc missing; candidates will use Rime order only" >&2
    echo "  Regenerate with: python3 scripts/generate-candidate-ranker-model.py" >&2
fi

# When Homebrew librime is available, make the IMK bundle self-contained so
# it does not depend on a developer's Homebrew prefix at runtime. The C target
# still builds a no-op adapter on machines without librime and falls back to
# the built-in pinyin engine.
RIME_PREFIX="${VIBE_VOICE_RIME_PREFIX:-/opt/homebrew/opt/librime}"
IMK_FRAMEWORKS="$IMK_STAGED/Contents/Frameworks"
if [[ -f "$RIME_PREFIX/lib/librime.1.dylib" ]]; then
    mkdir -p "$IMK_FRAMEWORKS"
    cp -L "$RIME_PREFIX/lib/librime.1.dylib" "$IMK_FRAMEWORKS/librime.1.dylib"
    for dependency_prefix in glog yaml-cpp gflags leveldb marisa opencc lua snappy; do
        for dependency in /opt/homebrew/opt/$dependency_prefix/lib/*.dylib(N); do
            cp -L "$dependency" "$IMK_FRAMEWORKS/${dependency:t}"
        done
    done
    # Homebrew bottles are often admin-owned and read-only; copied bundle code
    # must be writable for xattr cleanup and install-name rewriting.
    chmod -R u+rw "$IMK_FRAMEWORKS"
    if [[ -d "$RIME_PREFIX/lib/rime-plugins" && -d "$IMK_STAGED/Contents/Resources/RimeData" ]]; then
        mkdir -p "$IMK_STAGED/Contents/Resources/RimeData/rime-plugins"
        for plugin in "$RIME_PREFIX/lib/rime-plugins"/*.dylib(N); do
            cp -L "$plugin" "$IMK_STAGED/Contents/Resources/RimeData/rime-plugins/${plugin:t}"
        done
        chmod -R u+rw "$IMK_STAGED/Contents/Resources/RimeData/rime-plugins"
    fi
    install_name_tool -id "@rpath/librime.1.dylib" "$IMK_FRAMEWORKS/librime.1.dylib"
    install_name_tool -change "$RIME_PREFIX/lib/librime.1.dylib" "@loader_path/../Frameworks/librime.1.dylib" "$IMK_STAGED/Contents/MacOS/${INPUT_METHOD_EXECUTABLE}"
    for binary in "$IMK_FRAMEWORKS"/*.dylib "$IMK_STAGED/Contents/Resources/RimeData/rime-plugins"/*.dylib(N); do
        [[ -f "$binary" ]] || continue
        while read -r dependency_path; do
            [[ "$dependency_path" == /opt/homebrew/opt/*/lib/*.dylib ]] || continue
            dependency_name="${dependency_path:t}"
            if [[ -f "$IMK_FRAMEWORKS/$dependency_name" ]]; then
                if [[ "$binary" == */RimeData/rime-plugins/* ]]; then
                    install_name_tool -change "$dependency_path" "@loader_path/../../Frameworks/$dependency_name" "$binary"
                else
                    install_name_tool -change "$dependency_path" "@loader_path/$dependency_name" "$binary"
                fi
            fi
        done < <(otool -L "$binary" | sed -n '2,$ s/^[[:space:]]*\([^ ]*\.dylib\).*/\1/p')
        if [[ "$binary" == */RimeData/rime-plugins/* ]]; then
            install_name_tool -change "@rpath/librime.1.dylib" "@loader_path/../../Frameworks/librime.1.dylib" "$binary" 2>/dev/null || true
        fi
    done
fi

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
IMK_SIGN_ARGS=(--force --timestamp=none --options runtime)
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
    for nested_binary in "$IMK_FRAMEWORKS"/*.dylib "$IMK_STAGED/Contents/Resources/RimeData/rime-plugins"/*.dylib(N); do
        [[ -f "$nested_binary" ]] && codesign "${IMK_SIGN_ARGS[@]}" --sign "$IDENTITY" "$nested_binary"
    done
    codesign "${IMK_SIGN_ARGS[@]}" --sign "$IDENTITY" "$IMK_STAGED"
    codesign "${SIGN_ARGS[@]}" --sign "$IDENTITY" "$STAGED_APP"
    echo "Signed with: $IDENTITY"
else
    for nested_binary in "$IMK_FRAMEWORKS"/*.dylib "$IMK_STAGED/Contents/Resources/RimeData/rime-plugins"/*.dylib(N); do
        [[ -f "$nested_binary" ]] && codesign "${IMK_SIGN_ARGS[@]}" --sign - "$nested_binary"
    done
    codesign "${IMK_SIGN_ARGS[@]}" --sign - "$IMK_STAGED"
    codesign "${SIGN_ARGS[@]}" --sign - "$STAGED_APP"
    echo "Warning: no persistent code-signing identity found; permissions may reset after rebuild."
fi
codesign --verify --deep --strict "$STAGED_APP"

# Build a standard macOS installer package for the input method. Installing it
# system-wide under /Library/Input Methods lets Text Input Sources discover it
# through the same path used by production input methods such as Squirrel.
PKG_ROOT="$STAGING_DIR/pkg-root"
PKG_SCRIPTS="$STAGING_DIR/pkg-scripts"
PKG_RAW="$STAGING_DIR/VibeVoiceInputMethod-raw.pkg"
PKG_UNSIGNED="$STAGING_DIR/VibeVoiceInputMethod-unsigned.pkg"
PKG_REPACKED="$STAGING_DIR/pkg-repacked"
PKG_EXPANDED="$STAGING_DIR/pkg-expanded"
PKG_COMPONENTS="$STAGING_DIR/pkg-components.plist"
IMK_SHORT_VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
    "$IMK_STAGED/Contents/Info.plist")
IMK_BUILD_VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' \
    "$IMK_STAGED/Contents/Info.plist")
PKG_VERSION="${IMK_SHORT_VERSION}.${IMK_BUILD_VERSION}"

mkdir -p "$PKG_ROOT" "$PKG_SCRIPTS" "$ROOT/dist"
cp "$ROOT/scripts/input-method-pkg/preinstall" "$PKG_SCRIPTS/preinstall"
cp "$ROOT/scripts/input-method-pkg/postinstall" "$PKG_SCRIPTS/postinstall"
chmod 755 "$PKG_SCRIPTS/preinstall" "$PKG_SCRIPTS/postinstall"
COPYFILE_DISABLE=1 ditto --norsrc \
    "$IMK_STAGED" \
    "$PKG_ROOT/$INPUT_METHOD_BUNDLE_NAME"
# A managed workspace may synthesize AppleDouble sidecars while copying. They
# are real payload files, not xattrs, and make strict code-signature validation
# fail after installation.
for sidecar in "$PKG_ROOT"/**/._*(ND); do
    rm -f "$sidecar"
done

# PackageKit otherwise searches the disk for an existing bundle with the same
# identifier and relocates this payload to that old path. That would preserve
# the former ~/Library/Input Methods installation instead of installing at the
# system input-method path.
pkgbuild --analyze --root "$PKG_ROOT" "$PKG_COMPONENTS"
/usr/libexec/PlistBuddy -c 'Set :0:BundleIsRelocatable false' "$PKG_COMPONENTS"
/usr/libexec/PlistBuddy -c 'Set :0:BundleIsVersionChecked true' "$PKG_COMPONENTS"
/usr/libexec/PlistBuddy -c 'Set :0:BundleHasStrictIdentifier true' "$PKG_COMPONENTS"
/usr/libexec/PlistBuddy -c 'Set :0:BundleOverwriteAction upgrade' "$PKG_COMPONENTS"

pkgbuild \
    --root "$PKG_ROOT" \
    --scripts "$PKG_SCRIPTS" \
    --component-plist "$PKG_COMPONENTS" \
    --identifier "$INPUT_METHOD_PKG_ID" \
    --version "$PKG_VERSION" \
    --install-location "/Library/Input Methods" \
    --ownership recommended \
    "$PKG_RAW"

# InputMethodKit processes from the old login session may retain stale bundle
# metadata. Squirrel's production package requires logout for the same reason.
pkgutil --expand "$PKG_RAW" "$PKG_REPACKED"
/usr/bin/perl -0pi -e \
    's/postinstall-action="none"/postinstall-action="logout"/' \
    "$PKG_REPACKED/PackageInfo"
[[ "$(<"$PKG_REPACKED/PackageInfo")" == *'postinstall-action="logout"'* ]]
pkgutil --flatten "$PKG_REPACKED" "$PKG_UNSIGNED"

INSTALLER_IDENTITY="${PRODUCTSIGN_IDENTITY:-}"
if [[ -z "$INSTALLER_IDENTITY" ]]; then
    INSTALLER_IDENTITY=$(security find-identity -v -p basic \
        | sed -n 's/.*"\(\(Developer ID Installer\|Mac Installer Distribution\):[^"]*\)".*/\1/p' \
        | sort \
        | head -n 1)
fi
rm -f "$INPUT_METHOD_PKG"
if [[ -n "$INSTALLER_IDENTITY" ]]; then
    productsign --sign "$INSTALLER_IDENTITY" "$PKG_UNSIGNED" "$INPUT_METHOD_PKG"
    echo "Installer signed with: $INSTALLER_IDENTITY"
else
    mv "$PKG_UNSIGNED" "$INPUT_METHOD_PKG"
    echo "Warning: no Installer signing identity found; generated an unsigned local .pkg."
fi

# Fully expanding validates both the flat package archive and its payload.
pkgutil --expand-full "$INPUT_METHOD_PKG" "$PKG_EXPANDED"
test -f "$PKG_EXPANDED/PackageInfo"
test -f "$PKG_EXPANDED/Scripts/postinstall"
PKG_PAYLOAD_IMK="$PKG_EXPANDED/Payload/$INPUT_METHOD_BUNDLE_NAME"
test -d "$PKG_PAYLOAD_IMK"
codesign --verify --deep --strict "$PKG_PAYLOAD_IMK"

rm -rf "$APP"
mkdir -p "${APP:h}"
ditto "$STAGED_APP" "$APP"

# CI packaging only needs dist/; set VIBE_VOICE_SKIP_INSTALL=1 to skip /Applications.
if [[ -n "${VIBE_VOICE_SKIP_INSTALL:-}" ]]; then
    xattr -cr "$APP"
    codesign --verify --deep --strict "$APP"
    echo "$APP"
    echo "$INPUT_METHOD_PKG"
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
            # File Provider may reattach FinderInfo/fpfs xattrs between the
            # cleanup and verification calls. Verify an xattr-free copy in a
            # local temp directory so a managed workspace cannot make an
            # otherwise valid signed build fail nondeterministically.
            if [[ "$bundle" == "$APP" ]]; then
                VERIFY_DIR=$(mktemp -d)
                VERIFY_BUNDLE="$VERIFY_DIR/$(basename "$bundle")"
                ditto --norsrc "$bundle" "$VERIFY_BUNDLE"
                xattr -cr "$VERIFY_BUNDLE"
                codesign --verify --deep --strict --verbose=2 "$VERIFY_BUNDLE"
                rm -rf "$VERIFY_DIR"
                echo "Warning: File Provider metadata remains on $bundle; verified an xattr-free copy instead."
            else
                codesign --verify --deep --strict --verbose=2 "$bundle"
            fi
        fi
        sleep 0.2
    done
done
# Day-to-day iteration: once the .pkg has registered the input method under
# /Library/Input Methods, overwrite that copy from this build and restart the
# process. First-time install still needs the .pkg; set
# VIBE_VOICE_SKIP_IMK_REFRESH=1 to leave the live input method untouched.
if [[ -z "${VIBE_VOICE_SKIP_IMK_REFRESH:-}" ]]; then
    zsh "$ROOT/scripts/refresh-input-method.sh" \
        "$APPLICATIONS_APP/Contents/Library/Input Methods/$INPUT_METHOD_BUNDLE_NAME" \
        || true
fi

echo "$APP"
echo "$APPLICATIONS_APP"
echo "$INPUT_METHOD_PKG"
