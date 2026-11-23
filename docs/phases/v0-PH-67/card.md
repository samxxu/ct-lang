---
phase-id: v0-PH-67
version-minor: 67
---

# Phase 67 — 无真机硬件能力扩展（时钟 / 第二厂商 / RTOS / DMA / GDB）

> **状态：完成**（2026-11-18 收口；`v0.66.0`；R1–R5 全绿，R6 收口）。
> **依据**：[TEST-21](../../../issues/testing/test21-baremetal-renode-stm32f4.md)、
> [hardware-readiness-requirements](../../planning/hardware-readiness-requirements.md)（REQ-HW-010/011）。
> **前置**：v0-PH-66 收口（`v0.65.1`）；TEST-21 已在 CI 绿。
> **纪律**：不收口不 bump；tag 按 6.7 V-7；真机项只登记、不代做。

## 0 卡片字段（冻结）

| 项 | 值 |
| --- | --- |
| 编号 | v0-PH-67 |
| 目标 | 在没有真实板卡的条件下，把裸机能力从"能启动/打 UART"扩到：正确时钟树、第二家厂商、RTOS、DMA 代码面、GDB 联调 |
| 范围 | 仅模拟器（Renode，CI Linux）与仓库内夹具；不碰真实板卡、不伪造 pilot 证据 |
| 交付物 | `test/baremetal-renode/**` 扩展、CI job、`test/ast/p67_*.sh`、docs |
| 任务清单 | §4（R1–R6，共 6 项） |
| 退出判据 | E67-1…E67-6（§5） |
| 依赖 | Renode 1.17（CI 下载 portable）、arm-none-eabi-gcc、FreeRTOS-Kernel（CI 下载到 `.temp`） |
| version-minor | 66（v0-PH-67，`d=1`，见 AGENTS §0.3） |
| 已知风险 | R67-1…R67-4（§7） |

## 1 需求与边界

### 1.1 一句话

在**没有真机**的前提下，把"CT 生成的裸机固件"从 Hello-UART 推进到
"配时钟、跑 RTOS、动 DMA、能 GDB 调试、还能换一家 MCU"。

### 1.2 非目标

- 不做真实板卡验证（REQ-HW-020 的 pilot 仍属外部依赖）；
- 不把 FreeRTOS/Zephyr 纳入仓库构建路径：只在 CI 里下载到 `.temp/`，产物不入库；
- 不声称 DMA 的真实搬运已验证（寄存器级配置绿不等于硅片行为）；
- 不改 `--freestanding` 的产物契约（无系统头、无 libc）。

### 1.3 关键决策

| 编号 | 决策 | 理由 |
| --- | --- | --- |
| D67-1 | 所有模拟器验证跑 CI 的 Linux x86_64 | 本机 macOS 的 Renode 只能由用户在沙箱外运行，夜间代理不能依赖它 |
| D67-2 | FreeRTOS 源码 CI 现取到 `.temp/`，不入库 | 第三方依赖不进仓库、不进构建路径 |
| D67-3 | DMA 只验寄存器序列与编译面，真实搬运登记为 hardware-gated | Renode 的 DMA 模型覆盖有限，不能冒充真机 |
| D67-4 | 第二厂商选 nRF52840（Renode 官方平台） | 无需硬件，能验证不同内存图/UART 基址 |

## 2 环境约束（夜间执行必须遵守）

1. **不得请求沙箱外权限**；本机 `renode` 只在用户终端可用，代理不调用它。
2. 所有 Renode 运行走 CI：push 后 `gh run watch`，失败读原始日志。
3. 下载只落 `.temp/`（已 gitignore）；不得 vendored 进 `test/**`。
4. 真机相关项（DMA 真实搬运、烧录、电气特性）只登记 issue，不写"已验证"。

## 3 验收与证据

每个 R 任务按 T-7：先 `test(...) 红`（含 `baseline: <sha>` 与原始输出），再实现。
红证以 CI 原始日志或本地可复跑命令为准；本地不能跑 Renode 时，红证用 CI 失败日志。

## 4 任务清单（冻结）

| 任务 | 交付物 | verify | effort | 备注 |
| --- | --- | --- | --- | --- |
| R1 时钟树 | `test/baremetal-renode/clock.c/.h`；board 用 PLL 168MHz 并重算 BRR | `bash test/ast/p67_clock.sh` → `OK p67/clock (168MHz, BRR consistent)` | M | 读回 RCC 寄存器算频率 |
| R2 nRF52840 | `test/baremetal-renode/nrf52/**`（linker/startup/UART@0x40002000） | `bash test/ast/p67_nrf52.sh` → `OK p67/nrf52` | M | Renode `nrf52840` 平台 |
| R3 FreeRTOS | `test/baremetal-renode/freertos/**` + CI 取源码 | `bash test/ast/p67_freertos.sh` → `OK p67/freertos (2 tasks, queue)` | M | `.temp/FreeRTOS-Kernel` |
| R4 DMA | `test/baremetal-renode/dma.c/.h`（DMA1 Stream6 USART2_TX 描述符） | `bash test/ast/p67_dma.sh` → `OK p67/dma (registers)` | M | 真实搬运登记 issue |
| R5 GDB | `test/baremetal-renode/gdb.sh`（Renode GDB server + `arm-none-eabi-gdb` 断点） | `bash test/ast/p67_gdb.sh` → `OK p67/gdb (breakpoint main)` | S | 需 CI 装 gdb |
| R6 收口 | 卡内 §9、docs、版本 v0.66.0、tag | `no-test: 收口文档与版本移动` | S | REV 签字后收口 |

## 5 退出判据

| 编号 | 判据 |
| --- | --- |
| E67-1 | `p67/clock` 绿：读回 PLL 配置得 168MHz，BRR 与 UART 时钟一致 |
| E67-2 | `p67/nrf52` 绿：nRF52840 内存图上启动并输出 `boot ok` |
| E67-3 | `p67/freertos` 绿：两个任务经队列交替输出，顺序确定 |
| E67-4 | `p67/dma` 绿：DMA 寄存器序列符合参考手册；真实搬运不在本相声称 |
| E67-5 | `p67/gdb` 绿：GDB 在 `main` 断点命中并读回 PC |
| E67-6 | `check-all` 11/11、`check-ast` 全绿；版本 `v0.66.0` + annotated tag；真机项全部登记 issue |

## 6 风险

| 编号 | 风险 | 缓解 |
| --- | --- | --- |
| R67-1 | Renode 的 DMA 模型缺失/不全 | 只验寄存器，不声称搬运；必要时降级为编译面 + 单测 |
| R67-2 | FreeRTOS 端口在 Renode 上时序不稳 | 用队列与信号量而非裸延时，输出顺序确定化 |
| R67-3 | CI 时长增长 | 每个 job 只加一个探针；必要时拆成独立 workflow |
| R67-4 | 夜间无人值守卡住 | 每步有超时；失败即停并留原始日志，不重试到天荒地老 |

## 7 迁移备注

phase-ID 迁移（主规范 1.16/1.17 的 `v0-PH-*`）尚未开始（见
[phase-migration-blockers](../../planning/phase-migration-blockers.md)）。本卡沿用现有
legacy 布局 `docs/phases/v0-PH-67/card.md`；迁移启动时按 PN-5 机械改名，不单独预迁移。

## 8 收口对照表（2026-11-18，v0.66.0）

| 判据 | 命令 | 结果 |
| --- | --- | --- |
| E67-1 | `bash test/ast/p67_clock.sh <ct-ast>`；CI `baremetal_renode` | `OK p67/clock (168MHz, BRR derived from PCLK)`；CI `ok v0-PH-67-R1 clock` |
| E67-2 | `bash test/ast/p67_nrf52.sh <ct-ast>` | CI `ok v0-PH-67-R2 nRF52840 (second vendor: flash 0x0, UART0)` |
| E67-3 | `bash test/ast/p67_freertos.sh <ct-ast>` | CI `ok v0-PH-67-R3 FreeRTOS (2 tasks, queue, SysTick/PendSV/SVC)` |
| E67-4 | `bash test/ast/p67_dma.sh <ct-ast>` | CI `ok v0-PH-67-R4 DMA (Stream6 descriptor registers)`；真实搬运见 [TEST-22](../../../issues/testing/test22-dma-real-transfer-hardware-gated.md) |
| E67-5 | `bash test/ast/p67_gdb.sh <ct-ast>` | CI `ok v0-PH-67-R5 GDB (breakpoint main)` |
| E67-6 | `bash selfhost/check-all.sh` | 11/11；版本 `v0.66.0` + annotated tag |

任务级红证：R1 `8b165d03`、R2 `91aacb1f`、R3 `345e6c01`、R4 `ccb2778d`、R5 `cb88daa1`（均为对应实现提交的父提交）。

实现提交：R1 `da40abf7`、R2 `7e2ae6e3`、R3 `a1995028`、R4 `cc2de5ce`、R5 `2d685d2a`。
（R2 的 `f95883b0`、R3 的 `c2cf8cc1`、R5 的 `ee830378` 是随后的平台/链接/GDB 修正，不是红证对应的实现提交。）

CI 证据：收口提交 `709d3a7` 的 run `44339119194`（三 job 全绿），逐项 `ok v0-PH-67-R1…R5`；`44335562103` 是父提交 `ee830378` 的运行。

边界：Linux CI 的 Renode 是唯一运行点（macOS 沙箱内不可用，夜/日间代理不改权限）；
DMA 真实搬运、烧录、电气特性均未验证。
