# iOS 0.7.0 候选重排器

键盘的候选来源始终是 Rime。`CandidateRanker` 只允许在 Rime 已给出的候选集合内调整顺序，不能生成或替换文本。

## 运行时分层

- iOS 17/18/26：先立即显示 Rime 候选，后台异步执行重排；请求 ID 过期时丢弃结果。
- 没有模型、模型加载失败或内存压力：`PassthroughCandidateRanker` 保留 Rime 顺序，并可应用本地接受次数。
- iOS 26：Input Playground 可由用户主动触发“整句增强”，调用 Apple Foundation Models；输入法扩展不在每次按键时调用该模型。

中文键盘的空格现在只作为拼音音节分隔符，不会提前提交当前音节；Rime 会继续累积整段拼音（例如 `wodaolefangandexianchang`），直到用户点选候选或按 Return。这样整句候选和 Core ML scorer 才能看到完整上下文。

## 对话上下文

键盘扩展通过 `UITextDocumentProxy` 读取插入点附近的 `documentContextBeforeInput`、`documentContextAfterInput` 和 `selectedText`，组合成最多 240 个字符的内存窗口。该窗口随当前输入刷新，进入 Core ML 的整句/候选联合特征；不会写入学习数据库，也不会上传。没有上下文（系统限制、密码框或用户关闭完整访问）时，模型自动退化为仅使用当前拼音和 Rime 候选。

## Core ML 模型契约

首轮模型已随 App 和键盘扩展内置，资源名为 `VibeCandidateRanker.mlmodelc`。可选下载模型放在 App Group：

`Models/CandidateRanker/downloaded/VibeCandidateRanker.mlmodelc`

内置模型是一个可离线运行的句级 scorer，输入 128 维特征：候选元数据、候选字符/二元组哈希，以及完整拼音 preedit 与候选文本的联合哈希，输出一个 score。模型只排序 Rime 已产生的句级候选，不生成文本；因此 Rime 负责可编辑的拼音解码，Core ML 负责整句上下文重排。后续训练模型可以保持相同 Core ML 输入/输出契约，下载模型必须先校验 manifest 中的 SHA-256、版本和最低系统版本，再原子替换目录。

## 个性化数据

当前只在内存中记录“前缀 + 被接受候选”的增量计数，不保存原始输入文本；下一轮接入 App Group SQLite 时保持同一数据边界，并提供清除学习数据入口。
