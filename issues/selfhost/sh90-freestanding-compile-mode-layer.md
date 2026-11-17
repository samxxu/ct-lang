# SH-90 · `--freestanding` 在 compile 模式下仍拼接内置层（带 stdio/malloc）

| 项 | 值 |
| --- | --- |
| 模块 | selfhost（`frontend/module` 的内置层加载 / `backend/emit`） |
| 类型 | 契约违背（REQ-HW-010/011 说 freestanding 不隐式拉 std） |
| 严重度 | Medium（产物带 libc 头与 Str 代码；`-nostdlib` 链不上） |
| 状态 | verified |
| 锚点 | `v0.63.4`（`72ed6dc6`） |
| 承诺出处 | [REQ-HW-010/011](../../docs/planning/hardware-readiness-requirements.md)、[PH-64 卡](../../docs/design/phase64.md) |

## 现象

compile 模式（单文件）下 `--freestanding` 不会跳过内置层：

```console
$ ct-ast --freestanding test/baremetal-qemu/prog.ct -o /tmp/p.c ; echo $?
0
$ grep -c '#include <' /tmp/p.c
3
$ grep -n 'malloc' /tmp/p.c | head -2
66:    r.data = (char *)(malloc(((size_t)(n) + 1)));
```

产物里有 `#include <stdio.h>/<stdlib.h>/<string.h>` 与 `Str` 单元的 `str_from` 等实现；
`arm-none-eabi-gcc -nostdlib` 链接时找不到这些符号。build 模式（`ct build --freestanding
--emit-c`）是对的：只发 `prog.c`、没有系统头。

## 原因

按需单元（PH-64 T2）只在 `build` 路径的 emit 前算 `builtin_live`；compile 模式走
`load_builtin` 的无条件拼接，`--freestanding` 只关掉了 constructor 与未映射堆的硬错，
没有关掉层本身。

## 期望行为

`--freestanding` 下 compile 模式也不隐式加载内置层；用到容器/`Str` 时给明确诊断
（提示用 `ct build` 或不用 freestanding）。

## 处置（v0.63.5）

- 提交 `506039e8`（红证 `be24fd4f`，baseline `22500ad5`）。
- `Driver::load_builtin` 在 `m->freestanding` 时返回 -1：compile 模式不再加载内置层。
- 验证：`p64_freestanding` 新增 compile 模式断言后 `OK p64free`；`check-all` 11/11、
  `check-ast` 1465/0。

## 关联

- 发现于 [TEST-20](../../issues/testing/test20-baremetal-qemu-smoke.md) 的 QEMU 冒烟（该冒烟走 build 模式，故不受影响）；
- 与 [SH-89](sh89-libc-io-auto-include.md) 相邻但不相同（那条是自动补头策略）。

## 复核（REV，2026-11-18）

| 项 | 值 |
| --- | --- |
| 复核人 | REV |
| HEAD | `8739ec96`（`ct-ast v0.65.1`；macOS arm64 / Apple clang 21.0.0） |
| 结论 | `verified` |

命令与原始输出（`W=/tmp/rev2`）：

```console
$ env -u CT_C_BOUNDARY bash test/ast/p64_freestanding.sh "$W/ct-ast" ; echo rc=$?
OK p64free
rc=0
```

探针 `test/ast/p64_freestanding.sh:131` 起即本条的 compile 模式断言：单文件
`--freestanding` 产物必须无 `#include <…>`、无 `malloc(`。`OK p64free` 表示
三组 build 符号面断言 + compile 断言全部通过。无失败项。
逐条对照见 [复核结论](../../docs/reviews/2026-11-18-fix-rev-verdict-batch2.md) §2.2。
