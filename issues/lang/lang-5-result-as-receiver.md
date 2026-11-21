# LANG-5 · 方法 / 下标结果不能作接收者，字段形态还静默产出坏 C

| 项 | 值 |
| --- | --- |
| 模块 | lang（接收者物化 / 下标链） |
| 严重度 | **High**（字段形态是静默错误；方法形态有诊断） |
| 优先级 | **P1** —— 挡住 ct-json 的 `doc["k"].x` / 多级链 |
| 状态 | verified |
| 处置证据 | **verified**（2026-11-20，REV） |
| 锚点 | `v0.53.1`（`c4727787`） |
| 上游 | ct-json JSON-2（仓库外记录，本仓不复制；合并进本条，见「合并关系」） |

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
> **v0.53.2 修法（形态 1/2，即 JSON-2）**：根因不在接收者白名单，而在类型推断。
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

## 处置（2026-11-20，DEV #2）

**结论：fixed**（`.v` 字段形态在 ct 阶段拒绝指针/接口返回值；值形态与方法形态不回归）。

复现结论比原单更精确：issue 里的值返回夹具（`Inner get(...)`）在 HEAD 产出的
`Box_get(&b,"k").v` 是**合法 C**（`struct Inner` 返回值取字段，cc 通过、rc=0），
原单「cc 报 member reference base type 不是结构体」在 HEAD 不成立。真正的静默坏 C
出现在 `get` 返回**指针**（`Inner *`）或**接口值**（`struct T_iface`）时：ct rc=0，
`Box_get(...).v` 到宿主 cc 才报错。三例在 baseline 全部静默通过。

- 红证（baseline `fa89d727`，`.temp/b/ct-ast` 由该提交重建）：
  ```console
  $ sh test/ast/p77_lang5_field.sh .temp/b/ct-ast   # rc=1
  ok   b["k"]->v compiles and runs
  ok   b["k"].v with a value result compiles and runs
  ok   b["k"].m() still materialises and runs
  ok   f().m() still materialises and runs
  ok   f().v on a value compiles and runs
  ok   b["k"].m() pointer receiver keeps its diagnostic
  FAIL p77/lang5: b["k"].v with a pointer result is refused
    exit 0; expected a compile-time refusal (the emitted C is not checked by ct)
  FAIL p77/lang5: b["k"].v with an interface result is refused
    exit 0; expected a compile-time refusal (the emitted C is not checked by ct)
  FAIL p77/lang5: p.v on a pointer variable is refused
    exit 0; expected a compile-time refusal (the emitted C is not checked by ct)
  ```
- 修法：`Expr.h.ct` 的 `.` 非调用字段分支读取接收者静态类型后硬错
  - 指针：`'.' cannot access field 'v' through a pointer receiver; use '->v'`
  - 接口：`'.' cannot access field 'v': 'T' is an interface value; it has methods, not fields`
  豁免 `self.n`（发射器已拼 `_self->n`）、接口的 `.self` 载荷字段、以及
  `Vec_Show__iface` 这类名字碰巧以 `_iface` 结尾的容器/实例类型（再用 `find_trait`
  确认）。值返回值无需临时变量（`f().v` 合法）；方法形态仍由发射器物化成
  `struct Inner __ct_tmp0 = ...; Inner_twice(&__ct_tmp0)`，未回归。
- 绿：
  ```console
  $ sh test/ast/p77_lang5_field.sh .temp/b/ct-ast   # rc=0
  ok   b["k"].v with a pointer result is refused
  ok   b["k"].v with an interface result is refused
  ok   b["k"]->v compiles and runs
  ok   b["k"].v with a value result compiles and runs
  ok   b["k"].m() still materialises and runs
  ok   f().m() still materialises and runs
  ok   f().v on a value compiles and runs
  ok   p.v on a pointer variable is refused
  ok   b["k"].m() pointer receiver keeps its diagnostic
  OK p77/lang5 (field receiver: pointer/interface refused, value forms kept)
  ```
- 提交：
  - `7627a43d` `test(ct-ast): LANG-5 红 — 下标结果的字段形态`
  - `7b8e8c9b` `fix(ct-ast): LANG-5 拒绝指针/接口返回值的 '.' 字段访问`
- 探针：`test/ast/p77_lang5_field.sh`，已接入 `selfhost/check-ast.sh`。
- 回归扫描：289 个 `test/ast` 夹具 + `test/cases` + `examples` 无新增拒绝
  （`181_iface_vec` 等 multi-file 夹具仍走 build 模式；errors/ 与 corpus 与基线一致）。

## 复核（2026-11-20，REV）

**结论：verified。** 独立自举 `git archive v0.77.2` → L0→L1→L2→ct-ast（`ct-ast v0.77.2`，
四段 `cc` 均零警告）；红证用 `git archive fa89d727` 重建的基线二进制配同一支探针复跑
（基线归档尚无 `p77_lang5_field.sh`，探针取自 HEAD）。

```console
$ sh test/ast/p77_lang5_field.sh /tmp/rev-v0772/ct-ast
ok   b["k"].v with a pointer result is refused
ok   b["k"].v with an interface result is refused
ok   b["k"]->v compiles and runs
ok   b["k"].v with a value result compiles and runs
ok   b["k"].m() still materialises and runs
ok   f().m() still materialises and runs
ok   f().v on a value compiles and runs
ok   p.v on a pointer variable is refused
ok   b["k"].m() pointer receiver keeps its diagnostic
OK p77/lang5 (field receiver: pointer/interface refused, value forms kept)
$ echo $?
0
```

```console
$ sh test/ast/p77_lang5_field.sh /tmp/rev-base/ct-ast
FAIL p77/lang5: b["k"].v with a pointer result is refused
  exit 0; expected a compile-time refusal (the emitted C is not checked by ct)
FAIL p77/lang5: b["k"].v with an interface result is refused
  exit 0; expected a compile-time refusal (the emitted C is not checked by ct)
ok   b["k"]->v compiles and runs
ok   b["k"].v with a value result compiles and runs
ok   b["k"].m() still materialises and runs
ok   f().m() still materialises and runs
ok   f().v on a value compiles and runs
FAIL p77/lang5: p.v on a pointer variable is refused
  exit 0; expected a compile-time refusal (the emitted C is not checked by ct)
ok   b["k"].m() pointer receiver keeps its diagnostic
$ echo $?
1
```

逐条对照：指针结果 `.v`、接口值 `.v`、指针变量 `.v` 三例基线 rc=0（静默发射），v0.77.2 均硬错且
诊断首行带 `file:line:col`；值返回 `.v`、方法形态 `b["k"].m()` / `f().m()`、`f().v`、`b["k"]->v`
基线绿、v0.77.2 仍绿，未回归。

**与 issue 原文的差异（不打回）**：原文对形态 2/3 的期望是「至少一致：要么都支持，要么都硬错」，
并未要求值返回也必须硬错。值返回 `f().v` 是合法 C（`struct Inner` 返回值取字段，cc 通过），
方法形态由发射器物化为 `__ct_tmp`；两者都支持，符合「都支持」分支。真正静默坏 C 的是
指针/接口返回，`7b8e8c9b` 已拒绝，故不按「值返回未硬错」判 reopened。

T-7：红 `7627a43d`（父 `fa89d727`）→ 修 `7b8e8c9b`；红提交只含探针与 `check-ast.sh` 接入，
实现提交只改 `Expr.h.ct`。
