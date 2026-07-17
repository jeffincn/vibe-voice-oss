# Vibe Voice OSS

Local-first macOS menu-bar voice input. Press a hotkey to record, stop to transcribe through an OpenAI-compatible ASR server (for example [oMLX](https://github.com/ml-explore/mlx) / compatible gateways), optionally run local chat completions for translation or cleanup, then insert text at the caret.

Licensed under the [MIT License](LICENSE).

## Requirements

- macOS 14+
- Apple Silicon
- Xcode 16+
- A local (or otherwise trusted) OpenAI-compatible ASR endpoint

## Quick start

1. Start your ASR server. Default assumption: `http://127.0.0.1:8000`.
2. Load an ASR model the client can name, for example `mlx-community/Qwen3-ASR-0.6B-4bit`.
3. Confirm `GET http://127.0.0.1:8000/v1/models` responds.
4. Build and run:

```bash
chmod +x scripts/build-app.sh
./scripts/build-app.sh
open "dist/Vibe Voice OSS.app"
```

The build installs as **Vibe Voice OSS** (bundle id `app.vibevoice.oss.macos`, version **0.4.0**) into both `dist/` and `/Applications`.
First launch needs Microphone and Accessibility permissions.

The build script prefers an Apple Development identity from your keychain so Accessibility grants survive rebuilds; without one it falls back to ad-hoc signing.

## Settings

Open Settings from the menu bar to configure:

- ASR HTTP endpoint, optional API key, model name, language, hotspot prompt
- Streaming mode and WebSocket URL
- Separate LLM endpoint / key / model for translation, structured cleanup, and prompt compile
- Input device, hotkeys, launch-at-login

API keys are stored in the macOS Keychain. See [docs/configuration.md](docs/configuration.md) and [docs/privacy.md](docs/privacy.md).

**Data flow:** audio and text go only to the URLs you configure. Defaults target localhost. If you enter a remote URL, that host receives the request payloads.

## Workflow

```text
Hotkey → capture microphone → hotkey again → 16 kHz mono WAV
→ POST /v1/audio/transcriptions (or streaming path)
→ optional LLM post-process
→ insert into the focused app
```

Insertion prefers Accessibility APIs; some Electron/Chromium editors fall back to a real paste event. Successful transcripts can always be copied from the menu.

## Development

```bash
swift test
swift build
```

Prefer testing the `.app` from `scripts/build-app.sh` so microphone usage strings are present.

Optional HUD preview:

```bash
cd tools/fluid-voice-oss && pnpm install && pnpm dev
```

More detail: [docs/architecture.md](docs/architecture.md), [CONTRIBUTING.md](CONTRIBUTING.md), [SECURITY.md](SECURITY.md).
