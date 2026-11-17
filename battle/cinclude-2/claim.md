# battle/cinclude-2 · 主张席（REQ）· A：`.m.ct` 可任意 `#include`，它就是映射边界

| 项 | 值 |
| --- | --- |
| 基线 | `729369fa`（v0.63.2）；ct-ast 由 HEAD 自举，`ct --version` → `ct v0.63.2` |
| 主张 A | `.ct`/`.h.ct` 默认 strict（不得直接 `#include`）；**`.m.ct` prologue 放行任意 `#include`/`#define`**；strict 同覆 `#ct-raw`/`extern`/函数式 `#define`；合法 C 出口 = `.m.ct` prologue 与 `<base>.shim.h`；CT 核心/1.0 前代码内部豁免；包/文件 `allow-c-boundary` opt-in |
| 判据 | question.md 的 J-1…J-6；证据按 §7.7 E1–E5 |
## 1 范围、默认层级、`.m.ct` 理由与豁免

| 项 | A 的形态 | 依据 |
| --- | --- | --- |
| 范围 | 外部库/用户代码默认 strict；`selfhost/**`、`lib/std`、`test/**`、`examples/**` 是 1.0 前代码，整类豁免、不迁移 | 含显式 include 的 688 个 `.ct` 全落在四类内（E1-4） |
| 默认层级与 opt-in | strict 是**包/构建策略**，语言默认仍是 C 超集（沿用 cinclude-1 B′）；`ct.pkg` 的 `c-boundary = strict\|allow`，新包缺省 strict、旧包缺省 allow；混合包可用文件级 `// ct:c-boundary=allow`，清单只减不增 | 清单键读取点已存在（`selfhost/ct-ast/frontend/module/Module.h.ct:2313`） |
| 为何 `.m.ct` 可任意 include | `.m.ct` 是零产物映射单元：只放 `#include/#define/pub trait/pub type/map`，不产 `.c/.h`、`ct compile` 拒收、不能声明 struct/全局/impl（E2 实测）→ C 面只以「prologue 行 + 单次调用 recipe」存在，一库一文件，**它本身就是边界**；把同一份 C 再拆进 shim 不增加封装，只增加一个文件 | `docs/language-spec.md:605`、`docs/language-spec.md:731` |
| 核心豁免机制 | ① 编译器内按路径类豁免，`lib/std` + `CT_STD_DIR` 已有先例（`selfhost/ct-ast/frontend/parse/Parser.h.ct:2164`、`selfhost/ct-ast/frontend/module/Module.h.ct:596`）；② 自举自编入口显式 `--allow-c-boundary`（`selfhost/check-ast.sh:6121`）；③ 不把 `selfhost/**` 字面量散写进 parser 通用分支 | 先例可复用，新机制 2 处 |
| `.h.ct` 公开 C 类型 | 经 `.m.ct` 类型别名（`docs/language-spec.md:1747`）或 `<base>.shim.h` 暴露，不直接 include；须把 shim 探测从 `is_map` 扩到 `.h.ct`（`selfhost/ct-ast/frontend/module/Module.h.ct:683`） | 现状是 `.h.ct` 直通 include（E1-3），这是 A 的欠账、不是既成事实 |
## 2 E1 命令与原始输出

以下命令全部在 HEAD 工作树上原样重跑过；`/tmp/claimA/ct` 为 HEAD 自举产物。
```console
# 前置：HEAD → ct-ast（各步 rc=0）
$ cd /Users/samxx/dsh-ws/ct-lang && gcc -Wall -Wextra -std=c99 selfhost/l0/ctc.c -o /tmp/claimA/ctc && /tmp/claimA/ctc selfhost/l1/ctc.ct -o /tmp/claimA/l1.c && gcc -Wall -Wextra -std=c99 /tmp/claimA/l1.c -o /tmp/claimA/l1 && mkdir -p /tmp/claimA/l2src && /tmp/claimA/l1 build selfhost/l2/driver.ct -o /tmp/claimA/l2src && gcc -Wall -Wextra -std=c99 /tmp/claimA/l2src/*.c -o /tmp/claimA/l2 && mkdir -p /tmp/claimA/astsrc && /tmp/claimA/l2 build -I selfhost/ct-ast selfhost/ct-ast/main.ct -o /tmp/claimA/astsrc && gcc -Wall -Wextra -std=c99 /tmp/claimA/astsrc/*.c -o /tmp/claimA/ct
cc /tmp/claimA/l2src/core.c /tmp/claimA/l2src/driver.c -o a.out
cc -std=c99 /tmp/claimA/astsrc/Symbols.c /tmp/claimA/astsrc/Init.c /tmp/claimA/astsrc/Lexer.c /tmp/claimA/astsrc/MapTable.c /tmp/claimA/astsrc/Unit.c /tmp/claimA/astsrc/Arena.c /tmp/claimA/astsrc/Diag.c /tmp/claimA/astsrc/Memory.c /tmp/claimA/astsrc/TypeCheck.c /tmp/claimA/astsrc/ParseSupport.c /tmp/claimA/astsrc/Expr.c /tmp/claimA/astsrc/Emitter.c /tmp/claimA/astsrc/MapBuild.c /tmp/claimA/astsrc/Stmt.c /tmp/claimA/astsrc/Parser.c /tmp/claimA/astsrc/Cache.c /tmp/claimA/astsrc/Sh.c /tmp/claimA/astsrc/Module.c /tmp/claimA/astsrc/Pkg.c /tmp/claimA/astsrc/Driver.c /tmp/claimA/astsrc/main.c -o a.out
$ /tmp/claimA/ct --version
ct v0.63.2

# E1-1 利 A：仓内 .m.ct 的 include 现成可用、零 shim（test/modules/map_unit）
$ mkdir -p /tmp/claimA/o1 && /tmp/claimA/ct build --emit-c test/modules/map_unit/main.ct -o /tmp/claimA/o1; echo rc=$?
cc -std=c99 -I /tmp/claimA/o1 /tmp/claimA/o1/main.c -o a.out
rc=0
$ sed -n 3,4p /tmp/claimA/o1/main.c
#include <stdio.h>
#include <stdlib.h>
$ grep -n 'atoi\|getenv' /tmp/claimA/o1/main.c
20:    int n = atoi((a));
26:    char * home = getenv(("HOME"));
$ gcc -Wall -Wextra -std=c99 -I /tmp/claimA/o1 /tmp/claimA/o1/main.c -o /tmp/claimA/o1/demo && /tmp/claimA/o1/demo; echo rc=$?
42 2 0 1 zzz env-ok
rc=0

# E1-2 不利 A：.m.ct 直接 map printf/snprintf（含 ...），封装并不存在（test/modules/map_unit_varargs）
$ mkdir -p /tmp/claimA/o9 && /tmp/claimA/ct build --emit-c test/modules/map_unit_varargs/main.ct -o /tmp/claimA/o9; echo rc=$?
cc -std=c99 -I /tmp/claimA/o9 /tmp/claimA/o9/main.c -o a.out
rc=0
$ sed -n '6p;18p' test/modules/map_unit_varargs/std/io/io.m.ct
#include <stdio.h>
    printf(fmt, ...)             -> printf(fmt, ...);
$ grep -n 'printf' /tmp/claimA/o9/main.c | head -2
16:    printf(("type %d %d\n"), (4), (5));
18:    printf(("ns-zero\n"));
$ gcc -Wall -Wextra -std=c99 -I /tmp/claimA/o9 /tmp/claimA/o9/main.c -o /tmp/claimA/o9/demo && /tmp/claimA/o9/demo; echo rc=$?
type 4 5
ns-puts
ns-zero
ns-one 1
ns-three 1 2 3
ns-six 1 2 3 4 5 6
7/9 one
rc=0

# E1-3 不利 A：.h.ct 公开 C 类型靠直通 include，没有 shim（test/bindings/mock-hal）
$ mkdir -p /tmp/claimA/o8 && /tmp/claimA/ct build --emit-c test/bindings/mock-hal/demo.ct -o /tmp/claimA/o8; echo rc=$?
cc -std=c99 -I /tmp/claimA/o8 /tmp/claimA/o8/demo.c /tmp/claimA/o8/uart.c -o a.out
rc=0
$ grep -n '#include' /tmp/claimA/o8/uart.h
8:#include "mock_hal.h"
$ ls test/bindings/mock-hal/*.shim.h; echo rc=$?
ls: test/bindings/mock-hal/*.shim.h: No such file or directory
rc=1

# E1-4 不利 A：CT 核心/1.0 代码的 include 依赖（豁免不是可选项）
$ for d in selfhost lib test examples; do printf '%s ' $d; grep -rl --include='*.ct' -E '^\s*#\s*include' $d | wc -l; done
selfhost       22
lib        4
test      490
examples      172
$ printf 'm.ct total: '; find . -name '*.m.ct' | wc -l; printf 'm.ct with <include>: '; grep -rl --include='*.m.ct' -E '^\s*#\s*include\s*<' . | grep -v battle | wc -l
m.ct total:       43
m.ct with <include>:       17
$ grep -n '#include' selfhost/l2/core.ct | head -2
20:#include <ctype.h>
21:#include <setjmp.h>

# E1-5 不利 A：c-boundary = strict 在 HEAD 完全无效（策略层要从零实现）
$ rm -rf /tmp/c2 && cp -R test/modules/map_unit /tmp/c2 && printf 'name = p\nversion = 0.1.0\nnamespace = libc\npublisher = p\nns-root = libc\nc-boundary = strict\n' > /tmp/c2/ct.pkg && mkdir -p /tmp/c2/out && /tmp/claimA/ct build --emit-c /tmp/c2/main.ct -o /tmp/c2/out; echo rc=$?
cc -std=c99 -I /tmp/c2/out /tmp/c2/out/main.c -o a.out
rc=0
$ grep -n '#include' /tmp/c2/out/main.c | head -3
3:#include <stdio.h>
4:#include <stdlib.h>
5:#include <string.h>
```
## 3 E2 `file:line`：利 A 与不利于 A
**利 A**

- `docs/language-spec.md:605`：`.m.ct` 的合法内容恰是 `#include/#define` + 映射声明，且零产物、不能承载 impl → 它天然是「只有 C 面、没有实现」的边界；A 只给 `.ct`/`.h.ct` 加限制，`.m.ct` 原样放开，改动落在策略层。
- `docs/language-spec.md:671`：`.m.ct` prologue 按整行去重展开进消费者 `.c`（E1-1 实测 `#include <stdio.h>` 出现在 `main.c` 顶部）→ include 已是既有契约，A 不新增代码生成。
- `docs/language-spec.md:684` + `selfhost/ct-ast/backend/emit/Emitter.h.ct:608`：shim 由编译器自动 `#include "<base>.shim.h>"` 并加 `-I` → shim 与 `.m.ct` prologue 是同一条边界上的两种写法，放行后者不削弱前者。
- `selfhost/ct-ast/frontend/parse/Parser.h.ct:1347`：prologue 白名单**只对 `.m.ct`** 生效，`.ct`/`.h.ct` 目前无任何 include 限制 → A 的 strict 是补上后两类，而非给 `.m.ct` 加限制。
**不利于 A**

- `docs/language-spec.md:731` + `docs/language-spec.md:732`：`.m.ct` 不能声明类型、不能含 impl；实测 `struct S` → `a .m.ct unit cannot declare a type`（rc=1）。→ `.m.ct` 放行任意 include 也只能「声明 + 调用」，藏不住状态；代价是 A 的封装保证只是「C 面集中」，不是「C 不可达」。
- `docs/language-spec.md:680` + `selfhost/ct-ast/frontend/module/Module.h.ct:683`：shim 只为 `.m.ct` 探测，`.h.ct`/`.ct` 旁的 `<base>.shim.h` 被忽略 → A 的第 6 条当前**没有机制**，须先扩探测。
- `selfhost/check-ast.sh:2456` + `selfhost/ct-ast/backend/emit/Emitter.h.ct:1563`：门禁 `hdr_prologue` 断言生成的 `.h` 必须含 `#include <stdio.h>`（实现即 `.h.ct` prologue 复制）→ 把 `.h.ct` 的 include 移进 shim 要同时改门禁与 `test/modules/hdr_prologue`，不是删行。
- `docs/tutorial.md:800`：`.m.ct` prologue 只放 `#include/#define`，映射模块合不成单文件，header-only shim 按消费方复制（`String.shim.h` 约 190 行/5.5K）→ 这正是 B 强制的形态；A 允许直接 include 才避免这份复制。

`.m.ct` 能声明：`pub type` 编译期别名（不发射 typedef）、静态 `pub trait`、`map`、`_Static_assert`；不能声明：struct/enum/union、全局变量、`impl`、函数定义、`#ct-raw`——状态与实现只能进 `<base>.shim.h`（同类实测：`int counter;` → `a .m.ct unit cannot declare a global variable`；`impl S` → `a .m.ct unit cannot contain an impl`；map 全局量 → `a map recipe must be a single call`）。
## 4 E3 可证伪预测

- **P1（A 成立，strict 默认仍能接真实 C 库）**：把 `test/bindings/posix-socket`（`.m.ct` 零 include，shim 提供 `socketpair`/`write`/`read`/`errno`）复制成新包并写 `c-boundary = strict`，`ct build` 必须 rc=0、`demo.c` 仍只有 `#include "socket.shim.h"`、输出 `hello 5`。HEAD 现状（无 strict 检查）见下；若 strict 实现后要求改这份映射，P1 被否证。
- **P2（A 的额外许可是关键差异）**：`test/modules/map_unit_varargs` 的 `.m.ct` 直连 `<stdio.h>` 并 map `printf`；A 下必须保持 rc=0，B 下必须报错（只许 `<base>.shim.h`）。A 的实现若判它错，A 即被否证。
- **P3（若只能靠任意 include 才可用，则 `.m.ct` 是唯一边界）**：posix-socket 证明 shim-only 可接真实 POSIX；E1-1/E1-2 证明直连系统头更短。两条都落在这一个文件类型里 → 边界是 `.m.ct`，shim 是可选附件；若有人能在 strict 下不建 `.m.ct`、只用 `.ct`/`.h.ct` 接 C 库，A 的边界说被否证。
```console
$ grep -n '#include' test/bindings/posix-socket/posix/socket.m.ct | wc -l
       0
$ mkdir -p /tmp/claimA/o10 && /tmp/claimA/ct build --emit-c test/bindings/posix-socket/demo.ct -o /tmp/claimA/o10; echo rc=$?
cc -std=c99 -I test/bindings/posix-socket/posix -I /tmp/claimA/o10 /tmp/claimA/o10/demo.c -o a.out
rc=0
$ sed -n 3p /tmp/claimA/o10/demo.c
#include "socket.shim.h"
$ gcc -Wall -Wextra -std=c99 -I test/bindings/posix-socket/posix /tmp/claimA/o10/demo.c -o /tmp/claimA/o10/demo && /tmp/claimA/o10/demo; echo rc=$?
hello 5
rc=0
```
## 5 E4 代价

| 项 | 量 | 后果 |
| --- | --- | --- |
| 改动面 | 6 文件：`Parser.h.ct:1347-1353`（12 行）、`Module.h.ct:683-720`（约 50）、`Emitter.h.ct:580-660`（约 80）、`Pkg.h.ct:405-435`（31）、`Driver.h.ct:280-295`（16）、`check-ast.sh` 自编 2 处；delta 估算 150–200 行 | A 是策略层闸门，不动 codegen |
| 生成物/门禁 | A 不改变生成物（E1-1/E1-2 的 `.c` 就是今天的样子）→ 0 golden 重生成；B 要改 17 个 `.m.ct` 的 prologue 形态（consumer `.c` 多一行 shim include、cc 行多 `-I`），相关夹具 golden 须重生成 | 动 `check-ast.sh` 的 modules/bindings/self-host 段与 `test/run.sh`；`tools/check.sh` g0–g9 不动 |
| 迁移 | 仓内含 include 的 688 个 `.ct` 全在豁免类（E1-4）→ A 强制迁移 0；外部 `ct-pkg/std` 的 str/fs/utf8 已是 `.m.ct`+shim（`docs/tutorial.md:740`）；其余外部包未知 | 迁移面在仓外，按包 opt-in |
| grandfather/回退 | 旧包 `c-boundary = allow`；混合包文件级 marker；清单只减不增；回退 = 删策略读取（1 提交 + 1 MINOR）或清单改 `allow` | 生成物与 golden 不变，11 道门禁 + G9 无 golden 影响 |
## 6 E5 对 B 最强论点的 steelman 与逐条反驳
**B 最强（steelman）**

- B-3 原文（`battle/cinclude-2/question.md:26`）："`.m.ct` 的 `map` 可以直接把任意 C 函数暴露成 CT 方法；若允许任意 include，strict 只是把绕过从 `.ct` 搬到 `.m.ct`，并未强制封装。"
- B-4/B-6 原文（`battle/cinclude-2/question.md:27`）："`.h.ct` 的姊妹 `.shim.h` 被忽略，需扩展"；"默认 strict 应是**包/构建策略**，不是 parser 对语言的无条件默认"。
- 本席补全第三根支柱（cinclude-1 verdict §2.6）：shim 内任意 C、链接外部 `.c` 都是受控出口 → 唯一可机械枚举的 C 面就是「每包自有 shim 文件集」，B 把这集合当清单，A 没有清单。
**逐条反驳**

- R1（绕过搬到 `.m.ct`）：成立，但 B 搬得更远——搬进 `<base>.shim.h`，而 shim 是任意 C（cinclude-1 J-3 实测七类绕过 rc=0；`selfhost/ct-ast/backend/emit/Emitter.h.ct:608` 显示 shim 头被直接 `#include` 进 consumer `.c`）。B 把审计目标从「`.m.ct` 的 prologue 行」换成「shim 文件」，文件数不减反增。
- R2（可机械枚举）：`.m.ct` 的 C 面本来就枚举得出——prologue 只有 `#include/#define` 行，调用只有单次 recipe，`--emit-map` 逐 binding 输出 `symbol`（`docs/language-spec.md:692`）；`grep '^#include'` 就能列出全部 C 头，不需要 shim 做代理指标。
- R3（`.m.ct` 藏状态）：`.m.ct` 不能声明类型/全局/impl（E2 实测），任意 include 给不了隐藏实现；相反 B 的 shim 恰恰**允许**实现（`static inline`、宏、全局 accessor）——B 的边界比 A 更宽。
- R4（`.h.ct` 缺 shim）：A 不否认，且 A 的第 6 条正是「`.h.ct` 经 `.m.ct`/shim 暴露」；这项机制 A、B 都要新建（`selfhost/ct-ast/frontend/module/Module.h.ct:683` 同一个改动点），不构成 A 的额外成本。A 亦同意 strict 属包/构建策略，与 B-6 无冲突——分歧只在「`.m.ct` 是否保留直连系统头」，而它决定 17 个现成 `.m.ct`（E1-4）与所有 printf 式映射要不要为通过 strict 新建 shim。
## 7 结论
**A 胜出（条件不可拆）**：① strict 覆盖 `.ct`/`.h.ct` 的 include、`#ct-raw`、`extern`、函数式 `#define`；② `.m.ct` prologue 保持任意 `#include/#define`，作为唯一映射边界；③ `.h.ct` 公开 C 类型经 `.m.ct` 别名或 `<base>.shim.h` 并补 shim 探测；④ CT 核心按路径类 + 自举 flag 豁免，1.0 前代码零迁移；⑤ 包/文件 `allow-c-boundary` opt-in、清单只减不增。
**A 不成立条件**：① strict 实现把（E1-2 那类）直连系统头的 `.m.ct` 判错，或要求为 17 个现成 `.m.ct` 新建 shim——那 A 实际上就是 B；② `.h.ct` 的 shim 探测扩不到、公开 C 类型仍只能直通 include（E1-3），A 的第 6 条落空、`.h.ct` 成事实豁免；③ 要求「每包可机械枚举被调用的 C 符号集」时，A、B 都不足，须另做 shim 内容审计 + 链接白名单（cinclude-1 §2.6 的出口），此时应按 C 方案重开，而不是在 A/B 间选。
