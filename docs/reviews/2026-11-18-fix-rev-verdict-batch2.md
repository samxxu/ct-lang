# 2026-11-18 修复与 phase 证据复核（batch2，REV）

| 项 | 值 |
| --- | --- |
| 性质 | 复核结论（REV）；`status` 按 5.4 由 REV 写入 issue |
| 复核日期 | 2026-11-18 |
| 复核者 | REV |
| HEAD | `8739ec96`（`8739ec962da42a1e6d4da0a9c20a3cbbdc52589a`，`ct-ast v0.65.1`） |
| A 部分结论 | **4/4 通过**：SH-89 / SH-90 / SH-91 / TEST-20 均 `verified`（无 skip） |
| B 部分结论 | **不成立（部分任务）**：PH-65 R1–R5 合规；R6 / R7 不合规；PH-66 R1–R5 的 test/impl 父提交关系成立，但红证均未写 `baseline: <sha>`（R5 无 baseline 字段） |

复核期间 HEAD 由 `ff9dd9c5` 前移到 `8739ec96`；新增提交只动
`docs/reviews/2026-11-17-pkg-index-audit.md`（953 行，纯文档），
`git diff --name-only ff9dd9c5 HEAD` 无源码路径，故本文的构建与探针结论不受影响。

## 0 环境

```console
$ uname -m
arm64
$ cc --version | head -1
Apple clang version 21.0.0 (clang-2100.4.1.1)
$ git rev-parse --short HEAD
8739ec96
```

- 本机 `/usr/bin/gcc` 实际是 Apple clang 21.0.0（`gcc --version` 自报 clang），
  不能复现 GCC 的 `-Wunused-function` 语义；SH-91 用 podman
  （6.2.0，`docker.io/library/gcc:13`，linux/amd64 仿真）跑 **GNU GCC 13.5.0**。
- `arm-none-eabi-gcc`、`qemu-system-arm`、`arm-none-eabi-nm` 均在本机可用
  （`/opt/homebrew/bin`），TEST-20 未 skip。

## 1 构建（一次性，`W=/tmp/rev2`）

```console
$ cc -Wall -Wextra -std=c99 selfhost/l0/ctc.c -o "$W/ctc"
$ "$W/ctc" selfhost/l1/ctc.ct -o "$W/l1.c"
$ cc -Wall -Wextra -std=c99 "$W/l1.c" -o "$W/l1"
$ "$W/l1" build selfhost/l2/driver.ct -o "$W/l2src"
$ cc -Wall -Wextra -std=c99 "$W/l2src"/*.c -o "$W/l2"
$ "$W/l2" build -I selfhost/ct-ast selfhost/ct-ast/main.ct -o "$W/astsrc"
$ cc -Wall -Wextra -std=c99 "$W/astsrc"/*.c -o "$W/ct-ast"
$ "$W/ct-ast" --version
ct-ast v0.65.1
```

七步全部 `rc=0`，构建过程零警告（`-Wall -Wextra`）。

## 2 A 部分：逐条结论

探针按各自注释与 `selfhost/check-ast.sh` 的调用方式执行；带 `CT_C_BOUNDARY`
环境时统一 `env -u CT_C_BOUNDARY`。

### 2.1 SH-89 通过（`verified`）

```console
$ env -u CT_C_BOUNDARY bash test/ast/p66_io_detect.sh "$W/ct-ast" ; echo rc=$?
OK p66/io-detect
rc=0
$ env -u CT_C_BOUNDARY bash test/ast/p66_io_emit.sh "$W/ct-ast" ; echo rc=$?
OK p66/io-emit
rc=0
$ env -u CT_C_BOUNDARY bash test/ast/p66_io_empty.sh "$W/ct-ast" ; echo rc=$?
OK p66/io-empty
rc=0
$ env -u CT_C_BOUNDARY bash test/ast/p66_io_boundary.sh "$W/ct-ast" ; echo rc=$?
OK p66/io-boundary
rc=0
$ bash test/ast/p66_io_docs.sh ; echo rc=$?
OK p66/docs
rc=0
```

五支探针覆盖验收 A1–A8：空程序零系统头（compile 与 build 两种模式）、
`printf`/`puts`/`fprintf`/`scanf` 补一次 `<stdio.h>`、`wprintf` 补 `<wchar.h>`、
`syslog` 不补、用户同名 `printf` 不抢、`--freestanding` 硬错且不留产物、
重复调用去重；文档探针查 `docs/language-spec.md` §4.67 / 包指南 / README。
**不通过项：无。**

### 2.2 SH-90 通过（`verified`）

```console
$ env -u CT_C_BOUNDARY bash test/ast/p64_freestanding.sh "$W/ct-ast" ; echo rc=$?
OK p64free
rc=0
```

该探针除 build 模式的三组符号面断言外，第 131 行起即 SH-90 的 compile 模式断言：
`--freestanding` 单文件产物必须无 `#include <…>`、无 `malloc(`。`OK p64free` 表示
三组 build 断言 + compile 断言全部通过。**不通过项：无。**

### 2.3 SH-91 通过（`verified`）

```console
$ CT_STD_DIR="$PWD/lib/std" "$W/ct-ast" /tmp/rev2/probe/empty.ct -o /tmp/rev2/probe/empty.c ; echo rc=$?
rc=0
$ grep -c '#include' /tmp/rev2/probe/empty.c
0
$ grep -c 'Str_Drop_drop' /tmp/rev2/probe/empty.c
0
$ grep -c '^static' /tmp/rev2/probe/empty.c
0
```

`p66_io_empty.sh` 第 50–53 行就是 `Str_Drop_drop` 断言，上文 `OK p66/io-empty`
已覆盖。再用 **GNU GCC 13.5.0** 编同一份空程序产物：

```console
$ podman run --rm -v "$PWD":/src:ro docker.io/library/gcc:13 \
    sh -c 'gcc --version | head -1; gcc -Wall -Wextra -std=c99 -c /src/.temp/rev2/empty.c -o /tmp/empty.o'
gcc (GCC) 13.5.0
$ echo rc=$?
rc=0
```

GCC stderr 为空（警告计数 0），无 `-Wunused-function`、无 `declared 'static' but
never defined`。产物既无系统头也无任何 `static` 顶层声明，未用层单元确实没有进入
解析/发射。**不通过项：无。**

说明：podman 有 `image platform (linux/amd64) does not match the expected
platform (linux/arm64)` 提示，属仿真运行方式提示，不影响 GCC 判定。

### 2.4 TEST-20 通过（`verified`）

```console
$ env -u CT_C_BOUNDARY bash test/baremetal-qemu/run.sh "$W/ct-ast" ; echo rc=$?
OK baremetal-qemu
rc=0
```

为取得 run.sh 内部比对的实际客人输出，按其步骤手工复跑：

```console
$ "$W/ct-ast" build --freestanding --emit-c test/baremetal-qemu/prog.ct -o /tmp/rev2/bm/c
$ grep -c '#include *<' /tmp/rev2/bm/c/prog.c
0
$ arm-none-eabi-gcc -mcpu=cortex-m3 -mthumb -ffreestanding -nostdlib -O1 -Wall -Wextra \
    -I test/baremetal-qemu -T test/baremetal-qemu/link.ld \
    test/baremetal-qemu/startup.c test/baremetal-qemu/board.c /tmp/rev2/bm/c/prog.c \
    -o /tmp/rev2/bm/fw.elf
$ arm-none-eabi-nm -u /tmp/rev2/bm/fw.elf | wc -l
0
$ timeout 10 qemu-system-arm -M lm3s6965evb -display none -monitor none -serial stdio \
    -semihosting-config enable=on,target=native -kernel /tmp/rev2/bm/fw.elf
boot ok
tick=3
$ diff -u test/baremetal-qemu/prog.expected.out /tmp/rev2/bm/out.txt ; echo rc=$?
rc=0
```

`boot ok`（复位路径 + UART）、`tick=3`（SysTick 中断真的进 ISR）、QEMU 退出 0、
`nm -u` 为空、产物零系统头，与 TEST-20 的四条判据一致。**不通过项：无。**

## 3 B 部分：phase 任务级红证核对

方法：对 `phase65-draft.md` §9 / `phase66-draft.md` §9 列出的每个红证提交，
核对（a）存在 `test(...) 红` 提交；（b）`git rev-parse <impl>^` 等于该 test 提交；
（c）提交正文的 `baseline:` 值是 sha 且 `git merge-base --is-ancestor` 为真。
不重跑红证（按要求只核对）。

### 3.1 PH-65（R1–R7）

| 任务 | test 提交（红） | impl 提交 | `impl^ == test` | baseline 字段 | baseline 是 HEAD 祖先 | 判定 |
| --- | --- | --- | --- | --- | --- | --- |
| R1 | `3cfe6772` | `87aaad4e` | 是 | `7a66dcae` | 是 | 合规 |
| R2 | `9164e46c` | `6f7ec245` | 是 | `0b161355` | 是 | 合规 |
| R3 | `6c539422` | `03e3b81e` | 是 | `e7a3c519` | 是 | 合规 |
| R4 | `abe45eb4` | `dbb13cf5` | 是 | `7f2ee392` | 是 | 合规 |
| R5 | `604340ef` | `8196ece4` | 是 | `4cc7d1fa` | 是 | 合规 |
| R6 | §9 写 `64fc41db` | **不存在 R6 实现提交** | 不适用 | 无（`64fc41db` 正文无 baseline） | — | **不合规** |
| R7 | `64fc41db` | `ef121c6c` | 是 | **缺 `baseline:`** | — | **不合规** |

逐条发现：

1. **R6 引用错误且无红/绿对**：`64fc41db` 的实际标题是
   `test(ast): PH-65-R7 红（C 边界文档）`，其父提交是 `983ecf33`
   （`PH-65-R6 接入门禁`），不是任何"R6 实现提交"。R6 的真实夹具提交是
   `d044860a`（`PH-65-R6 回归面探针`，父 `8c2824d3`），随后 `983ecf33` 仍是
   `test(...)` 提交；全历史 `--grep='PH-65-R6'` 只有这两个 `test` 提交，没有
   `feat`/`fix` 实现提交。`d044860a` 正文写的是
   `红证（baseline: 相位前 v0.63.4 构建 /tmp/p0/ct-head）`，也不是 sha。
   §9 把 R6 与 R7 都指向 `64fc41db`，属**引用错误**。
2. **R7 缺 baseline**：`ef121c6c^ == 64fc41db` 成立，但 `64fc41db` 正文
   （`git log -1 --format='%B'`）没有任何 `baseline:` 行，不满足 T-7 的最小字段。

### 3.2 PH-66（R1–R5）

| 任务 | test 提交（红） | impl 提交 | `impl^ == test` | baseline 字段（原文） | baseline 是 HEAD 祖先 | 判定 |
| --- | --- | --- | --- | --- | --- | --- |
| R1 | `c3f382c0` | `663546cb` | 是 | `v0.64.0 构建 /tmp/p0/ct-0640` | 是（tag→`c2aa952e`） | 不合规（非 sha） |
| R2 | `3fc6b51a` | `d9c00a1c` | 是 | `v0.64.0 /tmp/p0/ct-0640` | 是（tag→`c2aa952e`） | 不合规（非 sha） |
| R3 | `d4080bf6` | `f022ffc3` | 是 | `v0.64.0 /tmp/p0/ct-0640` | 是（tag→`c2aa952e`） | 不合规（非 sha） |
| R4 | `79eccf5f` | `c5c357f1` | 是 | `R3 完成 /tmp/p0/ct-p66r3c` | 未写 sha（R3 impl `f022ffc3` 是祖先） | 不合规（非 sha） |
| R5 | `ac55c523` | `d5e0fa80` | 是 | **无** | — | 不合规（缺 baseline） |

逐条发现：

1. **R1–R3**：`baseline:` 后的值是 tag 名 `v0.64.0`，不是 sha。tag 可解析为
   `c2aa952e` 且确是 HEAD 祖先，**实质**满足"实现落地前"，但**字面**不满足
   `baseline: <sha>`，无法机械校验。
2. **R4**：`baseline: R3 完成` 是状态描述，没有 sha；`/tmp/p0/ct-p66r3c` 是
   本地构建目录，不可追溯。
3. **R5**：`ac55c523` 正文完全没有 baseline 字段（`git log --format='%B'` 已核）。
   它虽是"纯文档"任务，卡片 §4 的 R5 行没有 `no-test: <理由>`，不能按 T-7 的
   纯文档例外豁免；即便豁免，红证字段仍缺 baseline。
4. 附带（不属 §9 表格）：PH-66 收口提交 `9c3f175e` 正文把 R5 实现写成
   `ab202b1f`，该对象在仓库中不存在（`git cat-file -t` 报 not a valid object
   name）；实际 R5 实现是 `d5e0fa80`。属提交正文笔误，不影响 §9 的 test 链。

### 3.3 任务清单与退出判据冻结

用每一版草案的 §4–§5 原文做 md5（`git show <c>:<file> | awk '/^## 4 /{f=1}
/^## 6 /{f=0} f' | md5`）：

```console
# phase65：ff35652c 立项 → c2aa952e 收口，共 11 个版本
89048797bebe57a461918cf46b3d85d0   # 11/11 完全相同
# phase66：3faa2126 立项 → 9c3f175e 收口，共 6 个版本
be092eaf90437e93db4c1cd086533947   # 6/6 完全相同
```

`git diff -U0 <立项> HEAD -- docs/design/phase65-draft.md` 的 hunk 只落在
第 3 行、74–75、118–120、189–204；§4/§5 位于 133–161，**未相交**。
phase66 的 hunk 只落在第 3 行、108–124；§4/§5 位于 64–86，**未相交**。
两者都只改了状态行、§3.4 可观测入口与收口对照表。

**结论：两 phase 的任务清单与退出判据在开工后未改动，冻结成立。**

## 4 与复核包/文档命令的差异

| 文档写的 | 实测 | 判定 |
| --- | --- | --- |
| `bash test/ast/p66_io_docs.sh` | 无参数、`$0` 定位仓库根 | 一致；该探针不需要 `<ct-ast>` |
| TEST-20 `run.sh <ct-ast>` | `run.sh` 注释写 `sh`，用 `bash` 调用同样通过 | 等价 |
| SH-91 用本机 `gcc` | 本机 `gcc` 是 clang；改用 podman GCC 13.5.0 | 环境差异，已按提示换工具 |
| SH-90 卡写 `v0.63.5` | HEAD `ct-ast v0.65.1` | 版本 token 差异，非回归 |

## 5 未覆盖声明

- 未重跑红证（按要求只核对提交关系与字段）；A 部分探针均为当前代码的绿证。
- 未跑全量 `selfhost/check-ast.sh`（1477/0）与 `selfhost/check-all.sh`（11/11）；
  这两项是 phase 级门禁，本轮只复跑条目自己的探针。
- 未用 GCC 复跑 `check-warnings.sh` 的 493 个产物；SH-91 只按复核要求用 GCC 13
  编空程序产物，确认无 `-Wunused-function`。
- podman GCC 为 amd64 仿真（宿主 arm64），仅用于 SH-91 的单文件编译判定。

## 6 台账动作

- [SH-89](../../issues/selfhost/sh89-libc-io-auto-include.md)、
  [SH-90](../../issues/selfhost/sh90-freestanding-compile-mode-layer.md)、
  [SH-91](../../issues/selfhost/sh91-unparsed-layer-symbol-residue.md)、
  [TEST-20](../../issues/testing/test20-baremetal-qemu-smoke.md) 状态写 `verified`，
  各追加「复核（REV，2026-11-18）」节。
- B 部分不合规项已在 §3 逐条列出，交 DEV/EDITOR 处置（补写 `baseline: <sha>`
  或纠正 §9 引用）；本文件不代改 phase 卡片。
- 本文件与四个 issue 单提交；纯文档/台账，按 V-4 不动版本号。
