# 提案：自定义类型下标协议（REQ-L1）

> **状态：提案 / 未立项 / 未过分析，不作数**（2026-11-13；原 `phase40-draft.md` 因 PH-40 已由
> errdefer 占用，移入 `docs/proposals/`；等待 AN、排期与立项）。
> **基线**：若立项，以立项时的 `HEAD` 为基线；S0 记录 `baseline: <sha>` 并复跑 §2.2。
> **文档形态**：`docs/proposals/custom-index-protocol.md`；转正时由 EDITOR 新建 phase 卡。
> **前置**：[phase31.md](../history/design/phase31.md)（`v[i]` / `m[k]` 的既有降级路径与 L31-3/L31-4 写保护）、
> [phase34-draft.md](../design/phase34-draft.md)（非泛型固有 `impl Name`）。
> **关联**：[requirements-pool.md](../planning/requirements-pool.md) 的 `REQ-L1`、
> [modern-oo-gap.md](../modern-oo-gap.md) §6.2（`C1 下标糖`）。
> **编号**：不认领 phase 编号；PH-40 已由 errdefer 占用，本提案通过 AN 后按 roadmap 空位排期。
> **规模**：编译器 120–220；夹具/断言 90–170；文档 40–80；合计 **250–470**（±40%）。
> **纪律**：不 bump、不打 tag、不 push；只更新本提案。

## 1 目标与边界

### 1.1 一句话

允许自定义 struct 在 `impl` 中声明签名匹配的 `get` / `set` 后使用 `obj[key]` / `obj[idx]` 下标语法，由编译器展开为对应方法调用；类型未声明该协议时是编译期硬错，错误信息必须指名类型。

### 1.2 三项

| 编号 | 内容 | 今天 |
| --- | --- | --- |
| O1 | 读形态：`obj[k]` → `obj.get(k)`，覆盖非泛型 struct 与泛型实例 | 只有 `Vec` / `Map` 有下标糖；用户 struct 原样发射 C 下标 |
| O2 | 写形态：语句 `obj[k] = v` → `obj.set(k, v)`，只收左值接收者 | 用户 struct 的 `obj[k] = v` 发射 `obj[k] = v`，由 `cc` 报错 |
| O3 | 诊断：缺 `get` / 缺 `set` / 参数个数不符 / `static` / 右值接收者 / 复合赋值 / 取地址 / `own` 右值，全部编译期硬错并指名类型 | 无诊断；`ct-ast` 退出 0，`cc` 才报 `array subscript is not an integer` |

### 1.3 非目标

- 不做 `+` / `==` / `()` 等其他运算符重载；只做 `[]`。
- 不改 `Vec` / `Map` 的布局、生成代码与既有诊断；L31-3/L31-4 的文案逐字保持。
- 不放宽 L29-11（容器不装 `own` / `borrow` 值）与 L29-13（容器不装带 vptr 的实体）；
  不碰 `container_vptr_type` 与接口/vptr 元素规则。
- 不接受 trait 提供的 `get` / `set`；只认 `impl` 的固有方法（`inst_inherent_method`）。
- 不做 `set`-only 类型：读形态是写形态的解析前置，v1 要求 `get` 存在。
- 不做参数/返回类型的完整兼容检查；v1 只校验方法名、参数个数、非 `static`，类型错误仍由
  C 编译器兜底（与 `ct check` 的 opt-in 边界一致）。
- 不做指针接收者：`struct X *p; p[k]` 保持 C 的指针算术；要协议写 `(*p)[k]`。
- 不做文件作用域 / 常量初始化器 / `#ct-raw` 内的自定义下标。

### 1.4 关键决策

| 编号 | 决策 | 理由 |
| --- | --- | --- |
| RL1-D1 | 复用 Phase 31 的 `N_MCALL` 糖：`aux = 9`、`text2 = "get"`、`a = 接收者`、`b = 下标` | 与 `Vec` / `Map` 的下标走同一条发射路径，不新增节点种类 |
| RL1-D2 | 协议只认 `impl X` 的固有方法；trait 方法不算 | trait 方法可能来自 vtable，`obj[k]` 会隐式改变派发语义；固有方法才是静态糖 |
| RL1-D3 | 签名匹配 = 方法名 + 参数个数 + 非 `static`；类型留给 `cc` | 本仓没有完整表达式类型系统；扩类型检查是 Phase 32 的轴，不塞进本相 |
| RL1-D4 | 写形态只收语句位置 + 左值接收者 | `obj[k] = v` 作为值表达式应产出被赋的值，而 `set` 返回 `void`；右值接收者会被发射成临时量，写入会静默丢失 |
| RL1-D5 | 缺协议是硬错，不是回退 C 下标 | 回退正是今天 `ct-ast` 退出 0、`cc` 才报错的根因；用户要求编译期指名类型 |
| RL1-D6 | 错误文案里的类型名用 `static_ctype` 的拼写；泛型实例先尝试 `ct_inst_find` 还原 `Box<int>`，失败则用 `Box_int` | 不让用户拿 `Box_int` 去猜源码类型；还原失败仍必须指名，不静默 |
| RL1-D7 | 写形态的右值若为 `own` / `borrow` 变量，复用 L29-11 的判定并硬错 | 自定义 `set` 可能保存指针；AutoDrop 仍会在块尾释放同一对象，双释放 |
| RL1-D8 | C 数组 / 指针 / `Vec` / `Map` 一律保持原行为 | Z3（C 超集）与 Phase 31 的冻结面；本相只新增 `struct` 分支 |

## 2 现状与基线

### 2.1 门禁基线

参考值（**历史量级参考**，v0.30.0）：`check-ast` 1155/0、`check-warnings` 389/0、
`test/run` 145、`check-docs` 1036 links / 181 files、`design window 12/12`。
这些数字**不是判据**；S0 在实现提交的父提交上实测并替换本节。

### 2.2 红证探针（上一轮实测；S0 必须复跑并记录 `baseline: <sha>`）

| 探针 | 命令 | 基线输出 |
| --- | --- | --- |
| 用户 struct 下标 | `ct-ast` 编译 `Box<int> b; b[0];` | `ct-ast` 退出 0；生成 C 保留 `b[0]`；`cc` 报 `error: array subscript is not an integer` |
| 缺协议 | 同上，另加 `b["k"]` | 同上：无编译期诊断，只有 `cc` 的 `array subscript is not an integer` |
| 写形态 | `Box<int> b; b[0] = 1;` | `ct-ast` 退出 0；`cc` 报 `array subscript is not an integer` |
| 既有容器 | `Vec<int> v; v[0];` | `ct-ast` 展开为 `v.get(0)`（Phase 31 O3），可编译运行 |
| 既有写保护 | `Vec<int> v; v[0] = 1;` | `v[0]` 是只读的；用 `set(i, v)`（L31-3，逐字） |

### 2.3 代码锚点

| 主题 | 位置 |
| --- | --- |
| `[` 后缀解析与 `Vec` / `Map` 糖 | `selfhost/ct-ast/frontend/parse/Expr.h.ct:3957-4007` |
| 非糖下标的 `N_INDEX` 构造 | `Expr.h.ct:4009-4022` |
| `container_index_check`（只拒 `Vec` / `Map`） | `Expr.h.ct:3729-3742` |
| `container_subscript_kind`（写保护识别） | `Expr.h.ct:3776-3795` |
| `container_write_check` / `container_addr_check` | `Expr.h.ct:3798-3829` |
| 赋值节点构造（语句与值位置共用一个入口） | `Expr.h.ct:2849-2913` |
| 前缀 / 后缀 `++` / `--` | `Expr.h.ct:3354-3372`、`Expr.h.ct:4458-4473` |
| 固有方法查找 | `Expr.h.ct:3420-3453`（`inst_inherent_method`） |
| 静态类型推导 | `Expr.h.ct:3582-3695`（`static_ctype`） |
| L29-11 `own` / `borrow` 实参守卫 | `Expr.h.ct:4169-4189` |
| L29-13 vptr 元素守卫 | `Expr.h.ct:2116-2143`（`container_vptr_type`） |
| `N_MCALL` 发射 | `selfhost/ct-ast/backend/emit/Emitter.h.ct` 的 `N_MCALL` 分支 |

## 3 语义与落码

### 3.1 展开表

| 源码 | 展开 | 条件 |
| --- | --- | --- |
| `obj[k]` | `obj.get(k)` | `obj` 的静态类型是 `struct X`（非指针），`X` 有 1 参、非 `static` 的固有 `get` |
| `obj[k] = v;` | `obj.set(k, v);` | 同上，且 `X` 有 2 参、非 `static` 的固有 `set`；语句位置；接收者是左值 |
| `obj[k] += v;` / `obj[k]++` | 硬错 RL1-L6 | 只支持 `=` |
| `&obj[k]` | 硬错 RL1-L7 | `get` 返回的是值，没有地址 |
| `p[k]`（`p` 为 `struct X *`） | 原样 C 指针算术 | 保持 Z3；要协议写 `(*p)[k]` |
| `a[k]`（`a` 为 C 数组） | 原样 C 下标 | 保持 Z3 |
| `v[k]` / `m[k]` | 原样 Phase 31 行为 | 不进入本相的新分支 |

### 3.2 协议识别

读形态在 `parse_postfix` 的 `[` 分支里扩展 `sugar`：

1. `static_ctype(n, bty, &bd)` 成功，`bd == 0`，`bty` 不含 `*`，且以 `struct ` 开头；
2. `inst_inherent_method(bty, "get")` 返回方法节点；
3. 方法节点非 `static`（`nodes[m].c == 0`），且参数链恰好 1 项。

命中后构造 `N_MCALL`：`aux = 9`、`text = bty`、`text2 = "get"`、`a = 接收者`、`b = 下标`，
`line` / `num` 指向 `[` 的位置，与 `Vec` / `Map` 的糖完全同形。
第 2 步命中但第 3 步不成立时，直接报 RL1-L3 / RL1-L5，**不回退** C 下标；第 2 步不命中时
留给 `container_index_check` 报 RL1-L1。

写形态在 `parse_assign` 的赋值分支里、`container_write_check` 之前识别，顺序固定：

1. 左节点是上面的自定义下标 `N_MCALL`（`aux == 9`、`text2 == "get"`、`text` 非 `Vec_` / `Map_`）；
2. 运算符不是 `=`（`op != 0`）→ RL1-L6；
3. `assign_ok != 0`（值位置）或接收者沿 `N_MEMBER` / `N_ARROW` 链回溯不到 `N_VAR`
   （右值接收者）→ RL1-L8；
4. `inst_inherent_method(text, "set")` 不命中 → RL1-L2；命中但 `static` 或参数链不是 2 项
   → RL1-L5 / RL1-L4；
5. 右值是 `own` / `borrow` 变量（复用 L29-11 的 `autodrop` / `borrowed` 判定）→ RL1-L9。

全部通过后把左节点改写成 `N_MCALL`：`aux = 9`、`text2 = "set"`、`a = 接收者`、
`b = 下标节点`，并把右值挂到下标节点的 `next`，形成 `(k, v)` 实参链；赋值节点本身不再生成。
`set` 的返回值按 `void` 处理，语句位置不需要结果。

### 3.3 诊断（RL1-L1–RL1-L9）

文案在 S1 冻结前可改，冻结后逐字断言；位置一律指向 `[` 的 `file:line:col`，一次只报一条。

| 编号 | 触发 | 文案（草案） |
| --- | --- | --- |
| RL1-L1 | `struct X` 无 `get` | `type 'X' has no subscript: declare 'V get(K)' in impl X` |
| RL1-L2 | 有 `get`、无 `set`，写形态 | `type 'X' has a read-only subscript: declare 'void set(K, V)' in impl X` |
| RL1-L3 | `get` 参数个数 ≠ 1 | `type 'X' has no subscript: 'get' must take 1 parameter` |
| RL1-L4 | `set` 参数个数 ≠ 2 | `type 'X' has no writable subscript: 'set' must take 2 parameters` |
| RL1-L5 | `get` / `set` 是 `static` | `type 'X' has no subscript: 'get' must be an instance method` |
| RL1-L6 | `+=` / `++` / `--` | `a custom subscript supports only '='; use set(k, v)` |
| RL1-L7 | `&obj[k]` | `cannot take the address of a custom subscript; bind it to a local first` |
| RL1-L8 | 写形态不是语句或接收者非左值 | `a custom subscript write needs a statement and an lvalue receiver` |
| RL1-L9 | 右值是 `own` / `borrow` 变量 | `a custom subscript set cannot take an 'own' or 'borrow' value` |

`RL1-L1` / `RL1-L2` 的类型名按 RL1-D6 还原；泛型实例还原失败时至少给出 `Box_int`，
不允许只报 `has no subscript` 而不指名。

### 3.4 与既有守卫的关系

- `container_index_check` 只在 `Vec_` / `Map_` 两个分支之后追加 `struct` 分支；前两条文案不变。
- `container_subscript_kind` 增加 kind `3`（自定义下标）；kind `1` / `2` 的写保护不变。
- `container_write_check` / `container_addr_check` 对 kind `3` 给 RL1-L6 / RL1-L7；不改变 kind `1` / `2`。
- **不调用** `container_vptr_type` 判断自定义类型；L29-13 的接口 / vptr 元素规则完全不碰。
- L29-11 只复用其 `autodrop` / `borrowed` 判定，用于 RL1-L9；不扩大它对普通实参的适用范围。

## 4 退出判据（RL1-E1–RL1-E10）

| 编号 | 判据 | 证据 |
| --- | --- | --- |
| RL1-E1 | 非泛型 `struct X` + `int get(int)`：`x[1]` 展开为 `x.get(1)`，生成 C 可编译并运行 | 夹具 `233_custom_index_read` |
| RL1-E2 | 泛型实例 `Box<int>` + `get`：`b[1]` 同样展开，产物无模板残留 | 夹具 `235_custom_index_generic` |
| RL1-E3 | `struct X` + `void set(int, int)`：语句 `x[1] = 9;` 展开为 `x.set(1, 9)`，读回 `9` | 夹具 `234_custom_index_write` |
| RL1-E4 | RL1-L1–RL1-L9 各一条负例，`file:line:col` 与文案逐字命中，且失败后不落 `.c` | `test/ast/errors/RL1_*.ct` + `check-ast.sh` 断言 |
| RL1-E5 | C 数组、`int *`、`struct X *` 的下标语义与产物不变 | 夹具 `236_custom_index_c_passthrough` |
| RL1-E6 | `Vec` / `Map` 的 L31-3/L31-4 文案与产物逐字不变 | 既有 `L31_3_*` / `L31_4_*` 负例继续绿 |
| RL1-E7 | 同一份 L40 负例在 `ct-ast` 与 `ct check` 下同文案、同位置 | T-5 的双模式断言 |
| RL1-E8 | 自举 fixpoint 通过：新编译器编译自身，重建产物逐字节一致 | `check-ast.sh` 的 self-hosting 段 |
| RL1-E9 | 全量门禁零失败：`check-ast` / `check-warnings` / `test/run` / `check-docs` | 收口时贴原始末行 |
| RL1-E10 | 任务清单每项可独立验收（6.6 T-6） | 本卡 §5 的 `verify` 列逐条可执行 |

## 5 任务清单（T-1–T-7；每项一个交付物、一条验收命令、一次提交、可单独回滚）

| 任务 | 交付物（主路径） | `verify` | 工量 | 备注 |
| --- | --- | --- | --- | --- |
| T-1 | `selfhost/ct-ast/frontend/parse/Expr.h.ct` 的读形态 + `test/ast/233_custom_index_read/` | `./selfhost/check-ast.sh 2>&1 \| grep -F "ok    233_custom_index_read"` | M | 先提红夹具；含 RL1-L1 |
| T-2 | 同一文件的写形态 + `test/ast/234_custom_index_write/` | `./selfhost/check-ast.sh 2>&1 \| grep -F "ok    234_custom_index_write"` | M | 先提红夹具；含 RL1-L2 / RL1-L8 / RL1-L9 |
| T-3 | `Expr.h.ct` 的参数个数 / `static` / 复合赋值 / 取地址守卫 + `test/ast/errors/RL1_*.ct` + `check-ast.sh` 断言块 | `./selfhost/check-ast.sh 2>&1 \| grep -F "RL1_"` | M | 覆盖 RL1-L3–RL1-L7；只补守卫，不改 T-1/T-2 的正向糖 |
| T-4 | `Expr.h.ct` 的泛型实例还原 + `test/ast/235_custom_index_generic/` | `./selfhost/check-ast.sh 2>&1 \| grep -F "ok    235_custom_index_generic"` | S | RL1-D6 的类型名还原 |
| T-5 | `test/ast/236_custom_index_c_passthrough/` + `ct check` 双模式断言 | `./selfhost/check-ast.sh 2>&1 \| grep -F "ok    236_custom_index_c_passthrough"` | S | RL1-E5 / RL1-E7 |
| T-6 | `docs/language-spec.md` §4.54（中英对称） | `python3 test/docs/check-docs.py` | S | `no-test: 纯文档；语法章节不新增门禁` |
| T-7 | `docs/proposals/custom-index-protocol.md` 的收口证据表（§7） | `./selfhost/check-ast.sh 2>&1 \| tail -3` | S | `no-test: 收口证据；实现红绿已在 T-1–T-5` |

依赖：T-1 → T-2 → T-3；T-4 依赖 T-1；T-5 依赖 T-1/T-2；T-6 与 T-1–T-5 并行；T-7 最后。
T-1–T-5 每个任务的第一笔提交是 `test(...)` 红夹具（含 `baseline: <sha>` 与原始输出），
实现提交随后转绿；T-6 / T-7 按表内理由标 `no-test`。
每项各自可 `git revert`，路径集合与本表一致；T-3 只补守卫与夹具，不动 T-1/T-2 已写的正向糖。

## 6 版本

本提案**不 bump、不打 tag**；若立项，版本号由对应的 phase 卡按 6.7 决定。

## 7 冻结面与收口证据

**冻结面（不得顺手放宽）**：

| 面 | 位置 | 本相允许的改动 |
| --- | --- | --- |
| `container_index_check` | `Expr.h.ct:3729-3742` | 只在 `Vec_` / `Map_` 之后追加 `struct` 分支；两条既有文案逐字不变 |
| `container_subscript_kind` | `Expr.h.ct:3776-3795` | 只追加 kind `3`；kind `1` / `2` 的识别与顺序不变 |
| `container_write_check` | `Expr.h.ct:3798-3815` | 只追加 kind `3` 的 RL1-L6；既有两条文案不变 |
| `container_addr_check` | `Expr.h.ct:3818-3829` | 只追加 kind `3` 的 RL1-L7 |
| L29-11 `own` / `borrow` 守卫 | `Expr.h.ct:4169-4189` | 只复用判定；不扩大容器 `push` / `set` / `put` 的既有范围 |
| L29-13 vptr 元素守卫 | `Expr.h.ct:2116-2143` | **不改**；接口 / vptr 元素规则一字不动 |
| `Vec` / `Map` 生成物 | `lib/std/Vec.h.ct` | **不改**；下标糖与布局保持 Phase 31 状态 |

**收口证据表（T-7 填）**：

| 退出判据 | 命令 | 原始末行 | 结论 |
| --- | --- | --- | --- |
| RL1-E1–RL1-E3 | `check-ast.sh` 的 233–235 | 待填 | 待填 |
| RL1-E4 / RL1-E7 | `check-ast.sh` 的 L40 断言 | 待填 | 待填 |
| RL1-E5 / RL1-E6 | `check-ast.sh` 的 236 与 L31 负例 | 待填 | 待填 |
| RL1-E8 | `check-ast.sh` self-hosting 段 | 待填 | 待填 |
| RL1-E9 | `check-all.sh` 末行 | 待填 | 待填 |

## 8 风险

| 编号 | 风险 | 触发信号 | 处置 |
| --- | --- | --- | --- |
| RL1-R1 | `static_ctype` 对复杂接收者（`f().box[k]`、字段链）推导失败，糖不生效，退回 C 下标并只在 `cc` 报错 | 新夹具用调用结果作接收者 | 只对静态类型可解析的接收者承诺协议；失败保持 C 语义，不在本相扩类型推导 |
| RL1-R2 | 右值接收者的写形态被发射成临时量，写入静默丢失 | `make()[0] = 1;` 通过 | RL1-D4 硬错 RL1-L8；T-2 负例钉住 |
| RL1-R3 | `own` / `borrow` 右值交给 `set` 后，块尾 AutoDrop 再释放，双释放 | `x[0] = own_v;` 通过 | RL1-D7 / RL1-L9；复用 L29-11 判定 |
| RL1-R4 | 写形态把右值挂到下标节点的 `next`，若下标子表达式被共享会改到别处 | 同一 AST 节点被两个父节点引用 | 解析树按树构造；T-2 增加 `x[f()] = v` 夹具，断言只出现一次 `f()` |
| RL1-R5 | 泛型类型名还原失败，错误文案给出 `Box_int`，用户无法对应源码 | RL1-L1 在泛型上触发 | RL1-D6：先 `ct_inst_find` 还原 `Box<int>`，失败才退回 C 拼写；T-4 断言 |
| RL1-R6 | trait 提供的 `get` 被误认成固有方法，改变派发语义 | `impl Trait for X` 里的 `get` | RL1-D2：只走 `inst_inherent_method`；T-3 加一条 trait `get` 负例 |
| RL1-R7 | 自举链用新语法编译编译器自身，L1/L2 不认 | `check-ast.sh` self-hosting 段红 | 编译器源码不使用该语法；只新增解析分支，T-7 跑 fixpoint |
