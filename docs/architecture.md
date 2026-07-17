# Architecture

Vibe Voice OSS is a macOS menu-bar dictation client. It records from a chosen microphone, sends audio to a user-configured OpenAI-compatible ASR endpoint, optionally runs chat/completions for translation / structure / prompt compile, then inserts text into the previously focused app.

```text
Hotkey / menu
  → AudioRecorder (PCM)
  → WAVEncoder / streaming session
  → TranscriptionClient or StreamingASRClient
  → optional TranslationClient / SemanticFormatter / PromptCompiler
  → PasteService (Accessibility or Cmd+V)
```

## Configuration flow

Settings live in `AppSettings`. Non-secret preferences use `UserDefaults`. API keys use `KeychainStore` (`app.vibevoice.oss.macos`).

Clients receive configuration structs:

- `TranscriptionConfiguration` → ASR HTTP / SSE
- WebSocket streaming uses the same ASR API key
- `TranslationConfiguration` / `SemanticFormatterConfiguration` → chat completions

## Bundled UI preview

`tools/fluid-voice-oss` is a Vite/React preview of the particle HUD. It is not required to build or run the macOS app.
