# Phase 73 — 字段可见性与 ABI（LANG-9）

> **状态：完成**（2026-11-19 收口；`v0.72.0`；R1–R3 全绿）。
> **前置**：上一相收口；本卡在轮到时才开始实现。
> **布局说明**：phase-ID 迁移仍被 blocker 挡住，本卡暂用 legacy 路径
> `docs/history/design/phase73.md`，迁移时统一改名。

## 0 卡片字段（冻结）

| 项 | 值 |
| --- | --- |
| 编号 | v0-PH-73（legacy 文件 `phase73.md`） |
| 目标 | 字段可见性与 ABI（LANG-9） |
| 范围 | `pub` 决定 struct 字段是否进入公开头文件；ABI 冲突硬错 |
| 非目标 | 不改命名规则；不引入新的 ABI 版本 |
| 交付物 | 编译器改动、`test/ast/p73_*` 探针、文档 |
| 任务清单 | §3（R1–R3） |
| 退出判据 | E73-1…E73-3（§4） |
| version-minor | 72（PH-73，`d=1`） |
| 已知风险 | R73-1…R73-1（§5） |

## 1 需求与边界

字段可见性与 ABI（LANG-9）：`pub` 决定 struct 字段是否进入公开头文件；ABI 冲突硬错。不改命名规则；不引入新的 ABI 版本。

## 2 证据口径

每项任务 T-7：先 `test(...) 红`（含 `baseline: <sha>` 与原始输出），再实现。
合法语料零误报；`check-all` 11/11；golden 变化必须逐条说明。

## 3 任务清单（冻结）

| 任务 | 交付物 | verify | effort |
| --- | --- | --- | --- |
| R1 导出面 | 公开头只导出 `pub` 字段 | ``bash test/ast/p73_export.sh` → `OK p73/export`` | M |
| R2 ABI 硬错 | 同名 struct 的 ABI 不一致硬错 | ``bash test/ast/p73_abi.sh` → `OK p73/abi`` | S |
| R3 文档 | 语言规范与 ABI 说明同步 | ``bash test/ast/p73_docs.sh` → `OK p73/docs`` | S |

## 4 退出判据

| 编号 | 判据 |
| --- | --- |
| E73-1 | E73-1 公开头只含 `pub` 字段，私有字段不进 ABI |
| E73-2 | E73-2 ABI 冲突有硬错与负例 |
| E73-3 | E73-3 `check-all` 11/11，golden 变化逐条说明 |

## 5 风险

| 编号 | 风险 | 缓解 |
| --- | --- | --- |
| R73-1 | 既有头文件 golden 会变 | 本相只改 `--lib`/ABI 面，逐条重生成 |

## 6 进展与收口对照（2026-11-19，v0.72.0）

| 任务 | 状态 | 证据 |
| --- | --- | --- |
| R1 导出面 | ✅ | `p73/export`：公开视图只有 `int fd;`；库（`.c` 用 CT_UNIT_PRIVATE）可构建；消费者读 `secret` 构建失败 |
| R2 ABI 硬错 | ✅ | `p73/abi`：同名 struct 不同布局报 `duplicate struct 'T'`（既有行为验收） |
| R3 文档 | ✅ | `p73/docs`：语言规范 §4.11.2 字段级可见性 + ABI 说明 |

| 判据 | 命令 | 结果 |
| --- | --- | --- |
| E73-1 | `p73_export.sh` | 绿 |
| E73-2 | `p73_abi.sh` | 绿 |
| E73-3 | `check-all.sh` | 11/11；golden 仅 banner（含新增 `#ifdef` 的 ABI 件需逐条确认） |

口径：只有「至少一个字段标 `pub`」的 struct 才切公开/私有视图；无字段 `pub`
的保持旧行为；带 `use` 的 struct 暂不切分（vtable 布局耦合），已在规范中写明。
