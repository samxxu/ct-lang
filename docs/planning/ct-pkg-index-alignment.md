# ct-pkg index 消费侧接口对齐清单（approved）

| 项 | 值 |
| --- | --- |
| 状态 | **approved**（2026-11-21 用户裁定：A/B/C 口径；A1+A2 批准开工；B/C 四行锁死为门禁） |
| 日期 | 2026-11-21 |
| 依据 | 用户 2026-11-21 裁决；[D-014](../decisions/D-014.md)；[契约 v1](ct-pkg-get-contract.md)；[PKG-18](../../issues/packages/pkg-18-native-ct-index-refresh.md) |
| 范围 | 消费侧 `ct get` / `ct index verify` / `ct install` + `ct.lock`；**不碰** `ct-pkg/index` 仓 |
| 冻结口径 | 主线只收 bugfix、本清单 approved 条目与重写切片；特性一律 v1.1 |
| 工单 | 总跟踪 [PKG-21](../../issues/packages/pkg-21-ct-pkg-index-refactor-ruling.md)；A1 → [PKG-19](../../issues/packages/pkg-19-get-index-field-count.md)；A2 → [PKG-20](../../issues/packages/pkg-20-get-index-row-identity.md) |

## 0. 裁决落点

| # | 事项 | 定性 | 落点 |
| --- | --- | --- | --- |
| ① | `package.sh` 的 `verify_row` 找不到 `ct` 时 `warn` 并成功，可能推送未回放行（违反 I10） | **bug**，但在 index 仓 | 已另派单修复；本仓不动 |
| ② | 原生 `ct index refresh` 缺失 | **特性**，不是 bug | [PKG-18](../../issues/packages/pkg-18-native-ct-index-refresh.md)，v1.1；冻结期不实现 |
| ③ | 消费侧「三处接口对齐」 | 逐条分类 | 本文件 §3 六行；只有 bugfix 行可进冻结期 |

## 1. 「三处」的口径（待评审确认）

按消费侧实际读/校验/落库的三个接触点划分：

- **A 读取**：`ct get` 的索引解析与选中行处理（`pkg_index_lookup`）；
- **B 校验**：`ct index verify` 的全文件结构校验（`pkg_index_verify`）；
- **C 落库与锁**：`pkg_store_commit` / `pkg_verify_lock` 的身份字段与 `ct.lock` v2。

> 如果需求方说的「三处」是另外三条（例如 index 行 / 摘要 / 身份分三处，而不是按命令分），
> 请在本节直接改口径；六行表按新口径重排后再评审，未确认前不写代码。

## 2. 分类规则

- **bugfix**：行为与**已成文契约**不一致，且修正不引入新格式/新字段/新命令；可进冻结期。
- **特性**：契约外的新行为（新命令、新字段、新校验时机、新输出），一律 v1.1；
  原生 refresh 本身就是特性，见 PKG-18。
- 已对齐但需要锁死的条目，也归 bugfix 行（零行为改动，只补 conformance/门禁）；
  不为“已经正确”单独造特性。

## 3. 六行清单（旧接口 / 新接口 / 兼容断言）

| ID | 处 | 旧接口 | 新接口 | 兼容断言 | 定性 |
| --- | --- | --- | --- | --- | --- |
| A1 | A 读取 | `pkg_index_lookup` 接受 `ntok >= 5`，`ntok > 6` 的多余列静默忽略 | 恰好六字段；五字段按 legacy 硬错；`>6` 与 `verify` 同判为 `field-count` | 五字段文案保持 `index row ... is legacy (five fields)`；七字段在 `ct get` 与 `ct index verify` 都失败 | **bugfix** |
| A2 | A 读取 | 只按 `name` / `publisher` 匹配；不校验选中行的 publisher 字符集与 `tag == 'v<version>'` | 对**选中的六字段行**执行与 `ct index verify` 相同的身份与 tag 校验 | 选中行非法时 `ct get` 硬错且不改 store/lock；未选中坏行不阻塞 `ct get`（与 verify 的全文件扫描区分） | **bugfix** |
| B1 | B 校验 | `ct index verify` 已扫描全文件：字段数、五字段、publisher、version、tag、digest、重复 | 保持现状，作为 A1/A2 的对齐基准与 conformance oracle | 退出码 0/1/2、行号与错误类别与契约 §4.4 一致；`--json` 稳定 | **bugfix**（已对齐，锁死） |
| B2 | B 校验 | digest 只接受 `sha256:<64 lowercase hex>`；16-hex/大写硬错 | 同左；与 index 行、`ct.lock` 使用同一拼写 | 同一包树在 shell 与 Ct 生成的摘要逐字节一致；三组 digest 向量通过 | **bugfix**（已对齐，锁死） |
| C1 | C 落库 | 读取 `ct.pkg` 后要求 `publisher`（非空、非 `local`）与 `ns-root`（相对、存在、无 `..`）；失败在写 store/lock 前 | 同左；错误文案与 PK-2/PK-5 一致 | 缺 publisher / `local` / 非法 ns-root 时不写 store、不写 lock | **bugfix**（已对齐，锁死） |
| C2 | C 落库 | `ct.lock` 只接受 v2（`# ct-lock 2`）；首字段 `<publisher>/<name>`；digest 与索引行同拼写 | 同左；v1 硬错并提示 `run 'ct migrate'` | v1 lock 不被部分改写；未重解的其它行保留；摘要拼写不变 | **bugfix**（已对齐，锁死） |

**当前唯一预期需要改代码的是 A1 / A2。** B1 / B2 / C1 / C2 已与契约一致，
保留在清单里是为了每次合入都跑同一套兼容断言，防止重构把已对齐项改坏。

## 4. 逐行证据

### A1 字段数

- 现实现：`pkg_index_lookup` 把最多 8 个 token 收进 `tok`，`legacy = (ntok < 6)`，
  之后只用前 6 个；`>6` 没有报错（[Pkg.h.ct:2412-2440](../../selfhost/ct-ast/tool/pkg/Pkg.h.ct#L2412-L2440)）。
- 对齐基准：`pkg_index_verify` 对 `ntok == 5` 报 legacy、`ntok != 6` 报 field-count
  （[Pkg.h.ct:2666-2679](../../selfhost/ct-ast/tool/pkg/Pkg.h.ct#L2666-L2679)）。
- 契约：索引行六字段（[契约 §3.2](ct-pkg-get-contract.md#32-索引行)）；五字段按行硬错（D-014 第 5 条）。
- 实测（v0.84.1）：七字段行 `ct index verify` 报 `field-count`；`ct get --index` 仍进入
  `git clone`（没有先报字段数）——两者判定不一致。

### A2 选中行身份

- 现实现：lookup 只做 `name`/`publisher` 匹配与 digest 拼写检查
  （[Pkg.h.ct:2441-2471](../../selfhost/ct-ast/tool/pkg/Pkg.h.ct#L2441-L2471)）；
  没有校验 `publisher` 字符集，也没有校验 `tag == 'v' + version`。
- 对齐基准：verify 校验 `index_name_ok` / publisher / version / tag / digest
  （[Pkg.h.ct:2680-2715](../../selfhost/ct-ast/tool/pkg/Pkg.h.ct#L2680-L2715)）。
- 契约：IV-1…IV-6（[契约 §4.4](ct-pkg-get-contract.md#44-ct-index-verify只读ct-lang-负责)）。
- 实测（v0.84.1）：`tag = v9.9.9` 与 `publisher = local` 的行，`ct index verify` 分别报
  `tag-version` / `identity`；`ct get --index` 仍进入 `git clone`。两者判定不一致。
- 边界：只校验**被选中**的行；要求 `ct get` 扫描整份文件是契约外新行为，不在本行。

### B1 / B2 校验与摘要

- `ct index verify` 全文件扫描、`--json`、退出码见 [Pkg.h.ct:2529-2750](../../selfhost/ct-ast/tool/pkg/Pkg.h.ct#L2529-L2750)；
- digest 拼写只接受 `sha256:<64 lowercase>`（[Pkg.h.ct:399-410](../../selfhost/ct-ast/tool/pkg/Pkg.h.ct#L399-L410)）；
- 契约：I6 / §3.3 digest 伪代码与三向量、§4.4 verify。

### C1 / C2 身份与 lock

- `ct.pkg` 的 `publisher` / `ns-root` 校验与 `local` 拒绝见
  [Pkg.h.ct:1923-1945](../../selfhost/ct-ast/tool/pkg/Pkg.h.ct#L1923-L1945)；
- lock v1 拒绝与 v2 header 见 [Pkg.h.ct:1504-1512](../../selfhost/ct-ast/tool/pkg/Pkg.h.ct#L1504-L1512)、
  [Pkg.h.ct:1554](../../selfhost/ct-ast/tool/pkg/Pkg.h.ct#L1554)；
- 契约：I5、§4.1 发布端硬接口 3/4（[契约 §4.1](ct-pkg-get-contract.md#41-ct-get)）。

## 5. 合入门禁（每条 bugfix 一行一合入）

每合入一条，跑同一套双 job：

```sh
# job 1: host（macOS）
ct get --index <fixture>/index <publisher>/<name>@<version>
ct index verify <fixture>/index
ct install
<run the package's expected output and diff>

# job 2: Linux x64（容器）
# 同一 fixture、同一命令、同一期望输出
```

- fixture 三件套：官方 `ct/std@0.19.0` 六字段行、第三方 fixture（PKG-17）、
  五字段 legacy 负例；
- `ct index verify` / `ct install` 零网络、零子进程；`ct get` 只用固定 commit/tag；
- 失败即回滚该行，不夹带下一行；不顺手改 index 仓脚本。

### 5.1 施工切片（评审通过后）

1. **A1**：[PKG-19](../../issues/packages/pkg-19-get-index-field-count.md)：`pkg_index_lookup` 对齐“恰好六字段”，补七字段负例；
2. **A2**：[PKG-20](../../issues/packages/pkg-20-get-index-row-identity.md)：选中行补 name/publisher/version/tag 校验，补 `local` / 错 tag 负例；
3. **B/C 锁死**：B1/B2/C1/C2 只加 conformance 与门禁断言，不改行为。

每片独立提交、独立回滚；一片未过双 job 门禁，不合入下一片。

## 6. 冻结纪律

- 只收：bugfix、本清单 approved 条目、重写切片；**不收**新特性；
- 不新增索引字段、不改六字段形态、不改 digest 算法；
- 不在本仓实现 `ct index refresh`（PKG-18，v1.1）；
- 若某行实施时发现需要契约外新行为：**停止该行**，改判为特性并转 PKG-18 / v1.1，
  不在冻结期“顺手做了”。

## 7. 评审与下一步

- **2026-11-21 用户裁定**：三处按 A 读取 / B 校验 / C 落库；A1+A2 批准开工；
  B1/B2/C1/C2 保留为门禁，不做行为改动。
- REQ 已开单：A1 → [PKG-19](../../issues/packages/pkg-19-get-index-field-count.md)，
  A2 → [PKG-20](../../issues/packages/pkg-20-get-index-row-identity.md)。
- DEV 按 §5.1 顺序施工：A1 一提交、A2 一提交；每片过双 job 门禁后才开下一片。
- 清单与口径若需变更，先改本文件并重新评审，不在施工中夹带。

## 8. 已确认

- 「三处」= A 读取 / B 校验 / C 落库（2026-11-21 用户裁定）；
- A2 只校验**被选中**的行，不做 `ct get` 全文件预检（后者是契约外新行为，转 v1.1）；
- B1/B2/C1/C2 保留在清单里作为每次合入的兼容门禁，不做行为改动。
