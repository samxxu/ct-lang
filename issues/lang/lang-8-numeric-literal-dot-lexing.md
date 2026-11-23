# LANG-8 · 裸 `5.method()` 词法失败（`5.` 被扫成浮点字面量）

| 项 | 值 |
| --- | --- |
| 模块 | lang（词法） |
| 严重度 | Low |
| 优先级 | **P3** —— 加空格即可绕；但与 C 的同一歧义同源，登记备查 |
| 状态 | verified |
| 处置证据 | **deferred**（2026-11-22，REV/REQ：§4.24 按 C 词法把 `5.` 读成浮点字面量是既有设计；待语言侧裁定「方法调用语法是否优先于浮点字面量」。触发：该裁定或下一次 Lexer 批次（`LANG-16 → LANG-8`，post-58-plan.md:115）；负责人 REQ/EDITOR 裁定后交 DEV；P3 Low） |
| 锚点 | `v0.53.1`（`c4727787`） |

## 精确触发条件

数字字面量后**紧跟** `.` 且左侧没有空格：`5.foo()`。词法器按 C 规则把 `5.` 收成浮点字面量，
随后 `foo` 成为相邻 token，后缀 `.` 已不存在。

## 最小复现

```ct
#include <stdio.h>
int main(void) {
    int n = 5.foo();
    printf("%d\n", n);
    return 0;
}
```

```sh
ct-ast a8.ct -o a8.c
```

## 实际行为

```text
a8.ct:3:16: error: unexpected token
rc=1
```

同一份源码加空格（`5 . foo()`）后词法正常，改报语义错：

```text
a8b.ct:3:1: error: no method 'foo' for type 'int'
```

## 期望行为

两种写法等价：`5.foo()` 与 `5 . foo()` 都按「对 `int` 调方法」解析，报同一条 `no method …`。
（C 语言里 `5.foo` 同样不合法，所以是否算缺陷取决于是否主张「CT 的方法调用语法优先于浮点字面量」；
登记以待决策，不在本轮修复。）

## 影响面

小：用户加空格即可绕；只有当字面量接收者要直接调方法时才遇到。
`std::Str` 之类字符串字面量不受影响（`"x".len()` 无歧义）。

## 定位

词法器的数字分支把 `.` 计入浮点（`Lexer.h.ct` 的数字扫描），parser 的后缀 `.` 永远看不到它。

## 处置（REV/REQ，2026-11-22）

**结论：`deferred`。** 在干净归档 HEAD（`38cd4ae4`）重建 ct-ast v0.88.2，按本条「最小复现」
复跑，行为与原报告一致（`a8.ct` 用 `5.foo()`；`a8b.ct` 用 `5 . foo()`）：

```console
$ /tmp/ct-head-rev/.temp/b/ct-ast a8.ct -o a8.c
a8.ct:3:16: error: unexpected token
rc=1
$ /tmp/ct-head-rev/.temp/b/ct-ast a8b.ct -o a8b.c
a8b.ct:3:1: error: no method 'foo' for type 'int'
rc=1
```

**为什么不现在修**：`docs/language-spec.md` §4.24 已把浮点字面量定为按 C 拼写读取
（`<digits>.<digits>`、`.5`、指数与后缀），词法器把 `5.` 收成浮点字面量是既有设计。
本条真正要定的是「方法调用语法是否优先于浮点字面量」，属语言表面裁定，不是词法器漏扫。
`docs/planning/open-items-routing.md:199` 曾把它排进 `0.53.9`，但该批已过期且没有裁定记录；
当前可用绕法是加空格（`5 . foo()`）。

**触发/下一步**：

1. REQ/EDITOR 在 §4.24 或 §4.5 明确数字字面量后直接 `.` 的归属；若坚持 C 口径，把本条改
   `rejected` 并在 spec 写明「`5.foo()` 不是方法调用」；
2. 若裁定方法调用优先，按 `LANG-16 → LANG-8` 的 Lexer 批次改数字扫描（`5.` 后紧跟标识符或
   `(` 时不吞 `.`），补 `5.method()`、`5.0`、`5..6` 三组夹具。

## 处置（DEV/REQ，2026-11-23）：维持 C 词法

**裁定：方法调用不优先于浮点字面量。** `5.foo()` 继续按 C 词法读成浮点 `5.f` +
标识符 `oo`（无后缀时是 `5.` + `foo`），不做词法器特判；规范只在 §4.24 记明归属。
`status` 字段不动（状态词归 REV/REQ 另走流程）。

可行动诊断已落地：解析器在相邻形态下把 `unexpected token` 换成
`a numeric literal followed by '.' is a float; add a space for a method call`；
`5 . foo()` 仍走方法解析并报 `no method 'foo' for type 'int'`。改动见提交
`fix(ct-ast): LANG-8 浮点后点号诊断`，探针 `test/ast/lang8_float_dot.sh`。

## 复核（REV/REQ，2026-11-23）

裁定维持 C 词法：`5.foo()` 报专门文案
`a numeric literal followed by '.' is a float; add a space for a method call`；
`5 . foo()` 仍 `no method`；spec §4.24 记明；`p lang8` 4/4。
