# 硬件可用性需求（评估会产出）

| 项 | 值 |
| --- | --- |
| 性质 | 需求文档；**未立项**，不占 phase、不 bump、不改实现 |
| 日期 | 2026-11-16 |
| 基线 | `v0.62.0`（`485129c9`）；以 P0/PH-64 开卡时 H0 记录的 sha 为准 |
| 输入 | Gemini 裸机生成契约提案、ChatGPT 硬件试点提案、[battle hw-1](../../battle/hw-1/verdict.md) |
| 结论 | 采纳“P0 → PH-64 → pilot”；freestanding 用“每单元 `nm -u` ⊆ 允许集”，不按容器名单；const vtable 全量；pilot 不占 phase |
| 关联 | [裸机提案](../proposals/ct-bare-metal-proposal.md)、[硬件试点提案](../proposals/ct-hardware-pilot-proposal.md)、[language-spec](../language-spec.md)、[bindings-and-patterns](../bindings-and-patterns.md)、[test/bindings](../../test/bindings/README.md) |

## 0. 结论摘要

- **P0（v0.62.1）**：先修“数组/const 的 vptr 静默坏 C”。这是 D-005 的静默坏 C，独立 patch，不塞进 PH-64。
- **PH-64（v0.63.0，`d=1`）**：`--freestanding` + 按需单元 + `--alloc` + const vtable；验收以**符号面**为准，不以容器名单为准。
- **硬件 pilot（不占 phase）**：PH-64 收口后做 P0（UART/GPIO/状态机）→ P1（ISR/DMA）；用真实板与厂商工具链；失败 no-go。
- **明确不采纳**：CT 作为唯一主语言、按容器名字禁、`Option/Result` “纯值可 freestanding”、条件 const、现在立 `layout(plain)` 语法、完整借用/类型检查器。

## 1. P0：静默坏 C 止血

### REQ-HW-001 — 数组与 const 的 vptr 静态初始化

| 项 | 值 |
| --- | --- |
| 优先级 | **P0** |
| 状态 | 采纳（需求；待实现） |
| 内容 | 带 trait 的局部/文件作用域数组、`[]` 推导、const 标量与 const 数组，初值必须生成合法 C，vptr 必须静态写入；不得出现顶层 `. __x_vptr = …` designator |
| 验收 | `ct` rc=0；`cc -std=c99 -Wall -Wextra -c` rc=0；const 标量/数组显式派发 `run rc=0`（不得 139）；`sizeof` 只多指针宽度；`check-all` 11/11 |
| 依赖 | 无；只改 ct-ast，L0/L1 不动 |
| 版本 | `v0.62.1`（fix，+PATCH） |
| 来源 | Gemini 提案 §3.1 + 证据席补充（const 标量同根因） |

### REQ-HW-002 — constructor、`[]` 与多维

| 项 | 值 |
| --- | --- |
| 优先级 | **P0** |
| 状态 | 采纳（需求；待实现） |
| 内容 | 带初值数组不得再发 `__attribute__((constructor))`；`[]` 不得生成空上界循环；多维 trait 数组在 `ct` 阶段硬错并给位置；无初值文件作用域数组仍走原路径（P0 不改变其运行语义） |
| 验收 | 带初值数组产物 constructor 计数为 0；`[]` 产物无 `__ct_i < ;`；多维 rc≠0 且不落 `.c`；无初值数组回归夹具全绿 |
| 依赖 | REQ-HW-001 同一 patch |
| 版本 | `v0.62.1` |
| 来源 | Gemini 提案 B1–B7 + 证据席 |

> P0 收口时允许 50 个 L0/L1 golden 各变 1 行 banner（版本 token）；这是版本规则，不是语义变化。新增夹具只进 `test/ast`，不重生成 L0/L1 语料。

## 2. PH-64：裸机生成契约

### REQ-HW-010 — `--freestanding` 的符号面契约

| 项 | 值 |
| --- | --- |
| 优先级 | **P1** |
| 状态 | 采纳（需求；待实现） |
| 内容 | `--freestanding` 下，每个生成单元的 `nm -u` 必须 ⊆ 允许集；默认允许集只含编译器内建、`--alloc` 映射和用户显式提供的运行时符号；不得隐式带 libc/heap；不得发 constructor；不得按容器名字禁 |
| 验收 | `cc -ffreestanding -nostdlib -c` 产物 `nm -u` ⊆ 允许集；默认集下 `Vec/Str/Option/Result` 要么不拉、要么给出明确硬错；允许集按目标工具链固定/归一化（`-O2`/FORTIFY 的 `bzero`、`__*_chk` 不得漏） |
| 依赖 | P0 收口 |
| 版本 | PH-64（`v0.63.0`，`d=1`） |
| 来源 | battle J-3；B 的符号面判据 + A 的保守默认 |

### REQ-HW-011 — std 单元按需

| 项 | 值 |
| --- | --- |
| 优先级 | **P1** |
| 状态 | 采纳（需求；待实现） |
| 内容 | `ct build --emit-c` 不再无条件发射 `Vec/Option/Result/Str`；只按实际使用/实例化拉取；不得依赖 `CT_STD_DIR`、cwd 或输入旁 `../lib/std` 的隐式发现来决定“拉不拉” |
| 验收 | 最小无容器程序产物只有自身 `.c`；`Option<int>` 只拉 `Option`，且其 `nm -u` 必须满足 REQ-HW-010；不得把四个单元一起塞进 `-nostdlib` 链接 |
| 依赖 | REQ-HW-010 |
| 版本 | PH-64 |
| 来源 | 证据席（四单元并非无条件，但不能依赖隐式路径） |

### REQ-HW-012 — `--alloc` 分配器契约

| 项 | 值 |
| --- | --- |
| 优先级 | **P1** |
| 状态 | 采纳（需求；待实现） |
| 内容 | `--alloc` 至少映射 `malloc/free`；可扩展 `realloc/calloc`；注入到所有生成单元；是否允许 `Str/Vec/Map/Option/Result` 由符号面决定，不设名字白名单 |
| 验收 | `ct build --alloc pvPortMalloc,vPortFree --emit-c` 后产物不含 `malloc/free` 未定义符号；`Str` 在映射后 `nm -u` 为空即可用；`Vec` 若仍剩 `fprintf/abort/memcpy` 等非允许符号则硬错，不静默链接；`own/delete`/装箱无 `--alloc` 时硬错 |
| 依赖 | REQ-HW-010/011 |
| 版本 | PH-64 |
| 来源 | battle J-3；Gemini S2 + 证据席（`Vec` 不止 realloc） |

### REQ-HW-013 — const vtable

| 项 | 值 |
| --- | --- |
| 优先级 | **P1** |
| 状态 | 采纳（需求；待实现） |
| 内容 | vtable 定义 `static const`；`__vptr`/`_iface.vt` 为 `const … *`；三处成套改，不做 `--freestanding` 条件 const |
| 验收 | `-Wall -Wextra` 零告警；vtable 进 `__DATA,__const`/`.rodata`；`sizeof` 不变；跨 TU const/non-const 链接/运行通过；7 条带类型文本的 gate 断言同步更新；17 个发射点逐一核对 |
| 依赖 | 可与 REQ-HW-010 并行开发，串行发版 |
| 版本 | PH-64 |
| 来源 | battle J-4；A 全量 + B 让步 |

### REQ-HW-014 — `layout(plain)`（延后）

| 项 | 值 |
| --- | --- |
| 优先级 | **P2** |
| 状态 | 延后（本波不立语法） |
| 内容 | 先把“镜像 wire/寄存器/共享内存结构体不得 adopt trait”写进文档；真实需求出现再评估语法 |
| 验收 | language-spec/指南有明确规则；无解析器/发射器改动 |
| 依赖 | 无 |
| 版本 | 不占 PH-64 |
| 来源 | Gemini S5 可裁项 + battle 判决 |

## 3. 硬件 pilot（验证项目，不占 phase）

### REQ-HW-020 — 参考工程

| 项 | 值 |
| --- | --- |
| 优先级 | **P1** |
| 状态 | 采纳（需求；PH-64 后执行） |
| 内容 | 一块真实 Cortex-M 板 + 厂商 HAL + 一个 RTOS 候选；CT 只做上层状态机/协议/驱动接口；底层 UART/GPIO/ISR/DMA 用 C shim；用 `--emit-c` 纳入厂商构建 |
| 验收 | P0：UART/GPIO/状态机在板上运行；P1：一个 ISR + 一个 DMA 通道通过 A1–A10；生成 C 与手写 C 的体积/周期/栈对比；失败 no-go |
| 依赖 | PH-64 收口；板卡/工具链 H0 冻结 |
| 版本 | 不占 phase；独立验证项目 |
| 来源 | ChatGPT 试点提案 + battle J-2 |

### REQ-HW-021 — 构建集成与可追溯

| 项 | 值 |
| --- | --- |
| 优先级 | **P1** |
| 状态 | 采纳（需求；随 pilot） |
| 内容 | 生成 C 进版本库；CT 版本钉死；用厂商 Makefile/CMake 编译；不替换工具链；升级必须 diff 生成 C |
| 验收 | 目标工具链直接编译生成 C；`ct -v`/sha 记录；生成 C 与二进制可追溯 |
| 依赖 | REQ-HW-020 |
| 版本 | 不占 phase |
| 来源 | 两份提案共同点 |

### REQ-HW-022 — 类型安全边界文档

| 项 | 值 |
| --- | --- |
| 优先级 | **P1** |
| 状态 | 采纳（文档需求；不新增检查器） |
| 内容 | 明确 CT 类型检查是部分/opt-in；`ct check --types` 覆盖有限；硬件代码仍须目标 C 编译器告警、MISRA/静态分析、人工审查 |
| 验收 | language-spec/README 有明确“不保证完整类型安全”段落；pilot 验收包含 `-Wall -Wextra` 与静态分析 |
| 依赖 | 无 |
| 版本 | 文档，不占 phase |
| 来源 | ChatGPT 评估 |

### REQ-HW-023 — ISR/DMA/Cache 边界

| 项 | 值 |
| --- | --- |
| 优先级 | **P1** |
| 状态 | 采纳（边界需求） |
| 内容 | ISR 入口、DMA buffer 生命周期、Cache/MPU、屏障仍由 C/汇编与驱动设计负责；CT 的 `own/Drop` 不单独承担 |
| 验收 | pilot P1 的 A3/A4 通过；文档列失效矩阵；ISR 不调用可能分配/清理的 CT 函数 |
| 依赖 | REQ-HW-020 |
| 版本 | 不占 phase |
| 来源 | ChatGPT 评估 + 证据席 |

### REQ-HW-024 — 厂商 SDK/头文件隔离

| 项 | 值 |
| --- | --- |
| 优先级 | **P1** |
| 状态 | 采纳（边界需求） |
| 内容 | 不要求 CT 解析完整 CMSIS/厂商头；用 C shim 暴露干净声明；`#include`/属性/汇编走 C 侧 |
| 验收 | pilot 的 UART/GPIO 只依赖 shim；不把整棵 SDK 头喂给 CT；属性/中断入口在 C 侧 |
| 依赖 | REQ-HW-020 |
| 版本 | 不占 phase |
| 来源 | 两份提案共同点 |

### REQ-HW-025 — 功能安全/工具资格（延后）

| 项 | 值 |
| --- | --- |
| 优先级 | **P2** |
| 状态 | 延后（不在本波） |
| 内容 | 安全关键项目需要 tool qualification、生成物追溯、MISRA/覆盖率证据；本波不作安全认证声明 |
| 验收 | 有需求时另立评估；当前文档明确“不适用于安全关键生产” |
| 依赖 | 无 |
| 版本 | 不占 phase |
| 来源 | ChatGPT 评估补充 |

## 4. 顺序与版本

| 步 | 内容 | 版本 |
| --- | --- | --- |
| 0 | 修正 AGENTS §0.3 的 `d` 表述；确认 PH-64 为 `v0.63.0, d=1` | 文档 |
| 1 | P0 patch（REQ-HW-001/002） | `v0.62.1` |
| 2 | PH-64（REQ-HW-010…013 + 门禁/文档） | `v0.63.0` |
| 3 | 硬件 pilot P0（REQ-HW-020/021/022/024） | 不占 phase |
| 4 | 硬件 pilot P1（REQ-HW-023） | 不占 phase |

PH-64 的 S5/`layout(plain)` 不在本波；pilot 失败即 no-go，不调阈值凑绿。

## 5. 不采纳 / 不承诺

| 项 | 处置 |
| --- | --- |
| CT 作为唯一主语言 | 不采纳；底层 C/汇编保留 |
| 按容器名字禁 freestanding | 不采纳；改用符号面 |
| `Option/Result` 是纯值、freestanding 可用 | 不采纳；实例化会发 `fprintf/abort`，按符号面判 |
| 条件 const vtable | 不采纳；全量 const |
| 现在就立 `layout(plain)` 语法 | 延后；先文档 |
| 完整借用检查器/完整类型检查器 | 不承诺；不属于本需求 |
| 所有 MCU/BSP 一次覆盖 | 不承诺；pilot 只覆盖 H0 板卡 |
| 安全认证 | 延后；另立 tool qualification 评估 |

## 6. 需求来源与状态说明

- **采纳**：需求成立，允许进入 P0/PH-64/pilot；不等于已实现。
- **延后**：有触发条件，当前不排期。
- **不采纳**：已有证据否定，不再作为需求。
- 本文件不是 phase 卡；P0/PH-64 开卡时仍需各自的 `version-minor`、任务四要素、退出判据与红证。
