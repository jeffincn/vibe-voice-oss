#!/usr/bin/env python3
"""Generate the offline Core ML dialogue/candidate scorer.

The model consumes a 256-element hashed representation of the Rime preedit,
committed prefix, document/session context, and one candidate, then emits a
score. Rime remains the only source of candidate text. Examples below seed a
reproducible training set; a larger private corpus can replace them without
changing the runtime contract.
"""
from pathlib import Path
import shutil
import subprocess
import numpy as np
import coremltools as ct
from coremltools.models import datatypes
from coremltools.models.neural_network import NeuralNetworkBuilder

FEATURE_COUNT = 256
HIDDEN = 64
CONTEXT_LIMIT = 512

def bucket(text: str) -> int:
    value = 14695981039346656037
    for byte in text.encode("utf-8"):
        value ^= byte
        value = (value * 1099511628211) & ((1 << 64) - 1)
    return 16 + value % (FEATURE_COUNT - 16)

def features(preedit: str, candidate: str, document_context: str = "",
             committed_prefix: str = "", raw_weight: float = 0.0) -> np.ndarray:
    document_context = document_context[-CONTEXT_LIMIT:]
    values = np.zeros(FEATURE_COUNT, dtype=np.float32)
    values[0] = min(max(raw_weight / 100000.0, -10), 10)
    values[1] = len(candidate) / 16.0
    values[2] = len(preedit) / 64.0
    values[3] = 1.0 if len(candidate) > 1 else 0.0
    values[5] = len(committed_prefix) / 16.0
    values[6] = len(document_context) / float(CONTEXT_LIMIT)
    values[7] = min(len(candidate), 8) / 8.0
    values[8] = 1.0 if committed_prefix else 0.0
    values[9] = 1.0 if document_context else 0.0
    has_latin = any(("a" <= ch.lower() <= "z") for ch in candidate)
    values[10] = 1.0 if has_latin else 0.0
    values[11] = 1.0 if has_latin else 0.0
    values[12] = 0.0  # synthesised flag filled at runtime
    values[13] = min(len(candidate), 32) / 32.0

    chars = list(candidate)
    for char in chars:
        values[bucket("c1:" + char)] += 1.0
    for left, right in zip(chars, chars[1:]):
        values[bucket("c2:" + left + right)] += 1.0

    prefix_chars = list(committed_prefix)
    for char in prefix_chars:
        values[bucket("p1:" + char)] += 1.0
    for left, right in zip(prefix_chars, prefix_chars[1:]):
        values[bucket("p2:" + left + right)] += 1.0
    if prefix_chars and chars:
        values[bucket("pc:" + prefix_chars[-1] + chars[0])] += 1.5

    context_chars = list(document_context)
    for char in context_chars:
        values[bucket("d1:" + char)] += 0.25
    for left, right in zip(context_chars, context_chars[1:]):
        values[bucket("d2:" + left + right)] += 0.5
    if context_chars and chars:
        values[bucket("dc:" + context_chars[-1] + chars[0])] += 2.0
    if len(context_chars) >= 2 and chars:
        values[bucket("d2c:" + context_chars[-2] + context_chars[-1] + chars[0])] += 1.5

    values[bucket("pair:p:" + preedit + "|f:" + committed_prefix + "|d:" + document_context + "|c:" + candidate)] += 1.0
    values[bucket("pair_short:p:" + preedit + "|c:" + candidate)] += 0.75
    values[bucket("pair_ctx:d:" + document_context[-24:] + "|c:" + candidate)] += 1.25
    return values

# Each example: (preedit, candidate, document_context, committed_prefix, label)
# Empty strings are allowed for context / prefix.
examples = [
    # Seed workplace phrases
    ("wodaolefangandexianchang", "我到了方案的现场", "", "", 1.0),
    ("wodaolefangandexianchang", "我倒了方案的现场", "", "", 0.0),
    ("womenbixuanbujiubandewanchengxitongbushu", "我们必须按部就班的完成系统部署", "", "", 1.0),
    ("womenbixuanbujiubandewanchengxitongbushu", "我们必须按部就班地完成系统部署", "", "", 0.0),
    ("mianduitufaguzhangjishutuanduiyishiyichoumozhan", "面对突发故障技术团队一时一筹莫展", "", "", 1.0),
    ("mianduitufaguzhangjishutuanduiyishiyichoumozhan", "面对突发故障技术团队意识一筹莫展", "", "", 0.0),
    ("hao", "好", "这个方案很", "", 1.0),
    ("hao", "号", "这个方案很", "", 0.0),
    ("xing", "行", "请确认是否可", "", 1.0),
    ("xing", "型", "请确认是否可", "", 0.0),

    # Dialogue: 不对劲 / 对劲
    ("buduijin", "不对劲", "你今天怎么从刚才开始就一直怪怪的", "", 1.0),
    ("buduijin", "不对劲", "你今天真的很非常", "", 1.0),
    ("buduijin", "部对劲", "你今天真的很非常", "", 0.0),
    ("duijin", "对劲", "我哪有不", "", 1.0),
    ("duijin", "对进", "我哪有不", "", 0.0),

    # 出差 vs 查事 / 厨房
    ("chucha", "出差", "你们公司昨天不是刚公布了办公室禁止", "", 1.0),
    ("chucha", "出岔", "你们公司昨天不是刚公布了办公室禁止", "", 0.0),
    ("chufang", "厨房", "你为什么把那个特别大的控制行李箱摸摸掉进了", "", 1.0),
    ("chufang", "出房", "你为什么把那个特别大的控制行李箱摸摸掉进了", "", 0.0),
    ("liulanggou", "流浪狗", "原来你一直在厨房里藏了一只", "", 1.0),
    ("liulanggou", "流浪购", "原来你一直在厨房里藏了一只", "", 0.0),
    ("xiaohuangmao", "小黄猫", "有一只浑身湿透腿还受了伤的", "", 1.0),
    ("xiaohuangmao", "小皇猫", "有一只浑身湿透腿还受了伤的", "", 0.0),

    # 暴雨 / 白噪音 / 鸡胸肉
    ("baoyu", "暴雨", "可是现在外面在下大", "", 1.0),
    ("baoyu", "宝玉", "可是现在外面在下大", "", 0.0),
    ("bainuoyin", "白噪音", "我最近在听那个舒缓身心的", "", 1.0),
    ("bainuoyin", "白诺音", "我最近在听那个舒缓身心的", "", 0.0),
    ("jixiongrou", "鸡胸肉", "你刚才拿去房间的那碗热牛奶和", "", 1.0),
    ("jixiongrou", "鸡兄肉", "你刚才拿去房间的那碗热牛奶和", "", 0.0),

    # Anti over-segmentation: prefer longer phrases
    ("haobuhao", "好不好", "你先去客厅看电视", "", 1.0),
    ("haobuhao", "号不号", "你先去客厅看电视", "", 0.0),
    ("shashade", "沙沙的", "那怎么厨房里一直传来", "", 1.0),
    ("shashade", "杀杀的", "那怎么厨房里一直传来", "", 0.0),
    ("yanyanshishi", "严严实实", "现在关得", "", 1.0),
    ("yanyanshishi", "言言实事", "现在关得", "", 0.0),

    # Partial-select committed prefix
    ("neirong", "内容", "请核对方案", "真实", 1.0),
    ("neirong", "内绒", "请核对方案", "真实", 0.0),
    ("shangkou", "伤口", "我想先给它寻找处理好", "", 1.0),
    ("shangkou", "上口", "我想先给它寻找处理好", "", 0.0),
    ("chongwujijiubao", "宠物急救包", "快把箱子拿出来我车上有", "", 1.0),
    ("chongwujijiubao", "从无急救包", "快把箱子拿出来我车上有", "", 0.0),

    # Continuity after accusing / hiding animal
    ("pianwo", "骗我", "那你刚才直接告诉我不就行了为什么要一直", "", 1.0),
    ("pianwo", "片我", "那你刚才直接告诉我不就行了为什么要一直", "", 0.0),
    ("manzhewo", "瞒着我", "那你直接跟我说啊刚才干嘛跟防贼一样", "", 1.0),
    ("manzhewo", "满着我", "那你直接跟我说啊刚才干嘛跟防贼一样", "", 0.0),

    # Context-aware verb continuation: 你有没有改 + 移除里面的代码
    ("yichulimiandedaima", "移除里面的代码", "你有没有改", "", 1.0),
    ("yichulimiandedaima", "一处理免得代码", "你有没有改", "", 0.0),
    ("yichu", "移除", "你有没有改", "", 1.0),
    ("yichu", "一处", "你有没有改", "", 0.0),

    # Mixed pinyin + proper noun
    ("woxiangyongcoremlzuohouxuanpaixu", "我想用 Core ML 做候选排序", "", "", 1.0),
    ("woxiangyongcoremlzuohouxuanpaixu", "我想用coreml做候选排序", "", "", 0.0),
]

X = np.stack([
    features(preedit, candidate, document_context, committed_prefix)
    for preedit, candidate, document_context, committed_prefix, _ in examples
])
y = np.array([label for *_, label in examples], dtype=np.float32)

# Two-layer MLP trained with ridge on the closed-form expansion is awkward;
# fit a tiny ReLU network with a few GD steps so Core ML stays ANE-friendly.
rng = np.random.default_rng(42)
W1 = rng.normal(0, 0.05, size=(HIDDEN, FEATURE_COUNT)).astype(np.float32)
b1 = np.zeros(HIDDEN, dtype=np.float32)
W2 = rng.normal(0, 0.05, size=(1, HIDDEN)).astype(np.float32)
b2 = np.zeros(1, dtype=np.float32)

def forward(batch):
    hidden = np.maximum(0.0, batch @ W1.T + b1)
    return (hidden @ W2.T + b2).reshape(-1), hidden

lr = 0.08
for epoch in range(400):
    pred, hidden = forward(X)
    err = pred - y
    loss = float(np.mean(err * err))
    # Gradients
    dW2 = (err[:, None] * hidden).mean(axis=0, keepdims=True)
    db2 = err.mean(keepdims=True)
    dhidden = err[:, None] * W2
    dhidden = dhidden * (hidden > 0)
    dW1 = (dhidden.T @ X) / len(X)
    db1 = dhidden.mean(axis=0)
    # L2
    dW1 += 0.002 * W1
    dW2 += 0.002 * W2
    W1 -= lr * dW1.astype(np.float32)
    b1 -= lr * db1.astype(np.float32)
    W2 -= lr * dW2.astype(np.float32)
    b2 -= lr * db2.astype(np.float32)
    if epoch % 100 == 0 or epoch == 399:
        print(f"epoch {epoch} mse={loss:.4f}")

pred, _ = forward(X)
print("train accuracy", float(np.mean((pred > 0.5) == (y > 0.5))))

root = Path(__file__).resolve().parents[1]
output = root / "Resources/InputMethod/CandidateRanker/VibeCandidateRanker.mlmodel"
builder = NeuralNetworkBuilder(
    input_features=[("features", datatypes.Array(FEATURE_COUNT))],
    output_features=[("score", datatypes.Array(1))],
)
builder.add_inner_product(
    name="hidden_fc",
    input_channels=FEATURE_COUNT,
    output_channels=HIDDEN,
    has_bias=True,
    W=W1,
    b=b1,
    input_name="features",
    output_name="hidden_preact",
)
builder.add_activation(
    name="hidden_relu",
    non_linearity="RELU",
    input_name="hidden_preact",
    output_name="hidden",
)
builder.add_inner_product(
    name="score_fc",
    input_channels=HIDDEN,
    output_channels=1,
    has_bias=True,
    W=W2,
    b=b2,
    input_name="hidden",
    output_name="score",
)
builder.spec.description.metadata.author = "Vibe Voice OSS"
builder.spec.description.metadata.shortDescription = (
    "Offline dialogue-aware Rime candidate scorer (256-d MLP)"
)
output.parent.mkdir(parents=True, exist_ok=True)
ct.utils.save_spec(builder.spec, str(output))

compiled = output.with_suffix(".mlmodelc")
if compiled.exists():
    shutil.rmtree(compiled)
subprocess.run(
    ["xcrun", "coremlcompiler", "compile", str(output), str(output.parent)],
    check=True,
)
print(output)
print(compiled)
