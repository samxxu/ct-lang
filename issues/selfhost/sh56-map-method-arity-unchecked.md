# SH-56 · 映射方法的实参个数不校验，多余实参被静默丢弃

| 项 | 值 |
| --- | --- |
| 模块 | selfhost（ct-ast 调用点） |
| 严重度 | Medium |
| 锚点 | `v0.19.1`（2026-11-06） |
| 文件 | [frontend/parse/Expr.h.ct:1562-1586](../../selfhost/ct-ast/frontend/parse/Expr.h.ct#L1562-L1586) |
| 状态 | 待修 |

## 现象

19.1 的调用点 arity 检查只对「解析出来的、非静态的 trait 方法」生效。`Expr.h.ct:1562-1567` 的注释
自己写明了豁免面：

```c
/* 19.1: a resolved trait method is compared against the call's
   argument count. A static trait (a `.m.ct` recipe), a `map`
   binding (the receiver's type stays in `text`) and a call
   through a function-pointer field (`kind` became N_CALL) are
   all unknown here and pass. */
```

于是 `std::str` / `std::fs` / `std::utf8` 这类**静态映射**（`.m.ct` 的 `map trait … for type char *`）
在调用点多写实参时：编译通过、退出码 0、多余实参在生成的 C 里**直接消失**。trait 声明里其实有完整
参数表（`String.m.ct` 的 `pub trait String`），只是这个分支不查。

少写实参不属于静默：生成的 C 调用少参，`cc` 会报 `too few arguments`。危险的是**多写**。

## 最小复现

复现于 ct-pkg 包 **`std` 0.1.0**（`ct get std` 拉入项目的 `vendor/std`；std 已迁出本仓库，`-I .` 不再适用）。

```ct
/* arity.ct */
import std::str::String;

int main(void)
{
    int n = "abc".len(1);
    return n == 3 ? 0 : 1;
}
```

```text
$ ct get std && ct install
$ ct build -I vendor/std --emit-c arity.ct -o out
cc -std=c99 -I out out/arity.c -o a.out
$ sed -n '/int main/,/^}/p' out/arity.c
int main(void) {
    int n = std_str_len(("abc"));
    return ((n == 3) ? 0 : 1);
}
```

`len(1)` 里的 `1` 没有进入生成物，退出码 0。

`ct check` 也覆盖不到：它只接受单文件单元，`import` 直接被拒（见
[SH-55](sh55-import-reject-message-not-actionable.md) / [DOC-65](../docs/doc65-compile-import-boundary-undocumented.md)），
所以这类文件没有任何一道门禁会检查调用点 arity。

## 影响

源码写了 2 个实参、实际执行的是 1 个实参的语义，中间没有任何提示。与
[SH-29](sh29-max-fields-silent-drop.md)（第 65 个字段静默丢弃）、
[SH-34](sh34-file-scope-borrow.md)（文件作用域 `borrow` 静默接受）、
[SH-32](sh32-multi-input-silently-ignored.md)（多输入只编最后一个）同族：
**输入被丢弃，编译器仍以 0 退出**。

## 期望行为

映射方法在声明侧已有参数个数（`traits[t].m[mi].nparams`），静态 trait 不应走豁免分支：

- 实参个数与 trait 声明不符时给出诊断。最小改动是与 19.1 一致——compile 模式告警、
  `ct check` 报 `error:` 并 exit 1；
- 若要更严格，多余实参直接硬错 `too many arguments to method 'len' (expected 0, got 1)`。

同时补一条回归：`ast` fixture 覆盖「静态映射多一个实参」，并断言 compile 侧输出（或至少
`--emit-c` 里不出现被丢弃的实参）。
