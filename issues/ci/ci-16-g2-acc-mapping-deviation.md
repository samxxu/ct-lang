---
id: CI-16
title: "G2 的 ACC-* 映射缺失：先登记 deviation，v1.1 前补机械校验"
status: deferred
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
