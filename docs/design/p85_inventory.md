# PH-85 S85a 源码 inventory（v0.85.0）

> **S85a 交付物**。本文件是 `selfhost/ct-ast/**` 在 v0.85.0（M0 粗切之后）的
> 函数集合、职责、文件级状态、导入图与环清单；`tools/p85_inventory.py` 重算这些
> 数字，`test/ast/p85_inventory.sh` 逐行比对，**文档漂移即红**。
> M0 之前的基线（函数体哈希集合、产物集合、旧→新映射）见
> [p85_m0.md](p85_m0.md)；spike 见 [p85_spike.md](p85_spike.md)。
> 依据：[D-017](../decisions/D-017.md) A2/A3/A4/B1、[phase85.md](phase85.md) §1.2。

## 0 方法与抽查口径

- 扫描单位：`selfhost/ct-ast/**/*.h.ct` 加入口 `main.ct`；每个 `.h.ct` 就是一个
  “单元”，按单元名声明同名类型/trait（`check-ast.sh` 的单位名 lint 同一规则）。
- 函数集合：把 `{ … }` 的**函数体文本**作为最小单元，函数签名、注释、`#define`
  不计入；方法按 `impl <Trait> for <Type>` 归属。
- 状态：文件作用域变量（`static`/`pub`），按“主要使用方”归属（B1 规则）。
- 环：导入图的**基本环**枚举；基线为 0 条，M0 之后仍为 0（J4 只要求“不新增”）。
- 本次汇总：**27 units, 44464 lines, 842 functions**；导入边 138 条；环 0 条。
- 抽查：`test/ast/p85_inventory.sh` 对每个单元重算“行数 / 自由函数 / trait 方法 /
  import 数 / 文件级状态名”，与下表逐格比对；另抽查 3 个跨单元事实
  （`Emitter::emit_node` 的 37 个 `N_*` 判别、`Symbols::symbols_get` 的唯一使用方、
  `Pkg::sha256_*` 留在宿主）与文中叙述一致。

## 1 单元与子系统

### 1.1 子系统汇总（职责）

| 子系统 | 单元 | 行数 | 函数 | 职责 |
| --- | --- | --- | --- | --- |
| entry | 1 | 139 | 1 | `main`：绑定各单例、按 argv 分派 `build`/`compile`/`check`/`run` |
| frontend::lex | 1 | 391 | 3 | 源缓冲游标、一对一 token 前瞻（`tok/toktext/toknum`、行/列、数字后缀） |
| frontend::parse | 7 | 20709 | 329 | 声明/语句/表达式解析、`map` 构建、ADT/match、类型判定的门（`types_mode`） |
| frontend::sym | 2 | 2727 | 84 | 符号表、类型/实例/impl/ADT 注册表、类型拼写工具 |
| frontend::type | 1 | 1081 | 17 | 表达式静态类型推导、boxing 决策（`TypeOps`） |
| frontend::module | 4 | 3397 | 61 | 单元装载、import 解析、C 边界、循环检测、构建入口 |
| backend::emit | 3 | 9518 | 192 | 节点→C 发射、vtable/初始化器、头文件与 ABI 头、map/model 导出 |
| backend::mem | 1 | 481 | 15 | 所有权/泄漏分析（`own`/borrow/AutoDrop） |
| runtime::arena | 1 | 163 | 9 | 节点池与字符串池 |
| tool::diag | 1 | 753 | 40 | 警告存储、`nsem` 计数、`check` 的严重级、PH-85 的 `types_level` |
| tool::driver | 1 | 1042 | 12 | 命令行、模式分派、`--check-level` 预扫描 |
| tool::pkg | 2 | 3847 | 72 | 包管理（`get/install/verify/index`）与索引行校验 |
| tool::cache | 1 | 168 | 6 | 构建缓存键与依赖折叠 |
| tool::sh | 1 | 48 | 1 | shell 单引号转义 |

### 1.2 单元表（机器校验）

| 单元 | 子系统 | 行数 | 类型/trait | 自由函数 | trait 方法 | 文件级状态 | import |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `selfhost/ct-ast/main.ct` | entry | 139 | - | 1 | 0 | - | 14 |
| `selfhost/ct-ast/backend/emit/Emitter.h.ct` | backend::emit | 8876 | EmitOps, FldSnap, StrRetain, Emitter | 117 | 53 | g_sb, g_slice_used, g_emit | 19 |
| `selfhost/ct-ast/backend/emit/EmitterText.h.ct` | backend::emit | 234 | EmitterText | 9 | 0 | - | 18 |
| `selfhost/ct-ast/backend/emit/Init.h.ct` | backend::emit | 408 | InitOps, Init, Init | 4 | 9 | g_init | 1 |
| `selfhost/ct-ast/backend/mem/Memory.h.ct` | backend::mem | 481 | MemoryOps, Memory, Memory | 1 | 14 | g_memory | 3 |
| `selfhost/ct-ast/frontend/lex/Lexer.h.ct` | frontend::lex | 391 | LexOps, Lexer, Lexer | 2 | 1 | g_lexer | 0 |
| `selfhost/ct-ast/frontend/module/MapTable.h.ct` | frontend::module | 56 | Call, MapBind, MapTable | 0 | 0 | - | 0 |
| `selfhost/ct-ast/frontend/module/Module.h.ct` | frontend::module | 2934 | ModuleOps, Module, Module | 10 | 37 | g_cycle_adj, g_cycle_nout, g_module, g_units | 13 |
| `selfhost/ct-ast/frontend/module/ModuleBoundary.h.ct` | frontend::module | 373 | ModuleBoundary | 14 | 0 | - | 12 |
| `selfhost/ct-ast/frontend/module/Unit.h.ct` | frontend::module | 34 | Unit | 0 | 0 | - | 0 |
| `selfhost/ct-ast/frontend/parse/Expr.h.ct` | frontend::parse | 8703 | ExprOps, ExprTraitInst, ExprSubscript, ExprOptional, ExprNew, ExprAdt, ExprTypes, ExprTry, Expr, Expr | 28 | 85 | g_expr | 17 |
| `selfhost/ct-ast/frontend/parse/ExprTypeText.h.ct` | frontend::parse | 325 | ExprTypeText | 14 | 0 | - | 15 |
| `selfhost/ct-ast/frontend/parse/MapBuild.h.ct` | frontend::parse | 897 | MapBuildOps, MapBuild, MapBuild | 7 | 3 | g_mapbuild | 8 |
| `selfhost/ct-ast/frontend/parse/ParseSupport.h.ct` | frontend::parse | 759 | SupportOps, ParseSupport, ParseSupport | 1 | 44 | g_support | 6 |
| `selfhost/ct-ast/frontend/parse/Parser.h.ct` | frontend::parse | 4784 | ParseOps, ParseDeclOps, Parser, Parser | 29 | 32 | g_parse, g_calls, g_maps, g_pend_fields | 18 |
| `selfhost/ct-ast/frontend/parse/Stmt.h.ct` | frontend::parse | 5055 | StmtOps, Stmt, Stmt | 31 | 48 | g_stmt | 12 |
| `selfhost/ct-ast/frontend/parse/StmtRangeText.h.ct` | frontend::parse | 186 | StmtRangeText | 7 | 0 | - | 10 |
| `selfhost/ct-ast/frontend/sym/Symbols.h.ct` | frontend::sym | 2310 | TypeAliasOps, SymbolOps, TypeAlias, Fn, Var, Closure, MethAnn, MethodSig, Trait, Field, StructDef, GenericInst, StructTmpl, StructInst, StructImpl, AdtVariant, Adt, Symbols, Symbols, StructTmpl, StructInst, StructImpl, Adt | 24 | 47 | g_symbols, g_tmpls, g_ntmpls, g_insts, g_ninsts, g_impls, g_nimpls, g_adts, g_nadts | 1 |
| `selfhost/ct-ast/frontend/sym/SymbolsTypeText.h.ct` | frontend::sym | 417 | SymbolsTypeText | 13 | 0 | - | 0 |
| `selfhost/ct-ast/frontend/type/TypeCheck.h.ct` | frontend::type | 1081 | TypeOps, TypeCheck, TypeCheck | 2 | 15 | g_type | 8 |
| `selfhost/ct-ast/runtime/arena/Arena.h.ct` | runtime::arena | 163 | ArenaOps, Node, Arena, Arena | 3 | 6 | g_arena | 0 |
| `selfhost/ct-ast/tool/cache/Cache.h.ct` | tool::cache | 168 | CacheOps, Cache, Cache | 1 | 5 | g_cache | 0 |
| `selfhost/ct-ast/tool/diag/Diag.h.ct` | tool::diag | 753 | DiagStore, Warn, Diag | 21 | 19 | g_diag | 0 |
| `selfhost/ct-ast/tool/driver/Driver.h.ct` | tool::driver | 1042 | DriverOps, Driver | 8 | 4 | g_driver | 11 |
| `selfhost/ct-ast/tool/pkg/Pkg.h.ct` | tool::pkg | 3686 | PkgOps, PkgRec, Pkg, Sha256 | 39 | 27 | g_hexd, g_sha_k, g_pkg | 2 |
| `selfhost/ct-ast/tool/pkg/PkgIndex.h.ct` | tool::pkg | 161 | PkgIndex | 6 | 0 | - | 1 |
| `selfhost/ct-ast/tool/sh/Sh.h.ct` | tool::sh | 48 | Sh | 1 | 0 | - | 0 |

`main.ct` 是入口而非单元（不声明同名类型）；`MapTable`/`Unit` 是纯数据单元。M0 新增
6 个“无状态单元”（`EmitterText`、`ModuleBoundary`、`ExprTypeText`、`SymbolsTypeText`、
`StmtRangeText`、`PkgIndex`，见 §2.3），它们的行数已计入上表。

## 2 文件级状态

### 2.1 单例（每个子系统一个）

| 状态 | 单元 | 使用方 | 规则 |
| --- | --- | --- | --- |
| `g_lexer` | `frontend/lex/Lexer.h.ct` | 本单元 `lexer_get()` | 随词法器走；token 的 `char[160]` 缓冲在结构体内 |
| `g_parse` | `frontend/parse/Parser.h.ct` | 本单元的 `ct_parse_*` 门面、`parser_st_hook` | 解析器单例；`g_calls`/`g_maps`/`g_pend_fields` 是它的数组，只被该单元读写 |
| `g_expr` | `frontend/parse/Expr.h.ct` | 本单元 `ct_expr_bind`/`expr_get` | 表达式解析器的绑定门面 |
| `g_stmt` | `frontend/parse/Stmt.h.ct` | 本单元 `ct_stmt_bind`/`stmt_get` | 语句解析器的绑定门面 |
| `g_symbols` | `frontend/sym/Symbols.h.ct` | 单元内 `symbols_get()`（以及跨单元 `ct_*` 注册表函数经它取表） | 符号表单例；`g_tmpls`/`g_insts`/`g_impls`/`g_adts` + 计数是它的数组 |
| `g_type` | `frontend/type/TypeCheck.h.ct` | `type_get()` | 类型推导单例 |
| `g_module` | `frontend/module/Module.h.ct` | `module_get()`、`build_main` | 构建上下文；`g_units`（单元表）随它走 |
| `g_emit` | `backend/emit/Emitter.h.ct` | `ct_emit_*` 门面 | 发射器单例；`g_sb`（`StrRetain` 簿记）、`g_slice_used` 指针是它的附属状态 |
| `g_init` | `backend/emit/Init.h.ct` | `init_get()` | vptr/初始化器子对象 |
| `g_memory` | `backend/mem/Memory.h.ct` | `memory_get()` | 所有权分析单例 |
| `g_arena` | `runtime/arena/Arena.h.ct` | `arena_get()` | 节点池/字符串池 |
| `g_diag` | `tool/diag/Diag.h.ct` | `ct_*` 诊断门面 | 警告数组 + `nsem` + `types_level`（PH-85） |
| `g_cache` | `tool/cache/Cache.h.ct` | `cache_get()` | 缓存表 |
| `g_pkg` | `tool/pkg/Pkg.h.ct` | `ct_pkg_*`/`ct_index_verify` 门面 | 包管理器状态 |
| `g_driver` | `tool/driver/Driver.h.ct` | `ct_driver_run` | 命令行上下文 |

### 2.2 其他文件级状态

| 状态 | 单元 | 用途 |
| --- | --- | --- |
| `g_sha_k[64]`、`g_hexd` | `tool/pkg/Pkg.h.ct` | SHA-256 常量表与十六进制字母（M0 未搬：签名用 `size_t`，且 `struct Sha256` 随之留在宿主） |
| `g_cycle_adj[8][4]`、`g_cycle_nout[8]` | `frontend/module/Module.h.ct` | 直接环检测的邻接表（PH-82） |
| `g_adts`、`g_nadts` | `frontend/sym/Symbols.h.ct` | ADT 注册表（PH-84）；随 `Symbols` 单例走 |
| `g_ntraits`/`g_nfuncs` 等数组长度 | 各单元 | `pub struct` 落头文件，宏不跨单元，长度写死为字面量 |

### 2.3 归属规则（B1）与 M0 的边界

1. **状态随主要使用方走**：一个文件作用域变量只被某一组自由函数使用时，M0 允许
   把它和这组函数一起搬走；被“留下的方法”与“搬走的函数”同时使用的不许搬——
   `tools/p85_inventory.py m0` 的闭包检查会拒绝这种搬移。
2. **跨单元走 `pub` 接口或显式传参**：M0 只把 `static` 函数改 `pub` + 在新单元里
   生成一行 `pub` 原型（接口变化，卡允许），不改函数体、不改调用点。
3. **允许暴露状态**：`struct Sha256` 之类的数据单元在 M0 里没有搬（`size_t` 参数
   会让生成的 `.h` 出现 `size_t`，而头文件不带 `#include`）；这条边界写进
   [p85_m0.md](p85_m0.md) §3，不当作“漏搬”。

## 3 导入图

### 3.1 邻接表（源单元 → 直接 import 的单元）

| 单元 | 直接依赖 |
| --- | --- |
| `backend/emit/Emitter.h.ct` | `EmitterText.h.ct`, `Init.h.ct`, `Lexer.h.ct`, `MapTable.h.ct`, `Unit.h.ct`, `Expr.h.ct`, `Symbols.h.ct`, `SymbolsTypeText.h.ct`, `TypeCheck.h.ct`, `Arena.h.ct` |
| `backend/emit/EmitterText.h.ct` | `Init.h.ct`, `Lexer.h.ct`, `MapTable.h.ct`, `Unit.h.ct`, `Expr.h.ct`, `Symbols.h.ct`, `SymbolsTypeText.h.ct`, `TypeCheck.h.ct`, `Arena.h.ct` |
| `backend/emit/Init.h.ct` | `Symbols.h.ct` |
| `backend/mem/Memory.h.ct` | `Symbols.h.ct`, `Arena.h.ct`, `Diag.h.ct` |
| `frontend/module/Module.h.ct` | `Emitter.h.ct`, `Memory.h.ct`, `Lexer.h.ct`, `ModuleBoundary.h.ct`, `Unit.h.ct`, `Parser.h.ct`, `Symbols.h.ct`, `TypeCheck.h.ct`, `Arena.h.ct`, `Cache.h.ct`, `Diag.h.ct`, `Sh.h.ct` |
| `frontend/module/ModuleBoundary.h.ct` | `Emitter.h.ct`, `Memory.h.ct`, `Lexer.h.ct`, `Unit.h.ct`, `Parser.h.ct`, `Symbols.h.ct`, `TypeCheck.h.ct`, `Arena.h.ct`, `Cache.h.ct`, `Diag.h.ct`, `Sh.h.ct` |
| `frontend/parse/Expr.h.ct` | `Memory.h.ct`, `Lexer.h.ct`, `MapTable.h.ct`, `ExprTypeText.h.ct`, `ParseSupport.h.ct`, `Symbols.h.ct`, `SymbolsTypeText.h.ct`, `TypeCheck.h.ct`, `Arena.h.ct`, `Diag.h.ct` |
| `frontend/parse/ExprTypeText.h.ct` | `Memory.h.ct`, `Lexer.h.ct`, `MapTable.h.ct`, `ParseSupport.h.ct`, `Symbols.h.ct`, `TypeCheck.h.ct`, `Arena.h.ct`, `Diag.h.ct` |
| `frontend/parse/MapBuild.h.ct` | `Memory.h.ct`, `Lexer.h.ct`, `MapTable.h.ct`, `Expr.h.ct`, `ParseSupport.h.ct`, `Symbols.h.ct`, `Diag.h.ct` |
| `frontend/parse/ParseSupport.h.ct` | `Memory.h.ct`, `Lexer.h.ct`, `Symbols.h.ct`, `TypeCheck.h.ct`, `Arena.h.ct`, `Diag.h.ct` |
| `frontend/parse/Parser.h.ct` | `Memory.h.ct`, `Lexer.h.ct`, `MapTable.h.ct`, `Expr.h.ct`, `MapBuild.h.ct`, `ParseSupport.h.ct`, `Stmt.h.ct`, `Symbols.h.ct`, `SymbolsTypeText.h.ct`, `TypeCheck.h.ct`, `Arena.h.ct`, `Diag.h.ct` |
| `frontend/parse/Stmt.h.ct` | `Memory.h.ct`, `Lexer.h.ct`, `Expr.h.ct`, `ParseSupport.h.ct`, `StmtRangeText.h.ct`, `Symbols.h.ct`, `SymbolsTypeText.h.ct`, `Arena.h.ct`, `Diag.h.ct` |
| `frontend/parse/StmtRangeText.h.ct` | `Memory.h.ct`, `Lexer.h.ct`, `Expr.h.ct`, `ParseSupport.h.ct`, `Symbols.h.ct`, `Arena.h.ct`, `Diag.h.ct` |
| `frontend/sym/Symbols.h.ct` | `SymbolsTypeText.h.ct` |
| `frontend/type/TypeCheck.h.ct` | `Lexer.h.ct`, `MapTable.h.ct`, `Symbols.h.ct`, `SymbolsTypeText.h.ct`, `Arena.h.ct` |
| `main.ct` | `Emitter.h.ct`, `Memory.h.ct`, `Lexer.h.ct`, `MapTable.h.ct`, `Module.h.ct`, `Unit.h.ct`, `Parser.h.ct`, `Symbols.h.ct`, `TypeCheck.h.ct`, `Arena.h.ct`, `Cache.h.ct`, `Diag.h.ct`, `Driver.h.ct`, `Pkg.h.ct` |
| `tool/driver/Driver.h.ct` | `Emitter.h.ct`, `Memory.h.ct`, `Lexer.h.ct`, `Module.h.ct`, `ModuleBoundary.h.ct`, `Parser.h.ct`, `Symbols.h.ct`, `Arena.h.ct`, `Diag.h.ct`, `Pkg.h.ct` |
| `tool/pkg/Pkg.h.ct` | `PkgIndex.h.ct`, `Sh.h.ct` |
| `tool/pkg/PkgIndex.h.ct` | `Sh.h.ct` |
### 3.2 环清单

- **cycles: 0**。基线（`10c23c77`）就没有导入环；M0 的 6 个新单元都**不**导入宿主，
  依赖方向是“宿主 → 新单元”，因此没有新增环（J4）。
- 现状的“非环但重”依赖：`frontend::parse` 的 7 个单元几乎都依赖
  `Symbols` + `ParseSupport` + `Expr`，这是 PH-86–88 要保留的边界；破环/减边不在
  M0 范围（D-017 A4：破环单独成案）。

## 4 可折叠 helper（R 切片目标）

R 切片（PH-86–88）用 `?`/`errdefer`/`match` 折叠的候选，按“可机械识别”的三类列出；
数字由 `tools/p85_inventory.py` 的同名扫描给出（函数体为口径）。

### 4.1 `?`（错误传播）

- 函数体里 `return -1;` 共 **1642** 处、分布在 **308** 个函数；`?` 能折叠的是
  “检查 → 立即返回错误码”的直线前缀，典型：
  `emit_expr`、`emit_node`、`parse_postfix`、`parse_stmt`、`parse_decl_node`、
  `chk_assignable`、`chk_mcall_args`、`sym_find` 系列、`pkg_*` 系列。
- 词法器**没有**错误通道（`toktrunc` 是标志位，错误由解析器报），所以 `?` 在
  `Lexer` 上不适用——这是 PH-86 的范围边界。
- 折叠判据（PH-86 卡）：折叠后 `return -1` 的语义（-1 是“错误”而非“任意负值”）
  与 `#line`/诊断位置不变。

### 4.2 `errdefer`（清理）

- `goto` 集中在 9 个函数：`pkg_index_verify`（10 处，错误行/文件清理）、
  `func_end`（7，defer/errdefer 收尾）、`build_main`（6，临时目录/缓存）、
  `parse_func`（3）、`is_decl_start`（2），以及 `parse_stmt`/`parse_decl_node`/
  `parse_block`/`emit_node` 各 1。
- 这些函数是 PH-87/88 的 `errdefer` 首选；`own` 资源（`FILE *`、堆分配）的释放点
  与 `goto` 标签同址。

### 4.3 `match`（穷尽判别）

- `N_*` 判别链（函数体内不同 kind 测试数 ≥8）：**21** 个函数，最大的是
  `Emitter::emit_node`（37）、`Emitter::emit_expr`（35）、`Parser::out_scan`（23）、
  `TypeCheck::expr_type`（20）、`Expr::parse_postfix`（19）、`Expr::chk_type`（17）、
  `Stmt::parse_stmt`（14）、`Expr::static_ctype`（14）、`Expr::parse_primary`（13）、
  `Emitter::emit_inline`（13）、`Expr::parse_expr`（11）、`Emitter::expr_unstable`（11）。
- `switch (…kind)` 语句另有 5 处（`chk_type` 17 case、`static_ctype` 14、
  `map_fold_num` 10、`emit_node` 6、`parse_stmt` 4）。
- PH-84 的 ADT/`match` 是这些判别链的落点；`Emitter::emit_node`/`emit_expr` 是
  PH-88 的主目标，`chk_type`/`static_ctype` 归 PH-87。

### 4.4 不适合折叠的 helper（M0 已确认不动）

- `sb_*`（`StrRetain` 簿记）：状态是 `g_sb`，被 `emit_node`/`emit_decl` 等大量方法
  使用；`?`/`errdefer` 不减少状态耦合，不得为折叠而拆。
- `num_accumulate`：饱和到 `LONG_MAX`（UBSan 护栏），不是错误路径。
- `lex_*`：见 spike 的 sharp edge（§3），词法器的“现代化”是 `Str` 视图迁移，不是
  `?`/`match`。

## 5 未覆盖 / 简化

| # | 项 | 现状 | 去向 |
| --- | --- | --- | --- |
| 1 | 文件级状态的**动态**生命周期（谁在何时赋值） | 只列归属与使用方，不追踪时序 | PH-86–88 逐切片时补 |
| 2 | `tool::pkg` 的 `g_sha_k`/`struct Sha256` | 留在宿主（`size_t` 会进 `.h`） | PH-86 词法器之外的独立小任务 |
| 3 | 导入图仍偏重（parse 7 单元互依） | 只登记，不破环 | D-017 A4：破环单独成案 |
| 4 | 函数体哈希只覆盖 `{ … }` 文本 | 注释/签名变化不计 | 与 J1 口径一致（见 p85_m0.md） |
