---
id: SH-95
title: "ref/out place 检查只看节点种类，f().x / bit-field / const 被放行"
status: verified
area: selfhost
severity: P1
opened: 2026-11-20
confirmed-by: REV-PH-78
---

# SH-95 · ref/out place 检查未递归到基址

## 来源

[PH-78 收口复核](../../docs/reviews/2026-11-20-phase78-rev-verdict.md) B2（E78-3 / R78-5）。

## 复现（baseline `ca3354a5`，ct-ast v0.78.0）

```ct
/* f().x */
struct P { int x; }
struct P mk(void) { struct P p = { 1 }; return p; }
void inc(ref int x) { x = x + 1; }
int main(void) { inc(mk().x); return 0; }
```

```ct
/* bit-field */
struct S { int x : 3; }
void inc(ref int x) { x = x + 1; }
int main(void) { struct S s = { 0 }; inc(s.x); return 0; }
```

```ct
/* const 变量 */
const int g = 1;
void inc(ref int x) { x = x + 1; }
int main(void) { inc(g); return 0; }
```

```console
$ ct check f.x.ct   # exit 0（应硬错）
$ ct build f.x.ct   # cc: cannot take the address of an rvalue
$ ct check bf.ct    # exit 0（应硬错）
$ ct build bf.ct    # cc: address of bit-field requested
$ ct check const.ct # exit 0（应硬错）
$ ct build const.ct # exit 0；运行 Bus error
```

## 期望

`ref`/`out` 的实参必须递归到基址的可赋值 place：

- 基址是调用结果/表达式（rvalue）→ CT 层硬错；
- 成员是 bit-field → CT 层硬错；
- 目标变量或字段带顶层 `const` → CT 层硬错；
- 数组、Vec、Map 元素（`*m[k]`）仍合法。

## 原因

`ref_arg_place()` 对 `N_MEMBER` / `N_ARROW` 只看 Vec/Map 下标糖，对 `N_INDEX`
直接返回 1，不检查基址是否 place、字段是否 bit-field、目标是否 const。

## 红证（baseline `ca3354a5`）

```console
$ CC=cc sh test/ast/p78_basic.sh build/ct-ast
FAIL p78/basic: SH-95 call-result member rejected
  ... bad_member_rvalue.c ...
bad_member_rvalue.ct:20:9: error: cannot take the address of an rvalue of type 'int'
FAIL p78/basic: SH-95 bit-field member rejected
  ... bad_bitfield.c ...
bad_bitfield.ct:16:9: error: address of bit-field requested
FAIL p78/basic: SH-95 const variable rejected
  accepted (expected a hard error)
exit=1
```

## 处置（DEV，2026-11-20）

`fixed` 主张：`ref_arg_place()` 现在递归到基址：

- `N_MEMBER` / `N_ARROW`：基址必须是 place（Map 元素指针 `m[k]->field` 例外），
  字段若是 bit-field 或顶层 `const` 则拒绝；
- `N_INDEX`：基址必须是 place；`N_DEREF`：基址是 place，或 Map 下标糖
  `*m[k]`；
- `N_VAR`：拒绝枚举常量与顶层 `const` 变量（`const int g`），保留
  `const int *p`（指针本身可写）；
- 调用结果/表达式不再被当作基址。

绿输出（v0.78.1 前的修复编译器）：

```console
$ CC=cc sh test/ast/p78_basic.sh build/ct-ast
ok   SH-95 call-result member rejected
ok   SH-95 bit-field member rejected
ok   SH-95 const variable rejected
p78_basic: OK
exit=0
```

提交：`git log --grep "SH-95"`。
