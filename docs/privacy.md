# Privacy

## What leaves the device

Vibe Voice sends audio and text only to the HTTP/WebSocket endpoints configured in Settings. The default endpoints are on `127.0.0.1`. If you point Settings at a remote service, that service receives the payloads you send (audio for ASR; text for translation / structure / prompt compile).

The app does not ship a mandatory cloud backend and does not upload recordings to a fixed third-party URL hard-coded in the source.

## What stays local

- Audio for the API and streaming paths stays in memory for the active session and is never written to disk.
- The on-device ASR path is the exception: it writes the recording to `~/Library/Application Support/VibeVoiceOSS/NativeASR/jobs/<uuid>/recording.wav` and deletes it once transcription finishes. A crash or force-quit mid-transcription leaves the file behind; the directory is swept on the next launch.
- API keys are stored in the macOS Keychain (service `app.vibevoice.oss.macos`) when the app carries a certificate-backed code signature — the default for Homebrew and release builds, and for builds signed with an Apple Development identity.
- Ad-hoc-signed developer builds cannot use the Keychain, because an ad-hoc signature changes on every rebuild and would trigger a password prompt each launch. They store keys in clear text at `~/Library/Application Support/VibeVoiceOSS/credentials.json` (mode 0600, in a mode 0700 directory, excluded from backups), and Settings says so. Values migrate into the Keychain on the first launch of a signed build, and the clear-text copy is deleted.
- Non-secret preferences (endpoints, model names, hotkeys, feature toggles) use UserDefaults. Earlier versions also kept API keys there; those entries are removed on upgrade.

## What is refused

- Sending an API key to a remote `http://` or `ws://` endpoint. Loopback stays allowed so local model servers work over plain HTTP.
- Settings flags any endpoint that would carry audio or transcripts unencrypted, whether or not a key is set.
- HTTP error text shown in the UI has credentials masked and is truncated, so error toasts and bug reports cannot leak a key.

## Permissions

- Microphone: capture audio for transcription.
- Accessibility: insert text into the focused field (with clipboard paste as a fallback for some editors).

Review macOS System Settings if you rebuild with a different bundle identifier; permissions are tied to the app identity.
