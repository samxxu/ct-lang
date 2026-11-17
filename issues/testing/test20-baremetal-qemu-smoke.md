# TEST-20 · 缺 QEMU 裸机冒烟：`--freestanding` 产物没在 Cortex-M 上跑过

| 项 | 值 |
| --- | --- |
| 模块 | test（`test/baremetal-qemu/`） |
| 类型 | 测试缺口（PH-64 的符号面只到 `nm -u`，没有"能启动、能进中断"的证据） |
| 严重度 | Medium |
| 状态 | `open`（DEV 已处置，待复核） |
| 锚点 | `v0.63.4`（`72ed6dc6`） |
| 承诺出处 | [REQ-HW-010/011](../../docs/planning/hardware-readiness-requirements.md)、[PH-64 卡](../../docs/design/phase64-draft.md) |

## 缺口

PH-64 的验收停在"每个单元 `nm -u` ⊆ 允许集"。符号面干净不等于能启动：vector table、
`.data/.bss`、SysTick 向量、semihosting 退出都没被任何门禁覆盖。

## 处置

`test/baremetal-qemu/`：`startup.c`（vector table + reset）、`board.c`（UART/SysTick/
SYS_EXIT_EXTENDED）、`link.ld`（lm3s6965evb：256K flash / 64K RAM）、`prog.ct`
（CT 状态机 + ISR 消费）、`prog.expected.out`、`run.sh`（build 模式发射 → 交叉编译 →
`arm-none-eabi-nm -u` 为空 → QEMU 启动 → 输出比对；缺工具 `exit 77`）。

判据：
- 输出 `boot ok` / `tick=3`（复位路径 + UART + SysTick 中断）；
- QEMU 退出码 0（SYS_EXIT_EXTENDED，未挂起、无缺失符号）；
- 产物无 `#include <…>`（freestanding 承诺）；
- 缺 `arm-none-eabi-gcc` 或 `qemu-system-arm` 时 `skip`，不伪装通过。

## 边界（不许夸大）

QEMU 的 `lm3s6965evb` 是 Cortex-M3 通用模型，**不是** STM32F4 / nRF52 / RP2040：
它证明"生成的 C 能在 Cortex-M 上启动并进中断"，不证明任何具体芯片的外设。
硬件 pilot（REQ-HW-020/021）仍需要真实板卡。

## 关联

- [SH-90](../selfhost/sh90-freestanding-compile-mode-layer.md)：该冒烟顺带发现的 compile 模式缺口；
- [PH-64 卡 §5](../../docs/design/phase64-draft.md)：符号面证据。
