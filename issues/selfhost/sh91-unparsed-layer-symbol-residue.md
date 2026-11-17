# SH-91 · 未使用的层单元仍被解析：静态声明无定义（GCC 警告；CI 红）

| 项 | 值 |
| --- | --- |
| 模块 | selfhost（`tool/driver/Driver.h.ct` 的 compile 模式层加载） |
| 类型 | 回归（PH-66 R3 引入） |
| 严重度 | High（`check-warnings` 在 Ubuntu/GCC 上红，CI `ubuntu-gcc` 失败） |
| 状态 | verified |
| 锚点 | `v0.65.0`（`9c3f175e`） |
| 承诺出处 | [PH-66 卡](../../docs/design/phase66-draft.md) R3；[D-008](../../docs/decisions/D-008.md) |

## 现象

CI `ubuntu-gcc` 在 v0.65.0 上红（run 44131513213）：

```console
FAIL  01_hello: generated C warns: …:6:37: warning: 'Str_Drop_drop' declared 'static' but never defined [-Wunused-function]
…（test/cases 大量条目同一条警告）
```

## 原因

R3 让 compile 模式"按需拼接内置层"，但决策发生在**解析之后**：未使用的层单元照样解析，
其 `Str_Drop_drop` 等符号进入符号表；splice 时跳过该单元，于是发射器只声明、不定义，
GCC 报 `-Wunused-function`（clang 不报，所以本机 macOS 绿）。

## 处置

把决策提前到解析**之前**：按输入源整词判断（`Vec`/`Map`、`Option`、`Result`、`Str` 或
`str_` 前缀），未命中就完全不解析该单元。附带删除 `layer_used`（解析后判定的旧实现）。

判据：不引用层的产物不再出现 `Str_Drop_drop`；`test/cases/**` 在 GCC 下 `-Wall -Wextra`
零警告。

## 处置记录

- 修复提交见本轮 `fix(ct-ast): SH-91 …（v0.65.1）`；红证父提交 `aa7213ad`。
- 验证：`p66/io-empty` OK；`check-warnings` 493/0；`check-all` 11/11。

## 关联

- 红证：[p66_io_empty 的 `Str_Drop_drop` 断言](../../test/ast/p66_io_empty.sh)；
- CI：run 44131513213 的 `ubuntu-gcc` 原始日志。

## 复核（REV，2026-11-18）

| 项 | 值 |
| --- | --- |
| 复核人 | REV |
| HEAD | `8739ec96`（`ct-ast v0.65.1`；macOS arm64 / Apple clang 21.0.0） |
| 结论 | `verified` |

命令与原始输出（`W=/tmp/rev2`；本机 `gcc` 实为 Apple clang，GCC 用 podman）：

```console
$ env -u CT_C_BOUNDARY bash test/ast/p66_io_empty.sh "$W/ct-ast" ; echo rc=$?
OK p66/io-empty
rc=0
$ CT_STD_DIR="$PWD/lib/std" "$W/ct-ast" /tmp/rev2/probe/empty.ct -o /tmp/rev2/probe/empty.c
$ grep -c 'Str_Drop_drop' /tmp/rev2/probe/empty.c ; grep -c '^static' /tmp/rev2/probe/empty.c
0
0
$ podman run --rm -v "$PWD":/src:ro docker.io/library/gcc:13 \
    sh -c 'gcc --version | head -1; gcc -Wall -Wextra -std=c99 -c /src/.temp/rev2/empty.c -o /tmp/empty.o'
gcc (GCC) 13.5.0
$ echo rc=$?
rc=0
```

GCC stderr 为空（警告计数 0），无 `-Wunused-function`、无
`declared 'static' but never defined`；产物无系统头、无未定义静态声明。
`p66_io_empty.sh:50-53` 的 `Str_Drop_drop` 断言已由 `OK p66/io-empty` 覆盖。
无失败项。逐条对照见
[复核结论](../../docs/reviews/2026-11-18-fix-rev-verdict-batch2.md) §2.3。
