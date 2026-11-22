# battle/phase80-gate-1 主张席（claim）

- 争点：PH-80/81/82 的施工入口是否被「P-7.4 / P-7.5 全量未补」硬阻断。
- 本席主张：**A**（可执行形态见 §1.1 的 A′；差别只在排期，不在证据门槛）。
- 基线：HEAD `6665f01a`（v0.79.2）；卡状态「实施中（准备；施工入口未过）」。
- 边界：只写本文件；不改卡、不改源码、不改 roadmap。证据按规范 §7.7 E1–E5。

## 1 主张 A

**P-7.4 / P-7.5 的「全量」不是 PH-80 落实现代码的绝对前置。PH-80 现在开工，先落 S5a
内建层；P-7.4 在 S5b 入口与 PH-80 收口前补齐；P-7.5 不属于 PH-80 入口集合，内化为
PH-81 S1a 的首任务。**

题面 A 的「三卡现在」按字面与 plan §0.6 的单卡纪律冲突：本席主张的是**三卡的 P-7.x 证据前置
同时解除、施工仍按卡串行**（A′，§1.1）；即「现在」指不再等 P-7.4/P-7.5，不指三卡同日动工。

三条可核查断言：

| ID | 断言 | 在哪被判 |
| --- | --- | --- |
| A-1 | 卡面对 P-7.4 只有一个自洽读法：S5a 入口 = P-7.3 + PH-79 收口；S5b 入口 = P-7.4 + S5a 收口 | J-1、J-3 |
| A-2 | S5a 是加法：新类型入内建层，旧 owning `Str` 以 `std::str::Str` 保留，旧布局与旧生成物不动 | J-5、E3-2 |
| A-3 | P-7.5 是 S1 `box/new` 的原型；PH-80 卡无一处引用它，P-7.3 已验 `{refs,aux}` 头 | J-4、E1-5 |

**本席不主张（防止扩大解释）**：

- 不是免掉 P-7.4：七项仍是 S5b 入口与 PH-80 收口的硬条件；E80-7 未满足前不得收口、
  不得 bump v0.80.0（[docs/design/phase80.md:93](../../docs/design/phase80.md#L93)）。
- 不是三卡并行：PH-81 仍等 PH-80 收口，PH-82 仍等 PH-81 收口
  （[docs/planning/pointer-free-phase-plan.md:15-18](../../docs/planning/pointer-free-phase-plan.md#L15-L18)、
  [docs/design/phase81.md:6](../../docs/design/phase81.md#L6)、[docs/design/phase82.md:6](../../docs/design/phase82.md#L6)）。
  若 `question.md` 把 A 定义为「今天同时落三卡代码」，本席承认该字面版本与 plan §0.6 冲突并撤回，
  只主张 A′。

### 1.1 三卡施工许可表（A′）

| 卡 | 本次允许的实现范围 | 入口 | 仍禁止 |
| --- | --- | --- | --- |
| PH-80 | S5a-1…S5a-4（内建层；旧 `Str` 限定名并存） | P-7.3（在 HEAD 重放后）+ PH-79 已收口（v0.79.0；HEAD v0.79.2） | S5b（删旧/迁移/包版本）、收口、MINOR +1 |
| PH-81 | 不现在开工；PH-80 收口后，S1a 首任务 = P-7.5 七项转红证 | PH-80 收口；P-7.5 内化 | S1b `new` 关键字（P-7.5 未过前）；与 PH-80 并行 |
| PH-82 | 不现在开工；PH-81 收口后 | PH-81 收口 + D-012 accepted + battle 已 closed | 无 P-7.x 前置 |

### 1.2 可接受的条件（K-1…K-7，供裁判逐条写入判决）

| ID | 条件 | 判据 |
| --- | --- | --- |
| K-1 | 只开 S5a；S5b 不删旧、不迁移、不改包版本/索引/README | S5b 的第一个提交晚于 P-7.4 补齐提交 |
| K-2 | S5a-0（证据重放，不计交付）：把 `p73-rebased-5736f0d5.patch` 重放到 `6665f01a`，复跑 `test/p73/run.sh` 得 16/16 | 红证含 `baseline: 6665f01a` + 原始输出；出现任一正例失败即停 |
| K-3 | P-7.4-1（`.data` 类型）在 S5a-4 红证前以 decision 裁定；两种选项各配 `printf("%s", s.data)` 负例 | decision 入库 + 负例原始输出 |
| K-4 | P-7.4-2/3/5/7 作为 **S5a stage 退出证据**；P-7.4-4/6 作为 S5b 入口；P-7.4-7 的 `box<String>` 项在 PH-81 收口后回填并登记 | 卡上逐项贴原始输出；未贴不得判 S5a 过 |
| K-5 | 「旧 `Str` 限定名并存」折进 S5a-1 的验收（`p80_layout` 增加限定名解析正例 + 旧 ABI 不变断言），不新增任务行 | 不改 `tasks`/E80/`version-minor`（`g8-phase-freeze`） |
| K-6 | P-7.5 七项转 S1a 首任务（红证先行）；S1b 关键字改动在 P-7.5 证据齐备前不开工 | 红证 + PH-80 收口 sha |
| K-7 | 每项任务按 T-7 先红后绿；S5a 可回滚到旧 `Str` 唯一拼写；S5a 期间不 bump MINOR、不打 tag | 提交序列 + 回滚演练 |

## 2 J 项（逐条判据与自查）

> 本席自拟 J-1…J-7；若 `question.md` 用不同编号，按本节标题语义对齐。

### J-1 卡内入口条款是否自洽

**结论：卡头与 §1.1/§1.2 互相矛盾，但只有一个读法能同时满足全部卡内条款。**
卡头把 P-7.4 全量写成「前置」（[:7](../../docs/design/phase80.md#L7)），§1.1 却把 S5a 入口写成
「P-7.3；PH-79 收口」（[:53](../../docs/design/phase80.md#L53)），把 P-7.4 放进 S5b 入口
（[:54](../../docs/design/phase80.md#L54)）；E80-7 再把「旧 `Str` 限定名并存」记为 S5a 交付、
「删旧 + 迁移」记为 S5b（[:93](../../docs/design/phase80.md#L93)）。按「具体条款优于摘要」，
S5a 的入口是 P-7.3 + PH-79 收口，P-7.4 是 S5b 与收口的门。plan 明确授权按卡收窄：
「各卡按自己的入口收窄/等待」（[docs/planning/pointer-free-phase-plan.md:8](../../docs/planning/pointer-free-phase-plan.md#L8)）。
**反证**：卡头 [:5](../../docs/design/phase80.md#L5)、[:7](../../docs/design/phase80.md#L7) 与
§1.2 标题「施工前补齐」（[:56](../../docs/design/phase80.md#L56)）按字面不利于本席，见 E2。

### J-2 P-7.3 + PH-79 收口是否足以支撑 S5a 开工

**结论：足以支撑「开工」，不足以支撑「收口」。** P-7.3 的硬断言已实测：`String`/`Str` 16 字节、
头 8 字节、`refs=-1`、Drop/ASan、不可变下标、`.data`/`cstr` 负例，6 正 6 负 16/16
（[docs/planning/j6-evidence/p73/evidence.md:13](../../docs/planning/j6-evidence/p73/evidence.md#L13)、
[:107](../../docs/planning/j6-evidence/p73/evidence.md#L107)）。S5a 的剩余项是 U16、方法集、
字面量期望类型绑定——与已验证部分同构，不是未知机制。
**但入口证据自身已过期**：`git apply --check` 在当前 HEAD 失败（3 个文件冲突，E1-4），
即「P-7.3 已过」只在 `5736f0d5` 上成立。故 K-2 是 A 的第一条义务，不是附加项。

### J-3 P-7.4 是否可以「施工前补齐」——逐项论证

| 项 | 判据的自然产物 | 能否在 S5a 开工前闭合 | 处置 |
| --- | --- | --- | --- |
| P-7.4-1 `.data` 类型裁定 | 一行 decision（S5a-4 的输入） | **能** | K-3 |
| P-7.4-2 旧 `Str` 限定名并存 | S5a 的产物（§1.1 明列） | 不能（循环） | K-4/K-5 |
| P-7.4-3 既有测试全绿/迁移清单 | S5a 后段 + S5b | 不能 | K-4 |
| P-7.4-4 `Map<Str,V>`/`str_slice`/`str_dup` | S5b 的 std 迁移 | 不能（属 S5b） | K-1/K-4 |
| P-7.4-5 UTF-8/U16 API 全量清单 | S5a-3 的交付 | 不能 | K-4 |
| P-7.4-6 外部消费者 dry-run | S5b（卡 R80-5 明定 S5b blocking） | 不能 | K-1/K-4 |
| P-7.4-7 A.3.1–A.3.3 全绿 | S5a（自动 retain）+ PH-81 后回填 `box<String>` | 不能 | K-4 |

三条论证：

1. **循环前置**：P-7.4-2 的判据要求「旧 owning `Str` 仅 `std::str::Str` 限定名、同单元并存」
   （[docs/design/phase80.md:63](../../docs/design/phase80.md#L63)），而 §1.1 把同一件事写成 S5a 的内容
   （[:53](../../docs/design/phase80.md#L53)）。要求 S5a 开工前交出 S5a 的产物，等于要求先交付再生产。
2. **死锁**：P-7.4-7 要求 A.3 全绿，而 A.3.2 的判据含 `box<String>` refcount 轨迹
   （[docs/proposals/pointer-free-v2.md:228](../../docs/proposals/pointer-free-v2.md#L228)）；`box` 由 PH-81 产出，
   PH-81 的前置是 PH-80 收口，PH-80 收口又要求 P-7.4 全量——形成
   `S5b ← P-7.4-7 ← box<String> ← PH-81 ← PH-80 收口 ← S5b` 的环。按字面执行，列车无法启动。
3. **可先行项只有一项**：七项中真正不需要实现即可闭合的只有 P-7.4-1（`.data` 类型），
   它是 S5a-4 的输入而非 blocker，用 decision 在 S5a-4 红证前定即可。

**结论**：P-7.4 只能阶段化；把「全量」当 S5a 入口既循环又死锁。**因此 P-7.4 未做不构成
S5a 开工的硬阻断；它构成 S5b 与 PH-80 收口的硬阻断，这一点本席接受并按 K-1/K-4 兜住。**
阶段化后，S5a 的入口回到 P-7.3 + PH-79 收口，这就是 A。

### J-4 P-7.5 是否属于 PH-80 入口集合

**结论：不属于。** A.7 定义 P-7.5 = S1 `box/new`（最后）
（[docs/proposals/pointer-free-v2.md:273](../../docs/proposals/pointer-free-v2.md#L273)），
phase81 §1.1 把它列为 S1a 入口（[docs/design/phase81.md:46](../../docs/design/phase81.md#L46)）。
`grep -n "P-7.5" docs/design/phase80.md` 为空（E1-5，exit 1）。唯一交集是 refs 头协议，
而 P-7.3 已实测 `sizeof(header)=8`、`{refs,aux}` 语义（docs/planning/j6-evidence/p73/evidence.md:222）。
**故 P-7.5 未做不构成 PH-80 开工的硬阻断**；对 PH-81，本席也不主张现在开工（K-6），
只主张它不再是独立外部前置。

### J-5 先落 S5a 是否引入不可回滚面

**结论：面上的回滚是单 stage 的；语义面有残留风险，须承认。** 卡面明写「S5a 可回退到旧 `Str`；
S5b 与外部迁移绑定，不能整体单回滚」（[docs/design/phase80.md:107](../../docs/design/phase80.md#L107)）。
S5a 只增内建类型 + 保留旧类型，旧 `lib/std/Str.h.ct` 的 `{char *data; int len}` 与生成物不动
（[lib/std/Str.h.ct:18](../../lib/core/Str.h.ct#L18)）；回退 = 反做 8 文件 patch（E1-4 stat）+ 恢复旧拼写。
**残留风险**：裸名 `Str` 的语义是用户可见的，即使未发布也会在 golden/示例中定形；若 S5a 收口前
改口径，会产生一次内部语义 churn。缓解：S5a 不 bump MINOR、不打 tag、不发布，收口门在 E80-7。

### J-6 是否违反 D-011 / T-7 / 单卡 / 版本门禁

| 条款 | 结论 |
| --- | --- |
| D-011 §3.3「未过前不开施工卡」（[docs/decisions/D-011.md:44](../../docs/decisions/D-011.md#L44)） | **字面冲突**（E2 不利项）。但 plan 以「各卡按自己的入口收窄」执行，PH-78/79 均以原型（非全量）开工并收口（[docs/planning/pointer-free-phase-plan.md:26](../../docs/planning/pointer-free-phase-plan.md#L26)、[:31](../../docs/planning/pointer-free-phase-plan.md#L31)）；A 请求同一口径，不是新例外 |
| D-011 §5「具体开卡仍待 J-6 证据通过」（[:61](../../docs/decisions/D-011.md#L61)） | 卡已开（准备态）；争的是「施工」。D-011 未区分二者，需裁判解释 |
| D-011「契约文本未落地不得进入实现」（[:64](../../docs/decisions/D-011.md#L64)） | 借用视图契约已定稿（[docs/proposals/pointer-free-v2.md:144](../../docs/proposals/pointer-free-v2.md#L144)），PH-79 已按四位置白名单落地并收口 |
| T-7 | 满足：每项任务 `test(...) 红` → 实现，K-2 提供 `baseline` |
| 版本 | 满足：S5a/S5b 同一 MINOR，不单独 bump（[docs/planning/pointer-free-phase-plan.md:106](../../docs/planning/pointer-free-phase-plan.md#L106)）；`version-minor=80` 不动 |
| `g8-phase-freeze` | 满足：A′ 不改 `tasks`/E80/`version-minor`；K-5 把并存折进既有任务验收 |
| 单卡纪律 | 满足：PH-81/82 排队（§1.1） |

### J-7 若坚持 B（P-7.4 全量先于 PH-80 开工），是否可执行

**结论：不可执行。** 见 J-3 的死锁环：P-7.4-7 的 `box<String>` 判据只能由 PH-81 产出，
而 PH-81 排在 PH-80 收口之后。B 要可执行，必须把 P-7.4-7 拆出 `box<String>` 项并回填——这已经是
阶段化解释；一旦阶段化，S5a 的入口就回到 P-7.3，即 A。B 若拒绝阶段化，则它的开工条件永远无法满足。

## E1 — 证据（命令与原始输出）

### E1-1 卡面入口条款

```console
$ awk 'NR==3||NR==5||NR==7||NR==51||NR==53||NR==54||NR==56||NR==58||NR==93||NR==107{printf "%d:%s\n", NR, $0}' docs/design/phase80.md
3:> **状态：实施中（准备；施工入口未过）**（2026-11-20 立项并开卡；`v0.80.0`）。
5:> **施工闸门**：P-7.3 最小切片已过、**PH-79 已收口（v0.79.0）**；**P-7.4 全量未补**。
7:> **前置**：P-7.3 最小垂直切片 + P-7.4 全量；PH-79 切片表示收口 ✅。
51:| stage | 内容 | 入口 |
53:| S5a 内建层 | `String/Str` + `U16String/U16Str` 类型、L1 字面量、核心方法、旧 `Str` 限定名并存 | P-7.3；PH-79 收口 |
54:| S5b 删旧/迁移 | 删旧 `Str`、std 消费者迁移、索引/包版本、README/spec/roadmap 三处同步 | P-7.4；S5a 收口 |
56:### 1.2 P-7.4 入口证据清单（施工前补齐）
58:P-7.3 最小切片已 rebase 到 `5736f0d5` 并重放 **16/16**，产物 [`j6-evidence/p73/p73-rebased-5736f0d5.patch`](../planning/j6-evidence/p73/p73-rebased-5736f0d5.patch)；它替换了旧 `lib/std/Str.h.ct`，只作 S5a 参考，不直接合并。
93:| E80-7 | S5a 旧 `Str` 限定名并存；S5b 删旧 + std 消费者迁移 dry-run |
107:回滚：S5a 可回退到旧 `Str`；S5b 与外部迁移绑定，不能整体单回滚。
# 退出码 0
```

### E1-2 计划与先例

```console
$ awk 'NR==8||NR==26||NR==27||NR==31||NR==32||NR==106{printf "%d:%s\n", NR, $0}' docs/planning/pointer-free-phase-plan.md
8:| 门槛 | J-6 证据（P-7.1a/P-7.1b/P-7.2/P-7.3）、J-7 成本、J-8 依赖；各卡按自己的入口收窄/等待 |
26:| **PH-79** | S3 切片 `T[]`（[卡](../design/phase79.md)） | v0.79.0 | P-7.2 原型（25/25、10/10 放置；已在 `ca3354a5` 重放）；不要求 J-6 全量；PH-78 收口 | 附录 A.4 全绿；`T[]` 唯一拼写；`T a[]` 迁移；`s[i]` 带检查 place、越界 trap；`get` 软访问；`const T[]` 只读 | 单卡回滚；数组仍走 C |
27:| **PH-80** | S5 `String` / `Str`（[卡](../design/phase80.md)） | v0.80.0 | P-7.3 最小垂直切片 + P-7.4 全量；S3 收口 | 附录 A.3/A.6 全绿；UTF-8/UTF-16 双类型；L1 字面量；`.data`/`cstr`；U16 核心方法；std 消费者迁移 dry-run | S5a 内建层 + 旧 `Str` 并存；S5b 删旧 + 外部迁移；S5b 前不可整体回滚 |
31:> PH-78 已收口（v0.78.0 / fix v0.78.1），PH-79 已收口（v0.79.0，入口只要求 P-7.2 原型）；
32:> PH-80–82 已开卡（准备），施工按入口串行：P-7.4 → PH-80、P-7.5 + PH-80 → PH-81、PH-81 → PH-82。
106:- S5a/S5b 是同一 phase 的 stage，不换号、不单独 bump；
# 退出码 0
```

### E1-3 D-011 的门槛条款

```console
$ awk 'NR==44||NR==61||NR==63||NR==64{printf "%d:%s\n", NR, $0}' docs/decisions/D-011.md
44:3. **证据门槛仍是硬门**：J-6/J-7/J-8 未过前不开施工卡；P-1…P-7 见
61:  [pointer-free-phase-plan](../planning/pointer-free-phase-plan.md)；具体开卡仍待 J-6 证据通过；
63:- 证据任务全部完成后，回到 EDITOR 复核 J-6/J-7/J-8，再决定是否开第一张施工卡；
64:- 若 J-4a/J-4b 的契约文本未落地，`Str`/切片的借用位置规则不得进入实现。
# 退出码 0
```

### E1-4 P-7.3 原型对当前 HEAD 的复用性

```console
$ git apply --check docs/planning/j6-evidence/p73/p73-rebased-5736f0d5.patch; echo exit=$?
exit=1
error: patch failed: selfhost/ct-ast/backend/emit/Emitter.h.ct:1398
error: patch failed: selfhost/ct-ast/frontend/parse/Expr.h.ct:306
error: patch failed: selfhost/ct-ast/frontend/parse/Stmt.h.ct:2288

$ git apply --check --3way docs/planning/j6-evidence/p73/p73-rebased-5736f0d5.patch; echo exit=$?
exit=0
Applied patch to 'lib/std/Str.h.ct' cleanly.
Applied patch to 'selfhost/ct-ast/backend/emit/Emitter.h.ct' with conflicts.
Applied patch to 'selfhost/ct-ast/frontend/module/Module.h.ct' cleanly.
Applied patch to 'selfhost/ct-ast/frontend/parse/Expr.h.ct' with conflicts.
Applied patch to 'selfhost/ct-ast/frontend/parse/Parser.h.ct' cleanly.
Applied patch to 'selfhost/ct-ast/frontend/parse/Stmt.h.ct' with conflicts.
Applied patch to 'selfhost/ct-ast/frontend/type/TypeCheck.h.ct' cleanly.
Applied patch to 'selfhost/ct-ast/tool/driver/Driver.h.ct' cleanly.

$ git apply --stat docs/planning/j6-evidence/p73/p73-rebased-5736f0d5.patch | tail -1
 8 files changed, 560 insertions(+), 111 deletions(-)
$ git diff --stat 5736f0d5..HEAD -- selfhost/ct-ast/frontend/parse selfhost/ct-ast/backend/emit | tail -1
 5 files changed, 1028 insertions(+), 16 deletions(-)
```

`--3way` 的 `exit=0` 只表示「冲突可三方合并」，不表示可无冲突重放：三个 `with conflicts`
就是必须人工解决的三处。这条同时是对本席不利的证据（E2）。

### E1-5 P-7.5 不在 PH-80 卡内

```console
$ grep -n "P-7.5" docs/design/phase80.md; echo exit=$?
exit=1

$ grep -n "P-7.5" docs/design/phase81.md | head -3
5:> **施工闸门**：P-7.5 未做、PH-80 未收口；未过前只做证据、设计与夹具，不落实现代码。
6:> **前置**：P-7.5；PH-80 句柄协议收口。
46:| S1a 类型/协议 | `box<T>`、refs 头、Drop、借用视图/失效检测 | P-7.5；PH-80 |
```

### E1-6 P-7.4-7 的 `box<String>` 死锁源

```console
$ grep -n "P-7.4\|P-7.5" docs/proposals/pointer-free-v2.md; sed -n "186,187p" docs/proposals/pointer-free-v2.md
272:| P-7.4 | S5 全量（施工前） | A.3 全绿；跨仓 dry-run |
273:| P-7.5 | S1 `box/new`（最后） | 句柄协议复用；`new` 仅具名 struct |
J-6 最低原型集：**S2 全量 + S3 全量 + S5 最小垂直切片**（String 句柄 + 字面量 `Str`，不做
`cstr`/迁移/旧 `Str`）。通过后开第一张正式卡（S2）；S5 全量原型在 S5 施工卡开工前补齐。

$ grep -n "box<String>" docs/proposals/pointer-free-v2.md
228:| P-3.2 | 复制/Drop 协议 | 参数/返回/字段/`Vec<String>`/`box<String>` refcount 轨迹；ASan |
```

### E1-7 P-7.3 实测结论与缺口

```console
$ awk 'NR>=13&&NR<=18||NR==107{printf "%d:%s\n", NR, $0}' docs/planning/j6-evidence/p73/evidence.md
13:| P-7.3 最小垂直切片（String 句柄 + 字面量 `Str` + A.3.1/A.3.3） | **通过**：6 个正例、6 个负例、ASan、build 模式全部实测通过 |
14:| A.3.1（16 字节句柄 + 8 字节头） | **通过** |
15:| A.3.2（复制/Drop 协议） | **部分通过**：显式 `copy()`/`retain()`/`release()`、`Vec<String>` 元素 glue、`own`/`delete` 实测；**未覆盖**参数/返回/字段的自动 retain、`box<String>`、`Map<...,String>` |
16:| A.3.3（字面量视图 / immortal / String 有 Drop） | **通过** |
17:| 旧 `std::str::Str` | **未覆盖**：原型用新 `String`/`Str` 替换了 `lib/std/Str.h.ct`，旧 owning `Str` 及其消费者不在本轮 |
18:| J-6 能否据此过 P-7.3 | **可以记 P-7.3 通过（最小切片）**；不能据此把 A.3 全量或 P-7.4 记为通过 |
107:summary: 16 passed, 0 failed
```

## E2 — 证据锚点（含不利于己方）

**有利于 A**：

- [docs/design/phase80.md:53-54](../../docs/design/phase80.md#L53-L54)：S5a 入口 = P-7.3 + PH-79；S5b 入口 = P-7.4。
- [docs/design/phase80.md:93](../../docs/design/phase80.md#L93)：E80-7 把 P-7.4 的内容分给 S5a/S5b。
- [docs/planning/pointer-free-phase-plan.md:8](../../docs/planning/pointer-free-phase-plan.md#L8)：各卡按自己的入口收窄。
- [docs/planning/pointer-free-phase-plan.md:26](../../docs/planning/pointer-free-phase-plan.md#L26)：PH-79 入口只要求原型、不要求 J-6 全量（先例）。
- [docs/proposals/pointer-free-v2.md:273](../../docs/proposals/pointer-free-v2.md#L273)：P-7.5 = S1 `box/new`（最后）。

**不利于己方（本席主动列出，不回避）**：

1. [AGENTS.md:590](../../AGENTS.md#L590)：「PH-80–82 已开卡准备（施工入口未过，**不落实现代码**）」——
   项目当前状态明写禁止，A 要改的正是这句话所描述的状态。
2. [docs/design/phase80.md:5](../../docs/design/phase80.md#L5)、[:7](../../docs/design/phase80.md#L7)、
   [:56](../../docs/design/phase80.md#L56)：P-7.4 全量被写成「前置」「施工前补齐」。
3. [docs/decisions/D-011.md:44](../../docs/decisions/D-011.md#L44)：J-6/J-7/J-8 未过前不开施工卡；
   [:63](../../docs/decisions/D-011.md#L63)：证据任务全部完成后才决定是否开第一张施工卡。
4. [docs/proposals/pointer-free-v2.md:272](../../docs/proposals/pointer-free-v2.md#L272)、[:187](../../docs/proposals/pointer-free-v2.md#L187)：
   P-7.4 =「S5 全量（施工前）」；「S5 全量原型在 S5 施工卡开工前补齐」。
5. [docs/planning/j6-evidence/p73/evidence.md:281](../../docs/planning/j6-evidence/p73/evidence.md#L281)：「P-7.4 在 S5 施工卡前补齐」；
   [:18](../../docs/planning/j6-evidence/p73/evidence.md#L18)：「不能据此把 A.3 全量或 P-7.4 记为通过」。
6. E1-4：P-7.3 patch 在 `6665f01a` 上不能无冲突重放，且 A.3.2 只到显式协议
   （[docs/planning/j6-evidence/p73/evidence.md:223](../../docs/planning/j6-evidence/p73/evidence.md#L223)）——「入口已过」
   的时效与覆盖面都弱于卡头措辞。

## E3 — 可证伪预测

1. **若 A-2 成立**：S5a-1 落地「旧 `Str` 限定名并存」时，`lib/std/Str.h.ct` 的
   `pub struct Str` 布局与全部旧 golden 字节不变，`std::str::Str` 限定名可解析，裸名 `Str` 为借用。
   若必须改旧 `Str` 的布局或生成物才能并存，A-2 失败，A 退为 B。
2. **若 J-2 成立**：K-2 的重放应在一个 stage 内得到 `summary: 16 passed, 0 failed`
   （baseline `6665f01a`）。若重放后任一正例失败且需要先改 P-7.4 决策才能转绿，
   「P-7.3 足以支撑开工」失败。
3. **若 B 成立**：应能给出一个不依赖 S5a/S5b/PH-81 产物的 P-7.4 全量证据包。
   只要 P-7.4-2/5/7 中任一项的判据必须由这些产物提供，B 的可执行性失败（J-3/J-7）。
4. **若 A-3 成立**：PH-80 卡与 plan 中不应存在把 P-7.5 列为 PH-80 入口的条款（E1-5 已验空）。
   反对席若能指出一处，A-3 失败。

四条都是一次性可验：前两条是命令，后两条是文档检索。

## E4 — 代价

| 项 | 量化 |
| --- | --- |
| 参考改动面 | P-7.3 参考 patch：8 文件、+560/−111（E1-4）；当前 HEAD 在其涉及的 parse/emit 文件上已有 +1028/−16，需解决 3 处冲突 |
| 语料面 | 提及 `Str` 的 `.ct` 17 个；`import std::str` 的实际非临时文件 2 个（其余在 `.temp/` 副本）；跨仓消费者未知（P-7.4-6 的缺口） |
| 门禁面 | `check-all` 11 道、`check-ast`（新增 `p80_*`）、`check-docs`、5 处 `CTC_VERSION`、README/docs/AGENTS/phase-log、G1/G4/G6/G8 |
| 回退 | S5a：反做 8 文件 patch + 恢复旧 `Str` 唯一拼写（[docs/design/phase80.md:107](../../docs/design/phase80.md#L107)）；S5b 不可单回滚 |
| 等待成本 | 不是日历估算，而是不可执行性：B 的字面读法使 `S5b ← P-7.4-7 ← box<String> ← PH-81 ← PH-80 收口` 成环（J-3） |

## E5 — 对 B 最强论点的 steelman

**B 最强原文**：「证据门槛仍是硬门：J-6/J-7/J-8 未过前不开施工卡」
（[docs/decisions/D-011.md:44](../../docs/decisions/D-011.md#L44)）；「P-7.4 | S5 全量（施工前）」
（[docs/proposals/pointer-free-v2.md:272](../../docs/proposals/pointer-free-v2.md#L272)）；卡头「前置：P-7.3 最小垂直切片
+ P-7.4 全量」（[docs/design/phase80.md:7](../../docs/design/phase80.md#L7)）。三点字面一致，且都是同一权威链上的
上位文件；单看任意一条，A 都不成立。

**回应（四条，前两条是让步）**：

1. **让步**：若裁判采用「D-011 字面优先于 plan 执行口径」，A 不成立。但同一逻辑必须同时适用于
   PH-78/79——它们同样在 J-6 全量未过时以原型开工并收口（PH-78 入口「不要求 P-7.2/P-7.3」见
   [docs/planning/pointer-free-phase-plan.md:25](../../docs/planning/pointer-free-phase-plan.md#L25)；
   PH-79「不要求 J-6 全量」见 [:26](../../docs/planning/pointer-free-phase-plan.md#L26)）。裁判若不追认这两张卡的开工，
   规则对同类事实不可预期；若追认，就应给出与 A 相同的阶段化解释。
2. **让步**：P-7.3 的证据不覆盖 P-7.4，也不能覆盖旧 `Str` 并存与自动 retain
   （[docs/planning/j6-evidence/p73/evidence.md:18](../../docs/planning/j6-evidence/p73/evidence.md#L18)、
   [:223](../../docs/planning/j6-evidence/p73/evidence.md#L223)）。本席不声称 S5a 一开工就已达标，
   只声称它产出的正是 P-7.4 缺的那部分证据，且 E80-7 会拦住提前收口。
3. **B 不可执行**：B 的门槛含 P-7.4-7 → A.3.2 → `box<String>` → PH-81 → PH-80 收口，
   成环（E1-6、J-3）。一个永远无法满足的门槛不是门槛；B 必须阶段化，阶段化后即 A。
4. **门槛目的**：A.8 的目的是「不以设计推理替代实测」（[docs/proposals/pointer-free-v2.md:277](../../docs/proposals/pointer-free-v2.md#L277)）。
   A 不替代实测：K-2 先在 HEAD 重放 P-7.3，S5a 每项仍先红后绿，P-7.4 的产物仍是原始输出。
   差别只在证据与代码的**先后**（同一 phase 内），不在证据的有无——这正是 §1.1 已把两件事
   分给 S5a/S5b 的原因。
