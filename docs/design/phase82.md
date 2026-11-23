# Phase 82 — 泄漏防护（`leaks` 配置 + 直接环告警 + 树模式）

> 命名注记（LANG-24 Stage A）：本文件是历史快照，正文保留当时的 `box<T>` 拼写；v1.0 起规范拼写为 `Box<T>`（见 docs/language-spec.md §1.2）。


> **状态：完成（v0.82.0）**（2026-11-20 立项并开卡；2026-11-21 S82a–S82d 完成，E82-1…8 通过）。
> **签收：EDITOR 2026-11-20**（主编统一签收；卡作者 REQ）。
> **施工闸门**：PH-81 `box<T>` 已收口；D-012 accepted、battle leak-guards-1 closed（2026-11-20 已满足）。
> **前置**：PH-81 `box<T>` 收口；[D-012](../decisions/D-012.md) accepted；battle leak-guards-1 closed。
> **收口**：2026-11-21；收口复核见 §7（DEV `dev-ph82`）。
> **布局说明**：phase-ID 迁移仍被 blocker 挡住，本卡暂用 legacy 路径 `docs/design/phase82.md`。
> **依据**：[提案草案](../proposals/leak-guards.md)、[D-012](../decisions/D-012.md)、
> [battle 判决](../../battle/leak-guards-1/verdict.md)、[D-011](../decisions/D-011.md) J-4c。

## 0 卡片字段（冻结）

| 项 | 值 |
| --- | --- |
| 编号 | v0-PH-82（legacy 文件 `phase82.md`） |
| 目标 | 把「环 = 作者责任」升级为可见风险：包级泄漏告警可强制、`box` 字段直接环可静态告警、父子结构有官方写法 |
| 范围 | `leaks` 两档（`warn` / `error`）配置；`box<X>` 字段直接环检测（限深 3）；`/* ct: allow-cycle */` 豁免；`patterns.md` 树模式 |
| 非目标 | 运行期环检测/`--debug-leaks` 语义变更；GC；weak；跨过程/容器/泛型间接环；自动解环；句柄运行期泄漏分析 |
| 交付物 | 编译器改动、`test/ast/p82_*`、`patterns.md`/spec 文档、`check-all` |
| 任务清单 | §2（S82a–S82d） |
| 退出判据 | E82-1…E82-8（§3） |
| version-minor | 82（PH-82，`d=0`） |
| 已知风险 | R82-1…R82-5（§4） |

## 1 需求与边界

```ct
/* ct.pkg */
leaks = error          /* error：本包泄漏诊断与直接环告警构建失败；缺省 warn */

struct A { box<B> b; }
struct B { box<A> a; }        /* warning: potential reference cycle: A → B → A */

struct C { box<C> self; }     /* warning: potential reference cycle: C → C */

struct D { box<A> a; }        /* OK：单向，不构成环 */

/* 手工破环的合法写法 */
struct Node {                 /* ct: allow-cycle */
    box<Node> first_child;
    Node *parent;
}
```

- `leaks = warn|error`：缺省 `warn`；`error` 同时升级现有 `potential leak` 诊断与直接环告警；与 `c-boundary = strict` 无关。
- 直接环：只展开 `box<X>` 字段，相邻边计 1，限深 3；同一环只报一次。
- 豁免：`/* ct: allow-cycle */` 必须与 `struct` 声明同一行；`ct check` 输出被抑制点，便于审计。
- `--debug-leaks` 不在本卡：维持 D-011 J-4c，只报未配对 alloc/release 计数，不叫环检测。
- 本卡不改 `c-boundary`、不改 `--debug-leaks`、不引入 GC/weak。

### 1.1 分期

| stage | 内容 | 入口 |
| --- | --- | --- |
| S82a 配置/诊断 | `leaks` 两档（`warn` / `error`）解析与严重级别 | D-012；无代码前置 |
| S82b 环检测 | `box<X>` 字段图、限深 3、去重 | S82a；PH-81 收口 |
| S82c 豁免/负例 | `allow-cycle`；非目标路径不误报 | S82b |
| S82d 文档/门禁 | `patterns.md` 树模式、spec 配置说明、`check-all` | S82c |

### 1.2 施工前准备清单（准备态可做，不落实现代码）

| # | 项 | 通过方式 |
| --- | --- | --- |
| P82-pre-1 | `ct.pkg` 未知键行为：新键 `leaks` 可读、旧编译器静默忽略 | 审读 manifest 解析 + 夹具 |
| P82-pre-2 | 注释 pragma 可行性：词法器当前丢弃注释，确定扫描入口 | 词法只读审查 / 最小探针 |
| P82-pre-3 | `box` 字段图来源：Symbols 的 struct/field 表、build 模式跨单元 | 类型表审查 |
| P82-pre-4 | 严重级别通道：`leaks = error` 不污染 `c-boundary = strict` | Diag/Module 审查 + 负例计划 |
| P82-pre-5 | 默认 `warn` 下既有 leak golden 不变 | `test/modules/leak` 基线 |

## 2 任务

| 任务 | 交付 | 验收 | effort |
| --- | --- | --- | --- |
| S82a 配置 | `ct.pkg` 读 `leaks`；warn/error 两档 | `p82_config` | S |
| S82b 环检测 | `box` 字段图、限深、去重、诊断文案 | `p82_cycle` | M |
| S82c 豁免/负例 | `allow-cycle`；容器/泛型/接口/typedef 不报 | `p82_allow` / `p82_errors` | M |
| S82d 文档 | 树模式、spec `leaks` 说明 | `p82_docs` | S |

每项任务先提 `test(<scope>): <task-id> 红`（含 `baseline: <sha>`），实现提交随后转绿；S82d 为纯文档任务，写 `no-test:` 并由 REVIEW 签字。

## 3 退出判据

| ID | 断言 |
| --- | --- |
| E82-1 | `leaks` 两档（`warn` / `error`）从 `ct.pkg` 读取；缺省 `warn`；存量包无变化 |
| E82-2 | `warn` 下泄漏/环告警不失败；`error` 下同一代码构建失败；`c-boundary` 语义不变 |
| E82-3 | 自环、A→B→A、A→B→C→A 均命中；同一环只报一次；仅 `box<X>` 字段 |
| E82-4 | `Vec<box<T>>`、泛型参数、接口字段、typedef、间接环不报；语料零误报 |
| E82-5 | `/* ct: allow-cycle */` 抑制告警并在 `ct check` 报告；移除后重新告警 |
| E82-6 | 文案为「可能泄漏，除非手工破环」，不写「会泄漏」；`--debug-leaks` 不被改称环检测 |
| E82-7 | `patterns.md` 有父子结构一节；spec 记录 `leaks` 与检测范围/限深 |
| E82-8 | 旧 golden 不变；`check-all` 通过；单卡回滚（配置/检测/文档同退） |

## 4 风险与回滚

| ID | 风险 | 缓解 |
| --- | --- | --- |
| R82-1 | 手工破环被误报 | 默认 warning；`allow-cycle` 豁免；`ct check` 可审计 |
| R82-2 | 限深 3 漏检造成假安全感 | 文案明示范围；L3 已 descope，不承诺运行期 |
| R82-3 | `leaks` 与 `c-boundary = strict` 混淆 | 窄键、专测；文档并列说明 |
| R82-4 | 跨单元类型缺失导致漏报 | `ct build` 全单元在场；`ct check` 单单元缺类型时静默跳过并记录 |
| R82-5 | v1.0 再顺延一个 MINOR | roadmap/D-012 明确；v1.0 范围不变 |

回滚：单卡回滚；`leaks` 配置、环检测、文档同退；`--debug-leaks` 与 D-011 不受影响。

## 5 验收记录（S82a–S82d）

| stage | 红证提交 | 实现提交 | 验收命令 | 结果 |
| --- | --- | --- | --- | --- |
| S82a 配置 | `1d36a8b1`（baseline `bf558eb7`） | `03012a3a` | `sh test/ast/p82_config.sh .temp/p82a/ct-ast` | `p82_config: OK`（13 条） |
| S82b 环检测 | `93e4fc67`（baseline `03012a3a`） | `42242e8e` | `sh test/ast/p82_cycle.sh .temp/p82b2/ct-ast` | `p82_cycle: OK`（13 条） |
| S82c 豁免/负例 | `b1097f23`（baseline `42242e8e`） | `aa18772e` | `sh test/ast/p82_allow.sh` / `p82_errors.sh` | `p82_allow: OK`（10 条）/ `p82_errors: OK`（11 条） |
| S82d 文档 | `no-test: 纯文档`（签收 EDITOR 2026-11-21） | `5526a1d2` | `sh test/ast/p82_docs.sh .temp/p82final/ct-ast` | `p82_docs: OK`（收口接入） |

S82c 的负例支（`p82_errors`）在 baseline 已绿：S82b 的边构造本来就不越过 Vec/泛型/接口/
typedef/4 边环，因此它作为 E82-4 的回归守卫与 allow 支同任务提交，红证以 allow 支的 5 条
失败为准。

## 6 T-7 提交对照

| 任务 | `test(...) 红` | 实现 | 父提交关系 |
| --- | --- | --- | --- |
| S82a | `1d36a8b1` | `03012a3a` | 实现父 = 红；红 baseline `bf558eb7` = 红的父 |
| S82b | `93e4fc67` | `42242e8e` | 实现父 = 红；红 baseline `03012a3a` = 红的父 |
| S82c | `b1097f23` | `aa18772e` | 实现父 = 红；红 baseline `42242e8e` = 红的父 |
| S82d | `no-test` 纯文档 | `5526a1d2` | 无行为改动；文档断言 `p82_docs` 在收口接入 |

## 7 收口对照（E82-1…8）

### 7.1 原始输出

```console
$ sh test/ast/p82_config.sh .temp/p82final/ct-ast
ok   no manifest: default warn, compile exits 0 and writes the C
ok   leaks = warn: build exits 0, warning, product written
ok   old manifest (no leaks key): unchanged warning, exit 0
ok   leaks = error: build exits 1 with error: on the same record
ok   leaks = error: no .c product is written
ok   compile: error package fails before writing the C (no -I needed)
ok   JSON: leaks = error record carries "severity":"error"
ok   JSON: warn package keeps the pre-PH-82 shape
ok   c-boundary: leaks = error alone does not make the package strict
ok   c-boundary: an explicit c-boundary = strict still wins
ok   leaks = error: a clean unit still exits 0 with no findings
ok   leaks = error: a clean build still succeeds
ok   leaks = error does not escalate arity (still a warning, exit 0)
p82_config: OK
$ echo $?
0
```

```console
$ sh test/ast/p82_cycle.sh .temp/p82final/ct-ast
ok   self loop C -> C is reported as a warning
ok   A -> B -> A is reported once (duplicate payload field is one edge)
ok   A -> B -> C -> A is reported (depth limit 3)
ok   a four-edge ring is not reported (limit is 3 edges)
ok   a one-way chain (D -> A -> B) is not reported
ok   a plain pointer field is not a box edge (A * B -> A alone is not a cycle)
ok   wording says may leak unless broken by hand, never will leak
ok   ct check: potential_cycle JSON carries severity error and col
ok   ct check: text finding is file:line:col: error:
ok   leaks = warn: build exits 0 and writes the product
ok   leaks = error: build exits 1 with error: on the cycle
ok   leaks = error: no .c product is written
ok   corpus: exactly one finding, the deliberate p81_box/cycle.ct self loop
p82_cycle: OK
$ echo $?
0
```

```console
$ sh test/ast/p82_allow.sh .temp/p82final/ct-ast
ok   same-line marker suppresses the tree pattern's self loop
ok   removing the marker brings the warning back
ok   a marker on the line above the struct does not suppress
ok   a marker on a field line does not suppress
ok   a marker on one participant suppresses A -> B -> A
ok   a marker on an unrelated struct does not suppress
ok   ct check: reports the suppressed point as a note and exits 0
ok   ct compile: a suppressed cycle produces no note
ok   leaks = error: a suppressed cycle does not fail the build
ok   leaks = error: removing the marker makes the build fail again
p82_allow: OK
$ echo $?
0

$ sh test/ast/p82_errors.sh .temp/p82final/ct-ast
ok   vec: no cycle warning
ok   generic: no cycle warning
ok   geninst: no cycle warning
ok   iface: no cycle warning
ok   alias: no cycle warning
ok   indirect: no cycle warning
ok   container_ring: no cycle warning
ok   corpus test/ast/05_struct/prog.ct: no cycle warning
ok   corpus test/patterns/composite/prog.ct: no cycle warning
ok   corpus test/patterns/decorator/prog.ct: no cycle warning
ok   box corpus: exactly one finding, the deliberate p81_box/cycle.ct self loop
p82_errors: OK
$ echo $?
0
```

```console
$ sh test/ast/p82_docs.sh .temp/p82final/ct-ast
ok   selfhost/l0/ctc.c CTC_VERSION 0.82.0
ok   selfhost/l1/ctc.ct CTC_VERSION 0.82.0
ok   selfhost/l2/core.ct CTC_VERSION 0.82.0
ok   selfhost/l2/driver.ct CTC_VERSION 0.82.0
ok   selfhost/ct-ast/main.ct CTC_VERSION 0.82.0
ok   README / docs/README carry v0.82.0
ok   roadmap lists Phase 82 done with v0.82.0
ok   spec has the leak-guard section (4.72)
ok   spec mentions leaks = warn|error
ok   spec mentions allow-cycle
ok   spec mentions 3 条边
ok   spec mentions 可能泄漏
ok   spec mentions 会泄漏
ok   spec mentions --debug-leaks
ok   spec mentions c-boundary
ok   spec mentions unless the cycle is broken by hand
ok   spec mentions §4.72
ok   package-guide lists the leaks key and points at §4.72
ok   patterns §5 is the tree pattern with allow-cycle and a raw parent pointer
ok   phase card has the §7 closeout
ok   card rule row E82-1
ok   card rule row E82-2
ok   card rule row E82-3
ok   card rule row E82-4
ok   card rule row E82-5
ok   card rule row E82-6
ok   card rule row E82-7
ok   card rule row E82-8
ok   card records the closeout (完成 / E82-8 ✅)
ok   --debug-leaks is still unknown (not renamed as cycle detection, D-011 J-4c)
p82_docs: OK
$ echo $?
0
```

`ct check` 的抑制点与被抑制环（手动复跑，路径为简写；`p82_allow` / `p82_cycle` 断言同一形状）：

```console
$ .temp/p82final/ct-ast check --allow-c-boundary t/allow.ct
t/allow.ct:1:1: note: reference cycle suppressed by 'ct: allow-cycle': Node -> Node
$ echo $?
0

$ .temp/p82final/ct-ast check --allow-c-boundary t/two.ct
t/two.ct:1:1: error: potential reference cycle: A -> B -> A; instances may leak unless the cycle is broken by hand
$ echo $?
1
```

### 7.2 逐条对照

| ID | 断言 | 验收输出 |
| --- | --- | --- |
| E82-1 | `leaks` 两档从 `ct.pkg` 读取；缺省 `warn`；存量包无变化 | `p82_config`：no manifest / `leaks = warn` / 旧 manifest 三路均 `warning:` + exit 0；`leaks = error` 时同一条记录变 `error:` |
| E82-2 | `warn` 不失败；`error` 同代码构建失败；`c-boundary` 语义不变 | `p82_config`：error 包 build/compile 均 exit 1 且不落 `.c`；`leaks = error` 单独不使包 strict，`c-boundary = strict` 仍 wins；arity 仍 warning + exit 0；`p82_cycle`：warn 构建写产物、error 构建失败 |
| E82-3 | 自环、A→B→A、A→B→C→A 命中；同一环一次；仅 `box<X>` 字段 | `p82_cycle`：`C -> C`、`A -> B -> A`（双载荷字段仍 1 条）、`A -> B -> C -> A`；4 边环 / 单向链 / 裸指针字段不报 |
| E82-4 | `Vec<box<T>>`、泛型参数、接口字段、typedef、间接环不报；语料零误报 | `p82_errors`：7 条形状负例 + 3 条结构语料 + box 语料唯一命中 `p81_box/cycle.ct` |
| E82-5 | `allow-cycle` 抑制告警并在 `ct check` 报告；移除后重新告警 | `p82_allow`：同行标记抑制、移除后复报、错位标记不抑制、`check` 打 `note:` 且 exit 0、compile 静默 |
| E82-6 | 文案「可能泄漏，除非手工破环」，不写「会泄漏」；`--debug-leaks` 不被改称环检测 | `p82_cycle`：`may leak unless the cycle is broken by hand` 且无 `will leak`；`p82_docs`：`--debug-leaks` 仍是 `unknown option`（D-011 J-4c） |
| E82-7 | `patterns.md` 父子结构一节；spec 记录 `leaks` 与范围/限深 | `p82_docs`：patterns §5、spec §4.72（`leaks`/`allow-cycle`/`3 条边`/`可能泄漏`/`c-boundary`）、package-guide `leaks` 行 |
| E82-8 | 旧 golden 不变；`check-all` 通过；单卡回滚 | 51 个 golden/expected + p39 ABI banner 仅版本 token 变化；§7.3 门禁；整卡回退 = S82a/S82b/S82c + 文档同退（单 stage 回退需连带其下游，S82b 依赖 S82a 的严重级别通道） |

### 7.3 门禁

```console
$ bash selfhost/check-all.sh
...
1) L0 suite (test/run.sh)
== summary: 156 passed, 0 failed ==
3) CT: check-archive
== summary: 153 passed, 0 failed ==
8) AST compiler (Phase 9.1–9.7 + 10.x–12.x + batches 13–39)
  ok    PH-82-S82a leaks config (E82-1/2: warn/error, compile/build, JSON, c-boundary)
  ok    PH-82-S82b direct cycle (E82-3/6: self/2/3-edge, depth 3, dedup, wording)
  ok    PH-82-S82c allow-cycle (E82-5: same-line marker, check note, error build)
  ok    PH-82-S82c negatives (E82-4: Vec/generic/iface/typedef/indirect, corpus clean)
  ok    PH-82-S82d docs (E82-6/7/8: spec 4.72, package-guide, patterns 5, v0.82.0)
== summary: 1545 passed, 0 failed, 4 skipped ==
9) generated C warning-free (-Wall -Wextra)
check-warnings: 490 ok, 0 failed
11) docs (links, version, gate count, phase status)
check-docs: OK (2185 relative links in 361 files, v0.82.0, 11 hard gates, 12 phase status, 5 适用版本 header(s), 2 superseded link(s), 7 signoff(s))
...
check-all: OK (11 hard gates green)
$ echo $?
0

$ env -u CT_C_BOUNDARY bash selfhost/check-warnings.sh
check-warnings: 490 ok, 0 failed
$ echo $?
0

$ bash selfhost/check-sanitizers.sh
check-sanitizers: OK (583 checks, no sanitizer report)
$ echo $?
0

$ bash tools/check.sh g0
g0: OK (block 1.17.0, session-map present)
$ bash tools/check.sh g8
g8: OK (PN-2 version coherence; 9 legacy offsets)
```

8) 的 acceptance 段（仅报告、不阻塞）：`== summary: 20 pass, 0 new, 0 pending, 0 regression ==`。
4 个 skip 为宿主条件（Renode / GDB / node）；网络探针 `PH-77-S5 external` 的跳过/通过随环境变化，
上一轮复跑为 1544 passed / 5 skipped，与本轮的差异只在它。

### 7.4 未覆盖 / 简化（诚实）

- 限深 3 条边：4 边以上的环、跨过程/跨单元转手的环不报；这是 D-012 的范围决定，不是缺陷（R82-2）。
- `Vec<box<T>>`、泛型 struct/实例、接口字段、`box<typedef>` 别名不做边；不报不代表没有泄漏。
- 运行期环检测/回收、`weak`、未释放句柄清单不在本卡；`--debug-leaks` 仍未实现，只保留
  「不把计数叫环检测」的契约（D-011 J-4c）。
- 诊断文案是英文（编译器既有风格）：`potential reference cycle: …; instances may leak unless
  the cycle is broken by hand`；中文契约「可能泄漏，除非手工破环」记在 spec §4.72。
- `leaks` 以构建的第一个输入（`ct build`）或唯一输入（`ct compile` / `ct check`）所在包为准；
  一个构建混多个包且设置不同时不做逐单元分级。
- 环按最小行号 struct 的位置报告；同一环的其它参与者不重复出诊断，只看 `ct check` 的链文本。

## 8 结论

E82-1…8 均有原始输出（E82-8 ✅）；S82a/S82b/S82c 按 T-7 红/绿成对，S82d 为 `no-test` 纯文档并由
EDITOR 签收。PH-82 收口为 v0.82.0；PH-83（包管理契约 v1，D-014）入口满足、未开工。
不 push、不打 tag（用户指令）。
