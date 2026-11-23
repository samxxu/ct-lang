---
phase-id: v0-PH-63
version-minor: 63
---

# Phase 63 · 删除 `vendor/` 支持（v0-PH-54 S7）

**状态：完成（v0.62.0）**

| 项 | 值 |
| --- | --- |
| 状态 | **完成**（v0.62.0） |
| 依据 | [v0-PH-54 S7](../../roadmap.md#ct-pkg-共享库包体系phase-54s0s7)；[提案 §10 S7](../../proposals/ct-pkg-shared-store.md)；[需求 SP-029](../../planning/ct-pkg-shared-store-requirements.md) |
| 版本位 | `version-minor: 62`；收口 **v0.62.0**（v0-PH-63，d=1） |
| 只动 | `selfhost/ct-ast/tool/pkg/Pkg.h.ct`、`test/pkg/**`、`docs/**` |

## 1. 目标

兼容期（v0.58 之后至少两个 MINOR）已过，删除 `vendor/` 读写：

- `ct build` 不再扫描 `vendor/`；
- v1 lock 直接报错并指向 `ct migrate`；
- `ct get` 写入共享 store、只写 v2 lock，不再 `copy_tree` 到 `vendor/`；
- `ct install` / `verify` / `update` 只读 store；
- `ct migrate` 保留为一次性迁移桥，可读旧 `vendor/` 并写 v2。

## 2. 验收

| # | 判据 |
| --- | --- |
| S7-1 | 无 lock 工程不读 `vendor/`；显式 `-I` 仍可用 |
| S7-2 | v1 lock 在 build / get / install / verify / update 都 RC!=0，并含 `run 'ct migrate'` |
| S7-3 | `ct get` 不创建、不写 `vendor/`；只写 store + v2 lock |
| S7-4 | `ct install` / `verify` / `update` 对 store 工作，不再读 vendor |
| S7-5 | `ct migrate` 仍能把手工构造的 v1 + vendor 迁到 store，移走 vendor 后可 build |
| S7-6 | `test/pkg` 141/0；`check-all` 11/11 |

## 3. 结果

- `Pkg.h.ct` 删除 `vendor/` 写入、v1 读回退、无 lock 的 pin 重解与 vendor `-I` 输出；
- 缺 `publisher` / `ns-root` 的清单在 store 提交处失败；
- `test/pkg` 改为 store/v2 语义：store 断言、v1 负例、手工 v1→migrate→移走 vendor 的正例；
- 文档（package-guide / tutorial / glossary / README）删除兼容期措辞。
