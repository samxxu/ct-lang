# battle/phase80-retain-scope-1 主张席（claim）

- 争点：PH-80 / SH-102 的字段 `release` 以「保守、无 UAF/SEGV、允许已登记泄漏」收口，还是以
  「D-013 §3 字面全满足（含循环重赋零泄漏）」收口。
- 本席主张：**A —— 接受保守字段 `release` 作为 PH-80 收口条件**；不实现完整数据流。
- 基线：HEAD `953c19e0`（v0.80.2 + 第三轮复核）；SH-102 `status: reopened`；卡与 roadmap 已写「完成」。
- 边界：只写本文件；不改源码、卡、issue、decision、roadmap。证据按主规范 §7.7 E1–E5；`/tmp` 里的
  原型是**可行性证据**，不是交付物，未提交。
- 若 `question.md` 使用不同判据编号，按本节标题语义对齐（同 `battle/phase80-gate-1` 先例）。

## 0 争点、基线与三条已定事实

| 项 | 值 |
| --- | --- |
| 争点 | PH-80 能否在「R6a 修好、R6b 以 issue 承接」处收口，而不是等完整字段数据流 |
| 基线 | HEAD `953c19e0`；`ct-ast v0.80.2`；SH-102 `reopened`（[issue:4](../../issues/selfhost/sh102-p80-auto-retain-not-implemented.md#L4)） |
| 主张席 | claim（A） |
| 反对席 | counter（B：D-013 §3 字面满足前不置 `verified` / 不承认收口） |
| 裁判 | EDITOR |
| 禁止触碰 | 源码、卡、issue、decision、roadmap、tests |

先定三条事实（各有 E1 证据，不在争点内）：

- **FACT-1（R6a 是 UB，不是“偶发”）**：`if` 体内未执行的字段赋值仍被静态标记为 known，后续重赋
  release 未初始化字段；HEAD 上编译期 `cond=0` 必现 ASan SEGV（E1-1）。运行期 `cond=(argc>100)`
  的同一程序可能因栈上的零值而“碰巧通过”（本席实测 exit=0），所以**不能靠跑一遍探针来证明安全**，
  只能靠发射规则的结构性保证。
- **FACT-2（R6b 是真实泄漏且随循环线性增长）**：`Holder h = {0}` 循环 3 次、每轮重赋，`final live=2`
  （E1-2）。不是“测试噪声”。
- **FACT-3（收口记录已存在，REV 又打回）**：卡头写「状态：完成」（[phase80:3](../../docs/design/phase80.md#L3)）、
  roadmap 写「✅ 完成（v0.80.2）」（[roadmap:93](../../docs/roadmap.md#L93)），而 SH-102 仍 `reopened`
  （[issue:4](../../issues/selfhost/sh102-p80-auto-retain-not-implemented.md#L4)）。本场要判的是
  **怎样让这条已写下的收口记录成立**，不是要不要开始收口。

## 1 主张 A

**一句话**：PH-80 的收口条件 = 在 §1.2 的触发集内，编译器发射的字段 `release` 只发生在
「本路径段已由编译器自己写入 owning 句柄」的字段上，由此 UAF/SEGV = 0；未被证明初始化的
分支 / 循环重赋允许泄漏，按「每次覆盖 1 个 buffer」计量并登记；合同收窄以 USER 签收的
新 decision 为准；不实现支配树、别名或跨函数数据流。

### 1.1 收口条件（C-A1…C-A5）

| ID | 条件 | 判据 |
| --- | --- | --- |
| C-A1 | **结构性无 UAF/SEGV**：字段 `release` 只在标记成立时发射；标记键含 owner，且只由同一 `(owner, base, field)` 的赋值建立；标记在控制流汇合、基址重绑、整结构体赋值、作用域结束时被丢弃；**箭头基址（`p->tag`）不发射自动 `release`**（旧值转泄漏，避免别名 UAF）；`goto` 与含 `String` / `U16String` 字段的结构体局部共存为硬错；取址逃逸的 tracked 基址降级为不跟踪（只泄漏）或硬错，二选一并在卡上写明 | 四个汇合形状（`N_BLOCK`（含 if / 循环体）、`foreach`、`switch case`、`do-while`）各 1 个 ASan 负例；`pointer rebind`、`h = other`、同名遮蔽、取址各 1 个；实测全绿 |
| C-A2 | **泄漏可计量、登记**：分支覆盖重赋 1 buffer/次；未证明初始化的循环重赋 N−1 buffer/N 次；已证明初始化的循环重赋 0 泄漏 | `field_branch_hit` / `field_loop0` / `field_loop_known` 三条轨迹钉死（E1-6）；卡 §7.9.7 写数字，不写“少量” |
| C-A3 | **合同限定**：新 decision（建议 `D-015`，编号入库时定）`target: v0-PH-80`、`signer: USER`、`date` 非空；把 D-013 §3「重新赋值：先 retain 右值，再 release 旧值」限定为「仅当 C-A1 的标记成立；否则不 release，登记为作者负责的泄漏」（这是发射规则层面的“支配”，**不要求**实现支配树 / 数据流）；D-013 原文不动，末尾按主规范 §7.12.1 追加注记指向新记录 | decision 入库；`grep` 到三项字段；D-013 原文无删除行 |
| C-A4 | **台账与文档**：SH-102 的处置段明确只覆盖 UAF/SEGV，REV 据此可置 `verified`；泄漏半部新立一条 issue（P2，REV/REQ 立案），带触发条件与去向；卡 §7.9.7 增 R6 条目、§7.9.1 补「控制流汇合」行；`language-spec.md:2918-2922` 的条件句同步 | 每条 issue 只有一个去向（G6）；卡/规范里不再出现无条件的「重新赋值 release 旧值」 |
| C-A5 | **测试**：`test/ast/p80_retain` 增分支未初始化、循环未初始化、已初始化循环、`switch case`、同名遮蔽、指针重绑 6 个夹具（ASan/UBSan 至少各 1 个负例）；红证 `baseline: 953c19e0`，实现提交随后转绿 | `p80_retain.sh` ≥ 24 项 ok；`check-ast` 1538/0；sanitizer 583 checks 全绿 |

### 1.2 触发集（承诺面）与承诺外

**承诺面**：基址是普通局部变量（结构体值）的直接字段赋值 / 重赋 `h.tag = expr`（`String` / `U16String` 字段同规则），含分支、循环、
`switch`、嵌套块、同名遮蔽与基址重绑（`h = other` 只保证**清除旧标记**，不替浅拷贝补 retain）。

**承诺外（不在“无 UAF”里，按卡 §7.9.7 作者负责，或硬错）**：

- 通过指针 / 别名写入（`p->tag = …`、`(&h)->tag = …`、跨函数写入、并发写）：C-A1 明确**不发射**
  `p->tag` 的自动 `release`，所以最坏是泄漏，不是 UAF；取址逃逸的 tracked 基址按硬错处理或降级为
  不跟踪；
- `a.b.tag`、下标字段、泛型实例 `T` 位置；
- 整结构体浅拷贝把别的对象的句柄搬进本对象时的所有权语义（`h = other` 只做标记清除，不 retain
  搬入的句柄；D-013 未管这种拷贝）；
- 嵌套结构体字面量、`foreach item`、`for` 初始化器里的句柄（卡 §7.9.7 已列）。

这不是新开的口子：卡 §0 的「非目标」已写「借用检查」（[phase80:21](../../docs/design/phase80.md#L21)），
指针别名本来就不在本 phase 的静态保证范围内。**区别在于：A 要求把这条边界写在卡上并逐项给
issue，而不是像 R6 那样漏在边界清单之外。**

### 1.3 本席不主张（防扩大解释）

- 不主张 D-013 §3 字面满足。A 的准确措辞是「**限定后的合同**满足」；字面版仍由 USER 决定。
- 不主张完整数据流、支配树、跨函数别名分析；不新增分析 pass、不改 `refs` 布局 / ABI、不 bump MINOR
  （同一缺陷返工，按 §6.7 V-3 不重复 `+1`）。
- 不主张用本判决关闭未列出的反例：触发集外每一条仍要落卡 §7.9.7 或新 issue，否则 G6 按「无结论关闭」。

### 1.4 与 B 的差别（只差在收口门槛）

| 维度 | A（本席） | B |
| --- | --- | --- |
| 收口门槛 | 触发集内 UAF/SEGV = 0；泄漏按 issue 承接 | D-013 §3 字面满足：R6a **与** R6b 均无 |
| 循环重赋 | 允许 N−1 泄漏，登记 | 必须 0 泄漏 |
| 实现 | 约 5 条局部发射规则（汇合丢弃 / owner 化键 / 重绑清除 / goto 硬错），~50–80 行 | 需字段级支配 / 别名数据流（新分析） |
| 周期 | 1 个 DEV 轮次（S） | 估不出边界（T-2 的 L/XL，须再拆） |
| 对 PH-81/82 | 解锁 PH-81 的入口之一（PH-80 收口；[plan:19](../../docs/planning/pointer-free-phase-plan.md#L19)） | 继续阻塞 |

## 2 E1 — 证据（可复制命令 + 原始输出）

环境：macOS arm64，`Apple clang version 21.0.0`，`CC=cc`；所有 `ct-ast` 均从 HEAD `953c19e0`
的 `git archive` 隔离构建，不使用工作树既有二进制。

### E1-0 构建

```console
$ rm -rf /tmp/p80b && mkdir -p /tmp/p80b/work/l2src /tmp/p80b/work/astsrc
$ cd /Users/samxx/dsh-ws/ct-lang && git archive HEAD | tar -x -C /tmp/p80b
$ cc -Wall -Wextra -std=c99 /tmp/p80b/selfhost/l0/ctc.c -o /tmp/p80b/work/ctc
$ /tmp/p80b/work/ctc /tmp/p80b/selfhost/l1/ctc.ct -o /tmp/p80b/work/l1.c
$ cc -Wall -Wextra -std=c99 /tmp/p80b/work/l1.c -o /tmp/p80b/work/l1
$ cd /tmp/p80b && /tmp/p80b/work/l1 build selfhost/l2/driver.ct -o /tmp/p80b/work/l2src
cc /tmp/p80b/work/l2src/core.c /tmp/p80b/work/l2src/driver.c -o a.out
$ cc -Wall -Wextra -std=c99 /tmp/p80b/work/l2src/*.c -o /tmp/p80b/work/l2
$ cd /tmp/p80b && /tmp/p80b/work/l2 build -I selfhost/ct-ast selfhost/ct-ast/main.ct -o /tmp/p80b/work/astsrc
cc -std=c99 /tmp/p80b/work/astsrc/*.c -o a.out
$ cc -Wall -Wextra -std=c99 /tmp/p80b/work/astsrc/*.c -o /tmp/p80b/work/ct-ast
$ /tmp/p80b/work/ct-ast -v
ct-ast v0.80.2
```

### E1-1 R6a：HEAD 上编译期 `cond=0` 必现 SEGV

复现源与复核报告 §12.3 相同（[verdict:934-1019](../../docs/reviews/2026-11-20-phase80-rev-verdict.md#L934-L1019)），只把运行期条件
改成编译期 `0`（源码见附录 B.1）：

```console
$ CT_STD_DIR=/tmp/p80b/lib/std /tmp/p80b/work/ct-ast --allow-c-boundary field_branch.ct -o field_branch.c
$ cc -std=c99 -fsanitize=address -g field_branch.c -o field_branch
$ ASAN_OPTIONS=detect_leaks=0 ./field_branch; echo exit=$?
exit=134
AddressSanitizer:DEADLYSIGNAL
=================================================================
==54050==ERROR: AddressSanitizer: SEGV on unknown address 0x00000001eaa8 (pc 0x0001006266d8 bp 0x00016f7dab70 sp 0x00016f7daaa0 T0)
==54050==The signal is caused by a READ memory access.
    #0 0x0001006266d8 in String_release field_branch.c:557
    #1 0x000100632830 in main field_branch.c:1813
    #2 0x000180a36050 in start+0x19f8 (dyld:arm64e.x1+0x30050)
==54050==Register values:
 x[0] = 0x000000016f7dabe0   x[1] = 0x000000016f7dac98   x[2] = 0x0000000000000000   x[3] = 0x000000016f7dabd0
 ...
 x[28] = 0x00000001009e4000     fp = 0x000000016f7dab70     lr = 0x0000000100632834     sp = 0x000000016f7daaa0
AddressSanitizer can not provide additional info.
SUMMARY: AddressSanitizer: SEGV field_branch.c:557 in String_release
==54050==ABORTING
```

> 原始输出的寄存器段中间 24 行在本文件以 `...` 略去，其余逐字；证据席重跑会得到同结构输出。
> PID / 地址每次运行不同，属正常。

生成的 C（同一份 `field_branch.c`，1808–1813 行）：

```c
struct Holder h;
int cond = 0;
if (cond) {
    { h.tag = Str_to_string(&lit); }
}
{ struct String __ct_sold51 = h.tag; h.tag = Str_to_string(&lit); String_release(&__ct_sold51); }
```

把 `cond` 改回运行期 `(argc > 100)` 后同一构建 **exit=0**（栈上恰为 0），说明该缺陷的不确定性
来自 UB，不是条件本身消失。这条同时是 E3-P1 的基线。

### E1-2 R6b：HEAD 上循环重赋泄漏

源码见附录 B.2（与复核报告 §12.3 逐字相同）。

```console
$ CT_STD_DIR=/tmp/p80b/lib/std /tmp/p80b/work/ct-ast --allow-c-boundary field_loop0.ct -o field_loop0.c
$ cc -std=c99 -fsanitize=address -g field_loop0.c -o field_loop0
$ ASAN_OPTIONS=detect_leaks=0 ./field_loop0; echo exit=$?
iter 0 refs=1 live=1
iter 1 refs=1 live=2
iter 2 refs=1 live=3
final live=2
exit=0
```

生成的循环体只有 `h.tag = Str_to_string(&lit);`，没有 `String_release(&__ct_sold…)`。3 次循环
泄漏 2 个 buffer；N 次循环泄漏 N−1 个，随迭代线性增长。

### E1-3 `switch case` 同类：HEAD 会 release 未初始化字段

源码见附录 B.3；编译命令同 E1-1。

```console
$ ./field_switch; echo exit=$?
after switch refs=1 live=1
final live=0
exit=0
```

生成的 `switch` 之后：

```c
{ struct String __ct_sold51 = h.tag; h.tag = Str_to_string(&lit); String_release(&__ct_sold51); }
```

`case 0` 是否执行是运行期的，但标记是静态的；这是 R6a 在 `switch` 上的同构，**未在复核报告与
卡 §7.9 中出现**。本次运行 `final live=0` 只说明那次栈上零值让 release 成了 no-op；上面的生成
C 才是缺陷证据。

### E1-4 `goto` 同类：HEAD 会 release 未初始化字段

源码见附录 B.4；编译命令同 E1-1。

```console
$ ./field_goto; echo exit=$?
after goto refs=1 live=1
exit=0
```

```c
if (c) {
    goto L;
}
{ h.tag = Str_to_string(&lit); }
L:
    ;
    { struct String __ct_sold51 = h.tag; h.tag = Str_to_string(&lit); String_release(&__ct_sold51); }
```

`goto` 跳过第一条赋值后，`L` 处仍释放未初始化的 `h.tag`。现有硬错只覆盖「local owning `String`」
（[Stmt.h.ct:3934-3936](../../selfhost/ct-ast/frontend/parse/StmtLoop.h.ct#L511-L513)），不覆盖字段。

### E1-5 原型：汇合丢弃标记（15+/5−，1 文件）→ R6a 转绿

在 `/tmp` 的隔离副本上只改 `Emitter.h.ct`：每个块入口记 `g_sb.nfield`，块关闭时截断回该值；
`foreach` / `case` / `do-while` 的手工块同样处理（完整 diff 见附录 A）。

```console
$ git diff --no-index --stat emitter.orig.ct Emitter.patched.ct
 work/{emitter.orig.ct => Emitter.patched.ct} | 20 +++++++++++++++-----
 1 file changed, 15 insertions(+), 5 deletions(-)

$ ct-ast2 -v
ct-ast v0.80.2
$ ASAN_OPTIONS=detect_leaks=0 ./field_branch       # 原型重编译
after branch refs=1 live=1
exit=0
$ ASAN_OPTIONS=detect_leaks=0 ./field_switch
after switch refs=1 live=2
final live=1
exit=0
$ CT_C_BOUNDARY=allow sh test/ast/p80_retain.sh ./ct-ast2 | grep -c '^ok'
18
$ CT_C_BOUNDARY=allow sh test/ast/p80_retain.sh ./ct-ast2 | tail -1
p80_retain: OK
$ bash selfhost/check-ast.sh 2>&1 | tail -2
  ok    p36 E36-4 (Option glue drops the payload field)
== summary: 1538 passed, 0 failed, 5 skipped ==
```

生成的 C 在 `if` 之后只剩 `{ h.tag = Str_to_string(&lit); }`，不再有 `__ct_sold`。即：**R6a 与
`switch` 同类被结构性消除，代价是泄漏**。`p80_retain` 18 项不回归。

### E1-6 泄漏面计量（同一原型）

```console
$ ./field_branch_hit        # cond=1：if 内先赋 A，if 外重赋 B，最后 release B
after refs=1 live=2
final live=1
exit=0

$ ./field_loop_known        # h.tag 在循环前直线赋值，循环内重赋
iter 0 refs=1 live=1
iter 1 refs=1 live=1
iter 2 refs=1 live=1
final live=0
exit=0

$ ./field_loop0             # h = {0} 但没有被标记（原因见 §5 隐藏成本），循环内首赋未证明
iter 0 refs=1 live=1
iter 1 refs=1 live=2
iter 2 refs=1 live=3
final live=2
exit=0
```

三条一起说明：**泄漏只发生在“本路径段没有支配初始化”的位置；已证明初始化的循环重赋不因保守
而多漏**。这把“少量泄漏”从形容词变成了可核对的数字。

## 3 E2 — 锚点（含至少一条不利于己方）

### 3.1 有利 A

- [Emitter.h.ct:962-975](../../selfhost/ct-ast/backend/emit/Emitter.h.ct#L962-L975)：`sb_field_mark()`
  只按 `<base>.<field>` 记账，不记控制流路径；这是 R6a/R6b 的共同根因。
- [Emitter.h.ct:643-647](../../selfhost/ct-ast/backend/emit/Emitter.h.ct#L643-L647)：`sb_field_known()`
  「找到即 known，否则 `owner < 0` 即 known」——没有“路径段”概念。
- [Emitter.h.ct:1104-1110](../../selfhost/ct-ast/backend/emit/Emitter.h.ct#L1104-L1110)：`release_old`
  由 `sb_field_known()` 直接决定，没有支配检查。
- [Emitter.h.ct:979-990](../../selfhost/ct-ast/backend/emit/Emitter.h.ct#L979-L990)：`sb_field_prune()`
  只在块关闭时按 **owner** 丢弃，不丢弃“本块内新增的标记”；四个调用点
  [:5176](../../selfhost/ct-ast/backend/emit/Emitter.h.ct#L5176)、[:5867](../../selfhost/ct-ast/backend/emit/Emitter.h.ct#L5867)、
  [:5922](../../selfhost/ct-ast/backend/emit/Emitter.h.ct#L5922)、[:5949](../../selfhost/ct-ast/backend/emit/Emitter.h.ct#L5949)
  都是同一形状。
- [Emitter.h.ct:617-638](../../selfhost/ct-ast/backend/emit/Emitter.h.ct#L617-L638)：`sb_field_find()`
  只按路径字符串匹配，**不比较 owner**，所以同名遮蔽会误配（本席另测到 `field_shadow`
  反例，§7 F3）。
- [test/ast/p80_retain/field_reassign.ct:1-26](../../test/ast/p80_retain/field_reassign.ct#L1-L26)：现有字段重赋
  夹具是纯直线代码，没有 `if` / 循环；这是 R6 漏网的直接原因。
- [docs/design/phase80.md:362-380](../../docs/design/phase80.md#L362-L380)：§7.9.7 的边界清单不含 R6；
  A 要求把它补进去，而不是继续用旧清单。

### 3.2 不利于 A（必须计入）

- **U1 合同是 USER 签收的无条件句**：[D-013.md:33](../../docs/decisions/D-013.md#L33)
  「重新赋值：先 retain 右值，再 release 旧值；」没有“仅当已初始化”的限定。A 要成立，必须先拿到
  USER 对限定版的签字（C-A3）；battle 判决本身不能替 USER 改合同。
- **U2 上一轮 REV 已明确拒绝“已登记边界”作为收口依据**：
  [verdict:977](../../docs/reviews/2026-11-20-phase80-rev-verdict.md#L977)「这正是 SH-102『未赋过值的
  字段不 release』声明的反例；也违反 D-013 §3」；
  [verdict:1018-1020](../../docs/reviews/2026-11-20-phase80-rev-verdict.md#L1018-L1020)「这不是卡 §7.9
  明列的边界……而是 D-013 §3『字段赋值 / 重新赋值』的字面反例」；
  [verdict:1032-1039](../../docs/reviews/2026-11-20-phase80-rev-verdict.md#L1032-L1039) 因而仍写
  「SH-102 保持 `reopened`，不置 `verified`」。A 的“补进 §7.9”与 REV 拒绝的动作**形式上相同**；
  A 只能靠“USER 签收的合同限定 + 结构性无 UAF + 泄漏另行立案”三点与之区分（§6）。
- **U3 仓内已经发布过无条件说法**：[language-spec.md:2920](../../docs/language-spec.md#470-string--strutf-8-owning-与借用phase-80仅-ct-ast)
  「重新赋值先 `retain` 右值再 `release` 旧值」已随 v0.80.1/0.80.2 发出；R6 证明该句在控制流下为假。
  A 要求同步这句；B 可以据此说 A 是在“把已发出的文档改成能收口的样子”。
- **U4 承诺面确实变窄**：A 的“无 UAF”不含别名 / 指针写 / 跨函数写（§1.2）。而这些位置在 C 边界
  完全可达；若裁判要求“任何 D-013 §3 字段赋值都无 UAF”，A 不成立，必须走 B 的数据流或硬错路线。
- **U5 收口记录先于判决存在**：卡与 roadmap 已写「完成」
  （[phase80:3](../../docs/design/phase80.md#L3)、[roadmap:93](../../docs/roadmap.md#L93)），SH-102 却
  `reopened`。A 的提案在外观上像“事后追认”；程序上必须先由 REV 重新给 SH-102 一个去向，才能谈
  收口是否成立。

## 4 E3 — 可证伪预测

| ID | 预测（若 A 成立） | 验证方式 | 现状 |
| --- | --- | --- | --- |
| P1 | HEAD 上 `field_branch`（`cond=0`）exit=134 ASan SEGV；应用附录 A 补丁后 exit=0，且生成的 C 在 `if` 后无 `__ct_sold` | 重跑 E1-1 / E1-5 | **已观测**：134 → 0 |
| P2 | 补丁后 `p80_retain.sh` 仍 18/18 ok | E1-5 | **已观测**：18 / `p80_retain: OK` |
| P3 | 补丁后 `field_loop0` 仍 `final live=2`（A 接受泄漏；若全数据流实现，应为 `final live=0`） | E1-2 / E1-6 | **已观测**：`live=2` |
| P4 | 补丁后 `field_loop_known`（循环前有支配赋值）`final live=0` | E1-6 | **已观测**：`live=0` |
| P5 | 把 goto 硬错扩到「含 `String` 字段的结构体局部 + `goto`」后，`field_goto.ct` 必须以 `a goto cannot cross an owning String scope…` 拒绝（exit≠0） | `ct-ast field_goto.ct` | **未实现**；若仍接受，A 的 C-A1 不完整 |
| P6 | 应用完整 C-A1（含 owner 化键、基址重绑清除、整结构体赋值清除、箭头基址关闭/取址降级）后，`field_shadow` 不再 SEGV，`field_ptr` 转为不 `release`（泄漏）或硬错 | 两个 ASan 夹具 | **未实现**；只有汇合补丁时仍 SEGV（§7 F3） |
| P7 | 汇合补丁后，现有 `check-ast` 全绿（1538 passed / 0 failed）；完整 C-A1 + 新夹具后仍须全绿 | `bash selfhost/check-ast.sh` | **部分已观测**：附录 A 补丁 + 现有夹具 → `1538 passed, 0 failed, 5 skipped`；新夹具与其余四条规则未加 |

**关键区分预测**：同一 `field_loop0`，A 给 `live=2`、B 给 `live=0`。若 B 的实现也只能给 2，则 B 的
“零泄漏”要求在这条探针上没有增量，A 的收口门槛更便宜。

## 5 E4 — 代价

| 项 | 实测 / 估计 | 说明 |
| --- | --- | --- |
| 汇合丢弃标记（原型已实测） | 1 文件，+15/−5（`Emitter.h.ct`） | 其中 4 行是未读取的 `nfield0` 槽位；最小形态约 +11/−5 |
| owner 化字段键 | +10/−5（估） | `sb_field_find` 增加 owner 比较；`sb_field_mark` / `sb_field_known` 同步 |
| 基址重绑 / 整结构体赋值清除 | +15（估） | 新增 `sb_field_forget(base)`；在 `sb_var` 赋值路径调用 |
| 箭头基址关闭 / 取址降级 | +10（估） | `N_ARROW` 不进 `release_old`；`&h` 逃逸时降级不跟踪（或硬错，二选一） |
| `goto` 硬错扩展 | +15（估） | `Stmt.h.ct` 加一个 `f_field_local` 标记 + `func_end` 条件（[Stmt.h.ct:4368-4374](../../selfhost/ct-ast/frontend/parse/StmtSwitch.h.ct#L474-L480) 处增判） |
| 夹具 | 5–7 文件，+120（估） | `test/ast/p80_retain/{field_branch,field_loop,field_loop_known,field_switch,field_shadow,field_ptr}.ct` + `expected.*.out` + 脚本行 |
| 文档 / 台账 | 5 文件，+60/−10（估） | 卡 §7.9 / §7.9.1、`language-spec.md`、新 issue、新 decision、D-013 注记 |
| **合计** | **约 12 文件，+245/−20；1 个 DEV 轮次（S）** | 不改 ABI、不改 `refs` 布局、不 bump MINOR、不打 tag |
| 门禁 | `p80_retain`（≥24）、`check-ast`（1538）、`sanitizer`（583 checks）、`check-docs`、G0/G6/G8 | 红证 baseline `953c19e0`；`test(...) 红` 提交为父提交（T-7） |
| 回退 | `git revert` 实现提交 + 夹具提交；旧探针仍指向 HEAD 基线 | 单文件核心改动，回退面小 |

**与 B 的代价对比**：B 要“循环重赋零泄漏”，只能走字段级支配 + 别名分析（或对 `goto` / 指针写
全面硬错）。这不是 1 个 S 任务：它要新增分析、改 `StrRetain` 记账、覆盖 `foreach` / `for` 初始化器 /
嵌套字面量 / 泛型 `T`，且仍要解决别名；按 T-2 属 L/XL，必须先拆。A 的 ~245 行里没有一行是分析 pass。

**A 的隐藏成本（如实写）**：泄漏按循环迭代线性增长；长驻程序可能持续涨。缓解只能靠 (a) 作者显式
`release()`（卡 §7.9.4 已要求）、(b) 后续把「聚合零初始化」也标成 known（E1-6 的 `field_loop0` 会转
`live=0`；本席试过一版补丁，因 `sb_mark_aggregate` 只读 `N_RAW`、读不到 `N_INIT_BRACE`
（[Emitter.h.ct:608-613](../../selfhost/ct-ast/backend/emit/Emitter.h.ct#L608-L613)、[:995-1018](../../selfhost/ct-ast/backend/emit/Emitter.h.ct#L995-L1018)）
而未生效，故不作为 A 的收口条件）。**不要把“少量”读成“有界”**。

## 6 E5 — 对 B 最强论点的 steelman 与回应

**B 最强论点（原文）**：

1. [D-013.md:33](../../docs/decisions/D-013.md#L33)：「重新赋值：先 retain 右值，再 release 旧值；」——
   USER 2026-11-20 签收的 C-6 合同，无「已初始化」限定。
2. [verdict:1018-1020](../../docs/reviews/2026-11-20-phase80-rev-verdict.md#L1018-L1020)：「这不是卡
   §7.9 明列的边界……而是 D-013 §3『字段赋值 / 重新赋值』的字面反例。」
3. [verdict:1032-1039](../../docs/reviews/2026-11-20-phase80-rev-verdict.md#L1032-L1039)：「因此第三轮
   仍不能写 `REV: 通过`；SH-102 保持 `reopened`，不置 `verified`。」

合起来：**REV 已经判过“把未覆盖位置写进边界清单”不构成收口依据；A 现在做的是同一动作换个名字。**

**A 的回应（不回避）**：

- **承认相同点**：形式上确实是“把 R6 补进 §7.9”。A 不否认这一点；A 的区分不在文字，在三个可核对
  的附加物：① USER 签收的**合同限定**（C-A3），而不是作者单方注释；② **结构性**消除 UAF/SEGV
  （C-A1 的发射规则 + 6 个 ASan 负例），而不是“本轮没复现”；③ 泄漏**独立立案**、带触发条件与
  去向（C-A4），而不是留在卡里当形容词。
- **指出 B 的不可执行处**：B 要求“字面满足”，但字面句在未初始化字段上**本身不安全**——
  无条件 release 旧值正是 R6a 的 SEGV 来源（E1-1）。要同时满足字面句与安全，B 必须做支配/别名
  数据流；这是新分析，不是修 bug。B 若拒绝数据流，B 自己的方案也不成立。
- **代价不对称**：A 用 ~245 行换“触发集内 UAF=0 + 可计量泄漏”；B 用 L/XL 的分析换“泄漏=0”，
  且仍要对指针别名 / 跨函数写入设边界。两者都要设边界，A 的边界更早、更便宜、已实测。
- **程序上的让步**：A 不要求 EDITOR 在判决里替 USER 改合同；A 只要求判决确认“这个收口条件在技术上
  足以消除 UAF/SEGV，且泄漏已可计量”，然后把合同限定交 USER 签。若 USER 不签，A 自动退回 B 的
  未收口状态（§7 F1）。

## 7 不利己方与失效条件

| ID | 条件 | 后果 |
| --- | --- | --- |
| F1 | USER 拒绝签 C-A3 的合同限定 | A 不成立；SH-102 保持 `reopened`，PH-80 收回「完成」 |
| F2 | 任一触发集内程序在完整 C-A1 后仍出现 ASan UAF/SEGV（不依赖 UB 巧合） | A 不成立；转 B 或扩大硬错面 |
| F3 | **本席已实测的未覆盖洞**：`p = &b` 重绑后 `p->tag` 仍按旧标记 release 未初始化字段（`field_ptr`）；同名遮蔽 `Holder h` 内层重赋会误配外层标记（`field_shadow`，原型上实测 SEGV）。完整 C-A1 的 owner 化键 + 重绑清除 + 箭头基址关闭/取址降级必须覆盖它们；只做汇合补丁（附录 A）**不够** | 若 C-A1 不包含这几条，A 的“无 UAF”为假；本席不把附录 A 当作完整实现 |
| F4 | 触发集外的别名 / 跨函数写入被裁判计入“D-013 §3 字段赋值” | A 的承诺面不够，必须转 B 或增设硬错 |
| F5 | 泄漏被 USER 视为发布阻断（而不是可登记的 P2） | A 的 C-A2 不成立；A 无法收口 |
| F6 | 卡 / roadmap 的既有「完成」记录未先由 REV 重新处置 | 收口程序不成立；A 不要求跳过 REV |

**本席主动承认的最不利事实**：D-013 §3 是 USER 签收的无条件句，而 A 的核心动作是把它改成有条件句。
无论技术证据多强，这一步都不能由本席或裁判代替 USER；A 的全部价值在于把“改什么、为什么安全、
代价多少”写成可签的形态，而不是宣称合同已经被满足。

## 8 边界与未做

- 本文件只写主张；未改源码、卡、issue、decision、roadmap、tests；`/tmp/p80b*` 的补丁与探针
  是隔离副本，未提交。
- E1 的 `ct-ast` 全部来自 HEAD `953c19e0` 的 `git archive` 独立构建；不引用工作树既有二进制。
- 已跑的完整门禁：在 `/tmp/p80b`（附录 A 的汇合补丁 + 现有夹具，未加新夹具）上
  `bash selfhost/check-ast.sh` 的 stdout 尾部为 `== summary: 1538 passed, 0 failed, 5 skipped ==`
  （管道只保留尾部，故不引用管道退出码；判据是 `0 failed`）。新夹具与 C-A1 其余四条未包含在这 1538 项里。
- `field_switch` / `field_goto` 的 SEGV 与栈布局有关，E1-3 / E1-4 只证明“发射了未初始化 release”，
  不证明每次必崩。
- 若 `question.md` 的判据编号与本文件不同，按 §1.1 的 C-A 编号对齐；C-A 是收口条件，不是新增门禁。
- 本席不使用卡 §7.9 已有边界（`foreach item` / `for` 初始化器 / 嵌套字面量 / 泛型 `T` / 字段无 Drop）
  作为打回或收口理由；A 只处理 R6 及其同构的**直接字段赋值**。

## 附录 A — 汇合丢弃标记原型（候选实现，未提交）

基线 `Emitter.h.ct` 来自 HEAD `953c19e0`；只在 `/tmp` 副本改动。核心思想：块入口记字段标记数，
块关闭截断回该值——控制流汇合点不携带本段新增的“已知”状态。

```diff
--- work/emitter.orig.ct	2026-11-20 23:55:04
+++ work/Emitter.patched.ct	2026-11-20 23:54:53
@@ -265,6 +265,7 @@
        are known to hold an owning handle, so a later assignment releases the
        old value. Only straight-line member / arrow targets are tracked. */
     int  nfield;
+    int  nfield0[256];  /* field-mark count at each block entry (conservative join) */
     char fpath[128][160];
     int  fowner[128];   /* binding index of the base local; -1 = global */
     int  ln;
@@ -5145,8 +5146,9 @@
             return self->emit_node(self->arena->nodes[n].a, ind);
         if (self->arena->nodes[n].kind == N_DEFER) return 0;
         if (self->arena->nodes[n].kind == N_BLOCK) {
-            int save_nclvar, save_sb, save_l, funcbody;
-            save_nclvar = self->nclvar;   /* a closure bound here dies with the block */
+            int save_nclvar, save_sb, save_l, funcbody, save_nf;
+            save_nclvar = self->nclvar;
+            save_nf = g_sb.nfield;   /* a closure bound here dies with the block */
             funcbody = g_sb.pending;
             g_sb.pending = 0;
             /* a function body's closing brace ends the parameters' lives too */
@@ -5160,6 +5162,7 @@
                     g_sb.blk[g_sb.nblk] = save_sb;
                     g_sb.lblk[g_sb.nblk] = save_l;
                     g_sb.bkind[g_sb.nblk] = bk;
+                    g_sb.nfield0[g_sb.nblk] = save_nf;
                     g_sb.nblk++;
                 }
             }
@@ -5174,6 +5177,7 @@
             g_sb.n = save_sb;
             g_sb.ln = save_l;
             sb_field_prune(self, save_l);
+            g_sb.nfield = save_nf;
             self->nclvar = save_nclvar;
             self->emit_indent(ind);
             fputs("}\n", self->out);
@@ -5851,11 +5855,12 @@
                continue baseline is pushed (and released) here. `item` is not a
                tracked binding: for a `Vec` / `Map` it is a borrowed view. */
             {
-                int sbase = g_sb.n, lbase = g_sb.ln;
+                int sbase = g_sb.n, lbase = g_sb.ln, fbase = g_sb.nfield;
                 if (g_sb.nblk < 256) {
                     g_sb.blk[g_sb.nblk] = sbase;
                     g_sb.lblk[g_sb.nblk] = lbase;
                     g_sb.bkind[g_sb.nblk] = 1;
+                    g_sb.nfield0[g_sb.nblk] = fbase;
                     g_sb.nblk++;
                 }
                 for (c = self->arena->nodes[self->arena->nodes[n].d].a; c >= 0;
@@ -5865,6 +5870,7 @@
                 g_sb.n = sbase;
                 g_sb.ln = lbase;
                 sb_field_prune(self, lbase);
+                g_sb.nfield = fbase;
                 if (g_sb.nblk > 0) g_sb.nblk--;
             }
             self->emit_indent(ind + 1);
@@ -5907,11 +5913,12 @@
             /* SH-102: a case body has no N_BLOCK of its own; a `break` here must
                not release the enclosing scope's handles. */
             {
-                int sbase = g_sb.n, lbase = g_sb.ln;
+                int sbase = g_sb.n, lbase = g_sb.ln, fbase = g_sb.nfield;
                 if (g_sb.nblk < 256) {
                     g_sb.blk[g_sb.nblk] = sbase;
                     g_sb.lblk[g_sb.nblk] = lbase;
                     g_sb.bkind[g_sb.nblk] = 0;
+                    g_sb.nfield0[g_sb.nblk] = fbase;
                     g_sb.nblk++;
                 }
                 for (c = self->arena->nodes[n].a; c >= 0; c = self->arena->nodes[c].next)
@@ -5920,6 +5927,7 @@
                 g_sb.n = sbase;
                 g_sb.ln = lbase;
                 sb_field_prune(self, lbase);
+                g_sb.nfield = fbase;
                 if (g_sb.nblk > 0) g_sb.nblk--;
             }
             return 0;
@@ -5934,11 +5942,12 @@
                `emit_node`, which would put the closing brace on its own line */
             b = self->arena->nodes[n].b;
             {
-                int sbase = g_sb.n, lbase = g_sb.ln;
+                int sbase = g_sb.n, lbase = g_sb.ln, fbase = g_sb.nfield;
                 if (g_sb.nblk < 256) {
                     g_sb.blk[g_sb.nblk] = sbase;
                     g_sb.lblk[g_sb.nblk] = lbase;
                     g_sb.bkind[g_sb.nblk] = 1;
+                    g_sb.nfield0[g_sb.nblk] = fbase;
                     g_sb.nblk++;
                 }
                 for (c = self->arena->nodes[b].a; c >= 0; c = self->arena->nodes[c].next)
@@ -5947,6 +5956,7 @@
                 g_sb.n = sbase;
                 g_sb.ln = lbase;
                 sb_field_prune(self, lbase);
+                g_sb.nfield = fbase;
                 if (g_sb.nblk > 0) g_sb.nblk--;
             }
             self->emit_indent(ind);
```

说明：

- `g_sb.nfield0[]` 只写不读（可直接删除）；保留它是为了说明“块栈本来就有位置记这个数”。
- 该原型**只**实现 C-A1 的第 1 条（汇合丢弃）。owner 化键、基址重绑清除、整结构体赋值清除、
  `goto` 硬错是 C-A1 的其余四条，未包含在附录 A 里（因此 F3 的反例仍可击穿它）。
- 原型不改变 `refs` 布局 / 16 字节句柄 / 8 字节头，不改生成的 C ABI；`p80_retain` 18/18 不回归
  （E1-5）。

## 附录 B — 探针源码（与 E1 输出一一对应）

> 全部在 `/tmp/p80b/probes` 一次性生成，未入库；`CT_STD_DIR=/tmp/p80b/lib/std`，
> 统一 `ct-ast --allow-c-boundary <name>.ct -o <name>.c && cc -std=c99 -fsanitize=address -g …`。

### B.1 `field_branch.ct`（E1-1；R6a）

```ct
#include <stdio.h>
struct Holder { String tag; }
int main(int argc, char **argv)
{
    Str lit = "abc";
    Holder h;
    int cond = 0;
    if (cond) {
        h.tag = lit.to_string();
    }
    h.tag = lit.to_string();
    printf("after branch refs=%d live=%d\n", h.tag.refs(), ct_str_live_count());
    h.tag.release();
    return 0;
}
```

### B.2 `field_loop0.ct`（E1-2；R6b，与复核报告 §12.3 逐字相同）

```ct
#include <stdio.h>
struct Holder { String tag; }
int main(void)
{
    Str lit = "abc";
    Holder h = { 0 };
    int i;
    for (i = 0; i < 3; i++) {
        h.tag = lit.to_string();
        printf("iter %d refs=%d live=%d\n", i, h.tag.refs(), ct_str_live_count());
    }
    h.tag.release();
    printf("final live=%d\n", ct_str_live_count());
    return 0;
}
```

### B.3 `field_switch.ct`（E1-3）

```ct
#include <stdio.h>
struct Holder { String tag; }
int main(void)
{
    Str lit = "abc";
    Holder h;
    int c = 0;
    switch (c) {
    case 0:
        h.tag = lit.to_string();
        break;
    default:
        break;
    }
    h.tag = lit.to_string();
    printf("after switch refs=%d live=%d\n", h.tag.refs(), ct_str_live_count());
    h.tag.release();
    printf("final live=%d\n", ct_str_live_count());
    return 0;
}
```

### B.4 `field_goto.ct`（E1-4）

```ct
#include <stdio.h>
struct Holder { String tag; }
int main(int argc, char **argv)
{
    Str lit = "abc";
    Holder h;
    int c = (argc > 100);
    if (c) { goto L; }
    h.tag = lit.to_string();
L:
    h.tag = lit.to_string();
    printf("after goto refs=%d live=%d\n", h.tag.refs(), ct_str_live_count());
    h.tag.release();
    return 0;
}
```

### B.5 `field_ptr.ct` / `field_shadow.ct`（F3 的两个反例）

```ct
/* field_ptr.ct: 基址重绑后仍按旧标记 release 未初始化字段 */
#include <stdio.h>
struct Holder { String tag; }
int main(void)
{
    Str lit = "abc";
    Holder a;
    Holder b;
    Holder *p = &a;
    p->tag = lit.to_string();
    p = &b;
    p->tag = lit.to_string();
    printf("after refs=%d live=%d\n", p->tag.refs(), ct_str_live_count());
    p->tag.release();
    return 0;
}
```

```ct
/* field_shadow.ct: 内层同名 h 继承了外层 h.tag 的标记 */
#include <stdio.h>
struct Holder { String tag; }
int main(void)
{
    Str lit = "abc";
    Holder h;
    h.tag = lit.to_string();
    {
        Holder h;
        h.tag = lit.to_string();
        printf("inner refs=%d live=%d\n", h.tag.refs(), ct_str_live_count());
        h.tag.release();
    }
    printf("outer refs=%d live=%d\n", h.tag.refs(), ct_str_live_count());
    h.tag.release();
    return 0;
}
```

`field_ptr` / `field_shadow` 在 HEAD 与附录 A 原型上都会生成 `__ct_sold = p->tag` / `__ct_sold = h.tag`
（未初始化读），是否 SEGV 取决于栈布局；这正是 A 要求 C-A1 必须包含 owner 化键、重绑清除、箭头基址
关闭/取址降级的原因。

