# battle/p39-1 主张书（REQ，立场 A）

| 字段 | 值 |
| --- | --- |
| 争点 | `ct build --lib` 的导出面选择机制：A（`pub` 即导出，非 C 兼容即硬错 L39-1） vs B（显式标记/清单） |
| 主张席 | REQ（独立上下文，只代表 A） |
| 锚定 HEAD | `ac040d17f0bfcebe5bea042bcd6d07070dc05978`（2026-11-13） |
| 编译器 | `/tmp/p39head/ct`，`ct v0.37.0`，sha256 `080650f62e4fa894efc672c10a14a615bdaa531bdef5f24470e99fb37e59dd10`（由 HEAD `ac040d1` 干净归档构建） |
| 干净源码 | `/tmp/p39head/src`（HEAD 归档，无 `.git`；只在此树取输入与生成物） |
| 环境 | `Darwin arm64`；`Apple clang version 21.0.0 (clang-2100.4.1.1)` |
| 证据可复现性 | 下列每条命令只读 `/tmp/p39head/**` 与 `/tmp/p39claim/**`，不读工作树；工作树对 `lib/std`、`test/modules`、`docs/design/phase39-draft.md`、`AGENTS.md` 的 `git status --porcelain` 为空（锚点行号与 HEAD 一致） |

> 本席只写 `battle/p39-1/claim.md` 与 `/tmp/p39claim/**`，未改动任何源码或文档。

---

## 1 方案一句话与 §3.1 对应

### 1.1 方案

**A：`ct build --lib` 的导出面 = 本次构建所有非内建 `.h.ct` 单元里「有定义」的 `pub` 函数；签名不满足 C 兼容（内建标量 / `void` / 指针 / 数组参数之外）即报 L39-1 硬错，位置在声明行，不写任何产物。**

`pub` 就是导出意图的唯一声明处：`.h.ct` 单元是包的公开头，`pub` 是 Phase 34 起的包级可见性。C ABI 库不需要第二套可见性，因为 C 侧能看到的函数集合本来就只能是 C 能表达的那些。

### 1.2 与 PH-39 §3.1 的逐条对应

| A 的规则 | §3.1 条款（`docs/design/phase39-draft.md`） | 判据 | 落点 |
| --- | --- | --- | --- |
| 范围：非内建 `.h.ct` 单元 | §3.1 规则 1「声明在**非内建** `.h.ct` 单元」 | 内建 std 单元不进导出面 | `docs/design/phase39-draft.md:100` |
| 资格：`pub` 且有定义 | §3.1 规则 1「带 `pub`，且本构建内有定义（`Func.body >= 0`）」 | 排除 `pub extern`（D39-2）与仅原型 | 同上 |
| 类型白名单 | §3.1 规则 2「内建标量、`void`、指针（含指向具名 struct 的指针、函数指针）、数组参数（decay 成指针）」 | 只有这四类可进 `.abi.h` | `docs/design/phase39-draft.md:101` |
| 类型黑名单 → L39-1 | §3.1 规则 3「按值 struct/union、trait/接口值（`*_iface`）、泛型参数、`Vec`/`Map`/`Option`/`Result`/`Str` 等 std 类型、`own`」 | 命中即 L39-1，不写产物 | `docs/design/phase39-draft.md:102`、`:134` |
| 诊断 | §3.4 L39-1 `'<name>' cannot be exported: <reason>` | `file:line:col` + 原因 | `docs/design/phase39-draft.md:134` |

结论：**A 不是新提案，而是 PH-39 §3.1 的直接读法**；本庭要裁的是「A 的硬错 vs B 的标记」这一处，不是重写 §3.1。

### 1.3 边界（不在本庭裁）

- 按值 struct / `pub` 全局 / `main` / `.m.ct` shim 已由用户定（D39-6 / D39-7），本席不借 A 扩张它们。
- `.a` 产物、`ar` 确定性、visibility（O1/O3）属 PH-39 R1/R4/R5，不是本庭的「选择机制」，E4 里分开算。

---

## 2 J-1…J-5 主张

| ID | 判据 | 本席主张 | 一句话证据 |
| --- | --- | --- | --- |
| J-1 | 意图一致：`.abi.h` 导出集合 = 作者明确要导出的集合；三个夹具不被误杀 | **成立，但须按 C-ABI 语义读**：f1 导出 2/2；f2/f3 的 `pub` 不是 C 可表达者，A 判死是 §3.1 的显式设计；若裁判采用「任何 `pub` 都不得判死」的字面读法，J-1 对 f2/f3 不成立——本席不隐瞒 | §3.1 规则 3；f2/f3 的 `--emit-c` 今天已把泛型/trait 从生成头里静默剔除（E1-2、E1-4） |
| J-2 | 既有 `.h.ct` 零语法改动即可构成 `--lib` 库 | **成立**（零 `.ct` 语法改动）；但 69 个 `.h.ct` 中 5 个单元含 12 个 A 会拒绝的 `pub` 函数，它们做不了 `--lib` 根——这也是字面口径下的漏洞，见 E2 不利锚点 | E1-3 统计：53 个 `pub` 函数声明，12 个非 C 兼容，3 个待定 |
| J-3 | 语言面最小：不新增关键字/语法 | **成立**：A 只新增 `--lib` 一个 CLI 选项（PH-39 已立项、用户已批准冻卡），不加关键字、不加语法 | `docs/design/phase39-draft.md:16`；`AGENTS.md:469`（新增语法/CLI 须用户确认） |
| J-4 | 实现成本 ≤2 文件 / ≤80 行；不改 G1/G3/G4 判据 | **成立（限「选择机制」切片）**：`Module.h.ct`（扫描 + 类型判定 + L39-1 + `.abi.h` 原型集合）与 `Driver.h.ct`（`--lib` 解析/分派/互斥）两个文件，机制增量 ≤80 行；`.a`/ar/visibility 属 O1/O3，另计 | §1.3、E4 |
| J-5 | 可诊断：被拒签名必须 `file:line:col` + 原因，不得静默丢弃 | **成立**：A 的失败路径是硬错并带位置；编译器已有该格式（E1-5） | E1-5 |

**逐条展开：**

- **J-1。** 判据要的是「导出集合 = 作者明确要的集合」。A 把「明确」落在 `pub` 上：`.h.ct` 的 `pub` 是包级公开 API，C ABI 是该 API 的 C 子集。f1 的 2 个 `pub` 全部 C 兼容，A 导出 2/2；f2 的 `id<T>`、f3 的 `Sink` 返回值在 C 里根本不存在对应类型，作者若声称要导出它们，这个意图本身不可实现（B 也导不出，只能静默省略）。因此 A 的「判死」不是误杀，而是拒绝为一个不可实现的 ABI 承诺签字。**若判据成立需要什么输出**：三夹具各一次 `--lib` 构建，`f1` 的 `.abi.h` 原型集合恰好 2 个且无 `_iface/_vtbl/Vec_/Map_`；`f2`/`f3` 非零退出且首条诊断为 `f2/lib.h.ct:3:<col>`、`f3/lib.h.ct:22:<col>` 的 L39-1（E3 即此预测）。
- **J-2。** 判据问的是「语法改动」，不是「任何单元都能当 C 库」。今天 53 个 `pub` 函数里 38 个 C 兼容、12 个不兼容、3 个待定（E1-3）；不兼容者集中在 `lib/std/Str.h.ct` 与 4 个 CT 包/夹具单元，它们本来就不是 C ABI 库。A 不要求改任何 `.h.ct` 的一行语法，只要求「不要把不可 C 表达的单元当 `--lib` 根」。**若判据成立需要什么输出**：`grep` 统计（E1-3）+ 一个 C 兼容单元 `--lib` 成功、导出数 = 该单元 C 兼容 `pub` 数。
- **J-3。** A 的唯一语言面变化是 `--lib` 选项，PH-39 §3.2 已固定其形态；没有 `pub export`、没有清单文件、没有新关键字。B 的 `pub export` 直接撞 `AGENTS.md:469`「新增语法、改变命名、改变 CLI 必须先向用户说明方案并获得确认」，而本庭材料里没有这份批准。**若判据成立需要什么输出**：方案文本 + 上述锚点；负向证据是 B 的语法提案在 `docs/design/**` 中不存在。
- **J-4。** 本争点的机制增量只有「扫 `pub` + 判类型 + 报 L39-1 + 把原型写进 `.abi.h`」，落在 `Module.h.ct`；`Driver.h.ct` 只加选项解析与模式互斥。≤2 文件 / ≤80 行。**若判据成立需要什么输出**：改动清单（文件 + 行数上限）与回退步骤，见 E4；G1/G3/G4 的既有判据零改动，新增用例只挂在 `check-ast.sh` 的 p39 段。
- **J-5。** A 的拒绝是硬错：`'<name>' cannot be exported: <reason>` 带声明行 `file:line:col`，不产出 `.abi.h`/`.a`。B 的「未标记 `pub` 不导出也不报错」恰好是静默丢弃：作者写了 `pub`，产物里没有，构建还绿。**若判据成立需要什么输出**：三条负例（按值 struct / trait 值 / 泛型）各一条 `file:line:col: error:` 原文，见 E3 的预测形态与 E1-5 的既有格式。

---

## 3 E1：完整命令 + 原始输出

> 二进制：`/tmp/p39head/ct`（sha256 见文首），源码：`/tmp/p39head/src`（HEAD `ac040d1` 归档）。以下均在 `/tmp/p39head/src` 下执行；`/tmp/p39claim/**` 为本席临时目录。

### E1-1 今天的 `ct build --lib` 行为（HEAD 原样）

```console
$ cd /tmp/p39head/src
$ /tmp/p39head/ct build --lib test/modules/p34_pub_generic/lib.h.ct; echo "exit=$?"
ctc: unknown option '--lib'
exit=1
```

即：`--lib` 今天不存在，PH-39 §2.2 的基线可复现；本庭裁的是它的实现方式，不是它是否存在。

### E1-2 现状：`--emit-c` 已把泛型 `pub` 从生成头里静默剔除（B 式行为）

```console
$ mkdir -p /tmp/p39claim/out_repo
$ /tmp/p39head/ct build --emit-c test/modules/p34_pub_generic/lib.h.ct --outdir /tmp/p39claim/out_repo; echo "exit=$?"
cc -std=c99 -I /tmp/p39claim/out_repo /tmp/p39claim/out_repo/Vec.c /tmp/p39claim/out_repo/Option.c /tmp/p39claim/out_repo/Result.c /tmp/p39claim/out_repo/Str.c /tmp/p39claim/out_repo/lib.c -o a.out
exit=0
$ cat /tmp/p39claim/out_repo/lib.h
#ifndef LIB_H
#define LIB_H

/* Generated by ct v0.37.0 from test/modules/p34_pub_generic/lib.h.ct (multi-file mode: exported types; the matching .c
   includes this header).
   Generated output is not covered by the GPL and may be used without restriction (LICENSE.EXCEPTION). */

#include "Vec.h"
#include "Option.h"
#include "Result.h"
#include "Str.h"

struct ct_buf;
struct Str;
long from_lib(long);

#endif
```

`lib.h` 里只有 `from_lib`，`pub T id<T>(T x)`（`lib.h.ct:3`）一个字都没有，也没有任何诊断。这正是 B 的「未标记/不可导出就不导出、不报错」的现状形态；A 要把这个静默变成 L39-1。

### E1-3 现有 `.h.ct` 中 `pub` 函数的 C 兼容性统计（干净 HEAD 归档）

```console
$ cd /tmp/p39head/src
$ grep -rnE '^\s*pub .*\(' --include='*.h.ct' lib/std test/modules | grep -vE '^[^:]+:[0-9]+:pub (struct|trait|enum|union|extern)\b' > /tmp/p39claim/pubfns2.txt
$ echo "pub function declarations = $(wc -l < /tmp/p39claim/pubfns2.txt)"
pub function declarations =       53
$ grep -E '\bStr\b|<[A-Za-z_][^>]*>\(|:pub (Writer|Stream) ' /tmp/p39claim/pubfns2.txt
lib/std/Str.h.ct:33:pub Str str_from_len(const char *p, int n)
lib/std/Str.h.ct:51:pub Str str_from(const char *s)
lib/std/Str.h.ct:63:pub int str_len(Str s)
lib/std/Str.h.ct:70:pub Str str_slice(Str s, int start, int n)
lib/std/Str.h.ct:80:pub Str str_concat(Str a, Str b)
lib/std/Str.h.ct:99:pub int str_compare(Str a, Str b)
lib/std/Str.h.ct:117:pub char *str_c_str(Str s)
test/modules/ns_types/hal/uart.h.ct:22:pub Writer open_uart(void) {
test/modules/p34_pub_bound/lib.h.ct:21:pub T id<T>(T x)
test/modules/p34_pub_bound/lib.h.ct:26:pub T max2<T: Compare>(T a, T b)
test/modules/xunit_box/net.h.ct:22:pub Stream stream_open(void) {
test/modules/p34_pub_generic/lib.h.ct:3:pub T id<T>(T x)
$ echo "count = $(grep -cE '\bStr\b|<[A-Za-z_][^>]*>\(|:pub (Writer|Stream) ' /tmp/p39claim/pubfns2.txt)"
count = 12
$ grep -E '\(Point p\)' /tmp/p39claim/pubfns2.txt | wc -l
       3
$ find lib/std test/modules -name '*.h.ct' | wc -l
      69
```

分类（判据 = §3.1 规则 2/3 的类型白名单/黑名单；`grep` 只负责列出候选行，分类按规范文本人工核对）：

| 类 | 数量 | 位置 |
| --- | --- | --- |
| 纯 C 兼容（内建标量 / `void` / 指针 / 数组参数） | 38 | 其余单元 |
| 按值 `Str`（§3.1 规则 3 的 std 类型） | 7 | `lib/std/Str.h.ct:33,51,63,70,80,99,117` |
| 泛型参数（`<T>` / `<T: Compare>`） | 3 | `test/modules/p34_pub_generic/lib.h.ct:3`、`test/modules/p34_pub_bound/lib.h.ct:21,26` |
| trait/接口值（`Writer` / `Stream` 返回） | 2 | `test/modules/ns_types/hal/uart.h.ct:22`、`test/modules/xunit_box/net.h.ct:22` |
| **A 会判死的小计** | **12** | **5 个单元：`lib/std/Str.h.ct`、`p34_pub_generic`、`p34_pub_bound`、`ns_types`、`xunit_box`** |
| 待定：`Point` 按值参数，`pub` 仅声明（定义行非 `pub`） | 3 | `test/modules/ns_qual/src/app/model.h.ct:9,15`、`test/modules/ns_bare_call/src/app/model.h.ct:7` |

补充边界：`test/modules/p29_generic_struct/shapes.h.ct:15` 的 `pub Vec<int> table[2];` 是 `pub` 全局，不属本统计（已由 D39-7 裁为 L39-4）；`pub extern` 按 D39-2 不入导出面，也不在本统计内。

### E1-4 泛型 / trait 的 `pub` 函数在 A 下的判死实例

实例 1（泛型 + 有定义，`lib.h.ct` 单元）：

`test/modules/p34_pub_generic/lib.h.ct:3` 是 `pub T id<T>(T x)`，函数体在第 4–6 行，**满足 §3.1 规则 1（非内建 `.h.ct` + `pub` + 有定义）**；签名含泛型参数，命中规则 3 → A 报 L39-1，构建整体不产 `.abi.h`。今天该单元 `--emit-c` 退出 0 且 `lib.h` 静默省略它（E1-2）。

实例 2（trait 约束泛型）：

`test/modules/p34_pub_bound/lib.h.ct:26` 是 `pub T max2<T: Compare>(T a, T b)`（同文件 `:21` 还有 `pub T id<T>(T x)`），同样是「非内建 `.h.ct` + `pub` + 有定义」；泛型参数 + trait 约束 → A 报 L39-1。今天：

```console
$ mkdir -p /tmp/p39claim/out_bound
$ /tmp/p39head/ct build --emit-c test/modules/p34_pub_bound/lib.h.ct --outdir /tmp/p39claim/out_bound; echo "exit=$?"
cc -std=c99 -I /tmp/p39claim/out_bound /tmp/p39claim/out_bound/Vec.c /tmp/p39claim/out_bound/Option.c /tmp/p39claim/out_bound/Result.c /tmp/p39claim/out_bound/Str.c /tmp/p39claim/out_bound/lib.c -o a.out
exit=0
$ cat /tmp/p39claim/out_bound/lib.h
#ifndef LIB_H
#define LIB_H

/* Generated by ct v0.37.0 from test/modules/p34_pub_bound/lib.h.ct (multi-file mode: exported types; the matching .c
   includes this header).
   Generated output is not covered by the GPL and may be used without restriction (LICENSE.EXCEPTION). */

#include "Vec.h"
#include "Option.h"
#include "Result.h"
#include "Str.h"

struct ct_buf;
struct Str;
struct Num;
struct Compare_vtbl {
    int (*cmp)(void *, void *);
};
struct Compare_iface {
    void *self;
    struct Compare_vtbl *vt;
};

extern struct Compare_vtbl Num_Compare_vtable;

struct Num {
    int v;
    struct Compare_vtbl *__compare_vptr;
};

#endif
```

生成头把 `Compare_vtbl` / `Compare_iface` / `Num_Compare_vtable` 都当「导出类型」放了进去，却没有 `id` / `max2` 的原型——A 的立场正是：这种半截 ABI 要么给错，要么别给。

实例 3（trait 值返回）：`test/modules/ns_types/hal/uart.h.ct:22` `pub Writer open_uart(void)`、`test/modules/xunit_box/net.h.ct:22` `pub Stream stream_open(void)`。二者都是「非内建 `.h.ct` + `pub` + 有定义」，返回值是 trait 接口值（C 里是 `*_iface` 结构体），命中 §3.1 规则 3 → L39-1。

### E1-5 诊断形态已存在（J-5 的机制证据）

```console
$ cd /tmp/p39head/src
$ /tmp/p39head/ct test/archive/errors/namespace_path_too_long.ct 2>&1 | head -2
test/archive/errors/namespace_path_too_long.ct:1:171: error: namespace is too long
```

A 的 L39-1 要沿用同一格式（`文件:行:列: error: 描述`），并在 §3.4 固定文案 `'<name>' cannot be exported: <reason>`。

### E1-6 J-1 的三个夹具（自建，源码在此，可原样复制重跑）

`/tmp/p39claim/f1_purec/lib.h.ct`：

```c
/* F1: pure C-compatible library unit. */
pub int lib_add(int a, int b)
{
    return a + b;
}

pub const char *lib_name(void)
{
    return "f1";
}
```

`/tmp/p39claim/f2_generic/lib.h.ct`：

```c
/* F2: C-compatible export plus a generic pub helper (as in
   test/modules/p34_pub_generic/lib.h.ct). */
pub T lib_id<T>(T x)
{
    return x;
}

pub int lib_add(int a, int b)
{
    return a + b;
}
```

`/tmp/p39claim/f3_trait/lib.h.ct`：

```c
/* F3: pub method on a trait type (as in test/modules/xunit_box/net.h.ct). */
pub trait Sink {
    int write(char *buf, int len);
}

pub struct FileSink {
    int fd;
} use Sink;

struct FileSink sink1;

impl Sink for FileSink {
    int write(char *buf, int len) {
        return len + self->fd + buf[0];
    }
}

pub Sink sink_open(void)
{
    Sink s;
    sink1.fd = 1;
    s = sink1;
    return s;
}
```

今天的构建（三夹具均只有 `pub` 函数、无 `main`，`--emit-c` 退出 0；`--lib` 全部 `unknown option`）：

```console
$ cd /tmp/p39claim && mkdir -p out_f1_purec out_f2_generic out_f3_trait
$ /tmp/p39head/ct build --emit-c f1_purec/lib.h.ct --outdir /tmp/p39claim/out_f1_purec; echo "exit=$?"
cc -std=c99 -I /tmp/p39claim/out_f1_purec /tmp/p39claim/out_f1_purec/lib.c -o a.out
exit=0
$ cat /tmp/p39claim/out_f1_purec/lib.h
#ifndef LIB_H
#define LIB_H

/* Generated by ct v0.37.0 from f1_purec/lib.h.ct (multi-file mode: exported types; the matching .c
   includes this header).
   Generated output is not covered by the GPL and may be used without restriction (LICENSE.EXCEPTION). */

int lib_add(int, int);
const char * lib_name(void);

#endif
```

| 夹具 | 作者在 C 层要导出的 | A 的导出集合 | 判定 |
| --- | --- | --- | --- |
| f1 纯 C 兼容 | `lib_add`、`lib_name` | 同集合（2/2） | 通过 |
| f2 含泛型 helper | `lib_add`；`lib_id<T>` 只给 CT 消费方 | L39-1 @ `f2/lib.h.ct:3`，整建失败 | 判死（见 2·J-1 与 E2 不利锚点） |
| f3 含 trait 值 | C 侧无对应类型 | L39-1 @ `f3/lib.h.ct:22`，整建失败 | 判死（同上） |

---

## 4 E2：HEAD 锚点

> 全部用 `git grep -n <pat> HEAD -- <path>` 取行号（HEAD = `ac040d1`），工作树同路径 `git status --porcelain` 为空。

### 4.1 支持 A 的锚点

| # | 锚点 | 内容 | 为何支持 A |
| --- | --- | --- | --- |
| S-1 | `docs/design/phase39-draft.md:16` | 「给 `ct build` 增加 `--lib`：…`.h.ct` 的 `pub` 函数即为 C ABI 导出面」 | PH-39 的目标本身把 `pub` 定义为 ABI 面；A 是唯一不需要第二套声明的读法 |
| S-2 | `docs/design/phase39-draft.md:98` + `:101` + `:102` | 「一个函数进入导出面，当且仅当…」三条件 | A 就是 §3.1，硬错是规则 3 的执行 |
| S-3 | `AGENTS.md:469` | 「涉及行为变更（新增语法、改变命名、改变 CLI）必须先向用户说明方案并获得确认」 | B 的 `pub export` 是新语法；没有用户批准证据 → J-3 对 B 不成立 |

### 4.2 不利于 A 的锚点（必须披露）

| # | 锚点 | 内容 | 对 A 的杀伤 |
| --- | --- | --- | --- |
| A-1 | `lib/std/Str.h.ct:51`（另见 `:33,63,70,80,99,117`） | `pub Str str_from(const char *s)` 等 7 个按值 `Str` 的 `pub` 定义 | 仓库自带的 std 库**不能**作为 `--lib` 根：A 报 7 条 L39-1。这是 J-2「不改一行即可构成 `--lib` 库」的字面反例，也是 B 的最强事实 |
| A-2 | `test/modules/p34_pub_generic/lib.h.ct:3` | `pub T id<T>(T x)`，有定义 | `pub` 是 P34 为「包级复用」引入的可见性（`phase34-draft.md:13`「让泛型能力从单单元自用变成**可被包复用**」、`:19` O1「`pub` 泛型函数」），A 把它重解释成 C ABI 承诺；一个用 `pub` 泛型做复用的 CT 包因此无法同时产出 C 库 |
| A-3 | `test/modules/p34_pub_bound/lib.h.ct:26` | `pub T max2<T: Compare>(T a, T b)`，有定义 | 同上，且带 trait 约束，B 的「未标记不导出」能保住该包，A 直接整建失败 |
| A-4 | `test/modules/xunit_box/net.h.ct:22` | `pub Stream stream_open(void)` | 今天 `--emit-c` 把头文件里的 `Sink_iface`/`Stream_iface` 当导出类型发出（E1-4），A 会让该单元整建失败——连同 A-1 的 `lib/std/Str.h.ct`，共 5 个单元会被 A 判死 |

### 4.3 为什么仍不改立场

1. **A-1/A-2 的「判死」不是误杀，是 C 边界的事实。** `Str` 是按值 struct 且带 `Drop`，`id<T>` 是模板，`Writer`/`Stream` 是接口值——这三类在 C 里没有可移植的签名。B 能让构建变绿，但 `.abi.h` 里要么没有它们（静默，J-5 反对），要么写一个 C 编不过的原型（更糟）。A 的硬错把「这个单元没有 C ABI」提前到构建期，代价明确、位置明确。
2. **A 不要求改任何 `.ct` 语法。** A-1..A-4 的单元不是「改一行才能过」，而是「它们本来就不该做 `--lib` 根」；`ct build`（可执行）与 `--emit-c` 的行为按 §3.5 逐字节不变，现有测试与产品路径不受影响。J-2 问的是语法改动，答案是 0 行。
3. **B 的代价落在 J-3/J-4/J-5。** 显式标记要新语法（`AGENTS.md:469` 未批准），清单要新文件格式与校验（>2 文件/80 行），未标记的 `pub` 静默不导出（J-5 的「不得静默丢弃」）。A 用 1 个 CLI 选项 + 1 条既有类型规则解决同一问题。
4. **「包级复用 vs C ABI」的冲突是设计边界，不是 A 的 bug。** 一个包若要同时服务 CT 消费方与 C 消费方，正确形态是两份制品：CT 源码包（`.h.ct`，可含泛型）与 C ABI 库（只含 C 可表达签名的单元）。A 强迫这个边界显式化；B 把它藏进标记，作者仍要维护两套真相。

---

## 5 E3：可证伪预测

**若 A 成立（PH-39 R2 按 §3.1 落地），运行：**

```console
$ /tmp/p39head/ct build --lib test/modules/p34_pub_bound/lib.h.ct; echo "exit=$?"
```

**应得到**（一次性可判）：

1. `exit=1`（非零）；
2. stderr 至少两条 `: error:`，首条定位 `test/modules/p34_pub_bound/lib.h.ct:21:<col>`，文案形如 `'id' cannot be exported: <reason>`；第二条定位 `:26:<col>`，形如 `'max2' cannot be exported: <reason>`；
3. 输出目录中**不出现** `lib.abi.h`、`lib<base>.a`（「不写任何产物」，§3.1）。

**若得到 `exit=0`，或得到一个静默省略 `id`/`max2` 的 `.abi.h`，则 A 没有成立**（实现退化成了 B 的静默剔除）。此预测不依赖本席的任何未提交代码：它只断言 A 落地后的可观察行为，证据席可在 R2 提交上原样重跑。

---

## 6 E4：代价量化

**范围声明**：只算「导出面选择机制」（O2），不含 `.a`/`ar` 确定性（O1）与 visibility/static 化（O3）；后两者是 PH-39 R1/R4/R5，独立任务、独立回退。

| 项 | 上限 | 说明 |
| --- | --- | --- |
| 改动文件数 | **2** | `selfhost/ct-ast/frontend/module/Module.h.ct`（遍历本构建 `.h.ct` 单元 → 过滤 `is_pub && body >= 0` → 类型判定 → 收集导出 → 生成 `.abi.h` 原型集合 → L39-1）、`selfhost/ct-ast/tool/driver/Driver.h.ct`（`--lib` 解析、`build` 分派、与 `--emit-c`/`compile` 互斥） |
| 改动行数 | **≤80 行**（机制增量，上限） | 扫描与原型发射复用既有 `build_main` / `write_unit_header` / `emit_proto` 的形状；新增的是一个类型判定函数（约 30–35 行）+ 导出收集与诊断（约 25–35 行）+ 选项（约 10 行），合计 ≤80 |
| 影响门禁 | **只增不改** | G1/G3/G4 判据零改动；`check-ast.sh` 新增 p39 段（`p39/errors` 负例、`p39/abi-header` 原型集合），`selfhost/check-all.sh` 既有步骤不变；不新增门禁编号 |
| 回退步骤 | 单提交可回退 | ①`git revert <R2-sha>`（导出扫描 + L39-1）；②若需整体撤 `--lib`，再 `git revert <R1-sha>`；③重跑 `bash selfhost/check-ast.sh` 与 `./test/run.sh`，断言 `git diff --stat` 在 `test/modules/**` 的 golden 上为空（§3.5：`ct build`/`--emit-c` 逐字节不变） |

**对照 B 的成本**（用于 J-4，不是替对方立论）：`pub export` 需 lexer/parser/sym 三处改动 + 新诊断 + 文档；`--export` 清单需新文件格式解析、清单与定义的交叉校验、未知/过期条目诊断。文件数 ≥3、行数 ≥150，且都必须先过 `AGENTS.md:469` 的用户确认。A 在 J-4 上严格更小。

---

## 7 E5：预判反对席最强论点（B）与回应

> **本节是预判，不是引用。** 反对席的 `counter.md` 尚不存在，以下「B 方最强论点」由本席按 B 的立场重构；若对方原文与本节不同，以对方原文为准，本席保留在下一轮补充回应的权利。

**预判 B 方最强论证：**

1. `pub` 是 CT 的**包级可见性**（P34 O1：泛型能力「可被包复用」），不是 C ABI 契约。A 把两者等同，等于给所有既有的包级 `pub` 追加一个它们从未承诺过的 C 约束。
2. 因此 A 会误杀合法的库形态：一个包既要给 CT 消费方导出泛型 helper，又要给 C 消费方导出几个标量函数——A 让它整建失败，B 只导出标记过的几个，其余不导也不报错，**J-1 与 J-2 同时成立**。
3. 今日 `--emit-c` 已经静默省略泛型 `pub`（本席 E1-2 自证），说明「不导出泛型」是既有事实；A 把既有事实升级为硬错，是无必要的破坏性变更。
4. 显式标记还解决「隐式 ABI 增长」：A 下任何人往被 import 的 `.h.ct` 加一个 `pub`，`.abi.h` 就悄悄多一个导出，ABI 面随代码漂移；标记/清单让导出面显式、可审。

**回应：**

1. **「包级可见性」与「C ABI 面」在 `.h.ct` 这一层重合，是 PH-39 的既定设计。** S-1（`phase39-draft.md:16`）已经写死「`.h.ct` 的 `pub` 函数即为 C ABI 导出面」；本庭若改判 B，等于改 PH-39 的 O2 定义，那不是「A 加了约束」，是「B 撤回已批准的目标」。`pub` 的 P34 语义在本庭没有被 A 扩大：A 只在 `--lib` 这一个新模式里读它，`ct build` 与 `--emit-c` 不变。
2. **「不判死」的代价是「不告诉」。** f2/f3 的泛型/trait 函数**任何机制都导不出 C ABI**；B 的「不导也不报错」让作者以为导出成功，直到 C 消费者链接失败——这不是 J-1 的意图一致，是意图缺席。A 用一条 `file:line:col` 让作者在构建期做一次明确选择：去 `pub`（库内用）、移出 C-ABI 单元（CT 包用）、或保留（不做 `--lib`）。**三个出口都存在，且都不改 `.ct` 语法。**
3. **既有静默不是契约。** §3.5 明确 `--lib` 是新增分支、既有模式逐字节不变；`--emit-c` 的生成头从来不是 ABI 承诺（它叫「exported types」，且今天连泛型原型都没有）。把 `--lib` 的新契约建立在一个从未承诺的旧行为上，才是真正的破坏性变更。
4. **「隐式 ABI 增长」用清单治不了根。** 手写清单会与代码漂移（清单说导出 `f`，代码删了 `f` → 链接期才炸）；自动从代码生成清单，那就是 A。真正的防线是「`.h.ct` 是公开头、往公开头加 `pub` 是 ABI 变更」这条发布纪律（CHANGELOG / semver / G8），不是第二份真相。A 让「代码即清单」，漂移不可能存在。
5. **J-3 是 B 的硬伤。** `pub export` 是新语法，`--export` 是新 CLI/文件格式；`AGENTS.md:469` 要求用户先确认，本庭材料没有这份确认。A 只新增已立项的 `--lib`，语言面零增长。
6. **B 也解决不了 A-1/A-2 的实质问题。** 无论标记多精确，`Str` 按值、`T id<T>` 都无法出现在 `.abi.h` 里；B 只是把「不可导出」从错误变成默认，把选择成本从构建期推到链接期/运行期。A 把成本放在最早的可发现点。

**本席承认的最弱处（供裁判直接检验）：** 在 J-1 的字面读法下，f2/f3 被判死，A 不满足「不把其余判死」；在 J-2 的字面读法下，`lib/std/Str.h.ct` 与 4 个 `test/modules` 单元不能做 `--lib` 根。本席的回应是「这是 C ABI 边界的必然，不是 A 的实现缺陷」，但这一回应成立与否，取决于裁判是否接受「作者意图 = `.h.ct` 里的 `pub`」这一前提（S-1 支持它）。若裁判不接受，A 应被判 `rejected`——本席不请求用叙述替代这条判据。

---

## 8 复现清单

| 步骤 | 命令 |
| --- | --- |
| 1 | 取 HEAD 归档：`git archive ac040d1 \| tar -x -C /tmp/p39head/src`，按项目方式构建 `ct`（本席用既有 `/tmp/p39head/ct`） |
| 2 | 核对二进制：`shasum -a 256 /tmp/p39head/ct` = `0806…dd10`；`/tmp/p39head/ct --version` = `ct v0.37.0` |
| 3 | 在 `/tmp/p39head/src` 跑 E1-1/E1-2/E1-3/E1-4/E1-5 的命令与 `grep` |
| 4 | 按 E1-6 的源码在 `/tmp/p39claim/f1_purec`、`f2_generic`、`f3_trait` 重建夹具，跑 `--emit-c` 与 `--lib` |
| 5 | 锚点：`git grep -n <pat> HEAD -- <path>`，见 §4 |

**本席未覆盖的限制：**

- `/tmp/p39head/ct` 是 HEAD 构建，A 的 `--lib` 与 L39-1 尚不存在，E1 的 `--lib` 输出只有「unknown option」；A 的导出集合是 §3.1 的推演，E3 给出了它的可证伪形态。
- E1-3 的「38 / 12 / 3」分类按 §3.1 文本人工核对；`grep` 只枚举候选行，`Point` 的 3 条因「`pub` 仅在声明、定义行非 `pub`」单列为待定，未计入 12。
- `test/modules/p34_pub_bound/lib.h.ct` 的 `max2<T: Compare>` 是 trait 约束泛型，A 下同属规则 3；本席未把 `pub trait` 本身计入函数统计（它不是顶层函数）。
