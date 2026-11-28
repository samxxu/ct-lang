# LANG-31 · 常量键折叠：`p["x"]` → `p.x`（v1.2 S8a，可砍）

| 项 | 值 |
| --- | --- |
| 模块 | lang / selfhost（parser、Symbols、TIR/LIR 折叠） |
| 定性 | 能力增量（来稿 Indexable 的可落地切片 I1） |
| 严重度 | **Medium**（不影响既有程序；收益是静态 struct 的零开销下标） |
| 锚点 | `4b57567d`（2026-11-27） |
| 依据 | [RFC-0000 评估](../../docs/reviews/2026-11-27-indexable-rfc-evaluation.md) §3、[lang31-const-key-fold-construction](../../docs/design/lang31-const-key-fold-construction.md)、[D-028](../../docs/decisions/D-028.md) |
| 状态 | open |
| 负责人 | DEV（实施）；REVIEW（ADR 签收）；REQ（验收） |
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
