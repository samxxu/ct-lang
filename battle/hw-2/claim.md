---
id: hw-2
head: 369a2606
seat: DEV
subject: builtin_live_for 的 Str 判据
---

# hw-2 主张书（位置 A：文本近似）

## 0. 结论

位置 A 拆成两个可分别判的命题：

| 命题 | 本席结论 | 关键证据 |
| --- | --- | --- |
| A1 完备性：三条判据覆盖 `Str` 的全部真实使用路径 | **不成立**，本席主动交出反例 | E1-4 |
| A2 处方：不必改成符号级引用位 | **成立** | E1-5、E4 |

反例形态：程序直调层函数、源码不出现 `Str` 字面量（`return str_len(str_from("hi"));`）。
CT 接受（exit 0），判死，产物缺 `Str.c`，`ct build` exit 1。J-1 的失效条件逐字命中。

修正版 A′（本席主张）：三条判据补一条**文本**判据（层导出函数名），子串匹配换成
`Module.h.ct:1228-1230` 已有的词边界谓词。1 个文件、约 6–10 行；仍不引入引用位。

证据环境：HEAD `369a2606`，`/tmp/p0/ct-now` = `ct-ast v0.63.0`，`cc` = clang。工作树未改；
夹具与产物只在 `/tmp/hw2-claim/**`。

```console
$ /tmp/p0/ct-now --version
ct-ast v0.63.0
```

## 1. E1 完整命令与原始输出

六组命令，夹具全文附在本节末。每条都从仓库根执行（`lib/std` 的发现依赖 cwd）。

### E1-1 最小程序：三判据全不命中 → 不拉 `Str`

```console
$ /tmp/p0/ct-now build --emit-c /tmp/hw2-claim/e1/min/m.ct -o /tmp/hw2-claim/e1/min; echo "exit=$?"
cc -std=c99 -I /tmp/hw2-claim/e1/min /tmp/hw2-claim/e1/min/m.c -o a.out
exit=0
$ ls -1 /tmp/hw2-claim/e1/min
m.c
m.ct
```

`cc` 行里只有 `m.c`，没有 `Vec.c/Option.c/Result.c/Str.c`。REQ-HW-011 验收第一条成立。

### E1-2 `struct Struct`：判据 2 子串命中 → 拉 `Str`（如实给出）

```console
$ /tmp/p0/ct-now build --emit-c /tmp/hw2-claim/e1/struct/s.ct -o /tmp/hw2-claim/e1/struct; echo "exit=$?"
cc -std=c99 -I /tmp/hw2-claim/e1/struct /tmp/hw2-claim/e1/struct/Str.c /tmp/hw2-claim/e1/struct/s.c -o a.out
exit=0
$ ls -1 /tmp/hw2-claim/e1/struct
Str.c
Str.h
s.c
s.ct
```

判活为真，产物未引用任何 `Str*` 符号：

```console
$ cc -Wall -Wextra -std=c99 /tmp/hw2-claim/e1/struct/*.c -o /tmp/hw2-claim/e1/struct/prog; echo "cc exit=$?"
cc exit=0
$ nm /tmp/hw2-claim/e1/struct/prog | grep -c ' T _Str\| T _str_'
10
$ /tmp/hw2-claim/e1/struct/prog; echo "exit=$?"
exit=1
```

论证其无害（限 J-1 口径）。多出的单元只增文件，不改任何值：程序返回 1，与判活无关。
成本可量化：`Str.c` 136 行、`Str.h` 一份、链接面 10 个 `Str*` 符号。
这 10 个符号在裸机面不是零成本（`Str.c` 带 `malloc/free`，见 E4），所以本席不称"完全无害"，
只称"无错值、无链接失败"。精确性代价可用 `Module.h.ct:1228-1230` 的词边界谓词消掉。

### E1-3 `Option<Str>`：判据 3（实例参数）命中 → 拉 `Str`

```console
$ /tmp/p0/ct-now build --emit-c /tmp/hw2-claim/e1/optstr/o.ct -o /tmp/hw2-claim/e1/optstr; echo "exit=$?"
cc -std=c99 -I /tmp/hw2-claim/e1/optstr /tmp/hw2-claim/e1/optstr/Option.c /tmp/hw2-claim/e1/optstr/Str.c /tmp/hw2-claim/e1/optstr/o.c -o a.out
exit=0
$ ls -1 /tmp/hw2-claim/e1/optstr
Option.c
Option.h
Str.c
Str.h
o.c
o.ct
```

判据 3 成立：`Str.c` 在产物中。C 层另有一处与本判据无关的失败，如实记录：

```console
$ cc -Wall -Wextra -std=c99 /tmp/hw2-claim/e1/optstr/*.c -o /tmp/hw2-claim/e1/optstr/prog; echo "exit=$?"
lib/std/Option.h.ct:11:25: error: incomplete definition of type 'struct Option_Str'
   11 |     Str_Drop_drop(&_self->value);
      |                    ~~~~~^
optstr/Str.h:14:8: note: forward declaration of 'struct Option_Str'
exit=1
```

界定：`struct Option_Str` 定义在根单元 `o.c:13`，模板单元 `Option.c:16` 只见到前向声明。
这是实例放置问题，不是判活问题（`Str.c` 已在产物里，`Option.c` 也 `#include "Str.h"`）。
本席把它列为观察项，不计入三条判据的反证；它也不影响 `Option<int>` 主线（E3-P1）。

### E1-4 反例（不利己方）：直调层函数、不写字面量 → 判死 → 缺 `Str.c`

```console
$ /tmp/p0/ct-now build --emit-c /tmp/hw2-claim/e1/direct/d.ct -o /tmp/hw2-claim/e1/direct; echo "exit=$?"
cc -std=c99 -I /tmp/hw2-claim/e1/direct /tmp/hw2-claim/e1/direct/d.c -o a.out
exit=0
$ ls -1 /tmp/hw2-claim/e1/direct
d.c
d.ct
$ cc -Wall -Wextra -std=c99 /tmp/hw2-claim/e1/direct/*.c -o /tmp/hw2-claim/e1/direct/prog; echo "exit=$?"
/tmp/hw2-claim/e1/direct/d.ct:7:12: error: call to undeclared function 'str_len'; ISO C99 and later do not support implicit function declarations [-Wimplicit-function-declaration]
    7 |     return str_len(str_from("hi"));
      |            ^
/tmp/hw2-claim/e1/direct/d.ct:7:20: error: call to undeclared function 'str_from'; ISO C99 and later do not support implicit function declarations [-Wimplicit-function-declaration]
exit=1
$ /tmp/p0/ct-now build /tmp/hw2-claim/e1/direct/d.ct -o /tmp/hw2-claim/e1/direct/prog; echo "exit=$?"
'cc' -std=c99 -I '.ctbuild' '.ctbuild/d.c' '-o' '/tmp/hw2-claim/e1/direct/prog'
/tmp/hw2-claim/e1/direct/d.ct:7:12: error: call to undeclared function 'str_len'; ISO C99 and later do not support implicit function declarations [-Wimplicit-function-declaration]
    7 |     return str_len(str_from("hi"));
      |            ^
/tmp/hw2-claim/e1/direct/d.ct:7:20: error: call to undeclared function 'str_from'; ISO C99 and later do not support implicit function declarations [-Wimplicit-function-declaration]
    7 |     return str_len(str_from("hi"));
      |                    ^
2 errors generated.
exit=1
```

这就是 J-1 的失效条件：自洽输入（CT exit 0）、程序需要 `Str` 的 C 符号、判活为假、产物缺
`Str.c`、链接失败。反例的触发条件可复述为一句：**源码里没有 `Str` 这个 token**。

### E1-5 同一输入只差一个注释 → 判活 → 构建成功

夹具唯一差别是第一行注释里出现 `Str`：

```console
$ /tmp/p0/ct-now build --emit-c /tmp/hw2-claim/e1/direct2/d2.ct -o /tmp/hw2-claim/e1/direct2; echo "exit=$?"
cc -std=c99 -I /tmp/hw2-claim/e1/direct2 /tmp/hw2-claim/e1/direct2/Str.c /tmp/hw2-claim/e1/direct2/d2.c -o a.out
exit=0
$ grep -n '#include' /tmp/hw2-claim/e1/direct2/d2.c
3:#include "Str.h"
$ cc -Wall -Wextra -std=c99 /tmp/hw2-claim/e1/direct2/*.c -o /tmp/hw2-claim/e1/direct2/prog; echo "exit=$?"
exit=0
$ /tmp/hw2-claim/e1/direct2/prog; echo "exit=$?"
exit=2
```

判活是纯文本开关：多一个 `Str` token 就补回整个单元与头。A2 由此成立——闭合缺口只需要在文本
判据里加"层导出函数名"，不需要在 `frontend/sym` 里加引用位。

### E1-6 真实使用正例：`Str` 命名 → 拉 `Str`，产物可运行

```console
$ /tmp/p0/ct-now build --emit-c /tmp/hw2-claim/e1/real/r.ct -o /tmp/hw2-claim/e1/real; echo "exit=$?"
cc -std=c99 -I /tmp/hw2-claim/e1/real /tmp/hw2-claim/e1/real/Str.c /tmp/hw2-claim/e1/real/r.c -o a.out
exit=0
$ ls -1 /tmp/hw2-claim/e1/real
Str.c
Str.h
r.c
r.ct
$ cc -Wall -Wextra -std=c99 /tmp/hw2-claim/e1/real/*.c -o /tmp/hw2-claim/e1/real/prog; echo "exit=$?"
exit=0
$ /tmp/hw2-claim/e1/real/prog; echo "exit=$?"
exit=2
```

### 夹具全文（可复制）

```c
/* /tmp/hw2-claim/e1/min/m.ct */
int main(void)
{
    return 0;
}
```

```c
/* /tmp/hw2-claim/e1/struct/s.ct */
struct Struct { int x; };

int main(void)
{
    struct Struct v;
    v.x = 1;
    return v.x;
}
```

```c
/* /tmp/hw2-claim/e1/optstr/o.ct */
int main(void)
{
    Option<Str> o = { str_from("hi"), 1 };
    return o.has;
}
```

```c
/* /tmp/hw2-claim/e1/direct/d.ct */
int main(void)
{
    return str_len(str_from("hi"));
}
```

```c
/* /tmp/hw2-claim/e1/direct2/d2.ct（与 direct/d.ct 只差第 1 行） */
/* Str is mentioned only in this comment. */
int main(void)
{
    return str_len(str_from("hi"));
}
```

```c
/* /tmp/hw2-claim/e1/real/r.ct */
int main(void)
{
    Str s = str_from("hi");
    int n = str_len(s);
    s.release();
    return n;
}
```

## 2. E2 锚点

### 2.1 支持己方

| 锚点 | 内容 |
| --- | --- |
| `selfhost/ct-ast/frontend/module/Module.h.ct:2047-2049` | 判据 3：实例的 `ctype[0]`/`carg[0]` 含 `Str` 即活（`Option<Str>` 走这条，E1-3） |
| `Module.h.ct:2051-2055` | 判据 2 + `Vec`→`Str` 边：非内置单元源码扫描；`Vec` 活则 `Str` 活 |
| `Module.h.ct:1228-1230` | 同一文件已有 `Str` 名的**词边界**谓词（`strncmp(base,"Str",3)` 后查 `0/' '/'*'/'['`）；A′ 直接复用，不必新造机制 |

### 2.2 不利于己方（必须给出）

| 锚点 | 内容 | 影响面界定 |
| --- | --- | --- |
| `Module.h.ct:211` | `hit = strstr(buf, needle) ? 1 : 0;` 子串匹配，`Struct`/`String`/注释/字符串字面量全命中（E1-2、E1-5） | 只影响判活集合，方向单一：只会**多**留单元，不会少留；不产生错值。实测成本 1 个单元（136 行）+ 10 符号 |
| `Module.h.ct:2048` | `strstr(ins[i].ctype[0], "Str")` 同类子串匹配；`String` 等实例参数会误命中 | 同上，仅多留 |
| `Module.h.ct:2053` | `file_mentions(self->units[i].path, "Str")` 只认字面量；`str_from`/`str_len` 不含 `Str` → 判死（E1-4） | 反方向：只会**少**留单元，后果是链接失败。漏的路径可枚举：层导出的 10 个函数名（`lib/std/Str.h.ct`） |
| `battle/hw-2/question.md:64-66` | 位置 B 对本行的指控（见 E5） | 逐点回应见 §5 |

补充一条对己方不利的事实：判死时 emitter **已经知道** `Str` 被引用——`/tmp/hw2-claim/e1/direct/d.c:6-7`
仍写出 `struct Str;` 与 `extern void Str_Drop_drop(void *self);`。判活发生在其之前
（`Module.h.ct:1871`），这条信息未被利用。它说明"更早置位"技术上可行，本席不据此主张 A1，
仅承认它是 A′ 之外的一条可选路线。

## 3. E3 可证伪预测

P1（已跑，一次验证）：REQ-HW-011 的两条主线在现状下成立。

```console
$ bash test/ast/p64_on_demand.sh /tmp/p0/ct-now; echo "exit=$?"
OK p64ond
exit=0
```

预测：若 A′ 的"主线不变"成立，任何后续补丁都必须保持这一行 `OK p64ond`。一次验证即可。

P2（已跑）：误命中只增产物、不改行为。

```console
$ nm /tmp/hw2-claim/e1/struct/prog | grep -c ' T _Str\| T _str_'; /tmp/hw2-claim/e1/struct/prog; echo "exit=$?"
10
exit=1
```

预测：`struct Struct` 程序的返回码与未判活时相同（1），`Str*` 符号数恒为 10。任一条不符即证伪。

P3（已跑）：判活由文本唯一决定。

```console
$ ls -1 /tmp/hw2-claim/e1/direct/*.c /tmp/hw2-claim/e1/direct2/*.c | xargs -n1 basename
d.c
Str.c
d2.c
```

预测：`direct`（无 token）产物只有 `d.c`，`cc` 失败；`direct2`（注释含 token）产物含 `Str.c`，
`cc` 成功且运行退出 2（E1-4/E1-5 的 exit 已给出）。一次验证：只改注释一行，结果翻转。

P4（未跑，一次可验）：A′ 的补法足够。给判据 2 增加层导出函数名后，`direct` 应判活并构建成功，
且 `frontend/sym/**` 无 diff。验证配方：

```console
$ cp -R /Users/samxx/dsh-ws/ct-lang /tmp/hw2-claim/tree
# 只在副本里改 Module.h.ct:2051-2055，加 str_from/str_len/... 名单
$ cd /tmp/hw2-claim/tree && /tmp/p0/l2 build -I selfhost/ct-ast selfhost/ct-ast/main.ct -o /tmp/hw2-claim/out
$ cc -Wall -Wextra -std=c99 /tmp/hw2-claim/out/*.c -o /tmp/hw2-claim/ct
$ /tmp/hw2-claim/ct build --emit-c /tmp/hw2-claim/e1/direct/d.ct -o /tmp/hw2-claim/e1/direct-p4 && ls /tmp/hw2-claim/e1/direct-p4
```

预测输出：`Str.c d.c d.ct`，且后续 `cc` + 运行退出 2。若仍只有 `d.c`，A′ 的补法被证伪。

## 4. E4 代价量化

### 4.1 A′（文本补充，本席主张）

| 项 | 预计 |
| --- | --- |
| 改动文件 | 1 个实现文件 `selfhost/ct-ast/frontend/module/Module.h.ct`；1 个探针 `test/ast/p64_on_demand.sh` |
| 行数 | 实现 +6～10 行（判据 2 加层导出名；子串换 `:1228-1230` 的词边界谓词）；探针 +15～25 行（直调反例 + `struct Struct` 精确性断言） |
| 门禁 | `p64_on_demand`（`selfhost/check-ast.sh:649`）由绿转严；`check-ast` 全量重跑；`p39 r8` 基线当前 0 条 `Str.*`（`grep -c 'Str\.' test/modules/p39_lib/baseline.sha` = 0），词边界收紧不改它 |
| 回退 | 单提交 `git revert`，探针回退；无基线冲突 |
| 风险 | 层导出名与实现脱钩（名单漏新函数）→ 需一条"名单覆盖 `lib/std/Str.h.ct` 全部 `pub` 函数"的机械检查 |

### 4.2 B（符号级引用位）

| 文件 | 预计行数 | 理由 |
| --- | --- | --- |
| `frontend/sym/Symbols.h.ct` | +45～60 | 引用位集合 + `ct_ref_add`/`ct_ref_has` |
| `frontend/type/TypeCheck.h.ct` | +15～25 | 每个解析出 `Str` 类型的点置位（声明、参数、返回、字段、cast） |
| `frontend/module/Module.h.ct` | -20/+10 | `builtin_live_for` 读引用位；删 `file_mentions` |
| `backend/emit/Emitter.h.ct` | +5～10 | 若走 emitter 的 `struct Str;` 路径，则在此置位 |
| `test/ast/p64_on_demand.sh` + 新夹具 | +30～40 | 直调、词边界、负例 |
| `test/modules/p39_lib/baseline.sha` | 可能重写 | 判活集合一变大/变小就要重写；`91c6c179` 已示范一次（50 行） |
| 合计 | 4 个实现文件、约 100～160 行 + 基线 | |

影响门禁：`selfhost/check-ast.sh` 的自编不动点与全量语料等价（整脚本）、裸机段
`p64_on_demand:649`、`p64_freestanding:657`、`p39 r1–r8:3701-3753`、`test/pkg/run.sh`；
提交层 `g3`（零警告）、`g5`（负例）、`g8`（路径/粒度）。

回退步骤（B 或 A′ 通用）：

```console
$ git revert <impl-sha>
$ bash test/ast/p64_on_demand.sh <ct-ast>
$ bash selfhost/check-ast.sh
# 基线若冲突：
$ git checkout <impl-sha>^ -- test/modules/p39_lib/baseline.sha
```

结论：B 的改动面是 A′ 的 4 倍以上，且置位点每漏一处就新增一条 J-1 反例；A′ 只有一处判据、
一份名单可机械核对。A2 的"不必改成符号级引用位"由代价差支撑。

## 5. E5 steelman 与逐点回应

位置 B 原文（`battle/hw-2/question.md:64-66`）：

> `strstr(源码, "Str")` 是子串匹配，`struct Struct`、`String`、`Strlen`
> 都会误命中；这使「只按实际使用/实例化拉取」（REQ-HW-011）在可复现输入上为假，且 J-2 的口径
> 无法机械界定——同一个 `strstr` 既可能漏（拼写差异）也可能多（子串），属不可验收的近似。

这是本场最强论点：它同时指控精度（多）与完备（漏），并给出"不可验收"的结论。逐点回应：

1. "误命中使 REQ 为假"——误命中可复现（E1-2），本席承认。但 REQ-HW-011 的**验收条目**只有两条
   主线（最小程序、`Option<int>`），现状都过（E1-1、E3-P1）。误命中的代价是 1 个单元 + 10 符号，
   无错值（E3-P2）。B 未给出"误命中导致链接失败或错值"的样本。
2. "J-2 口径无法机械界定"——不成立。判活是纯函数（实例表 + 源码文本），产物集合可逐输入断言；
   `p64_on_demand` 已经这样断言了两条主线（E3-P1）。补词边界后可把第三条也写成断言。
   "无法界定"是"尚未写探针"，不是"写不出探针"。
3. "既可能漏（拼写差异）"——方向正确，且比 B 说得更重：真正的漏不是拼写，而是直调层函数不写
   `Str` 字面量（E1-4）。本席主动交出这条反例，并承认 A1 因此不成立。但漏的路径可枚举
   （层导出的 10 个函数名），补一条文本判据即可，不需要引用位。
4. "不可验收的近似"——多与漏的方向不同：多只增单元、可断言；漏只在 token 缺失时发生、可枚举。
   两边都能落成探针，故"不可验收"言过其实；真正的结论是"现状缺一条判据"，不是"近似不可用"。
5. B 的处方（符号级引用位）代价见 E4：4 文件 100～160 行 + 基线重写 + 全门禁，收益只是把同一
   集合校准；且置位点分散，漏一处就新增一条与 E1-4 同类的反例。与 A′ 的 1 文件 6～10 行不成比例。

本席接受 B 的可复现部分（子串误命中），不接受其处方（符号级引用位）。

## 6. 失效条件（自列，供反证）

- 若存在"需要 `Str` 符号、既无 `Str` 字面量、也不经层导出函数名"的路径（如手写 C 头里直接用
  `struct Str`），A′ 仍漏；该路径未找到样本。
- 若语料要求产物集合与文本命中严格绑定，词边界收紧会改 `p39` 基线；当前基线 0 条 `Str.*`，
  预计不改，未实测。
- P4 未跑：A′ 的补丁是预测，不是已验收的实现。本席不主张 A′ 已落地。
- E1-3 的 `Option<Str>` 在 C 层失败（实例放置），与本争点无关但仍是 PH-64 产物面的观察项。
