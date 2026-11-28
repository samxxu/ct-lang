# LANG-31 · 常量键折叠：`p["x"]` → `p.x`（v1.2 S8a，可砍）

| 项 | 值 |
| --- | --- |
| 模块 | lang / selfhost（parser、Symbols、TIR/LIR 折叠） |
| 定性 | 能力增量（来稿 Indexable 的可落地切片 I1） |
| 严重度 | **Medium**（不影响既有程序；收益是静态 struct 的零开销下标） |
| 锚点 | `4b57567d`（2026-11-27） |
| 依据 | [RFC-0000 评估](../../docs/reviews/2026-11-27-indexable-rfc-evaluation.md) §3、[lang31-const-key-fold-construction](../../docs/design/lang31-const-key-fold-construction.md)、[D-028](../../docs/decisions/D-028.md) |
| 状态 | verified |
| 验收 | REQ 2026-11-28 通过（§7）；EDITOR 2026-11-28 签 verified（依据 §7 + D-031 §8） |
| 负责人 | ARCH（ADR 技术审定）；EDITOR（ADR 签收与状态）；DEV（实施）；REVIEW（复核）；REQ（排期与验收） |
| 交付窗口 | **v1.2 必做（所有者 2026-11-28 撤回 deferred）**：与 I2 一起随 1.2 交付；1.2.0 已提交但未打 tag，tag 推迟到本项与 I2 落地后 |
| 处置证据 | 施工卡已交 DEV（2026-11-27）：[lang31-const-key-fold-construction](../../docs/design/lang31-const-key-fold-construction.md)；前置 ADR 与 spec 新节。**2026-11-28 转回 `open`**：所有者裁定不再后推，随 [卡 §8 CR-V3-2](../../docs/phases/v1-PH-2/card.md#8-判据变更记录) 纳入 1.2；与 I2 共用 D-028 的下标解析表，但独立交付。 |

## 1 现象

`p["x"]` 对普通结构体是硬错（`type 'X' has no subscript: declare 'V get(K)' in impl X`），
而 `p.x` 是零开销字段访问。来稿的核心卖点就是把两者统一——**动态键走 `get`，编译期已知
的键走字段**。Ct 目前只支持前者。

## 2 目标（最小形态）

1. 字符串**字面量**键 + 非指针 struct 值接收者 + 字段可见 → `p["x"]` 折叠为 `p.x`；
2. 折叠后生成 C 中**没有 `get` 调用、没有临时量**；
3. 字段改名后原字面量键**编译失败**（候选里列出真实字段），保住静态检查；
4. 与既有 `get(char *)` 的解析规则**不冲突、不静默改行为**（见 §3 的优先级）。

## 3 边界

- 只做**读**形态；`p["x"] = v` 不在本条；
- 不做嵌套常量键（`p["a"]["b"]` 走两个字段？留待后续）、不做数组/切片折叠、不做接口值下标（I2）；
- 键必须是字面量；变量键一律走既有 `get` 解析；
- 字段可见性与普通 `p.x` 同判据（不可见字段不折叠）；
- 接收者可回溯到变量或字段链（与 D52-4 的写形态同判据），避免对临时量取址。

## 4 与既有协议的关系（必须先定）

同一类型若同时有字段 `x` 与 `get(char *)`：

- **推荐**：字面量键先查**字段**；命中即折叠；未命中再走 `get(char *)`；两者都命中时给
  **歧义诊断**（要求写 `p.x` 或 `p.get("x")`），不静默选择；
- 这样既有代码不受影响（既有 `get` 类型没有同名字段时的行为逐字节不变），新能力也可预测。

## 5 验收

| # | 判据 |
| --- | --- |
| 1 | 折叠后的生成 C 是 `recv.field`，无 `get` 调用、无 `__ct_*` 临时 |
| 2 | 未知字段负例：`p["nope"]` 硬错，诊断列出候选字段名 |
| 3 | 字段重命名负例：改名后原 `p["old"]` 编译失败（证明静态性未丢） |
| 4 | 字面量键 + `get(char *)` 并存时的歧义负例 |
| 5 | `check-goldens-ast` 25/25；`check-docs` 绿；改 `selfhost/**` 时 seed 两轮逐字节 |

## 6 关联

- [lang31-const-key-fold-construction](../../docs/design/lang31-const-key-fold-construction.md)（施工卡，DEV 入口）
- [RFC-0000 评估](../../docs/reviews/2026-11-27-indexable-rfc-evaluation.md)
- [REQ-INDEXFOLD-1](../../docs/planning/requirements-pool.md)
- [spec §4.64](../../docs/language-spec.md)（既有下标协议）

## 7 验收记录（REQ，2026-11-28）

实现提交：T1 `93b1bc2c`、T2 `0c10bd2d`、T4 `27becd9a`（spec §4.79 + glossary +
`examples/70_const_key_fold`）、T5 `1ede1dce`（seed 重生成）、探针重钉 `9e4e87e4`。
验收环境：从当前 `bootstrap/ct-ast` 重建 ct-ast（`ct-ast v1.2.0`）。

| 判据 | 结果 |
| --- | --- |
| E31-1 `p["x"]`/`p["y"]` 折叠为 `p.x`/`p.y`，LIR 与 `--ir=off` 逐字节一致，生成 C 无 `get(`、无 `__ct_*` | 通过 |
| E31-2 字段链 `h.p.x`、数组元素 `ps[0].x`、泛型实例 `g.v` 均折叠 | 通过 |
| E31-3 未命中字段的字面量键仍走 `X_get(&x, "a")`（`p52_read` 生成的 C 不变） | 通过 |
| E31-4 三条负例：未知字段 / 重命名字段 / 字段与 `get` 并存歧义，位置指向 `[`，仅 1 条诊断、不写产物 | 通过（`12:13`、`12:13`、`19:13`） |
| E31-5 常量键写形态不折叠，报只读下标诊断 | 通过（`11:6`） |
| E31-6 `Box<struct Point>` 内部字段不可达 | 通过（`8:14`） |
| `examples/70_const_key_fold` 运行输出 `7 9`，生成 C 无 `get`/临时量 | 通过 |
| `CT_C_BOUNDARY=allow check-goldens-ast` 25/25 | 通过 |
| `check-seed` 两轮逐字节（73 .c + 75 .h） | 通过 |
| `check-warnings` 622 ok / 0 failed | 通过 |
| `test/ir/run.sh` 15 checks、83 语料逐字节 | 通过 |

> 过程说明：实现先于 `D-031` 签收落地（DEV 2026-11-28，早于"签收前不改实现"的口径）；
> ADR 追签路径为 **ARCH 技术审定 → EDITOR 签收**（方案 a，前置见
> [s10 Q-12 注](../../docs/phases/v1-PH-2/s10-closeout.md#12-收口后队列2026-11-28)）。
> 本记录不经手 issue 状态词；`verified` 由 EDITOR 落。

**ARCH 技术审定（2026-11-28）：接受、附条件 C1–C4**（见 [D-031 §8](../../docs/decisions/D-031.md)）。
以下探针由 DEV 后补，不影响 EDITOR 按现证据签 `verified`：

| 条件 | 待补 | 现状 |
| --- | --- | --- |
| C1 | 非 place 接收者（`f()["x"]`）**不折叠**、保持 L52-1 文案的负例 | 现有探针只覆盖变量/字段链/数组/泛型实例正例 |
| C2 | `&p["x"]` → `&p.x` 正例；spec 写明折叠判定先于 L52-7 取址拒绝 | spec §4.79 已写「读位置可折叠」；探针待补 |
| C3 | 前向声明（`defined == 0`）字段表未知 → 不折叠、不报未知字段的探针 | 未覆盖 |
| C4 | 歧义只在 `get` **匹配且可见**时触发：private `get` / 参数类型不同两条负例 | 未覆盖 |

**R2（breaking）处置**：并存歧义由“可编译”变硬错，ARCH 判定可接受（25 条用户语料 + 83 条 IR
语料零命中）；发布前需写入迁移说明与 release note。
