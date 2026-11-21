# PKG-21 · ct-pkg index 重构裁决落地（总跟踪）

| 项 | 值 |
| --- | --- |
| 模块 | packages（跨仓裁决与跟踪） |
| 定性 | **裁决跟踪**（不是新特性；把三项裁定落成一个可验收的总项） |
| 严重度 | Medium |
| 锚点 | v0.84.1（2026-11-21） |
| 依据 | 用户 2026-11-21 裁决；[D-014](../decisions/D-014.md)；[契约 v1](../planning/ct-pkg-get-contract.md)；[消费侧对齐清单](../planning/ct-pkg-index-alignment.md) |
| 状态 | deferred |
| 处置证据 | **deferred（REQ，2026-11-22；触发：PKG-19/20 合入 + index 仓工单可定位）** |

## 裁决

| # | 事项 | 定性 | 落点 |
| --- | --- | --- | --- |
| ① | `package.sh` 的 `verify_row` 找不到 `ct` 时 `warn` 并成功（可能推送未回放行，违反 I10） | **bug**，在 index 仓 | **index 仓另派单修复**；本仓不改 |
| ② | 原生 `ct index refresh` 缺失 | **特性**，不是 bug | [PKG-18](pkg-18-native-ct-index-refresh.md)，v1.1；冻结期不实现 |
| ③ | 消费侧「三处接口对齐」 | 逐条分类 | [对齐清单](../planning/ct-pkg-index-alignment.md)：A1 → [PKG-19](pkg-19-get-index-field-count.md)，A2 → [PKG-20](pkg-20-get-index-row-identity.md)；B/C 四行锁死为门禁 |

## 口径

- 「三处」= **A 读取**（`ct get`）/ **B 校验**（`ct index verify`）/ **C 落库**（`ct install` + `ct.lock`）；
- 对齐已成文契约的算 **bugfix**，可进冻结期；契约外新行为算 **特性**，推 v1.1；
- A1/A2 已批准开工，各一提交；B1/B2/C1/C2 不改行为，只作为兼容门禁。

## 冻结纪律

- 主线只收 bugfix、本清单 approved 条目、重写切片；
- 不在冻结期实现 `ct index refresh`（PKG-18）；
- 不改索引六字段形态、digest 算法、`ct.lock` v2；
- 若实施中发现需要契约外新行为：停止该行，改判特性并转 PKG-18 / v1.1。

## 验收

| ID | 断言 |
| --- | --- |
| PKG21-1 | ① 的外部修复单可定位（index 仓工单/链接），本仓无残留改动 |
| PKG21-2 | ② PKG-18 已登记 v1.1，冻结窗口内零实现提交 |
| PKG21-3 | ③ A1/A2 各一提交，双 job 门禁绿；B/C 四行兼容断言绿 |
| PKG21-4 | 以上三项均可独立回滚，互不夹带 |

## 关联

- [PKG-18](pkg-18-native-ct-index-refresh.md)（v1.1 特性）
- [PKG-19](pkg-19-get-index-field-count.md)（A1）
- [PKG-20](pkg-20-get-index-row-identity.md)（A2）
- [消费侧对齐清单](../planning/ct-pkg-index-alignment.md)

## §复核与处置（REV，2026-11-22，HEAD `38cd4ae4`）

逐条对照本卡验收：

| ID | 断言 | 复核结果 |
| --- | --- | --- |
| PKG21-1 | ① 的外部修复单可定位，本仓无残留改动 | **未满足**：仓内只有“已另派单”的口径（对齐清单 §0），没有 index 仓工单链接/编号；本仓无 ① 的代码改动（正确） |
| PKG21-2 | ② PKG-18 已登记 v1.1，冻结窗口内零实现提交 | **满足**：PKG-18 `deferred`（目标 v1.1）；`grep -rn 'index refresh' selfhost/ct-ast` 命中 0 |
| PKG21-3 | ③ A1/A2 各一提交，双 job 门禁绿；B/C 兼容断言绿 | **未满足**：PKG-19/PKG-20 仍 `open`，`git log --grep=PKG-19/20` 只有立项文档提交，无 `test` 红 + 实现提交 |
| PKG21-4 | 三项可独立回滚、互不夹带 | 不适用（前置未落地） |

```console
$ grep -rn 'index refresh\|index_refresh' selfhost/ct-ast | wc -l
       0
$ git log --oneline --all --grep='PKG-19' | wc -l
       2      # 均为 8e81762d / 996fdddd 立项文档，无实现
$ git log --oneline --all --grep='PKG-20' | wc -l
       2      # 同上
```

处置：`deferred`。①③ 的验收都依赖外部工单与 A1/A2 两个 bugfix 落地，本卡不重开裁决。
触发条件：PKG-19、PKG-20 各以 `test(...) 红` + 实现提交合入，且 index 仓工单/链接可定位后，
本卡按 PKG21-1…4 逐条复核转 `verified`。owner：REQ（协调 + 总复核）；P2；登记日期
2026-11-22。冻结纪律不变：不实现 `ct index refresh`，不改六字段/摘要/`ct.lock` v2。
