# Vibe Voice OSS

Local-first macOS menu-bar voice input. Press a hotkey to record, stop to transcribe through an OpenAI-compatible ASR server (for example [oMLX](https://github.com/ml-explore/mlx) / compatible gateways), optionally run local chat completions for translation or cleanup, then insert text at the caret.

Licensed under the [MIT License](LICENSE).

## Requirements

- macOS 15+
- Apple Silicon
- Xcode 16+
- Optional: a local (or otherwise trusted) OpenAI-compatible ASR / LLM endpoint

## Quick start

1. Build and run:

```bash
chmod +x scripts/build-app.sh
./scripts/build-app.sh
open "dist/Vibe Voice OSS.app"
```

By default the app uses **Integrated ASR** with WhisperKit. Use **Prepare Model** in Settings to download or repair the selected local ASR model. Qwen3-ASR is available through `mlx-swift-asr` and defaults to the Hugging Face repo `mlx-community/Qwen3-ASR-0.6B-6bit`; you can also point it at an existing local MLX model directory. You can switch the ASR mode to an OpenAI-compatible API endpoint in Settings.

The build installs as **Vibe Voice OSS** (bundle id `app.vibevoice.oss.macos`, version **0.5.0**) into both `dist/` and `/Applications`.
First launch needs Microphone and Accessibility permissions.

See the [0.5.0 Change Note](docs/change-note-0.5.0.md) for upgrade guidance and a complete summary of changes since 0.4.

The build script prefers an Apple Development identity from your keychain so Accessibility grants survive rebuilds; without one it falls back to ad-hoc signing.

## Settings

Open Settings from the menu bar to configure:

- ASR mode: integrated local MLX or OpenAI-compatible API
- Integrated ASR engine: Qwen3-ASR / mlx-swift-asr or Whisper / WhisperKit
- Prepare Model downloads or repairs local WhisperKit / Qwen3-ASR model files before first use
- API ASR HTTP endpoint, optional API key, model name, language, hotspot prompt
- API streaming mode and WebSocket URL
- LLM API mode, endpoint / key / model for translation, structured cleanup, and prompt compile
- Input device, hotkeys, launch-at-login

API keys are stored in the macOS Keychain. See [docs/configuration.md](docs/configuration.md) and [docs/privacy.md](docs/privacy.md).

**Data flow:** integrated ASR runs locally without Python. API modes send audio and/or text only to the URLs you configure. If you enter a remote URL, that host receives the request payloads.

## Workflow

```text
Hotkey → capture microphone → hotkey again → 16 kHz mono WAV
→ integrated MLX ASR or POST /v1/audio/transcriptions
→ optional LLM API post-process
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
