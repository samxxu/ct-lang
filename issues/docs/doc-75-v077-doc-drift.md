---
id: DOC-75
title: "v0.77 文档漂移批：typecheck/test README/tutorial/AGENTS/session-map"
status: verified
area: docs
severity: P1
opened: 2026-11-20
confirmed-by: REQ-review-v077-1
---

# DOC-75 · v0.77 文档漂移批

## 来源

[full-review-v0.77.0](../../docs/reviews/full-review-v0.77.0.md) §4；battle [review-v077-1](../../battle/review-v077-1/verdict.md)。

## P1 子项

| ID | 位置 | 现状 | 修正 |
| --- | --- | --- | --- |
| D-1 | [typecheck-semantic-plan](../../docs/planning/typecheck-semantic-plan.md) | “未开卡”，基线 v0.65.1 | v0-PH-68–71 已收口；改为历史计划/已完成 |
| D-2 | [docs/README](../../docs/README.md#L41) | 类型检查“未开卡” | 同上 |
| D-3 | [test/README](../../test/README.md#L6) | ast/errors 141、ast 119 | 实际 295 / 299 |
| D-5 | [AGENTS](../../AGENTS.md#L452) | `phase=v0-PH-66` | 当前 v0-PH-77 |

## P2 子项（可批处理）

- D-4 tutorial“16 个示例” → 实际 **51**（报告写 52，错）；
- D-6 session-map 表格被 blockquote 截断；
- D-7 roadmap Phase 76 写 v0.76.1 → v0.76.0（v0.76.1 是 SH-92 fix）；
- D-8 README 0.44.1 基线应标“最近实测/历史”；
- D-9 README 缺 `--emit-model` / `ct check --types`；
- D-10 architecture 只讲 L0；
- D-11 selfhost/README grammar 40 → 169；
- D-12 bare-metal 提案状态；
- D-13 `v[0]` 描述分包重核（A2 已硬错，A1/A3 未实现）；
- design window 12/12：下一次开 phase 前必须把 phase66 退役到 `docs/history/design/`；
- package-guide 补“官方 pin 强校验 / 第三方索引仅便利”的信任模型；
- README/package-guide 明确 git 网络失败/超时行为（与 CI-9 联动）。

## 验收

- 所有计数由脚本回填或在 `check-docs` 断言；
- 51/299/295/169 等数字与实测一致；
- `AGENTS` phase、session-map 表、roadmap 版本位一致；
- D-1/D-2 不再把已完成 phase 说成未开卡；
- 不把 D-4/D-6 等 P2 冒充 P1。

## 范围

P1 批，不占 phase；纯 docs，除计数脚本外不 bump。

## 处置（2026-11-20，DEV）

范围：仅文档与本文处置；**不改 `status`**、不 push、不打 tag、不碰 `battle/**`、`docs/reviews/**` 与代码。

实测命令与值：

- `sh test/run.sh` → `156 passed, 0 failed`；
- `bash selfhost/check-ast.sh` → `1519 passed, 0 failed, 4 skipped`；
- `ls test/ast/errors/*.ct | wc -l` → `295`；`find test/ast -mindepth 1 -maxdepth 1 -type d | wc -l` → `299`（含 `errors/`；行为探针 298）；
- `find examples -mindepth 1 -maxdepth 1 -type d | wc -l` → `51`；
- `python3 editors/vscode/test/check-grammar.py` → `== 169 checks, 0 failed ==`。

| ID | 状态 | 改后值 / 位置 |
| --- | --- | --- |
| D-1 | fixed | [typecheck-semantic-plan](../../docs/planning/typecheck-semantic-plan.md) 标题/性质改为「历史计划，已交付」；基线标注 v0.65.1 起草、收口核对 2026-11-20；§6 状态由「规划中（未开卡）」改为「✅ 已收口」，版本 v0.67.0–v0.70.0 |
| D-2 | fixed | [docs/README](../../docs/README.md) 类型检查行改为「已交付、历史计划；v0-PH-68–71 已收口（版本 0.67.0–0.70.0）」，不再写「未开卡」 |
| D-3 | fixed | [test/README](../../test/README.md)：`ast/errors` 141→**295**（含实测命令）；`ast/` 119→**299** 目录（含 `errors/`；行为探针 298）；另补 runner 实测 `156 passed, 0 failed` / `1519 passed, 0 failed, 4 skipped` |
| D-4 | fixed | [tutorial](../../docs/tutorial.md)「16 个可运行示例」→「**51 个示例目录**」（`find examples -mindepth 1 -maxdepth 1 -type d \| wc -l` 实测；注明 `49_socket` 为文档型） |
| D-5 | fixed | [AGENTS](../../AGENTS.md) 实例化节 `phase=v0-PH-66` → `phase=v0-PH-77`（只改该字段，未动生成块） |
| D-6 | fixed | [session-map](../../docs/session-map.md) 把截断表格的 blockquote 移到表后；v0-PH-38…v0-PH-77 行连成完整表格 |
| D-7 | fixed | [roadmap](../../docs/roadmap.md) Phase 76 收口版本 v0.76.1 → **v0.76.0**（v0.76.1 是 SH-92 fix）；与 [phase76 卡](../../docs/phases/v0-PH-76/card.md) 一致 |
| D-8 | fixed | [README](../../README.md)：0.44.1 标为「历史基线（最近一次完整实测）」，并在 §0 表、§0.1、§3 四处同口径；未改结论 |
| D-9 | fixed | [README](../../README.md) §2 常用命令补 `ct check --types` 与 `ct … --emit-model <file\|->` 两行（含 opt-in、默认编译路径不做类型检查的边界） |
| D-10 | fixed | [architecture](../../docs/architecture.md) 标题改为 L0（主线 ct-ast 见 §0）；新增 §0「四代编译器与本文范围」表，给出 L0 / L1 / L2 / ct-ast 位置与指针（selfhost/README、AGENTS §2、roadmap） |
| D-11 | fixed | [selfhost/README](../../selfhost/README.md) grammar「40 项断言」→「**169 项断言**」（`python3 editors/vscode/test/check-grammar.py` 实测） |
| D-12 | fixed | [ct-bare-metal-proposal](../../docs/proposals/ct-bare-metal-proposal.md) 状态改为「已采纳并交付（v0-PH-64，v0.63.0）」，落点改 `phase64` 卡；[docs/README](../../docs/README.md) 同步去掉「待 CT 组评估」 |
| D-13 | fixed | [language-spec](../../docs/language-spec.md) §4.64 与 §8 三处按实测改写：`ct check` 对键类型不匹配给 error（rc=1），`ct compile` / `ct build` 只给 warning（rc=0，仍发射 `get(0)`）；**按键类型分派仍未实现**，保留 REQ-JSACCESS-1 与包层 `get_idx`（不编造已实现） |
| —（design window） | deferred | 未开新 phase，窗口未触发；`check-docs` 报 `design window: ok (12/12)`。下次开 phase 前须把 `docs/phases/v0-PH-66/card.md` 退役到 `docs/history/design/`（本次不动，避免提前改变窗口） |
| —（package-guide 信任模型） | fixed | [package-guide](../../docs/package-guide.md) §4.1：官方 pin 强校验（tag + sha256、默认不读索引；显式索引 `publisher=ct` 是用户显式选择）、第三方索引仅便利（无签名，信任边界 = 索引文件 + 显式 `<publisher>/<name>`） |
| —（git 网络失败） | fixed | [README](../../README.md) §2 与 [package-guide](../../docs/package-guide.md) §4：clone/fetch 失败或超时在写 `ct.lock` 前非零退出、旧锁逐字节不变；git 子进程已有有界超时（`CT_GIT_TIMEOUT` 默认 180s）与 `GIT_TERMINAL_PROMPT=0`（CI-9 已落地），文案仍只写「有界失败」 |

验证：`python3 test/docs/check-docs.py` → OK；`bash tools/check.sh g0` → OK。

## 复核（2026-11-20，REV）

**结论：verified。** 独立自举后逐项核对：

```console
$ ls test/ast/errors/*.ct | wc -l
295
$ find test/ast -mindepth 1 -maxdepth 1 -type d | wc -l
299
$ find examples -mindepth 1 -maxdepth 1 -type d | wc -l
51
$ python3 editors/vscode/test/check-grammar.py
== 169 checks, 0 failed ==
$ python3 test/docs/check-docs.py
check-docs: OK (1945 relative links in 324 files, v0.77.1, 11 hard gates, 12 phase status, 3 适用版本 header(s))
design window: ok (12/12)
$ bash tools/check.sh g0
g0: OK (block 1.17.0, session-map present)
```

D-1…D-13 逐项对照：typecheck 计划/README 已改“历史计划、已交付”；test/README 295/299；
tutorial 51；AGENTS `phase=v0-PH-77`；session-map 表完整；roadmap Phase 76 `v0.76.0`；
README 0.44.1 标历史基线；`ct check --types` 与 `--emit-model` 在 README §2；
architecture §0 四代表；selfhost/README 169；bare-metal 提案“已采纳并交付”；§4.64
按键类型与实测一致（下）。package-guide §4.1 信任模型、README/package-guide 的有界
网络失败文案均在案。

D-13 行为实测（归档二进制）：

```console
$ /tmp/rev-v0771-build/ct-ast check --types bad.ct;  echo rc=$?
bad.ct:4:56: error: argument 1: expected 'char *', got 'int'
rc=1
$ /tmp/rev-v0771-build/ct-ast compile bad.ct -o bad.c; echo rc=$?
bad.ct:4: warning: argument 1: expected 'char *', got 'int'
rc=0
$ /tmp/rev-v0771-build/ct-ast build bad.ct -o out; echo rc=$?
bad.ct:4:56: warning: argument 1: expected 'char *', got 'int'
rc=0
```

唯一未执行的是 P2 里的条件项“下次开 phase 前把 phase66 退役”：当前 `design window`
为 12/12、未开新 phase，触发条件未到，按条件 deferred 记录；其余 P1/P2 全部落实。
