# LANG-30 · `Str` / `String` 无直接打印入口，阻塞样例去指针

| 项 | 值 |
| --- | --- |
| 模块 | lang / lib-core（`Str`、`String`）+ docs |
| 定性 | **能力缺口**（REQ 提案；不是缺陷，不声称已有 API 丢失） |
| 严重度 | **Medium**（阻塞 `v1-PH-2` S8c 的 E3 类 26 个样例去指针） |
| 交付窗口 | **v1.2 必做（所有者 2026-11-27）**：必须在 S8c 收口前落地，是 E-V3-9c 的一部分，不顺延到 v1.3 |
| 锚点 | `55c82d16`（2026-11-27） |
| 依据 | [str-print-api 提案](../../docs/proposals/str-print-api.md)、[pointer-free-exemptions](../../docs/planning/pointer-free-exemptions.md) E3、[D-013](../../docs/decisions/D-013.md) |
| 状态 | verified |
| 负责人 | **DEV**（实施）；REVIEW 复核 + ADR 签收；REQ 验收 |
| 处置证据 | 提案已交（2026-11-27）：推荐 `Str.print()` / `Str.println()`，零分配。**所有者 2026-11-27 批准方案 A**，施工卡已交 DEV：[lang30-str-print-construction](../../docs/design/lang30-str-print-construction.md)（P1–P2 前置 + T1–T6）。实现已落（`lib/core/Str.h.ct`、`String.h.ct`、`Str.shim.h`，spec §4.78）；REQ 验收见 §4.1，`test/ast/lang30_print.sh` 7 项全过。ADR [D-030](../../docs/decisions/D-030.md) 仍为 `proposed`，**待 REVIEW 签收**（非作者席位，REQ 不自签）。 |

## 1 现象

`lib/core` 的 `Str` / `String` 没有直接输出入口。`cstr()` 会**分配**一份 NUL 结尾的
C 字符串并要求调用方 `free`（`String.h.ct:118-119`、`Str.h.ct:122`），所以
「把字符串打印出来」在 Ct 里只能写成：

```ct
printf("%s\n", s.cstr());
free(那个返回值);
```

这不是去指针，而是把指针换成一次分配。`examples/` 里因此有 26 个文件（E3 类）无法完成
[TEST-27](../testing/test27-feature-examples-pointer-free.md) 的「非 C 互操作样例指针清零」。

## 2 为什么不是缺陷

`cstr()` 的行为与文档一致（分配 + 调用方释放），`printf` 的 `%s` 也只认 C 字符串（C 语义）。
缺的是**借用视图的输出 API**，属于语言/内置层的增量能力，按 REQ 流程走。

## 3 提案要点

完整对比见 [str-print-api](../../docs/proposals/str-print-api.md)。推荐方案 A：

- `Str.print()` / `Str.println()`：按字节写 stdout，零分配；
- `String` 同名转发到 `as_str()`；
- `cstr()` 保留，只用于 C 互操作；
- `fwrite` 的声明走 `.m.ct` / shim（与 S9 同方向），不改 §4.67 的补头集合。

## 4 验收

1. `print` / `println` 在 `ct build` 与 `ct compile` 下可用、零分配（ASAN 无泄漏）；
2. E3 的 26 个 examples 改写后 `char *` / `cstr()` / `free` 清零，输出逐字节不变；
3. `check-warnings` / `check-ast` / `check-docs` 绿；改 `selfhost/**` 时 seed 两轮逐字节；
4. spec 新节 + glossary + tutorial 同步；ADR 记录「方法 vs 内建函数」的裁定。

### 4.1 验收结论（REQ，2026-11-27）

四条验收逐条核对，全部通过：

1. **双模式可用、零分配**：`bash test/ast/lang30_print.sh <ct>` 7 项全 `ok`（末行
   `lang30_print: OK`），覆盖 `ct compile` 与 `ct build` 两条路径、两次运行字节一致、
   emitted body 无 `malloc` / `free` / `cstr`、ASAN 无泄漏、`ct_str_live_count()` 归零。
2. **长度语义**：独立探针 `Str s = "a\0b"; s.println();` 的 `od -An -c` 输出
   `a \0 b \n`——按 `len` 写 4 字节而非遇 `\0` 截断；空视图 `print()` 写 0 字节、
   `println()` 只写 `\n`。生成的 `Str_print` 仅一条 `fwrite`，`Str_println` 为
   `fwrite` + `fputc('\n')`。
3. **E3 去指针**：`examples/` 中 `.cstr()` 计数已清零（`48_string_steps` 等改用
   `print` / `println`）；本轮补修 `examples/53_match_adt/prog.ct`（`body.cstr()` →
   `body.println()`，原先漏 `free` 属泄漏），`ct build` 输出仍为 `hi`。
4. **门禁**：`check-warnings` / `check-ast` / `check-docs` 通过（`check-docs` 仅余
   他人并发改动引入的 `docs/decisions/D-013.md` 死链，与本条无关）；`p85_m0`
   重生成语料 pin 后 `4 passed, 0 failed`；未改 `selfhost/**`，seed 不变。

遗留：`D-030` 状态仍是 `proposed`，需 REVIEW 以非作者席位签收后改 `accepted`；
本条验收不替代 ADR 签收。

## 5 非目标

- 不做格式化、不做 stderr、不做宽字符、不抽 `io::Writer`；
- 不改 `cstr()` 语义，不删任何现有 API；
- 不借本条改 `std::io`（包侧独立）。

## 6 关联

- [lang30-str-print-construction](../../docs/design/lang30-str-print-construction.md)（**施工卡，DEV 入口**）
- [str-print-api](../../docs/proposals/str-print-api.md)（提案）
- [REQ-PRINT-1](../../docs/planning/requirements-pool.md)（需求池）
- [TEST-27](../testing/test27-feature-examples-pointer-free.md)（S8c 交接单）
- [pointer-free-exemptions](../../docs/planning/pointer-free-exemptions.md)（E3 清单）
