# Architecture

Vibe Type / Vibe Voice OSS is a macOS monorepo with two product surfaces that share a thin bridge:

1. **Voice** — menu-bar dictation client (`VibeVoiceOSS`)
2. **Input Method** — IMK pinyin IME (`VibeVoiceInputMethod` / Vibe Type)

```text
Sources/
  Voice/           # hotkey → mic → ASR → optional LLM → paste
    App/ Audio/ ASR/ Pipeline/ LLM/ UI/ Storage/ Networking/
  InputMethod/     # IMK server, candidate bar, Rime engine host
  Pinyin/          # syllable table, lexicon, typo/fuzzy, composer, ranker
  Shared/          # InputMethodBridge (file + Darwin notify)
  Rime/            # librime C adapter
  ObjCExceptionCatcher/

Resources/
  Voice/           # Info.plist, entitlements, app icon
  InputMethod/     # RimeData, Lexicon, CandidateRanker, VibeType assets

Tests/
  VoiceTests/ PinyinTests/ SharedTests/
```

## Voice pipeline

```text
Hotkey / menu
  → AudioRecorder (PCM)
  → WAVEncoder / streaming session
  → NativeASRClient or TranscriptionClient / StreamingASRClient
  → optional API-only TranslationClient / SemanticFormatter / PromptCompiler
  → PasteService (Accessibility or Cmd+V)
```

Settings live in `AppSettings`. Non-secret preferences use `UserDefaults`. API keys use `KeychainStore` (`app.vibevoice.oss.macos`).

Clients receive configuration structs:

- `TranscriptionConfiguration` → ASR backend, integrated engine, HTTP / SSE settings
- `NativeASRClient` calls `mlx-swift-asr` for Qwen3-ASR and WhisperKit for Whisper
- WebSocket streaming uses the same ASR API key and is available only in API ASR mode
- `TranslationConfiguration` / `SemanticFormatterConfiguration` → chat completions

Translation, structured cleanup, and Prompt compile are gated behind LLM API mode plus a configured endpoint and model. When LLM post-processing is off or incomplete, the pipeline emits the ASR transcript directly and the related UI controls are disabled.

## Pinyin input method

```text
Key event (IMK)
  → RimeEngine (librime) + Pinyin typo/fuzzy recovery
  → PhraseComposer / MixedTokenAnalyzer overlays
  → CandidateRanker (Core ML, optional)
  → CandidateBarWindow commit
```

IME-only code lives under `Sources/InputMethod` and `Sources/Pinyin`. Rime schemas and dictionaries ship in `Resources/InputMethod/RimeData`.

## Shared bridge

`VibeVoiceShared.InputMethodBridgeStore` lets the IME request a voice session from the menu-bar app through a JSON file under Application Support plus a Darwin notification.

## Shared correction lexicon

`VibeVoiceShared.SharedCorrectionLexicon` stores cross-product vocabulary at:

`~/Library/Application Support/VibeVoiceOSS/Lexicon/shared-corrections.v1.tsv`

```text
canonical	pinyin_code	aliases	kind	weight	source
魔法棒	mofabang	魔法帮|魔发棒	phrase	12000	user
Core ML	coreml	扣肉ML	proper	100	project
```

`source` records provenance (`project` / `migrated` / `user`). Pinyin overlays use `pinyin_code`; Voice merges `canonical` into the ASR hotspot and feeds alias→canonical rows (with source labels) into LLM role/cleanup context. Bundle Lexicon TSVs remain IME-only defaults.

Voice Settings also imports `VibeVoicePinyin` so fuzzy-pinyin and project-vocabulary toggles stay in sync with the IME.

## Bundled UI preview

`tools/fluid-voice-oss` is a Vite/React preview of the particle HUD. It is not required to build or run the macOS app.
