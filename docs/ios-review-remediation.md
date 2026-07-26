# iOS 0.7.0 Review Remediation

Tracks the findings from the iOS code review of the `ios/0.7.0` keyboard and
voice subsystem. Each finding has a stable ID so a commit message, a review
comment, and this table can refer to the same thing. Desktop-only findings are
out of scope here and stay with the macOS owner.

Status values are `open`, `fixed`, or `deferred`. A `deferred` row carries the
reason and what would close it.

## Severe

| ID | Finding | Status | Closed by |
|---|---|---|---|
| S1 | A finished transcript was auto-inserted into whatever text field the keyboard attached to next, not the field that requested dictation | fixed | `fix(ios): only auto-insert dictation into the field that requested it` |
| S2 | `markConsumed` left the transcript readable in the shared container indefinitely; Rime learning data had no protection class and no way to clear it | fixed | `refactor(ios): move the voice bridge to a coordinated app-group file`, `feat(ios): let the user clear shared dictation and learning data` |
| S3 | App Group `UserDefaults` is not a sound cross-process channel: per-process read caching plus unsynchronised read-modify-write | fixed | `refactor(ios): move the voice bridge to a coordinated app-group file` |

## High

| ID | Finding | Status | Closed by |
|---|---|---|---|
| H1 | Keyboard and containing app opened the same Rime user dictionary; LevelDB is single-writer, and failure silently degraded to a ten-word prototype engine | fixed | `fix(ios): give the keyboard its own rime user dictionary` |
| H2 | `stopAndTranscribe` read `audioSamples` while the capture tap was still writing, racing and dropping the tail of the recording | fixed | `fix(ios): stop the recorder before reading captured samples` |
| H3 | `commitBestCandidate` returned a commit cached from an earlier keystroke, and `process_key`'s return value was discarded so unhandled keys vanished | fixed | `fix(ios): insert rime auto-commits immediately and pass through unhandled keys` |
| H4 | No `AVAudioSession` interruption or route-change handling, so a call during recording left the UI stuck in `.recording` | fixed | `feat(ios): recover from audio interruptions and route changes` |
| H5 | Project-level `TARGETED_DEVICE_FAMILY = 1` was overridden by XcodeGen's per-target `1,2`, shipping an untested iPad build | fixed | `build(ios): keep the iPhone-only device family and extension API limits` |
| H6 | Keyboard target did not set `APPLICATION_EXTENSION_API_ONLY`, so non-extension-safe API use would only fail at App Store validation | fixed | `build(ios): keep the iPhone-only device family and extension API limits` |
| H7 | No shift, digits, or punctuation; candidates beyond the first page unreachable; schema has no `punctuator` | deferred | Feature work, not a defect fix. Tracked separately; the首页 copy no longer claims a complete keyboard. |
| H8 | Composition was not reset when the host changed the document or moved the caret, so a stale preedit committed into the wrong place | fixed | `fix(ios): reset composition when the host document changes` |
| H9 | Physical-device acceptance is entirely `Pending` | open | Requires hardware; see `docs/ios-device-acceptance.md` |

## Medium

| ID | Finding | Status | Closed by |
|---|---|---|---|
| M1 | Required-priority `greaterThanOrEqualToConstant` height fought the system input-view constraint; layout ignored the safe area | fixed | `fix(ios): resolve keyboard height and safe-area layout conflicts` |
| M2 | 0.4s keyboard timer plus 0.5s app loop, both running in the background | fixed | `fix(ios): only auto-insert dictation into the field that requested it` |
| M3 | `UIBackgroundModes: audio` declared with no background audio use case; open-access keyboard shipped without an iOS privacy statement | fixed | `fix(ios): drop the unused background audio mode`, `docs(ios): describe iOS keyboard and dictation privacy` |
| M4 | `DEVELOPMENT_TEAM = ""` written into the project breaks automatic signing in the Xcode UI | fixed | `build(ios): keep the iPhone-only device family and extension API limits` |
| M5 | `startRecording` could be entered twice during the permission phase, creating two capture taps | fixed | `feat(ios): recover from audio interruptions and route changes` |
| M6 | Swift 5 language mode with `targeted` concurrency checking cannot diagnose races like H2 | fixed | `build(ios): raise concurrency checking to complete` |
| M7 | No keyboard-extension tests; the ASR test downloads a real 73 MB model in the default plan | fixed | `test(ios): cover bridge delivery rules and split the model download test` |
| M8 | Vendored `librime_full.a` is committed with no recorded digest, and Boost is taken unpinned from Homebrew | fixed | `build(ios): verify the vendored librime archives against recorded digests` |
| M9 | marisa-trie is dual BSD-2-Clause/LGPL-2.1 and the project never stated which it takes | fixed | `docs(ios): state the marisa-trie license choice` |
| M10 | No iOS CI at all | fixed | `ci: build and test the iOS targets on pull requests` |

## Low

| ID | Finding | Status | Closed by |
|---|---|---|---|
| L-project | The generated `.xcodeproj` was committed and also rewritten by every build | fixed | `build(ios): stop tracking the generated Xcode project` |
| L-l10n | All iOS strings are hardcoded Simplified Chinese with no localisation infrastructure | deferred | Needs the same `L10n` treatment the macOS target has; not a 0.7.0 blocker |
| L-a11y | Letter keys and candidates carry no VoiceOver labels | fixed | `fix(ios): label keyboard controls for VoiceOver` |
| L-deploy | `start_maintenance(True)` forces a full check on every launch | fixed | `fix(ios): give the keyboard its own rime user dictionary` |
| L-rimeapi | `gAPI` is read outside the mutex that guards its assignment | fixed | `fix(ios): insert rime auto-commits immediately and pass through unhandled keys` |
| L-dictsize | The 1.2 MB raw dictionary source is bundled into the extension, which never compiles it | deferred | Removing it changes what librime sees as deployable; needs the device gate first |
| L-jq | `scripts/test-ios-device.sh` uses `jq` without the dependency check its sibling script has | fixed | `build(ios): check device test script dependencies up front` |

## Verification status

No commit on this branch has been compiled. The work was prepared in a Linux
container without Xcode or an iOS SDK. Foundation-only sources were typechecked
with a Linux Swift 6.0.3 toolchain, with Darwin-only APIs shimmed. Before merge:

1. `zsh scripts/build-ios.sh` — simulator matrix plus the generic device build.
2. `zsh scripts/test-ios-device.sh` — physical iPhone gate.
3. Fill in `docs/ios-device-acceptance.md`, which closes H9.
