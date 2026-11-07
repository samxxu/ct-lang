# Phase 21 计划（规划中）：非逃逸栈闭包

> 中文 · [English](#english)
>
> **状态：规划中**（2026-11-06 立项；2026-11-08 按 HEAD `v0.20.2`（`0263cca`）实测勘误，补设计缺口 G1–G3
> 与切片 S0–S7；D21-13–D21-16（第一批）与 D21-1 / D21-2 / D21-4 / D21-5（第二批）已于 2026-11-08 定稿；
> D21-8 并入 D21-3、D21-17 并入 D21-14；其余 7 条待用户确认）。
> **版本口径：Phase 21 ↔ `v0.21.x`，收口 bump 到 `v0.21.0`。** 当前仓库 `v0.20.2`（`CTC_VERSION` 五处一致）。
> 前置：Phase 17 / 18 / 19 / 20 均已完成；Phase 20 = 包支持（[phase20.md](phase20.md)，已完成，与本相无语义依赖）。
> 关联：[borrow 设计](../history/design/borrow.md)、[language-spec](../language-spec.md)、
> [std 能力缺口](../../issues/std/std1-markdown-readiness.md)、[roadmap](../roadmap.md)。

---

## 中文

### 0. 一页结论

| # | 判断 | 结论 |
| --- | --- | --- |
| 1 | 提案的物理模型（`(fn, env)` 两词、档② = 档① 自动展开） | **成立**，且与今天的 `<Struct>_<Trait>_<method>(void *self, …)` 同形 |
| 2 | 提案的「逃逸判定复用 `own`、扩展闭包为第三类右值，性价比最高」 | **不成立**。`own` 的判定是变量中心 + 取消析构 + 泄漏警告；闭包逃逸必须是硬错误。闭包在语义上是**绑定**、实现上是一对局部（`fn`, `env`），`Var` 里也没有可复用的槽：`Var.st` 是 **struct 下标**（类型为 `struct T *` 时指向结构体表），不是作用域下标；作用域深度来自 `sym->scope[]` / `nscope`，由 `Stmt.var_scope(sym, vi)` 推导。可复用形态识别与寿命比较，不能复用数据结构 |
| 3 | 提案的「容器先行，因为闭包最大用途是 map/filter」 | **不成立**（无泛型）。容器上的闭包省掉的是每处 adapter struct，不是每元素类型的包装函数；且先冻结容器回调签名，会把错误的 ABI 固化下来 |
| 4 | 提案的「borrow 阶段一尚未实现、需合并」 | **已实现**（v0.16.0 阶段一 + 阶段二，v0.16.1 加固）。Phase 21 只剩「抽出共用的寿命判定并由闭包侧接入」 |
| 5 | 设计草案本身 | **整体可实现，但有 4 处需修、2 处过期、1 处事实错误**（§4.10）；另外有 3 个未覆盖的实现缺口 G1–G3（§4.11） |

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

四点必须钉死：

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
- 不把 `Callable` 做成「万能可调用」：无泛型时它只能是**按签名一族**的约定，不是一个 trait 包打天下（§4.9 / S6）。
- 不改 L0 / L1 / L2；新能力只落 `selfhost/ct-ast/**`、`docs/**`、`test/ast/**`、`examples/**`。
- 不为闭包改 `CTC_VERSION` 之外的生成物形态；既有 golden 只允许版本 token 变化。口径是
  **`test/cases` 25 组逐字节 golden**（`check-goldens.sh` 的 baseline ratchet；`test/cases` 目录共 98 个文件，
  未进 baseline 的记为 PENDING，不参与失败判定）**+ `test/ast` 68 个编号探针**（HEAD 共 69 个目录 =
  68 个编号 + `errors`，编号 67 缺位）。

---

### 3. 核对：v0.12.0 提案 vs HEAD 实测（偏差单独成节）

#### 3.1 逐项核对

| # | 提案依赖的机制 | HEAD 实测 | 判定 |
| --- | --- | --- | --- |
| 1 | `own` / AutoDrop「两套逃逸形态：`q = p;`、`return p;`」 | 现有 **4 个入口**：声明初始化式 `leak_decl`、赋值 `leak_assign`（含 `s->f = p` 的基名）、`return` 的 `leak_return` + `expr_returns`（SH-36/41 区分「读字段」与「真移交」）、作用域出口 `leak_scope`（路径敏感 + `path_warned`）。另有 `ret_owned` 一级跨过程提示。形态只增不减 | **提案低估了形态数量** |
| 2 | 「扩展闭包值为第三类右值」是性价比最高的切入点 | 判定是**变量中心**：`Var{owned, autodrop, borrowed, st, is_param, is_global, is_static}` + 名字 token 匹配。闭包值是「一对局部（fn, env）」，没有 struct 类型可挂，`Var.st` 也不承担作用域信息（它是 struct 下标）；且 `own` 逃逸 = 取消析构/泄漏警告，闭包逃逸 = **硬错误** | **不成立**，见 §3.2 |
| 3 | trait / impl mangling：`Adder_Callable_call(&adder, x)` | 仍成立：`<Struct>_<Trait>_<method>(void *self, …)`，调用方传 `&obj`；vtable 为 `struct <Trait>_vtbl`，实例级为 `<inst>_<Trait>_vtable` | **成立**（有一处限制，见 §3.3） |
| 4 | 官方 `Callable` | 全仓 **0 命中**；`Callable` 不存在，属绿地 | 提案 §9 不是「官方化」，是新建 |
| 5 | 方言生成可作档①通路 | 编译器对 DSL **零感知**；方言只允许是 `examples/` 与 `test/ct-dialects/` 下的仓库外展开器（Phase 6.6 / D20） | 提案 §1 把「方言生成」列为档①基础机制 **不成立** |
| 6 | `=>` 未被占用 | **确认**：398 个 `.ct` + 135 个 `.c/.h` 中 0 处；`ct-pkg` 55 个 `.ct` 中 0 处（详见 §8） | **成立** |
| 7 | borrow 阶段一待做、建议与档②合并 | **已实现**：`borrow` 参数注解 + 变量声明 + 出口 `handback`（v0.16.0），SH-33/35/36/37/39/40/41 已修；探针 `test/ast/61_autodrop_return`、`62_borrow_handback`；[borrow.md](../history/design/borrow.md) §12 记录实现差异 | **前提已消失**，见 §3.2 |
| 8 | 提案要求「错误码」 | CT **没有错误码体系**。硬错误统一走 `ct_sem_error(line, col, msg, path)` → `path:line:col: error: msg`；只有警告有 `Warn.kind` 分桶（0–6） | 需要换一种可钉住的契约（§4.6） |
| 9 | 局部函数指针初始化式是否可用（原 R1） | **可用**：`Stmt.h.ct` 的声明路径对含 `(*` 的类型置 `fnval_ok`，`int (*p)(int) = strcmp;` 已被接受并发射 | **风险已消解**（§4.1 / §4.10） |

#### 3.2 因核对而失效的提案结论

1. **「复用 `own` 基础设施、把闭包当第三类右值」不可直接执行。**
   可复用的是**形态识别**（声明 / 赋值 / return / 作用域出口四个入口）与**寿命比较**
   （`Stmt.var_scope(sym, vi)`：变量所属 scope 更浅 = 更长寿命；作用域边界在 `sym->scope[]` / `nscope`）。
   数据结构和语义都要新建：
   - `Var` 增加 `is_closure` / `closure_id`（1 个 flag + 1 个 id），不复用 `owned` / `autodrop`；
   - 新增闭包表（id → env 结构名、trampoline 名、捕获字段清单、owner 函数）；
   - 逃逸是硬错误（`ct_sem_error`），不是取消析构 + 泄漏警告。
   因此该项**不是「性价比最高」的小改动**，而是一个独立检查器；它仍比通用闭包轻得多。
2. **「borrow 阶段一尚未实现，需要与档②合并」失效。** 阶段一 / 二已落地。Phase 21 只剩下
   「把 `check_borrow_store` 里的寿命比较抽成公共判定，并让闭包侧调用它」这一小步。
   「合并实现、不要两套语义」的目标仍可达成，但方式是抽公共函数，不是重做 borrow。
3. **「方言生成」不能作为档①的官方通路。** 它只能作为仓库外实验；官方逃生门只有显式 `Callable`。
4. **「两档可零改动互通」在同单元成立，跨单元要加限定。** trait impl 的包装函数一律发射为 `static`
   （`Emitter.emit_impls` 的 `static %s`），只有「pub trait + pub struct」的 vtable 才导出。
   准确表述见 §4.4：**不能按符号名跨单元引用**，但把 trampoline / 包装函数的地址当实参传出去是合法 C。

#### 3.3 仍然成立、可直接沿用的结论

- 档② = 档① 的自动展开；`(fn, env)` 两词；环境在栈上；无 `malloc/free`。
- trait 方法名 / 调用形态与提案 §3 一致（`self` 是 `void *`，调用传 `&obj`）。
- 撞墙必须硬报错并给逃生门 hint；档③ 不做。
- 已知限制（`store(add)` 这类跨过程漏洞）必须诚实标注。

---

### 4. 设计基线（S2 / S3 的实现依据）

#### 4.1 语法

**已定稿（D21-1，2026-11-08）：沿用函数指针声明，不引入 `auto`、不做类型推断；误用由 E6 拦。**
CT 里 `auto` 是 C 的存储类，引入它等于同时引入类型推断，与本相「无泛型、无推断」冲突。
闭包的**表面类型**复用现有函数指针声明，初始化式是闭包字面量：

```c
int apply(int base) {
    int n = 3;
    int (*add)(int x) = (int x) => x + n + base;   /* 单表达式体 */
    return add(5);
}
```

- 字面量：`(参数列表) => 表达式`；多行体：`(参数列表) => { 语句… }`（S5）。
- 参数必须带类型（与 CT 的声明风格一致）；返回类型由左侧声明的函数指针给出，不推断。
- 无参：`() => expr`；`void` 返回：`void (*f)(int) = (int x) => { … };`。
- 表面类型是函数指针，但编译器把它标记为**闭包变量**；它不能被当作普通函数指针使用
  （§4.5 的 E6）。
- `=>` 只在「`)` 之后、表达式起始位置」被识别为闭包运算符；`>=`、`==`、`->` 不受影响。

**落地检查点（已由 HEAD 证实，2026-11-08，不再是待办）**：函数指针的**局部初始化式**已被接受——
`Stmt.h.ct` 的声明路径在类型含 `(*` 时置 `fnval_ok`，`int (*p)(int) = strcmp;` 可解析并发射。
因此前端不必先补声明解析，S2 只需在同一路径上识别 `=>` 字面量。

#### 4.2 捕获语义

**已定稿（D21-2，2026-11-08）：按值捕获、创建点求值、捕获名只读；写捕获名报错；需要写回就捕获
指针并显式解引用。**

捕获语义：

- 捕获集合 = 闭包体内自由出现的、属于**外层函数/外层闭包的局部变量或参数**的名字。
  全局变量、函数名、枚举常量、类型名**不捕获**（可直接引用）。
- 每个捕获在 env 结构里占一个同名字段；创建时拷贝当前值。指针按值拷贝 = 浅拷贝，
  通过指针写回是允许的（`int *p` 捕获后写 `*p`，这是 D21-2 指定的写回方式）。
- 闭包体内**禁止写捕获名**：`n = 1;`、`n++`、`n += 1` 一律硬报错；也**禁止取捕获名地址**
  （`&n`），否则 env 内部地址可能被交到比 env 更长命的地方。
- 闭包体内**禁止声明与捕获名同名的局部**（避免解析歧义）。
- 捕获 `own` / `borrow` 变量 → 硬报错（与提案 §5 一致）。原因：`own` 的释放仍在外层出口，
  闭包若复制其句柄会制造第二份所有权；`borrow` 的归还在外层出口，同理。
- 捕获**另一个闭包变量** → 硬报错：闭包是绑定不是值（与 E7 同一条规则），不能按值捕获。
- **闭包变量声明即绑定**：变量名只是那个 `(trampoline, env)` 对的别名，本身不是可复制的值。
  `c = d;`、`int (*d)(int) = c;`、以及任何把 `c` 放到别的变量名的写法一律硬报错（D21-16，已定稿）；
  hint 指向「就地内联闭包」或档①（`struct` + `trait`）。
- 嵌套闭包：内层捕获外层闭包的捕获变量时，从**外层 env 字段**读值再拷贝，不引用外层 env，
  不产生 env 之间的指针链。

**与既有内存分析的接缝（新增检查，落 S4）**：`own` / `borrow` / `Drop` 与 `check_borrow_store`
都是变量中心的，判的是「所有权移交」与「borrow 存到更长寿命处」，**不覆盖**只读捕获。D21-2 需要
四个新检查，已写入 S4 验收：

| 检查 | 判据 | 为什么现有检查不覆盖 |
| --- | --- | --- |
| `check_closure_capture_write` | 闭包体内写捕获名（`=` / `++` / 复合赋值） | `leak_assign` 只判 `own` 的移交，不判只读捕获；`*p = …` 必须放行 |
| `check_closure_capture_addr` | 闭包体内取捕获名地址 `&n` | 现有 borrow 检查不分析 env 字段的地址逃逸 |
| `check_closure_capture_own` | 捕获项是 `own` / `borrow` 变量 | 必须在 AutoDrop / borrow 注册**之前**拦，否则先复制句柄再报错已晚 |
| `check_closure_capture_closure` | 捕获项是另一个闭包变量 | E7 只管赋值，捕获是另一条 AST 路径 |

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
- **顺序与时机（D21-15，已定稿）**：解析期在闭包表里记下每个闭包的 **owner 函数**；发射器在写每个
  函数体**之前**，先按 owner 预扫该函数的闭包并就地发 env struct 与 `static` trampoline，再写函数体。
  每对 (env struct, trampoline) 都在函数定义之前，外层先于内层，struct 先于 trampoline；
  单遍发射主干不变。**零闭包单元的生成物必须逐字节不变**。
- **调试映射**：`line_mode` 打开时，在 trampoline 前后重锚定 `#line`（复用 `Emitter` 现有机制）；
  无论开关，都在生成物前发 `/* closure at <file>:<line> */`；env 字段沿用源变量名；
  所有诊断只指向源位置，不出现 `__ct_cl_*`。
- **保留前缀**：`__ct_` 为编译器保留。用户声明以 `__ct_` 开头的标识符 → 硬报错
  （否则可能与 `__ct_retN` / `__ct_cl_*` 撞名）。这是新检查，成本低。
- **容量**：生成的 env 结构**不登记**进 `Symbols.Structs`（不占 `MAX_STRUCTS 128`）；
  每个闭包占 1 个 `Var` 槽（闭包变量本身）+ 1 个闭包表项（建议 `MAX_CLOSURES 64`，见 M3）。
  闭包变量在 C 侧是两个局部（fn + env），但源级只算 1 个变量。

#### 4.4 ABI

**已定稿（D21-4，2026-11-08）：两词 `(fn, env)`，`env` 是第一参数；与档① `impl` 包装
`(void *self, …)` 同形。这是 ABI 冻结点：S3 之后不可改（顺序、命名、调用点展开规则一并冻结）。**

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
  参数个数检查（Phase 19 的 arity）把闭包记为 2 个实参。字面量直接作实参时的类型比对见 G2 / D21-14。
- **跨单元限制（准确表述）**：
  - **可以**：把 trampoline / impl 包装的**地址**作为实参传给另一个单元的函数，由对方在运行期调用
    （地址只是函数指针，C 层面完全合法）。典型形态是「本单元创建闭包，调用别单元的 `each`」。
  - **不可以**：按符号名在另一个单元引用 `__ct_cl_tramp_*` / `Adder_Callable_call`（都是 `static`）；
    闭包类型出现在 `.h.ct`；把闭包作返回值；把闭包作字段或数组元素；在另一单元声明闭包变量。
  - 公开给别单元时走 vtable / iface，或用户自写 `pub` 包装；21.4 / S6 评估是否给 `Callable` 增加 `pub` 转发。

#### 4.5 逃逸判定

**已定稿（D21-5，2026-11-08）：逃逸检查做全量 E1–E7，一律硬错误；E8 是「传给不透明 C 函数时
拦不住、但必须说明」的文档级诊断，E9 记录 `goto` 的静默失效。**

| 编号 | 形态 | 判定 |
| --- | --- | --- |
| E1 | `return c;` / `return c.f;`（闭包变量在返回表达式中） | 错误 |
| E2 | `g = c;`、外层局部 `x = c;`、`static` 局部 | 错误（用 `var_scope` 比较：目标更浅 / 全局 / static） |
| E3 | `s->cb = c;`、`arr[i] = c;`、容器存入 | 错误（字段 / 元素一律拒绝，不做别名分析） |
| E4 | 捕获 `own` / `borrow` 变量 | 错误 |
| E5 | 闭包体内写捕获名（`=` / `++` / 复合赋值）或取捕获名地址 `&n` | 错误 |
| E6 | 闭包变量赋给普通函数指针、或传给非 `(fn, env)` 参数对 | 错误 |
| E7 | 同作用域或更内层的局部拷贝 `int (*d)(int) = c;`（含后续赋值、含把闭包变量作捕获项） | **错误**：闭包是绑定不是值，闭包变量只在其声明处可用（D21-13，已定稿）；hint 指向内联或 `struct` + `trait` |
| E8 | 闭包经 `void *` 传给不透明 C 函数（或另一个 CT 函数）后被保存 | **不检查**：编译器看不到接收方；必须在 §4.8 与 hint 中说明（D21-5） |
| E9 | `goto` 跨过闭包声明 | 已知静默失效（与 `own` / `borrow` 相同），文档记录，不做检查 |

复用点（明确到函数）：

- `Memory.expr_returns(e, name)`：判断「真移交」而不是「读字段」，E1 直接复用。
- `Stmt.var_scope(sym, vi)`：寿命比较，E2 直接复用（作用域边界是 `sym->scope[]`，不是 `Var.st`）。
- `Memory.leak_decl` / `leak_assign` / `leak_return` 的**调用位置**（`Stmt.h.ct` 的声明、赋值、return 三处）
  作为挂载点；不改变它们对 `own` 的行为。
- `check_borrow_store` 只处理 borrow；闭包另写 `check_closure_store`，共用 `var_scope` 与
  「全局 / static / 更浅作用域」的判定（S1 抽公共函数 `outlives()`）。

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
a closure cannot capture another closure
a captured variable cannot be reassigned inside a closure
the address of a captured variable cannot be taken inside a closure
a closure cannot be used where a plain function pointer is expected
a closure argument must fill a '(fn, env)' parameter pair
this closure takes <n> parameters, but the expected type takes <m>
this closure's parameter <i> is '<type>', but the expected type is '<type>'
this closure is a binding, not a value (inline it or use a struct + trait)
a local cannot shadow the captured '<name>'
identifier '__ct_' is reserved for the compiler
```

hint 必须给出**可抄的三行**档① 写法（`struct` / `use Callable` / `impl Callable for …`），
不能只写「不支持」。

#### 4.7 与 borrow 的共用检查（修正原「假安全承诺」）

- borrow 阶段一 / 二已实现，Phase 21 **不重做**。
- S1 把 `check_borrow_store` 中的「目标是否更长寿命」抽成
  `static int outlives(struct Symbols *sym, int target, int source)`（全局 / `static` / `var_scope` 比较），
  borrow 与闭包两侧都调用它。
- **原稿的这句话不成立，现删除**：「接收方函数体按同一套闭包规则编译，因此在接收方把 env 存进
  全局 / 字段会被同一条检查拦住」。
  实际情况：闭包传给一个 CT 函数时，接收方只看到 `void *env` 这个**普通参数**；它可以把 `env`
  存进全局、字段或容器，编译器不会报——那条赋值表达式里没有闭包变量，`Var.is_closure` 不参与。
  因此这是**已知未防护面**：包括 std 规划中的 `each(v, fn, env)`，接收方完全可以保存 `env`。
  只能靠 API 约定与文档约束，不能靠编译器（§4.8 第 1 条、风险 H1）。
- 这不扩展 `borrow` 的指针语义（`borrow` 仍只接受 struct 指针），也不引入第二个注解关键字。

#### 4.8 必须对用户诚实标注的限制

1. **E8（文档级，不检查）**：逃逸判定拦得住 `g = c` / `s->f = c` / `return c`，**拦不住**两类
   「把 env 交出去」：
   (a) 把 `env` 以 `void *` 传给不透明 C 函数后由对方保存；
   (b) 传给另一个 CT 函数（**包括 std 的 `each`**）后由对方保存到全局 / 字段 / 容器。
   ct-ast 不做跨过程可达性分析，接收方看到的是普通 `void *`。
2. **E9（文档级，不检查）**：`goto` 跨过闭包声明静默失效（同 `own` / `borrow`）。
3. 捕获按值；对捕获名的写入、取捕获名地址一律报错（E5），不静默。
4. 闭包**类型**不能出现在 `.h.ct`、不能作返回值、不能作字段或元素；trampoline 的地址可以作实参
   传给别的单元（§4.4）。
5. 环境在栈上，**闭包值本身不能被容器持有**；容器需要持有时走档①。

#### 4.9 类型宿主隔离（防 std 的歧义坑）

`map trait T for type <ctype>` 的候选集按类型全局聚合，std 已踩过 `ambiguous type-host map`
（`Emitter.h.ct` 里仍有该诊断）。闭包**不得**进入这条派发通路：

- 闭包调用、传参、逃逸检查一律以 `Var.is_closure` 为唯一依据，不查 trait / 类型宿主；
- 不提供 `.call()` 方法语法：闭包只能 `c(args)` 直接调用；
- 禁止对函数指针类型使用 `map trait … for type`；官方 `Callable` 只能是真实 struct 类型；
- `Callable` 只作为 trait 名存在，不叠加同名类型宿主。

否则 `char *` 宿主映射会与闭包调用点共享候选集，每个闭包调用都可能变成歧义报告。

#### 4.10 勘误清单（2026-11-08，对照 HEAD `0263cca`）

| # | 原文 | 现状与依据 | 处理 |
| --- | --- | --- | --- |
| E-1 | 用 `Var.st` 指代作用域 / 说闭包值「没有 `st` 可挂」 | `Var.st` 是 struct 下标（`struct T *` 时指向结构体表，否则 -1）；作用域深度来自 `sym->scope[]` / `nscope`，由 `Stmt.var_scope(sym, vi)` 推导 | §0 第 2 行、§3.1 第 2 行、§3.2 第 1 条已改写 |
| E-2 | 「既有 71 个 golden」 | `check-goldens.sh` 的 baseline 是 **25 组**逐字节比对（`test/cases` 共 98 个文件，其余记 PENDING）；`test/ast` 是 **68 个编号探针**（69 个目录 = 68 + `errors`，缺 67） | §2、§5、§12 已改为「25 组 + 68 探针」 |
| E-3 | 把 `qsort` 列为闭包的即时收益 | `qsort` 的比较函数签名 `int (*)(const void *, const void *)` **没有 env 槽**，闭包与档① 的 `(fn, env)` 都塞不进去 | §6 删除 `qsort`，改为准确表述 |
| E-4 | 「闭包不能跨单元传递」 | `static` 只挡「按符号名引用」，不挡「把地址当实参传出去」；真正不能跨单元的是闭包类型出现在 `.h.ct` / 返回值 / 字段 / 元素 | §4.4、§4.8 第 4 条已改写 |
| E-5 | §4.7「接收方会被同一条检查拦住」 | 假安全承诺：接收方看到的是普通 `void *env`，保存它不会触发闭包检查（含 std 的 `each`） | §4.7 已改写并标为未防护面 |
| E-6 | R1「函数指针局部初始化式可能不被接受」 | 已被 HEAD 证实支持（`Stmt.h.ct` 对含 `(*` 的类型置 `fnval_ok`） | §4.1 标为已证实；风险表删除 R1 |
| E-7 | 「12 道硬门禁」等旧计数 | 实际 **11 道**（`check-all.sh` 的 `run_gate` 调用数） | 沿用 §1 第 4 点的既有更正 |

#### 4.11 三个设计缺口（G1–G3）

原设计只覆盖了「闭包变量怎么生成、怎么判逃逸」，没有覆盖下面三处；它们都会静默生成错误代码，
必须在切片里显式解决。

**G1 · 闭包值两词 vs 局部拷贝丢 env**

- 触发：原 §4.5 的 E7 曾允许 `int (*d)(int) = c;`（现按 D21-13 改为错误）。若不做这条禁令，闭包在
  C 侧是 `(fn, env)` 两词，源级声明却只有一个函数指针类型——按现有声明/赋值路径，拷贝只会搬 `fn`。
- 后果：`d(5)` 调用时没有 env 可传（trampoline 读 `self` 直接段错误），或者编译器擅自复用 `c` 的 env，
  在 `c` 的作用域结束后变成悬垂指针。两者都不报错，属**静默内存错误**。
- 可选修法：
  - (a) 闭包变量在符号表 / AST 里就是两词（`closure_id` 指向闭包表），声明与拷贝由发射器生成两条 C 赋值
    （`d_fn = c_fn; d_env = c_env;`），并要求目标作用域不浅于源；`d` 因此仍是闭包变量，不能当普通 fnptr（E6）。
  - (b) 禁止拷贝，把 E7 改成硬错误。
  - (c) 只允许语法上的「直接初始化拷贝」(`T (*d)(…) = c;`)，禁止后续赋值；覆盖面窄，但规则好讲。
- **定稿（D21-13，2026-11-08）：选 (b)。** 闭包是**绑定**，不是可复制的值：闭包变量只在其声明处
  可用，出现在赋值右侧、别的声明初始化式、字段/元素等任何「把值搬走」的位置都报错。理由：
  (a) 要把「值」语义补全到声明、赋值、`&`、阴影与作用域比较，而收益只是「起个别名」；
  (c) 的「只许初始化拷贝」仍要两词赋值，却留下一条难以解释的边界。禁止拷贝后，E7 从「允许」翻成
  「错误」，G1 的悬垂面整体消失；代价是同作用域别名必须改写为就地内联或档①。
  hint 文案：`a closure is a binding, not a value; inline it or use a struct + trait`。

**G2 · 闭包字面量直接作实参时与宿主函数指针类型无比对**

- 触发：`each(v, (int x) => x + 1)`。字面量本身没有左侧声明，返回类型与完整 fn 类型无处来；
  现有实参检查（Phase 19 `argtype_check`）只比较「已声明变量」的粗类型，闭包字面量是新的实参形态。
- 后果：参数个数 / 类型与宿主的 `(fn, env)` 对不符时不会在 `ct check` 报错，要到 `cc` 编译生成 C
  才暴露（还可能是隐式转换后静默运行）。
- 可选修法：
  - (a) 用宿主 `(fn, env)` 对里 fn 的完整类型作为期望类型：逐参数比对，返回类型取 fn 的返回类型。
  - (b) 要求字面量自带完整返回类型（`int (int x) => …`），语法噪音大。
  - (c) 本相禁止字面量直接作实参，必须先赋给已声明的闭包变量；最省，但 ergonomics 砍掉。
- **定稿（D21-14，2026-11-08）：选 (a)。** 闭包字面量的参数表必须与宿主函数指针类型比对：
  **arity 相同 + 逐参类型相容**；块体闭包（`=> { … }`）先合成返回类型（见 D21-17），再与宿主的返回类型
  比对。不匹配在**源码位置**报错（不用 `__ct_cl_*` 的名字），而不是推给 `cc`。
  理由：错误尽量停在 `.ct` 行列上；宿主 `(fn, env)` 对本来就在 `argtype_check` 拿得到形参类型，
  新增的只是「实参是字面量时就地构造期望类型」。落 S5（S3 只走左侧声明路径）。

**G3 · 发射器缺少「按函数预发文件作用域产物」的机制**

- 触发：env struct 与 trampoline 必须发在**文件作用域**且先于使用它的函数。`emit_unit_body` 是单遍流式：
  PP → struct 前向 → trait vtbl → 类型声明 → 全部原型 → 全局 → impl → maps → 函数体；
  `hoist_*` 只处理语句内的 `__ct_tmpN`（`MAX_HOISTS 4`），没有「按函数回填文件作用域产物」的缓冲。
- 后果：如果在发射函数体的途中才发现闭包，trampoline 只能发进函数体内部——C 不允许嵌套函数定义，
  生成物直接不可编译；要避免就得重排整个单元，改动远超一相。
- 可选修法：
  - (a) 发每个函数体**之前**先只读遍历该函数 AST，收集闭包字面量，就地把 env struct + trampoline
    发在函数定义之前（单遍流仍成立，只是多一次本函数预扫）。
  - (b) 单元级预扫：在「全部原型之后」统一发所有闭包产物；遍历一次，但要在发射流程里新开一个插点。
  - (c) 把函数体先渲染到缓冲区再回填：最灵活，也最重，破坏流式结构。
- **定稿（D21-15，2026-11-08）：选 (a)。** 解析期在闭包表里记录每个闭包的 **owner 函数**；发射器
  在写每个函数体之前，按 owner 预扫并就地发 env struct 与 `static` trampoline。这样**不碰单遍发射主干**
  （不加整单元缓冲、不重排 `emit_unit_body`），只多一次只读本函数遍历；闭包表容量 `MAX_CLOSURES 64`
  纳入风险 M3。硬性回归判据：**零闭包单元的生成物逐字节不变**（`test/cases` 25 组 baseline 是现成的证明）。

---

### 5. 切片计划（S0–S7，替换原 21.0–21.5）

每片都必须能**独立验证、独立回滚**；S3 是 ABI 冻结点，冻结之后 `(fn, env)` 顺序、命名规则、
调用点展开规则不再改。

| 切片 | 内容 | 依赖 | 触碰层 | 独立验证 | 回滚边界 |
| --- | --- | --- | --- | --- | --- |
| **S0** | 文档约定：ABI / 命名 / 诊断文案 / 已知未防护面 | 无 | `docs/**` | `python3 test/docs/check-docs.py` 绿；与 §4 一致 | 只回滚文档 |
| **S1** | 抽 `outlives()`，borrow 行为不变 | 无（与 S0 并行） | `Stmt.h.ct` | borrow 正负例全绿；抽取前后生成 C **逐字节一致** | 函数级回滚，无生成物变化 |
| **S2** | 前端：`=>` token、闭包字面量 AST、闭包变量两词表示、`Var.is_closure/closure_id`、闭包表、**owner 函数记录**；只接受函数指针声明（D21-1，不接受 `auto`） | S1 | `Lexer.h.ct`、`Parser.h.ct`、`Expr.h.ct`、`Stmt.h.ct`、`Symbols.h.ct` | 正例通过 `ct check`；`auto x = (int x) => …;` 报错；类型不符的负例给出 §4.6 文案；既有 25 组 golden 与 68 探针不受影响 | 移除 lexer/parser 分支与 `Var` 字段 |
| **S3** | **最小端到端 + ABI 冻结**：单表达式闭包、env/trampoline、按 owner 预发（G3）、调用点改写；冻结 `(fn, env)` 顺序与命名 | S2 | `Emitter.h.ct`、`Diag` | 探针 70 的生成 C 过 `cc -std=c99`、运行结果正确、`grep -c malloc` = 0；**零闭包单元生成物逐字节不变**；冻结后任何 ABI 改动必须另开版本 | 移除 emitter 分支；S2 保持 |
| **S4** | 逃逸检查 E1–E7（含 E7 绑定规则）、捕获规则的 4 个新检查（§4.2）、`note:` hint；E8/E9 写入文档 | S3 | `Stmt.h.ct`、`Memory.h.ct`、`Diag` | 探针 72–75、84 的负例文案被 `check-ast.sh` 钉住；`int (*d)(int) = c;`、`c = d;`、字段/元素搬运、写捕获名、`&n`、捕获 `own`/`borrow`/闭包都在**源码位置**报错；`*p = …` 不误报 | 移除 `check_closure_store` 与 4 个捕获检查 |
| **S5** | 多行体、嵌套闭包、参数对实参（G2）、两单元 | S4 | `Parser.h.ct`、`Expr.h.ct`、`Emitter.h.ct` | 探针 71、76、77、79；`ct build` 两单元各自 `static` 不冲突 | 逐个语法特性独立回滚 |
| **S6** | 官方 `Callable`（按签名一族）+ 互通 | S3（可与 S4/S5 并行） | `ct-pkg/std`（需授权）、本仓 `docs/**` + `examples/**` | 探针 78：档① 与档② 交给同一个函数；ct-pkg 测试绿 | 撤回 ct-pkg 包，本仓文档保留 |
| **S7** | 自举、文档、收口 | S4 / S5 / S6 | 全仓 | 11 道硬门禁 + CI 三 job + nightly + fixpoint；bump `v0.21.0` | 按版本回退 |

#### 依赖顺序

```text
S0 文档 ─────────────┐
S1 outlives ─→ S2 前端 ─→ S3 端到端（ABI 冻结）─→ S4 逃逸/G1 ─→ S5 多行/嵌套/G2/两单元 ─┐
                          └─→ S6 Callable（可与 S4/S5 并行，需 ct-pkg 授权）──────────┴─→ S7 收口
```

#### 与旧编号的映射

| 旧 | 新 |
| --- | --- |
| 21.0 容器回调约定 | 并入 S0 文档，不再单列（容器不在本相） |
| 21.1 共用寿命判定 | S1 |
| 21.2 档② 核心 | 拆成 S2（前端）+ S3（端到端与 ABI 冻结） |
| 21.3 多行 / 嵌套 / 参数对 | S5 |
| 21.4 官方 `Callable` | S6 |
| 21.5 自举与收口 | S7 |

#### 里程碑

| 里程碑 | 含义 | 判据 |
| --- | --- | --- |
| M21-A | 地基就绪 | S0 + S1 完成；borrow 生成物逐字节不变 |
| **M21-B** | **ABI 冻结（S3）** | 探针 70 绿；`(fn, env)` / 命名 / 调用点规则不再改 |
| M21-C | 能力完整 | S4 + S5 探针绿；多行体、嵌套、参数对、两单元、G1 |
| M21-D | 档① 官方化 | S6 互通探针 + ct-pkg 测试绿 |
| M21-E | 收口 | S7 全部门禁 + fixpoint + `v0.21.0` |

---

### 6. 对提案排期顺序的判断

提案建议：**容器规约 → borrow 阶段一 → 档② 闭包 → 官方 Callable**。逐条判断：

| 提案理由 | 判断 |
| --- | --- |
| 容器先落地，因为闭包最大用途是 `map/filter` | **不成立**。无泛型时 `VecInt.map` 与 `VecStr.map` 仍需各自的包装函数；闭包省掉的是每处 adapter struct，不是每元素类型的函数。且容器回调签名一旦先冻结，很可能把 `env` 顺序 / 是否打包定错。**应先定闭包 ABI，再定容器回调** |
| borrow 阶段一必须先做，且与档② 合并 | **已完成**。只剩抽公共寿命判定（S1），必须与闭包逃逸检查同批，不能分两次做 |
| 官方 Callable 最后 | **成立**，但要注意它只能是「按签名一族」，不是万能接口 |
| 闭包最大用途是容器 | **部分成立**：容器是收益之一；今天的即时收益是**就地循环与把上下文塞进回调**（省掉一个手写的 adapter struct）。注意 `qsort` 这类签名没有 env 槽的 C 回调**不能**接收闭包（档① 也不行），不要拿它当收益例子 |

**建议顺序**（若用户采纳）：

```text
S1 共用判定（小，先行）
S2 前端闭包表示
S3 端到端 + ABI 冻结   ← S0 文档与 S1 可并行
S4 逃逸 + G1  ┐
S5 多行/嵌套/G2 ┘ 串行；S6 Callable 可并行（需授权）
S7 自举与收口（串行，最后）
```

即：**把「容器规约」从阻塞项降为 S0 文档，把「borrow 阶段一」从一整段降为 S1 的一次抽取**。

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

严重度按「是否静默生成错误代码」判：会静默错的为 High；需要新机制或新容量、但会在门禁里显形为 Medium；
只影响可读性 / 文档的为 Low。

| # | 严重度 | 风险 | 处置 |
| --- | --- | --- | --- |
| H1 | **High** | **E8**：`env` 经 `void *` 逃逸——传给不透明 C 函数或**另一个 CT 函数（含 std 的 `each`）**后被保存，编译器不报 | D21-5 已把 E8 定为「文档级、不检查」；§4.7 / §4.8 如实标注；API 约定 + 文档；探针 76 记录现状，不伪装成已防护 |
| H2 | **High** | G1：闭包若被当成值搬走（`d = c`、初始化式、字段/元素），只搬 `fn` 丢 `env` → 静默段错误 / 悬垂 | 已定稿为**禁止搬运**（D21-13）：E7 与重赋值（D21-16）都在 S4 报源码位置错误；风险只剩「漏检某个赋值形态」，用 E1–E3 + E7 的负例矩阵钉住 |
| H3 | **High** | G3：发射器单遍流式，闭包产物只能在函数体内生成 → 生成非法 C | S3 实现「每函数体前预扫」；探针 70 强制生成物过 `cc -std=c99` |
| H4 | **High** | ABI 过早冻结：G2 已定稿但实现留在 S5，若冻结条款没排除「字面量实参」，后续改动要重生成全部闭包 golden | D21-4 已把 S3 定为冻结点；冻结条款明确排除「字面量实参」形态（D21-14），G2 落 S5 不回头改 ABI |
| M1 | Medium | 跨单元 `static`：不能按符号名引用；`pub` 转发方案未定 | §4.4 写清「地址可传、名字不可引」；S6 评估 `pub` 转发 |
| M2 | Medium | 闭包误入类型宿主 `map` 派发，复制 std 的 `ambiguous` 坑 | §4.9 隔离规则；探针 81 |
| M3 | Medium | 新表 / 计数超 `MAX_*`（`MAX_VARS 4096`、`MAX_HOISTS 4`、新增 `MAX_CLOSURES`） | env 结构不登记 `Structs`；每闭包 1 个 `Var` + 1 个闭包表项；S3 定容量并加断言 |
| M4 | Medium | `-Wall -Wextra` 下 trampoline 未使用告警（`ct check` 警告即退出 1） | 照 `Drop` 的先例加 `__attribute__((unused))`，或仅在确被引用时发射 |
| M5 | Medium | 断点停在合成帧，生成物失去可读性对应 | `#line` 重锚定 + `/* closure at … */` + 源名；探针 80 |
| M6 | Medium | 捕获规则的误报：把 `*p = …`（显式解引用写回）误判为写捕获名，或漏掉 `n++` / 复合赋值 | 判据绑在「基名 + 写操作」上，`N_DEREF` 里的基名不算写；探针 84 覆盖 `*p` 放行与 `n++` 报错 |
| L1 | Low | `=>` 保留字破坏面 | 实测 0（§8） |
| L2 | Low | **E9**：`goto` 跨过闭包声明静默失效 | 与 `own` / `borrow` 同现状；文档记录，不做检查（E9） |
| L3 | Low | golden 变动面被高估 | 实际只有 `test/cases` 25 组 baseline + `test/ast` 68 探针；版本 token 之外不应有 diff |

**回退**：`=>` 是 opt-in，不写不检查；回退按切片进行——S3 之前的切片不产生任何生成物变化，
S3 之后移除 lexer / parser / emitter 的闭包分支与 `Var.is_closure` 即可，其余能力（borrow、Phase 19 检查、
包管理）不动；无数据格式与 ABI 兼容负担。

---

### 10. 决策清单（D21-1–D21-17）

D21-13–D21-16（第一批）与 D21-1 / D21-2 / D21-4 / D21-5（第二批）已于 **2026-11-08 定稿**；
D21-8 并入 D21-3、D21-17 并入 D21-14，不再单列；其余 7 条（D21-3、D21-6、D21-7、D21-9、D21-10、
D21-11、D21-12）仍为 **待确认**。定稿的八条共享三条理由：**闭包是绑定不是值**；
**错误尽量在源码位置报**；**不碰单遍发射主干**。

| # | 问题 | 选项（互斥） | 代价 | 定稿 / 建议 |
| --- | --- | --- | --- | --- |
| D21-1 | 闭包语法 | **A** `ret (*name)(params) = (params) => expr`，不引入 `auto`；**B** 引入 `auto name = (params) => expr` | A：无新关键字，但表面类型是 fnptr，用户可能误用（E6 兜底）。B：要加类型推断，且 `auto` 在 C 里是存储类，语义冲突 | **已定稿（2026-11-08）：选 A。** 沿用函数指针声明，不引入 `auto`、不做类型推断；误用由 E6 拦 |
| D21-2 | 捕获方式 | **A** 按值、创建点求值、捕获名只读；**B** 按引用捕获 | A：无生命周期，语义简单；大 struct 有拷贝成本，写回需显式指针。B：需要生命周期/逃逸分析，等于档③ | **已定稿（2026-11-08）：选 A。** 写捕获名报错；写回用指针显式解引用；S4 另加 4 个捕获检查（§4.2） |
| D21-3 | 生成物命名 | **A** 单元级单调计数器 `__ct_cl_env_<N>` / `__ct_cl_tramp_<N>` / `__ct_cl_env_v_<N>`；**B** 按 owner 函数命名 `<func>__ct_cl_<k>` | A：名字不可读，但与 `__ct_ret%d` 同风格、天然去重、不依赖函数名。B：生成物可读性好，但要处理 namespace / 超长函数名 / 同名与转义 | **A**。D21-8（namespace 前缀）已并入本条：闭包符号是 `static` 且从不按名跨单元引用，前缀没有消费者 |
| D21-4 | ABI | **A** 两词 `(fn, env)`，env 第一；**B** 打包 `struct { fn; env; }` 单指针 | A：与既有 fnptr / impl 包装同形，档① 零改动；调用点要展开成两个 C 实参。B：单参数好看，但档① 包装是单个 fn，必须再造 thunk，破坏互通 | **已定稿（2026-11-08）：选 A。** 与档① `(void *self, …)` 同形；**S3 是 ABI 冻结点，之后不可改** |
| D21-5 | 逃逸检查范围 | **A** E1–E7 全量、一律硬错误；E8 为「传给不透明 C 函数拦不住但必须说明」的文档级诊断；E9 记录 `goto`；**B** 只做 E1–E3 | A：检查矩阵最大，但每条都有现成挂载点。B：与已定稿的绑定规则、D21-2 的只读捕获冲突（拷贝/重赋值/写捕获都会漏检） | **已定稿（2026-11-08）：选 A。** |
| D21-6 | 诊断契约 | **A** 固定英文文案 + 独立 `note:` 通道（`ct_sem_note`，不计 `nsem`）；**B** 把 hint 拼进 `ct_sem_error` 的同一条 message | A：新增一个通道，Diag 与门禁要认 `note`。B：hint 会占 `MAX_ERRORS 20`，且文案与 hint 混在一条里不便逐条断言 | **A** |
| D21-7 | `Callable` 形态 | **A** 按签名一族（`Callable0` / `Callable1i` …）；**B** 单个 `Callable` + `void *` 参数 | A：每个签名一个 trait，类型安全。B：把类型擦除带回来，调用点强转，等于放弃检查 | **A**。无泛型时不存在万能接口 |
| D21-8 | namespace 交互 | 原选项：**A** 不加前缀；**B** 加前缀 | A：`static` + 一单元一 `.c` 已保证不冲突。B：无收益 | **已并入 D21-3，无需单独决策。** D21-4 与 D21-15 定稿后，闭包符号不按名跨单元引用，前缀没有消费者 |
| D21-9 | golden 形态 | **A** 在 `test/ast` 新增 70–84 编号探针（负例进 `test/ast/errors/`）；**B** 只加 `test/cases` 逐字节 golden | A：要维护期望输出，但能覆盖负例与诊断文案。B：只覆盖正向生成物，负例无处断言 | **A**。与现有 `check-ast.sh` 结构一致 |
| D21-10 | 版本 | **A** Phase 21 ↔ `v0.21.x`，收口 `v0.21.0`；**B** 作为 patch 塞进 `v0.20.x` | A：与 roadmap 版本规则一致。B：闭包与包支持共用一个 minor，回滚边界模糊 | **A** |
| D21-11 | 排期 | **A** S0/S1 并行 → S2 → S3（冻结）→ S4 → S5 ∥ S6 → S7；**B** 先做 S6、再回头补 S3 | A：先钉 ABI。B：与 D21-4 已定稿的「S3 之后不可改」冲突——S6 会迫使 ABI 在冻结前再变一次 | **A** |
| D21-12 | 泛型口径 | **A** 不引入；STD-1 的「Phase 21+」改为「Phase 22+ / 1.0 之后」；**B** 本相顺带做最小泛型以支撑容器 | A：保持零成本模型。B：要同时改 L2、门禁、自举，远超一相 | **A** |
| D21-13 | **（G1）** 闭包变量拷贝 | **A** 禁止：闭包是绑定不是值，只在声明处可用，任何搬运都报错；**B** 两词表示 + 允许同/内层拷贝（fn 与 env 一起搬）+ 目标更浅报错；**C** 只允许声明时的直接初始化拷贝 | A：同作用域起别名要改写成内联或档①，实现最省且没有半套「值」语义。B：要定义声明/赋值/`&`/阴影/作用域比较，且仍需 E6 兜普通 fnptr。C：仍要两词赋值，边界难解释 | **已定稿（2026-11-08）：选 A。** 闭包是绑定不是值；E7 翻成错误；悬垂面整体消失 |
| D21-14 | **（G2）** 闭包字面量直接作实参 | **A** 用宿主 `(fn, env)` 对的 fn 型作期望类型，比对 arity 与逐参类型，块体先合成返回类型再比；**B** 要求字面量写全类型；**C** 本相禁止，必须先赋给变量 | A：要在实参位置就地构造期望类型（复用 `argtype_check` 的形参信息）。B：语法噪音大。C：砍 ergonomics | **已定稿（2026-11-08）：选 A。** 错误尽量停在 `.ct` 源码位置；落 S5，S3 只走左侧声明路径 |
| D21-15 | **（G3）** 闭包产物发射时机 | **A** 解析期记 owner 函数；每个函数体前按 owner 预扫，就地发 env/trampoline；**B** 单元级预扫，统一发在原型之后；**C** 缓冲函数体再回填 | A：每函数多一次只读遍历，单遍发射主干不动。B：一次遍历，但要新开插点。C：改动最大 | **已定稿（2026-11-08）：选 A。** 不碰单遍发射主干；零闭包单元生成物逐字节不变（S3 验收） |
| D21-16 | 闭包变量能否重新赋值（`c = d`，两者都是闭包） | **A** 禁止：声明即绑定，之后不允许重新赋值；**B** 允许，按两词赋值处理且目标作用域不得浅于源 | A：少一类悬垂面，与 D21-13 同一条规则。B：需要两词赋值 + 作用域比较，且 `c = 更内层闭包` 会让 `c` 的 env 先死 | **已定稿（2026-11-08）：选 A。** 闭包是绑定不是值；重赋值报源码位置错误 |
| D21-17 | 闭包字面量直接作实参时，返回类型如何反推 | 原选项：**A** 取宿主 fn 的返回类型；**B** 由字面量 `return` 表达式推断；**C** 要求显式注解 | A：依赖宿主签名，C 函数与 CT 函数都可得。B：引入局部类型推断，与已定稿的 D21-1 直接冲突。C：噪音 | **已并入 D21-14，无需单独决策。** D21-14 定 A：期望类型来自宿主 fn，返回类型随之确定；D21-1 又排除了推断，B 不再存在 |

---

### 11. golden 用例（`test/ast/**`，由 `check-ast.sh` 自动发现）

| 编号 | 用例 | 期望 |
| --- | --- | --- |
| 70 | `closure_basic` | env + tramp + 栈上实例；结果正确；生成 C 无 `malloc`；过 `cc -std=c99` |
| 71 | `closure_nested_block` | 嵌套闭包 / 多行体；env 名不冲突；逐层正确 |
| 72 | `closure_escape_return` | `return c;` 硬错误 + hint |
| 73 | `closure_escape_store` | 全局 / 外层局部 / `static` / 字段 / 元素 硬错误 |
| 74 | `closure_capture_own_borrow` | 捕获 `own` / `borrow`、捕获另一个闭包变量均硬错误 |
| 75 | `closure_param_pair` | 传给 `(fn, env)` 参数对通过；传给普通函数指针报错 |
| 76 | `closure_opaque_hole`（**E8**） | 经 `void *` 传给不透明函数或 CT 函数并保存 → **记录为已知未防护**（不伪装成通过） |
| 77 | `closure_goto`（**E9**） | 记录现状（静默失效），不崩 |
| 78 | `callable_interop` | 手写档① 的 `call` 与档② tramp 交给同一个函数；零改动 |
| 79 | `closure_two_units` | `ct build` 两单元各自 `static` 命名不冲突；地址作实参可跨单元调用 |
| 80 | `closure_debug_line` | 开启 `#line` 时，trampoline 行映射回闭包源行；生成物含 `/* closure at … */` |
| 81 | `closure_no_typehost` | 存在 `map trait … for type` 时，闭包调用仍直接解析，不产生歧义 |

另需三个专项探针（建议编入 82–84）：
`closure_copy_local`（同作用域 `int (*d)(int) = c;` → **硬错误**，hint 指向内联或档①）、
`closure_reassign`（`c = d;` → **硬错误**，报在源行列）、
`closure_capture_rules`（写捕获名 `n = 1` / `n++` / `n += 1` 与取地址 `&n` → 硬错误；
`*p = …` 显式解引用写回 → 放行）。

---

### 12. 出口判据

Phase 21 完成需同时满足：

1. 11 道硬门禁全绿；CI 三 job + nightly 全绿。
2. 探针 70–79（以及 82–84）全部按上表行为；负例文案被 `check-ast.sh` 钉住。
3. 既有 golden 口径：`test/cases` 25 组 baseline 逐字节不变（仅允许版本 token），
   `test/ast` 68 个编号探针的既有期望不变。
4. 生成物：闭包探针无 `malloc` / `free` / 引用计数 / vtable；只有 env struct + `static` trampoline。
5. G1 / G2 / G3 各自有探针与实现：闭包搬运（拷贝 / 重赋值）在源码位置报错、字面量实参的 arity 与
   逐参类型被比对（块体先合成返回类型）、闭包产物按 owner 发在函数之前且零闭包单元生成物逐字节不变。
6. D21-2 的 4 个捕获检查生效：写捕获名（含 `++` / 复合赋值）与 `&n` 报错，`*p = …` 放行，
   捕获 `own` / `borrow` / 闭包均在源码位置报错。
7. E8 / E9 已写入文档（含 hint），且探针 76 / 77 记录现状。
8. fixpoint 通过；编译器源码的 `=>` 使用在 M21-E2 之后。
9. 文档：language-spec 增加闭包一节；tutorial 有「档② 还是档①」的判据表；glossary 加 `closure` /
   `trampoline` / `env`；roadmap 状态改为完成。

---

## English

### Summary

**Status: planned** (opened 2026-11-06; revised 2026-11-08 against HEAD `v0.20.2` = `0263cca`, adding
gaps G1–G3, slices S0–S7 and option-level decisions; **D21-13–D21-16 (first batch) and D21-1 / D21-2 /
D21-4 / D21-5 (second batch) were finalised on 2026-11-08**; D21-8 is folded into D21-3 and D21-17 into
D21-14; the other 7 decisions still await confirmation).
**Phase 21 ↔ `v0.21.x`, closing bump to `v0.21.0`.** The repo is at `v0.20.2`; Phases 17/18/19/20 are done,
Phase 20 (package support, [phase20.md](phase20.md)) is closed and has no semantic dependency here. The gate
count is **11**.

This phase implements **tier ② non-escaping stack closures** (`=>`), lowered **as an expansion of tier ①**
(`struct` + `trait`), sharing one `(fn, env)` ABI. Tier ③ (general escaping closures) is out of scope.

**First batch, decided 2026-11-08 (all option A):**

1. **A closure is a binding, not a value.** It is usable only at its declaration; copying it into another
   local (same or inner scope) and any reassignment are source-position errors, with a hint pointing at
   inlining or `struct` + `trait`.
2. **A closure literal's parameter list is compared with the host function-pointer type** (arity plus
   parameter-by-parameter types); block-bodied literals synthesise their return type first, then compare.
   Mismatches are reported at the source position.
3. **The emitter emits the env struct and `static` trampoline per owner function, before writing each
   body.** The parser records the owning function; a unit with no closures must generate byte-identical C.
4. **Declaration is binding: a closure variable cannot be reassigned.**

Shared rationale: closures are bindings, not values; errors should stop at `.ct` source positions; the
single-pass emitter's main path must not be disturbed.

**Second batch, decided 2026-11-08 (all option A):**

1. **D21-1 — syntax keeps the function-pointer declaration** (`int (*f)(int x) = (int x) => …;`); no
   `auto`, no type inference. Misuse is caught by E6. `auto` is a C storage class, so adopting it would
   drag in inference, which this phase forbids.
2. **D21-2 — capture is by value, evaluated at the creation point; captured names are read-only.** Writing
   a captured name is an error; a closure that must write back captures a pointer and dereferences it
   explicitly (`*p = …`).
3. **D21-4 — the ABI is frozen as two words `(fn, env)` with `env` first**, the same shape as the tier-①
   `impl` wrapper `(void *self, …)`. **This is the freeze point: nothing changes after S3** (order, naming
   and the call-site expansion rule are frozen together).
4. **D21-5 — escape checking is the full E1–E7 set**, plus E8 kept as the documented diagnosis ("cannot be
   caught when handed to an opaque C function, but must be stated"). E9 records the silent `goto` failure.

### Errata against the earlier draft (verified at HEAD)

| # | Earlier text | Reality at HEAD | Fix |
| --- | --- | --- | --- |
| E-1 | `Var.st` used as a scope index | `Var.st` is the **struct index** (set when the type is `struct T *`, else -1). Scope depth lives in `sym->scope[]` / `nscope`, derived by `Stmt.var_scope(sym, vi)` | §0, §3.1, §3.2 rewritten |
| E-2 | "71 existing goldens" | `check-goldens.sh` compares a **25-case baseline** byte for byte (`test/cases` holds 98 files; the rest are PENDING). `test/ast` holds **68 numbered probes** (69 directories = 68 + `errors`; 67 is missing) | §2, §5, §12 now say "25 + 68" |
| E-3 | `qsort` cited as an immediate benefit | `qsort`'s comparator is `int (*)(const void *, const void *)` — **no env slot**, so neither closures nor tier-① `(fn, env)` fits | `qsort` removed from §6 |
| E-4 | "Closures cannot cross unit boundaries" | `static` blocks **name references**, not passing the address as an argument; what cannot cross is the closure **type** in `.h.ct`, a return value, a field or an element | §4.4, §4.8 rewritten |
| E-5 | §4.7 claimed the callee would be caught by the same check | False safety: the callee sees a plain `void *env` and may store it; no closure check fires (this includes a future std `each`) | §4.7 rewritten and marked unprotected |
| E-6 | R1: local function-pointer initializers may be unsupported | Supported: `Stmt.h.ct` sets `fnval_ok` for types containing `(*` | §4.1 marked confirmed; R1 removed |
| E-7 | "12 hard gates" etc. | **11** (`run_gate` calls in `check-all.sh`) | kept from §1.4 |

Other corrections kept: the `own` machinery is variable-centric, so closures need a new checker;
`borrow` stages one/two already shipped (only `outlives()` extraction remains); dialects cannot be an official
tier-① path; CT has no error codes, so the contract is stable text plus a `note:` line.

### Design gaps G1–G3

**G1 — a closure is two words, but a local copy would keep only `fn`.**
The earlier E7 allowed `int (*d)(int) = c;`. The closure variable lowers to `(fn, env)`, while the
source-level type is a single function pointer, so a naive copy drops `env`: `d(5)` either has no env
(trampoline dereferences garbage) or reuses `c`'s env and dangles after `c`'s scope ends. Silent memory error.
Options: (a) forbid copying (E7 becomes an error); (b) represent the closure as two words and emit two C
assignments, rejecting shallower targets; (c) allow only direct-initialisation copies.
**Decided (D21-13, 2026-11-08): (a).** A closure is a binding, not a value: it is usable only at its
declaration, and moving it anywhere is an error. The dangling surface disappears; the cost is that a local
alias must be rewritten as an inline closure or tier ①. Hint:
`a closure is a binding, not a value; inline it or use a struct + trait`.

**G2 — a closure literal passed directly as an argument is never checked against the host's function type.**
`each(v, (int x) => x + 1)` has no left-hand declaration, so the literal has no return type and no full fn
type; Phase 19 `argtype_check` only compares declared variables. A mismatch then surfaces at `cc`, not at
`ct check`. Options: (a) take the expected type from the host `(fn, env)` pair and compare arity plus each
parameter, with block bodies synthesising the return type first; (b) require a fully typed literal; (c) forbid
literals as direct arguments. **Decided (D21-14, 2026-11-08): (a).** Mismatches are reported at the source
position; the host pair's formal types are already available through `argtype_check`. Lands in S5; S3 keeps
only the declaration path.

**G3 — the emitter has no way to emit file-scope artefacts before a function.**
`emit_unit_body` is a single streaming pass (PP → struct forwards → trait vtables → type declarations →
all prototypes → globals → impls → maps → bodies); `hoist_*` only handles statement-local `__ct_tmpN`
(`MAX_HOISTS 4`). If a closure is discovered while emitting a body, the trampoline cannot be emitted
(C has no nested functions), so the output would not compile. Options: (a) record the owner function at
parse time and pre-scan that function right before writing its body, emitting env struct + trampoline
immediately before the definition; (b) one unit-level pre-scan after the prototypes; (c) buffer bodies and
back-patch. **Decided (D21-15, 2026-11-08): (a).** The single-pass main path is untouched; a unit with no
closures must generate byte-identical C (verified in S3).

### Pinned design baseline

- Syntax (**D21-1, finalised 2026-11-08**): `int (*add)(int x) = (int x) => x + n;` — the
  function-pointer declaration only, no `auto` and no inference (E6 catches misuse); multi-line body
  `=> { … }` in S5. Local function-pointer initialisers are already accepted at HEAD, so no front-end
  fix-up is needed first.
- Capture (**D21-2, finalised 2026-11-08**): **by value, evaluated at the creation point**, captured names
  are read-only; writing a captured name or taking `&n` is an error, a write-back captures a pointer and
  dereferences it explicitly; `own`/`borrow` captures and capturing another closure are errors.
- Capture checks that are new (S4): `check_closure_capture_write` (no `=` / `++` / compound assignment on a
  captured name; `*p = …` is allowed), `check_closure_capture_addr` (no `&n`), `check_closure_capture_own`
  (runs before AutoDrop/borrow registration), `check_closure_capture_closure` (capturing a closure variable
  is another AST path than E7). The existing `own`/`borrow`/`Drop`/`check_borrow_store` analyses are
  variable-centric and judge ownership transfer, not read-only capture, so they do not cover these.
- Generated names: `__ct_cl_env_<N>`, `__ct_cl_tramp_<N>`, `__ct_cl_env_v_<N>`; a per-unit monotonic
  counter (like `__ct_ret%d`); file-scope `static`, never in headers, no namespace prefix.
- ABI (**D21-4, finalised 2026-11-08**): two words, `env` first, the same shape as tier-①'s
  `(void *self, …)`; a closure argument fills an adjacent `(fn, env)` parameter pair; arity counts a
  closure as two C arguments. **S3 is the freeze point; after it the order, the naming and the call-site
  expansion do not change.**
- Cross-unit: the **address** of a trampoline may be passed to another unit as an argument (legal C); what
  cannot cross is the closure type (header, return value, field, element) or a by-name reference to the
  `static` symbol.
- Escapes (**D21-5, finalised 2026-11-08**): E1–E7 are all hard errors with a hint; E8 is the documented,
  unchecked diagnosis for handing `env` to an opaque C function (or another CT function) that stores it;
  E9 records that `goto` across a closure declaration fails silently.
- Honest limits: env handed out as `void *` to an opaque C function **or to another CT function (including a
  future std `each`)** can be stored there; the compiler cannot see it.

### Slices S0–S7

S3 freezes the ABI: after it, the `(fn, env)` order, the naming rules and the call-site expansion do not change.

| Slice | Content | Depends on | Layers | Independent verification |
| --- | --- | --- | --- | --- |
| S0 | Docs: ABI, naming, diagnostics, known holes | — | `docs/**` | `check-docs.py` green |
| S1 | Extract `outlives()` shared with `borrow` | — (parallel with S0) | `Stmt.h.ct` | borrow probes green; generated C byte-identical before/after |
| S2 | Front end: `=>` token, literal AST, two-word closure variable, `Var.is_closure/closure_id`, closure table, **owner function recorded**; function-pointer declarations only (**D21-1**, no `auto`) | S1 | Lexer, Parser, Expr, Stmt, Symbols | positive probe type-checks; `auto x = (int x) => …;` errors; typed negatives produce the planned text; the 25 goldens + 68 probes unchanged |
| S3 | **End-to-end + ABI freeze**: single-expression closures, env/trampoline, per-owner pre-scan (G3), call-site rewrite; freezes the `(fn, env)` order and naming (**D21-4**) | S2 | Emitter, Diag | probe 70 compiles with `cc -std=c99`, runs, `malloc` count 0; **zero-closure units byte-identical**; any ABI change after the freeze needs a new version |
| S4 | Escapes E1–E7 (incl. the E7 binding rule) + the **four new capture checks** (§4.2) + `note:` hints; E8/E9 documented | S3 | Stmt, Memory, Diag | probes 72–75 and 84 pinned; `int (*d)(int) = c;`, `c = d;`, field/element moves, writing a captured name, `&n`, and capturing `own`/`borrow`/a closure all error at the **source position**; `*p = …` does not false-positive |
| S5 | Block bodies, nesting, parameter-pair arguments (G2), two units | S4 | Parser, Expr, Emitter | probes 71, 76, 77, 79; two-unit `static` names do not clash |
| S6 | Official `Callable` family + interop | S3 (parallel with S4/S5) | `ct-pkg/std` (authorisation), docs, examples | probe 78: tier ① and tier ② handed to the same function |
| S7 | Bootstrap, docs, `v0.21.0` close | S4/S5/S6 | whole tree | 11 gates, CI, nightly, fixpoint |

Ordering: S0 ∥ S1 → S2 → S3 (freeze) → S4 → S5 ∥ S6 → S7. The old 21.0 becomes part of S0 (containers are
not in this phase); 21.1 → S1; 21.2 → S2 + S3; 21.3 → S5; 21.4 → S6; 21.5 → S7.

Milestones: M21-A (S0+S1), **M21-B = S3, ABI freeze**, M21-C (S4+S5), M21-D (S6), M21-E (S7).

### Ordering judgement

"Containers first" does not hold without generics — each element type still needs its own wrapper, and
freezing container callbacks before the closure ABI risks freezing the wrong signature. Borrow stage one is
already done; what remains is a single extraction (S1). `Callable` must come last and can only be a family of
per-signature traits. Closures do help local loops and callback context today, but a `qsort`-style C callback
with no env slot **cannot** take a closure.

### Risks (4 High, 6 Medium, 3 Low)

| # | Severity | Risk | Handling |
| --- | --- | --- | --- |
| H1 | **High** | **E8**: `env` escapes as `void *` through an opaque C function or another CT function (incl. `each`); no diagnostic | D21-5 keeps E8 as documented/unchecked (§4.7/§4.8); probe 76 records the hole instead of pretending otherwise |
| H2 | **High** | G1: a closure moved as a value (`d = c`, initialiser, field/element) would keep only `fn`, dropping `env` → silent dangling | Finalised as **forbid moving** (D21-13): E7 and reassignment (D21-16) error at the source position in S4; the residual risk is a missed assignment form, covered by the negative matrix |
| H3 | **High** | G3: single-pass emitter cannot place closure artefacts before a function → invalid C | S3: per-owner pre-scan; probe 70 must compile with `cc -std=c99` |
| H4 | **High** | Freezing the ABI before G2 is validated forces a later regeneration of every closure golden | **D21-4 pins S3 as the freeze point**; the freeze clause explicitly excludes the literal-argument form (D21-14), which lands in S5 without reopening the ABI |
| M1 | Medium | Cross-unit `static`: no by-name references; `pub` forwarding undecided | §4.4 wording; S6 evaluates `pub` forwarding |
| M2 | Medium | Closures leaking into type-host `map` dispatch (`ambiguous type-host map`) | §4.9 isolation; probe 81 |
| M3 | Medium | New tables exceed `MAX_*` (`MAX_VARS`, `MAX_HOISTS`, new `MAX_CLOSURES`) | env structs not registered in `Structs`; one `Var` + one closure entry per closure; capacity asserted in S3 |
| M4 | Medium | `-Wall -Wextra` unused-trampoline warning (`ct check` exits 1 on warnings) | `__attribute__((unused))` as with `Drop` |
| M5 | Medium | Debugger stops in a synthetic frame | `#line` re-anchoring + `/* closure at … */`; probe 80 |
| M6 | Medium | Capture-rule false positives: `*p = …` (explicit dereference write-back) misread as writing a captured name, or `n++` / compound assignment missed | Judge on base name plus write op; a base name under `N_DEREF` is not a write; probe 84 covers `*p` allowed and `n++` rejected |
| L1 | Low | `=>` reserved-word breakage | 0 occurrences (§8) |
| L2 | Low | **E9**: `goto` across a closure declaration fails silently | Same as `own`/`borrow`; documented (E9), no check |
| L3 | Low | Golden churn overestimated | Only the 25-case baseline + 68 probes; no diff beyond the version token |

### Decisions D21-1–D21-17 (D21-1/2/4/5 and D21-13–16 decided; D21-8/17 folded; the rest pending)

D21-1/2/4/5 (second batch) and D21-13–D21-16 (first batch) were **finalised on 2026-11-08**; D21-8 is
folded into D21-3 and D21-17 into D21-14; the remaining 7 (D21-3, D21-6, D21-7, D21-9, D21-10, D21-11,
D21-12) are still **pending**. The eight decided ones share three reasons: **a closure is a binding, not a
value**; **errors should stop at the source position**; **the single-pass emitter's main path is not
touched**.

| # | Question | Mutually exclusive options | Recommendation |
| --- | --- | --- | --- |
| D21-1 | Closure syntax | **A** `ret (*name)(params) = (params) => expr`, no `auto`; **B** `auto name = (params) => expr` | **Decided 2026-11-08: A.** Keep the function-pointer declaration, no `auto`, no inference; E6 catches misuse |
| D21-2 | Capture mode | **A** by value at the creation point, read-only; **B** by reference | **Decided 2026-11-08: A.** Writing a captured name errors; write-back captures a pointer and dereferences it; S4 adds the four capture checks (§4.2) |
| D21-3 | Generated names | **A** per-unit monotonic counter `__ct_cl_env_<N>` / `__ct_cl_tramp_<N>` / `__ct_cl_env_v_<N>`; **B** per-owner `<func>__ct_cl_<k>` | **A.** D21-8 (namespace prefix) is folded in: closure symbols are `static` and never referenced by name across units, so a prefix has no consumer |
| D21-4 | ABI | **A** two words `(fn, env)`, env first; **B** packed `struct { fn; env; }` | **Decided 2026-11-08: A.** Same shape as tier-①'s `(void *self, …)`; **S3 is the ABI freeze point, not changeable afterwards** |
| D21-5 | Escape checks | **A** E1–E7 all hard errors; E8 documented as "cannot be caught when handed to an opaque C function, but must be stated"; E9 records `goto`; **B** E1–E3 only | **Decided 2026-11-08: A.** B contradicts the decided binding rule and D21-2's read-only capture |
| D21-6 | Diagnostic contract | **A** fixed text + separate `note:` channel; **B** hint inside the error message | **A** |
| D21-7 | `Callable` shape | **A** per-signature family; **B** one `Callable` + `void *` | **A** |
| D21-8 | Namespace interaction | Old options: **A** no prefix; **B** prefix | **Folded into D21-3, no separate decision.** After D21-4/D21-15 closure symbols are not referenced by name across units, so a prefix has no consumer |
| D21-9 | Golden form | **A** new numbered `test/ast` probes 70–84 (negatives under `test/ast/errors/`); **B** `test/cases` only | **A** |
| D21-10 | Version | **A** `v0.21.x`; **B** patch inside `v0.20.x` | **A** |
| D21-11 | Ordering | **A** S0/S1 → S2 → S3 → S4 → S5 ∥ S6 → S7; **B** S6 first, back-fill S3 afterwards | **A.** B conflicts with D21-4's "nothing changes after S3": S6 would force one more ABI change before the freeze |
| D21-12 | Generics | **A** none; reword STD-1 to "Phase 22+ / after 1.0"; **B** minimal generics now | **A** |
| D21-13 | (G1) copying a closure variable | **A** forbid: a closure is a binding, usable only at its declaration; **B** two-word copy with a scope check; **C** initialisation-only copy | **Decided 2026-11-08: A** |
| D21-14 | (G2) literal as a direct argument | **A** expected type from the host `(fn, env)` pair: arity + per-parameter, block-body return synthesised first; **B** fully typed literal; **C** forbid in this phase | **Decided 2026-11-08: A**, in S5 |
| D21-15 | (G3) emission point | **A** owner recorded at parse time, per-owner pre-scan before each body; **B** unit-level pre-scan; **C** buffered bodies | **Decided 2026-11-08: A** |
| D21-16 | Reassigning a closure variable (`c = d`) | **A** forbid: declaration is binding; **B** allow with a two-word assignment and a scope check | **Decided 2026-11-08: A** |
| D21-17 | Return type of a literal argument | Old options: **A** from the host fn; **B** inferred from `return`; **C** explicit annotation | **Folded into D21-14, no separate decision.** D21-14 chose A (expected type from the host fn, so the return type follows), and D21-1 rules out inference, so B no longer exists |

### Probes and exit criteria

Probes 70–81 keep their meanings (70 basic, 71 nested/block, 72 return escape, 73 store escape, 74
own/borrow/closure capture — D21-2, 75 parameter pair, 76 opaque hole — **E8**, documented, 77 `goto` —
**E9**, 78 interop, 79 two units, 80 debug lines, 81 type-host isolation), plus 82–84: 82
`closure_copy_local` (`int (*d)(int) = c;` → hard error), 83 `closure_reassign` (`c = d;` → hard error at
the source position), 84 `closure_capture_rules` (writing `n` via `=`, `++` or a compound assignment and
`&n` are hard errors; `*p = …` is allowed).

Exit: 11 gates + CI + nightly green; probes 70–79 and 82–84 behave as specified; the 25-case baseline and
68 probes unchanged except the version token; no `malloc`/`free`/refcount/vtable in closure output; G1, G2
and G3 each implemented and covered (moving a closure errors at the source position, literal arguments are
compared for arity and per-parameter type with block-body return synthesised, closure artefacts are emitted
before the owner function and zero-closure units stay byte-identical); D21-2's four capture checks are in
force (writing a captured name incl. `++`/compound, and `&n`, error; `*p = …` allowed; capturing
`own`/`borrow`/a closure all error at the source position); E8/E9 documented (with hints) and probes 76/77
record the status quo; fixpoint passes; `=>` enters `selfhost/ct-ast/**` only after M21-E2;
language-spec, tutorial, glossary and roadmap updated.
