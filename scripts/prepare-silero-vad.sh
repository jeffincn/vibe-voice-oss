#!/usr/bin/env zsh
# Prepare Silero VAD for the Vibe Voice OSS voice pipeline.
# Default target: ~/Documents/VibeVoiceOSS/Models/SileroVAD (override with SILERO_VAD_DIR).
#
# Produces silero_vad.mlpackage with the exact interface VADService expects:
#   inputs  audio [1,1,576], h [1,1,128], c [1,1,128]
#   outputs probability, h_out, c_out
# Writes USE_ENERGY_VAD instead when conversion is not possible, so the app can
# still start on the much weaker Silero-windowed energy backend.

set -euo pipefail

MODEL_DIR="${SILERO_VAD_DIR:-$HOME/Documents/VibeVoiceOSS/Models/SileroVAD}"
mkdir -p "$MODEL_DIR"

# Pinned to the v6.2.1 commit rather than a branch: the previous version fetched
# from master, so the weights loaded into the process changed whenever upstream
# pushed, and nothing verified what arrived.
SILERO_COMMIT="7e30209a3e901f9842f81b225f3e93d8199902b1" # v6.2.1
JIT_SHA256="e1122837f4154c511485fe0b9c64455f7b929c96fbb8d79fbdb336383ebd3720"
JIT_URL="https://github.com/snakers4/silero-vad/raw/${SILERO_COMMIT}/src/silero_vad/data/silero_vad.jit"
JIT_PATH="$MODEL_DIR/silero_vad.jit"
MARKER="$MODEL_DIR/USE_ENERGY_VAD"

echo "==> Silero VAD directory: $MODEL_DIR"

fall_back_to_energy() {
    echo "!! $1"
    echo "!! Writing USE_ENERGY_VAD — the app will run the energy backend, which"
    echo "   treats music, keystrokes and fan noise as speech."
    print -r -- "energy" > "$MARKER"
    exit 0
}

verify_checksum() {
    # Not named `path`: in zsh that is tied to $PATH, and shadowing it here would
    # empty the command search path for the rest of the function.
    local file="$1" expected="$2"
    local actual
    actual=$(shasum -a 256 "$file" | cut -d' ' -f1)
    [[ "$actual" == "$expected" ]] && return 0
    echo "!! checksum mismatch for $file" >&2
    echo "   expected $expected" >&2
    echo "   actual   $actual" >&2
    return 1
}

if [[ -f "$JIT_PATH" ]] && verify_checksum "$JIT_PATH" "$JIT_SHA256" 2>/dev/null; then
    echo "==> Reusing verified $JIT_PATH"
else
    echo "==> Downloading silero_vad.jit @ ${SILERO_COMMIT:0:12}…"
    rm -f "$JIT_PATH"
    if ! curl -fL --retry 3 -o "$JIT_PATH" "$JIT_URL"; then
        fall_back_to_energy "Download failed."
    fi
    if ! verify_checksum "$JIT_PATH" "$JIT_SHA256"; then
        # Refuse to convert weights we cannot identify — they end up running
        # inside the app.
        rm -f "$JIT_PATH"
        fall_back_to_energy "Refusing to use a model that failed verification."
    fi
    echo "==> Verified silero_vad.jit"
fi

if ! command -v python3 >/dev/null 2>&1; then
    fall_back_to_energy "python3 not found."
fi

echo "==> Converting to CoreML…"
if ! SILERO_VAD_DIR="$MODEL_DIR" python3 "${0:A:h}/convert-silero-vad.py"; then
    fall_back_to_energy "CoreML conversion failed (see the error above)."
fi

rm -f "$MARKER"
echo "==> Contents of $MODEL_DIR:"
ls -la "$MODEL_DIR"
echo "Done. Restart Vibe Voice OSS to pick up the model."
