# LANG-23 · 内建 trait 声明显性化（`Drop` / `Handback`；`AutoDrop` 不是 trait）

| 项 | 值 |
| --- | --- |
| 模块 | lang / 编译器内建 trait |
| 定性 | 可见性重构（不改语义） |
| 严重度 | Low–Medium |
| 锚点 | v0.88.0（2026-11-21） |
| 依据 | Kimi 2026-11-21 说明；[language-spec §4.9](../../docs/language-spec.md#49-autodropphase-5-新增仅-ct-线)、[§4.40](../../docs/language-spec.md#440-borrow-与-handbackphase-5-续仅-ct-ast)、[§4.71](../../docs/language-spec.md#471-box--new单对象句柄phase-81仅-ct-ast) |
| 状态 | verified |
| 处置证据 | **accepted（2026-11-22 所有者改判：提前到当前 pre 窗口，不再等 v1.1；依赖 DOC-87 Stage 1）** |

## 背景

`Drop` / `Handback` 名义上是 trait，实际是编译器按名字识别的**保留名内建 trait**：

- 用户不声明它们；`use Drop` / `impl Drop for S` 触发释放胶水、逆序释放、泄漏告警等；
- 当前没有 `trait Drop` / `trait Handback` 的可见声明，读代码找不到定义；
- `trait Drop` 目前会被 parser 拒绝（`'Drop' is a reserved built-in trait and cannot be defined`）；
- `AutoDrop` **不是 trait**，是 `own` 的自动释放机制；不要把它声明成 trait。

## 目标

在 `lib/core/` 提供可见的正式声明（目录名按 [DOC-87](../../issues/docs/doc-87-lib-core-rename.md) Stage 1）：

```ct
/* lib/core/BuiltinTraits.h.ct（名字待定） */
pub trait Drop { void drop(); }
pub trait Handback { void handback(); }
```

要求：

- 编译器仍按名字识别，**不引入 vtable/vptr**；
- 两个 trait 不进入 `use[]` 列表、不计入 `MAX_TRAITS`；
- `use Drop` / `impl Drop` / `borrow` 的行为与 v0.88 完全一致；
- 编辑器/索引器能跳转到声明；
- `AutoDrop` 不作为 trait 声明，只在文档/注释中说明它是机制。

## 需要改的地方

| 位置 | 改动 |
| --- | --- |
| `selfhost/ct-ast/frontend/parse/Parser.h.ct` | 允许**内建声明单元**声明 `Drop`/`Handback`（其他单元仍报保留名）；标记 `is_builtin` |
| `selfhost/ct-ast/frontend/sym/Symbols.h.ct` | 若进 trait 表，排除 `MAX_TRAITS` 计数与 vtable 生成；或只做声明行不建可派发 trait |
| `adopt_use` / `find_trait` / `impl` 解析 / `Emitter` | 审计：现有 `strcmp("Drop")` 分支必须优先于普通 trait 路径 |
| `editors/vscode/indexer.js` | 把 `lib/core` 的内建声明纳入跳转索引 |
| spec §4.9/§4.40/§4.71、glossary | 写明声明位置与“保留名、无 vtable”的契约 |

## 验收

1. `lib/core` 中能看到 `Drop` / `Handback` 声明；跳转可到定义；
2. `use Drop`、`impl Drop`、`delete`、`borrow` 的生成 C 与 v0.88 逐字节一致；
3. 没有 vtable/vptr；`MAX_TRAITS` 计数不变；
4. 用户在其他单元写 `trait Drop` 仍报保留名；
5. `trait AutoDrop` 不被引入；
6. `check-all` / `check-ast` / `check-docs` / 编辑器 grammar 绿；
7. 单提交回滚。

## 非目标

- 不改变 Drop/Handback 的语义、生成胶水、泄漏告警；
- 不把 `AutoDrop` 变成 trait；
- 不把 `arena` 收进编译器内建层（arena 是 std 包的用户面实现，维持现状）；
- 不与 DOC-87 Stage 1 同一提交；Stage 1 落 `lib/core` 后独立提交、独立回滚。

## 风险

| 风险 | 缓解 |
| --- | --- |
| `find_trait` 返回 ≥0 后走普通 trait 路径 | 保留按名字优先的分支；加回归夹具 |
| 计入 `MAX_TRAITS`/生成 vtable | 标记 `is_builtin`；断言无 vtable、计数不变 |
| 保留名检查被绕过 | 只允许内建声明单元；其他单元负例 |
| 与 DOC-87 Stage 2 `namespace core` 交叉 | 先落 DOC-87 Stage 1；Stage 2 时把声明改为 `core::Drop` |

## 关联

- [DOC-87](../../issues/docs/doc-87-lib-core-rename.md)（`lib/core` 目录）
- [language-spec §4.9 / §4.40 / §4.71](../../docs/language-spec.md#49-autodropphase-5-新增仅-ct-线)
- [glossary.md](../../docs/glossary.md)

## 排期改判（2026-11-22，所有者）

**结论：`deferred` → `open`，提前到当前 pre 窗口（v1.0 前），不再等 v1.1。**

- 执行顺序：DOC-87 Stage 1 落 `lib/core` → 独立提交 LANG-23（parser 例外、Symbols 计数排除、
  Emitter 分支优先级、编辑器索引、spec/glossary 条款）→ DOC-87 Stage 2 时再改
  `core::Drop` / `core::Handback`；
- 仍然只声明 `Drop` / `Handback` 两个 trait；**`AutoDrop` 是 `own` 的机制，不是 trait，
  本卡不得为它生成声明**；
- 代码与脚本由 DEV 执行，REQ 侧只改排期与验收；`AutoDrop` 的措辞纠正在
  [lib/core 提案评估](../../docs/reviews/2026-11-22-lib-core-proposal-eval.md) §2 留档。


## 复核（REV，2026-11-23）

主干提交 `fb9dddd9`：`lib/core/Vec.h.ct` 提供可见 `pub trait Drop` / `pub trait Handback`；
`use`/`impl` 行为与 C 输出不变；用户重定义仍被拒；`AutoDrop` 非保留 trait。

```console
$ sh test/ast/lang23_builtin_traits.sh .temp/verify-current/ct-ast
lang23: 0 failure(s)
$ TMPDIR=.temp/checktmp bash selfhost/check-all.sh
check-all: OK (11 hard gates green)
```
