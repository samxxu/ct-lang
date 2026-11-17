# 2026-11-17 修复批次收口复核结论（REV）

| 项 | 值 |
| --- | --- |
| 性质 | 复核结论（REV）；`status` 按 5.4 由 REV 写入 issue |
| 复核包 | [2026-11-17-fix-closeout-review.md](2026-11-17-fix-closeout-review.md) |
| 复核日期 | 2026-11-17 |
| 复核者 | REV |
| HEAD | `72ed6dc`（`72ed6dc6119e9cb04d37c4030f3140238a46d63e`，`ct-ast v0.63.4`） |
| 结论 | **4/4 通过**：SH-86 / SH-87 / SH-88 / TEST-19 均 `verified` |

## 0 环境

```console
$ uname -m
arm64
$ uname -sr
Darwin 27.2.0            # macOS 27.2（26B123）
$ cc --version | head -1
Apple clang version 21.0.0 (clang-2100.4.1.1)   # Target: arm64-apple-darwin27.2.0
$ git rev-parse --short HEAD
72ed6dc
```

- 本机 `/usr/bin/gcc` 实际是 Apple clang 21.0.0（没有 GNU GCC）；
  `-fsanitize=address,undefined` 运行时可用，故 SH-88 未跳过，用 clang 的 ASAN/UBSAN 实测。
- TEST-19 的 x86-64 对照：podman 6.2.0 + `--arch amd64` + `docker.io/library/gcc:13`。

## 1 前置构建（一次性，`W=/tmp/rev`）

复核包写 `W=/tmp/review`；本轮按指示改放 `/tmp/rev`，步骤与产物相同。

```console
$ cc -Wall -Wextra -std=c99 selfhost/l0/ctc.c -o "$W/ctc"
$ "$W/ctc" selfhost/l1/ctc.ct -o "$W/l1.c"
$ cc -Wall -Wextra -std=c99 "$W/l1.c" -o "$W/l1"
$ "$W/l1" build selfhost/l2/driver.ct -o "$W/l2src"
$ cc -Wall -Wextra -std=c99 "$W/l2src"/*.c -o "$W/l2"
$ "$W/l2" build -I selfhost/ct-ast selfhost/ct-ast/main.ct -o "$W/astsrc"
$ cc -Wall -Wextra -std=c99 "$W/astsrc"/*.c -o "$W/ct-ast"
$ "$W/ct-ast" --version
ct-ast v0.63.4
```

七步全部 `rc=0`。`v0.63.4` ≠ 复核包的 `v0.63.2`：HEAD 比复核包基线（`cbff2209`）新，
其后又有 PKG-10 / PKG-11 两个 fix；这是版本 token 差异，按 6.7 的 V-4 口径不是判据。

## 2 逐条结论

### 2.1 SH-86 通过

```console
$ "$W/ct-ast" test/ast/287_trait_array_vptr_init/prog.ct -o /tmp/r287.c ; echo rc=$?
rc=0
$ cc -std=c99 -Wall -Wextra -c /tmp/r287.c -o /tmp/r287.o ; echo rc=$?
rc=0
$ grep -c 'constructor' /tmp/r287.c ; echo rc=$?
0
rc=1                      # grep -c 零命中退 1；判据是计数 0
```

`cc -c` 退 0、constructor 计数 **0**，与验收一致。补强（非验收项）：

```console
$ cc -std=c99 -Wall -Wextra /tmp/r287.c -o /tmp/r287 && /tmp/r287 > /tmp/r287.out
$ diff -u test/ast/287_trait_array_vptr_init/prog.expected.out /tmp/r287.out ; echo rc=$?
rc=0                      # 数组元素 / const 对象 / [] 推导的 vptr 均已由初值写入
```

无初值数组仍走构造函数路径（`288_trait_array_noinit`：`grep -c constructor` = 1，运行输出与期望一致），
符合「无初值数组保持原路径」的期望。

多维硬错：

```console
$ "$W/ct-ast" test/ast/errors/trait_array_multidim.ct -o /tmp/r_multi.c ; echo rc=$?
test/ast/errors/trait_array_multidim.ct:18:1: error: a multi-dimensional array cannot hold trait-carrying values
rc=1
```

退 1，stderr 含 `a multi-dimensional array cannot hold trait-carrying values`，与验收一致。

### 2.2 SH-87 通过

```console
$ bash test/ast/p64_on_demand.sh "$W/ct-ast" ; echo rc=$?
OK p64ond
rc=0
```

探针三例齐备（`test/ast/p64_on_demand.sh:71-143`）：
① 只调层内小写函数（`str_from`/`str_len`）必须拉 `Str.c`；
② 用户 `struct Struct` 不得拉 `Str.c`；③ 超过 262143 B 的源里出现 `Str` 必须仍拉到。
`OK p64ond` 表示三例与既有两例（裸程序零容器单元、`Option<int>` 只拉 `Option`）全过。

### 2.3 SH-88 通过

```console
$ CC=gcc bash selfhost/check-sanitizers.sh ; echo rc=$?
cc: …/cc-san (-fsanitize=address,undefined -fno-omit-frame-pointer)

== build the bootstrap chain and the AST compiler (sanitized) ==
  ok    the chain builds (L0 -> L1 -> L2 -> ct-ast)

== L0 suite (test/run.sh, sanitized) ==
  ok    test/run.sh (no sanitizer report)
…
  ok    range_init_overflow
…
check-sanitizers: OK (581 checks, no sanitizer report)
rc=0
```

20 位字面量夹具 `test/ast/errors/range_init_overflow.ct` 在 UBSAN 下 `ok`（不再有
`signed integer overflow` 报告），全门禁 581 项零报告。`581` vs 复核包写的 `580`：
HEAD 语料比 v0.63.2 多一个夹具，计数随之 +1，不是回归。

### 2.4 TEST-19 通过

```console
$ python3 test/ast/check_eval_order.py ; echo rc=$?
eval-order: 1265 sources, 0 order-dependent print calls
rc=0
```

0 命中；且 lint 自带红样例（`--self-test`：脏行必须被报出、干净行不得误报，`rc=0`），
证明 0 命中不是空转。

x86-64 对照（podman + amd64）：

```console
$ CT_STD_DIR="$PWD/lib/std" "$W/ct-ast" test/ast/241_map_str_key/prog.ct -o .temp/r241/241.c ; echo rc=$?
rc=0
$ podman run --rm --arch amd64 -v "$PWD/.temp/r241":/w docker.io/library/gcc:13 \
    bash -c 'cd /w && gcc -std=c99 241.c -o a && ./a > out.txt' ; echo rc=$?
rc=0
$ diff -u test/ast/241_map_str_key/prog.expected.out .temp/r241/out.txt ; echo rc=$?
rc=0
```

`out.txt` 的关键行已是 `remove=1 len=1`（修复前 x86-64 上该行为 `len=2`）；
arm64 本机用同一份 `.c` 复跑，`diff` 同样无差异——两平台一致。

## 3 全量门禁（复核包 §2 末行）

```console
$ bash selfhost/check-all.sh ; echo rc=$?
…
== summary: 1463 passed, 0 failed, 0 skipped ==
…
check-all: OK (11 hard gates green)
rc=0
```

`check-ast` 1463/0，与复核包一致的 `check-all: OK (11 hard gates green)`。

## 4 与复核包的差异（均为口径差异，不构成回归）

| 复核包写的 | 实测 | 判定 |
| --- | --- | --- |
| `--version` 期望 `ct-ast v0.63.2` | `ct-ast v0.63.4` | HEAD 更新（PKG-10/11 两个 fix）；版本 token 差异，非判据 |
| `check-sanitizers: OK (580 checks…)` | `581 checks` | 语料 +1 个夹具，计数随语料变；非回归 |
| `bash test/ast/check_eval_order.py` | `bash` 跑 `.py` → 语法错误 `rc=2`；`python3` → `rc=0` | 复核包命令笔误（脚本 Usage 即 `python3`）；按 `python3` 判 |
| `grep -c 'constructor'` 期望 `0` | 计数 `0`、`grep` 退 `1` | `grep -c` 零命中的正常语义 |
| `cc -c /tmp/r287.c`（无 `-o`） | 加 `-o /tmp/r287.o` | 等价（产物不入库） |

红证签字：四个条目的红证（`baseline: 9929fa8d` 等、`566f8e1b` / `47f7c339` / CI 日志）
仍由 DEV 自签（`deviation: single-session-workflow`）；T-7 规定用当前代码复跑不算红证，
本轮 REV 只验绿，不重跑红证。此为本轮未覆盖项，如实登记。

## 5 台账动作

- [SH-86](../../issues/selfhost/sh86-trait-array-const-vptr.md)、
  [SH-87](../../issues/selfhost/sh87-builtin-str-live-false-negative.md)、
  [SH-88](../../issues/selfhost/sh88-lexer-numeric-overflow.md)、
  [TEST-19](../../issues/testing/test19-unspecified-eval-order.md) 状态写 `verified`，
  各追加「复核（REV，2026-11-17）」节。
- 本文件与四个 issue 单提交；纯文档/台账，按 V-4 不动版本号。
