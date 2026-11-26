# 提案：`Str` / `String` 的直接打印入口

> **状态：提案（2026-11-27），待 REVIEW / 所有者裁定。** 对应 [REQ-PRINT-1](../planning/requirements-pool.md)
> 与 [LANG-30](../../issues/lang/lang-30-str-print-api.md)；实施要等一条 ADR 与新 spec 节。
> 本提案只解决「把借用视图写到 stdout」这一件事，不引入格式化系统。

## 0 问题

`examples/` 里 26 个文件（[pointer-free-exemptions](../planning/pointer-free-exemptions.md) 的 E3 类）
仍用 `char *` + `printf("%s", …)`。原因是 `Str` / `String` **没有直接输出入口**：

| 现状 | 位置 |
| --- | --- |
| `String.cstr()` / `Str.cstr()` 分配一份 NUL 结尾的 C 字符串，调用方 `free` | `lib/core/String.h.ct:118-119`、`lib/core/Str.h.ct:122` |
| `lib/core` 没有 `print` / `puts` / `write` 一类文本出口 | `grep 'pub .*print' lib/core/*.ct` → 无命中 |
| `printf` 的 `%s` 只认 C 字符串 | C 语义；spec §4.67 只补头，不做格式转换 |

于是「去指针」只能变成「`cstr()` + `free`」，指针没消失，还多一次分配。这不满足
[TEST-27](../../issues/testing/test27-feature-examples-pointer-free.md) 的目标，也不符合
`Str` 作为零分配借用视图的定位。

## 1 方案对比

| 方案 | 形态 | 优点 | 缺点 |
| --- | --- | --- | --- |
| **A（推荐）** | `Str.print()` / `Str.println()`，`String` 同名转发（内部 `as_str()`） | 零分配、零格式串、与 `Str` 语义一致；调用点 `name.print()` 读起来像方法 | 需要一处 lowering（`fwrite(ptr, 1, len, stdout)`）；`println` 在 Windows 文本模式下 `\n` 与 `\r\n` 需说明 |
| B | 内建函数 `ct_print(Str)` / `ct_println(Str)` | 与 `ct_*` 内建族一致；不改方法表 | 自由函数风格，与 `Vec`/`Map` 方法面不一致；名字进入用户命名空间风险更高 |
| C | 扩展 `printf` 格式串（`%v`） | 与现有 `printf` 写法最接近 | 改 C 语义、影响所有格式串；与「不重写 C 字面量」的既有约束冲突 |

推荐 **A**；B 作为 A 不可行时的退路。C 不采纳。

## 2 方案 A 的契约（草案）

```ct
Str s = "hello".as_str();
s.print();                 // 写 stdout，无换行
s.println();               // 写 stdout + 一个 '\n'
String owned = "world";
owned.print();             // String 转发到 as_str()
```

| 项 | 约定 |
| --- | --- |
| 输出目标 | 只做 stdout；stderr 留给后续（`print_err` 不在这条 REQ） |
| 字节语义 | 按字节写出（`Str.len` 是字节长度），UTF-8 原样透传；不做编码转换 |
| 分配 | **零分配**：内部直接用 `ptr` + `len`，不调用 `cstr()` |
| 返回 | `void`；写失败不报错（与 `printf` 一致，错误另立） |
| 空视图 | `len == 0` 时写 0 字节，不写越界 |
| `cstr()` | 保留，只用于 C 互操作；文档标注「会分配」 |
| 与 `printf` 的关系 | 不替代 `printf`；`ct build` 的补头规则（§4.67）不变 |
| 生成 C | 读起来就是一次 `fwrite`（或等价循环），可读性优先，不要求最短 |

## 3 落点与成本

| 层 | 改动 | 估算 |
| --- | --- | --- |
| `lib/core/Str.h.ct` | `print` / `println` 两个方法 | ~20 行 |
| `lib/core/String.h.ct` | 两个转发方法 | ~8 行 |
| 编译器 | 若走方法 lowering，需要 `fwrite` 的 C 边界声明（`<stdio.h>` 已按 §4.67 补头，`fwrite` 不在补头集合内） | 1 条边界声明或 shim |
| 测试 | `test/ast/*_str_print` 正例 + 空视图 + `String` 转发 | 1 夹具 |
| 文档 | spec 新小节（§4.78 拟）+ glossary + tutorial；README 0.5 段改用 `print()` | 3 处 |

**关键待定**：`fwrite` 不在 §4.67 的自动补头集合里。要么把它加进补头集合（改 spec，
影响面大），要么在 `lib/core` 里用 `.m.ct` / shim 声明（与 S9 的迁移方向一致，推荐后者）。

## 4 验收（提案通过后由 DEV 实施）

1. `Str` / `String` 的 `print` / `println` 在 `ct build` 与 `ct compile` 下都可用，零分配（ASAN 无泄漏）；
2. E3 的 26 个 examples 改写后 `char *` / `cstr()` / `free` 清零，输出逐字节不变；
3. `check-warnings` / `check-ast` / `check-docs` 绿；改 `selfhost/**` 时 seed 两轮逐字节；
4. spec 新节 + glossary + tutorial 同步；ADR 记录「为什么是方法而不是内建函数」。

## 5 非目标

- 不做格式化（`printf` 已存在）、不做 stderr、不做宽字符、不做 `io::Writer` 抽象；
- 不改 `cstr()` 的语义，不删除任何现有 API；
- 不借这条 REQ 顺带改 `std::io`（包侧独立）。

## 6 关联

- [REQ-PRINT-1](../planning/requirements-pool.md)
- [LANG-30](../../issues/lang/lang-30-str-print-api.md)（跟踪条）
- [pointer-free-exemptions](../planning/pointer-free-exemptions.md)（E3 的 26 个文件）
- [TEST-27](../../issues/testing/test27-feature-examples-pointer-free.md)
- [D-013](../decisions/D-013.md)（String / Str 的复制与引用计数契约）
