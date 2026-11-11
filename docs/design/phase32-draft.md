# Phase 32 — 类型安全检查网：赋值、`return`、容器实参

> **状态：规划中**（2026-11-11 立项草案；**不写实现**）。
> **基线**：**Phase 31 收口提交**（S0 开工时记录实际 sha）。Phase 31 的容器形态与元素助手是本相 O3 的前置；`bd91bfe` 上这些能力尚不存在，不得作为基线。
> **红证**：红证提交必须是**实现提交的父提交**；S0 在 Phase 31 收口提交上重建二进制、复跑 §2.2 探针，并把脚本与基线清单随红证提交入库。
> **文档形态**：`phase32-draft.md`。转正按「每次转正归档当时最老的一张」：32 转正时归档 `phase20`，33 转正时归档 `phase21`，依此类推；本卡不抢跑。
> **deviation:** G4 `g4-size` 要求单份文档 ≤ 300 行；本卡承载判定内核、三处挂点、精确覆盖率集合与判据/负例台账，约 446 行。按自裁 **waiver** 保留单卡（判定内核、矩阵、判据、负例必须同卡才能互相对照），不再寻求需求提出方签字。
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
- 不检查四类位置以外：字段初值、下标、条件/循环条件、`switch`、`sizeof`、`_Generic`、宏、指针基类型与层数（D32-6）。
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
| `python3 test/docs/check-docs.py` | **OK**（1069 relative links in 185 files，11 hard gates，12 phase status，design window 12/12；2026-11-11 本树实测） |
| `examples/` 编号 | 最高 `29_into_block`；**30–34 由 Phase 31 预占**，本相用 **35** |

> 这些数字只用于确认量级；Phase 31 落地会改变断言数与链接数，**S0 必须重测并把实际值写进红证提交**。

### 2.2 红证探针

探针二进制为 `/tmp/ct-ast`（v0.26.4），仅用于确认方向；S0 在 Phase 31 收口提交上重建二进制后必须复跑，**以 S0 原始输出为 T-7 红证**。`test/probes/` 当前**不存在**，由 S0 交付：`p32_check_baseline.sh` 在 `test/probes/fixtures/` 生成下表全部源码，把 `check` / `check --types` 的退出码与 stderr 写入 `test/probes/p32_check_baseline.txt`。**`p32_legal_manifest.tsv` 由 S13 独占**（列 `path rc stderr`），S0 不生成；表中的 `/tmp/p32_*.ct` 只是本地临时路径，不构成红证。

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
| **void actual 探针**：`void f(); int x = f();`、`void f(); Vec<int> v; v.push(f());` | `… check /tmp/p32_void_actual.ct` | `rc=0`（actual void 走跳过表，不是语法错） |
| **`void x;`** | `… check /tmp/p32_void_var.ct` | `rc=0`（该形态可解析，**不**是 n/a） |
| **`Vec<void> v;`** | `… check /tmp/p32_vec_void.ct` | `1:9: type argument 'void' cannot instantiate a generic struct`（证明元素类型被拒，不是 actual-void 实参） |
| **泛型跳过**：`T id<T>(T x){ return x; }` | `… check /tmp/p32_generic.ct` | `rc=0`（必须保持） |

> 基线命令用 `ct check`（不带 `--types`）证明今日不查类型；实现后改用 `ct check --types` 复跑并必须失败。`ct check --types` 在基线上应报未知选项，S0 记录原始退出码与文案。**接口初值新诊断已删除**（原占用 L32-7 编号，现 L32-7 是 CLI 诊断）：既有装箱诊断已覆盖 `Show sh = o;`，本相不得新增第二条。

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

新增只读入口 `chk_type(expr, out, cap, *is_zero)`，返回 0 表示判出、非 0 表示不可判；`is_zero` 可选，用于空指针 0 判定：

| 形态 | 结果 |
| --- | --- |
| `N_NUM` | `int`；`*is_zero = (toknum == 0)`（签名不靠字符串回传数值） |
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
chk_assignable(formal, actual, is_zero, diag):
  if formal 为空 or actual 为空: 跳过
  if formal 是接口类型: 跳过           # 已有装箱路径
  if actual 是数组/闭包/CAST: 跳过   # 沿用 argtype_mismatch 跳过表
  if is_zero 且 formal 含 '*': 通过  # 空指针字面量，由调用方从 chk_type 取得
  r = arg_class(formal, actual)
  r == 0 -> 通过
  if formal 含 '*' 且 actual 含 '*': 跳过   # 基类型与层数均不校验（D32-6 / T32-1）
  r == 2 -> 双方都在 struct 表命中 -> emit(diag, ...)；任一判不出 -> 跳过
  r == 1 -> emit(diag, ...)
  r == -1 -> 跳过
```

- **诊断由调用方传入**：`diag` ∈ `L32-1`（初值）/ `L32-2`（赋值）/ `L32-3`（`return`）/ `L32-6`（容器实参）。`r==2` 与 `r==1` 都走 `emit(diag, ...)`，不得在 `chk_assignable` 内硬编码 L32-2；否则 `return/struct` 会错报 `assignment:`。
- **所有调用必须显式传诊断号**：§3.3 传 `L32-6`，§3.4 传 `L32-3`，赋值传 `L32-2`，初值传 `L32-1`；缺参数的调用点一律视为未接线。
- **`is_zero` 的传递路径写死**：四个调用点都先跑 `chk_type(expr, out, sizeof out, &is_zero)`，再把 `is_zero` **原样**传给 `chk_assignable`；非字面量表达式置 0。禁止在 `chk_assignable` 内重新扫字符串找 `0`，也禁止只传三个参数的旧写法。

  | 调用点 | 诊断 | `is_zero` 来源 |
  | --- | --- | --- |
  | 声明初值 | L32-1 | `chk_type(init)` 的 `&is_zero` |
  | 赋值 / `into` 字段 | L32-2 | `chk_type(rhs)` 的 `&is_zero` |
  | `return` | L32-3 | `chk_type(ret_expr)` 的 `&is_zero` |
  | 容器/泛型方法实参 | L32-6 | `chk_type(actual)` 的 `&is_zero` |
- **指针守卫放在 `r==2` 之前、`r==1` 之前**：`arg_class` 对 `struct A *` vs `char *` 返回 **1**，对 `struct A *` vs `struct B *` 返回 **2**；两者都必须在 `r != 0` 时跳过。守卫条件是“**两侧都是指针**”：`int x = "s"` 只有实际侧是 `char *`，必须继续走 `r==1` 报 L32-1，否则 E32-1 变成死判据（B32-8）。`void *` 双向转换由 `arg_class` 在 `r==0` 处先放行；`void **` vs `char *` 也返回 0，本相**不**再加层数条件，统一在 T32-1 登记“基类型与层数均不校验”。
- **`r == 2` 的语义**：`arg_class` 对同名同基已返回 0；返回 2 只可能是**不同 struct**。因此 `struct A a; struct B b; a = b;` 必须报 L32-2，不能走「同一 struct 才通过」的死分支。
- **算术类**：`arg_class` 把算术类型归为一类，`int x = 1.5`、`long n = 1` 不误报；不额外建模提升。
- **结构体**：不同 struct 明确报错；struct → 接口由 `iface_ref_type` 跳过，交给既有装箱。
- **void**：`arg_class` 对 void 返回 `-1`，O2 的缺值/多值单独判（§3.4）；`int x = f()`（actual void）与 `v.push(f())`（actual void）都走 `skip:void actual`，不是语法错。
- **接口初值诊断不新增**（原 L32 编号已回收，L32-7 现指 CLI）：`Show sh = o;`（`Other` 未 `use Show`）在既有 `ct check` 下已报 `the struct does not use this trait`；本相不再新增任何接口初值诊断，E32-10 只断言“仍恰一条且 `--types` 不追加”。
- **L32-6 的列**：指向**出错实参的起点**（不是接收者、不是 `push` 名字）。

### 3.3 O3 容器实参：绑定 + 替换，不按容器名分支

在 `Expr.h.ct` 的固有方法调用分支（当前只查元数与 own/借用/容器守卫）追加：

1. 取接收者的 `ibase`（如 `struct Vec_int`），在 `ct_insts[]` 找到实例行，读出 `tmpl` 与 `c1/c2`。
2. 在 `ct_impls[]` 找到该方法 impl，按位置把 `tp[0..n)` 绑定到 `c1/c2`；**新增 `ct_method_bind`**（注意：Phase 33 的 `ct_impl_bind` 是 pattern 匹配器，两者语义不同，不得同名）。
3. 形参做**受限替换**：仅裸 `T`/`U` 或 `T *`/`U *` 替换；其他结构标记不可判并跳过。本相只需覆盖 `push(T)`、`set(int, T)`、`put(K, V)`。
4. 先 `chk_type(actual, out, sizeof out, &is_zero)`（判不出即跳过），再对替换后的形参调用 `chk_assignable(patched_formal, out, is_zero, L32-6)`，文案沿用 `argument %d: expected '%s', got '%s'`，由 `ct_type_warn` 统一出。

### 3.4 O2 `return`

- 新增 `Parser.cur_ret[MAX_TEXT]`，在 `parse_func` 入口保存、出口恢复；trait 默认方法与普通函数共用。
- `parse_return`：无返回值 + `cur_ret` 非 `void` → L32-4；有返回值 + `cur_ret == void` → L32-5；有返回值 + 非 void 时：

  ```c
  char out[MAX_TEXT];
  int is_zero = 0;
  if (chk_type(expr, out, sizeof out, &is_zero) == 0)
      chk_assignable(cur_ret, out, is_zero, L32-3);
  ```

  `chk_type` 是 3 个必选参数 + 1 个可选出参（共 4 个位置参数；`is_zero` 可传 `NULL`），0 成功 / 非 0 判不出；`is_zero` 必须继续传给 `chk_assignable`，不得丢弃；`cur_ret` 为空/含泛型参数/判不出 → 跳过。
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
| L32-7 | `ctc: --types is only valid with 'ct check'` |

> 旧接口初值诊断（原编号 L32-7，已回收）：既有 `ct check` 已报 `the struct does not use this trait`，新增会违反“恰一条”和“新增为零”。CLI 诊断（现 L32-7）不是源码诊断，不参与 `file:line:col` 断言；既有 CLI 诊断全部带 `ctc:` 前缀。

### 3.6 覆盖率矩阵（可执行）

矩阵固定为 **24 行**，落盘 `test/ast/check_coverage.tsv`，列：

```
position  formal_class  actual_class  result  fixture  expected
assign    arithmetic    pointer       L32-1   check_errors/check_init_ptr.ct  initializer: expected 'int', got 'char *'
```

- **列语义**：`formal_class` 是左侧/形参/返回类型，`actual_class` 是右侧/实参类型；两者分开写，避免 `return/void`（formal void + actual int）与其他行混用。
- **专属负例目录**：L32-1–L32-6 的 12 个夹具放 `test/ast/check_errors/*.ct`（**不叫 `prog.ct`，不放 `test/ast/errors/`**）。**硬门禁**（`check-ast.sh` 行为循环与负向扫描、`check-warnings.sh`、`check-archive.sh`、`test/run.sh`）都不编译、不读这两个目录；唯一的递归读取者是 nightly fuzz（`test/fuzz/run.sh:114` 的 `find test/ast -name '*.ct'`），它只把种子**变异后**编译、从不按原样判红，因此 `check_errors/**` 与 `check_only/**` 出现在它的种子集合里不构成断言。每个夹具首行注释精确标识：
  `// p32: L32-n position=assign|return|container formal=<F> actual=<A>`
- **期望源独立**：24 条期望元组**硬编码在 `selfhost/check-ast.sh` 的 `p32_coverage` 中**（或落 `check_coverage.expected.tsv` 并由 S12 的文件清单包含）；`check_coverage.tsv` 只是实现方的声明，必须与硬编码期望逐条相等，禁止“文件和自己比”。卡片里的表只是人类镜像。
- **7 条可判行（精确）**：

  | position | formal_class | actual_class | result | fixture | expected 子串 |
  | --- | --- | --- | --- | --- | --- |
  | assign | arithmetic | pointer | L32-1 | `check_errors/check_init_ptr.ct` | `initializer: expected 'int', got 'char *'` |
  | assign | struct A | struct B | L32-2 | `check_errors/check_struct_assign.ct` | `assignment: expected 'struct A', got 'struct B'` |
  | return | arithmetic | pointer | L32-3 | `check_errors/check_return_ptr.ct` | `return: expected 'int', got 'char *'` |
  | return | struct A | struct B | L32-3 | `check_errors/check_return_struct.ct` | `return: expected 'struct A', got 'struct B'` |
  | return | void | arithmetic | L32-5 | `check_errors/check_return_in_void.ct` | `return: a value is not allowed in a void function` |
  | container | arithmetic | pointer | L32-6 | `check_errors/check_container_push.ct` | `argument 1: expected 'int', got 'char *'` |
  | container | arithmetic | struct A | L32-6 | `check_errors/check_container_struct.ct` | `argument 1: expected 'int', got 'struct A'` |

- **固定 6 条 `ok`**（`ast/211_coverage_aux/prog.ct`，`expected` 写 `-`；可行为编译、所有局部变量被消费、`cc -Wall -Wextra` 零告警，退出 0）：assign/interface←struct、assign/arithmetic←arithmetic、return/interface←struct、return/arithmetic←arithmetic、container/interface←struct、container/arithmetic←arithmetic。**211 的 `prog.ct` 不承载任何 skip 行。** 正文固定为（`prog.expected.out` = `1 1 1 1 1`）：

  ```c
  #include <stdio.h>

  struct Circle { int r; } use Show;
  impl Show for Circle { void show() { } }
  Circle gc;                              /* 全局元素：避免返回栈上接口 */
  int gi = 1;
  Show ret_iface() { return gc; }         /* return/interface←struct */
  int ret_arith()  { return 1; }          /* return/arithmetic←arithmetic */

  int main() {
      Show sh = gc;                       /* assign/interface←struct */
      int x = 1;                          /* assign/arithmetic←arithmetic */
      Vec<Show> vv = {gc};                /* container/interface←struct */
      Vec<int> v = {1};                   /* container/arithmetic←arithmetic */
      sh.show();
      ret_iface();
      printf("%d %d %d %d %d\n", x, gi, ret_arith(), v.len(), vv.len());
      return 0;
  }
  ```

  **不能换的写法**：`return` 接口若用局部 `Circle`，返回的是栈上地址，输出不确定；裸 `Vec<int> v;` 不做零初始化（T31-4），`v.push(1)` 实测运行 `rc=139`。因此元素必须是全局/静态（`Circle gc;`），容器必须用 Phase 31 的花括号初值（`Vec<int> v = {1};`、`Vec<Show> vv = {gc};`；花括号初值只允许局部声明，L31-10）。所有局部变量与全局都必须被消费，保证零告警。
- **固定 11 条 `skip`**（全部在 `ast/211_coverage_aux/check_only/`，由 `p32_coverage` 直接跑 `ct check --types`，退出 0）：
  - `check_only/void_actual.ct`：assign/arithmetic←void（`int x = f();`）、container/arithmetic←void（`v.push(f());`）；
  - `check_only/array_actual.ct`：assign/pointer←array、return/pointer←array、container/pointer←array；
  - `check_only/closure_actual.ct`：assign/arithmetic←closure、return/arithmetic←closure、container/arithmetic←closure；
  - `check_only/fnptr_actual.ct`：assign/arithmetic←fnptr、return/arithmetic←fnptr、container/arithmetic←fnptr。
- **0 条 `n/a`**：`void x;` 实测 `rc=0`，`Vec<void>` 报的是“元素类型不能实例化泛型 struct”，两者都不能证明“assign/container 的 actual-void 语法不存在”；统一改为 `skip:void actual`。
- **`p32_types` 块的接线（段锚点 / 命令 / 期望 stderr）**：一段独立块，块首 `echo "== p32 types (L32) =="`，插在 `selfhost/check-ast.sh` 行为循环（`for d in test/ast/*/`，`:502`）结束之后、`== negative cases (test/ast/errors/*.ct) ==`（`:3018`）之前；块内四部分，全部用主线二进制 `"$work/ct-ast"`（`:409` 构建的那个），失败计数并入脚本既有 `fail` 与 `:6358` 汇总：
  - `p32_errors`：12 个 `test/ast/check_errors/*.ct`，**逐文件独立 `if`**（禁止一条 `for` 只看退出码）。每条执行 `out=$("$work/ct-ast" check --types "$f" 2>&1); rc=$?`，断言：`rc == 1`；`printf '%s\n' "$out" | grep -cF "<expected>"` == 1；`printf '%s\n' "$out" | grep -cE 'initializer:|assignment:|return:|argument [0-9]+:'` == 1（无第二条 L32）；首行匹配 `"$f:<line>:<col>: error: "`。
  - `p32_coverage`：24 行逐行断言；L 行同上，`ok`/`skip` 断言 `rc == 0` 且 `out` 为空；逐条打印 6 个 ok 形态名（`assign/interface<-struct`、`assign/arithmetic<-arithmetic`、`return/interface<-struct`、`return/arithmetic<-arithmetic`、`container/interface<-struct`、`container/arithmetic<-arithmetic`）并与硬编码名逐条相等（6 条 ok 共用 `prog.ct`，靠形态名定位到行）；最后打印 `coverage: 24 rows, 7 L32-n, 6 ok, 11 skip, 0 n/a`。
  - `p32_cli`：见 E32-11，两条拒绝调用行 + 一条 `check --types` 放行行。
  - `p32_iface`：`test/ast/errors/check_iface_use.ct`（待建，S10）分别跑 `"$work/ct-ast" check "$f"` 与 `"$work/ct-ast" check --types "$f"`，两遍都断言 `rc == 1` 且 `grep -cF "the struct does not use this trait"` == 1、两遍 `file:line:col` 相同（E32-10）。
- **12 个负例夹具的逐文件断言**（7 条同时进矩阵；其余 5 条只在 `p32_errors` 中断言，不占矩阵行）。每个夹具首行为 `// p32:` 注释，其余是最小骨架（`struct A`/`struct B` 声明、函数外壳、`main`）；下表“出错行”给出该行行号与原文，列号即由此行直接数出：

  | fixture | L | 出错行（行号：原文） | expected 完整子串 | rc | 位置 |
  | --- | --- | --- | --- | --- | --- |
  | `check_init_ptr.ct` | L32-1 | 3: `    int x = "s";` | `initializer: expected 'int', got 'char *'` | 1 | 3:13 |
  | `check_assign_ptr.ct` | L32-2 | 4: `    x = "s";` | `assignment: expected 'int', got 'char *'` | 1 | 4:9 |
  | `check_struct_assign.ct` | L32-2 | 7: `    a = b;` | `assignment: expected 'struct A', got 'struct B'` | 1 | 7:9 |
  | `check_return_ptr.ct` | L32-3 | 3: `    return "s";` | `return: expected 'int', got 'char *'` | 1 | 3:12 |
  | `check_return_struct.ct` | L32-3 | 6: `    return b;` | `return: expected 'struct A', got 'struct B'` | 1 | 6:12 |
  | `check_return_missing.ct` | L32-4 | 3: `    return;` | `return: missing a value (function returns 'int')` | 1 | 3:5 |
  | `check_return_in_void.ct` | L32-5 | 3: `    return 1;` | `return: a value is not allowed in a void function` | 1 | 3:12 |
  | `check_container_push.ct` | L32-6 | 4: `    v.push("s");` | `argument 1: expected 'int', got 'char *'` | 1 | 4:12 |
  | `check_container_set.ct` | L32-6 | 4: `    v.set(0, "s");` | `argument 2: expected 'int', got 'char *'` | 1 | 4:14 |
  | `check_container_put.ct` | L32-6 | 4: `    m.put("a", "b");` | `argument 2: expected 'int', got 'char *'` | 1 | 4:16 |
  | `check_container_struct.ct` | L32-6 | 6: `    v.push(a);` | `argument 1: expected 'int', got 'struct A'` | 1 | 6:12 |
  | `check_generic_arg.ct` | L32-6 | 10: `    p.set_second(a);` | `argument 1: expected 'int', got 'struct A'` | 1 | 10:18 |

  容器夹具的接收者：`check_container_{push,set,struct}.ct` 用 `Vec<int> v = {1};`；`check_container_put.ct` 用 `Map<char *, int> m = {"a": 1};`；`check_generic_arg.ct` 用用户泛型 `Pair<A, B>`（`impl<A, B> Pair<A, B> { void set_second(B v) { self.second = v; } }`，实参 `Pair<int, int>`），证明 L32-6 不按容器名分支。
- **任何新增/删除/改文案/改夹具都会失败**：24 行集合、12 条逐文件断言、6 个 ok 形态名都是硬编码期望，与 `check_coverage.tsv` 逐条比对而不是读它自证。

## 4 决策表

| 编号 | 决策 | 理由 |
| --- | --- | --- |
| D32-1 | `--types` opt-in；不带开关的 `ct check` 与今日逐字节一致 | 安全网关定位；避免既有 check 输出漂移 |
| D32-2 | `arg_class` 是唯一兼容内核 | 一条规则四处复用，防止 check 与 19.2 分叉 |
| D32-3 | 声明初值并入赋值位置 | 用户给出的 `int x = "s"` 正是初值形态 |
| D32-4 | 判不出 → 静默跳过 | opt-in 安全网，不做推测性报错 |
| D32-5 | 算术类内部互相兼容，不校验位宽 | 不碰隐式转换规则；避免 `int x = 1.5` 误报 |
| D32-6 | 指针基类型与层数均不校验：**两侧都是指针且 `r != 0` 时跳过**；`is_zero` 为真且 formal 含 `*` 时先放行 | `arg_class` 对指针基座可能返回 1 或 2，必须在 `r==2`/`r==1` 前守卫；单侧指针（如 `int x = "s"`）仍报错；不加层数比较（避免第二个兼容内核） |
| D32-7 | `r==2` 且双方 struct 命中 → 报 L32-2 | 修正死分支；保证 `a = b` 可红 |
| D32-8 | 容器实参走 `ct_method_bind` + 形参替换 | 满足 B29-3；与 Phase 33 的 `ct_impl_bind` 区分 |
| D32-9 | 不改变普通调用与 trait 方法的既有结果 | 新检查只做加法 |
| D32-10 | 单单元；`ct build` 跨单元体不查 | `ct check` 本就拒绝 `import` |
| D32-11 | 不新增 `MAX_*`；只加 `cur_ret`/`types_mode` 两个字段 | 控制解析器结构体膨胀 |
| D32-12 | 新诊断一律经 `ct_type_warn` | strict 自动升级为 error，check 退出码已有保证 |
| D32-13 | 覆盖率矩阵锁**精确 24 元组集合**（position/formal/actual/result/fixture/expected），期望源硬编码在 `check-ast.sh` 或独立 `.expected.tsv` | 只锁数量、或只读实现方 TSV，都可自证；期望源必须与实现文件分离 |

## 5 Battle 记录

### B32-1 精确类型相等 vs 粗粒度类 vs 完整转换模型
采纳**粗粒度类**。精确相等会让 `long n = 1`、`int x = 1.5` 全部误报；完整转换模型超出预算且违背「不碰隐式转换规则」。

### B32-2 check-only vs 编译期 warning
采纳 **check-only**。若 `ct build` 也出 warning，`check-warnings` 计数与大量样例 stderr 都会变，golden 也要重生成。

### B32-3 是否包含声明初值
包含。`int x = "s";` 是用户点名的第一形态。

### B32-4 是否校验不同基类型的指针
不校验基类型与层数，但守卫条件是“**两侧都是指针**”。实测 `arg_class("struct A *","char *") == 1`、`("struct A *","struct B *") == 2`，所以必须在 `r==2` 和 `r==1` 之前显式跳过；否则 `struct A *p; char *s = p;` 会被误报。不能写成“任一侧含 `*`”：`int x = "s"` 只有实际侧是 `char *`，那样会跳过 `r==1`，让 E32-1 失效。层数同样不比较（`int **` vs `int *` 也跳过），这是有意的 false negative，E32-12/13 依赖它；加层数比较会引入第二个兼容内核。登记 T32-1。

### B32-5 容器实参：按方法名特判 vs 绑定替换
采纳**绑定替换**（`ct_method_bind`）。按 `push`/`put` 名字分支违反 B29-3，且用户泛型 struct 无法受益。

### B32-6 字面量 0 是否允许赋给指针
允许。C 的空指针常量惯用法；与 `argtype_mismatch` 现有跳过规则一致。

### B32-7 覆盖率下限按 24 格还是按 L32-n 格
按 **精确 24 元组集合**，其中 `L32-n` 恰 7 条、`ok` 6 条、`skip` 11 条、`n/a` 0 条。只锁 `D==7` 会被实现方用任意 7 条自证；只读实现方 TSV 等于文件和自己比。期望集合必须硬编码在 `check-ast.sh` 或独立 `.expected.tsv`，卡片表只作人类镜像。

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
| S8 | `--types` 解析 + `types_mode` + L32-7 + `p32_cli` 断言块。**落点 (a) 写死**：`Driver.h.ct` 的 `run()` 在 `argv[1]=="build"` 分派（`:165`）**之前**预扫 `argv` 中的 `--types`，非 `check` 即打印 L32-7 并 `return 1`，**不进入 `build_main`**；`Module.h.ct` **不改**；`Parser.h.ct` 只加 `types_mode` 字段 | `Driver.h.ct`（`run()` 预扫）/ `Parser.h.ct`（`types_mode`）/ `selfhost/check-ast.sh` | 55–90 |
| S9 | 诊断收口（L32-1–L32-6 文案/位置） | `Parser.h.ct` / `Diag.h.ct` | 35–60 |
| S10 | L32-1–L32-6 的 `check_errors/*.ct` 专属负例 + `p32_*` 断言（恰一条 + 位置 + 首行标识）；**209/210 归本片**：`prog.ct` 只放可编译正例，`check_only/` 放 `ct check --types` 专属形态；三命令均断言 rc=0 且 stderr 为空。**另建 `test/ast/errors/check_iface_use.ct`（E32-10 的 `p32_iface` 用；当前不存在）** | `test/ast/check_errors/**`、`test/ast/209_*`、`210_*`、`test/ast/errors/check_iface_use.ct` / `selfhost/check-ast.sh` | 100–150 |
| S12 | 24 行精确集合 `check_coverage.tsv` + `p32_coverage`；**211 辅助夹具归本片**（`prog.ct` 只放 6 条 ok；11 条 skip 放 `check_only/`）；期望元组硬编码进 `check-ast.sh`（或独立 `check_coverage.expected.tsv`） | `test/ast/check_coverage.tsv`、`211_coverage_aux/**` / `selfhost/check-ast.sh`（或 `test/ast/check_coverage.expected.tsv`） | 85–140 |
| S13 | 合法语料显式清单 + 逐文件 diff（§7 E32-15）；**S13 独占** `p32_legal_manifest.tsv`，列 `path rc stderr`，S0 不再生成；包含规则见 E32-15 | `test/probes/p32_legal_manifest.tsv` / 夹具/内核修正 | 80–130 |
| S14 | 样例 `examples/35_type_safety` + `test/run.sh` | `examples/35_*` | 60–110 |
| S15 | 文档（language-spec/glossary/tutorial/roadmap）+ 全量门禁 | `docs/**` | 80–140 |

依赖：S1→S2/S3/S4/S5；S6→S7；S8/S9 可与 S2 并行；S10 覆盖 S3–S9 的全部 AST 诊断与 CLI（原 S11 并入 S8/S10）；S12 依赖 S10；S13 在 S10 之后；S14/S15 最后。

## 7 退出判据（E32-n）

每条给出独立夹具、门禁与红证；下表所有 `check` 均指 **`ct check --types`**。不带 `--types` 的基线行为由 E32-16 锁定。

| ID | 断言 | 夹具 | 门禁 | 红证 |
| --- | --- | --- | --- | --- |
| E32-1 | `int x = "s";` 恰一条 L32-1，位置为表达式起点，退出非 0 | `check_errors/check_init_ptr.ct` | `check-ast.sh`（`p32_*`） | S0 基线 `rc=0` |
| E32-2 | `x = "s";` 恰一条 L32-2 | `check_errors/check_assign_ptr.ct` | `check-ast.sh`（`p32_*`） | S0 基线 `rc=0` |
| E32-3 | `struct A a; struct B b; a = b;` 恰一条 L32-2 | `check_errors/check_struct_assign.ct` | `check-ast.sh`（`p32_*`） | S0 基线 `rc=0` |
| E32-4 | `int f(){ return "s"; }` 与 `struct A f(){ struct B b; return b; }` 各恰一条 L32-3 | `check_errors/check_return_ptr.ct` / `check_errors/check_return_struct.ct` | `check-ast.sh`（`p32_*`） | S0 基线 `rc=0` |
| E32-5 | `int f(){ return; }` 恰一条 L32-4 | `check_errors/check_return_missing.ct` | `check-ast.sh`（`p32_*`） | S0 基线 `rc=0` |
| E32-6 | `void g(){ return 1; }` 恰一条 L32-5 | `check_errors/check_return_in_void.ct` | `check-ast.sh`（`p32_*`） | S0 基线 `rc=0` |
| E32-7 | `Vec<int> v; v.push("s");` 与 `v.push(someStruct)` 各恰一条 L32-6 | `check_errors/check_container_push.ct` / `check_errors/check_container_struct.ct` | `check-ast.sh`（`p32_*`） | S0 基线 `rc=0` |
| E32-8 | `v.set(0,"s")` 恰一条 L32-6 | `check_errors/check_container_set.ct` | `check-ast.sh`（`p32_*`） | S0 基线 `rc=0` |
| E32-9 | `Map<char *,int> m; m.put("a","b")` 恰一条 L32-6 | `check_errors/check_container_put.ct` | `check-ast.sh`（`p32_*`） | S0 基线 `rc=0` |
| E32-10 | 既有诊断不重复：`Show sh = o;`（`Other` 未 `use Show`）在 `ct check` 与 `ct check --types` 下都**恰一条** `the struct does not use this trait`，rc=1，文案/位置逐字相同 | `errors/check_iface_use.ct`（**待建**，S10 建；当前 `test/ast/errors/` 无此文件） | `check-ast.sh`（既有负向扫描 + `p32_iface` 复跑） | 基线 `rc=1` 单条（实测 `7:16`） |
| E32-11 | `p32_cli` 块：先 `printf 'int main() { return 0; }\n' > "$work/p32_cli_x.ct"`，再执行两条 `"$work/ct-ast" build --types "$work/p32_cli_x.ct"` 与 `"$work/ct-ast" --types "$work/p32_cli_x.ct"`。落点是 `Driver.h.ct` 的 `run()`：在 `argv[1]=="build"` 分派**之前**预扫 `--types`，非 `check` 即打印 L32-7 并退出，**不进入 `build_main`**（`build` 的 `-o` 可选，卡片不再引用“缺 `-o`”这个不存在的前置）。断言：两条都 `rc == 1`、各 `grep -cF "ctc: --types is only valid with 'ct check'"` == 1、输出不含 `: error:`；另跑 `"$work/ct-ast" check --types "$work/p32_cli_x.ct"`，必须 `rc == 0` 且不出现该文案 | S8 内 `p32_cli` 子块（临时 `$work/p32_cli_x.ct`，无独立夹具） | `check-ast.sh` | 基线 `ct build --types` 报 `ctc: unknown option '--types'`（rc=1） |
| E32-12 | **零告警可编译正例**：`ast/209_valid_assignments/prog.ct` 只含 `char *s="hi"; char *p=0; int x=1; long n=1; void *v=p; Show sh=circle;`，全部经 `printf` 消费，`cc`/`check-warnings` 零告警，`prog.expected.out` 确定；`int x=1.5;`、`struct A *pa; char *pc=pa;`、`void z;`、`int y=f();`、`vv.push(f())` 放 `check_only/`，由 S10 bespoke 块跑 `ct check --types` rc=0 且 stderr 空 | `ast/209_valid_assignments/{prog.ct,prog.expected.out,check_only/*}`（S10 建） | `check-ast.sh` + `check-warnings.sh` | 夹具待建；探针见 §2.2 `rc=0` |
| E32-13 | 跳过形态：**可编译**的 array actual 进 `prog.ct`；struct 指针互转（`cc -Wall` 下是 `incompatible pointer types`）、闭包/fnptr/void actual 一律进 `check_only/`（`int x = f;` 在 `cc` 下是 `incompatible pointer to integer conversion`） | `ast/210_valid_skip_forms/{prog.ct,check_only/*}`（S10 建） | `check-ast.sh` + `check-warnings.sh` | 夹具待建；探针见 §2.2 `rc=0` |
| E32-14 | 所有源码 L 诊断（L32-1–L32-6）格式 `file:line:col`，列指向表达式；L32-6 指向**出错实参的起点**；每条恰一条且位置固定。**L32-7 是 CLI 诊断，显式排除** | 上述 L 夹具 | `check-ast.sh` | S0 基线无这些诊断 |
| E32-15 | 合法语料**显式清单**（S13 独占 `test/probes/p32_legal_manifest.tsv`，列 `path rc stderr`）：基线 `ct check`（无开关）vs 实现后 `ct check --types`，同一清单逐文件 diff 为空，新增诊断 = 0。**包含规则**：`prog.ct` 文件名（`test/ast/**`、`examples/**`、`test/modules/**` 下的 `prog.ct`）在两种模式下都必须 rc=0 且 stderr 为空，纳入清单且不得排除 `test/modules/**`；`check_errors/**`、`check_only/**`、`test/ast/errors/**` 为负例/专属形态，不纳入；`test/probes/fixtures/**` 为探针源码，不纳入；其余 `.ct` 只记录、不断言。禁止 glob 隐式枚举 | `test/probes/p32_legal_manifest.tsv` | `check-ast.sh` | S13 产出 |
| E32-16 | `ct build`/`ct compile` 的 `.c` 与 golden 逐字节不变；不带 `--types` 的 `ct check` 逐字节一致；`check-warnings` **不低于 S0 实测值 N** | 全量 | `test/run.sh` + `check-warnings.sh` | 基线见 §2.1，N 由 S0 记录 |
| E32-17 | 用户泛型 struct `Pair<A,B>` 的实参错同样被 L32-6 拦截，证明无 `Vec`/`Map` 特判 | `check_errors/check_generic_arg.ct` | `check-ast.sh`（`p32_*`） | S0 基线 `rc=0` |
| E32-18 | 覆盖率：24 行精确集合（7 L32-n / 6 ok / 11 skip / 0 n/a）与**独立期望源**逐条相等；期望源硬编码在 `check-ast.sh` 或 `check_coverage.expected.tsv`；**12 个 `check_errors` 夹具逐文件独立断言**（7 条进矩阵，5 条只在 `p32_errors` 中断言）；打印 `coverage: 24 rows, 7 L32-n, 6 ok, 11 skip, 0 n/a` 与 6 个 ok 形态名。**“7 L32-n”是 7 行携带 L 诊断，不是 7 个 L 码**：L32-4（缺值/多值）没有 formal/actual 对，由 E32-5 单独覆盖 | `test/ast/check_coverage.tsv` + 独立期望源 | `check-ast.sh` | 当前无矩阵 |
| E32-19 | 样例 `examples/35_type_safety` 进入 `test/run.sh`，golden 编译生成并人工核对 | `examples/35_type_safety` | `test/run.sh` | 当前不存在 |
| E32-20 | language-spec/glossary/tutorial 写清 `--types`、三处边界、指针基类型不查；roadmap 行落地 | `docs/**` | `check-docs` | 当前无表述 |
| E32-21 | `check-all.sh` 11 道硬门禁全绿；各项计数**不低于 S0 实测值 N**；不 bump、不打 tag | 全量 | `check-all.sh` | 基线见 §2.1，N 由 S0 记录 |

## 8 负例台账（L32-n）

每条 L 必须有独立夹具与门禁断言；无夹具的条目不得保留。

| 编号 | 触发 | 夹具 | 断言 |
| --- | --- | --- | --- |
| L32-1 | 声明初值不兼容 | `check_errors/check_init_ptr.ct` | E32-1 |
| L32-2 | 赋值不兼容（含 `into` 字段 / 不同 struct） | `check_errors/check_assign_ptr.ct` / `check_errors/check_struct_assign.ct` | E32-2/E32-3 |
| L32-3 | `return` 值不兼容 | `check_errors/check_return_ptr.ct` / `check_errors/check_return_struct.ct` | E32-4 |
| L32-4 | 非 void 缺返回值 | `check_errors/check_return_missing.ct` | E32-5 |
| L32-5 | void 多返回值 | `check_errors/check_return_in_void.ct` | E32-6 |
| L32-6 | 容器/泛型方法实参不兼容 | `check_errors/check_container_{push,set,put,struct}.ct` | E32-7/E32-8/E32-9 |
| L32-7 | `--types` 与错误子命令组合（CLI，非源码诊断） | S8 `p32_cli` 块（`"$work/ct-ast" build --types "$work/p32_cli_x.ct"`） | E32-11 |

> 旧接口初值诊断（原编号，已回收）；`Show sh = o;` 由既有诊断覆盖，见 E32-10（夹具 `errors/check_iface_use.ct` 待建，S10 建）。

## 9 样例计划

- **`examples/35_type_safety`**：覆盖声明/赋值（含 `into` 字段）、`return`（void 与非 void）、`Vec`/`Map` 实参；结构体、接口、指针、算术类各至少一例；输出确定。
- 反例统一进 `test/ast/check_errors/`，由 `check-ast.sh` 的 `p32_*` bespoke 块跑 `ct check --types` 断言；样例在 `ct check --types` 下零诊断（E32-15）。
- 编号：30–34 由 Phase 31 预占，本相只用 **35**。

## 10 估算（等于切片求和）

| 区 | 切片 | 行数 |
| --- | --- | --- |
| 编译器（S1–S9） | 90–130 + 40–80 + 40–70 + 50–80 + 60–100 + 70–110 + 70–110 + 55–90 + 35–60 | **510–830** |
| 夹具/断言（S10–S14） | 100–150 + 85–140 + 80–130 + 60–110（S11 已并入 S8/S10） | **325–530** |
| 文档（S15） | 80–140 | **80–140** |
| 红证（S0） | 30–60 | **30–60** |
| **合计** | 全部切片 | **945–1,560** |

> 编译器预算上限仍为 1,000；切片和 510–830 留有余量。每片上限 ≤150 行。

## 11 风险与触发条件

| 编号 | 风险 | 处置 |
| --- | --- | --- |
| R32-1 | 合法 C 惯用法误报 | 复用 `argtype_mismatch` 跳过表；S12 清账；误报必须修内核或登记 T32-x，不得默认关闭 |
| R32-2 | check 与编译行为分叉 | 单一 `--types` 开关；E32-16 锁死 golden 与 warning 计数 |
| R32-3 | 字面量/枚举/字符归类不全 | `chk_type` 判不出即跳过；E32-12 正例锁定 |
| R32-4 | 泛型 impl 绑定顺序错 | `Pair<A,B>` 单夹具（E32-17）；`impl<U> Box<U>` 由 S6 绑定表覆盖 |
| R32-5 | 既有错误夹具多出诊断 | E32-10 锁既有接口诊断；E32-15 显式清单 diff；新增真阳性必须写进夹具 |
| R32-6 | `cur_ret` 嵌套泄漏 | 入口保存、出口恢复；错误路径走 `die`，不存在恢复后继续解析；默认方法与普通函数共用 |
| R32-7 | `into` 赋值漏检 | S4 明确覆盖；E32-2 |
| R32-8 | 跨单元 `ct build` 被误改 | O3 只在单单元 check 路径；D32-10 |

### 开放项 / 触发条件

| 编号 | 内容 | 触发条件 |
| --- | --- | --- |
| T32-1 | 指针基类型兼容 | 本相**基类型与层数均不校验**（`void **` vs `char *` 也经 `r==0` 放行）；出现真实误用且 31 的容器元素形态稳定后再做层数/基类型比较 |
| T32-2 | 字段/下标/条件位置 | 三处位置零误报运行一个发布周期后 |
| T32-3 | 流分析 | 有独立设计卡与预算 |
| T32-4 | 跨单元函数体检查 | `ct check` 支持 `import` 后 |

## 12 交付物清单

- `selfhost/ct-ast/**`：S1–S9 的实现与诊断。
- `test/probes/p32_check_baseline.sh`、`.txt`：S0 交付的红证脚本与逐文件基线；`p32_legal_manifest.tsv` 由 **S13 独占**（列 `path rc stderr`）。
- `test/ast/check_errors/check_*.ct`：L32-1–L32-6 专属负例（不叫 `prog.ct`、不放 `errors/`），由 `check-ast.sh` 的 `p32_*` 块跑 `ct check --types`。
- `test/ast/errors/check_iface_use.ct`：E32-10 的既有诊断夹具，**待建**（S10），由 `p32_iface` 在 `check` 与 `check --types` 下各跑一遍。
- `selfhost/check-ast.sh` 内 `p32_cli` 块：L32-7，调用行 `"$work/ct-ast" build --types "$work/p32_cli_x.ct"`，断言 `ctc:` 文案与退出码。
- `test/ast/check_coverage.tsv` + **独立期望源**（`check-ast.sh` 硬编码或 `check_coverage.expected.tsv`）：24 行精确集合断言；`211_coverage_aux/prog.ct`（6 条 ok）与 `211_coverage_aux/check_only/*.ct`（11 条 skip）由 S12 建。
- `test/ast/209_valid_assignments/`、`210_valid_skip_forms/`：S10 建；`prog.ct` 零告警、`prog.expected.out` 确定，`check_only/` 放 `ct check --types` 专属形态。
- `examples/35_type_safety/` + golden。
- `docs/language-spec.md`、`glossary.md`、`tutorial.md`、`roadmap.md`。

## 13 收口与纪律

- **T-7**：S0 在 Phase 31 收口提交上重建二进制，提交 `test(check): P32 红证`（含探针脚本与基线输出，不含 209/210/211 正式夹具）；该提交必须是第一个实现提交的父提交。实现提交随后转绿。
- 每片 ≤150 行；发现超限就再拆。仓库任何时刻可构建。
- 不改判据、不改 golden、不改版本号凑绿；不 bump、不打 tag、不 push。
- 只暂存本相文件；`editors/vscode/**`、`docs/design/phase31.md` 与其他会话在改的文件一律不碰。
- 收口跑 `bash selfhost/check-all.sh`，贴末行 VERDICT 与关键计数；未满足的判据必须回退状态。
