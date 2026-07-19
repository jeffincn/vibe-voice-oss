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

Integrated ASR runs through native Swift libraries: Qwen3-ASR uses `mlx-swift-asr`, and Whisper uses WhisperKit. Click **Prepare Model** to download missing local files or repair an incomplete cache. Qwen3-ASR downloads from the configured Hugging Face repo and writes the resolved local directory back into settings; WhisperKit downloads from `argmaxinc/whisperkit-coreml`. Changing an endpoint to a remote host means audio and/or text leave the machine and go to that host. There is no built-in cloud account; the app only calls the URLs you configure.
