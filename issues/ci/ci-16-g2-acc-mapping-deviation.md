---
id: CI-16
title: "G2 的 ACC-* 映射缺失：先登记 deviation，v1.1 前补机械校验"
status: verified
area: ci
severity: P2
opened: 2026-11-21
confirmed-by: CI-10
---

# CI-16 · G2 ACC-* 映射缺失

## 现象

`AGENTS.md` §6.4 的 G2 要求「每个接口/协议承诺映射到 `ACC-*` 条目」。
本仓 `docs/design/*.md` 没有任何 `ACC-*` 条目：

```console
$ grep -rl 'ACC-[0-9]' docs/design --include='*.md' | wc -l
0
$ grep -rho 'ACC-[0-9][0-9]*' docs --include='*.md' | sort -u | head
ACC-07        # 仅出现在主规范副本 docs/spec/ai-coding-workflow.md 的示例
```

历史 phase 卡用 `E<phase>-<n>` 验收判据承载承诺（见 `g5`），但 E-* 与 ACC-* 不是同一
映射表：G2 的「接口/协议承诺」需要需求侧先给 ACC-* 编号，属重构，不能由门禁脚本代造。

## 处置（CI-10 批次，2026-11-21，REQ/REV）

- `tools/check.sh g2` 目前只打印 SKIP，指向 `AGENTS.md` 0.3 的 `deviation: g2-acc-mapping`；
- 偏离含日期、理由、收敛方式与签字（用户 2026-11-21，CI-10 任务指令）；
- G2 的 P1/P2 归属按 CI-10 的分组保持 P2，不阻塞 G1/G5/G6 的最小入口。

## 收敛（v1.1 前）

1. REQ 在 `docs/design/*.md` 为每个接口/协议承诺分配 `ACC-*` 编号并维护映射表；
2. `tools/check.sh g2` 换成机械校验：每个承诺至少一条 `ACC-*`，缺一条即红，并配负例；
3. 删除 `AGENTS.md` 0.3 的 `deviation: g2-acc-mapping`，本条目转 `verified`。

## 验收

- `grep -rl 'ACC-[0-9]' docs/design --include='*.md'` 覆盖所有接口/协议文档；
- `bash tools/check.sh g2` 对缺映射的负例返回非 0；
- `AGENTS.md` 0.3 不再有该偏离。


## 状态（REQ，2026-11-21）

`deferred`，触发条件：**v1.1 开工前**（ACC-* 映射属需求侧重构，P2，不阻塞 v1.0）。
偏离 `g2-acc-mapping` 已生效，`tools/check.sh g2` 当前 SKIP；触发时按本卡「收敛」三步执行并转 `verified`。

## 实现（2026-11-23，DEV；状态字段未改）

按「收敛」三步落地，`g2` 从 SKIP 换成机械校验，偏离已删除。

- `docs/design/acc-scope.tsv`：9 个接口/协议文档的登记表（doc / 协议 / 最少 ACC）；
- 9 个文档各加 `<!-- g2:interface -->` 与 `## ACC 映射` 四列表（ACC-id / 承诺 / 章节 / 判据证据），
  当前 25 条 ACC；
- `tools/gates/acc_map.py`：双向校验（登记表 ↔ marker）、ACC id 全局唯一、承诺/章节/证据非空、
  证据必须是可跑/可读的 test/tools/selfhost/docs 路径或 §spec；缺表、未登记、重复 id、空证据、
  悬空登记、行数不足均红；
- `tools/check.sh g2`：调用 `acc_map.py`，不再是 SKIP；
- `AGENTS.md` 0.3 删除 `deviation: g2-acc-mapping`，0.1 的「g2 见偏离」同步改为「g2 已机械校验」。

```console
$ bash tools/check.sh g2
g2: OK (9 interface doc(s), 25 ACC row(s))
$ sh test/gates/acc_map_test.sh
OK g2/acc-map (6 negative cases + 1 positive)
$ bash tools/check.sh g0
g0: OK (block 1.17.0, session-map present)
```

负例红证（旧树 `a0ce8ef1` + 新测试、旧实现）：`acc_map.py` 不存在，`good` 用例即红；
新增 6 个负例覆盖缺表 / 未登记 marker / 重复 id / 空证据 / 悬空登记 / 行数不足。
状态仍为 `deferred`：本段只落实现与证据，等 REV 复核后决定是否改状态（本次任务要求不改状态）。

## 复核（REV，2026-11-23）

`g2` 机械校验：9 个接口文档、25 条 ACC；`acc_map_test` 6 条负例；`AGENTS.md` 0.3 的
`deviation: g2-acc-mapping` 已删除；`g0/g2` 绿。


## 复核（REV，2026-11-23）

`g2` 已机械校验：9 个接口文档、25 条 ACC；`acc_map_test` 6 条负例；
`AGENTS.md` 0.3 的 `deviation: g2-acc-mapping` 已删除；`g0/g2` 绿。
