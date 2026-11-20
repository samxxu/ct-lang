# battle/phase80-retain-scope-1 判决

> **状态：`closed`**（2026-11-21；裁判 EDITOR；1 轮 claim/counter；本场无 `question.md`、无
> `verify.json`，见 §7）。
> **判决：A `rejected`；B 的核心判据成立。** PH-80 不能以「保守字段 release（无 UAF/SEGV，
> 允许已登记泄漏）+ 文档限制」收口；必须先做到字段 release 的两条结构性精确性：①任何字段
> `release` 只作用于已定义存储；②同一存储位置的字段重赋必须 `release` 旧值，做不到的形状
> 硬错。**但「必须先实现字段数据流精确 release」按字面不成立**：B 的可行路线是「声明即定义 +
> 既有 `sb_field_known → release_old` 路径 + 边界硬错」，不需要新增支配树 / 别名数据流 pass。
> **一句话**：A 的「已登记泄漏」不是 D-013 §3 的满足，而是对它的改写；改写要 USER 签，且 A 自己
> 的安全半部（C-A1 的多条规则）在 HEAD 尚未实现。B 的核心路线已被原型证明可在 `+59/−7` 内
> 同时消除 R6a/R6b，代价与 A 同阶，不是 L/XL。

判决：A `rejected`；B 的核心判据成立。PH-80 不能以「保守字段 release + 已登记泄漏」收口，
必须先实现字段 release 的结构性精确性（`release` 只作用于已定义存储；同一存储位置的字段
重赋 `release` 旧值，做不到的形状硬错）；不要求新增支配树 / 别名数据流 pass。

## 0 争点、基线与材料

| 项 | 值 |
| --- | --- |
| 争点 | PH-80 / SH-102 的字段 `release` 能否以「保守、无 UAF/SEGV、允许已登记泄漏」收口，还是必须先做到字段赋值 / 重赋在发射规则上精确 |
| 基线 | HEAD `953c19e0`（`v0.80.2`，第三轮复核后）；SH-102 `status: reopened`；卡头「状态：完成」；roadmap「✅ 完成（v0.80.2，SH-102 修复）」 |
| 主张席 | A（claim）：保守字段 `release` + 已登记泄漏 + USER 签收的窄合同 + 文档限制 |
| 反对席 | B（counter）：R6a/R6b 必须在发射规则里结构性消除或硬错；在此之前 SH-102 不得 `verified`、PH-80 不得签字 |
| 材料 | `claim.md`、`counter.md`；`question.md` 缺失、`verify.json` 缺失（§7） |
| 裁判 | EDITOR（本席）；未改源码、卡、issue、decision、roadmap、tests；只写本文件 |
| 证据限制 | 双方原型均在 `/tmp`、未提交；本席只复跑行为，不复核其完整交付性（§7） |

先定三条事实（各有生成 C 或台账证据，不在争点内）：

- **FACT-1（R6a 是结构性缺陷，不是“偶发”）**：HEAD 生成的 C 在 `if` 体内未执行的字段赋值之后，
  仍无条件读旧字段再 `release`（[claim.md:140-149](claim.md#L140-L149)；
  [verdict:970-977](../../docs/reviews/2026-11-20-phase80-rev-verdict.md#L970-L977)）。
  单次运行是否 SEGV 取决于栈内容（§1.2 实测），所以**不能靠跑一遍探针证明安全**。
- **FACT-2（R6b 是真实泄漏且线性增长）**：`Holder h = { 0 }` 循环 3 次、每轮重赋，`final live=2`；
  N 次泄漏 N−1 个 buffer（[claim.md:154-171](claim.md#L154-L171)；
  [verdict:980-1020](../../docs/reviews/2026-11-20-phase80-rev-verdict.md#L980-L1020)）。不是测试噪声。
- **FACT-3（收口记录先于判决存在，REV 又打回）**：卡头「状态：完成」
  （[phase80:3](../../docs/design/phase80.md#L3)）、roadmap「✅ 完成（v0.80.2，SH-102 修复）」
  （[roadmap:93](../../docs/roadmap.md#L93)），而 SH-102 仍 `reopened`
  （[issue:4](../../issues/selfhost/sh102-p80-auto-retain-not-implemented.md#L4)）。本场判的是
  **怎样让这条已写下的收口记录成立**，不是要不要开始收口。

## 1 逐项判决

> 标签口径：**A** = 主张席在该项成立；**B** = 反对席在该项成立；**双方一致** = 双方证据都支持、
> 不构成分歧的事实项；**条件项** = 双方都不完整、必须在 §4 补齐。
> 一个 J 的 A 不自动推出另一个 J 的 A；整体结论在 §2。

| J | 争点 | 判决 | 依据（条款 / 证据） |
| --- | --- | --- | --- |
| J-1 | D-013 §3 的「字段赋值 / 重新赋值」在 HEAD 是否已允许「已登记泄漏」 | **B** | [D-013:33](../../docs/decisions/D-013.md#L33)「重新赋值：先 retain 右值，再 release 旧值；」是 USER 签收的无条件句；`docs/decisions/` 无任何限定字段重赋的记录（§8）。A 的 C-A3 自己也要求「新 decision + USER 签收」，该记录在 HEAD 不存在（A 的 F1 承认） |
| J-2 | A 的「保守 release（无 UAF/SEGV）」在其 HEAD 原型上是否已结构性成立 | **B（未满足）** | A 的 E1-5 只实现 C-A1 的第 1 条（汇合丢弃），`+15/−5`；C-A1 的 owner 化键、基址重绑清除、整结构体赋值清除、箭头基址关闭 / 取址降级、`goto` 硬错均未实现（[claim.md:216-245](claim.md#L216-L245)、[claim.md:392-393](claim.md#L392-L393)）。本席在其原型上实测 `field_shadow` SEGV、`field_ptr live=2`（§1.2）。**A 的“无 UAF”在 HEAD 为假，不只是合同问题** |
| J-3 | R6a 是否真实 | **双方一致（成立）** | 生成的 C 明确读未初始化字段再 `String_release`（HEAD `field_branch0.c:1813`；§1.2）。运行期是否 SEGV 随栈变化，但“release 未定义存储”是稳定的结构性事实 |
| J-4 | R6b 是否真实且随迭代增长 | **双方一致（成立）** | 同一组 `field_loop0` / `field_loop_bare`：HEAD `final live=2`，N 次循环泄漏 N−1（§1.2） |
| J-5 | 「已登记泄漏」能否替代 D-013 §3 的字段重赋零泄漏 | **B** | REV 第三轮已明确 R6a/R6b 是 D-013 §3「字段赋值 / 重新赋值」的字面反例，并据此不置 `verified`（[verdict:934-1020](../../docs/reviews/2026-11-20-phase80-rev-verdict.md#L934-L1020)、[:1032-1039](../../docs/reviews/2026-11-20-phase80-rev-verdict.md#L1032-L1039)）；G6 要求每条 issue 只有一个去向，不能用“登记泄漏”让 P1 与「完成」并存；A 自己写「不要把‘少量’读成‘有界’」（[claim.md:353-357](claim.md#L353-L357)） |
| J-6 | A 的「B 只能走字段级支配 / 别名分析，属 L/XL，必须再拆」 | **B（A 的论断不成立）** | B 的原型 `+59/−7`（1 文件，§8 复核 `diffstat`），无新分析 pass；`field_loop0`/`field_loop_bare` 由 HEAD 的 `live=2` 变为 `live=0`，`field_branch0` 由 134 变为 0（§1.2）。A 自己的代价表是 `+245/−20`、B 是 `+280/−22`，差约 35 行，不是 L/XL 差（[claim.md:345](claim.md#L345)、[counter.md:485-492](counter.md#L485-L492)） |
| J-7 | B 的「未初始化结构体局部零初始化」是否需要 USER 授权 | **B（需要，条件 C-1）** | 零初始化是语言语义变化（未初始化字段从“未定义值”变成“空串 / 零句柄”）；B 自己也把它列为隐藏成本与 F2（[counter.md:445-451](counter.md#L445-L451)、[:546](counter.md#L546)）。若 USER 拒绝，B 退到硬错路线（C-1(b)）。这是 B 的成本，不是 A 的胜利；A 同样需要 USER 签 C-A3 |
| J-8 | A 的记录闭合是否满足 G6 / 5.4 | **B** | 卡头「完成」（[phase80:3](../../docs/design/phase80.md#L3)）、roadmap「SH-102 修复」（[roadmap:93](../../docs/roadmap.md#L93)）与 SH-102 `reopened`（[issue:4](../../issues/selfhost/sh102-p80-auto-retain-not-implemented.md#L4)）并存；A 的 C-A4 只写卡 §7.9.7 与 `language-spec`（[claim.md:49](claim.md#L49)），未覆盖卡头与 roadmap。即使 E80-1…8 不含 retain（B 的 F6，[counter.md:452-455](counter.md#L452-L455)），卡 §7.9.1 与 roadmap 已把「SH-102 修复」写成已交付，不能保留「完成」再让 P1 `reopened` |
| J-9 | EDITOR 能否在判决里替 USER 签 C-A3（窄合同） | **B** | §7.9 裁判只判证据 / 判据；0.7 的签收规则；D-013 是 USER 签收的 decision，A 的 C-A3 / F1 也明确「不能由本席或裁判代替 USER」（[claim.md:398-400](claim.md#L398-L400)）。判决只能确认「技术上是否足以消除 UAF」与「泄漏是否可计量」，不能替 USER 改合同 |
| J-10 | 整体：PH-80 能否以 A 收口 | **B** | J-1/J-2/J-5/J-8/J-9 任一成立即足以拒绝 A；J-3/J-4 是双方共同事实，J-6 否定 A 的“B 太贵”论据。A 不成立，必须按 B-1/B-2/B-3 的机械判据补齐（§4），**但不要求新增数据流 pass** |

**条件级对照**（claim 的 C-A / counter 的 B-）：

| 条件 | 判定 | 一句话依据 |
| --- | --- | --- |
| C-A1（结构性无 UAF/SEGV） | **不成立（未实现）** | 只做了汇合丢弃；`field_shadow` 仍 SEGV，`field_ptr` 仍泄漏（§1.2） |
| C-A2（泄漏可计量、登记） | **不成立（合同不允许）** | D-013 §3 是无条件句；REV 已拒绝「登记泄漏」替代（§1.1(a)） |
| C-A3（USER 签收窄合同） | **未满足** | HEAD 无该 decision；A 的 F1 自认（§8） |
| C-A4（台账与文档） | **不充分** | 未覆盖卡头「完成」与 roadmap「SH-102 修复」（§1.1(f)） |
| C-A5（测试） | **未做** | 新夹具与 C-A1 其余规则不在 HEAD；现有 18 项不覆盖 R6（§7） |
| B-1（R6a 结构性消除） | **成立（核心已证）** | B 原型 `field_branch0` 134 → 0（§1.2） |
| B-2（R6b 零泄漏） | **成立（核心已证）** | B 原型 `field_loop0` / `field_loop_bare` `live=2` → 0（§1.2） |
| B-3（边界闭合） | **条件（C-4）** | B 原型 `field_copy` UAF、`field_goto_struct` BUS，必须硬错 / 逐字段 retain |
| B-4（记录一致） | **条件（C-5）** | 卡 / roadmap / issue 三处矛盾未解 |
| B-5（不回归） | **条件（C-6/C-7）** | 新夹具、全量门禁与 ABI 未在完整实现上验 |

### 1.1 关键理由

**(a) A 的收口条件是对 D-013 §3 的改写，不是满足。** D-013 §3 把「字段赋值」放进自动 retain 的
承诺面，并逐字写「重新赋值：先 retain 右值，再 release 旧值」
（[D-013:33](../../docs/decisions/D-013.md#L33)）。A 的 C-A2 允许循环重赋 N−1 泄漏，C-A3 要求新
decision 把该句限定为「仅当 C-A1 标记成立」；这在 HEAD 没有发生。A 自己把 F1 写成「USER 拒绝签
C-A3，A 不成立」，所以 A 至多是**有条件方案**，不是 PH-80 现在可以据以收口的判据。裁判不能替 USER
签，REV 也不能在合同未改时把 SH-102 置 `verified`。

**(b) 即使只看 A 的“安全半部”，它在 HEAD 也不成立。** A 的 E1-5 只做了“块关闭截断字段标记”的
汇合补丁（`+15/−5`），C-A1 还列出 owner 化键、基址重绑清除、整结构体赋值清除、箭头基址关闭 /
取址降级、`goto` 硬错。A 的 F3 自己承认「只做汇合补丁不够」，并点名 `field_shadow` 会误配外层
标记、`field_ptr` 会按旧标记 release。本席在其原型上复跑：
`field_shadow.ct-ast2` → ASan SEGV；`field_ptr.ct-ast2` → `after refs=1 live=2`（泄漏）。也就是说，
A 的“保守 release 无 UAF/SEGV”不是已实现状态；要让它成立，仍需 C-A1 的其余规则。A 的
“便宜”论据建立在一个未完成的原型上。

**(c) B 的核心路线已被实测，A 的“L/XL 新分析”前提被否定。** B 的原型只改 `Emitter.h.ct`
（`+59/−7`）：声明处定义存储（裸声明补 `= { 0 }`、聚合初始化按字段标记 known）＋字段 release
判据从 `N_MEMBER || N_ARROW` 收窄为 `N_MEMBER`。本席复跑其 `/tmp/p80c` 构建：
`field_branch0` 134 → 0、`field_loop0` `live=2` → 0、`field_loop_bare` `live=2` → 0、
`field_loop_pre` 保持 0（§1.2）；`p80_retain` 18/18。生成 C 里 `struct Holder h = { 0 };` 先定义
存储，再在分支 / 循环内 `release` 旧零句柄（[counter.md:262-279](counter.md#L262-L279)）。
这不是支配树、不是别名求解，也不新增分析 pass；A 的“B 必须做数据流、只能给 `live=2`”两条都被
实测否定（A 的关键区分预测见 [claim.md:331-332](claim.md#L331-L332)）。

**(d) B 的原型不完整，但它的缺口是 §4 的条件，不是 A 的胜利。** B 自己也把
`h = other`（整结构体赋值）与 `goto` 跳过零初始化列为未实现硬错的两个洞
（[counter.md:293-347](counter.md#L293-L347)）。本席复跑确认：`field_copy.b` → ASan
heap-use-after-free，`field_goto_struct.b`（101 args）→ ASan BUS（§1.2）。B 因此**不能**把
`+59/−7` 当作完整交付；必须在 C-4 补两条硬错或逐字段 retain。但 A 的 `field_shadow` / `field_ptr`
同样是洞（§1.1(b)），而且 A 的 C-A1 还多出 owner 化键、基址重绑等规则。两边的“完整修复”都要
补边界；B 的核心机制已经同时覆盖 R6a/R6b，A 的汇合补丁只覆盖 R6a 的一半。

**(e) 「字面 vs 安全」是假二选一。** A 的正确观察是：在未定义存储上无条件 `release` 旧值本身
不安全（这正是 R6a）。但 B 的路线不删 `release`、不删 `retain`，而是让存储先定义：`Holder h;`
→ `= { 0 }`，`{ … }` / 裸聚合由 C 零填充；于是「先 retain 右值再 release 旧值」在分支、循环、
`switch` 下都安全。若 USER 拒绝零初始化，退到「未定义存储上的字段 release 硬错」。两条路都不
需要支配 / 别名数据流。A 用“字面句不安全”推出“B 必须做数据流”，这一步不成立；本判决因此
把要求写成**结构性的两条不变量**，而不是“新增分析 pass”。

**(f) 记录与程序。** 卡头、roadmap、SH-102 三处已经互相矛盾（FACT-3）。A 的 C-A4 只处理
§7.9.7 与 `language-spec`，没有处理卡头「完成」和 roadmap「SH-102 修复」；即使 USER 签了窄合同，
「P1 `reopened` + 卡写完成 + roadmap 写已修复」仍然是 G6 的「无结论关闭」。B-4 的记录一致要求
是收口的必要条件，不是附加装饰。

### 1.2 本席独立复跑的证据信号（只读）

**单次探针不是安全证明。** 本席在双方 `/tmp` 构建上各跑多次，确认 R6a 的“必现”只是 UB 的栈
布局表现：

| 探针（HEAD 构建） | 运行 | 结果 |
| --- | --- | --- |
| claim `field_branch`（`cond=0`） | 10 次 | `0 134 0 0 134 134 134 0 0 0`（混合） |
| counter `field_branch0`（`cond=0`） | 10 次 | `134` × 10 |
| REV 的运行期 shape `field_branch_rt` | 1 次 | exit 0 |

因此 J-3 判“成立”依据的是生成的 C（`__ct_sold51 = h.tag` 读未定义字段），不是某一次退出码。
反过来，任何“跑一遍 exit=0 所以安全”的举证都不成立。

**核心行为对照**（同一 HEAD 构建；A proto = `/tmp/p80b` 的 `.p` / `.ct-ast2`；B proto =
`/tmp/p80c` 的 `.b`；`HEAD` = 同目录无后缀二进制）：

| 探针 | HEAD | A proto | B proto |
| --- | --- | --- | --- |
| `field_branch0`（`cond=0`，counter 构建） | 134（10/10） | — | 0 |
| `field_branch`（`cond=0`，claim 构建） | 混合（10 次：0/134） | 0（`.p`） | — |
| `field_branch_rt`（`argc>100`） | 0 | 0 | 0 |
| `field_loop0` | `final live=2` | `final live=2` | `final live=0` |
| `field_loop_bare` | `final live=2` | 未提供 | `final live=0` |
| `field_loop_pre` | `final live=0` | `final live=0` | `final live=0` |
| `field_shadow` | 134 | 134（A `.ct-ast2`） | 0 |
| `field_ptr` | `live=2` | `live=2` | `live=2` |
| `field_copy` | 0 | 未提供 | 134（UAF） |
| `field_goto_struct`（101 args） | 0 | 未提供 | 134（BUS） |

这张表同时说明三件事：①B 的核心机制确实同时覆盖 R6a/R6b；②B 的边界缺口是真的（`field_copy` /
`field_goto_struct`）；③A 的“无 UAF”不成立（`field_shadow` SEGV），A 的泄漏面也真实
（`field_ptr` / `field_loop0`）。双方原型都只是可行性证据，不是交付物。

## 2 整体判决

**A `rejected`；B 的证伪成立。** 按 §7.9：A 的判据未被满足，且反证清单中的失效条件
FA-1（回退已交付行为）、FA-2（无 USER 签收的窄合同）、FA-3（记录未闭合）、FA-4（B 不需要
L/XL）、FA-6（完成记录与 `reopened` 冲突）、FA-7（字面句可在定义存储后为真）均被证据证实。
本判决不是 `undecidable`：D-013 文本、SH-102 状态、REV 结论与双方可复现的行为足以判定。

**判决的准确表述**：

1. PH-80 **不能**以「保守字段 release + 已登记泄漏 + 文档限制」收口。
2. 必须先实现字段 release 的**结构性精确性**：`release` 只作用于已定义存储；同一存储位置的
   字段重赋必须 `release` 旧值；做不到的形状硬错。仅 C-4 明列的触发集外形状（箭头 / 别名 /
   跨函数写等）可按 C-4 登记，不得静默泄漏。
3. **不要求**新增支配树 / 别名数据流；B 的「声明即定义 + 既有 known/release 路径」路线已被
   原型证明是 S 级、无新 pass。A 的“B 必须做数据流”是错误前提。
4. B 的原型**不是**可直接交付的完整修复；`h = other` 与 `goto` 两条边界必须按 C-4 补齐，且
   zero-init / 硬错语义要有 USER 签收的 decision（C-1）。
5. A 若将来拿到 USER 对窄合同的签字，按 §6.1 重开；本判决不替 USER 改 D-013。

## 3 不采纳

| # | 不采纳项 | 理由 |
| --- | --- | --- |
| 1 | 「保守字段 release + 已登记泄漏即可收口」（A 的核心） | 违反 D-013 §3 的字面承诺；REV 两轮拒绝；泄漏线性无界；G6 不能与 `reopened` P1 并存 |
| 2 | 「B 需要字段级支配 / 别名数据流，属 L/XL」（A 的代价论据） | B 的 `+59/−7` 原型同时把 R6a/R6b 转绿，无新分析 pass；A 自己的代价表也只差约 35 行 |
| 3 | 「先写完成，USER 稍后补签窄合同」 | 有条件方案不是收口；判决不能替 USER 签；无 decision 的「完成」是虚假记录 |
| 4 | 「E80-1…8 不含 retain，所以 PH-80 可以先收口、SH-102 单独 reopened」 | E80 清单确实不含 retain（B 的 F6 成立），但卡 §7.9.1 与 roadmap 已把「SH-102 修复」写成已交付；要么撤回这些文字，要么让 SH-102 `verified`，不能两者并存 |
| 5 | 「少量 / 已登记泄漏是可接受的」 | A 自己写「不要把‘少量’读成‘有界’」；N 次循环泄漏 N−1，长驻程序会持续涨；这不是“少量” |
| 6 | 「B 的原型也有洞，所以 A 更完整」 | B 的洞是 `h = other` / `goto`，A 的洞是 `field_shadow` SEGV / `field_ptr` 泄漏，且 A 还有四条 C-A1 规则未实现；两边都要补，B 的核心覆盖 R6a+R6b，A 的汇合补丁只覆盖 R6a 的一半 |
| 7 | 「零初始化未授权，所以 B 不可行」 | B 有硬错退路（C-1(b)）；A 同样要 USER 签 C-A3。零初始化是 B 的成本，不是 A 的胜利 |

## 4 条件（可机械验收）

> 全部条件要求**入库**（`git log` 可追溯）且**有原始输出**；未入库的草稿、口头确认、卡内备注
> 不算。命令在仓库根执行；`<ct-ast>` = 修复后由 `bash selfhost/check-ast.sh` 构建的二进制；
> `<fix>` = 实现提交；`<test>` = 红证提交。C-1…C-4 是实现的前置；C-5…C-9 是收口的前置。

### C-1 语义 / 合同 decision（阻断）

- 条件：新 decision `docs/decisions/D-015.md`（HEAD 上未被占用；若入库时已被占用，用下一个空号，
  判决按实际号执行），`target: v0-PH-80`、`signer: USER`、`date:` 非空；内容必须二选一并写清：
  - **(a) 零初始化路线**：含 owning 字段的结构体局部在声明处定义为零句柄（`= { 0 }`），并说明
    `h = other`、`goto` 的处置；
  - **(b) 硬错路线**：无法证明已定义的字段 `release`、整结构体赋值、`goto` 跳过零初始化等形状
    一律硬错，并逐条给出诊断与负例。
- 不得用该 decision 删除 D-013 原文；若涉及 D-013 的合同解释，按 §7.12.1 在末尾追加注记。
- 机械验收：

```console
$ test -f docs/decisions/D-015.md
$ grep -Eq 'target: *v0-PH-80' docs/decisions/D-015.md
$ grep -Eq 'signer: *USER' docs/decisions/D-015.md
$ grep -Eq 'date: *2026-' docs/decisions/D-015.md
$ grep -qE '零初始化|zero-init|硬错|hard error' docs/decisions/D-015.md
$ git log --oneline -1 -- docs/decisions/D-015.md
```

### C-2 R6a：release 只作用于已定义存储

- 夹具：`field_branch0`（编译期 `cond=0`）、`field_branch_rt`（运行期 `argc>100`）、
  `field_switch`（`case` 未执行）、`field_goto`（`goto` 跳过字段赋值）。
- 判据：修复后每个程序在 ASan/UBSan 下 **10/10 exit 0**；生成的 C 在首次 `__ct_sold = h.tag`
  之前已有 `struct Holder h = { 0 };`（或等价的显式定义）；若走硬错路线，编译必须以明确诊断
  拒绝（exit≠0），并附负例夹具。
- 机械验收（以 `field_branch0` 为例；其余同形）：

```console
$ CT_STD_DIR=lib/std <ct-ast> --allow-c-boundary test/ast/p80_retain/field_branch0.ct -o /tmp/p80/fb0.c
$ cc -std=c99 -fsanitize=address,undefined -g /tmp/p80/fb0.c -o /tmp/p80/fb0
$ for i in $(seq 1 10); do ASAN_OPTIONS=detect_leaks=0 /tmp/p80/fb0; test $? -eq 0 || exit 1; done
$ grep -q 'struct Holder h = { 0 };' /tmp/p80/fb0.c
$ ! grep -q 'struct Holder h;' /tmp/p80/fb0.c
```

### C-3 R6b：同一存储位置的字段重赋 release 旧值

- 夹具：`field_loop0`（`Holder h = { 0 }`）、`field_loop_bare`（裸声明）、
  `field_loop_pre`（循环前直线赋值）、`field_loop_long`（迭代数 100，防止只对 3 次调参）。
- 判据：`field_loop0` / `field_loop_pre` / `field_loop_long` 均 `final live=0`；
  `field_loop_bare` 在零初始化路线下 `final live=0`，在硬错路线下以诊断拒绝（exit≠0）；
  ASan/UBSan 无报告；生成 C 的循环体内有旧值 `release`（`__ct_sold`）。
- 机械验收：

```console
$ CT_STD_DIR=lib/std <ct-ast> --allow-c-boundary test/ast/p80_retain/field_loop0.ct -o /tmp/p80/fl0.c
$ cc -std=c99 -fsanitize=address,undefined -g /tmp/p80/fl0.c -o /tmp/p80/fl0
$ ASAN_OPTIONS=detect_leaks=0 /tmp/p80/fl0 | tail -1
final live=0
$ grep -q '__ct_sold' /tmp/p80/fl0.c
```

### C-4 B-3 边界闭合

| 形状 | 可接受结果 | 机械验收 |
| --- | --- | --- |
| `h = other`（整结构体赋值） | 硬错（推荐）或逐字段 retain + release 旧字段；**不得**静默浅拷贝后让字段 release | 硬错：编译 exit≠0，诊断含 `whole-struct` / `owning`；逐字段：ASan 无报告且 `final live=0` |
| `goto` 跳过含 owning 字段的结构体局部零初始化 | 硬错，或使零初始化不可跳过 | `neg_goto_struct.ct` 编译 exit≠0，诊断含 `goto`；或运行 ASan 无报告 |
| `p->tag` / `(&h).tag` / 跨函数写 / 并发写 | 不自动 `release`；旧值泄漏可接受，但必须登记触发条件与去向 | `field_ptr` ASan 无报告（`live=2` 允许）；卡 §7.9.7 有对应行 |
| 同名遮蔽 `field_shadow` | 正确 release 内层 / 不 SEGV，或硬错 | ASan 通过（本席 B 原型 `.b` 为 `inner refs=1 live=2` / `outer refs=1 live=1`）或明确诊断 |
| `foreach item` / `for` 初始化器 / 嵌套结构体字面量 / 泛型 `T` | 沿用卡 §7.9 既有边界，或硬错；每条有 issue / §7.9.7 去向 | `grep` 卡 §7.9.7 有对应条目；不得静默泄漏 |

- 整结构体赋值若选逐字段 retain，必须同时处理“旧字段 release + 新字段 retain”，并有
  `field_copy` 的 ASan + `final live=0` 证据；若选硬错，`field_copy` 必须在编译期拒绝，不能生成 C。
- 机械验收以 `test/ast/p80_retain.sh` 的 `neg_copy` / `neg_goto_struct` / `field_copy` /
  `field_goto_struct` 条目为准，全部输出 `ok` 或明确诊断。

### C-5 台账与文档闭合

- 二选一，且必须与 C-2…C-4 的实际状态一致：
  - **通过**：DEV 在 SH-102 写 `fixed` 处置段；REV 独立复现后把 `status` 改为 `verified`；
    卡头「完成」、roadmap「SH-102 修复」、`language-spec` 的「重新赋值」句与实现一致；
  - **未通过**：SH-102 保持 `reopened`；卡头 / roadmap **撤回**「完成 / SH-102 修复」的表述，
    不得在 `verified` 前保留。
- `language-spec` 不得再写未实现的无条件句；D-013 原文不动；若 USER 签了窄合同，按 §7.12.1
  追加 `superseded-by` 注记，并同步卡 §7.9.1 / §7.9.7。
- 机械验收：

```console
$ grep -n '^status: verified' issues/selfhost/sh102-p80-auto-retain-not-implemented.md
$ grep -n '状态：完成' docs/design/phase80.md
$ grep -n 'SH-102' docs/roadmap.md
$ grep -n '重新赋值' docs/design/phase80.md docs/language-spec.md
$ bash tools/check.sh g6
$ python3 test/docs/check-docs.py
```

> 若选“未通过”分支，上列 `verified` / `完成` / `SH-102 修复` 应为空；若选“通过”分支，三者必须
> 同时出现且互相不矛盾。G6 不接受「完成 + reopened」并存。

### C-6 测试与红证

- `test/ast/p80_retain` 新增至少 9 个夹具：`field_branch0`、`field_branch_rt`、
  `field_loop0`、`field_loop_bare`、`field_loop_pre`、`field_loop_long`、`field_copy`、
  `field_goto_struct`、`field_shadow`（`field_ptr` 可复用现有探针）；每个正例有 `expected.*.out`，
  每个负例有明确诊断。
- `p80_retain` 的 `ok` 行 **≥ 24**（当前 18），最后一行 `p80_retain: OK`；ASan/UBSan 至少各覆盖
  一个 R6 负例。
- 红证：`test(ct-ast): <task-id> 红` 提交只含夹具与原始输出，`baseline: 953c19e0`；实现提交
  `fix(...)` 是其子提交（T-7）。红证输出不得用当前代码复跑替代。
- 机械验收：

```console
$ sh test/ast/p80_retain.sh <ct-ast> | grep -c '^ok'
24
$ sh test/ast/p80_retain.sh <ct-ast> | tail -1
p80_retain: OK
$ git log --oneline -2
$ git merge-base --is-ancestor 953c19e0 HEAD
```

### C-7 不回归

- `check-ast`：`0 failed`，`passed ≥ 1538`（当前基线；新增夹具后可增加），`5 skipped`；
  `p80_layout` 的 `gap param_refs=2` 不变；`check-sanitizers`: `583 checks`（当前基线，可增加）、
  无报告；`check-all`: 11 道硬门禁绿；`check-docs` 绿。
- 不改 `refs` 布局、16 字节句柄、8 字节头、生成 C 的 ABI；除 `test/ast/p80_*` 的期望输出外，
  不改既有 golden。
- 机械验收：

```console
$ bash selfhost/check-ast.sh 2>&1 | tail -1
== summary: 1538 passed, 0 failed, 5 skipped ==   # passed 可增加；0 failed / 5 skipped 不变
$ bash selfhost/check-sanitizers.sh 2>&1 | tail -1
check-sanitizers: OK (583 checks, no sanitizer report)   # 当前基线；可增加
$ bash selfhost/check-all.sh 2>&1 | tail -1
check-all: OK (11 hard gates green)
$ python3 test/docs/check-docs.py
$ sh test/ast/p80_layout.sh <ct-ast> | grep -q 'gap param_refs=2'
$ bash tools/check.sh g0 && bash tools/check.sh g6 && bash tools/check.sh g8
```

### C-8 版本、tag 与顺序门

- 同一缺陷返工，按 §6.7 V-3 不重复 `+1`；不新增 MINOR。若项目按 `deviation: fix-tags` 需要新
  fix tag，必须在 SH-102 `verified` 之后创建，指向实现提交，且五处 `CTC_VERSION` 一致。
- PH-80 的收口提交必须晚于 C-1…C-7；PH-81/82 仍按入口串行，不因本判决放行。
- 机械验收：

```console
$ grep -n 'CTC_VERSION' selfhost/l0/ctc.c selfhost/l1/ctc.ct selfhost/l2/core.ct \
    selfhost/l2/driver.ct selfhost/ct-ast/main.ct
$ git tag --list 'v0.80.*'
$ git rev-parse <new-tag>^{commit}   # 若新建 tag，必须等于修复提交
$ bash tools/check.sh g8
$ git log --oneline -- docs/decisions/D-015.md docs/design/phase80.md
```

### C-9 现在允许 / 不允许

| 工作 | 现在允许 | 判据 |
| --- | --- | --- |
| `/tmp` 隔离原型、探针 | 是 | 不落 `selfhost/**` 实现；不把 `/tmp` 输出当交付 |
| 新夹具（红） | 是 | `test/ast/p80_retain/*.ct` + `expected.*.out`，按 T-7 先红 |
| D-015 起草 / USER 签收 | 是 | C-1；未签字的草稿不算 |
| 卡 §7.9.7 / language-spec 措辞修订 | 是 | 不得先写「已修复」；与实现状态一致 |
| 以「保守 release + 登记泄漏」宣布 PH-80 完成 | **否** | 本判决 A；C-1…C-8 未过 |
| 把 SH-102 置 `verified` | **否** | 必须 C-2…C-5 全过且 REV 独立复现 |
| 打 tag / bump MINOR / 宣布 PH-80 收口 | **否** | C-8 顺序门 |

## 5 生效范围

- **PH-80**：收口判据按本判决 §4；卡 §7.9 / §7.9.1、`language-spec` 的 retain 段、
  `docs/roadmap.md:93`、SH-102 的处置与状态均受约束。`version-minor=80` 不动，不 bump，不新增
  phase tag。
- **SH-102**：在 C-2…C-5 全过并由 REV 独立复现前，保持 `reopened`；不得写 `verified`，不得在
  卡 / roadmap 写「已修复」。
- **PH-81 / PH-82**：仍按 `P-7.5 + PH-80 收口` / `PH-81 收口` 串行；本判决不放行，也不改其入口。
- **D-013**：原文不改；若 USER 签 C-1 / C-A3，按 §7.12.1 追加注记，不重写原文。
- **范围外**：本判决不评价 PH-78/79 的已收口结论、不评价 PH-83/包管理、不评价 A/B 原型的
  代码风格；`/tmp` 产物不构成本判决的交付物。

## 6 失效条件

1. **USER 签收窄合同**：若 USER 以新 decision 明确「D-013 §3 的重新赋值只覆盖直线代码；字段
   控制流泄漏由作者负责」，J-1/J-5/J-9 被该 decision 取代；本判决按 §7.9 重开，A 的 C-A1 仍需
   满足 C-2（R6a），且 C-A4 必须扩展到卡头 / roadmap。
2. **USER 签收零初始化 / 硬错语义**：C-1 满足，B 路线按 C-2…C-4 执行；本判决的结论不变，只是
   从“待授权”转为“可开工”。
3. **B 路线被证明不可行**：若完整实现（含 C-4 两条硬错）在真实消费者 / 全量门禁上造成不可接受
   的回归，且无更小的安全替代，则 B 的“同阶成本”论据失效，需重开并考虑 A 的窄合同；但 R6a 的
   安全修复仍不得放弃。
4. **REV 独立复核通过**：SH-102 置 `verified` 后，FACT-3 的矛盾消失；本判决的“未收口”前提被
   满足，不是被推翻。此时只按 C-5/C-8 检查记录与顺序。
5. **正式裁定 E80 是唯一收口判据**：若 USER/EDITOR 明确 PH-80 的 E80-1…8 与 SH-102 状态分离，
   “PH-80 不得收口”部分可收窄；但 SH-102 仍不得 `verified`，卡 / roadmap 不得在未修复时写
   「SH-102 修复」。本判决的 R6a/R6b 技术判断不因此改变。
6. **用户裁决**：用户是最终权威；放宽必须按 0.7 / §6.7 留下 `deviation:` 或 decision（签字 +
   日期），不得由执行侧自行选择。

## 7 证据限制

- **本场缺 `question.md` 与 `verify.json`**：`python3 tools/check-battle.py phase80-retain-scope-1`
  输出 `FAIL question.md missing`、`warn verify.json not written yet (required before verdict)`，
  exit 1（§8）。因此 §7.8 T0/T4 未满足，本场没有独立证据席；本判决的事实基础是 claim/counter
  的原始输出 + 本席在 `/tmp` 构建上的只读复跑。
- **本文件的 `closed` 是判决状态，不是归档状态**：`battle.sh close` 需要 `question.md` /
  `verify.json`；在补齐前，`battle/phase80-retain-scope-1/` 不能按 §7.8 T7 归档。
- **claim/counter 未入库**：`git status --porcelain` 只有 `?? battle/phase80-retain-scope-1/`；
  本判决引用的是文件行号，不是提交 sha。
- **双方原型均未提交**：A 的 `/tmp/p80b`、B 的 `/tmp/p80c` 是隔离副本，不是交付物。本席复跑了
  其中的二进制，但没有从 HEAD 重新构建，也没有逐行复核两个 patch 的重放；`+15/−5` 与
  `+59/−7` 只复核了 `diffstat`，不是对完整实现的验收。
- **R6a 的单次信号不可靠**：claim 的 `field_branch` 10 次中 4 次 exit 134、6 次 exit 0；
  `field_branch_rt` 本次 exit 0；counter 的 `field_branch0` 10/10 exit 134。三者都是 UB 的栈
  布局表现，不能用某一次退出码证明“安全”或“必现”；本判决只把生成的 C 当结构性证据。
- **未跑完整门禁**：本席没有在修复后的实现上跑 `p80_retain` / `check-ast` / `check-all` /
  sanitizer / `check-docs`；C-6/C-7 是条件，不是已证事实。双方原型的 `p80_retain` 18/18 本席
  复跑通过，但该脚本当前只有 18 项，未覆盖 R6，不能作为安全证据。
- **A 的 `field_switch` / `field_goto` 未复跑**：`/tmp/p80b/probes` 中没有这两个二进制；claim
  的生成的 C 已足以显示“未初始化 release”的结构，但本判决不声称其退出码已复现。
- **B 的 `field_copy` / `field_goto_struct` 已复跑为红**：B 的原型在这两个形状上 UAF / BUS；
  B 自己也在 counter §7 承认。C-4 因此是阻断条件，不是可选项。
- **锚点校验**：`check-battle` 对 claim/counter 的内联短名给出 43 条 anchor 警告（`field_branch.c`、
  `Emitter.h.ct`、`claim.md` 等未解析为完整路径）；本判决的关键锚点由本席逐条读取，但未由独立
  证据席机器校验。
- **T-8 签收**：本判决由 EDITOR 席出具；按项目 0.7，battle 判决的默认签收是 REQ 或 REVIEW
  （不得自签）。本文件的庭外签收待 REQ/REVIEW 补记，不影响判决的生效范围。

## 8 证据附录（本席在本机只读复跑）

> 以下是关键行摘录；`...` 表示省略的逐行 `iter` 输出或 ASan 栈，退出码与结论行保留。
> 命令中的 `<ct-ast>` 指修复后构建的二进制；本节用的是双方 `/tmp` 构建。

```console
$ git rev-parse HEAD
953c19e0696819252f112b72f5f3e99167d70a89
$ git log -1 --oneline
953c19e0 review: PH-80 第三轮复核（SH-102 仍 reopened）

$ grep -n '重新赋值' docs/decisions/D-013.md
33:- 重新赋值：先 retain 右值，再 release 旧值；
$ grep -n '^status:' issues/selfhost/sh102-p80-auto-retain-not-implemented.md
4:status: reopened
$ grep -n '状态：完成' docs/design/phase80.md
3:> **状态：完成**（2026-11-20 立项并开卡；D-013 签收后 S5a-1…4、S5b-1 删旧迁移与 S5b-2 文档
$ grep -n 'Phase 80' docs/roadmap.md
93:| Phase 80 | `String` / `Str`（S5；UTF-8/UTF-16 双类型、L1 字面量、std 迁移） | ✅ 完成（v0.80.2，SH-102 修复） | v0.80.2 | [卡](design/phase80.md) · [安排](planning/pointer-free-phase-plan.md) · [提案](proposals/pointer-free-v2.md) |
$ test -e docs/decisions/D-015.md; echo exit=$?
exit=1

$ python3 tools/check-battle.py phase80-retain-scope-1; echo exit=$?
check-battle: phase80-retain-scope-1
  rounds: 1/3
  FAIL  question.md missing
  warn  verify.json not written yet (required before verdict)
  FAIL (1 errors, 43 warnings)
exit=1
```

**核心探针**（`/tmp` 构建；`ASAN_OPTIONS=detect_leaks=0`）：

```console
# B prototype：R6a / R6b 同时转绿
$ cd /tmp/p80c/probes
$ ./field_branch0; echo exit=$?          # HEAD 为 134
after branch refs=1 live=1
exit=0
$ ./field_loop0; echo exit=$?
...
final live=0
$ ./field_loop_bare; echo exit=$?
final live=0
$ ./field_loop_pre; echo exit=$?
final live=0
$ ./field_shadow; echo exit=$?
inner refs=1 live=2
outer refs=1 live=1
exit=0
$ ./field_ptr; echo exit=$?
after refs=1 live=2
exit=0

# B prototype 的两个洞（必须由 C-4 关闭）
$ ./field_copy.b; echo exit=$?
AddressSanitizer: heap-use-after-free ...
exit=134
$ ARGS=$(seq 1 101); ./field_goto_struct.b $ARGS; echo exit=$?
AddressSanitizer: BUS ...
exit=134

# A prototype：汇合补丁后 R6b 仍泄漏，F3 的 shadow 仍 SEGV
$ cd /tmp/p80b/probes
$ ./field_loop0.p; echo exit=$?
final live=2
$ ./field_shadow.ct-ast2; echo exit=$?
AddressSanitizer: SEGV ...
exit=134
$ ./field_ptr.ct-ast2; echo exit=$?
after refs=1 live=2
exit=0
```

**单次信号不确定性**：

```console
$ cd /tmp/p80b/probes
$ for i in $(seq 1 10); do ASAN_OPTIONS=detect_leaks=0 ./field_branch; echo -n "$? "; done
0 134 0 0 134 134 134 0 0 0
$ cd /tmp/p80c/probes
$ for i in $(seq 1 10); do ASAN_OPTIONS=detect_leaks=0 ./field_branch0; echo -n "$? "; done
134 134 134 134 134 134 134 134 134 134
```

**`p80_retain` 复跑**（两个原型，均为 18 项）：

```console
$ CT_C_BOUNDARY=allow sh test/ast/p80_retain.sh /tmp/p80c/work/ct-ast2 | tail -1
p80_retain: OK
$ CT_C_BOUNDARY=allow sh test/ast/p80_retain.sh /tmp/p80c/work/ct-ast2 | grep -c '^ok'
18
$ CT_C_BOUNDARY=allow sh test/ast/p80_retain.sh /tmp/p80b/work/ct-ast2 | tail -1
p80_retain: OK
```

**`diffstat` 复核**：

```console
$ diff -u /tmp/p80b/work/emitter.orig.ct /tmp/p80b/work/Emitter.patched.ct | diffstat
 Emitter.patched.ct |   20 +++++++++++++++-----
 1 file changed, 15 insertions(+), 5 deletions(-)
$ diff -u /tmp/p80c/selfhost/ct-ast/backend/emit/Emitter.orig.ct \
    /tmp/p80c/selfhost/ct-ast/backend/emit/Emitter.h.ct | diffstat
 Emitter.h.ct |   66 ++++++++++++++++++++++++++++++++++++++++++++++++++++-------
 1 file changed, 59 insertions(+), 7 deletions(-)
```

本判决未修改源码、卡、issue、decision、roadmap、tests；只写本文件。
