# v0.88.0 全面评审处置（2026-11-21）

> 对象：[full-review-v0.88.0](full-review-v0.88.0.md)（基线 `5605eb6c`）。
> 口径：接受项落库；争议项由 [battle/v1-readiness-1](../../battle/v1-readiness-1/verdict.md) 判决；
> 不改 `selfhost/**` / `test/**` 代码。

## 1. 已接受并落库（文档勘误）

| 项 | 处置 | 证据 |
| --- | --- | --- |
| D-1 `test/README` ast 目录数 | 299/298 → **312/311** | `find test/ast -mindepth 1 -maxdepth 1 -type d` |
| D-2 `test/README` 实测版本/计数 | v0.77.0、1519/0/4 → **v0.88.0、1575/0/5** | 评审 §1 / 本轮 `check-ast`（本机 Renode 环境差异另记） |
| D-4 `phase88.md` MAX_FUNCS 余量 | 37 → **11（501/512）** | p88_metrics §4 #3 |
| D-5 `p88_metrics.md` 余量 | 37 → **11（501/512）** | 同文件 §5 |
| D-6 `phase-log.md` MAX_FUNCS | 475/512 → **501/512（余 11）**（两处） | p88_metrics |
| D-7 `v1-release-plan.md` 基线 | v0.65.1 / Phase 66 → **v0.88.0 / PH-88** | 本轮 |
| D-8/P3-12 `docs/README` 评审索引 | 最新 v0.88.0 + 历史 v0.77.0 具体链接 | 本轮 |
| P3-13 工作树 guide/battle/memory/sh106 | 与本处置同一批提交入库 | 见提交记录 |
| P1-5 历史债之一：dogfood FP 未立案 | 立 [SH-108](../../issues/selfhost/sh108-p87-dogfood-t-a-fp.md) | PH-87 N-4 |

补充勘误（评审 N-1 的剩余位置）：`language-spec.md` §4.75、`v1-pre-evidence.md`、
`AGENTS.md` 的 MAX_FUNCS 数字同步到 **425 → 501 / 余 11**。

## 2. 已接受并登记（不阻塞 v1-PH-0）

| 项 | 落点 |
| --- | --- |
| P2-9 新特性 example（ref/out、slice、box/new、match） | [DOC-84](../../issues/docs/doc-84-new-feature-examples.md) |
| P2-10 覆盖率/容量边界测试 | [TEST-25](../../issues/testing/test25-coverage-and-unit.md)；容量负例并入 [SH-109](../../issues/selfhost/sh109-max-funcs-capacity.md) |
| P2-11 包契约 v1 收尾 | 现有 PKG-12/13/15/16/17/19/20 |
| P2-8 退役 phase77 | `v1-PH-0` 开卡前归档；本轮不动（避免设计窗口漂移） |

## 3. 争议项 → battle 判决

| 评审项 | 处置 |
| --- | --- |
| P1-1 SH-104/105 | **Tier 1**（v1-PH-0 入口），现有 issue |
| P1-2 `MAX_FUNCS` 501/512 | 原 Tier 1 决策；**2026-11-21 所有者改落 `v1-PH-1 / S0`（512→1024）** → [SH-109](../../issues/selfhost/sh109-max-funcs-capacity.md) |
| P1-3 phase-ID 迁移 | **Tier 2**（v1.0 发布）→ [DOC-83](../../issues/docs/doc-83-phase-id-migration-decision.md) |
| P1-4 G1/G6 | **Tier 2**（v1.0 发布）→ [CI-13](../../issues/ci/ci-13-g6-ledger-closure.md) |
| P1-5 历史 High 证据债 | **Tier 2**；SH-107/DOC-81/DOC-82 逐项“修/不修+理由” |
| P2-6 p88 EDITOR 追签 | **Tier 1**（v1-PH-0 入口），沿用 battle/p88-emit-match |

判决见 [battle/v1-readiness-1/verdict.md](../../battle/v1-readiness-1/verdict.md)：
两级门禁 + `v1-PH-0` 出口复核；五项一个都不删除。

## 4. 复现

```console
$ git rev-parse --short HEAD        # 5605eb6c（v0.88.0）
$ find test/ast -mindepth 1 -maxdepth 1 -type d | wc -l   # 312
$ grep -n "501" docs/history/p88_metrics.md | head -3
$ bash tools/check.sh g0
$ python3 test/docs/check-docs.py
```

本机 `check-ast` 在 Renode/podman 环境有一项环境性失败（`baremetal_renode` 缺
`.temp/renode-run/out/uart.txt`），其余 1576 通过、3 skip；评审基线的 1575/0/5
来自 Renode 正常 skip 的环境。该差异记入本处置，不据此改产品判据。

## 5. 未决

- 历史 High 证据债的具体“修/不修”结论：SH-107 / DOC-81 / DOC-82 各自补；
- phase-ID blocker A/B：等主规范裁定；
- G1/G6：实现或 deviation，CI-13 二选一；
- `MAX_FUNCS` 方案：SH-109 三选一，方案 A 需 USER 签字。
