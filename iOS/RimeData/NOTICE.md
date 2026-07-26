# Rime data notice

`pinyin_simp.dict.yaml` is from
[`rime/rime-pinyin-simp`](https://github.com/rime/rime-pinyin-simp) and is
distributed under the Apache License 2.0. The complete license is included as
`LICENSE.rime-pinyin-simp.txt`.

`default.yaml` and `vibe_pinyin.schema.yaml` are original Vibe Voice OSS
configuration files.

`vibe_pinyin_trad_pinyin.schema.yaml` and `vibe_zhuyin_trad.schema.yaml` are
original Vibe Voice schema wrappers around librime's standard OpenCC and
traditional-output features. The bundled dictionary remains the Apache-2.0
`rime-pinyin-simp` data; users may import additional Rime-format dictionaries
from the app settings into their private App Group container.

`vibe_phrases.dict.yaml` and `vibe_emoji.dict.yaml` are original Vibe Voice
curated seed data. They contain Unicode text only; no third-party emoji artwork
is redistributed. OpenMoji can be considered for a future visual picker, but
its artwork requires CC BY-SA 4.0 attribution and share-alike terms.

The keyboard links a core-only `librime.xcframework` built by
`scripts/prepare-librime-ios.sh` from the official librime 1.16.1 release. No
librime Lua, octagram, predict, legacy-plugin, or other external plugin source
is fetched or linked. Licenses for librime and its statically linked
dependencies are included under `iOS/Vendor/Licenses/`.

marisa-trie, reached through OpenCC, is dual-licensed under BSD-2-Clause and
LGPL-2.1. Vibe Voice OSS takes it under BSD-2-Clause. See `iOS/Vendor/README.md`
for how the vendored archives are built and verified.
