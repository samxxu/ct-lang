# PKG-12 · 契约 v1 的判据原文与文档缺口

| 项 | 值 |
| --- | --- |
| 模块 | packages（跨仓契约） |
| 定性 | 文档缺口（契约 v1 已立，部分判据原文未入库） |
| 严重度 | Medium |
| 锚点 | v0.79.0（2026-11-20） |
| 文件 | [ct-pkg-get-contract.md](../../docs/planning/ct-pkg-get-contract.md) §6.1、[D-014](../../docs/decisions/D-014.md) |
| 状态 | verified |
| 处置证据 | **verified（REV 复核，2026-11-22，HEAD `38cd4ae4`）** |

## 现象

契约 v1 已新增 §6.1 判据归属矩阵，但 PK-1…PK-13 / R1–R3 / S1–S5 的**原文归 index 仓**，
本仓只掌握 PK-1/2/5/8 的语义；矩阵里 PK-4/7/9/10/11/13 仍是 TBD，无法逐条判定归属。

## 期望

1. 从 `ct-pkg/index` 取回各判据原文（或链接到固定版本），逐条补进 §6.1；
2. 明确每条判据的归属：CT（离线只读）/ 包仓 / index CI；
3. 标出可在 v0-PH-83 迁入 CT 的离线候选（`dep` 全名、`requires` 可满足性、tag 一致性等）；
4. 与 [PKG-15](pkg-15-conformance-suite.md) 的用例编号对齐。

## 验收

- §6.1 不再有 TBD；
- 每条判据都能指到“原文位置 + 归属 + 本仓是否实现”；
- 与 index 仓确认过的版本号记录在契约修订记录里。

## 关联

- [D-014](../../docs/decisions/D-014.md)、[评估](../../docs/reviews/2026-11-20-pkg-contract-proposal-eval.md)
- [SH-80](../selfhost/sh80-pkg-check-criteria-narrow.md)（本仓只承诺 PK-1/2/5/8 的裁定）

## 证据（DEV，v0-PH-83 S83a，2026-11-21）

- **原文基线**：`ct-pkg/index` @ `0cdb132a179a9cfab5e339da9fec856ec4f29fcc`（`main`，2026-11-20）。
- 逐条核对结果：
  - PK-1 / PK-2 / PK-5 / PK-8：`tools/package-check.sh:15-18`（实现 `:77-276`）；
  - R1 / R2 / R3：`tools/package-check.sh:22-25`；S1–S5：`:28-32`；
  - **PK-3 / 4 / 6 / 7 / 9 / 10 / 11 / 12 / 13：该基线全部 `*.sh` + `*.md` 无原文**
    （`grep -rn 'PK-[0-9]'` 只命中上述 PK-1/2/5/8）。
- 契约 §6.1 已按该基线定稿为 v1.1：PK-1/2/5/8 归 CT，R/S 归 index CI，缺原文的编号
  保留但**不分配归属、不作为判据**；v0-PH-83 新增 IV-1…IV-7 归 CT（`ct index verify`）。
  矩阵不再有待补条目。
- 与 PKG-15 对齐：conformance 数据在 `test/conformance/pkg/v1/`，索引类别与 IV-1…IV-6
  同名；manifest 类别与 PK-1/2/5/8 一一对应（见该目录 README）。

## §复核（REV，2026-11-22，HEAD `38cd4ae4`）

本卡是文档验收，不依赖二进制；直接核对 `docs/planning/ct-pkg-get-contract.md` §6.1 与修订记录。

```console
$ grep -c 'TBD' docs/planning/ct-pkg-get-contract.md
0
$ awk '/^### 6.1/{f=1} /^## 7\./{f=0} f' docs/planning/ct-pkg-get-contract.md | grep -c '^| '
24
$ grep -n '0cdb132' docs/planning/ct-pkg-get-contract.md | head -3
341:> **原文基线**：`ct-pkg/index` @ `0cdb132a179a9cfab5e339da9fec856ec4f29fcc`（2026-11-20，`main`）。
351:| 判据 | 内容（原文摘要） | 原文位置（index@0cdb132） | 归属 | 本仓状态（v0-PH-83） |
446:| Q8 | PK/R/S 全量原文与逐条归属 | **已定（2026-11-21，v0-PH-83）**：§6.1 按 index@0cdb132 基线定稿；PK-1/2/5/8 归 CT，R/S 归 index CI，缺原文的 PK-3/4/6/7/9–13 编号保留但不作判据（PKG-12） |
```

逐条对照：

- §6.1 矩阵覆盖 PK-1/2/5/8、R1–R3、S1–S5，每行都有“原文位置（index@0cdb132）/ 归属 / 本仓状态”；
- PK-3/4/6/7/9–13 明写“无原文（编号保留）/ 未分配 / 不在 CT”，不是 TBD，也不冒充判据；
- IV-1…IV-7 单列 CT 侧状态，v0-PH-83 已实现；
- 修订记录 v1.1 记录基线版本、日期与“缺原文编号不分配”的口径，满足“版本号记录在契约修订记录”；
- 跨仓**书面确认**（谁确认、何时确认）不由本卡承担：由 [PKG-16](pkg-16-external-baseline-and-schedule.md)（`deferred`，触发：index 仓书面确认）承载，不阻塞本节文档缺口关闭；
- 与 [PKG-15](pkg-15-conformance-suite.md) 的类别对齐见其复核段（19 例全绿）。

结论：`verified`。
