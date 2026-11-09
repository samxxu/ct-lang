# Phase 25 · 静态映射调用的闭包实参（`array.each(closure)`）

> 中文 · [English](#english)
>
> **状态：规划中**（2026-11-09），**待实现**。D25-1–D25-11 已定稿；
> 本文是 **as-planned** 记录，落地后按 [phase23.md](phase23.md) 的先例改写为 as-built。
> 关联：[phase24.md](phase24.md)（数组 range 初值，本相前置但不依赖）、
> [phase21.md](phase21.md)（非逃逸栈闭包）、
> [batch38-map-unit/spec.md](../history/design/batch38-map-unit/spec.md)（`.m.ct` 静态映射）、
> [batch39-shim-layer/spec.md](../history/design/batch39-shim-layer/spec.md)（shim 层）、
> [closure-conventions.md](../closure-conventions.md)、[roadmap.md](../roadmap.md)。

---

## 1. 定位

Phase 21 的闭包只能作为**普通函数调用**的实参，因为只有那里有「已解析签名」来判断
`(fn, env)` 参数对。本相把同一条规则接到**静态映射调用**（`.m.ct` 的 recipe）上，让
数组这样的 C 类型宿主也能直接吃闭包：

```c
/* arr/arr.m.ct */
namespace arr;

pub trait IntSeq {
    void each(int n, int (*fn)(void *env, int x), void *env);
}

map trait IntSeq for type int * {
    each(a, n, fn, env) -> ct_each_int(a, n, fn, env);
}
```

```c
/* arr/arr.shim.h —— recipe 写不出的循环放这里 */
static inline void ct_each_int(int *a, int n, int (*fn)(void *env, int x), void *env)
{
    for (int k = 0; k < n; k++) fn(env, a[k]);
}
```

```c
/* 消费者 */
int base = 10;
int a[4] = { 1, 2, 3, 4 };
a.each(4, (int x) => { printf("%d\n", x + base); });
```

产物是裸 C 调用，闭包的两半按 Phase 21 的 `(fn, env)` ABI 落位：

```c
ct_each_int(a, 4, __ct_cl_tramp_0, &(struct __ct_cl_env_0){ .base = base });
```

判断标准：**产物与手写「函数指针 + 环境结构体」完全一致**，不新增运行时对象、不装箱、
不引入 vtable。

### 1.1 本相不做

| 不做的东西 | 一句话理由 |
| --- | --- |
| `each (nums) { … item … }` 语句形态 | 需要隐式名字、块参数与 `break`/`continue`，是语言级语法糖，未排期 |
| 自动取数组长度 | 类型宿主只看 decay 后的 `int *`，长度已丢；`int *p` 与 `int a[4]` 命中同一宿主，`sizeof` 宏方案会静默出错 |
| `Vec` / 泛型 / 自定义容器 | 泛型是 Phase 26；本相只做「C 类型宿主 + 现有 trait」 |
| 闭包作方法**接收者** | Phase 21 S5 已定：闭包调用不走类型宿主（`test/ast/81_closure_no_typehost`） |
| 闭包经 recipe 的 `...` 变参尾部 | 尾部的实参个数由绑定参数决定，闭包要占两格，无法在尾部定位 |
| 跨调用保存 `env` | 环境是栈上的复合字面量；shim 必须同步消费（§3.5），编译器看不到，只能约定 |
| 动态派发（`impl`）吃闭包 | 动态方法调用不经 `(fn, env)` ABI；要做是另一个量级 |
| 静态 trait 的返回型闭包 | 闭包不能作返回值（Phase 21 D21-13） |

---

## 2. 现状与四个缺口

今天 `a.each(4, (int x) => …)` 会**编译失败**（不是静默出错），缺口正好四处：

| # | 位置 | 现状 |
| --- | --- | --- |
| 1 | `map_arity`（[Expr.h.ct](../../selfhost/ct-ast/frontend/parse/Expr.h.ct)） | `got = arg_count(args)`，闭包只算 1 个实参 → 与 `want = 3` 不符 |
| 2 | `argtype_check` 的调用点 | 静态 trait 被 `!is_static` 跳过，闭包的 `(fn, env)` 配对检查不生效 |
| 3 | `map_actual_at`（[Emitter.h.ct](../../selfhost/ct-ast/backend/emit/Emitter.h.ct)） | 一个索引对应一个实参；闭包要占两个 recipe 参数位 |
| 4 | `emit_closure_arg` | 一口气输出「trampoline, &env」两个 C 实参；recipe 需要分两次单独落位 |

结果就是 arity 警告 + `a map call has fewer arguments than its binding` 硬错。

---

## 3. 语义

### 3.1 触发条件（D25-1 / D25-2）

闭包实参**只在**下面两个条件同时成立时展开：

1. 调用形态是静态映射（`traits[t].is_static`，即 `.m.ct` 的 recipe），且
2. 该实参所对应的**宿主方法形参对**满足 Phase 21 的 `(fn, env)` 判定
   （第一个是 `formal_is_env_fn`，第二个是 `void *`）。

其余位置一律硬错（L25-1），包括：长度位、指针位、`sizeof` 位、非静态方法、变参尾部。

### 3.2 参数个数（D25-3）

沿用普通调用的口径：`got = arg_count(args) + closure_arg_count(args)`。

`a.each(4, closure)` → `arg_count = 2`、`closure_arg_count = 1`、`got = 3`；
宿主方法的 `nparams` 是 `3`（`n` / `fn` / `env`，接收者不计入，见
[MapBuild.h.ct](../../selfhost/ct-ast/frontend/parse/MapBuild.h.ct) 的
`want = nparams + (type_host ? 1 : 0)`）。两者相等，`map_arity` 不再报。

### 3.3 实参到 recipe 参数的映射（D25-4）

recipe 的绑定参数序是 `[接收者, 方法形参…]`。闭包实参在**方法形参序**上占两格：

| recipe 参数 | 来自 | 输出 |
| --- | --- | --- |
| `a`（接收者） | 接收者表达式 | `emit_expr(recv)` |
| `n` | 第 1 个实参 | `emit_expr(arg1)` |
| `fn` | 闭包实参的**前半** | `__ct_cl_tramp_N`（闭包变量则是同名符号） |
| `env` | 闭包实参的**后半** | `&(struct __ct_cl_env_N){ … }`（闭包变量则是 `&__ct_cl_env_v_N`） |

实现上把 `map_actual_at` 换成闭包感知的游标，并平行维护 `half[]`：
`0` = 整体实参、`1` = `fn` 半、`2` = `env` 半。

### 3.4 使用次数（D25-5）

对每个闭包实参，recipe 必须**各引用 `fn` 与 `env` 一次**：

- 任一被引用两次 → L25-2（`map_repeatable` 对 `N_CLOSURE` 返回 0，既有守卫已能拦住）；
- 两者都未被引用 → L25-4（否则 trampoline 变成未使用的 `static` 函数，撞 `-Wall`）；
- 只引用其一 → L25-4（另一侧的 shim 形参拿不到值，只会在 C 侧炸，不如在 CT 侧拦住）。

### 3.5 生命周期（D25-6）

环境是栈上的复合字面量（D21-14），生命周期到**所在块结束**。因此：

- shim 的函数必须**同步**消费回调，调用返回后不得再使用 `env`；
- 编译器无法验证这一点（与 E8 同类，见 [closure-conventions.md](../closure-conventions.md)）；
- 命名约定：能接闭包的 shim 入口统一用 `ct_<verb>_<type>`，文档里标注「同步回调」；
- 逃逸检测仍由 Phase 21 的既有规则负责：闭包进 `.h.ct`、作返回值 / 字段 / 元素依旧硬错。

### 3.6 两种实参形态

| 实参 | 输出 |
| --- | --- |
| 闭包字面量 `(int x) => …` | `__ct_cl_tramp_N, &(struct __ct_cl_env_N){ … }` |
| 闭包变量 `f`（`int (*f)(void*, int)` 绑定） | `__ct_cl_tramp_M, &__ct_cl_env_v_M` |

两者的 trampoline 与环境命名由 Phase 21 的既有实现给出，本相不新增命名。

---

## 4. 发射

### 4.1 拆分 `emit_closure_arg`

现在它一次写出 `tramp, &env` 两个 C 实参。本相把它拆成两个静态辅助：

```c
static int emit_closure_fn(struct Emitter *self, int n);   /* __ct_cl_tramp_N */
static int emit_closure_env(struct Emitter *self, int n);  /* &(struct __ct_cl_env_N){ … } */
```

普通调用路径改为连续调用两者（产物逐字节不变），recipe 路径按 `half` 选择其中一个。

### 4.2 `emit_recipe` 的游标

```c
/* 展开一次 recipe 的实参表：闭包实参产出两个槽位 */
for (i = 0; i < b->nparams; i++) {
    actual[i] = map_actual_span(e->arena, recv, args, m->type_host, i, &half[i]);
    ...
}
```

- `map_repeatable` 与「少参数」的既有判定不变；
- 未命中的槽位（`unused`）逻辑不变，但闭包实参的两个槽位**不允许**落进 `(void)(…)` 分支
  （§3.4 已把它变成硬错）。

### 4.3 产物

```c
/* 输入 */  a.each(4, (int x) => { printf("%d\n", x + base); });
/* 输出 */  ct_each_int(a, 4, __ct_cl_tramp_0, &(struct __ct_cl_env_0){ .base = base });
```

生成物不含 `each`、不含 `.m.ct` 的任何痕迹，与手写调用一致。

---

## 5. 诊断

| 编号 | 场景 | 文案 | 严重度 |
| --- | --- | --- | --- |
| L25-1 | 闭包落在非 `(fn, env)` 位 | `a closure argument must fill a '(fn, env)' parameter pair (got '<param>')` | error |
| L25-2 | recipe 对 `fn` / `env` 引用两次 | `a map recipe must use a closure argument exactly once` | error |
| L25-3 | 闭包跟在 `...` 尾部 | `a map recipe cannot pass a closure through '...'` | error |
| L25-4 | `fn` 与 `env` 未成对使用（含都未使用） | `a map recipe must use both halves of a closure argument` | error |
| L25-5 | 真少参数（非闭包场景） | 沿用 `a map call has fewer arguments than its binding` | error |

- 文案风格与 Phase 22–24 一致：小写、无句号、单引号；
- L25-1 取代今天那句误导性的「参数不够」；
- 本相不新增 `ct check` kind：这些都是硬错，编译与 `ct check` 行为一致。

---

## 6. 验收与测试

### 6.1 正例（`test/ast/`）

| fixture | 覆盖 |
| --- | --- |
| `120_map_each_closure` | 字面量闭包 + 捕获外层变量；`int a[4]` 经 decay 命中 `int *` 宿主 |
| `121_map_each_closure_var` | 闭包变量作实参（`&__ct_cl_env_v_N` 路径） |
| `122_map_each_tier1` | 档① 三实参 `a.each(4, cb, &ctx)`（今天就能跑，回归保护） |

### 6.2 负例（`test/ast/errors/`）

`map_each_closure_slot`（闭包放长度位）、`map_each_closure_twice`（recipe 写两次 `fn`）、
`map_each_closure_unused`（recipe 不引用 `fn`/`env`）、`map_each_closure_vararg`（`...` 尾部）。

### 6.3 硬断言（`check-ast.sh` 的 Phase 25 块）

- **形态**：`120` 的生成物含 `ct_each_int(`、`__ct_cl_tramp_`、`__ct_cl_env_`，
  且不含 `a map call has fewer arguments`；
- **逐字节**：`120` 的调用行与手写
  `ct_each_int(a, 4, __ct_cl_tramp_0, &(struct __ct_cl_env_0){ .base = base });` 相等（剔除缩进）；
- **回归**：`81_closure_no_typehost` 仍 PASS（闭包作接收者的语义未变）、
  `75_closure_param_pair` 生成物逐字节不变（`emit_closure_arg` 拆分后两条路径同形）；
- **无告警**：`check-warnings.sh` 全绿（trampoline 必被引用，§3.4 已排除未使用函数）。

### 6.4 golden 影响

功能本身对既有 golden **零变化**：静态 recipe 调用此前不接受闭包实参，没有既有代码命中。
收口 bump 到 `v0.25.0` 时，带版本 token 的 74 个文件仅版本变化
（`test/cases/**` 50 + `test/modules/**` 21 + `examples/tour/**` 3 = 74；roadmap 版本记录里的
71 是只统计测试 golden 的历史口径）。

---

## 7. 实现切点

| 切点 | 文件 | 内容 |
| --- | --- | --- |
| 25.1 解析 | `frontend/parse/Expr.h.ct` | `map_arity` 的 `got` 加 `closure_arg_count`；静态 trait 也跑 `argtype_check`；非参数对位置报 L25-1 |
| 25.2 绑定 | `backend/emit/Emitter.h.ct` | `map_actual_span`（闭包占两格 + `half`）、`emit_recipe` 的槽位循环 |
| 25.3 发射 | `backend/emit/Emitter.h.ct` | 拆 `emit_closure_fn` / `emit_closure_env`；普通调用路径改为两者连写 |
| 25.4 诊断与测试 | `frontend/parse/**`、`test/ast/**`、`selfhost/check-ast.sh` | L25-1–L25-5 与 §6 用例 |
| 25.5 文档 | `docs/**` | 本文件 + language-spec §4.10（映射）与 §4.44（闭包）各补一段 + tutorial + roadmap |

提交切片：**S1** 解析与诊断；**S2** 绑定与发射；**S3** 测试与门禁；**S4** 文档；
**S5** `v0.25.0` 版本收口。

---

## 8. 依赖与风险

| 项 | 结论 |
| --- | --- |
| Phase 21 | **硬前置**：`(fn, env)` ABI、trampoline / env 命名、逃逸规则 |
| Phase 24 | 无依赖；两者都动 `Expr.h.ct` / `Emitter.h.ct`，合并次序需留意 |
| Phase 26（泛型） | 无依赖；本相只做具体类型的宿主 |
| L0 / L1 / L2 | 功能只落 `selfhost/ct-ast/**`；S5 改五处 `CTC_VERSION` |
| R1 recipe 参数个数校验 | `MapBuild` 的 `want = nparams + (type_host ? 1 : 0)` 不改 |
| R2 `sizeof %s` 用在闭包上 | 闭包实参在 `sizeof` 位报 L25-1，不放行 |
| R3 递归 / 嵌套闭包 | 沿用 Phase 21 的既有实现，本相不新增路径 |
| R4 trampoline 未使用告警 | §3.4 的「必须成对引用」把它变成硬错 |
| R5 自举 | `selfhost/**` 不使用 `.m.ct`，天然不受影响 |
| R6 动态派发误放行 | 判定按 `is_static` 分流，`impl` 路径不变 |

---

## 9. 已定决策

| 编号 | 决策 |
| --- | --- |
| D25-1 | 只对**静态映射调用**（`.m.ct` recipe）的实参启用闭包展开 |
| D25-2 | 只在宿主方法形参构成 `(fn, env)` 对时生效；其余位置硬错 |
| D25-3 | `map_arity` 的 `got` 采用 `arg_count + closure_arg_count`，与普通调用同口径 |
| D25-4 | 闭包实参占据 `fn` / `env` 两个 recipe 参数位，由 `map_actual_span` + `half` 定位 |
| D25-5 | recipe 必须成对引用 `fn` 与 `env` 各一次；重复、缺失、`...` 尾部都是硬错 |
| D25-6 | 闭包环境仍为栈上复合字面量；shim 必须同步消费，编译器不诊断（文档规则） |
| D25-7 | 拆分 `emit_closure_arg` 为 `emit_closure_fn` / `emit_closure_env`；普通调用产物不变 |
| D25-8 | 不做语句形态 `each (…) { … }`、不做自动取长度、不做泛型容器 |
| D25-9 | 闭包作接收者的既有语义不变（`81_closure_no_typehost` 为守护用例） |
| D25-10 | 仅 ct-ast；L0 / L1 / L2 不改 |
| D25-11 | 收口 bump `v0.25.0`；功能层既有 golden 零变化 |

---

## English

### Status

**Design frozen** (2026-11-09), **not implemented**. D25-1–D25-11 are final.

### Positioning

Phase 21 closures can only fill a `(fn, env)` parameter pair of a **plain function call**,
because only that site has a parsed signature. This phase extends the same rule to **static
mapping calls** (`.m.ct` recipes), so a C type host such as `int *` can accept a closure:

```c
a.each(4, (int x) => { printf("%d\n", x + base); });
/* -> ct_each_int(a, 4, __ct_cl_tramp_0, &(struct __ct_cl_env_0){ .base = base }); */
```

The output is a bare C call; no new runtime object, no boxing, no vtable.

### Four gaps in today's implementation

1. `map_arity` counts the closure as one actual (`got = arg_count`), while the host method has
   three formals (`n`, `fn`, `env`).
2. Static traits skip `argtype_check`, so the `(fn, env)` pair is never compared for a closure.
3. `map_actual_at` maps one index to one actual; a closure must occupy two recipe slots.
4. `emit_closure_arg` writes both `tramp` and `&env` in one go, while a recipe needs them in
   two separate slots.

Today the call fails loudly (arity warning + `a map call has fewer arguments than its binding`),
never silently.

### Rules

- Only static mapping calls, and only at a `(fn, env)` formal pair; every other position is a
  hard error (`L25-1`).
- `got = arg_count + closure_arg_count`, the same formula the plain-call path uses.
- A closure actual fills the `fn` slot with the trampoline and the `env` slot with the address
  of its stack environment; a closure variable fills them from its own instance.
- The recipe must use both halves exactly once (`L25-2` / `L25-4`); `...` tails cannot carry a
  closure (`L25-3`).
- The environment lives until the end of the enclosing block, so a shim entry that accepts a
  closure must consume it synchronously. The compiler cannot check this; it is a documented rule.

### Non-goals

Statement-level `each (…) { … }`, automatic element counts (a decayed `int *` cannot know its
length, and `int *p` matches the same host as `int a[4]`), `Vec` / generics (Phase 26), closures
as method receivers, and closures through dynamic dispatch.
