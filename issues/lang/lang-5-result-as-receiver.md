# LANG-5 · 方法 / 下标结果不能作接收者，字段形态还静默产出坏 C

| 项 | 值 |
| --- | --- |
| 模块 | lang（接收者物化 / 下标链） |
| 严重度 | **High**（字段形态是静默错误；方法形态有诊断） |
| 优先级 | **P1** —— 挡住 ct-json 的 `doc["k"].x` / 多级链 |
| 状态 | 方法形态修复中（本相）；字段形态（形态 3）仍 open |
| 锚点 | `v0.53.1`（`c4727787`） |
| 上游 | ct-json [JSON-2](../../../ct-json/issues/JSON-2.md)（合并进本条，见「合并关系」） |

> **合并关系**：ct-json 的 JSON-2（`doc["server"].has(k)`）与 LANG-5 形态 2 是同一根因
> （非泛型固有方法结果没有静态类型，后续 `.m()` 无法解析），不另立条目，以本条为准；
> JSON-1（同类型三级链）是另一根因，见 [LANG-13](lang-13-three-level-subscript-chain.md)。

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
/* 2 */ a5b.ct:8:1: error: method receiver must be a variable, an element, a call or a field chain
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
>
> **v0.53.1 修法（形态 1/2，即 JSON-2）**：根因不在接收者白名单，而在类型推断。
> `TypeCheck::inst_method_ret` 只认泛型实例（`ct_inst_find`），非泛型 `impl Ref { … }` 的方法结果
> 没有静态类型 → 后续 `.has()` / `.twice()` 解析不到固有方法 → 落到 trait 分支，被接收者种类
> 白名单（`N_MCALL` 不在其中）拒绝。修法是让 `inst_method_ret` 在无实例行时扫描非泛型固有
> `impl`，直接读声明返回类型（`struct` 前缀补全，与 `static_ctype` 同形）。**SH-73 不动**：
> trait 动态派发的 `a.m().n()` 仍拒绝。
>
> 回归：`test/ast/262_inherent_mcall_receiver`（`doc.get(2).get(4)` 与 `doc[3].has(3)`）、
> `test/ast/errors/temp_receiver_trait_chain.ct`（trait 形态仍须报错）。

## 影响面与绕法

ct-json 的 `doc["k"]["k2"].as_int()`、`doc["k"].kind()` 都必须拆成多行局部变量：

```ct
JsonRef a = doc["k"];
JsonRef b = a["k2"];
int n = b.as_int();
```

链式写法是多级 JSON 访问的主要形态，逐级展开会显著拉长调用点。

## 定位

- 方法形态的拒绝：类型推断 [TypeCheck.h.ct](../../selfhost/ct-ast/frontend/type/TypeCheck.h.ct)
  `inst_method_ret`（非泛型固有方法无返回类型）+ 发射器接收者种类白名单
  [Emitter.h.ct](../../selfhost/ct-ast/backend/emit/Emitter.h.ct)
  `method receiver must be a variable, an element, a call or a field chain`；
  trait 动态派发的同一句文案与 SH-73 同族（`a.m().n()`），保持；
- 字段形态无守卫：`[` 后缀在 [Expr.h.ct:4230-4286](../../selfhost/ct-ast/frontend/parse/Expr.h.ct#L4230-L4286)
  产出 `N_MCALL`，随后 `.v` 直接按成员处理，未做「接收者是否临时值」的检查。
