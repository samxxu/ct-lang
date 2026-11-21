# battle/v1-readiness-1 反对席（REVIEW）——五项全部作为 v1-PH-0 硬门禁

- 主张：五项 P1 **全部**在 `v1-PH-0` 开卡前清零；不接受 Tier 2“发布门禁”分层。
- 理由：评审已经认定它们是 v1.0 的硬前置；分层会让低优先级项在开卡后被遗忘，
  而历史证据债正是“收口证据可能不成立”的教训。

## E1 — 关键实物证据

```console
$ sed -n '29,40p' docs/reviews/full-review-v0.88.0.md
**不能发布 1.0 的原因**
1. **v1.0 的两个硬闸门仍是 `待办`**：SH-104、SH-105 ...
2. **phase-ID 迁移仍未执行** ...
3. **治理门禁仍缺 G1/G6** ...
4. **自举容量只剩 11 个顶层函数** ...
5. **PH-88 的 E88-1 只“部分通过”** ...

$ grep -n "在 A/B 裁定前\|需要裁定" docs/planning/phase-migration-blockers.md
17:**需要裁定**：旧 `v0-*` 卡是否允许 ...
34:**需要裁定**：迁移后卡片路径是 ...
47:**需要裁定**：迁移脚本是否统一补字段 ...
74:在 A/B 裁定前不动文件；否则会二次迁移。

$ grep -n "g0)\|g8)\|battle-selftest)" tools/check.sh
63:  g0) g0 ;;
64:  g8) g8 ;;
65:  battle-selftest) battle_selftest ;;

$ grep -n "状态" issues/selfhost/sh107-m0-commit-not-buildable.md issues/docs/doc-81-phase85-clean-archive-dead-link.md issues/docs/doc-82-phase85-e85-2-gate.md
10:| 状态 | **open** |     (x3)

$ grep -n "501" docs/history/p88_metrics.md | head -3
64:| 3 | ... 425 → 501 | 再切一批（>11 个函数）会撞顶 |
103:3. `MAX_FUNCS` 余量 11 个顶层函数（501/512）...
```

## E2 — 逐项锚点（含不利于己方的一条）

- `docs/reviews/full-review-v0.88.0.md:31`：SH-104/SH-105 是“v1.0 的两个硬闸门”；
- `docs/reviews/full-review-v0.88.0.md:33`：phase-ID 迁移未执行，仓库仍用裸 `PH-*`；
- `tools/check.sh:63-65`：只有 g0/g8/battle-selftest，G1/G6 没有机械实现；
- `docs/history/v1-pre-evidence.md:47`：dogfood FP 曾长期“工作树待提交”，
  证明“先记后补”的 Tier 2 容易变长期欠账；
- **不利于己方的一条**：评审 §8 的 P1 列表里，**只有 SH-104/105 被明确写成
  “v1-PH-0 前必须”**；phase-ID、G1/G6、历史债在 §8 被列为 v1.0 前必须，并没有说
  “开 v1-PH-0 前必须”。这削弱了“五项全部堵在 v1-PH-0 门口”的文本依据。
  回应：评审 §0 同时写“v1.0 不是再做一点”，且 `v1-PH-0` 是 v1.0 的第一张卡；
  若开卡即意味着进入发布倒计时，则五项都应在开卡前有明确处置，而不是只留 issue。

## E3 — 可证伪预测

1. 若 B 成立：`v1-PH-0` 开卡前，五项全部有“已清零”证据；任何一项仍是 `待办/open` 即不开卡。
2. 若 A 成立：`v1-PH-0` 可在 phase-ID blocker A/B 未裁、G6 未实现、历史债未处置时开卡；
   这三项必须带 owner/日期，否则 B 的“会遗忘”预测成立。
3. 失效条件：若 `v1-PH-0` 的卡命名、账本识别或出口验收确实不依赖 phase-ID/G6，
   则 B 的“全部前置”过严；此时应降至 A 的两级。

## E4 — 代价

- B：开卡被主规范/跨仓 blocker 阻塞，可能无限期等待；但 v1.0 不会带着证据债发布。
- A：开卡快，但 Tier 2 三项有被后续重写/特性挤掉的风险；历史债已出现“工作树待提交”
  长期挂起的先例。
- 两者都不改代码；B 的代价是时间，A 的代价是治理风险。

## E5 — 对 A 的 steelman

A 的最强论点是：**评审自己把 SH-104/105 写成 v1-PH-0 硬门禁，其余三项写在 v1.0 发布清单**；
按文本分层是忠实执行，而不是降级。

回应：文本确实分层，但评审的结论是“v1.0 不可发布”，五项都是 P1；`v1-PH-0` 是 v1.0 的
第一张卡，开卡会把团队注意力从治理/证据债转到重写。若没有“开卡前五项都有处置”的硬门禁，
Tier 2 很可能在 PH-86–88 的重写节奏里被推迟——v1-pre 已经发生过一次（SH-107/DOC-81）。
