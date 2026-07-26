# iOS vendored binaries

`librime.xcframework` is a core-only static build of librime 1.16.1 produced by
`scripts/prepare-librime-ios.sh`. It is committed rather than rebuilt on every
clone, because the build needs CMake, a full Xcode toolchain, and roughly ten
minutes per slice.

## Verifying

`scripts/verify-librime-ios.sh` checks both archives against
`librime.xcframework.sha256`, and both `scripts/build-ios.sh` and
`scripts/test-ios-device.sh` run it before building. To check by hand:

```zsh
zsh scripts/verify-librime-ios.sh
```

`librime-build-provenance.txt` records the source versions and digests the
archives were built from.

## Rebuilding

```zsh
zsh scripts/prepare-librime-ios.sh
```

The script downloads librime, yaml-cpp, leveldb, and OpenCC over HTTPS and
verifies each archive against a pinned SHA-256 before extracting it. It then
rewrites `librime.xcframework.sha256` and `librime-build-provenance.txt`, so a
rebuild that changes the output shows up as a diff on those files.

Boost is the one input that is not pinned. librime needs its headers only, and
the script takes them from the build machine's Homebrew prefix after checking
for 1.77 or newer. A different Boost therefore produces a different archive,
which is why the version used is recorded in the provenance file rather than
assumed.

## Licenses

`Licenses/` holds the license text for librime and every statically linked
dependency, copied from the source trees the archives were built from.

marisa-trie is offered under either BSD-2-Clause or LGPL-2.1. **Vibe Voice OSS
takes it under BSD-2-Clause**, which is what makes static linking into a
closed-distribution binary unencumbered. `Licenses/marisa-trie-license.txt`
contains both texts as shipped upstream; the BSD-2-Clause half is the one that
applies here.
