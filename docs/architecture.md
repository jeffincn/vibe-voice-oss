# Architecture

Vibe Voice OSS is a macOS menu-bar dictation client. It records from a chosen microphone, transcribes audio with either integrated native ASR backends or a user-configured OpenAI-compatible ASR endpoint, optionally runs chat/completions for translation / structure / prompt compile, then inserts text into the previously focused app.

```text
Hotkey / menu
  → AudioRecorder (PCM)
  → WAVEncoder / streaming session
  → NativeASRClient or TranscriptionClient / StreamingASRClient
  → optional API-only TranslationClient / SemanticFormatter / PromptCompiler
  → PasteService (Accessibility or Cmd+V)
```

## Configuration flow

Settings live in `AppSettings`. Non-secret preferences use `UserDefaults`. API keys use `KeychainStore` (`app.vibevoice.oss.macos`).

Clients receive configuration structs:

- `TranscriptionConfiguration` → ASR backend, integrated engine, HTTP / SSE settings
- `NativeASRClient` calls `mlx-swift-asr` for Qwen3-ASR and WhisperKit for Whisper
- WebSocket streaming uses the same ASR API key and is available only in API ASR mode
- `TranslationConfiguration` / `SemanticFormatterConfiguration` → chat completions

Translation, structured cleanup, and Prompt compile are gated behind LLM API mode plus a configured endpoint and model. When LLM post-processing is off or incomplete, the pipeline emits the ASR transcript directly and the related UI controls are disabled.

## Bundled UI preview

`tools/fluid-voice-oss` is a Vite/React preview of the particle HUD. It is not required to build or run the macOS app.
