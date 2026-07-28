# Configuration

All runtime modes, endpoints, and models are edited in the in-app Settings window. Defaults are local-first and meant as examples.

| Setting | Default | Notes |
|---------|---------|-------|
| ASR mode | Integrated local MLX | Switch to API mode for oMLX / OpenAI-compatible servers |
| Integrated ASR engine | Whisper / WhisperKit | Qwen3-ASR / mlx-swift-asr is also available |
| Qwen model repo | `mlx-community/Qwen3-ASR-0.6B-6bit` | Used by Prepare Model; can be changed to other compatible MLX repos |
| Qwen model directory | empty | Filled by Prepare Model or selected manually; must contain `config.json`, `model.safetensors`, and tokenizer files |
| WhisperKit model | `tiny` | Used only in WhisperKit native mode; use short WhisperKit names such as `tiny` or `large-v3-v20240930_626MB` |
| API ASR model | empty | API mode only; must match your server |
| ASR language | `zh` | Passed to the integrated runner or transcription API |
| ASR prompt | `local ASR, macOS` | Bias / hotspot words for ASR |
| ASR endpoint | `http://127.0.0.1:8000/v1/audio/transcriptions` | API mode only |
| Streaming WebSocket | `ws://127.0.0.1:8000/v1/audio/stream` | API mode only; falls back to overlapping-window pseudo-streaming |
| ASR API key | empty | API mode only; optional `Authorization: Bearer …`; stored in Keychain |
| LLM post-processing | off | Must be switched to API mode before translation / structure / prompt compile are enabled |
| LLM endpoint | derived from ASR URL → `/v1/chat/completions` | Translation, structure, prompt compile |
| LLM model | empty | Fill with your loaded chat model name |
| LLM API key | empty (may copy ASR key on first run) | Keychain |
| Professional roles | none selected | Create/edit professional context; select up to three candidates for LLM routing |

## Professional roles

Version 0.8.0 includes editable **程式工程师** and **外贸人员** presets. A role supplies background, terminology, and expression boundaries to LLM cleanup, translation, Prompt compilation, and Smart Route.

- Select one role to lock it immediately, or select two or three so the LLM can choose the best role for the first role-aware input.
- The selected role remains locked until you choose a different one or clear the lock from the menu or result banner.
- The engineer profile preserves code identifiers, commands, API names, paths, and uncertainty; it never invents technical facts.
- The foreign-trade profile handles quotations and negotiation terms such as MOQ, FOB/CIF, lead time, payment, samples, and logistics; it never invents prices, delivery promises, stock, or payment terms.
- Role management is available without an LLM, but role-aware processing requires a configured LLM endpoint and model.

Integrated ASR runs through native Swift libraries: Qwen3-ASR uses `mlx-swift-asr`, and Whisper uses WhisperKit. Click **Prepare Model** to download missing local files or repair an incomplete cache. Qwen3-ASR downloads from the configured Hugging Face repo and writes the resolved local directory back into settings; WhisperKit downloads from `argmaxinc/whisperkit-coreml`. Changing an endpoint to a remote host means audio and/or text leave the machine and go to that host. There is no built-in cloud account; the app only calls the URLs you configure.
