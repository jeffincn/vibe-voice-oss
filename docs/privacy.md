# Privacy

This page covers the macOS app first. The iOS app and its keyboard extension
behave differently and are described in [iOS](#ios) below.

## What leaves the device

Vibe Voice sends audio and text only to the HTTP/WebSocket endpoints configured in Settings. The default endpoints are on `127.0.0.1`. If you point Settings at a remote service, that service receives the payloads you send (audio for ASR; text for translation / structure / prompt compile).

The app does not ship a mandatory cloud backend and does not upload recordings to a fixed third-party URL hard-coded in the source.

## What stays local

- Temporary audio buffers are kept in memory for the active session; the client does not write temporary recordings to disk for the normal path.
- API keys are stored in the macOS Keychain (service `app.vibevoice.oss.macos`) when the app carries a certificate-backed code signature (the default for Homebrew / release builds and builds signed with an Apple Development identity). Ad-hoc-signed developer builds fall back to UserDefaults, because ad-hoc signatures change on every rebuild and would trigger a Keychain password prompt each time. Existing plaintext values migrate into the Keychain automatically on first launch of a signed build.
- Non-secret preferences (endpoints, model names, hotkeys, feature toggles) use UserDefaults.

## Permissions

- Microphone: capture audio for transcription.
- Accessibility: insert text into the focused field (with clipboard paste as a fallback for some editors).

Review macOS System Settings if you rebuild with a different bundle identifier; permissions are tied to the app identity.

## iOS

The iOS app shares no code path with the macOS networking stack. Nothing above
about endpoints, API keys, or the Keychain applies to it.

### What leaves the device

Nothing. Transcription runs on-device through WhisperKit, and translation is
WhisperKit's own speech-to-English capability rather than a text API. There is
no endpoint setting, no API key, and no analytics.

WhisperKit model weights are downloaded from Hugging Face the first time you
prepare a model. That request carries no audio and no text.

### Open access

The keyboard requests open access (`RequestsOpenAccess`), which iOS warns about
in strong terms because it lets a keyboard send what you type over the network.
Vibe Voice needs it for one reason: without open access an extension cannot read
the App Group container, and the App Group is how a transcript recorded in the
main app reaches the keyboard. The keyboard performs no networking of its own.

### What is stored, and where

Everything lives in the `group.app.vibevoice.oss.shared` container:

| Data | Location | Lifetime |
|---|---|---|
| Dictation transcript awaiting insertion | `VoiceBridge/voice-bridge.v2.json`, complete file protection | Deleted the moment it is inserted, and ignored after five minutes |
| Compiled Rime schema | `Rime/Deploy` | Until you reinstall or redeploy |
| Pinyin learning from the keyboard | `Rime/KeyboardUser`, protected until first unlock | Until you clear it |

Audio samples stay in memory for the duration of a recording and are never
written to disk.

**Clearing.** The main app's privacy card removes the pending transcript and
every learned dictionary in one action. Deleting the app removes the whole
container.

### Delivery of dictation results

A transcript is tagged with the text field that requested it and is inserted
automatically only back into that field. If you move somewhere else before it
finishes, the keyboard says a result is waiting and inserts it only when you tap
the microphone key. Speech never lands in a field that did not ask for it.

### Permissions

- Microphone, requested by the main app: recording for transcription. The
  keyboard extension never has microphone access; iOS does not grant it to
  third-party keyboards, which is why dictation happens in the app.
- Open access for the keyboard: shared container access, as described above.
