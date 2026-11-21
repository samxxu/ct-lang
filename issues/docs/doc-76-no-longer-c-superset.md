# DOC-76 · 兼容承诺“不再是 C 超集”未三处同步

| 项 | 值 |
| --- | --- |
| 模块 | docs（README / spec / roadmap） |
| 定性 | 文档缺口（v1.0 兼容承诺） |
| 严重度 | Medium |
| 锚点 | v0.83.3（2026-11-21） |
| 文件 | [README.md](../../README.md)、[language-spec.md](../../docs/language-spec.md)、[roadmap.md](../../docs/roadmap.md) |
| 状态 | **已完成（2026-11-21：spec §1.2 权威段 + README/roadmap 同步 + 内容一致性断言）** |

## 进展（2026-11-21）

- **spec §1.2「兼容承诺（v1.0 起不再自称 C 超集）」**：三段承诺表（仍接受 / 不再承诺 /
  旧工程迁移）+ 四类常见偏离表 + 弃用窗口表。
- **弃用窗口**（用户精修项）：`T a[]` v0.x 警告 → v1.0 硬错；`box<T>` → `Box<T>`（v1.0 弃用、
  v1.1 删除）；`std::str::String` → `CharStr`（包发布后一个 MINOR）；`lib/std` 根拼写 →
  `lib/core`（一个 MINOR）。窗口结束即硬错，不自动续期。
- **README / roadmap**：同一段承诺措辞，链接 spec §1.2。
- **内容一致性断言**（用户精修项）：三处各带
  `<!-- ct-compat: not-c-superset claim=v1.0-not-c-superset spec=1.2 -->`；
  `check-docs` 的 `check_compat_claim` 校验三处 claim 相同、`spec=1.2` 能在规范里解析到标题、
  三处都含「不再自称 C 超集」。负例自测：改 roadmap 的 claim 即报两条红（值错 + 跨文件不一致）。
- 措辞按**硬版**口径：不再承诺 C 全集（函数式宏、strict 边界 `#include`、旧 L1/L2 管线语法），
  不以「C 代码原样全收」为目标。

## 现象

README / spec 目前没有明确写出“v1.0 起不再是 C 超集”的兼容承诺；用户仍可能按 C 超集理解。

## 期望

1. 三处同步同一口径：
   - 哪些 C 形态仍接受（pass-through / C 机制）；
   - 哪些不再承诺（旧内部语法、L1/L2 管线相关）；
   - 旧工程迁移建议（用 v0.x 编译器 / `ct migrate`）；
2. 措辞与 v1.0 退出条件一致，不承诺未实现能力；
3. 加一条 check-docs 断言，防止三处漂移。

## 验收

- 三处文本存在且语义一致；
- check-docs 能拦住“只改一处”。

## 关联

- [v1 路线 §1.5](../../docs/planning/v1-release-plan.md#L57-L71)、[2026-11-21 评估](../../docs/reviews/2026-11-21-v1-campaign-eval.md)
