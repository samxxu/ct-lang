# battle/hw-1 — 硬件提案合并：采纳哪些点、按什么顺序

| 字段 | 值 |
| --- | --- |
| 争点 | 两份硬件提案（[裸机生成契约](../../docs/proposals/ct-bare-metal-proposal.md)、[硬件试点](../../docs/proposals/ct-hardware-pilot-proposal.md)）合并后：P0 patch 与 PH-64 的顺序、`--freestanding`/`--alloc` 边界、const vtable 范围、pilot 的定位 |
| 当前 HEAD | `v0.62.0`（`485129c9`）；工作树含未提交的 Pkg 诊断改动，不作为证据 |
| 触发理由 | 用户要求结合 ChatGPT/Gemini 两份意见开评估会、battle，并形成新需求文档 |
| proposer | REQ（主张 A） |
| opposition | REVIEW（主张 B） |
| judge | EDITOR |
| 禁止触碰 | `selfhost/**`、`test/**`、`docs/proposals/**`、`docs/design/**`；只写 `battle/hw-1/` 与 `/tmp` |

## 位置 A（主张）

1. **先 P0 patch**：数组/const 的 vptr 静态初始化；带初值数组不再走 constructor；多维 trait 数组硬错；既有 golden 零变化。
2. **P0 后 PH-64**，再做硬件 pilot。P0 修静默坏 C，PH-64 提供裸机生成契约，pilot 验证两者；不能让 pilot 先替语言设计试错。
3. **freestanding 从严**：`Vec/Map/Str` 在 freestanding 下硬错（`--alloc` 也不能带回）；`Option/Result` 按需拉；无 constructor；`own/delete`/装箱无 `--alloc` 硬错。
4. **`--alloc` 只收 malloc/free**；`Vec` 需要 realloc，故不在 freestanding 支持；要容器走托管模式。
5. **const vtable 一次改到底**（所有模式），不搞 `--freestanding` 条件 const；接受 golden 全量重生成。
6. **`layout(plain)` 暂不立语法**；先把“镜像结构体不得 adopt trait”写进文档。
7. **pilot 不是 phase**：PH-64 收口后做 P0（UART/GPIO/状态机）→ P1（ISR/DMA）；失败 no-go。

## 位置 B（反对）

1. P0 patch 先做，但 **pilot 应在 PH-64 之前**：先用真实板暴露 freestanding/alloc/const 需求，再冻结契约。
2. freestanding 不应一刀切禁容器：`Str` 只用 malloc/free，若 `--alloc` 映射它们应可用；`Vec` 需要 realloc 的话把 alloc 扩成 malloc/free/realloc，而不是禁容器。
3. const vtable 条件化（仅 freestanding）可避免全量 ABI/golden 变更；或先 pilot 再决定。
4. PH-64 的 S1/S2/S3 是 CLI/生成契约，不是语言特性；`layout(plain)` 可以先做文档，不应阻塞。
5. 先做 P0 + pilot，再决定 PH-64 是否拆成两个小相（freestanding/alloc 与 const vtable）。

## 判据

| ID | 判据 | 通过方式 |
| --- | --- | --- |
| J-1 | P0 是否独立成立、范围是否最小、既有 golden 是否零变化 | P0 夹具 + `cc -Wall -Wextra` + golden diff |
| J-2 | 顺序：P0 → pilot → PH-64，还是 P0 → PH-64 → pilot；以“先证据后契约”还是“先契约后验证”评分 | 顺序决策记录 + pilot/PH-64 证据 |
| J-3 | freestanding 容器/allocator 边界是否可机械验收；是否允许 `Str`/`Vec` 在 `--alloc` 下使用 | freestanding 夹具与 `nm -u`/`cc -nostdlib` |
| J-4 | const vtable 全量 vs 条件：ABI 风险、golden 成本、跨模式链接 | golden 差异与跨模式链接夹具 |
| J-5 | pilot 是否占 phase 号；失败/通过如何影响 PH-64 | phase/pilot 定义与 no-go 记录 |
| J-6 | 新需求文档是否可执行：每条 REQ 有优先级、验收、依赖、来源，且不把“提案”写成“已承诺” | 需求文档逐条字段与验收命令 |

## 证据要求

按 §7.7 E1–E5：完整命令/原始输出、`file:line`、可证伪预测、代价量化、对对方最强论点的 steelman。重点复现 P0 坏 C、const vptr、constructor、四单元链接、vtable 可写、`Vec` 的 realloc / `Str` 的 malloc/free、`-ffreestanding -nostdlib` 现状。
