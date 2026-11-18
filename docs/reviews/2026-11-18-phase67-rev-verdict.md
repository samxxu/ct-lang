# 2026-11-18 PH-67 收口复核（REV）

| 项 | 值 |
| --- | --- |
| 性质 | 复核结论（REV） |
| 复核日期 | 2026-11-18 |
| 复核者 | REV（独立会话 `rev-ph67`，无本会话历史） |
| 被复核 HEAD | `709d3a76`（`709d3a7673bfa47f747a449f6132f829824dcb86`，`ct-ast v0.66.0`，tag `v0.66.0`） |
| 结论 | **不通过**：实质门禁（探针、CI、版本、tag 指向、边界）全部成立；但卡 §8 的实现提交映射 3/5 与 `git rev-parse <impl>^` 不符，且 §8 的 CI 证据引用的是父提交 run（HEAD 自身 run 已绿、但未被卡引用）。两项均属收口证据层，不是实现缺陷；更正后即可重签。 |

## 0 环境

```console
$ git rev-parse --short HEAD
709d3a76
$ uname -m
arm64
$ cc --version | head -1
Apple clang version 21.0.0 (clang-2100.4.1.1)
```

- `uname -s` = `Darwin`；本机有 `/opt/homebrew/bin/renode`、`arm-none-eabi-gcc`、
  `arm-none-eabi-gdb`，但 R2/R3/R5 的 run.sh 硬性要求 Linux
  （`nrf52/run.sh:14`、`freertos/run.sh:12`、`gdb.sh:16`），故本地 77 skip。
  按卡 D67-1 与沙箱约束，**未**在本机启动 host Renode；Renode 级运行只认 CI 日志。
- `/tmp/ct-host-renode/ct-ast` 是既有产物，自报 `ct-ast v0.65.1`（PH-66）。
  为独立复核，另在 `/tmp/rev67` 从被复核 HEAD 自举到 `ct-ast v0.66.0` 后重跑
  （七步 `rc=0`）：

```console
$ # L0→L1→L2 按 README 七步自举，均 rc=0（中间步骤略）
$ /tmp/rev67/ctc-l2 build -I selfhost/ct-ast selfhost/ct-ast/main.ct -o /tmp/rev67/ast
$ cc -Wall -Wextra -std=c99 /tmp/rev67/ast/*.c -o /tmp/rev67/ct-ast
$ /tmp/rev67/ct-ast -v
ct-ast v0.66.0
```
## 1 结论摘要

| 项 | 结论 |
| --- | --- |
| 任务级红证（T-7） | **按卡 §8 列的实现 sha 检查：R1、R4 通过；R2、R3、R5 不通过**（卡内列的是后续 `fix` 提交，其父不是红证提交）。按真实 `feat` 提交 `7e2ae6e3`/`a1995028`/`2d685d2a` 检查，则 5/5 成立。 |
| 探针与门禁 | 5 支探针存在且都被 `selfhost/check-ast.sh` 调用；`p67_clock`、`p67_dma` 本地静态面通过；`p67_nrf52`、`p67_freertos`、`p67_gdb` 77 skip（非 Linux）。 |
| CI | `709d3a7` 的 run `44339119194` 三 job 全绿；`ubuntu-gcc` 有 `ok PH-67-R1…R5` 五行，`check-all: OK (11 hard gates green)`。 |
| 版本 | 五处 `CTC_VERSION` = `0.66.0`；`README.md` / `docs/README.md` / `AGENTS.md` / `docs/history/phase-log.md` 已同步。 |
| tag | annotated tag `v0.66.0` → `709d3a76`，远端 peeled ref 同提交；tag message 截断且缺 sha（与前三版相同的系统性问题，见 §5）。 |
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

按真实 feat 提交检查父关系：

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

**但按卡 §8 列出的“实现提交”检查，R2/R3/R5 不成立**：

```console
$ git rev-parse --short f95883b0^     # 卡内 R2 实现
9cca9a3a                              # 不是红证 91aacb1f
$ git rev-parse --short c2cf8cc1^     # 卡内 R3 实现
690a0c09                              # 不是红证 345e6c01
$ git rev-parse --short ee830378^     # 卡内 R5 实现
1c3a8332                              # 不是红证 cb88daa1
```

`f95883b0`、`c2cf8cc1`、`ee830378` 的标题分别为 `fix(ast): PH-67-R2 …`、
`fix(ast): R3 …`、`fix(ast): R5 …`，都是实现之后的修复提交。因此
`docs/design/phase67.md:106` 的“（均为对应实现提交的父提交）”按 §8 自己的
实现 sha（`:108`）为**假**。正确写法是把 §8 的实现提交改为 feat 提交
（R2 `7e2ae6e3`、R3 `a1995028`、R5 `2d685d2a`），或把“父提交”限定到 feat 提交。
T-7 本身在 feat 提交上成立，实现无需改动。

## 3 探针与门禁

`selfhost/check-ast.sh` 对五支探针均有调用（`799/806/813/820/827` 行，依次
`p67_clock/nrf52/freertos/dma/gdb`）。本地执行（HEAD 自举的 `ct-ast v0.66.0`）：

```console
$ bash test/ast/p67_clock.sh /tmp/rev67/ct-ast ; echo rc=$?
OK p67/clock (168MHz, BRR derived from PCLK)
rc=0
$ bash test/ast/p67_nrf52.sh /tmp/rev67/ct-ast ; echo rc=$?
<stderr>skip: nRF52 probe needs Linux Renode (CI)
rc=77
$ bash test/ast/p67_freertos.sh /tmp/rev67/ct-ast ; echo rc=$?
<stderr>skip: FreeRTOS probe needs Linux Renode (CI)
rc=77
$ bash test/ast/p67_dma.sh /tmp/rev67/ct-ast ; echo rc=$?
OK p67/dma (DMA1 Stream6 descriptor registers)
rc=0
$ bash test/ast/p67_gdb.sh /tmp/rev67/ct-ast ; echo rc=$?
<stderr>skip: GDB probe needs Linux Renode (CI)
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

**卡 §8 的 CI 证据与事实不符**：卡（`docs/design/phase67.md:110`）写
`run 44335562103`，而

```console
$ gh api repos/{owner}/{repo}/actions/runs/44335562103 --jq '.head_sha'
ee8303789697467398c951aa423ce42a1fd24122
```

该 run 属于父提交 `ee830378`，不是被复核的 `709d3a7`。`709d3a7` 自己的 run 是
`44339119194`，且如上全绿。结论本身（五项 `ok`）成立，但 §8 的证据行指错了
run；收口提交正文里的“CI run 44335562103”同样应更新为 `44339119194`。

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
e19511111da69938f51b34fe39a4b3412bfec2ee	refs/tags/v0.66.0
709d3a7673bfa47f747a449f6132f829824dcb86	refs/tags/v0.66.0^{}
```

`v0.66.0` 是 annotated tag：`ls-remote` 第一行是 tag 对象（与本地
`git rev-parse v0.66.0` 相同，说明远端 tag 对象未变），`^{}` 解析出的提交才是
`709d3a7`。指向、annotated 属性与远端可追溯均成立。

文档同步（`README.md:3`、`docs/README.md:5`、`AGENTS.md:563`、
`docs/history/phase-log.md:186`）均已是 `v0.66.0`。

**tag message 缺陷（系统性问题）**：message 在 `（` 后被截断，含非法 UTF-8 字节，
且没有 V-7 要求的收口提交 sha 前 7 位：

```console
$ git cat-file tag v0.66.0 | tail -c 9 | od -An -tx1
 e5 8f a3 ef bc 88 bc 89 0a
```

即 `口`（`e5 8f a3`）+ `（`（`ef bc 88`）+ 非法续字节 `bc 89` + 换行，之后无 sha。

同样的截断也出现在 `v0.65.1`、`v0.65.0`、`v0.64.0`（`PH-66…（��`、`SH-91…（��`、
`PH-65…（��`），不是 PH-67 新引入；但 V-7 的“message 含 phase-id 与收口 sha 前 7 位”
仍未满足。建议单独立项修 tag 生成流程，并决定是否重建已推 tag（重建需用户签字）；
本项不作为单独否掉 PH-67 的依据。

## 6 卡 §8 逐行对照

| 行 | 卡内写的 | 实测 | 判定 |
| --- | --- | --- | --- |
| E67-1 | `OK p67/clock (168MHz, BRR derived from PCLK)`；CI `ok PH-67-R1 clock` | 本地逐字相同；CI 为 `ok PH-67-R1 clock (PLL 168MHz, BRR derived)`（卡省略后缀，非假） | 成立（措辞有省略） |
| E67-2 | CI `ok PH-67-R2 nRF52840 (second vendor: flash 0x0, UART0)` | CI 逐字相同 | 成立 |
| E67-3 | CI `ok PH-67-R3 FreeRTOS (2 tasks, queue, SysTick/PendSV/SVC)` | CI 逐字相同 | 成立 |
| E67-4 | CI `ok PH-67-R4 DMA (Stream6 descriptor registers)`；真实搬运见 TEST-22 | CI 逐字相同；`p67_dma.sh` 自身只验编译面，寄存器回读由 `baremetal_renode`（`dma=1`）覆盖；TEST-22 `open` | 成立（归因需注明） |
| E67-5 | CI `ok PH-67-R5 GDB (breakpoint main)` | CI 逐字相同 | 成立 |
| E67-6 | `check-all` 11/11；版本 `v0.66.0` + annotated tag | `check-all: OK (11 hard gates green)`；五处版本一致；tag 成立 | 成立 |
| 任务级红证 | 5 个红证 sha；均为对应实现提交的父提交 | 5 个 sha 正确；但按 §8 列的实现 sha，R2/R3/R5 的父提交不是红证（见 §2） | **不成立（3/5）** |
| 实现提交 | R1 `da40abf7`、R2 `f95883b0`、R3 `c2cf8cc1`、R4 `cc2de5ce`、R5 `ee830378` | R2/R3/R5 列的是 `fix` 提交；真实 feat 是 `7e2ae6e3`/`a1995028`/`2d685d2a` | **不成立（3/5）** |
| CI 证据 | run `44335562103`（三 job 全绿），`ok PH-67-R1…R5` | 该 run 是父提交 `ee830378`；HEAD 的 run 是 `44339119194`，同样全绿且含五行 `ok` | **指错 run** |

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

## 8 失败复现与重签条件
以下均为只读命令复现；本次复核**未改任何实现**。
1. **§8 实现提交映射/父提交声明不成立（R2/R3/R5）**：
   `git rev-parse --short f95883b0^ c2cf8cc1^ ee830378^` →
   `9cca9a3a` / `690a0c09` / `1c3a8332`，无一是红证
   `91aacb1f` / `345e6c01` / `cb88daa1`。三条 `^` 无一命中所属任务的红证提交；
   对应 feat 提交 `7e2ae6e3`/`a1995028`/`2d685d2a` 的父提交分别是
   `91aacb1f`/`345e6c01`/`cb88daa1`。
   修法（仅文档）：把 `docs/design/phase67.md:108` 的三个 fix sha 换成 feat sha。

2. **§8 的 CI run 是父提交的，不是 `709d3a7` 的**：
   `gh api .../runs/44335562103 --jq .head_sha` → `ee830378…`；HEAD 的 run
   `44339119194` 才是 `709d3a7`（`success`）。

3. **tag message 截断/缺 sha（系统性，见 §5）**：`git cat-file tag v0.66.0`
   末尾为 `（` + `0xBC 0x89`（非法 UTF-8），无 sha；V-7 要求 phase-id 与收口 sha 前
   7 位。`v0.64.0`/`v0.65.0`/`v0.65.1` 同样复现，建议另立 issue；若要以
   deviation 接受现状，需用户签字。

重签条件：

1. `docs/design/phase67.md:108` 的实现提交改为 R2 `7e2ae6e3`、R3 `a1995028`、
   R5 `2d685d2a`（R1/R4 不变），使 `:106` 的“父提交”声明为真；或改写该句限定到
   feat 提交并保留 fix 提交列表作为补充。
2. `docs/design/phase67.md:110` 与收口提交正文的 CI 证据改为 run `44339119194`。
3. tag message 与前三版一并处理：修生成流程并决定是否重建 `v0.66.0`；若要接受
   现状，登记 `deviation:` 并由用户签字。
4. TEST-22 继续 `open`（hardware-gated，不是本次缺陷）。

## 9 未覆盖声明
- Renode 运行期（R1 时钟读回、R2 nRF52840、R3 FreeRTOS、R4 DMA 寄存器回读、
  R5 GDB 断点）**未在本机重跑**；本机 `uname -s` = Darwin，探针按设计 77 skip。
  这些项的结论只来自 CI run `44339119194` 的原始日志。
- `p67_clock.sh`/`p67_dma.sh` 的本地 `OK` 只覆盖静态/编译面，不覆盖 Renode 运行期。
- 未在本机运行 `bash selfhost/check-all.sh`；`11/11` 与 `1483 passed, 0 failed,
  0 skipped` 取自 CI 同一 job。
- 未核 FreeRTOS-Kernel 下载缓存的内容（CI 现取到 `.temp/`，不入库）。

## 10 结论

**REV: 不通过**。

实质门禁全部成立：R1–R5 的 CI 运行、五支探针、`check-all` 11/11、五处版本、
annotated tag 指向 `709d3a7` 且远端可追溯、TEST-22 保持 `open`、工作树无未提交改动。
否项只在收口证据层：§8 的“实现提交”有 3/5 不是红证的直接子提交（父提交不对，
把 fix 当成了实现），且 §8 的 CI 证据引用了父提交的 run。两处更正是纯文档改动，
改完即可重签；
不需要改实现。tag message 的截断是跨版本的系统性问题，建议另立 issue，不作为
本次否项的唯一依据。
