# 评估：外部《CT 语言组 —— 包管理契约与原生实现》

| 项 | 值 |
| --- | --- |
| 评估对象 | 外部提案《提示词：CT 语言组 —— 包管理契约与原生实现》（2026-11-20 收，仓外文件） |
| 评估方 | REQ（主张人） |
| 日期 | 2026-11-20 |
| 结论 | **方向受理、整包不受理**：拆成契约/测试/分发三轨；七项异议已由用户逐条裁定，见 [D-014](../decisions/D-014.md) |
| 关联 | [D-010](../decisions/D-010.md)、[D-014](../decisions/D-014.md)、[契约 v1](../planning/ct-pkg-get-contract.md)、[ct-pkg](../ct-pkg.md)、[ct-pkg-index](../ct-pkg-index.md)、[battle index-pkg-1](../../battle/index-pkg-1/verdict.md)、[SH-80](../../issues/selfhost/sh80-pkg-check-criteria-narrow.md) |

## 1. 提案主张

1. 由 CT 语言组发布《包管理契约 v1》，含 `ct.pkg`、索引行、digest、tag、spec 语法、MVS、多 registry；
2. 把发布、校验、索引生成收进 CT：`ct pkg check` 覆盖全部 PK/R/S、`ct pkg release`、
   `ct index build|refresh|verify`；
3. 随契约发布 conformance 测试套件；
4. 发布单文件、免依赖的 Linux x64 二进制（tar.gz + sha256、稳定 URL、版本节奏）；
5. 建仓库等宿主平台操作不进 CT。

## 2. 与现状核对

| 提案项 | 现状 | 结论 |
| --- | --- | --- |
| 契约 v1 | [ct-pkg-get-contract.md](../planning/ct-pkg-get-contract.md) 已是两端规范文本（I1–I12、制品、命令、校验矩阵、归属） | 约七成已存在，应补齐而非另立文档 |
| 索引六字段 / 五字段兼容 | [ct-pkg-index.md](../ct-pkg-index.md) 已写；契约 §3.2 已写 | 已覆盖，需按 D-014 第 5 条改旧行行为 |
| digest 算法 | 契约 I6 有文字定义 | **缺伪代码与测试向量**，本轮补齐 |
| `ct pkg check` | 只承诺 **PK-1/2/5/8**（[D-010](../decisions/D-010.md)、[SH-80](../../issues/selfhost/sh80-pkg-check-criteria-narrow.md)、[post-58 计划](../planning/post-58-phase-sequence.md)） | 提案“覆盖全部”是需求变更，按 D-014 第 2 条先做归属矩阵 |
| 发布/索引脚本 | 归 `ct-pkg/index`；[ct-pkg](../ct-pkg.md) §5 明确不进 `ct` 二进制 | 提案第 2 节推翻现状，按 D-014 第 1 条维持 B′ |
| CI 二进制 | 当前 `install.sh` 拉源码构建；无 Linux x64 产物流水线 | 真缺口，按 D-014 第 6 条做最小产物 |

### 2.1 事实性修正

- 提案的 “PK-1~S5” 不是有效编号：现行是 **PK-1…PK-13 + R1–R3 + S1–S5**；
  PK 原文归 index 仓，本仓只引用、不重定义。
- 索引行是 **6 字段**，`ct.lock` v2 是 **7 字段**；两者是不同制品，契约 v1 已并列写明。
- “20+ 个包”“index 仓脚本现状”在本仓不可核实，需提案方提供基线（见 §5）。

## 3. 七项裁定（用户 2026-11-20 确认）

| # | 议题 | 裁定 | 主要理由 |
| --- | --- | --- | --- |
| 1 | 发布/索引生成是否收进 `ct` | **维持 B′**，只加只读 `ct index verify` | 写仓库凭据不进通用二进制；发布留在持凭据的 CI |
| 2 | `ct pkg check` 判据范围 | **先做 PK/R/S 归属矩阵**，再并入离线可判定项 | 全量 PK 需要网络/包仓上下文，破离线边界 |
| 3 | 契约 v1 落点 | **扩展现有契约**，不建 `contract-v1.md` | 避免第二份规范；D-010 第 7 条已指定现有文本 |
| 4 | 多 registry / 多索引 | **单索引**，写清 `--index` > `CT_INDEX` > 默认路径 | 与实现一致；多源由调用方合并索引文件 |
| 5 | 五字段旧索引行 | **按行立即硬错**，其余六字段行照常可用 | 需求方选择立即收敛；推翻契约 I12 |
| 6 | CI 分发 | **每 MINOR 发 linux-x64 tar.gz + sha256，稳定 URL** | 满足 index CI 钉版本；先不做全矩阵 |
| 7 | 排期与归属 | 契约/向量/矩阵立即做；`ct index verify` 与产物开 **PH-83**（PH-82 后、v1.0 前）；跨仓废弃由 index 仓确认 | 不打断 PH-80→82→v1.0 |

## 4. 不受理 / 降级的部分

- **不受理** `ct pkg release`、`ct index build|refresh`：与 D-010 §6、`index-pkg-1` 冲突，
  且把发布凭据带进通用二进制；
- **降级** “`ct pkg check` 覆盖全部 PK/R/S”：先出归属矩阵，本仓只接收离线可判定项；
- **降级** “index 仓只保留纯数据”：跨仓改造由 index 仓自行确认，本仓只提供契约与二进制；
- **不新建** `docs/contract-v1.md`：契约 v1 进入现有 `ct-pkg-get-contract.md`。

## 5. 风险与发布前置

| 风险 | 说明 | 缓解 |
| --- | --- | --- |
| 硬错发布顺序 | 五字段行按行硬错一旦随版本发出，`ct/hal` 等存量包立即不可安装 | index 仓先清零五字段行，再发硬错版本；或先发默认关闭的硬错逻辑 |
| 跨仓漂移 | 契约改了、index CI 不跟 | 契约 v1 写“发布前置 + 回放校验”；跨仓时间表由 index 仓确认 |
| 二进制供给 | 产物缺失或不可复现会让 index CI 卡住 | 固定构建环境、发 sha256、URL 规则写死 |
| 外部事实 | “20+ 包”、脚本现状未核实 | 提案方补基线，否则只按本仓可核实部分受理 |

## 6. 后续交付

| 交付 | 归属 | 落点 |
| --- | --- | --- |
| 契约 v1（digest 向量、spec 语法、单索引、MVS、归属矩阵、旧行硬错） | REQ | [契约](../planning/ct-pkg-get-contract.md)，本轮 |
| 评估与裁定记录 | REQ | 本文 + [D-014](../decisions/D-014.md)，本轮 |
| 契约缺口跟踪 | REQ | [PKG-12](../../issues/packages/pkg-12-contract-v1-doc-gaps.md) |
| 五字段按行硬错 + 发布前置 | REQ/DEV | [PKG-13](../../issues/packages/pkg-13-legacy-five-field-row-hard-error.md) |
| `ct index verify` + Linux x64 产物（PH-83） | DEV | [PKG-14](../../issues/packages/pkg-14-ph83-index-verify-and-binary.md) |
| conformance 数据 + runner | REQ/DEV | [PKG-15](../../issues/packages/pkg-15-conformance-suite.md) |
| 外部基线与跨仓时间表 | REQ | [PKG-16](../../issues/packages/pkg-16-external-baseline-and-schedule.md) |

## 7. 待提案方补充

- index 仓脚本清单与各判据原文（PK-1…13 / R1–R3 / S1–S5）；
- “20+ 个包”的清单与当前索引字段分布；
- 五字段旧行清零的时间表；
- 宿主写操作（push tag、建仓库）的凭据模型与最小权限；
- 契约条款的验收方式（除 conformance 外的跨仓验收）。
