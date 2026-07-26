# iOS 0.7.0 Review Remediation

Tracks the findings from the iOS code review of the `ios/0.7.0` keyboard and
voice subsystem. Each finding has a stable ID so a commit message, a review
comment, and this table can refer to the same thing. Desktop-only findings are
out of scope here and stay with the macOS owner.

Status is `fixed`, `deferred`, or `open`. A `deferred` row says why and what
would close it. The "Closed by" column gives the commit subject, which is also
where the reasoning for each change lives.

## Severe

| ID | Finding | Status | Closed by |
|---|---|---|---|
| S1 | A finished transcript was auto-inserted into whatever text field the keyboard attached to next, not the field that requested dictation | fixed | `fix(ios): only auto-insert dictation into the field that requested it` |
| S2 | `markConsumed` left the transcript readable in the shared container indefinitely; Rime learning data had no protection class and no way to clear it | fixed | `refactor(ios): move the voice bridge to a coordinated app-group file` and `feat(ios): let the user clear shared dictation and learning data` |
| S3 | App Group `UserDefaults` is not a sound cross-process channel: per-process read caching plus unsynchronised read-modify-write | fixed | `refactor(ios): move the voice bridge to a coordinated app-group file` |

## High

| ID | Finding | Status | Closed by |
|---|---|---|---|
| H1 | Keyboard and containing app opened the same Rime user dictionary; LevelDB is single-writer, and failure silently degraded to a ten-word prototype engine | fixed | `fix(ios): rework the rime layer for process isolation and key fidelity` |
| H2 | `stopAndTranscribe` read `audioSamples` while the capture tap was still writing, racing and dropping the tail of the recording | fixed | `feat(ios): recover from audio interruptions and route changes` |
| H3 | `commitBestCandidate` returned a commit cached from an earlier keystroke, and `process_key`'s return value was discarded so unhandled keys vanished | fixed | `fix(ios): rework the rime layer for process isolation and key fidelity` |
| H4 | No `AVAudioSession` interruption or route-change handling, so a call during recording left the UI stuck in `.recording` | fixed | `feat(ios): recover from audio interruptions and route changes` |
| H5 | Project-level `TARGETED_DEVICE_FAMILY = 1` was overridden by XcodeGen's per-target `1,2`, shipping an untested iPad build | fixed | `build(ios): correct device family, extension limits, and declared capabilities` |
| H6 | Keyboard target did not set `APPLICATION_EXTENSION_API_ONLY`, so non-extension-safe API use would only fail at App Store validation | fixed | `build(ios): correct device family, extension limits, and declared capabilities` |
| H7 | No shift, digits, or punctuation; candidates beyond the first page unreachable; the Rime schema has no `punctuator` | fixed | `feat(ios): complete the keyboard with shift, symbols, and paging` |
| H8 | Composition was not reset when the host changed the document or moved the caret, so a stale preedit committed into the wrong place | fixed | `fix(ios): keep the composition tied to the host document and fix layout` |
| H9 | Physical-device acceptance is entirely `Pending` | open | Requires hardware. Run `zsh scripts/test-ios-device.sh` and fill in `docs/ios-device-acceptance.md`. Several fixes on this branch — interruption recovery, the Rime directory split, keyboard memory under the extension budget — can only be proven there. |

## Medium

| ID | Finding | Status | Closed by |
|---|---|---|---|
| M1 | Required-priority `greaterThanOrEqualToConstant` height fought the system input-view constraint; layout ignored the safe area | fixed | `fix(ios): keep the composition tied to the host document and fix layout` |
| M2 | 0.4s keyboard timer plus 0.5s app loop, both running in the background | fixed | `fix(ios): only auto-insert dictation into the field that requested it` |
| M3 | `UIBackgroundModes: audio` declared with no background audio use case; open-access keyboard shipped without an iOS privacy statement | fixed | `build(ios): correct device family, extension limits, and declared capabilities`, `fix(ios): end recording when the app leaves the foreground`, `docs(ios): describe iOS keyboard and dictation privacy` |
| M4 | `DEVELOPMENT_TEAM = ""` written into the project breaks automatic signing in the Xcode UI | fixed | `build(ios): correct device family, extension limits, and declared capabilities` |
| M5 | `startRecording` could be entered twice during the permission phase, creating two capture taps | fixed | `feat(ios): recover from audio interruptions and route changes` |
| M6 | Swift 5 language mode with `targeted` concurrency checking cannot diagnose races like H2 | fixed | `build(ios): correct device family, extension limits, and declared capabilities` |
| M7 | No test covered the keyboard's delivery rule; the ASR test downloaded a real 73 MB model in the default plan | fixed | `test(ios): cover bridge delivery rules and split the model download test` |
| M8 | Vendored `librime_full.a` is committed with no recorded digest, and Boost is taken unpinned from Homebrew | fixed | `build(ios): verify the vendored librime archives against recorded digests` |
| M9 | marisa-trie is dual BSD-2-Clause/LGPL-2.1 and the project never stated which it takes | fixed | `build(ios): verify the vendored librime archives against recorded digests` |
| M10 | No iOS CI at all | fixed | `ci: build and test the iOS targets on pull requests` |

## Low

| ID | Finding | Status | Closed by |
|---|---|---|---|
| L-project | The generated `.xcodeproj` was committed and also rewritten by every build | fixed | `build(ios): stop tracking the generated Xcode project` |
| L-a11y | Letter keys and candidates carried no VoiceOver labels | fixed | `fix(ios): keep the composition tied to the host document and fix layout` |
| L-deploy | `start_maintenance(True)` forced a full dictionary check on every launch | fixed | `fix(ios): rework the rime layer for process isolation and key fidelity` |
| L-rimeapi | `gAPI` was read outside the mutex that guards its assignment | fixed | `fix(ios): rework the rime layer for process isolation and key fidelity` |
| L-l10n | All iOS strings are hardcoded Simplified Chinese with no localisation infrastructure | fixed | `feat(ios): localise the interface instead of hard-coding Chinese` |
| L-dictsize | The 1.3 MB raw dictionary source is bundled into the extension, which never compiles it | deferred | Deliberately not attempted. The payoff is 1.3 MB of download size and no runtime memory, because a file the extension never opens is never resident. The cost is splitting `RimeData` into two directories, since an XcodeGen folder reference cannot exclude one file, and then betting that no librime code path consults the source dictionary when deciding whether the prebuilt data in `staging_dir` is current. If that bet is wrong the keyboard degrades to the ten-word prototype engine, which is a far worse outcome than 1.3 MB. Revisit once H9 gives a device to measure and confirm on. |
| L-jq | `scripts/test-ios-device.sh` used `jq` without the dependency check its sibling script has | fixed | `build(ios): verify the vendored librime archives against recorded digests` |

## Verification status

**Nothing on this branch has been compiled.** It was prepared in a Linux
container with no Xcode and no iOS SDK. What was verified:

- Every file in `iOS/Shared` except `VoiceBridgeSignal.swift` typechecks under a
  Linux Swift 6.0.3 toolchain in Swift 5 language mode, with `NSFileCoordinator`,
  `FileManager.containerURL`, the Darwin notification calls, and the Objective-C
  bridge replaced by shims that mirror the real signatures.
- The `KeyboardLayout` and `MobileL10n` invariants were run as a real program,
  not just typechecked: every plane has three rows ending in backspace, every
  character key holds exactly one character, the letters plane covers the
  alphabet with no duplicates, and all 86 catalog keys resolve in both
  languages with the positional format specifiers substituting in order.
- `iOS/project.yml` was generated with xcodegen 2.44.1 built from source for
  Linux. The two `InfoPlist.strings` files become one `PBXVariantGroup` in both
  the app and the extension, `knownRegions` picks up `en` and `zh-Hans`, and no
  `.plist` or `.entitlements` file leaks into a resources phase.
- `iOS/RimeData/vibe_pinyin.schema.yaml` parses, and the inline `punctuator`
  map round-trips through a YAML loader — worth checking by machine, because a
  malformed schema fails at deployment rather than at build time.
- `iOS/Vendor/librime.xcframework.sha256` matches the committed archives.
- `.github/workflows/ios.yml` parses.

What still has to happen before merge:

1. `zsh scripts/build-ios.sh` — simulator matrix plus the generic device build.
   Expect new warnings: `SWIFT_STRICT_CONCURRENCY` moved to `complete`, and
   surfacing those was the point of M6. The UIKit in
   `KeyboardViewController.swift` has never been through a compiler, so this is
   the first real check of the H7 layout code.
2. `VIBEVOICE_RUN_INTEGRATION_TESTS=1 zsh scripts/build-ios.sh` at least once,
   since the WhisperKit test no longer runs by default.
3. `zsh scripts/test-ios-device.sh` and `docs/ios-device-acceptance.md`, which
   closes H9. Beyond the existing checklist, H7 adds things only a device shows:
   that Chinese punctuation comes out full-width, that the candidate arrows
   page, and that shift and the symbol planes lay out correctly on the smallest
   supported screen.
