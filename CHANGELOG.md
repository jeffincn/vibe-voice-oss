# Changelog

## Vibe Voice OSS 0.5.0

Vibe Voice OSS 0.5.0 moves the app from an API-dependent dictation client to a local-first voice workflow. It can now transcribe entirely on the Mac while retaining OpenAI-compatible API support for users who prefer an external ASR or LLM service.

## Highlights

### Integrated native ASR

- WhisperKit is the default local transcription engine.
- Qwen3-ASR is available through `mlx-swift-asr`.
- Native transcription runs in Swift without a Python runtime or separate ASR server.
- OpenAI-compatible ASR remains available as an optional API mode.

The new **Prepare Model** action downloads or repairs local model files. WhisperKit accepts model variants such as `tiny`; Qwen3-ASR supports a configurable Hugging Face repository and an existing local MLX model directory. Readiness checks now provide guidance for missing files, gated repositories, authorization failures, and model-loading errors.

### Independent ASR and LLM modes

ASR and LLM processing are now configured separately. ASR can use an integrated engine or an API, while translation, structured cleanup, Prompt compilation, and Smart Route run only when LLM API mode has a valid endpoint and model. If LLM processing is disabled, the app emits the ASR transcript directly and disables unavailable controls.

### New output workflows

Five global shortcuts now select the output pipeline:

| Shortcut | Workflow |
| --- | --- |
| `⌘⇧R` | Conversation or configured output-language workflow |
| `⌘⇧E` | Translate directly to English |
| `⌘⇧F` | Structured formatting |
| `⌘⇧T` | Compile for the selected Prompt target |
| `⌘⇧G` | Smart Route using the custom System Prompt |

Smart Route lets a user-supplied System Prompt control the result, enabling specialized rewriting, extraction, classification, formatting, or routing. The custom System Prompt can also supplement translation, formatting, and Prompt compilation.

### Token usage reporting

A new Token Usage window records usage returned by compatible APIs. It presents cumulative totals and recent requests for transcription, formatting, translation, and Prompt optimization, including input, output, cached, reasoning, and audio tokens as well as reported audio duration. Local inference and APIs that omit `usage` are not estimated.

## Reliability improvements

- Text insertion now uses CGEvent paste with an AppleScript fallback, improving compatibility with web editors and stricter macOS event handling.
- Clipboard contents are restored when possible after insertion.
- Accessibility permission prompts and insertion errors are clearer and less repetitive.
- LLM and formatting requests now allow up to 180 seconds.
- Integrated ASR allows up to 10 minutes for initial model download or loading.
- Streaming API responses can contribute token usage data.
- Pseudo-streaming avoids starting inference for every small audio frame, reducing unnecessary local-ASR workload.
- Errors better distinguish API failures, local runtime failures, model problems, permissions, and text insertion failures.

## Build and compatibility changes

- Minimum supported system: macOS 15, up from macOS 14.
- Swift tools version: 6.2, up from 6.0.
- Added `mlx-swift-asr`, WhisperKit, and Argmax OSS dependencies.
- The packaging process compiles and bundles MLX Metal shaders for native GPU inference.
- Signing now supports the persistent `Vibe Voice OSS Local Code Signing` identity before falling back to an Apple Development identity or ad-hoc signing.
- Both `dist/` and `/Applications` bundles are independently signed and strictly verified.
- Release version: 0.5.0, build 9.

## Privacy

API keys remain in the macOS Keychain. Integrated ASR processes audio locally. Audio or text leaves the Mac only when the corresponding API mode is configured with a remote endpoint. API streaming and WebSocket transcription remain available in ASR API mode.

## Upgrading from 0.4

Version 0.4 required an OpenAI-compatible ASR service. Version 0.5 defaults to integrated WhisperKit transcription, so an external server is no longer required. Existing API users can select API mode and keep their endpoint, model, and Keychain-backed credentials. Because the minimum deployment target is now macOS 15, macOS 14 systems must remain on the 0.4 release line.

## Detailed feature reference

### ASR configuration

The Settings window now separates ASR mode, integrated engine, Qwen model repository and directory, WhisperKit model, API endpoint, API key, model, language, prompt, streaming mode, and WebSocket URL. Integrated mode uses WhisperKit or Qwen3-ASR locally; API mode retains HTTP transcription, SSE, WebSocket streaming, and overlapping-window pseudo-streaming.

The **Prepare Model** action downloads or repairs local model files. A manually selected Qwen directory must contain `config.json`, `model.safetensors`, and tokenizer files. Readiness checks provide targeted guidance for missing files, gated repositories, Hugging Face authorization, and local runtime failures.

### LLM processing and routing

When LLM API mode has a complete endpoint and model, the app supports translation, direct English translation, clean or structured formatting, two-stage Prompt compilation, and Smart Route. Custom System Prompts supplement normal tasks and control Smart Route output, enabling specialized rewriting, extraction, classification, formatting, or routing. LLM controls are disabled when the backend is off or incomplete.

### Processing and errors

The pipeline now distinguishes routing, model preparation, local transcription, API transcription, structuring, translation, and Prompt optimization. Cancellation works across these stages. Errors identify model, authorization, API, runtime, Accessibility, and insertion failures. If insertion fails after processing, the result remains available for copying and is preserved in the clipboard when possible.

### Usage accounting

Usage records are persisted locally with a bounded history and include stage, model, timestamp, and provider-reported usage. The report shows cumulative totals and recent requests for input, output, cached, reasoning, audio, and duration fields. It accepts common Chat/Responses, realtime, and audio-transcription usage shapes without double-counting nested details. Local inference and APIs that omit `usage` are not estimated, and the report can be cleared.

### Packaging and deployment

The release build conditionally compiles MLX Metal sources into `default.metallib`, places it in `mlx-swift_Cmlx.bundle`, installs independently into `dist/` and `/Applications`, and strictly verifies both copies. Signing selects an environment override, the persistent local identity, an Apple Development identity, or ad-hoc signing in that order. Release 0.5.0 used `Vibe Voice OSS Local Code Signing`, so Accessibility grants survive rebuilds.

### Verification

The 0.5.0 release passed 81 Swift tests. The release build completed successfully, the bundle reports version `0.5.0` / build `9`, the MLX Metal library is present in both installed bundles, and both app copies pass `codesign --verify --deep --strict`.
