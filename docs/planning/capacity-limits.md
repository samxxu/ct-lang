# 容量上限：初始值 + 倍增 + 形式上限

> 中文
>
> **状态**：S1a-0 已收口（2026-11-26，C1–C4）。本文只描述当前策略，不再是逐常量清单；
> 常量的唯一权威是 [`Limits.h.ct`](../../selfhost/ct-ast/frontend/sym/Limits.h.ct)。
> 目标：不再有“固定语言上限 + 越界硬报错”；计数表按需增长，只保留 OOM 保护与深度 / 错误恢复保护。

## 0 结论

- **三类形式上限**：`CAP_LIMIT`（一张计数表最多 65536 行）、`TEXT_LIMIT`（单条文本 / 路径 / 命令最多
  65536 字节）、`NODE_LIMIT`（AST 节点池最多 16777216 个节点）。它们只作 OOM / 资源保护，
  **不是语言语义**：真实程序不应触到，触到只报资源错误，不静默截断。
- **计数表**从 `MAX_*` 初始值开始，满时 2 倍增长，到 `CAP_LIMIT` 才停；初始值只是第一次分配的
  大小，不是功能上限。
- **文本 / 路径 / 命令 / 键**按需分配，精确长度或 2 倍增长，到 `TEXT_LIMIT` 才停。
- **深度 / 错误恢复**保留固定值（见 §3）；这是容量表中唯一仍按固定值报错的类别。各特性语法自带的形状上限
  （如 range 初值 1024、闭包嵌套 16、每帧闭包绑定 64）不属于 S1a-0 的容量表，仍按各自小节 / 夹具描述。
- 旧契约“超过 `MAX_*` 就报 `too many …`”已退役（S1a-0 C4，TEST-9）；旧夹具改为“增长成功”，
  负例只保留形式上限与深度 / 错误恢复。

## 1 分类与处置

| 类 | 含义 | 当前处置 |
| --- | --- | --- |
| 计数表 | 函数、变量、类型、struct、trait、方法、参数、ADT、map、import、unit、label、call 等行表 | 初始值 + 倍增到 `CAP_LIMIT`；越界只剩 OOM |
| 文本 | 标识符、字面量、路径、命令、缓存键、锁行、初始化文本 | 按需分配，单条到 `TEXT_LIMIT`；不再静默截断 |
| 语义计数 | ADT / 变体 / 负载字段 / 泛型元数 | 同计数表：初始值 + 倍增到 `CAP_LIMIT`（C3） |
| 节点池 | AST arena | 初始 `MAX_NODES`，倍增到 `NODE_LIMIT`；OOM 报错 |
| 深度 / 错误恢复 | 别名链、布局、包依赖、块嵌套、闭包嵌套、错误数 | 保留固定值，见 §3 |

## 2 初始值

初始值写在 `Limits.h.ct`，每个用到它的单元按 `tools/limits_sync.py` 镜像。它们只是第一次 `malloc` /
`calloc` 的行数或字节数，**不是上限**；满后统一 2 倍增长到形式上限。典型初始值（不是完整清单）：

| 区域 | 初始值示例 |
| --- | --- |
| 函数 / 变量 / 类型 | `MAX_FUNCS` 512（整程序累计）、`MAX_VARS` 4096、`MAX_TYPES` 256、`MAX_SCOPE` 256 |
| struct / trait / 方法 | `MAX_STRUCTS` 128、`MAX_TRAITS` 64、`MAX_METHODS` 64、`MAX_FIELDS` 64 |
| 形参 / 调用 / 标签 | `MAX_PARAMS` 16、`MAX_ARG_POS` 32、`MAX_CALLS` 8192、`MAX_LABELS` 64 |
| 模块 / 包 | `MAX_UNITS` 64、`MAX_IMPORTS` 32、`MAX_INCDIRS` 16、`MAX_PKG_DEPS` 16 |
| ADT / 泛型 | `MAX_ADTS` 64、`MAX_ADT_VARIANTS` 96、`MAX_ADT_FIELDS` 8、`MAX_STRUCT_TPARAMS` 2 |
| 文本 | `MAX_TEXT` 160（仅 5 处确定短 scratch；用户文本按需到 `TEXT_LIMIT`） |
| 节点池 | `MAX_NODES` 262144 |

`MAX_FUNCS` 是整程序累计预算：`build` 模式共用一张符号表，`nfunc` 跨单元累加（builtin 层经
`nfunc_base` 扣除），增长后仍按 `CAP_LIMIT` 封顶。

## 3 保留的固定值（深度 / 错误恢复）

| 常量 | 值 | 含义 |
| --- | --- | --- |
| `MAX_ALIAS_CHAIN` | 32 | 类型别名展开链的递归保护 |
| `MAX_LAYOUT_DEPTH` | 32 | 布局递归深度保护 |
| `MAX_PKG_DEPTH` | 8 | 包依赖深度保护 |
| `MAX_ERRORS` | 20 | 错误恢复上限；达到后报 `too many errors, stopping` |
| 块嵌套 / 闭包嵌套 | 实现定值 | parser 递归下降的深度保护（如 `blocks are nested too deeply`） |

这些值不会增长；触到即报错，不属于“容量不够就放大”的类别。

## 4 实现约定

- **单一权威**：`selfhost/ct-ast/frontend/sym/Limits.h.ct` 是唯一选值处；其他 `.h.ct` 的
  `#define` 是镜像，由 `tools/limits_sync.py --check`（`selfhost/check-ast.sh` 调用）拒绝漂移，
  `--write` 只改镜像数值。同步集包括三个形式上限与全部 `MAX_*`。
- **不截断**：文本 / 路径 / 命令超限即显式报错；不再出现“截到 160 字节后继续编译”。
- **OOM 唯一失败面**：计数表增长失败只报 `out of memory`；不再有“too many <table>”的功能上限。
- **生成物**：容量策略变化只影响编译器自身 C；用户语料的生成 C 逐字节不变（S1a-0 各切片的判据）。

## 5 切片记录（S1a-0）

| 切片 | 内容 | 结果 |
| --- | --- | --- |
| C1 | 33 个计数表 + 本地常量 + A 类字面量：满时 `realloc` 倍增 | 旧上限负例改为“增长成功” |
| C2a–C2p | 文本 / 路径 / 命令 / 键 / 锁 / 行 / 初始化文本按需；`MAX_TEXT` 791 处定长数组清到 5 处短 scratch | 长名 / 长路径正例；`TEXT_LIMIT` 为唯一文本上限 |
| C3 | ADT / 变体 / 负载字段 / 泛型元数收到形式上限；spec / stable-subset 同批改写 | 不再有 64 / 96 / 8 / 2 语义上限 |
| C4 | TEST-9 契约改为“增长成功”；spec §7 / stable-subset / 本文退役上限表；`Limits.h.ct` 合并为 `CAP_LIMIT` / `TEXT_LIMIT` / `NODE_LIMIT` 与初值 / D 类 | `check-all`、seed 两轮、生成物逐字节 |

各切片的红 / 绿提交与证据见 `docs/history/phase-log.md`、`docs/phases/v1-PH-2/card.md` 与
`test/ast/cap_*.sh`。

## 6 关联

- [`Limits.h.ct`](../../selfhost/ct-ast/frontend/sym/Limits.h.ct)（唯一权威）
- [`tools/limits_sync.py`](../../tools/limits_sync.py)（镜像校验）
- [language-spec §7](../language-spec.md)（用户文档）
- [stable-subset](../stable-subset.md)（冻结面）
- [SH-109](../../issues/selfhost/sh109-max-funcs-capacity.md)（动态容量样板）
- [`v1-PH-2`](../phases/v1-PH-2/card.md)（S1a-0）
