# battle/hw-2 反证（REVIEW）

- HEAD：`369a2606`（v0.63.0）。只读基线：`/tmp/p0/ct-now`（同 HEAD 构建）。
- 立场：位置 A（`builtin_live_for` 三条近似已满足 REQ-HW-011）**不成立**。
- 一句话：`strstr` 判据同时**多判**（`struct Struct` / `String` / `Strlen` / 注释 / 字面量）与**漏判**
  （>262143 B 文件、小写内置 API 路径）可复现；J-1 / J-2 / J-4 三条判据均不成立。
- 工作树只改 `battle/hw-2/counter.md`；夹具与产物全在 `/tmp/hw2-counter/`。

## E1 可复制命令 + 原始输出

所有命令在 `/tmp/hw2-counter` 下执行；`/tmp/p0/ct-now` 为 HEAD 构建的 ct-ast。

### C1 基线：最小程序不拉内置层（对照组）

```console
$ mkdir -p fp/out_min && cd /Users/samxx/dsh-ws/ct-lang && /tmp/p0/ct-now build --emit-c /tmp/hw2-counter/fp/min.ct -o /tmp/hw2-counter/fp/out_min && ls /tmp/hw2-counter/fp/out_min
cc -std=c99 -I /tmp/hw2-counter/fp/out_min /tmp/hw2-counter/fp/out_min/min.c -o a.out
min.c
exit=0
```

### C2 误命中 1：只有 `struct Struct`，产物不引用任何 `Str*` 符号，仍拉入 `Str.c`

```console
$ mkdir -p fp/out_struct && cd /Users/samxx/dsh-ws/ct-lang && /tmp/p0/ct-now build --emit-c /tmp/hw2-counter/fp/struct.ct -o /tmp/hw2-counter/fp/out_struct && ls /tmp/hw2-counter/fp/out_struct
cc -std=c99 -I /tmp/hw2-counter/fp/out_struct /tmp/hw2-counter/fp/out_struct/Str.c /tmp/hw2-counter/fp/out_struct/struct.c -o a.out
Str.c
Str.h
struct.c
exit=0
```

`struct.c` 的目标文件**没有任何未定义符号**，`Str.o` 却带 10 个全局 `T` 符号：

```console
$ cc -c -std=c99 -I fp/out_struct fp/out_struct/struct.c -o fp/out_struct_objs/struct.o
$ cc -c -std=c99 -I fp/out_struct fp/out_struct/Str.c -o fp/out_struct_objs/Str.o
$ nm -u fp/out_struct_objs/struct.o
（空输出，exit=0）
$ nm -g fp/out_struct_objs/Str.o | grep -c " T "
10
$ ls -l fp/out_struct/Str.c fp/out_struct/struct.c fp/out_struct_objs/Str.o fp/out_struct_objs/struct.o | awk '{print $5, $9}'
3089 fp/out_struct/Str.c
478 fp/out_struct/struct.c
2808 fp/out_struct_objs/Str.o
536 fp/out_struct_objs/struct.o
```

### C3 误命中 2：一句注释即拉入 `Str.c`

```console
$ mkdir -p fp/out_comment && cd /Users/samxx/dsh-ws/ct-lang && /tmp/p0/ct-now build --emit-c /tmp/hw2-counter/fp/comment.ct -o /tmp/hw2-counter/fp/out_comment && ls /tmp/hw2-counter/fp/out_comment
cc -std=c99 -I /tmp/hw2-counter/fp/out_comment /tmp/hw2-counter/fp/out_comment/Str.c /tmp/hw2-counter/fp/out_comment/comment.c -o a.out
Str.c
Str.h
comment.c
exit=0
```

同样的误命中在 `struct String`、`int Strlen(...)`、字符串字面量 `"Str"` 三个夹具上逐条复现（`fp/string.ct`、
`fp/strlen.ct`、`fp/literal.ct`，输出形状与 C3 相同，均含 `Str.c Str.h`，exit=0）。

### C4 天然样本：仓库既有用例 `test/ast/165_vec_subscript`（只有 `Vec<int>`）也拉 `Str.c`，而产物不要它

```console
$ mkdir -p fp/out_vec165 && cd /Users/samxx/dsh-ws/ct-lang && /tmp/p0/ct-now build --emit-c test/ast/165_vec_subscript/prog.ct -o /tmp/hw2-counter/fp/out_vec165 && ls /tmp/hw2-counter/fp/out_vec165
cc -std=c99 -I /tmp/hw2-counter/fp/out_vec165 /tmp/hw2-counter/fp/out_vec165/Vec.c /tmp/hw2-counter/fp/out_vec165/Str.c /tmp/hw2-counter/fp/out_vec165/prog.c -o a.out
Str.c
Str.h
Vec.c
Vec.h
prog.c
exit=0
$ cd /tmp/hw2-counter/fp/out_vec165 && cc -Wall -Wextra -std=c99 Vec.c prog.c -o vec_nostr && ./vec_nostr
3
exit=0
```

即：去掉 `Str.c` 后产品照常链接、照常输出 `3` —— `Str` 对该程序毫无用处。

### C5 漏判 1（硬）：`Str` 唯一出现在偏移 262290，文件 262353 B → 判死，产物编译失败

```console
$ mkdir -p fn/out_big && cd /Users/samxx/dsh-ws/ct-lang && /tmp/p0/ct-now build --emit-c /tmp/hw2-counter/fn/big.ct -o /tmp/hw2-counter/fn/out_big && ls /tmp/hw2-counter/fn/out_big
cc -std=c99 -I /tmp/hw2-counter/fn/out_big /tmp/hw2-counter/fn/out_big/big.c -o a.out
big.c
exit=0
$ cd /tmp/hw2-counter && wc -c fn/big.ct && grep -bo Str fn/big.ct | head -1
  262353 fn/big.ct
262290:Str
exit=0
$ cd /tmp/hw2-counter && cc -Wall -Wextra -std=c99 fn/out_big/*.c -o fn/out_big/bin
/tmp/hw2-counter/fn/big.ct:7:16: error: variable has incomplete type 'struct Str'
    7 |     struct Str s;
      |                ^
/tmp/hw2-counter/fn/big.ct:2:8: note: forward declaration of 'struct Str'
    2 | struct Str;
      |        ^
1 error generated.
exit=1
```

对照组：同内容去掉填充（84 B）后 `Str.c` 正常拉入。

```console
$ mkdir -p fn/out_small && cd /Users/samxx/dsh-ws/ct-lang && /tmp/p0/ct-now build --emit-c /tmp/hw2-counter/fn/small.ct -o /tmp/hw2-counter/fn/out_small && ls /tmp/hw2-counter/fn/out_small
cc -std=c99 -I /tmp/hw2-counter/fn/out_small /tmp/hw2-counter/fn/out_small/Str.c /tmp/hw2-counter/fn/out_small/small.c -o a.out
Str.c
Str.h
small.c
exit=0
```

这正是 `file_mentions` 的 `static char buf[262144]` + `fread(buf, 1, sizeof buf - 1, f)`（Module.h.ct:201、208）
的截断：扫描窗只有 262143 B。

### C6 漏判 2（准）：不写 `Str` 字样、只调内置小写 API → `ct` 退出 0、产物缺 `Str.c`、`cc` 报未声明

```console
$ mkdir -p fn/out_raw2 && cd /Users/samxx/dsh-ws/ct-lang && /tmp/p0/ct-now build --emit-c /tmp/hw2-counter/fn/raw2.ct -o /tmp/hw2-counter/fn/out_raw2 && ls /tmp/hw2-counter/fn/out_raw2
cc -std=c99 -I /tmp/hw2-counter/fn/out_raw2 /tmp/hw2-counter/fn/out_raw2/raw2.c -o a.out
raw2.c
exit=0
$ cd /tmp/hw2-counter && cc -Wall -Wextra -std=c99 fn/out_raw2/*.c -o fn/out_raw2/bin
/tmp/hw2-counter/fn/raw2.ct:8:9: error: call to undeclared function 'str_from_len'; ISO C99 and later do not support implicit function declarations [-Wimplicit-function-declaration]
    8 |     if (str_from_len("abcd", 4)) { Str_Drop_drop(str_from_len("abcd", 4)); free(str_from_len("abcd", 4)); }
      |         ^
/tmp/hw2-counter/fn/raw2.ct:8:50: error: incompatible integer to pointer conversion passing 'int' to parameter of type 'void *' [-Wint-conversion]
    8 |     if (str_from_len("abcd", 4)) { Str_Drop_drop(str_from_len("abcd", 4)); free(str_from_len("abcd", 4)); }
      |                                                  ^
exit=1
```

注意同名 `.c` 第 7–8 行是 `struct Str;` 与 `extern void Str_Drop_drop(void *self);`：**发射器认为需要
`Str` 的 Drop 符号，判活扫描却判死** —— 前端与判活自相矛盾。此样本同时撞上
`delete <非标量表达式>` 的另一缺陷（补上 `Str.c` 后 C 报 `if (str_from_len(...))` 类型错），故只作
「准漏判」，不计入 J-1 的硬反例；硬反例见 C5。

### C7 官方探针现状（主张席 E3 引用的那一条）

```console
$ cd /Users/samxx/dsh-ws/ct-lang && bash test/ast/p64_on_demand.sh /tmp/p0/ct-now
OK p64ond
exit=0
```

它绿，但两个夹具（`p64_on_demand.sh` 的 `min/m.ct` 含 `return 0;`、`opt/o.ct` 含 `Option<int>`）**不含
`Str` 子串**，`file_mentions` 对它们根本不会触发 —— 对本争点零敏感度（见 E4）。

### C8 反证探针（J-4）：一条按「实际使用拉取」写的探针在现状下红

`/tmp/hw2-counter/probe_str_live.sh`：真使用必须拉 `Str.c`；`struct String` / `Vec<int>` / >262143 B 三例
必须不拉（后两例含「>262143 B 必须拉」的正向断言）。

```console
$ cd /tmp/hw2-counter && bash probe_str_live.sh /tmp/p0/ct-now
FAIL probe: 'struct String' pulled Str.c
FAIL probe: Vec<int> pulled Str.c
FAIL probe: Str use past byte 262143 was missed
exit=1
```

## E2 `file:line` 锚点

支持己方：

| 锚点 | 内容 | 作用 |
| --- | --- | --- |
| `selfhost/ct-ast/frontend/module/Module.h.ct:2031` | `int builtin_live_for(int u)` | 争点入口 |
| `selfhost/ct-ast/frontend/module/Module.h.ct:2047-2049` | `strcmp(base,"Str")==0 && (strstr(ins[i].ctype[0],"Str") \|\| strstr(ins[i].carg[0],"Str"))` | 实例判据是子串匹配，且只看第 0 个类型参数 |
| `selfhost/ct-ast/frontend/module/Module.h.ct:2051-2054` | `file_mentions(self->units[i].path, "Str")` | 源码判据只有「出现即命中」 |
| `selfhost/ct-ast/frontend/module/Module.h.ct:199-211` | `static int file_mentions(...)`，`buf[262144]`、`fread(...sizeof buf - 1...)`、`strstr` | 误命中与截断漏判的同一实现点 |
| `lib/std/Str.h.ct:18-29` | `pub struct Str { char *data; int len; } use Drop;` + `impl Drop for Str` | 判活失败时缺的正是结构定义与 Drop 符号（C5 报错内容） |
| `lib/std/Vec.h.ct:31-38` | `struct ct_buf` / `pub struct Vec<T>` | `Vec<int>` 不需要 Str 的对照依据 |

**不利于己方（必须列）**：`selfhost/ct-ast/frontend/module/Module.h.ct:2055-2058`

```c
for (i = 0; i < self->nbuiltin; i++)
    if (strcmp(self->units[self->builtin_units[i]].base, "Vec") == 0
        && self->builtin_live[i])
        return 1;
```

这一条覆盖的是一条**真实依赖**：`lib/std/Vec.h.ct:466` 的 `impl<V> Map<Str, V>` 在 `lib/std/Vec.h.ct:492/496`
调用 `Str_retain` / `Str_release`，故「`Map<Str,V>` 被实例化」确实需要 `Str.c`。
但它按单元粒度 blanket 成立，不按实例：C4 实测 `Vec<int>` 的 `Vec.o` 不含 `Str_*` 未定义符号，产品去掉
`Str.c` 仍链接运行。所以这一行既证明「存在真实跨单元边」，也证明该边被超额保留——对主张席是半个支持，
对整个判据是成本证据。

## E3 可证伪预测

- **P1**：若位置 A 成立（「只按实际使用/实例化拉取」），`fp/string.ct`（只声明 `struct String`，产物不
  引用任何 `Str*` 符号）应只产出 `string.c`。**实测**：产出 `Str.c` + `Str.h`（C2/C3 同形），预测被证伪。
- **P2**：若 J-1 成立（完备性），`fn/big.ct` 应产出 `Str.c` 且 `cc` 退出 0。**实测**：只有 `big.c`，
  `cc` 退出 1 报 `incomplete type 'struct Str'`，预测被证伪。
- **P3**：若 J-4 成立（可机械检测），存在一条在现状下为绿、且能区分「真使用」与「子串误命中」的探针。
  **实测**：`probe_str_live.sh` 在 3 个用例上红、仅真使用用例绿（exit=1），预测被证伪。唯一能绿的写法
  是把「`String` 拉 `Str.c`」写进断言，那等于把 J-2 的违反固化成门禁。
- **P4（可被对方一次推翻的强预测）**：任何 ≥256 KB 的 `.ct` 单元，只要其 `Str` 首次出现于 262144 B 之后，
  就判死。`fn/big.ct` 是样本；若对方能构造出该形态而 `Str.c` 仍被拉入，本条即伪。

## E4 代价量化（维持现状、不修）

可测口径（均在 C2/C4 实测）：

| 项 | 量 |
| --- | --- |
| 误判拉入的单元数 | 每次构建多 2 个文件（`Str.c` + `Str.h`） |
| 产物体积 | +3089 B C 源；+2808 B 目标文件；`Str.o` 带 10 个全局 `T` 符号进链接 |
| 触发面 | 任一同前缀标识符（`Struct`/`String`/`Strlen`）、注释、字符串字面量、任一 `Vec`/`Map` 实例化（C4，仓库既有用例即触发） |
| 反方向代价 | 漏判不产生「多一个单元」，而产生产物编译失败（C5 `exit=1`），且 `ct` 自身 `exit=0` 无诊断 |
| 对 E3 探针断言强度 | `p64_on_demand.sh` 夹具无 `Str` 子串，`file_mentions` 不触发 → 该探针对本争点断言强度为 0；真正的探针在现状下 `exit=1`（C8） |

主张席 E4 漏掉的成本项：

1. **漏判类代价未计入**：位置 A 只讨论「多保留一个单元」。C5 显示同一 `strstr` 也会**少保留**，代价是
   下游 C 编译失败、`ct` 退出 0 无诊断 —— 这是错误产物类，不是体积类。
2. **扫描窗截断**：`buf[262144]`（Module.h.ct:201/208）使判据在 >262143 B 文件上失效；仓库现已有两个
   超过该尺寸的单元（`selfhost/ct-ast/frontend/parse/Expr.h.ct` 355536 B、
   `selfhost/ct-ast/backend/emit/Emitter.h.ct` 304182 B），该类文件不是极端假设。
3. **`Vec` 活 ⇒ `Str` 活 的 blanket 成本**：每个 `Vec`/`Map` 用户都被加 3089 B 与 10 个符号，即使元素
   类型非 `Str`（C4）。这一条是主张席引为「真实依赖」的那一行自身的超额部分。
4. **粒度耦合成本**：判据对象是「子串」而不是「标识符」，任何无关改动（新增 `String`/`Strlen` 命名、
   改注释、改字面量）都会改变内置层产物集合 → 产物对无关改动敏感，golden/增量比较被动。
5. **探针自证的成本**：主张席把「E3 探针已钉住两条主线」当作已覆盖，但该探针不覆盖本争点，等于用零
   敏感度的门禁为判据背书。

若要求改：改动文件/行数不计入己方举证义务；本席不提替代方案（§7.9：`rejected` 不等于反对席方案成立）。

## E5 steelman 与逐点回应

主张席最强原文（`battle/hw-2/question.md` 位置 A）：

> 首版近似满足 J-1——`Str` 的所有真实使用路径都先命中三条判据之一（Vec 活、源码出现该标识符、实例参数
> 出现）；`strstr` 的冗余只会**多保留**一个单元，不产生错值，且 E3 探针（`test/ast/p64_on_demand.sh`）
> 已钉住「最小程序只有自身 `.c`」与「`Option<int>` 只拉 `Option`」两条主线。改符号级引用位要动
> `frontend/sym` 的解析路径，代价大于收益。

逐点回应：

1. 「所有真实使用路径都先命中三条判据之一」——**假**。C5：唯一 `Str` 在偏移 262290，三条判据全不命中，
   但程序真实使用 `Str`；C6：只用小写 `str_from_len` 的路径同样全不命中（尽管叠加了另一缺陷）。
2. 「`strstr` 的冗余只会多保留一个单元，不产生错值」——**半句已被推翻**。同一 `strstr` 在 C5 上给出
   少保留，错值是「产物缺 `Str` 定义」，不是体积。且「多保留」本身即 J-2 的违反：E1（C2–C4）给出 4 个
   可复现样本，误命中不是边缘，是 `strstr` 语义的直接后果。
3. 「E3 探针已钉住两条主线」——**无关**。该探针两个夹具（`p64_on_demand.sh:16-20`、`23-28`）不含 `Str`
   子串，对本争点零敏感度；它钉住的是 `Vec`/`Option`/`Result` 三条实例判据，恰好绕开了争议的那一条。
4. 「改符号级引用位代价大于收益」——**不满足 §7.7 E4**。主张席没给 `git diff --stat`、行数、受影响门禁
   清单、回退步骤，只有定性判断；且未计入 E4 表里 5 项现状成本。代价比较因此不成立，不能作为「维持
   现状」的理由。
5. 对主张席唯一成立的点（诚实记录）：`Vec` 活 ⇒ `Str` 活 这一行确实覆盖了真实跨单元边
   （`Module.h.ct:2055-2058` + `lib/std/Vec.h.ct:466/492/496`），不是凭空近似。但它按单元而非按实例，
   C4 实测超额；J-5（不以容器名单判活）主张席也确实满足。

## 判据逐条结论

| ID | 结论 | 依据 |
| --- | --- | --- |
| J-1 | **不成立** | C5：>262143 B 文件判死，`cc` 退出 1；C6 为叠加另一缺陷的准反例 |
| J-2 | **不成立** | C2/C3/C4：4 类可复现误命中，产物未引用任何 `Str*` 符号仍拉 `Str.c` |
| J-3 | 不计入（代价项见 E4，供裁判席用） | — |
| J-4 | **不成立** | C7 的官方探针零敏感度；C8 的探针在现状下 `exit=1`；能绿的写法只能固化 J-2 违反 |
| J-5 | 成立（对主张席有利） | 实现与主张文本均无容器名单 |

## 失效条件清单（逐条可复现）

主张「三条近似已满足 REQ-HW-011」在下列任一条件下不成立：

1. 单元源码 >262143 B，且 `Str` 首次出现于偏移 ≥262143 → 判死，产物缺 `Str` 定义。
   复现：`fn/big.ct`（C5）。
2. 源码出现 `Str` 子串但程序不使用 `Str` → 判活。复现：`fp/struct.ct`、`fp/string.ct`、`fp/strlen.ct`、
   `fp/comment.ct`、`fp/literal.ct`（C2/C3）。
3. 任一 `Vec`/`Map` 实例化且元素类型非 `Str` → 判活。复现：`test/ast/165_vec_subscript/prog.ct`（C4）。
4. 调内置小写 API（`str_from_len` 等）而不写 `Str` 字样 → 判死（并叠加另一缺陷）。
   复现：`fn/raw2.ct`（C6）。
5. 新增任何以 `Str` 开头的标识符（类型、函数、注释、字面量）→ 内置层产物集合随之变化，与是否使用
   `Str` 无关。复现：同 2，`fp/string.ct` 与 `fp/min.ct` 的唯一差异是一个标识符名。
6. 判据依赖文件可读：`file_mentions` 的 `fopen` 失败即返回 0（Module.h.ct:203-205）→ 判死。
   未实测（需构造不可读单元）；列出以备证据席复现。

## 夹具

```console
$ cat /tmp/hw2-counter/fp/min.ct
int main(void)
{
    return 0;
}
$ cat /tmp/hw2-counter/fp/struct.ct
struct Struct { int x; };

int main(void)
{
    struct Struct s;
    s.x = 1;
    return s.x - 1;
}
$ cat /tmp/hw2-counter/fp/string.ct
struct String { char *p; };

int main(void)
{
    struct String s;
    s.p = 0;
    return s.p != 0;
}
$ cat /tmp/hw2-counter/fp/comment.ct
/* This program never mentions the built-in type; the scanner sees this
   comment word: Str. */
int main(void)
{
    return 0;
}
$ cat /tmp/hw2-counter/fn/small.ct   # C5 对照组；big.ct = 262269 B 注释填充 + 同一函数体
int main(void)
{
    Str s;
    s.data = 0;
    s.len = -1;
    return s.len + 1;
}
$ cat /tmp/hw2-counter/fn/raw2.ct
#include <stdlib.h>

int main(void)
{
    delete str_from_len("abcd", 4);
    return 0;
}
```

`big.ct` 由 `/tmp/hw2-counter` 下的 python 一行生成（`/* xxx... */` 填充至 262269 B 再拼 `small.ct` 的
函数体）；`probe_str_live.sh` 同目录。
