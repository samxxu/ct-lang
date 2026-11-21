# PKG-21 · ct-pkg index 重构裁决落地（总跟踪）

| 项 | 值 |
| --- | --- |
| 模块 | packages（跨仓裁决与跟踪） |
| 定性 | **裁决跟踪**（不是新特性；把三项裁定落成一个可验收的总项） |
| 严重度 | Medium |
| 锚点 | v0.84.1（2026-11-21） |
| 依据 | 用户 2026-11-21 裁决；[D-014](../decisions/D-014.md)；[契约 v1](../planning/ct-pkg-get-contract.md)；[消费侧对齐清单](../planning/ct-pkg-index-alignment.md) |
| 状态 | open |
| 处置证据 | **accepted（2026-11-21 用户裁定）** |

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
