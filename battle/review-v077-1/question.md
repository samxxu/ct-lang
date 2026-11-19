# battle/review-v077-1 — v0.77.0 全面评审报告的 P1 是否成立、是否阻塞 1.0

| 字段 | 值 |
| --- | --- |
| 争点 | `docs/reviews/full-review-v0.77.0.md` 的事实、定级与 P1 行动是否成立；哪些必须落 issue/阻塞 1.0 |
| 当前 HEAD | `5b13fef4`（v0.77.0，报告基线；2026-11-19） |
| 触发理由 | 用户要求以 REQ/主张人身份 battle 评估报告，并把确认项落 issues |
| proposer | REQ（主张 A：报告 P1 基本成立，按 P1 全量阻塞 1.0） |
| opposition | REVIEW（主张 B：只有部分 P1 阻塞；文档/样例可批处理，个别结论需降级/撤回） |
| judge | EDITOR |
| 禁止触碰 | `selfhost/**`、`test/**`、`docs/language-spec.md`、`issues/**`（证据席不得改）；只写 `battle/review-v077-1/` 与 `/tmp` |

## 报告 P1 清单

1. `check-all` 在 `p77_external` 因 `ct get` 的 `system("git clone")` 无超时挂起。
2. 治理门禁缺位：`tools/check.sh` 只有 `g0`/`g8`；G1/G2/G4/G5/G6/G7/G9 无同名子命令，也无 deviation。
3. 问题台账不闭合：13+ 已修 issue 仍 open；168 条状态词不在 §5.4 闭集。
4. phase-ID 迁移未执行：无账本，A/B/C blocker 挂起，阻塞 `v1-PH-0`。
5. 文档漂移成簇：typecheck 计划、test/README、tutorial 示例数、AGENTS phase、session-map、README 命令表等。

## 位置 A（P1 全量成立，阻塞 1.0）

- 上述 5 项均属实且必须在 1.0 前解决；
- 治理门禁缺位使“全绿”不可信；台账不闭合使发布说明不可审计；phase-ID 是 v1.0 开卡硬前置；
- 文档漂移是用户/模型误读源，按 P1 阻塞。

## 位置 B（部分阻塞）

- 网络挂起、治理门禁、台账、phase-ID 是发布/治理硬阻塞；
- 文档漂移应降为 P1/P2 混合批处理，不必每项单独阻塞；计数类可由脚本回填；
- 报告个别结论需重核/降级（如 D-13、设计窗口、样例覆盖是否等于发布门槛）；
- 不能用“报告说 P1”代替可复现证据。

## 判据

| ID | 判据 | 通过方式 |
| --- | --- | --- |
| J-1 | 事实准确性：每条 P1 有可复现证据 | 命令/原始输出 |
| J-2 | 定级合理性：是否真的阻塞 1.0 | 发布契约/风险 |
| J-3 | 可执行性：建议是否可落成 issue/任务 | 验收命令/owner |
| J-4 | 范围：是否把 P2/P3 误升 P1 | 逐条对照 |
| J-5 | 成本：修复/批处理代价 | 文件/行数/阶段 |
| J-6 | 台账落法：按 bug/新需求/文档批，分别进 issue/REQ | 分流结果 |

## 证据要求

按 §7.7 E1–E5：完整命令/原始输出、`file:line`、可证伪预测、代价量化、对对方最强论点的 steelman。重点核：
- `selfhost/check-all.sh` / `p77_external` / `Pkg.h.ct` 的 `system("git clone")`；
- `tools/check.sh` 子命令；
- `issues/**` 状态词/已修项；
- `docs/planning/phase-id-ledger.md` 是否存在；
- `docs/planning/typecheck-semantic-plan.md`、`test/README.md`、`docs/tutorial.md`、`AGENTS.md`、`docs/session-map.md`、`docs/roadmap.md` 的现状。
