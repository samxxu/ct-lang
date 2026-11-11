# Phase 32 — 类型安全检查网：赋值、`return`、容器实参

> **状态：规划中**（2026-11-11 立项草案；**不写实现**）。
> **基线**：`v0.30.0` @ `bd91bfe`（`test(release): regenerate the goldens for v0.30.0`）；不 bump 版本、不打 tag。
> **文档形态**：本卡以 `phase32-draft.md` 落盘。`docs/design/` 现有 phase20–31 共 12 份编号卡，design window 已满 12/12；转正采用「每转正 k 张编号卡，按最老顺序归档 k 张」：本组 32–36 共 5 张全部转正时，需把 phase20–24 归档到 `docs/history/design/`（phase21 内含数十条相对链接，属独立收口工作）。评审通过后执行「重命名 + 归档 + 同步 README/roadmap 链接」，本次草案不抢跑。
> **deviation:** G4 `g4-size` 要求单份文档 ≤ 300 行；本卡承载范围、判定内核、三处挂点、判据/负例台账与估算，约 330 行，需需求提出方签字保留单卡。
> 关联：[phase31.md](phase31.md)（容器能力，P32 的前置）、[phase29.md](phase29.md)（泛型 struct / 内置容器）、[phase30.md](phase30.md)（`into` 赋值形态）、[modern-oo-gap.md](../modern-oo-gap.md) §6.1/§7（B 档与依赖关系）

## 1 目标与范围

### 1.1 一句话目标

`ct check --types` 从「只挡调用元数与既有粗粒度实参」扩展为一张**只覆盖三处位置**的类型安全网：声明初值/赋值、`return`、容器方法实参；`int x = "s";`、`return "s";`、`v.push("s")` 在 `ct check --types` 下给出 `.ct` 行列硬错，而 `ct build`/`ct compile` 的输出与 golden 保持逐字节不变。**不带 `--types` 的 `ct check` 保持今日行为逐字节不变**。

### 1.2 范围（O1–O4）

| 编号 | 范围 | 说明 |
| --- | --- | --- |
| O1 | 声明初值与赋值 | `T x = expr;`、`lhs = expr;`，含 Phase 30 `into` 块内的 `.field = expr`。左侧类型取声明类型或 `static_ctype(lhs)`；判不出即跳过 |
| O2 | `return` | 返回值与当前函数返回类型比对；同时覆盖 `return;`（非 void 缺值）与 `return expr;`（void 多值） |
| O3 | 容器方法实参 | `Vec::push/set`、`Map::put` 等**泛型 impl 方法**的实参；通过接收者的实例行绑定 impl 类型参数后替换形参，不按容器名分支 |
| O4 | 判定内核与覆盖率下限 | 以 19.2 的 `arg_class` 为唯一兼容内核；对全部单单元合法夹具跑 `ct check --types`，新增诊断必须为零；并用「位置 × 类型类」矩阵锁定覆盖率下限（见 §3.6） |

### 1.3 非目标（本相明确不做）

- 不建完整表达式类型系统；不引入类型变量、约束求解或推断。
- 不建模 C 的隐式转换等级、整型提升、位宽、符号性；算术类内部一律视为兼容（见 D32-5）。
- 不检查四类位置以外的类型错误：字段初值、下标表达式、条件/循环条件、`switch`、`sizeof`、`_Generic`、宏、指针基类型兼容（见 D32-6）。
- 不做流分析（定值到达、空指针、借用逃逸、生命周期）。
- 不在 `ct build` / `ct compile` 下新增任何诊断；不产生 warning，不改 golden。
- 不检查跨单元函数体；`ct check` 仍拒绝 `import`（`Parser.h.ct:1039-1042`）。
- 不改变现有 `argtype_check` 对普通函数调用与 trait 方法的结果；新检查只做加法。
- 不新增 `MAX_*`，不触碰冻结层 `l0/l1/l2`，不碰 `editors/vscode/**` 与其他会话在改的文件。

### 1.4 与既有决策/相位的边界

- **clap 形态**：`ct check` 新增 `--types` 开关；不带开关时 `check_mode` 只做既有检查，stderr 与退出码与基线逐字节一致。`--types` 只允许与 `check` 同用，其他子命令给可读硬错。
- **Phase 19 的延续**：`ct check` 由 `Driver.h.ct:171-178` 打开 `check_mode` 并 `ct_diag_set_strict(1)`；`Diag.h.ct:276` 在 strict 下把 warning 升级为 `error`。本相复用这条通道，不新建诊断层。
- **SH-60**：静态映射调用点的实参硬错保持现状（`Expr.h.ct:1191-1201`），本相不改。
- **Phase 31**：`Vec<Show>`、`Vec<Vec<int>>`、`v[i]`、花括号初值由 Phase 31 交付；本相只消费其结果。若 31 尚未落地，O3 只对既有 `Vec`/`Map` 形态生效，S1–S5 照常推进（见 §6 依赖）。
- **Phase 30**：`into` 块内的 `.f = expr` 走同一赋值挂点；`$ = expr` 若目标类型判不出则跳过。
- **D29/B29-3**：不得为 `Vec`/`Map` 写编译器特判；O3 必须走「实例行绑定 + 形参替换」的通用路径。

## 2 现状与基线（2026-11-11 实测）

### 2.1 门禁基线（`bd91bfe`，`v0.30.0`）

| 门禁 | 实测 |
| --- | --- |
| `bash selfhost/check-ast.sh` | **1073 passed / 0 failed** |
| `./test/run.sh` | **141 passed / 0 failed** |
| `bash selfhost/check-warnings.sh` | **353 ok / 0 failed** |
| `python3 test/docs/check-docs.py` | **OK**（1021 relative links / 180 files，11 hard gates，12 phase status，design window 12/12） |
| `examples/` 编号 | 最高 `29_into_block`；**30–34 已由 Phase 31 预占**，本相从 **35** 起排 |

### 2.2 红证探针

探针二进制为 `/tmp/ct-ast`（v0.26.4）。三处目标位置与 19.2 判定内核在 Phase 27–30 未改语义；实现前 S0 必须在 `bd91bfe` 重建的二进制上复跑同一组探针，**以 S0 的原始输出作为 T-7 红证**（本表只用于确认方向）。

| 探针 | 命令 | 基线 |
| --- | --- | --- |
| `int x = "s";` | `CT_STD_DIR=lib/std /tmp/ct-ast check /tmp/p32_assign.ct` | `rc=0`，无输出 |
| `int f(){ return "s"; }` | `… check /tmp/p32_return.ct` | `rc=0` |
| `Vec<int> v; v.push("s");` | `… check /tmp/p32_push.ct` | `rc=0` |
| `v.set(0,"s"); m.put("a","b");` | `… check /tmp/p32_container.ct` | `rc=0` |
| `struct A a; struct B b; a = b;` | `… check /tmp/p32_struct.ct` | `rc=0` |
| `int f(){ return; } void g(){ return 1; }` | `… check /tmp/p32_ret_void.ct` | `rc=0` |
| **正例**：`char *s="hi"; char *p=0; int x=1.5; void *v=s; Show sh=circle;` | `… check /tmp/p32_ok.ct` | `rc=0`（必须保持） |
| **泛型跳过**：`T id<T>(T x){ return x; }` | `… check /tmp/p32_generic.ct` | `rc=0`（必须保持） |

> 基线命令用 `ct check`（不带 `--types`）证明今日不查类型；实现后同一夹具改用 `ct check --types` 复跑并必须失败。`ct check --types` 在基线上应报未知选项（S0 记录原始退出码与文案），这是 `--types` 自身的红证。

### 2.3 可复用的既有内核

- `arg_class(formal, actual)`：`Expr.h.ct:491-521`。返回 `0` 兼容、`1` 明确不兼容、`2` 同类但基类型不同（由调用方按 struct 身份裁决）、`-1` 判不出。
- `argtype_mismatch`：`Expr.h.ct:1120-1173`。已内置跳过表：数组形参/实参、`N_CAST`、闭包实参、整型字面量 `0` 作空指针、接口引用、`expr_ctype` 判不出。**本相直接抽取这套跳过表，不另写一套。**
- `argtype_check`：`Expr.h.ct:1175-1184`，统一经 `ct_type_warn` 出诊断。
- `static_ctype`：`Expr.h.ct:3130-3255`，覆盖 `N_VAR`/`N_INDEX`/`N_DEREF`/`N_ADDR`/`N_MEMBER`/`N_ARROW`/`N_CALL`/`N_MCALL`；`depth>8` 返回 0。
- `expr_ctype`：`TypeCheck.h.ct:413`，覆盖字面量、`N_BOX`、`N_CAST`、`N_SIZEOF`、`N_INTO` 并保留数组维度。
- 结构体实例行：`ct_inst_add`（`Expr.h.ct:1920`）保存 `name/tmpl/c1/c2`，O3 用它取实参。
- 泛型 impl 匹配：`ct_impl_matches`（`Symbols.h.ct:1648-1676`），O3 需要把「bool」扩成「绑定表」（见 §3.3）。

## 3 判定设计

### 3.1 表达式静态类型（`chk_type`）

新增一个**只读**入口 `chk_type(expr, out, cap)`，返回 0 表示判出、非 0 表示不可判：

| 形态 | 结果 |
| --- | --- |
| `N_NUM` | `int`（保留 `num` 值，供空指针 0 判定） |
| `N_FNUM` | `double` |
| `N_STR` | `char *` |
| 字符字面量 | 沿用 `expr_ctype` 的现有归类 |
| `N_VAR` | 声明类型（局部/形参/全局，经符号表） |
| `N_MEMBER` / `N_ARROW` | 字段类型（现有 struct 表） |
| `N_DEREF` / `N_ADDR` / `N_INDEX` | 每次剥/加一层（沿用 `static_ctype`） |
| `N_CALL` / `N_MCALL` | 返回类型 |
| `N_CAST` | 目标类型 |
| `N_BOX` | 接口类型 |
| `N_INTO` | 接收者类型 |
| `N_BIN` | 两侧均为算术类 → 算术类；否则不可判 |
| `N_COND` | 两支同类同基 → 该类；否则不可判 |
| 其他 | 不可判 |

**唯一规则**：`chk_type` 判不出就返回非 0，调用方静默跳过。不得用字符串前缀猜类型，不得读 `strstr` 猜 `(*`（V29-4 的教训）；所有判定必须来自符号表或既有 `static_ctype`。

### 3.2 兼容判定（`chk_assignable`）

```
chk_assignable(formal, actual, struct_ctx):
  if formal 为空 or actual 为空: 跳过
  if 形参是接口引用: 跳过            # 已有装箱路径，避免误报
  if actual 是数组/闭包/CAST: 跳过   # 沿用 argtype_mismatch 跳过表
  if actual 是字面量 0 且 formal 含 '*': 通过
  r = arg_class(formal, actual)
  r == 0 -> 通过
  r == 2 -> 仅当双方都是同一 struct（find_struct 相等）时通过，否则跳过
  r == 1 -> 报不匹配
  r == -1 -> 跳过
```

- **算术类**：`arg_class` 的类划分已把算术类型归为一类（`cf == 0 && ca == 0` → 0），因此 `int x = 1.5`、`long n = 1` 不会误报；本相不额外建模提升规则。
- **指针**：不同基类型的指针在 `arg_class` 下返回 2，非 struct 基座经 `find_struct` 判不出 → `-1` → 跳过。这是**有意边界**（D32-6），不扩大到 `char *` vs `int *`。
- **结构体**：同名 struct 通过；不同 struct 明确报错；struct → 接口由 `iface_ref_type` 跳过，交给既有装箱。
- **void**：`arg_class` 对 void 返回 `-1`，因此 O2 的「缺值/多值」必须单独判（见 §3.4）。

### 3.3 O3 容器实参：绑定 + 替换，不按容器名分支

在 `Expr.h.ct:3514-3520` 的固有方法分支（目前只查元数与 own/借用/容器守卫）追加：

1. 取接收者的 `ibase`（如 `struct Vec_int`），在 `ct_insts[]` 找到实例行，读出 `tmpl` 与 `c1/c2`。
2. 在 `ct_impls[]` 找到该方法的 impl 行，按位置把 impl 的 `tp[0..n)` 绑定到 `c1/c2`；新增 `ct_impl_bind(impl_idx, inst_idx, binds)`，`ct_impl_matches` 改为它的薄包装，避免两套算法漂移。
3. 对每个形参类型做**受限替换**：仅当形参是裸 `T`/`U` 或 `T *`/`U *` 时替换；含其他结构（如 `Vec<T>`、函数指针）则标记该位置不可判并跳过。本相只需覆盖 `push(T)`、`set(int, T)`、`put(K, V)` 一类裸形参。
4. 对替换后的形参调用 `chk_assignable`，诊断文案沿用 `argument %d: expected '%s', got '%s'`，由 `ct_type_warn` 统一出。

这样 `Vec`/`Map` 与用户自定义 `Pair<A,B>` 走同一条路径，满足 B29-3；E32-11 用用户泛型 struct 反证没有容器特判。

### 3.4 O2 `return`

- 新增 `Parser.cur_ret[MAX_TEXT]`，在 `parse_func` 入口保存、出口恢复；trait 默认方法与普通函数共用。
- `parse_return`（`Stmt.h.ct:1071-1078`）：
  - 无返回值 + `cur_ret` 非 `void` → L32-4；
  - 有返回值 + `cur_ret == void` → L32-5；
  - 有返回值 + 非 void → `chk_assignable(cur_ret, chk_type(expr))`；
  - `cur_ret` 为空/含泛型参数/判不出 → 跳过。

### 3.5 诊断与开关

- `Driver.h.ct` 的 `check` 分支解析 `--types`，置 `types_mode=1`；解析器新增 `types_mode` 字段并在 `check` 路径透传。**不带 `--types` 时不进入本相任何新检查**；`ct build` / `ct compile` 也不进入，因此不产生 warning、不改 golden。
- `--types` 只与 `check` 组合；其他子命令携带时报可读硬错（L32-8），不静默忽略。
- 文案（统一 `file:line:col`，列指向表达式起点；缺值指向 `return` 关键字）：

| 编号 | 文案 |
| --- | --- |
| L32-1 | `initializer: expected '<T>', got '<U>'` |
| L32-2 | `assignment: expected '<T>', got '<U>'` |
| L32-3 | `return: expected '<T>', got '<U>'` |
| L32-4 | `return: missing a value (function returns '<T>')` |
| L32-5 | `return: a value is not allowed in a void function` |
| L32-6 | `argument <n>: expected '<T>', got '<U>'`（容器方法） |
| L32-7 | `initializer: a struct value does not use the interface '<T>'`（仅在 `use` 缺失且接口形态明确时） |
| L32-8 | `--types is only valid with 'ct check'` |

L32-7 只在左侧是接口、右侧是具体 struct 且 `use` 列表不含该 trait 时触发；若 `iface_ref_type` 判不出则跳过，避免与既有装箱诊断重复。

### 3.6 覆盖率下限（可观测断言）

覆盖率定义为 **3 个位置 × 8 个来源类型类** 的矩阵：位置 = 声明/赋值、`return`、容器实参；类型类 = 算术、指针、结构体、接口、数组、函数指针、`void`、不可判。共 24 格。

- 落盘 `test/ast/check_coverage.tsv`，每行 `位置<TAB>类型类<TAB>diag:<夹具>` 或 `位置<TAB>类型类<TAB>skip:<理由>`。
- 每个 `diag` 夹具必须在 `ct check --types` 下产出对应 L32-n；每个 `skip` 夹具必须保持退出 0 且理由可读。
- **下限断言**：`diag` 格数 ≥ **18**（75%），`skip` 格数 ≤ **6**；24 格必须全部登记，缺格即失败；`skip` 不得用于「本该判却判不出」的类型类。
- `check-ast.sh` 新增 `p32_coverage`，解析该 TSV 并逐行执行，最终打印 `coverage: <diag>/24 (skip=<n>)`；低于下限直接 `fail`。

## 4 决策表

| 编号 | 决策 | 理由 |
| --- | --- | --- |
| D32-1 | `--types` opt-in；不带开关的 `ct check` 与今日逐字节一致 | 安全网关定位；避免既有 check 输出与 CI 断言漂移 |
| D32-2 | `arg_class` 是唯一兼容内核 | 一条规则四处复用，防止 check 与 19.2 分叉 |
| D32-3 | 声明初值并入赋值位置 | 用户给出的 `int x = "s"` 正是初值形态 |
| D32-4 | 判不出 → 静默跳过 | opt-in 安全网，不做推测性报错 |
| D32-5 | 算术类内部互相兼容，不校验位宽 | 不碰隐式转换规则；避免 `int x = 1.5` 误报 |
| D32-6 | 指针基类型不校验（`char *` vs `int *` 跳过） | C 语料大量 `void *`/回调转换；本相不扩大打击面 |
| D32-7 | struct 只认同名；struct→接口交给 `use`/装箱 | 复用既有语义，不另立规则 |
| D32-8 | 容器实参走 impl 绑定 + 形参替换 | 满足 B29-3；用户泛型 struct 同样受益 |
| D32-9 | 不改变普通调用与 trait 方法的既有结果 | 新检查只做加法 |
| D32-10 | 单单元；`ct build` 跨单元体不查 | `ct check` 本就拒绝 `import` |
| D32-11 | 不新增 `MAX_*`；只加 `cur_ret`/`check_types` 两个字段 | 控制解析器结构体膨胀 |
| D32-12 | 新诊断一律经 `ct_type_warn` | strict 自动升级为 error，check 退出码已有保证 |

## 5 Battle 记录

### B32-1 精确类型相等 vs 粗粒度类 vs 完整转换模型
采纳**粗粒度类**。精确相等会让 `long n = 1`、`int x = 1.5` 全部误报；完整转换模型超出 500–1,000 行预算且违背「不碰隐式转换规则」。粗粒度类足以命中三个目标 bug。

### B32-2 check-only vs 编译期 warning
采纳 **check-only**。若 `ct build` 也出 warning，`check-warnings.sh` 的 353 条计数与大量既有样例的 stderr 都会变，golden 也要重生成；与「安全网 opt-in」的定位冲突。

### B32-3 是否包含声明初值
包含。`int x = "s";` 是用户点名的第一形态；不包含会让 P32 的核心样例无法红。

### B32-4 是否校验不同基类型的指针
不校验。`arg_class` 对非 struct 基座返回 `-1`，沿用跳过即可；强行判会与 C 语料的 `void *`、函数指针转换冲突。登记为 T32-2。

### B32-5 容器实参：按方法名特判 vs impl 绑定替换
采纳**绑定替换**。按 `push`/`put` 名字分支违反 B29-3，且用户泛型 struct 无法受益；绑定替换只依赖实例行与 impl 形参，规模更小。

### B32-6 字面量 0 是否允许赋给指针
允许。C 的空指针常量惯用法；`argtype_mismatch` 已有同一跳过规则（`Expr.h.ct:1148-1152`），保持一致。

### B32-7 `return` 在泛型函数/默认方法中的处理
`cur_ret` 含类型参数或判不出时跳过。不在本相引入类型变量替换；E32-7 用 `T f<T>(T x){ return x; }` 锁定「不误报」。

## 6 实现切片（每片独立提交，仓库随时可构建）

| 片 | 内容 | 主要文件 | 预估行 |
| --- | --- | --- | --- |
| S0 | 在 `bd91bfe` 重建二进制，复跑 §2.2 全部探针，贴原始输出（红证） | 无源码改动 | 0 |
| S1 | `chk_type` + 字面量归类 + 不可判返回 | `Expr.h.ct` | 120–200 |
| S2 | 声明初值挂点 + L32-1 | `Stmt.h.ct` | 40–80 |
| S3 | 赋值挂点（含 `into` 块）+ L32-2 | `Expr.h.ct` / `Stmt.h.ct` | 50–90 |
| S4 | `cur_ret` + `return` 三形态 + L32-3/4/5 | `Parser.h.ct` / `Stmt.h.ct` | 60–100 |
| S5 | `ct_impl_bind` + 形参替换 + 固有方法挂点 + L32-6 | `Expr.h.ct` / `Symbols.h.ct` | 100–180 |
| S6 | `--types` 解析 + `types_mode` 透传 + 诊断收口 + L32-7/8 | `Driver.h.ct` / `Parser.h.ct` / `Diag.h.ct` | 50–100 |
| S7 | 负例夹具 + `check-ast.sh` 新增 `p32_*` 断言块（逐字 grep + 恰一条 + 位置）+ `p32_coverage` | `test/ast/errors/**` / `test/ast/check_coverage.tsv` / `selfhost/check-ast.sh` | 180–300 |
| S8 | 单单元合法语料全量清账：对 S0 基线做 diff，新增诊断必须为 0 | 夹具/内核修正 | 80–200 |
| S9 | 样例 `examples/35_type_safety` + `test/run.sh` | `examples/35_*` | 60–120 |
| S10 | 文档（language-spec/glossary/tutorial/roadmap）+ 全量门禁 | `docs/**` | 140–260 |

依赖：S1→S2/S3/S4/S5；S6 可与 S2 并行；S8 必须在 S7 之后、S9 之前。O3 依赖 Phase 31 落地后的容器形态；31 未落地时 S1–S4、S6–S10 照常，S5 只覆盖既有 `Vec`/`Map`。

## 7 退出判据（E32-n）

每条都必须给出夹具、门禁与红证；「判不出就跳过」不算通过，必须有正例锁定。下表所有 `check` 均指 **`ct check --types`**；不带 `--types` 的基线行为由 E32-10 锁定。

| ID | 断言 | 夹具 | 门禁 | 红证 |
| --- | --- | --- | --- | --- |
| E32-1 | `int x = "s";` 在 check 下恰一条 L32-1，位置为表达式起点，退出码非 0 | `errors/check_init_mismatch.ct` | `check-ast.sh` | 基线 `rc=0`（§2.2） |
| E32-2 | `x = "s";` 恰一条 L32-2；`into { .f = "s"; }` 同样命中 | `errors/check_assign_mismatch.ct` | `check-ast.sh` | 基线 `rc=0` |
| E32-3 | `struct A a; struct B b; a = b;` 恰一条 L32-2 | `errors/check_struct_assign.ct` | `check-ast.sh` | 基线 `rc=0` |
| E32-4 | `int f(){ return "s"; }` → L32-3；`int f(){ return; }` → L32-4；`void g(){ return 1; }` → L32-5 | `errors/check_return_*.ct` | `check-ast.sh` | 基线 `rc=0` |
| E32-5 | `Vec<int> v; v.push("s");` → L32-6；`v.set(0,"s")` → L32-6；`Map<char *,int> m; m.put("a","b")` → L32-6 | `errors/check_container_arg.ct` | `check-ast.sh` | 基线 `rc=0` |
| E32-6 | 正例 `char *s="hi"; char *p=0; int x=1.5; long n=1; void *v=s; Show sh=circle;` check 退出 0 | `ast/209_valid_assignments`（`prog.ct` + `expected.out`） | `check-ast.sh` | 当前 `rc=0`，实现后必须仍为 0 |
| E32-7 | 泛型/闭包/函数指针/接口实际值不误报：`T id<T>(T x){return x;}`、`f(cb)`、`Show s=circle` 均退出 0 | `ast/210_valid_skip_forms` | `check-ast.sh` | 当前 `rc=0` |
| E32-8 | 诊断格式 `file:line:col`，列指向表达式；同一夹具的 compile 路径无新增输出 | `errors/check_*.ct` + `p32_*` 断言块 | `check-ast.sh` | 编译 stderr 为空 |
| E32-9 | 对 S0 的 `/tmp/p32_check_baseline.txt` 做 diff：单单元合法语料的新增诊断 = 0；既有错误夹具的期望消息仍存在且不新增无关诊断 | 全量语料 | `check-ast.sh` | 基线 1073 passed；diff 文件为 S0 原始输出 |
| E32-10 | `ct build` / `ct compile` 的 `.c` 与 golden 逐字节不变；不带 `--types` 的 `ct check` stderr/退出码与基线逐字节一致；`check-warnings` 仍 353 ok | 全量 | `test/run.sh` + `check-warnings.sh` | 基线 141 / 353 |
| E32-11 | 用户泛型 struct `Pair<A,B>` 的 `set` 实参错同样被 L32-6 拦截，证明无 `Vec`/`Map` 特判 | `errors/check_generic_arg.ct` | `check-ast.sh` | 当前 `rc=0` |
| E32-12 | 样例 `examples/35_type_safety` 进入 `test/run.sh`，golden 由编译器生成并人工核对 | `examples/35_type_safety` | `test/run.sh` | 样例当前不存在 |
| E32-13 | language-spec/glossary/tutorial 写清「check 是 opt-in，只覆盖三处，指针基类型不查」；roadmap 行落地 | `docs/**` | `check-docs` | 文档当前无此表述 |
| E32-14 | `check-all.sh` 11 道硬门禁全绿；`check-ast` / `test/run` / `goldens` / `warnings` 计数不回退 | 全量 | `check-all.sh` | 基线见 §2.1 |
| E32-15 | 覆盖率下限：`check_coverage.tsv` 24 格全登记，`diag ≥ 18`、`skip ≤ 6`，`p32_coverage` 打印 `coverage: <n>/24` 且不失败 | `test/ast/check_coverage.tsv` | `check-ast.sh` | 当前无矩阵，`coverage` 行不存在 |

## 8 负例台账（L32-n）

| 编号 | 触发 | 文案要点 |
| --- | --- | --- |
| L32-1 | 声明初值不兼容 | `initializer: expected 'int', got 'char *'` |
| L32-2 | 赋值不兼容（含 `into` 字段） | `assignment: expected 'int', got 'char *'` |
| L32-3 | `return` 值不兼容 | `return: expected 'int', got 'char *'` |
| L32-4 | 非 void 缺返回值 | `return: missing a value (function returns 'int')` |
| L32-5 | void 多返回值 | `return: a value is not allowed in a void function` |
| L32-6 | 容器/泛型方法实参不兼容 | `argument 1: expected 'int', got 'char *'` |
| L32-7 | 接口初值来自未 `use` 该 trait 的 struct | `initializer: a struct value does not use the interface 'Show'` |
| L32-8 | `--types` 与错误子命令组合 | `--types is only valid with 'ct check'` |

## 9 样例计划

- **`examples/35_type_safety`**（本相唯一必需样例，进 `test/run.sh`）：一个可运行程序，覆盖正例三角：声明/赋值（含 `into` 字段赋值）、`return`（含 void 与非 void）、`Vec`/`Map` 实参；结构体、接口、指针、算术类各至少一例。输出确定、可逐字节比对。
- 反例不放进样例，统一进 `test/ast/errors/`，由 `check-ast.sh` 断言；样例本身在 `ct check` 下必须零诊断（E32-9）。
- 编号：`examples/30–34` 已由 Phase 31 预占，本相只用 **35**；36 起留给 Phase 33。

## 10 估算（`git diff --shortstat` 标尺）

### 10.1 校准（实测）

| 相 | 编译器 | 夹具 | 文档 |
| --- | --- | --- | --- |
| Phase 29 | 3,658 行 / 8 文件 | 1,697 行 / 68 文件 | 733 行 / 6 文件 |
| Phase 30 | 807 行 / 7 文件 | 1,553 行 / 97 文件 | 1,101 行 / 11 文件 |

### 10.2 Phase 32

| 区 | 行数 | 文件数 |
| --- | --- | --- |
| 编译器（S1–S6） | **500–1,000**（用户口径） | 4–6 |
| 夹具与门禁（S7–S8） | 300–560 | 15–26 |
| 文档与样例（S9–S10） | 140–260 + 60–120 | 5–7 |
| **合计** | **1,000–1,940** | **24–39** |

## 11 风险与触发条件

| 编号 | 风险 | 处置 |
| --- | --- | --- |
| R32-1 | 合法 C 惯用法误报 | 复用 `argtype_mismatch` 跳过表；S8 全量清账；误报必须修内核或登记 T32-x，不得用默认关闭掩盖 |
| R32-2 | check 与编译行为分叉 | `check_types` 单一开关；E32-10 锁死 golden 与 warning 计数 |
| R32-3 | 字面量/枚举/字符类型归类不全 | `chk_type` 判不出即跳过；E32-6 正例锁定 |
| R32-4 | 泛型 impl 绑定顺序错 | 用 `impl<U> Box<U>` 与 `Pair<A,B>` 双夹具；E32-11 |
| R32-5 | 既有错误夹具多出诊断 | E32-9 要求期望消息仍在且无无关诊断；新增真阳性必须写进夹具 |
| R32-6 | `cur_ret` 在嵌套函数/默认方法中泄漏 | 入口保存、出口恢复；trait 默认方法与普通函数共用 |
| R32-7 | `into` 赋值漏检 | S3 明确覆盖；E32-2 |
| R32-8 | 跨单元 `ct build` 被误改 | O3 只在单单元 check 路径；D32-10 |

### 开放项 / 触发条件

| 编号 | 内容 | 触发条件 |
| --- | --- | --- |
| T32-1 | 指针基类型兼容（`char *` vs `int *`） | 出现真实误用且 31 的容器元素形态稳定 |
| T32-2 | 字段/下标/条件位置 | 三处位置零误报运行一个发布周期后 |
| T32-3 | 流分析（空指针、定值到达） | 有独立设计卡与预算 |
| T32-4 | 跨单元函数体检查 | `ct check` 支持 `import` 后 |

## 12 交付物清单

- `selfhost/ct-ast/**`：S1–S6 的实现与诊断。
- `test/ast/errors/check_*.ct`：L32-1–L32-8 负例；`selfhost/check-ast.sh` 新增 `p32_*` 断言块（逐字文案 + 恰一条 + 位置）。
- `test/ast/check_coverage.tsv` + `p32_coverage`：24 格覆盖率矩阵与下限断言。
- `test/ast/209_valid_assignments/`、`test/ast/210_valid_skip_forms/`：正例与跳过形态（`prog.ct` + `expected.out`）。
- `examples/35_type_safety/` + golden：唯一可运行样例。
- `docs/language-spec.md`、`docs/glossary.md`、`docs/tutorial.md`：opt-in 与三处边界。
- `docs/roadmap.md`：Phase 32 中英两行（本卡落地时）。
- `docs/README.md`：设计索引（与 window 归档一并做）。

## 13 收口与纪律

- **T-7 先红后绿**：S0 在 `bd91bfe` 重建二进制复跑探针，提交 `test(check): P32 红证`；随后按片实现，每片 `check-ast.sh` 或 `test/run.sh` 通过即提交。
- 每片 ≤3 文件、净增尽量 ≤150 行；仓库任何时刻可构建。
- 不改判据、不改 golden、不改版本号凑绿；不 bump、不打 tag、不 push。
- 只暂存本相文件；`editors/vscode/**`、`docs/design/phase31.md` 与其他会话在改的文件一律不碰。
- 收口跑 `bash selfhost/check-all.sh`，贴末行 VERDICT 与关键计数；未满足的判据必须回退状态，不得用「偏差表」包装为完成。
