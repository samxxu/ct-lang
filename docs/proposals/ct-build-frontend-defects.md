# `ct build` 前端缺陷修复提案（给 CT 组）

> **读者**：CT 语言与编译器的维护者。
> **来源**：RILL 在 CT 上实现时撞到的四条 `ct build` 限制；本文只把其中**确认为实现缺陷**的条目
> 写成可直接照着修的修复单，规范空白放在 §5 单列。
> **基线**：`ct v0.44.1`（tag `13db6cad`），macOS arm64 / Apple clang。探针在 `/tmp/ctgap3`，
> 全部在 `CT_STD_DIR=<repo>/lib/std` 下重跑（不设会把泛型声明误解析，见总清单 §9.3）。
> **纪律**：不改 `selfhost/`、`test/`、规约正文；本文只描述根因与修法，不含补丁代码。

---

## 0 结论（可直接摘出）

RILL 撞到的四条 `ct build` 限制，按源码核实为 **3 条实现缺陷 + 1 条规范空白**。最该先修的是
**DF-1：超过 159 字节的预处理行被静默截断**——`ct` 退出码 0、无任何诊断，生成的 C 与源码不一致
（实测：510 字节的宏在生成物里只剩 159 字节；截断点落在合法边界时 `ct`、`cc`、运行全部 rc=0，
但返回值从 6 变成 3）。它不是「编不过」，是「编过了、产物不一样」，属于会静默改变行为的编译器缺陷，
比报错的缺陷危险。DF-2（宏续行）与 DF-3（前向 typedef）是前端未实现，报错明确、有绕法；修完这三条，
RILL 的 CT 实现才能不再退回单文件 `ctc`，从而保住多单元组织与增量构建。第四条（`impl` 尾分号）
是规范空白（grammar 本来就没写 `;`），先定规约再谈实现，优先级最低。

**与能力缺口清单的分工**：清单 [language-capability-gaps.md](language-capability-gaps.md) 是
「能力缺口总账」（26 条，含规范缺口与优先级口径），回答**要不要补**；本文是「具体缺陷的修复单」，
只收已确认为实现缺陷的条目，回答**怎么修、怎么验、修了会不会弄坏别的**。两边的条目互相对应
（G-8↔DF-1、G-7↔DF-2、G-5↔DF-3、G-6↔SB-1），本文不复制清单里的影响面评估与优先级推导。

---

## 1 DF-1 超过 159 字节的预处理行被静默截断

**现象**：一行以 `#` 开头的预处理行（`#define`、`#include` 或其他指令）超过 159 字节时，`ct`
正常退出，但生成的 C 里这一行被截短；随后 `cc` 报语法错误，报错指向这一行的末尾，而不是
「编译器截断了它」；截断点落在合法边界时连 `cc` 都不报错，宏的语义已被改掉。

**最小复现**：

```c
#define is_kw(x) (strcmp((x),"if")==0 || strcmp((x),"else")==0 || strcmp((x),"while")==0 || strcmp((x),"for")==0 || strcmp((x),"return")==0 || strcmp((x),"struct")==0 || strcmp((x),"union")==0 || strcmp((x),"enum")==0 || strcmp((x),"switch")==0 || strcmp((x),"case")==0 || strcmp((x),"default")==0 || strcmp((x),"break")==0 || strcmp((x),"continue")==0 || strcmp((x),"sizeof")==0 || strcmp((x),"typedef")==0 || strcmp((x),"static")==0 || strcmp((x),"const")==0 || strcmp((x),"void")==0 || strcmp((x),"int")==0)

#include <string.h>

int main(void) {
    return is_kw("if") ? 0 : 1;
}
```

```text
$ ct l4_long_macro.ct -o l4.c          # 单文件模式
$ echo $?
0
$ grep '^#define is_kw' l4.c | awk '{print length($0)}'
159                                    # 源行 510 字节
$ cc -std=c99 l4.c -o l4
l4.c:11:155: warning: missing terminating '"' character [-Winvalid-pp-token]
l4.c:156:13: error: expected expression
1 warning and 3 errors generated.
$ echo $?
1
```

`ct build l4_long_macro.ct -o out` 的结果相同：输出以 `'cc' -std=c99 …` 开头，说明**失败发生在
`cc` 阶段，前端没有报任何错**；`cc` 的报错经 `#line` 映回源文件 1:155。

静默改行为的版本（探针 `/tmp/ctgap3/l6_valid_trunc.ct`）：宏行 162 字节，`* 2` 落在第 160 字节
之后——

```text
$ python3 -c 'h="#define M (1 + 2)"; open("l6.ct","w").write(h + " "*(159-len(h)) + "* 2\n\nint main(void) { return M; }\n")'
$ ct l6.ct -o l6.c && cc -std=c99 l6.c -o l6 && ./l6; echo $?
3                                      # 源码语义是 6；ct/cc/run 全 rc=0
```

**根因定位**（词法层为主，语法层二次拷贝为次）：

1. 词法层：`selfhost/ct-ast/frontend/lex/Lexer.h.ct` 的 `LexOps::next`，T_PP 分支（第 90–97 行）
   逐字符拷进 `toktext`，条件是 `n + 1 < MAX_TEXT`，超出的字符**直接丢弃且不置 `toktrunc`**。
   对照同一函数的标识符分支（第 108–110 行）会置 `toktrunc`，由 parser 报 `identifier is too long`。
   `MAX_TEXT` 为 160（`Lexer.h.ct:18`、`frontend/sym/Symbols.h.ct:29`）。
2. 语法层：`selfhost/ct-ast/frontend/parse/Parser.h.ct` 的 `parse_program`，第 1311–1313 行把
   `toktext` 用 `snprintf(self->arena->nodes[n].text, MAX_TEXT, "%s", …)` 拷进节点；`Arena::Node.text`
   是 `char text[160]`（`selfhost/ct-ast/runtime/arena/Arena.h.ct:35`）。此处没有第二次机会。
3. 发射层不是元凶：`selfhost/ct-ast/backend/emit/Emitter.h.ct:1339`（普通单元的 `N_PP`）与 `:545`
   （`.m.ct` prologue 去重后）都只是 `fprintf("%s\n", nodes[n].text)`。

另有一个同源上限：`.m.ct` prologue 的去重表是 `char seen[64][256]`（`Emitter.h.ct:497`，
`:542` 用 `snprintf(..., 256, ...)` 写入）。即使节点文本被修好，超过 255 字节的两条**不同**宏也会
因去重键被截断而互相判重，只能展开一条。

**影响面**：任何 `#define` / `#include` 行超过 159 字节的包（长 include 路径同样中招）。后果两档：
截断点不合法 → `cc` 失败，错误位置指向生成物；截断点合法 → **静默改变宏语义**。这是四条里唯一
`ct` 退出码为 0 的缺陷，也是唯一会产出「能编译但不对」的产物的缺陷。

**修复思路**：

- **方案 A（推荐）**：预处理行不再存进定长 `Node.text`，改为存源缓冲切片 `(unit, offset, len)`，
  发射时按切片写出；`.m.ct` prologue 去重对切片内容做比较/哈希。改动点：`Lexer` 的 T_PP 捕获、
  `Parser.h.ct:1311` 的节点构造、`Emitter` 的两处 `N_PP` 输出与去重表。代价是动节点表示与去重键，
  但彻底移除上限，且保留「原样透传」的语义。
- **方案 B（止损，可与 A 并行先上）**：保留 160 上限，越界时置标志并 `die`，例如
  `preprocessor line is too long (N > 159); split it or move it to a .shim.h`。一行守卫，把静默错误
  变成显式错误；不增加能力，但立刻消除最危险的一档。若 DF-2 尚未修，多行长宏也会落到这条诊断上，
  而不是被截断——这是可接受的中间态。
- **方案 C（不推荐）**：把 `MAX_TEXT` 调大（1024/4096）。`MAX_TEXT` 在每个单元各有一份宏，
  `Lexer` 是 `pub struct`、`toktext[160]` 是写死的字面量（宏不跨单元），`Arena::Node` 有三个
  `char[160]`。加大会让每个节点和每个 `Lexer` 一起膨胀，而且只是把墙推远。

**兼容性风险**：

- 方案 A：此前被截断的行会完整发射，生成物变化（这正是修复目的）。若 `test/` 的 golden 里存在
  >159 字节的 `#` 行，夹具会变；需先 `grep -n '^#' test/` 逐行量长度。
- 方案 B：此前「能过」（`ct` rc=0、产物错误）的输入会变成 `ct` 失败，属于行为收紧，必须写进
  release note；这是有意的。
- 方案 C：所有单元的 `MAX_TEXT`、`Lexer` 的 `toktext` 字面量、`Arena::Node` 的三个 `char[160]`
  必须同步；`.h` 里没有宏，漏改会静默按旧容量工作。
- 门禁：`bash selfhost/check-all.sh`、全部 golden、`--emit-c` 一致性、`.m.ct` prologue 去重夹具、
  `python3 test/docs/check-docs.py`。

**验收方式**：

- 负例 `fx_pp_too_long.ct`：一行 200 字节的 `#define`。方案 B 下断言 `ct` rc≠0 且诊断含 `too long`；
  方案 A 下断言生成 C 的该行与源行逐字节相等、`cc` 通过。
- 正例 `fx_pp_value.ct`：即上面的 `l6` 形态（源语义 6，`* 2` 在第 160 字节之后），断言 `ct`、`cc`
  rc=0，运行返回 6；并断言生成行长度等于源行长度。
- 边界对：159 / 160 字节各一条，断言 159 通过、160 不静默。
- `.m.ct` prologue：两条不同、都 >255 字节的宏各自展开一次；两条相同长宏只展开一次（保留去重语义）。

**不修的后果**：所有用长宏的包都会中招，且 `ct` 不报错。RILL 的 `is_kw`（510 字节）在生成 C 里只剩
159 字节，`cc` 的报错指向生成物；更坏的情况是截断点合法、编译通过但语义变了（`l6`：6 变 3）。
被迫退回单文件 `ctc`，失去多单元组织与增量构建。

---

## 2 DF-2 `#define` 的反斜杠续行被当成独立语句

**现象**：`#define f(x) \` 换行续写时，续行没有被并进同一个宏，而是被当作顶层声明解析，报
`expected a type`。

**最小复现**：

```c
#define ADD(a, b) \
    ((a) + (b))

int main(void) {
    return ADD(1, 2);
}
```

```text
$ ct l3_macro_continuation.ct -o l3.c
l3_macro_continuation.ct:2:6: error: expected a type (tok 4 '(')
$ echo $?
1
$ ct build l3_macro_continuation.ct -o out
l3_macro_continuation.ct:2:6: error: expected a type (tok 4 '(')
$ echo $?
1
```

**根因定位**（词法层）：`selfhost/ct-ast/frontend/lex/Lexer.h.ct` 的 T_PP 分支（第 90–97 行）
`while (self->src[self->pos] && self->src[self->pos] != '\n')` 只读到物理行尾就返回，不检查行尾的
`\`，也不吞掉换行。下一次 `next()` 见到 `\n` 后置 `bol=1`，续行按普通 C 代码重新 token 化；
语法层没有「T_PP 还有续行」的概念，于是 `((a) + (b))` 在顶层按声明解析，在 `(` 上报
`expected a type`。诊断位置落在第二行，用户很难联想到上一行的反斜杠。

**影响面**：所有多行宏（关键字表、前缀判断、单行放不下的表达式）。报错明确（不是静默），但位置
误导。真正的麻烦是绕法：把宏压成一行后必然撞 DF-1 的 159 字节上限，因此「多行长宏」在修好这两条
之前无法表达。

**修复思路**：

- **方案 A（推荐）**：在词法层做行拼接（C 的翻译阶段 2）：捕获到的物理行若以 `\` 结尾，丢掉 `\`
  与换行、`line++`，把下一行续进同一个 token。parser 完全无感。前提是 token 存储能超过 159 字节
  （与 DF-1 方案 A 一起做；否则拼接后立刻被截断，反而制造新的静默错误）。
- **方案 B**：把续行表示成多个 `N_PP` 节点并加 `continued` 标志，发射时合成一行。保留物理行粒度，
  便于 `#line` 映射与逐行去重，但 parser、emitter、去重三处都要改。
- 细节：C 规定反斜杠必须是行尾的最后一个字符，`\` 后带空格**不算**续行；实现要按此判断，并给
  「`\` 后有空白」一条明确诊断，而不是让用户看到续行被当代码。

**兼容性风险**：

- 此前被拒的写法变为接受，不会让现有好代码从「能编」变「编不过」。
- `.m.ct` prologue 的「按整行去重」单位从物理行变成逻辑行（[language-spec.md:591](../language-spec.md#410-mapphase-11-新增--sh-20-扩展仅-ct-ast)）：
  同一宏的两种换行写法会从两条变一条，去重结果改变；要重跑 prologue 夹具。
- 若只做拼接、不修 DF-1，>159 字节的多行宏会从「报错」变成「静默截断」——**这比现状更坏**，
  两条必须一起上或先上 DF-1 的方案 B。
- 门禁：`bash selfhost/check-all.sh`、全部 golden、`.m.ct` prologue 夹具。

**验收方式**：

- 正例 `fx_macro_cont.ct`：一条 2 行、一条 3 行宏；其中一条总长 >159 字节（需 DF-1 方案 A），
  断言生成 C 里是**一条**逻辑行、`cc` 通过、运行值正确。
- 负例 `fx_macro_cont_space.ct`：`\` 后带空格 → 不拼接，诊断说明续行符必须是行尾最后一个字符。
- 负例 `fx_macro_cont_eof.ct`：`\` 在文件末尾、无续行 → 明确诊断，不越界读。

**不修的后果**：所有多行长宏写不出来；RILL 的 `is_kw` 被迫压成单行，随即撞 DF-1；只能退回单文件
`ctc`，失去多单元组织与增量构建。

---

## 3 DF-3 前向 typedef（`typedef struct JVal JVal;`）被拒

**现象**：`typedef struct JVal JVal;` 报 `unexpected token`；错误列号指在别名上，看起来像少了
一个 `{`。

**最小复现**：

```c
typedef struct JVal JVal;

struct JVal {
    int tag;
}

int main(void) {
    JVal v;
    v.tag = 1;
    return v.tag;
}
```

```text
$ ct l1_typedef.ct -o l1.c
l1_typedef.ct:1:21: error: unexpected token
$ echo $?
1
$ ct build l1_typedef.ct -o out
l1_typedef.ct:1:1: error: unexpected token
$ echo $?
1
```

**根因定位**（语法/声明层）：

1. `selfhost/ct-ast/frontend/parse/Parser.h.ct` 的 `parse_typedef`（第 2395 行），struct/union
   分支（第 2432–2436 行）读完 `struct` 就无条件调用 `parse_record_def`。
2. `parse_record_def`（同文件第 2082 行）只在下一个 token 是 `;` 时接受前向形式
   （第 2178–2184 行，返回 `NO_NODE`）；否则继续到 `parse_record_body`，由第 1927 行的
   `expect("{")` 报 `unexpected token`。别名 `JVal` 正好是那个「本该是 `{`」的 token。
3. 缺的分支：**标签后面直接跟别名 + `;`**（无体）这一形态。词法、类型表都支持，只是
   `parse_typedef` 没走到。

对照实测（同一套探针）：`struct JVal;` 前向声明可用（`l1b`，`ct`/`cc`/run 全 0）；
`typedef struct JVal { … } JVal;` 可用（`l1c`，全 0）；两个类型互相引用、指针处写
`struct B *` 可用（`l1d`，全 0）。只有「前向 typedef」这一种拼写失败。

**影响面**：相互递归类型、想用 typedef 名铺公开 API 的包。编译失败（显式报错，不是静默），
绕法是 `struct T *` 拼写或调整定义顺序。

**修复思路**：

- **方案 A（推荐）**：在 `parse_typedef` 的 struct/union 分支里增加「标签 + 标识符 + `;`」形态：
  注册标签（`add_struct`，`defined=0`）与别名，建一个发射 `typedef struct Tag Alias;` 的节点。
  生成的 C 与源码拼写一致，使用方能看到这个 C 类型名。
- **方案 B**：只做成编译器内部同义词（类似 §4.19 的 `type` 别名），生成物里不出现该 C 名字。
  改动小，但会破坏「头文件里能看到这个名字」的预期，跨单元消费者拿不到该 typedef。
- 注意：第 2178 行的前向形式返回 `NO_NODE`，别名分支需要自己的节点与发射路径；重复检查沿用
  `structs[].defined` 即可（与 `struct JVal;` 后接定义同一路径）。

**兼容性风险**：此前被拒的写法变为接受，现有代码产物不变。要确认别名与标签同名
（`typedef struct JVal JVal;`）不会被重复类型诊断误报，且后续 `struct JVal { … }` 不会被当成
「重复定义」。门禁：typedef 夹具、`.h.ct` 导出夹具、重复类型诊断夹具、`--emit-c` 一致性。

**验收方式**：

- 正例 `fx_fwd_typedef.ct`：上面的 `l1` 形态 → `ct`、`cc` rc=0，运行返回 1。
- 正例 `fx_fwd_typedef_mutual.ct`：两个前向 typedef 互相引用 → 全 0，运行值正确。
- 负例 `fx_fwd_typedef_dup.ct`：同一别名声明两次 → 重复别名诊断。
- 负例 `fx_fwd_typedef_nodef.ct`：前向 typedef 后从无定义、按值使用 → 至少 `cc` 报
  incomplete type；若 CT 想更早报，需先定诊断文案。

**不修的后果**：所有想用 C 习惯写法组织类型的包都要改成 `struct T *`，公开 API 里多出 `struct`
关键字；RILL 的 CT 实现因此退回单文件 `ctc`。

---

## 4 修复顺序与依赖

- **DF-1 先上**：它是唯一静默的一条，且 DF-2 的正确修法依赖它的存储改造（否则拼接后立即截断）。
  若排期紧，DF-1 的方案 B（越界报错）可以独立先发，代价是不增加能力、只是不再骗人。
- **DF-2 紧随**：与 DF-1 方案 A 同批最省事；单独上会把「多行宏报错」变成「多行宏静默截断」。
- **DF-3 独立**：与另两条无耦合，可并行，改动面最小。
- **SB-1 最后**：只需规约改一行 + `accept(";")`，但按「先定规范再补实现」的顺序走。

---

## 5 规范空白（不进修复清单）

### SB-1 `impl` 块尾分号被拒

**现象**：在 `impl Trait for T { … }` 或 `impl T { … }` 的 `}` 后写 `;`，报
`expected a type (tok 4 ';')`。

**最小复现**：

```c
struct J {
    int n;
}

impl J {
    int get(int i) {
        return self->n + i;
    }
};

int main(void) {
    struct J j;
    j.n = 1;
    return j.get(2);
}
```

```text
$ ct l2_impl_semicolon.ct -o l2.c
l2_impl_semicolon.ct:9:2: error: expected a type (tok 4 ';')
$ echo $?
1
```

**定性**：**规范空白**，不是实现缺陷。语法定义 `impl-def` 没有尾分号
（[language-spec.md:75](../language-spec.md#3-语法总览)），所以拒绝是**照规约执行**。但 `struct` / `enum`
的定义后分号是可选的（`Parser.h.ct:816-825` 对两者都 `accept(";")`），`impl` 分支
（`Parser.h.ct:808-809`）没有，宽容度不一致——这是要决定的「设计边界」，不是「已定义却没做到」。

**需要先定规范还是先补实现**：**先定规范**。两个选项：

1. 与 `struct` 对齐：grammar 的 `impl-def` 末尾加可选 `";"`，再在 `parse_impl` / `parse_impl_inherent`
   返回前加 `accept(";")`。
2. 维持拒绝：在规约里明说「`impl` 块后不写分号」，并把诊断改成 `remove the ';' after an impl block`
   （现在是 `expected a type`，指向 `;`，不像语法规则）。

**绕法**：删掉 `;`，代价一个字符。不要用「退回 `ctc`」绕：实测 `ctc` 不接受固有 impl
（`error: expected 'for' in impl of 'J'`），L0 也没有 `pub` / `import` / `namespace`。

**不修的后果**：从 C 迁移、习惯在块后加分号的代码每次要多改一个字符；RILL 确实踩到，但这是四条里
代价最小的一条。

---

## 6 汇总

| 编号 | 定性 | 危害 | 修复难度 | 建议优先级 |
| --- | --- | --- | --- | --- |
| **DF-1** | 实现缺陷 | **静默错误**：`ct` rc=0、无诊断，生成 C 与源码不一致；截断点合法时编译通过但行为改变（实测 6→3） | 中（预处理行改切片存储 + 去重键改造；或先加越界报错） | **P0** |
| **DF-2** | 实现缺陷 | 编译失败：多行长宏的续行被当成顶层代码；错误位置误导 | 低–中（词法层拼接，依赖 DF-1 存储改造） | **P1** |
| **DF-3** | 实现缺陷 | 编译失败：前向 typedef 被拒，相互递归类型只能用 `struct T *` 拼写 | 低（`parse_typedef` 增分支 + 一条 typedef 发射） | **P2** |
| SB-1 | 规范空白 | 编译失败：`impl` 尾分号被拒，与 `struct`/`enum` 的宽容度不一致 | 极低（规约加可选 `;` + `accept(";")`） | P3 |

四条与能力缺口清单的对应：DF-1↔[G-8](language-capability-gaps.md)、DF-2↔[G-7](language-capability-gaps.md)、
DF-3↔[G-5](language-capability-gaps.md)、SB-1↔[G-6](language-capability-gaps.md)。

---

## 7 探针附录（`/tmp/ctgap3`，`ct v0.44.1`）

| 探针 | 命令 | 原始结果 |
| --- | --- | --- |
| `l1_typedef`（DF-3） | `ct l1_typedef.ct -o l1.c` | `l1_typedef.ct:1:21: error: unexpected token`，rc=1 |
| `l1_typedef`（build） | `ct build l1_typedef.ct -o out` | `l1_typedef.ct:1:1: error: unexpected token`，rc=1 |
| `l1b_struct_fwd` | `ct` + `cc` + run | rc 全 0（`struct JVal;` + `struct JVal *` 可用） |
| `l1c_typedef_body` | 同上 | rc 全 0（`typedef struct JVal { … } JVal;` 可用） |
| `l1d_mutual` | 同上 | rc 全 0（互相引用，指针写 `struct B *`） |
| `l2_impl_semicolon`（SB-1） | `ct l2.ct -o l2.c` | `l2_impl_semicolon.ct:9:2: error: expected a type (tok 4 ';')`，rc=1 |
| `l3_macro_continuation`（DF-2） | 同上 | `l3_macro_continuation.ct:2:6: error: expected a type (tok 4 '(')`，rc=1 |
| `l4_long_macro`（DF-1） | `ct l4.ct -o l4.c` | rc=0；生成 C 第 11 行 159 字节（源 510）；`cc` → `l4.c:156:13: error: expected expression`，rc=1 |
| `l4_long_macro`（build） | `ct build l4.ct -o out` | 前端无报错，失败在 `cc`；报错经 `#line` 映回源 1:155 |
| `l5_num_macro` | `ct` + `cc` | `ct` rc=0；`cc`：`integer literal is too large to represent`（221 位十进制字面量被截断后越界） |
| `l6_valid_trunc` | `ct` + `cc` + run | rc 全 0；返回 `3`（源码语义 `6`） |
| `ctc` 对照（DF-1/2/3） | `ctc <file>.ct -o <file>.c` | `l1`/`l3`/`l4` rc=0；`l4` 生成物保留 510 字节宏，`cc` + run rc=0 |
| `ctc` 对照（SB-1） | 同上 | `l2_impl_semicolon.ct:5:8: error: expected 'for' in impl of 'J'`，rc=1（L0 不接受固有 impl） |
