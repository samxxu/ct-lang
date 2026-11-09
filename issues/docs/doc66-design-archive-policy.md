# DOC-66 · `docs/design/` 的「只放当前阶段」约定与 phase17–25 未归档并存

| 项 | 值 |
| --- | --- |
| 模块 | docs |
| 严重度 | **Medium**（不影响编译器，但目录语义与索引声明互相矛盾） |
| 锚点 | `v0.25.0`（2026-11-09） |
| 文件 | [docs/README.md](../../docs/README.md)、[docs/design/](../../docs/design/)、[docs/history/README.md](../../docs/history/README.md)、[test/docs/check-docs.py](../../test/docs/check-docs.py) |
| 状态 | open |

## 现象

[docs/README.md:5-6](../../docs/README.md#L5-L6) 写着「本目录只放**当前有效**的文档；已关闭阶段的设计记录与评审报告在 [history/](history/README.md)」，
但 `docs/design/` 实际保留着 **Phase 17–25 的 9 份已完成主计划**（`phase17.md` … `phase25.md`，另有
`phase20-disputes.md` / `phase20-review.md` / `phase20-type-alias.md` 三份专题记录），而
`docs/history/design/` 的归档并不连续（现存 `phase6` / `phase8` / `phase9` / `phase10` / `phase12`）。

本轮只修索引事实（把「规划中」改为「已完成」并补 phase24/25），没有搬动任何阶段文档。

## 判据（完成定义，二选一）

**A. 归档路线**

- 把 `phase17.md`–`phase25.md`（及 phase20 三份专题）移入 `docs/history/design/`；
- 同步 `docs/README.md`、`docs/history/README.md`、`docs/roadmap.md`、`issues/**` 中的所有相对链接；
- `check-docs.py` 增加断言：`docs/design/` 只允许当前未完成 phase 的文档（或明确白名单）。

**B. 保留路线**

- 修改 `docs/README.md` 的「只放当前有效」表述，明确 `docs/design/` 保留最近 N 个已完成 phase；
- 写清退役阈值与 `history/` 的对应关系；
- `check-docs.py` 增加对应的白名单/上限断言，避免再次漂移。

两条路线都必须满足：`python3 test/docs/check-docs.py` 与 `bash selfhost/check-all.sh` 全绿。

## 代价

- **A**：约 12 个文件移动 + 数十处相对链接重写（roadmap、issues、docs/README、history/README），diff 大、审查成本高；收益是目录语义恢复。
- **B**：零搬迁，只需改一段约定并加一条门禁断言；代价是 `design/` 继续增长，需要定义上限并接受「当前有效」改为「最近 N 个阶段」。
- 本轮不选：属于目录政策而非事实漂移，按用户授权范围不在本轮处理；登记为 `open`，避免擅自搬文件或另立流程。

## 证据

- [docs/README.md:5-6](../../docs/README.md#L5-L6) 的「只放当前有效文档」；
- `ls docs/design/phase{17..25}.md` → 9 个文件（另加 phase20 三份专题）；
- `find docs/history/design -name 'phase*.md'` → 仅 `phase6` / `phase8` / `phase9` / `phase10` / `phase12`，无 17–25；
- [test/docs/check-docs.py:168-190](../../test/docs/check-docs.py#L168-L190) 只校验 design 文档的状态行与 roadmap 一致，没有归档位置断言。

## 处置

本轮（`v0.25.0` 文档漂移）只修索引事实，不改变归档策略；保持 `open`。
