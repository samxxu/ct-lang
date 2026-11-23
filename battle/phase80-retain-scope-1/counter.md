# battle/phase80-retain-scope-1 反对席（counter）

- 争点：PH-80 / SH-102 的字段 `release` 能否以「保守、无 UAF/SEGV、允许已登记泄漏」（主张 A）收口，
  还是必须先做到 **D-013 §3 的字段赋值 / 重赋在数据流上精确**（本席 B）——分支未初始化不得
  `release`，循环内重赋必须 `release` 旧值。
- 本席主张：**B**。R6a（分支未初始化 release → ASan 致命信号）与 R6b（循环重赋 → 泄漏随迭代线性
  增长）都必须在发射规则里结构性消除，或由**硬错**承接；在此之前 SH-102 不得置 `verified`，
  PH-80 的「完成」不得签字，卡 §7.9.1 / roadmap / `language-spec` 的「已修复」主张必须先撤回或改写。
- 基线：HEAD `953c19e0`（v0.80.2 + 第三轮复核，2026-11-20）；SH-102 `status: reopened`；
  卡头「状态：完成」；roadmap「✅ 完成（v0.80.2，SH-102 修复）」。
- 边界：只写本文件；不改源码、卡、issue、decision、roadmap、tests。`/tmp/p80c` 的原型与探针是
  **可行性证据**，不是交付物，未提交。
- 若 `question.md` 使用不同判据编号，按本节 §1 的 B-1…B-5 对齐（同 `battle/phase80-gate-1` 先例）。

## 0 反证清单：主张 A 的失效条件

本席不反对 A 的**安全半部**（A 的 C-A1 在触发集内确实能消除 R6a 式的 UAF/SEGV）；本席反对 A 把
R6b 的**零泄漏**降级为「可登记的泄漏」。下列条件任一成立，A 的收口条件即不成立。

| ID | A 的失效条件 | 可核验方式 | 若成立 |
| --- | --- | --- | --- |
| FA-1 | 「重新赋值先 `retain` 右值再 `release` 旧值」在字段位置**已经**是 v0.80.2 的已交付行为（DEV 自述与卡 §7.9.1 都这样写），只是控制流下不精确；A 把它改成「仅直线代码、其余登记泄漏」是**回退已交付行为**，不是「收窄未实现承诺」 | [issue:318-321](../../issues/selfhost/sh102-p80-auto-retain-not-implemented.md#L318-L321)、[phase80:394](../../docs/design/phase80.md#L394) 与 A 的 `field_loop0` `live=2`（[claim.md:262-268](claim.md#L262-L268)）对照 | A 的 C-A2「泄漏可计量」是**新增回退**，不是既有边界的保留；A 必须写成「撤回 R2 的一半」，不能写成「沿用 §7.9 边界」 |
| FA-2 | A 的 C-A3 要求一份 **USER 签收**的新 decision 把 D-013 §3 限定为「仅当标记成立」；HEAD 上不存在这份记录 | `grep -rn "D-013" docs/decisions/` 只有 D-013 本身；`grep -rn "字段.*release\|重新赋值" docs/decisions/` | 没有签字，A 的收口条件按 A 自己的 C-A3 就不成立；EDITOR 不能替 USER 签 |
| FA-3 | A 的 C-A4 只写「卡 §7.9.7 / language-spec 同步」，没有覆盖卡头「状态：完成」与 roadmap「✅ 完成（v0.80.2，SH-102 修复）」这两处已发布主张 | [phase80:3](../../docs/design/phase80.md#L3)、[roadmap:93](../../docs/roadmap.md#L93)；A 的 C-A4 原文（[claim.md:49](claim.md#L49)） | 即使 USER 签了窄合同，A 的收口记录仍与 SH-102 `reopened` / 泄漏 issue 并存；G6「无结论关闭」仍红 |
| FA-4 | A 认为 B 需要「字段级支配 / 别名数据流（新分析）」所以是 L/XL、必须再拆（[claim.md:84](claim.md#L84)、[claim.md:349-351](claim.md#L349-L351)） | 本席原型：1 文件 `+59/−7`，无新分析 pass，R6a 与 R6b 同时转绿（E1-5）；`p80_retain` 18/18、`check-ast` 1538/0/5 | A 的「代价不对称」论据崩塌；B 的代价与 A 同阶（见 §5） |
| FA-5 | A 用「运行期探针 exit=0」证明 R6a 不危险 | HEAD 上同一 shape：编译期 `cond=0` → exit=134（E1-1）；运行期 `argc>100` → exit=0（E1-2）；REV 同一运行期 shape → exit=134（[verdict:956-963](../../docs/reviews/2026-11-20-phase80-rev-verdict.md#L956-L963)） | 单次探针通过不构成证据；A 的 FACT-1 已经承认这一点，A 的 C-A1 必须继续按结构性保证举证 |
| FA-6 | 卡/roadmap 的「完成 / SH-102 修复」可以在 SH-102 仍 `reopened` 时成立 | [phase80:3](../../docs/design/phase80.md#L3)、[roadmap:93](../../docs/roadmap.md#L93) 与 [issue:4](../../issues/selfhost/sh102-p80-auto-retain-not-implemented.md#L4) | 收口记录与 5.4 / 6.6 G6 冲突：一个 P1 仍 `reopened` 却写「修复完成」，属「无结论关闭」 |
| FA-7 | A 说「字面句本身不安全，所以 B 必须做数据流」 | 本席路线不删 `release`、不删 `retain`，而是让**存储先定义**（零初始化 / 聚合初始化），于是「先 retain 再 release 旧值」的字面句在任何控制流下都安全（E1-5 生成 C） | 「字面 vs 安全」不是二选一：A 的隐含前提（未初始化存储无法避免）被证伪 |

## 1 B 的主张与收口判据（B-1…B-5）

### 1.1 一句话

**让「字段赋值 / 重赋」在发射规则上做到：①任何 `release` 只作用于已定义的存储；②同一存储位置的
重赋一定 `release` 旧值（零泄漏）；③无法满足 ①/② 的形状一律硬错或专项立案。** ①不靠支配树：
用「定义即零值」把存储变成总是已定义；②不靠循环分析：既有 `sb_field_known → release_old` 机制在
声明处标记后自然生效（本席原型实测 `field_loop0 final live=0`）。

### 1.2 判据

| ID | 条件 | 判据（可核对） |
| --- | --- | --- |
| B-1 | **R6a 结构性消除**：字段 `release` 只出现在存储已定义的位置；分支未执行时旧值是零句柄（release 为 no-op），分支执行时旧值是该分支写入的句柄 | `field_branch0`（编译期 `cond=0`）exit=0；`field_branch_rt` exit=0；生成 C 里 `Holder h;` 必须落成 `= { 0 }`，`if` 体内/后的赋值都带 `__ct_sold`（E1-5）；不得依赖栈布局 |
| B-2 | **R6b 零泄漏**：同一存储位置的循环重赋每轮 `release` 旧值，`final live=0` | `field_loop0`（`Holder h = {0}`）与 `field_loop_bare`（`Holder h;`）都是 `final live=0`；`field_loop_pre`（循环前直线赋值）保持 `final live=0`（E1-3/E1-4/E1-5） |
| B-3 | **边界闭合**：无法做到 ①/② 的形状必须**硬错**或**专项 issue**，不得静默泄漏，更不得 UAF | 整结构体赋值（`h = other`）与 `goto` 跳过结构化局部：硬错（本席原型已暴露这两个洞，E1-6/E1-7，未实现硬错）；`p->tag` / 别名写：不自动 `release`（安全优先，旧值泄漏登记），但右值为 place 时仍 retain；`foreach item`、`for` 初始化器、嵌套字面量、泛型 `T`、字段无 Drop 沿用卡 §7.9 既有边界并逐项有去向 |
| B-4 | **记录一致**：SH-102 的处置段不得再写「D-013 §3 已满足」；REV 只能在 B-1/B-2 通过后置 `verified`；卡 §7.9.1 的「重新赋值先 retain 再 release 旧值」一行与 `language-spec.md:2918-2922` 必须改成与实现一致的表述；roadmap 的「SH-102 修复」在 `verified` 前撤回 | `grep -n "重新赋值" docs/design/phase80.md docs/language-spec.md` 的措辞与 E80 轨迹一致；G6 每个 issue 只有一个去向；G8 版本与 phase 号一致 |
| B-5 | **不回归**：不改 `refs` 布局 / 16 字节句柄 / 8 字节头 / ABI；既有夹具与 sanitizer 全绿；新增 6 个字段控制流夹具 | `p80_retain` ≥24 项 ok（当前 18）；`check-ast` 1538/0；sanitizer 583 checks；`p80_layout` 的 `gap param_refs=2` 不变 |

### 1.3 本席不主张（防扩大解释）

- 不主张「任何字段赋值零泄漏」：字段/全局无自动 Drop（卡 §7.9.4）不变；循环体里**新建**的结构体
  局部（`for (...) { Holder h = {0}; h.tag = …; }`）仍按 §7.9.4 由作者 `release`，B 不为它新增
  scope Drop（本席实测该形状 HEAD 与原型都是 `final live=3`，E1-9）。
- 不主张 `p->tag` / `(&h).tag` / 跨函数写 / 并发写零泄漏；A 的 C-A1 在这类位置「不发射 release」
  本席接受，理由见 E1-8（安全优先），但**整结构体拷贝**必须另有硬错或 retain，因为它不是别名写，
  而是直接复制 owning 句柄。
- 不主张本轮实现完整数据流 / 支配树 / 跨函数分析；B 的路线是**定义性不变量**，不是新分析 pass。
- 不主张用本判决直接关闭 §7.9 既有边界；每条仍要卡 §7.9.7 或 issue。

### 1.4 与 A 的差别（只差在「循环重赋」与「记录口径」）

| 维度 | A（claim） | B（本席） |
| --- | --- | --- |
| R6a | 汇合丢弃标记：不 release，分支命中时泄漏 1 buffer | 声明处定义存储：`release` 为零 no-op 或正确旧值；无 UAF、无泄漏 |
| R6b | 允许 N−1 泄漏，登记（`field_loop0 live=2`） | 必须 `live=0`（原型已实测） |
| 实现 | 约 12 文件 / +245（含文档夹具），5 条发射规则 | 约 11 文件 / +280（含文档夹具）；核心 1 文件 `+59/−7`，外加 2 条硬错（整拷贝 / goto） |
| 合同 | 需 USER 签新 decision 把 D-013 §3 改成有条件句；D-013 原文加注记 | 不要求改 D-013 §3 原文；要求实现让字面句为真；**也要**一条决定（零初始化语义，见 §7 F2） |
| 对 PH-81/82 | 解锁 | 同样解锁；周期同为 1 个 DEV 轮次（估） |

## 2 E1 — 证据（可复制命令 + 原始输出）

环境：macOS 27.2.1 arm64，`Apple clang version 21.0.0 (clang-2100.4.1.1)`，`CC=cc`；所有 `ct-ast`
均从 HEAD `953c19e0` 的 `git archive` 隔离构建；原型只在 `/tmp/p80c` 的副本里改动，未提交。

### E1-0 构建与基线

```console
$ rm -rf /tmp/p80c && mkdir -p /tmp/p80c/work/l2src /tmp/p80c/work/astsrc /tmp/p80c/probes
$ cd /Users/samxx/dsh-ws/ct-lang && git archive HEAD | tar -x -C /tmp/p80c
$ cc -Wall -Wextra -std=c99 /tmp/p80c/selfhost/l0/ctc.c -o /tmp/p80c/work/ctc
$ /tmp/p80c/work/ctc /tmp/p80c/selfhost/l1/ctc.ct -o /tmp/p80c/work/l1.c
$ cc -Wall -Wextra -std=c99 /tmp/p80c/work/l1.c -o /tmp/p80c/work/l1
$ cd /tmp/p80c && /tmp/p80c/work/l1 build selfhost/l2/driver.ct -o /tmp/p80c/work/l2src
$ cc -Wall -Wextra -std=c99 /tmp/p80c/work/l2src/*.c -o /tmp/p80c/work/l2
$ /tmp/p80c/work/l2 build -I selfhost/ct-ast selfhost/ct-ast/main.ct -o /tmp/p80c/work/astsrc
$ cc -Wall -Wextra -std=c99 /tmp/p80c/work/astsrc/*.c -o /tmp/p80c/work/ct-ast
$ /tmp/p80c/work/ct-ast -v
ct-ast v0.80.2
```

每一步退出码 0；`l2`/`astsrc` 构建时各自打印一行 `cc … -o a.out`（与 `claim.md` 的 E1-0 同形，
此处略去）。探针统一用
`CT_STD_DIR=/tmp/p80c/lib/std <ct-ast> --allow-c-boundary <name>.ct -o <name>.c` 生成，再
`cc -std=c99 -fsanitize=address -g <name>.c -o <name>`，运行加 `ASAN_OPTIONS=detect_leaks=0`
（否则退出时的进程级泄漏报告会掩盖信号；泄漏看 `ct_str_live_count()`）。

### E1-1 R6a：编译期 `cond=0` 必现致命信号（HEAD）

源码见附录 B.1（`field_branch0.ct`）。

```console
$ CT_STD_DIR=/tmp/p80c/lib/std /tmp/p80c/work/ct-ast --allow-c-boundary field_branch0.ct -o field_branch0.c
$ cc -std=c99 -fsanitize=address -g field_branch0.c -o field_branch0
$ ASAN_OPTIONS=detect_leaks=0 ./field_branch0; echo exit=$?
exit=134
AddressSanitizer:DEADLYSIGNAL
=================================================================
==74166==ERROR: AddressSanitizer: BUS on unknown address (pc 0x0001046aa7b4 bp 0x00016b756b70 sp 0x00016b756aa0 T0)
==74166==The signal is caused by a WRITE memory access.
==74166==Hint: this fault was caused by a dereference of a high value address (see register values below).  Disassemble the provided pc to learn which register was used.
    #0 0x0001046aa7b4 in String_release field_branch0.c:560
    #1 0x0001046b6828 in main field_branch0.c:1813
    #2 0x000180a36050 in start+0x19f8 (dyld:arm64e.x1+0x30050)
==74166==Register values:
 x[0] = 0x000000016b756be0   x[1] = 0x000000016b756c88   x[2] = 0x0000000000000000   x[3] = 0x000000016b756bd0
 ...（x[4]…x[28] 共 7 行原样略去，见 E1-1 复跑）
SUMMARY: AddressSanitizer: BUS field_branch0.c:560 in String_release
==74166==ABORTING
```

> REV 报告的形态是 SEGV（[verdict:957-963](../../docs/reviews/2026-11-20-phase80-rev-verdict.md#L957-L963)），
> 本席这台机器上是 BUS；两者都是「`String_release` 读/写未初始化句柄」的同一缺陷，信号名随栈内容
> 与平台变化。PID / 地址每次运行不同，属正常。

生成的 C（同一份；主函数 1806–1817 行，其中 1813 行正是 REV 报告的那一行）：

```c
int main(void) {
    struct Str lit = ((struct Str){ (char *)"abc", (int)(sizeof("abc") - 1) });
    struct Holder h;
    int cond = 0;
    if (cond) {
        { h.tag = Str_to_string(&lit); }
    }
    { struct String __ct_sold51 = h.tag; h.tag = Str_to_string(&lit); String_release(&__ct_sold51); }
    printf("after branch refs=%d live=%d\n", String_refs(&h.tag), ct_str_live_count());
    String_release(&h.tag);
    return 0;
}
```

`if` 体内未执行的赋值被静态记为「字段已赋值」，随后那次赋值**无条件**读旧值再 `release`。根因是
发射器的字段记账是词法/静态的：`sb_field_mark()` 不区分控制流（[Emitter.h.ct:962-975](../../selfhost/ct-ast/backend/emit/Emitter.h.ct#L962-L975)），
`release_old` 由 `sb_field_known()` 直接决定（[Emitter.h.ct:1104-1110](../../selfhost/ct-ast/backend/emit/Emitter.h.ct#L1104-L1110)），
四个 `sb_field_prune()` 调用点只按 **owner** 丢弃（[:5176](../../selfhost/ct-ast/backend/emit/Emitter.h.ct#L5176)、
[:5867](../../selfhost/ct-ast/backend/emit/Emitter.h.ct#L5867)、[:5922](../../selfhost/ct-ast/backend/emit/Emitter.h.ct#L5922)、
[:5949](../../selfhost/ct-ast/backend/emit/Emitter.h.ct#L5949)），不丢弃「本块内新增的标记」。

### E1-2 R6a 运行期：同一 shape 这次 exit=0

```console
$ ASAN_OPTIONS=detect_leaks=0 ./field_branch_rt; echo exit=$?
after branch refs=1 live=1
exit=0
```

`field_branch_rt.ct` 与 `field_branch0.ct` 唯一的差别是 `int cond = (argc > 100);`。同一个缺陷在
本机这次「碰巧通过」（栈上恰为 0），而 REV 的同一运行期 shape 曾 `exit=134`
（[verdict:956-963](../../docs/reviews/2026-11-20-phase80-rev-verdict.md#L956-L963)）。这条证据的作用
是**否定「跑一遍探针」这种举证方式**，不是证明安全：只要旧值来自未初始化栈，通过与否取决于栈布局。

### E1-3 R6b：循环内重赋不 release（HEAD）

```console
$ ASAN_OPTIONS=detect_leaks=0 ./field_loop0; echo exit=$?
iter 0 refs=1 live=1
iter 1 refs=1 live=2
iter 2 refs=1 live=3
final live=2
exit=0

$ ASAN_OPTIONS=detect_leaks=0 ./field_loop_bare; echo exit=$?
iter 0 refs=1 live=1
iter 1 refs=1 live=2
iter 2 refs=1 live=3
final live=2
exit=0
```

生成的循环体（`field_loop0.c:1811`）：

```c
for (i = 0; i < 3; i++) {
    h.tag = Str_to_string(&lit);
    printf("iter %d refs=%d live=%d\n", i, String_refs(&h.tag), ct_str_live_count());
}
```

`h = { 0 }` 的零初始化**没有被记账**：`sb_decl()` 对带聚合初始化器的普通局部在
[Emitter.h.ct:1037-1041](../../selfhost/ct-ast/backend/emit/Emitter.h.ct#L1037-L1041) 直接 `return 0`，
既不 `sb_lpush()` 登记绑定，也不标记任何字段；`sb_mark_aggregate()` 又只读
`N_RAW` 文本（[Emitter.h.ct:995-1020](../../selfhost/ct-ast/backend/emit/Emitter.h.ct#L995-L1020)），
读不到 `N_INIT_BRACE`。于是循环体在发射时看不到 known，永远不发射旧值 `release`。`field_loop0` 与
`field_loop_bare`（裸声明）都给 `final live=2`，与 REV §12.3 逐字一致。

### E1-4 `field_loop_pre`：机制已经存在，只缺声明处定义

```console
$ ASAN_OPTIONS=detect_leaks=0 ./field_loop_pre; echo exit=$?
iter 0 refs=1 live=1
iter 1 refs=1 live=1
iter 2 refs=1 live=1
final live=0
exit=0
```

`field_loop_pre.ct` 在循环**前**有直线赋值 `h.tag = lit.to_string();`。此时 `h.tag` 已被标记 known，
循环体那一句就自然发射 `release`，每轮 `live=1`、循环后 `final live=0`。**这说明循环重赋的发射路径
本来就在，缺的是「声明 / 聚合初始化也算已定义」这一步**；A 把它描述成「需要字段级支配 / 新分析」
（[claim.md:349-351](claim.md#L349-L351)）与实测不符。

### E1-5 原型：定义存储 + 既有 release 路径（`+59/−7`，1 文件）→ R6a 与 R6b 同时转绿

在 `/tmp/p80c` 的隔离副本上只改 `Emitter.h.ct`（完整 diff 见附录 A，`patch -p1` 已验证可重放，
产物与本席工作副本逐字节一致）：

1. 普通局部若是「含非数组 `String`/`U16String` 字段的结构体」，在 `sb_decl()` 里**先登记绑定**，
   再按初始化器分派：裸声明 → 由通用声明发射器补 `= { 0 }`；`{ … }` / 裸聚合文本 → C 会零填充
   省略成员，直接按字段类型标记全部 owning 字段为 known；
2. 字段 `release` 的判据从 `N_MEMBER || N_ARROW` 收窄为 `N_MEMBER`（箭头/别名写不自动 release，
   避免 `p = &b` 重绑后释放未初始化字段；右值为 place 时仍 `retain`）。

```console
$ git diff --no-index --stat selfhost/ct-ast/backend/emit/Emitter.orig.ct selfhost/ct-ast/backend/emit/Emitter.h.ct
 selfhost/ct-ast/backend/emit/{Emitter.orig.ct => Emitter.h.ct} | 66 +++++++++++++++++++---
 1 file changed, 59 insertions(+), 7 deletions(-)
```

R6a / R6b 同一组探针，原型重编译后：

```console
$ ./field_branch0; echo exit=$?          # 编译期 cond=0；HEAD 是 134
after branch refs=1 live=1
exit=0

$ ./field_branch_rt; echo exit=$?        # 运行期 argc>100
after branch refs=1 live=1
exit=0

$ ./field_loop0; echo exit=$?            # HEAD final live=2
iter 0 refs=1 live=1
iter 1 refs=1 live=1
iter 2 refs=1 live=1
final live=0
exit=0

$ ./field_loop_bare; echo exit=$?        # HEAD final live=2
iter 0 refs=1 live=1
iter 1 refs=1 live=1
iter 2 refs=1 live=1
final live=0
exit=0

$ ./field_loop_pre; echo exit=$?         # 不回归
iter 0 refs=1 live=1
iter 1 refs=1 live=1
iter 2 refs=1 live=1
final live=0
exit=0
```

原型生成的关键 C（`field_branch0.b.c` / `field_loop0.b.c`）：

```c
struct Holder h = { 0 };
int cond = 0;
if (cond) {
    { struct String __ct_sold51 = h.tag; h.tag = Str_to_string(&lit); String_release(&__ct_sold51); }
}
{ struct String __ct_sold52 = h.tag; h.tag = Str_to_string(&lit); String_release(&__ct_sold52); }
```

```c
struct Holder h = { 0 };
for (i = 0; i < 3; i++) {
    { struct String __ct_sold51 = h.tag; h.tag = Str_to_string(&lit); String_release(&__ct_sold51); }
    printf("iter %d refs=%d live=%d\n", i, String_refs(&h.tag), ct_str_live_count());
}
```

门禁（同一份原型源码）：

```console
$ CT_C_BOUNDARY=allow sh test/ast/p80_retain.sh /tmp/p80c/work/ct-ast2 | tail -1
p80_retain: OK          # 18 行 ok = 5 组正例 × trace/ASan/UBSan + 3 个负例
$ bash selfhost/check-ast.sh 2>&1 | tail -1
== summary: 1538 passed, 0 failed, 5 skipped ==
```

**结论**：B 的判据 B-1 与 B-2 在这条路线上**可同时满足**，且不是新分析 pass：`+59/−7`、1 文件、
现有 1538 夹具不回归。A 的「B 需要 L/XL 新分析」与「B 的实现也只能给 `live=2`」两条都被实测否定。

### E1-6 原型自曝的洞 1：整结构体赋值（`h = other`）

B 的路线让 `h = other` 之后的 `h.tag = …` 释放「从 other 浅拷贝来的句柄」，这是原型**引入**的 UAF
（HEAD 因 `h = {0}` 未登记而只是不释放 / 共享句柄）：

```console
$ ASAN_OPTIONS=detect_leaks=0 ./field_copy; echo exit=$?     # HEAD
other refs=1 live=2
final live=0
exit=0

$ ASAN_OPTIONS=detect_leaks=0 ./field_copy.b; echo exit=$?   # 原型
exit=134
=================================================================
ERROR: AddressSanitizer: heap-use-after-free on address 0x602000000970
READ of size 4 at 0x602000000970 thread T0
    #0 String_refs field_copy.b.c:524
    #1 main field_copy.b.c:1813
freed by thread T0 here:
    #1 String_release field_copy.b.c:563
    #2 main field_copy.b.c:1812
```

生成的 C：

```c
struct Holder other = { 0 };
{ struct String __ct_sold51 = other.tag; other.tag = Str_to_string(&lit); String_release(&__ct_sold51); }
struct Holder h = { 0 };
h = other;
{ struct String __ct_sold52 = h.tag; h.tag = Str_to_string(&lit); String_release(&__ct_sold52); }
```

B-3 要求：整结构体赋值给含 owning 字段的局部，必须**硬错**（推荐，与 goto 同类）或**逐字段
retain + 释放旧字段**；不能静默浅拷贝后让字段释放。原型未实现，代价计入 §5。

### E1-7 原型自曝的洞 2：`goto` 跳过结构化局部的零初始化

现有 `goto` 硬错只覆盖「local owning `String`」（[Stmt.h.ct:3931-3936](../../selfhost/ct-ast/frontend/parse/Stmt.h.ct#L3931-L3936)、
[:4368-4374](../../selfhost/ct-ast/frontend/parse/Stmt.h.ct#L4368-L4374)），不覆盖「含 owning 字段的
结构体局部」。原型把裸 `Holder h;` 改成 `= { 0 }` 后，`goto` 跳过这条初始化就会让字段处于未定义：

```console
$ ARGS=$(seq 1 101)   # argc>100，触发 goto
$ ASAN_OPTIONS=detect_leaks=0 ./field_goto_struct $ARGS; echo exit=$?     # HEAD
exit=0
$ ASAN_OPTIONS=detect_leaks=0 ./field_goto_struct.b $ARGS; echo exit=$?   # 原型
exit=134
==93375==ERROR: AddressSanitizer: stack-buffer-overflow on address 0x00016ba7e7b8 ...
    #0 String_release field_goto_struct.b.c:558
```

生成的 C（原型）在 `if (c) goto L;` 之后写 `struct Holder h = { 0 };`，`L:` 在声明之后，C 允许
跳过初始化进入作用域，于是 `h.tag` 是未定义值。B-3 要求把 `f_string_local` 扩展到「含 owning
字段的结构体局部」，或把零初始化改成不可能被跳过的方式。原型未实现，代价计入 §5。

### E1-8 箭头 / 别名写：不自动 release，泄漏但安全

```console
$ ASAN_OPTIONS=detect_leaks=0 ./field_ptr; echo exit=$?    # HEAD
after refs=1 live=2
exit=0
$ ASAN_OPTIONS=detect_leaks=0 ./field_ptr.b; echo exit=$?  # 原型
after refs=1 live=2
exit=0
```

两条都泄漏 1 个旧 buffer（`p = &a; p->tag = …; p = &b; p->tag = …` 覆盖时旧值不释放），但都不再
可能释放未初始化字段。B 接受这一**安全优先**的边界（与 A 的 C-A1 一致），把它登记为触发条件明确的
作者负责位置，不列为 R6 阻断项。

### E1-9 B 没有改动 §7.9.4 的字段无 Drop 边界

```console
$ ASAN_OPTIONS=detect_leaks=0 ./field_loop_local; echo exit=$?    # HEAD
iter 0 refs=1 live=1
iter 1 refs=1 live=2
iter 2 refs=1 live=3
final live=3
exit=0
$ ASAN_OPTIONS=detect_leaks=0 ./field_loop_local.b; echo exit=$?  # 原型
iter 0 refs=1 live=1
iter 1 refs=1 live=2
iter 2 refs=1 live=3
final live=3
exit=0
```

`for (...) { Holder h = {0}; h.tag = …; }` 每轮新建对象、作用域结束不释放字段，HEAD 与原型都
`final live=3`。这是卡 §7.9.4「字段/全局 `String` 无自动 Drop」的既有边界，**不是 R6b**：R6b 是
「同一存储位置的覆盖」。B 不把 scope Drop 混进本轮判据；但它确实是 B 的 `live=0` 主张的边界，
列入 §7 不利项。

### E1-10 其他形状未见回归（原型）

`field_shadow`（同名遮蔽）、`field_switch`（`case` 内赋值）、`field_multidecl`（`Holder a, b;`）
在原型上均 exit=0、活计数与 HEAD 相同；`field_multidecl` 的原型生成 C 给每个声明符补
`= { 0 }` 并各自释放旧值：

```console
$ ./field_multidecl.b; echo exit=$?     # 原型
a=1 b=1 live=2
final live=0
exit=0
```

## 3 E2 — 锚点（含至少一条不利于己方）

### 3.1 有利 B

- **合同原文**：[D-013.md:33](../../docs/decisions/D-013.md#L33)「重新赋值：先 retain 右值，再
  release 旧值；」——USER 2026-11-20 签收，**没有**「仅当已初始化 / 仅直线代码」的限定。
- **issue 仍 reopened**：[issue:4](../../issues/selfhost/sh102-p80-auto-retain-not-implemented.md#L4)、
  R6a [issue:380-417](../../issues/selfhost/sh102-p80-auto-retain-not-implemented.md#L380-L417)、
  R6b [issue:419-440](../../issues/selfhost/sh102-p80-auto-retain-not-implemented.md#L419-L440)、
  第三轮结论 [issue:442-446](../../issues/selfhost/sh102-p80-auto-retain-not-implemented.md#L442-L446)。
- **REV 第三轮**：[verdict:934-1020](../../docs/reviews/2026-11-20-phase80-rev-verdict.md#L934-L1020)
  给出同样的两个反例，[verdict:1032-1039](../../docs/reviews/2026-11-20-phase80-rev-verdict.md#L1032-L1039)
  明确「不置 `verified`」。
- **DEV 自述已把字段重赋 release 当成交付行为**：
  [issue:318-321](../../issues/selfhost/sh102-p80-auto-retain-not-implemented.md#L318-L321)
  「新增 `<base>.<field>` 记账……直线代码里赋过值的字段在下次赋值时 hold 旧值、retain / 移动新值、
  再 release 旧值」；卡 §7.9.1 也把「重新赋值」写成已实现
  （[phase80:394](../../docs/design/phase80.md#L394)）。**A 的「泄漏可登记」是撤回这条已交付行为**，
  不是「保留未实现承诺」。
- **发布文档的无条件句**：[language-spec.md:2918-2922](../../docs/language-spec.md#470-string--strutf-8-owning-与借用phase-80仅-ct-ast)
  「重新赋值先 retain 右值再 release 旧值」已随 v0.80.1/v0.80.2 发出；R6b 证明该句在循环下为假。
- **收口记录**：卡头「状态：完成」[phase80:3](../../docs/design/phase80.md#L3)、roadmap
  「✅ 完成（v0.80.2，SH-102 修复）」[roadmap:93](../../docs/roadmap.md#L93)，与 SH-102
  `reopened` 并存。
- **根因锚点**：静态标记 [Emitter.h.ct:962-975](../../selfhost/ct-ast/backend/emit/Emitter.h.ct#L962-L975)；
  `sb_field_known()` 只查路径字符串不看控制流
  [:643-647](../../selfhost/ct-ast/backend/emit/Emitter.h.ct#L643-L647)；`release_old`
  [:1104-1110](../../selfhost/ct-ast/backend/emit/Emitter.h.ct#L1104-L1110)；
  聚合初始化被 `sb_decl()` 提前返回
  [:1037-1041](../../selfhost/ct-ast/backend/emit/Emitter.h.ct#L1037-L1041)；
  `sb_mark_aggregate()` 只读 `N_RAW`
  [:995-1020](../../selfhost/ct-ast/backend/emit/Emitter.h.ct#L995-L1020)；
  裸结构体局部无 `= {0}`（通用声明器的零初始化只覆盖 `String` 与 vptr 类型）
  [:6086-6097](../../selfhost/ct-ast/backend/emit/Emitter.h.ct#L6086-L6097)。

### 3.2 不利于 B（本席主动列出，不回避）

1. **A 的安全半部确实便宜且已被实测**：A 的汇合丢弃原型 `+15/−5` 就让 R6a 转绿、`p80_retain`
   18/18（[claim.md:216-245](claim.md#L216-L245)）。B 的独立增量主要在 R6b；若裁判把 R6a 当作
   SH-102 的唯一阻断项，A 与 B 在这一半上同价，B 的「必须数据流精确」就只剩循环那一条。
2. **D-013 §3 是否覆盖「字段重赋」本身是有争议的合同解释**：DEV 在 v0.80.1 的处置段明确写过窄
   解释——「D-013 的第一条只要求『字段赋值 retain』，把『先 retain 再 release 旧值』限定在变量
   重新赋值，避免对未初始化字段 release」
   （[issue:189-195](../../issues/selfhost/sh102-p80-auto-retain-not-implemented.md#L189-L195)）。
   REV 后来按字面驳回（[verdict:1018-1020](../../docs/reviews/2026-11-20-phase80-rev-verdict.md#L1018-L1020)），
   但那是复核意见，不是 USER 改合同。**B 的 B-2 依赖字面读法，而字面读法尚未由 USER/EDITOR 裁定。**
3. **B 的原型改动了未初始化结构体局部的可观察语义**：`Holder h;` 现在是 `= { 0 }`，读未赋值字段
   会得到空串而不是未定义值。这在 C 术语里是安全化，但它是**语言语义变化**，D-013 没有授权；
   若 USER 拒绝，B 只能退到「硬错」路线（见 §7 F2），代价上升、覆盖面变窄。
4. **B 的原型当前对 `h = other` 与 `goto` 是回归**（E1-6/E1-7 实测 UAF/越界），必须补两条硬错
   或逐字段 retain；在补齐之前，B 的原型**不能**直接当交付物，B 的 `+59/−7` 只是核心机制的成本，
   不是完整修复的成本。**这一点上 A 反而更完整**：A 的 C-A1 已列「整结构体赋值清除标记」
   （[claim.md:46](claim.md#L46)），B 应复用该规则或改硬错，不能把「A 没管整拷贝」当作 A 的失败。
5. **E80-1…8 没有 retain/D-013 判据**（[phase80:89-96](../../docs/design/phase80.md#L89-L96)）：
   严格按卡面退出判据，PH-80 的「完成」并不依赖 D-013 §3；B 的「PH-80 不得收口」主要依赖
   卡 §7.9.1 的已交付声明 + roadmap 的「SH-102 修复」+ SH-102 的 `reopened`，而不是 E80 条目。
   这是 B 的程序弱点（§7 F6）。
6. **卡 §7.9.4 的「字段/全局无自动 Drop」是既有边界**：B 的零泄漏主张只覆盖「同一存储位置的
   重赋」，不覆盖循环内新建结构体的最后一次赋值（E1-9 两种实现都 `live=3`）；把两者混读会
   高估 B 的覆盖面。

## 4 E3 — 可证伪预测

| ID | 若 B 成立，应观察到 | 一次性核验 | 现状 |
| --- | --- | --- | --- |
| P1 | HEAD 上编译期 `cond=0` 的分支探针 exit=134；B 的实现后 exit=0 | 重跑 E1-1 / E1-5 | **已观测**：134 → 0 |
| P2 | HEAD 上 `field_loop0` / `field_loop_bare` `final live=2`；A 的汇合补丁后仍 `live=2`；B 的实现后 `live=0` | E1-3 + [claim.md:262-268](claim.md#L262-L268) + E1-5 | **已观测**：HEAD 2 → A 2（A 自测）→ B 0 |
| P3 | B 的实现不回归 `field_loop_pre`（`live=0`）、`p80_retain` 18/18、`check-ast` 1538/0/5 | E1-4 / E1-5 | **已观测**：全部保持 |
| P4 | B 的实现若不做整结构体赋值 / goto 硬错，`field_copy` / `field_goto_struct`（101 args）必现 UAF / 越界 | E1-6 / E1-7 | **已观测**（原型确实红）：补齐后应 exit=0 或明确硬错 |
| P5 | 循环内新建结构体（`for { Holder h = {0}; h.tag = …; }`）在 HEAD 与 B 的实现下都 `final live=3` | E1-9 | **已观测**：3 / 3；B 不为该形状背书 |
| P6 | 若 D-013 §3 确实不覆盖「字段重赋」，应存在一份 `signer` + `date` 的 decision 写明该限定 | `grep -rn "重新赋值\|字段.*release" docs/decisions/`；当前只有 D-013 §3 原文 | **未观测到**；出现则该记录取代 B-2 的合同依据 |
| P7 | 若 USER 拒绝零初始化语义，B 的可行退路是把「未定义存储上的字段 release」做成硬错；此时 `field_branch0` 应以诊断拒绝（exit≠0），而不是编译成 C | 以 `Holder h;` + 分支/循环字段赋值的负例夹具验证 | **未实现**；这是 B 在 F2 下的最小可执行回退 |

**关键区分预测**（对 A 的 `claim.md:331-332` 的反向检验）：A 说「若 B 的实现也只能给 2，则 B 的
零泄漏要求在 field_loop0 上没有增量」。实测 B 的原型给 `final live=0`，该条件不成立；因此「B 更贵
且无增量」不能作为拒绝 B 的理由。

## 5 E4 — 代价（三项：文件数/行数、影响门禁、回退步骤）

| 项 | 实测 / 估计 | 说明 |
| --- | --- | --- |
| 核心发射规则（原型已实测） | 1 文件 `+59/−7`（`Emitter.h.ct`） | 定义存储（裸/聚合声明）+ 登记绑定 + 箭头不自动 release；无新分析 pass |
| 整结构体赋值硬错（B-3） | +8～+25（估） | 硬错最省；若选逐字段 retain 则 +25 左右 |
| `goto` 硬错扩展到 owning 字段结构体（B-3） | +12（估） | `Stmt.h.ct` 的 `f_string_local` 条件扩展 + 负例 |
| 夹具 | 7 文件、+160（估） | `field_branch0` / `field_branch_rt` / `field_loop0` / `field_loop_bare` / `field_loop_pre` / `field_copy` / `field_goto_struct`（+ 预期输出 / 脚本行） |
| 文档 / 台账 | 5 文件、+60/−15（估） | 卡 §7.9/§7.9.1、`language-spec.md:2918-2922`、SH-102 处置段、roadmap、零初始化语义的 decision |
| **合计** | **约 11 文件、+280/−22；1 个 DEV 轮次（S）** | 不改 `refs` 布局 / 16 字节句柄 / 8 字节头 / ABI；不 bump MINOR（同一缺陷返工，§6.7 V-3） |
| 门禁 | `p80_retain` ≥24（现 18）；`check-ast` 1538/0/5（原型实测）；sanitizer 583；`check-docs`、G0/G6/G8 | 红证 baseline `953c19e0`；`test(...) 红` 为父提交（T-7） |
| 回退 | `git revert` 核心提交 + 夹具提交 | 核心 1 文件；`/tmp/p80c` 的探针不指向工作树 |

**与 A 的代价对比**：A 约 12 文件 / `+245/−20`，换来「触发集内 UAF=0 + 循环 N−1 泄漏」；B 约
11 文件 / `+280/−22`，换来「触发集内 UAF=0 + 循环零泄漏 + 两条硬错边界」。**成本差约 35 行，不是
L/XL 差。** A 的代价表把 B 估成「新分析、必须再拆」的依据（[claim.md:349-351](claim.md#L349-L351)）
被 E1-5 否定。

**B 的隐藏成本（如实写）**：

- 零初始化是**语言语义变化**：未初始化结构体字段从「未定义值」变成「空串 / 零句柄」，需要一条
  decision 授权；若拒绝，退到硬错（§7 F2），R6b 的 `Holder h;` 裸声明形状将不再零泄漏而是被拒。
- 整结构体赋值与 `goto` 的硬错可能打到既有消费者；本席**没有**扫全仓的 `h = other` /
  结构化局部 + goto 语料（只验证了 `check-ast` 1538 不回归），这是一项未做的迁移面测量。
- 原型把「带聚合初始化器的普通局部」纳入登记，影响面比 5 行补丁大（E1-10 只覆盖了 `check-ast`
  的 1538 项；5 个 skipped 未恢复）。

## 6 E5 — 对 A 最强论点的 steelman 与回应

**A 最强论点（原文，[claim.md:378-382](claim.md#L378-L382)）**：

> 「B 要求『字面满足』，但字面句在未初始化字段上**本身不安全**——无条件 release 旧值正是 R6a 的
> SEGV 来源（E1-1）。要同时满足字面句与安全，B 必须做支配/别名数据流；这是新分析，不是修 bug。
> B 若拒绝数据流，B 自己的方案也不成立。」

以及 [claim.md:349-351](claim.md#L349-L351)：

> 「B 要『循环重赋零泄漏』，只能走字段级支配 + 别名分析（或对 `goto` / 指针写全面硬错）。这不是
> 1 个 S 任务：它要新增分析、改 `StrRetain` 记账、覆盖 `foreach` / `for` 初始化器 / 嵌套字面量 /
> 泛型 `T`，且仍要解决别名；按 T-2 属 L/XL，必须先拆。」

**回应（前两条是让步）**：

1. **让步**：字面句「无条件 release 旧值」在**未定义存储**上确实不安全。A 指出这一点是对的，也是
   R6a 的根因；B 不主张无条件读未初始化值。
2. **让步**：A 的「安全半部」便宜是事实（汇合补丁 `+15/−5`，claim E1-5）；B 的独立增量在 R6b，
   不在 R6a。
3. **「字面 vs 安全」是假二选一**。B 不删 release、不删 retain，而是让存储**先定义**：
   `Holder h;` → `= { 0 }`，`Holder h = {0}` / 裸聚合 → C 零填充。于是「先 retain 右值再 release
   旧值」在分支、循环、`switch` 下都成立，且 `field_loop0` 实测 `live=0`（E1-5）。这不是「支配 /
   别名数据流」：没有 CFG、没有 dominator、没有别名求解，只有「声明即定义」+ 既有
   `sb_field_known → release_old` 路径。**A 的「必须新分析」前提错了。**
4. **「B 的实现也只能给 2」被实测否定**：A 自己把关键区分预测写成「同一 `field_loop0`，A 给
   `live=2`、B 给 `live=0`；若 B 也只能给 2，则 B 没有增量」（[claim.md:331-332](claim.md#L331-L332)）。
   本席实测 B 给 `live=0`（E1-5）。所以「代价不对称」不再是拒绝理由，**剩下的只是合同解释**
   （字段重赋是否属于 D-013 §3 的「重新赋值」），而那应当由 USER/EDITOR 裁定，不能由「B 太贵」
   替代。
5. **A 的泄漏不是「可登记」而是「已交付行为的回退」**：v0.80.2 的 DEV 处置段与卡 §7.9.1 已经把
   「字段重赋 release 旧值」写成已实现（issue:318-321、phase80:394），`language-spec` 也已发布。
   A 现在要把它改成「仅直线代码、其余登记泄漏」，必须同时撤回这些文字并说明是回退；不能以
   「§7.9 既有边界」的名义把它当成从未承诺过的东西。
6. **B 不要求裁判替 USER 改合同**：B 的判据 B-1/B-2 是「实现让 D-013 §3 的字面句为真」；B-3/B-4
   才涉及记录。若 USER 选择 A 的窄合同（新 decision），B 服从新合同（§7 F1），但 B-1 的 R6a
   安全缺陷仍须修——这一点 A 也同意（C-A1），所以那不是两方分歧，而是 A 的既有承诺。

## 7 不利己方与失效条件（B 的 F1…F7）

| ID | 条件 | 后果 |
| --- | --- | --- |
| F1 | USER/EDITOR 以新 decision 明确：D-013 §3 的「重新赋值」**不含字段**，字段只需「赋值 retain」 | B 的 B-2 失去合同依据；B 退为「R6a 必须修 + R6b 登记泄漏」，与 A 的收口条件基本重合。B 服从新合同，但不承认在无 decision 时按窄解释收口 |
| F2 | USER 拒绝「未初始化结构体局部零初始化」的语义变化 | B 只能对「字段可能未初始化」做硬错（P7）；`Holder h;` + 循环的零泄漏不再成立（被拒而不是 `live=0`）；B 的覆盖面与 A 的触发集接近，但仍有 R6a 安全 |
| F3 | 整结构体赋值 / `goto` 的硬错打到既有消费者，或逐字段 retain 的实现成本超过 §5 的 +25 | B 的成本上升到与 A 同阶甚至更高；B 的「更便宜」主张失效（但 R6b 的实测 `live=0` 不变） |
| F4 | B 的实现在全量门禁（含 5 个 skipped、`p80_layout`、sanitizer、真实消费者）上出现回归 | B 的可行性证据降级为「隔离副本原型」；A 可要求先做完整实现再谈收口 |
| F5 | 裁判认定「字段无 Drop（§7.9.4）」使字段重赋的旧值不属于 D-013 §3 的自动半部 | 同 F1，B-2 不成立 |
| F6 | 裁判把 PH-80 收口与 SH-102 状态分开处理：E80-1…8 不含 retain，卡可先收口、SH-102 单独 reopened | B 的「PH-80 不得收口」不成立；B 只剩「SH-102 不得 `verified` + 文档不得写『已修复』」 |
| F7 | 证据席不接受未提交的 `/tmp` 原型作为 E1 证据（要求入库或独立实现） | B 的 E1-5 成本证据降级为估计；A 的 L/XL 论断不再被实测否定，B 的性价比论证变弱（但 E1-1/E1-3 对 HEAD 缺陷的复现不受影响） |

**本席主动承认的最不利事实**：

- B 的强项是 **R6a**：编译期 `cond=0` 的致命信号是确定性的安全缺陷，与合同解释无关；这一条足以
  支撑「SH-102 不得 `verified`」。B 的弱项是 **R6b**：它依赖「D-013 §3 的重新赋值覆盖字段」这一
  解释，而 DEV 在 v0.80.1 写过相反的窄解释，REV 第三轮按字面驳回但没有 USER 签字。**B 不能替
  USER 裁定合同。**
- B 的「零泄漏」只覆盖同一存储位置的重赋，不覆盖 §7.9.4 的 scope Drop；且 B 的路线需要一条新的
  零初始化语义 decision。若 USER 两条都不给，B 的可执行退路是硬错，而不是零泄漏。
- B 的原型当前对 `h = other` 与 `goto` 是**红的**（E1-6/E1-7）；B 不把它们藏起来，也不把
  `+59/−7` 说成完整修复。

## 8 边界与未做（本文件）

- 只写本文件；未改源码、卡、issue、decision、roadmap、tests。`/tmp/p80c` 的补丁与探针是隔离
  副本，未提交；工作树 `git status --porcelain` 只有 `battle/phase80-retain-scope-1/`。
- E1 的 HEAD 证据全部来自 `git archive 953c19e0` 的独立构建；原型来自同一副本的 `Emitter.h.ct`，
  `patch -p1` 已验证可重放（附录 A 的 diff 与本席工作副本逐字节一致）。
- **未做**：整结构体赋值 / `goto` 硬错的实现（E1-6/E1-7 只暴露洞）；全仓 `h = other` 与
  结构化局部 + goto 语料扫描；真实外部消费者回归；zero-init decision 的起草。
- E1-1 的寄存器段在正文以 `...` 略去（7 行），其余逐字；E1-1/E1-5 的 PID/地址每次不同。
- 本目录当前只有 `claim.md` / `counter.md`；`question.md` 与 `verify.json` 未落盘
  （`python3 tools/check-battle.py phase80-retain-scope-1` 输出 `FAIL question.md missing`）。
  其余 anchor 警告来自内联短名（`claim.md:` / `Emitter.h.ct:` / `/tmp` 生成 C 的 `:行号`），
  与 `claim.md` 的写法同形；`tools/battle.sh` 的 verify/close 不加 `--strict`，故不阻断。
  T0/T4 不属本席，未代写。
- 若 `question.md` 的判据编号与本文件不同，按 §1.2 的 B-1…B-5 对齐；B-1…B-5 是收口条件，不是
  新增门禁编号。

## 附录 A — B 原型（候选实现，未提交）

基线 `Emitter.h.ct` 来自 HEAD `953c19e0`；`patch -p1` 已在本席的隔离副本验证，应用后与本席工作
副本逐字节一致（`diff -q` 无输出）。diff 头两行已把 `Emitter.orig.ct` 改写为原文路径，便于直接
应用。

```diff
diff --git a/selfhost/ct-ast/backend/emit/Emitter.h.ct b/selfhost/ct-ast/backend/emit/Emitter.h.ct
--- a/selfhost/ct-ast/backend/emit/Emitter.h.ct
+++ b/selfhost/ct-ast/backend/emit/Emitter.h.ct
@@ -1019,6 +1019,46 @@ static void sb_mark_aggregate(struct Emitter *self, int decl)
     }
 }
 
+/* 1 when the type is a struct with a non-array owning string field. */
+static int sb_struct_owns(struct Emitter *self, const char *tp)
+{
+    const char *txt = tp;
+    int si, fi;
+    if (strncmp(txt, "struct ", 7) == 0) txt += 7;
+    while (*txt == ' ') txt++;
+    si = self->sym->find_struct(txt);
+    if (si < 0) return 0;
+    for (fi = 0; fi < self->sym->structs[si].nfields; fi++) {
+        if (self->sym->structs[si].fields[fi].dims[0]) continue;
+        if (frontend::sym::ct_is_string_value_type(self->sym->structs[si].fields[fi].type))
+            return 1;
+    }
+    return 0;
+}
+
+/* B prototype: a brace-initialised (C zero-fills the omitted members) or
+   explicitly zeroed struct local defines every owning field, so a later
+   `h.f = ...` may release the old value safely. */
+static void sb_mark_struct_all(struct Emitter *self, int decl)
+{
+    const char *txt = self->arena->nodes[decl].text;
+    char base[MAX_TEXT];
+    int si, fi, owner;
+    if (strncmp(txt, "struct ", 7) == 0) txt += 7;
+    while (*txt == ' ') txt++;
+    si = self->sym->find_struct(txt);
+    if (si < 0) return;
+    owner = g_sb.ln - 1;
+    if (owner < 0) return;
+    snprintf(base, sizeof base, "%s", g_sb.lname[owner]);
+    for (fi = 0; fi < self->sym->structs[si].nfields; fi++) {
+        if (self->sym->structs[si].fields[fi].dims[0]) continue;
+        if (!frontend::sym::ct_is_string_value_type(self->sym->structs[si].fields[fi].type))
+            continue;
+        sb_field_mark(self, base, self->sym->structs[si].fields[fi].name, owner);
+    }
+}
+
 /* The `String` / `U16String` declaration statement: retain the initialiser when
    it is another owner's place, zero-initialise a bare declaration so the scope
    release is always safe, and record the binding. 0 = not ours. */
@@ -1034,17 +1074,26 @@ static int sb_decl(struct Emitter *self, int n, int ind)
     if (self->arena->nodes[n].text3[0] || self->arena->nodes[n].aux == 1
         || self->arena->nodes[n].aux == 2) return 0;
     init = self->arena->nodes[n].a;
-    if (init >= 0) {
-        int k = self->arena->nodes[init].kind;
-        if (k == N_INIT_RANGE || k == N_INIT_BRACE || k == N_INIT_MBRACE
-            || k == N_RAW || k == N_CLOSURE) return 0;
-    }
     if (!kind) {
         /* a plain local still records its declared type: `h.tag = s` needs it */
+        int structured = 0;
+        if (init >= 0 && self->arena->nodes[init].kind == N_CLOSURE) return 0;
         sb_lpush(self, self->arena->nodes[n].text2, tp);
-        sb_mark_aggregate(self, n);
+        if (sb_struct_owns(self, tp) && !self->arena->nodes[n].text3[0]) {
+            int ik = init >= 0 ? self->arena->nodes[init].kind : -1;
+            if (init < 0 || ik == N_INIT_BRACE || ik == N_RAW) {
+                structured = 1;
+                sb_mark_struct_all(self, n);
+            }
+        }
+        if (!structured) sb_mark_aggregate(self, n);
         return 0;
     }
+    if (init >= 0) {
+        int k = self->arena->nodes[init].kind;
+        if (k == N_INIT_RANGE || k == N_INIT_BRACE || k == N_INIT_MBRACE
+            || k == N_RAW || k == N_CLOSURE) return 0;
+    }
     if (self->hoist_rvalue(n) != 0) return -1;
     if (self->emit_hoists(ind) != 0) return -1;
     self->emit_indent(ind);
@@ -1105,7 +1154,7 @@ static int sb_assign(struct Emitter *self, int n, int ind)
     fbase[0] = 0;
     ffield[0] = 0;
     fowner = -1;
-    if ((k == N_MEMBER || k == N_ARROW) && sb_field_key(self, lhs, fbase, ffield, &fowner)
+    if (k == N_MEMBER && sb_field_key(self, lhs, fbase, ffield, &fowner)
         && !borrowed && sb_field_known(self, fbase, ffield, fowner))
         release_old = 1;
     self->emit_indent(ind);
@@ -6087,6 +6136,9 @@ impl EmitOps for Emitter {
                        of a declaration this writer does not track (a multiple
                        declarator or a `for` initialiser) is still safe. */
                     fputs(" = { 0 }", self->out);
+                } else if (sb_struct_owns(self, self->arena->nodes[n].text) && !self->arena->nodes[n].text3[0]) {
+                    /* B prototype: define the storage before any field release */
+                    fputs(" = { 0 }", self->out);
                 } else if (self->init->type_needs_init(self->arena->nodes[n].text) && !self->arena->nodes[n].text3[0]) {
                     fputs(" = { ", self->out);
                     if (self->init->emit_vptr_items("", self->arena->nodes[n].text) != 0) return -1;
```

说明：

- 该原型**只**实现 B-1/B-2 的核心机制（定义存储 + 既有 release 路径 + 箭头收窄），**不含** B-3 的
  两条硬错（整结构体赋值、`goto` 扩展），所以 E1-6/E1-7 仍红；B 不把它当完整交付物。
- 不改 `refs` 布局 / 16 字节句柄 / 8 字节头 / 生成的 C ABI；`check-ast` 1538/0/5 与 `p80_retain`
  18/18 不回归。

## 附录 B — 探针源码（与 E1 输出一一对应）

> 全部在 `/tmp/p80c/probes` 一次性生成，未入库；`CT_STD_DIR=/tmp/p80c/lib/std`，统一
> `ct-ast --allow-c-boundary <name>.ct -o <name>.c && cc -std=c99 -fsanitize=address -g …`。

### B.1 `field_branch0.ct`（E1-1；编译期 `cond=0`）

```ct
#include <stdio.h>
struct Holder { String tag; }
int main(void)
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

### B.2 `field_branch_rt.ct`（E1-2；运行期 `argc>100`）

```ct
#include <stdio.h>
struct Holder { String tag; }
int main(int argc, char **argv)
{
    Str lit = "abc";
    Holder h;
    int cond = (argc > 100);
    if (cond) {
        h.tag = lit.to_string();
    }
    h.tag = lit.to_string();
    printf("after branch refs=%d live=%d\n", h.tag.refs(), ct_str_live_count());
    h.tag.release();
    return 0;
}
```

### B.3 `field_loop0.ct` / `field_loop_bare.ct` / `field_loop_pre.ct`（E1-3/E1-4）

```ct
/* field_loop0.ct：与 REV §12.3 逐字相同 */
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

```ct
/* field_loop_bare.ct：与 field_loop0 只差 Holder h;（无初始化器） */
#include <stdio.h>
struct Holder { String tag; }
int main(void)
{
    Str lit = "abc";
    Holder h;
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

```ct
/* field_loop_pre.ct：循环前有直线赋值，用来证明 release 路径已存在 */
#include <stdio.h>
struct Holder { String tag; }
int main(void)
{
    Str lit = "abc";
    Holder h;
    h.tag = lit.to_string();
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

### B.4 `field_copy.ct`（E1-6；整结构体赋值）

```ct
#include <stdio.h>
struct Holder { String tag; }
int main(void)
{
    Str lit = "abc";
    Holder other;
    other.tag = lit.to_string();
    Holder h = { 0 };
    h = other;
    h.tag = lit.to_string();
    printf("other refs=%d live=%d\n", other.tag.refs(), ct_str_live_count());
    other.tag.release();
    h.tag.release();
    printf("final live=%d\n", ct_str_live_count());
    return 0;
}
```

### B.5 `field_goto_struct.ct`（E1-7；`goto` 跳过零初始化）

```ct
#include <stdio.h>
struct Holder { String tag; }
int main(int argc, char **argv)
{
    Str lit = "abc";
    int c = (argc > 100);
    if (c) { goto L; }
    Holder h;
L:
    h.tag = lit.to_string();
    h.tag.release();
    return 0;
}
```

### B.6 `field_ptr.ct`（E1-8；箭头基址重绑）

```ct
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

### B.7 `field_loop_local.ct`（E1-9；循环内新建结构体，§7.9.4 边界）

```ct
#include <stdio.h>
struct Holder { String tag; }
int main(void)
{
    Str lit = "abc";
    int i;
    for (i = 0; i < 3; i++) {
        Holder h = { 0 };
        h.tag = lit.to_string();
        printf("iter %d refs=%d live=%d\n", i, h.tag.refs(), ct_str_live_count());
    }
    printf("final live=%d\n", ct_str_live_count());
    return 0;
}
```
