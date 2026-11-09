# Phase 26 · 泛型函数（单类型参数 + 显式实例化 + 编译期单态化）

> 中文。
>
> **状态：完成**（退出判据于 2026-11-09、首个实现提交前冻结；收口记录见 §6/§7）。
> **主题来源**：[phase25.md:65](phase25.md#L65) 与 [phase25.md:261](phase25.md#L261) 明确写「泛型是 Phase 26」；
> 立项时 [roadmap.md](../roadmap.md) 尚无 Phase 26 行，本相同时补入；需求池中「类型检查 / 泛型」一项被本相拆出实现。
> 关联：[phase25.md](phase25.md)（静态映射闭包实参）、[phase19.md](phase19.md)（受限语义检查）、
> [language-spec.md](../language-spec.md)、[roadmap.md](../roadmap.md)、[AGENTS.md](../../AGENTS.md)。

---

## 1. 立项

### 1.1 编号

**Phase 26**，发布版本 **`v0.26.0`**（`CTC_VERSION` = `0.26.0`）。

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
| E1 | 正例 `123_generic_identity` 构建、运行、输出逐字节匹配；生成 C 中每个类型实参一份函数，且签名/函数体内不残留类型参数 `T` | `bash selfhost/check-ast.sh` 的 Phase 26 块：`cmp -s` + `grep -c '__ct[0-9]'` + `! grep -E '\bT\b'` 作用于生成 C 的函数段 |
| E2 | 正例 `124_generic_struct` 以 `struct Point` 为类型实参，字段访问与返回正确 | 同上，运行输出 `x=3 y=4` |
| E3 | 五条负例各自只产生一条 L26 错误，位置与文案精确匹配；v0.25.0 编译器对同一夹具给出不同结果（证明断言非空转） | `bash selfhost/check-ast.sh` 的 `"fixture|line:col|message"` 表；另用 `~/.local/bin/ct`（v0.25.0）复核旧行为并记录在 §6 |
| E4 | 既有 784 条断言零回归；非泛型 golden 逐字节不变 | `bash selfhost/check-ast.sh` 汇总 `>= 792 passed, 0 failed`；`bash selfhost/check-goldens.sh` / `check-all` 的 `check-goldens: OK` |
| E5 | 11 道硬门禁全绿 | `bash selfhost/check-all.sh` 末行 `check-all: OK (11 hard gates green)` |
| E6 | 五处 `CTC_VERSION` 均为 `0.26.0`；安装后 `ct -v` 输出 `ct v0.26.0` | `grep -n 'CTC_VERSION'` 五处；`bash install.sh` 后 `ct -v` |
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
| `N_SIZEOF` | `text` | `sizeof(T)` |
| `N_OFFSETOF` | `text` | `offsetof(T, f)` |

不替换 `N_VAR.text2`、`N_ID.text`、`N_CALL.text` 等标识符位；`T` 作值使用会自然解析失败。
不替换 `N_RAW` 内的原始文本；泛型体内出现原始初始化器时按 L26-5 拒绝。

### 2.4 发射（D26-7，B26-1 第二轮修订）

- 原型循环：模板跳过（`ntparams > 0`），按实例表输出 `static` 原型。
- 定义循环：模板跳过；每个实例**复用模板的 `N_FUNC` 节点**，发射期间在发射器上打开「类型替换上下文」
  （`gtparam` / `gtarg` / `gtname`），类型打印点在上下文非空时替换，发射结束即关闭。**不改写任何 AST
  字段**，因此不存在「恢复不精确污染后续函数」的路径。
- 替换点：`emit_type_name_dims`（形参 / 局部声明）、`N_FUNC` 返回类型与函数名、`N_CAST`、`N_SIZEOF`、
  `N_OFFSETOF`。
- 头文件导出：本相不支持 `pub` 泛型，因此头文件不出现实例。
- 非泛型代码的发射路径与 v0.25.0 完全一致（上下文为空时所有替换点原样输出），golden 零变化。

### 2.5 诊断（D26-8）

| 码 | 触发 | 文案（精确） |
| --- | --- | --- |
| L26-1 | 调用已知泛型函数但缺 `<type>` | `generic function '<name>' needs a type argument` |
| L26-2 | `pub` 泛型函数 | `generic functions cannot be pub` |
| L26-3 | 类型参数多于 1 个 / 空列表 | `only one type parameter is supported` |
| L26-4 | 类型实参为 `void` / 数组 / 函数指针 / 含 `T` | `'<type>' cannot be a generic type argument` |
| L26-5 | 泛型体内递归或嵌套泛型调用 | `recursive generic calls are not supported` |

所有诊断走 `ct_sem_error(line, col, msg, path)`，带 `file:line:col`；`ct check` 与编译路径一致。

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
4. L26-3 的「空列表」与「多参数」共用一条文案；空列表由 `parse_params` 的既有空参数诊断先行处理。
5. 「数组作类型实参」不在解析期显式识别（`id<int[3]>` 会在 `[` 处报 `expected '>' after the generic type argument`）；L26-4 夹具覆盖 `void`。
6. L26-5 只拦「解析模板体时遇到的泛型调用」；模板自递归（指向尚未 `add_func` 的自己）会落到普通未声明调用诊断。夹具用「嵌套调用」形态。
7. `N_RAW` 原始初始化器内的 `T` 不替换（§2.3 已声明）；本相夹具不覆盖。

### 6.3 门禁实跑（2026-11-09）

- `bash selfhost/check-ast.sh` → `== summary: 803 passed, 0 failed ==`，`EXIT=0`（基线 784 + 19 新增：2 正例 + 2 生成 C 断言 + 5 条 L26 定位 + 5 条 `ct check` 复用 + 5 个负例扫描）。
- `bash selfhost/check-all.sh` → `check-all: OK (11 hard gates green)`，`EXIT=0`。同一日志内的分项原始行：
  `== summary: 118 passed, 0 failed ==`（bootstrap）、`check-goldens: OK (no regression, and the self-hosted rebuild agrees)`、
  `check-archive: OK (no regression)`、`== summary: 82 passed, 0 failed ==`（包管理）、
  `== summary: 803 passed, 0 failed ==`（check-ast）、`check-warnings: 245 ok, 0 failed`、
  `check-semantics: OK (23 assertions)`、`check-docs: OK (850 relative links in 172 files, v0.26.0, 11 hard gates, 10 phase status, 3 适用版本 header(s))`、
  `== summary: 20 pass, 0 new, 0 pending, 0 regression ==`（acceptance probes）。
- E6 安装复核：`CT_SOURCE_DIR=. ./install.sh --prefix /tmp/p26install` → `EXIT=0`；`/tmp/p26install/ct -v` → `ct v0.26.0`，`ctc -v` → `ctc v0.26.0`；五处 `CTC_VERSION` 均为 `0.26.0`。

### 6.4 E3 旧编译器对照（`~/.local/bin/ct`，v0.25.0）

| 夹具 | v0.25.0 输出（首条） | v0.26.0 输出 |
| --- | --- | --- |
| `123_generic_identity` | `prog.ct:5:5: error: unexpected token` | 构建并运行，输出 `42 hi` |
| `124_generic_struct` | `prog.ct:10:7: error: unexpected token` | 构建并运行，输出 `x=3 y=4` |
| `generic_missing_arg` | `3:5: error: unexpected token` | `10:14: error: generic function 'id' needs a type argument` |
| `generic_pub` | `2:9: error: unexpected token` | `2:9: error: generic functions cannot be pub` |
| `generic_two_params` | `2:7: error: unexpected token` | `2:9: error: only one type parameter is supported` |
| `generic_void_arg` | `2:5: error: unexpected token` | `9:19: error: 'void' cannot be a generic type argument` |
| `generic_recursive` | `3:8: error: unexpected token` | `10:17: error: recursive generic calls are not supported` |

旧编译器在**声明处**就失败，新断言要求的行、列与文案全部不同，说明断言不是空转。

### 6.5 E4 的 golden 口径

`CTC_VERSION` 从 `0.25.0` 到 `0.26.0`，74 个 golden（`test/cases/**` 50 + `test/modules/**` 21 + `examples/tour/**` 3）各只变一行 banner；`git diff -U0 -- test/cases test/modules examples/tour` 过滤掉版本 token 后无任何残行，非泛型发射路径逐字节不变。

---

## 7. 退出判据对照表

| 交付物 | 判据 | 证据 / 锚点 |
| --- | --- | --- |
| D1 `docs/design/phase26.md` | E1–E8 的规范来源；状态与 roadmap 一致 | `python3 test/docs/check-docs.py` → `v0.26.0, 10 phase status`；本文件 §1.5 冻结 |
| D2 `Symbols.h.ct` | E1 / E3 | `GenericInst`、`ginsts/nginsts`、`Fn.ntparams/tparam/body`、`ct_generic_subst` |
| D3 `Parser.h.ct` | E1 / E3 | `T name<T>(...)` 解析；L26-2/L26-3；模板标记 `N_FUNC.text3` |
| D4 `Expr.h.ct` | E1 / E3 / E8 | `name<type>(...)`；`generic_instance` 缓存与命名；L26-1/L26-4/L26-5 |
| D5 `Emitter.h.ct` | E1 / E2 / E4 | `gtparam/gtarg/gtname` 上下文；`emit_gsub_type`；`emit_generic_defs`；模板跳过 |
| D6 `test/ast/123_generic_identity/` | E1 | 生成 C 含 `id__ct1`/`id__ct2`、无 `\bT\b`、运行 `42 hi` |
| D7 `test/ast/124_generic_struct/` | E2 | 实例签名 `static struct Point pass__ct1(struct Point);`、运行 `x=3 y=4` |
| D8–D12 `test/ast/errors/generic_*.ct` | E3 / E8 | 五条 L26 各自 `file:line:col` + 文案；`ct check` 同文案 |
| D13 `selfhost/check-ast.sh` | E1–E4 / E8 | Phase 26 块：`cmp -s`、`grep -c '__ct[0-9]'`、`! grep '\bT\b'`、5 条定位、5 条 check |
| D14 `docs/language-spec.md` | E7 | §4.48 中英文（语法/语义/非目标/诊断） |
| D15 `docs/tutorial.md` | E7 | §10.5 中英文可运行示例 |
| D16 `docs/roadmap.md` | E7 | Phase 26 行 `✅ 完成（v0.26.0）`、v0.26.0 版本记录、映射行 |
| D17 `AGENTS.md` | E7 | 当前版本 v0.26.0；泛型限定说明 |
| D18–D22 五处版本文件 | E6 | `grep -n 'CTC_VERSION'` 五处均 `0.26.0`；`CT_SOURCE_DIR=. ./install.sh --prefix /tmp/p26install` 后 `ct -v` → `ct v0.26.0`；`git diff -U0` 仅版本 token |

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
