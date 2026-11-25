# 容量上限清单与放开计划（L0 遗留）

> 状态：**盘点完成；S1a-0 实施中**（2026-11-25：`MAX_NODES`/`MAX_WARNINGS` 与 A 类表/实例/形参/调用/标签/布局/hoist/into 等已动态；`MAX_MAPS` 与 B/C/D 类待做）。
> 目标：把 L0 阶段留下的“固定上限 + 越界硬报错”全部改为按需容量；只保留 OOM 安全阀与真正的语言语义上限。
> 基线：`v1.1.0`（`54b60225` 之后的规划提交）。

## 0 结论

- `ct-ast` 共 **49** 个 `Limits.h.ct` 常量 + **8** 个单元内本地常量 + **约 14** 处硬编码数字上限；
- 目前**只有 `MAX_FUNCS` 已动态化**（SH-109：初始 512、倍增、安全阀 65536）；
- 其余全部是“固定上限 + 越界报错”；其中 `MAX_METHODS=64` 已挡住新增方法，`MAX_TEXT=160` 在 31 个单元出现 **1494** 次、定长数组 **791** 处，是最大的一块；
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
| `MAX_METHODS` | 64 | 27 | A | **已动态**：`Trait.m` 堆块 + `MAX_METHODS_MAX=65536`；trait 实例行深拷贝方法块；parser 默认体环检查矩阵按实扩 |
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
| `MAX_MAPS` | 64 | 5 | A | 动态 |
| `MAX_METH_ANN` | 256 | 4 | A | **已动态**：`MethAnn` 行表倍增到 `MAX_METH_ANN_MAX=65536`；每行注记块也随 `MAX_PARAMS` 增长 |
| `MAX_PARAMS` | 16 | 21 | A | **已动态**：`Fn`/`MethodSig` 形参三/两组并行块 + `MethAnn` 注记块倍增到 `MAX_PARAMS_MAX=65536`；实例行深拷贝；map 参数仍 16（剩余） |
| `MAX_TYPE_ALIASES` | 64 | 6 | A | **已动态**：本地 `taliases` 倍增到 `MAX_TYPE_ALIASES_MAX=65536` |
| `MAX_GLOBAL_TYPE_ALIASES` | 256 | 4 | A | **已动态**：全局 `gtaliases` 倍增到 `MAX_GLOBAL_TYPE_ALIASES_MAX=65536` |
| `MAX_IMPORTS` | 32 | 10 | A | 动态 |
| `MAX_INCDIRS` | 16 | 4 | A | 动态 |
| `MAX_UNITS` | 64 | 24 | A | 动态 |
| `MAX_PKG_DEPS` | 16 | 42 | A | 动态 |
| `MAX_DIGEST_FILES` | 4096 | 4 | A | 动态 |
| `MAX_INIT_ITEM` | 4096 | 3 | A | 动态 |
| `MAX_RAW_INIT` | 4096 | 9 | A | 动态 |
| `MAX_LAYOUT_ADTS` | 64 | 5 | A | **已动态**：`g_adt_layout_state` 堆块倍增到 `MAX_LAYOUT_ADTS_MAX=65536`（受 C 类 MAX_ADTS=64 遮蔽） |
| `MAX_LAYOUT_INSTS` | 128 | 11 | A | **已动态**：`g_inst_layout_state`/`g_shell_emit_state` 倍增到 `MAX_LAYOUT_INSTS_MAX=65536`；`EmitterQuery` 的全表扫描去掉固定界 |
| `MAX_WARNINGS` | 32 | 15 | A | **已落**：`warns` 倍增到 65536；`--max-warnings` 另议 |
| `MAX_ADTS` | 64 | 5 | C | 放开到 `CAP_LIMIT`；spec §8 / stable-subset 同步 |
| `MAX_ADT_VARIANTS` | 96 | 3 | C | 放开到 `CAP_LIMIT`；spec §8 / stable-subset 同步 |
| `MAX_ADT_FIELDS` | 8 | 3 | C | 放开到 `CAP_LIMIT`；spec §8 / stable-subset 同步 |
| `MAX_STRUCT_TPARAMS` | 2 | 14 | C | 放开到 `CAP_LIMIT`；spec §8 “类型参数最多两个”同步改写 |
| `MAX_ALIAS_CHAIN` | 32 | 7 | D | 递归链保护；保留 |
| `MAX_LAYOUT_DEPTH` | 32 | 8 | D | 递归深度保护；保留 |
| `MAX_PKG_DEPTH` | 8 | 4 | D | 依赖深度保护；保留 |
| `MAX_FUNCS_MAX` | 65536 | 10 | D | OOM 安全阀；保留 |
| `MAX_NODES` | 262144 | 7 | D | **已落**：arena 倍增到 `NODE_LIMIT=16777216`（新槽清零） |
| `MAX_TEXT` | 160 | 1494 | B | 动态文本；当前 791 处定长数组，最大切片 |
| `MAX_PATH` | 1024 | 74 | B | 路径按需分配；OS 上限单独报错 |
| `MAX_PKG_PATH` | 512 | 85 | B | 同上（包内路径） |
| `MAX_PKG_CMD` | 2048 | 35 | B | 命令缓冲动态化 |
| `MAX_KEY` | 768 | 8 | B | 缓存键动态化 |
| `MAX_INIT_TEXT` | 16384 | 8 | B | 初始化文本动态化 |
| `MAX_RAW_BLOCK` | 32768 | 3 | B | raw 块动态化 |

## 3 单元内本地常量（不在 Limits）

| 常量 | 值 | 位置 | 类 | 动作 |
| --- | --- | --- | --- | --- |
| `MAX_FLAGS` | 1024 | `Module.h.ct` / `Driver.h.ct` | B | 动态 |
| `MAX_CMD` | 8192 | `Module.h.ct` | B | 动态 |
| `MAX_IH` | 5120 | `Module.h.ct`（`MAX_IMPORTS * MAX_TEXT`） | B | 动态，随 A/B 消除 |
| `MAX_ERRORS` | 20 | `Diag.h.ct` | D | 错误恢复上限；保留并明确文案 |
| `MAX_LOCK` | 4096 | `Pkg.h.ct`（`MAX_PKG_PATH * 8`） | B | 动态 |
| `MAX_PKG_LINE` | 1024 | `Pkg.h.ct` | B | 动态 |
| `MAX_PKG_GITERR` | 8 | `Pkg.h.ct` | D | 展示行数；保留 |
| `MAX_INDEX_ROWS` | 1024 | `Pkg.h.ct` | A | 动态 |

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
