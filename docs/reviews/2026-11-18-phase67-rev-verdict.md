# 2026-11-18 PH-67 收口复核（REV，补正后）

| 项 | 值 |
| --- | --- |
| 性质 | 复核结论（REV）；初判 `d7ba7410` 不通过，本次复核补正 |
| 复核日期 | 2026-11-18 |
| 复核者 | REV（独立会话 `rev-ph67`，无本会话历史） |
| 被复核收口 | `709d3a76`（`709d3a7673bfa47f747a449f6132f829824dcb86`，`ct-ast v0.66.0`，tag `v0.66.0`） |
| 补正提交 | `e78a0cdb`（docs/phase67 §8 提交与 CI 证据）；其父 `d7ba7410` 是初判 verdict |
| 结论 | **通过（补正后）**：三项否项均已按证据修正并复验；实现/测试路径自 `709d3a7` 未动，CI run 仍有效。 |

## 0 环境

```console
$ git rev-parse --short HEAD
e78a0cdb
$ uname -m
arm64
$ cc --version | head -1
Apple clang version 21.0.0 (clang-2100.4.1.1)
```

- `uname -s` = `Darwin`；本机有 `renode`、`arm-none-eabi-gcc`、`arm-none-eabi-gdb`，
  但 R2/R3/R5 的 run.sh 硬性要求 Linux（`nrf52/run.sh:14`、`freertos/run.sh:12`、
  `gdb.sh:16`），故本地 77 skip。按卡 D67-1 与沙箱约束，**未**在本机启动 host
  Renode；Renode 级运行只认 CI 日志。
- `/tmp/ct-host-renode/ct-ast` 是既有产物，自报 `ct-ast v0.65.1`（PH-66）。
  独立复核用 `/tmp/rev67`（从 `709d3a7` 源码自举、七步 `rc=0`）：

```console
$ /tmp/rev67/ct-ast -v
ct-ast v0.66.0
```

- 补正提交只改文档，不碰实现/测试：

```console
$ git diff --name-only 709d3a7..HEAD
docs/design/phase67.md
docs/reviews/2026-11-18-phase67-rev-verdict.md
```

因此 §3 的本地探针与 §4 的 CI run `44339119194` 对 `709d3a7` 仍然有效。

## 1 结论摘要

| 项 | 结论 |
| --- | --- |
| 任务级红证（T-7） | **5/5 通过**：按补正后的卡 §8 实现 sha，`git rev-parse <impl>^` 逐一等于对应红证。 |
| 探针与门禁 | 5 支探针存在且都被 `selfhost/check-ast.sh` 调用；`p67_clock`、`p67_dma` 本地静态面通过；`p67_nrf52`、`p67_freertos`、`p67_gdb` 77 skip（非 Linux）。 |
| CI | `709d3a7` 的 run `44339119194` 三 job 全绿；`ubuntu-gcc` 有 `ok PH-67-R1…R5` 五行，`check-all: OK (11 hard gates green)`。卡 §8 已改引此 run。 |
| 版本 | 五处 `CTC_VERSION` = `0.66.0`；`README.md` / `docs/README.md` / `AGENTS.md` / `docs/history/phase-log.md` 已同步。 |
| tag | annotated tag `v0.66.0` 已重建（对象 `d45d632…`），message 为 `PH-67 closeout (709d3a7)`；指向 `709d3a7`，远端 peeled 同提交。 |
| 边界 | TEST-22 仍 `open`；`git status` 仅 `?? battle/static-dispatch-1/`；无真机结论。 |

## 2 任务级红证（R1–R5）

红证提交正文均含 `baseline: <sha>`、命令、原始输出与退出码；`baseline` 等于该
test 提交的父提交、是 HEAD 的祖先：

| 任务 | 红证提交 | 正文 baseline | `test^` = baseline | 正文原始输出（摘录） |
| --- | --- | --- | --- | --- |
| R1 | `8b165d03` | `77f446c5` | 是 | `FAIL p67/clock: firmware never calls clock_init_168()` 等 3 行，退出码 1 |
| R2 | `91aacb1f` | `4c489620` | 是 | `FAIL p67/nrf52: missing link.ld` …（6 个文件缺失，退出码 1） |
| R3 | `345e6c01` | `f95883b0` | 是 | `FAIL p67/freertos: missing FreeRTOSConfig.h` …（10 个文件缺失，退出码 1） |
| R4 | `ccb2778d` | `c2cf8cc1` | 是 | `FAIL p67/dma: dma.c/.h missing`（退出码 1） |
| R5 | `cb88daa1` | `cc2de5ce` | 是 | `FAIL p67/gdb: gdb.sh missing`（退出码 1） |

补正后的卡 §8 实现 sha 与父关系（逐条 YES）：

```console
$ for pair in "8b165d03 da40abf7" "91aacb1f 7e2ae6e3" "345e6c01 a1995028" \
               "ccb2778d cc2de5ce" "cb88daa1 2d685d2a"; do
    set -- $pair
    echo "test=$1 impl=$2  impl^=$(git rev-parse --short $2^)  match=$([ "$(git rev-parse $2^)" = "$(git rev-parse $1)" ] && echo YES || echo NO)"
  done
test=8b165d03 impl=da40abf7  impl^=8b165d03  match=YES
test=91aacb1f impl=7e2ae6e3  impl^=91aacb1f  match=YES
test=345e6c01 impl=a1995028  impl^=345e6c01  match=YES
test=ccb2778d impl=cc2de5ce  impl^=ccb2778d  match=YES
test=cb88daa1 impl=2d685d2a  impl^=cb88daa1  match=YES
```

卡 §8 现写明 `f95883b0`/`c2cf8cc1`/`ee830378` 是 R2/R3/R5 的后续平台/链接/GDB
修正，不是红证对应的实现提交；该表述与 git 历史一致。

## 3 探针与门禁

`selfhost/check-ast.sh` 对五支探针均有调用（`799/806/813/820/827` 行，依次
`p67_clock/nrf52/freertos/dma/gdb`）。本地执行（HEAD 自举的 `ct-ast v0.66.0`）：

```console
$ bash test/ast/p67_clock.sh /tmp/rev67/ct-ast ; echo rc=$?
OK p67/clock (168MHz, BRR derived from PCLK)
rc=0
$ bash test/ast/p67_nrf52.sh /tmp/rev67/ct-ast ; echo rc=$?
skip: nRF52 probe needs Linux Renode (CI)
rc=77
$ bash test/ast/p67_freertos.sh /tmp/rev67/ct-ast ; echo rc=$?
skip: FreeRTOS probe needs Linux Renode (CI)
rc=77
$ bash test/ast/p67_dma.sh /tmp/rev67/ct-ast ; echo rc=$?
OK p67/dma (DMA1 Stream6 descriptor registers)
rc=0
$ bash test/ast/p67_gdb.sh /tmp/rev67/ct-ast ; echo rc=$?
skip: GDB probe needs Linux Renode (CI)
rc=77
```

要点：

- 题面要求的 `bash test/ast/p67_clock.sh /tmp/ct-host-renode/ct-ast` 也通过；
  该既有二进制自报 `v0.65.1`，故另用 `v0.66.0` 自举产物复核，结论相同。
- **本地实际是 3 支 skip，不是 4 支**：`p67_dma.sh` 是静态/编译面探针
  （`ct build --freestanding --emit-c` 成功 + 生成物含 `dma_setup_tx` +
  `run.sh` 链接 `dma.c` + 期望输出含 `dma=1`），不需要 Renode，所以本地 `rc=0`。
  它**不**在本地做寄存器回读；`PAR/M0AR/NDTR/CR` 的回读由 CI 的
  `baremetal_renode` 执行 `prog.expected.out`（含 `dma=1`）覆盖。不能把本地的
  `OK p67/dma` 读成“寄存器已验证”，更不能读成真实搬运（TEST-22 仍 open）。
- `p67_clock.sh` 同理只做静态面 + 期望输出断言；168MHz 的运行期读回
  由 CI 的 `baremetal_renode` 覆盖。

## 4 CI 事实

```console
$ XDG_CACHE_HOME=/tmp/ghcache gh run list --workflow ci.yml --limit 3
completed	success	feat(ast): PH-67 无真机硬件能力扩展收口（v0.66.0）	ci	main	push	44339119194	9m46s	2026-11-18T15:44:32Z
completed	success	fix(ast): R5 让 GDB 的 continue 启动机器	ci	main	push	44335562103	11m8s	2026-11-18T15:25:57Z
completed	failure	fix(ast): R5 GDB 带上 ELF 以解析符号	ci	main	push	44332046948	16m42s	2026-11-18T15:07:59Z

$ XDG_CACHE_HOME=/tmp/ghcache gh api repos/{owner}/{repo}/actions/runs/44339119194 --jq '.head_sha, .conclusion'
709d3a7673bfa47f747a449f6132f829824dcb86
success

$ XDG_CACHE_HOME=/tmp/ghcache gh run view 44339119194
✓ ubuntu-clang-smoke in 2m6s
✓ macos-clang in 4m12s
✓ ubuntu-gcc in 9m43s
```

`ubuntu-gcc` 的逐行原始输出（`gh run view 44339119194 --log` 摘录）：

```text
ubuntu-gcc	hard gates	2026-11-18T15:52:29.7431874Z   ok    PH-67-R1 clock (PLL 168MHz, BRR derived)
ubuntu-gcc	hard gates	2026-11-18T15:52:40.6883018Z   ok    PH-67-R2 nRF52840 (second vendor: flash 0x0, UART0)
ubuntu-gcc	hard gates	2026-11-18T15:52:51.7948610Z   ok    PH-67-R3 FreeRTOS (2 tasks, queue, SysTick/PendSV/SVC)
ubuntu-gcc	hard gates	2026-11-18T15:52:51.8112967Z   ok    PH-67-R4 DMA (Stream6 descriptor registers)
ubuntu-gcc	hard gates	2026-11-18T15:52:54.8468791Z   ok    PH-67-R5 GDB (breakpoint main)
ubuntu-gcc	hard gates	2026-11-18T15:52:17.8956434Z   ok    baremetal_renode (STM32F4: boot, button, SysTick, UART)
ubuntu-gcc	hard gates	2026-11-18T15:54:15.6390419Z check-all: OK (11 hard gates green)
ubuntu-gcc	hard gates	2026-11-18T15:53:29.6746830Z == summary: 1483 passed, 0 failed, 0 skipped ==
```

其他两个 job 对 R2/R3/R5 是 `skip`（`ubuntu-clang-smoke` 无 `arm-none-eabi-gcc`，
`macos-clang` 非 Linux），没有把 skip 写成通过；R2/R3/R5 的真运行只在
`ubuntu-gcc`。

卡 §8 的 CI 证据已改为 `44339119194`（`git show e78a0cdb` 可见），并注明
`44335562103` 是父提交 `ee830378` 的运行；与事实一致。

## 5 版本与 tag

```console
$ grep -n 'CTC_VERSION "0.66.0"' selfhost/l0/ctc.c selfhost/l1/ctc.ct \
      selfhost/l2/core.ct selfhost/l2/driver.ct selfhost/ct-ast/main.ct
selfhost/l0/ctc.c:61:#define CTC_VERSION "0.66.0"
selfhost/l1/ctc.ct:108:#define CTC_VERSION "0.66.0"
selfhost/l2/core.ct:55:#define CTC_VERSION "0.66.0"
selfhost/l2/driver.ct:36:#define CTC_VERSION "0.66.0"
selfhost/ct-ast/main.ct:36:#define CTC_VERSION "0.66.0"

$ git tag -l v0.66.0
v0.66.0
$ git cat-file -t v0.66.0
tag
$ git rev-parse v0.66.0^{commit}
709d3a7673bfa47f747a449f6132f829824dcb86
$ git ls-remote --tags origin 'v0.66.0*'
d45d63245da4105bff61a29a6983424e1554804b	refs/tags/v0.66.0
709d3a7673bfa47f747a449f6132f829824dcb86	refs/tags/v0.66.0^{}
```

tag message（重建后，合法 UTF-8，含 `PH-67` 与 sha 前 7 位）：

```console
$ git cat-file -p v0.66.0
object 709d3a7673bfa47f747a449f6132f829824dcb86
type commit
tag v0.66.0
tagger Sam X. Xu@macMini <samxxu@gmail.com> 1795017788 +0800

PH-67 closeout (709d3a7)
```

`v0.66.0` 是 annotated tag：本地 tag 对象 `d45d632…`，`ls-remote` 第一行与之
相同（远端已同步），`^{}` 解析出的提交为 `709d3a7`。旧 tag 对象 `e195111…`
不再被引用。文档同步（`README.md:3`、`docs/README.md:5`、`AGENTS.md:563`、
`docs/history/phase-log.md:186`）均已是 `v0.66.0`。

## 6 卡 §8 逐行对照

| 行 | 卡内写的 | 实测 | 判定 |
| --- | --- | --- | --- |
| E67-1 | `OK p67/clock (168MHz, BRR derived from PCLK)`；CI `ok PH-67-R1 clock` | 本地逐字相同；CI 为 `ok PH-67-R1 clock (PLL 168MHz, BRR derived)`（卡省略后缀，非假） | 成立 |
| E67-2 | CI `ok PH-67-R2 nRF52840 (second vendor: flash 0x0, UART0)` | CI 逐字相同 | 成立 |
| E67-3 | CI `ok PH-67-R3 FreeRTOS (2 tasks, queue, SysTick/PendSV/SVC)` | CI 逐字相同 | 成立 |
| E67-4 | CI `ok PH-67-R4 DMA (Stream6 descriptor registers)`；真实搬运见 TEST-22 | CI 逐字相同；`p67_dma.sh` 自身只验编译面，寄存器回读由 `baremetal_renode`（`dma=1`）覆盖；TEST-22 `open` | 成立 |
| E67-5 | CI `ok PH-67-R5 GDB (breakpoint main)` | CI 逐字相同 | 成立 |
| E67-6 | `check-all` 11/11；版本 `v0.66.0` + annotated tag | `check-all: OK (11 hard gates green)`；五处版本一致；tag 成立 | 成立 |
| 任务级红证 | 5 个红证 sha；均为对应实现提交的父提交 | 补正后的实现 sha 逐一满足（见 §2） | 成立 |
| 实现提交 | R1 `da40abf7`、R2 `7e2ae6e3`、R3 `a1995028`、R4 `cc2de5ce`、R5 `2d685d2a` | 与 git 历史一致；三个 follow-up 修正已注明 | 成立 |
| CI 证据 | 收口提交 `709d3a7` 的 run `44339119194`，三 job 全绿，`ok PH-67-R1…R5` | run 的 head_sha 为 `709d3a7`，三 job 全绿，五行 `ok` | 成立 |

没有发现“把 skip 写成 pass”：`ubuntu-clang-smoke`/`macos-clang` 的 R2/R3/R5
明写 `skip`，`ubuntu-gcc` 真跑。也没有发现把寄存器面写成真实 DMA 搬运：
卡与 TEST-22 均写明“真实搬运未验证/等真板”。

## 7 边界

```console
$ grep -n '状态' issues/testing/test22-dma-real-transfer-hardware-gated.md
8:| 状态 | `open`（hardware-gated，等真板） |
$ git status --porcelain
?? battle/static-dispatch-1/
```

TEST-22 仍 `open`（hardware-gated），是本次的登记项，不是本次缺陷；未跟踪目录仅
`battle/static-dispatch-1/`，无源码/文档未提交改动。`docs/history/phase-log.md:186`
明确“真机项（DMA 真实搬运等）登记为 TEST-22”，没有把真机写进已验证。

## 8 补正复核

初判 `d7ba7410`（REV: 不通过）的三项否项已逐项复验：

| # | 初判否项 | 补正后复验 | 结论 |
| --- | --- | --- | --- |
| 1 | 卡 §8 把 R2 `f95883b0`、R3 `c2cf8cc1`、R5 `ee830378` 当实现提交 | 卡已改为 `7e2ae6e3`/`a1995028`/`2d685d2a`，并注明三个 follow-up；`impl^` 与红证 5/5 相等 | 已消解 |
| 2 | §8 CI 证据引用父提交 run `44335562103` | 卡已改为 `709d3a7` 的 run `44339119194`，并注记父提交 run；该 run head_sha、三 job、五行 `ok` 均复核 | 已消解 |
| 3 | `v0.66.0` tag message 截断/缺 sha | tag 已重建：message `PH-67 closeout (709d3a7)`，合法 UTF-8，含 phase-id 与 sha；仍指向 `709d3a7`，远端已同步 | 已消解 |

三项均已按证据修正，无未消解项。补正提交 `e78a0cdb` 只改
`docs/design/phase67.md`（`git show --stat` = 1 file, 3 insertions/2 deletions），
未改实现/测试。

## 9 未覆盖声明

- Renode 运行期（R1 时钟读回、R2 nRF52840、R3 FreeRTOS、R4 DMA 寄存器回读、
  R5 GDB 断点）**未在本机重跑**；本机 `uname -s` = Darwin，探针按设计 77 skip。
  这些项的结论只来自 CI run `44339119194` 的原始日志。
- `p67_clock.sh`/`p67_dma.sh` 的本地 `OK` 只覆盖静态/编译面，不覆盖 Renode 运行期。
- 未在本机运行 `bash selfhost/check-all.sh`；`11/11` 与 `1483 passed, 0 failed,
  0 skipped` 取自 CI 同一 job。
- 未核 FreeRTOS-Kernel 下载缓存的内容（CI 现取到 `.temp/`，不入库）。

## 10 结论

**REV: 通过（补正后）**。

初判的三项否项（§8 实现提交映射、§8 CI run 引用、tag message）均已修正并复验：
补正后的实现 sha 与红证 5/5 对应；`44339119194` 是 `709d3a7` 的 run 且三 job 全绿、
五行 `ok`；tag 重建后 message 含 `PH-67` 与 `709d3a7`、annotated、指向收口提交、
远端 peeled 一致。其余门禁与边界不变：五处版本 `0.66.0`、`check-all` 11/11、
TEST-22 保持 `open`、工作树仅 `battle/static-dispatch-1/` 未跟踪。

TEST-22 继续 `open`（hardware-gated，不是本次缺陷）。
