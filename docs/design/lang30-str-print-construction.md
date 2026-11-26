# 施工卡：`Str` / `String` 打印入口（LANG-30 / REQ-PRINT-1）

| 项 | 值 |
| --- | --- |
| 编号 | `LANG-30-C1`（`LANG-30` 的唯一施工切片） |
| 目标 | 给 `Str` / `String` 加零分配输出入口，解锁 S8c 的 E3 类 26 个样例去指针 |
| 方案 | [str-print-api](../proposals/str-print-api.md) **方案 A**（所有者 2026-11-27 批准） |
| 负责人 | **DEV**（起草 ADR、实现、自测）；**REVIEW** 复核 + ADR 签收 |
| 需求侧 | REQ（本卡作者；验收口径见 §4） |
| 前置 | 一条 ADR（拟 `D-030`，编号写前先核 `docs/decisions/`）；spec 新节（拟 §4.78） |
| 交付窗口 | **v1.2 必做（所有者 2026-11-27）**：必须在 S8c 收口前完成，是 [E-V3-9c](../phases/v1-PH-2/card.md) 的一部分；**不顺延** |
| 状态 | **待开工（ready for DEV）** |
| 约束 | 不改 C 语义、不动 `printf` 的补头集合、不删 `cstr()`、不碰 `std::io` |

> **为什么硬绑 v1.2**：E3 类 26 个样例（[pointer-free-exemptions](../planning/pointer-free-exemptions.md) §2）
> 的全部指针都卡在「字符串只能 `%s` 打印」这一点上。若本卡顺延，S8c 的 E-V3-9c 无法达成，
> 「去指针」只能停在 75/101；而这块成本只有 ~30 行 + 一条边界声明，没有理由留到 v1.3。
> 排期冲突时的让行顺序：**本卡优先于 S8b 的同文件集工作**（`lib/core` 与 S8b 的 `tool`/`runtime`/`sym`
> 不重叠），与 S2–S6 的编译器改动也不冲突。

## 1 范围

**做**：

- `Str.print()`：按字节把 `ptr[0..len)` 写到 stdout，零分配；
- `Str.println()`：同上 + 一个 `\n`；
- `String.print()` / `String.println()`：转发到 `as_str()`；
- `fwrite` 的声明：走 `lib/core` 的 `.m.ct` / shim（**不**扩 §4.67 的自动补头集合）；
- 夹具：正例、空视图、`String` 转发、含 `\0` 的长度语义各一条；
- spec 新节 + glossary + tutorial 同步。

**不做**：格式化、stderr、宽字符、`io::Writer` 抽象、`cstr()` 语义变更、`std::io` 改造。

## 2 前置（先做，否则不要动 `lib/core`）

| # | 产出 | 负责 | 判据 |
| --- | --- | --- | --- |
| P1 | ADR `D-030`：方法 vs 内建函数、为什么只做 stdout、`fwrite` 的声明路径 | DEV 起草，REVIEW 签收 | `docs/decisions/D-030.md` 按 T-8 带非作者 `签收:` 行；结论与 [str-print-api](../proposals/str-print-api.md) 一致 |
| P2 | spec 新节（拟 §4.78）：语法、字节语义、零分配、每条出口的 C 形态 | DEV（与实现同批提交） | `docs/language-spec.md` 目录新增一条可解析的 H3；`check-docs` 绿 |

## 3 任务分解

| # | 任务 | 文件 | 验收 | 估算 |
| --- | --- | --- | --- | --- |
| T1 | `Str` 两个方法 | `lib/core/Str.h.ct` | 生成 C 是一次 `fwrite`（或等价循环），无 `malloc`；空视图写 0 字节 | ~20 行 |
| T2 | `String` 转发 | `lib/core/String.h.ct` | `owned.print()` 与 `owned.as_str().print()` 同一产物形态 | ~8 行 |
| T3 | `fwrite` 边界声明 | `lib/core` 的 `.m.ct` / shim | 不调用 `#include`；`ct compile` 单文件也成立 | 1 个 shim 或 1 个映射单元 |
| T4 | 夹具 | `test/ast/7x_str_print/`（编号按当时空闲） | 正例 / 空视图 / `String` 转发 / 含 `\0` 各一条；`prog.expected.out` 为实测 | 1 目录 |
| T5 | 文档 | spec 新节、`docs/glossary.md`、`docs/tutorial.md` | `check-docs` 绿；glossary 有 `Str.print` 词条 | 3 处 |
| T6 | 语料 pin 与 seed | `test/probes/p85_corpus_sha.tsv`、`bootstrap/**` | 改 `selfhost/**` 时 seed 两轮逐字节；pin 同提交重生成 | 1 次 |

顺序：P1 → P2 → T1 → T3 → T2 → T4 → T5 → T6。T3 与 T1 可同批；T4 必须在 T1/T2 之后写（先红后绿）。

## 4 验收（REQ 复核口径）

1. 零分配：`Str.print()` / `println()` 的生成 C 里没有 `malloc` / `cstr` / `free`；
   ASAN 夹具无泄漏；
2. 长度语义：`Str` 含 `\0` 时按 `len` 写出全部字节（与 `%s` 的行为不同，夹具要钉住）；
3. 空视图写 0 字节，不越界；
4. `ct build` 与 `ct compile` 两种模式都可用；
5. `check-warnings` / `check-ast` / `check-docs` 绿；改 `selfhost/**` 时 seed 两轮逐字节；
6. 不改任何现有 API 的行为：`cstr()`、`printf("%s")`、`#include` 的补头集合逐字节不变。

## 5 回滚

- 全部改动在 `lib/core` + `test` + `docs`，不碰 `selfhost/**`（除 seed 重生成）；
- 单提交可 revert；revert 后 `check-goldens-ast` / `check-seed` 必须仍绿；
- 条目不进入 `docs/diagnostics/codes.md`（本卡不新增诊断码）。

## 6 风险

| 风险 | 处置 |
| --- | --- |
| `print` 这个名字与用户方法冲突 | 它是 `Str` / `String` 的方法而非全局名；用户实现同名方法时按既有 `impl` 规则遮蔽，不改解析 |
| Windows 文本模式把 `\n` 变 `\r\n` | `println` 的文档写明用 `\n`；真机差异记入 spec 已知限制，不在本卡加平台分支 |
| stdout 缓冲与 `printf` 交错 | 两者都走 stdio 缓冲，顺序一致；夹具里混用一次钉住 |
| `fwrite` 走 shim 后 `--freestanding` 不可用 | 文档写明：freestanding 下没有 stdout 概念，本 API 不适用 |

## 7 交接与报告

- 开工前在 [LANG-30](../../issues/lang/lang-30-str-print-api.md) 留一行 `开工：<分支/日期>`；
- 每完成 T1–T6 一片，在 issue 追加 `T<n> | 提交 | 门禁结果`；
- 全部完成后把 LANG-30 转 `open` → 待 REQ 复核 §4 后转 `verified`；
- E3 的 26 个 examples 改写**不在本卡**，由 TEST/REVIEW 按
  [TEST-27 §8](../../issues/testing/test27-feature-examples-pointer-free.md) 在本卡收口后进行。

## 8 关联

- [str-print-api](../proposals/str-print-api.md)（方案对比）
- [REQ-PRINT-1](../planning/requirements-pool.md)（需求池）
- [LANG-30](../../issues/lang/lang-30-str-print-api.md)（跟踪条）
- [pointer-free-exemptions](../planning/pointer-free-exemptions.md)（E3 清单）
- [TEST-27](../../issues/testing/test27-feature-examples-pointer-free.md)（S8c 交接单）
- [D-013](../decisions/D-013.md)（String / Str 的复制与引用计数契约）
