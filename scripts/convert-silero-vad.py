#!/usr/bin/env python3
"""Convert the Silero VAD TorchScript model to CoreML for the voice pipeline.

Produces silero_vad.mlpackage with exactly the interface VADService feeds:

    inputs   audio [1, 1, 576]   64 samples of carried context + a 512-sample chunk
             h     [1, 1, 128]   LSTM hidden state
             c     [1, 1, 128]   LSTM cell state
    outputs  probability, h_out, c_out

The stock module is TorchScript, and two of its pieces branch on values the
CoreML converter cannot follow: ``F.pad`` tests the mode string, and
``LSTMCell`` tests the input rank. Both are rebuilt below in plain torch from
the same weights, and the result is checked against the stock module before
conversion so a silent numerical drift cannot slip through.

Reads SILERO_VAD_DIR (default ~/Documents/VibeVoiceOSS/Models/SileroVAD).
"""

from __future__ import annotations

import os
import shutil
import sys
from pathlib import Path

CONTEXT_SAMPLES = 64
CHUNK_SAMPLES = 512
TOTAL_SAMPLES = CONTEXT_SAMPLES + CHUNK_SAMPLES
STATE_SIZE = 128


def model_directory() -> Path:
    raw = os.environ.get("SILERO_VAD_DIR")
    if raw:
        return Path(raw).expanduser()
    return Path.home() / "Documents/VibeVoiceOSS/Models/SileroVAD"


def fail(message: str) -> None:
    print(f"error: {message}", file=sys.stderr)
    raise SystemExit(1)


try:
    import torch
    import torch.nn.functional as F
except ImportError:
    fail("PyTorch is required. Install it with: pip install torch")

try:
    import coremltools as ct
except ImportError:
    fail("coremltools is required. Install it with: pip install 'coremltools>=8'")


class SileroVADChunk(torch.nn.Module):
    """One 512-sample chunk of Silero VAD with the LSTM state passed explicitly."""

    def __init__(self, model: torch.nn.Module) -> None:
        super().__init__()
        stft, rnn = model.stft, model.decoder.rnn
        self.register_buffer("basis", stft.forward_basis_buffer.detach().clone())
        self.hop = int(stft.hop_length)
        self.cutoff = int(stft.filter_length) // 2 + 1
        # TorchScript cannot close over module-level constants, so the chunk
        # geometry has to live on the instance.
        self.context = CONTEXT_SAMPLES
        self.total = TOTAL_SAMPLES
        self.register_buffer("weight_ih", rnn.weight_ih.detach().clone())
        self.register_buffer("weight_hh", rnn.weight_hh.detach().clone())
        self.register_buffer("bias_ih", rnn.bias_ih.detach().clone())
        self.register_buffer("bias_hh", rnn.bias_hh.detach().clone())
        self.encoder = model.encoder
        self.head = model.decoder.decoder

    def magnitude(self, x):
        padded = F.pad(x.unsqueeze(1), [0, self.context], mode="reflect")
        spectrum = F.conv1d(padded, self.basis, stride=self.hop)
        real = spectrum[:, : self.cutoff, :]
        imag = spectrum[:, self.cutoff :, :]
        return torch.sqrt(real * real + imag * imag)

    def cell(self, x, h, c):
        gates = F.linear(x, self.weight_ih, self.bias_ih) + F.linear(
            h, self.weight_hh, self.bias_hh
        )
        i, f, g, o = gates.chunk(4, 1)
        c_out = torch.sigmoid(f) * c + torch.sigmoid(i) * torch.tanh(g)
        return torch.sigmoid(o) * torch.tanh(c_out), c_out

    def forward(self, audio, h, c):
        features = self.encoder(self.magnitude(audio.reshape(1, self.total)))
        h_out, c_out = self.cell(
            torch.squeeze(features, -1), torch.squeeze(h, 0), torch.squeeze(c, 0)
        )
        logits = self.head(torch.unsqueeze(h_out, -1))
        probability = torch.unsqueeze(torch.mean(torch.squeeze(logits, 1), [1]), 1)
        return probability, torch.unsqueeze(h_out, 0), torch.unsqueeze(c_out, 0)


def check_parity(wrapper: torch.nn.Module, reference: torch.nn.Module) -> None:
    """Reject a rebuild that does not reproduce the stock module's output."""
    torch.manual_seed(0)
    for trial in range(4):
        audio = (
            torch.zeros(1, 1, TOTAL_SAMPLES)
            if trial == 0
            else torch.randn(1, 1, TOTAL_SAMPLES) * 0.3
        )
        state_scale = 0.2 if trial >= 2 else 0.0
        h = torch.randn(1, 1, STATE_SIZE) * state_scale
        c = torch.randn(1, 1, STATE_SIZE) * state_scale
        with torch.no_grad():
            got = wrapper(audio, h, c)
            expected, state = reference(
                audio.reshape(1, TOTAL_SAMPLES), torch.cat([h, c], dim=0)
            )
        for label, actual, want in (
            ("probability", got[0], expected),
            ("h_out", got[1], state[0:1]),
            ("c_out", got[2], state[1:2]),
        ):
            if not torch.allclose(actual, want, atol=1e-5):
                fail(
                    f"rebuilt model diverges from upstream on {label} "
                    f"(trial {trial}, max delta {(actual - want).abs().max():.3e})"
                )
    print("    parity with the upstream module verified")


def main() -> None:
    directory = model_directory()
    jit_path = directory / "silero_vad.jit"
    if not jit_path.exists():
        fail(f"missing {jit_path}; run scripts/prepare-silero-vad.sh")

    module = torch.jit.load(str(jit_path))
    module.eval()
    wrapper = SileroVADChunk(module._model).eval()
    check_parity(wrapper, module._model)

    frozen = torch.jit.freeze(torch.jit.script(wrapper))
    mlmodel = ct.convert(
        frozen,
        inputs=[
            ct.TensorType(name="audio", shape=(1, 1, TOTAL_SAMPLES)),
            ct.TensorType(name="h", shape=(1, 1, STATE_SIZE)),
            ct.TensorType(name="c", shape=(1, 1, STATE_SIZE)),
        ],
        outputs=[
            ct.TensorType(name="probability"),
            ct.TensorType(name="h_out"),
            ct.TensorType(name="c_out"),
        ],
        minimum_deployment_target=ct.target.macOS15,
        compute_precision=ct.precision.FLOAT16,
        convert_to="mlprogram",
    )

    out_package = directory / "silero_vad.mlpackage"
    if out_package.exists():
        shutil.rmtree(out_package)
    mlmodel.save(str(out_package))

    spec = mlmodel.get_spec()
    inputs = {i.name: list(i.type.multiArrayType.shape) for i in spec.description.input}
    outputs = [o.name for o in spec.description.output]
    expected_inputs = {
        "audio": [1, 1, TOTAL_SAMPLES],
        "h": [1, 1, STATE_SIZE],
        "c": [1, 1, STATE_SIZE],
    }
    if inputs != expected_inputs:
        fail(f"unexpected CoreML inputs {inputs}, wanted {expected_inputs}")
    if sorted(outputs) != ["c_out", "h_out", "probability"]:
        fail(f"unexpected CoreML outputs {outputs}")

    print(f"    saved {out_package}")
    print(f"    inputs  {inputs}")
    print(f"    outputs {outputs}")


if __name__ == "__main__":
    main()
