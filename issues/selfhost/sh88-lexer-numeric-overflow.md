# SH-88 · 词法器数字累加有符号溢出（UBSAN 门禁在 20 位字面量上红）

| 项 | 值 |
| --- | --- |
| 模块 | selfhost（`frontend/lex`：数字扫描的 `toknum` 累加） |
| 类型 | 未定义行为（整数溢出；不产生错值，但 UBSAN 中止） |
| 严重度 | Medium（编译器自身 UB；`check-sanitizers` 因此失败） |
| 状态 | verified |
| 锚点 | `v0.63.0`（`369a2606`） |
| 承诺出处 | [AGENTS §6 验证](../../AGENTS.md)；[nightly 工作流](../../.github/workflows/nightly.yml) 的 ASAN/UBSAN 门禁 |

## 现象

`test/ast/errors/range_init_overflow.ct` 用 20 位字面量 `0..99999999999999999999`。
`check-sanitizers` 在 `CC=gcc` 的 Ubuntu 24.04 上：

```console
$ bash selfhost/check-sanitizers.sh
  FAIL  range_init_overflow: ct-ast emitted a sanitizer report
check-sanitizers: FAIL (5 failed, 579 passed)
```

`range_bound_value`（`frontend/parse/Stmt.h.ct:781`）本来就会重读拼写并按 `LONG_MAX` 判溢出，
但**词法器先累加**（`frontend/lex/Lexer.h.ct:130/139/145` 的 `toknum * base + d`），
20 位十进制在 `long` 上溢出，属未定义行为。

## 期望行为

扫描器不得对任何输入触发有符号溢出；超范围字面量由需要该值的一方报错。

## 处置（v0.63.1）

`Lexer` 增 `num_accumulate(v, base, d)`：溢出时饱和到 `LONG_MAX`，三处累加改用它。
`range_bound_value` 仍在重读拼写时报 2（out of `long`），因此诊断与退出码不变。

## 关联

- [SH-87](sh87-builtin-str-live-false-negative.md)：另一条 P1，尚未修；
- 门禁侧：`check-sanitizers.sh` 的 build 模式支持与 CI 的 clang 运行时安装在同一个 CI 修复里完成。

## 复核（REV，2026-11-17）

| 项 | 值 |
| --- | --- |
| 复核人 | REV |
| HEAD | `72ed6dc`（`ct-ast v0.63.4`；macOS 27.2 arm64 / Apple clang 21） |
| 结论 | `verified` |

命令与原始输出：

```console
$ CC=gcc bash selfhost/check-sanitizers.sh ; echo rc=$?
cc: …/cc-san (-fsanitize=address,undefined -fno-omit-frame-pointer)
…
  ok    range_init_overflow
…
check-sanitizers: OK (581 checks, no sanitizer report)
rc=0
```

说明：本机 `/usr/bin/gcc` 实为 Apple clang 21.0.0，`-fsanitize=address,undefined` 运行时可用，
因此未 `skip`；20 位字面量夹具在 UBSAN 下 `ok`。计数 `581` 较复核包的 `580` 多一个，
是 HEAD 语料较 v0.63.2 增加了一个夹具，非回归。逐条对照见
[复核结论](../../docs/reviews/2026-11-17-fix-closeout-rev-verdict.md) §2.3。
