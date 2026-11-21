# TEST-21 · STM32F4 裸机冒烟（Renode）

| 项 | 值 |
| --- | --- |
| 模块 | test（`test/baremetal-renode/`） |
| 类型 | 测试缺口（QEMU 冒烟只覆盖通用 Cortex-M，没有厂商内存映射） |
| 严重度 | Medium |
| 状态 | verified |
| 处置证据 | **verified**（CI `ubuntu-gcc`：`ok baremetal_renode (STM32F4: boot, button, SysTick, UART)`；run `44882080268`；见文末处置） |
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

## 处置（2026-11-22，REV/REQ）

**结论：`verified`。** 上轮 REV 只持有本机 `exit 77`，因此「不判绿、status 不动」；本轮补上
**权威运行点**（CI `ubuntu-gcc`）的证据，验收可在离线/无真板条件下核对，不需要宿主 Renode。

```console
# 1) 本机（macOS）：探针按设计 skip，不是失败（2026-11-22 复跑）
$ sh test/baremetal-renode/run.sh /tmp/ci9-sh93-build/ct-ast
skip: container Renode is known-slow here; set RENODE_ALLOW_SLOW=1 to try
$ echo $?
77

# 2) 权威运行点：CI ubuntu-gcc 的硬门禁原始日志（PH-67 复核已入库）
ubuntu-gcc	hard gates	2026-11-18T15:52:17.8956434Z   ok    baremetal_renode (STM32F4: boot, button, SysTick, UART)

# 3) 最近一次 ci 运行（v0.88.0，`5605eb6c`）
$ curl -s https://api.github.com/repos/samxxu/ct-lang/actions/runs/44882080268 \
  | python3 -c 'import json,sys; d=json.load(sys.stdin); print({k: d[k] for k in ("id","name","head_sha","head_branch","conclusion","created_at")})'
{'id': 44882080268, 'name': 'ci', 'head_sha': '5605eb6ca9fd832e930ac43c9ec3e6f96d34b93c', 'head_branch': 'main', 'conclusion': 'success', 'created_at': '2026-11-21T07:50:21Z'}
$ curl -s https://api.github.com/repos/samxxu/ct-lang/actions/runs/44882080268/jobs \
  | python3 -c 'import json,sys; [print(j["name"], j["conclusion"]) for j in json.load(sys.stdin)["jobs"]]'
ubuntu-clang-smoke success
ubuntu-gcc success
macos-clang success
```

（第 1 条命令用的是 `/tmp` 里既有的 `ct-ast v0.77.0` 产物；`skip` 发生在 `ct build` 之前——
先判交叉工具链与 Renode 模式，所以与二进制版本无关。）

**为什么 job 绿即本条绿。** `test/baremetal-renode/run.sh` 的 `77` 分支只在四种条件触发：
① 缺 `arm-none-eabi-gcc`/`arm-none-eabi-nm`；② `RENODE_MODE=host` 且 PATH 无 `renode`；
③ `.temp/renode-linux/renode` 不可执行；④ 非 CI 的 podman 慢机。`ubuntu-gcc` 的
"bare-metal smoke tools" 步骤装了 ① 的交叉工具链、下载并**启动自检**了 Renode（自检失败该步骤
即红），故 ③ 不成立、② 不属 Linux、④ 被 `CI` 变量排除。剩下的只有 `ok` 与 `FAIL`，而
`FAIL` 会让 `check-all.sh` 红 → job 绿 ⇒ 探针返回 `ok`。

逐条对照（下表是探针输出 `ok` 之前必须**同时**成立的子判据：任一条不过即 `FAIL`/`bad`，
所以 CI 的 `ok` 等于四条一起成立）：

| 判据 | 结果 | 证据 |
| --- | --- | --- |
| STM32F407 内存图（1 MiB flash @0x08000000 / 128 KiB SRAM @0x20000000） | 通过：`link.ld` 固定内存图，`nm -u` 为空才走到加载 | `test/baremetal-renode/link.ld`；`run.sh` 的 `undef` 段 |
| USART2 / GPIOA / RCC 寄存器面 | 通过：USART2 写文件后与 `prog.expected.out` 逐字节相等 | `diff -u` 无差即 `OK baremetal-renode (local)` |
| SysTick / 按键 | 通过：`tick=` 与 `btn=0` 行被 golden 钉死 | `prog.expected.out` |
| 门禁接线（不是一次性脚本） | 通过：`check-ast.sh` 把它算作硬门禁项，`0=ok` / `77=skip` / 其余 `bad` | `selfhost/check-ast.sh` 的 `baremetal_renode` 段 |

**边界（明确不声称）：** 本条只闭合「Renode 模拟 STM32F4 内存图 + 寄存器面」这一层；真板 +
厂商 HAL 仍是 REQ-HW-020 的事，真实 DMA 搬运见 [TEST-22](test22-dma-real-transfer-hardware-gated.md)。
本机无法复跑不构成未闭合：探针在 CI 每次 push 都会重跑，权威运行点不是一次性结论。
