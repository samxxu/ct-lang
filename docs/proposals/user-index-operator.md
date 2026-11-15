# 提案：用户类型下标运算符（REQ-INDEX-1）

> **状态：提案 / 未立项 / 未过分析，不作数**（2026-11-15）。
> **基线**：本仓 `v0.53.1` 之前的工作树（`v0.53.0` 之后，含两处 P0 修复）；立项时 S0 记录 `baseline: <sha>` 并复跑 §1。
> **关联**：[requirements-pool.md](../planning/requirements-pool.md) 的 `REQ-INDEX-1`（本条登记）、`REQ-L1`（PH-52 已交付方案 A）、
> `REQ-JSACCESS-1`（参数类型匹配，本提案的第一步）。
> **前作**：[custom-index-protocol.md](custom-index-protocol.md)（REQ-L1 的设计草案）、[design/phase52.md](../design/phase52.md)（方案 A 施工卡与 D52-2 / D52-5 / D52-6）。
> **规模估算**：编译器 150–300 行；夹具/断言 80–160 行；文档 30–60 行。
> **纪律**：不 bump、不打 tag、不 push；本文件只登记与设计，不动实现。

---

## 0 一句话

把 PH-52 的「方法名 + 参数个数」静态糖，补成一套**完整的用户类型下标协议**：参数类型参与匹配、借用视图有明确形态、
缺失/越界语义落到包层、复合赋值与取址给出二值化的支持或拒绝——仍然只做编译期静态展开，不引入运行期派发。

---

## 1 现状（实测，不是转述）

### 1.1 已经能做到的（容易误判为「不支持」）

`get` / `set` 的**签名决定**返回值形态：`int get(int)` 是值拷贝，`int *get(int)` 是借用视图。两者今天都已能展开：

```ct
struct Box { int a[4]; }
impl Box {
    int  get(int i)    { return self->a[i]; }
    void set(int i, int v) { self->a[i] = v; }
}
int main(void) {
    Box b;
    b.set(0, 7);      /* -> Box_set(&b, 0, 7) */
    printf("%d\n", b[0]);   /* -> Box_get(&b, 0) */
    b[1] = 9;         /* -> Box_set(&b, 1, 9) */
    return 0;
}
```

```text
$ ct-ast b1.ct -o b1.c ; echo rc=$?
rc=0
$ cc -std=c99 b1.c -o b1 && ./b1
7
9
```

借用形态也已可用：

```ct
impl Buf { int *get(int i) { return &self->a[i]; } }
int main(void) { Buf b; *b[1] = 6; }   /* -> (*Buf_get(&b, 1)) = 6; */
```

```text
$ ct-ast b3.ct -o b3.c ; echo rc=$?
rc=0
```

### 1.2 真正的缺口

| # | 缺口 | 实测 | 锚点 |
| --- | --- | --- | --- |
| G1 | **参数类型不参与匹配**：只有 `char *get(char *)` 时 `x[0]` 也命中，展开成 `get(0)`，静默返回空 | `printf("[%s]\n", j[0])` → `J_get(&j, 0)`，rc=0，运行输出 `[none]` | 协议匹配 [Expr.h.ct:6269-6320](../../selfhost/ct-ast/frontend/parse/Expr.h.ct#L6269-L6320)；D52-2 / D52-6 |
| G2 | **复合赋值 / 自增 / 取址一律拒绝**，借用形态本是合法写法却也被拦 | `b[0] += 2;` → rc=1，`a custom subscript supports only '='; use set(k, v)` | [Expr.h.ct:2994-3011](../../selfhost/ct-ast/frontend/parse/Expr.h.ct#L2994-L3011)、[:4032-4050](../../selfhost/ct-ast/frontend/parse/Expr.h.ct#L4032-L4050) |
| G3 | **下标结果不能取成员**：`q[0].x` 原样发射 `Q_get(&q,0).x`，ct-ast rc=0、`cc` 才报错 | `cc`：`member reference type 'struct P *' is a pointer; did you mean to use '->'?` | [Expr.h.ct:4230-4286](../../selfhost/ct-ast/frontend/parse/Expr.h.ct#L4230-L4286) |
| G4 | **无缺失/越界语义**：协议层零规定，包各写各的（`NULL` / 哨兵 / `Option`） | ct-json 只能提供 `get_idx(i)` 过渡方法 | §2 议题 C |
| G5 | **trait 方法不参与**：只有固有 `impl` 的 `get`/`set` 算协议 | `inst_inherent_method` 只查固有方法 | D52-2；[:3576](../../selfhost/ct-ast/frontend/parse/Expr.h.ct#L3576) |

> G3 是独立缺陷（静默坏产物，rc=0），不属于本条设计范围；建议另立 issue，见 §5。

### 1.3 今天为什么「下游写不了」

ct-json 需要 `doc[0]` 与 `doc["k"]` 并存。方案 A 下同类型只能有一个 `get`；`get` 写成 `char *` 时数字下标**静默变空**，
写成 `int` 时字符串下标静默变 `0`。包层的唯一安全写法是放弃下标语法、暴露 `get_idx(i)` / `get_key(k)`——
这正是本需求要消除的泄漏。

---

## 2 七个设计问题与裁定

裁定编号 `D-IX-n`，与 §3 的两席结论一一对应；本提案**不保留「待定」项**。

### 2.1 语法形态（D-IX-1）

- **读写共用 `[]`，但写形态仍只收「语句位置 + 左值接收者」**（沿用 D52-8）。`x[k]` 是读，`x[k] = v;` 是写。
- **不引入 `Index` / `IndexMut` 两条 trait，也不引入单 trait 的可变视图**：协议就是固有 `impl` 里的
  `V get(K)` / `void set(K, V)` / `V *get(K)`。理由见 §3 议题 A。
- 读写共用 `[]` 的代价是「写形态的语义由 `set` 决定、读形态由 `get` 决定」，这与 C 的 `[]` 直觉一致；
  不引入 `x[k]` 的「可变引用」概念（CT 没有引用类型，只有指针）。

### 2.2 返回值形态（D-IX-2）

- **完全由签名决定，编译器不强制、不包装**：
  - `V get(K)` → 值拷贝；
  - `V *get(K)` → 借用视图，读形态得到指针，写形态写 `*x[k] = v`（今天已可发射，见 §1.1）。
- 不新增 `get_ref` / `at` 之类的第二个方法名（§3 议题 B 裁定）。理由：`V *` 与 `V` 已经是语言里区分
  「借用 / 拷贝」的既有手段（`std::Vec::at` 与 `get` 同形），再加协议名只会分裂生态。

### 2.3 越界与缺失语义（D-IX-3）

- **语言不定义缺失/越界语义**，只定义「协议是什么」。库层用既有设施表达：
  - 借用形态：`NULL` 表示缺失（`V *get(K)` 返回 `0`）；
  - 值形态：包返回 `Option<V>`（`ct build` 自动加载，见规范 §0），或自己的哨兵值；
  - 需要错误码时走 `Result<V, E>` + 后缀 `?`。
- **不统一成「越界硬错」**：越界是运行期事实，静态无法判定；把它写成编译期规则只能得到错误承诺。
- 因此「返回 `NULL` 还是置错误码」的答案是：**借用形态 NULL、值形态 Option/Result，两者在语言层不统一，
  在库层通过 `?` 归一**。

### 2.4 与 trait + vtable 的关系（D-IX-4）

- **静态派发，只认固有 `impl`**（维持 D52-2）。`[]` 是语法糖，展开成 `<Inst>_get(&x, k)` 的普通 C 调用，
  零 vtable、零运行期类型信息。
- 不支持「接口值上的下标」：接口类型无法保证所有实现都声明了 `get`，要支持就得把 `get` 提进 trait 声明，
  那会让 `x[k]` 在「静态糖」与「vtable 派发」之间分裂成两条语义（§3 议题 A）。
- 若将来确需接口下标，走**显式方法调用**（`x.get(k)`），不扩展 `[]`。

### 2.5 与 `into` 块、泛型、`impl` 签名的交互（D-IX-5）

| 交互面 | 裁定 |
| --- | --- |
| `into` 块 | `x into { … }` 内的 `$` 是接收者别名；**`$[k]` 不在本条范围**（`$` 的静态类型判定与 `into` 的物化语义耦合，另案）。块外的 `x[k]` 不受影响。 |
| 泛型 | 沿用 PH-52 的实例还原：`Box<int>` 的下标按 `Box_int_get` 展开，诊断里的类型名用 `ct_inst_find` 还原成 `Box<int>`（[Expr.h.ct:6245-6263](../../selfhost/ct-ast/frontend/parse/Expr.h.ct#L6245-L6263)）。参数类型匹配在**实例化后的签名**上做。 |
| `impl` 签名 | 只有固有 `impl X { … }` 参与；`impl Trait for X` 里的同名方法不参与（今天已如此，`inst_inherent_method` 保证）。固有 impl 与 trait impl 同名时，`x[k]` 永远选固有那个。 |
| 跨单元 | `get` / `set` 私有（无 `pub`）→ 消费单元不可见 → 沿用 L52-10 的硬错文案，不放宽。 |

### 2.6 参数类型匹配规则（D-IX-6）

- 匹配维度：**方法名 + 参数个数 + 非 `static` + 实参类型**。
- 类型比较复用 `type_key`（去空白、去 `const` / `volatile`、折叠整数别名，见 [TypeCheck.h.ct](../../selfhost/ct-ast/frontend/type/TypeCheck.h.ct) 的 `type_key`），
  不做隐式转换、不做数值提升；`int` 实参只匹配 `int` / `long` 之外的**同 key** 签名（`int` 与 `long` key 不同）。
- 命中 0 条 → 硬错，列出该类型全部候选签名（名字 + 参数类型），文案见 §7。
- 命中 ≥2 条且无法区分 → 硬错「ambiguous」，同样列出候选；**不做优先级规则**（不做 C++ 那套重载决议）。
- 实参类型推不出来（`static_ctype` 失败）→ 硬错并提示「把下标存进局部变量再下标」，**不回退 C 下标**（维持 D52-5）。

### 2.7 复合赋值、自增、取址（D-IX-7）

| 形态 | 值形态 `V get(K)` | 借用形态 `V *get(K)` |
| --- | --- | --- |
| `x[k] = v;` | 展开 `x.set(k, v)`（今天如此） | 展开 `*x.get(k) = v`，**要求 `get` 存在且无 `set`**；同名 `set` 存在时仍走 `set` |
| `x[k] += v;` | 硬错（沿用），文案指向「读回再 `set`」 | 硬错（保持单次求值；`x.get(k)` 只求值一次的临时量规则会引入新节点） |
| `x[k]++` | 硬错（沿用） | 硬错（同上） |
| `&x[k]` | 硬错（沿用） | 允许？**不允许**——`get` 已返回指针，`&x[k]` 会得到 `V **`，语义易误读；硬错文案提示写 `x[k]` 本身 |

裁定：**写形态只支持 `=`**，借用形态的写靠 `*x[k] = v`（今天已成立，D-IX-7 只是把它写进规范并加夹具）。
`+=` / `++` / `&x[k]` 三者在两种形态下**统一硬错**，保证判据二值。

---

## 3 两席打（主张席 / 反证席 / 裁定）

### 议题 A：要不要引入 `Index` / `IndexMut` trait

| 席 | 主张 | 依据 |
| --- | --- | --- |
| 主张席（TRAIT） | 引入 `trait Index { V get(K); }` + `trait IndexMut { void set(K, V); }`，用户 `impl Index for X`，与 Rust 对齐 | 生态熟悉；trait 可复用文档与 `--emit-map` |
| 反证席（STATIC） | 不引入。`[]` 是**静态糖**，trait 是 vtable 派发；两者叠加会要求「接口值上的 `[]`」，而接口无法保证每个实现都有 `get` | D52-2 现状；[Emitter.h.ct:5261-5293](../../selfhost/ct-ast/backend/emit/Emitter.h.ct#L5261-L5293) 的 `aux == 9` 分支是**直接 C 调用**，没有 vtable 路径 |
| 证据席（ARCH） | 引入 trait 的收益是「可被泛型约束」，但 CT 的泛型约束目前只按 `trait` 名存在，且下标糖必须在**编译期**知道方法名才能展开；trait 只增加一层间接，不增加表达能力 | `test/ast/p52_*` 现有夹具全走固有 impl |

**裁定：A-STATIC**——不引入 `Index` / `IndexMut`，维持固有 `get` / `set`。若将来要做「泛型容器 + 下标」，
以 `trait` 约束 + 显式 `x.get(k)` 解决，不动 `[]`。

### 议题 B：借用返回值要不要独立方法名（`get` vs `get_ref`）

| 席 | 主张 | 依据 |
| --- | --- | --- |
| 主张席（TWO-NAMES） | 值拷贝与借用视图用两个名字（`get` / `get_ref`），避免同名 `get` 返回类型不同导致的阅读歧义 | Rust 的 `Index` 返回引用、`get` 返回 `Option<&T>`，名字区分了失败 |
| 反证席（ONE-NAME） | 一个名字即可：CT 已有 `V` 与 `V *` 的区分，签名即契约；再加名字会让「同类型既有 `get` 又有 `get_ref`」的匹配规则复杂化 | §1.1 实测：`int *get(int)` 已可写、可读、可用 `*x[k] = v` 写 |
| 证据席（ARCH） | 两个名字会把 D-IX-6 的「参数类型匹配」变成「名字集匹配」，规则面翻倍；而借用与否是**包的实现选择**，不是调用点语法差异 | 探针 `b3.ct` 证明单名可行 |

**裁定：B-ONE-NAME**——只有 `get` / `set`；借用与否由返回类型决定。

### 议题 C：缺失/越界语义统一到 `NULL` 还是 `Option`

| 席 | 主张 | 依据 |
| --- | --- | --- |
| 主张席（NULL） | 统一 `NULL`：`V *get(K)` 返回 0 即缺失，规则最简单，C 侧零成本 | 借用形态天然有 NULL |
| 反证席（OPTION） | 值形态没有 NULL 表示（`int get(int)` 不能返回空），统一 NULL 只能强制所有 `get` 返回指针，等于禁止值拷贝，破坏 §1.1 现状 | `type_key` 不区分「可空」；`int` 无哨兵 |
| 证据席（ARCH） | 两者不能统一：**语言层不规定**，借用用 NULL、值用 `Option<V>`，`?` 已在 PH-44 落地可做归一 | 规范 §4.61 / §4.62；`Option` 随 `ct build` 自动加载 |

**裁定：C-NO-LANGUAGE-RULE**——语言不定义缺失语义；借用形态用 NULL，值形态用 `Option` / 包的哨兵。
理由写进规范对应段落（见 §6 T-4）。

### 议题 D：数字键与字符串键并存，靠重载还是靠分开的名字

| 席 | 主张 | 依据 |
| --- | --- | --- |
| 主张席（OVERLOAD） | 同类型并存 `get(int)` / `get(char *)`，实参类型选版（= REQ-JSACCESS-1 原案） | `doc["a"]` 与 `doc[0]` 必须同形，否则语法糖退化成两个名字 |
| 反证席（NO-OVERLOAD） | 不做重载：数字用 `get`、字符串用 `getk`，规则面最小，避免 `int` / `long` / `char *` 之间的匹配歧义 | 本仓没有完整表达式类型系统，`static_ctype` 覆盖有限（R-1 风险） |
| 证据席（ARCH） | `static_ctype` 已能给出字面量、变量、成员、下标的静态类型（V29-4 路径），字面量键（`"k"` / `0`）是**最容易**判定的一类；歧义场景（`int` vs `long`）可用 `type_key` 精确比较消除，不做隐式转换 | [Expr.h.ct:3762](../../selfhost/ct-ast/frontend/parse/Expr.h.ct#L3762) `static_ctype`；D52-6 正是「不重载」的后果 |

**裁定：D-OVERLOAD**——做参数类型匹配（即 `REQ-JSACCESS-1`），**不做隐式转换、不做优先级**；
推不出类型时硬错。匹配失败时的候选清单是二值判据的关键。

---

## 4 编译器侧改动范围

| 层 | 文件与锚点 | 改动 | 备注 |
| --- | --- | --- | --- |
| Lexer | [Lexer.h.ct](../../selfhost/ct-ast/frontend/lex/Lexer.h.ct) | **零改动** | `[` / `]` 已是单字符 punct |
| Parser 后缀 | [Expr.h.ct:4178-4286](../../selfhost/ct-ast/frontend/parse/Expr.h.ct#L4178-L4286) | 已有 `[` 后缀与自定义下标分支（4230-4286）；把 4235 的判据从「是 struct 值」扩到「struct 值 + 能匹配到签名」 | 不改 `Vec_` / `Map_` 分支（4188-4229） |
| 协议匹配 | [Expr.h.ct:6269-6320](../../selfhost/ct-ast/frontend/parse/Expr.h.ct#L6269-L6320) `custom_index_method` | 增加「实参静态类型 → 候选签名」筛选与候选清单文案 | 现签名 `(bty, name, want, line, col, writable)` 需要多一个实参类型入参 |
| 写形态守卫 | [Expr.h.ct:2994-3011](../../selfhost/ct-ast/frontend/parse/Expr.h.ct#L2994-L3011) | 借用形态的 `*x[k] = v` 不被这条守卫误拦 | 守卫按 `container_subscript_kind(left) == 3` 判定 |
| 写/取址守卫 | [Expr.h.ct:4008-4050](../../selfhost/ct-ast/frontend/parse/Expr.h.ct#L4008-L4050) | `+=` / `++` / `&x[k]` 的文案统一（D-IX-7） | 文案冻结后逐字断言 |
| 类型推导 | [Expr.h.ct:3762](../../selfhost/ct-ast/frontend/parse/Expr.h.ct#L3762) `static_ctype` | 若下标结果要参与外层匹配，需要 `N_MCALL` 返回类型 | 先核对现状，避免扩大面 |
| 发射 | [Emitter.h.ct:5261-5293](../../selfhost/ct-ast/backend/emit/Emitter.h.ct#L5261-L5293)（`aux == 9`） | 一般无需改动；借用写形态要确认 `(*X_get(...)) = v` 的括号路径 | 现有 `b3.ct` 已产出该形状 |
| 泛型实例名 | [Expr.h.ct:6245-6263](../../selfhost/ct-ast/frontend/parse/Expr.h.ct#L6245-L6263) | 复用 `ct_inst_find` 还原 | 不新增逻辑 |
| 规范 | [language-spec.md](../language-spec.md) 自定义下标一节 | 补 D-IX-1…7 的口径（缺失语义、借用形态、匹配规则、拒绝清单） | 见 §6 T-4 |

**不做**：`frontend/type/TypeCheck.h.ct` 的 `maybe_box` 路径不动（接口装箱与下标无关）。

---

## 5 范围外与已知洞

| 项 | 处置 |
| --- | --- |
| `x[k].field` / `x[k].m()`（G3） | **另案**：静默坏产物（rc=0、`cc` 才报错），应单独立 issue 并按缺陷修，不塞进本需求；本需求不承诺它 |
| `$[k]`（`into` 块内的接收者下标） | 不做；`into` 的物化规则与本条解耦 |
| 接口值上的 `[]` | 不做（§3 议题 A） |
| `x[k] +=` / `x[k]++` / `&x[k]` | 统一硬错（D-IX-7），不实现 |
| 多级连写 `x["a"]["b"]` | 包层（`JsonRef`）；语言只保证单跳 |
| 指针接收者 `p[k]` | 保持 C 指针算术（D52） |
| 其它运算符重载 | 不做 |
| 返回值语义检查（`get` 返回类型与 `set` 第二参数是否一致） | 不做；由 `cc` 兜底（与 `ct check` 的 opt-in 边界一致） |

---

## 6 施工切分与排期

### 6.1 切片

| 切片 | 内容 | 出口 | 规模 |
| --- | --- | --- | --- |
| S0 | 核对 §4 全部锚点、复跑 §1 探针、记录 `baseline: <sha>` | 无提交 | S |
| S1 | **只读 + 参数类型匹配**（= `REQ-JSACCESS-1` 全部判据）：候选筛选、0 命中/歧义文案 | A1 / A2 绿 | M |
| S2 | **借用写形态**：`*x[k] = v` 正式化 + `set` 缺失时走 `*get` 的判定 | A3 绿 | M |
| S3 | **拒绝清单统一**：`+=` / `++` / `&x[k]` 三形态文案与夹具 | A4 绿 | S |
| S4 | 回归：`p52_*`、`Vec`/`Map`、C 透传 | A5 / A6 绿 | S |
| S5 | 规范口径 + 收口证据 | A7 绿 | S |

### 6.2 排期建议

- **相号**：`PH-54`（`PH-53` 已收口 `v0.53.0`，54 是下一个空位）。本提案只做候选登记，**不占号**。
- **与当前工作的关系**：不抢正在做的两处 P0 缺陷修复（字符串截断在
  [Lexer.h.ct](../../selfhost/ct-ast/frontend/lex/Lexer.h.ct) + [Expr.h.ct](../../selfhost/ct-ast/frontend/parse/Expr.h.ct) 的 `T_STR` 分支；
  右值装箱在 [TypeCheck.h.ct](../../selfhost/ct-ast/frontend/type/TypeCheck.h.ct) 的 `maybe_box`），两边的改动文件区域不重叠。
  PH-53 已收口，不存在占位冲突。
- **拆两步**：**先只读**（S1，即 `REQ-JSACCESS-1`），**后借用写**（S2/S3）。理由：只读是下游 ct-json / rill-dsl 的
  真实阻塞（`doc[0]["k"]` 的第一跳），借用写是能力补齐；先只读可以让 ct-json 提前解阻塞，且 S1 的红证最小。
- **依赖**：`REQ-JSACCESS-1` ⊂ S1（先做）；PH-52（已交付）与 PH-51（已交付）是前置；S2 依赖 S1 的匹配结果。
- **不并入 PH-52**：PH-52 的 D52-2 / D52-6 是冻结口径，本需求改的是那条口径本身，必须另立相号并显式记录版本。

---

## 7 判据（二值）

| ID | 判据 | 命令 | 通过 | 失败 |
| --- | --- | --- | --- | --- |
| IX-E1 | 同类型并存 `get(int)` / `get(char *)`，`x[0]` / `x["k"]` 各选其版 | `./selfhost/check-ast.sh 2>&1 \| grep -F "ok    index_overload_both"` | 命中且运行值正确 | 任一静默空 |
| IX-E2 | 只有 `char *get(char *)` 时 `x[0]` 硬错并列出候选 | `... \| grep -F "INDEX_1_no_candidate"` | 文案含两个候选签名 | rc=0 或文案缺候选 |
| IX-E3 | 借用写 `*x[0] = 7;` 后读回 7 | `... \| grep -F "ok    index_borrow_write"` | 输出 `7` | 编译失败或值错 |
| IX-E4 | `x[k] += 1` / `x[k]++` / `&x[k]` 三形态文案与位置 | `... \| grep -F "INDEX_L"` | 三条全命中 | 任一放行 |
| IX-E5 | PH-52 既有夹具零回归 | `bash selfhost/check-ast.sh 2>&1 \| grep -c "p52_"` | 与基线计数一致 | 少一条 |
| IX-E6 | `Vec` / `Map` 与 C 透传零回归 | `./selfhost/check-ast.sh 2>&1 \| grep -F "ok    p52_str_only"` | 命中 | 未命中 |
| IX-E7 | 全量门禁 | `bash selfhost/check-all.sh 2>&1 \| tail -3` | 11 green | 任一红 |

文案草案（S1 冻结前可改，冻结后逐字断言）：

```text
type 'X' has no subscript matching 'get(int)': candidates are 'char *get(char *)'
type 'X' has no subscript: cannot infer the subscript type; bind it to a local first
type 'X' has an ambiguous subscript: candidates are 'int get(int)', 'long get(long)'
a custom subscript supports only '='; use set(k, v) or *x[k] = v
cannot take the address of a custom subscript; use x[k] itself
```

---

## 8 风险与回滚

| 编号 | 风险 | 信号 | 处置 |
| --- | --- | --- | --- |
| IX-R1 | `static_ctype` 推不出实参类型，匹配退化成「无法判定」 | 字面量以外的键（函数返回值、成员链）全报错 | 硬错 + 提示落局部变量；不回退 C 下标（D52-5） |
| IX-R2 | 借用写形态与既有 `set` 同时存在，选择规则歧义 | 同类型既有 `set(int,int)` 又有 `int *get(int)` | 明确优先级：有 `set` 走 `set`，无 `set` 才走 `*get`；夹具钉住 |
| IX-R3 | 参数类型匹配放宽后，PH-52 的字符串键行为变化 | `p52_*` 红 | 以 `type_key` 精确比较，`char *` 与 `const char *` 同 key，保证 `p52_*` 不变 |
| IX-R4 | 复合赋值若强行支持，下标子表达式被求值两次 | `x[f()] += 1` 出现两次 `f()` | D-IX-7 明确不支持，硬错 |
| IX-R5 | 自举链不认新分支 | `check-goldens` fixpoint 红 | 编译器源码不使用该语法；只改解析与诊断 |

---

## 9 规模与退出

- 编译器 150–300 行（S1 约 80–150，S2/S3 约 40–90，S4/S5 约 30–60）。
- 夹具 80–160 行（4 个正向 + 3 组负向）。
- 文档 30–60 行（规范一节 + 本提案收口表）。
- 退出：IX-E1…E7 全绿，且 §1 的 G1 / G2 由「静默」或「误拒」转为**二值判定**。
