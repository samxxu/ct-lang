# Phase 26 · 泛型函数（单类型参数 + 显式实例化 + 编译期单态化）

> 中文。
>
> **状态：完成**（退出判据于 2026-11-09、首个实现提交前冻结；收口记录见 §6/§7；v0.26.4 补丁见 §9）。
> **主题来源**：[phase25.md:65](phase25.md#L65) 与 [phase25.md:261](phase25.md#L261) 明确写「泛型是 Phase 26」；
> 立项时 [roadmap.md](../roadmap.md) 尚无 Phase 26 行，本相同时补入；需求池中「类型检查 / 泛型」一项被本相拆出实现。
> 关联：[phase25.md](phase25.md)（静态映射闭包实参）、[phase19.md](../history/design/phase19.md)（受限语义检查）、
> [language-spec.md](../language-spec.md)、[roadmap.md](../roadmap.md)、[AGENTS.md](../../AGENTS.md)。

---

## 1. 立项

### 1.1 编号

**Phase 26**，发布版本 **`v0.26.0`**（`CTC_VERSION` = `0.26.0`）；独立评审后的修复补丁为 **`v0.26.1`**（SH-62 / SH-63 / TEST-17 / DOC-67，见 §8），
第二轮重开修复为 **`v0.26.2`**（SH-62 / TEST-17 根因修复 + 系统性防线 + `_Generic` 标签放行，见 §6.2 / §6.3.3 / §8），
第三轮阻断项修复为 **`v0.26.3`**（SH-64 值位置类型参数 + 防线假阳与覆盖记录，见 §2.7 / §6.3 / §8）。

### 1.2 一句话目标

让 CT 支持**单类型参数的泛型函数**：声明 `T name<T>(...)`，调用 `name<int>(...)` 时在编译期为每个
具体类型参数生成一份单态化的 C 函数，产物与手写同类型函数一致，不引入运行时类型信息或装箱。

### 1.3 范围

**做什么**

| # | 内容 |
| --- | --- |
| S1 | 泛型函数声明：`T name<T>(T x, ...) { ... }`，单类型参数，函数形态 |
| S2 | 显式实例化调用：`name<int>(1)`、`name<char *>(p)`、`name<struct Point>(p)` |
| S3 | 编译期单态化：按 `(函数, 类型实参)` 去重，生成 `name__ct1`、`name__ct2` … 的 C 函数 |
| S4 | 类型替换：返回类型、形参、局部声明、`(T)` 转型、`sizeof(T)` 中的类型参数替换为具体类型 |
| S5 | 诊断 L26-1–L26-5（见 §4.2），编译路径与 `ct check` 共用同一套解析期诊断 |
| S6 | 正例/负例夹具与 `check-ast.sh` 断言；`check-warnings` 零告警 |

**不做什么**

| 不做的东西 | 一句话理由 |
| --- | --- |
| 泛型结构体 / 联合 / 枚举 | 需要类型声明与字段布局的单态化，另一个量级 |
| 泛型 trait / `impl` 方法 / 静态映射 | 与 Phase 25 的 recipe 槽位绑定耦合，先不做 |
| 类型参数约束（`T: Ord` 等） | 当前编译器没有约束系统，做了也只是装饰 |
| 类型推导（`name(1)` 自动取 `int`） | 显式实例化是刻意选择；推导需要双向类型检查，超出本相 |
| 多个类型参数、变参泛型、默认类型参数 | 单参数先跑通，避免 `>>` 词法与组合爆炸 |
| 泛型函数作 `pub` / 跨单元调用 | 实例只在定义单元生成；跨单元需要头文件导出实例，本相明确拒绝 |
| 递归泛型调用 / 泛型体内再调用泛型 | 实例化时机与缓存键会递归；先拒绝并给 L26-5 |
| 类型参数用于数组维度、闭包环境、`_Generic`、`__attribute__` | 替换点不可控，容易静默出错 |
| 运行时泛型（`void *` / vtable / 类型标签） | 违背「零运行时对象」的项目口径 |

### 1.4 交付物清单（每项一个路径）

| # | 路径 | 作用 |
| --- | --- | --- |
| D1 | `docs/design/phase26.md` | 本文件：立项、语义、切片、决策、battle、退出判据 |
| D2 | `selfhost/ct-ast/frontend/sym/Symbols.h.ct` | `Fn` 增加 `ntparams/tparam`；`GenericInst` 表与 `add_generic_inst` |
| D3 | `selfhost/ct-ast/frontend/parse/Parser.h.ct` | 声明语法 `T name<T>(...)`；模板标记；`pub`/多参数/递归诊断 |
| D4 | `selfhost/ct-ast/frontend/parse/Expr.h.ct` | 调用语法 `name<int>(...)`；实例化登记、实参检查、类型替换辅助 |
| D5 | `selfhost/ct-ast/backend/emit/Emitter.h.ct` | 实例原型/定义发射；类型字段替换与恢复；跳过模板本体 |
| D6 | `test/ast/123_generic_identity/` | 正例：`int` 与 `char *` 两次实例化，输出确定 |
| D7 | `test/ast/124_generic_struct/` | 正例：`struct Point` 作类型实参，字段访问与返回 |
| D8 | `test/ast/errors/generic_missing_arg.ct` | 负例 L26-1：泛型函数缺少类型实参 |
| D9 | `test/ast/errors/generic_pub.ct` | 负例 L26-2：`pub` 泛型函数 |
| D10 | `test/ast/errors/generic_two_params.ct` | 负例 L26-3：多个类型参数 |
| D11 | `test/ast/errors/generic_void_arg.ct` | 负例 L26-4：`void` 作类型实参 |
| D12 | `test/ast/errors/generic_recursive.ct` | 负例 L26-5：泛型体内递归/嵌套泛型调用 |
| D13 | `selfhost/check-ast.sh` | 正例构建/运行、实例 C 文本、五条负例文案与位置断言 |
| D14 | `docs/language-spec.md` | 语法与语义条目、非目标、诊断表 |
| D15 | `docs/tutorial.md` | 一个可运行示例与限制说明 |
| D16 | `docs/roadmap.md` | Phase 26 行与 `v0.26.0` 版本记录 |
| D17 | `AGENTS.md` | 当前阶段与「泛型仅单参数/显式实例化」限定 |
| D18 | `selfhost/l0/ctc.c` | 仅 `CTC_VERSION` 版本串（无逻辑改动） |
| D19 | `selfhost/l1/ctc.ct` | 仅 `CTC_VERSION` 版本串（无逻辑改动） |
| D20 | `selfhost/l2/core.ct` | 仅 `CTC_VERSION` 版本串（无逻辑改动） |
| D21 | `selfhost/l2/driver.ct` | 仅 `CTC_VERSION` 版本串（无逻辑改动） |
| D22 | `selfhost/ct-ast/main.ct` | 仅 `CTC_VERSION` 版本串（无逻辑改动） |

### 1.5 退出判据（冻结）

每条都必须有可执行命令或可核对锚点；任一不满足即不得打 `v0.26.0`。

| # | 判据 | 命令 / 锚点 |
| --- | --- | --- |
| E1 | 正例 `123_generic_identity` 构建、运行、输出逐字节匹配；整份生成 C 中恰好 2 个实例原型，`id__ct1` 定义恰好 1 份（两次 `id<int>` 调用共用），且不残留类型参数 `T` | `bash selfhost/check-ast.sh` 的 Phase 26 块：`cmp -s` + `grep -cE '^static .*__ct[0-9]+\(.*\);$' = 2` + `grep -cE '^static int id__ct1\(int x\) \{' = 1` + `! grep -E '\bT\b'` 作用于整份生成 C |
| E2 | 正例 `124_generic_struct` 以 `struct Point` 为类型实参，字段访问与返回正确 | 同上，运行输出 `x=3 y=4` |
| E3 | 五条负例各自只产生一条 L26 错误，位置与文案精确匹配；v0.25.0 编译器对同一夹具给出不同结果（证明断言非空转） | `bash selfhost/check-ast.sh` 的 `"fixture|line:col|message"` 表；另用 `~/.local/bin/ct`（v0.25.0）复核旧行为并记录在 §6 |
| E4 | 既有 784 条断言零回归；非泛型 golden 逐字节不变 | `bash selfhost/check-ast.sh` 汇总 `>= 792 passed, 0 failed`；`bash selfhost/check-goldens.sh` / `check-all` 的 `check-goldens: OK` |
| E5 | 11 道硬门禁全绿 | `bash selfhost/check-all.sh` 末行 `check-all: OK (11 hard gates green)` |
| E6 | 五处 `CTC_VERSION` 均为 `0.26.3`；安装后 `ct -v` 输出 `ct v0.26.3` | `grep -n 'CTC_VERSION'` 五处；`bash install.sh` 后 `ct -v` |
| E7 | 文档门禁绿，Phase 26 索引/状态与 roadmap 一致 | `python3 test/docs/check-docs.py` 退出 0；`docs/README.md` design 索引含 phase26 |
| E8 | `ct check` 对五条负例给出同一 L26 文案（解析期诊断共用） | `ct check test/ast/errors/generic_*.ct` 各自非零退出并含对应文案 |

### 1.6 依赖

| 依赖 | 说明 |
| --- | --- |
| Phase 9.x AST 前端 | `Parser.h.ct` / `Expr.h.ct` 的声明与调用解析是唯一插入点 |
| Phase 19 `ct check` | 只在解析期诊断，天然复用；不得为泛型新增独立检查通道 |
| Phase 21 闭包 | 本相不支持闭包环境里的 `T`，无依赖 |
| Phase 25 静态映射 | 本相不支持泛型 trait/recipe，无依赖 |
| L0/L1/L2 | **逻辑冻结**；只允许 `CTC_VERSION` 字符串变更（见 D26-10） |
| `MAX_FUNCS` / `MAX_GENERIC_INSTS` | 新增实例表上限；越界走 `die()`，不得静默截断 |

### 1.7 已知风险（每条带触发信号）

| # | 风险 | 触发信号 | 缓解 |
| --- | --- | --- | --- |
| R1 | 模板体里的局部变量在符号表中仍记为 `T`，发射期类型推导拿到旧类型 | 泛型体内 `T x;` 参与带类型检查的调用时出现误报 | 发射期临时替换 AST 的 `N_DECL/N_PARAM/N_FUNC/N_CAST/N_SIZEOF` 类型字段；用例 123 覆盖 |
| R2 | 发射期「替换—发射—恢复」若恢复不精确，会污染后续函数 | 非泛型 golden 变化或同一模板第二次实例化输出错误 | 按字段保存旧值并逆序恢复；`check-goldens` 零变化作为硬信号 |
| R3 | `<` 在表达式里是小于号，误判为类型实参会吞掉比较表达式 | `a < b` 出现在泛型函数名之后时解析错误 | 只有符号表中 `ntparams==1` 的函数名才进入类型实参分支；负例覆盖 `int x = g < 3;` 不受影响 |
| R4 | `pub` 泛型跨单元调用时找不到实例 | 其他单元链接报未定义 | 声明期直接拒绝 `pub` 泛型（L26-2），不做半成品导出 |
| R5 | 递归实例化导致无限循环或重复定义 | 泛型体调用自身或另一个泛型 | 解析期检测并报 L26-5；缓存键含类型实参，天然去重 |
| R6 | 实例名 `name__ctN` 与用户标识符冲突 | 用户函数恰名 `foo__ct1` | `add_func` 去重键冲突时改用 `name__ctN_x` 重试，最多 8 次；仍冲突则 `die()` |
| R7 | `MAX_NODES` 逼近上限 | 自举构建或 `check-ast` 出现节点容量错误 | 本相不新增函数体节点，只新增实例登记；若撞顶按容量策略先抬 `MAX_GENERIC_INSTS` 不改 `MAX_NODES` |

---

## 2. 语义

### 2.1 语法（D26-1）

```c
/* 声明：返回类型 T，函数名 id，类型参数 T */
T id<T>(T x)
{
    return x;
}

/* 调用：显式类型实参 */
int a = id<int>(42);
char *p = id<char *>("hi");
struct Point q = id<struct Point>(p0);
```

- CT 是 C 风格语法，没有 `fn` 关键字；类型参数写在函数名之后的 `<...>`。
- 只允许一个类型参数；`<T, U>` 报 L26-3。
- 类型参数名必须是 `T_ID`，且在函数签名与函数体内作为「类型」使用。
- 调用必须是 `name<type>(args)`；`name(args)` 报 L26-1。

### 2.2 实例化与命名（D26-5）

- 缓存键：`(模板函数 cname, 类型实参拼写)`。
- 首次遇到某个键时分配实例名 `<模板名>__ct<N>`，`N` 从 1 单调递增；同一键复用。
- 实例函数与模板同 `static` 属性；模板本身不发射。
- 实例顺序由源码扫描顺序决定，保证生成物确定性。

### 2.3 类型替换（D26-6）

只替换**类型位**上的精确拼写：

| 节点 | 字段 | 说明 |
| --- | --- | --- |
| `N_FUNC` | `text` | 返回类型 |
| `N_PARAM` | `text` | 形参类型 |
| `N_DECL` | `text` | 局部声明类型 |
| `N_CAST` | `text` | `(T)x` |
| `N_SIZEOF` | `text` | `sizeof(T)` / `_Alignof(T)`（同一节点，`aux` 区分） |
| `N_OFFSETOF` | `text` | `offsetof(T, f)` |
| `N_VAARG` | `text` | `va_arg(ap, T)` |

不替换 `N_VAR.text2`、`N_ID.text`、`N_CALL.text` 等标识符位；`T` 作值使用会自然解析失败。
不替换 `N_RAW` 内的原始文本；泛型体内出现原始初始化器时按 L26-5 拒绝。
数组维度同样不是替换点：维度里出现类型参数在解析期硬错
`type parameter 'T' cannot be used in an array dimension`（SH-66）；模板名离开 `<type>` 作值
（`int (*p)(int) = id;`）报 L26-1，不发射没有 C 符号的名字。
紧邻 `struct` / `union` / `enum` 的同名 token 是**标签**而不是类型参数，`ct_generic_subst` 以前瞻跳过（D26-13）。

### 2.4 发射（D26-7，B26-1 第二轮修订）

- 原型循环：模板跳过（`ntparams > 0`），按实例表输出 `static` 原型。
- 定义循环：模板跳过；每个实例**复用模板的 `N_FUNC` 节点**，发射期间在发射器上打开「类型替换上下文」
  （`gtparam` / `gtarg` / `gtname`），类型打印点在上下文非空时替换，发射结束即关闭。**不改写任何 AST
  字段**，因此不存在「恢复不精确污染后续函数」的路径。
- 替换点：`emit_type_name_dims`（形参 / 局部声明）、`N_FUNC` 返回类型与函数名、`N_CAST`、`N_SIZEOF`
  （含 `_Alignof`）、`N_OFFSETOF`、`N_VAARG`。
- 头文件导出：本相不支持 `pub` 泛型，因此头文件不出现实例。
- 非泛型代码的发射路径与 v0.25.0 完全一致（上下文为空时所有替换点原样输出），golden 零变化。

### 2.5 诊断（D26-8）

| 码 | 触发 | 文案（精确） |
| --- | --- | --- |
| L26-1 | 调用已知泛型函数但缺 `<type>` | `generic function '<name>' needs a type argument` |
| L26-2 | `pub` 泛型函数 | `generic functions cannot be pub` |
| L26-3 | 类型参数多于 1 个（`<T, U>`） | `only one type parameter is supported` |
| L26-4 | 类型实参为 `void`，或在非泛型上下文把 `T` 当类型实参 | `'<type>' cannot be a generic type argument` |
| L26-5 | 泛型体内递归或嵌套泛型调用 | `recursive generic calls are not supported` |

补充（DOC-67 对齐实测）：

- 空列表 `<>` 不由 L26-3 接管，类型参数解析先报 `expected a type parameter name`（§6.2 第 4 条）。
- 函数指针类型实参（`id<int (*)(int)>`）由类型解析先拒绝，文案是 `expected a name in the function-pointer declarator`；
  数组类型实参（`id<int[3]>`）报 `expected '>' after the generic type argument`。两者都不伪装成 L26-4。
- `T` 作类型实参只在**非泛型上下文**得到 L26-4；模板体内再写 `id<T>(...)` 先命中 L26-5（D26-9）。
- `_Generic(...)` 选择体原样透传，模板体内出现类型参数报 `type parameter cannot be used inside _Generic`（硬错，不发射）。

所有诊断走 `ct_sem_error(line, col, msg, path)`，带 `file:line:col`；`ct check` 与编译路径一致。

> **P34 覆盖（Phase 34，未发版）**：L26-2 已解禁——`pub T name<T>(...)` 合法，模板体必须写在 `.h.ct` 中，
> 消费方为每个 `(模板, 具体类型)` 发 `static` 实例（实例名沿用 `<name>__ct<N>`，按 owner 各自从 1 编号）。
> §2.5 的表格行保留 P26 当时的状态作为历史；L26-1 / L26-3–L26-5 不变。变更面与回滚方式见
> [phase34-draft.md](phase34-draft.md) §1.4；`generic_pub` 夹具已转正为 `test/ast/228_pub_generic_fn/`。

### 2.6 类型操作数的解析分支（v0.26.2 根因修复，D26-14）

v0.26.1 的缺陷不是某个算子漏了拦截，而是**类型名判定只长在括号分支**：`parse_unary` 里
`if (paren && next_is_type_name())` 之后，无括号形态直接落回表达式路径，`sizeof T` 的 `T` 成为
`N_VAR` 并被原样发射。v0.26.2 把“**当前** token 是否为类型名”抽成 `tok_is_type_name()`
（规则与 `next_is_type_name()` 完全一致，只是不前移游标），三算子统一先问它；无括号类型操作数经
`parse_type` 读取，并由 `type_no_ptr` 截止在一个类型名。

| 书写形态 | 判定分支 | 节点 / `aux` | 发射 | 替换点 |
| --- | --- | --- | --- | --- |
| `sizeof(type)` | `(` 且 `next_is_type_name()` | `N_SIZEOF`，`text`=类型，`aux=1` | `sizeof(type)` | `emit_gsub_type` |
| `sizeof T` / `sizeof struct S` | 无括号：`tok_is_type_name()` 为真（模板体内 `T` 命中类型参数优先规则） | `N_SIZEOF`，`text`=类型，`aux=1`，`type_no_ptr=1` | `sizeof(type)` | `emit_gsub_type` |
| `sizeof expr` | 前两条都不命中 | `N_SIZEOF`，`a`=表达式，`aux=0` | `sizeof(expr)` | 无（值表达式） |
| `_Alignof(type)` / `_Alignof T` | 与 `sizeof` 的两条类型分支共用 | `N_SIZEOF`，`aux=2` | `_Alignof(type)` | `emit_gsub_type` |
| `_Alignof expr` | 三条类型分支都不命中 | — | 硬错 `_Alignof needs a type in parentheses` | — |
| `alignof(type)` / `alignof T` | 与 `sizeof` 的两条类型分支共用 | `N_SIZEOF`，`aux=4` | `alignof(type)` | `emit_gsub_type` |
| `alignof expr` | 类型分支不命中后的表达式兜底 | `N_SIZEOF`，`aux=3` | `alignof(expr)` | 无 |
| `_Atomic(type)` / `_Atomic type` | `parse_type` 内的限定符分支；`tok_is_type_name()` 把 `_Atomic(...)` 整串视为类型名 | 类型拼写进 `text` | 原样（`_Atomic(type)`） | 外层类型文本替换 |
| `offsetof(type, field)` | 独立内建分支（`offsetof_ahead()` 要求 `(`），`parse_type` 直接读第一参 | `N_OFFSETOF`，`text`=类型，`text2`=字段 | `offsetof(type, field)` | `emit_gsub_type` |
| `(type)expr` | `(` 且 `next_is_type_name()` | `N_CAST`，`text`=类型 | `(type)(expr)` | `emit_gsub_type` |
| `va_arg(ap, type)` | 调用解析的专用分支 | `N_VAARG`，`text`=类型 | `va_arg(ap, type)` | `emit_gsub_type` |

两条共同语义：

1. `tok_is_type_name()` 与 `next_is_type_name()` 共用同一套规则：模板体内类型参数优先于 ALL_CAPS 宏规则；
   `_Atomic(...)` 整串；类型词 / 已解析类型 / 仅头文件声明的类型名（如 `time_t`）。因此 cast 的括号路径与
   `sizeof` 的无括号路径不再各写一套判定。
2. `type_no_ptr` 只在无括号类型操作数期间置位：`parse_type` 此时不吃 `*`、不进入函数指针声明符，于是
   `sizeof T * 2` 读作 `(sizeof T) * 2`，而不是 `sizeof(T *)`。

### 2.7 标识符解析路径与类型参数（SH-64 收口证据）

同一个兜底漏了三次：`sizeof(T)`（SH-62 首轮）、`sizeof T`（SH-62 重开）、值位置（SH-64）。下面把
**所有会经过标识符 / 类型名解析的路径**逐条列出，说明遇到当前模板的类型参数 `T` 时走哪条分支、行为是什么。
`parse_primary` 读到 `T_ID` 后的统一入口检查（SH-64）覆盖第 8 组的全部出口。

| # | 路径 / 书写形态 | 解析入口 | 遇到类型参数 `T` |
| --- | --- | --- | --- |
| 1 | 声明说明符、返回类型、形参、局部声明 | `parse_type` → `Symbols` 类型层 | 类型参数优先，实例化时替换为实参类型 |
| 2 | `sizeof T` / `_Alignof T` / `alignof(T)` | `parse_unary` 的类型操作数分支（§2.6） | 按类型读取并替换 |
| 3 | `sizeof(T)` / `_Alignof(T)` / `alignof(T)` 括号形态 | 同上，`next_is_type_name()` 分支 | 按类型读取并替换 |
| 4 | `(T)expr` 强制转换 | `parse_unary` 的 cast 分支（`next_is_type_name()`） | 按类型读取并替换 |
| 5 | `offsetof(T, field)` | 内建分支，第一参 `parse_type` | 替换类型，字段名保留 |
| 6 | `va_arg(ap, T)` | 内建分支，第二参 `parse_type` | 替换类型 |
| 7 | `_Generic(x, T: 1, …)` / `_Generic(x, struct T: 1, …)` | `_Generic` 原样透传分支 | 裸 `T` 硬错；`struct`/`union`/`enum` 后的标签放行（SH-62 P2） |
| 8 | 值位置标识符：`return T;`、`h(T)`、`sizeof T * T`、`sizeof T + T`、`T(0)`、`T.member`、`T::x`、`p = T`、`p = &T` | `parse_primary` 的 `T_ID` 分支（泛型实例 `name<…>`、限定名 `::`、调用 `(`、裸函数值、ALL_CAPS 宏兜底、`fnval_ok`、最终未声明错误） | **SH-64 修复前**：ALL_CAPS 兜底当宏常量、`fnval_ok` 当库函数名，原样发射裸 `T`，退出 0；**修复后**：分支入口统一硬错 `type parameter 'T' cannot be used as a value`（`file:line:col: error:` 与其他未声明标识符同格式） |
| 9 | `struct T` / `union T` / `enum T` | `parse_type` 的标签分支 | 标签名，不替换（SH-63） |
| 10 | `.` / `->` 后的成员名、`goto` 标签、字段声明名 | 成员 / 标签 / 声明解析，不经过 `parse_primary` | 是用户命名的值 / 标签，合法保留 |
| 11 | 真正的未声明标识符 | `parse_primary` 的最终兜底 | `use of an undeclared variable`；类型参数在值位置使用同一条 `fail` 通道，位置与格式一致 |

这张表的结论：类型参数只允许出现在**类型操作数**（第 1–6 组）和标签（第 7、9 组）上；一旦进入
标识符的值解析（第 8 组），无论后续是调用、限定名、宏兜底还是库函数回退，都必须先被第 8 组的入口守卫拒绝。
守卫放在 `parse_primary` 的 `T_ID` 分支入口，而不是逐个出口打补丁，正是为了避免第四次漏网。

**防线覆盖范围与残留盲区**（`tparam_residue()`，v0.26.3 起只扫实例体）：

| 项 | 状态 |
| --- | --- |
| `test/ast/*/prog.ct` 的编译产物，且文件内确有泛型声明 | ✅ 扫描（从夹具自身声明提取类型参数名，只读 `<name>__ctN` 函数体） |
| 非模板函数里的同名局部变量（`int T = 5;`） | ✅ 不误报（v0.26.2 的整文件扫描返回 `T(2)`，现为空；129 正例固定该行为） |
| 合法 `struct` / `union` / `enum T` 标签 | ✅ 扣掉（126） |
| `.h.ct` 的产物 | ✅ 断言不含任何 `<name>__ctN` 实例定义（v0.26.4 / TEST-18；`.h` 只携带类型。P34 起 `pub` 泛型模板体在 `.h.ct`，实例只由消费方 `.c` 发） |
| `test/ast/*/` 的 `build` 产物（目录含 `.m.ct` 或 `.h.ct`） | ✅ 每个 `*.c` 都过同一扫描，类型参数名从**目录下全部 `.ct`** 提取（v0.26.4 / TEST-18；`130_generic_build_mode` 固定单文件泛型，`131_generic_cross_unit` 固定「泛型只声明在导入单元」的形态） |
| `test/ast/errors/**`（本就不产生产物）、`test/modules/**`（`p34_pub_generic` / `p34_pub_bound` 之外的夹具）与 `examples/**` 的构建产物、语料 | ❌ 不扫（残余名目：这些位置目前没有泛型夹具。触发条件是其中新增泛型夹具，此时必须在同一改动里补扫描钩子；P34 S3a 已按此规则把两个 `pub` 泛型模块夹具接入 modules 段。解析期守卫 D26-14 / D26-15 与实例体扫描互补，前者覆盖全部形态，后者兜住发射期回归） |
| 泛型声明与实例调用分处两个单元（例如 `extra/lib.h.ct` 内 `static T twice<T>`，由同一单元内的 `pub` 函数实例化） | ✅ 扫描（实例体落在该单元的 `.c` 产物，`-o` 目录下扁平化为 `lib.c`；类型参数名从该 `.h.ct` 读出，入口 `prog.ct` 即使没有任何泛型声明也不影响）。P34 起 `pub` 泛型模板体写在 `.h.ct`，实例由消费方触发；这条路径由 modules 段的 `p34_pub_generic` / `p34_pub_bound` 钩子覆盖（TEST-18） |
| 扫描器的书写形态假设 | ⚠️ 已知限制：实例体提取要求 `__ctN(` 与 `{` 同行（K&R），类型参数声明要求 `<T>` 在行首；发射器当前恒为这两种形态，自检也只覆盖 K&R。**触发信号**：发射器改成分行花括号（Allman）或缩进声明时，扫描会静默失效——那时必须同时把 `tparam_residue` 的提取改成按花括号深度匹配，并给自检加一份 Allman 样本 |

---

## 3. 切片

| 切片 | 内容 | 主要文件 | 完成信号 |
| --- | --- | --- | --- |
| 26.1 | 声明解析：`<T>`、`Fn.ntparams/tparam`、`pub`/多参数诊断、模板标记 | `Parser.h.ct`、`Symbols.h.ct` | 模板可解析且不发射；负例 9/10 红 |
| 26.2 | 调用解析：`name<type>(...)`、实例表、缓存、实参检查、递归诊断 | `Expr.h.ct`、`Symbols.h.ct` | `id<int>(1)` 生成实例登记；负例 8/11/12 红 |
| 26.3 | 发射：实例原型/定义、替换上下文、跳过模板 | `Emitter.h.ct` | 生成 C 含 `id__ct1`，无残留 `T` |
| 26.4 | 夹具与门禁：正例 123/124、负例五条、`check-ast.sh` 断言、旧编译器对照 | `test/ast/**`、`check-ast.sh` | `check-ast` ≥ 792 passed |
| 26.5 | 文档、版本、发布：语言规范/教程/roadmap/AGENTS、五处版本、tag | `docs/**`、`AGENTS.md`、五处版本文件 | `check-all` 绿、tag 推送 |

切片 26.1–26.3 不单独提交；26.4 与 26.1–26.3 合并为一个功能提交（避免中间提交无法构建）；
26.5 单独提交；文档漂移/issue 若有则单独提交。

---

## 4. 决策表（D26-nn）

| 编号 | 决策 | 理由 | 生效范围 |
| --- | --- | --- | --- |
| D26-1 | 语法 `T name<T>(...)` / `name<type>(...)` | 复用 C 风格声明与现有 `<`/`>` 记号，不新增关键字；与 CT 无 `fn` 的事实一致 | 本相全部泛型函数 |
| D26-2 | 单类型参数、函数形态 | 多参数会引入 `>>` 词法与组合实例化；结构体/联合需要布局单态化 | 本相 |
| D26-3 | 只做显式实例化 | 推导需要双向类型检查；显式实例化让实例集合在解析期确定 | 本相 |
| D26-4 | 泛型函数必须 `static`（或默认文件内），拒绝 `pub` | 跨单元需要头文件导出实例；本相不做半成品 | 本相 |
| D26-5 | 实例名 `<name>__ct<N>`，按首次使用顺序 | 确定性、可 grep、避免类型拼写进入 C 标识符 | 本相 |
| D26-6 | 只替换类型位精确拼写 | 避免误伤同名值标识符；`T` 作值自然解析失败 | 本相 |
| D26-7 | 发射期类型替换上下文（不写 AST） | 避免深拷贝整棵 AST；也避免「替换—恢复」的恢复不精确风险。实例复用模板 `N_FUNC`，发射器持 `gtparam/gtarg/gtname`，类型打印点按上下文替换（B26-1 第二轮） | 本相 |
| D26-8 | 五条 L26 诊断，解析期发出 | `ct check` 与编译路径天然一致 | 本相 |
| D26-9 | 泛型体内禁止递归/嵌套泛型调用 | 避免实例化循环与缓存键递归 | 本相 |
| D26-10 | L0/L1/L2 只改 `CTC_VERSION`，不改逻辑 | 用户要求冻结；版本串是发布必需 | 本相发布提交 |
| D26-11 | 用户已授权代决 | 用户明确「不参与、自己裁决」，本表无待拍板项 | 本相 |
| D26-12 | SH-62 的四处类型位置走**真实现替换**（不硬错误） | B26-2 两轮 `upheld`：复用既有替换点，兑现 S4；硬错误会让 `(T)` 与 `sizeof` 类用法失去意义 | 模板体内的 `sizeof(T)` / `_Alignof(T)` / `offsetof(T, …)` / `(T)` |
| D26-13 | `ct_generic_subst` 跳过紧邻 `struct` / `union` / `enum` 的同名 token | SH-63：`struct T` 是标签名，不是类型参数；不加前瞻会把 `struct T` 改成 `struct int` | 所有实例的签名与类型打印 |
| D26-14 | 类型操作数的类型名判定统一为 `tok_is_type_name()`（当前 token），`sizeof` / `_Alignof` / `alignof` 的无括号形态走 `parse_type`；`type_no_ptr` 截止一个类型名 | SH-62 重开的根因是判定只长在 `(type)` 分支；逐算子补拦截会在下一种无括号形态再漏。把判定抽成谓词是同一路径上的唯一收口点 | 三算子无括号形态、`sizeof T * 2`，以及共享该谓词的 cast / `_Atomic` / `offsetof` |
| D26-15 | `parse_primary` 的 `T_ID` 分支入口守卫：标识符等于当前模板类型参数即硬错 `type parameter 'T' cannot be used as a value` | SH-64 是同一兜底第三次漏网（前两次是 `sizeof(T)` / `sizeof T`）；逐个出口补丁会在调用、限定名或 `fnval_ok` 上复发。入口守卫一次覆盖全部标识符解析出口 | 4 个值位置负例、`ct check` 同文案，以及 §2.7 的全路径枚举 |

---

## 5. battle 记录

### B26-1 · 单态化实现位置

| 席 | 主张 |
| --- | --- |
| 主张 | **emitter 期临时替换 AST 类型字段**（D26-7） |
| 反对 | **parser 期深拷贝 N_FUNC 并重建符号表** |
| 证据 | E1：`emit_unit_body` 已在 1399–1406 按 `N_FUNC` 循环，插入实例循环的 diff 最小；E2：深拷贝需要复制 `a/b/c/d/next` 与三个 text 字段，且 `Var` 表仍指向模板作用域，需重建；E3：源级重解析会重入 `parse_func`，clobber `cur_func/ret_type/scopes`（`Parser.h.ct:1120-1140`）；E4：替换点仅 6 种节点（§2.3），可枚举；E5：恢复用旧值栈可避免 `int → T` 反向替换误伤具体类型。 |
| 裁判（EDITOR） | **upheld**：采用 emitter 期临时替换。生效范围：Phase 26 全部实例发射；若 R2/R1 触发（golden 变化或类型推导误报），退回深拷贝方案并重开 battle。 |

三轮内无新增证据，反对席未能证明深拷贝在 `Var` 作用域重建上更省；判决生效并落到 D26-7。

#### B26-1 第二轮（实现中期，按 §7 重新举证）

| 席 | 主张 |
| --- | --- |
| 主张（改提） | **emitter 期类型替换上下文**：实例复用模板 `N_FUNC`，发射器持 `gtparam/gtarg/gtname`，六个类型打印点按上下文替换；AST 只读 |
| 反对（原方案） | 维持「替换—发射—恢复」：发射前把 6 类节点的 `text` 压栈改写，发射后逆序恢复 |
| 证据 | E1：替换—恢复的子树遍历必须按 kind 区分槽位——`N_FUNC.c` 是 `variadic` 标量、`N_SWITCH.c` 是 `case_hi`、`N_STRUCT/N_TYPEDEF.d` 是 `is_pub`；盲递归会把标量当节点索引，这是恢复污染之外的第二类缺陷（`Stmt.h.ct:1522`、`Parser.h.ct` 的 `N_FUNC.c`）。E2：上下文方案只加 3 个 `char[160]` 与 `emit_gsub_type`（`Emitter.h.ct:257-264`），改 6 个打印点，AST 零写入。E3：可证伪预测——若上下文正确，`test/ast/123_generic_identity` 生成物应含 `id__ct1/id__ct2`、`\bT\b` 计数为 0、运行输出逐字节等于期望；实跑通过（见 §6）。E4：成本上，替换—恢复还要子树遍历 + 保存栈 + 槽位分支，约 +80 行且难以单测；上下文方案 +3 字段 +1 helper。E5（最强反方）：上下文方案让「模板定义」无法单独发射——但本相模板本就不发射，且实例入口 `emit_generic_defs` 复用同一 `emit_node`，反方不成立。 |
| 裁判（EDITOR） | **upheld**：D26-7 修订为「发射期类型替换上下文」。生效范围：Phase 26 全部实例发射；R1/R2 因不写 AST 而不再触发，转记为「已规避」。 |

第二轮只有一次举证，反对席未能提出「上下文方案会改变非泛型发射路径」的反例；golden 零变化即为该反驳的否证。

### B26-2 · SH-62 四处类型位置：真替换 vs 硬错误

**案由**：SH-62 要求消除 `sizeof(T)`、`_Alignof(T)`、`offsetof(T, …)`、`(T)` 的静默坏产物。
方案 A（真实现替换）与方案 B（四处改硬错误）都能过门禁，成本差 < 2 倍，按方法论 §7 / B-4 立案。

#### 第一轮

| 席 | 主张 |
| --- | --- |
| 主张席（SCRIBE，方案 A） | 在模板体内把这四处识别为**类型位**：`next_is_type_name` 认 `T`，`parse_type` 产出 `T`，`offsetof` 允许未解析的 `T`；发射期沿用既有替换点，产出 `sizeof(int)` / `_Alignof(int)` / `offsetof(struct Pair, y)` / `(int)` |
| 反对席（ARCH，方案 B） | 四处一律编译期硬错误（新增 L26-6「type parameter cannot be used in this position」），彻底堵死静默坏产物，且不需要在发射器里新增任何路径 |
| 证据席（VERIFY） | E1 复现（v0.26.0 基线）：`sizeof(T)` 退出 0 且生成物含 `sizeof(T)`，`cc` 报 `'T' undeclared`；`_Alignof(T)` 报 `_Alignof needs a type in parentheses`；`offsetof(T, y)` 报 `offsetof needs a struct type`；`(T)v` 报 `unexpected token`。E2 代码锚点：`Emitter.h.ct:3016-3039` 的 `N_SIZEOF`/`N_OFFSETOF` 与 `N_CAST` 已经在做 `emit_gsub_type`，缺的只是**解析期把 `T` 当类型**；`Expr.h.ct:182-185` 已有 `in_generic` 但没有类型参数拼写；`Expr.h.ct:1684-1694` 的 ALL_CAPS 兜底把 `T` 变成 `N_RAW`。E3 可证伪预测（方案 A）：四处分别产出 `sizeof(int)`、`_Alignof(int)`、`offsetof(struct Pair, y)`、`(int)`，函数段 `\bT\b` 计数为 0。E4 成本：A 改 2 个文件约 40 行（含 SH-63 的 `struct T` 前瞻）+ 2 个夹具；B 改 1 个文件约 25 行守卫 + 4 处文档删改，**比值 < 2**。E5（最强反方自检）：A 无法在解析期校验 `offsetof(T, field)` 的字段存在性；但 `ct` 对普通成员的 `p->field` 本来也不校验字段，字段错误留给 `cc`，与「类型名不得未声明」这一退出判据不冲突。 |
| 裁判席（EDITOR） | **upheld（方案 A）**。理由：A 兑现 S4 的承诺且复用既有 6 个替换点，新增面仅在解析期识别 `T`；B 会把 `(T)` 这一泛型体里的规范窄化写法直接判死，并让 S4 的「`sizeof` 类用法」成为空话。生效范围：**仅模板体内**的这四处；非泛型代码路径零变化；若日后这四处再次出现「退出 0 但生成物含未声明类型名」，立即退回 B 并重开本 battle。 |

#### 第二轮（新增证据）

| 席 | 主张 |
| --- | --- |
| 主张席 | 补充预测：`(T)` 必须能用于函数实参（`absorb((T)v)`），否则 TEST-17 的「调用实参」类型位置无从落夹具 |
| 反对席 | 仍主张 B：硬错误至少能保证「永不静默」，A 依赖夹具覆盖，覆盖不到就回归 |
| 证据席 | E1：在 v0.26.0 基线上，`printf("%d", (int)sizeof(T))` 的生成物第 12 行为 `(int)(sizeof(T))`，`cc` 直接报 `'T' undeclared`——静默通道只有 `sizeof` 一条，其余三条已硬失败但文案与类型位置无关。E2：方案 A 的四处都落在既有 `emit_gsub_type` 调用上，不新增打印点；测试用 `test/ast/125_generic_type_positions` 一次覆盖四形态 + 局部声明 + 调用实参，`grep -E '\bT\b'` 作为总闸。E3：若 A 任一形态产出错拼写，125 的 `cmp` 或 `grep` 必红，且基线编译器在同一夹具上必红（红证先做）。E4：A 的总改动经实测为 3 个文件 40 行（`Expr.h.ct` 16、`Parser.h.ct` 2、`Symbols.h.ct` 22），B 为 25 行守卫 + 文档删改，仍在 2 倍内但 A 多出的 15 行买回了 S4 的完整性。E5（最强反方）：A 可能让 `T` 在**非泛型**位置被误认——由 `in_generic && strcmp(tok, tparam)` 双条件阻断，且 123/124 与全量 golden 作为否证。 |
| 裁判席（EDITOR） | **upheld（方案 A），维持第一轮判决**。第二轮未出现推翻 A 的新证据；反对席的「覆盖不到就回归」由 125/126 与红证流程吸收。判决落 D26-12，范围不变。 |

两轮共 10 条举证，反对席未能证明 B 在「零静默」上严格优于 A + 夹具（`_Alignof`/`offsetof`/cast 的静默通道本就不存在）。

---

## 6. as-built 记录

### 6.1 切片落地

| 切片 | 落地 |
| --- | --- |
| 26.1 声明解析 | `Parser.h.ct`：`T name<T>(...)` 解析、`pub` / 多参数 / 无函数体拒绝、`Fn.ntparams/tparam/body`、`N_FUNC.text3` 模板标记；`Symbols.h.ct`：`GenericInst`、`Symbols.ginsts/nginsts`、`MAX_GENERIC_INSTS`、`ct_generic_subst` |
| 26.2 调用解析 | `Expr.h.ct`：`name<type>(...)`、`generic_instance`（缓存 + 命名 + 签名替换）、L26-1 / L26-4 / L26-5 |
| 26.3 发射 | `Emitter.h.ct`：`gtparam/gtarg/gtname` 上下文、`emit_gsub_type`、`emit_generic_defs`、模板跳过、六个类型打印点替换 |
| 26.4 夹具与门禁 | `test/ast/123/124`、5 个负例、`check-ast.sh` 的 Phase 26 块（E1 / E2 / E3 / E8） |
| 26.5 文档与发布 | language-spec §4.48、tutorial §10.5、roadmap v0.26.0、AGENTS、docs/README、五处版本、tag |

### 6.2 实现与立项的偏差（逐条登记）

1. D26-7 由「替换—发射—恢复」改为「发射期类型替换上下文」（B26-1 第二轮 `upheld`）：不写 AST，R1/R2 直接规避。
2. D2 的 `add_generic_inst` 未单独成方法，逻辑内联在 `Expr::generic_instance`；`GenericInst` 表与路径不变。
3. 泛型一律强制 `static`：即使用户未写 `static`，模板行 `is_static=1`、`N_FUNC.aux=1`，实例因此不导出（D26-4）。
4. L26-3 只覆盖「多参数」；空列表 `<>` 由类型参数解析报 `expected a type parameter name`，不走 L26-3。
5. 「数组作类型实参」不在解析期显式识别（`id<int[3]>` 会在 `[` 处报 `expected '>' after the generic type argument`）；L26-4 夹具覆盖 `void`。
6. L26-5 只拦「解析模板体时遇到的泛型调用」；模板自递归（指向尚未 `add_func` 的自己）会落到普通未声明调用诊断。夹具用「嵌套调用」形态。
7. `N_RAW` 原始初始化器内的 `T` 不替换（§2.3 已声明）；本相夹具不覆盖。
8. **v0.26.1（SH-62）**：v0.26.0 的 §2.3/§2.4 把 `N_CAST` / `N_SIZEOF` / `N_OFFSETOF` 列为替换点，但解析器从不给 `T` 生成这三类节点——`sizeof(T)` 落成 `N_RAW`（退出 0 的坏产物），`(T)` / `_Alignof(T)` / `offsetof(T, …)` 在解析期硬失败。修复轮按 B26-2 判决采用**方案 A**（真实现替换）：模板体内把 `T` 识别为类型位，使 §2.3 的替换点从死代码变为活路径（D26-12）。同时补 `va_arg(ap, T)`——它是同一根因下的第五条类型位，v0.26.0 从未在文档里承诺，修复轮一并纳入以避免再留一条静默通道。`_Generic(...)` 的选择体是原样透传、无法在发射期安全替换，模板体内出现类型参数时改为解析期硬错 `type parameter cannot be used inside _Generic`——它仍属「本相不支持」，但不再是退出 0 的坏产物。
9. **v0.26.1（SH-63）**：`ct_generic_subst` 以前只按词边界匹配，`struct T` 里的标签 `T` 被替换成 `struct int`。现对紧邻 `struct` / `union` / `enum` 的同名 token 前瞻跳过（D26-13）；裸返回类型 `T` 被同一标签解析吞掉时，`Parser` 在拿到 `<T>` 后按类型参数改写（`last_bare_tag`）。
10. **v0.26.1（TEST-17）**：123 的模板体加入第二次 `id<int>` 调用以证明去重；新增 `125_generic_type_positions`（局部声明 / cast / `sizeof` / `_Alignof` / `offsetof` / 调用实参 / `va_arg`）、`126_generic_struct_tag`（`struct T` 标签）、`127_generic_name_retry`（R6 冲突回退）与 `generic_too_many`（第 65 个实例硬错）。新断言先在 v0.26.0 基线上变红，再在修复后的编译器上转绿。
11. **v0.26.1（DOC-67）**：§2.5 的 L26-3 / L26-4 与函数指针 / 数组 / `T` 作实参的文案，按实测改写；E1 明确作用域是**整份生成 C**，实例计数改为精确 `-eq`；AGENTS 的版本 bump 清单改为指向 roadmap 版本记录。
12. **v0.26.2（SH-62 重开，根因修复）**：类型操作数的类型名判定只长在括号分支——`parse_unary` 对
    `sizeof` 只做 `if (paren && next_is_type_name())`，无括号形态落回表达式路径，`T` 成为 `N_VAR` 原样发射。
    现抽出 `tok_is_type_name()`（判当前 token，规则与前瞻版一致），`sizeof` / `_Alignof` / `alignof` 三算子
    统一先问当前 token，无括号类型操作数走 `parse_type`；`type_no_ptr` 使其只吃一个类型名，保住
    `sizeof T * 2` 的乘法。分支矩阵见 §2.6。`_Atomic` / `offsetof` / cast / `va_arg` 原本已在自己的类型解析
    分支上，未改判定，只共享同一谓词。同轮修 P2：`_Generic(x, struct T: 1, …)` 的选择器里紧邻
    `struct`/`union`/`enum` 的是标签，放行；裸类型参数仍硬错。
13. **v0.26.2（TEST-17 重开，系统性防线）**：`check-ast.sh` 的主夹具循环新增 `tparam_residue()`——从夹具
    自身声明提取类型参数名，扫描发射产物，扣掉合法的 `struct|union|enum <T>` 标签用法，残留即 `FAIL`。
    它不替代根因修复，而是让下一处同类漏网无法以退出 0 静默通过。红证见 §6.3.1。
14. **v0.26.3（SH-64，第三次漏网）**：类型参数用在**值位置**时仍退出 0 并发射裸 `T`——`parse_primary` 的
    `T_ID` 兜底在 `in_generic_tparam` 判定之前把全大写名当宏常量（`fnval_ok` 又会当库函数名）。修复在每个
    标识符解析出口的**共同入口**加守卫：当前标识符等于模板类型参数即硬错
    `type parameter 'T' cannot be used as a value`，调用、限定名、泛型实例、宏兜底、库函数回退全部被同一
    守卫覆盖（路径枚举见 §2.7）。同轮修防线假阳：`tparam_residue()` 只扫描实例函数体（`<name>__ctN`），
    不再把用户在非模板函数里写的 `int T = 5;` 当泄漏；覆盖范围与盲区见 §2.7 / TEST-18。
15. **v0.26.3（TEST-18，防线覆盖登记）**：`tparam_residue()` 覆盖 `test/ast/*/prog.ct` 的编译产物；`.h`
    产物、`test/ast/errors/`、module 构建产物与 `test/cases` / `examples` 语料仍未扫描。扩展需要把扫描挂到
    `build` 与 module 产物路径并跨单元匹配模板声明，成本高于本轮，登记为 TEST-18 并写明代价。

### 6.3 门禁实跑（2026-11-09，v0.26.1 修复轮）

- `bash selfhost/check-ast.sh` → `== summary: 815 passed, 0 failed ==`，`EXIT=0`。v0.26.0 收口时为 803；本轮 +12：`p26_generic_type_positions`、`p26_generic_struct_tag`、`p26_generic_name_retry`、`p26_diag_generic_too_many`、`p26_check_generic_too_many`、`p26_diag_generic_generic_selector`、`p26_check_generic_generic_selector` 共 7 条，123 的去重断言收紧 4 条（精确实例原型计数、`id__ct1` 定义恰 1 份、`b = id__ct1(7)` 等），负例总扫描对新增 `.ct` 计 1 条。
- `bash selfhost/check-all.sh` → `check-all: OK (11 hard gates green)`，`EXIT=0`。同一日志内的分项原始行：
  `== summary: 118 passed, 0 failed ==`（bootstrap）、`check-goldens: OK (no regression, and the self-hosted rebuild agrees)`、
  `check-archive: OK (no regression)`、`== summary: 82 passed, 0 failed ==`（包管理）、
  `== summary: 815 passed, 0 failed ==`（check-ast）、`check-warnings: 248 ok, 0 failed`、
  `check-semantics: OK (23 assertions)`、`check-docs: OK (863 relative links in 173 files, v0.26.1, 11 hard gates, 10 phase status, 3 适用版本 header(s))`、
  `== summary: 20 pass, 0 new, 0 pending, 0 regression ==`（acceptance probes）。

### 6.3.1 红证（v0.26.0 基线编译器，修复前）

用 tag `v0.26.0` 的源码树编出的 `ct-ast`（`ct-ast v0.26.0`）跑同一批夹具：

| 命令 | v0.26.0 结果 | v0.26.1 结果 |
| --- | --- | --- |
| `ct-ast test/ast/125_generic_type_positions/prog.ct -o /tmp/red125.c` | `prog.ct:21:12: error: unexpected token`，退出 1 | 退出 0，生成 C 含 `sizeof(int)` / `_Alignof(int)` / `offsetof(struct Pair, y)` / `va_arg(ap, int)` / `(int)(a)`，运行输出 `4 4 4 4 5` |
| `ct-ast test/ast/126_generic_struct_tag/prog.ct -o /tmp/red126.c` | **退出 0**，发射 `static struct int getv__ct1(struct int *);`，`cc` 拒绝 | 退出 0，发射 `static int getv__ct1(struct T *);`，运行输出 `7` |
| `sizeof(T)` 探针（`return sizeof(T);`） | **退出 0**，生成物残留 `sizeof(T)`，`cc` 报 `'T' undeclared` | 生成 `return sizeof(int);`，运行输出 `4` |
| `_Generic(x, T: 1, default: 0)` 探针 | **退出 0**，生成物残留 `_Generic ( x , T : 1 , default : 0 )`，`cc` 报 `unknown type name 'T'` | 解析期硬错 `type parameter cannot be used inside _Generic`，退出 1 |
| `ct-ast test/ast/123_generic_identity/prog.ct` | 退出 0，`49 hi`，实例原型 2 条 | 同左（去重断言在两侧都绿，新增价值是把它钉死） |

即：新增断言在缺陷存在时**确实变红**（125 解析失败、126 静默坏产物），修复后转绿。

v0.26.2 修复轮用 tag `v0.26.1` 的源码树编出的 `ct-ast`（`ct-ast v0.26.1`）逐形态复跑：

| 探针（同一源码分别喂两个编译器） | v0.26.1 结果 | v0.26.2 结果 |
| --- | --- | --- |
| `int f<T>(T x) { return (int)sizeof T; }` | **退出 0**，发射 `return (int)(sizeof(T));`，`cc` 报 `'T' undeclared` | 发射 `return (int)(sizeof(int));` |
| `(int)_Alignof T` | 退出 1：`4:26: error: _Alignof needs a type in parentheses` | 发射 `_Alignof(int)` |
| `(int)alignof(T)`（`stdalign.h`） | **退出 0**，发射 `alignof(T)`，`cc` 报 `'T' undeclared` | 发射 `alignof(int)` |
| `(int)sizeof T * 2` | **退出 0**，发射 `((int)(sizeof(T)) * 2)` | 发射 `((int)(sizeof(int)) * 2)` |
| `(int)(sizeof(T) + sizeof T)` | **退出 0**，发射 `(sizeof(int) + sizeof(T))`（半边漏） | 发射 `(sizeof(int) + sizeof(int))` |
| `_Generic(x, struct T: 1, default: 0)`（`struct T` 已声明） | 退出 1：`4:31: error: type parameter cannot be used inside _Generic`（P2 过拒） | 退出 0，发射 `_Generic ( x , struct T : 1 , default : 0 )` |

**防线的红证**：把 v0.26.1 的坏产物 `sz261.c`（含 `return (int)(sizeof(T));`）直接喂给 `tparam_residue()`：

```
v0.26.1 bad artefact sz261.c:
static int nogrow__ct1(int x) {
    return (int)(sizeof(T));
}
scan result: [T(1) ]
```

同一函数在 v0.26.2 的 123–128 产物上返回空（126 的 7 处 `struct T` 标签全部被扣掉）。即：即使根因修复
再次漏掉某个形态，门禁也会在产物层变红，而不是等到 `cc`。

v0.26.3（SH-64）的值位置四形态，用同一份源码分别喂 `v0.26.2` 基线与修复后的编译器：

| 负例夹具 | v0.26.2 结果 | v0.26.3 结果 |
| --- | --- | --- |
| `return T;` | **退出 0**，发射 `return T;`，`cc` 报 `'T' undeclared` | 退出 1：`6:13: error: type parameter 'T' cannot be used as a value` |
| `return h(T);` | **退出 0**，发射 `return h(T);` | 退出 1：`11:15: … cannot be used as a value` |
| `sizeof T * T` | **退出 0**，发射 `return (int)((sizeof(int) * T));` | 退出 1：`6:30: … cannot be used as a value` |
| `sizeof T + T` | **退出 0**，发射 `return (int)((sizeof(int) + T));` | 退出 1：`6:30: … cannot be used as a value` |

**防线假阳的红/绿对照**（同一扫描函数）：含 `int T = 5;` 的非模板函数探针，整文件扫描返回 `T(2)`
（假阳）；改为只扫实例函数体后返回空。同一改动仍对 v0.26.1 的坏产物 `sz261.c` 返回 `T(1)`，对
123–129 的 v0.26.3 产物返回空。覆盖范围与残留盲区见 §2.7 与 TEST-18。

### 6.3.2 安装复核（v0.26.1）

`grep -n 'CTC_VERSION'` 五处均为 `0.26.1`；`ct-tour` 的分项日志可见 `ct -v` 输出 `ct v0.26.1`。

### 6.3.3 门禁实跑（`v0.26.2`，2026-11-09）

```console
$ bash selfhost/check-ast.sh
== summary: 817 passed, 0 failed ==            # v0.26.1: 815

$ bash selfhost/check-all.sh
== summary: 118 passed, 0 failed ==            # test/run.sh
L1 (self-hosted rebuild): 25 passed, 0 failed
L2 (split tree, built by L1): 25 passed, 0 failed
check-goldens: OK (no regression, and the self-hosted rebuild agrees)
check-archive: OK (no regression)
== summary: 82 passed, 0 failed ==            # ct-tour
== summary: 817 passed, 0 failed ==            # check-ast
check-warnings: 249 ok, 0 failed               # v0.26.1: 248
check-semantics: OK (23 assertions)
check-docs: OK (863 relative links in 173 files, v0.26.2, 11 hard gates, 10 phase status, 3 适用版本 header(s))
== summary: 20 pass, 0 new, 0 pending, 0 regression ==
check-all: OK (11 hard gates green)
```

计数变化如实记录：`check-ast 815 → 817`（+2 = 主夹具循环的 `128_generic_type_operands` 与专用
`p26_generic_type_operands` 块）；`check-warnings 248 → 249`（+1 = 新夹具进入警告扫描）；
`tparam_residue()` 是红/绿判定，不新增 `ok` 条数；其余计数不变（`test/run.sh` 118、bootstrap 25 + 25、
`ct-tour` 82、tour shapes 20、`check-semantics` 23、`check-docs` 863 链接 / 173 文件）。

安装复核：`CT_SOURCE_DIR=. ./install.sh --prefix /tmp/p27/bin` 后 `/tmp/p27/bin/ct -v` 输出 `ct v0.26.2`；
`grep -n 'CTC_VERSION'` 五处均为 `0.26.2`。

### 6.3.4 门禁实跑（`v0.26.3`，2026-11-09）

```console
$ bash selfhost/check-ast.sh
== summary: 830 passed, 0 failed ==            # v0.26.2: 817

$ bash selfhost/check-all.sh
== summary: 118 passed, 0 failed ==            # test/run.sh
L1' (self-hosted rebuild): 25 passed, 0 failed
L2 (split tree, built by L1): 25 passed, 0 failed
check-goldens: OK (no regression, and the self-hosted rebuild agrees)
check-archive: OK (no regression)
M2-a: PASS (L1 output is byte-identical with L0 on test/cases/01_trait_basic.ct)
== summary: 82 passed, 0 failed ==            # ct-tour
== summary: 830 passed, 0 failed ==            # check-ast
check-warnings: 250 ok, 0 failed               # v0.26.2: 249
check-semantics: OK (23 assertions)
check-docs: OK (866 relative links in 173 files, v0.26.3, 11 hard gates, 10 phase status, 3 适用版本 header(s))
== summary: 20 pass, 0 new, 0 pending, 0 regression ==
check-all: OK (11 hard gates green)
```

计数变化如实记录：`check-ast 817 → 830`（+13）的构成可逐条核对——主夹具循环的 `129_generic_tparam_value_false_positive`
（1）、4 条 `p26_diag_generic_tparam_value_*`（4）、4 条 `p26_check_generic_tparam_value_*`（4）、
`test/ast/errors/**` 主循环对 4 条新负例各一条 “rejected with a positioned diagnostic”（4）。
`check-warnings 249 → 250`（+1 = 129 进入警告扫描；4 条负例不产生产物）。
`check-docs 863 → 866`（+3 = 本轮在 `issues/README.md` 与 `phase26.md` 新增的交叉引用：SH-64 ×1、
TEST-18 ×2）；文件数仍 173，阶段状态仍 10，硬门禁仍 11。
其余计数不变（`test/run.sh` 118、bootstrap 25 + 25、`ct-tour` 82、tour shapes 20、`check-semantics` 23）。

安装复核：`CT_SOURCE_DIR=. ./install.sh --prefix /tmp/p28/bin` 后 `/tmp/p28/bin/ct -v` 输出 `ct v0.26.3`；
`grep -n 'CTC_VERSION'` 五处均为 `0.26.3`。`tparam_residue()` 是红/绿判定，不新增 `ok` 条数。

### 6.4 E3 旧编译器对照（`~/.local/bin/ct`，v0.25.0）

| 夹具 | v0.25.0 输出（首条） | v0.26.0 输出 |
| --- | --- | --- |
| `123_generic_identity` | `prog.ct:5:5: error: unexpected token` | 构建并运行，输出 `42 hi` |
| `124_generic_struct` | `prog.ct:10:7: error: unexpected token` | 构建并运行，输出 `x=3 y=4` |
| `generic_missing_arg` | `3:5: error: unexpected token` | `10:14: error: generic function 'id' needs a type argument` |
| `generic_pub` | `2:9: error: unexpected token` | `2:9: error: generic functions cannot be pub`[^p34-l26-2] |
| `generic_two_params` | `2:7: error: unexpected token` | `2:9: error: only one type parameter is supported` |
| `generic_void_arg` | `2:5: error: unexpected token` | `9:19: error: 'void' cannot be a generic type argument` |
| `generic_recursive` | `3:8: error: unexpected token` | `10:17: error: recursive generic calls are not supported` |

[^p34-l26-2]: 该行是 v0.26.0 的历史对照。Phase 34 已解禁 L26-2（`pub` 泛型函数），见 §2.5 的「P34 覆盖」与 [phase34-draft.md](phase34-draft.md) §1.4。

旧编译器在**声明处**就失败，新断言要求的行、列与文案全部不同，说明断言不是空转。

### 6.5 E4 的 golden 口径

`CTC_VERSION` 从 `0.25.0` 到 `0.26.0`，74 个 golden（`test/cases/**` 50 + `test/modules/**` 21 + `examples/tour/**` 3）各只变一行 banner；`git diff -U0 -- test/cases test/modules examples/tour` 过滤掉版本 token 后无任何残行，非泛型发射路径逐字节不变。

---

## 7. 退出判据对照表

| 交付物 | 判据 | 证据 / 锚点 |
| --- | --- | --- |
| D1 `docs/design/phase26.md` | E1–E8 的规范来源；状态与 roadmap 一致 | `python3 test/docs/check-docs.py` → `v0.26.4, 10 phase status`；本文件 §1.5 冻结 |
| D2 `Symbols.h.ct` | E1 / E3 | `GenericInst`、`ginsts/nginsts`、`Fn.ntparams/tparam/body`、`ct_generic_subst` |
| D3 `Parser.h.ct` | E1 / E3 | `T name<T>(...)` 解析；L26-2/L26-3；模板标记 `N_FUNC.text3` |
| D4 `Expr.h.ct` | E1 / E3 / E8 | `name<type>(...)`；`generic_instance` 缓存与命名；L26-1/L26-4/L26-5 |
| D5 `Emitter.h.ct` | E1 / E2 / E4 | `gtparam/gtarg/gtname` 上下文；`emit_gsub_type`；`emit_generic_defs`；模板跳过 |
| D6 `test/ast/123_generic_identity/` | E1 | 生成 C 含 `id__ct1`/`id__ct2`、`id__ct1` 定义恰好 1 份、无 `\bT\b`、运行 `49 hi` |
| D7 `test/ast/124_generic_struct/` | E2 | 实例签名 `static struct Point pass__ct1(struct Point);`、运行 `x=3 y=4` |
| D8–D12 `test/ast/errors/generic_*.ct` | E3 / E8 | 五条 L26 各自 `file:line:col` + 文案；`ct check` 同文案；v0.26.1 增第 6 条 `generic_generic_selector`（`_Generic` 内的裸类型参数硬错）；v0.26.2 起该夹具仍硬错，而 `struct T` 标签选择器放行（126 断言）；v0.26.3 增 4 条值位置负例 `generic_tparam_value_{return,arg,mul,add}`（SH-64），`ct check` 同文案 |
| D13 `selfhost/check-ast.sh` | E1–E4 / E8 | Phase 26 块：`cmp -s`、实例原型精确计数、`! grep '\bT\b'`、6 条定位、6 条 check；v0.26.1 起加 125/126/127/容量夹具；v0.26.2 起加 128，以及主夹具循环的 `tparam_residue()` 产物层扫描（只读实例体，扣掉合法 `struct|union|enum T`）；v0.26.3 起加 129 正例与 4 条值位置负例（`p26_diag` + `p26_chk` 各 4） |
| D14 `docs/language-spec.md` | E7 | §4.48 中英文（语法/语义/非目标/诊断） |
| D15 `docs/tutorial.md` | E7 | §10.5 中英文可运行示例 |
| D16 `docs/roadmap.md` | E7 | Phase 26 行 `✅ 完成（v0.26.0；v0.26.1 / v0.26.2 / v0.26.3 / v0.26.4 修复）`、v0.26.0–v0.26.4 版本记录、映射行 |
| D17 `AGENTS.md` | E7 | 当前版本 v0.26.4；泛型限定说明；版本 bump 清单指向 roadmap |
| D18–D22 五处版本文件 | E6 | `grep -n 'CTC_VERSION'` 五处均 `0.26.4`；`ct -v` → `ct v0.26.4`；`git diff -U0` 仅版本 token |

### 7.1 lessons（每条落 `gate:` / `spec:` / `rejected:`）

| # | 结论 | 落点 |
| --- | --- | --- |
| 1 | 每条新断言都配一个曾变红的负例；L26 文案与 `file:line:col` 精确 grep，位置漂移即红 | `gate:check-ast` |
| 2 | 设计文档状态词必须与 roadmap emoji 一致（`完成` ↔ ✅），否则文档门禁红 | `gate:check-docs` |
| 3 | 泛型只覆盖函数、单类型参数、显式实例化；非目标与五条诊断写进语言规范 | `spec:§4.48` |
| 4 | 实例发射用「类型替换上下文」而非改写 AST；上下文为空时非泛型路径逐字节不变 | `spec:§2.4` |
| 5 | 深拷贝整棵 AST 需要按节点 kind 区分槽位并重建 `Var` 作用域，成本高且难测 | `rejected:深拷贝整棵 AST` |
| 6 | 「替换—发射—恢复」有恢复污染与槽位歧义两重风险，被 B26-1 第二轮驳回 | `rejected:替换—发射—恢复` |
| 7 | 类型推导需要双向类型检查，超出一相的范围 | `rejected:类型推导` |
| 8 | `pub` / 跨单元泛型需要头文件导出实例，半成品风险高 | `rejected:pub/跨单元泛型` |
| 9 | L0/L1/L2 只允许版本串变化；11 道硬门禁同时校验冻结与五处版本一致 | `gate:check-all` |
| 10 | 实现与立项的偏差必须逐条登记（§6.2），不得让文档停留在计划态 | `spec:§6.2` |
| 11 | 文档列出的替换点必须有解析侧对应：只在发射器写分支、解析器不产该节点，就是死代码加静默坏产物 | `gate:check-ast` / `spec:§2.4` |
| 12 | 「退出 0 但生成物含 `T`」是本相唯一不可接受的失败形态；断言须作用于整份生成 C，而非只看实例行 | `gate:check-ast` / `spec:E1` |
| 13 | 类型名判定只能有一个谓词；把「下一 token 是类型名」和「当前 token 是类型名」分开写，就会让无括号类型操作数走丢。修复抽 `tok_is_type_name()`，三算子共享 | `spec:§2.6` / `gate:check-ast` |
| 14 | 根因修复之外必须有产物层机械检查：`tparam_residue()` 从夹具自身声明自动提取类型参数并扫描生成 C，新夹具自动纳入，下一处漏网不能静默通过 | `gate:check-ast` / `spec:§6.3.1` |
| 15 | 同一个「标识符兜底」漏了三次（`sizeof(T)`、`sizeof T`、值位置）；修法必须是分支入口的统一守卫 + 全路径枚举，而不是逐个出口 | `spec:§2.7` / `gate:check-ast` |

---

## 8. 修复轮记录（v0.26.1 / v0.26.2 / v0.26.3，2026-11-09）

两轮的 issue 文件均已置 `fixed` 并附证据命令；`verified` 留给独立评审回写。

### 8.1 v0.26.1

| issue | 修复提交 | 证明其成立的命令 | 实测 |
| --- | --- | --- | --- |
| SH-62 | `87b03ec` + `4995dff`（`fix(ct-ast): make the generic type parameter a type in every template position` / `fix(ct-ast): reject the type parameter inside a _Generic selection`） | `bash selfhost/check-ast.sh`；基线复现：`/tmp/p26fix/base/ct-ast /tmp/p26fix/sz.ct -o /tmp/red.c && grep sizeof /tmp/red.c && cc -std=c99 /tmp/red.c`；`_Generic` 硬错：`ct-ast test/ast/errors/generic_generic_selector.ct` | 修复前退出 0 + `sizeof(T)` + `cc: 'T' undeclared`；修复后 `sizeof(int)`，运行 `4`；125/126 由红转绿；`_Generic` 由退出 0 的坏产物变为解析期硬错 |
| SH-63 | 同上 `87b03ec` | `ct-ast test/ast/126_generic_struct_tag/prog.ct -o /tmp/126.c && grep 'getv__ct1' /tmp/126.c && cc -std=c99 /tmp/126.c -o /tmp/126 && /tmp/126` | 修复前 `static struct int getv__ct1(struct int *);`（cc 拒绝）；修复后 `static int getv__ct1(struct T *);`，输出 `7` |
| TEST-17 | `f5f1092` + `4995dff`（`test(ct-ast): cover every type position inside a generic template body` / `_Generic` 夹具随修复提交） | `bash selfhost/check-ast.sh`（Phase 26 块 `p26_generic_type_positions` / `p26_generic_struct_tag` / `p26_generic_name_retry` / `p26_diag_generic_too_many` / `p26_check_generic_too_many` / `p26_diag_generic_generic_selector` / `p26_check_generic_generic_selector`）；红证见 §6.3.1 | 815 passed, 0 failed；新断言在 v0.26.0 基线上失败（125 解析错误、126 静默 `struct int`、`_Generic` 静默 `T`） |
| DOC-67 | 本文件所在提交（`docs(phase26): align the spec, roadmap and AGENTS ledger with v0.26.1`） | `python3 test/docs/check-docs.py`；`bash selfhost/check-all.sh` | `check-docs: OK (863 relative links in 173 files, v0.26.1, …)`；`check-all: OK (11 hard gates green)` |

B26-2 判决：两方案（真实现替换 / 改成硬错误）都能满足验收，按 §7 立案；成本差 < 2×，判决采用**方案 A（真实现替换）**，理由与证据见 §5 B26-2，决策登记 D26-12 / D26-13。

### 8.2 v0.26.2（第二轮重开）

| 条目 | 修复提交 | 证明其成立的命令 | 实测 |
| --- | --- | --- | --- |
| SH-62（根因） | `fix(parse): recognise a type parameter on the unparenthesised type-operand path`（`Expr.h.ct` 的 `tok_is_type_name()` / `type_no_ptr` / 三算子统一分支，`Emitter.h.ct` 的 `aux` 1–4 发射） | `bash selfhost/check-ast.sh`；`ct-ast test/ast/128_generic_type_operands/prog.ct -o /tmp/128.c && grep -nE 'sizeof|_Alignof|alignof' /tmp/128.c`；基线对照见 §6.3.1 | `sizeof T` / `_Alignof T` / `alignof(T)` / `sizeof T * 2` / `sizeof(T) + sizeof T` 全部替换；128 运行 `4 4 4 8 8`；v0.26.1 基线在对应形态上分别退出 0 坏产物或硬错 |
| SH-62（P2） | 同上（`_Generic` 标签放行） | `ct-ast test/ast/126_generic_struct_tag/prog.ct -o /tmp/126.c && grep '_Generic' /tmp/126.c`；`ct-ast test/ast/errors/generic_generic_selector.ct` | 126 发射 `_Generic ( x , struct T : 1 , default : 0 )` 并输出 `7 0`；裸 `T` 选择器仍报 `type parameter cannot be used inside _Generic`（退出 1） |
| TEST-17（防线） | `test(gate): scan every emitted fixture for a residual type parameter`（`tparam_residue()` + 128 夹具 + 126 扩断言） | `bash selfhost/check-ast.sh`；红证：`tparam_residue /tmp/p27/probe/sz.ct /tmp/p27/probe/sz261.c` | 红证打印 `T(1)`（v0.26.1 坏产物）；v0.26.2 的 123–128 产物为空；`check-ast` 815 → 817 passed, 0 failed |
| 发布 | `chore(release): v0.26.2`（五处 `CTC_VERSION` + 74 个 golden 的版本 token） | `grep -n 'CTC_VERSION'` 五处；`bash selfhost/check-all.sh` | 五处均 `0.26.2`；`check-all: OK (11 hard gates green)` |

### 8.3 v0.26.3（第三轮阻断项）

| 条目 | 修复提交 | 证明其成立的命令 | 实测 |
| --- | --- | --- | --- |
| SH-64（根因） | `fix(parse): reject a type parameter in a value position at the identifier entry`（`Expr.h.ct` 的 `T_ID` 入口守卫） | 4 个 `generic_tparam_value_*` 负例的 `p26_diag` / `p26_chk`；基线对照见 §6.3.1 | v0.26.2 四个探针均退出 0 并发射裸 `T`；v0.26.3 分别报 `6:13` / `11:15` / `6:30` / `6:30` 的 `type parameter 'T' cannot be used as a value`，`ct check` 同文案 |
| 防线假阳 | `test(gate): scope the residue scan to instance bodies`（`tparam_residue()` 只读 `<name>__ctN`；新增 129 正例） | 非模板函数含 `int T = 5;` 的探针：整文件扫描 `T(2)`、实例体扫描空；`bash selfhost/check-ast.sh` | 假阳消失；v0.26.1 坏产物仍 `T(1)`；123–129 产物为空 |
| 防线盲区 | `docs(phase26): enumerate identifier paths and record the residue blind spots`（TEST-18）→ v0.26.4 收口 | `docs/design/phase26.md` §2.7；`issues/testing/test18-...`；`bash selfhost/check-ast.sh` | v0.26.4 / TEST-18：`build` 的每个 `.c` 产物纳入扫描、`.h` 产物断言无 `<name>__ctN` 实例定义、新增夹具 `130_generic_build_mode` 与扫描器红/绿自检；`test/ast/errors/**`、`test/modules/**` / `examples/**` 与语料仍不扫，理由与触发条件见 §2.7 |
| 发布 | `chore(release): v0.26.3`（五处 `CTC_VERSION` + 74 个 golden 的版本 token） | `grep -n 'CTC_VERSION'` 五处；`bash selfhost/check-all.sh` | 五处均 `0.26.3`；`check-all: OK (11 hard gates green)` |

## 9. v0.26.4 补丁（工程可信度四项收口，2026-11-09）

### 9.1 版本与定位

本项是 Phase 26 之后的修复补丁，取 **`v0.26.4`**：五处 `CTC_VERSION` 同步、74 个 golden 仅版本 token 由 `0.26.3` 重生成到 `0.26.4`，编译器逻辑零改动。

- 修复不构成阶段边界：`docs/design/` 不新增阶段文档，`docs/roadmap.md` 只记补丁记录。
- S2（编辑器泛型跳转索引）**不计入编译器版本**：`editors/vscode` 按扩展自己的版本线发布 `0.5.1`，与本仓库的 `CTC_VERSION` 无关。
- 发布形态：annotated tag `v0.26.4` 指向发布提交，远端 `main` 与 peeled tag 为同一提交。

### 9.2 范围与判据

四条工作合并为一个补丁，每条有独立判据；判据编号 `P1`–`P8`。

| # | 工作 | 判据 |
| --- | --- | --- |
| S1 / TEST-18 | 把 `tparam_residue()` 防线扩到 `build` 的每个 `.c` 产物与 `.h` 产物，并让类型参数名从夹具的全部单元提取 | P1：`130` / `131` 跑通且产物含实例体；`.h` 无实例定义；P2：扫描器自检红/绿；P3：编译器逻辑零改动 |
| S2 / DOC-68 | 编辑器索引识别 `T name<T>(...)` 声明，纯函数抽成可断言的 `indexer.js` | P4：`check-index.js` 26 断言；旧正则变异后 12 条红 |
| S3 / CI-8 | `AGENTS.md` 锚定主规范 `spec-version` / `spec-sha256`，接入门禁 11 | P5：`spec pin: ok (1.0.0, 93a8e968)`；篡改 → `mismatch`；缺席 → `skipped` |
| S4 / DOC-66 | `docs/design/` 保留最近 12 个已完成阶段并断言无重复归档 | P6：`design window: ok`；越界 / 双存变红 |
| 收口 | 零回归、11 道硬门禁、版本串 | P7：`check-ast` 不低于基线 830 且 `0 failed`；P8：五处 `CTC_VERSION` = `0.26.4`、annotated tag、远端 hash 一致 |

**不做**：不改编译器语义；不新增第 12 道门禁（G9 并入门禁 11）；不迁移 `docs/design/` 的既有文件（选窗口断言而非路线 A）；不碰 L0/L1/L2 的逻辑（只改版本串）。

### 9.3 S1 根因与红证

- **盲区一（产物形态）**：v0.26.3 的防线只扫 compile 模式的单个 `.c`，`build` 产物与 `.h` 从未进入扫描。补法：`build` 分支对输出目录下每个 `*.c` 逐份调用同一函数，对每个 `*.h` 断言不含 `<name>__ctN(` 后接 `{` 的实例体；`.h.ct` / prologue 块接同一断言。夹具 `test/ast/130_generic_build_mode/`（期望 `6 42`）。
- **盲区二（跨单元）**：`tparam_residue()` 的类型参数名只从入口文件取。泛型若只声明在导入单元（`extra/lib.h.ct`），实例体落在该单元的 `.c`（`-o` 扁平化为 `lib.c`），扫描器没有名字可比，静默通过。补法：`fixture_sources()` 递归列出夹具目录下全部 `.ct`；夹具 `test/ast/131_generic_cross_unit/`（入口 `prog.ct` 无泛型，期望 `40`）固定该形态。`check-warnings.sh` 的 build 触发条件同步扩到 `.h.ct`。
- **红证（先红后绿）**：

| 变异 | 实测 |
| --- | --- |
| `tparam_residue()` 首行 `return 0;` | `FAIL tparam_residue self-test: the scanner stayed silent on a leaked type parameter` → `832 passed, 1 failed`，退出 1 |
| 自检只传入口 `src.ct`（v0.26.3 口径，泛型只写在 `lib.h.ct`） | 同一条 FAIL → `833 passed, 1 failed`，退出 1；脏 `lib.c` + 入口锚 → `[]` |
| `TPARAMS` 置空（旧正则） | `check-index: 26 assertions, 12 failed` |
| 主规范副本追加 1 字节 | 状态 `mismatch (1.0.0, 93a8e968)` + 摘要不符错误；缺席 → `skipped (spec not found)`、0 错 |
| 临时树加 `phase99` / `phase80` / 双存 `phase99` | `check-docs: FAIL (15 problem(s))`（越界 12 + 双存 1 + 缺状态行 2） |

- **残余盲区**：`test/modules/**` 与语料不做全量扫描（§2.7 已写触发条件）；扫描器假定 `__ctN(` 与 `{` 同行、类型参数声明在列 1（发射器当前恒为此形态，触发信号同样记在 §2.7）。

### 9.4 决策

| 编号 | 决策 | 理由 |
| --- | --- | --- |
| D26-16 | 四条工作合并为一个补丁 | 共享「把文字承诺变成可执行门禁」主线；分开做会重复一次门禁收口 |
| D26-17 | TEST-18 扩覆盖，不做永久豁免 | 扩覆盖只需在 `build` 分支加一次循环；豁免会让 Phase 26 的教训继续悬空 |
| D26-18 | 抽取 `indexer.js` 而不是在 `extension.js` 里加分支 | 只有纯函数能被 Node 直接断言；`extension.js` 依赖 `vscode` 模块 |
| D26-19 | G9 并入门禁 11 | 新门禁会连锁改动计数声明、`node` 前置与 CI 配置 |
| D26-20 | DOC-66 选路线 B（窗口断言） | 路线 A 要迁移 10 个文件并重算相对链接，成本约为 B 的 6 倍 |

各项取舍均无对立判据，由 EDITOR 代决（**用户已授权代决**）；未触发 §7 battle。

### 9.5 交付物

| 路径 | 作用 |
| --- | --- |
| `selfhost/check-ast.sh`、`selfhost/check-warnings.sh` | 产物扫描、`.h` 断言、自检、`.h.ct` 触发 |
| `test/ast/130_generic_build_mode/`、`test/ast/131_generic_cross_unit/` | 两个新夹具 |
| `editors/vscode/indexer.js`、`editors/vscode/extension.js` | 索引抽取（扩展线 `0.5.1`） |
| `editors/vscode/test/check-index.js`、`editors/vscode/test/check-grammar.py` | 26 条断言与门禁挂载 |
| `AGENTS.md`、`test/docs/check-docs.py` | G9 锚定、spec pin、12 阶段窗口 |
| `docs/README.md`、`docs/history/README.md` | 归档政策的中英声明 |
| `docs/history/reports/review-phase26-v0.26.4.md` | 独立评审报告 |
| `issues/{testing/test18,docs/doc68,ci/ci-8,docs/doc66}-*.md` | 四条台账的处置与验证 |

### 9.6 门禁实跑（`v0.26.4`，2026-11-09）

| 命令 | 原始输出 |
| --- | --- |
| `bash selfhost/check-ast.sh` | `== summary: 834 passed, 0 failed ==`（基线父提交 `8c88211` 实跑 `830 passed, 0 failed`） |
| `bash selfhost/check-all.sh` | `check-all: OK (11 hard gates green)` |
| `bash selfhost/check-warnings.sh` | `check-warnings: 253 ok, 0 failed` |
| `python3 test/docs/check-docs.py` | `spec pin: ok (1.0.0, 93a8e968)`；`check-docs: OK (875 relative links in 174 files, v0.26.4, 11 hard gates, 10 phase status, 3 适用版本 header(s))`；`design window: ok (10/12)` |
| `python3 editors/vscode/test/check-grammar.py` | `== 109 checks, 0 failed ==` |

74 个 golden 仅版本 token 由 `0.26.3` → `0.26.4` 变化；`check-goldens: OK (no regression, and the self-hosted rebuild agrees)`。

### 9.7 独立评审

[review-phase26-v0.26.4.md](../history/reports/review-phase26-v0.26.4.md)：P1–P7 全部 PASS、P8 判为 release-ready，最终 `release: GO`。评审自建自举链并独立复现跨单元盲区；5 条 minor 中 3 条放行前修复，2 条记录接受（扫描器的书写形态假设、提交顺序）。

### 9.8 lessons

- `gate:check-ast` — 断言的判别力必须先证：「全部单元」口径下绿、「只读入口」口径下红，才说明修复不是空转。
- `gate:check-warnings` — 「夹具是否多单元」的判定存在两份（`check-ast.sh` / `check-warnings.sh`），改一处必须两处同改；夹具 `131` 正是在第二份里才暴露出漏改。
- `gate:check-docs` — 门禁的状态行要与判决一致，且失败路径也必须打印，否则末行读起来像通过。
- `spec:§6 证据门禁` — 基线数字必须现跑（815 是 v0.26.0 的旧值，父提交实跑 830）。
- `spec:§7 battle` — 无判据取舍由 EDITOR 代决并注明「用户已授权代决」，不虚设 battle。
- `rejected:把修复包装成新阶段并 bump minor` — 修复不是阶段边界；版本只 bump patch。
- `rejected:迁移 12 个 design 文件（路线 A）` — 成本约为窗口断言的 6 倍，防漂移收益相同。
- `rejected:新增第 12 道门禁承载 G9` — 连锁改动计数声明、`node` 前置与 CI 配置，收益不足。

### 9.9 判据映射与冻结边界（2026-11-10 核对）

本节只做映射与事实回写，不改 §1.5 的冻结原文。

- **E6 的补丁口径**：§1.5 E6 冻结时写的是 `0.26.3`。v0.26.4 补丁把五处 `CTC_VERSION` 推进到 `0.26.4`，
  按 §1.5 原文逐字判 E6 不再成立；现行判定以 §9.2 P8 为准（五处 `0.26.4`、`ct -v` → `ct v0.26.4`、
  annotated tag `v0.26.4` 与远端一致）。「按原文判不满足、按补丁判满足」由此在唯一位置有可审计映射，
  冻结原文保留不动。
- **§7 的版本号**：§7 是收口对照表，不属于 §1.5 冻结块；D16 / D17 / D18–D22 的版本号按 v0.26.4 同步，
  §1.5 E6 原文保持 `0.26.3`。
- **P8 远端闭合（2026-11-10）**：`git push origin refs/tags/v0.26.0:…refs/tags/v0.26.4` 返回
  `Everything up-to-date`；`git ls-remote origin 'refs/tags/v0.26.*'` 显示五个 annotated tag 均在远端，
  tag 对象 hash 与本地逐一相同：`v0.26.0 f91ba25a`、`v0.26.1 d45269ac`、`v0.26.2 1be16400`、
  `v0.26.3 3a894b6d`、`v0.26.4 76d18e05`。P8 的「远端 hash 一致」自此成立。
- **判据覆盖缺口**：E1–E8 未覆盖 v0.26.4 的 TEST-18 / CI-8 / DOC-66 / DOC-68，已登记
  [DOC-69](../../issues/docs/doc69-phase26-exit-criteria-patch-gap.md)；不为让结论好看而回溯扩写 E1–E8。
