# PH-53 立项草案：候选、依据与待裁项

> **状态：讨论材料（2026-11-15）；Q1/Q2 已落定：PH-53 = `?.` 可选链，施工卡见 [design/phase53.md](../design/phase53.md)。**
> 其余候选处置见 §8；本文件不再是待拍板草案，保留为选择依据。
> **基线**：`1d49bb1a`（`v0.52.0` 之后 4 个纯文档提交；工作树干净）。
> **纪律**：本文件只新增文档；不改实现、不改卡片判据、不改 golden、不 bump、不 push、不打 tag。
> **证据口径**：仓库内事实带文件与行号；仓库外事实写明来源路径，未在本机重跑。

---

## 0 一页结论

1. **PH-46–52 已全部实施完毕**：七张卡的状态行均为「完成」，`v0.46.0`–`v0.52.0` 七个 annotated tag
   本地与 `origin` 一致；`v0.52.0` 收口提交正文记录 `check-all 11/11`、`check-ast 1420/0`。
   当时 `docs/roadmap.md`、`docs/README.md`、`phase46-52-plan.md`、`phase46-52-handoff.md`
   仍写着「50–52 待实施 / 下一刀 PH-50」——**本轮已修正**（§8）。
2. **PH-53 当时只是 `?.` 的占位记录**，状态「记录 / 待商定 / 暂不排期」。2026-11-15 已裁定：
   PH-53 = `?.` 可选链施工，卡面 [design/phase53.md](../design/phase53.md)，见 §8。
3. **当时建议首选 A1（前端 DF-1/DF-2/DF-3）**；该建议已被 Q1 裁定取代：A1 留需求池 / 后续相，
   **不进 PH-53**。理由与证据仍保留在 §2.1。
4. **当时次选 A2（REQ-JSACCESS-1）与 A3（B-2/SH-73）**；两者均不进 PH-53，处置见 §8。
5. **文档真相**：roadmap / docs/README / plan / handoff 的 50–52 排期矛盾已修正；
   能力缺口总表与 `language-spec.md:673` 仍留后续文档治理（§8 C3）。
6. 5 道题的落定情况见 §8：Q1/Q2/Q4 已定，Q3/Q5 仍开放；本文件保留为选择依据。

---

## 1 仓库实际状态核对（只读）

### 1.1 已核实的事实

| 项 | 实测值 | 证据 |
| --- | --- | --- |
| HEAD / 分支 | `1d49bb1a`，`main` 比 `origin/main` 领先 4 个文档提交 | `git status -sb`；`git log --oneline -5` |
| 收口 tag | `v0.45.0`–`v0.52.0` 均为 annotated tag，远端同名 tag 指向同一提交 | `git cat-file -t v0.52.0`；`git ls-remote --tags origin` |
| 50–52 卡面 | 三张卡第 3 行均为「状态：完成（2026-11-15；v0.5x.0；S1–S5 全绿）」 | [phase50.md:3](../history/design/phase50.md)、[phase51.md:3](../history/design/phase51.md)、[phase52.md:3](../design/phase52.md) |
| 收口门禁记录 | `v0.52.0` 正文：`check-all 11/11；check-ast 1420/0、warnings 667/0、docs 1224/243` | `git log -1 43b8c992` |
| 版本落点 | `CTC_VERSION` 五处为 `0.52.0`（`main.ct`、`l0/ctc.c`、`l1/ctc.ct`、`l2/core.ct`、`l2/driver.ct`） | `selfhost/ct-ast/main.ct:36` |
| 门禁重跑 | **本次未重跑**：只读核对，未构建、未执行仓库脚本；上述数字引自收口提交正文 | 见 §1.3 |

### 1.2 文档与实际状态的不一致（如实登记）

| # | 位置 | 现在写的 | 实际 | 影响 |
| --- | --- | --- | --- | --- |
| 1 | [roadmap.md:74](../roadmap.md) | 「Phase 50–52 已于 2026-11-15 签字定稿、**待实施**」 | 同一文件 `:66-68` 三行均写「✅ 完成 / v0.50.0–v0.52.0」 | 同一文件自相矛盾，读者无法判断该不该派工 |
| 2 | [docs/README.md:47](../README.md) | 「46–49 已收口，**50 起待实施**」 | 50–52 已收口 | 索引页把已收口相标成待实施 |
| 3 | [docs/README.md:52](../README.md) | 「Phase 50–52……**未实施**」 | 同上 | 同上 |
| 4 | [phase46-52-plan.md:66-68](../design/phase46-52-plan.md) | 50–52 状态为「定稿（2026-11-15 签字）」 | 已收口；同文件 `:42` 仍写「下一刀是 PH-50」 | 计划表与卡面、tag 冲突 |
| 5 | [phase46-52-handoff.md:13](../design/phase46-52-handoff.md)、`:26`、`:139` | 顺序图停在 52；「下一刀是 PH-50」 | 52 已收口 | 施工手册会把执行方送回已完成的相 |
| 6 | [roadmap.md:69](../roadmap.md) | Phase 53 = `?.` 记录，状态「记录 / 待商定 / 暂不排期」 | `?.` 未立项、未评审通过；占着相号 | 与「不立项不占相号」口径冲突；本次立项前必须先处置 |
| 7 | [language-capability-gaps.md:1530-1557](language-capability-gaps.md) | C-4、E-2、E-4、F-1、G-2、G-3、G-4 仍标「未修 / 未定义」 | 分别由 PH-46、47、52、48、49 收口 | 能力缺口总表会诱导重复立项 |
| 8 | [language-spec.md:673-677](../language-spec.md) | 「**仍未修**：impl 方法或自由函数返回局部接口值时……悬垂」 | SH-75 已于 `b5797cbf` 修复（该提交在 `v0.44.2` 内） | 规范正文落后于实现，用户会按旧缺陷做规避设计 |

### 1.3 流程缺口（只登记，不补造）

- `v0.50.0`–`v0.52.0` 三次收口各自只有**一个提交**，同一提交里同时含实现、夹具、文档与版本 bump；
  提交正文写 `red: n/a（版本收口）`。这不符合 T-7「红证提交是实现提交的父提交」，
  也与 [handoff §5](../design/phase46-52-handoff.md) 的五样证据要求不一致。
- 45–49 的同类缺口已在 [plan §13.1](../design/phase46-52-plan.md) 登记，并写明「后续相须先红后绿」；
  50–52 又重复了一次。**不得事后补造红证**；可做的是补回归夹具（不冒充红证）与前向门禁（§2.3 C2）。
- 本次未重跑 11 道门禁，原因是不在只读核对范围内执行仓库脚本/构建；因此「11/11 绿」只是
  `v0.52.0` 收口时的记录值，不是本次复测值。

### 1.4 无法从本仓库核实的事项

- 下游仓库的当前 HEAD 与其探针复跑结果：只读到了它们的文档结论（§3），未在本机重建下游。
- `install.sh` 安装出的 `ct` 版本：本机 `PATH` 中没有 `ct` / `ct-ast`，无法用安装产物复跑探针。

---

## 2 候选任务清单（分类、排序、依据）

排序原则：先「解除下游阻塞」，再「语言能力缺口」，最后「工程质量与工具链」。
同一类内按「是否静默错产物 → 有无绕法 → 影响面」排。成本量级沿用仓库既有估算口径，
没有估算的写明「未估」，不编造行数。

### 2.1 解除下游阻塞

| 序 | 候选 | 依据（可核查） | 范围与成本量级 | 风险 / 前置 |
| --- | --- | --- | --- | --- |
| A1 | **`ct build` 前端三缺陷 DF-1/DF-2/DF-3** | DF-1：`#` 行超过 159 字节被静默截断，`ct` rc=0；截断点合法时 6 变 3（[ct-build-frontend-defects.md:29-131](ct-build-frontend-defects.md)）。代码仍在：T_PP 分支 `Lexer.h.ct:90-99` 不置 `toktrunc`，而标识符分支 `:108-110` 会置；`MAX_TEXT` 为 160（`:18`）。RILL 因此退回单文件 `ctc`（同文 `:15-21`）。 | DF-1 中（切片存储 + 去重键；或先做「越界即硬错」的小方案）；DF-2 低–中（依赖 DF-1 存储）；DF-3 低（另有独立修法，[同文:201-278](ct-build-frontend-defects.md)）。按 PH-52 的量级校准约 200–400 行 ±40%。 | DF-2 必须先有 DF-1 的存储改造，否则拼接后立即截断，比现状更坏（同文 `:185-186`）。DF-1 可先上「硬错」版单独止血。 |
| A2 | **REQ-JSACCESS-1：下标参数类型匹配（`v[0]`）** | PH-52 只主张单层字符串键；`v[0]` 实测展开成 `get(0)` 并静默返回空（[phase52.md:58-61](../design/phase52.md)）。ct-json 的目标形态是 `data["server"]` / `items[0].name`（`/Users/samxx/trae-ws/ct-json/README.md` 的 ADR-0007 段）。需求已登记、不占相号（[requirements-pool.md:66-98](../planning/requirements-pool.md)）。 | 未估；按 PH-52 同类 250–470 行估，另加候选签名匹配与诊断。 | 依赖 PH-52 收口（已满足）。多级连写仍归包层，不在本项。 |
| A3 | **B-2 / SH-73：方法结果作接收者（一行链）** | ct-http 的产品形态是一行链，现只能逐跳落变量；规约明写「方法调用的结果不能直接作下一跳接收者」（[language-spec.md:668-670](../language-spec.md)）。缺陷卡：[SH-73](../../issues/selfhost/sh73-temp-receiver-dynamic-dispatch.md)。 | plan 给 100–300 行，且改既有生成物（[phase46-52-plan.md:191](../design/phase46-52-plan.md)）。 | 有明示降级路径；会动生成形状与 golden，风险高于 A1。 |
| A4 | **ABI 导出面加固：REQ-ABI-3 / REQ-ABI-4 / REQ-ABI-2** | `.abi.h` 只为 `struct` 补前置声明，`enum` / `union` 形参被跳过（[requirements-pool.md:131-155](../planning/requirements-pool.md)）；`ABI_HASH` 只折函数名（`:118-129`）。nexcore 的基线是 `ct v0.44.2`，P1 依赖 C ABI 与 `nm` 白名单（`/Users/samxx/trae-ws/nexcore/docs/README.md` 状态行、`docs/roadmap.md` P1）。 | REQ-ABI-3/4 各约 10–30 行 + 头 golden；REQ-ABI-2 约 10 行 + 1 golden（需求池原文）。 | 触发条件是「下游用 `#if` 做编译期 pin」；当前是防御性加固，不是硬阻塞。 |

### 2.2 语言能力缺口

| 序 | 候选 | 依据（可核查） | 范围与成本量级 | 风险 / 前置 |
| --- | --- | --- | --- | --- |
| B1 | `?.` 可选链（指针 / map） | 前置裁定：map 键缺失整链跳出、结果 NULL；指针接收者 `p?.field` 展开为 `(p ? p->field : 0)`；切词在 parser 内按 `?` 后 token 组合识别，`c?.5 : 1.0` 保持三目，**不是阻塞项**（[battle 记录 §3](../reviews/phase53-optional-chain-battle.md)）。普通 struct 值接收者已于 2026-11-15 裁定**不支持**（[battle §2](../reviews/phase53-optional-chain-battle.md)）：值类型没有「不存在」状态，零值/哨兵不可判定，含 Drop 字段浅拷贝 ASAN 双释放；但**值上取到的指针/map 跳允许继续 `?.`**（`a.b?.c`；`a.m["k"]?.c` 要求 `Map<K, V>` 的 `V` 是值类型，`V` 为指针时 `get` 返回 `V**`，直接 `?.c` 不成立），接收者只求值一次。当前实现两者走同一 `'?' needs a Result operand`，卡面必须先补接收者判定。`a?[k]` 仍单列。 | 未估；只做指针/map 链，范围小于原「重新设计」；不引入 `Maybe<T>` / `T?`。 | 若要求值语义可缺失，须另立可空类型相；不得塞进本卡，也不得用零值冒充缺失；正例与反例必须分别有夹具。 |
| B2 | `.h.ct` 内允许 `defer` / `errdefer` | 明文限制：`defer is not allowed in a .h.ct unit`（[language-spec.md:441](../language-spec.md)；实现 `Stmt.h.ct:1492`）。包作者只能逐失败点手写释放，漏释放风险随失败点线性上升（[plan §11 #13](../design/phase46-52-plan.md)）。 | 未估；属语义放宽，需先定「`.h.ct` 的出口」规则。 | 与「接口单元不产生实现」的既有模型相邻，容易扩成新相；收益是包作者体验，不是下游硬阻塞。 |
| B3 | A-3：类型位置的限定名 `ns::Type` | 多单元多命名空间包只能靠 alias 绕；缺口表标 P2、未修（[language-capability-gaps.md:1534](language-capability-gaps.md)）。 | 「动四处文法」，无行数估算（[plan §6](../design/phase46-52-plan.md)）。 | 与 PH-51 的类型求值面相邻；改动面广。 |
| B4 | G-1：同单元同名函数只告警 | `cc` 报 conflicting types，诊断在 C 编译器（缺口表 `:1550`）。 | 小；诊断前移即可。 | 价值低，绕法便宜（改名）。 |
| B5 | N-9 / E-3 / C-1：跨 union 字段链、匿名 union 具名成员、裸泛型类型名 | 均有便宜绕法，plan §6 已判「不做 / 不进本波」（[phase46-52-plan.md:195-201](../design/phase46-52-plan.md)）。 | 小。 | 建议只补「不允许」诊断，不放开能力。 |
| B6 | REQ-MEM-2：借用经调用/字段逃逸的一层写入摘要 | 需求池给 300–600 行 + 夹具（[requirements-pool.md:189-205](../planning/requirements-pool.md)）。 | 300–600 行。 | 新判定族；不做跨单元。 |
| B7 | REQ-TYPE-1：默认路径全量类型检查 | 461 语料 rc 与 `test/cases/*.expected.c` 全量重生成；仓库方法论从 opt-in 改为默认严格（[requirements-pool.md:157-171](../planning/requirements-pool.md)）。 | 大；需用户单独签字。 | 不是「缺功能」，是策略变更；不应夹带进能力相。 |

### 2.3 工程质量与工具链

| 序 | 候选 | 依据（可核查） | 范围与成本量级 | 风险 / 前置 |
| --- | --- | --- | --- | --- |
| C1 | CI 口径对齐：TSan job + ASAN 栈悬垂选项 | `nightly.yml` 只有 sanitizers / fuzz 两个 job，`check-tsan.sh` 却写「nightly Linux job 会跑」（[requirements-pool.md:207-221](../planning/requirements-pool.md)）；ASAN 未开 `detect_stack_use_after_return`（`:223-237`）。 | 小（workflow + 选项），需先测噪声与耗时。 | 需负责人二选一：补 job 还是改口径。 |
| C2 | 红证缺口的前向门禁 | 45–52 的收口提交没有 T-7 红证父提交（§1.3）；现有门禁不检查提交形状。 | 小–中；新门禁必须带负例，按 g0–g9 风格加子命令。 | 不能追溯修复；只能约束后续相。 |
| C3 | 文档真相修复（本文件 §1.2 八条） | 同上。 | 文档改动，无实现风险。 | 与 `language-spec.md` 文档线有句子级冲突风险，需按句切片。 |
| C4 | 下游升级与兼容语料 | CT 已到 `0.52.0`，nexcore 基线仍是 `0.44.2`，rill / ct-http 探针基于 `0.44.1`（各自文档）。45–52 的修复尚未被下游消费。 | 中；需要把 ct-pkg 的 `fs/str/io/utf8` 等包纳入一次真实构建回归。 | 不是本仓库单方面能完成，需下游配合。 |
| C5 | 增量构建基准 + 1.0 稳定子集清单 | roadmap「未排期（治理项）」两条（[roadmap.md:96-99](../roadmap.md)）。 | 小–中；基准 + 文档。 | 属治理，不直接解除任何下游阻塞。 |

**排序结论（建议）：A1 > A2 > A3 > A4；B 类仅 B6 有独立价值；C 类中 C3 应先做，C1/C2 次之。**

---

## 3 下游实际卡点（只记录文档结论，未重跑）

| 下游 | 记录的卡点 | 现状判断 | 来源 |
| --- | --- | --- | --- |
| rill-dsl | `ct build` 四限制：DF-1 静默截断、DF-2 多行长宏、DF-3 前向 typedef、`impl` 尾分号；因此退回单文件 `ctc` | DF-1/2/3 未修；`impl` 尾分号是规范空白（优先级最低）。PH-46 已收口，RILL 当年「不用 `Map`」的绕法已过时 | `/Users/samxx/trae-ws/rill-dsl/docs/planning/rill-0.1.0-ct-defect-workarounds.md`；`ct-build-frontend-defects.md:15-21` |
| rill-dsl | PD-1 `$"..."`、PD-2 相邻拼接 | **不是 CT 缺陷**，已裁定修 RILL 实现 | `/Users/samxx/trae-ws/rill-dsl/docs/planning/rill-0.1.0-parser-defects.md` |
| ct-http | SH-71 单元边界、SH-72 返回装箱、SH-74 `&_self`、SH-75 局部悬垂 | SH-71 组合已可用；SH-72/74/75 已修（`v0.44.2` 前） | `issues/selfhost/sh7*.md` |
| ct-http | SH-73 方法结果作接收者；HTTP-3 Linux 半边未跑 | SH-73 仍是明示限制；HTTP-3 是环境缺口，不是语言缺陷 | `issues/selfhost/sh73-*.md`；`/Users/samxx/trae-ws/ct-http/issues/HTTP-3.md` |
| ct-json | 对象值按值进 `Map`、键保真、跨单元 Drop、`own` 接工厂 | 分别由 PH-46/47/48/49 收口；目标访问形态改为 JS 风格 | `ct-json-capability-blockers.md`；`/Users/samxx/trae-ws/ct-json/README.md` ADR-0007 |
| ct-fsguard | 原文写法 2 处硬阻塞（`pub trait ... for char *`、`#define` 常量） | 改后口径 **0 条 CT 硬阻塞**；改用 `pub enum` / `map trait` / 显式 Drop 即可 | `/Users/samxx/trae-ws/ct-fsguard/docs/requirements.md` |
| nexcore | 无语言阻塞记录；C ABI、`pub enum`、`nm` 白名单 | 基线 `v0.44.2`，落后 8 个次版本；ABI 前置声明类问题与本仓库 REQ-ABI-3/4 相关 | `/Users/samxx/trae-ws/nexcore/docs/README.md`；`docs/roadmap.md` P1 |
| ct-sse / ct-llm-sse / ct-token / ct-process | 目录内只有 requirements/spec，无 issues 目录 | **未见 CT 缺陷记录，也未验证**；本次不作为立项依据 | 各仓库目录 |

---

## 4 本相不做（范围与理由）

| 不做 | 理由 | 归属 |
| --- | --- | --- |
| GC、完整 borrow checker、CFG 数据流分析 | 无 CFG/IR 承载物；量级 5,000+ 行，超过任一已收口相 | [REQ-MEM-1](../planning/requirements-pool.md)（dormant） |
| 默认路径全量类型检查 | 策略变更 + 全部 golden 重生成，需单独签字 | REQ-TYPE-1 |
| 多级 `v["a"]["b"]` 的语言侧实现 | 已裁定由包层 `JsonRef` 承担 | [phase46-52-plan.md:136](../design/phase46-52-plan.md) |
| 用户类型指针接收者进入下标协议 | `p[k]` 保持 C 指针算术 | PH-52 §7 |
| `[]` 之外的运算符重载 | 与 Z1/Z3 及既有设计边界冲突 | [custom-index-protocol.md](custom-index-protocol.md) §1.3 |
| `.h.ct` 的 `defer` / `errdefer` 放宽 | 除非 Q1 选 D；否则会让接口单元语义扩成新相 | §2.2 B2 |
| 下游包的 API 重写（ct-http / ct-json 等） | 不属于本仓库；语言侧只提供能力与诊断 | 各下游仓库 |
| 事后补造 45–52 的红证 | 既有纪律：不得补造；只能补回归夹具与加前向门禁 | [plan §13.1](../design/phase46-52-plan.md) |
| 改冻结层 `selfhost/l0`、`l1`、`l2` | 仅限 bug 修复；本相无此需求 | handoff §4 |
| 动 `.ai-engineering` | 不在本仓库职责内 | 用户指令 |

---

## 5 需要负责人拍板的选择题

> **2026-11-15 已裁定：Q1 = B1（`?.` 可选链）；Q2 = 原占位转为施工卡，不再另占相号。**
> 下表保留当时的选项与成本，供追溯；不再代表待决状态。

### Q1 PH-53 的主题选哪一项？

| 选项 | 内容 | 影响 | 成本量级 |
| --- | --- | --- | --- |
| **A（建议）** | 前端静默缺陷 DF-1/DF-2/DF-3 | 消除唯一「静默错产物」；RILL 可回到多单元；所有长 `#include` / 长宏包受益 | 约 200–400 行 ±40%，含 DF-1 存储改造与 DF-2 |
| B | REQ-JSACCESS-1 | ct-json 的目标访问形态前进一步；`v[0]` 从静默空变为硬错 | 250–470 行量级（未估） |
| C | B-2 / SH-73 一行链 | ct-http 的「一行链」成立；但会改既有生成物与 golden | 100–300 行 + 大面积产物对比 |
| D | `.h.ct` 的 `defer` / `errdefer` | 包作者减少重复释放代码；语义新规则 | 未估，偏高 |
| E | 工程治理相（C1 + C2 + C3 + 下游语料） | 不新增语言能力；修复文档真相、CI 口径与红证门禁 | 小–中，但单项多、需拆片 |

> 不建议把 A 与 B/C 塞进同一相：三者都动 `Expr` / `Lexer` / 生成物，口径与验收面不同。

### Q2 `?.` 的相号怎么处置？

| 选项 | 做法 | 影响 |
| --- | --- | --- |
| **A（建议）** | 收回 PH-53 相号；把 `?.` 记录转成需求池条目（不占相号），等重新设计通过再排期 | 与「不立项不占相号」一致；roadmap 需改一行；不影响 `phase53-optional-chain-draft.md` 的结论 |
| B | 保留占位，把实施相排成 PH-54 | 相号继续被未立项内容占用；后续每次讨论都要解释 |
| C | 与 REQ-JSACCESS-1 合并为「可选访问」大相 | 范围显著扩大，且 `?.` 现形态已驳回，短期不可实施 |

### Q3 45–52 的红证缺口怎么处理？

| 选项 | 做法 | 影响 |
| --- | --- | --- |
| **A（建议）** | 只登记、不补造；新增前向门禁，要求后续相先红后绿 | 历史相不可复验，但不再扩大债务；门禁需带负例 |
| B | 补回归夹具（不写成红证），把已修行为钉住 | 增加覆盖，不改变历史判定 |
| C | 重开 45–52 补红证 | 成本最高，且等于改写已发布历史；不建议 |

### Q4 版本与收口节奏？

| 选项 | 做法 | 影响 |
| --- | --- | --- |
| **A（建议）** | 一相一版：PH-53 收口 bump `v0.53.0`（五处 `CTC_VERSION` + README + golden） | 与 V-7 及 46–52 的节奏一致 |
| B | 若 Q1 选 E（工程治理），仍 bump `v0.53.0` | 保持「每相一版」；代价是版本号承载治理改动 |
| C | 多相合并一次 bump | 有 27–30 先例，但会让「哪一相改了什么」难以追溯 |

### Q5 是否把下游兼容语料纳入 PH-53？

| 选项 | 做法 | 影响 |
| --- | --- | --- |
| **A（若 Q1=A，建议）** | 在 PH-53 内加一组 ct-pkg 包的真实 `ct build` 回归（至少 `fs`/`str`/`io`/`utf8`） | 能证明 DF-1/2 修复对真实包有效；成本中 |
| B | 只发升级说明，下游自行升级 | 成本小；但 45–52 的修复仍无人消费验证 |
| C | 另开升级验证相 | 相号成本；与 Q1 的取舍重复 |

---

## 6 下一步（不含实现细节）

1. 先拍 Q2：把 `?.` 从相号里移出或明确保留；否则 PH-53 的主题没有干净的落点。
2. 再拍 Q1：只选一项作为施工主题；其余进需求池或后续相。
3. 拍 Q3–Q5 后，再由本仓库按 AGENTS 的「先出卡再开工」补 `docs/design/phase53-draft.md`
   （退出判据、任务清单、`version-minor`、红证要求），本文件只作讨论材料，不转成卡。
4. §1.2 的文档真相修复建议单独成一组文档提交（不占相号），避免与新相的实现混在一起。

---

## 7 证据索引

| 主题 | 位置 |
| --- | --- |
| 50–52 已收口、53 施工卡 | [roadmap.md](../roadmap.md) 的 Phase 52 / 53 行 |
| 50–52 旧口径（已修正） | [roadmap.md](../roadmap.md) 的 Phase 45–52 段 |
| 索引页旧口径（已修正） | [docs/README.md](../README.md) 的 Phase 50–53 行 |
| 计划表历史口径 | [phase46-52-plan.md](../design/phase46-52-plan.md) 顶部说明 |
| 施工手册历史顺序 | [phase46-52-handoff.md](../design/phase46-52-handoff.md) 顶部说明 |
| DF-1/2/3 修复单 | [ct-build-frontend-defects.md](ct-build-frontend-defects.md) |
| DF-1 代码锚点 | `selfhost/ct-ast/frontend/lex/Lexer.h.ct:18`、`:90-99`、`:108-110` |
| 能力缺口总表（部分过期） | [language-capability-gaps.md:1530-1557](language-capability-gaps.md) |
| 规范旧陈述 | [language-spec.md:673-677](../language-spec.md) |
| `?.` 记录 | [phase53-optional-chain-draft.md](phase53-optional-chain-draft.md) |
| PH-52 的 `v[0]` 已知洞 | [phase52.md:58-61](../design/phase52.md) |
| REQ-JSACCESS-1 | [requirements-pool.md:66-98](../planning/requirements-pool.md) |
| ABI 三条 | [requirements-pool.md:118-155](../planning/requirements-pool.md) |
| 红证与流程缺口 | [phase46-52-plan.md:425-436](../design/phase46-52-plan.md) |

---

## 8 决策落定与候选处置（2026-11-15）

**Q1 已裁定**：PH-53 施工主题 = B1 `?.` 可选链，卡面 [design/phase53.md](../design/phase53.md)，
版本 `v0.53.0`。**Q2 已裁定**：原 `?.` 记录转为施工卡，相号不再闲置，记录保留为设计依据。
**Q4** 由卡面固定为 `v0.53.0`；**Q3** 按「历史不补造红证、本卡 S1 先红」执行；
**Q5** 下游兼容语料不纳入本卡，留治理项。

| 候选 | 处置 | 落点 |
| --- | --- | --- |
| B1 `?.` 可选链 | **本相施工** | [phase53.md](../design/phase53.md) |
| A1 DF-1/DF-2/DF-3 | 留需求池 / 下一相候选；**不占 PH-53** | [ct-build-frontend-defects.md](ct-build-frontend-defects.md) |
| A2 REQ-JSACCESS-1 | 留需求池，不占相号；`v[0]` 仍不主张 | [requirements-pool.md:66-98](../planning/requirements-pool.md) |
| A3 B-2 / SH-73 | 独立缺陷，留后续相候选 | `issues/selfhost/sh73-*.md` |
| A4 ABI 加固 | 留需求池；防御性，不阻塞 | [requirements-pool.md:118-155](../planning/requirements-pool.md) |
| B2 `.h.ct` 的 `defer` / `errdefer` | 留需求池 / 后续相 | 本文件 §2.2 |
| B3 A-3、B4 G-1、B5 诊断、B6 REQ-MEM-2、B7 REQ-TYPE-1 | 留需求池 / 后续相 | [requirements-pool.md](../planning/requirements-pool.md) |
| C1 CI 口径、C2 红证门禁、C4 下游语料、C5 基准与稳定子集 | 留治理项，不占相号 | 本文件 §2.3 |
| C3 文档真相 | 本轮已修正 roadmap / docs/README 的 50–52 排期矛盾，并在 plan / handoff 顶部加 PH-53 说明；能力缺口总表与 `language-spec.md:673` 仍留后续文档治理 | [roadmap.md](../roadmap.md)、[docs/README.md](../README.md) |

**不预排 PH-54**；下一相由负责人另行立项。
