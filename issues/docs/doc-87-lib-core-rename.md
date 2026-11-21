# DOC-87 · `lib/std` → `lib/core` 改名（待所有者书面确认）

| 项 | 值 |
| --- | --- |
| 模块 | docs / 工具链命名 |
| 定性 | 改名（跨仓兼容） |
| 严重度 | Medium |
| 锚点 | v0.88.0（2026-11-21） |
| 依据 | [外部评审与惯用卡评估](../../docs/reviews/2026-11-21-v088-external-review-eval.md) §1 |
| 状态 | **待确认（仓库未找到所有者签字/ADR）** |

## 现象

外部报告称“所有者已定：`lib/std` → `lib/core` + `namespace core`”。本仓复核：

- 只有 2026-11-15 的 [同名核查](../../docs/review/builtin-layer-vs-std-package-name-check.md)
  提出兼容方案（`CT_CORE_DIR` 优先、`CT_STD_DIR` 回退）；
- 没有 ADR、phase 卡或 owner 签字记录；
- `lib/` 下目前只有 `std/`；`lib/std/README.md` 明确“不是整个 std 的新家”。

因此**不能按“已定”直接改名**；需所有者书面确认后再执行。

## 若确认，执行口径（建议）

1. `git mv lib/std lib/core`；同步 `CT_STD_DIR` → `CT_CORE_DIR` 优先，保留一个 MINOR 回退窗；
2. 机械替换：`selfhost/**`、`docs/**`、`test/**`、`examples/**` 的 `lib/std` 引用；
3. `namespace core` 只用于**新增**单元；内置层保持根命名空间（D29-3），避免 `Vec`/`Map` 拼写变化；
4. 一次 commit；`grep -rn 'lib/std'` 清零；`check-all` 绿；
5. 回滚：单 commit revert；保留 `CT_STD_DIR` 兼容期。

## 验收

- 所有者确认（ADR 或签字）在案；
- `ct build` 与 `ct build -I lib/core` 均可用；旧 `lib/std` 引用在兼容窗内仍可解析；
- 文档/脚本无残留；`check-alls` 绿；
- 单提交回滚。

## 非目标

- 不把外部 `std` 包的 `namespace std::*` 改名；
- 不改内置层的根命名空间（`Vec`/`Map`/`String` 等拼写不变）；
- 不在确认前动任何文件。

## 关联

- [同名核查](../../docs/review/builtin-layer-vs-std-package-name-check.md)
- [D-014](../../docs/decisions/D-014.md)、[DOC-86](doc-86-readme-v088-rewrite.md)
