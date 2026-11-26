# 容量上限清单与放开计划（L0 遗留）

> 状态：**盘点完成；S1a-0 实施中**（2026-11-25：`MAX_NODES`/`MAX_WARNINGS` 与 A 类表/实例/形参/调用/标签/布局/hoist/into 等已动态；2026-11-25 再落 module 表（UNITS/IMPORTS/INCDIRS）、pkg 表（DIGEST_FILES/INDEX_ROWS 已动态）与初始化文本（RAW_INIT/INIT_ITEM）与 map 表；`MAX_MAPS`（含 `MapTable.b` 与 `MapBind` 参数并行表）已动态；`MAX_PKG_DEPS`（含 `ct.lock` 行块与构建期锁根）已动态；**C 类已全部动态：ADT 计数（`MAX_ADTS` / `MAX_ADT_VARIANTS` / `MAX_ADT_FIELDS`）与泛型元数（`MAX_STRUCT_TPARAMS`）**；**C2 文本/路径开始：raw 块已收到 `TEXT_LIMIT=65536`（C2a），缓存键（C2b）、初始化文本（C2c）、pkg 锁文本（C2d）、pkg 命令/路径文本（C2e）、cc 命令行（C2f）、cflags/ldflags 累加器（C2g）、pkg 行读取（C2h）、包目录/树扫描路径（C2i）与 dep 行（C2j）已按需增长**；**`MAX_PKG_PATH` 已全部退场（C2k）：store / 锁行 / 索引 / 锁根路径改按需，源码与 `Limits.h.ct` 中不再有该 cap**；B/D 类其余待做）。**C2l/C2m：`MAX_PATH` 已全部退场（`Diag.file`、Cache 路径、Unit/Driver/Module/Emitter/ModuleBoundary）**；**C2n 驻留池与 C2o 硬编码长度已完成（见 §5.5）**。
> 目标：把 L0 阶段留下的“固定上限 + 越界硬报错”全部改为按需容量；只保留 OOM 安全阀与真正的语言语义上限。
> 基线：`v1.1.0`（`54b60225` 之后的规划提交）。

## 0 结论

- `ct-ast` 共 **49** 个 `Limits.h.ct` 常量 + **8** 个单元内本地常量 + **约 14** 处硬编码数字上限；
- A 类多数表已按需增长（SH-109 起，初值 + 倍增 + 65536 安全阀）；
- **C 类**：`MAX_ADTS` / `MAX_ADT_VARIANTS` / `MAX_ADT_FIELDS` 与 `MAX_STRUCT_TPARAMS` 均已动态（C3）；
- 尚未放开的仍是“固定上限 + 越界报错”；其中 `MAX_METHODS=64` 已挡住新增方法，`MAX_TEXT=160` 在 31 个单元出现 **1494** 次、定长数组 **791** 处，是最大的一块；
- 放开分四类：**A 计数**（动态数组）、**B 文本/路径**（按需分配）、**C 语言语义上限**（一并放开，但必须先同步 spec / stable-subset）、**D 资源保护**（保留必要的深度/恢复保护）。
- **形式上限（2026-11-25 所有者裁定）**：所有放开项统一收敛到一个形式上限 `CAP_LIMIT = 65536`（与 `MAX_FUNCS_MAX` 同形）；文本类另有 `TEXT_LIMIT = 65536` 字节。真实程序不应触到它，触到只作 OOM/资源保护报错。只有深度/错误恢复类保护保留原值。

## 1 分类规则

| 类 | 含义 | 处置 |
| --- | --- | --- |
| A | 表/栈/实例表的**条数**上限 | 动态倍增到 `CAP_LIMIT=65536`；删越界诊断 |
| B | 单条记录里的**字符/路径/命令缓冲** | 按需分配，单条到 `TEXT_LIMIT=65536` 字节；消除静默截断 |
| C | **语言语义**上限（泛型元数、ADT 形态） | 一并放开到 `CAP_LIMIT`；**先同步 spec §8 / stable-subset**，再改实现 |
| D | **递归深度 / 安全阀 / 错误恢复** | 保留，文案改为 resource limit；不作为功能上限宣传 |

## 2 49 个 `Limits.h.ct` 常量

> “使用次数”为 `selfhost/ct-ast/**/*.h.ct` 中该宏出现的次数（镜像也算），由 2026-11-25 脚本统计。
> **A 类统一动态到 `CAP_LIMIT=65536`；B 类单条动态到 `TEXT_LIMIT=65536` 字节；C 类同样收到这两个形式上限。**

| 常量 | 值 | 次数 | 类 | 动作 |
| --- | --- | --- | --- | --- |
| `MAX_FUNCS` | 512 | 19 | A | **已动态（SH-109）**；保留初始值 |
| `MAX_METHODS` | 64 | 27 | A | **已动态**：`Trait.m` 堆块 + `MAX_METHODS_MAX=65536`；trait 实例行深拷贝方法块；parser 默认体环检查矩阵按实扩；`MapTable.b`（一个 map 的绑定块）以 64 为初值倍增 |
| `MAX_VARS` | 4096 | 12 | A | **已动态**（符号表 `vars`，`MAX_VARS_MAX=65536`）；Memory 的 `own` 计数表仍 4096，剩余 |
| `MAX_SCOPE` | 256 | 5 | A | 符号表 `scope` 栈已动态（`MAX_SCOPE_MAX`）；可观察嵌套仍受 parser 递归深度 256 保护（D 类，360 层实测栈溢出），剩余 |
| `MAX_TYPES` | 256 | 4 | A | **已动态**：`types`/`type_kind`/`type_target` 三组并行数组一起倍增到 `MAX_TYPES_MAX=65536` |
| `MAX_STRUCTS` | 128 | 10 | A | **已动态**：单元 struct 表（与实例行共用一个块）倍增到 `MAX_STRUCTS_MAX=65536` |
| `MAX_TRAITS` | 64 | 8 | A | **已动态**（trait 行表 + 实例行）；`StructDef.use[64]` 的采纳列表仍 64，剩余 |
| `MAX_FIELDS` | 64 | 10 | A | **已动态**：`StructDef.fields`/`StructTmpl.fields`/parser 待定字段表各自倍增到 `MAX_FIELDS_MAX=65536` |
| `MAX_STRUCT_INSTS` | 128 | 10 | A | **已动态**：单元内实例行并入 struct 表；全局 `g_insts` 倍增到 `MAX_STRUCT_INSTS_MAX=65536` |
| `MAX_STRUCT_IMPLS` | 64 | 4 | A | **已动态**：全局 `g_impls` 倍增到 `MAX_STRUCT_IMPLS_MAX=65536` |
| `MAX_STRUCT_TPLS` | 64 | 4 | A | **已动态**：全局 `g_tmpls` 倍增到 `MAX_STRUCT_TPLS_MAX=65536` |
| `MAX_GENERIC_INSTS` | 64 | 5 | A | **已动态**：单元 `ginsts` 倍增到 `MAX_GENERIC_INSTS_MAX=65536` |
| `MAX_CLOSURES` | 64 | 5 | A | **已动态**：单元 `closures` 倍增到 `MAX_CLOSURES_MAX=65536`；emitter 每帧 64 绑定上限另列剩余 |
| `MAX_CALLS` | 8192 | 7 | A | **已动态**：调用图 `calls` 堆块倍增到 `MAX_CALLS_MAX=65536`；删除 `too many calls` |
| `MAX_ARG_POS` | 32 | 14 | A | **已动态**：`arg_line`/`arg_col` 并行块倍增到 `MAX_ARG_POS_MAX=65536`；第 33 个以后不再静默丢位置 |
| `MAX_LABELS` | 64 | 5 | A | **已动态**：label/goto 行块（`LabelRow`）倍增到 `MAX_LABELS_MAX=65536`；删除 `too many labels/gotos` |
| `MAX_HOISTS` | 4 | 4 | A | **已动态**：`hoist_calls` 行表 + 局部接收者链倍增到 `MAX_HOISTS_MAX=65536` |
| `MAX_INTOS` | 4 | 3 | A | **已动态**：`into_nodes` 行表倍增到 `MAX_INTOS_MAX=65536` |
| `MAX_MAPS` | 64 | 5 | A | **已动态**：`g_maps` 表倍增到 `MAX_MAPS_MAX=65536`（parse/type/emit 改持槽位）；`MapTable.b[64]` 改堆块（`MAX_METHODS` 初值）、`MapBind.params/uses/sizeofs[16]` 改并行堆块（`MAX_PARAMS` 初值）；`--emit-map` 与 `map_visible` 全表扫描；`emit_recipe` 的 `actual[16]` 改按绑定分配 |
| `MAX_METH_ANN` | 256 | 4 | A | **已动态**：`MethAnn` 行表倍增到 `MAX_METH_ANN_MAX=65536`；每行注记块也随 `MAX_PARAMS` 增长 |
| `MAX_PARAMS` | 16 | 21 | A | **已动态**：`Fn`/`MethodSig` 形参三/两组并行块 + `MethAnn` 注记块倍增到 `MAX_PARAMS_MAX=65536`；实例行深拷贝；map 绑定的 `params`/`uses`/`sizeofs` 并行块同样倍增（初值 16） |
| `MAX_TYPE_ALIASES` | 64 | 6 | A | **已动态**：本地 `taliases` 倍增到 `MAX_TYPE_ALIASES_MAX=65536` |
| `MAX_GLOBAL_TYPE_ALIASES` | 256 | 4 | A | **已动态**：全局 `gtaliases` 倍增到 `MAX_GLOBAL_TYPE_ALIASES_MAX=65536` |
| `MAX_IMPORTS` | 32 | 10 | A | **已动态**：`Module` 的单元依赖行 `dep`/`depu` 与 `Parser` 的导入表一起倍增到 `MAX_IMPORTS_MAX=65536`；删除 `too many imports`，`cache_key_of` 的 `MAX_IH` 定长块改为按 `ndep` 分配 |
| `MAX_INCDIRS` | 16 | 4 | A | **已动态**：`Module.incdirs` 堆块倍增到 `MAX_INCDIRS_MAX=65536`；删除 `too many -I roots` |
| `MAX_UNITS` | 64 | 24 | A | **已动态**：`Module.units` 堆块倍增到 `MAX_UNITS_MAX=65536`（扩容后重绑 emitter），`build_main` 的 inputs/cache 行走堆块，可达性 scratch 按 `nunits` 增长；删除 `too many units` / `too many inputs` |
| `MAX_PKG_DEPS` | 16 | 42 | A | **已动态**：`struct Pkg` 的 `seen`（扁平 `MAX_TEXT` 行）与 `recs`（结构体行）倍增到 `MAX_PKG_DEPS_MAX=65536`；manifest 的 `dep` 行、`ct.lock` 的四列（`LockRow`：name/ver/ns/dig + install 的 ipath）、构建期锁根扫描（`LockParsedRow`）、`ct index refresh`/`ct migrate` 的 dep 表、`Driver` 的 `-I` roots/notes 全部改动态行块；删除 `too many packages` 与 `ct.lock lists more than 16 packages` |
| `MAX_DIGEST_FILES` | 4096 | 4 | A | **已动态**：`dir_digest` 的文件路径块按倍增 realloc 到 `MAX_DIGEST_FILES_MAX=65536`（`sha_collect` 收 `char **`/`int *cap`），4100 文件树可算摘要 |
| `MAX_INIT_ITEM` | 4096 | 3 | A | **已动态**：`rewrite_init_text` 的单项暂存按该行捕获文本长度分配（不再受 4096 限制），`MAX_INIT_ITEM_MAX=65536` 为形式上限 |
| `MAX_RAW_INIT` | 4096 | 9 | A | **已动态**：`ParseSupport` 的花括号捕获缓冲区倍增到 `MAX_RAW_INIT_MAX=65536`，`init_raw(char **out)` 返回内部块；删除 `initializer is too long` 的 4096 上限 |
| `MAX_LAYOUT_ADTS` | 64 | 5 | A | **已动态**：`g_adt_layout_state` 堆块倍增到 `MAX_LAYOUT_ADTS_MAX=65536`；ADT 表本身也按需增长（C3），不再遮蔽 |
| `MAX_LAYOUT_INSTS` | 128 | 11 | A | **已动态**：`g_inst_layout_state`/`g_shell_emit_state` 倍增到 `MAX_LAYOUT_INSTS_MAX=65536`；`EmitterQuery` 的全表扫描去掉固定界 |
| `MAX_WARNINGS` | 32 | 15 | A | **已落**：`warns` 倍增到 65536；`--max-warnings` 另议 |
| `MAX_ADTS` | 64 | 5 | C | **已动态（C3）**：ADT 行块倍增到 `MAX_ADTS_MAX=65536`，初值 64；spec §4.73 / stable-subset 同步 |
| `MAX_ADT_VARIANTS` | 96 | 3 | C | **已动态（C3）**：每个 ADT 的变体行块倍增到 `MAX_ADT_VARIANTS_MAX=65536`，初值 96；`match` 覆盖 scratch 按变体数分配 |
| `MAX_ADT_FIELDS` | 8 | 3 | C | **已动态（C3）**：每个变体的负载字段行块倍增到 `MAX_ADT_FIELDS_MAX=65536`，初值 8；`match` 绑定名表按字段数分配 |
| `MAX_STRUCT_TPARAMS` | 2 | 14 | C | **已动态（C3）**：行块倍增到 `MAX_STRUCT_TPARAMS_MAX=65536`，初值 2；spec §8 / §4.51 / §4.55 / stable-subset 同步 |
| `MAX_ALIAS_CHAIN` | 32 | 7 | D | 递归链保护；保留 |
| `MAX_LAYOUT_DEPTH` | 32 | 8 | D | 递归深度保护；保留 |
| `MAX_PKG_DEPTH` | 8 | 4 | D | 依赖深度保护；保留 |
| `MAX_FUNCS_MAX` | 65536 | 10 | D | OOM 安全阀；保留 |
| `MAX_NODES` | 262144 | 7 | D | **已落**：arena 倍增到 `NODE_LIMIT=16777216`（新槽清零） |
| `MAX_TEXT` | 160 | 1494 | B | 动态文本；当前 791 处定长数组，最大切片 |
| `MAX_PATH` | 1024 | 72 | B | **已全部退场（C2l/C2m）**：cap 从 `Limits.h.ct` 与六个单元删除，源码不再有该 define。C2l 改 `Diag.file`（记录持有精确自有路径，`diag_reset` 释放）与 `Cache.paths`（目录/键文件返回自有块，初值 1024 倍增到 `TEXT_LIMIT`）；C2m 改 `Unit.path/shim_dir/shim_h/shim_c`、`Module` 的 `outdir/map_path/model_path` 与 `resolve_import/find_builtin/load_unit/check_ns_dir/leaks_for`、`Driver.default_output/load_builtin/ct check` 的路径、`Emitter` 的 `.c/.h` 与 header guard、`ModuleBoundary` 的 `ct_norm_path/ct_root_find/ct_pkg_key`。全部为 `char *` 或 run-scoped 块（`ct_scratch_*`，1024 初值→`TEXT_LIMIT`，OOM/超限显式），命令结束时统一释放；旧「path is too long / output directory is too long / import path is too long」截断与拒绝删除。正例：1500 字节逻辑 `--outdir`、1406 字节逻辑缓存键、1500 字节逻辑诊断路径；Linux CI 用真实 >1024 字节源/输出/导入路径（Darwin 条件 skip）。 |
| `MAX_PKG_PATH` | 512 | 85 | B | **已全部退场（C2k）**：cap 从 `Limits.h.ct` 与 `Pkg.h.ct` 删除。包目录/树扫描（C2i）、dep 行（C2j）之外，store 路径（`pkg_store_root/dir/pkgdir` 返回精确自有字符串，`pkg_mkdirs`、`pkg_store_commit.parent`）、记录字段（`PkgRec.store`、`LockRow.ipath`、`LockParsedRow.full/loc/nsr`、`IndexRow.url`、`Pkg.index`）与消费点（`install` 的 `vdir/rel/cand`、`pkg check` 的 `cdir/cpath/cqueue`、`pkg_index_lookup/verify` 的 path、`pkg_verify_lock.vdir`、`pkg_migrate` 的 `nsroot/src/store`）全部改 `char *`/按需；`ct_pkg_lock_roots` 的 `roots/notes` 从 512-stride 扁块改为指针行，Driver 直接取 `roots[i]`/`notes[i]`。`ns-root` 也由 `pkg_read_identity` 返回精确自有字符串。正例：538 字节 store 路径（get/verify/install）、574 字节包目录（build 的 lock root 与 `pkg check`）、562 字节 index git-url、570 字节 index 路径（`--index` / `index verify`） |
| `MAX_PKG_CMD` | 2048 | 35 | B | **已动态（C2e）**：`Pkg` 的命令/路径缓冲改 `self` 持有的按需文本（初值 2048，倍增到 `TEXT_LIMIT=65536`，OOM 显式）；`sh_quote` 改为 `char **` + 容量，`git_run` / `fetch_git` / `git_pick_tag` / `install` / `update` 的定长命令缓冲删除；文本在 `ct_pkg_*` 入口返回时由 `pkg_owned_free` 统一释放 |
| `MAX_KEY` | 768 | 8 | B | **已动态（C2b）**：缓存键按需增长（初值 768，倍增到 `MAX_KEY_MAX=65536`）；`Cache.key` 返回 `char **` + 容量，OOM/超限显式报错，不再静默跳过缓存 |
| `MAX_INIT_TEXT` | 16384 | 8 | B | **已动态（C2c）**：重写文本按需倍增到 `MAX_INIT_TEXT_MAX=65536`；单项与改名 scratch 按实际长度分配；超限报 `initializer text exceeds 65536 bytes`，不再无诊断地返回 -1 |
| `MAX_RAW_BLOCK` | 32768 | 3 | B | **已动态（C2a）**：块字节写入可增长的字面量池，定长上限删除，只余形式上限 `TEXT_LIMIT=65536` |

## 3 单元内本地常量（不在 Limits）

| 常量 | 值 | 位置 | 类 | 动作 |
| --- | --- | --- | --- | --- |
| `MAX_FLAGS` | 1024 | `Module.h.ct` / `Driver.h.ct` | B | **已动态（C2g）**：`Module.cflags`/`ldflags` 由定长 `char[1024]` 改 `char *` + 容量（`ct_append_flags(char **, int *, init, val)`，初值 1024 倍增到 `TEXT_LIMIT`）；build 与 compile 两条命令行都追加同一累加器，`ct_module_free_flags` 在 driver 返回后释放 |
| `MAX_CMD` | 8192 | `Module.h.ct` | B | **已动态（C2f）**：`Module` 的 link/archive 命令行改 `char **` + 容量（初值 8192，倍增到 `TEXT_LIMIT=65536`）；`ct_cmd_raw`/`ct_cmd_token` 改为向 `tool/sh/Sh.h.ct` 的 `ct_text_*` 追加，quoted token 不再先落 `char q[MAX_PATH]`；lib 模式的每对象/ar 行与 `ZERO_AR_DATE=1` 包装同样按需 |
| `MAX_ERRORS` | 20 | `Diag.h.ct` | D | 错误恢复上限；保留并明确文案 |
| `MAX_LOCK` | 4096 | `Pkg.h.ct`（旧 8 × 512） | B | **已动态（C2d）**：`struct Pkg.lock` 改堆块倍增到 `MAX_LOCK_MAX=65536`；`get` 追加、`pkg_lock_keep` scratch、`update`/`migrate` 读写与 `ct.pkg` 读取都按实际大小分配；41 行锁（4721 字节）可 get/verify/update/build |
| `MAX_PKG_LINE` | 1024 | `Pkg.h.ct` | B | **已动态（C2h）**：Pkg 的行读取（`ct.lock` / `ct.pkg` / index / package list）改 `pkg_text_fgets`（初值 1024，倍增到 `TEXT_LIMIT=65536`）；index verify 的 `seen` 改指针行（每行 `pkg_text_dup`），index refresh 的输出按行实际长度求和、`key`/`prev` 与全部诊断消息改 `pkg_text_setf`；删除「line is longer than 1023 bytes」，不再把长行切成伪行 |
| `MAX_PKG_GITERR` | 8 | `Pkg.h.ct` | D | 展示行数；保留 |
| `MAX_INDEX_ROWS` | 1024 | `Pkg.h.ct` | A | **已动态**：`ct index refresh` 行表倍增到 `MAX_INDEX_ROWS_MAX=65536`；删除 `package list has more than 1024 rows` |

## 4 硬编码数字上限

| 位置 | 上限 | 类 | 动作 |
| --- | --- | --- | --- |
| `StmtDefer.h.ct` | postfix `?` 512 | A | 动态 |
| `Stmt.h.ct` | owned 变量 4096 | A | 动态（并入 `MAX_VARS`） |
| `Stmt.h.ct` | 初始化元素 1024 | A | 动态 |
| `Stmt.h.ct` | 初始化项 1024 | A | 动态 |
| `Stmt.h.ct` | range 元素 1024 | A | 动态 |
| `Stmt.h.ct` | match 臂绑定数 | A | 动态 |
| `Expr.h.ct` | 闭包捕获 16 | A | 动态 |
| `Expr.h.ct` | 闭包参数 16 | A | 动态 |
| `Expr.h.ct` | 闭包嵌套 16 | D | 递归保护；保留 |
| `Symbols.h.ct` | import 别名 24 | A | **已动态（C2o）**：别名行改指针行，别名本身是 pool 文本；同一提交把 import 路径段表也改为按需 |
| `Symbols.h.ct` | 导出类型名 128 | A | **已动态（C2o）**：`tbare`/`tfull`/`tbambig` 改按需指针行（初值 `MAX_EXPORTED_TYPES`=128，形式上限 65536） |
| `Symbols.h.ct` / `Expr.h.ct` | 实例名 159 字符 | B | **剩余**：模板实例名拼接仍在 `ExprTypeParse` 用 159 字符诊断；长**源标识符**已不经过它（C2o） |
| `Lexer.h.ct` | 标识符 159 / 字符串字面量 158 字节 | B | **已动态（C2o）**：token 视图不再按 159 截断，只在 `TEXT_LIMIT=65536` 显式报错；`tok_cstr` 的 C 边界缓冲按 token 长度 realloc |

## 5 实施顺序（`v1-PH-2` S1a-0）

| 切片 | 内容 | 判据 |
| --- | --- | --- |
| C1 计数 | 33 个 A 类（含本地 `MAX_INDEX_ROWS` 与第 4 节 A 类字面量）：`realloc` 倍增，OOM 阀与 `MAX_FUNCS` 同形 | 旧上限的越界负例改为“可增长并通过”；新增扩容用例；生成物逐字节 |
| C2 文本/路径（已完成 C2a–C2m） | 路径/命令/键/锁/行/初始化文本等已按需增长；`MAX_PKG_PATH`、`MAX_PATH` 已退场 | 切片证据见 §2 / §3 |
| C2n `MAX_TEXT` 驻留池 | 把 791 处 `char[MAX_TEXT]` 改“字符串驻留池 + 偏移/句柄”，一次替换；分三步：①池单元 + 符号表字段 ②parser/Expr/Stmt ③emitter/诊断 | 池自测（去重、超 `TEXT_LIMIT` 报错）；名字 API 统一；生成物逐字节；seed 两轮 |
| C2o 硬编码长度 | 标识符/字面量 159/158、import 别名 24、导出类型名 128、限定名 8 段/qcap、offsetof 字段 → 池/动态；`TEXT_LIMIT` 为唯一形式文本上限 | 长名正例（2000 字节标识符/字面量/别名/字段、24 段限定名、218 字节命名空间、>128 导出类型）；旧上限负例改“增长成功”；生成物逐字节 |
| C2p 合批 | 每提交 4–6 个单元（单元簇），不按单 cap 一片；C4 只在收口做一次 | 每提交只重生成一次 seed；`check-ast` 绿 |
| C3 语言上限（已完成） | `MAX_ADTS` / `MAX_ADT_VARIANTS` / `MAX_ADT_FIELDS` / `MAX_STRUCT_TPARAMS` 已放到形式上限，spec §8 / stable-subset 同批改写 | 已有切片证据；spec 与实现一致 |
| C4 测试与文档 | TEST-9 的“too many”契约改为“增长成功”；spec §8 上限表退役；`Limits.h.ct` 只留 `CAP_LIMIT` / `TEXT_LIMIT` / `NODE_LIMIT` 与 D 类 | `check-all` 绿；seed 两轮逐字节 |

- C2a–C2m 已落地的切片不回滚；**C2n 是单写者阶段**：池迁移期间不允许并行改 Expr/Stmt；
- C2n 完成后再做 C2o/C2p；C2p 的并行只适用于 S1a-1（见卡 N-7）；
- C3 与 C1/C2 同属 S1a-0，但 spec / stable-subset 的改写必须与实现同批提交，不允许实现先行；
- 每个切片都要重生成 `bootstrap/ct-ast` 并过 gate 13（内置层/编译器自身布局变化）。

## 5.1 C2n-0 spike：驻留池 + `TypeAlias` 迁移

**目的**：用一个最小结构体验证“字符串驻留池 + 字段改 `const char *`”的形状，再批量迁移 791 处
`char[MAX_TEXT]`。spike 只迁 `Symbols.h.ct` 的 `TypeAlias.name` / `.target`，**不动** `path`、
parser、emitter，也不改任何诊断文案。

### 5.1.1 新单元与 API

新单元 `selfhost/ct-ast/runtime/text/Intern.h.ct`（`namespace runtime::text`），提供：

| API | 语义 |
| --- | --- |
| `pub const char *ct_intern(const char *s)` | 去重后返回稳定指针；`NULL` 表示 OOM 或超 `TEXT_LIMIT` |
| `pub const char *ct_intern_len(const char *s, int n)` | 同上，允许非 NUL 结尾片段 |
| `pub void ct_intern_reset(void)` | 仅测试用；生产进程不调用 |

实现要求：

- FNV-1a + 开放寻址；装载因子 0.7 时表按 2 倍增长；`strcmp` 去重；
- 每条字符串单独 `malloc` 复制，长度上限 `TEXT_LIMIT=65536`；超限返回 `NULL`，**不截断**；
- 池内存在进程生命周期内不释放（编译一次即退出）；`ct_intern_reset` 只在测试中释放；
- 指针稳定：池增长只搬表项，不搬字符串本体。
- 若 Ct 的 `pub` 自由函数在 `const char *` 返回值上有语法限制，退回 `char *`（池内仍只读），
  在函数注释里标明“caller must not mutate”，不改变调用点语义。

### 5.1.2 迁移步骤（一个提交）

1. 新建 `runtime/text/Intern.h.ct`，在 `Symbols.h.ct` 加 `import runtime::text::Intern;`；
2. `pub struct TypeAlias` 的 `char name[160]` / `char target[160]` 改 `const char *`；
3. 三处写入点（`begin_type_alias` / `finish_type_alias` / `add_visible_type_alias` /
   `add_forward_type_alias`）由 `snprintf(..., MAX_TEXT, ...)` 改 `ct_intern(...)`；
   `NULL` 时走既有 `fail` 路径并给 OOM 文案，不落半成品；
4. 复查 `sizeof(name)`、`strncpy`、`memcpy`、按值赋值与 reset：指针复制即可，
   **reset 不得 free**（池拥有）；
5. 生成物对照：用户语料 `check-goldens-ast.sh` 25/25；编译器自身 C/seed 允许差异（D-017 A1 第 2 层）；
6. `gen-seed.sh` + `check-seed.sh` 两轮逐字节。

### 5.1.3 spike 判据

| # | 判据 |
| --- | --- |
| S1 | `ct_intern("x") == ct_intern("x")`（指针相等）；`ct_intern_len("abc",2)` 得 `"ab"` |
| S2 | 64 KiB 字符串可 intern；65537 字节返回 `NULL` 且有明确错误，不截断 |
| S3 | 生成 2000 个不同别名（`type A0001 = int;` …）编译通过；重复别名不触发额外分配 |
| S4 | `check-goldens-ast.sh` 25/25；`check-ast.sh` fixpoint；`p85_inventory.py cycles` 0 |
| S5 | `TypeAlias` 内不再有 `char [160]`；`MAX_TEXT` 在 `Symbols.h.ct` 的引用数下降（记录前后 `grep -c`） |
| S6 | seed 两轮逐字节；`check-all` 绿 |

S1/S2 用独立 C harness 链接生成的 `Intern.c`（`test/ast/intern_pool.sh`），不进编译器 CLI；
S3 用生成的 `.ct` 夹具。

### 5.1.4 回滚与风险

- 回滚：revert 该提交 + 重生成 seed；池是新增单元，删除即恢复。
- 风险：`TypeAlias` 是 `pub struct`，改字段类型会改编译器自身头文件与 seed，但**不影响用户生成 C**；
  若某调用点依赖 `char[]` 可写（例如就地 `strcat`），改为池指针前必须先改成局部 builder。

## 5.2 C2n-1：Symbols / Module / MapTable / Unit 的持久文本字段迁移

**范围**：把四类持久记录里的定长文本字段改成 `const char *`，由
`runtime::text::Intern` 拥有；一次写入 = 一次 `ct_intern`，失败即 `fail("out of memory")`。
不迁局部 scratch（一次性格格式化、解析中的临时缓冲）与 parser/Expr/Stmt 的
arena 文本行（C2n-2）。

| 单元 | 迁移字段 |
| --- | --- |
| `Symbols.h.ct` | `TypeAlias.path`；`Fn.name/cname/ret/tparam/bound`；`Var.name/type/dims/cname/ns/slice_elem`；`Trait.name/path/ns`；`MethAnn.host/name`；`MethodSig.name/ret`；`Field.name/type/dims`；`StructDef.name/use[]`；`StructTmpl.name/full/use[]`；`StructInst.name/tmpl`；`StructImpl.tmpl/use`；`Symbols.alias_name/alias_full`（改为指针行） |
| `MapTable.h.ct` | `Call.caller/callee`；`MapBind.method/call/wrapper`；`MapTable.trait/inst/cname/prefix/vtable/host_type/bind_dst/path` |
| `Unit.h.ct` | `base` / `ns` / `nsprefix`（`path`、`shim_*` 已在 C2l 改为 run-scoped 自有块） |
| `Module.h.ct` | 无新增持久文本字段；本切片修了它对 `Unit`/`Fn`/`Var`/`StructDef` 的写入点与导入再导出路径 |

**不变量**

- 指针复制即可：`struct` 行复制、`ct_tmpls/ct_insts/ct_impls` 行复制、`trait_inst` 的
  `MethodSig` 行复制都不再复制字节；池拥有文本，按单元 reset 只清计数，**不 free**。
- 写入点全部 `ct_intern` / `ct_intern_len` / 新增 `ct_intern_join`；`ct_intern` 返回
  NULL（OOM 或超 `TEXT_LIMIT=65536`）时调用方显式报错，不截断、不落半成品。
- 命名空间拼接（`ns + name`）改用 `ct_intern_join`，不再经 160 字节 scratch：
  `Fn.cname`、`Var.cname`、`resolve_func`、导入/再导出路径与 `emit_global_decl`。
- `sizeof(field)`、对字段的 `strncpy/memcpy/memset`、`field[0] = 0` 已复查；行的
  `memset(&row, 0, sizeof row)` 只把指针置 NULL，随后必写，不释放池文本。

**证据**

- 正例：`test/ast/intern_pool.sh` S5——123 字节命名空间 + 100 字节函数/全局名，
  生成 223 字节 C 名，编译、构建、运行通过；生成 C 含完整拼写。
- 红证：同一夹具在 `baseline b380eb57` 上 `error: name is too long`（`name is too
  long` / `variable name is too long`），实现提交后转绿。
- `check-goldens-ast.sh` 25/25；`check-ast.sh` 全量（71 语料逐字节、345 诊断逐字、
  fixpoint、p88 metrics）；`check-seed.sh` 两轮逐字节；sanitizers 无报告。

**剩余（不在本切片）**

- `Closure.*`、`GenericInst.targ/cname`、`Adt*`、`Symbols.tbare/tfull/tachain` 与
  `MethodSig` 之外的 `char **` 行块（`Trait.tparam/bound/carg`、`StructDef.tparam`、
  `StructTmpl.tparam/bound`、`StructInst.carg/ctype`、`StructImpl.tparam/pat`、
  `MapBind.params/uses/sizeofs`、`Unit.dep`）留给 C2n-2 / C2o 的单元簇。
- parser/Expr/Stmt 的 arena `text/text2/text3` 与 `char[MAX_TEXT]` 局部缓冲（含
  `resolve_func` 调用点之外的名字回填）仍在 C2n-2。
- 词法器标识符上限 159 在 C2n-1 当时仍拒绝单一 >159 的标识符；C2o 已放开
  （现在只有 `TEXT_LIMIT` 形式上限）。本片段的 >160 正例来自命名空间拼接后的 C 名。

## 5.3 C2n-2：parser/Expr/Stmt 的 Node 文本迁 Intern

**范围**：`runtime::arena::Node` 的 `text` / `text2` / `text3` / `text4`
从 `char[160]` 改为 `const char *`，由 `runtime::text::Intern` 拥有；
`OutConv.formal` / `.ret` 同批。`Arena.alloc` 把四行都初始化到
`ct_intern("")`；`ct_intern` 返回 NULL（OOM）时回滚槽位并返回 -1。
行复制只复制指针；按单元 `reset` 只清 node 计数，池拥有文本、**不 free**。

**写点**（共约 216 处）：`snprintf(row, MAX_TEXT, ...)` 204 处改为
`ct_internf(fmt, ...)`（`"%s"` 单参形式直接 `ct_intern(s)`）；`tok_copy`
6 处改为 `ct_intern_len(tokstr.ptr, tokstr.len)`；`row[0] = 0` 3 处与
`OutConv` 2 处改为 `ct_intern("")` / `ct_intern(s)`；就地截尾 3 处改为
先算长度再 `ct_intern_len`（池文本不可写）。读取点不变。

**Stmt 子系统同批**：`LabelRow.name`、`Stmt.u_decl/u_asg/u_rd/u_addr`
（`[48]` 行）、`del_names`（`[64]` 行）、`yield_type`（`[16]` 行）与
`last_yield_type` 改为 `const char *`。`u_add` 的 `char[48][160]` 展平指针
算术改为行指针数组；`del_take` 的返回值扩为 1=重复删除 / 0=记录 / -1=OOM；
`yield_type` 的 out-buffer 调用改为局部 `char[MAX_TEXT]` 再 `ct_intern`；
`last_yield_type` 只是指针复制。

**`ct_internf`**（`Intern.h.ct` 唯一新增公共 helper，+1 个顶层函数）：
`vsnprintf(NULL, 0, …)` 量长 → 精确大小 `malloc` → `vsnprintf` →
`ct_intern_len`；结果超过 `TEXT_LIMIT = 65536` 返回 NULL，不截断、不插入。
`MAX_FUNCS` 已按 SH-109 动态化（初值 512、安全阀 `MAX_FUNCS_MAX` 65536），
本切片只新增这 1 个顶层 helper。

**证据**

- 正例：`test/ast/intern_pool.sh` 8/8——S5 的 223 字节 C 名在原型、定义、
  调用三处逐字保留；S6 的 200/1000 字节相邻字面量逐字节往返；S1/S2 的
  harness 覆盖 `ct_internf`（200 字节不截断、65536 接受、65537 拒绝）。
- 红证：同一 S5 在 `baseline 3ed0851b` 上函数名只出现 1 次（仅原型），
  定义与调用被 160 字节行截断，`intern_pool: 7 passed, 1 failed`。
- `check-ast.sh` 全量（71 语料逐字节、343 诊断逐字、p88 66 文件逐字节、
  2 轮自举不动点、`c2n/intern` 8/8）；`check-seed.sh` 两轮逐字节；
  `check-goldens-ast.sh` 25/25。

**剩余（C2p）**

- `Parser.ns_decl/cur_func/cur_record` 与 `Expr.cur_func` 已在 C2o 迁到 pool
  文本/指针槽；`c_base`、`out_names` 与 `Expr.fnptr_*/decl_prefix/inst_canon/
  in_generic_bound/last_bare_tag` 的 160 行仍在 C2p 合批。
- 一次性局部 `char[MAX_TEXT]` scratch 与发射器/诊断文本：合批在 C2p。

## 5.4 C2n-3：Emitter/Init/Emit* 簇的文本缓冲按需化

`backend/emit/`：持久字段/类型拼写改 `const char *` + `ct_intern`；发射输出不进
Intern（随输出增长），改用 `ct_scratch_*` builder。已迁：`Emitter.errmsg/cur_ret/`
`clvar[]/gtname/ginst`；`StrRetain` 的 `name/type/fpath/lname/ltype/method/recv`
与 `FldSnap.path`；`elem_ret_ctype`/`try_result_tag` 返回池文本；`Init` 的
`sub/next/prefix/bound`、`EmitInit` 项、`emit_hoists.hty`、`EmitInvariant` 消息与
4 处长诊断。真实截断：嵌套 vptr 的 `recv+"."+field`（90+90 字节）截成
`no member named`；`sb_rewrite_init` 跳过 >160 字节 `String` 项的 owning 改写
（`release` 释放静态存储）；`.field` 设计符与字段路径键 `base.field` 截断。
**证据**：S7 红在 baseline 38632c23（`9 passed, 2 failed`）、绿在实现后
（`11 passed, 0 failed`）；`check-ast` 71 语料 / 343 诊断 / goldens / fixpoint，
`check-seed` 两轮，warnings 559/559，sanitizers 612 项，`check-all` 8 门绿。
**剩余**：`Emitter.h.ct` 约 112 处 `char[MAX_TEXT]` 局部（`owner` 闭包键须与
`Parser.cur_func[160]` 同批迁移）；`type_needs_layout.pat` 等仍由上游 160 行界定。

## 5.5 C2o：硬编码长度改按需

**范围**：词法器/解析器单 token 的 159/158 字节、import 别名 24、导出类型名
128 行、限定名 8 段、`offsetof` 字段名、C 边界 scratch。

**实现**

- `Lexer.h.ct`：`lex_view` 只按 `TEXT_LIMIT=65536` 封顶，超过时置 `toktrunc`，
  解析器报 `identifier is too long (over the 65536-byte formal text limit)` /
  `string literal exceeds 65536 bytes; split it`；`tok_cstr` 的 `cbuf` 改为按 token
  长度 `realloc` 的块（不再固定 160）。PP 行上限同批收到 65536。
- 名字写入：`Parser.cur_func` / `ns_decl` / `cur_record` 改为 pool 文本；
  `Expr.cur_func` 改为指向 Parser 槽的 `const char **`；函数名、局部变量名、
  结构体/字段名在解析处直接 `ct_intern_len`，不再先落 `char[160]`。
- import：`Parser.rels` 改指针行；`skip_import` 用 `TokView` 段表（倍增）+
  `ct_text_*` 动态拼路径/别名，段数与单段长度都只受 `TEXT_LIMIT` 约束。
- 导出类型：`Symbols.tbare/tfull/tbambig` 改按需指针行，新增
  `MAX_EXPORTED_TYPES`（初值 128）/`MAX_EXPORTED_TYPES_MAX`（65536）。
- 限定名：`Expr.qseg` 持久段表按需增长，删除 `nseg >= 8`；`ns_decl_text`
  返回 pool 文本，命名空间 `Symbols.ns` 改 pool 文本，218 字节命名空间可用。
- `offsetof` 字段名直接 intern，诊断用动态消息。
- 单测：`test/ast/c2o_limits.sh` 9 项（2000 字节标识符/字面量/别名/字段、
  20 段 import、24 段限定调用、218 字节命名空间、200 个导出类型、超上限显式报错）。

**证据**：baseline `32898164` 上 `test/ast/c2o_limits.sh` 红（旧上限错误）；
实现后 9/9。`test/ast/p86_tokens.sh` 22/22（2000 字节正例 + 65537 字节负例）；
`p86_errors` 342 条诊断（3 条旧上限负例改为 >65536 负例）；`intern_pool` 11/11；
`check-seed` 两轮逐字节；`check-ast` 全量见交付报告。

**剩余（C2p）**：见 §5.6；C2p-1 已把 `qpath`/`cname` 按需化，C2p-2 已把
诊断文本按需化，C2p-3 已把类型拼写/实例名的 160 总闸解除（`parse_type`、
`expr_type`/`expr_ctype`、实例编码与类型表），C2p-4 已把跨解析调用存活的
持久类型行改指针行（trait 方法参数、闭包参数、`map binding`、ADT 名称、
`ret_type`、类型别名展开），`Expr/Stmt`/发射器其余一次性 scratch 仍在后续
批次。

## 5.6 C2p 合批（进行中）

C2p 按 4–6 个单元一批迁移剩余的 160/159/128 scratch；每批重生成一次 seed，
并以 `test/ast/c2p_limits.sh` 的对应段落做红→绿。未完成批次登记在文末。

**C2p-1 限定路径（已落）**：`parse_qual_path` 的 `name`/`cname`/`qpath`
三个输出改 pool 文本（内部用 `ct_text_*` 增长），`Parser.parse_func` 的
`gns` 改 pool 文本，`find_qualified_global` 返回 pool 指针，新增
`resolve_type_text`。>160 字节的限定变量/调用可用；无命名空间导入单元的
裸名回退（`plain::twice`）照旧。证据：`c2p_limits.sh` 3/3，baseline
`772d7611` 为 1/3。

**C2p-2 诊断文本（已落）**：`ParseSupport`/`Symbols`/`TypeCheck`/`Memory`
的 `errmsg[160]` 改 pool 文本，`Parser.emsg` 改 run-scoped，`Diag.Warn` 的
`var`/`tname`/`stype`/`msg` 改 pool 文本。150 字节 struct 名的 trait 诊断、
300 字节 callee 的 arity 警告不再截断。证据：`c2p_limits.sh` 5/5，baseline
`772d7611` 为 1/5。

**C2p-3 类型拼写/实例名（已落）**：`parse_type`/`parse_inst_type` 新增
pool-text 入口（`parse_type_text`/`parse_inst_type_text`），内部
`rname`/`qn`/`iface`/`enc`/`canon`/`last_bare_tag`/`inst_canon` 改 pool 文本；
`type_append` 的输出上限只剩 `TEXT_LIMIT`。`ExprTypeParse`/`ExprInstantiate`/
`Symbols` 的实例名拼接改 `ct_inst_encode_text`/`ct_type_canon_text`/
`ct_generic_subst_text`，实例参数行按需 `ct_row_set`；`Fn.ptype`/`pdim`、
`GenericInst.targ`/`cname` 与 `Symbols.types`/`type_target` 改指针行。
`expr_type`/`expr_ctype` 新增 pool-text 入口并在 `parse_postfix` 使用。
2000 字节 struct 名的声明/字段/参数/返回/方法接收者/调用与
`Holder<struct 2000>`、2000 字节模板名实例、trait 接收者/vptr 初始化/接口
装箱均可用。证据：`c2p_limits.sh` 9/9，baseline `f2233e7a` 为 5/9。

**C2p-4 持久类型文本（已落）**：六个单元，全部是跨解析调用存活的类型/名字行。
`MethodSig.ptype` 改指针行（trait 方法参数；实例替换走
`ct_generic_subst_text`）；`Closure.ptype`/`pname` 改 16 槽指针行（未填槽为
`""`，`closure_match` 会读到这里）；`MapBuild.parse_binding` 的 `src`/`dst`
改 `parse_type_text`，`host_type`/`bind_dst` 直接保存 pool 文本，发射器
`map binding` 的 pair 也直接读 pool（不再先落 `char[160]`）；`AdtField` 的
`name`/`type`、`AdtVariant` 的 `name`/`cname`、`Adt` 的 `name`/`full` 改 pool
文本，ADT 构造器前瞻去掉 160 截断、match arm 的变体名改 pool；
`Symbols.ret_type` 改 pool 文本（impl/普通函数的返回类型与 return 语句检查）；
`expand_type_alias`/`expand_type_text` 改 pool 文本输出，内部 `id`/`eb` 160
scratch 与输出上限一并删除；`parse_type` 的 `(*)(...)` 声明符 scratch
（`pt`/`plist`/`fdims`）改 pool 文本，函数指针形参可为 2000 字节类型。
证据：`c2p_limits.sh` 16/16，baseline `af193df6` 为 9/16；发射 C 67577 ->
67620 行（仅 .c），切片清单仍为 76。

**C2p-5 调用方缓冲 / 持久名字 / 比较键（已落）**：`expr_type`/`expr_ctype`
的 38 处调用点（`Expr` 17、`Stmt` 7、`Emitter` 4、`StmtMatch` 3、`TypeCheck`
2、`StmtLoop` 2、`ExprTypes`/`ExprNewObject`/`ExprCallCheck` 各 1）全部改
pool 文本入口（`expr_type_text`/`expr_ctype_text`），`ParseSupport` 内部的
3 处 `self->ty->expr_type` 同批收掉；`Emitter.sb_expr_type` 改为返回 pool
文本，`emit_gsub_type` 新增 pool 形式，`write_abi_header` 的 `fwd[64][160]`
改指针行。持久行迁池：`Closure.owner/ret/cap_name/cap_type`、
`Symbols.trait_default/tachain`（`tachain` 改指针行）、`ExprCore` 的
`fnptr_name`/`fnptr_dims`/`decl_prefix`/`in_generic_bound`/`iter`、ADT 标签
（`parse_enum_def.name` 与构造器/match 的 `rn`）；`CT_ADT` 的 `ct_adt_from_type`
也改 pool 解析。比较键 `type_key`/`bind_conv_key`/`map_bind_key` 新增 pool
形式并迁移全部调用点，`method_trait` 新增 pool 形式：两个只在前 159 字节
相同的长类型不再同键（旧行为报 "ambiguous map binding"）。
证据：`c2p_limits.sh` 22/22，baseline `86ae58db` 为 16/22；发射 C 67620 ->
68180 行（仅 .c），`Emitter.h.ct` 10215 -> 10315 行，切片清单仍为 76。
S1a-0 C2p-6（map type host / 泛型实参 / match / foreach / `_Atomic` /
`_Alignas` 的 160 行）：`c2p_limits.sh` 28/28，baseline `cef14798` 为
22/28；发射 C 68188 -> 68338 行（仅 .c），`Emitter.h.ct` 10315 -> 10318
行，切片清单仍为 76。

C2p-6 后剩余（`grep -c '\[MAX_TEXT\]'`）：`frontend/parse` 284 处
（`Expr.h.ct` 63、`Parser.h.ct` 44、`Stmt.h.ct` 32、`ExprTypes.h.ct` 32、
`ExprStaticType.h.ct` 22、`MapBuild.h.ct` 15、`ExprInstantiate.h.ct` 14 …）、
`backend/emit` 93 处（`Emitter.h.ct` 83、`EmitterText.h.ct` 3、
`Init.h.ct` 2 …）。下一批按单元簇（Expr / Parser / Stmt / Emit）继续，
每批 4–6 单元、生成物逐字节。

**剩余（按文件，`grep -c '\[MAX_TEXT\]'`）**：`frontend/parse` 390 处
（`Expr.h.ct` 94、`Parser.h.ct` 53、`Stmt.h.ct` 42、`ExprTypes.h.ct` 33、
`MapBuild.h.ct` 24、`ExprStaticType.h.ct` 23、`ExprBinding.h.ct` 16、
`ExprInstantiate.h.ct` 14 …）、`backend/emit` 114 处（`Emitter.h.ct` 101、
`EmitterText.h.ct` 3、`Init.h.ct` 2、`EmitInit.h.ct` 2、`EmitHoist.h.ct` 2、
`EmitterMapText.h.ct` 1）、`tool/pkg` 55 处、`frontend/type` 29 处、
`frontend/sym` 16 处、`frontend/module` 20 处、`backend/mem` 7 处。另有
8 处 `[128]` 计数行（`Emitter` 的路径/字段数组等），它们是行数容量而非文本
scratch。下一批优先级：`Emitter.gtarg`（仍是 `ct_rows_reserve` 的
`MAX_TEXT` 行，泛型实例的 2000 字节类型实参在发射端仍会被截；`Emitter`
`tbuf/rbuf/ibuf` 已改 pool，但 `gen` 的 2000 字节泛型函数实参仍红）、
`Closure` 之外的 `MapBuild.parse` 局部（`inst/icn/prefix/vt/host_type`
仍 160）、`ExprInstantiate` 的实例行与 `ExprStaticType`/`Stmt` 中剩余的
一次性 `char[MAX_TEXT]` scratch，以及 `foreach` 迭代变量的 2000 字节声明
路径（`iter` 已迁池，但 `declare_var` 前仍有一处 160 行截断）。

**剩余（按文件，`grep -c '\[MAX_TEXT\]'`）**：`frontend/parse` 390 处
（`Expr.h.ct` 94、`Parser.h.ct` 53、`Stmt.h.ct` 42、`ExprTypes.h.ct` 33、
`MapBuild.h.ct` 24、`ExprStaticType.h.ct` 23、`ExprBinding.h.ct` 16、
`ExprInstantiate.h.ct` 14 …）、`backend/emit` 114 处（`Emitter.h.ct` 101、
`EmitterText.h.ct` 3、`Init.h.ct` 2、`EmitInit.h.ct` 2、`EmitHoist.h.ct` 2、
`EmitterMapText.h.ct` 1）、`tool/pkg` 55 处、`frontend/type` 29 处、
`frontend/sym` 16 处、`frontend/module` 20 处、`backend/mem` 7 处。另有
8 处 `[128]` 计数行（`Emitter` 的路径/字段数组等），它们是行数容量而非文本
scratch。下一批优先级：`expr_type`/`expr_ctype` 的调用方缓冲（`parse` 与
`emit` 各按 4–6 单元一批；当前直接传栈缓冲的调用点是 38 处：`Expr.h.ct` 17、
`Stmt.h.ct` 7、`Emitter.h.ct` 4、`StmtMatch.h.ct` 3、`TypeCheck.h.ct` 2、
`StmtLoop.h.ct` 2、`ExprTypes.h.ct`/`ExprNewObject.h.ct`/`ExprCallCheck.h.ct`
各 1），随后是 `Closure.owner`/`ret`/`cap_*`、`Symbols.trait_default`/
`tachain`、`ExprCore` 的 `fnptr_*`/`decl_prefix`/`in_generic_bound`/`iter`、
`MapBuild` 的 `for type` host 路径与 `Emitter.h.ct` 的局部
`tbuf`/`rbuf`/`ibuf` 及 `EmitterText`/`EmitHoist`/`EmitInit`/`Init` 的一次性
scratch。

**S1a-0 C2p-8（发射器读取行与剩余 emit 单元，已落）**：`backend/emit` 的
reader 行按 4 个单元一批收掉。

- `Emitter.h.ct`：`sb_norm`/`adt_base_type`/`sb_life_prefix`/`sb_is_tparam`
  改为指针视图或 pool 文本（新增 `base_type_text` / `adt_base_type_text` /
  `sb_life_prefix_text`）；`sb_owning_struct_type` 走 `concrete_struct_text`；
  `sb_field_key` 直接返回两段 pool 文本；`Box_type_owns` /
  `Box_emit_release_at` / `Box_emit_copy_at` 的 base 改 pool 文本、嵌套字段
  表达式改 `ct_text_*`；`adt_emit_variant_life` 的 `self->u.<v>.<f>` 改
  `ct_text_*`；`impl_emit_method`/`impl_emit_one` 的 `iname`/`cname`/`mret`/
  `cuse` 改 pool 文本（`impl_use_concrete` 内部改用 `ct_inst_encode_text`，
  输出 cap 由调用方给 `TEXT_LIMIT`）；`inst_emit_one` 与 `em_decl_struct` 的
  vptr 小写名改 run-scoped 精确块；`elem_has_life`/`elem_plain_owner`/
  `inst_emit_elem_method_protos`/`inst_emit_elem_helpers` 的 base/ename 改视图；
  `map_param_type` 改 `map_param_type_text`（两侧本来就是 pool 文本），
  `map_clean_type`/`map_recipe_callee` 改 pool 文本形式；`map_subst_arg` 的
  token 用 `ct_intern_len`、后缀按源区间打印、`emit_recipe_impl` 的参数区间
  改 run-scoped 块；`em_expr_try` 的 operand/Result 列改 pool 文本或
  `TEXT_LIMIT` scratch；`em_expr_newobj` 的 `ctype`、`emit_outconv` 的 `ret`、
  `emit_value_for` 的 `t`、`write_map` 的 callee、ABI header 的大写名改
  pool/scratch；`em_unit_init`/局部数组/堆对象的 `cnt`/`recv` 改视图或
  `ct_internf`。
- `EmitHoist`：`bt`/`hbuf` 改 `TEXT_LIMIT` scratch（`hoist_ctype` 的 cap
  参数本来就按传入值生效）。
- `EmitterText`：`elem_ret_ctype` 的 `cur`/`nxt`/`res` 改
  `ct_generic_subst_text` + `ct_inst_resolve(TEXT_LIMIT)`。
- `Init`：两处 vptr 小写名改 run-scoped 精确块（`Init` 的 `[MAX_TEXT]` 清零）。
- `EmitterMapText`：删除已无调用方的 `map_bind_key`（其 160 行随之退场）。

保留的固定短行（逐类记录）：`fail_unknown_statement` 的 `msg[160]`（只有
kind 数字）、`em_expr_newobj` 的 `tmp[160]`（`__ct_new<N>`）、`em_expr_try`
的 `qt[160]`（`__ct_q<N>`）、`EmitInit.sb_rewrite_init` 的 `expr[160]`
（只在 `e0 - fs < MAX_TEXT` 时走，长区间已走 run-scoped 块）。它们不承载
用户文本，上限只由整数位数决定。

证据：`test/ast/c2p_limits.sh` 39/39（baseline `06e1b8c5` 34/39：长 trait 的
vptr 名、map 主机类型的 `sizeof`、长 ADT 变体的生命周期成员、长 Drop 字段类型、
长命名空间闭包五处被 160 截断）；`check-ast` 1666→（本次）全量、`p88/metrics`
复算 68377、`test25_unit` 的 map 文本 helper 改 pool 形式。源码
`[MAX_TEXT]`：`backend/emit` 92 → 5（`Emitter.h.ct` 83 → 4 行，其中 1 行是
注释、3 行是上述短 scratch；`EmitInit.h.ct` 1 行短 scratch），全树
460 → 371。

**C2p-8 后剩余（`grep -c '\[MAX_TEXT\]'`，行数）**：全树 371 处。
`frontend/parse` 271（`Expr` 58、`Parser` 39、`Stmt` 32、`ExprTypes` 32、
`ExprStaticType` 22、`MapBuild` 15、`ExprInstantiate` 14、`ExprOptional` 9、
`StmtLoop` 8、`ExprCallCheck` 7、`ExprBinding` 6、`ExprClosure` 5、
`ExprTypeText` 4、`StmtRangeText`/`ExprSubscript`/`ExprAdtCtor` 各 3、
`StmtMatch`/`ParseSupport`/`ExprPure` 各 2、`StmtRangeScan`/`StmtControl`/
`ExprTypeParse`/`ExprTry`/`ExprTraitInst` 各 1）；`tool/pkg` 39；
`frontend/type` 21；`frontend/module` 20；`frontend/sym` 8；
`backend/emit` 5；`backend/mem` 7。下一批按卡片的第 2 项继续：
`Expr`/`Parser`/`Stmt`/`ExprTypes`/`ExprStaticType` 中仍会截断用户文本的
一次性 `msg`/类型 scratch（`expr_type` 系列调用点已在前批转 pool 文本）。

**S1a-0 C2p-10（表达式/类型/语句/解析器四层，已落）**：本批把 `frontend/parse`
剩余的 227 行 `[MAX_TEXT]` 清到 1 行（保留的确定短 scratch，见下），分五个
红/绿对提交、每对 5 个单元左右：

- **A 静态类型链**（红 20f2c1d3 / 绿 3b94f3b6）：`ExprStaticType` 的
  `static_ctype_text` / `ctype_expand_text` / `fnptr_ret_text` /
  `peel_ptr_text` 家族与 13 个 `ctype_*` slice；`ExprTry` 的
  `result_tag_text` / `result_cols_text`；`ExprInstantiate` 的
  `inst_subst_type_text`；`ExprOptional` 的 `?.` / `?[` 接收者、`ExprPure`、
  `ExprSubscript` 的标签，以及 `Expr` 的 9 个 `static_ctype` 调用点。
- **B 类型检查链**（红 517d4ee1 / 绿 d84b2704）：`chk_type_text` 家族
  （`chk_assignable` / `chk_brace_init` / `chk_callptr_args` /
  `chk_mcall_args` / `closure_match` / `lit_coerce`）、`plist_next_text` /
  `subst_tparam_text`、`bplus_lit_type_text`、`var_type_text`，以及
  `ExprClosure` / `ExprAdtCtor` / `ExprTraitInst` / `ExprInstantiate`。
- **C 语句层**（红 9c9d1dc7 / 绿 d06f1089）：`Stmt` 的切片视图
  `{ptr,len}`、`map_decode_str_text`、`_Alignas` 捕获、限定类型前瞻、
  yield/return/赋值/初始化器类型行、`map_brace_target_text`；`StmtMatch` /
  `ParseSupport` / `StmtControl`。
- **D 表达式层**（红 9145c38a / 绿 1a24e846）：`Expr` 的 `$` 目标、
  `_Generic` 选择、绑定转换、静态调用实例/方法名、原子内建类型、C 边界
  诊断；`inst_method_ret_text`（TypeCheck）；`parse_inst_type_text` 的
  输出块清零。
- **E 解析器层**（红 cb7a9120 / 绿见本批最后一个 feat 提交）：`Parser` 的
  `borrow` struct 名、`_Alignas`、泛型边界、成员/结构体/enum/ADT/trait
  注册诊断、impl/trait 实例名、drop 字段诊断。

**保留的确定短 scratch（逐类记录）**：`ExprTypeParse.type_resolve_name` 的
`buf[MAX_TEXT]` 只用于 `strlen(name) < MAX_TEXT` 的名字；长名本来就走
`resolve_type_text`，该行不截断任何用户文本，且歧义导出的诊断依赖 buffer
形式。这是本批唯一保留的 `[MAX_TEXT]` 行。

**证据**：`test/ast/c2p_limits.sh` 54/54（五个红证分别覆盖 42/46、46/47、
47/49、49/52、52/54 的失败面）；71 语料生成 C 与每批上一提交逐字节相同
（`ct-seed*` 对比，71/71）；`check-ast` 1665 passed / 0 failed / 7 skipped；
`check-goldens-ast` 25/25；`check-warnings` 559/559；`check-seed` 两轮
逐字节（60 .c + 59 .h）；`check-docs`、`g1`、`g8` 绿。发射 C 68571 ->
68903 行（仅 .c），切片清单仍为 76，判别式仍各读 1 次。

**C2p-10 后剩余（`grep -c '\[MAX_TEXT\]'`，行数）**：全树 101 处。
`frontend/parse` 1（上述 keeper）；`tool/pkg` 39、`frontend/type` 21、
`frontend/module` 20、`frontend/sym` 8、`backend/mem` 7、`backend/emit` 5。
下一批（C2p-11）按单元簇继续：`tool/pkg` 的命令/缓存行、`frontend/type` 与
`frontend/module` 的路径/键行、`backend/mem` 的池行。

## 6 关联

- [SH-109](../../issues/selfhost/sh109-max-funcs-capacity.md)（已落地的动态容量样板）
- [SH-94](../../issues/selfhost/sh94-giant-units-duplicate-constants.md)（方法组拆分；S1a-1）
- [`v1-PH-2`](../phases/v1-PH-2/card.md)（S1a-0 → S1a-1 → S1b）
- [language-spec §8](../language-spec.md)（L0 上限表，C4 退役）
- [stable-subset](../stable-subset.md)（ADT 形态与泛型元数，C3 与实现同批改写）

**S1a-0 C2p-7（成员/方法/标签/match 绑定名，已落）**：`Expr.parse_postfix`
的成员名（`.` / `->` / `?.`）由 `tok_copy` 的 160 行改为 pool 文本，2000 字节
字段名的声明与每次访问不再是“声明整名、访问截名”；`Parser.parse_impl`
（trait impl / inherent impl / 泛型 impl 三处）与 `parse_enum_def` 的成员名
改 pool 文本，2000 字节 trait 方法名能匹配 trait 行并贯穿 vtable 原型、定义
与调用，枚举成员不再经 160 行落名；`StmtSwitch` 的 label / `goto` 名改 pool
文本（`[MAX_TEXT]` 清零），2000 字节标签的 goto 与定义逐字一致；`StmtMatch`
的 arm 绑定名由 `calloc(nbind, MAX_TEXT)` 改 `ct_text_rows_reserve` 指针行，
2000 字节绑定名可声明并使用。
证据：`test/ast/c2p_limits.sh` 34/34（baseline `48b01c54` 为 29/34：字段访问、
字段指定初始化、trait 方法、match 绑定、标签五处被 160 截断）；`check-seed`
两轮逐字节（60 .c + 59 .h）；源码 `[MAX_TEXT]`：`frontend/parse` 284 → 271，
`backend/emit` 93 → 92，`frontend/type` 22 → 21，全树 475 → 460。未改语义、
版本号与 issue。

**C2p-7 后剩余（`grep -c '\[MAX_TEXT\]'`）**：`frontend/parse` 271 处
（`Expr.h.ct` 58、`Parser.h.ct` 39、`Stmt.h.ct` 32、`ExprTypes.h.ct` 32、
`ExprStaticType.h.ct` 22、`MapBuild.h.ct` 15、`ExprInstantiate.h.ct` 14 …）、
`backend/emit` 92 处（`Emitter.h.ct` 83、`EmitInit.h.ct` 1 为短项保留行 …）、
`tool/pkg` 39、`frontend/type` 21、`frontend/module` 20、`frontend/sym` 10、
`backend/mem` 7，全树 460 处。下一批
仍按单元簇（Emitter / Expr / Parser / Stmt）推进；`Expr` 的 `rty`/`ret`/
`msg` 一次性 scratch、`ExprTypes` 的 `fbase`/`actual`、`Emitter` 的 `pbuf`/
`base`/`msg` 是主要剩余。

**S1a-0 C2p-9（表达式/语句/解析器的 recipe 与诊断 scratch，已落）**：本批 7 个
单元、44 行 `char[MAX_TEXT]` 退场，全部是“用户文本被 160 行截断”或
“一次性格式化 scratch”两类，没有改语义。

- `ExprBinding`（6）：新增 `bind_conv_ibase_text` / `bind_conv_inherent_text` /
  `bind_conv_maps_text`。接收者类型、内置 `as` 的返回类型、映射 trait 的返回
  类型都以 pool 文本流转；旧的 `char*+cap` 形式保留为薄包装。2000 字节 struct
  的内置 `as` 不再报 “no conversion from”。
- `MapBuild`（15）：recipe 捕获改 `mapb_capture`（run-scoped，`TEXT_LIMIT` 为
  唯一上限），`MapBind.params` 由 `char**`（每行 160）改 `const char**` pool
  文本行，调用 `var_cname_text` 拼接 wrapper 体；token / `prev` / `sizeof(...)`
  参数名 / 诊断都改 pool 或 `ct_scratch_fmt`。2000 字节 recipe 被调函数名、
  2000 字节绑定参数名可用。
- `StmtLoop`（8）：range bound、foreach / loop / range initializer 的诊断改
  `ct_scratch_fmt`；`range_element_bad_text`、`elemtype`/`iname` 走 pool 文本。
  诊断里的 2000 字节变量名/元素类型不再截断。
- `StmtRangeText`（3）：`loop_count_class` 改为按词 span 比较（只认固定 C
  关键字，长别名不再需要 160 行），`range_element_spelling_text` /
  `range_vec_target_text` 新增 pool 形式，`vbrace_type_same` 原地跳过空白比较。
- `StmtRangeScan`（1）：`range_spelling_text` 直接 `ct_intern_len` 源区间，
  `range_bound_value_text` 返回 pool 文本；数字/标识符/溢出诊断都保留整词。
- `ExprCallCheck`（7）：`argtype_mismatch_text` 以 pool 文本返回期望/实际类型，
  `arity_check` / `argtype_check(_static)` 的消息改 `ct_scratch_fmt`。
- `ExprTypeText`（4）：新增 `tnorm_text` / `tbase_text` / `arg_class_text`；
  `arg_class` 保留原签名但内部走文本形式，`subst_tparam` 与 `tnumeric` 不再
  落 160 行。

配套的小改动：`Symbols` 新增 `var_cname_text`（`Var.cname` 本来就是 pool
文本），`MapTable.MapBind.params` 的类型改为 `const char **`。

证据：`test/ast/c2p_limits.sh` 42/42（baseline `4b8345dd` 为 39/42：2000 字节
map recipe 被拒、2000 字节 `as` 接收者报 “no conversion from”、foreach 诊断
把 2000 字节变量名截成 159 字节）；`check-seed` 两轮逐字节（60 .c + 59 .h）。
源码 `[MAX_TEXT]`（行数）：`frontend/parse` 271 → 227，全树 371 → 327。
未改语义、版本号与 issue。

**C2p-9 后剩余（`grep -c '\[MAX_TEXT\]'`，行数）**：`frontend/parse` 227 处
（`Expr.h.ct` 58、`Parser.h.ct` 39、`Stmt.h.ct` 32、`ExprTypes.h.ct` 32、
`ExprStaticType.h.ct` 22、`ExprInstantiate.h.ct` 14、`ExprOptional.h.ct` 9、
`ExprClosure.h.ct` 5、`ExprSubscript.h.ct` 3、`ExprAdtCtor.h.ct` 3、
`StmtMatch.h.ct` 2、`ParseSupport.h.ct` 2、`ExprPure.h.ct` 2、
`StmtControl.h.ct` / `ExprTypeParse.h.ct` / `ExprTry.h.ct` /
`ExprTraitInst.h.ct` 各 1）、`backend/emit` 5、`tool/pkg` 39、
`frontend/type` 21、`frontend/module` 20、`frontend/sym` 8、`backend/mem` 7，
全树 327 处。下一批仍按单元簇推进：`Expr` 的 58 行一次性 scratch 与类型行、
`Parser` 的 39 行（含 15 处诊断）、`Stmt` 的 32 行、`ExprTypes` /
`ExprStaticType` 的 `static_ctype` 链（需 `static_ctype_text` 家族）。
