# Vibe Voice iOS 0.7.0 Development Plan

## Product boundary

The iOS product is a complete Chinese/English keyboard plus voice input:

- Standard QWERTY English input.
- Simplified Chinese full Pinyin through Rime.
- Original, polished, and translated voice output.
- Local-first ASR in the containing app.

The keyboard extension never opens the microphone and never loads ASR models. It owns only keyboard UI, the Rime session, candidate selection, and text insertion. The containing app owns audio capture, VAD, model management, ASR, translation, and structured cleanup.

## Targets

| Target | Responsibility |
|---|---|
| `VibeVoiceMobile` | Onboarding, permissions, model management, audio and ASR |
| `VibeVoiceKeyboard` | Chinese/English keyboard, Rime session, result insertion |
| `VibeVoiceMobileTests` | Rime boundary and App Group bridge tests |

## Rime integration

`RimeEngine` is the stable Swift boundary. Phase one uses a deterministic prototype engine to validate keyboard lifecycle and automated tests. Production replaces it with a pinned, BSD-3-Clause `librime.xcframework`.

Rime deployment and schema compilation happen in the containing app. The extension loads precompiled schemas and writes only user learning data. Squirrel is a GPL-3.0 architectural reference only; its source is not copied into this MIT repository. Plum is not executed inside iOS; schema packages use a native manifest, pinned versions, archive validation, and per-package license inventory.

## Test matrix

| Environment | Gate |
|---|---|
| iPhone 14 Pro Max / iOS 17 Simulator | Required before claiming iOS 17 compatibility; temporarily skipped when runtime is absent |
| iPhone 14 Pro Max / iOS 18 Simulator | Required on every iOS change |
| iPhone 14 Pro Max / iOS 26 Simulator | Required on every iOS change |
| iPhone 14 Pro Max / iOS 26 physical device | Required for microphone, model, background, thermal and memory acceptance |

Simulator ASR tests use deterministic audio fixtures. Real microphone, Metal/Core ML performance, background audio survival, interruptions, thermal behavior, and jetsam acceptance are physical-device-only evidence.

## Delivery gates

1. Generate the Xcode project from `iOS/project.yml`.
2. Pass all installed simulator runtimes with `zsh scripts/build-ios.sh`.
3. Keep missing runtimes visibly marked `SKIPPED`.
4. Increment the macOS `CFBundleVersion`.
5. Build, sign, verify, and deploy the macOS app with `zsh scripts/build-app.sh`.
6. Before a device milestone, install to the user's iPhone 14 Pro Max and retain `.xcresult`, performance, memory, power, and thermal evidence.
