# battle/p39-1 反证书（反对席 REVIEW）

| 字段 | 值 |
| --- | --- |
| 争点 | `ct build --lib` 导出面：A 全量 `pub` + 非 C 兼容硬错 L39-1 vs B 显式标记/清单 |
| 立场 | **反对 A**（不提出替代方案；替代方案按 §7.10 另出） |
| 证据环境 | 干净 HEAD `ac040d1`，`/tmp/p39head/ct`（v0.37.0），源码 `/tmp/p39head/src` |
| 重跑方式 | 下列命令全部在 `/tmp/p39head/src` 下执行，只读；产物落 `/tmp/p39e1` |

**结论一句话**：A 把 CT 的 `pub`（跨单元可见）直接等同于"对外 ABI 承诺"，在仓库内**标准可复用库夹具** `test/modules/p34_pub_generic` 上按 A 自己的规则必然 L39-1、整库不产；同一张卡对"泛型 pub"又同时写了"不导出"（跳过）与"硬错"（中止）两种处置。故 A 违反 J-1、J-2，且不满足其最强卖点"可预测"。

---

## 1 反证清单：A 的失效条件（可观测、可复现）

> 每条给"触发条件 / 观测 / 复现锚点"。这些条件不是假想：C1、C2、C6 在 HEAD 上已有真实夹具与产物。

### C1 只要有一次构建里存在泛型 `pub` helper，A 就整库判死 —— 违反 J-1、J-2

- **触发条件**：本次构建任一非内建 `.h.ct` 单元含 `pub T f<T>(…)`（带定义）。
- **观测**：按 A 的规则 1（`pub` + 有定义 → 进导出面）与规则 3（签名含泛型 → 违规），报 L39-1，**不写任何产物**（`.a` / `.abi.h` 都不产生）。
- **HEAD 实例（3 个函数 / 3 个文件）**：
  - `test/modules/p34_pub_generic/lib.h.ct:3` `pub T id<T>(T x)`
  - `test/modules/p34_pub_bound/lib.h.ct:21,26` `pub T id<T>(T x)` / `pub T max2<T: Compare>(T a, T b)`
  - `examples/38_ecosystem_reuse/src/eco.h.ct:24` `pub T twice<T>(T x) {`
- **为什么这不是"坏代码"**：`p34_pub_generic` 正是"可复用库 + 消费方"的正例（`main.ct` 直接调 `id<int>`，所以 `id` 必须是 `pub`）。作者要导出的只有 C 包装器 `from_lib`；`id` 只是同头里的泛型 helper。A 不给作者"只导出 `from_lib`"的任何入口 → 导出集合 ≠ 作者意图，J-1 夹具 2 直接失败。
- **复现**：§2 E1-a/E1-b。

### C2 A 的判据是"全量函数集合"，体系里不存在"导出子集"的输入 —— 违反 J-1

- **触发条件**：任何时候作者只想导出 `pub` 集合的一个真子集。
- **观测**：A 的导出面定义（`phase39-draft.md:37`）逐字为"本次构建所有非内建 `.h.ct` 单元的有定义 `pub` 函数"，没有任何过滤输入（无清单、无标记、无白名单）。结果只有两种：全部导出，或任一签名不合规 → 全部不产。**没有"只导出想要的"这一档。**
- **为什么这是 CT 的结构性问题**：`pub` 是跨单元可见的唯一手段（`docs/language-spec.md:617`："其它单元 `import` 后即可按名引用。`pub` 只表示导出：未标 `pub` 的全局仍只属于本单元。"；`:534`：`.h.ct` "发布类型、`pub` 声明与 vtable 接口"）。跨单元 helper 必须 `pub`，于是**每个内部 helper 都被 A 抓进 ABI**。
- **量化**：`selfhost/ct-ast/**/*.h.ct` 当前有 **72 个**顶层 `pub` 函数；典型内部访问器如 `selfhost/ct-ast/frontend/sym/Symbols.h.ct:423` `pub int ct_impl_add(…)`、`:431` `pub int ct_tmpl_find(const char *name)`。把这类工程改成 `--lib`，A 会把这 72 个全部写进 `.abi.h` ——恰好是 J-1 要排除的"作者没打算导出的集合"。

### C3 卡内自相矛盾：同一个"泛型 `pub`"，一处说跳过、一处说硬错

- **触发条件**：实现者/R1–R2 任务读卡实现"泛型 pub 怎么办"。
- **观测**：`phase39-draft.md:45` 写"不导出泛型函数……三者都不写进 `.abi.h`"（语义 = 跳过、继续构建）；`:102` 规则 3 写"签名里没有……泛型参数"为**进入导出面**的必要条件；`:104` 写"违反 2/3 报 L39-1……不写任何产物"；`:134` L39-1 表把"泛型"列为硬错。**同一文件、同一函数，两条相反的处置。**
- **后果**：A 的"可预测"承诺在卡面内部就不成立；实现者可能实现成跳过，也可能实现成中止，作者无法从文档预知。J-5（可诊断）要求的"原因"在这里先于实现就是二义的。

### C4 `pub` 语义被偷换：跨单元可见 ≠ 对外 ABI

- **触发条件**：任何沿用现有 `pub` 写法的库（本仓库全部 `.h.ct` 都是）。
- **观测**：`pub` 的既有定义是单元间链接（`docs/language-spec.md:617`、`:534`、`:629` "跨单元可装箱的边界"）。A 把"单元间可见"重绑为"对外 ABI 承诺"，等价于给**每一行已存在的 `pub`** 追加一个从未商定的外部契约。这不是"零成本"，而是把成本从编译器作者转移到所有库作者：要么删 `pub`（破坏既有消费方），要么另建包装单元。
- **可观测实例**：`p34_pub_generic/main.ct` 依赖 `id<int>` 是 `pub`；删 `pub` 即编译失败。所以"改一下标记"不是零成本选项。

### C5 "非内建"口径未定义，且 std 的 `pub` 符号在归档里照样是外部符号

- **触发条件**：库使用了 `lib/std`（Vec/Map/Str）或包管理器拉入的 `vendor/std`。
- **观测一（口径）**：A 只写"非内建"，而内建判定是 `selfhost/ct-ast/frontend/module/Module.h.ct:453` `is_builtin_unit()`，来源 `find_builtin()`（`:427-441`）只认 `CT_STD_DIR`、`lib/std/<base>`、`<输入目录>/../lib/std/<base>`。`vendor/std` 不在其中 → 包 std 是普通单元 → `lib/std/Str.h.ct:33,51,63,70,80,99,117` 的 7 个值类型 `Str` 的 `pub` 函数全部触发 L39-1。J-2 要求"`lib/std/**/*.h.ct` 不改一行即可构成 `--lib` 库"，在 A 下这半句要么失败（vendor/std），要么因内建跳过而不可测。
- **观测二（符号面）**：`-fvisibility=hidden` 不会把 std 的 `pub` 函数从 `nm -g` 里去掉。见 §2 E1-d 的原始输出：`Str.o` 仍有 9 个 `T` 符号。A 承诺"导出函数是唯一 default 可见的符号"（`phase39-draft.md` §3.3）而卡片自己在 `:40` 承认"visibility 不改变静态归档的全局符号表"——两处结论互相否定。

### C6 "把现有可执行工程改造成库"变成全量改造 —— 违反 J-2

- **触发条件**：把一个已经在跑的工程（如 `test/modules/p34_pub_generic`、`examples/38_ecosystem_reuse`）加 `--lib` 产出库。
- **观测**：不改源码则 C1 的 L39-1 中止；要过 A，必须删/改 `pub`（破坏消费方）或新增一层 C 包装单元（新文件 + 新函数 + 新测试）。J-2 的"不改一行"在 A 下对 `test/modules` 已有 2 个文件 / 3 个函数不成立。
- **复现**：§2 E1-a 证明这些文件今天能构建运行；§2 E1-c 给出 A 判死它们的规则原文。

---

## 2 E1：命令 + 原始输出

> 诚实边界：HEAD `ac040d1` **尚未实现 `--lib`**（`/tmp/p39head/ct build --help` 无该选项，见 E1-e），所以无法运行真实的 L39-1。E1 由三段组成：①该头今天确实是一个可用的可复用库（可运行）；②其泛型 helper 在生成 C 里**不是** ABI 符号（`nm` 实测）；③A 的规则原文对同一函数判死（规则照抄，file:line）。三段合起来即可机械推出"整库不产"，不是伪造编译器输出。

### E1-a 正常头文件今天可以构建并运行

```console
$ mkdir -p /tmp/p39e1 && cd /tmp/p39head/src
$ /tmp/p39head/ct build test/modules/p34_pub_generic/main.ct -o /tmp/p39e1/app
'cc' -std=c99 -I '.ctbuild' '.ctbuild/Vec.c' '.ctbuild/Option.c' '.ctbuild/Result.c' '.ctbuild/Str.c' '.ctbuild/main.c' '.ctbuild/lib.c' '-o' '/tmp/p39e1/app'
$ /tmp/p39e1/app
3 3 4
$ echo $?
0
```

### E1-b 该 helper 在生成 C 里是 `static`，根本不进 ABI

```console
$ /tmp/p39head/ct build --emit-c -o /tmp/p39e1 --emit-map /tmp/p39e1/map.json test/modules/p34_pub_generic/main.ct
$ cc -c -fvisibility=hidden /tmp/p39e1/lib.c -o /tmp/p39e1/lib.o
$ nm /tmp/p39e1/lib.o | grep -E 'id__ct1|from_lib'
0000000000000000 T _from_lib
0000000000000024 t _id__ct1
```

`T` = 唯一 external（就是作者要导出的 `from_lib`）；`t` = static（`id` 的实例化，不可能是导出符号）。**作者意图 = {from_lib}，而 A 在源码声明行把 `id` 判死。**

### E1-c A 的规则原文（照抄 grid，file:line）

```console
$ cd /tmp/p39head/src && grep -n "不导出泛型\|泛型\|L39-1\|导出面 = " docs/design/phase39-draft.md | sed -n '1,12p'
6:> **前置**：[phase34-draft.md](phase34-draft.md)（`pub` 语义；本相只导出非泛型 `pub`）、[phase36-draft.md](phase36-draft.md)（`Str` 的 ABI 边界）、[phase38-draft.md](phase38-draft.md)（收口基线）。
17:| 范围 | O1/O2/O3；不导出按值 struct / `pub` 全局 / 泛型 / `pub extern`；不做 dylib、MSVC、版本协商 |
37:| O2 | 导出面 = 本次构建所有非内建 `.h.ct` 单元的有定义 `pub` 函数；签名不 C 兼容即 L39-1 | 无导出面概念 |
45:- 不导出 `pub` 全局变量；不导出泛型函数与 `pub extern`（定义在库外的 C 符号）——三者都不写进 `.abi.h`。
60:| D39-6 | v1 只收标量 / 指针 / 函数指针 / 数组参数 / 指向具名 struct 的指针；按值 struct、trait 值、泛型、std 容器类型一律 L39-1 | 不透明前置声明与按值传参不可兼得 |
102:3. 签名里没有按值 struct/union、trait/接口值（`*_iface`）、泛型参数、`Vec`/`Map`/`Option`/`Result`/`Str` 等 std 类型、`own`。
104:违反 2/3 报 L39-1（位置在声明行），不写任何产物。`pub extern` 不进导出面（D39-2）。
134:| L39-1 | 导出签名含按值 struct / trait 值 / 泛型 / std 类型 / `own` | `'<name>' cannot be exported: <reason>` |
```

- 规则 1：`id` 是 `pub` 且本构建有定义（`main.ct` 还实例化了它）→ **进导出面**。
- 规则 3：签名含泛型参数 → **违规**。
- `:104`：报 L39-1，**不写任何产物**。
- 而 `:45` 又说"不导出泛型函数"（跳过）。**同一函数，两条相反处置。**

### E1-d `-fvisibility=hidden` 挡不住 std 的 `pub` 符号（C5 观测二）

```console
$ cd /tmp/p39head/src && cc -c -fvisibility=hidden /tmp/p39e1/Str.c -o /tmp/p39e1/Str.o && nm -g --defined-only /tmp/p39e1/Str.o
0000000000000134 T _Str_release
0000000000000000 T _Str_retain
000000000000052c T _str_c_str
00000000000003f8 T _str_compare
00000000000002cc T _str_concat
0000000000000178 T _str_from
0000000000000048 T _str_from_len
00000000000001f0 T _str_len
0000000000000208 T _str_slice
```

### E1-e HEAD 无 `--lib`（诚实边界）

```console
$ /tmp/p39head/ct build --help
usage: ct build <input.ct>... [-o <exe>] [-I <dir>] [--ns-root <dir>]
                 [--emit-c] [--runtime-checks] [--outdir <dir>] [--cc <path>]
                 [--cflags <s>] [--ldflags <s>]
                 [--line|--no-line] [--emit-map <file|->]
                 [--diagnostics=text|json] [--std=c99|gnu99]
```

### E1-f J-2 统计（`grep` + 解析，HEAD）

```console
$ cd /tmp/p39head/src && python3 /tmp/p39_counter/scan.py test/modules lib/std | head -40
test/modules/p34_pub_bound/lib.h.ct:21: [generic] pub T id<T>(T x)
test/modules/p34_pub_bound/lib.h.ct:26: [generic] pub T max2<T: Compare>(T a, T b)
test/modules/p34_pub_generic/lib.h.ct:3: [generic] pub T id<T>(T x)
lib/std/Str.h.ct:33: [std:Str] pub Str str_from_len(const char *p, int n)
lib/std/Str.h.ct:51: [std:Str] pub Str str_from(const char *s)
lib/std/Str.h.ct:63: [std:Str] pub int str_len(Str s)
lib/std/Str.h.ct:70: [std:Str] pub Str str_slice(Str s, int start, int n)
lib/std/Str.h.ct:80: [std:Str] pub Str str_concat(Str a, Str b)
lib/std/Str.h.ct:99: [std:Str] pub int str_compare(Str a, Str b)
lib/std/Str.h.ct:117: [std:Str] pub char *str_c_str(Str s)
-- pub top-level functions scanned: 54
```

（`test/modules` 内共 54 个顶层 `pub` 函数，3 个在 2 个文件里触发 A 的 L39-1。`selfhost/ct-ast` 同法扫描得 72 个，见 C2。）

---

## 3 E2：`file:line` 锚点（≥2，且至少 1 条不利于己方）

| # | 锚点 | 原文要点 | 对哪方有利 |
| --- | --- | --- | --- |
| E2-1 | `test/modules/p34_pub_generic/lib.h.ct:3` | `pub T id<T>(T x)` —— 仓库自带的"可复用库"夹具里就有泛型 `pub` helper，且消费方依赖它 | 利于己方 |
| E2-2 | `docs/design/phase39-draft.md:102` + `:104` + `:134` | 泛型进导出面 → L39-1 → 不写任何产物（硬错中止） | 利于己方 |
| E2-3 | `docs/design/phase39-draft.md:45` | "不导出泛型函数……三者都不写进 `.abi.h`"（跳过，与 E2-2 互斥） | 利于己方（可预测性反证） |
| E2-4 | `docs/language-spec.md:617` | "其它单元 `import` 后即可按名引用。`pub` 只表示导出：未标 `pub` 的全局仍只属于本单元" —— `pub` 是单元间可见，不是对外 ABI | 利于己方 |
| E2-5 | `selfhost/ct-ast/frontend/sym/Symbols.h.ct:423` | `pub int ct_impl_add(…)` —— 编译器自己的跨单元内部访问器，A 会把它写进 ABI（72 个之一） | 利于己方 |
| **E2-6（不利于己方）** | `docs/design/phase39-draft.md:5` | "2026-11-13，用户批准三项决策均取 A：导出面只收指针、禁用构造硬错、现在冻卡" —— 用户已在方向上选过 A 味的三项 | **不利于己方** |
| **E2-7（不利于己方）** | `AGENTS.md:469` | "涉及行为变更（新增语法、改变命名、改变 CLI）必须先向用户说明方案并获得确认" —— B 的语法/清单方案天然要过一次用户批准 | **不利于己方** |

**为何 E2-6 仍不足以判 A 成立**：用户批准的是"**导出面里能放什么签名**"（D39-6 的按值 struct / trait 值 / 泛型 / std 类型一律拒绝）与"禁用构造硬错"。这回答的是 J-1 的后半句"不把其余判死"里的**签名合规性**；它没有回答 J-1 的前半句"**能否只导出作者要的子集**"。本庭争点恰恰是选择机制，而 `question.md:7` 自己写明该机制是"代决结论，未过庭"。且"硬错"的对象是否包含"作者根本没打算导出的 helper"，卡面本身在 `:45` 与 `:102/:134` 之间没有定论（C3）。所以用户签字不能补上 J-1 的缺口。

**为何 E2-7 仍不足以判 B 成立**：本席只负证伪，不主张 B 成立。即使 B 需要一次语法批准（J-3 要用户证据），那也只是 B 的成本，不能证明 A 满足 J-1/J-2。`§7.9` 明确："`rejected` 不等于'反对席的方案成立'"。

---

## 4 E3：可证伪预测

| # | 预测 | 一次性验证方式 | 若预测失败 |
| --- | --- | --- | --- |
| P1 | A 实现后，`ct build --lib test/modules/p34_pub_generic/lib.h.ct` **非零退出**，诊断含 `'id' cannot be exported: generic` 与 `lib.h.ct:3`，且目录中无 `.a` / `.abi.h` | R2 落地后跑一次，看退出码与 stderr | A 若改为"跳过泛型"，则 C3 的自相矛盾坐实，且仍违反 J-1（`id` 消失可以，但作者也无法只导出 `from_lib` 而保留 `id` 的跨单元可见性——除非 A 明确"泛型 pub 只对 CT 可见、不进 ABI"，这又回到 B 的选择问题） |
| P2 | A 实现后，任何使用 `Str` 的 `--lib` 构建，`nm -g lib<base>.a` 至少含 `_str_from`/`_str_len`/`_str_c_str` 三个外部符号，与 `.abi.h` 声明集合不等 | `ct build --lib` 一个 import `std::str` 的头，`nm -g` 对比 `.abi.h` | 预测成立即证明"导出面 = ABI 承诺"在链接层不成立 |
| P3 | 若 A 声称"`test/modules/**` 不改一行成库"（J-2），则 `p34_pub_bound/lib.h.ct`、`p34_pub_generic/lib.h.ct` 必有一个不能成库 | 各跑一次 `--lib` | 若都能成库 → A 的实现违背 `:102/:134`（泛型硬错），A 的两条规则必须有一条被删 |
| P4 | 若把 `selfhost/ct-ast` 当 `--lib` 构建，`.abi.h` 原型数 ≥ 70（=72 减去内建/无定义） | 统计 `.abi.h` 中 `(` 行数 | 若远小于 70，说明 A 的"全量 pub"定义没有按卡面实现，J-1 的"可预测"再失一分 |

---

## 5 E4：若 A 被判死，替代方案的最小代价估计

> 只作代价估算，不构成替代方案提案（§7.10 另出）。关键事实：A 在 HEAD 上**一行源码都没实现**（E1-e），所以改判的沉没成本为 0。

| 项 | 最小替代：`--export <清单文件>`（按 C 符号名过滤） | 语言内标记：`pub export`（B1） |
| --- | --- | --- |
| 改动文件 | `selfhost/ct-ast/tool/driver/Driver.h.ct`（解析选项/读清单）、`selfhost/ct-ast/frontend/module/Module.h.ct`（过滤导出面 + 清单项缺失报错） | `Parser.h.ct`（限定词识别）、`Symbols.h.ct`（`Func.is_export`）、`Module.h.ct`（导出扫描）、`Driver.h.ct` |
| 行数 | 约 **50–70 行** | 约 **100–160 行** |
| 语法批准 | **0**（无新语法） | **1 次**（AGENTS.md:469；另 §9 清单 8 项：tmLanguage、examples、golden、错误夹具…） |
| CLI 批准 | 1 次（`--export` 是新增 CLI 面，同样受 AGENTS.md:469 约束） | 0（`pub export` 落在语法侧） |
| 门禁影响 | 只新增 `check-ast.sh` 的 p39 段与 `test/modules/p39_lib/**`；G1/G3/G4 既有判据不动 | 同左 + `test/errors` 负例 + 文档语法表 |
| 回退 | 删除 `--lib`/`--export` 分支即可；`ct build` 与 `--emit-c` 逐字节不变（`phase39-draft.md:144` 已是承诺），无 golden 变更 | 回退需同时撤语法、文档、编辑器高亮，面更大 |
| 对既有夹具 | `p34_pub_generic` 用 `--export from_lib` 即可成库，源码 0 改动（J-2 成立） | 需要给 `from_lib` 标 `pub export`，`id` 不动 → 源码 1 行/库；J-2 的"零改动"字面不成立 |
| 卡面代价 | 只需改 `phase39-draft.md` §1.3 / §3.1 / D39-6 / L39-1 / R2 / 夹具表（约 20–30 行文档） | 同左 + 语言规范一节 |

**回退 A 的具体步骤**：A 未落地 → 删 `phase39-draft.md` 中 §1.3/§3.1 的"全量 pub"与 L39-1 的"泛型"项、把 R2 的 `p39_export_generic` 夹具改为"跳过不导出"或删除；`git diff` 只涉及 `docs/design/phase39-draft.md` + `test/modules/p39_lib/**` + `selfhost/check-ast.sh` 的 p39 段，不改任何既有 golden。

---

## 6 E5：预判主张席最强论点并回应（**预判**）

> 以下引文为**预判**（本席未读 `claim.md`，依据 question.md 与卡面重构其最强形态）。

**最强论点（预判）**："A 可预测、零新语法。`phase39-draft.md:37` 一行就说清了：导出面 = 所有非内建 `.h.ct` 的有定义 `pub` 函数；不需要新增关键字，不需要用户再批一次语法（`AGENTS.md:469` 是对 B 的硬门槛），实现与测试都能机械枚举。"

**回应**：

1. **"可预测"已被 A 自己打破**：`:45`（不导出泛型 = 跳过）与 `:102/:104/:134`（泛型 = L39-1 中止）对同一函数给出相反处置（C3）；`:40` 承认 visibility 不改变归档符号表，而 §3.3 又要求 `nm -g` 等于导出面（C5）。一个在自家卡面里二义的规则，不能叫可预测。
2. **"零新语法"是把成本藏起来，不是消除成本**：A 不新增语法，但它给**每一个已存在的 `pub`** 追加了"A 对外 ABI 承诺"的新语义。这是语义变更，成本落在所有库作者身上：`p34_pub_generic`/`eco` 要么删 `pub`（破坏消费方），要么加包装单元（C6）。零语法 ≠ 零代价。
3. **J-3 不能凌驾 J-1/J-2**：`question.md` 的判据是并列的；A 在 J-1 上已用仓库自带夹具实测失败（E1-a/E1-c），在 J-2 上有 2 个文件 / 3 个函数不成立（E1-f）。语言面最小是加分项，不是豁免项。
4. **用户的签字不覆盖选择机制**：`:5` 批的是"导出面只收指针/禁用构造硬错/现在冻卡"，`question.md:7` 写明选择机制是"代决结论，未过庭"。E2-6 是己方最弱处，但它证的是"签名限制"，不是"全量 pub"。

---

## 7 己方最弱处（自助披露）

- **B 至少要一次用户批准**：无论是 `pub export`（语法）还是 `--export`（CLI），都命中 `AGENTS.md:469`。A 在这点上确实更轻。若裁判把 J-3 读成"语言面零新增是硬门槛且优先于 J-1"，A 在 J-3 上占优——但 J-1/J-2 的失败与 B 无关，A 仍应 `rejected`（`§7.9`：rejected 不等于 B 成立）。
- **E1 不是真实 `--lib` 运行**：HEAD 无该分支（E1-e），L39-1 一段是"规则照抄 + 锚点"，不是编译器 stderr。证据强度依赖卡面文本的权威性；若裁判认为"未实现的规则可以改"，则 A 可被改写为"泛型 pub 跳过"，C1/C6 会弱化为"仍无法选择性导出"。
- **A 的可实现性未受挑战**：A 能实现、能测试，本席不主张它不可实现，只主张它不能满足 J-1/J-2（意图一致、零改动）。
