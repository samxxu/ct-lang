# 施工卡：常量键折叠（LANG-31 / REQ-INDEXFOLD-1）

| 项 | 值 |
| --- | --- |
| 编号 | `LANG-31-C1` |
| 目标 | `p["x"]` 在编译期折叠为 `p.x`，保留字段改名的编译期检查 |
| 负责人 | **DEV**（ADR 起草、实现、自测）；**REVIEW** 复核 + ADR 签收；**REQ** 验收 |
| 前置 | ADR（拟 `D-031`，`D-030` 已被 LANG-30 预留）；spec 新节（拟 §4.79，写前核 LANG-30 是否先占 §4.78） |
| 交付窗口 | **v1.2 的 S8a，可砍**：排在 S8（IR-2）之后；S8 收口后窗口不足即整体 deferred，S10 记录 |
| 状态 | **待开工（ready for DEV）** |

> **为什么排在 S8 之后**：S8 把 emitter 改成纯打印器。若先做，折叠要在 AST 与 LIR 上各写一遍。
> **为什么可砍**：它不阻塞 S8b / S9 / S10；砍掉只影响 E-V3-9d 一条，不影响 v1.2 收口。

## 1 范围

**做**：

- 字符串**字面量**键 + 非指针 struct 值 + 可见字段 → 折叠为字段访问；
- 字面量键先查字段，未命中再走既有 `get(char *)`；两者都命中给歧义诊断；
- 未知字段、字段重命名、并存歧义三条负例；
- spec 新节 + glossary 一行。

**不做**：写形态 `p["x"] = v`；嵌套常量键；数组/切片/接口值下标（I2）；变量键折叠。

## 2 任务

| # | 任务 | 落点 | 验收 |
| --- | --- | --- | --- |
| P1 | ADR `D-031`：字段优先 + 并存歧义、只读、只认字面量 | `docs/decisions/D-031.md` | T-8 带 REVIEW `签收:`；结论与本卡一致 |
| P2 | spec 新节：语法、优先级、诊断、C 形态 | `docs/language-spec.md` | 目录新增可解析条目；`check-docs` 绿 |
| T1 | 解析期识别「字面量键 + struct 值接收者」并解析到字段 id | parser / Symbols | 命中与未命中两条路径可区分 |
| T2 | 折叠为字段访问（AST 与 LIR 各一处，S8 之后 LIR 为主） | parse / lir | 生成 C 是 `recv.field`，无 `get`、无临时 |
| T3 | 负例：未知字段 / 重命名 / 并存歧义 | `test/ast/errors/` + 正例 | 三条各一，位置指向 `[` |
| T4 | 文档与样例 | spec、glossary、`examples/` 一条 | 样例进 corpus；pin 同提交重生成 |
| T5 | 自举与 seed | `bootstrap/**` | 改 `selfhost/**` 时 seed 两轮逐字节 |

顺序：P1 → P2 → T1 → T2 → T3 → T4 → T5。

## 3 验收

1. 折叠后生成 C 无 `get` 调用、无 `__ct_*` 临时；
2. 未知字段 / 重命名 / 并存歧义三条负例硬错并给位置；
3. `check-goldens-ast` 25/25；`check-warnings` 零告警；`check-docs` 绿；
4. 改 `selfhost/**` 时 seed 两轮逐字节；未改动的语料生成 C 逐字节不变；
5. 既有 `get` 类型（无同名字段）行为逐字节不变。

## 4 回滚

单提交可 revert；回滚后 `check-goldens-ast` / `check-seed` 仍绿。可砍时不需要 revert——不合并即可。

## 5 风险

| 风险 | 处置 |
| --- | --- |
| 与 `get(char *)` 静默抢语义 | 并存即歧义诊断，不静默选择 |
| 不可见字段被折叠 | 与普通 `p.x` 同判据，不可见即不折叠，报既有错误 |
| 字面量键拼写错误成为新的脆弱面 | 未命中即硬错并列出候选字段；重命名负例钉住 |
| 临时量取址 | 只允许可回溯到变量/字段链的接收者（D52-4 同判据） |

## 6 交接

开工前在 [LANG-31](../../issues/lang/lang-31-const-key-fold.md) 留 `开工：<分支/日期>`；每片追加
`T<n> | 提交 | 门禁结果`；完成后转 `open` → REQ 复核 §3 后转 `verified`。

## 7 关联

- [LANG-31](../../issues/lang/lang-31-const-key-fold.md)（跟踪条）
- [REQ-INDEXFOLD-1](../planning/requirements-pool.md)
- [RFC-0000 评估](../reviews/2026-11-27-indexable-rfc-evaluation.md)
- [spec §4.64](../language-spec.md)、[D-028](../decisions/D-028.md)
