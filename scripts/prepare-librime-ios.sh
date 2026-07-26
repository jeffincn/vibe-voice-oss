#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
CACHE_ROOT="${VIBEVOICE_LIBRIME_BUILD_ROOT:-${TMPDIR%/}/vibevoice-librime-ios-core}"
DOWNLOADS="$CACHE_ROOT/downloads"
SOURCES="$CACHE_ROOT/sources"
BUILD="$CACHE_ROOT/build"
PREFIX="$CACHE_ROOT/prefix"
OUTPUT="$ROOT/iOS/Vendor/librime.xcframework"
LICENSE_OUTPUT="$ROOT/iOS/Vendor/Licenses"
DEPLOYMENT_TARGET="17.0"

typeset -A URLS HASHES
URLS[librime]="https://codeload.github.com/rime/librime/tar.gz/refs/tags/1.16.1"
HASHES[librime]="944909b5d9fb81171b044b7f2ea89922bd73457fcc5105798a259173288cd2d9"
URLS[yaml-cpp]="https://codeload.github.com/jbeder/yaml-cpp/tar.gz/refs/tags/0.8.0"
HASHES[yaml-cpp]="fbe74bbdcee21d656715688706da3c8becfd946d92cd44705cc6098bb23b3a16"
URLS[leveldb]="https://codeload.github.com/google/leveldb/tar.gz/refs/tags/1.23"
HASHES[leveldb]="9a37f8a6174f09bd622bc723b55881dc541cd50747cbd08831c2a82d620f6d76"
URLS[opencc]="https://codeload.github.com/BYVoid/OpenCC/tar.gz/refs/tags/ver.1.1.9"
HASHES[opencc]="ad4bcd8d87219a240a236d4a55c9decd2132a9436697d2882ead85c8939b0a99"

for command_name in cmake curl shasum xcodebuild xcrun libtool rg; do
    command -v "$command_name" >/dev/null || {
        print "error: missing required command: $command_name" >&2
        exit 1
    }
done

BOOST_PREFIX="${BOOST_PREFIX:-$(brew --prefix boost 2>/dev/null || true)}"
if [[ -z "$BOOST_PREFIX" || ! -f "$BOOST_PREFIX/include/boost/version.hpp" ]]; then
    print "error: Boost headers 1.77+ are required (brew install boost)." >&2
    exit 1
fi

boost_version=$(sed -n 's/^#define BOOST_VERSION //p' "$BOOST_PREFIX/include/boost/version.hpp")
if [[ -z "$boost_version" || "$boost_version" -lt 107700 ]]; then
    print "error: Boost 1.77 or newer is required." >&2
    exit 1
fi

mkdir -p "$DOWNLOADS" "$SOURCES" "$BUILD" "$PREFIX" "$ROOT/iOS/Vendor"

fetch_source() {
    local name="$1"
    local archive="$DOWNLOADS/$name.tgz"
    if [[ -f "$archive" ]] && \
       [[ "$(shasum -a 256 "$archive" | awk '{print $1}')" != "$HASHES[$name]" ]]; then
        mv "$archive" "$archive.invalid"
    fi
    if [[ ! -f "$archive" ]]; then
        print "Downloading $name…"
        curl --fail --location --retry 5 --retry-all-errors \
            "$URLS[$name]" -o "$archive"
    fi
    local actual_hash
    actual_hash=$(shasum -a 256 "$archive" | awk '{print $1}')
    if [[ "$actual_hash" != "$HASHES[$name]" ]]; then
        print "error: checksum mismatch for $name" >&2
        exit 1
    fi
    if [[ ! -f "$SOURCES/$name/.vibevoice-extracted" ]]; then
        mkdir -p "$SOURCES/$name"
        tar xzf "$archive" -C "$SOURCES/$name" --strip-components=1
        touch "$SOURCES/$name/.vibevoice-extracted"
    fi
}

for source_name in librime yaml-cpp leveldb opencc; do
    fetch_source "$source_name"
done

# OpenCC's command-line tools and data compiler cannot be configured as iOS
# executables. The keyboard only needs the static conversion library.
if ! rg -q "VIBEVOICE_IOS_CORE_ONLY" "$SOURCES/opencc/CMakeLists.txt"; then
    sed -i.bak \
        -e 's/^add_subdirectory(doc)$/# VIBEVOICE_IOS_CORE_ONLY/' \
        -e 's/^add_subdirectory(data)$/# VIBEVOICE_IOS_CORE_ONLY/' \
        -e 's/^add_subdirectory(test)$/# VIBEVOICE_IOS_CORE_ONLY/' \
        "$SOURCES/opencc/CMakeLists.txt"
    sed -i.bak \
        's/^add_subdirectory(tools)$/# VIBEVOICE_IOS_CORE_ONLY/' \
        "$SOURCES/opencc/src/CMakeLists.txt"
fi

build_slice() {
    local slice="$1"
    local sdk="$2"
    local slice_build="$BUILD/$slice"
    local slice_prefix="$PREFIX/$slice"
    local common=(
        -G "Unix Makefiles"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_SYSTEM_NAME=iOS
        -DCMAKE_OSX_SYSROOT="$sdk"
        -DCMAKE_OSX_ARCHITECTURES=arm64
        -DCMAKE_OSX_DEPLOYMENT_TARGET="$DEPLOYMENT_TARGET"
        -DCMAKE_INSTALL_PREFIX="$slice_prefix"
    )

    mkdir -p "$slice_build" "$slice_prefix/lib" "$slice_prefix/include"
    print "Building core librime dependencies for $slice…"

    if [[ ! -f "$slice_prefix/lib/libyaml-cpp.a" ]]; then
        cmake -S "$SOURCES/yaml-cpp" -B "$slice_build/yaml-cpp" "${common[@]}" \
            -DYAML_BUILD_SHARED_LIBS=OFF \
            -DYAML_CPP_BUILD_TESTS=OFF \
            -DYAML_CPP_BUILD_TOOLS=OFF \
            -DYAML_CPP_BUILD_CONTRIB=OFF
        cmake --build "$slice_build/yaml-cpp" --target install -j 8
    fi

    if [[ ! -f "$slice_prefix/lib/libleveldb.a" ]]; then
        cmake -S "$SOURCES/leveldb" -B "$slice_build/leveldb" "${common[@]}" \
            -DBUILD_SHARED_LIBS=OFF \
            -DLEVELDB_BUILD_TESTS=OFF \
            -DLEVELDB_BUILD_BENCHMARKS=OFF \
            -DLEVELDB_INSTALL=ON
        cmake --build "$slice_build/leveldb" --target install -j 8
    fi

    if [[ ! -f "$slice_prefix/lib/libopencc.a" ]]; then
        cmake -S "$SOURCES/opencc" -B "$slice_build/opencc" "${common[@]}" \
            -DBUILD_SHARED_LIBS=OFF \
            -DENABLE_GTEST=OFF \
            -DENABLE_BENCHMARK=OFF \
            -DBUILD_DOCUMENTATION=OFF \
            -DBUILD_PYTHON=OFF
        cmake --build "$slice_build/opencc" --target libopencc marisa -j 8
        cp "$slice_build/opencc/src/libopencc.a" "$slice_prefix/lib/"
        cp "$slice_build/opencc/deps/marisa-0.2.6/libmarisa.a" "$slice_prefix/lib/"
        mkdir -p "$slice_prefix/include/opencc"
        cp "$SOURCES/opencc/src/"*.hpp "$SOURCES/opencc/src/opencc.h" \
            "$slice_prefix/include/opencc/"
        cp "$slice_build/opencc/src/opencc_config.h" \
            "$slice_build/opencc/src/Opencc_Export.h" \
            "$slice_prefix/include/opencc/"
        cp "$SOURCES/opencc/deps/marisa-0.2.6/include/marisa.h" \
            "$slice_prefix/include/"
        cp -R "$SOURCES/opencc/deps/marisa-0.2.6/include/marisa" \
            "$slice_prefix/include/"
    fi

    if [[ ! -f "$slice_build/librime/lib/librime.a" ]]; then
        cmake -S "$SOURCES/librime" -B "$slice_build/librime" "${common[@]}" \
            -DBoost_INCLUDE_DIR="$BOOST_PREFIX/include" \
            -DYamlCpp_INCLUDE_PATH="$slice_prefix/include" \
            -DYamlCpp_NEW_API="$slice_prefix/include/yaml-cpp/node/node.h" \
            -DYamlCpp_LIBRARY="$slice_prefix/lib/libyaml-cpp.a" \
            -DLevelDb_INCLUDE_PATH="$slice_prefix/include" \
            -DLevelDb_LIBRARY="$slice_prefix/lib/libleveldb.a" \
            -DMarisa_INCLUDE_PATH="$slice_prefix/include" \
            -DMarisa_LIBRARY="$slice_prefix/lib/libmarisa.a" \
            -DOpencc_INCLUDE_PATH="$slice_prefix/include" \
            -DOpencc_LIBRARY="$slice_prefix/lib/libopencc.a" \
            -DBUILD_SHARED_LIBS=OFF \
            -DBUILD_STATIC=ON \
            -DBUILD_MERGED_PLUGINS=OFF \
            -DBUILD_DATA=OFF \
            -DBUILD_TEST=OFF \
            -DBUILD_SAMPLE=OFF \
            -DENABLE_LOGGING=OFF \
            -DENABLE_EXTERNAL_PLUGINS=OFF \
            -DENABLE_TIMESTAMP=OFF
        cmake --build "$slice_build/librime" --target rime-static -j 8
    fi

    libtool -static -o "$slice_prefix/lib/librime_full.a" \
        "$slice_build/librime/lib/librime.a" \
        "$slice_prefix/lib/libyaml-cpp.a" \
        "$slice_prefix/lib/libleveldb.a" \
        "$slice_prefix/lib/libmarisa.a" \
        "$slice_prefix/lib/libopencc.a"
}

build_slice device iphoneos
build_slice simulator iphonesimulator

HEADERS="$CACHE_ROOT/headers"
mkdir -p "$HEADERS"
cp "$SOURCES/librime/src/rime_api.h" \
   "$SOURCES/librime/src/rime_api_deprecated.h" \
   "$SOURCES/librime/src/rime_api_stdbool.h" \
   "$SOURCES/librime/src/rime_levers_api.h" \
   "$HEADERS/"

STAGED="$CACHE_ROOT/librime.xcframework"
if [[ -d "$STAGED" ]]; then
    mv "$STAGED" "$CACHE_ROOT/previous-staged-$(date +%s)"
fi
xcodebuild -create-xcframework \
    -library "$PREFIX/device/lib/librime_full.a" -headers "$HEADERS" \
    -library "$PREFIX/simulator/lib/librime_full.a" -headers "$HEADERS" \
    -output "$STAGED"

if nm -gU "$PREFIX/device/lib/librime_full.a" | \
   rg -qi 'octagram|rime_lua|luaopen_|predict_module|legacy_module'; then
    print "error: an external librime plugin symbol entered the core archive" >&2
    exit 1
fi

if [[ -d "$OUTPUT" ]]; then
    mv "$OUTPUT" "$CACHE_ROOT/previous-output-$(date +%s)"
fi
mv "$STAGED" "$OUTPUT"

mkdir -p "$LICENSE_OUTPUT"
cp "$SOURCES/librime/LICENSE" "$LICENSE_OUTPUT/librime-BSD-3-Clause.txt"
cp "$SOURCES/yaml-cpp/LICENSE" "$LICENSE_OUTPUT/yaml-cpp-MIT.txt"
cp "$SOURCES/leveldb/LICENSE" "$LICENSE_OUTPUT/leveldb-BSD-3-Clause.txt"
cp "$SOURCES/opencc/LICENSE" "$LICENSE_OUTPUT/OpenCC-Apache-2.0.txt"
cp "$SOURCES/opencc/deps/marisa-0.2.6/COPYING.md" \
   "$LICENSE_OUTPUT/marisa-trie-license.txt"
BOOST_LICENSE="$DOWNLOADS/Boost-LICENSE_1_0.txt"
if [[ ! -f "$BOOST_LICENSE" ]]; then
    curl --fail --location --retry 5 --retry-all-errors \
        "https://raw.githubusercontent.com/boostorg/boost/boost-1.89.0/LICENSE_1_0.txt" \
        -o "$BOOST_LICENSE"
fi
if [[ "$(shasum -a 256 "$BOOST_LICENSE" | awk '{print $1}')" != \
      "c9bff75738922193e67fa726fa225535870d2aa1059f91452c411736284ad566" ]]; then
    print "error: checksum mismatch for Boost license" >&2
    exit 1
fi
cp "$BOOST_LICENSE" "$LICENSE_OUTPUT/Boost-1.0.txt"

# The XCFramework is committed rather than rebuilt on every clone, so record
# what it is and what produced it. scripts/verify-librime-ios.sh checks the
# digests before any iOS build.
(
    cd "$ROOT/iOS/Vendor"
    shasum -a 256 \
        librime.xcframework/ios-arm64/librime_full.a \
        librime.xcframework/ios-arm64-simulator/librime_full.a \
        > librime.xcframework.sha256
)

cat > "$ROOT/iOS/Vendor/librime-build-provenance.txt" <<PROVENANCE
Produced by scripts/prepare-librime-ios.sh
librime      1.16.1  ${HASHES[librime]}
yaml-cpp     0.8.0   ${HASHES[yaml-cpp]}
leveldb      1.23    ${HASHES[leveldb]}
OpenCC       1.1.9   ${HASHES[opencc]}
marisa-trie  0.2.6   bundled in the OpenCC source tree
Boost        ${boost_version} (headers only, from ${BOOST_PREFIX})

Boost is the one input that is not pinned to a digest: it comes from the
build machine's Homebrew prefix, so a different Boost produces a different
archive. The version above is what the committed digests correspond to.
PROVENANCE

print "Created core-only librime 1.16.1 XCFramework at $OUTPUT"
print "Recorded digests in iOS/Vendor/librime.xcframework.sha256"
