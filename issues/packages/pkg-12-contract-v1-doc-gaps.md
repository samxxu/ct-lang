# PKG-12 · 契约 v1 的判据原文与文档缺口

| 项 | 值 |
| --- | --- |
| 模块 | packages（跨仓契约） |
| 定性 | 文档缺口（契约 v1 已立，部分判据原文未入库） |
| 严重度 | Medium |
| 锚点 | v0.79.0（2026-11-20） |
| 文件 | [ct-pkg-get-contract.md](../../docs/planning/ct-pkg-get-contract.md) §6.1、[D-014](../../docs/decisions/D-014.md) |
| 状态 | open |
| 处置证据 | **待办（REQ）** |

## 现象

契约 v1 已新增 §6.1 判据归属矩阵，但 PK-1…PK-13 / R1–R3 / S1–S5 的**原文归 index 仓**，
本仓只掌握 PK-1/2/5/8 的语义；矩阵里 PK-4/7/9/10/11/13 仍是 TBD，无法逐条判定归属。

## 期望

1. 从 `ct-pkg/index` 取回各判据原文（或链接到固定版本），逐条补进 §6.1；
2. 明确每条判据的归属：CT（离线只读）/ 包仓 / index CI；
3. 标出可在 PH-83 迁入 CT 的离线候选（`dep` 全名、`requires` 可满足性、tag 一致性等）；
4. 与 [PKG-15](pkg-15-conformance-suite.md) 的用例编号对齐。

## 验收

- §6.1 不再有 TBD；
- 每条判据都能指到“原文位置 + 归属 + 本仓是否实现”；
- 与 index 仓确认过的版本号记录在契约修订记录里。

## 关联

- [D-014](../../docs/decisions/D-014.md)、[评估](../../docs/reviews/2026-11-20-pkg-contract-proposal-eval.md)
- [SH-80](../selfhost/sh80-pkg-check-criteria-narrow.md)（本仓只承诺 PK-1/2/5/8 的裁定）

## 证据（DEV，PH-83 S83a，2026-11-21）

- **原文基线**：`ct-pkg/index` @ `0cdb132a179a9cfab5e339da9fec856ec4f29fcc`（`main`，2026-11-20）。
- 逐条核对结果：
  - PK-1 / PK-2 / PK-5 / PK-8：`tools/package-check.sh:15-18`（实现 `:77-276`）；
  - R1 / R2 / R3：`tools/package-check.sh:22-25`；S1–S5：`:28-32`；
  - **PK-3 / 4 / 6 / 7 / 9 / 10 / 11 / 12 / 13：该基线全部 `*.sh` + `*.md` 无原文**
    （`grep -rn 'PK-[0-9]'` 只命中上述 PK-1/2/5/8）。
- 契约 §6.1 已按该基线定稿为 v1.1：PK-1/2/5/8 归 CT，R/S 归 index CI，缺原文的编号
  保留但**不分配归属、不作为判据**；PH-83 新增 IV-1…IV-7 归 CT（`ct index verify`）。
  矩阵不再有待补条目。
- 与 PKG-15 对齐：conformance 数据在 `test/conformance/pkg/v1/`，索引类别与 IV-1…IV-6
  同名；manifest 类别与 PK-1/2/5/8 一一对应（见该目录 README）。
