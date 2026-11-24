> **历史文档**：本文的 L0/L1/L2 构建链已在 SH-119（v1.1）退役；命令仅作历史记录。

# CT 下一波分期方案（v0-PH-46–v0-PH-52，已收口，历史记录）

> **2026-11-15 更新：v0-PH-46–52 已全部收口（v0.46.0–v0.52.0）。本文保留为历史分期方案；
> 当前施工相为 v0-PH-53 可选链，见 [phase53.md](../phases/v0-PH-53/card.md)。** 下文「草案 / 待实施 / 下一刀 v0-PH-50」
> 等字样均为当时口径，不再代表当前排期。
>
> **状态**：草案。未评审、未签字；本轮只写规划文档，不改 `selfhost/`、`test/`、`examples/`、
> `docs/language-spec.md`，不 bump、不打 tag、不 push。
> **基线**：`/Users/samxx/trae-ws/ct-lang`，规划提交 `94556f29`，`CTC_VERSION "0.44.1"`
> （`selfhost/ct-ast/main.ct:36`）。工作树有另一条线未提交的 `examples/**` 与 `issues/README.md`，
> 本文与各卡均不碰。
> **输入（事实基线）**：[language-capability-gaps.md](../proposals/language-capability-gaps.md)（22 条）、
> [ct-json-capability-blockers.md](../proposals/ct-json-capability-blockers.md)（J-1–J-6 / N-1–N-13）、
> [custom-index-protocol.md](../proposals/custom-index-protocol.md)。
> **输入（裁定）**：[2026-11-15-deepseek-ct-proposal-review.md](../reviews/2026-11-15-deepseek-ct-proposal-review.md)
> （语言侧，下称「评审一」）、[ct-json-proposal-review.md](../review/ct-json-proposal-review.md)
> （JSON 包侧，下称「评审二」）。两份评审的结论**优先于**本文早期版本对 L1 / `?.` 的排法。
> **命名说明**：`test/docs/check-docs.py:163-201` 的状态校验与 `:285-317` 的设计窗口只匹配
> `phase(\d+)\.md`；本文是跨相规划，故取 `phase46-52-plan.md`，不进入相卡命名空间。相卡另立
> `phase46.md`…`phase52.md`。
> **口径**：相号按 [roadmap.md](../roadmap.md) 顺延（本波规划时最后一个已用编号为 45；v0-PH-53 后来
> 只作记录占位，不排期），不另造编号体系；
> 版本号按仓库惯例「相号即次版本号」（v0-PH-44 → `v0.44.0` 实测）。
> **前置**：本波在 **v0-PH-45 收口后**开工（45 已于 2026-11-15 以 `v0.45.0` 收口；46 / 47 也已收口）。
> 两相不并发跑门禁。
> **责任边界（重要）**：**本仓库只维护规格、计划与验收判据，不执行实现。** 各相代码、夹具、
> golden 与门禁接入由外部 DeepSeek harness 完成；交接方式见 §10，已知缺陷与绕法见 §11。
> **裁决与手册**：73 条评审输入的逐条裁决见 [裁决记录](../reviews/phase46-52-freeze-verdict.md)；
> 施工顺序、入口条件与出口证据见 [施工手册](phase46-52-handoff.md)。
> **v0-PH-45 位置（2026-11-15）**：v0-PH-45 已由用户**直接签字立案**（未走本波的三席/裁决流程），排在
> **v0-PH-46 之前**；两刀顺序为 **S1 闭包 `return` 跳过 → S2 指针四位置判据**，详见
> [phase45.md](../phases/v0-PH-45/card.md)。本波七卡的开工基线随 v0-PH-45 收口提交重取；两相不并发跑门禁。

---

## 0 结论摘要

- **5 个实施相**：v0-PH-46–v0-PH-50（容器族 + 所有权族）；**2 个语言相**：v0-PH-51（指针接收者 `.` 发射缺陷，
  链式前置）、v0-PH-52（自定义下标 `[]`，方向已裁定）。
- **`?.` 不占相号**：按现形态**驳回**（评审一 §4）。若日后要做，按「可选调用 / 可选下标」重新设计并
  单列，不并入本波（见 §4.2）。
- 顺序：**46 → 47 → 50**（同一 `Map`/`Vec` 生成物）、**48 → 49**（同一 AutoDrop 出口）、
  **51 → 52**（链式前置先于下标糖；52 的单层下标本身不依赖 51，但连写依赖）。
- 用户点名的三条硬阻塞全部在前：`Map` 条目结构（46）、`Map` 键协议与键不复制（47）、
  指针字段 Drop 胶水（48，与跨单元空桩同相）。
- **当时下一刀是 v0-PH-50**（容器取用契约；[卡](../phases/v0-PH-50/card.md)，已于 `v0.50.0` 收口）；
  当前施工相为 [v0-PH-53](../phases/v0-PH-53/card.md)。

### 0.1 裁定状态（本波必须分开标）

| 事项 | 状态 | 来源 / 处置 |
| --- | --- | --- |
| L1 接、MVP 用**方案 A**（方法名 + 参数个数 + 非 static）、JSON 侧 `get_idx` 分名 | **已裁定** | 评审一 §3、§6 Q1；v0-PH-52 照此立卡 |
| L1 只覆盖**单层**下标；`p[k]`（`p` 为用户类型指针）留给 C 指针算术 | **已裁定** | 评审一 §3；v0-PH-52 的 RL1-E11 判据锁死 |
| 多级访问 `v["a"]["b"]` 由**包层返回值类型**承担（`get` 返回 `JsonRef` 值并给 `JsonRef` 实现 `get`） | **已裁定** | 评审一 §3.1、§7；语言侧不扩指针协议 |
| `?.` 现形态驳回（`(a ? a->b : 0)` 对 struct 值不成立；`a?[k]` 两种接收者都不合法；独立 token 破坏 `c?.5 : 1.0`） | **已驳回，待重新设计** | 评审一 §4；不占相号，见 §4.2 |
| 指针接收者用 `.` 调用发射 `S_f(&p)`（传 `S**`），`cc` 只给 warning、非空时结果已错 | **待确认影响面** | 评审一 §0.4、§7.5；v0-PH-51 的 S0 先统计波及面再冻修法 |
| `Map` 条目按值进共享头、`Map` 键协议与键不复制 | **已裁定为硬阻塞前置** | 用户输入；v0-PH-46 / v0-PH-47 |
| v0-PH-51 的修法取向（硬错要求 `->` vs 自动解引用发射） | **已签字：默认 A**（硬错）；若 S0 计数 > 0 需改 B，须执行期单独签字 | v0-PH-51 D51-1 |

---

## 1 总览

| 相号 | 主题（能力面） | 依赖 | 工量（行，±40%） | 状态 | 卡 |
| --- | --- | --- | --- | --- | --- |
| v0-PH-46 | `Map` 元素完整性（`Map<K, 用户 struct>` 在 `ct build` 下可编译） | 无（基线 = 交接提交） | ≤120 | 完成（v0.46.0） | [卡](../phases/v0-PH-46/card.md) |
| v0-PH-47 | 容器键协议（`Str` 键深拷贝；删 `put_owned`） | v0-PH-46 | 520–820 | 完成（v0.47.0） | [卡](../phases/v0-PH-47/card.md) |
| v0-PH-48 | Drop 语义闭环（指针字段胶水 + 跨单元 Drop 体） | 无（与容器族正交） | 300–550 | 完成（v0.48.0） | [卡](../phases/v0-PH-48/card.md) |
| v0-PH-49 | `own` 所有权转移（初始化式接工厂返回值） | v0-PH-48 | 200–380 | 完成（v0.49.0） | [卡](../phases/v0-PH-49/card.md) |
| v0-PH-50 | 容器取用契约（`has` / `at`；出参形态已废） | v0-PH-47 | 220–380 | 定稿（2026-11-15 签字） | [卡](../phases/v0-PH-50/card.md) |
| v0-PH-51 | 指针接收者 `.` 调用的发射缺陷（链式前置） | 无（必须先于 52 连写） | 50–250 | 定稿（2026-11-15 签字） | [卡](../phases/v0-PH-51/card.md) |
| v0-PH-52 | 自定义类型下标 `[]`（方案 A，只主张单层字符串键） | v0-PH-31 / v0-PH-34；连写依赖 51 | 250–470 | 定稿（2026-11-15 签字） | [卡](../phases/v0-PH-52/card.md) |
| — | `?.` 可选链 | 驳回待重新设计 | — | **不占相号** | 见 §4.2 |

> 工量含实现 + 诊断夹具 + 文档 + 门禁接入；校准参照 `phase44.md`（520–880）、
> v0-PH-40 实测 `git diff --stat v0.39.0 v0.40.0 -- selfhost/ct-ast/` = 3 文件 +271/−14。

---

## 2 排序依据

### 2.1 已实测缺口的分档

| 档 | 判据 | 条目 | 本波处置 |
| --- | --- | --- | --- |
| 硬阻塞 | 多数包撞 + 无等价绕法 / 只在 `ct build` 暴露 | C-4（J-1）、E-2（J-2）、G-4、G-2（J-3） | v0-PH-46 / 47 / 48 |
| 先修才敢用 | 默认写法静默失效或有安全绕法 | E-4、G-3（J-4） | v0-PH-47 / 49 |
| 链式前置 | 静默错值、且所有链式方案都会踩 | 指针接收者 `.` 发射 `S_f(&p)`（评审一 §0.4） | v0-PH-51 |
| 多数包会撞 | 有便宜绕法，但默认写法会踩 | C-2、C-3、J-5（L1） | v0-PH-50 / v0-PH-52 |
| 少数写法 | 绕法比缺失省事 | A-3、B-2、D-1、E-3、G-1、N-9 | 不占相（§6） |
| 不做 | 与 C 超集冲突或明文拒绝 | A-2、C-1、E-1、F-2、`?.` 现形态 | §6 |

### 2.2 三条硬阻塞 + 一条链式前置

1. **只在 `ct build` 暴露**（C-4）：单文件通过、多单元失败；包方探针验不出来，装进工程才炸。
2. **静默 UB**（G-4 / G-2）：`leaf drop 22792752`（读成指针低 32 位）与跨单元只打印 `done`，
   都是 rc=0、无诊断。
3. **无等价绕法**（E-2）：含 `\0` 的键在 `char *` 下必然碰撞；改编码丢字节保真，换有序表丢 API 面。
4. **链式前置**（评审一 §0.4）：`p.f()` 对指针接收者发 `S_f(&p)`，`cc` 只给 incompatible-pointer
   warning，非空时结果已错。任何链式方案（含 L1 连写、`json_get` 的包层实现）都会踩，必须先堵。

---

## 3 相间依赖与文件冲突面

| 文件 | 46 | 47 | 48 | 49 | 50 | 51 | 52 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `selfhost/ct-ast/backend/emit/Emitter.h.ct` | ● | ○ | ● | ○ | ○ | ● | ○ |
| `selfhost/ct-ast/frontend/parse/Expr.h.ct` | ○ | ● |  | ○ | ○ | ● | ● |
| `selfhost/ct-ast/frontend/parse/Stmt.h.ct` | ○ |  |  | ● |  |  | ○ |
| `lib/std/Vec.h.ct` | ● | ● |  |  | ● |  |  |
| `selfhost/check-ast.sh` / `check-sanitizers.sh` | ● | ● | ● | ● | ● | ● | ● |
| `docs/language-spec.md` | ● | ● | ● | ● | ● | ● | ● |

结论：

- **46 → 47 → 50 串行**：三者都改 `Map`/`Vec` 的生成物与 `lib/std/Vec.h.ct`。
- **48 → 49 串行**：49 的 AutoDrop 记账要调 48 修好的 Drop 体。
- **51 → 52 串行**：51 只改方法接收者的发射/诊断，52 改 `[` 后缀解析；两者都动 `Expr.h.ct`，
  且 52 的连写验收要先有 51 的结论。
- 51 / 52 可与其他相并行开发，但**门禁不得并发运行**（仓库既有纪律）。

### 3.1 文档面：`docs/language-spec.md` 由另一条线在改

按 [v043-split-plan.md](v043-split-plan.md) §5：**按句切片，不按文件抢**；S0 记录接手的行号/句子；
文档线未落定时等待（卡上记 `blocked-by: docs-correction`），不并发编辑；新增小节由该相独占。

---

## 4 裁定与外部决策

### 4.1 已裁定：L1（进 v0-PH-52）

| 项 | 裁定 | 对卡的影响 |
| --- | --- | --- |
| 是否立项 | **接**，依据必须是 [custom-index-protocol.md](../proposals/custom-index-protocol.md) 的 `RL1-D*` / `RL1-L*` / `RL1-E*` | 卡内不引 `phase40-draft.md` / `E40-*`（评审一 §1 #4/#5 已判该引用张冠李戴） |
| 签名匹配 | **方案 A**：方法名 + 参数个数 + 非 `static` | 不实现调用点重载解析；同一类型不能同时有 `get(char*)` 与 `get(int)` |
| JSON 侧 | `get_idx(int)` 与 `get(char*)` 分名 | `v[0]` 不主张（D52-6）；参数类型匹配归 [REQ-JSACCESS-1](../planning/requirements-pool.md) |
| 覆盖层级 | **只覆盖单层**；`p[k]`（用户类型指针）保持 C 指针算术 | 新增 RL1-E11：`p["k"]` 的「不做」口径 + 文档/诊断说明 |
| 多级访问 | 包层把 `get` 改成返回值类型（`JsonRef`）并给 `JsonRef` 实现 `get` | 语言侧不扩指针协议；卡的验收不含 `v["a"]["b"]` |

### 4.2 已驳回：`?.` 现形态（不占相号）

驳回理由（评审一 §4，均有实测）：

| # | 问题 | 结论 |
| --- | --- | --- |
| 1 | `a?.b → (a ? a->b : 0)` 对 struct 值接收者/结果不成立 | `cc` 报 `used type 'struct X' where arithmetic or pointer type is required` |
| 2 | `a?[k] → (a ? a.get(k) : 0)` 两种接收者都不合法 | 值不能作条件，指针不能用 `.` |
| 3 | 独立 token 破坏今天合法的 `c?.5 : 1.0` | 最长匹配会把 `?.` 切开，语义回归 |
| 4 | 「高于一元 `?`、低于 `.`」的优先级前提不成立 | 规范优先级表没有后缀行；`?.` 应并入后缀链 |
| 5 | JSON 需要的是**可选调用 / 可选下标**，不是可选字段 | `data.server` 不是 C 字段，而是 `get("server")` |

**重新设计门槛（若日后单列）**：接收者必须是指针或显式可空句柄；结果为零值时由编译器按结果类型
给出（`(T){0}` / `(void *)0`），不再是纯语法糖；词法**不做独立 token**，在 parser 后缀链里识别
`?` + `.`，且 `.` 后必须是标识符（排除 `.5`）；并入后缀链、左结合；只判 NULL，不判 `TAG_NULL`。
本波**不给相号**，避免把驳回形态固化进排期。
**2026-11-15 追加**：`?.` 已定稿为 [v0-PH-53 施工卡](../phases/v0-PH-53/card.md)（指针 / map；struct 值接收者拒绝）；
本节只保留当时的重新设计门槛，本波不覆盖。

### 4.3 待确认影响面：指针接收者 `.` 发射（v0-PH-51）

| 项 | 现状 |
| --- | --- |
| 事实 | `struct S *p; p.f();` 发射 `S_f(&p)`，传 `struct S **`；`cc` 只给 incompatible-pointer warning，非空时结果已错 |
| 影响面 | **未确认**：S0 统计 `test/`、`examples/`、`lib/std` 里「指针接收者 + `.` 调用」的实际用量 |
| 修法分叉 | 若零依赖 → 选「解析期硬错，要求 `->`」（最小、不静默）；若有依赖 → 选「自动解引用发射 `S_f(p)`」并给迁移清单。**改动前需用户裁定** |
| 排期 | 先于 v0-PH-52 的连写验收；不阻塞 46–50 |

---

## 5 每相通用流程（四件套；执行方 = 外部 harness）

> 本节步骤由外部 DeepSeek harness 执行；本仓库只维护卡片与判据，不代笔实现，也不替验收签字。

1. **S0 核现状（只读）**：spec / tutorial / README / glossary / roadmap 现在怎么写，实现真实行为是什么；
   输出写进卡内「现状与缺口」，记 `baseline: <sha>`。S0 不产提交。
2. **先红后绿**：每相第一个实现切片先提 `test(<scope>): PH-4x 红` 提交（父提交即含红证），正文写
   `baseline: <sha>` 与原始输出；实现提交随后转绿。
3. **小步**：每片 ≤150 行、≤3 文件；单片只跑相关门禁，`check-all.sh` 只在收口跑。
4. **收口**：同一次动作里完成 bump（五处 `CTC_VERSION` + 两处 README + 受影响 golden 重生成），
   跑 `bash selfhost/check-all.sh` 贴末行与关键计数；tag / push 需用户单独授权。
5. **缺陷类相不新增能力条款**：46 / 48 / 51 只让实现回到既有条款；47 / 49 / 52 才需要新条款。

---

## 6 本波不覆盖（不占相号）

| 项 | 判定 | 理由 / 归属 |
| --- | --- | --- |
| A-1 `.m.ct` import `.h.ct` | 已修（`fb55985c`） | 发版即关闭 |
| B-1 / B-3 / B-4 接口值返回三条装箱路径 | 已修（`5ff69ac3` / `d6e82e25` / `b5797cbf`） | 同上 |
| A-2 `.h.ct` 承载 `map … for type` | 维持拒绝 | SH-71 已明确拒绝；A-1 落地后组合已可用 |
| A-3 类型位置限定名 `ns::Type` | 不进本波 | 动四处文法；与 v0-PH-51 的类型求值面相邻 |
| B-2 方法结果作接收者（一行链） | 不进本波 | 100–300 行且改既有生成物；SH-73 仍是独立缺陷 |
| `?.` 可选链（现形态） | **驳回** | 见 §4.2；重新设计后单列 |
| 连写下标 `v["a"]["b"]` | 不进本波（语言侧） | L1 只覆盖单层；由包层 `JsonRef` 承担 |
| 用户类型指针接收者进入下标协议 | **不做** | 评审一 §3；`p[k]` 保持 C 指针算术 |
| C-1 裸泛型类型名 | 不做 | 裸 `Map *` 在 C 里无意义；只补「不允许」条款 |
| D-1 `#define` 导出到生成头 | 不做 | `pub enum` / `pub` 全局已覆盖 |
| E-3 匿名 union 具名成员 | 不做 | 命名 union 类型即可；C11 里「具名匿名成员」不是标准形态 |
| E-1 数值溢出检查 | 不做 | Z5 明确 opt-in |
| F-2 隐式转换协议 | 不做 | 与 Z3 冲突；建议规约写明永久不做 |
| G-1 同单元同名函数 | 不进本波 | 绕法便宜（改名）；与 REQ-TYPE-1 判定族相邻 |
| N-9 跨 union 成员字段链 | 不进本波 | 落局部即可绕；根因在类型求值 |
| REQ-TYPE-1 默认路径全量类型检查 | 不立项 | 策略变更 + 全量 golden 重生成，需用户签字 |
| REQ-MEM-2 借用经调用/字段逃逸 | 不立项 | 300–600 行写入摘要；等 43/44/45 收口后再评估 |
| REQ-CI-1 / REQ-CI-2 | 不占相号 | CI 口径与 ASAN 选项，需用户二选一 |
| 泛型 trait 未实现（提案一说法） | 事实已过时 | Phase 35 已交付 `trait Iter<T>`（评审一 §1 #15） |
| `lib/std/utf8` | 不存在 | 评审一 §1 #18、评审二 §5.1；`\uXXXX` 由包内手写 |

---

## 7 排期情形

| 情形 | 排法 |
| --- | --- |
| 默认（本方案） | 46 → 47 → 48 → 49 → 50 → 51 → 52，版本连续 `v0.46.0`…`v0.52.0` |
| 51 的 S0 发现零依赖、用户裁定选「硬错」 | 51 缩到 50–100 行，可与 50 并行开发（串行跑门禁） |
| `?.` 重新设计通过 | **不插队**：另立新相号（53 起），必须在 51 收口之后；不与 52 绑定 |
| 52 的评审改判方案 B | 需另立「调用点重载解析」相（53 起），不在 52 内扩面 |

---

## 8 交接顺序（当时下一刀：v0-PH-50；已收口）

签字时的建议是先开 **v0-PH-46**（已于 `v0.46.0` 收口），理由按权重：

1. **最小且无分歧**：只改 `MapEntry` 的发射归属，不动 API、不动语义、不动键规则；一相内可把
   「S0 → 红证 → 实现 → 夹具 → 门禁」模板跑通。
2. **它是 v0-PH-47 的硬前置**：47 要改同一份 `Map` 生成物与 `lib/std/Vec.h.ct`；先 46 把「条目结构在
   哪个单元完整」定下来，47 才不会一边改键比较一边挪结构。
3. **它堵的是「探针验不出」的洞**：C-4 只在 `ct build` 暴露，包方用单文件探针永远看不到。
4. **收口成本最低**：没有新语法、没有新诊断族，唯一争议（下沉到实例化单元 vs 共享头补 include）
   用一条 `--lib` 导出场景就能定，不必等用户裁定。

48 / 49 均已收口（`v0.48.0` / `v0.49.0`）；当时下一刀是 **v0-PH-50**（已收口），其后 v0-PH-51/52 已收口；
当前施工相为 [v0-PH-53](../phases/v0-PH-53/card.md)。

---

## 9 风险汇总

| 风险 | 相 | 触发信号 | 处置 |
| --- | --- | --- | --- |
| `MapEntry` 下沉后跨单元重复定义 | 46 | 目标文件出现两份 `MapEntry_*` | 固定唯一定义点；E46-3 锁 `--lib` 场景 |
| 改 `lib/std/Vec.h.ct` 引起大面积 golden 漂移 | 47 / 50 | `check-goldens` 红且 diff 面大 | 逐字节核对后重生成，提交正文写原因 |
| 跨单元 Drop 符号与 v0-PH-42 可见性判定冲突 | 48 | `drop` 被判私有后消费单元链接失败 | D48-2：胶水符号单独一档链接性，不经过方法可见性 |
| `own` 双释放 / 与 `?` 提前返回交叉 | 49 | ASAN double-free | 覆盖 `own` + `?` + `errdefer` 三组合，视为阻塞 |
| 51 改成自动解引用后生成物大面积变化 | 51 | golden diff 面大 | 优先选「硬错」；选自动解引用须用户签字 |
| 52 被期待「一次解决连写」 | 52 | 验收里出现 `v["a"]["b"]` | RL1-E11 + 卡内明写「只覆盖单层」；连写归包层 |
| 与文档线并发改 `language-spec.md` | 全部 | 同一行两条修补线 | §3.1 规则：按句切片、等落定、收口贴最终 diff |
| 与 v0-PH-45 并发跑门禁 | 全部 | `check-all.sh` 交叉失败 | 串行跑；45 已收口（`v0.45.0`），46 基线随 45 收口提交 |

---

## 10 交接说明（规格与计划在本仓，实现在外部）

### 10.1 读起顺序

外部 harness 只按下面顺序读，**不要从 `docs/history/` 或旧草案反推**：

1. 本文 §1 总览、§3 依赖、§8 起手建议、§11 已知缺陷 —— 先确定做什么、先后与坑。
2. 目标相卡 `docs/design/phase4N.md` —— §0 现状、§2 决策、§3 诊断、§4 切片、§6 验收。
3. 证据与裁定：[proposals/language-capability-gaps.md](../proposals/language-capability-gaps.md)、
   [proposals/ct-json-capability-blockers.md](../proposals/ct-json-capability-blockers.md)、
   [proposals/custom-index-protocol.md](../proposals/custom-index-protocol.md)（仅 v0-PH-52）、
   [reviews/2026-11-15-deepseek-ct-proposal-review.md](../reviews/2026-11-15-deepseek-ct-proposal-review.md)、
   [review/ct-json-proposal-review.md](../review/ct-json-proposal-review.md)。
4. 行为规约：[AGENTS.md](../../AGENTS.md)（提交、门禁、版本、T-7 红证）。
5. `docs/language-spec.md`：**只读**；要改时必须按句切片且先与本仓库文档线协调（§3.1）。

### 10.2 构建（从干净克隆到 `ct-ast`，与 `selfhost/check-ast.sh:388-412` 同形）

```sh
cd <ct-lang>
work=$(mktemp -d)
cc -Wall -Wextra -std=c99 selfhost/l0/ctc.c -o "$work/ctc"
"$work/ctc" selfhost/l1/ctc.ct -o "$work/l1.c"
cc -Wall -Wextra -std=c99 "$work/l1.c" -o "$work/l1"
"$work/l1" build selfhost/l2/driver.ct -o "$work/l2src"
cc -Wall -Wextra -std=c99 "$work/l2src"/*.c -o "$work/l2"
"$work/l2" build -I selfhost/ct-ast selfhost/ct-ast/main.ct -o "$work/astsrc"
cc -Wall -Wextra -std=c99 "$work/astsrc"/*.c -o "$work/ct-ast"
```

产物用法与 `check-ast.sh` 一致：单文件 `"$work/ct-ast" <x>.ct -o <x>.c`；工程模式
`"$work/ct-ast" build <dir>/main.ct -o <outdir>`。安装版 `ct` 的等价命令是 `ct <x>.ct` /
`ct build <dir>`，两者不得混用基线。

> 构建链任一环失败即为环境问题，**不要**据此改判据或改冻结层（`selfhost/l0| l1 | l2` 冻结）。

### 10.3 门禁

| 用途 | 命令 | 通过判据 |
| --- | --- | --- |
| 全量硬门禁（收口必须） | `bash selfhost/check-all.sh` | 退出码 0，末行 `check-all: OK (11 hard gates green)` |
| 单相快速回环 | `bash selfhost/check-ast.sh` | 退出码 0，末行 `0 failed` |
| golden 与 fixpoint | `bash selfhost/check-goldens.sh` | 退出码 0；L1/L2 fixpoint 段通过 |
| 生成 C 零告警 | `bash selfhost/check-warnings.sh` | 退出码 0，`0 failed` |
| 内存安全 | `bash selfhost/check-sanitizers.sh` | 退出码 0（**`detect_leaks=0`**，该脚本不报泄漏） |
| 文档与状态 | `python3 test/docs/check-docs.py` | 退出码 0；`phase status` 与本表一致 |

11 道硬门禁的完整清单以 `selfhost/check-all.sh:10-24` 为准（`test/run.sh`、`check-goldens`、
`check-archive`、`check-m2a`、`ct-tour`、editor grammar、`test/pkg/run.sh`、`check-ast`、
`check-warnings`、`check-semantics`、`check-docs`）。**门禁条数、版本号、判据宽度都不许改。**

### 10.4 提交与分支

| 项 | 要求 |
| --- | --- |
| 提交格式 | `<type>(<scope>): <subject>`，英文祈使 ≤50 字符；`type ∈ feat\|fix\|docs\|refactor\|test\|chore`，`scope ∈ parser\|codegen\|rewrite\|cli\|selfhost\|docs\|example` |
| 正文 | 中文说明「为什么 + 怎么验证」，一提交一事；不合并红证与实现 |
| 红证（T-7） | `test(<scope>): PH-4N 红` 为实现的**父提交**；正文含 `baseline: <sha>` 与原始输出；harness 用 `git archive <baseline>` 到 `/tmp` 复跑，不用工作树产物 |
| 暂存 | 用显式路径（`git add <file>` 或 `git commit --only <file>`）；**禁止** `git add -A`、`git add .` |
| 分支 | 仓库**没有**成文的分支命名规则（`AGENTS.md` 未规定）。约定：一相一分支 `phase/4N-<slug>`，基于交接基线；不合入主分支前不 rebase 别人在途改动 |
| 禁止 | 不 push、不打 tag、不改 `CTC_VERSION`（版本移动只在收口提交内，由本仓库指令触发）；遇 `.git/index.lock` 等 3–5 秒重试，最多 5 次，**不得删除他人的锁** |

### 10.5 目录归属

| 目录 / 文件 | 外部 harness | 本仓库（规格线） |
| --- | --- | --- |
| `selfhost/ct-ast/**` | 可改（本相范围） | 只读 |
| `lib/std/**` | 可改（v0-PH-47 / 50 范围） | 只读 |
| `test/ast/**`、`test/modules/**`、`test/pkg/**` | 可改（新增夹具；不动既有断言） | 只读 |
| `examples/**` | 只可新增本相样例 | **在改**（有未提交改动，见 §10.7） |
| `selfhost/check-*.sh` | 只可追加断言，不改既有断言与条数 | 只读 |
| `docs/language-spec.md` | 只可按句改本相独占句 | **在改**（文档线），需先协调 |
| `docs/tutorial.md`、`docs/package-guide.md` | 可改（本相小节） | 只读 |
| `docs/design/phase4N.md`、`docs/roadmap.md` | 只可回写状态行与交付证据 | 维护 |
| `selfhost/l0/ctc.c`、`selfhost/l1/**`、`selfhost/l2/**` | **禁止** | 只读（冻结层） |

### 10.6 交付物形态

每个任务一条：提交 sha + 该任务的验收命令原文 + 原始输出（T-3）。相收口另附：
`check-all.sh` 末行、11 道各自末行原文、`git diff --stat` 区间、生成物逐字节对比方式（`cmp`/`git diff`）。

### 10.7 交接基线

- 规格基线：本文件的**最后一次提交**即交接基线（上一版规划提交为 `94556f29`，`CTC_VERSION 0.44.1`）；
  取法：`git log -1 --format=%H -- docs/design/phase46-52-plan.md`。
- 工作树可能有本仓库另一条线的未提交改动（`examples/**` 若干、`issues/README.md`）。外部 harness
  应基于**干净克隆**开工；若复用同一工作树，先确认这些改动不属于自己，不得提交、不得回滚。
- v0-PH-45 已收口（`v0.45.0`）；原「未收口时改取 45 收口提交」的兜底不再适用。

---

## 11 已知缺陷与绕法（外部 harness 会撞上的集中表）

### 11.1 未修项与绕法

「绕法」只用于**在对应相交付前让其他相不被卡死**；不得把绕法写进语言语义、不得据此改判据。
每条绕法都必须在卡的 §8 复现段落里留一条反例（红证），证明缺陷当时确实存在。

| # | 缺陷 | 表现 | 撞上的相 | 绕法（临时） | 证据 |
| --- | --- | --- | --- | --- | --- |
| 1 | `Map` 条目按值进共享头 | `ct build` 报 `field has incomplete type`；单文件绿 | **46**（正题）、47/50（同文件面） | 元素改指针或改 `Vec`；不得把元素定义硬塞共享头 | 提案 J-1 |
| 2 | 指针接收者 `.` 调发射 `S_f(&p)` | `cc` 只告警、非空时结果错 | **51**（正题）、52 与任何链式 | 一律写 `p->f()`；不得忽略 `incompatible-pointer-types` | 评审一 §0.4 |
| 3 | `Map` 键只收 `int/long/char *` 且不复制 | `Str` 键硬错；含 `\0` 键碰撞；改缓冲后查不到 | **47**（正题）、52 的 JSON 单层 | 键拷到长寿命缓冲；含 NUL 用 `int` 序号键 | E-2 / E-4 / J-2 |
| 4 | 指针字段 Drop 胶水传 `T**` | `leaf drop 22792752`，rc=0 无诊断 | **48**（正题）、49（AutoDrop） | 手写 `release()` 显式释放，不依赖自动胶水 | G-4 |
| 5 | 跨单元 Drop 调空桩 | `delete` 后真实 Drop 体不跑（只打印 `done`） | **48**（正题）、49 | 在消费单元本地释放；不得假定跨单元可用 | G-2 / J-3 |
| 6 | `own` 不接工厂返回值 | `'own' requires a malloc or calloc initialiser` | **49**（正题）、ct-json 解码 | 普通指针 + **显式失败分支释放**；`.h.ct` 内不能用 `defer`/`errdefer`（见 #13），每个失败返回点重复释放代码 | G-3 / J-4 |
| 7 | 容器越界/缺键退零值 | `missing=0x0`、`oob=0` 与真值不可分 | **50**（正题）、ct-json | `Map` 用哨兵值 + 自维护存在性；`Vec` 用伴随 `found` 数组 | C-2 / C-3 / J-7 |
| 8 | 自定义下标未实现 | `ct` rc=0，`cc` 报 `subscripted value is not an array` | **52**（正题）、ct-json 访问 | 显式 `get("k")`；多级逐层 `get` | F-1 / REQ-L1 |
| 9 | 方法结果不能作接收者 | 链式第二跳报无法解析 | 任何链式方案（52） | 逐跳落局部变量 | B-2 / SH-73 |
| 10 | 跨 union 成员字段链 | `cannot resolve the method trait` | ct-json（非本波） | 先落局部变量再调用 | N-9 |
| 11 | 同单元同名函数只告警 | `cc` 报 conflicting types | 非本波 | 改名 | G-1 |
| 12 | `#define` 不导出到生成头 | 宏在消费单元不可见 | 非本波 | 用 `pub` 常量 / `pub enum` | D-1 |
| 13 | `.h.ct` 内 `defer` / `errdefer` 不可用 | `defer is not allowed in a .h.ct unit`；`errdefer is not allowed here` | 所有包实现（含 49、ct-json） | **只能显式失败分支释放**：每个 `return err` 前手写释放；无法用「defer + 成功标志」统一收口。代价：重复代码、漏释放风险随失败点线性上升 | `language-spec.md:432`；v0-PH-38 L38-3 / v0-PH-40 L40-5 |

> **逐条核对**：§11 其余绕法均**不依赖** `defer` / `errdefer`（#6 已改为显式失败分支释放）。
> 规范里 `.h.ct` 的禁用是明文限制，不是实现缺陷；不要试图在 v0-PH-49 里「顺手放开」。
>
> 撞表原则：**先确认自己在哪一相**。属于本相的缺陷必须在本相修掉并留红证；不属于本相的，
> 按「绕法」列走，并在交付报告里注明「受 #N 限制，绕法为 …」。禁止为了让本相夹具变绿而改判据。

### 11.2 已撤销 / 降级结论

| 旧结论 | 现状 | 复现版本与形态 | 处置 |
| --- | --- | --- | --- |
| 「带泛型字段的 struct 不能进 `.h.ct`」（提案 N-3 / H-03 / P-03） | **不成立（降级）**：v0.44.1 上 `pub struct Holder { Vec<int> *v; }` 导出、构建、运行 **rc=0**；`Vec<int> v`（按值）与 `Vec<JsonRef> *arr` 同样通过 | v0.44.1；三种形态均为单单元 + `ct build` | 从「缺陷/冲突」移除；**唯一**仍失败的是 `Map<char *, 用户 struct>`，归 C-4 / v0-PH-46，不是导出问题。实现方不得按「泛型字段不能进 `.h.ct`」做规避设计 |

> 归属证据：`docs/proposals/ct-json-capability-blockers.md:108`、`:450`（N-3 已标「部分不成立」）；
> `docs/proposals/language-capability-gaps.md:1252`（探针 `a3` / `a3b` / `j16` / `j10b`）。

### 11.3 规范文本待更新（本计划不越界改正文）

- `docs/language-spec.md:664` 仍写「**仍未修**：impl 方法或自由函数返回局部接口值时，装箱仍取局部地址」。
  A-1（`fb55985c`）、SH-74（`d6e82e25`）、SH-75（`b5797cbf`）均已修完，该句**待更新**。
  是否现在改由 `language-spec.md` 文档线决定；本计划只登记，不改规范正文。

---

## 12 实战限制（包实现撞到的原文报错，2026-11-15）

来源：实际写一个 `ct-pkg` 包时撞到，均带原文报错。**外部 harness 按本条做设计预案，不要当成本波要修的缺陷**，
除非卡里明确把它列为正题。命令统一用 §10.2 构建的 `$work/ct-ast`；退出码与报错位置以 harness
在本机复跑为准（原文由包实现提供）。

| # | 触发条件 | 最小代码 | 命令 | 退出码 | 原文报错 | 定性 | 绕法及代价 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | `.h.ct` 里 `union` 未写 `pub`，且被导出 struct 按值使用 | `lib.h.ct`：`union JsonPayload { int i; };` + `pub struct D { union JsonPayload p; };` | `"$work/ct-ast" build main.ct -o out` | `ct` 侧不报错；`cc` rc=1 | `error: field has incomplete type 'union JsonPayload'` | 规范空白 + 诊断缺失（`.h.ct` 的 union 导出可见性没写；`ct` 不提示，`cc` 才发现） | 给 union 加 `pub`。代价：零；但**必须写进包模板**，否则每次新建包都踩 |
| 2 | 包内直接读 `errno` | `func main() { int e = errno; }` | `"$work/ct-ast" x.ct -o x.c` | 1 | `error: use of an undeclared variable` | 规范空白（未定义 `errno` / 系统错误码互操作） | 在绑定层或手写 C 胶水里读 `errno`，转成返回值；代价：每处多一层胶水，跨平台语义要自己写 |
| 3 | 同一单元同时有：全局计数 + 一个 `check()` 函数 + 任意带 `char *` 参数并被调用的函数 | `var g: int;` + `func check() { g = g + 1; }` + `func use(char *s) { check(); }` | `"$work/ct-ast" probe.ct -o probe.c` | 1 | `a borrowed view is invalidated by a later mutation of its container; copy it with retain() first`（报错位置落在 `char *` 参数与 `int` 参数上） | **疑似实现缺陷，未确认**：该单元内没有任何 `get` / `entry`；去掉 `check()` 或去掉全局即不报。最小复现尚待确认 | 暂按「拆单元」或「去掉全局计数」规避；代价：多一个 `.ct` 单元或改数据结构。**不得据此改判据** |
| 4 | `.h.ct` 内（含函数体）使用 `defer` / `errdefer` | `lib.h.ct`：`pub func f() { defer { } }` | `"$work/ct-ast" x.ct -o x.c` | 1 | `error: defer is not allowed in a .h.ct unit`（`errdefer` 报 `error: errdefer is not allowed here`） | **规范限制**（`language-spec.md:432`；v0-PH-38 L38-3 / v0-PH-40 L40-5），不是 bug | 显式失败分支释放（同 §11 #13）；代价：重复代码、漏释放风险，不能用「成功标志 + defer」统一收口 |

> #3 的处置口径：在最小复现确认前，**只记录为风险**，不进任何卡的退出判据；若确认是实现缺陷，
> 由本仓库另立 Issue 并决定是否单列相，不并入 v0-PH-46–52。

---

## 13 裁决落地（2026-11-15）

| 变更 | 影响 |
| --- | --- |
| v0-PH-50 废弃 `try_get(..., V *out)`，改 `Vec::has/at` + `Map::has` | 出参形态实测双释放（ASAN rc=134） |
| v0-PH-47 删除 `put_owned`，`Str` 键改深拷贝 | `MapEntry` 无所有权位；工量上调至 520–820 |
| v0-PH-52 收缩为「只主张单层字符串键」 | `v[0]` 实测静默返回 0，记 D52-6 已知洞 |
| v0-PH-51 判据改为断言生成 C 实参形态 | 泛型实例 `void *self` 零告警、rc=139 |
| v0-PH-48 拆两个决策：胶水 owner 单元 / 符号可见性 | 后者 U-2 已签字 A（单独一档） |
| v0-PH-46 修法点写死为 `inst_elem_foreign` | 工量降至 ≤120 行 |

5 条已于 2026-11-15 按建议值签字，见 [裁决记录 §4](../reviews/phase46-52-freeze-verdict.md)；施工入口见
[施工手册](phase46-52-handoff.md)。
**2026-11-15 签字**：五条待裁全部按建议值生效（U-1…U-5 均 A）；签字时七张卡为「已定稿、未实施」。
后续 45–49 已收口，状态以 roadmap 与本文件 §13.1 errata 为准。
`v[0]` 的参数类型匹配登记为 [REQ-JSACCESS-1](../planning/requirements-pool.md)，属「JS 风格访问」
长期目标，不占相号、不得砍掉。

### 13.1 errata（2026-11-15）

- **v0-PH-45–49 均已收口**：`v0.45.0`（`70b66195`）、`v0.46.0`（`84f5a417`）、`v0.47.0`（`46969693`）、
  `v0.48.0`（`d60305b1`）、`v0.49.0`（`f29d7979`），五个 annotated tag 均已推送。
  卡头与 roadmap 已由 release 提交更新；本文与手册中「未实施 / 先派 46」的表述以本 errata 为准。
- **当时下一刀是 v0-PH-50**（容器取用契约，已收口）；v0-PH-51 可在 50 之后并行开发。
  当前施工相为 [v0-PH-53](../phases/v0-PH-53/card.md)。
- **v0-PH-48 锚点重录**：卡内 5 处锚点已按 `v0.49.0` 取「符号名 + 行号」，页首标明有效版本；
  §3.1 保留派工时 `v0.47.0` 的修复前读数，仅作回归对照。
- **流程缺口（登记，不补造）**：45–49 五个 release 提交各自同时含实现、夹具与版本收口，
  没有 T-7 要求的 `test(...): 红` 父提交，正文写 `red: n/a（版本收口）`，`baseline: <sha>` 与红证缺失。
  该缺口按既有事实登记，**不得事后补造红证**；后续相须按 T-7 先红后绿。
- 本 errata 只改陈述，不改任何卡的 §6 `exit-criteria` / `tasks`。

## 14 远端文档债（v0.49.0 快照，交 harness 核对）

以下四处存在于远端 `v0.49.0` 的文档里，不是本轮合并引入的；本地合并已按「48/49 完成、下一刀 50」
的事实口径修正（否则四份文件互相矛盾），此处留档，避免 harness 下次改这些文件时把旧口径带回来。

| 文件 | v0.49.0 远端现状 | 应为 |
| --- | --- | --- |
| `docs/design/phase46-52-plan.md` §1（48/49 行） | 仍写「定稿（2026-11-15 签字）」 | 完成（`v0.48.0` / `v0.49.0`） |
| `docs/design/phase46-52-plan.md` §8 | 仍写「紧随其后 v0-PH-48」 | 下一刀 v0-PH-50 |
| `docs/design/phase46-52-handoff.md` 顺序图 | 停在 `48 → 49` | 补 `49 → 50` |
| `docs/README.md` 索引 | 46–52 整组写成「未实施」 | 46–49 已完成、50–52 未实施 |
