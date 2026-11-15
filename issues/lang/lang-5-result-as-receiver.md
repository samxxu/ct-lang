# LANG-5 · 方法 / 下标结果不能作接收者，字段形态还静默产出坏 C

| 项 | 值 |
| --- | --- |
| 模块 | lang（接收者物化 / 下标链） |
| 严重度 | **High**（字段形态是静默错误；方法形态有诊断） |
| 优先级 | **P1** —— 挡住 ct-json 的 `doc["k"].x` / 多级链 |
| 状态 | open |
| 锚点 | `v0.53.1`（`c4727787`） |

## 精确触发条件

「一次调用的结果」再作接收者：

1. 方法结果调方法：`f().m()` —— 硬错；
2. 自定义下标结果调方法：`b["k"].m()` —— 同一句硬错；
3. 自定义下标结果**取字段**：`b["k"].v` —— **不报错**，原样发射 `Box_get(&b, "k").v`，交 `cc`；
4. 多级链 `a["x"]["y"]["z"]` —— 单层限制先报「no subscript」。

## 最小复现

```ct
/* 2 */
struct Inner { int v; }
impl Inner { int twice(void) { return self->v * 2; } }
struct Box { }
impl Box { Inner get(const char *k) { (void)k; Inner i = { 2 }; return i; } }
int main(void) { Box b; return b["k"].twice(); }
```

```ct
/* 3 */
struct Inner { int v; }
struct Box { }
impl Box { Inner get(const char *k) { (void)k; Inner i = { 1 }; return i; } }
int main(void) { Box b; return b["k"].v; }
```

## 实际行为

```text
/* 2 */ a5b.ct:8:1: error: a method call on a temporary is only allowed at the start of a statement or of an assignment
/* 3 */ rc=0（无诊断）；生成的 C 为 Box_get(&b, "k").v，cc 报 member reference base type 不是结构体
/* 4 */ a5c.ct:6:21: error: type 'In' has no subscript: declare 'V get(K)' in impl In
```

## 期望行为

- 形态 2 / 3 至少**一致**：要么都支持（把接收者物化成 `__ct_tmp<N>`），要么都硬错并指向同一句文案；
  不能出现「方法硬错、字段静默」。
- 形态 4 属单层下标限制（D52），本单只要求它**不静默**——当前已经硬错，保持。

> **与 SH-73 的关系**：方法形态的拒绝本身是**有意边界**（[SH-73](../selfhost/sh73-temp-receiver-dynamic-dispatch.md)，
> 「临时值接收者被拒：保持」），本单不推翻它；本条登记的是**字段形态没有对应守卫**（形态 3，静默），
> 以及「同一条链上两种形态给出不同结论」这一不一致。

## 影响面与绕法

ct-json 的 `doc["k"]["k2"].as_int()`、`doc["k"].kind()` 都必须拆成多行局部变量：

```ct
JsonRef a = doc["k"];
JsonRef b = a["k2"];
int n = b.as_int();
```

链式写法是多级 JSON 访问的主要形态，逐级展开会显著拉长调用点。

## 定位

- 方法形态的拒绝：[Expr.h.ct](../../selfhost/ct-ast/frontend/parse/Expr.h.ct) 的 `N_MCALL` 接收者守卫
  （与 SH-73 同族，`a.m().n()` 是同一句文案）；
- 字段形态无守卫：`[` 后缀在 [Expr.h.ct:4230-4286](../../selfhost/ct-ast/frontend/parse/Expr.h.ct#L4230-L4286)
  产出 `N_MCALL`，随后 `.v` 直接按成员处理，未做「接收者是否临时值」的检查。
