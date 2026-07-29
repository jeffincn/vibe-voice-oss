#!/usr/bin/env python3
"""Generate the offline Core ML sentence/candidate scorer.

The model consumes a 128-element hashed representation of the complete Rime
preedit and candidate and emits one score. Rime remains the only source of
candidate text. The examples below are a reproducible seed training set; a
larger private corpus can replace it without changing the runtime contract.
"""
from pathlib import Path
import numpy as np
import coremltools as ct
from coremltools.models import datatypes
from coremltools.models.neural_network import NeuralNetworkBuilder

FEATURE_COUNT = 128

def bucket(text: str) -> int:
    value = 14695981039346656037
    for byte in text.encode("utf-8"):
        value ^= byte
        value = (value * 1099511628211) & ((1 << 64) - 1)
    return 5 + value % (FEATURE_COUNT - 5)

def features(preedit: str, candidate: str, document_context: str = "", raw_weight: float = 0.0) -> np.ndarray:
    values = np.zeros(FEATURE_COUNT, dtype=np.float32)
    values[0] = min(max(raw_weight / 100000.0, -10), 10)
    values[1] = len(candidate) / 16.0
    values[2] = len(preedit) / 64.0
    values[3] = 1.0 if len(candidate) > 1 else 0.0
    chars = list(candidate)
    for char in chars:
        values[bucket("c1:" + char)] += 1.0
    for left, right in zip(chars, chars[1:]):
        values[bucket("c2:" + left + right)] += 1.0
    values[bucket("pair:p:" + preedit + "|d:" + document_context + "|c:" + candidate)] += 1.0
    context_chars = list(document_context)
    for char in context_chars:
        values[bucket("d1:" + char)] += 0.25
    for left, right in zip(context_chars, context_chars[1:]):
        values[bucket("d2:" + left + right)] += 0.5
    return values

# Seed phrase pairs exercise the full-sentence path and common workplace
# vocabulary. Negative examples share the same pinyin context but use a
# plausible homophone, so training does more than reward string length.
examples = [
    ("wodaolefangandexianchang", "我到了方案的现场", 1.0),
    ("wodaolefangandexianchang", "我倒了方案的现场", 0.0),
    ("womenbixuanbujiubandewanchengxitongbushu", "我们必须按部就班的完成系统部署", 1.0),
    ("womenbixuanbujiubandewanchengxitongbushu", "我们必须按部就班地完成系统部署", 0.0),
    ("mianduitufaguzhangjishutuanduiyishiyichoumozhan", "面对突发故障技术团队一时一筹莫展", 1.0),
    ("mianduitufaguzhangjishutuanduiyishiyichoumozhan", "面对突发故障技术团队意识一筹莫展", 0.0),
    ("hao", "好", "这个方案很", 1.0),
    ("hao", "号", "这个方案很", 0.0),
    ("xing", "行", "请确认是否可", 1.0),
    ("xing", "型", "请确认是否可", 0.0),
]
X = np.stack([features(pinyin, candidate, context if len(example) == 4 else "")
              for example in examples
              for pinyin, candidate, *rest in [example]
              for context in ([rest[0]] if len(rest) == 2 else [""])])
y = np.array([example[-1] for example in examples], dtype=np.float32)
# Ridge regression gives deterministic, non-zero weights for sentence/candidate
# interaction features while keeping inference a single tiny linear layer.
regularization = np.eye(FEATURE_COUNT, dtype=np.float32) * 0.05
regularization[:5, :5] *= 0.1
weights = np.linalg.solve(X.T @ X + regularization, X.T @ y).astype(np.float32)

root = Path(__file__).resolve().parents[1]
output = root / "iOS/Resources/CandidateRanker/VibeCandidateRanker.mlmodel"
builder = NeuralNetworkBuilder(
    input_features=[("features", datatypes.Array(FEATURE_COUNT))],
    output_features=[("score", datatypes.Array(1))],
)
builder.add_inner_product(
    name="candidate_score",
    input_channels=FEATURE_COUNT,
    output_channels=1,
    has_bias=True,
    W=weights.reshape(1, FEATURE_COUNT),
    b=np.array([0.0], dtype=np.float32),
    input_name="features",
    output_name="score",
)
builder.spec.description.metadata.author = "Vibe Voice OSS"
builder.spec.description.metadata.shortDescription = "Offline full-sentence Rime candidate scorer"
output.parent.mkdir(parents=True, exist_ok=True)
ct.utils.save_spec(builder.spec, str(output))
print(output)
