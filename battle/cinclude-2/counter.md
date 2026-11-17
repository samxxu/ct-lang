# battle/cinclude-2 反证书（REVIEW，主张 B）

| 项 | 值 |
| --- | --- |
| 主张 | B：范围同 A；`.m.ct` 只 include 自有 `<base>.shim.h`；`.h.ct` 自有 shim；strict 覆盖 raw/extern/define；默认 strict 走包/CLI 策略，不是 parser 无条件默认 |
| HEAD/环境 | `729369fa`（v0.63.2）；macOS arm64；`ct v0.63.2`；夹具在 `/tmp/ci2/`；仓库只读；未读 `claim.md` |
| B 形态 | B1 范围同 A（CT 核心/1.0 前豁免，外部库/用户 strict）。B2 `.m.ct` 只允许自有 `<base>.shim.h`（显式或编译器自动同权），系统/第三方头只能进 shim。B3 `.h.ct` 同步自有 shim，公开 `.h` 不出现系统头。B4 strict 覆盖 `#ct-raw`、`extern`、函数式 `#define`、`.m.ct` 非 shim include，唯一豁免 shim。B5 `ct.pkg` 增 `c-boundary=strict\|allow`（未知键报错），`ct build`/`ct pkg check` 读取，parser 不动，CT 核心按路径豁免。B6 包/文件 `allow-c-boundary` + `文件:行:列+类别+允许路径` 诊断，回退只改配置 |

B 是包级 guardrail，不是沙箱；shim 内容与链接面仍是受控出口（cinclude-1 判决 §2.6）。

## E1 命令与原始输出

### E1-1 `.m.ct` 现可任意 include 并直接 map C（支持 A，反证 B 的必要性）

```console
$ cat /tmp/ci2/e1/libc/libc.m.ct
#include <stdio.h>
#include <stdlib.h>
namespace libc;
pub trait Env { char *get(char *n); int say(char *s); int fmt(char *f, int n); }
map trait Env for namespace libc { get(n) -> getenv(n); say(s) -> puts(s); fmt(f, n) -> printf(f, n); }
$ cd /tmp/ci2/e1 && ct build --emit-c main.ct -o out; echo rc=$?
cc -std=c99 -I out out/main.c -o a.out
rc=0
$ nl -ba out/main.c | sed -n '3,4p;10,12p'
     3	#include <stdio.h>
     4	#include <stdlib.h>
    10	    char * home = getenv(("HOME"));
    11	    puts(("direct-map-no-shim"));
    12	    printf(("n=%d\n"), (7));
$ cc -Wall -Wextra -std=c99 out/main.c -o out/main && ./out/main; echo rc=$?
direct-map-no-shim
n=7
rc=0
```
零 shim。同类：`#include <sys/socket.h>` + `<unistd.h>` 后直接 map `socketpair/write/close`，同命令 build rc=0、run rc=0。A 的“边界”在 HEAD 无任何机制兑现。

### E1-2 对 B 不利①：强制每个 `.m.ct` 配 shim 会撞基名

```console
$ ct build --emit-c main.ct -I p1 -I p2 -o out; echo rc=$?
ctc: shim base name 'lib' is ambiguous: p1/a/lib and p2/b/lib
rc=1
$ # 同一布局改为各自 #include <stdlib.h>、删除 shim 后重跑：
$ ct build --emit-c main.ct -I p1 -I p2 -o out; echo rc=$?
cc -std=c99 -I out out/main.c -o a.out
rc=0
```
夹具：`p1/a/lib/lib.m.ct` 与 `p2/b/lib/lib.m.ct` 各带 `lib.shim.h`，`main.ct` import 两者。A 模型 rc=0、B 模型 rc=1：B 把“基名唯一”变成新约束，真实多包同名 `lib/io/fs` 会撞。

### E1-3 对 B 不利②：`.h.ct` 的姊妹 shim 在 HEAD 被忽略

```console
$ ct build --emit-c main.ct -o out; echo rc=$?
cc -std=c99 -I out out/main.c out/foo.c -o a.out
rc=0
$ grep -rn "shim" out/; echo rc=$?
rc=1
$ nl -ba out/foo.h | sed -n '8p'
     8	#include <stdio.h>
```
夹具：`foo.h.ct` 含 `#include <stdio.h>` 与 `pub int foo`，`foo.shim.h` 同目录。它存在但生成物零引用；`<stdio.h>` 原样复制进公开头。B 第 4 条未实现（B 的成本），A.6 的“公开 C 类型经 shim”同样无机制。

### E1-4 支持 B：真实 POSIX 与变参映射都可用自有 shim 表达

```console
$ grep -c '^#include' test/bindings/posix-socket/posix/socket.m.ct; sed -n '5,7p' test/bindings/posix-socket/posix/socket.shim.h
0
#include <errno.h>
#include <sys/socket.h>
#include <unistd.h>
$ ct build --emit-c test/bindings/posix-socket/demo.ct -o /tmp/ci2/posix; echo rc=$?
cc -std=c99 -I test/bindings/posix-socket/posix -I /tmp/ci2/posix /tmp/ci2/posix/demo.c -o a.out
rc=0
$ cc -Wall -Wextra -std=c99 /tmp/ci2/posix/demo.c -I test/bindings/posix-socket/posix -o /tmp/ci2/posix/demo && /tmp/ci2/posix/demo
hello 5
```
生成的 `demo.c:3` 是 `#include "socket.shim.h"`。变参同形态：`io.m.ct` 0 include、`io.shim.h` 仅 `#include <stdio.h>`，`printf`/`snprintf` 的 `...` 原样映射；`ct build` rc=0，运行 `shim-varargs`/`n=9`，`cc -Wall -Wextra` 零警告。

## E2 `file:line` 锚点

**支持 B（3 条）**

- `docs/language-spec.md:606-608`：`.m.ct` 只允许 namespace/import/`#include`/`#define`/`pub trait`/`pub type`/`map`/`_Static_assert`，函数、全局、类型、`impl` 都报错 → 它是 recipe 单元，不是封装/实现单元。
- `docs/language-spec.md:684-686`：消费者 `.c` 自动 `#include "<base>.shim.h>"`（prologue 之前去重）、自动 `-I` → B 的 `.m.ct` shim 机制在 HEAD 已完整，B 对 `.m.ct` 是收紧而非新建机制。
**不利于 B（3 条）**

- `docs/language-spec.md:680`：“编译器只为 `.m.ct` 探测 shim（`foo.h.ct` / `foo.ct` 旁的 `foo.shim.h` 被忽略）” → B 第 4 条未实现；E1-3 的 `grep shim` rc=1 即证据。136 个 `.h.ct`、32 个含 include 全压在这条上。
- `docs/language-spec.md:682-683`：“两个映射单元的 shim 同名但目录不同 → 构建失败” → E1-2 的 rc=1 是 B 强制 shim 的直接代价；A 模型同布局 rc=0。
- `docs/language-spec.md:729-732`：`.m.ct` 不能 import `.h.ct`、不能声明类型、不能含 `impl` → 有状态/接口/公开 C 类型的真实库只能落 `.h.ct`，而 `.h.ct` shim 未实现；B 的 `.m.ct` 规则解决不了这一半。
**`.m.ct` 能/不能声明状态与类型（HEAD 实测）**

```console
$ # 全局变量 / 新类型 / impl
./s/s.m.ct:7:1: error: a .m.ct unit cannot declare a global variable
./s/s.m.ct:5:1: error: a .m.ct unit cannot declare a type
./s/s.m.ct:7:1: error: a .m.ct unit cannot contain an impl
$ # pub type 别名可用：pub type FD = int; + map dup(fd) -> dup(fd); 构建 rc=0
```
`.m.ct` 只能**别名**已有 C 类型，不能新建类型、不能持有状态、不能写 `impl`。A 所说的“封装边界”只是文本边界；真正的封装（所有权、错误翻译、布局）必须在 `.h.ct` + shim，B 的 `.h.ct` shim 正是这一层的入口。

## E3 可证伪预测

| # | 若 B 成立 | 一次性验证 | 当前状态 |
| --- | --- | --- | --- |
| P1 | strict 包接受“`.m.ct` 0 直接 include + 自有 shim”的真实 C 库 | 把 E1-4 的 posix-socket 标 strict，`ct build` rc=0、运行 `hello 5` | 机制已在 HEAD 通过（E1-4）；strict 层未实现，验收时重跑 |
| P2 | 变参/真实库不需要在 `.m.ct` 直接 include | E1-4 的 `io.m.ct`+`io.shim.h` 构建 rc=0、输出 `shim-varargs`/`n=9` | **HEAD 已通过**；若换 shim 后失败，B 的“shim 足够”即被证伪 |
| P3 | strict 只对 `.m.ct` 非 shim include 报错并给允许路径 | strict 夹具放 `#include <stdio.h>`：预期 `文件:行:列` + 允许 `<base>.shim.h`，rc=1；删该行后 rc=0 | 未实现；若 `ct.pkg` 仍忽略未知键、`ct build` 不读策略，B5 失败 |
| P4 | 不存在“必须直接 include 才能 map”的目标库 | 对每个拟支持真实库做 E1-4 形态；任一失败即 B 不成立 | POSIX/stdio 变参均通过；未覆盖库是 B 的未验证面 |

## E4 代价量化

| 项 | 数量/改动 | 依据 |
| --- | --- | --- |
| `.m.ct` 迁移 | 43 个；28 个含 include（16 直接系统头、12 已 include 自有 shim、15 无 include）→ 约 16 个需新增 shim | HEAD 实测 |
| `.h.ct` 迁移 | 136 个；32 个含 include（stdio 29、string 16、stdlib 12…）→ 需 `.h.ct` shim 机制 | HEAD 实测 |
| 编译器/包/CLI | `Unit.h.ct:23-26` 已有 shim 字段；新增 `.h.ct` 探测、公开 `.h` 发射 shim include、`-I` 传播、缓存 key、歧义诊断；`ct.pkg` 增 `c-boundary` 与未知键报错，`ct build`/`ct pkg check`/索引读取，CT 核心路径豁免清单 | spec:680、684-690；cinclude-1 §4（当前未知键被忽略、build 不读） |
| 迁移总量/门禁 | 688 个含 include 的 `.ct`（665 个 grandfather）；`check-ast.sh` modules/bindings 段、g5 负例、g8；7 类诊断各带 `文件:行:列`+允许路径 | cinclude-1 J-4、AGENTS §6.4、question J-4/J-6 |
| 回退 | 改 `c-boundary=allow` 即回退；parser 未改，无语言回退；shim 可留可删 | B5/B6 |

## E5 对 A 最强论点的 steelman 与逐条反驳

A 原文（`question.md`）：

- A.3：“`.m.ct` 允许 `#include`/`#define`：它本来就是映射单元，是“封装边界”，不是实现代码；已有 prologue 机制可复用。”
- A.4：“strict 还覆盖 `#ct-raw`、`extern`、函数式 `#define` 等直接 C 边界；唯一允许的是 `.m.ct` prologue 和 `<base>.shim.h`。”

**Steelman（A 最强形态）**

1. `.m.ct` 是项目指定的映射单元，C 声明放这里最自然；prologue 已文档化（spec:671-673），无需第二文件；header-only shim 还会按消费方复制（tutorial:800-801）。`.m.ct` 已不能写函数/全局/类型/`impl`（E2 实测），C 面本就被 recipe 限制；include 不会让它变成“实现代码”，只是取声明。
2. B 不减少绕过：shim 是任意 C，cinclude-1 J-3 的 7 类绕过 rc=0；B 只是把洞从 `.m.ct` 挪到 `.shim.h`，纯摩擦。

**逐条反驳**

1. “边界”不是内容规则，是文件后缀。E1-1 证明 `.m.ct` 可 include 任意系统头并直接调 `getenv/puts/printf/socketpair/write`，零 shim。A.4 把“唯一允许”给 `.m.ct` prologue，等于把任意 C 通道命名为豁免；strict 对 `.ct`/`.h.ct` 的规则可被“把 C 挪进 `.m.ct`”整体绕过，J-4 的 sound 不成立。
2. recipe 限制的是**体内**写法，不是**接口**：recipe 可绑任意 C 符号，任意 include 让它拿到任意声明。`.m.ct` 不能声明状态/类型（E2），恰好证明它不能承担 A 所说的“封装”；A.6 让 `.h.ct` 公开 C 类型经 `.m.ct`/shim 暴露，但 `.m.ct` 不能 import `.h.ct`、不能声明类型（spec:729-732），A 自己的路也没走通。
3. B 的 shim 确实是任意 C，B 不声称沙箱（cinclude-1 §2.6）；差别是**可枚举**：shim 是显式文件类，`ct pkg check` 能列出/计数/审计并逐步加链接白名单；A 把同样的 C 藏进“看起来是 CT”的文件。若 J-4 要求零绕过，A/B 都不满足；B 至少不把失败藏起来。且 A 的成本不更低：A.6 也要 `.h.ct` shim、A.4 也要 strict raw/extern/define。
4. 单文件便利性：posix-socket 的 shim 是 5 行 include + 4 个 `static inline`；简单映射的 shim 可只有一行 `#include <stdio.h>`。E1-2 的基名冲突是 B 必须修的缺陷（按 namespace 限定 shim 路径，或给带改名指引的硬错），不是放弃 B 的理由。

## 结论

**B 胜出**，条件：①默认 strict 走包/CLI（B5），parser 不动，否则重蹈 cinclude-1 已否决的“语言默认禁止 include”并破坏 688 文件与 C 超集（J-5）；②`.m.ct` 只 allow 自有 shim（显式/自动），系统头只能进 shim，`.h.ct` 同步实现自有 shim，否则 32 个含 include 的 `.h.ct` 无出口；③strict 覆盖 raw/extern/函数式 define/`.m.ct` 非 shim include，shim 内容与链接面**不**声称 sound，只作可枚举 guardrail；④CT 核心按路径豁免，保留包/文件 `allow-c-boundary` 压力阀与带允许路径的诊断。

**B 不成立的条件（反证清单）**

- F1：某个目标真实库无法用自有 shim 映射（P2/P4 失败）——shim 不够，B 的“只 shim”不可行。
- F2：`.h.ct` shim 无法在不破坏公开头自包含/`-I` 部署的前提下实现（E1-3 的 32 个 `.h.ct` 是下限）。
- F3：shim 基名歧义不可修（E1-2 在真实包集合上复现且无法改命名）——B 强制 shim 会破坏合法多包构建。
- F4：`ct.pkg`/`ct build` 无法承载策略（未知键仍被忽略、无负例），B5 退化为 parser 默认，B 不可执行；或 J-4 被解释为“零绕过/可证明 sound”，A/B 均失败，此时结论应为“guardrail，非 sound”，不得宣称 B 胜出。
**本席不声称**：shim 内容审计、链接白名单、7 类绕过的完全封堵；这些不在 B 内，也不在 A 内。B 的收益是把 C 面从“CT 外观的文件”变成“显式、可数、可审计的 shim 文件类”；代价是每单元一个 shim、`.h.ct` 机制与基名约束。
