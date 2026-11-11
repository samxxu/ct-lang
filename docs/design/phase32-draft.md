# Phase 32 — 类型安全检查网：赋值、`return`、容器实参

> **状态：规划中**（2026-11-11 立项草案；**不写实现**）。
> **基线**：**Phase 31 收口提交**（S0 开工时记录实际 sha）。Phase 31 的容器形态与元素助手是本相 O3 的前置；`bd91bfe` 上这些能力尚不存在，不得作为基线。
> **红证**：红证提交必须是**实现提交的父提交**；S0 在 Phase 31 收口提交上重建二进制、复跑 §2.2 探针，并把脚本与基线清单随红证提交入库。
> **文档形态**：`phase32-draft.md`。转正按「每次转正归档当时最老的一张」：32 转正时归档 `phase20`，33 转正时归档 `phase21`，依此类推；本卡不抢跑。
> **deviation:** G4 `g4-size` 要求单份文档 ≤ 300 行；本卡承载判定内核、三处挂点、精确覆盖率集合与判据/负例台账，约 370 行。按自裁 **waiver** 保留单卡（判定内核、矩阵、判据、负例必须同卡才能互相对照），不再寻求需求提出方签字。
> 关联：[phase31.md](phase31.md)（容器能力，O3 前置）、[phase29.md](phase29.md)（泛型 struct / 内置容器）、[phase30.md](phase30.md)（`into` 赋值形态）、[modern-oo-gap.md](../modern-oo-gap.md) §6.1/§7

## 1 目标与范围

### 1.1 一句话目标

`ct check --types` 在**三处位置**提供粗粒度类型安全网：声明初值/赋值、`return`、容器方法实参；`int x = "s";`、`return "s";`、`v.push("s")` 给出 `.ct` 行列硬错。**不带 `--types` 的 `ct check` 与今日逐字节一致**，`ct build`/`ct compile` 的输出与 golden 不变。

### 1.2 范围（O1–O4）

| 编号 | 范围 | 交付 |
| --- | --- | --- |
| O1 | 声明初值与赋值 | `T x = expr;`、`lhs = expr;`，含 Phase 30 `into` 块内的 `.field = expr` |
| O2 | `return` | 返回值与当前函数返回类型比对；覆盖 `return;`（非 void 缺值）与 `return expr;`（void 多值） |
| O3 | 容器方法实参 | `Vec::push/set`、`Map::put` 等**泛型 impl 方法**的实参；经接收者实例行绑定 impl 类型参数后替换形参，不按容器名分支 |
| O4 | 判定内核与覆盖率下限 | 以 19.2 的 `arg_class` 为唯一兼容内核；新增诊断在合法语料上为零；用可执行的 24 行矩阵锁定 L32-n 覆盖（§3.6） |

### 1.3 非目标（本相明确不做）

- 不建完整表达式类型系统；不引入类型变量、约束求解或推断。
- 不建模 C 的隐式转换等级、整型提升、位宽、符号性；算术类内部一律兼容（D32-5）。
- 不检查四类位置以外：字段初值、下标、条件/循环条件、`switch`、`sizeof`、`_Generic`、宏、指针基类型（D32-6）。
- 不做流分析（定值到达、空指针、借用逃逸、生命周期）。
- 不在 `ct build` / `ct compile` 下新增任何诊断；不产生 warning，不改 golden。
- 不检查跨单元函数体；`ct check` 仍拒绝 `import`。
- 不改变现有 `argtype_check` 对普通调用与 trait 方法的结果；新检查只做加法。
- 不新增 `MAX_*`，不触碰冻结层 `l0/l1/l2`，不碰 `editors/vscode/**` 与其他会话在改的文件。

### 1.4 与既有决策/相位的边界

- **CLI**：`ct check` 新增 `--types`；不带开关时 `check_mode` 只做既有检查，stderr 与退出码与基线逐字节一致。`--types` 只允许与 `check` 同用，其他子命令给 L32-7。
- **Phase 19**：`ct check` 由 `selfhost/ct-ast/tool/driver/Driver.h.ct` 的 `check` 分支打开 `check_mode` 并 `ct_diag_set_strict(1)`；strict 下 warning 升级为 `error`。本相复用这条通道。
- **SH-60**：静态映射调用点的实参硬错保持现状。
- **Phase 31**：`Vec<Show>`、`Vec<Vec<int>>`、`v[i]`、花括号初值由 31 交付；本相只消费其结果。31 未收口时本相不开工，不得用旧容器形态替代。
- **Phase 30**：`into` 块内 `.f = expr` 走同一赋值挂点。
- **B29-3**：不得为 `Vec`/`Map` 写编译器特判；O3 必须走「实例行绑定 + 形参替换」的通用路径。

## 2 现状与基线

### 2.1 门禁快照（2026-11-11，仅作参考；S0 在 Phase 31 收口提交上重测）

| 门禁 | 实测 |
| --- | --- |
| `bash selfhost/check-ast.sh` | **1073 passed / 0 failed** |
| `./test/run.sh` | **141 passed / 0 failed** |
| `bash selfhost/check-warnings.sh` | **353 ok / 0 failed** |
| `python3 test/docs/check-docs.py` | **OK**（1070 relative links in 185 files，11 hard gates，12 phase status，design window 12/12；2026-11-11 本树实测） |
| `examples/` 编号 | 最高 `29_into_block`；**30–34 由 Phase 31 预占**，本相用 **35** |

> 这些数字只用于确认量级；Phase 31 落地会改变断言数与链接数，**S0 必须重测并把实际值写进红证提交**。

### 2.2 红证探针

探针二进制为 `/tmp/ct-ast`（v0.26.4），仅用于确认方向；S0 在 Phase 31 收口提交上重建二进制后必须复跑，**以 S0 原始输出为 T-7 红证**。`test/probes/` 当前**不存在**，由 S0 交付：`p32_check_baseline.sh` 在 `test/probes/fixtures/` 生成下表全部源码，把 `check` / `check --types` 的退出码与 stderr 写入 `test/probes/p32_check_baseline.txt`，并生成 `test/probes/p32_legal_manifest.tsv`（§7 E32-15 的显式清单）。表中的 `/tmp/p32_*.ct` 只是本地临时路径，不构成红证。

| 探针 | 命令 | 基线 |
| --- | --- | --- |
| `int x = "s";` | `CT_STD_DIR=lib/std /tmp/ct-ast check /tmp/p32_assign.ct` | `rc=0` |
| `int f(){ return "s"; }` | `… check /tmp/p32_return.ct` | `rc=0` |
| `Vec<int> v; v.push("s");` | `… check /tmp/p32_push.ct` | `rc=0` |
| `v.set(0,"s"); m.put("a","b");` | `… check /tmp/p32_container.ct` | `rc=0` |
| `struct A a; struct B b; a = b;` | `… check /tmp/p32_struct.ct` | `rc=0` |
| `int f(){ return; } void g(){ return 1; }` | `… check /tmp/p32_ret_void.ct` | `rc=0` |
| **正例**：`char *s="hi"; char *p=0; int x=1.5; void *v=s; Show sh=circle; struct A *pa; char *pc = pa;` | `… check /tmp/p32_ok.ct` | `rc=0`（必须保持） |
| **既有诊断**：`Show sh = o;`（`Other` 未 `use Show`） | `… check /tmp/p32_iface.ct` | `5:16: error: the struct does not use this trait`，`rc=1`；`--types` 下必须仍是**同一条** |
| **n/a 探针 1**：`void x;` | `… check /tmp/p32_void_var.ct` | 语法错（assign×void 不成立） |
| **n/a 探针 2**：`Vec<void> v;` | `… check /tmp/p32_vec_void.ct` | 语法/实例错（container×void 不成立；S0 记录原始文案） |
| **泛型跳过**：`T id<T>(T x){ return x; }` | `… check /tmp/p32_generic.ct` | `rc=0`（必须保持） |

> 基线命令用 `ct check`（不带 `--types`）证明今日不查类型；实现后改用 `ct check --types` 复跑并必须失败。`ct check --types` 在基线上应报未知选项，S0 记录原始退出码与文案。**L32-7 已删除**：既有装箱诊断已覆盖 `Show sh = o;`，本相不得新增第二条。

### 2.3 关键代码锚点（以符号名为准；Phase 31 已让行号漂移）

| 主题 | 位置（符号） |
| --- | --- |
| `arg_class` / `argtype_mismatch` / `argtype_check` | `selfhost/ct-ast/frontend/parse/Expr.h.ct` |
| `static_ctype` | `selfhost/ct-ast/frontend/parse/Expr.h.ct` |
| `expr_ctype` | `selfhost/ct-ast/frontend/type/TypeCheck.h.ct` |
| `check` 子命令 / `check_mode` | `selfhost/ct-ast/tool/driver/Driver.h.ct` |
| `ct_type_warn` / strict 升级 | `selfhost/ct-ast/tool/diag/Diag.h.ct` |
| `parse_decl_node` / `parse_return` | `selfhost/ct-ast/frontend/parse/Stmt.h.ct` |
| `ct_inst_add`（实例行 `c1/c2`） | `selfhost/ct-ast/frontend/parse/Expr.h.ct` |
| `ct_impl_matches` | `selfhost/ct-ast/frontend/sym/Symbols.h.ct` |

## 3 判定设计

### 3.1 表达式静态类型（`chk_type`）

新增只读入口 `chk_type(expr, out, cap)`，返回 0 表示判出、非 0 表示不可判：

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

**唯一规则**：判不出就返回非 0，调用方静默跳过。不得用字符串前缀猜类型，不得读 `strstr` 猜 `(*`；所有判定来自符号表或既有 `static_ctype`/`expr_ctype`。

### 3.2 兼容判定（`chk_assignable`）

```
chk_assignable(formal, actual, struct_ctx):
  if formal 为空 or actual 为空: 跳过
  if 形参是接口引用: 跳过            # 已有装箱路径
  if actual 是数组/闭包/CAST: 跳过   # 沿用 argtype_mismatch 跳过表
  if actual 是字面量 0 且 formal 含 '*': 通过
  r = arg_class(formal, actual)
  r == 0 -> 通过
  if formal 含 '*' 且 actual 含 '*': 跳过   # 两侧都是指针：只比指针层数，基类型不校验（D32-6）
  r == 2 -> 双方都在 struct 表命中 -> 报 L32-2；任一判不出 -> 跳过
  r == 1 -> 报不匹配
  r == -1 -> 跳过
```

- **指针守卫放在 `r==2` 之前、`r==1` 之前**：`arg_class` 对 `struct A *` vs `char *` 返回 **1**（双方指针层数相同、类不同），对 `struct A *` vs `struct B *` 返回 **2**；两者都必须在 `r != 0` 时跳过，否则分别误报 L32-1/L32-2 与 L32-2。守卫条件是“**两侧都是指针**”而不是“任一侧”：`int x = "s"` 只有实际侧是 `char *`，必须继续走 `r==1` 报 L32-1，否则 E32-1 变成死判据（B32-8）。`void *` 双向转换由 `arg_class` 在 `r==0` 处先放行。
- **`r == 2` 的语义**：`arg_class` 对同名同基已返回 0；返回 2 只可能是**不同 struct**。因此 `struct A a; struct B b; a = b;` 必须报 L32-2，不能走「同一 struct 才通过」的死分支。
- **算术类**：`arg_class` 把算术类型归为一类，`int x = 1.5`、`long n = 1` 不误报；不额外建模提升。
- **结构体**：不同 struct 明确报错；struct → 接口由 `iface_ref_type` 跳过，交给既有装箱。
- **void**：`arg_class` 对 void 返回 `-1`，O2 的缺值/多值单独判（§3.4）。
- **已删除 L32-7**：`Show sh = o;`（`Other` 未 `use Show`）在既有 `ct check` 下已报 `the struct does not use this trait`；本相不再新增任何接口初值诊断，E32-10 只断言“仍恰一条且 `--types` 不追加”。

### 3.3 O3 容器实参：绑定 + 替换，不按容器名分支

在 `Expr.h.ct` 的固有方法调用分支（当前只查元数与 own/借用/容器守卫）追加：

1. 取接收者的 `ibase`（如 `struct Vec_int`），在 `ct_insts[]` 找到实例行，读出 `tmpl` 与 `c1/c2`。
2. 在 `ct_impls[]` 找到该方法 impl，按位置把 `tp[0..n)` 绑定到 `c1/c2`；**新增 `ct_method_bind`**（注意：Phase 33 的 `ct_impl_bind` 是 pattern 匹配器，两者语义不同，不得同名）。
3. 形参做**受限替换**：仅裸 `T`/`U` 或 `T *`/`U *` 替换；其他结构标记不可判并跳过。本相只需覆盖 `push(T)`、`set(int, T)`、`put(K, V)`。
4. 对替换后的形参调用 `chk_assignable`，文案沿用 `argument %d: expected '%s', got '%s'`，由 `ct_type_warn` 统一出。

### 3.4 O2 `return`

- 新增 `Parser.cur_ret[MAX_TEXT]`，在 `parse_func` 入口保存、出口恢复；trait 默认方法与普通函数共用。
- `parse_return`：无返回值 + `cur_ret` 非 `void` → L32-4；有返回值 + `cur_ret == void` → L32-5；有返回值 + 非 void → `chk_assignable(cur_ret, chk_type(expr))`；`cur_ret` 为空/含泛型参数/判不出 → 跳过。
- **错误路径没有“恢复后继续解析”**：解析器遇到硬错走 `die` 直接终止，`cur_ret` 的保存/恢复只服务正常返回路径；不新增错误恢复状态机（与现有 `die` 语义一致）。

### 3.5 诊断与开关

- `Driver.h.ct` 的 `check` 分支解析 `--types`，置 `types_mode=1`；解析器新增 `types_mode` 字段并透传。不带 `--types` 时不进入本相任何新检查；`ct build`/`ct compile` 也不进入。
- `--types` 只与 `check` 组合；其他子命令 → L32-7，不静默忽略。
- 文案（统一 `file:line:col`，列指向表达式起点；缺值指向 `return` 关键字）：

| 编号 | 文案 |
| --- | --- |
| L32-1 | `initializer: expected '<T>', got '<U>'` |
| L32-2 | `assignment: expected '<T>', got '<U>'` |
| L32-3 | `return: expected '<T>', got '<U>'` |
| L32-4 | `return: missing a value (function returns '<T>')` |
| L32-5 | `return: a value is not allowed in a void function` |
| L32-6 | `argument <n>: expected '<T>', got '<U>'`（容器/泛型方法） |
| L32-7 | `--types is only valid with 'ct check'` |

> 原 L32-7（接口初值未 `use` trait）**已删除**：既有 `ct check` 已报 `the struct does not use this trait`，新增会违反“恰一条”和“新增为零”。CLI 诊断（L32-7）不是源码诊断，不参与 `file:line:col` 断言。

### 3.6 覆盖率矩阵（可执行）

矩阵固定为 **3 位置 × 8 实际类型类 = 24 行**，落盘 `test/ast/check_coverage.tsv`，列：

```
position  actual_class  result  fixture  expected
assign    pointer       L32-1   errors/check_init_ptr.ct  initializer: expected 'int', got 'char *'
```

- `result` ∈ `L32-n`（可判） / `ok`（合法） / `skip:<理由>`（现有跳过表） / `n/a:<理由>`（语法上不存在）。
- **精确集合断言**：`p32_coverage` 不只看数量，而是把 TSV 读成 `(position, actual_class, result, fixture, expected)` 五元组集合，与卡片内置的 24 条期望集合**逐条相等**（集合相等，不依赖行序）。`L32-n` 行还必须逐行断言 `expected` 恰出现一次、退出 1、无其他 L32 诊断。任何新增/删除/改文案/改夹具都会失败。
- **7 条可判行（精确）**：

  | position | class | result | fixture | expected 子串 |
  | --- | --- | --- | --- | --- |
  | assign | pointer | L32-1 | `errors/check_init_ptr.ct` | `initializer: expected 'int', got 'char *'` |
  | assign | struct | L32-2 | `errors/check_struct_assign.ct` | `assignment: expected 'struct A', got 'struct B'` |
  | return | pointer | L32-3 | `errors/check_return_ptr.ct` | `return: expected 'int', got 'char *'` |
  | return | struct | L32-3 | `errors/check_return_struct.ct` | `return: expected 'struct A', got 'struct B'` |
  | return | void | L32-5 | `errors/check_return_in_void.ct` | `return: a value is not allowed in a void function` |
  | container | pointer | L32-6 | `errors/check_container_push.ct` | `argument 1: expected 'int', got 'char *'` |
  | container | struct | L32-6 | `errors/check_container_struct.ct` | `argument 1: expected 'int', got 'struct A'` |

- **固定 6 条 `ok`**：assign/interface、assign/arithmetic、return/interface、return/arithmetic、container/interface、container/arithmetic；共用夹具 `ast/211_coverage_aux/prog.ct`（每类一个独立函数），`expected` 写 `-`，退出 0。
- **固定 9 条 `skip`**：assign/array、assign/closure、assign/fnptr、return/array、return/closure、return/fnptr、container/array、container/closure、container/fnptr；共用 `ast/211_coverage_aux/prog.ct`，`expected` 写 `-`，退出 0。`return/array` 是**语法可解析、语义非法**（C 不允许返回数组），按跳过表的既有行为登记为 `skip:<理由>`，不标 `n/a`。
- **固定 2 条 `n/a`**：assign/void、container/void；夹具写 `-`，理由必填。S0 必须分别用 `void x;` 与 `Vec<void> v;` 探针证明其**语法/实例阶段**即失败（§2.2）；若 S0 发现可解析，则按实际降为 `skip:<理由>` 并同步改集合，不得保留未经证实的 `n/a`。
- **下限口径**：可判行按精确集合计，不按 24 格总数计；任何 `skip` 格变为可判时必须升级为 `L32-n` 并同步改精确集合，不得只改数量。打印 `coverage: 24 rows, 7 L32-n, 6 ok, 9 skip, 2 n/a`。

## 4 决策表

| 编号 | 决策 | 理由 |
| --- | --- | --- |
| D32-1 | `--types` opt-in；不带开关的 `ct check` 与今日逐字节一致 | 安全网关定位；避免既有 check 输出漂移 |
| D32-2 | `arg_class` 是唯一兼容内核 | 一条规则四处复用，防止 check 与 19.2 分叉 |
| D32-3 | 声明初值并入赋值位置 | 用户给出的 `int x = "s"` 正是初值形态 |
| D32-4 | 判不出 → 静默跳过 | opt-in 安全网，不做推测性报错 |
| D32-5 | 算术类内部互相兼容，不校验位宽 | 不碰隐式转换规则；避免 `int x = 1.5` 误报 |
| D32-6 | 指针基类型不校验：**两侧都是指针且 `r != 0` 时跳过**；字面量 0 赋指针先放行 | `arg_class` 对指针基座可能返回 1 或 2，必须在 `r==2`/`r==1` 前守卫；单侧指针（如 `int x = "s"`）仍报错 |
| D32-7 | `r==2` 且双方 struct 命中 → 报 L32-2 | 修正死分支；保证 `a = b` 可红 |
| D32-8 | 容器实参走 `ct_method_bind` + 形参替换 | 满足 B29-3；与 Phase 33 的 `ct_impl_bind` 区分 |
| D32-9 | 不改变普通调用与 trait 方法的既有结果 | 新检查只做加法 |
| D32-10 | 单单元；`ct build` 跨单元体不查 | `ct check` 本就拒绝 `import` |
| D32-11 | 不新增 `MAX_*`；只加 `cur_ret`/`types_mode` 两个字段 | 控制解析器结构体膨胀 |
| D32-12 | 新诊断一律经 `ct_type_warn` | strict 自动升级为 error，check 退出码已有保证 |
| D32-13 | 覆盖率矩阵锁**精确 24 元组集合**（含 fixture/expected），不只锁 L32-n 数量 | 只锁数量可被任意 7 条自证；精确集合锁住位置/类型类/夹具/文案 |

## 5 Battle 记录

### B32-1 精确类型相等 vs 粗粒度类 vs 完整转换模型
采纳**粗粒度类**。精确相等会让 `long n = 1`、`int x = 1.5` 全部误报；完整转换模型超出预算且违背「不碰隐式转换规则」。

### B32-2 check-only vs 编译期 warning
采纳 **check-only**。若 `ct build` 也出 warning，`check-warnings` 计数与大量样例 stderr 都会变，golden 也要重生成。

### B32-3 是否包含声明初值
包含。`int x = "s";` 是用户点名的第一形态。

### B32-4 是否校验不同基类型的指针
不校验，但守卫条件是“**两侧都是指针**”。实测 `arg_class("struct A *","char *") == 1`、`("struct A *","struct B *") == 2`，所以必须在 `r==2` 和 `r==1` 之前显式跳过；否则 `struct A *p; char *s = p;` 会被误报。不能写成“任一侧含 `*`”：`int x = "s"` 只有实际侧是 `char *`，那样会跳过 `r==1`，让 E32-1 失效。登记 T32-1。

### B32-5 容器实参：按方法名特判 vs 绑定替换
采纳**绑定替换**（`ct_method_bind`）。按 `push`/`put` 名字分支违反 B29-3，且用户泛型 struct 无法受益。

### B32-6 字面量 0 是否允许赋给指针
允许。C 的空指针常量惯用法；与 `argtype_mismatch` 现有跳过规则一致。

### B32-7 覆盖率下限按 24 格还是按 L32-n 格
按 **精确 24 元组集合**，其中 `L32-n` 恰 7 条。只锁 `D==7` 会被实现方用任意 7 条自证；必须固定 position/class/result/fixture/expected 五列，`ok`/`skip`/`n/a` 也各自固定集合。

### B32-8 “任一侧含 `*`” vs “两侧都是指针”
采纳**两侧都是指针**。评审原文的“任一侧”若照字面实现，`int x = "s"`（单侧指针）会在 `r==1` 前被跳过，E32-1 直接变成死判据；这是评审意见内部冲突，按“不降低判据”原则取能保住 E32-1 的语义。`struct A *p; char *s = p;`（两侧指针）仍跳过。

### B32-9 删除接口初值新增诊断
采纳**删除**。既有 `ct check` 对 `Show sh = o;` 已报 `the struct does not use this trait`（rc=1）；再报一条会违反 E32-14“恰一条”与 E32-15“新增为零”。E32-10 改为锁定“既有诊断仍恰一条，`--types` 不追加”。

## 6 实现切片（每片独立提交，≤150 行；仓库随时可构建）

| 片 | 内容 | 主要文件 | 预估行 |
| --- | --- | --- | --- |
| S0 | 在 Phase 31 收口提交重建二进制；提交 `test/probes/p32_check_baseline.sh` + `.txt` 与原始输出（红证） | `test/probes/**` | 30–60 |
| S1 | `chk_type` 核心（变量/成员/调用/解引用/下标） | `Expr.h.ct` | 90–130 |
| S2 | 字面量归类 + 不可判返回 | `Expr.h.ct` | 40–80 |
| S3 | 声明初值挂点 + L32-1 | `Stmt.h.ct` | 40–70 |
| S4 | 赋值挂点（含 `into` 块）+ L32-2 | `Expr.h.ct` / `Stmt.h.ct` | 50–80 |
| S5 | `cur_ret` + `return` 三形态 + L32-3/4/5 | `Parser.h.ct` / `Stmt.h.ct` | 60–100 |
| S6 | `ct_method_bind` 绑定表 | `Symbols.h.ct` / `Expr.h.ct` | 70–110 |
| S7 | 固有方法挂点 + 形参替换 + L32-6 | `Expr.h.ct` | 70–110 |
| S8 | `--types` 解析 + `types_mode` + L32-7 | `Driver.h.ct` / `Parser.h.ct` | 50–80 |
| S9 | 诊断收口（L32-1–L32-6 文案/位置） | `Parser.h.ct` / `Diag.h.ct` | 40–70 |
| S10 | L32-1–L32-6 的 AST 独立夹具 + `p32_*` 断言（恰一条 + 位置） | `test/ast/errors/**` / `selfhost/check-ast.sh` | 100–150 |
| S11 | CLI 夹具 `test/cli/types_wrong_subcommand` + 断言（文案 + 退出码） | `test/cli/**` / `check-ast.sh` | 20–40 |
| S12 | 24 行精确集合 `check_coverage.tsv` + `p32_coverage` | `test/ast/check_coverage.tsv` / `check-ast.sh` | 80–130 |
| S13 | 合法语料显式清单 + 逐文件 diff（§7 E32-15） | `test/probes/p32_legal_manifest.tsv` / 夹具/内核修正 | 80–130 |
| S14 | 样例 `examples/35_type_safety` + `test/run.sh` | `examples/35_*` | 60–110 |
| S15 | 文档（language-spec/glossary/tutorial/roadmap）+ 全量门禁 | `docs/**` | 80–140 |

依赖：S1→S2/S3/S4/S5；S6→S7；S8/S9 可与 S2 并行；S10 覆盖 S3–S9 的全部 AST 诊断，S11 单独覆盖 CLI；S12 依赖 S10/S11；S13 在 S10 之后；S14/S15 最后。

## 7 退出判据（E32-n）

每条给出独立夹具、门禁与红证；下表所有 `check` 均指 **`ct check --types`**。不带 `--types` 的基线行为由 E32-16 锁定。

| ID | 断言 | 夹具 | 门禁 | 红证 |
| --- | --- | --- | --- | --- |
| E32-1 | `int x = "s";` 恰一条 L32-1，位置为表达式起点，退出非 0 | `errors/check_init_ptr.ct` | `check-ast.sh` | S0 基线 `rc=0` |
| E32-2 | `x = "s";` 恰一条 L32-2 | `errors/check_assign_ptr.ct` | `check-ast.sh` | S0 基线 `rc=0` |
| E32-3 | `struct A a; struct B b; a = b;` 恰一条 L32-2 | `errors/check_struct_assign.ct` | `check-ast.sh` | S0 基线 `rc=0` |
| E32-4 | `int f(){ return "s"; }` 与 `struct A f(){ struct B b; return b; }` 各恰一条 L32-3 | `errors/check_return_ptr.ct` / `errors/check_return_struct.ct` | `check-ast.sh` | S0 基线 `rc=0` |
| E32-5 | `int f(){ return; }` 恰一条 L32-4 | `errors/check_return_missing.ct` | `check-ast.sh` | S0 基线 `rc=0` |
| E32-6 | `void g(){ return 1; }` 恰一条 L32-5 | `errors/check_return_in_void.ct` | `check-ast.sh` | S0 基线 `rc=0` |
| E32-7 | `Vec<int> v; v.push("s");` 与 `v.push(someStruct)` 各恰一条 L32-6 | `errors/check_container_push.ct` / `errors/check_container_struct.ct` | `check-ast.sh` | S0 基线 `rc=0` |
| E32-8 | `v.set(0,"s")` 恰一条 L32-6 | `errors/check_container_set.ct` | `check-ast.sh` | S0 基线 `rc=0` |
| E32-9 | `Map<char *,int> m; m.put("a","b")` 恰一条 L32-6 | `errors/check_container_put.ct` | `check-ast.sh` | S0 基线 `rc=0` |
| E32-10 | 既有诊断不重复：`Show sh = o;`（`Other` 未 `use Show`）在 `ct check` 与 `ct check --types` 下都**恰一条** `the struct does not use this trait`，rc=1，文案/位置逐字相同 | `errors/check_iface_use.ct` | `check-ast.sh` | S0 基线已是 `rc=1` 单条 |
| E32-11 | `ct build --types x.ct` → 恰一条 L32-7，退出非 0；与源码诊断无关 | `test/cli/types_wrong_subcommand`（S0 建） | `check-ast.sh` | 夹具待建；S0 记录基线 |
| E32-12 | 正例：`char *s="hi"; char *p=0; int x=1.5; long n=1; void *v=s; Show sh=circle; struct A *pa; char *pc = pa;` 退出 0 | `ast/209_valid_assignments`（夹具待建，S0 建） | `check-ast.sh` | 夹具待建；探针见 §2.2 `rc=0` |
| E32-13 | 跳过形态：泛型/闭包/函数指针/接口实际值/**struct 指针互转**不误报 | `ast/210_valid_skip_forms`（夹具待建，S0 建） | `check-ast.sh` | 夹具待建；探针见 §2.2 `rc=0` |
| E32-14 | 所有源码 L 诊断（L32-1–L32-6）格式 `file:line:col`，列指向表达式；每条恰一条且位置固定。**L32-7 是 CLI 诊断，显式排除** | 上述 L 夹具 | `check-ast.sh` | S0 基线无这些诊断 |
| E32-15 | 合法语料**显式清单**（`test/probes/p32_legal_manifest.tsv`，排除 `test/ast/errors/**` 与 `test/modules/**`）逐文件记录 rc/stderr；实现后同一清单逐文件 diff 为空，新增诊断 = 0；禁止用 glob 隐式枚举 | `test/probes/p32_legal_manifest.tsv` + `p32_check_baseline.txt` | `check-ast.sh` | S0 原始输出 |
| E32-16 | `ct build`/`ct compile` 的 `.c` 与 golden 逐字节不变；不带 `--types` 的 `ct check` 逐字节一致；`check-warnings` **不低于 S0 实测值 N** | 全量 | `test/run.sh` + `check-warnings.sh` | 基线见 §2.1，N 由 S0 记录 |
| E32-17 | 用户泛型 struct `Pair<A,B>` 的实参错同样被 L32-6 拦截，证明无 `Vec`/`Map` 特判 | `errors/check_generic_arg.ct` | `check-ast.sh` | S0 基线 `rc=0` |
| E32-18 | 覆盖率：24 行精确集合（7 L32-n / 6 ok / 9 skip / 2 n/a）逐条相等；7 条 L32-n 逐行断言 expected 恰一次；打印 `coverage: 24 rows, 7 L32-n, 6 ok, 9 skip, 2 n/a` | `test/ast/check_coverage.tsv` | `check-ast.sh` | 当前无矩阵 |
| E32-19 | 样例 `examples/35_type_safety` 进入 `test/run.sh`，golden 编译生成并人工核对 | `examples/35_type_safety` | `test/run.sh` | 当前不存在 |
| E32-20 | language-spec/glossary/tutorial 写清 `--types`、三处边界、指针基类型不查；roadmap 行落地 | `docs/**` | `check-docs` | 当前无表述 |
| E32-21 | `check-all.sh` 11 道硬门禁全绿；各项计数**不低于 S0 实测值 N**；不 bump、不打 tag | 全量 | `check-all.sh` | 基线见 §2.1，N 由 S0 记录 |

## 8 负例台账（L32-n）

每条 L 必须有独立夹具与门禁断言；无夹具的条目不得保留。

| 编号 | 触发 | 夹具 | 断言 |
| --- | --- | --- | --- |
| L32-1 | 声明初值不兼容 | `errors/check_init_ptr.ct` | E32-1 |
| L32-2 | 赋值不兼容（含 `into` 字段 / 不同 struct） | `check_assign_ptr.ct` / `check_struct_assign.ct` | E32-2/E32-3 |
| L32-3 | `return` 值不兼容 | `check_return_ptr.ct` / `check_return_struct.ct` | E32-4 |
| L32-4 | 非 void 缺返回值 | `check_return_missing.ct` | E32-5 |
| L32-5 | void 多返回值 | `check_return_in_void.ct` | E32-6 |
| L32-6 | 容器/泛型方法实参不兼容 | `check_container_push/set/put.ct` / `check_container_struct.ct` | E32-7/E32-8/E32-9 |
| L32-7 | `--types` 与错误子命令组合（CLI，非源码诊断） | `test/cli/types_wrong_subcommand`（S0 建） | E32-11 |

> 原 L32-7（接口初值未 `use` trait）已删除；`Show sh = o;` 由既有诊断覆盖，见 E32-10。

## 9 样例计划

- **`examples/35_type_safety`**：覆盖声明/赋值（含 `into` 字段）、`return`（void 与非 void）、`Vec`/`Map` 实参；结构体、接口、指针、算术类各至少一例；输出确定。
- 反例统一进 `test/ast/errors/`，由 `check-ast.sh` 断言；样例在 `ct check --types` 下零诊断（E32-15）。
- 编号：30–34 由 Phase 31 预占，本相只用 **35**。

## 10 估算（等于切片求和）

| 区 | 切片 | 行数 |
| --- | --- | --- |
| 编译器（S1–S9） | 90–130 + 40–80 + 40–70 + 50–80 + 60–100 + 70–110 + 70–110 + 50–80 + 40–70 | **510–830** |
| 夹具/断言（S10–S14） | 100–150 + 20–40 + 80–130 + 80–130 + 60–110 | **340–560** |
| 文档（S15） | 80–140 | **80–140** |
| 红证（S0） | 30–60 | **30–60** |
| **合计** | 全部切片 | **960–1,590** |

> 编译器预算上限仍为 1,000；切片和 510–830 留有余量。每片上限 ≤150 行。

## 11 风险与触发条件

| 编号 | 风险 | 处置 |
| --- | --- | --- |
| R32-1 | 合法 C 惯用法误报 | 复用 `argtype_mismatch` 跳过表；S12 清账；误报必须修内核或登记 T32-x，不得默认关闭 |
| R32-2 | check 与编译行为分叉 | 单一 `--types` 开关；E32-16 锁死 golden 与 warning 计数 |
| R32-3 | 字面量/枚举/字符归类不全 | `chk_type` 判不出即跳过；E32-12 正例锁定 |
| R32-4 | 泛型 impl 绑定顺序错 | `impl<U> Box<U>` 与 `Pair<A,B>` 双夹具；E32-17 |
| R32-5 | 既有错误夹具多出诊断 | E32-10 锁既有接口诊断；E32-15 显式清单 diff；新增真阳性必须写进夹具 |
| R32-6 | `cur_ret` 嵌套泄漏 | 入口保存、出口恢复；错误路径走 `die`，不存在恢复后继续解析；默认方法与普通函数共用 |
| R32-7 | `into` 赋值漏检 | S4 明确覆盖；E32-2 |
| R32-8 | 跨单元 `ct build` 被误改 | O3 只在单单元 check 路径；D32-10 |

### 开放项 / 触发条件

| 编号 | 内容 | 触发条件 |
| --- | --- | --- |
| T32-1 | 指针基类型兼容 | 出现真实误用且 31 的容器元素形态稳定 |
| T32-2 | 字段/下标/条件位置 | 三处位置零误报运行一个发布周期后 |
| T32-3 | 流分析 | 有独立设计卡与预算 |
| T32-4 | 跨单元函数体检查 | `ct check` 支持 `import` 后 |

## 12 交付物清单

- `selfhost/ct-ast/**`：S1–S9 的实现与诊断。
- `test/probes/p32_check_baseline.sh`、`.txt`、`p32_legal_manifest.tsv`：S0 交付的红证脚本、逐文件基线与显式合法语料清单。
- `test/ast/errors/check_*.ct`：L32-1–L32-6 独立夹具；`check-ast.sh` 的 `p32_*` 断言。
- `test/cli/types_wrong_subcommand`：L32-7 的 CLI 夹具。
- `test/ast/check_coverage.tsv` + `p32_coverage`：24 行精确集合断言。
- `test/ast/209_valid_assignments/`、`210_valid_skip_forms/`、`211_coverage_aux/`：正例、跳过形态与矩阵辅助夹具。
- `examples/35_type_safety/` + golden。
- `docs/language-spec.md`、`glossary.md`、`tutorial.md`、`roadmap.md`。

## 13 收口与纪律

- **T-7**：S0 在 Phase 31 收口提交上重建二进制，提交 `test(check): P32 红证`（含脚本与基线清单）；该提交必须是第一个实现提交的父提交。实现提交随后转绿。
- 每片 ≤150 行；发现超限就再拆。仓库任何时刻可构建。
- 不改判据、不改 golden、不改版本号凑绿；不 bump、不打 tag、不 push。
- 只暂存本相文件；`editors/vscode/**`、`docs/design/phase31.md` 与其他会话在改的文件一律不碰。
- 收口跑 `bash selfhost/check-all.sh`，贴末行 VERDICT 与关键计数；未满足的判据必须回退状态。
