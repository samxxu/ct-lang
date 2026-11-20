# battle/phase80-gate-1 判决

> **状态：`closed`**（2026-11-20；裁判 EDITOR；1 轮 claim/counter；本场无 `question.md`、无 `verify.json`，见 §7）。
> **判决：B —— 现在不允许 PH-80/81/82 落实现代码。** A/A′ 不成立（§7.9 `rejected`）；
> A 只在 J-3a（`box<String>` 子项不可达）、J-4（P-7.5 不属 PH-80 入口）、J-8（PH-82 只等 PH-81）三处事实层面成立。
> **一句话**：P-7.3 的最小切片有 16/16 的证据支持，P-7.4 的「全量」确实有一个不可达子项；但这两点合起来
> 只能支持「先补证据、修订一个 gate 子项」，不能支持「S5a 先落实现、其余证据后补」。

## 0 争点、基线与材料

| 项 | 值 |
| --- | --- |
| 争点 | PH-80/81/82 的施工入口是否被「P-7.4 / P-7.5 全量未补」硬阻断；现在能否落实现代码 |
| 基线 | HEAD `6665f01a`（`v0.79.2`，PH-79 收口后）；三卡状态「实施中（准备；施工入口未过）」 |
| 主张席 | A（实际形态 A′：§1.1 + K-1…K-7；claim 自述若「A = 三卡同日动工」则撤回该字面版） |
| 反对席 | B（PH-80 ← P-7.4；PH-81 ← P-7.5；PH-82 ← PH-81；卡面矛盾须 EDITOR 以签收 decision 修订） |
| 材料 | `claim.md`、`counter.md`；`question.md` 缺失、`verify.json` 缺失（§7） |
| 裁判 | EDITOR（本席）；未改源码、卡、计划、decision；只写本文件 |

三条卡内事实先定：

- [phase80.md:5-6](../../docs/design/phase80.md#L5-L6) 的施工闸门逐字写「P-7.4 全量未补」与
  「未过前只做证据、设计与夹具，不落实现代码」；
- [phase80.md:53-54](../../docs/design/phase80.md#L53-L54) 的 stage 表把 S5a 入口写成
  `P-7.3；PH-79 收口`，S5b 入口写成 `P-7.4；S5a 收口`；
- [phase80.md:56](../../docs/design/phase80.md#L56) 的 §1.2 标题逐字写
  「P-7.4 入口证据清单（施工前补齐）」。

卡面矛盾是客观事实；争点不是「有没有矛盾」，而是「矛盾未由签收 decision 消解前，执行侧能不能自己选一边」。
本席判：**不能**。J-1/J-2/J-6 是本次判决的主干。

## 1 逐项判决

> 标签口径：**A** = 主张席（A/A′）在该项成立；**B** = 反对席（B）在该项成立。
> 一个 J 的 A 不自动推出另一个 J 的 A；整体结论在 §2。

| J | 争点 | 判决 | 依据（条款 / 证据） |
| --- | --- | --- | --- |
| J-1 | 卡面是否只有一个自洽读法（claim A-1） | **B** | 卡头 [phase80.md:5-7](../../docs/design/phase80.md#L5-L7) 的「施工闸门 / 前置」、[phase80.md:56](../../docs/design/phase80.md#L56) 的「施工前补齐」、[plan:27](../../docs/planning/pointer-free-phase-plan.md#L27) 的 PH-80 入口、[plan:32-33](../../docs/planning/pointer-free-phase-plan.md#L32-L33) 的「P-7.4 → PH-80」「准备态不得落实现代码」、[D-011:44](../../docs/decisions/D-011.md#L44)、[:61](../../docs/decisions/D-011.md#L61)、[:63](../../docs/decisions/D-011.md#L63) 与 [AGENTS.md:590](../../AGENTS.md#L590) 同向。claim 的读法使卡头 L6「不落实现代码」为假，见 §1.1(a) |
| J-2 | P-7.3 + PH-79 是否足以支撑 S5a 开工（claim J-2） | **B** | P-7.3 只覆盖最小切片；旧 `Str` 并存、自动 retain、U16、跨仓迁移未证（[p73 evidence:13-18](../../docs/planning/j6-evidence/p73/evidence.md#L13-L18)、[:242-251](../../docs/planning/j6-evidence/p73/evidence.md#L242-L251)）；参考 patch 在 HEAD 不能无冲突重放（`git apply --check` exit 1，3 冲突；`--3way` 仍有 3 个 `with conflicts`，见 §8）；卡头 L5-6 的闸门未过 |
| J-3a | P-7.4-7 的 `box<String>` 子项是否在 S5a 前不可达（claim J-3 的局部） | **A** | A.3.2 含 `box<String>` refcount 轨迹（[proposal:228](../../docs/proposals/pointer-free-v2.md#L228)）；`box` 属 PH-81（[proposal:273](../../docs/proposals/pointer-free-v2.md#L273)、[phase81.md:46](../../docs/design/phase81.md#L46)）；PH-81 排在 PH-80 收口后（[plan:42](../../docs/planning/pointer-free-phase-plan.md#L42)）。反证席 E5-1 也承认这一点 |
| J-3b | 该不可达性是否支持 A′ 把 -2/-3/-5/-7 全移入 S5a 产物（claim K-4） | **B** | P-7.4 定义为「S5 全量（施工前）」，且明写「S5 全量原型在 S5 施工卡开工前补齐」（[proposal:187](../../docs/proposals/pointer-free-v2.md#L187)、[:272](../../docs/proposals/pointer-free-v2.md#L272)）；p73 已示范隔离副本原型方法（[p73 evidence:47-52](../../docs/planning/j6-evidence/p73/evidence.md#L47-L52)）；这些项不需要产品代码。A′ 是「代码先于证据」，与 A.8「不以设计推理替代实测」（[proposal:277](../../docs/proposals/pointer-free-v2.md#L277)）和 D-011 L44 相反 |
| J-4 | P-7.5 是否属于 PH-80 入口（claim A-3） | **A** | `grep -n "P-7.5" docs/design/phase80.md` 为空（exit 1，§8）；P-7.5 列在 [phase81.md:5-6](../../docs/design/phase81.md#L5-L6)、[:46](../../docs/design/phase81.md#L46) 与 [plan:28](../../docs/planning/pointer-free-phase-plan.md#L28)。但 PH-81 仍等 P-7.5 + PH-80 收口，见 J-9 |
| J-5 | 先落 S5a 是否引入不可回滚面（claim J-5） | **B** | 卡面只有一句「S5a 可回退到旧 `Str`」（[phase80.md:107](../../docs/design/phase80.md#L107)），无命令、无 baseline、无演练；参考 patch 是 8 文件 +560/−111 的替换式改动，且 HEAD 有 3 冲突；S5a-1…4 落在同一批 parse/emit 行上。6.6 T-4 的「每项任务能单独 `git revert`」未演练；claim 自认「语义面有残留风险」 |
| J-6 | 是否违反 D-011 / 计划 / 单卡 / 版本 / T-7（claim J-6） | **B** | D-011 L44 是 USER 签收的硬门：「J-6/J-7/J-8 未过前不开施工卡」；L61/L63 写「具体开卡仍待 J-6 证据通过」「证据任务全部完成后…再决定」；plan L32-33 写「P-7.4 → PH-80」「准备态不得落实现代码」；AGENTS L590 同向。`grep -rn "P-7.4" docs/decisions/` 为空（§8），即无签收的拆分 decision。T-7、版本（S5a/S5b 同一 MINOR，`version-minor=80`）、单卡本身不阻断，但不足以抵消入口门 |
| J-7 | B 是否不可执行（claim J-7 的死锁论） | **B** | 死锁只在 `box<String>` 子项，不在其余各项（J-3a）；B 的修法是把该子项移出入口并写回填条件（反证席 §3/E5-3），其余项用 p73 的隔离副本方法（[p73 evidence:47-52](../../docs/planning/j6-evidence/p73/evidence.md#L47-L52)）。claim「阶段化即 A」是偷换：移一个 gate 子项 ≠ 把其余项变成 S5a 的产物 |
| J-8 | PH-82 的入口是否只剩 PH-81（双方一致点） | **A** | [D-012:5](../../docs/decisions/D-012.md#L5) 已 accepted；[battle/leak-guards-1/closed.md](../leak-guards-1/closed.md) 存在；[phase82.md:5-6](../../docs/design/phase82.md#L5-L6) 与 [plan:29](../../docs/planning/pointer-free-phase-plan.md#L29) 的另外两项已满足，剩余是 PH-81 收口 |
| J-9 | 整体：PH-80/81/82 现在能否落实现代码 | **B** | PH-80 受 P-7.4 全量门（J-1/J-2/J-6）；PH-81 受 P-7.5 + PH-80 收口（[phase81.md:5-6](../../docs/design/phase81.md#L5-L6)、[plan:28](../../docs/planning/pointer-free-phase-plan.md#L28)）；PH-82 受 PH-81 收口（[phase82.md:5](../../docs/design/phase82.md#L5)）；三者串行（[plan:42](../../docs/planning/pointer-free-phase-plan.md#L42)）。且无签收的 gate 拆分 decision |

### 1.1 关键理由

**(a) 卡面不是「只有一个自洽读法」（J-1）。** 主张席的读法是「S5a 入口 = P-7.3 + PH-79，所以 S5a 可以绕开 P-7.4」。
但卡头 [phase80.md:6](../../docs/design/phase80.md#L6) 是**针对实现代码的显式禁止**：「未过前只做证据、设计与夹具，不落实现代码」；
它不是一个可被 stage 表覆盖的摘要。反证席的读法（phase 级闸门是全局的；stage 表的「入口」是 stage 自己的追加前提，
S5a 的 P-7.3 在全局闸门打开后才生效）能同时满足卡头、§1.1、§1.2 三处；主张席的读法必然让 L6 为假。
因此「只有一个自洽读法」不成立；**有矛盾，且只有 B 的读法能同时满足全部卡内条款**。
claim 引用的「具体条款优于摘要」在本仓规范里没有这条规则（`grep` 无命中，§8 可复核），即使有，
L6 本身就是具体条款，不是摘要。

**(b) P-7.3 的时效与覆盖面（J-2）。** P-7.3 的 16/16 有报告与双方原始输出支持，但它在 `5736f0d5` 上成立：
`git apply --check` 在 HEAD `6665f01a` 上 exit 1，3 个文件冲突；`--3way` 只表示冲突可三方合并，仍有 3 个
`with conflicts`。更关键的是覆盖：旧 owning `Str` 被替换、自动 retain 未做、`box<String>`/`Map<...,String>` 未做、
U16 只是占位、跨仓 dry-run 未做（[p73 evidence:15-17](../../docs/planning/j6-evidence/p73/evidence.md#L15-L17)、
[:242-251](../../docs/planning/j6-evidence/p73/evidence.md#L242-L251)）。S5a 的剩余项（旧 `Str` 并存、U16 方法集、
字面量期望类型绑定）**不是**与已验证部分同构的「已知机制」：旧 `Str` 并存是 ABI/命名冲突，U16 是产品类型，
自动 retain 是所有权契约。claim 的「同构」判断没有证据。本席不否认 P-7.3 的机制底本
（句柄/字面量/不可变下标/ASan 有实测）；J-2 判的是「入口是否满足」，不是「机制是否存在」。

**(c) 死锁是真的，但只在一个子项（J-3a/J-3b）。** A.3.2 的 `box<String>` 子项只能由 PH-81 产出，
PH-81 又在 PH-80 收口后——这一点主张席判对了，反证席也承认。但正确的修法是反证席 §3/E5-3 的
**单子项 gate 修订**：把 `box<String>` 移出 S5a 入口，回填条件 = PH-81 收口；其余项（-6 按卡 L104 留 S5b）仍在 S5a 前以隔离原型产出。
主张席把它扩大成「-2/-3/-5/-7 全部变成 S5a 的产品」，这是把「修一个不可达子项」换成「代码先于证据」，
不是同一个阶段化。P-7.4 的文本自己写的是「S5 全量**原型**」在「S5 施工卡**开工前**补齐」
（[proposal:187](../../docs/proposals/pointer-free-v2.md#L187)），原型可以在 `/tmp` 副本里做，p73 已经示范过。

**(d) 回滚与 D-011（J-5/J-6）。** 卡面只有一句散文，没有回滚判据；参考 patch 是替换式 8 文件，且在 HEAD 有 3 冲突；
S5a-1…4 共用同一批 parse/emit 行。要证明「S5a 可回退」，需要一次实际 `git revert` 演练，而不是又一句「可回退」。
D-011 是 USER 签收的 decision，L44/L61/L63 把证据放在施工之前；plan L32-33 与 AGENTS L590 同向。
claim 用 PH-78/79 做先例，但 78/79 的卡头**逐字写死了豁免**：
[phase78.md:4-6](../../docs/design/phase78.md#L4-L6)「前置（口径写死）… 不要求 P-7.2/P-7.3」、
[phase79.md:6-8](../../docs/design/phase79.md#L6-L8)「J-6 全量不在本卡入口」。
PH-80 的卡头写的是相反的话（P-7.4 全量）。这不是「同类事实不同待遇」，而是 78/79 有明文豁免、PH-80 没有。

**(e) B 可执行（J-7）。** B 不是「永远等」：P-7.4 除 `box<String>` 外的各项（-6 按卡 L104 留 S5b）可以在隔离副本里做（p73 的方法）；
`box<String>` 一项由签收 decision 移出入口并写回填条件；PH-80 收口后再做 PH-81。claim 的「一个永远无法满足的
门槛不是门槛」只对 `box<String>` 一项成立，而一项的修法不需要推翻其余项的证据顺序。

## 2 整体判决

**B 胜；A/A′ `rejected`。** 按 §7.9：主张席的方案没有满足全部判据；反证席列出的六条失效条件
F-1…F-6 均未被证据证实——F-1（§1.1 优先）本席明确不采纳，F-2（存在签收的拆分 decision）经
`grep -rn "P-7.4" docs/decisions/` 证实不存在（§8），F-3…F-6 也都没有对应证据。

判决不是「卡面没有矛盾」，而是「矛盾不能由执行侧自行选择有利的一侧」：
- 卡头 L5-7 + §1.2 L56 + plan L27/L32 + D-011 L44/L61/L63 + AGENTS L590 构成同向的入口门；
- 唯一反例是 stage 表 L53；它不是「更具体所以优先」，而是与 L6 直接冲突；
- 执行侧自行采信 L53 就是「放宽/跳过门禁」，按 [AGENTS.md:468](../../AGENTS.md#L468) 应拒绝，走签收 decision 或规范修订；
- 截至 HEAD，`docs/decisions/` 没有任何 P-7.4 的拆分/放行记录（§8），故 F-2 未被证实，B 不被推翻。

**本席同时采纳 A 的三点事实**：P-7.5 不在 PH-80 入口（J-4）；PH-82 只等 PH-81（J-8）；
`box<String>` 子项在 S5a 前不可达（J-3a）。第三点使「照字面执行 P-7.4 全量」不可执行，
因此本判决附 §4 的 gate 修订条件；**但修订必须由签收 decision 完成，不能由本判决代替**。
本判决本身不是 ADR，不改 D-011；在 D-013 入库前，现行入口门（B）继续有效。

## 3 不采纳

| # | 不采纳项 | 理由 |
| --- | --- | --- |
| 1 | 「S5a 现在可开工，P-7.4 其余项后补」（A′ K-1/K-4） | 违反卡头 L6、plan L32-33、D-011 L44；且把 P-7.4 从「原型证据」改成「S5a 产品证据」，方向相反 |
| 2 | 「P-7.3 + PH-79 足以支撑 S5a 开工」（claim J-2） | P-7.3 是最小切片且已僵化；旧 `Str` 并存/U16/自动 retain/跨仓迁移未证 |
| 3 | 「卡面只有一个自洽读法」（claim J-1） | B 的读法同时满足卡头、§1.1、§1.2；A 的读法使 L6 为假 |
| 4 | 「B 不可执行 / 阶段化即 A」（claim J-7） | 死锁只在 `box<String>` 一项；单子项修订仍是 B，不是 A |
| 5 | 「PH-78/79 先例 = PH-80 可照做」（claim J-6） | 78/79 卡头写死了豁免；PH-80 卡头写的是「P-7.4 全量」 |
| 6 | 「S5a 是纯加法、旧 `Str` 布局与生成物不动」（claim A-2） | 未证；p73 是替换旧 `Str`，旧 ABI 含 Drop/release/`str_*`，且 `std::str::String` trait 的命名冲突未被 P-7.4-2 覆盖（[lib/std/README.md:10](../../lib/std/README.md#L10)、[examples/wave1-demo/src/main.ct:7](../../examples/wave1-demo/src/main.ct#L7)） |
| 7 | 「`.data` 类型可拖到 S5a-4 再定」（claim K-3） | `.data` 是类型/ABI 的一部分，S5a-1/2 的字面量与句柄就可能定形；本判决要求最迟 S5a-1 红证前（C-3） |

**采纳但降级为条件**：P-7.3 在 HEAD 重放（C-4）、P-7.4 隔离原型证据（C-5）、`.data` decision（C-3）、
retain 合同（C-6）、回滚演练（C-7）。这些是「现在可做」的工作，不是「现在可落实现代码」的许可。

## 4 条件（可机械验收）

> 所有条件都要求**入库**（`git log` 可追溯）且**有原始输出**；未入库的草稿、口头确认、卡内备注不算。
> 命令在仓库根执行；`<ct-ast>` 指 `bash selfhost/check-ast.sh` 构建出的二进制。

### 4.1 门禁修订（S5a 开工的前置）

| ID | 条件 | 机械验收 |
| --- | --- | --- |
| C-1 | 签收 decision：`docs/decisions/D-013.md`（当前下一个空号；若已被占用，用实际空号并同步替换本节）。内容至少四项：①`P-7.4-7` 的 `box<String>` 子项移出 S5a 入口，回填条件 = PH-81 收口；②`P-7.4-6` 外部 dry-run 按卡 L104 留在 S5b blocking；③其余六项（-1/-2/-3/-4/-5 + -7 去 box）在 S5a 前闭合：-1 为 decision（C-3），其余五项为隔离原型（C-5）；④明确「D-013 入库后，C-2…C-6 全过才放行 S5a 实现代码；C-7 是 S5a-1 后的回滚门」 | `test -f docs/decisions/D-013.md`；`grep -q 'P-7.4-7' docs/decisions/D-013.md`；`grep -q 'box<String>' docs/decisions/D-013.md`；`grep -q 'P-7.4-6' docs/decisions/D-013.md`；`grep -Eq '签收[:：].*USER' docs/decisions/D-013.md`；`grep -q 'v0-PH-80' docs/decisions/D-013.md`；`git log --oneline -1 -- docs/decisions/D-013.md` 非空；`grep -rn 'P-7.4' docs/decisions/` 非空（当前为空，§8） |
| C-2 | 卡头/计划消歧：`docs/design/phase80.md:5-7` 与 `docs/planning/pointer-free-phase-plan.md:27,32` 引用 D-013；删除「P-7.4 全量未补…不落实现代码」与「S5a 入口 = P-7.3」并存的矛盾。**不改** `tasks`、`E80-*`、`version-minor` | `grep -q 'D-013' docs/design/phase80.md`；`grep -q 'D-013' docs/planning/pointer-free-phase-plan.md`；`! git diff --unified=0 6665f01a..HEAD -- docs/design/phase80.md \| grep -qE '^[-+]\| (S5a-\|S5b-\|E80-)\|version-minor'` 退出 0；`bash tools/check.sh g8` 退出 0；`python3 test/docs/check-docs.py` 退出 0 |

### 4.2 证据（S5a-1 红证前）

| ID | 条件 | 机械验收 |
| --- | --- | --- |
| C-3 | `.data` 类型裁定：`const char *` + lint，或保留只读 `Str` 视图；两种选项各配 `printf("%s", s.data)` 负例；决定最迟在 S5a-1 红证提交前入库（写进 D-013 或另立的 D-014） | `grep -rn '\.data' docs/decisions/D-01*.md` 非空；`grep -q 'printf("%s", s.data)' test/ast/p80_cstr.sh`；`sh test/ast/p80_cstr.sh <ct-ast>` 输出该负例 `ok` 且无 `FAIL`；`git merge-base --is-ancestor <decision-sha> <s5a1-red-sha>` 为真 |
| C-4 | P-7.3 在 HEAD 重放 16/16（S5a-0，不计交付）：在 `/tmp` 副本应用 `p73-rebased-5736f0d5.patch`（三处冲突人工解决），跑 `bash test/p73/run.sh` | 证据文件 `docs/planning/j6-evidence/p73/replay-6665f01a.md`：`grep -q '^baseline: 6665f01a'`、`grep -q 'summary: 16 passed, 0 failed'`、含命令、原始输出、退出码；`git merge-base --is-ancestor 6665f01a HEAD` 为真；出现任一正例失败即停 |
| C-5 | P-7.4 的 -2/-3/-4/-5/-7（去 `box<String>`）五项隔离原型证据，落在 `docs/planning/j6-evidence/p74/`：`coexist.md`（-2）、`migration.md`（-3）、`map_str.md`（-4）、`api_matrix.md`（-5）、`asan.md`（-7 去 box）。每份含 `baseline:`、命令、原始输出、退出码；**主仓不落 `selfhost/**`/`lib/std/**` 实现改动** | 五文件存在；`grep -rL '^baseline: ' docs/planning/j6-evidence/p74/*.md` 为空；`grep -rn 'TBD' docs/planning/j6-evidence/p74/` 为空；`bash docs/planning/j6-evidence/p74/run.sh` 退出 0（脚本自建 `/tmp` 副本）；`git diff --name-only 6665f01a..HEAD -- selfhost lib/std examples` 为空 |
| C-6 | 复制/retain 合同：三选一（拷贝硬错 / 浅拷贝 + 显式 retain / 自动 retain），写进 D-013 或另立的 D-014/D-015；并补 E80 未覆盖的 retain 判据——**不新增任务**，折进 S5a-1 的 `p80_layout` | `grep -rn 'retain' docs/decisions/D-01*.md` 非空；`test/ast/p80_layout.sh` 含参数/返回/字段 refcount 轨迹（`grep -c retain test/ast/p80_layout.sh` ≥ 1）；`sh test/ast/p80_layout.sh <ct-ast>` 的 retain 用例全 `ok`；红/绿两态各跑一次，红态含 `refs=` 轨迹 |

### 4.3 S5a 开工后的回滚门（S5a-1 后可做）

| ID | 条件 | 机械验收 |
| --- | --- | --- |
| C-7 | S5a 回滚演练：S5a-1 落地后 `git revert` 该提交，`check-all` 仍绿，旧 `Str` golden/ABI 不变；S5a-2 开工前完成 | 证据 `docs/planning/j6-evidence/p74/rollback.md`；命令含 `git revert`；`bash selfhost/check-all.sh` 输出 `check-all: OK (11 hard gates green)`；`git diff <revert>..<base> -- lib/std/Str.h.ct` 为空；`git diff --stat <s5a1>..<revert> -- test/ast` 为空 |
| C-8 | 顺序门：D-013 入库且 C-2…C-6 全过后 S5a-1 才可开工；C-7 过、S5a-1 收口后 S5a-2 才可开工；S5a-4 收口后 S5b 仍等 P-7.4-6；PH-81/82 仍串行 | `git log --oneline -1 -- docs/decisions/D-013.md` 非空；C-2 的 `check-docs` 绿；C-3…C-6 的证据文件均在库；S5a-1 开工时 `git tag --list v0.80.0` 为空（收口前不得打 tag）；C-7 的 `rollback.md` 在 S5a-2 前入库 |

### 4.4 现在允许（不落实现代码）

| 工作 | 允许 | 判据 |
| --- | --- | --- |
| P-7.4 隔离原型证据（`/tmp` 副本） | 是 | 卡 L6「证据、设计与夹具」；主树 `git status` 不含 `selfhost/**`/`lib/std/**` 实现改动 |
| P-7.3 在 HEAD 重放 | 是 | C-4 |
| D-013 / `.data` / retain 合同起草 | 是 | C-1/C-3/C-6；未签字的草稿不算 |
| `test/ast/p80_*` 测试夹具（红） | 是 | 卡 L6 的「夹具」；T-7 的 `test(...) 红` 可先提；不落 `selfhost/**` 实现 |
| S5a-1…S5a-4 实现 | **否** | 本判决 B；C-1…C-6 未过 |
| S5b 删旧/迁移 | **否** | 本判决 B；P-7.4 全量 + S5a 收口 |
| PH-81 / PH-82 实现 | **否** | 本判决 B；串行入口 |

## 5 生效范围

- **PH-80**：S5a/S5b 全部不得落实现代码；允许的工作限 §4.4。`version-minor=80` 不动，不 bump，不打 tag。
- **PH-81**：不得开工；入口仍是 P-7.5 + PH-80 收口（[phase81.md:5-6](../../docs/design/phase81.md#L5-L6)）。
- **PH-82**：不得开工；入口仍是 PH-81 收口 + D-012 accepted + battle closed（[phase82.md:5-6](../../docs/design/phase82.md#L5-L6)），后两项已满足。
- **D-011**：本判决不改其原文；C-1 的 D-013 是对 §3.3 的追加裁定，不是 `superseded`。D-011 全文仍可读。
- **卡/计划/源码**：本判决不改 `docs/design/phase80.md`、`docs/planning/pointer-free-phase-plan.md`、`selfhost/**`、`lib/std/**`、`examples/**`。
- **范围外**：本判决不评价 PH-78/79 的已收口结论、不评价 P-7.1a/P-7.2 的证据质量、不评价 v1.0 排期。

## 6 失效条件

1. **D-013 入库且签收**：若 D-013 采纳 C-1 的拆分并以 `签收: USER` 入库，本判决 B 被该 decision 取代；
   S5a 仍须过 C-2…C-7，不能仅凭 D-013 开工。
2. **D-013 采纳 A′**：若 signer 明确把 -2/-3/-5/-7 定为 S5a 产物并放行 S5a，本判决被取代；
   但该 decision 必须同时改写 card L5-7/L56 与 plan L27/L32，否则仍是「同一张卡两种闸门」。
3. **卡面被签收修订**：若 EDITOR 签署 card 修订，把 L5-7 改成与 §1.1 一致并说明「P-7.4 是 S5b/收口门」，
   J-1/J-2 需按新卡重判；修订必须走 `g8-phase-freeze` 允许的范围（不改 tasks/E80/version-minor）。
4. **P-7.3 重放失败**：若 C-4 在 HEAD 上不能得到 16/16，则连「先补证据」的路径也受阻，本判决维持 B 且更严。
5. **用户裁决**：用户是最终权威；用户可直接裁定放宽，但须按项目规则留下 `deviation:` 或 decision（签字 + 日期）。

## 7 证据限制

- **本场缺 `question.md` 与 `verify.json`**：`python3 tools/check-battle.py phase80-gate-1` 输出
  `FAIL question.md missing`、`warn verify.json not written yet (required before verdict)`，exit 1（§8）。
  因此 §7.8 T0/T4 未满足，本场没有独立证据席；本判决的事实基础是 claim/counter 的原始输出 + 本席在 HEAD 上的只读重跑。
- **本文件的 `closed` 是判决状态，不是归档状态**：`battle.sh close` 需要 `question.md`/`verify.json`；
  在补齐前，`battle/phase80-gate-1/` 不能按 §7.8 T7 归档。
- **claim/counter 未入库**：`git status --porcelain` 显示 `?? battle/phase80-gate-1/`；
  本判决引用的是文件行号，不是提交 sha。
- **P-7.3 的 16/16 未经本席复跑**：本席只跑了 `git apply --check`（exit 1）与 `--3way`（3 冲突）；
  `test/p73/run.sh` 的 16/16 只来自 p73 报告与 claim/counter。C-4 因此是条件，不是已证事实。
- **未跑编译器/测试套件**：本判决没有构建 L0/L1/L2/ct-ast，也没有跑 `check-all`；
  对「S5a 会/不会变红」的判断来自卡面与证据文本，不是新实测。
- **锚点校验**：本判决引用的 `file:line` 由本席在 HEAD 上逐条读取；claim/counter 的行号与原文一致。
  但未由独立证据席逐条复现，故不声称「锚点全部机器校验通过」。
- **T-8 签收**：本判决由 EDITOR 席出具；按项目 0.7，battle 判决的默认签收是 REQ 或 REVIEW（不得自签），
  本文件的庭外签收待 REQ/REVIEW 补记，不影响判决的生效范围。

## 8 证据附录（裁判在本机重跑）

```console
$ git rev-parse HEAD
6665f01a9e53613add49dd24c64c13df7e44a0b4
$ git log -1 --oneline
6665f01a review: PH-79 复核（v0.79.2）

$ grep -n "P-7.5" docs/design/phase80.md; echo exit=$?
exit=1

$ grep -n "retain" docs/design/phase80.md; echo exit=$?
exit=1

$ grep -rn "P-7.4" docs/decisions/; echo exit=$?
exit=1

$ grep -c "^| E80-" docs/design/phase80.md
8

$ git apply --check docs/planning/j6-evidence/p73/p73-rebased-5736f0d5.patch; echo exit=$?
error: patch failed: selfhost/ct-ast/backend/emit/Emitter.h.ct:1398
error: selfhost/ct-ast/backend/emit/Emitter.h.ct: patch does not apply
error: patch failed: selfhost/ct-ast/frontend/parse/Expr.h.ct:306
error: selfhost/ct-ast/frontend/parse/Expr.h.ct: patch does not apply
error: patch failed: selfhost/ct-ast/frontend/parse/Stmt.h.ct:2288
error: selfhost/ct-ast/frontend/parse/Stmt.h.ct: patch does not apply
exit=1

$ git apply --check --3way docs/planning/j6-evidence/p73/p73-rebased-5736f0d5.patch; echo exit=$?
Applied patch to 'lib/std/Str.h.ct' cleanly.
Applied patch to 'selfhost/ct-ast/backend/emit/Emitter.h.ct' with conflicts.
Applied patch to 'selfhost/ct-ast/frontend/module/Module.h.ct' cleanly.
Applied patch to 'selfhost/ct-ast/frontend/parse/Expr.h.ct' with conflicts.
Applied patch to 'selfhost/ct-ast/frontend/parse/Parser.h.ct' cleanly.
Applied patch to 'selfhost/ct-ast/frontend/parse/Stmt.h.ct' with conflicts.
Applied patch to 'selfhost/ct-ast/frontend/type/TypeCheck.h.ct' cleanly.
Applied patch to 'selfhost/ct-ast/tool/driver/Driver.h.ct' cleanly.
exit=0

$ git apply --stat docs/planning/j6-evidence/p73/p73-rebased-5736f0d5.patch | tail -1
 8 files changed, 560 insertions(+), 111 deletions(-)

$ git diff --stat 5736f0d5..HEAD -- selfhost/ct-ast/frontend/parse selfhost/ct-ast/backend/emit | tail -1
 5 files changed, 1028 insertions(+), 16 deletions(-)

$ python3 tools/check-battle.py phase80-gate-1; echo exit=$?
check-battle: phase80-gate-1
  rounds: 1/3
  FAIL  question.md missing
  warn  verify.json not written yet (required before verdict)
  FAIL (1 errors, 1 warnings)
exit=1
```

补充：`head -4 battle/leak-guards-1/closed.md` 存在；
`sed -n '1,6p' docs/decisions/D-012.md` 含「状态：**accepted**」；
`grep -n 'CTC_VERSION "0.79.2"' selfhost/l0/ctc.c` 命中（版本未动）。
本判决未运行 `git apply` 的实际应用（只在 `--check`/`--check --3way` 层）；
`/tmp` 重放与 `check-all` 是 C-4/C-7 的验收动作，不是本判决已完成的动作。
