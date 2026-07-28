# AGENTS.md — Vibe Voice OSS Build, Sign & Deploy Agent Prompt

> This file instructs AI coding agents (Cursor, Claude Code, Grok, Codex, and compatible tools) on how to build, sign, and deploy Vibe Voice OSS. Agents MUST follow these rules whenever they modify source code, resources, or build scripts in this repository.

---

## Objective

After every code change, produce a correctly signed, launchable `.app` bundle installed to both `dist/` and `/Applications`. Automatically detect whether a persistent Apple Developer signing identity exists and fall back to ad-hoc signing when it does not—without requiring any manual intervention from the user.

---

## Context

Vibe Voice OSS is a SwiftPM-based macOS menu-bar app (Apple Silicon, macOS 15+). It has no Xcode project; all builds go through `swift build` and a Zsh packaging script. The app requires **Microphone** and **Accessibility** permissions at runtime. Accessibility grants are tied to the code signature: when the signature changes, macOS revokes the grant and the user must re-authorize. A stable signing identity prevents this; ad-hoc signing (`codesign --sign -`) causes the grant to reset on every rebuild.

### Key paths

| Artifact | Path |
|----------|------|
| SwiftPM manifest | `Package.swift` |
| Voice app sources | `Sources/Voice/` |
| IMK pinyin sources | `Sources/InputMethod/` |
| Shared bridge | `Sources/Shared/` |
| Pinyin engine | `Sources/Pinyin/` |
| App metadata | `Resources/Voice/Info.plist` |
| IMK resources | `Resources/InputMethod/` |
| Build & package script | `scripts/build-app.sh` |
| Staging output | `dist/Vibe Voice OSS.app` |
| System install | `/Applications/Vibe Voice OSS.app` |
| MLX Metal shaders | `.build/release/default.metallib` |

---

## Requirements

### R1 — Always Build Before Launch

Every time source code or resources are modified, the agent MUST compile and package a fresh `.app` bundle before reporting completion. Never tell the user "the change is ready" without a successful build.

**Build command** (must run with Zsh, not Bash):

```zsh
zsh scripts/build-app.sh
```

If the full app bundle is not needed (e.g. checking compilation only):

```zsh
swift build
```

### R2 — Increment `CFBundleVersion` on Every Change

Before building, increment the integer value of `CFBundleVersion` in `Resources/Voice/Info.plist` by 1. This lets the user confirm whether a new build contains the latest changes. Do NOT modify `CFBundleShortVersionString` unless explicitly asked.

### R3 — Automatic Signing Identity Detection

The build script (`scripts/build-app.sh`) implements a three-tier signing identity cascade. Agents MUST NOT bypass or hard-code any identity. The logic is:

```
1.  Environment override   →  $CODESIGN_IDENTITY (if set and non-empty)
2.  Local self-signed cert  →  "Vibe Voice OSS Local Code Signing" (searched in Keychain)
3.  Apple Developer cert    →  "Apple Development:*" (first match from Keychain)
4.  Ad-hoc fallback         →  codesign --sign -  (no identity, signature resets permissions)
```

**Detection mechanism** (already in `build-app.sh`):

```zsh
# Step 1: check for project-specific local cert
IDENTITY=$(security find-identity -v -p codesigning \
    | sed -n "s/.*\"\(Vibe Voice OSS Local Code Signing\)\".*/\1/p" \
    | head -n 1)

# Step 2: check for any Apple Development cert
if [[ -z "$IDENTITY" ]]; then
    IDENTITY=$(security find-identity -v -p codesigning \
        | sed -n 's/.*"\(Apple Development:[^"]*\)".*/\1/p' \
        | head -n 1)
fi

# Step 3: ad-hoc fallback
# SIGN_ARGS carries --force --timestamp=none plus the hardened-runtime flags.
if [[ -n "$IDENTITY" ]]; then
 codesign "${SIGN_ARGS[@]}" --sign "$IDENTITY" "$APP"
else
 codesign "${SIGN_ARGS[@]}" --sign - "$APP"
fi
```

Agents MUST NOT:
- Skip signing or remove signing steps.
- Hard-code a specific identity string (except the local cert name as a search target).
- Add `--no-strict` or disable verification.
- Reintroduce `--deep` when *signing*. It is deprecated for signing and the bundle has no nested Mach-O code. `--deep` remains correct for `codesign --verify`.

### R3a — Hardened Runtime

The app is signed with `--options runtime` and `Resources/Voice/VibeVoiceOSS.entitlements`. This blocks code injection and process-memory reads that would expose decrypted API keys, and is a prerequisite for notarization.

The hardened runtime denies the microphone and Apple Events unless the entitlements ask for them, so the file must keep:

| Entitlement | Needed by |
|-------------|-----------|
| `com.apple.security.device.audio-input` | `AVAudioEngine` capture |
| `com.apple.security.automation.apple-events` | `PasteService` NSAppleScript fallback |

Keep the list minimal — each entry weakens the protection. `VIBE_VOICE_SKIP_HARDENED_RUNTIME=1` disables it, and exists only to bisect a launch failure back to this step; it must not be the default.

### R4 — Post-Sign Verification

After signing, the script verifies the bundle:

```zsh
codesign --verify --deep --strict "$APP"
```

If verification fails (e.g. macOS File Provider attaches `com.apple.quarantine` xattrs), the script retries up to 3 times with `xattr -cr` cleanup between attempts. Agents MUST preserve this retry logic.

### R5 — MLX Metal Shader Compilation

The app depends on `mlx-swift` for GPU-accelerated ML inference. SwiftPM does not compile `.metal` shader sources automatically. The build script handles this:

1. Finds all `.metal` files under `.build/checkouts/mlx-swift/Source/Cmlx/mlx-generated/metal/`.
2. Compiles each to `.air` (Metal AIR) with `xcrun metal`.
3. Links all `.air` files into `default.metallib` with `xcrun metallib`.
4. Places the result at `.build/release/default.metallib`.
5. Copies it into the app bundle at `Contents/Resources/mlx-swift_Cmlx.bundle/default.metallib`.

This step is **conditional**: it only runs when `default.metallib` is missing or older than the `mlx-swift` checkout. Agents MUST NOT remove this step. If the Metal Toolchain is missing, install it:

```zsh
xcodebuild -downloadComponent MetalToolchain
```

### R6 — Dual Deployment

The build script installs the app to two locations:

1. `dist/Vibe Voice OSS.app` — version-controlled staging area.
2. `/Applications/Vibe Voice OSS.app` — system install for Launch-at-Login and daily use.

Both copies are independently signed and verified. Agents MUST maintain this dual deployment.

### R7 — Accessibility Permission Advisory

When using ad-hoc signing (tier 4 fallback), warn the user:

> **Accessibility permissions will reset after this rebuild.** Go to System Settings → Privacy & Security → Accessibility, remove and re-add "Vibe Voice OSS" to restore paste functionality.

When a persistent identity is used (tiers 1–3), this warning is unnecessary.

### R8 — Shell Interpreter

`scripts/build-app.sh` uses Zsh-specific syntax (`${0:A:h:h}` for script directory resolution). Always invoke it with `zsh`, never `bash` or `sh`.

---

## Constraints

- **No Xcode project.** All builds use SwiftPM (`swift build`) and the Zsh packaging script.
- **No `xcrun notarytool`.** The app is not notarized; it is intended for local or side-loaded use.
- **No hardcoded paths.** The build script derives all paths from `$ROOT` (the repository root).
- **Sandbox restrictions.** When running `swift build` inside a sandboxed AI agent, request `all` permissions to allow package resolution and compilation.
- **Bundle ID.** Always `app.vibevoice.oss.macos`. Do not change without explicit user request.
- **Executable name.** Always `VibeVoiceOSS` (must match `Package.swift` executable target).
- **No `cursor/` or `codex/` branch prefixes.** See R12.

---

## Build Lifecycle Summary

```
Agent modifies source code
  │
  ├─ Increment CFBundleVersion in Resources/Voice/Info.plist
  │
  ├─ Run: zsh scripts/build-app.sh
  │    │
  │    ├─ swift build -c release
  │    ├─ Generate app icon (.icns)
  │    ├─ Compile MLX Metal shaders (conditional)
  │    ├─ Assemble .app bundle in staging dir
  │    ├─ Detect signing identity (cascade 1→2→3→4)
  │    ├─ Sign with detected identity or ad-hoc
  │    ├─ Verify signature
  │    ├─ Deploy to dist/ and /Applications
  │    └─ Re-sign /Applications copy
  │
  └─ Report build result to user
       ├─ Success: version number + signing identity used
       └─ Ad-hoc: include Accessibility permission warning
```

---

## Expected Output

After a successful build, the agent should report:

1. The new `CFBundleVersion` number.
2. Which signing identity was used (or "ad-hoc" if none found).
3. Whether Accessibility re-authorization is needed (ad-hoc only).
4. Confirmation that both `dist/` and `/Applications` copies are installed.

---

## R9 — User Confirmation Before Closing a Task

Before the agent considers any task complete and ends its turn, it MUST present a structured confirmation prompt to the user asking whether the issue has been resolved. This applies to every conversation turn where the agent believes it has finished executing a task.

The prompt MUST use the agent platform's native structured-choice mechanism (e.g. `AskQuestion` in Cursor, `ask_user` in Claude Code, equivalent in Grok/Codex) and include exactly these options:

| Option | Meaning |
|--------|---------|
| **Yes** | The user confirms the task is resolved. The agent may end the turn. |
| **No** | The user indicates the problem persists. The agent MUST continue investigating. |
| *(Other / custom input)* | The user provides additional context or a follow-up request. The agent MUST act on it. |

The agent MUST NOT silently assume completion. Even if the build succeeds and all checks pass, the user's explicit confirmation is required.

---

## R10 — Qwen3-ASR Local Model Preparation

The Qwen3-ASR model (MLX quantised) requires special preparation before it can be loaded by the app. The Hugging Face repository (`mlx-community/Qwen3-ASR-0.6B-6bit`) does **not** ship a ready-to-use `tokenizer.json`. Agents MUST follow this procedure whenever the user downloads or prepares a Qwen3-ASR model.

### Step 1 — Download Model Files

Download all files from the Hugging Face repository to the local model directory:

```zsh
MODEL_DIR=~/Documents/VibeVoiceOSS/Models/Qwen3-ASR-0.6B-6bit
mkdir -p "$MODEL_DIR"
# Download core files (config, weights, vocab, merges, tokenizer_config)
for f in config.json model.safetensors vocab.json merges.txt tokenizer_config.json; do
  curl -sL "https://huggingface.co/mlx-community/Qwen3-ASR-0.6B-6bit/resolve/main/$f" \
       -o "$MODEL_DIR/$f"
done
```

If Hugging Face is unreachable, use a mirror:

```zsh
export HF_ENDPOINT=https://hf-mirror.com
```

### Step 2 — Generate `tokenizer.json`

The MLXASR library (`AutoTokenizer.from(modelFolder:)`) requires a `tokenizer.json` file in HuggingFace Tokenizers format (~11 MB). The repo only provides `vocab.json` + `merges.txt`. Generate it with Python:

```bash
pip install transformers tokenizers
python3 -c "
from transformers import AutoTokenizer
t = AutoTokenizer.from_pretrained('$MODEL_DIR')
t.save_pretrained('$MODEL_DIR')
"
```

Verify the generated file is at least 5 MB (a 12 KB file is the wrong format — that's likely a copy of `tokenizer_config.json`).

### Step 3 — Verify Required Files

After preparation, the model directory MUST contain at minimum:

| File | Size (approx.) | Purpose |
|------|----------------|---------|
| `model.safetensors` | ~818 MB | Model weights |
| `config.json` | ~2 KB | Model architecture config |
| `vocab.json` | ~2.8 MB | Vocabulary mapping |
| `merges.txt` | ~1.7 MB | BPE merge rules |
| `tokenizer.json` | ~11 MB | Full HuggingFace tokenizer (generated) |
| `tokenizer_config.json` | ~12 KB | Tokenizer configuration |

### Step 4 — MLX Metal Shader Prerequisite

Qwen3-ASR uses MLX for inference, which requires `default.metallib` in the app bundle. This is handled by the build script (see R5). If the user reports "Failed to load the default metallib":

1. Ensure the Metal Toolchain is installed: `xcodebuild -downloadComponent MetalToolchain`
2. Rebuild with `zsh scripts/build-app.sh` (the script auto-compiles `.metal` → `.metallib`)
3. Verify the metallib is in the bundle: `ls "dist/Vibe Voice OSS.app/Contents/Resources/mlx-swift_Cmlx.bundle/default.metallib"`

### Common Errors

| Error | Cause | Fix |
|-------|-------|-----|
| `Required configuration file missing: tokenizer.json` | Repo doesn't ship it | Run Step 2 to generate |
| `tokenizer.json` exists but model fails to load | File is only 12 KB (wrong format) | Delete and regenerate with Step 2 |
| `MLX Error: Failed to load the default metallib` | Metal shaders not compiled | Run Step 4 |
| Download stuck at 54% | Network restriction on huggingface.co | Use `HF_ENDPOINT` mirror or download with `curl` |
| `Invalid metadata: File metadata must have been retrieved from server` | Mirror redirect issue | Download directly with `curl` (Step 1) |

---

## R11 — Silero VAD Preparation (Voice Pipeline)

Voice Pipeline requires Silero VAD under `~/Documents/VibeVoiceOSS/Models/SileroVAD/`.

```zsh
zsh scripts/prepare-silero-vad.sh
```

| Artifact | Purpose |
|----------|---------|
| `silero_vad.jit` | Upstream TorchScript model, pinned to a commit and checksum-verified |
| `silero_vad.mlpackage` | CoreML model the app loads (compiled to `.mlmodelc` on first launch) |
| `USE_ENERGY_VAD` | Written when conversion is unavailable; the app falls back to the energy backend |

Conversion runs through `scripts/convert-silero-vad.py`, which needs `torch` and `coremltools>=8`:

```zsh
pip install torch 'coremltools>=8'
```

The CoreML model must expose exactly the interface `VADService` feeds — inputs `audio [1,1,576]`, `h [1,1,128]`, `c [1,1,128]`; outputs `probability`, `h_out`, `c_out`. The script asserts this and checks numerical parity against the upstream module before saving, so agents MUST NOT relax those checks: a model that converts but does not match is silently useless, which is how the previous script failed.

Without these files, enabling Voice Pipeline falls back to the energy backend, which Settings now warns about.

---

## R12 — Git Branch Naming

Agents MUST NOT create, push, or open pull requests from branches whose names start with `cursor/` or `codex/` (case-insensitive). Those prefixes split reviewable work across throwaway agent branches that cannot be tested as one development line.

Work on the active development branch instead:

| Track | Branch |
|-------|--------|
| macOS 0.8.0 / professional roles | `feat/professional-roles` |
| iOS 0.7.0 | `ios/0.7.0` |

Allowed prefixes when a separate branch is truly required: `feat/`, `fix/`, `chore/`, `docs/`, `test/`, `ci/`, `refactor/`, `ios/`. Branch names stay lowercase kebab-case.

If a cloud agent or other tool defaults to `cursor/` or `codex/` names, override that default and use one of the prefixes above — or commit directly on the active development branch when the change belongs there.

---

## R13 — Agent Reply Style

Agents MUST default to conversational replies, matching the "内容整理" intensity the app itself uses:

- Reorganize by meaning into short paragraphs or a light list; drop redundant subjects, filler words, and repeated phrasing.
- Keep it natural. Do not force every answer into enumerated items.
- Do not auto-switch into "command mode" / "task-solving mode" — no unsolicited project plans, calendars, milestones, or owner/priority tables.

Switch to strict itemization and hierarchy only when the user explicitly asks for it ("总结", "列出方案", "结构化", or an equivalent request), or when the rules being explained are genuinely complex enough that prose would be harder to read.

This mirrors the `StructureIntensity` contract in `Sources/Voice/LLM/SemanticFormatter.swift`; keep the two in sync when either changes.

---

## Acceptance Criteria

- [ ] Every code change is followed by a successful `zsh scripts/build-app.sh`.
- [ ] `CFBundleVersion` is incremented before each build.
- [ ] Signing identity detection is automatic—no manual user action required.
- [ ] Ad-hoc signing is used as a last resort, with a clear warning about permission resets.
- [ ] The `.app` bundle passes `codesign --verify --deep --strict`.
- [ ] Both `dist/` and `/Applications` contain the latest build.
- [ ] MLX `default.metallib` is present inside the app bundle when MLX dependencies exist.
- [ ] The build script is invoked with `zsh`, never `bash`.
- [ ] Agent presents a structured Yes / No / Other confirmation to the user before ending each task.
- [ ] No branch or PR uses a `cursor/` or `codex/` prefix (R12).
- [ ] Replies stay conversational by default; strict itemization only on explicit request (R13).
