# Vendored dependencies

`mlx-swift-asr` is vendored from https://github.com/ontypehq/mlx-swift-asr
at revision `f8ea5e6e76824eae903580fcfab0ef15e207b479`, with `Package.swift`
patched to pin:

- `mlx-swift` exact `0.31.4` (0.31.5+ requires Swift tools 6.3)
- `mlx-swift-lm` revision `d2424294a6c3bbd0de37a0761d80efc05e6813dd` (pre-`maskFill`, matches 0.31.4)

Upstream currently tracks `mlx-swift` / `mlx-swift-lm` on `main`, which breaks
builds on Xcode 26.1 / Swift 6.2.1. When you upgrade to a Swift 6.3+ toolchain,
you can switch `Package.swift` back to the remote dependency and delete this
vendor tree.
