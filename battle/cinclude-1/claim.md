# battle/cinclude-1 · 主张席（REQ）· A：默认禁止 `.ct` 直接 `#include` C 头

| 项 | 值 |
| --- | --- |
| 基线 | `85579c4d`（v0.63.2） |
| 主张 | `.ct` / `.h.ct` / `.m.ct` 默认不得 `#include` C 头；唯一例外是 `#include "<base>.shim.h"`（本单元自有 shim）；C 库声明只能经 `.shim.h/.shim.c` 暴露 |
| 判据 | 按 question.md 的 J-1…J-6；证据按 §7.7 E1–E5 |

## 1. 主张、J 映射与迁移策略

默认禁止 = **编译期硬错**（非 warning），`allow-c-include` 为显式 grandfather；规则未扩面（见 E3）前，A 只算方向，不算可验收。

| 判据 | A 的结论 | 依据 |
| --- | --- | --- |
| J-1 自举/基础库 | ct-ast 19 文件/51 行、`lib/std` 4/8 必须迁；**不永久豁免**；`l1`/`l2` 是冻结归档（1/5、2/12），唯一永久例外 | L2 编 ct-ast；冻结边界见 AGENTS §2 |
| J-2 C 互操作 | `.m.ct` + shim 全保留；binding 与厂商 SDK 改用 shim 暴露声明；`.h.ct` 不再直通 | 仓内 31 个 `.shim.h`/500 行已够证明可表达 |
| J-3 可执行性 | 只禁 `#include` **不足以** 阻止绕过（E1 实证）；须扩到 raw/extern/`#define`/`.m.ct` prologue | 见 E3 四项 |
| J-4 迁移成本 | 688 文件/845 行；真实迁移面仅 19+4 文件；examples/test 走 grandfather | E4 |
| J-5 兼容性 | 60 个 golden 含 include、2 条 hdr 门禁断言、444 个 expected 文件；pre-1.0 用 MINOR + 迁移说明 | E2/E4 |
| J-6 策略形态 | A 是语言默认（诊断/退出码可机械验收，回退=删硬错）；B 的包策略要先实现清单键（当前 unknown-key 仅警告，`Pkg.h.ct:435-438`） | 两者都可回退；A 影响面大 |

迁移策略（三步，缺一不可）：
1. v0.64：加硬错与 `allow-c-include`；现有 688 文件按目录/包整树 grandfather（`test/**`、`examples/**`、`selfhost/l1|l2`），文件级 marker 只给混合包；allow 清单进仓、**只减不增**（ratchet）。
2. v0.64–v0.65：ct-ast（19/51）换成 `#include "ctlibc.shim.h"`（shim 内 `static inline` + 宏别名，成本见 E4），`lib/std`（4/8）同法；期间生成物须仍过全部 11 道门禁。
3. v0.66：新包/新文件默认硬错；旧包只保留清单内文件；ct-ast 与 `lib/std` 不再出现在清单里才算 A 完成。

## 2. E1 命令与原始输出

```
$ P='^[[:space:]]*#include[[:space:]]+[<"]'
$ grep -rlE --include='*.ct' "$P" . | wc -l
688
$ grep -rE --include='*.ct' -h "$P" . | wc -l
845
$ for d in selfhost lib examples test; do echo "$d $(grep -rlE --include='*.ct' "$P" "$d"|wc -l|tr -d ' ') $(grep -rE --include='*.ct' -h "$P" "$d"|wc -l|tr -d ' ')"; done
selfhost 22 68
lib 4 8
examples 172 210
test 490 559
$ for s in .h.ct .m.ct; do echo "$s $(grep -rlE --include="*$s" "$P" .|wc -l|tr -d ' ') $(grep -rE --include="*$s" -h "$P" .|wc -l|tr -d ' ')"; done
.h.ct 32 67
.m.ct 28 33
$ grep -rlE --include='*.ct' "$P" . | grep -vE '\.(h|m)\.ct$' | wc -l
628
$ grep -rhE --include='*.ct' "$P" . | sed 's/.*#include//' | sort | uniq -c | sort -rn | head -5
 638  <stdio.h>
  82  <stdlib.h>
  47  <string.h>
  22  <stddef.h>
  11  <stdarg.h>
```

注：selfhost 细分 ct-ast 19/51、l1 1/5、l2 2/12；`lib/std` 只有 Option/Result/Str/Vec 四个 `.h.ct`；test 细分 test/ast 364、test/modules 84、test/cases 25（其余为 acceptance/archive/patterns）。

**A 的不利证据（本席实测，四条）：**
1. `#ct-raw` 可完整绕过任何“只查 include”的规则：`#ct-raw` 内放 `#include <stdio.h>`，`ct-ast /tmp/p.ct -o /tmp/p.c` → `rc=0`，生成物第 25 行为该 include，`cc -Wall -Wextra -std=c99` + 运行输出 `raw-bypass`。
2. `extern` 同样绕过：`extern int puts(const char *s);`（无 include）→ `rc=0`，生成物第 33 行 `int puts(const char *);`，运行输出 `extern-bypass`。
3. 语言重心在 libc：638/845（75.5%）是 `<stdio.h>`，而 `lib/std` 没有任何 IO/print 封装（只有 4 个容器/字符串单元）；examples 的 159 个 stdio include 无处可迁，A 须先落 IO shim（该包在 ct-pkg 外部仓）。
4. ct-ast 自身：19 文件/51 行 include，且 `grep -rEoh --include='*.ct' '\b(printf|fprintf|snprintf|fputs|fputc|puts|malloc|calloc|realloc|free|strlen|strcmp|strncmp|strcpy|strchr|strstr|memcpy|memset|fopen|fclose|stat|system)[[:space:]]*\(' selfhost/ct-ast | wc -l` → `4360`（22 个常用名，下限）。

## 3. E2 `file:line` 与 `.m.ct`/shim 现有契约

利 A：
- `docs/language-spec.md:1792`：CT 没有预处理器，`#include` 只按整行透传、头文件内容不参与解析 → 直通 include 给不了任何被检查的契约；A 把 C 边界收成每依赖一份可审计文件。
- `selfhost/ct-ast/backend/emit/Emitter.h.ct:604-611`：消费者 `.c` 自动 `#include "<base>.shim.h>"`（按整行去重，置于 prologue 前）→ 官方封装路径已机械接线，A 不需要新运行时。
- `examples/47_chain_factory/src/http/http.m.ct:3` 与 `test/modules/map_unit_shim`：自有 shim include 已是既有写法；`.m.ct` prologue 展开契约在 `language-spec.md:671-673`（实测 consumer `main.c:4` 得到 `.m.ct` 的 `<stdlib.h>`）。

不利 A：
- `selfhost/ct-ast/backend/emit/Emitter.h.ct:1563-1572`：`.h.ct` 的 `#include` 被复制进**公开** `.h`（实测 `main.h:8`）；两条门禁钉住此契约：`selfhost/check-ast.sh:2029`、`:2458`。A 要让 shim include 替它进头，或给 shim 探测扩到 `.h.ct`——不是纯删行。
- `test/bindings/mock-hal/uart.h.ct:16`：binding 契约第一步就是直通 include（`test/bindings/README.md:19-20`）；有状态 binding 改 `.m.ct`+shim 需把实例/状态搬进 C shim。
- `lib/std/Vec.h.ct:17-19` + `docs/design/phase36-draft.md:206`：内建层 include libc，且已否决“内建层 include 外部 shim”（零外部依赖 Z2）。
- `docs/language-spec.md:912-913`：`offsetof` 要求源文件自己写 `#include <stddef.h>`；A 下 `stddef` 也只能走 shim。

`.m.ct`/shim 现有契约（A 只改“谁能 include”，不改机制）：`.m.ct` prologue 白名单 `#include`/`#define`（`language-spec.md:605-610`；实现 `selfhost/ct-ast/frontend/parse/Parser.h.ct:1346-1353`）；prologue 去重后展开进消费者 `.c`（671-673）；编译器**只为 `.m.ct`** 探测 `<base>.shim.h/.c`（680-690；`Emitter.h.ct:604-611`）；`.shim.c` 必须有 `.shim.h`，cc 行加 `-I <shim 目录>`、`.shim.c` 直接列源文件，两文件进缓存 key。仓内 31 个 `.shim.h`、5 个 `.shim.c`、500 行，shim 内只有 12 行 include——**“只有 shim 可 include”在 shim 侧已成立**，缺的正是 `.ct/.h.ct` 侧。

## 4. E3 可证伪预测

- P1（A 成立）：新包（无 allow）`.ct` 写 `#include <stdio.h>` → `ct build` rc=1，报 `error: #include is not allowed in a .ct unit; expose it through <base>.shim.h`；同文件改 `#include "ctio.shim.h"` → rc=0，`grep -c '^#include' out/*.c` 恰为 1，`cc -Wall -Wextra` 零警告、输出一致。
- P2（J-3 反证，已部分实证）：若不扩面，`#ct-raw` 内 include 与 `extern` 声明仍 rc=0。A 必须把规则扩到四项：① 所有 `#` 行，含 `#ct-raw` 块原文（raw 文本已是独立节点，可扫）；② `.ct/.h.ct` 的 `extern`（C 库符号只在 shim 头声明，`errno` 走 accessor）；③ `.m.ct` prologue 只许自有 `<base>.shim.h`；④ `#define` 指向 C 符号同样受限。缺一项 → A 的 J-3 失败。
- P3（基础库）：A 完成后 `lib/std` 4/8 → 0/0（或仅 shim include），裸 `Vec`/`Str` 与 `--freestanding` 仍绿；否则 J-1 失败。预测 shim 若带 `.shim.c`，会改变 cc 行与缓存 key，`--emit-c` 断言出现新增源文件。
- P4（迁移完成）：`grep -rlE <pattern> . | grep -vFf allow-list | wc -l` = 0；allow 清单逐周只减。两个 MINOR 后 ct-ast/std 仍在清单 → A 不成立。
- P5（封装真实性）：新 shim 中“只有 include、无任何包装函数”的比例应 <30%（可机械数）；超阈说明 A 只添摩擦，未强制封装。

## 5. E4 代价

| 项 | 数值 | 后果 |
| --- | --- | --- |
| 文件/行 | 688/845；plain 628、`.h.ct` 32/67、`.m.ct` 28/33；selfhost 22/68、lib 4/8、examples 172/210、test 490/559 | 迁移主体是 examples/test，用 grandfather 不逐个改 |
| 自举 | L0 `ctc.c`（C）不变；L0→L1→L2→ct-ast；`l1`/`l2` 冻结（1/5、2/12）永久 grandfather；ct-ast 19/51 迁 `ctlibc.shim.h` | 若要求“所有调用都包”= ≥4,360 个调用点（snprintf 1304、strcmp 1173、fprintf 507、fputs 491…）；允许 `static inline`+宏别名则 ≈51 行 + 1 个 shim 头 |
| std | `lib/std` 4/8；外部 ct-pkg std 不在本仓；Z2 禁外部 shim | 迁移跨仓，A 的 J-5 依赖外部包节奏 |
| examples/test | 172/210 + 490/559；60 个 golden 含 include 文本，444 个 expected 文件；`hdr`/`hdr_prologue` 两门禁断言 | 走 grandfather 则零改动；一旦迁移对应源，60 个 expected 需重生成、两段门禁改写 |
| 版本/兼容 | v0.63.2 → 下一个 MINOR（v0.64.0；pre-1.0 允许破坏但要迁移说明）；grandfather ≥2 MINOR（v0.64–v0.65），v0.66 硬默认 | 回滚 = 删硬错、留诊断，一个提交 + 一个 MINOR |
| 门禁 | 11 道；动 check-ast（corpus/bindings/hdr）、check-warnings（include 位置）、check-goldens（仅当 l1/l2 迁移才动） | 每条新断言配负例（G5），门禁变更同提交带负例与 CR（G8） |

## 6. E5 对 B 的最强论点与逐条反驳

**B 最强（steelman）**：
- B1 契约：CT 是 C with Traits，`.ct` 可含普通 C（`language-spec.md:55`）、“语法糖必须无歧义脱糖到 C”（`docs/modern-oo-gap.md:37` Z3）；688 文件是既有消费者，默认翻面就是 breaking。
- B2 机械：include 禁令是**代理指标**，已被 raw/extern 实证绕过；真正可判的是符号面——`--freestanding` + `nm -u`（PH-64，v0.63.0 已交付）直接禁止隐式 libc。
- B3 可回退：包清单 `c-include = forbid` 一行开关；语言默认要动编译器、规范、文档、门禁、版本窗口和 grandfather 机制。
- B4 生态：外部 ct-pkg std 和第三方 binding 不能由本仓迁移；无 deprecation cycle 直接翻默认会破坏 J-5。
- B5 收益替代：`ct new` 模板 + 警告 + CI 严格模式可让“新代码干净”，且零 breaking。

**逐条反驳**：
- R1 “C 超集”不等于“直通 include 无约束”：`#ct-raw` 仍是逐字节 C 通道，A 禁的是**默认** include；raw 保留为显式 C 出口，但块内 `#include` / `extern` 仍进 strict 扫描（见 P2）；破坏真实，故 A 用 2 个 MINOR + 迁移说明吸收 B1 的代价，而非静默翻面。
- R2 绕过证据是 A 的修订清单，不是否定：raw 8 处、`extern` 4 行，扩面成本小（扫 raw 文本、extern 限定 shim 头）。“只禁 include 就够”才是 A 的错误版本；B2 的 `nm -u` 管不住 include 顺序/宏污染（`errno`、`_GNU_SOURCE`），A 是源级、`nm -u` 是目标级，A 应把它纳入同一严格门禁而非替代。
- R3 “默认干净”与 opt-in 互斥：B 的默认允许意味着新包默认脏，这正是提案要改的；模板只覆盖用模板的人。A 的 grandfather ratchet 给出可回退路径（allow 只减、两 MINOR），B3 的可回退在 A 里同样是删一行硬错。
- R4 跨仓迁移是 A 的边界条件而非反证：本仓只对仓内 `lib/std` 负责，外部包按同一规则由其仓迁移；旧包 grandfather 不阻断消费者，J-5 通过条件明确为“窗口 ≥2 MINOR + lock 不破”。
- R5 收益不可替代：A 把 688 个 include 收敛为 N 个 shim + 一份 allow 清单，`grep` 可审计；B 的包策略要靠每包自觉，且要先改 `Pkg.h.ct` 才认这个键。

**让步**：B 的“代理指标可绕过”成立。因此 A 只有在 E3 四项扩面同时成立时才胜出；否则 A 只添摩擦、J-3 失败，应判 B。

## 7. 结论

**A 胜出（条件不可拆）**：① 四类源（`.ct/.h.ct/.m.ct` + `#ct-raw` 原文）统一硬错，唯一例外 `<base>.shim.h`；② ct-ast 与 `lib/std` 两个 MINOR 内真迁移，`l1`/`l2` 冻结归档是唯一永久例外；③ 688 文件 grandfather 显式入清单、只减不增；④ 两 MINOR 兼容窗口 + 迁移说明 + MINOR 版本；⑤ 五条预测各有负例门禁。

**A 不成立条件**：①-③ 任一被削（保留 raw/extern 例外、ct-ast/std 永久豁免、或 allow 清单可增），A 就不满足 J-1/J-3，判 B（默认允许 + `c-include = forbid` 包策略 + `--freestanding` 符号面门禁）。一句话：A 方向正确——直通 include 没有契约；但它不免费，只按上述扩面与迁移窗口才可采纳。
