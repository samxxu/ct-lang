# battle/phase80-gate-1 反对席（counter）

- 争点：PH-80/81/82 的施工入口是否被「P-7.4 / P-7.5 全量未补」硬阻断。
- 本席主张：**B** — PH-80/81/82 在各自入口证据补齐前不得落实现代码；卡头「施工闸门」是硬门，
  不得由执行侧改写读法，只能由 EDITOR 在 decision 中修订。
- 基线：HEAD `6665f01a`（v0.79.2）；卡状态「实施中（准备；施工入口未过）」。
- 边界：只写本文件；不改卡、不改源码、不改 roadmap。证据按 §7.7 E1–E5；反证清单见 §0。

## 0 反证清单（B 的失效条件）

| ID | 失效条件 | 可核验方式 | 若成立 |
| --- | --- | --- | --- |
| F-1 | 裁判认定卡内 §1.1 stage 表（S5a 入口 = P-7.3 + PH-79）优先于卡头「前置」、§1.2 标题「施工前补齐」、plan 表 PH-80 行、提案 A.7 与 P-7.3 证据的「施工前」表述 | 对卡头、§1.2、plan、提案、p73 证据做条款位阶比较 | B 在 PH-80 上不成立；B 承认这是最薄的一环（E2 不利项 2） |
| F-2 | 存在已入库、有 `signer` + `date` 的 decision（或 D-011 追加裁定），把 P-7.4 拆成「S5a 前必须闭合」与「PH-81 后回填」，并明确允许 S5a 落实现代码 | `grep -rn "P-7.4" docs/decisions/` 非空，且文本含上述拆分与放行 | B 改判为「按该 decision 执行」；截至 HEAD 无此记录（E1-7） |
| F-3 | 裁判认为 P-7.4 只能由 S5a 产品实现产出，隔离副本原型不算证据 | 对 A.7「原型门槛」与 p73 §2 的复现方法做解释 | B 的「原型可先行」不成立；B 的替代回应见 §3/E5 |
| F-4 | `git apply --check` 在 `6665f01a` 上对 P-7.3 patch 退出 0 | 命令 `git apply --check ...` | B 的「P-7.3 入口证据已僵化」从属论点失败；主论点不受影响（E1-6 当前 exit=1） |
| F-5 | PH-80 卡面 E80-1…E80-8 或既有门禁已能抓住参数/返回/字段的自动 retain、UTF-16 语义、跨仓迁移 | `grep -n "retain" docs/design/phase80.md` 非空，或指出具体 E80/G5 条目 | B 的 §2.2/§2.3/§2.4 弱化（当前 0 命中，E1-5） |
| F-6 | 在 S5a 形状的分支上做回滚演练，`git revert` 后 PH-79 行为与旧 `Str` 消费者均不受影响 | 演练提交 + 原始输出 | B 的 §2.5 弱化（当前卡面只有一句散文，无演练证据） |

## 1 硬门条款逐条（引原文）

### 1.1 三张卡的卡头与卡内

| # | 条款 | 原文要点 | 对 B 的作用 |
| --- | --- | --- | --- |
| G-1 | [phase80.md:5](../../docs/design/phase80.md#L5) | 「**施工闸门**：P-7.3 最小切片已过、**PH-79 已收口**；**P-7.4 全量未补**。」「未过前只做证据、设计与夹具，不落实现代码。」 | 「不落实现代码」就写在闸门句里，不是摘要 |
| G-2 | [phase80.md:7](../../docs/design/phase80.md#L7) | 「**前置**：P-7.3 最小垂直切片 + P-7.4 全量」 | 「前置」= 施工前置，不是收口前置 |
| G-3 | [phase80.md:56](../../docs/design/phase80.md#L56) | 「### 1.2 P-7.4 入口证据清单（施工前补齐）」 | 小节标题逐字写「施工前补齐」，与 G-2 同向 |
| G-4 | [phase80.md:58](../../docs/design/phase80.md#L58) | 「它替换了旧 `lib/std/Str.h.ct`，只作 S5a 参考，**不直接合并**」 | 卡自己否定了「把 P-7.3 原型直接当 S5a 开工底本」 |
| G-5 | [phase80.md:104](../../docs/design/phase80.md#L104) | 「外部迁移 dry-run 为 S5b blocking」 | 迁移证据是 S5b 的硬条件，但内建化决定发生在 S5a |
| G-6 | [phase80.md:107](../../docs/design/phase80.md#L107) | 「S5a 可回退到旧 `Str`；S5b 与外部迁移绑定，不能整体单回滚」 | 回滚承诺没有配套演练判据（§2.5） |
| G-7 | [phase81.md:5](../../docs/design/phase81.md#L5) | 「**施工闸门**：P-7.5 未做、PH-80 未收口；未过前只做证据、设计与夹具，不落实现代码。」 | PH-81 的 P-7.5 门是硬门 |
| G-8 | [phase81.md:6](../../docs/design/phase81.md#L6) | 「**前置**：P-7.5；PH-80 句柄协议收口。」 | P-7.5 是 PH-81 的前置，不是 PH-80 的 |
| G-9 | [phase82.md:5](../../docs/design/phase82.md#L5) | 「**施工闸门**：PH-81 `box<T>` 未收口；未过前只做配置/检测设计与夹具，不落实现代码。」 | PH-82 的硬门是 PH-81 收口 |
| G-10 | [phase82.md:6](../../docs/design/phase82.md#L6) | 「**前置**：PH-81 `box<T>` 收口；D-012 accepted；battle leak-guards-1 closed。」 | D-012/battle 已满足，剩余门是 PH-81（E1-10） |

三张卡的分工必须说清，否则会被误读成 B 要求 P-7.5 也挡 PH-80：

| 卡 | B 主张的阻断项 | 依据 |
| --- | --- | --- |
| PH-80 | P-7.4（七项） | G-1、G-2、G-3；plan:27；提案 A.7 |
| PH-81 | P-7.5（七项） | G-7、G-8；plan:28；提案 A.7 |
| PH-82 | PH-81 收口（传递） | G-9、G-10；D-012 已 accepted |

### 1.2 D-011 §3/§5

| # | 条款 | 原文要点 | 对 B 的作用 |
| --- | --- | --- | --- |
| G-11 | [docs/decisions/D-011.md:44](../../docs/decisions/D-011.md#L44) | 「**证据门槛仍是硬门**：J-6/J-7/J-8 未过前不开施工卡；P-1…P-7 见提案 v2 附录 A」 | 「硬门」是 decision 用词，不是卡作者措辞 |
| G-12 | [docs/decisions/D-011.md:61](../../docs/decisions/D-011.md#L61) | 「具体开卡仍待 J-6 证据通过」 | 开卡（更不用说施工）仍以证据为条件 |
| G-13 | [docs/decisions/D-011.md:63](../../docs/decisions/D-011.md#L63) | 「证据任务全部完成后，回到 EDITOR 复核 J-6/J-7/J-8，再决定是否开第一张施工卡」 | 顺序写明：证据全部完成 → EDITOR 复核 → 才决定施工 |
| G-14 | [docs/decisions/D-011.md:64](../../docs/decisions/D-011.md#L64) | 「若 J-4a/J-4b 的契约文本未落地，`Str`/切片的借用位置规则不得进入实现」 | 借用规则连「进入实现」都不允许，何况先落代码再补证 |
| G-15 | [docs/decisions/D-011.md:36](../../docs/decisions/D-011.md#L36) | 「J-6 证据 \| **B** \| 无原型、无逐类语料迁移数据、无 ABI 实测」 | J-6 至今未升 A（plan:54 仍写「未过」） |

### 1.3 计划 §1/§3

| # | 条款 | 原文要点 | 对 B 的作用 |
| --- | --- | --- | --- |
| G-16 | [docs/planning/pointer-free-phase-plan.md:8](../../docs/planning/pointer-free-phase-plan.md#L8) | 「各卡按自己的入口收窄/等待」 | 主张书引这一句；但 PH-80 的「自己的入口」就是下面 G-17 的全量，不是收窄后的 P-7.3 |
| G-17 | [docs/planning/pointer-free-phase-plan.md:27](../../docs/planning/pointer-free-phase-plan.md#L27) | PH-80 入口：「P-7.3 最小垂直切片 + **P-7.4 全量**；S3 收口」 | 计划表逐字要求 P-7.4 全量，与卡头一致 |
| G-18 | [docs/planning/pointer-free-phase-plan.md:28](../../docs/planning/pointer-free-phase-plan.md#L28) | PH-81 入口：「**P-7.5**；S5 句柄协议收口」 | P-7.5 是 PH-81 的入口 |
| G-19 | [docs/planning/pointer-free-phase-plan.md:32](../../docs/planning/pointer-free-phase-plan.md#L32) | 「施工按入口串行：**P-7.4 → PH-80**、P-7.5 + PH-80 → PH-81、PH-81 → PH-82」 | 箭头方向即顺序：证据在前，施工在后 |
| G-20 | [docs/planning/pointer-free-phase-plan.md:33](../../docs/planning/pointer-free-phase-plan.md#L33) | 「J-6 全量仍未过；**准备态不得落实现代码**。」 | 计划自己也把「准备态」与「落实现代码」分开 |
| G-21 | [docs/planning/pointer-free-phase-plan.md:54](../../docs/planning/pointer-free-phase-plan.md#L54) | J-6 状态：「未过：……全量仍缺 P-1…P-6 正式证据包」 | 全量未过是计划承认的事实 |

### 1.4 提案 A.7 与 P-7.3 证据

| # | 条款 | 原文要点 | 对 B 的作用 |
| --- | --- | --- | --- |
| G-22 | [docs/proposals/pointer-free-v2.md:187](../../docs/proposals/pointer-free-v2.md#L187) | 「S5 全量原型在 **S5 施工卡开工前**补齐」 | 「施工卡开工前」= 实现之前 |
| G-23 | [docs/proposals/pointer-free-v2.md:272](../../docs/proposals/pointer-free-v2.md#L272) | 「P-7.4 \| S5 全量（**施工前**）\| A.3 全绿；跨仓 dry-run」 | P-7.4 的定义自带「施工前」 |
| G-24 | [docs/proposals/pointer-free-v2.md:273](../../docs/proposals/pointer-free-v2.md#L273) | 「P-7.5 \| S1 `box/new`（最后）\| 句柄协议复用；`new` 仅具名 struct」 | P-7.5 是 PH-81 的原型门槛 |
| G-25 | [docs/planning/j6-evidence/p73/evidence.md:281](../../docs/planning/j6-evidence/p73/evidence.md#L281) | 「P-7.4 在 S5 施工卡前补齐」 | 证据报告的执行者也这样收口 |

### 1.5 硬门的读法

G-1 到 G-25 来自六份独立文件（phase80/81 两张卡、D-011、plan、提案、p73 证据），全部把 P-7.4/P-7.5 放在
「施工前」。**唯一相反的文字是卡内 §1.1 的 stage 表**（[phase80.md:53](../../docs/design/phase80.md#L53)
把 S5a 入口写成「P-7.3；PH-79 收口」）。主张书据此主张「具体条款优于摘要」，但 §1.2 的小节标题
（G-3）与 plan 表行（G-17）同样是具体条款，且与卡头同向；§1.1 只是其中一处。因此正确的结论不是
「只有一个读法」，而是**卡面自相矛盾**。

卡面矛盾时，处置权在 EDITOR，不在执行侧：

- [AGENTS.md:468](AGENTS.md#L468)：「"放宽一下" / "跳过门禁" → 拒绝；走 `deviation:` 或改主规范（S7）」；
- [AGENTS.md:590](AGENTS.md#L590)：「PH-80–82 已开卡准备（施工入口未过，**不落实现代码**）」；
- [docs/decisions/D-011.md:63](../../docs/decisions/D-011.md#L63)：证据完成后由 EDITOR 复核再决定施工。

主张书的 A′（§1.1 + K-1…K-7）实质是一份**新闸门**：它把 P-7.4 的六项移到 S5a 阶段出口，
把 P-7.5 移到 PH-81 S1a，并允许 S5a 先落实现代码。改写闸门需要 `signer` + `date` 的 decision
（F-2）；截至 HEAD 没有任何 decision 记录 P-7.4（E1-7）。**没有签字的「读法」不是闸门修订。**

需要区分两件事：plan 允许「开卡做证据/设计/夹具」（
[docs/planning/pointer-free-phase-plan.md:18](../../docs/planning/pointer-free-phase-plan.md#L18)），
B 不主张把准备卡收回；B 主张的是卡一旦进入「落实现代码」，就必须先过闸门。A 的 K-1/K-4 把
P-7.4 留在 S5b/收口门，这是对**收口门**的尊重；但卡头写的是**入口门**，二者不能互相替代：
收口门管「能不能 bump v0.80.0」，入口门管「代码能不能先落地」。

## 2 跳过 P-7.4 / P-7.5 的具体风险

### 2.1 ABI：先落布局，再补裁定

- 旧 `Str` 的公开 ABI 是 `{ char *data; int len; }` + `impl Drop` 释放 buffer + `release()` 置
  `data=0,len=-1`（[language-spec.md:2594](../../docs/language-spec.md#L2594)、
  [lib/std/Str.h.ct:18](../../lib/std/Str.h.ct#L18)）；新 `String` 是 16 字节句柄 + 隐藏 8 字节
  `{refs,aux}` 头（[docs/planning/j6-evidence/p73/evidence.md:222](../../docs/planning/j6-evidence/p73/evidence.md#L222)、提案 Q4），
  `ptr` 指向头之后。**同样是 16 字节，指针语义与释放契约不同**：旧代码若直接读写 `s.data`、
  手工拼 `Str`，或依赖 `str_c_str`/`str_slice` 的调用点，都不是「换一个类型名」能覆盖的。
- P-7.4-1 的 `.data` 类型尚未裁定。p73 的原型把它做成只读 `Str` 视图，并明说这是相对提案拼写的
  偏离：「P-7.4 需要决定最终是 `const char *` + lint，还是保留视图类型」
  （[docs/planning/j6-evidence/p73/evidence.md:247](../../docs/planning/j6-evidence/p73/evidence.md#L247)）。若 S5a 先落 `p80_cstr`，
  这个未裁定的类型就会在 Emitter/TypeCheck 里定形；以后改裁定 = 重发所有字面量静态块
  （p73 实测每块 `8 + sizeof(literal)` 字节）+ C 边界 + golden 全量回流。v0.x 内的 ABI 决定是
  单向门，先落代码等于把单向门提前关上。
- 编译器已经有一个把字面拼写 `String` 判为 owning 的谓词
  （[selfhost/ct-ast/frontend/parse/Expr.h.ct:1324](../../selfhost/ct-ast/frontend/parse/Expr.h.ct#L1324)，PH-78 S2a 引入），
  而当前语言里并没有 `String` 值类型。内建化会改变这个既有判定的含义，并与
  `std::str::String`（外部 `std` 包的 `char *` 方法层 trait，
  [language-spec.md:2596](../../docs/language-spec.md#L2596)）同名不同物。P-7.4-2 只写了
  「旧 owning `Str` 仅 `std::str::Str` 限定名」，**没有写 `std::str::String` trait 怎么办**；
  先落代码会把一个未列出的命名冲突变成产品事实。

### 2.2 自动 retain：没有判据，复制语义悬空

- p73 的 A.3.2 只到显式协议：「按值传参/返回/字段赋值是普通 struct 拷贝，**不会自动 retain**；
  调用方要用 `copy()`/`retain()`」（[docs/planning/j6-evidence/p73/evidence.md:243](../../docs/planning/j6-evidence/p73/evidence.md#L243)）。
  A.3.2 的判据却要求「参数/返回/字段/`Vec<String>`/`box<String>` refcount 轨迹」
  （[docs/proposals/pointer-free-v2.md:228](../../docs/proposals/pointer-free-v2.md#L228)）。
- PH-80 卡的退出判据 **E80-1…E80-8 没有任何一条提到 retain/复制协议**（E1-5：`retain` 在卡面
  0 命中），E80-8 只要求文档三处同步与 `check-all`/ASan 通过。也就是说：若 S5a 带着 p73 的
  「普通拷贝」语义落地，**没有门禁会红**。失败形态取决于一个尚未做的选择：
  - 选「拷贝硬错」（与内置容器一致：[lib/std/README.md:49](../../lib/std/README.md#L49)
    「变量间直接拷贝是硬错」）→ 现有 `Str` 的「按值传递浅拷贝指针」
    （[language-spec.md:2595](../../docs/language-spec.md#L2595)）用法全部要迁移；
  - 选「浅拷贝 + 显式 retain」（旧 `Str` 口径）→ 新 `String` 带 `Drop`，按值复制后两个句柄各自
    drop 会二次释放，除非 release 另有守卫；
  - 选「自动 retain」→ 需要参数/返回/字段的 move/copy glue，正是 p73 §8 说「会引入 move/copy
    语义，不能在当前最小切片里诚实声称」的那部分
    （[docs/planning/j6-evidence/p73/evidence.md:263](../../docs/planning/j6-evidence/p73/evidence.md#L263)）。
- 这不是风格问题：这三种选择都是用户可见的所有权契约。P-7.4-7 就是为它设的证据门；跳过它，
  S5a 交付的是一个「有 `Drop`、但复制协议未定义」的公开类型。

### 2.3 UTF-16：占位类型变成产品类型

- p73 的 `U16String` 是**占位**：「没有 UTF-16 值、工厂或方法；只保留『隐式字面量转换 = 硬错』
  的负例」（[docs/planning/j6-evidence/p73/evidence.md:251](../../docs/planning/j6-evidence/p73/evidence.md#L251)）；patch 里就是一个
  `{ char *ptr; int len; }` 的 nominal struct（E1-9），`from_utf8` 只出现在错误消息里。
- PH-80 的退出判据要求 `U16String` **仅工厂**、`U16String[i]` 只读单 code unit、U16 核心 JS 方法
  snake_case（[phase80.md:88-92](../../docs/design/phase80.md#L88-L92)），P-7.4-5 要求「UTF-8
  码点/`byte_*` API 与 U16 核心 JS 方法**全量清单**，方法逐个正例/负例」
  （[phase80.md:66](../../docs/design/phase80.md#L66)）。若 S5a 先落 S5a-3，方法名、code unit
  语义、代理对处理、跨编码工厂边界都只能按实现时的猜测定形；PH-81 的 `box<T>` 又要复用同一
  refs 头（[phase81.md:76](../../docs/design/phase81.md#L76)），错误会沿 S5 → S1 传导。

### 2.4 跨仓迁移：替换式原型不是增量

- p73 是**替换** `lib/std/Str.h.ct`，不是并存：「旧 owning `Str`、`str_from`/`str_slice` 等函数、
  `Map<Str,V>` 的 key 块都不再存在……既有测试套件没有全绿」
  （[docs/planning/j6-evidence/p73/evidence.md:242](../../docs/planning/j6-evidence/p73/evidence.md#L242)）；报告自己写「只作 PH-80 参考，
  不直接当 S5a 合并」（[docs/planning/j6-evidence/p73/evidence.md:289](../../docs/planning/j6-evidence/p73/evidence.md#L289)）。
  本仓 tracked `.ct` 里 21 个文件提到 `Str`、12 个调用 `str_slice`/`str_from`/`str_concat`、
  7 个使用 `Map<Str, …>`（E1-8）。这些就是 P-7.4-2/3/4 要逐项记录的对象。
- P-3.6 跨仓 dry-run 完全未做（[docs/planning/j6-evidence/p73/evidence.md:227](../../docs/planning/j6-evidence/p73/evidence.md#L227)），
  而 P-7.4-6 要的正是外部消费者 dry-run；`std::str::String` 又是
  外部 `std` 包提供的 trait（[lib/std/README.md:10](../../lib/std/README.md#L10)），仓内已有消费者
  `import std::str::String`（[examples/wave1-demo/src/main.ct:7](../../examples/wave1-demo/src/main.ct#L7)）。
  内建 `String` 与这个 trait 同名：这是跨仓命名/迁移问题，不是 PH-80 单仓问题。
- 卡 R80-5 把外部 dry-run 定为 S5b blocking（G-5），但「把 `String` 内建化」这个决定发生在 S5a；
  先落 S5a 再补 dry-run，等于先改公共名字再问消费者能不能接受。

### 2.5 回滚：S5a 的「可回退」没有被演练

- 卡面只写了一句「S5a 可回退到旧 `Str`」（G-6），没有回滚判据、没有演练命令、没有 baseline。
  p73 的参考改动是 8 文件 +560/−111 的**替换式** patch，`git apply --check` 在当前 HEAD 已经
  3 个文件冲突（E1-6）；同一批 parse/emit 目录在 `5736f0d5..HEAD` 已漂移 +1028/−16。
  回退要同时处理 PH-79 的改动，不是卡面一句「反做 patch」。
- S5a-1…S5a-4 都落在同一批 Emitter/TypeCheck/Stmt/Parser 行上；6.6 T-4 要求「每项任务能单独
  `git revert`」，但卡上没有逐任务的回滚路径，也没有演练。S5a/S5b 共用一个 MINOR、不能单独 bump
  （plan:106）；半落地的 S5a 既不能发版，也不能靠回滚干净退出——这正是 G-2 要求「全量前置」的
  现实理由。

### 2.6 P-7.5 对 PH-81/82 的传导

- P-7.5 的七项（[phase81.md:52-60](../../docs/design/phase81.md#L52-L60)）包含 `box<T>` 布局与
  `{refs,aux}` 头对齐、release 按静态类型、`new` 仅具名 struct、借用视图/失效检测与 Vec 同构、
  旧 golden 不变 + ASan。跳过它直接落 S1a/S1b，会先把 box 布局与 `new` 关键字写进
  parser/emitter；PH-82 的直接环检测又只展开 `box<X>` 字段（
  [phase82.md:87](../../docs/design/phase82.md#L87)），错误会继续传到 E82-3/E82-4。
- 本席不主张「`new` 关键字会大量破坏既有代码」：tracked `.ct` 中命中单词 `new` 的 16 个文件里，
  本席抽查到的非注释样本是英文注释（示例 [lib/std/Str.h.ct:68](../../lib/std/Str.h.ct#L68)）；
  本席**没有**做 P-1.2 要求的标识符级分类，不能断言命中为零。因此 PH-81 的阻断理由不是关键字
  兼容性，而是 **box 布局/协议与借用视图失效检测没有 P-7.5 证据**。

## 3 为什么 B 不是死锁（对主张书 J-3/J-7 的核心反驳）

主张书的死锁论证是：`S5b ← P-7.4-7 ← A.3.2 的 box<String> ← PH-81 ← PH-80 收口 ← S5b`，
所以 B 只能阶段化，阶段化后即 A。**前提错了：P-7.4 是「原型门槛」，不是「S5a 产品实现门槛」。**

- p73 自己就是原型方法的样板：`git archive` 到 `/tmp/p73`、在那里打 patch、跑
  `test/p73/run.sh`，主仓只落报告与 patch、不改源码
  （[docs/planning/j6-evidence/p73/evidence.md:47-52](../../docs/planning/j6-evidence/p73/evidence.md#L47-L52)）。P-7.4 的
  参数/返回/字段自动 retain、`Map<...,String>`、旧 `Str` 并存、跨仓 dry-run，都能用同一方法在
  隔离副本里产出原始输出；**6/7 项不依赖 PH-81**。
- 唯一在定义上依赖 PH-81 的，是 A.3.2 里的 `box<String>` 子项
  （[docs/proposals/pointer-free-v2.md:228](../../docs/proposals/pointer-free-v2.md#L228)）。正确处置是 EDITOR 签一条
  gate 修订：把该子项移出 S5a 入口、回填条件 = PH-81 收口，其余六项仍在 S5a 前闭合。
  **这是「阶段化一个 gate 子项」，不是「阶段化证据与代码的顺序」**——前者仍是 B，后者才是 A。
- 主张书说「一旦阶段化，S5a 的入口就回到 P-7.3，即 A」。这一步是偷换：阶段化的对象不同。
  B 的阶段化只把 `box<String>` 一项移出入口；主张书的阶段化把 P-7.4-2/3/5/7 全部变成 S5a 的
  **产物**（K-4），即代码先于证据。两者不是同一件事。

## E1 — 证据（命令与原始输出）

### E1-1 三张卡的卡头闸门

```console
$ awk 'NR==5||NR==7||NR==54||NR==56{printf "%d:%s\n", NR, $0}' docs/design/phase80.md
5:> **施工闸门**：P-7.3 最小切片已过、**PH-79 已收口（v0.79.0）**；**P-7.4 全量未补**。
7:> **前置**：P-7.3 最小垂直切片 + P-7.4 全量；PH-79 切片表示收口 ✅。
54:| S5b 删旧/迁移 | 删旧 `Str`、std 消费者迁移、索引/包版本、README/spec/roadmap 三处同步 | P-7.4；S5a 收口 |
56:### 1.2 P-7.4 入口证据清单（施工前补齐）
# 退出码 0

$ awk 'NR==5||NR==6||NR==46{printf "%d:%s\n", NR, $0}' docs/design/phase81.md
5:> **施工闸门**：P-7.5 未做、PH-80 未收口；未过前只做证据、设计与夹具，不落实现代码。
6:> **前置**：P-7.5；PH-80 句柄协议收口。
46:| S1a 类型/协议 | `box<T>`、refs 头、Drop、借用视图/失效检测 | P-7.5；PH-80 |
# 退出码 0

$ awk 'NR==5||NR==6{printf "%d:%s\n", NR, $0}' docs/design/phase82.md
5:> **施工闸门**：PH-81 `box<T>` 未收口；未过前只做配置/检测设计与夹具，不落实现代码。
6:> **前置**：PH-81 `box<T>` 收口；[D-012](../decisions/D-012.md) accepted；battle leak-guards-1 closed。
# 退出码 0
```

### E1-2 D-011 与计划

```console
$ awk 'NR==44||NR==61||NR==63||NR==64{printf "%d:%s\n", NR, $0}' docs/decisions/D-011.md
44:3. **证据门槛仍是硬门**：J-6/J-7/J-8 未过前不开施工卡；P-1…P-7 见
61:  [pointer-free-phase-plan](../planning/pointer-free-phase-plan.md)；具体开卡仍待 J-6 证据通过；
63:- 证据任务全部完成后，回到 EDITOR 复核 J-6/J-7/J-8，再决定是否开第一张施工卡；
64:- 若 J-4a/J-4b 的契约文本未落地，`Str`/切片的借用位置规则不得进入实现。
# 退出码 0

$ grep -n "施工按入口串行" docs/planning/pointer-free-phase-plan.md
32:> PH-80–82 已开卡（准备），施工按入口串行：P-7.4 → PH-80、P-7.5 + PH-80 → PH-81、PH-81 → PH-82。

$ grep -n "准备态不得落实现代码" docs/planning/pointer-free-phase-plan.md
33:> J-6 全量仍未过；准备态不得落实现代码。

$ grep -n "P-7.4 全量" docs/planning/pointer-free-phase-plan.md
27:| **PH-80** | S5 `String` / `Str`（[卡](../design/phase80.md)） | v0.80.0 | P-7.3 最小垂直切片 + P-7.4 全量；S3 收口 | 附录 A.3/A.6 全绿；UTF-8/UTF-16 双类型；L1 字面量；`.data`/`cstr`；U16 核心方法；std 消费者迁移 dry-run | S5a 内建层 + 旧 `Str` 并存；S5b 删旧 + 外部迁移；S5b 前不可整体回滚 |
```

### E1-3 提案 A.7（P-7.4/P-7.5 的定义）

```console
$ awk 'NR==187||NR==272||NR==273{printf "%d:%s\n", NR, $0}' docs/proposals/pointer-free-v2.md
187:`cstr`/迁移/旧 `Str`）。通过后开第一张正式卡（S2）；S5 全量原型在 S5 施工卡开工前补齐。
272:| P-7.4 | S5 全量（施工前） | A.3 全绿；跨仓 dry-run |
273:| P-7.5 | S1 `box/new`（最后） | 句柄协议复用；`new` 仅具名 struct |
# 退出码 0
```

### E1-4 P-7.3 证据自述的缺口

```console
$ awk 'NR==15||NR==17||NR==18||NR==243||NR==281{printf "%d:%s\n", NR, $0}' docs/planning/j6-evidence/p73/evidence.md
15:| A.3.2（复制/Drop 协议） | **部分通过**：显式 `copy()`/`retain()`/`release()`、`Vec<String>` 元素 glue、`own`/`delete` 实测；**未覆盖**参数/返回/字段的自动 retain、`box<String>`、`Map<...,String>` |
17:| 旧 `std::str::Str` | **未覆盖**：原型用新 `String`/`Str` 替换了 `lib/std/Str.h.ct`，旧 owning `Str` 及其消费者不在本轮 |
18:| J-6 能否据此过 P-7.3 | **可以记 P-7.3 通过（最小切片）**；不能据此把 A.3 全量或 P-7.4 记为通过 |
243:2. **A.3.2 只到显式协议**：按值传参/返回/字段赋值是普通 struct 拷贝，**不会自动 retain**；调用方要用 `copy()`/`retain()`。`String` 的 `use Drop` 只覆盖 `own`/`delete` 和宿主字段 glue，不改变普通局部变量的复制语义。
281:- J-6 整体仍需 P-7.1a/P-7.1b、P-7.2、P-7.3 全绿，且 P-7.4 在 S5 施工卡前补齐。
# 退出码 0
```

### E1-5 PH-80 卡面没有 retain/复制协议判据

```console
$ grep -n "retain" docs/design/phase80.md; echo exit=$?
exit=1

$ grep -c "^| E80-" docs/design/phase80.md
8

$ awk 'NR>=87&&NR<=94{printf "%d:%s\n", NR, $0}' docs/design/phase80.md
87:| E80-1 | `String`/`Str` 16 字节句柄；refcount 头对齐；`_Static_assert` 进 golden |
88:| E80-2 | `String s = "x"` L1 immortal；`Str v = "x"` 借用；`U16String` 仅工厂 |
89:| E80-3 | `String` 不可变；`s[i]` 只读单码点；`U16String[i]` 只读单 code unit；写操作硬错 |
90:| E80-4 | UTF-8 码点下标 + `byte_*`；`String.slice` 新 `String`，`Str.slice` 视图 |
91:| E80-5 | `.data` 只读不保证 NUL；`cstr()` 补 NUL；printf 子视图负例 |
92:| E80-6 | U16 核心 JS 方法 snake_case；`match/locale/normalize` 不在内建 |
93:| E80-7 | S5a 旧 `Str` 限定名并存；S5b 删旧 + std 消费者迁移 dry-run |
94:| E80-8 | README/spec/roadmap 三处同步；`check-all`/ASan 通过 |
```

E80-1…8 没有一条覆盖「参数/返回/字段自动 retain」。p73 §7.2 已明说该语义不自动发生。

### E1-6 P-7.3 参考 patch 在当前 HEAD 不能重放

```console
$ git rev-parse --short HEAD
6665f01a

$ git apply --check docs/planning/j6-evidence/p73/p73-rebased-5736f0d5.patch; echo exit=$?
error: patch failed: selfhost/ct-ast/backend/emit/Emitter.h.ct:1398
error: selfhost/ct-ast/backend/emit/Emitter.h.ct: patch does not apply
error: patch failed: selfhost/ct-ast/frontend/parse/Expr.h.ct:306
error: selfhost/ct-ast/frontend/parse/Expr.h.ct: patch does not apply
error: patch failed: selfhost/ct-ast/frontend/parse/Stmt.h.ct:2288
error: selfhost/ct-ast/frontend/parse/Stmt.h.ct: patch does not apply
exit=1

$ git apply --stat docs/planning/j6-evidence/p73/p73-rebased-5736f0d5.patch | tail -1
 8 files changed, 560 insertions(+), 111 deletions(-)

$ git diff --stat 5736f0d5..HEAD -- selfhost/ct-ast/frontend/parse selfhost/ct-ast/backend/emit | tail -1
 5 files changed, 1028 insertions(+), 16 deletions(-)
```

「P-7.3 已过」只在 `5736f0d5` 上成立；在 HEAD 要重放必须先人工解 3 处冲突。开工前连入口证据
本身都要先复现，这与「现在开工」不相容。

### E1-7 没有 P-7.4 的裁定；`std::str::String` 消费者仍在

```console
$ grep -rn "P-7.4" docs/decisions/; echo exit=$?
exit=1

$ grep -n "std::str::String" lib/std/README.md examples/wave1-demo/src/main.ct
lib/std/README.md:10:`char *` 映射层 `std::str::String` 仍在 ct-pkg `std`（Phase 36 的 S0 实测该包没有
lib/std/README.md:43:`Vec.len` / `has` / `at`、`Map.len` / `has` 以及 `std::str::String.len` 是既有保留名，
examples/wave1-demo/src/main.ct:7:import std::str::String;
```

### E1-8 旧 `Str` 的 ABI/API 与迁移语料面

```console
$ sed -n '18,24p' lib/std/Str.h.ct
pub struct Str {
    char *data;
    int len;
} use Drop;

impl Drop for Str {
    void drop() {

$ git ls-files '*.ct' | xargs grep -ln "\bStr\b" | wc -l
21
$ git ls-files '*.ct' | xargs grep -ln "str_slice\|str_from\|str_concat" | wc -l
12
$ git ls-files '*.ct' | xargs grep -ln "Map<Str" | wc -l
7
$ git ls-files '*.ct' | xargs grep -ln "\bnew\b" | wc -l
16
```

### E1-9 p73 patch 的覆盖缺口（自动 retain / shim / UTF-16）

```console
$ P=docs/planning/j6-evidence/p73/p73-rebased-5736f0d5.patch
$ grep -c "auto_retain\|retain_glue\|__ct_elem_retain" "$P"; echo exit=$?
0
exit=1
$ grep -c "\.m\.ct\|shim" "$P"; echo exit=$?
0
exit=1
$ awk 'NR>=65&&NR<=70{printf "%d:%s\n", NR, $0}' "$P"
65:+/* A nominal UTF-16 placeholder: it exists only so an implicit literal
66:+ * conversion is rejected with a String-specific message. No U16 behaviour is
67:+ * claimed (see P-3.7/P-3.8 in the evidence report). */
68:+pub struct U16String {
69:+    char *ptr;
70:+    int len;
```

### E1-10 PH-82 的剩余闸门是 PH-81（传递阻断）

```console
$ head -4 battle/leak-guards-1/closed.md
# battle/leak-guards-1 归档（closed）

| 项 | 值 |
| --- | --- |

$ awk 'NR==5{printf "%d:%s\n", NR, $0}' docs/decisions/D-012.md
5:- 状态：**accepted**（battle leak-guards-1 判决 A′；用户同意「可确定部分进 PH-82」）
```

D-012 与 battle 归档都已满足 G-10 的两项；PH-82 剩下的门只有 PH-81 收口，而 PH-81 的门是 P-7.5。

### E1-11 P-7.4 可以用隔离副本原型产出（B 的可执行性）

```console
$ awk 'NR>=47&&NR<=52{printf "%d:%s\n", NR, $0}' docs/planning/j6-evidence/p73/evidence.md
47:$ rm -rf /tmp/p73
48:$ mkdir -p /tmp/p73
49:$ git -C /Users/samxx/dsh-ws/ct-lang archive dff5a0df | tar -x -C /tmp/p73
50:$ cd /tmp/p73
51:$ git apply /path/to/docs/planning/j6-evidence/p73/p73.patch
52:$ bash test/p73/run.sh
```

这就是 A.7 所谓「原型门槛」的标准形态：主仓不改源码，证据与原始输出落在 `j6-evidence/`。
P-7.4 的参数/返回/字段 retain、旧 `Str` 并存、`Map<String>`、跨仓 dry-run 都能在同一形态里做；
不需要先落 S5a 产品代码。

## E2 — 锚点（含不利于己方）

**有利于 B**：

- 卡头/卡内硬门：[phase80.md:5](../../docs/design/phase80.md#L5)、
  [:7](../../docs/design/phase80.md#L7)、[:56](../../docs/design/phase80.md#L56)、
  [:58](../../docs/design/phase80.md#L58)、[:104](../../docs/design/phase80.md#L104)、
  [:107](../../docs/design/phase80.md#L107)；
  [phase81.md:5](../../docs/design/phase81.md#L5)、[:6](../../docs/design/phase81.md#L6)；
  [phase82.md:5](../../docs/design/phase82.md#L5)、[:6](../../docs/design/phase82.md#L6)。
- Decision 硬门：[docs/decisions/D-011.md:44](../../docs/decisions/D-011.md#L44)、
  [:61](../../docs/decisions/D-011.md#L61)、[:63](../../docs/decisions/D-011.md#L63)、
  [:64](../../docs/decisions/D-011.md#L64)、[:36](../../docs/decisions/D-011.md#L36)。
- 计划顺序：[docs/planning/pointer-free-phase-plan.md:27](../../docs/planning/pointer-free-phase-plan.md#L27)、
  [:28](../../docs/planning/pointer-free-phase-plan.md#L28)、
  [:32](../../docs/planning/pointer-free-phase-plan.md#L32)、
  [:33](../../docs/planning/pointer-free-phase-plan.md#L33)。
- 提案/证据「施工前」：[docs/proposals/pointer-free-v2.md:187](../../docs/proposals/pointer-free-v2.md#L187)、
  [:272](../../docs/proposals/pointer-free-v2.md#L272)、
  [:273](../../docs/proposals/pointer-free-v2.md#L273)；
  [docs/planning/j6-evidence/p73/evidence.md:281](../../docs/planning/j6-evidence/p73/evidence.md#L281)。
- 缺口：自动 retain [docs/planning/j6-evidence/p73/evidence.md:243](../../docs/planning/j6-evidence/p73/evidence.md#L243)；
  `.data` 未裁定 [docs/planning/j6-evidence/p73/evidence.md:247](../../docs/planning/j6-evidence/p73/evidence.md#L247)；
  UTF-16 占位 [docs/planning/j6-evidence/p73/evidence.md:251](../../docs/planning/j6-evidence/p73/evidence.md#L251)；
  旧 `Str` 替换 [docs/planning/j6-evidence/p73/evidence.md:242](../../docs/planning/j6-evidence/p73/evidence.md#L242)；
  「不直接当 S5a 合并」[docs/planning/j6-evidence/p73/evidence.md:289](../../docs/planning/j6-evidence/p73/evidence.md#L289)。
- 命名/迁移：[language-spec.md:2596](../../docs/language-spec.md#L2596)、
  [lib/std/README.md:10](../../lib/std/README.md#L10)、
  [examples/wave1-demo/src/main.ct:7](../../examples/wave1-demo/src/main.ct#L7)。
- 门禁纪律：[AGENTS.md:468](AGENTS.md#L468)、[AGENTS.md:590](AGENTS.md#L590)。

**不利于己方（本席主动列出，不回避）**：

1. **P-7.3 不是零基础。** A.3.1（16 字节句柄 + 8 字节头）与 A.3.3（字面量/immortal/Drop）已通过，
   6 正 6 负 + ASan + build 模式 16/16（[docs/planning/j6-evidence/p73/evidence.md:13](../../docs/planning/j6-evidence/p73/evidence.md#L13)）；
   S5a 的布局、字面量、不可变下标、`.data`/`cstr` 核心行为已有实测底本。本席若声称「S5a 全部未证」
   就是错的；B 只主张「未证的那部分（自动 retain/U16/并存/迁移）不能靠先落代码补」。
2. **卡内 §1.1 确实支持 A 的读法。** [phase80.md:53](../../docs/design/phase80.md#L53) 逐字写
   S5a 入口 =「P-7.3；PH-79 收口」。B 的读法依赖卡头/§1.2/plan/提案整体优先；这是本席最薄的一处，
   若裁判按「§1.1 是 task 级具体条款」判，B 在 PH-80 上输（F-1）。
3. **`.data`/`cstr` 已被原型部分验证。** `p80_cstr` 的核心行为（只读、子视图、`cstr()` 补 NUL、
   4 个负例）在 p73 已有原始输出（[docs/planning/j6-evidence/p73/evidence.md:225](../../docs/planning/j6-evidence/p73/evidence.md#L225)），
   所以 §2.1 是「裁定缺失」风险，不是「能力未证」风险。B 不夸大。
4. **PH-81 的关键字风险很可能很低，但未测。** tracked `.ct` 中命中 `new` 的 16 个文件里，
   抽查到的非注释样本是英文注释（E1-8；示例 [lib/std/Str.h.ct:68](../../lib/std/Str.h.ct#L68)）；
   本席没有做 P-1.2 的标识符级分类，不能断言为零。B 不把「`new` 破坏既有标识符」当阻断理由；
   PH-81 的阻断只在 P-7.5 的 box 布局/协议证据。
5. **卡面矛盾对 A 同样有利。** 卡头 [:5](../../docs/design/phase80.md#L5) 与 §1.1
   [:53](../../docs/design/phase80.md#L53) 的矛盾是客观事实，任何一方都能引用其中一句；B 的优势
   只是「六份文件同向 + 唯一反例是卡内 stage 表」，不是「文本无歧义」。

## E3 — 可证伪预测

| # | 若 B 成立，应观察到 | 一次性核验 | 若相反 |
| --- | --- | --- | --- |
| 1 | HEAD 上没有任何 decision 把 P-7.4 拆出/放行 S5a | `grep -rn "P-7.4" docs/decisions/` 退出 1（E1-7） | A 能出示 `signer` + `date` 的拆分记录 → B 的过程主张被该记录取代（不是被「读法」取代） |
| 2 | P-7.3 参考 patch 在 HEAD 不能无冲突重放 | `git apply --check` 退出 1，3 处冲突（E1-6） | 若退出 0（或仓库内已有重放产物且 16/16），B 的「入口证据僵化」子论点失败；主论点不受影响 |
| 3 | PH-80 卡面没有 retain/复制协议判据，p73 也没有自动 retain glue | `grep -c "retain" docs/design/phase80.md` = 0；`grep -c "auto_retain..." patch` = 0（E1-5/E1-9） | 若 E80 或某道既有门禁能抓住该语义，§2.2 失败 |
| 4 | `std::str::String` 消费者仍在，P-7.4 七项没有一项覆盖它 | E1-7 + P-7.4 清单 [phase80.md:62-68](../../docs/design/phase80.md#L62-L68) | 若 A 指出某个 P-7.4 项已覆盖该 trait 的迁移，§2.4 弱化 |
| 5 | S5a 回滚只有散文、没有演练；参考 patch 是 8 文件替换且在 HEAD 冲突 | E1-6 + [phase80.md:107](../../docs/design/phase80.md#L107) | 若 A 在 S5a 形状分支上给出干净回滚演练（PH-79 行为不变），§2.5 弱化 |

## E4 — 代价

| 项 | 量化 | 出处 |
| --- | --- | --- |
| 参考改动面 | P-7.3 patch：8 文件、+560/−111；同批 parse/emit 目录在 `5736f0d5..HEAD` 已 +1028/−16；3 个文件冲突 | E1-6、[docs/planning/j6-evidence/p73/evidence.md:288](../../docs/planning/j6-evidence/p73/evidence.md#L288) |
| 迁移语料面 | 21 个 tracked `.ct` 提到 `Str`；12 个调用 `str_slice`/`str_from`/`str_concat`；7 个使用 `Map<Str, …>` | E1-8 |
| 门禁/版本面 | `check-all` 11 道硬门；5 处 `CTC_VERSION`；`test/ast` 404 个目录；E80-1…8 | `selfhost/check-all.sh`、E1-5 |
| P-7.4 待补工作 | 7 项：1 项 `.data` decision；4 项隔离副本原型（旧 `Str` 并存、测试迁移清单、`Map`/`str_*` 命名、跨仓 dry-run）；1 项 UTF-8/U16 API 全量清单；1 项 A.3 全量 ASan（其中 `box<String>` 子项待 PH-81 回填） | [phase80.md:62-68](../../docs/design/phase80.md#L62-L68)、[docs/proposals/pointer-free-v2.md:228](../../docs/proposals/pointer-free-v2.md#L228) |
| 回退 | 卡面只有一句「S5a 可回退到旧 `Str`」，无命令/无 baseline/无演练；参考 patch 是替换式 8 文件 | [phase80.md:107](../../docs/design/phase80.md#L107)、E1-6 |
| 等待成本 | 不是日历成本：原型在 `/tmp` 隔离副本做，不阻塞产品树（E1-11）；代价是 7 项证据的产出与复核 | E1-11 |

## E5 — 对 A 最强论点的 steelman

A 最强的是死锁论证，原文：

> 「P-7.4-7 的 `box<String>` 判据只能由 PH-81 产出，而 PH-81 排在 PH-80 收口之后。B 要可执行，
> 必须把 P-7.4-7 拆出 `box<String>` 项并回填——这已经是阶段化解释；一旦阶段化，S5a 的入口就
> 回到 P-7.3，即 A。」（主张书 J-7）

以及：

> 「一个永远无法满足的门槛不是门槛；B 必须阶段化，阶段化后即 A。」（主张书 E5 第 3 点）

**回应（前两条是让步）**：

1. **让步**：若把「P-7.4 必须由 S5a 自己的产品实现产出」当前提，B 确实成环。本席不接受这个前提。
   A.7 把 P-7.4 定义为「原型门槛」，p73 已经示范原型可以在隔离副本里产出（E1-11）；自动 retain、
   旧 `Str` 并存、`Map<String>`、dry-run 都不需要先合并 S5a。**只有 `box<String>` 一个子项**
   在定义上依赖 PH-81。
2. **让步**：卡面确有一处支持 A 的 §1.1（E2 不利项 2）。所以 B 请求的不是「文本唯一读法」，
   而是：文本冲突时，执行侧不得自行选择对自己有利的一侧；由 EDITOR 在 decision 里裁定。
   若裁判认为 §1.1 优先，B 接受败诉，但裁判必须同时处理卡头/§1.2/plan/提案的矛盾，不能留下
   「同一张卡两种闸门」。
3. **「阶段化即 A」是偷换。** 阶段化的对象不同：B 的阶段化只把 `box<String>` 子项移出入口
   （其余六项仍在 S5a 前闭合）；A′ 的阶段化把 P-7.4-2/3/5/7 全部变成 S5a 的产物（K-4），
   即实现先行、证据后补。前者仍是「证据先于代码」，后者才是 A。不能因为两者都叫「阶段化」
   就推出同一结论。
4. **先例不成立。** PH-78/79 的入口在 plan 里逐字写了豁免：
   PH-78「不要求 P-7.2/P-7.3」（[docs/planning/pointer-free-phase-plan.md:25](../../docs/planning/pointer-free-phase-plan.md#L25)）、
   PH-79「不要求 J-6 全量」（[docs/planning/pointer-free-phase-plan.md:26](../../docs/planning/pointer-free-phase-plan.md#L26)）；
   PH-80 的行写的是「P-7.4 全量」（[docs/planning/pointer-free-phase-plan.md:27](../../docs/planning/pointer-free-phase-plan.md#L27)）。
   同一张表里，78/79 的豁免是写明的，PH-80 没有。这不是「同类事实不同待遇」，而是条款不同；
   A 的「同一口径」请求实际上是在要求把 PH-80 的明文改成 78/79 的明文。
5. **目的对齐。** A.8 说「不以设计推理替代实测」
   （[docs/proposals/pointer-free-v2.md:277](../../docs/proposals/pointer-free-v2.md#L277)）。B 不反对实测，反对的是
   **由被测实现自己产出证据**：S5a 先落代码，再由 S5a 的阶段出口补 P-7.4 证据，等于让实现自证；
   p73 的价值恰恰是「独立副本、先出证据、主仓不动」。证据先行不提高门槛，只是回到卡面写的
   「施工前」。

## 6 结论

1. **B 在文本上成立**：G-1…G-25 来自六份文件（phase80/81 两张卡、D-011、plan、提案、p73 证据），
   一致把 P-7.4/P-7.5 放在施工之前；唯一反例是卡内 §1.1（E2 不利项 2）。这不是「A 的另一种
   读法」，而是卡面矛盾；矛盾未由 EDITOR 裁定前，执行侧不得落实现代码（AGENTS:468、D-011:63）。
2. **三卡的阻断是分层的**：PH-80 ← P-7.4；PH-81 ← P-7.5；PH-82 ← PH-81 收口（D-012 与 battle
   已满足，E1-10）。B 不主张 P-7.5 挡 PH-80，也不主张 PH-82 有独立 P-7.x 门。
3. **跳过的风险是具体的**：ABI（`.data`/头/旧 `Str` 的 `str_*`+`retain`/`release` API）、
   自动 retain（无 E80 判据、无 patch glue）、UTF-16（占位类型变产品类型）、跨仓迁移（替换式原型
   + `std::str::String` trait）、回滚（8 文件替换、HEAD 3 冲突、无演练）。
4. **B 可执行**：P-7.4 的 6/7 项可用 p73 的隔离副本方法产出；唯一依赖 PH-81 的 `box<String>`
   子项，应由 EDITOR 签一条 gate 修订移出入口并写回填条件。该修订不是 A：它不改「证据先于代码」，
   只改一项不可达的子项。
5. **改判条件**：F-1（裁判判 §1.1 优先且要求先修订卡面）或 F-2（出现签字的 P-7.4 拆分 decision）
   成立时，B 按记录改判；F-3 挑战 §3 的前提，F-4…F-6 只削弱从属论点，不动主论点。
