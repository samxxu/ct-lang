# DOC-91 · C Shim Contract 正式规范

| 项 | 值 |
| --- | --- |
| 模块 | docs（C 互操作 / 嵌入式） |
| 定性 | 文档缺口 |
| 严重度 | Medium |
| 锚点 | v0.88.3（2026-11-22，外部架构评估） |
| 文件 | [guide-for-c-programmers](../../docs/guide-for-c-programmers.md)、[patterns](../../docs/patterns.md)、`examples/**/shim` |
| 状态 | deferred |
| 处置证据 | **已立项（v1.1；不阻塞 v1.0）** |

## 现象

C Shim 已经是事实上的架构模式（examples、test/baremetal-renode、厂商 SDK 接入），但没有正式契约：
命名、头文件边界、所有权与释放、错误码、ISR/线程上下文、对齐/调用约定、版本兼容各自约定，
新成员只能从样例反推。

## 期望

成文 `docs/c-shim-contract.md`（或作为 guide 的独立附录），至少覆盖：

1. **命名与头文件**：`board_*` 前缀、`<base>.shim.h` 的包含边界、禁止把 CT 内部类型带进 shim；
2. **所有权**：buffer 的 `const`/长度/归属，提交后与完成后的归还规则；
3. **错误码**：返回码与 `Result` 的转换边界，禁止 sentinel 值；
4. **上下文**：ISR / 任务 / 启动阶段的允许调用集；`no_alloc` / `no_block` / `isr_safe`
   先以**文档标注**表达，不新增语言关键字；
5. **ABI**：固定宽度整数、opaque handle、对齐与调用约定、版本兼容；
6. **测试**：host mock + Renode 冒烟各一例；shim 变更的回归清单。

## DMA / 异步（硬条款）

- **提交即转移**：`board_dma_submit(buf, len, cb)` 返回后，buffer 归驱动所有；CT 侧不得
  `release`、重分配、写入或移动，直到完成回调返回。
- **完成即归还**：回调返回后所有权回到 CT；只有此时才允许释放或复用 buffer。
- **上下文**：回调必须声明运行在 ISR 还是任务上下文；ISR 上下文禁止分配、阻塞、Drop 与
  引用计数释放；需要延后处理时只投递事件。
- **借用视图**：不得把 `Str`/切片/句柄的借用视图跨过提交点保存；需要跨异步的数据必须是
  owning 句柄，且其寿命覆盖到完成回调。
- **证据**：真搬运仍归 [TEST-22](../../issues/testing/test22-dma-real-transfer-hardware-gated.md)
  （hardware-gated）；契约只约束 API 责任，不把模拟器寄存器测试当作真板证明。

## 非目标

- 不设计 C ABI 导出选择（P39 C 方案待评审）；
- 不新增 `isr_safe` 等语言关键字；
- 不承诺厂商 SDK 全量兼容。

## 验收

- 文档入库，`check-docs` 链接可解析；
- 现有 shim（examples/47、test/baremetal-renode）在文中逐一登记；
- 至少一个 host + 一个 Renode 例子指向契约条款；
- 无代码改动。

## 排期

v1.1；不阻塞 v1.0。与 [DOC-92](doc-92-c-interop-semantics-matrix.md) 同批评估。


## 处置（REQ，2026-11-22）：deferred

- 触发：**v1.1 文档窗口**
- 范围：C Shim Contract 成文
- 依据：本卡「处置证据」已标 `v1.1` 立项、不阻塞 v1.0；v1.0/v1.1 冻结期不排工。
- 触发时：改回 `open`，按本卡验收执行；不提前扩围。
