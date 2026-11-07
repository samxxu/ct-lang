# Phase 21 计划（规划中）：非逃逸栈闭包

> 中文 · [English](#english)
>
> **状态：规划中**（2026-11-06；本文件是计划与实现依据，不是已确认的最终决策；D21-1–D21-12 待用户确认）。
> **版本口径：Phase 21 ↔ `v0.21.x`，收口 bump 到 `v0.21.0`。** 当前仓库 `v0.20.0`（`CTC_VERSION` 五处一致）。
> 前置：Phase 17 / 18 / 19 / 20 均已完成；Phase 20 = 包支持（[phase20.md](phase20.md)，已完成，与本相无依赖）。
> 关联：[borrow 设计](../history/design/borrow.md)、[language-spec](../language-spec.md)、
> [std 能力缺口](../../issues/std/std1-markdown-readiness.md)、[roadmap](../roadmap.md)。

---

## 中文

### 0. 一页结论

| # | 判断 | 结论 |
| --- | --- | --- |
| 1 | 提案的物理模型（`(fn, env)` 两词、档② = 档① 自动展开） | **成立**，且与今天的 `<Struct>_<Trait>_<method>(void *self, …)` 同形 |
| 2 | 提案的「逃逸判定复用 `own`、扩展闭包为第三类右值，性价比最高」 | **不成立**。`own` 的判定是变量中心 + 取消析构 + 泄漏警告；闭包逃逸必须是硬错误，且闭包值没有可挂靠的 `Var.st`。可复用形态识别与寿命比较，不能复用数据结构 |
| 3 | 提案的「容器先行，因为闭包最大用途是 map/filter」 | **不成立**（无泛型）。容器上的闭包省掉的是每处 adapter struct，不是每元素类型的包装函数；且先冻结容器回调签名，会把错误的 ABI 固化下来 |
| 4 | 提案的「borrow 阶段一尚未实现、需合并」 | **已实现**（v0.16.0 阶段一 + 阶段二，v0.16.1 加固）。Phase 21 只剩「抽出共用的寿命判定并由闭包侧接入」 |

---

### 1. 相号与版本号对应关系

本仓库的口径是 **`v0.<phase>.<patch>`，Phase *n* ↔ `v0.n.x`**（roadmap「版本规则」，2026-10-15 确认；
D17-1 已按此恢复编号）。据此：

| Phase | 设计文档 | 状态 | 版本 |
| --- | --- | --- | --- |
| 17 | [phase17.md](phase17.md) | ✅ 完成 | `v0.17.0` |
| 18 | [phase18.md](phase18.md) | ✅ 完成 | `v0.18.0` |
| 19 | [phase19.md](phase19.md) | ✅ 完成 | `v0.19.0`；其后 `v0.19.1` 为修复补丁 |
| 20 | [phase20.md](phase20.md) | ✅ 完成 | `v0.20.0`（包支持；P20-05 移出、P20-07 延后，与本相无依赖） |
| 21 | 本文件 | ⬜ 规划中 | 收口 `v0.21.0`，阶段内 patch 位可用 |

三点必须钉死：

1. **Phase 21 不等于 `v0.21.1`。** 它指「第 21 相」，收口时一次性 bump 到 `v0.21.0`；阶段内只有需要重生成
   golden 的修复才用 patch 位。
2. **Phase 20 与本相相互独立。** Phase 20（包支持）独占 `v0.20.x`，本相占 `v0.21.x`；
   两相的改动面（包解析 / 发射器诊断 vs 闭包降级）不重叠，可并行，不存在「闭包要等 20 完结」的依赖。
3. **Phase 21 的软冲突**：`issues/std/std1-markdown-readiness.md` 用「Phase 21+」指代泛型。本计划占用 21 之后，
   该表述应改为「Phase 22+ / 1.0 之后」，否则读者会以为闭包内含泛型。
4. 门禁实数：`selfhost/check-all.sh` 当前 **11 道**硬门禁。Phase 19 roadmap 行里的「12 道」是笔误，
   不在本阶段修；Phase 21 只在既有门禁内加断言，不新增门禁。

---

### 2. 目标与非目标

#### 目标

- 落地**档② 非逃逸栈闭包**：`=>` 就地写法，环境在栈上，编译期禁止逃逸。
- 档②**必须实现为档①（`struct` + `trait`）的自动展开**，ABI 统一为 `(fn, env)` 两词，不引入第二套运行时、
  不引入隐藏 `malloc` / 引用计数。
- 逃逸判定与 `borrow` 共用同一套「更长寿命」判断；撞墙时**硬报错**并给出指向显式 `Callable` 的 hint。
- 档③（通用逃逸闭包）**不做**：不是做不到，而是能力已在档①、缺的只是语法糖；按引用捕获需要生命周期，
  本阶段不付这个价（见[评审](closure-proposal-review.md) §1.1）。`1.0.0` 前不引入泛型。

#### 非目标

- 不做堆上闭包、引用计数、生命周期标注、跨过程逃逸分析。
- 不做闭包的跨语言暴露；iOS / C 回调注册一律走档①（环境活不过栈帧）。
- 不把 `Callable` 做成「万能可调用」：无泛型时它只能是**按签名一族**的约定，不是一个 trait 包打天下（§5.5）。
- 不改 L0 / L1 / L2；新能力只落 `selfhost/ct-ast/**`、`docs/**`、`test/ast/**`、`examples/**`。
- 不为闭包改 `CTC_VERSION` 之外的生成物形态；既有 71 个 golden 只允许版本 token 变化。

---

### 3. 核对：v0.12.0 提案 vs v0.19.1 实测（偏差单独成节）

#### 3.1 逐项核对

| # | 提案依赖的机制 | v0.19.1 实测 | 判定 |
| --- | --- | --- | --- |
| 1 | `own` / AutoDrop「两套逃逸形态：`q = p;`、`return p;`」 | 现有 **4 个入口**：声明初始化式 `leak_decl`、赋值 `leak_assign`（含 `s->f = p` 的基名）、`return` 的 `leak_return` + `expr_returns`（SH-36/41 区分「读字段」与「真移交」）、作用域出口 `leak_scope`（路径敏感 + `path_warned`）。另有 `ret_owned` 一级跨过程提示。形态只增不减 | **提案低估了形态数量** |
| 2 | 「扩展闭包值为第三类右值」是性价比最高的切入点 | 判定是**变量中心**：`Var{owned, autodrop, borrowed, st, is_param, is_global, is_static}` + 名字 token 匹配；闭包值是「一对局部（fn, env）」，没有 `struct` 类型可挂 `st`；且 `own` 逃逸 = 取消析构/泄漏警告，闭包逃逸 = **硬错误** | **不成立**，见 §3.2 |
| 3 | trait / impl mangling：`Adder_Callable_call(&adder, x)` | 仍成立：`<Struct>_<Trait>_<method>(void *self, …)`，调用方传 `&obj`；vtable 为 `struct <Trait>_vtbl`，实例级为 `<inst>_<Trait>_vtable` | **成立**（有一处限制，见 §3.3） |
| 4 | 官方 `Callable` | 全仓 **0 命中**；`Callable` 不存在，属绿地 | 提案 §9 不是「官方化」，是新建 |
| 5 | 方言生成可作档①通路 | 编译器对 DSL **零感知**；方言只允许是 `examples/` 与 `test/ct-dialects/` 下的仓库外展开器（Phase 6.6 / D20） | 提案 §1 把「方言生成」列为档①基础机制 **不成立** |
| 6 | `=>` 未被占用 | **确认**：398 个 `.ct` + 135 个 `.c/.h` 中 0 处；`ct-pkg` 55 个 `.ct` 中 0 处（详见 §8） | **成立** |
| 7 | borrow 阶段一待做、建议与档②合并 | **已实现**：`borrow` 参数注解 + 变量声明 + 出口 `handback`（v0.16.0），SH-33/35/36/37/39/40/41 已修；探针 `test/ast/61_autodrop_return`、`62_borrow_handback`；[borrow.md](../history/design/borrow.md) §12 记录实现差异 | **前提已消失**，见 §3.2 |
| 8 | 提案要求「错误码」 | CT **没有错误码体系**。硬错误统一走 `ct_sem_error(line, col, msg, path)` → `path:line:col: error: msg`；只有警告有 `Warn.kind` 分桶（0–6） | 需要换一种可钉住的契约（§4.6） |

#### 3.2 因核对而失效的提案结论

1. **「复用 `own` 基础设施、把闭包当第三类右值」不可直接执行。**
   可复用的是**形态识别**（声明 / 赋值 / return / 作用域出口四个入口）与**寿命比较**
   （`Stmt.var_scope`：scope 下标更浅 = 更长寿命）。数据结构和语义都要新建：
   - `Var` 增加 `is_closure` / `closure_id`（1 个 flag + 1 个 id），不复用 `owned` / `autodrop`；
   - 新增闭包表（id → env 结构名、trampoline 名、捕获字段清单）；
   - 逃逸是硬错误（`ct_sem_error`），不是取消析构 + 泄漏警告。
   因此该项**不是「性价比最高」的小改动**，而是一个独立检查器；它仍比通用闭包轻得多。
2. **「borrow 阶段一尚未实现，需要与档②合并」失效。** 阶段一 / 二已落地。Phase 21 只剩下
   「把 `check_borrow_store` 里的寿命比较抽成公共判定，并让闭包侧调用它」这一小步。
   「合并实现、不要两套语义」的目标仍可达成，但方式是抽公共函数，不是重做 borrow。
3. **「方言生成」不能作为档①的官方通路。** 它只能作为仓库外实验；官方逃生门只有显式 `Callable`。
4. **「两档可零改动互通」在跨单元时不成立。** trait impl 的包装函数一律发射为 `static`
   （`Emitter.emit_impls` 的 `static %s`），只有「pub trait + pub struct」的 vtable 才导出。
   所以 `Adder_Callable_call` **只在同一翻译单元内**可当 `fn` 传递；跨单元只能走 vtable / iface，
   或由用户另写 `pub` 包装。Phase 21 必须把这条写进文档与 21.4 的交付物。

#### 3.3 仍然成立、可直接沿用的结论

- 档② = 档① 的自动展开；`(fn, env)` 两词；环境在栈上；无 `malloc/free`。
- trait 方法名 / 调用形态与提案 §3 一致（`self` 是 `void *`，调用传 `&obj`）。
- 撞墙必须硬报错并给逃生门 hint；档③ 不做。
- 已知限制（`store(add)` 这类跨过程漏洞）必须诚实标注。

---

### 4. 设计基线（21.2 / 21.3 的实现依据）

#### 4.1 语法

不引入 `auto`（CT 无类型推断，`auto` 不是关键字）。闭包的**表面类型**复用现有函数指针声明，
初始化式是闭包字面量：

```c
int apply(int base) {
    int n = 3;
    int (*add)(int x) = (int x) => x + n + base;   /* 单表达式体 */
    return add(5);
}
```

- 字面量：`(参数列表) => 表达式`；多行体：`(参数列表) => { 语句… }`（21.3）。
- 参数必须带类型（与 CT 的声明风格一致）；返回类型由左侧声明的函数指针给出，不推断。
- 无参：`() => expr`；`void` 返回：`void (*f)(int) = (int x) => { … };`。
- 表面类型是函数指针，但编译器把它标记为**闭包变量**；它不能被当作普通函数指针使用
  （§4.5 的 E6）。
- `=>` 只在「`)` 之后、表达式起始位置」被识别为闭包运算符；`>=`、`==`、`->` 不受影响。

**落地检查点**：现有 `parse_decl_node` 对函数指针的**局部初始化式**支持需要实测（
language-spec §4.12 只举了文件作用域初始化器与局部逐元素赋值）。若不支持，21.2 内一并补上，
这是本阶段最小的前端改动。

#### 4.2 捕获语义

**按值捕获（by value），在闭包创建点求值，只读。**

- 捕获集合 = 闭包体内自由出现的、属于**外层函数/外层闭包的局部变量或参数**的名字。
  全局变量、函数名、枚举常量、类型名**不捕获**（可直接引用）。
- 每个捕获在 env 结构里占一个同名字段；创建时拷贝当前值。指针按值拷贝 = 浅拷贝，
  通过指针写回是允许的（这是用户显式选择的语义）。
- 闭包体内**禁止重新赋值捕获名**（`n = 1;`、`n++` 一律硬报错）。要可变，捕获
  `int *p` 并写 `*p`，或用档①。
- 闭包体内**禁止声明与捕获名同名的局部**（避免解析歧义）。
- 捕获 `own` / `borrow` 变量 → 硬报错（与提案 §5 一致）。原因：`own` 的释放仍在外层出口，
  闭包若复制其句柄会制造第二份所有权；`borrow` 的归还在外层出口，同理。
- 嵌套闭包：内层捕获外层闭包的捕获变量时，从**外层 env 字段**读值再拷贝，不引用外层 env，
  不产生 env 之间的指针链。

#### 4.3 生成物与命名

```c
/* 文件作用域，先于外层函数 */
struct __ct_cl_env_1 { int n; int base; };
static int __ct_cl_tramp_1(void *self, int x) {
    struct __ct_cl_env_1 *e = self;
    return x + e->n + e->base;
}
int apply(int base) {
    int n = 3;
    struct __ct_cl_env_1 __ct_cl_env_v_1 = { n, base };
    return __ct_cl_tramp_1(&__ct_cl_env_v_1, 5);
}
```

- **命名**：`__ct_cl_env_<N>`（结构体 tag）、`__ct_cl_tramp_<N>`（trampoline）、
  `__ct_cl_env_v_<N>`（栈上实例），三者共用同一个 `N`。
- **N 的来源**：单元内单调递增计数器，与现有 `Emitter.ntmp`（`__ct_ret%d`）同风格；
  分配后不复用。嵌套、多层作用域、同一函数内多个闭包都靠它天然去重。
- **作用域**：env 结构与 trampoline 一律发在**本单元的 `.c` 文件作用域**，trampoline 为 `static`；
  绝不进 `.h`（闭包只可能出现在函数体里）。因此 **不加 namespace 前缀**：`static` + 一单元一 `.c`
  已经保证不冲突；`ct build` 两个单元各自有 `__ct_cl_tramp_1` 也合法。
- **顺序**：每对 (env struct, trampoline) 发在包含它的函数定义之前，外层先于内层；
  struct 先于其 trampoline。
- **调试映射**：`line_mode` 打开时，在 trampoline 前后重锚定 `#line`（复用 `Emitter` 现有机制）；
  无论开关，都在生成物前发 `/* closure at <file>:<line> */`；env 字段沿用源变量名；
  所有诊断只指向源位置，不出现 `__ct_cl_*`。
- **保留前缀**：`__ct_` 为编译器保留。用户声明以 `__ct_` 开头的标识符 → 硬报错
  （否则可能与 `__ct_retN` / `__ct_cl_*` 撞名）。这是新检查，成本低。
- **容量**：生成的 env 结构**不登记**进 `Symbols.Structs`（不占 `MAX_STRUCTS 128`）；
  每个闭包只占 1 个 `Var` 槽（闭包变量本身）+ 1 个闭包表项。

#### 4.4 ABI

**统一为两词 `(fn, env)`，`env` 是第一参数。**

```c
/* 档②生成 */
static int __ct_cl_tramp_1(void *self, int x);
/* 档①手写（同单元） */
static int Adder_Callable_call(void *self, int x);
/* 二者可交给同一个函数 */
static int run(int (*fn)(void *, int), void *env, int v) { return fn(env, v); }
```

- 不打包 `struct { fn, env; }`。打包只有档②能填，档①的 `impl` 包装函数是现成的 `fn`，
  打包会破坏「两档零改动互通」。
- 调用点：闭包变量 `add(5)` → `__ct_cl_tramp_1(&__ct_cl_env_v_1, 5)`。
- 作为实参：闭包是**一个源级实参**，在 `(fn, env)` 参数对上展开为两个 C 实参。
  例如 `each(v, add)` → `each(v, __ct_cl_tramp_1, &__ct_cl_env_v_1)`。
  识别规则（窄、可判）：被调方参数表中存在相邻的
  `ret (*P)(void *self, …)` + `void *E`，闭包实参必须落在这个对的起点。
  参数个数检查（Phase 19 的 arity）把闭包记为 2 个实参。
- **跨单元限制**：trampoline 与 impl 包装都是 `static`，闭包与档①的裸 `fn` 只能在**同一单元**内传递；
  跨单元走 vtable / iface，或用户自写 `pub` 包装。21.4 评估是否给 `Callable` 增加 `pub` 转发。

#### 4.5 逃逸判定

入口与现有 `own` / `borrow` 对齐，但一律硬错误：

| 编号 | 形态 | 判定 |
| --- | --- | --- |
| E1 | `return c;` / `return c.f;`（闭包变量在返回表达式中） | 错误 |
| E2 | `g = c;`、外层局部 `x = c;`、`static` 局部 | 错误（用 `var_scope` 比较：目标更浅 / 全局 / static） |
| E3 | `s->cb = c;`、`arr[i] = c;`、容器存入 | 错误（字段 / 元素一律拒绝，不做别名分析） |
| E4 | 捕获 `own` / `borrow` 变量 | 错误 |
| E5 | 闭包体内给捕获名赋值 | 错误 |
| E6 | 闭包变量赋给普通函数指针、或传给非 `(fn, env)` 参数对 | 错误 |
| E7 | 同作用域或更内层的局部拷贝 `int (*d)(int) = c;` | **允许**（env 仍在同一栈帧内） |
| E8 | `goto` 跨过闭包声明 | 已知静默失效（与 `own` / `borrow` 相同），文档记录，不做检查 |

复用点（明确到函数）：

- `Memory.expr_returns(e, name)`：判断「真移交」而不是「读字段」，E1 直接复用。
- `Stmt.var_scope(sym, vi)`：寿命比较，E2 直接复用。
- `Memory.leak_decl` / `leak_assign` / `leak_return` 的**调用位置**（`Stmt.h.ct` 的声明、赋值、return 三处）
  作为挂载点；不改变它们对 `own` 的行为。
- `check_borrow_store` 只处理 borrow；闭包另写 `check_closure_store`，共用 `var_scope` 与
  「全局 / static / 更浅作用域」的判定（21.1 抽公共函数）。

#### 4.6 诊断与 hint

CT 无错误码；契约是**稳定英文文案**，由 `check-ast.sh` 的负例断言钉住。
新增一个 `note:` 通道（`ct_sem_note(line, col, msg, path)`，不增加 `nsem`、不触发 `MAX_ERRORS`），
每条闭包错误的第二行是 hint：

```text
t.ct:4:9: error: a closure cannot escape through 'return'
t.ct:4:9: note: use an explicit Callable struct + trait: struct Adder { int n; } use Callable; impl Callable for Adder { int call(int x) { … } }
```

文案清单（小写、无句号、标识符单引号）：

```text
a closure cannot escape through 'return'
a closure cannot be stored in '<name>' (its scope outlives the closure)
a closure cannot be stored in a field, an element or a container
a closure cannot capture '<name>' (it is 'own' or 'borrow')
a captured variable cannot be reassigned inside a closure
a closure cannot be used where a plain function pointer is expected
a closure argument must fill a '(fn, env)' parameter pair
a local cannot shadow the captured '<name>'
identifier '__ct_' is reserved for the compiler
```

hint 必须给出**可抄的三行**档① 写法（`struct` / `use Callable` / `impl Callable for …`），
不能只写「不支持」。

#### 4.7 与 borrow 的共用检查

- borrow 阶段一 / 二已实现，Phase 21 **不重做**。
- 21.1 把 `check_borrow_store` 中的「目标是否更长寿命」抽成
  `static int outlives(struct Symbols *sym, int target, int source)`（全局 / `static` / `var_scope` 比较），
  borrow 与闭包两侧都调用它。
- 闭包作为参数传入时，「不持有」的语义由**参数对形状**表达（`fn` + `env` 相邻）；
  接收方函数体按同一套闭包规则编译，因此「在接收方把 env 存进全局 / 字段」会被同一条检查拦住。
- 这不扩展 `borrow` 的指针语义（`borrow` 仍只接受 struct 指针），也不引入第二个注解关键字。

#### 4.8 必须对用户诚实标注的限制

1. 逃逸判定拦得住 `g = c` / `s->f = c` / `return c`，**拦不住**把 `env` 以 `void *` 传给不透明 C 函数后
   由对方保存；ct-ast 不做跨过程可达性分析。
2. `goto` 跨过闭包声明静默失效（同 `own` / `borrow`）。
3. 捕获按值；对捕获名的写入不生效（直接报错，不静默）。
4. 闭包不能跨单元传递（`static`），也不能跨语言边界。
5. 环境在栈上，**闭包值本身不能被容器持有**；容器需要持有时走档①。

#### 4.9 类型宿主隔离（防 std 的歧义坑）

`map trait T for type <ctype>` 的候选集按类型全局聚合，std 已踩过 `ambiguous type-host map`。
闭包**不得**进入这条派发通路：

- 闭包调用、传参、逃逸检查一律以 `Var.is_closure` 为唯一依据，不查 trait / 类型宿主；
- 不提供 `.call()` 方法语法：闭包只能 `c(args)` 直接调用；
- 禁止对函数指针类型使用 `map trait … for type`；官方 `Callable` 只能是真实 struct 类型；
- `Callable` 只作为 trait 名存在，不叠加同名类型宿主。

否则 `char *` 宿主映射会与闭包调用点共享候选集，每个闭包调用都可能变成歧义报告。

---

### 5. 分段计划

| 段 | 内容 | 前置 | 并行 | 里程碑 | 出口 |
| --- | --- | --- | --- | --- | --- |
| 21.0 | **容器回调约定**（只写文档 + 示例，不改 std 包） | 无 | 与 21.2 / 21.3 并行 | M21-A | 示例在既有关卡下编译运行；签名与 §4.4 一致 |
| 21.1 | **共用寿命判定抽取**（borrow 行为不变） | 无 | 与 21.0 并行 | M21-A | `check-ast` / `check-goldens` 全绿；borrow 生成物逐字节不变 |
| 21.2 | **档② 核心**：单表达式闭包、逃逸硬错误、诊断与 hint | 21.1 | 与 21.0 并行 | **M21-B（ABI 冻结）** | 探针 70–75 + 78；`check-warnings` 绿；无 `malloc` |
| 21.3 | **多行体 / 嵌套 / 参数对调用点 / 跨单元探针** | M21-B | 与 21.4 并行 | M21-C | 探针 71、76、77、79 |
| 21.4 | **官方 `Callable` 约定**（std / ct-pkg，按签名一族） | M21-B + 跨仓库授权 | 与 21.3 并行 | M21-D | 档① 与档② 同函数互操作；跨单元限制成文 |
| 21.5 | **自举 + 文档 + 收口** | 21.2–21.4 | 串行，最后 | M21-E | 11 门禁 + CI + nightly；bump `v0.21.0` |

#### 21.0 容器回调约定

- **目标**：把 `map` / `filter` / `each` 的回调签名定成 `(fn, env)`，供容器与闭包共用。
- **交付**：本文件附录 A（签名表 + 两个示例）；`examples/` 一个只用档① 的容器遍历示例。
- **验收**：示例编译运行；`grep -c malloc` 为 0；与 §4.4 的参数顺序一致。
- **判断**：它是**约定**，不是容器实现，也不阻塞闭包。完整容器（`StringBuf`、`Map.grow`、`Vec` 泛型；
  `StringBuf` 为规划名，ct-pkg 尚无此类型）
  不在本阶段；`Vec` 泛型属「Phase 22+ / 1.0 之后」。

#### 21.1 共用寿命判定抽取

- **目标**：`outlives()` 成为 borrow 与闭包共用的唯一寿命判断。
- **交付**：`frontend/parse/Stmt.h.ct` 重构；`check_borrow_store` 改调 `outlives()`。
- **验收**：`62_borrow_handback` 与全部 borrow 负例仍通过；抽取前后生成 C 逐字节一致。

#### 21.2 档② 核心（ABI 冻结点）

- **目标**：单表达式闭包端到端可用；逃逸硬错误；hint 到位。
- **交付**：
  - lexer：`=>` token（仅在表达式位置）；
  - parser：闭包字面量、`ret (*name)(params) = (params) => expr`、`Var.is_closure` / `closure_id`、
    闭包表；
  - 检查：E1–E6、`__ct_` 保留前缀、捕获只读；
  - emitter：env struct + trampoline + 栈上实例 + 调用点改写；
  - Diag：`ct_sem_note` 通道 + §4.6 文案。
- **验收**：探针 70–75、78；`grep -c malloc` = 0；`check-warnings` 绿；71 个既有 golden 仅版本 token；
  文档门禁绿。
- **冻结**：M21-B 之后，`(fn, env)` 参数顺序、命名规则、调用点展开规则不再改。

#### 21.3 多行体 / 嵌套 / 参数对

- **目标**：`=> { … }`、嵌套闭包、闭包作为实参的配对展开、跨单元探针。
- **交付**：block body 解析（复用 `parse_block` + 合成作用域）；嵌套 env；调用点两参展开；
  arity 检查把闭包记为 2；`build` 两单元闭包探针。
- **验收**：探针 71、76、77、79；`ct build` 两单元各自 `static` 不冲突；`goto` 限制成文。

#### 21.4 官方 `Callable`（按签名一族）

- **目标**：给档① 一个可抄的官方形态，并验证两档互通。
- **关键判断**：无泛型 → **不存在万能 `Callable`**。一个 trait 只能有一个 `call` 签名。
  因此交付的是「一份约定 + 少量按签名的具体 trait」，不是单个万能接口。
- **交付**：约定文档（`use Callable`、`call` 的 `self` 位置、`(fn, env)` 分解规则）；
  `ct-pkg/std` 中 2–3 个具体可调用 trait（建议 `Callable0`：`int call(void)`、
  `Callable1i`：`int call(int)`），其余签名按同一形态手写；跨单元 `pub` 转发方案（若用户批准）。
- **前置**：跨仓库改动需用户显式授权；本仓库只放示例与文档。
- **验收**：探针 78（档① struct 的 `call` 与档② tramp 交给同一个 `(fn, env)` 函数）；
  ct-pkg 包的测试绿；跨单元限制在文档与错误提示中都写明。

#### 21.5 自举与收口

- **目标**：编译器自己先支持、再使用；文档与版本收口。
- **交付**：§7 的三步自举；language-spec / tutorial / glossary / roadmap 更新；
  `CTC_VERSION` 五处 bump 到 `0.21.0`；71 个 golden 仅版本 token 变化。
- **验收**：11 道硬门禁 + CI 三 job + nightly 全绿；fixpoint 通过；
  编译器源码中 `=>` 的出现只允许在 `v0.21.0` 二进制可用之后。

#### 里程碑

| 里程碑 | 含义 | 判据 |
| --- | --- | --- |
| M21-A | 地基就绪 | 21.0 文档 + 21.1 抽取完成，borrow 生成物逐字节不变 |
| **M21-B** | **ABI 冻结** | 21.2 全部探针绿；`(fn, env)` / 命名 / 调用点规则不再改 |
| M21-C | 能力完整 | 21.3 探针绿；多行体、嵌套、参数对、两单元 |
| M21-D | 档① 官方化 | 21.4 互通探针 + ct-pkg 测试绿 |
| M21-E | 收口 | 21.5 全部门禁 + fixpoint + `v0.21.0` |

---

### 6. 对提案排期顺序的判断

提案建议：**容器规约 → borrow 阶段一 → 档② 闭包 → 官方 Callable**。逐条判断：

| 提案理由 | 判断 |
| --- | --- |
| 容器先落地，因为闭包最大用途是 `map/filter` | **不成立**。无泛型时 `VecInt.map` 与 `VecStr.map` 仍需各自的包装函数；闭包省掉的是每处 adapter struct，不是每元素类型的函数。且容器回调签名一旦先冻结，很可能把 `env` 顺序 / 是否打包定错。**应先定闭包 ABI，再定容器回调** |
| borrow 阶段一必须先做，且与档② 合并 | **已完成**。只剩抽公共寿命判定（21.1），必须与闭包逃生检查同批，不能分两次做 |
| 官方 Callable 最后 | **成立**，但要注意它只能是「按签名一族」，不是万能接口 |
| 闭包最大用途是容器 | **部分成立**：容器是收益之一，但今天的即时收益还包括 C 回调（`qsort`、事件注册）与就地循环，这些不依赖容器 |

**建议顺序**（若用户采纳）：

```text
21.1 共用判定（小，先行）
21.2 档② 核心 + ABI 冻结   ← 与 21.0 文档并行
21.3 多行 / 嵌套 / 参数对   ┐
21.4 官方 Callable          ┘ 可并行（21.4 在 ct-pkg，需授权）
21.5 自举与收口（串行，最后）
```

即：**把「容器规约」从阻塞项降为并行项，把「borrow 阶段一」从一整段降为 21.1 的一次抽取**。
这是本计划与提案排期最大的两处不同。

---

### 7. 自举纪律（必须写进里程碑）

顺序不能倒挂：

1. **M21-B 之前**：编译器源码（`selfhost/ct-ast/**`）**不得出现 `=>`**。所有闭包能力只用
   `test/ast/**` 的探针与 `examples/**` 验证，探针由「手写档① 的编译器」编译。
2. **M21-E1**：用现有编译器编译新编译器 → 新二进制能编全部闭包探针；
   用新二进制再编一次自身，产物与第一次一致（fixpoint）。
3. **M21-E2**：fixpoint 绿且 `v0.21.0` 已安装后，才允许在 `selfhost/ct-ast/**` 中使用 `=>`。
   这一步单独提交，并声明：**更老的 `ct` 不能再编译本仓库的编译器源码**（自举链的最低版本抬到 v0.21.0）。
4. 守卫：`check-ast.sh` 增加一条断言——`selfhost/ct-ast/**` 中 `=>` 的命中数必须为 0，
   除非仓库存在 `v0.21.0` tag（M21-E2 之后）。这样「编译器自己先用了」会直接红。

---

### 8. `=>` 变保留字的破坏面（实数）

扫描范围与结果（2026-11-06 实测）：

| 范围 | 文件数 | `=>` 命中 |
| --- | --- | --- |
| 本仓库 `.ct`（含 `.h.ct` / `.m.ct`） | 398 | **0** |
| 本仓库 `.c` / `.h` | 135 | **0** |
| 同级 `ct-pkg` 仓库 `.ct` | 55 | **0** |
| 同级 `ct-pkg` 仓库 `.c` / `.h` | 117 | **0** |

非 CT 语法的命中（不构成破坏面，但需在迁移说明中区分）：

- `editors/vscode/extension.js`：24 行，是 JS 箭头函数，不是 CT 标识符；
- 三份历史报告的 `mermaid.min.js`：414 行，vendored 资产；
- `docs/history/reports/**` 的 `.md`：10 行，表格 / 文本；
- `install.sh`：1 行，`printf '==> %s\n'`；
- `.ttf` 字体二进制：若干字节巧合。

**结论：把 `=>` 设为保留字，现有 CT 标识符破坏数为 0（533 个仓库源文件 + 172 个 ct-pkg 文件全部无冲突）。**
唯一的兼容性成本是编辑器语法需要新增 `=>` 规则（`editors/vscode` 的 grammar 断言随之 +1）。

---

### 9. 风险与回退

| # | 风险 | 处置 |
| --- | --- | --- |
| R1 | 函数指针局部初始化式可能不被 `parse_decl_node` 接受 | 21.2 首个切片实测；不支持则在同一切片扩展声明解析 |
| R2 | 捕获名解析与遮蔽歧义 | 禁止闭包体内声明同名局部；禁止给捕获名赋值 |
| R3 | 生成物进 `.h` / 跨单元撞名 | 只发 `.c`；`static`；探针 79 两单元验证 |
| R4 | 跨单元裸 `fn` 不可用 | 文档 + hint 写明；21.4 评估 `pub` 转发 |
| R5 | `-Wall -Wextra` 下 trampoline 未使用告警 | 照 `Drop` 的先例加 `__attribute__((unused))` |
| R6 | 新表 / 计数超出 `MAX_*` | env 结构不登记 `Structs`；每闭包仅 1 个 `Var` + 1 个闭包表项 |
| R7 | hint 被计入 `MAX_ERRORS` | `ct_sem_note` 不增加 `nsem`、不触发上限 |
| R8 | 闭包值被当作普通函数指针误用 | 新增 `E6` 检查；探针覆盖 |
| R9 | 闭包误入类型宿主 `map` 派发，复制 std 的 `ambiguous` 坑 | §4.9 隔离规则；探针 81 |
| R10 | 断点停在合成帧，生成物失去可读性对应 | `#line` 重锚定 + `/* closure at … */` + 源名；探针 80 |

**回退**：`=>` 是 opt-in，不写不检查；回退即移除 lexer / parser / emitter 的闭包分支与 `Var.is_closure`，
其余能力（borrow、Phase 19 检查、包管理）不动；无数据格式与 ABI 兼容负担。

---

### 10. 待确认决策

| # | 问题 | 建议值 | 状态 |
| --- | --- | --- | --- |
| D21-1 | 语法：是否用 `ret (*name)(params) = (params) => expr`，不引入 `auto` | 采用；多行体 `=> { … }` | 待确认 |
| D21-2 | 捕获：按值 vs 按引用 | 按值、创建点求值、捕获名只读 | 待确认 |
| D21-3 | 生成物命名 | `__ct_cl_env_<N>` / `__ct_cl_tramp_<N>` / `__ct_cl_env_v_<N>`，单元内单调，无 namespace 前缀 | 待确认 |
| D21-4 | ABI：两参数 vs 打包 struct | 两参数、`env` 第一；闭包实参在 `(fn, env)` 参数对上展开为两参 | 待确认 |
| D21-5 | 逃逸判定扩展点 | E1–E6；同/内层局部拷贝允许；`goto` 记录为已知限制 | 待确认 |
| D21-6 | 诊断契约 | 无错误码；固定英文文案 + `note:` hint；负例由 `check-ast.sh` 钉住 | 待确认 |
| D21-7 | `Callable` 签名 | 按签名一族，不做万能 trait；`use Callable` 不强制 `use Drop` | 待确认 |
| D21-8 | namespace 交互 | 不加前缀（`static` + 单元私有） | 待确认 |
| D21-9 | golden 用例 | §11 的 70–79 | 待确认 |
| D21-10 | 版本 | Phase 21 ↔ `v0.21.x`，收口 `v0.21.0` | 待确认 |
| D21-11 | 排期 | 21.1 → 21.2（冻结 ABI）→ 21.3 ∥ 21.4 → 21.5；21.0 并行不阻塞 | 待确认 |
| D21-12 | 泛型口径 | 不引入；STD-1 的「Phase 21+」改为「Phase 22+ / 1.0 之后」 | 待确认 |

---

### 11. golden 用例（`test/ast/**`，由 `check-ast.sh` 自动发现）

| 编号 | 用例 | 期望 |
| --- | --- | --- |
| 70 | `closure_basic` | env + tramp + 栈上实例；结果正确；生成 C 无 `malloc` |
| 71 | `closure_nested_block` | 嵌套闭包 / 多行体；env 名不冲突；逐层正确 |
| 72 | `closure_escape_return` | `return c;` 硬错误 + hint |
| 73 | `closure_escape_store` | 全局 / 外层局部 / `static` / 字段 / 元素 硬错误 |
| 74 | `closure_capture_own_borrow` | 捕获 `own` / `borrow` 硬错误 |
| 75 | `closure_param_pair` | 传给 `(fn, env)` 参数对通过；传给普通函数指针报错 |
| 76 | `closure_opaque_hole` | 经 `void *` 传给不透明函数并保存 → **记录为已知未防护**（不误报通过） |
| 77 | `closure_goto` | 记录现状（静默失效），不崩 |
| 78 | `callable_interop` | 手写档① 的 `call` 与档② tramp 交给同一个函数；零改动 |
| 79 | `closure_two_units` | `ct build` 两单元各自 `static` 命名不冲突 |
| 80 | `closure_debug_line` | 开启 `#line` 时，trampoline 行映射回闭包源行；生成物含 `/* closure at … */` |
| 81 | `closure_no_typehost` | 存在 `map trait … for type` 时，闭包调用仍直接解析，不产生歧义 |

---

### 12. 出口判据

Phase 21 完成需同时满足：

1. 11 道硬门禁全绿；CI 三 job + nightly 全绿。
2. 探针 70–79 全部按上表行为；负例文案被 `check-ast.sh` 钉住。
3. 既有 71 个 golden 仅版本 token 变化（`v0.21.0`）。
4. 生成物：闭包探针无 `malloc` / `free` / 引用计数 / vtable；只有 env struct + `static` trampoline。
5. fixpoint 通过；编译器源码的 `=>` 使用在 M21-E2 之后。
6. 文档：language-spec 增加闭包一节；tutorial 有「档② 还是档①」的判据表；glossary 加 `closure` /
   `trampoline` / `env`；roadmap 状态改为完成。

---

## English

### Summary

**Status: planned** (2026-11-06). **Phase 21 ↔ `v0.21.x`, closing bump to `v0.21.0`.** The repo is at
`v0.20.0`; Phase 17/18/19/20 are done, Phase 20 (package support, [phase20.md](phase20.md)) is closed and
independent of this phase. The gate count is **11** (the "12" in the
Phase 19 roadmap row is a typo).

This phase implements **tier ② non-escaping stack closures** (`=>`), lowered **as an expansion of tier ①**
(`struct` + `trait`), sharing one `(fn, env)` ABI. Tier ③ (general escaping closures) is out of scope.

### Corrections to the v0.12.0 proposal (verified against v0.19.1)

1. `own`/AutoDrop escape detection is **not** "two shapes": it now has four entry points
   (`leak_decl`, `leak_assign`, `leak_return` with SH-36/41 true-transfer semantics, and the
   path-sensitive `leak_scope`). The suggested "third kind of rvalue" shortcut does not apply:
   the machinery is variable-centric, while a closure is a `(fn, env)` pair of locals; and `own`
   escapes *cancel* a destructor while a closure escape must be a **hard error**.
2. `borrow` stage one/two **already shipped** in v0.16.0 (hardened in v0.16.1). Phase 21 only extracts
   the shared lifetime test (`outlives`) and reuses it from the closure checker.
3. The dialect system cannot serve as an official tier-① path: the compiler has zero DSL awareness;
   dialect expanders live only outside the compiler (`examples/`, `test/ct-dialects/`).
4. `Adder_Callable_call` is emitted `static`, so the `(fn, env)` interchange is **same-unit only**;
   cross-unit callbacks go through the vtable/iface or a user-written `pub` wrapper.
5. CT has **no error codes**; the diagnostic contract is stable English text plus a new `note:` hint line.

Still valid: the `(fn, env)` two-word model, stack-only environment, `struct + trait` mangling
(`<Struct>_<Trait>_<method>(void *self, …)`), and the requirement to hard-fail with a `Callable` hint.

### Pinned design baseline

- Syntax: `int (*add)(int x) = (int x) => x + n;` (no `auto`; multi-line body `=> { … }`).
- Capture: **by value** at creation, captured names are read-only; `own`/`borrow` captures are errors.
- Generated names: `__ct_cl_env_<N>`, `__ct_cl_tramp_<N>`, `__ct_cl_env_v_<N>`; a per-unit monotonic
  counter (like `__ct_ret%d`); file-scope `static`, never in headers, no namespace prefix.
- ABI: two words, `env` first; a closure argument fills an adjacent `(fn, env)` parameter pair.
- Escapes: return / longer-lived store / field or element store / plain function pointer / mutable
  capture — all hard errors with a three-line `Callable` hint. `goto` stays a documented silent failure.

### Slices

| Slice | Content | Order |
| --- | --- | --- |
| 21.0 | Container callback convention (docs + example only) | parallel, non-blocking |
| 21.1 | Extract `outlives()` shared with `borrow` | first, serial |
| 21.2 | Tier-② core: single-expression closures, escape errors, hints | after 21.1; **freezes the ABI** |
| 21.3 | Block bodies, nesting, parameter-pair call sites, two-unit probe | after the freeze; parallel with 21.4 |
| 21.4 | Official `Callable` family (per signature; no universal trait without generics) | after the freeze; needs ct-pkg authorisation |
| 21.5 | Bootstrap discipline, docs, `v0.21.0` close | last, serial |

**Ordering judgement:** the proposal's "containers first" does not hold without generics — each element
type still needs its own wrapper, and freezing container callbacks before the closure ABI risks freezing
the wrong signature. Do the ABI first; keep the container convention parallel and non-blocking.

**Bootstrap:** compiler sources must not use `=>` before M21-B; after the fixpoint and the `v0.21.0`
install, `=>` may enter `selfhost/ct-ast/**` (M21-E2). A gate assertion keeps the order honest.

**`=>` breakage:** 0 occurrences in 398 `.ct` + 135 `.c/.h` sources here, and 0 in 55 `.ct` files under
`ct-pkg`. Only JS arrow functions in the editor extension and vendored report assets match.
