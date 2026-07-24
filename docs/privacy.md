# Privacy

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
