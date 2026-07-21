#!/usr/bin/env zsh
# Prepare Silero VAD for Vibe Voice OSS Voice Pipeline.
# Target: ~/Documents/VibeVoiceOSS/Models/SileroVAD/
#
# Prefer CoreML (silero_vad.mlpackage / .mlmodelc). If conversion is unavailable,
# writes USE_ENERGY_VAD so the app can start with the Silero-windowed energy backend.

set -euo pipefail

MODEL_DIR="${SILERO_VAD_DIR:-$HOME/Documents/VibeVoiceOSS/Models/SileroVAD}"
mkdir -p "$MODEL_DIR"

ONNX_URL="https://github.com/snakers4/silero-vad/raw/master/src/silero_vad/data/silero_vad.onnx"
ONNX_PATH="$MODEL_DIR/silero_vad.onnx"

echo "==> Silero VAD directory: $MODEL_DIR"

if [[ ! -f "$ONNX_PATH" ]]; then
  echo "==> Downloading silero_vad.onnx…"
  if ! curl -fL --retry 3 -o "$ONNX_PATH" "$ONNX_URL"; then
    echo "!! Download failed; enabling energy VAD marker."
    touch "$MODEL_DIR/USE_ENERGY_VAD"
    exit 0
  fi
else
  echo "==> Found existing $ONNX_PATH"
fi

convert_with_python() {
  python3 - <<'PY'
import sys
from pathlib import Path

model_dir = Path.home() / "Documents/VibeVoiceOSS/Models/SileroVAD"
onnx_path = model_dir / "silero_vad.onnx"
out_package = model_dir / "silero_vad.mlpackage"
marker = model_dir / "USE_ENERGY_VAD"

try:
    import coremltools as ct
except ImportError:
    print("coremltools not installed; pip install coremltools")
    marker.write_text("energy\n")
    sys.exit(0)

try:
    model = ct.converters.onnx.convert(
        model=str(onnx_path),
        minimum_deployment_target=ct.target.macOS15,
    )
    if out_package.exists():
        import shutil
        shutil.rmtree(out_package)
    model.save(str(out_package))
    if marker.exists():
        marker.unlink()
    print(f"Saved CoreML package: {out_package}")
except Exception as exc:
    print(f"CoreML conversion failed: {exc}")
    marker.write_text("energy\n")
    print("Wrote USE_ENERGY_VAD — app will use Silero-windowed energy backend.")
PY
}

if command -v python3 >/dev/null 2>&1; then
  echo "==> Attempting ONNX → CoreML conversion…"
  convert_with_python || {
    echo "!! Conversion script failed; enabling energy VAD."
    touch "$MODEL_DIR/USE_ENERGY_VAD"
  }
else
  echo "!! python3 not found; enabling energy VAD."
  touch "$MODEL_DIR/USE_ENERGY_VAD"
fi

echo "==> Contents of $MODEL_DIR:"
ls -la "$MODEL_DIR"
echo "Done."
