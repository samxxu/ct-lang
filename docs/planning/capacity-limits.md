# 容量上限清单与放开计划（L0 遗留）

> 状态：**盘点完成；S1a-0 实施中**（2026-11-25：`MAX_NODES`/`MAX_WARNINGS` 与 A 类表/实例/形参/调用/标签/布局/hoist/into 等已动态；2026-11-25 再落 module 表（UNITS/IMPORTS/INCDIRS）、pkg 表（DIGEST_FILES/INDEX_ROWS 已动态）与初始化文本（RAW_INIT/INIT_ITEM）与 map 表；`MAX_MAPS`（含 `MapTable.b` 与 `MapBind` 参数并行表）已动态；`MAX_PKG_DEPS`（含 `ct.lock` 行块与构建期锁根）已动态；**C 类已全部动态：ADT 计数（`MAX_ADTS` / `MAX_ADT_VARIANTS` / `MAX_ADT_FIELDS`）与泛型元数（`MAX_STRUCT_TPARAMS`）**；**C2 文本/路径开始：raw 块已收到 `TEXT_LIMIT=65536`（C2a），缓存键（C2b）、初始化文本（C2c）、pkg 锁文本（C2d）、pkg 命令/路径文本（C2e）、cc 命令行（C2f）、cflags/ldflags 累加器（C2g）、pkg 行读取（C2h）与包目录/树扫描路径（C2i）已按需增长**；B/D 类其余待做）。
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
| `MAX_PATH` | 1024 | 74 | B | 路径按需分配；OS 上限单独报错 |
| `MAX_PKG_PATH` | 512 | 85 | B | **部分动态（C2i）**：包目录与树扫描路径已按需——`pkg_pathf` 精确分配、`read_manifest` / `pkg_read_identity` / `pkg_read_meta` 的行与 `<dir>/ct.pkg`、`dir_digest` 的 `sha_collect` / `sha_sort`（指针行，每文件一条精确字符串）、`copy_tree`、`IndexRow.dir`、`ct index refresh` 的 list/out/tmp 路径、`split_spec` 的 path/range 均不再有 512 字节上限；`ct get <569 字节目录>` / `ct verify` / `ct index refresh` 正例。**剩余**：store / lock 行字段（`PkgRec.store`、`LockRow.ipath`、`LockParsedRow.*`）、`IndexRow.url`、`Pkg.index`、dep 行块与 `-I` roots/notes 的 512-stride 行（C2j） |
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
| `MAX_LOCK` | 4096 | `Pkg.h.ct`（`MAX_PKG_PATH * 8`） | B | **已动态（C2d）**：`struct Pkg.lock` 改堆块倍增到 `MAX_LOCK_MAX=65536`；`get` 追加、`pkg_lock_keep` scratch、`update`/`migrate` 读写与 `ct.pkg` 读取都按实际大小分配；41 行锁（4721 字节）可 get/verify/update/build |
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
| `Symbols.h.ct` | import 别名 24 | A | 动态 |
| `Symbols.h.ct` | 导出类型名 128 | A | 动态 |
| `Symbols.h.ct` / `Expr.h.ct` | 实例名 159 字符 | B | 动态文本 |
| `Lexer.h.ct` | 标识符 159 / 字符串字面量 158 字节 | B | 动态文本 |

## 5 实施顺序（`v1-PH-2` S1a-0）

| 切片 | 内容 | 判据 |
| --- | --- | --- |
| C1 计数 | 33 个 A 类（含本地 `MAX_INDEX_ROWS` 与第 4 节 A 类字面量）：`realloc` 倍增，OOM 阀与 `MAX_FUNCS` 同形 | 旧上限的越界负例改为“可增长并通过”；新增扩容用例；生成物逐字节 |
| C2 文本/路径 | 7 个 B 类 + `MAX_FLAGS`/`MAX_CMD`/`MAX_LOCK` 等；`char[MAX_TEXT]` 逐步改为按需缓冲 | 长名/长路径用例；无静默截断；生成物逐字节 |
| C3 语言上限 | `MAX_ADTS` / `MAX_ADT_VARIANTS` / `MAX_ADT_FIELDS` / `MAX_STRUCT_TPARAMS` 一并放到形式上限；**同一提交改 spec §8 / stable-subset** | spec 与实现一致；“类型参数最多两个”退役；正负例 |
| C4 测试与文档 | TEST-9 的“too many”契约改为“增长成功”；spec §8 上限表退役；`Limits.h.ct` 只留 `CAP_LIMIT` / `TEXT_LIMIT` / `NODE_LIMIT` 与 D 类 | `check-all` 绿；seed 两轮逐字节 |

- C1 与 C2 各自独立提交、独立回滚；C2 涉及 31 个单元与 791 处数组，排在 C1 之后；
- C3 与 C1/C2 同属 S1a-0，但 spec / stable-subset 的改写必须与实现同批提交，不允许实现先行；
- 每个切片都要重生成 `bootstrap/ct-ast` 并过 gate 13（内置层/编译器自身布局变化）。

## 6 关联

- [SH-109](../../issues/selfhost/sh109-max-funcs-capacity.md)（已落地的动态容量样板）
- [SH-94](../../issues/selfhost/sh94-giant-units-duplicate-constants.md)（方法组拆分；S1a-1）
- [`v1-PH-2`](../phases/v1-PH-2/card.md)（S1a-0 → S1a-1 → S1b）
- [language-spec §8](../language-spec.md)（L0 上限表，C4 退役）
- [stable-subset](../stable-subset.md)（ADT 形态与泛型元数，C3 与实现同批改写）
