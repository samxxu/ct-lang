# battle/v1-readiness-1 主张席（REQ）——按归属分两级

- 主张：五项 P1 **全部保留**，但分两级：`v1-PH-0` 入口门禁与 `v1.0` 发布门禁。
- 不把跨仓/主规范决策伪装成本仓可清；也不把历史债静默 open。
- 目标：让 `v1-PH-0` 能按本仓可验收项开卡，同时 `v1.0` 发布仍被五项全部约束。

## E1 — 关键实物证据

```console
$ grep -n "V1-C1\|V1-C2" docs/planning/v1-release-plan.md
64:| V1-C1 | J-6 全量证据台账 ... | [SH-104](...)
65:| V1-C2 | goldens 静态化 ... | [SH-105](...)

$ grep -n "状态" issues/selfhost/sh104-j6-evidence-ledger.md issues/selfhost/sh105-goldens-static-freeze.md
10:| 状态 | **待办（REQ 建台账；DEV 补证据）** |
10:| 状态 | **待办（DEV 实现；REQ 定验收）** |

$ grep -n "g0)\|g8)\|battle-selftest)\|usage:" tools/check.sh
63:  g0) g0 ;;
64:  g8) g8 ;;
65:  battle-selftest) battle_selftest ;;
66:  *) echo "usage: tools/check.sh g0 | g8 | battle-selftest" >&2; exit 2 ;;

$ grep -n "状态" issues/selfhost/sh107-m0-commit-not-buildable.md issues/docs/doc-81-phase85-clean-archive-dead-link.md issues/docs/doc-82-phase85-e85-2-gate.md
10:| 状态 | **open** |
10:| 状态 | **open** |
10:| 状态 | **open** |

$ grep -n "追签" battle/p88-emit-match/verdict.md
4:- 状态：**accepted（... REVIEW 2026-11-21 追签，条件见文末；EDITOR 追签待补）**

$ grep -n "501" docs/history/p88_metrics.md | head -3
64:| 3 | ... 425 → 501 | 再切一批（>11 个函数）会撞顶 | ... 501/512 |
103:3. `MAX_FUNCS` 余量 11 个顶层函数（501/512）...
```

## E2 — 逐项处置矩阵（归属 / 验收）

| 项 | A 案层级 | 归属 | 验收命令/证据 |
| --- | --- | --- | --- |
| SH-104 J-6 台账 | **Tier 1：v1-PH-0 入口** | 本仓（REQ 台账 + DEV 证据） | 台账零未决；`docs/planning/v1-release-plan.md:64` 的 V1-C1 |
| SH-105 goldens 静态化 | **Tier 1：v1-PH-0 入口** | 本仓（DEV） | 静态期望覆盖全部语料；V1-C2 |
| `MAX_FUNCS` 501/512 | **Tier 1：v1-PH-0 入口决策** | 本仓（REQ 数据 + USER 签字） | 复算 501/512；三选一：提上限/`impl`/调切片；补临界+越界负例 |
| E88-1 字面 `match` 承接 | **Tier 1：v1-PH-0 seed cutover** | 本仓（DEV） | `battle/p88-emit-match` EDITOR 追签；seed cutover 范围写死 |
| phase-ID 迁移 | **Tier 2：v1.0 发布** | 跨仓/主规范（blocker A/B） | 账本 + W0→W2；blocker A/B 由主规范裁定 |
| G1/G6 治理 | **Tier 2：v1.0 发布** | 本仓（CI/REQ） | G6 机械实现或显式 `deviation:`；184 条非闭集清零 |
| SH-107/DOC-81/DOC-82 历史债 | **Tier 2：v1.0 发布** | 本仓（DOC/DEV） | 每项“修/不修+理由+日期”，不得静默 open |

- **不利于己方的一条**：评审 §7 明确“v1.0 就绪 4/10”，且 `tools/check.sh` 当前只有
  g0/g8/battle-selftest——G6 不是文档项，而是实打实的门禁实现；A 把它放 Tier 2，
  若实现成本被低估，v1.0 会被它拖住。回应：Tier 2 仍写死 owner 与日期，并在
  `v1-PH-0` 出口复核一次；不因分层而消失。

## E3 — 可证伪预测

1. 若 A 成立：`v1-PH-0` 可在 SH-104/105、`MAX_FUNCS` 决策、E88-1 追签后开卡；
   phase-ID/G6/历史债仍列 `v1.0` 发布门禁，且各有 owner/日期。
2. 若 B 成立：`v1-PH-0` 必须等 phase-ID blocker A/B 与 G6 实现；而 blocker A/B 需要
   主规范裁定（不在本仓），开卡时间不可控。
3. 失效条件：若 phase-ID 的卡命名/账本是 `v1-PH-0` 开卡的硬前置（例如工具无法在 legacy
   `PH-*` 下识别新卡），则 A 的 Tier 划分错误，phase-ID 必须升入 Tier 1。

## E4 — 代价

- A：多 3–4 个 issue/决策记录；Tier 2 有被拖延的风险，但每项有日期与出口复核。
- B：`v1-PH-0` 被主规范/跨仓阻塞，重写收口后无法继续；历史债与 G6 也可能长期无人推。
- 两者都不改代码；A 的额外成本主要是台账与签字流程。

## E5 — 对 B 的 steelman

B 的最强论点是：**五项都是评审认定的 P1，分层会让低优先级项无限期挂起**；而且
“v1-PH-0 开卡”会消耗团队注意力，先把 G6/phase-ID 清掉更稳。

回应：A 不删除任何一项，只改**门禁位置**；Tier 2 每项必须写 owner、日期、验收命令，
并在 `v1-PH-0` 出口做一次“Tier 2 是否被拖延”的复核。若复核发现某项实际阻塞开卡，
按 §7.12 追加注记升入 Tier 1——这正是可证伪预测 3 的用途。
