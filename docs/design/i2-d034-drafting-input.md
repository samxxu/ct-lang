# D-034 起草输入包（供 ARCH）

> 性质：**设计输入**，不是 ADR 草案、不是签收记录。REQ 编，2026-11-28。
> 用法：ARCH 按本包在 `docs/decisions/D-034.md` 起草并署名；EDITOR 按
> [AGENTS §0.7](../../AGENTS.md#07-主编签收项目加严t-8) 签收；REQ 之后排期。
> **不代笔、不代签**：本包只把已裁定项、待选项与验收映射摆齐，技术判断与条文由 ARCH 落。

## 1 已由所有者裁定、不得在 D-034 中改动

| # | 口径 |
| --- | --- |
| 1 | 单 trait，无 `Indexable`、无 trait 继承（Ct 无继承） |
| 2 | 标记写在方法上：`Str get(Str k) index;`；`index` 是**上下文修饰词**，其它位置仍是普通标识符 |
| 3 | 不新增 vtable 槽；`index` 只是给已有 `get` / `set` 槽加“可作为 `[]`”的属性 |
| 4 | 两阶段：阶段一只读（`E-V3-9e`），阶段二写入（`E-V3-9f`），同属 1.2 |
| 5 | 不承诺 vtable 槽 ABI，只保证同一次构建内一致；语言稳定后再统一发布 ABI 标准 |
| 6 | I1（常量键折叠）只管 struct + 字面量；接口值下标不受 I1 影响 |

## 2 ARCH 需要在 D-034 中钉死的决定

| # | 决定 | 选项 / 建议 | 影响面 |
| --- | --- | --- | --- |
| D1 | **D-028 边界**：具体类型（非接口值）是否也能用 trait 里标 `index` 的 `get` | (i) 保持分裂：具体类型只认固有 impl；接口值只认 trait 的 `index` / (ii) 统一：具体类型先找固有 `get`，没有再找 trait 的 `index get` | 选 (ii) 要扩 D-028 并补负例；选 (i) 与现状一致、风险最小 |
| D2 | **标记位置与词法**：`index` 只允许出现在 trait 方法签名的 `)` 之后、`;` 之前；`impl` 侧重复写 → 硬错 | 按 Q2 裁定固定 | 词法/解析、既有 `index` 标识符零回归 |
| D3 | **接口值解析**：键按实参静态类型匹配；多个 `index get` 按键分派；未标 `index` 的 `get` 不参与 `[]` | 与 D-028 的“方法名 + 参数个数 + 实参静态类型”同源 | 解析表共用，I1 的 `T1` 先落 |
| D4 | **阶段一对写形态的处理**：`o[k] = v` 在阶段一必须被拒 | 建议专文硬错，与“未声明”区分；文案见 §3 | `E-V3-9e` 负例 |
| D5 | **阶段二只读实现的语义**：`set` 缺失但被写入 | 三选一：空实现 / 运行期报错 / 不允许标注 `set index` 的组合 | 决定 `E-V3-9f` 负例与所有权规则 |
| D6 | **阶段二值的所有权**：`o[k] = v` 的 `v` 是复制还是借用 | 建议按签名决定（`V` 值 = 复制；`V *` = 视图），与 D-013 一致 | 借用检查 / ASAN 负例 |
| D7 | **`set` 的返回类型**：是否只允许 `void` | 建议阶段二只允许 `void set(K, V) index`；`Result` 形态留待后续 | 失败语义不进入本次 |
| D8 | **重复标记**：同一 trait 内同键类型的 `index get` / `index set` 重复 | 建议硬错（与 D-028 重载去歧义一致） | 诊断负例 |
| D9 | **跨单元标记保留**：`.h.ct` 的 `pub trait` 必须把 `index` 带进公开头；impl 在他单元、调用在第三单元 | 只要求同一次构建内一致（Q4） | I2-3 验收 |
| D10 | **ABI 措辞**：写清“不新增槽、不承诺槽位跨版本” | 按 Q4 裁定固定 | 实现与发布说明 |

## 3 诊断文案（建议，ARCH 可改；改后以 D-034 为准）

| 场景 | 建议文案 |
| --- | --- |
| trait 未标 `index` | `trait 'T' declares no indexed get; 'o[k]' is not available` |
| 键类型不匹配 | `no indexed 'get' matches key type 'K': candidates are 'Str', 'int'` |
| `impl` 侧重复写标记 | `the 'index' marker belongs to the trait declaration, not the impl` |
| 阶段一对写形态 | `interface subscript is read-only in this phase; declare 'void set(K, V) index' (stage 2)` |
| 重复标记 | `trait 'T' marks more than one 'get(K) index' for key type 'K'` |

## 4 与既有材料的对应关系

| 材料 | 提供什么 | 不要重复什么 |
| --- | --- | --- |
| [RFC 评估 §3.1/§3.1.1](../reviews/2026-11-27-indexable-rfc-evaluation.md) | 四问裁定、样例写法、D-028 (i)/(ii) 边界 | 不重开已裁定的四问 |
| [I2-C1](i2-interface-subscript-construction.md) §1/§3 | 施工切片 I2-1…I2-5、每片判据 | 不在 D-034 里排期 |
| [I2-C1](i2-interface-subscript-construction.md) §10 | 验收清单 A1–A9 / B1–B5 | 不在 D-034 里复述验收步骤 |
| [D-028](../decisions/D-028.md) | 固有 `get` / `set` 的匹配规则 | 不改变 D-028 已发布行为（除非选 D1=(ii)） |
| [D-013](../decisions/D-013.md) | 字符串/值的所有权口径 | 不另立所有权模型 |

## 5 ARCH 起草时填这张表（D-034 正文用）

| 项 | 结论 | 理由 |
| --- | --- | --- |
| D1 `D-028` 边界 | (i) / (ii) | |
| D2 标记位置与词法 | | |
| D3 接口值解析 | | |
| D4 阶段一写形态 | | |
| D5 阶段二只读实现 | | |
| D6 写入值所有权 | | |
| D7 `set` 返回类型 | | |
| D8 重复标记 | | |
| D9 跨单元保留 | | |
| D10 ABI 措辞 | | |
| 诊断文案是否采用 §3 | 采用 / 修改（列出） | |

## 6 交付与后续

1. ARCH 在 `docs/decisions/D-034.md` 起草（状态 `proposed`），署名 ARCH；
2. EDITOR 按 `AGENTS §0.7` 签收（非作者席位）；
3. REQ 把 `D-034` 合入后更新 `s10` Q-8 状态并启动 I2-1（`E-V3-9e`）；
4. 若 ARCH 选 D1=(ii)，D-034 必须同时给出**扩展 D-028 的负例清单**，否则按 (i) 执行。

## 7 关联

- [D-028](../decisions/D-028.md)、[D-013](../decisions/D-013.md)
- [RFC 评估](../reviews/2026-11-27-indexable-rfc-evaluation.md)（§3.1 裁定、§3.1.1 样例）
- [I2-C1](i2-interface-subscript-construction.md)（切片、验收、风险）
- [s10 队列 Q-8](../phases/v1-PH-2/s10-closeout.md#12-收口后队列2026-11-28)
