# STM32F4 冒烟（Renode，TEST-21）

自包含固件 + Renode 平台，用来证明 `--freestanding` 产物能在 **STM32F407**
的内存图上启动、跑中断、打 UART（不是通用 Cortex-M 模型）。

| 文件 | 作用 |
| --- | --- |
| `startup.c` | 向量表（16 + 82 IRQ）、`.data` 拷贝、`.bss` 清零、跳 `main` |
| `link.ld` | STM32F407：flash `0x08000000` 1 MiB，SRAM `0x20000000` 128 KiB |
| `board.c` | RCC / GPIOA / USART2（0x40004400）/ SysTick / PA0 按键 |
| `prog.ct` | Ct 状态机：`boot ok` → 按键 → 3 次 SysTick → `tick=3` |
| `run.sh` | 构建固件 → Renode 加载 → 比对 `prog.expected.out` |

## 运行

```bash
# Linux（CI 用的路径）：下载 portable 包（自带 .NET），然后
mkdir -p .temp/renode-linux
curl -fsSL -o /tmp/renode.tar.gz \
  https://github.com/renode/renode/releases/download/v1.17.0/renode-1.17.0.linux-x64-portable.tar.gz
tar -xzf /tmp/renode.tar.gz -C .temp/renode-linux --strip-components=1
RENODE_MODE=local sh test/baremetal-renode/run.sh /path/to/ct-ast

# macOS：用容器里的 Linux 版（写只落在工作树/容器内）
RENODE_MODE=podman sh test/baremetal-renode/run.sh /path/to/ct-ast

# 宿主直跑：需要调用者预先准备（签名 dotnet + 可写用户目录）
RENODE_MODE=host sh test/baremetal-renode/run.sh /path/to/ct-ast
```

退出码：`0` 通过、`1` 失败、`77` 跳过（工具缺失/宿主权限不足/已知慢）。
本机 macOS 的 Renode（宿主与 podman VM）实测异常慢或停在平台加载，因此
默认 skip；`RENODE_ALLOW_SLOW=1` 可强行尝试。

## 边界

Renode 的 USART 不采样波特率；按键模型默认释放（`btn=0`）。这仍是
**pre-pilot** 证据，REQ-HW-020 要求真实板卡。
