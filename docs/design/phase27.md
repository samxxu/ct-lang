# Phase 27 · `foreach` 语句形态（完成）

> 中文。
>
> **状态：完成**（判据冻结于 2026-11-10、首个实现提交之前；版本仍为 `v0.26.4`，未 bump）。
> **冻结口径**：D27-1–D27-11 全部裁决完毕（§4），E27-1–E27-7 与 L27-1–L27-5 的文案、夹具清单在本文件落定后不再为通过而改写；此后的实现、夹具与文档只能向判据靠拢。
> **主题来源**：[D25-12](phase25.md#L287) 保留库层 `each`、为语句形态预留 `foreach`；[DOC-70](../../issues/docs/doc70-each-statement-form-unimplemented.md) 记录了命名判据与探针。
> Phase 22 / 24 / 25 曾把集合遍历列为非目标：[phase22.md:60](phase22.md#L60)（`for x in xs` 无泛型，另议）、[phase24.md:45](phase24.md#L45)（SHIM/宏做不到）、[phase25.md:61-64](phase25.md#L61-L64)（隐式名、块参数、`break`/`continue`，未排期）。
> 关联：[phase21.md](phase21.md)（非逃逸闭包）、[phase25.md](phase25.md)（静态映射闭包实参）、[phase26.md](phase26.md)（泛型函数）、[language-spec.md](../language-spec.md)、[roadmap.md](../roadmap.md)。

---

## 1. 立项

### 1.1 编号

| 项 | 值 |
| --- | --- |
| Phase | 27 |
| 目标版本 | `v0.27.0`（开工后 bump；规划期不计版本） |
| 依赖 | Phase 21（非逃逸闭包）、Phase 25（`each` / 静态映射闭包实参）、Phase 26（泛型函数与显式实例化） |
| 改动边界 | 仅 `selfhost/ct-ast/**`；L0 / L1 / L2 种子不改（同 Phase 22/25/26 先例） |

### 1.2 一句话目标

加一个语句级 `foreach (集合) { … item … }`：`item` 是隐式绑定，整条语句展开为普通 C 循环，零运行时对象，`break` / `continue` / `return` 按外层函数语义工作。

### 1.3 范围

| 切片 | 内容 |
| --- | --- |
| S1 | 语法：`foreach (expr) { stmt* }`；`foreach` 是**上下文关键字**（仅语句位置 + 后跟 `(`），其余位置仍是合法标识符 |
| S2 | 隐式绑定 `item`；嵌套时内层遮蔽外层，策略与 `loop` 的 `i` 一致 |
| S3 | 数组展开：一维、长度编译期已知（`T a[N]` 或 `T a[] = {…}`） |
| S4 | 容器展开：**本相不做**（D27-4，见 §4.1）；`foreach` 只接受编译期可定长的一维数组 |
| S5 | 控制流：`break` / `continue` / `return` 原生工作（因为展开为真循环，不是闭包调用） |
| S6 | 诊断 L27-1…L27-5，`ct build` 与 `ct check` 同口径 |
| S7 | 夹具、生成 C 断言、文档（spec / tutorial / roadmap） |

### 1.4 本相不做

| 不做 | 理由 |
| --- | --- |
| `foreach (x in xs)`、`foreach (xs, name)`、块参数 `\|x\|` | 与 `loop(n)` 的隐式 `i` 保持一致；显式名字留到有真实需求再议 |
| 迭代器对象 / `range` / 字符串按字符 | 需要运行时对象或 char 协议，违背零运行时口径 |
| 裸指针 `int *p` 的 `foreach` | 长度已丢失；`int a[4]` 与 `int *p` 在语句层无法区分（同 D25-8 的自动长度结论） |
| 多维数组 | `item` 会是数组类型，C 不能按值赋值；v1 直接拒绝（L27-3） |
| 泛型容器 / `Vec<T>` | 依赖泛型 struct；Phase 26 明确不做（D26-2：布局单态化，另一个量级） |
| 容器协议（`len()` + `get(int)` / `entry(int)`） | 本仓没有 std 容器实现，协议的唯一消费者在 ct-pkg；无夹具就无红证，冻结一个不可验证的 API 违背证据门禁。转下一阶段（D27-4，§4.1） |
| 数组成员 `m.cells`、数组形参 `int a[]` | 前者元素类型只能靠字段表推，后者在 C 里已衰减为指针、长度已丢失；都拒绝（L27-4） |
| 把 `foreach` 降级为 `each(closure)` | `break`/`continue`/`return` 不能跨闭包边界；这正是语句形态存在的理由 |
| 运行时迭代器 / 装箱 / vtable | 违背「零运行时对象」口径 |

---

## 2. 语法

### 2.1 形状

数组：

```ct
int nums[5] = { 3, 1, 4, 1, 5 };
int total = 0;

foreach (nums) {
    total += item;
}
```

map（`item` 是容器定义的条目值，字段由条目类型决定）：

```ct
foreach (m) {
    printf("%s = %d\n", item.key, item.value);
}
```

嵌套（内层 `item` 遮蔽外层，离开内层后恢复）：

```ct
foreach (rows) {
    foreach (row) {
        count += item;
    }
}
```

### 2.2 规则

- `item` 只在该 `foreach` 块内可见；块外引用 → L27-1。
- 嵌套 `item` 遮蔽：`ct build` 记 warning，`ct check` 记 error（与 `loop` 的 `i` 同级策略）。
- `item` 是元素**值拷贝**（C 赋值语义）；修改 `item` 不回写容器。需要回写就用原生 `for` 或下标访问。
- 空集合执行零次；`break` 立即退出整条 `foreach`；`continue` 进入下一次。
- `foreach` 后必须是块 `{ … }`，不接受单语句。

### 2.3 与 `loop` 对照

| | `loop(n)` | `foreach(xs)` |
| --- | --- | --- |
| 隐式绑定 | `int i`（可写） | `item`（元素值的拷贝） |
| 迭代对象 | 计数 | 集合 |
| 展开 | 一行 `for` | 一行 `for` + 元素绑定 |
| `break` / `continue` / `return` | 支持 | 支持 |
| 自定义绑定名 | 不做 | 不做 |
| 求值次数 | 计数表达式求值一次 | 长度求值一次（快照） |

### 2.4 与最初描述的对照

| 最初想法 | 本计划 | 说明 |
| --- | --- | --- |
| 语言级 `each` 循环关键字 | `foreach` 语句 | 按 D25-12 更名，避免与 `each<T>(...)` 调用歧义 |
| `each (nums) { … item … }` | `foreach (nums) { … item … }` | **形状不变**：集合表达式 + 隐式 `item` |
| 自动取长度 | 数组自动；容器用 `len()` | 方法形态因 decay 丢长度做不到；语句形态对数组可以（见 §3） |
| 泛型容器 | 不在本相 | 依赖泛型 struct，Phase 26 已明确不做 |

**明确未采用**：`foreach (item in xs)`、`foreach (xs, item)`、`foreach (xs) \|item\| { … }`。如果目标是 `in` 形式，需要在 §4 冻结前改 D27-1/D27-2。

---

## 3. 展开规则（已冻结）

### 3.1 数组

```ct
foreach (nums) { total += item; }
```

展开为（`K` 是发码器的单调计数，示例里是 `0`）：

```c
{
    int __ct_foreach_n_0 = (int)(sizeof(nums) / sizeof((nums)[0]));
    for (int __ct_foreach_i_0 = 0; __ct_foreach_i_0 < __ct_foreach_n_0; __ct_foreach_i_0++) {
        int item = (nums)[__ct_foreach_i_0];
        (void)item;   /* keeps -Wall -Wextra clean when the body ignores item */
        total += item;
    }
}
```

- 长度取 `sizeof(x) / sizeof((x)[0])`（D27-9）：`[5]`、`[]`、`[MAX]`、VLA 都对，且在循环前只求值一次（D27-7 快照语义）。
- 外层加块，避免 `__ct_foreach_n_K` / `__ct_foreach_i_K` 泄漏到用户作用域。
- `K` 每生成一条 `foreach` 自增，嵌套时天然得到 `_1`、`_2` …，不需要预扫描。
- `item` 的声明类型取符号表里该数组的元素类型，按值初始化（D27-5）。

### 3.2 容器（D27-4：本相不做）

候选协议曾是 `len()` + `get(int)`、map 用 `len()` + `entry(int)`。**裁决为不做**（battle 记录见 §4.1），理由是不存在可验证的消费者：

- 本仓没有 std 容器源码；协议的唯一真实消费者在 ct-pkg，而项目已裁定包管理挂账不纳入本仓考量。
- 没有夹具就写不出「先红后绿」的断言；冻结一个无人调用的 API 属于推测性设计。
- 容器元素要落成 C 调用（`N_MCALL`）并按方法签名取返回类型，这条通路当前没有任何既有夹具覆盖，风险高于收益。

因此 `foreach` 只接受一维数组（§3.1）；非数组容器一律 L27-4，文案明确指向下一阶段，不假装支持。

### 3.3 明确拒绝的降级

`foreach (xs) { body }` **不**降级为 `xs.each((item) => body)`：

- `break` / `continue` 无法跨闭包边界；
- `return` 会变成“从闭包返回”，语义错误；
- 闭包环境是栈上复合字面量，与循环语义不匹配。

---

## 4. 决策与开放问题

| 编号 | 决策 | 建议 | 状态 |
| --- | --- | --- | --- |
| D27-1 | `foreach` 是上下文关键字，不做保留字 | 采纳 | 已决 |
| D27-2 | 隐式绑定名固定为 `item`；嵌套遮蔽同 `loop.i` | 采纳 | 已决 |
| D27-3 | 数组仅一维、长度编译期已知；裸指针拒绝 | 采纳 | 已决 |
| D27-4 | 容器协议 `len()` + `get(int)`；map 用 `len()` + `entry(int)` | **不采纳（本相不做）** | 已决（battle，§4.1） |
| D27-5 | `item` 值拷贝，不回写容器 | 采纳 | 已决 |
| D27-6 | 展开为真循环，不降级为 `each(closure)` | 采纳 | 已决 |
| D27-7 | 长度在循环前求值一次（快照语义） | 采纳 | 已决 |
| D27-8 | 生成名 `__ct_foreach_n_<K>` / `__ct_foreach_i_<K>`，`K` 为发码器单调计数，嵌套天然不撞名 | 采纳 | 已决 |
| D27-9 | 长度表达式用 `(int)(sizeof(x) / sizeof((x)[0]))`，而不是从维度文本抠字面量 | 采纳 | 已决（§4.2） |
| D27-10 | 遮蔽只在 `foreach` 套 `foreach` 时报；手写 `item` 与原生 `for` 保持静默，对齐 D22-5 | 采纳 | 已决（§4.2） |
| D27-11 | 数组形参、未定长的文件作用域数组、数组成员、接口元素一律硬错（L27-4） | 采纳 | 已决（§4.2） |

### 4.1 D27-4 的 battle

| 立场 | 判据 | 结论 |
| --- | --- | --- |
| 支持在本相冻结 `len()` + `get(int)` 协议 | 底稿 S4 / E27-2 把它写成交付物；协议形状简单，与 `each` 的库层方法名互补 | 判据弱：协议没有本仓消费者，ct-pkg 已裁定不纳入本仓考量 |
| 本相只做数组，容器推迟 | 本仓无 std 容器；无夹具即无红证；方法调用落码（`N_MCALL` + 返回类型）无既有夹具覆盖；违反证据门禁与「不发射坏 C」红线的风险更高 | **采纳**：可验证性 > 纸面完整性 |

裁决：容器协议不进 Phase 27。`foreach` 对非数组容器给 L27-4 硬错，文案指向下一阶段；协议本身留给有真实容器实现（ct-pkg 集成）的阶段重新冻结。此裁决不改写 E27-2 的「容器缺 len/get」一项，而是把它降级为「非数组容器被拒绝」的负例，仍可测。

### 4.2 其余判据的裁决理由

- **D27-9 长度**：从 `text3` 抠 `[13]` 只覆盖数字维度，`[]`（`T a[] = {…}`）、`[MAX]`、VLA 全落空。`sizeof(x)/sizeof((x)[0])` 对四者都成立，且在循环前求值一次，正好满足 D27-7 的快照语义；生成的 C 仍是单个 `for`，不引入运行时对象。
- **D27-10 遮蔽**：D22-5 已裁定「只有 `loop` 套 `loop` 才报，手写 `int i` 静默」。`item` 沿用同一策略，避免把用户普通局部变量变成噪声；`ct check` 由诊断层统一升为 error（E27-4）。
- **D27-11 不可迭代形态**：数组形参在 C 里已是指针（`sizeof` 会静默给错长度），未定长的文件作用域数组类型不完整（会发射非法 C），数组成员的元素类型只能靠字段表推（本相不做），接口元素按值拷贝会绕过 vptr 约束。四者都硬错，宁可拒绝也不发射坏 C。

---

## 5. 切片

| 切片 | 内容 | 主要 unit |
| --- | --- | --- |
| 27.1 | 语法与诊断：上下文关键字、块解析、`item` 作用域、L27-1…L27-5 | `frontend/parse/Stmt.h.ct`、`frontend/sym/Symbols.h.ct`、`tool/diag/Diag.h.ct` |
| 27.2 | 数组展开与夹具（正例 `132`–`135`、负例九条） | `runtime/arena/Arena.h.ct`、`backend/emit/Emitter.h.ct` |
| 27.3 | ~~容器协议查找与 map 条目~~ **本相取消**（D27-4），对应判据并入 27.1 的 L27-4 负例 | — |
| 27.4 | 文档与样例：spec 新章节、tutorial、roadmap 状态、DOC-70 回链；`examples/20_foreach_statement`（E27-7） | `docs/**`、`examples/**` |
| 27.5 | 自举与全门禁：fixpoint、`check-warnings.sh`、`make check` | `selfhost/**` |

---

## 6. 退出判据

| 编号 | 判据 |
| --- | --- |
| E27-1 | 正例 `132`–`135` 全绿：`int` 数组、`T a[] = {…}` 推断长度、结构体数组（字段访问）、指针数组、文件作用域 `static const` 表、嵌套遮蔽、`break`/`continue`/`return` 各一 |
| E27-2 | 负例逐条命中自己的文案：裸指针、多维数组、数组形参、非数组结构体、数组成员、未定长文件作用域数组、`item` 块外引用、空集合表达式、非块体；且 `foreach` 作普通标识符（变量名 / 调用）仍编译通过 |
| E27-3 | 生成 C 是单个 `for`：存在 `__ct_foreach_n_<K>` 与 `__ct_foreach_i_<K>`，长度表达式只出现一次；运行时输出与手写 `for` 版本逐字节一致 |
| E27-4 | `ct check` 与 `ct build` 同口径：嵌套 `foreach` 的遮蔽在 build 下是 warning、在 `ct check` 下是 error；其余 L27 文案两模式一致 |
| E27-5 | 全语料零新增 warning；`check-docs.sh` 通过 |
| E27-6 | 自举 fixpoint 与 11 道硬门禁全绿；`selfhost/**` 改动后 `bash selfhost/check-all.sh` 通过 |
| E27-7 | 样例 `examples/20_foreach_statement`：覆盖数组遍历、块内隐式 `item`、`break`、`continue`、块内 `return`、与闭包同用的组合场景；同一文件内与库层 `each`（trait 方法 + 回调）对照，能看出「什么时候用 `foreach`、什么时候用 `each`」。`expected.out` 由编译器产物生成后人工核对（禁手写），在 `examples/README.md` 登记，并靠 `//@ct-requires: ct-ast` 纳入 `test/run.sh` 的端到端路径（同时进 `check-ast` / `check-warnings` 语料） |

> E27-7 为 2026-11-10 追加的交付要求（用户明确「`foreach` 必须有对应样例，不等到收口补」），
> 在**首个实现提交之前**冻结；它只增加交付面，不放宽 E27-1–E27-6。

### 6.1 L27 诊断（冻结文案）

| 编号 | 触发 | 文案 |
| --- | --- | --- |
| L27-1 | 块外引用 `item` | 走普通未声明标识符诊断，要求带位置且非零退出（不新增专用文案） |
| L27-2 | 集合不是数组 | `foreach needs an array; '<name>' is not iterable` |
| L27-3 | 多维数组 | `foreach does not support multidimensional arrays ('<name>')` |
| L27-4 | 数组形参 / 未定长文件作用域数组 / 数组成员 / 接口元素 / 非标识符集合 | `foreach cannot iterate the array parameter '<name>' (its length is lost)`；`foreach needs an array with a known length ('<name>')`；`foreach needs a plain array variable`；`foreach cannot copy interface values ('<name>')` |
| L27-5 | 空集合表达式 / 非块体 | `foreach needs a collection expression`；`foreach body must be a block` |
| — | 嵌套遮蔽（warning；`ct check` 下 error） | `foreach shadows the outer 'item'; use a native for to name the binding` |

---

## 7. 风险

- ~~容器协议依赖外部~~：已由 D27-4 移除（本相不做容器）。
- **`sizeof` 前提**：只对完整类型成立。数组形参、未定长的文件作用域数组、数组成员之外的不可迭代形态全部在解析期拒绝（L27-4），不把不完整类型留给 C。
- **值拷贝成本**：大结构体元素每轮复制；文档需明确，必要时提供指针容器的 `get` 返回指针。
- **`item` 命名冲突**：仅 `foreach` 套 `foreach` 时报遮蔽（D27-10）；手写同名局部变量静默，与 `loop.i` 的噪声策略一致。
- **多维数组拒绝**：与 C 直觉有落差，需在 spec 写明。
- **快照语义**：长度在循环前求值一次；循环体里修改数组长度（VLA）不会改变本轮迭代次数。

---

## 8. 与既有特性的关系

| 特性 | 关系 |
| --- | --- |
| `loop(n)` / `loop(a..b)` | 同一类“隐式绑定 + 单行展开”语法糖；`i` 与 `item` 并列 |
| `each`（库方法 / 自由泛型） | 语义重叠但实现不同：`each` 传回调、可跨单元；`foreach` 是语句、支持控制流。两者不互相降级 |
| 闭包 `=>` | `foreach` 的块**不是闭包**，不能存储、不能传递、不能返回值 |
| 泛型函数 | 无依赖；本轮 `item` 类型直接取数组声明，不做类型推导或单态化 |
| trait / impl | 本轮不解析容器方法（D27-4）；trait 值作为元素时按 L27-4 拒绝，避免拷贝 vptr |
| 静态映射 / 函数指针 | 函数指针数组可行但本轮拒绝（非朴素声明符），留给需要回调表的场景 |

---

## 9. 结果与收口（2026-11-10）

### 9.1 交付物

| 交付物 | 位置 |
| --- | --- |
| 解析：`N_FOREACH`、上下文关键字前瞻、作用域与诊断 | `selfhost/ct-ast/frontend/parse/Stmt.h.ct` |
| 符号：`Var.dims`（声明维度原文）、`Var.is_fnparam` | `selfhost/ct-ast/frontend/sym/Symbols.h.ct`、`frontend/parse/Parser.h.ct` |
| 发码：单个 `for` + `sizeof` 长度快照 | `selfhost/ct-ast/backend/emit/Emitter.h.ct` |
| 正例 `132`–`135` | `test/ast/132_foreach_array_values`、`133_foreach_control_flow`、`134_foreach_nested_pointer`、`135_foreach_contextual` |
| 负例 10 条 | `test/ast/errors/foreach_{pointer,multidim,param,struct,member,unsized_global,scope,empty,non_block,fnptr_array}.ct` |
| 门禁断言 14 条 | `selfhost/check-ast.sh` 末尾 Phase 27 段（逐条文案、生成 C、等价性、`ct check` 升错） |
| 样例 | `examples/20_foreach_statement`（`foreach_statement.ct` + `foreach_statement.expected.out`，E27-7） |
| 文档 | spec §4.49（中英）、tutorial 10.6（中英）、glossary、roadmap、examples/README、DOC-70 关闭 |

### 9.2 红证 → 绿证

- 红证：在 `HEAD`（`f04f331`，未实现的 v0.26.4 编译器）上跑同一份 `check-ast.sh`
  → `855 passed, 17 failed`，17 条恰好是 3 个正例 + 14 条 Phase 27 断言；失败原文统一是
  `test/ast/...:N:C: error: unexpected token`（旧编译器在 `foreach` 处停下），正例与
  “expected exit 0”类断言全红，`ct check` 的 JSON 断言也拿不到目标文案。
- 绿证：实现后 `872 passed, 0 failed`（`+36` 条：3 正例 + 10 负例的通用判定 + 14 条专用断言 + 与手写 `for` 的等价性等）。
- 期间修掉三处实现缺口：数组形参原被当成可迭代（C 里已衰减为指针），补 `Var.is_fnparam`；
  `item` 块外引用沿用通用文案 `use of an undeclared variable`，L27-1 据此冻结；
  体内不用 `item` 时生成物触发 `-Wunused-variable`（`check-warnings` 红），补一行 `(void)item;`。

### 9.3 判据核对

| 判据 | 结果 | 证据 |
| --- | --- | --- |
| E27-1 正例 | ✅ | `132`–`135` 全绿（含 `T a[] = {…}`、结构体字段、指针数组、文件作用域 `static const`、嵌套、`break`/`continue`/`return`） |
| E27-2 负例 | ✅ | 10 条 `foreach_*` 各中自己的文案；`135` 证明 `foreach` 作变量/标签仍编译 |
| E27-3 生成 C | ✅ | 断言 `int __ct_foreach_n_0 = (int)(sizeof(nums) / sizeof((nums)[0]));`、`for (int __ct_foreach_i_0 = 0; …)`、`int item = (nums)[__ct_foreach_i_0];`；与手写 `for` 输出 `cmp` 一致 |
| E27-4 口径一致 | ✅ | 嵌套 `item` 在编译模式为 warning、`ct check --diagnostics=json` 为 `"severity":"error"` |
| E27-5 零新增 warning | ✅ | `check-warnings.sh` 263 ok / 0 failed |
| E27-6 自举 / 门禁 | ✅ | `check-all.sh` 11 道全绿；`test/run.sh` 132 passed |
| E27-7 样例 | ✅ | `examples/20_foreach_statement`：数组遍历、隐式 `item`、`break`/`continue`、块内 `return`、块内闭包；同文件对照库层 `each`（trait 方法 + `(fn, env)` 回调）。`expected.out` 由 ct-ast 产物生成后逐行人工核对；`examples/README.md` 已登记；`//@ct-requires: ct-ast` 使其进 `test/run.sh` 端到端，并进 `check-ast` / `check-warnings` 语料 |

### 9.4 门禁原始数字（2026-11-10 收口实跑）

| 门禁 | 结果 |
| --- | --- |
| `test/run.sh` | `132 passed, 0 failed` |
| L1 自重建成 | `25 passed, 0 failed` |
| L2（L1 构建的拆分树） | `25 passed, 0 failed` |
| `check-ast.sh` | `873 passed, 0 failed` |
| `check-warnings.sh` | `263 ok, 0 failed` |
| acceptance | `20 pass, 0 new, 0 pending, 0 regression` |
| `check-docs.py` | 11 phase status + 版本登记通过 |
| `check-all.sh` | 11 道全绿 |

### 9.5 版本与发布

- 本轮**不 bump**、**不打 tag**，版本仍为 `v0.26.4`。
- 若后续要 bump 到 `v0.27.0`，需五处同步（`selfhost/l0/ctc.c`、`selfhost/l1/ctc.ct`、
  `selfhost/l2/core.ct`、`selfhost/l2/driver.ct`、`selfhost/ct-ast/main.ct`）并重生成全部
  golden（`test/**/*.expected.*`、`docs/**` 中的版本号）；风险是冻结层 banner/版本改动
  需同时通过 `check-version` 与 L0/L1/L2 全量回归，建议单独一个 `chore(release)` 提交。

### 9.6 Lessons

- 形状枚举要在解析期先落成硬错表：数组形参在 C 里已衰减，`sizeof` 会给出错误但合法的长度，
  这是「不发射坏 C」之外的第二类陷阱——**静默算错**比编译失败更贵。
- 上下文关键字的前瞻必须完整保存/恢复 lexer 状态（`pos/bol/tok/toknum/line/tokline/tokstart/lstart/toktext`），
  否则 `foreach:` 标签会被误判。
- 现有符号表只记 `is_array` 不记维度；补 `dims` 比在发码期反推声明文本更可靠，也让「多维 / 未定长」
  两类拒绝都有单一事实来源。
