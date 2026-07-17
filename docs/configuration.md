# Configuration

All runtime endpoints and models are edited in the in-app Settings window. Defaults are local-first and meant as examples.

| Setting | Default | Notes |
|---------|---------|-------|
| ASR endpoint | `http://127.0.0.1:8000/v1/audio/transcriptions` | OpenAI-compatible transcriptions URL |
| Streaming WebSocket | `ws://127.0.0.1:8000/v1/audio/stream` | Falls back to overlapping-window pseudo-streaming |
| ASR model | `mlx-community/Qwen3-ASR-0.6B-4bit` | Must match a model loaded by your server |
| ASR language | `zh` | Passed to the transcription API |
| ASR prompt | `local ASR, macOS` | Bias / hotspot words for ASR |
| ASR API key | empty | Optional `Authorization: Bearer …`; stored in Keychain |
| LLM endpoint | derived from ASR URL → `/v1/chat/completions` | Translation, structure, prompt compile |
| LLM model | empty | Fill with your loaded chat model name |
| LLM API key | empty (may copy ASR key on first run) | Keychain |

Changing an endpoint to a remote host means audio and/or text leave the machine and go to that host. There is no built-in cloud account; the app only calls the URLs you configure.
