# TEST-21 · STM32F4 裸机冒烟（Renode）

| 项 | 值 |
| --- | --- |
| 模块 | test（`test/baremetal-renode/`） |
| 类型 | 测试缺口（QEMU 冒烟只覆盖通用 Cortex-M，没有厂商内存映射） |
| 严重度 | Medium |
| 状态 | `open`（DEV 已处置，待复核） |
| 承诺出处 | [REQ-HW-010/011](../../docs/planning/hardware-readiness-requirements.md)、[PH-64 卡](../../docs/design/phase64.md) |

## 缺口

TEST-20 的 QEMU 冒烟跑在 `lm3s6965evb`（通用 M3，256K/64K）。它证明不了
STM32F4 的 1 MiB flash @0x08000000 / 128 KiB SRAM @0x20000000、USART2 与
GPIO 的寄存器面。

## 处置

`test/baremetal-renode/`：自包含 `startup.c`（向量表、`.data`/`.bss`）、
`link.ld`（STM32F407 内存图）、`board.c`（RCC/GPIOA/USART2/SysTick/按键）、
`prog.ct`、`run.sh`。Renode 用官方 `stm32f4_discovery-kit` 平台加载 ELF，
`sysbus.usart2 CreateFileBackend` 把 UART 写进文件后比对。

运行方式：
- **Linux（CI）**：`RENODE_MODE=local`，用 `.temp/renode-linux/renode`
  （portable 包自带 .NET）；CI 的 `ubuntu-gcc` job 下载后自动走这条；
- **macOS**：`RENODE_MODE=podman` 用容器内 Linux 版（写只落在工作树/容器内）；
- **宿主直跑**：`RENODE_MODE=host`，需要调用者预先装好签名 `dotnet`，并让
  Renode 能写 `~/Library/Application Support/renode`（agent 沙箱内做不到，会 skip）。

## 已知限制

- 本机 macOS 宿主与 podman VM 里的 Renode 都异常慢/挂起（0.02 s 虚拟时间
  >20 分钟，或停在平台加载）；因此本地默认 **skip**（`RENODE_ALLOW_SLOW=1`
  才尝试），门禁速度不被拖垮。CI（Linux x86_64）是这条探针的权威运行点。
- Renode 的 USART 模型不采样波特率；`BRR` 只是按真实板写成 115200。
- 按键默认释放（PA0 低），所以期望输出是 `btn=0`；真实板按下时是 `btn=1`。
- 这仍是 **pre-pilot** 证据：REQ-HW-020 要真实板卡 + 厂商 HAL。

## 关联

- [TEST-20](test20-baremetal-qemu-smoke.md)：通用 Cortex-M 冒烟；
- [PH-64 卡 §5](../../docs/design/phase64.md)：符号面证据。

## 处置（2026-11-20，DEV · 复跑）

- 结论：本机（macOS 沙箱）无法给出 Renode 证据；探针按设计 skip，CI Linux
  仍是权威运行点。只记录证据，不改 `status`。
- 命令/输出：

```console
$ sh test/baremetal-renode/run.sh /tmp/ci9-sh93-build/ct-ast
rc=77
skip: container Renode is known-slow here; set RENODE_ALLOW_SLOW=1 to try
```

（未声称已验证；`RENODE_ALLOW_SLOW=1` 会拖垮本机门禁速度，未尝试。）

## 复核（2026-11-20，REV）

**结论：skip，不判绿；status 不动。**

```console
$ sh test/baremetal-renode/run.sh /tmp/rev-v0771-build/ct-ast
skip: host Renode cannot use its user directory/JIT (run it outside the agent sandbox)
$ echo $?
77
```

宿主 Renode 需写工作树外目录且 JIT 不可用，按探针设计 `exit 77`；CI Linux 仍是权威
运行点，本条不因本机 skip 转 verified。
