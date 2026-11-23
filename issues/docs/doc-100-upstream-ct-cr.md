# DOC-100 · 上游 CR 草案：主规范语言名书写 `CT → Ct`

| 项 | 值 |
| --- | --- |
| 模块 | docs（跨仓提案；本仓只存放草案，不写上游） |
| 定性 | 主规范 CR（书写一致性，不改条款语义） |
| 严重度 | Low |
| 锚点 | `ef88bb86`（`v1.0.0` 后；2026-11-24） |
| 依据 | [DOC-94](doc-94-ct-spelling.md)、[DOC-98](doc-98-ct-language-name.md)、[命名一致性评审](../../docs/reviews/naming-consistency-2026-11-24.md) |
| 状态 | open |
| 处置证据 | **accepted（2026-11-24 所有者：先提上游 CR；本仓不代写上游仓）** |

## 1. 问题

本仓已按 DOC-94 / DOC-98 把活跃散文的语言名统一为 **`Ct`**（命令/后缀/仓库名仍为 `ct`）。
但主规范（`spec-version 1.18.0`）仍以 **`CT`** 指代同一语言，导致两处无法本地修正：

| 位置 | `CT` 次数 | 为什么不能改 |
| --- | --- | --- |
| `AGENTS.md:46`（`spec:begin…end` 生成块） | 2 | `g0` 校验 `docs/spec` 的 sha256 与块头一致；手改即红 |
| `docs/spec/ai-coding-workflow.md`（全文副本） | 7 | 必须与主规范逐字一致；`g0` / `g9` |

结果：项目内“活跃散文禁止裸 `CT`”与上游“条款里写 `CT`”同时成立，读者会在同一棵树里看到两种写法。

## 2. 提案（逐行原文 → 替换后）

> 目标：只把指代该语言的 `CT` 改为 `Ct`；**不改任何条款语义、编号、文件名**。

1. `docs/spec/ai-coding-workflow.md:178`

```text
- **CT 包另有专用规范。** `methodology/ct-package-coding-general.md`（CG-1…CG-7）收编对任何 CT 包都成立的编码条款；它只适用于 CT 包，不进生成块的判据摘录，也不改变主规范对其他项目的要求。
+ **Ct 包另有专用规范。** `methodology/ct-package-coding-general.md`（CG-1…CG-7）收编对任何 Ct 包都成立的编码条款；它只适用于 Ct 包，不进生成块的判据摘录，也不改变主规范对其他项目的要求。
```

2. `docs/spec/ai-coding-workflow.md:1347`

```text
- │   ├── ct-package-coding-general.md    # CT 包编码通用条款（CG-1…CG-7，仅 CT 项目）
+ │   ├── ct-package-coding-general.md    # Ct 包编码通用条款（CG-1…CG-7，仅 Ct 项目）
```

3. `docs/spec/ai-coding-workflow.md:1549`

```text
- | 18 CT 包编码通用条款 | 任何 CT 包都适用：……
+ | 18 Ct 包编码通用条款 | 任何 Ct 包都适用：……
```

4. `AGENTS.md:46` 生成块（由 `sync-agents.sh` 从主规范生成，不手改）

```text
- | CT 包编码通用条款（仅 CT 项目）：……
+ | Ct 包编码通用条款（仅 Ct 项目）：……
```

合计 **7 次**（`grep -o '\bCT\b' docs/spec/ai-coding-workflow.md | wc -l` = 7；`AGENTS.md` 块内 2 次）。

## 3. 为什么值得提

- **单一事实源**：下游已裁定语言名写 `Ct`；上游继续写 `CT` 会让每个纳管项目的副本都保留一处冲突写法；
- **不改语义**：纯书写，不涉及 CG-1…CG-7 的判据、编号或文件名（上游文件名仍为 `ct-package-coding-general.md`）；
- **成本一次**：主规范定版 → 项目侧 `sync-agents.sh --write` → 生成块与 `docs/spec` 同步更新，`g0` / `g9` 绿。

## 4. 范围与非目标

- 只改指代该语言的 `CT`；`CT_*` 环境变量、`CTC_VERSION`、`ct` 命令、`.ct` 后缀、`ct-pkg` 等一律不动；
- 不改 CG-1…CG-7 的条款文字、编号与文件路径；
- 不改历史版本说明；
- 不新增/删除方法论章节。

## 5. 落地与回退

| 阶段 | 动作 |
| --- | --- |
| 上游 | 所有者把 §2 提交为主规范 CR；主规范按自身流程定版（PATCH 级书写修正即可） |
| 本仓 | 定版后运行 `sync-agents.sh --write AGENTS.md`，同一次提交刷新生成块与 `docs/spec/` 副本，跑 `g0` / `g9` |
| 回退 | 单次同步提交即可回滚；不影响语言、构建与门禁行为 |

若上游不采纳：本仓把这两处登记为**已知上游例外**（已有做法见 DOC-99 的“上游不改”条目），不阻塞 v1.1。

## 6. 关联

- [DOC-94](doc-94-ct-spelling.md)（`CT → Ct` ratchet）
- [DOC-98](doc-98-ct-language-name.md)（语言名统一 `Ct`）
- [命名一致性评审](../../docs/reviews/naming-consistency-2026-11-24.md)
- `AGENTS.md` §11.5（落库：一版一同步）
