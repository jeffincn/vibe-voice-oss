# Vibe Voice OSS 0.5.0 Change Note

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
