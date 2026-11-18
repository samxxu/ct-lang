# battle/inline-materialize-1 — 反对席（REVIEW）主张 B

| 项 | 值 |
| --- | --- |
| 席位 | REVIEW（反对 A） |
| 主张 | B：不新增 `.m(args)$name`；现有拆链与 `into` 已覆盖 |
| 基线 | `0c449d2e`；该提交的 ct-ast 自报 v0.65.1（question.md 记 v0.67.0），关键探针在基线与 HEAD v0.67.0 上输出一致 |
| 证据目录 | `/tmp/ct-battle-build/final`（一次性，不入库） |
| 结论 | B 在当前范围胜出；不成立条件见 §7 |

## 1. B 的语义边界

B 不主张 `into` 是万能替代。三种形态各管一段，边界必须说清：

| 场景 | B 的写法 | 依据 |
| --- | --- | --- |
| 类型改变的一跳，结果后面还要用 | `T x = e.m(); x.next();`（复用已声明变量时 `x = e.m();`） | 现有声明/赋值；`split2.ct` 实测通过 |
| 同一接收者的兄弟方法 / 多步 | `a into { .m(); .n(); }` | §4.52；`test/ast/152` |
| 同一接收者的同类型重绑 + 后缀 | `e into { $ = .m(); }.next()` | `test/ast/155`（规格未写，见 §5） |
| 静态宿主全链 | 不物化，直接一条链 | `examples/47`；`main.ct:27-32` |

关键点：A 也要先写 `HttpRequest req;`，也要在链里写 `$req`；B 的 `HttpRequest req = ...;` 与 `req.next()` 同样是两次 `req`、一次类型名。在“先声明再物化”的完整形态里两者都是两条语句；只有当变量本来就要复用时，A 才少一次赋值语句（B 是 `x = ...; x.next()`，A 是一条链），但名字和类型并没有减少（§5 有拆解）。

## 2. E1 命令与原始输出（含 B 的不利证据）

B 的不利证据一：`into` **不能改变接收者类型**，所以类型改变的一跳不能内联，只能拆链（以下命令在 `/tmp/ct-battle-build/final` 下执行；用基线二进制 `CT=/tmp/ct-battle-baseline/build/ct-ast`，`EX=/tmp/ct-battle-baseline/src/examples/47_chain_factory/src`；当前 HEAD 的 v0.67.0 输出相同）。

```console
$ $CT build -I $EX -I $EX/http --c-boundary=allow into_inline.ct -o /tmp/ct-battle-build/final/into_inline.bin
into_inline.ct:10:1: error: no method 'status' for type 'struct HttpRequest'
[exit 1]
```

B 的不利证据二：真实 6 跳链拆开后，`req` 被重复念 6 次，原链的一条表达式阅读被打断。

```console
$ nl -ba multihop.ct | sed -n '6,10p'
     6	    CRequest req = "https://api.example.com/users".method("GET");
     7	    req = req.header("Accept", "application/json");
     8	    req = req.timeout(3000);
     9	    CResponse resp = req.send();
    10	    int status = resp.status();
$ grep -o 'req' multihop.ct | wc -l
6
$ $CT build -I $EX -I $EX/http --c-boundary=allow multihop.ct -o multihop.bin && ./multihop.bin
200
[exit 0]
```

B 的不利证据三：用户明确要 inline，而不是“再想想”。

> `question.md:7`：用户认为 CT 鼓励链式，缺少 inline 物化会显得僵化；要求 battle。

```console
$ cd /Users/samxx/dsh-ws/ct-lang && grep -rn '\$[A-Za-z_]' --include='*.ct' selfhost examples test | wc -l
7
```

E1 旁证（利 B）：7 条全是注释里的 shell 变量（`$PWD` / `$CT_HOME` / `$WORK`），源码/示例/测试的**代码**里没有 `$name` 用例；J-1 的“真实需求”目前只有偏好，没有语料。

B 的回应不是否认这些成本，而是量化：多数成本是“一条语句的边界”和可读性；真正的能力缺口只出现在 §4 的 C1–C4（参数/返回位置、短路、接口多跳），而 A 也没有全部覆盖它们。A 的代价见 §5。

## 3. E2 `file:line`

| 方向 | 位置 | 事实 |
| --- | --- | --- |
| 利 B | `test/ast/155_into_value_host/prog.ct:10-18` | `$ = .add(1).add(2).add(3)` 在 `into` 内同类型重绑，块后 `.value()` 继续；实测 `mid 16 / done 16 3 / v 6`，`[exit 0]` |
| 利 B | `test/ast/152_into_trait_method/prog.ct:24-26` | `pp into { .hello("Ann"); }` 兄弟方法走 `into`；实测 `Tom says hi to Ann`，`[exit 0]` |
| 利 B | `docs/language-spec.md:2462` | `into { … }` 后接 `.field`、`->field`、`[i]`、`(args)` 等后缀，已有“块后继续”契约 |
| 利 B | `docs/language-spec.md:2131` | **`$` 不是标识符**；不新增 `$name` 就不动这条冻结语义 |
| 利 B | `selfhost/ct-ast/frontend/parse/Expr.h.ct:5363`、`selfhost/ct-ast/frontend/parse/Stmt.h.ct:1505/3366` | `$` 只在 range/into/尾随三个上下文里成立；其余位置是 `unexpected token` |
| 不利 B | `docs/language-spec.md:2458-2462` | 块的值仍是接收者本身，所以 `into` 无法把 `HttpRequest` 换成 `HttpResponse`；§2 探针实证 |
| 不利 B | `examples/47_chain_factory/src/main.ct:27-32` | 6 跳写在一条表达式里；要命名中间 `req` 就得拆成两条以上 |
| 不利 B | `issues/selfhost/sh73-temp-receiver-dynamic-dispatch.md:76-78` | 接口链只能“逐跳落变量”，6 跳 = 6 条语句；B 的可读性成本真实存在 |
| 不利 B | `docs/language-spec.md:323-326` | 右值接收者提升只允许在语句行首 / 赋值、声明初始化式行首；A 的 inline 赋值同样受此限 |
| 不利 B | `docs/language-spec.md:2735` | 可选方法调用（`?.m()`）在范围外；A 的 `?.m()$x` 依赖一个尚未实现的特性 |
| 不利 B | `docs/language-spec.md:2580` | 尾随块里的 `$` 是只读别名；`$name` 必须与 range/into/尾随三种既有义项逐一对齐 |

`$ident` 路径不存在的直接证据（三个上下文都只把 `$` 当单字符 token；均 `[exit 1]`）：

```console
$ ct-ast build -I . chain_dollar.ct -o /tmp/.../chain_dollar.bin   # builder_make(10)$b.add(1)
chain_dollar.ct:7:21: error: unexpected token
$ ct-ast check range_dollar.ct                                     # int a[] = 0..3($x);
range_dollar.ct:3:21: error: unexpected token
$ ct-ast check into_dollar.ct                                      # cfg into { $n = 1; };
into_dollar.ct:5:17: error: unexpected token
```

## 4. E3 可证伪预测与反例

B 的可证伪预测：

- **P1**：任何“类型改变的一跳”都能写成声明/赋值 + 继续，运行结果不变。`split2`、`multihop` 均为 `200`、`[exit 0]`。
- **P2**：任何“同一接收者的多步/兄弟”都能用 `into`。`152`、`155`、`examples/29` 均通过。
- **P3（强形式）**：没有合法程序只因缺少 `$name` 而无法表达；`$name` 只改语句形状，不改能力。

P3 至少被以下反例打破：

1. **类型改变的内联**：`e.m()$req.next()...send()$resp.status()` 想保持一条表达式；`into` 换不了类型（§2 原文），`split2` 只能拆成两条。此例 B 的“into 足够”为假。
2. **表达式位置**：`return a.m()$x.n();` 或 `f(a.m()$x.n())`。B 必须先声明临时量并把调用拆到语句前，无法保持一条表达式。
3. **短路**：`p?.m()$x.n()` 要求空指针时不赋值、不继续；B 要写显式 `if`。更糟的是当前 `?.m()` 本身就被拒（`opt_method.ct:10:14: error: optional method calls are not supported; assign the receiver to a variable first`，`[exit 1]`）。
4. **接口多跳**：SH-73 下 6 跳只能 6 条语句；B 的“两行”在接口链里不成立。

因此 B 的可证伪结论应写成弱形式：**两行/into 足够覆盖“声明/赋值位置 + 同类型块”；对“参数/返回位置的一条表达式 + 类型改变 + 短路”不够**。这正好卡住 question 的范围：A 自己也要求“已声明变量”，也明确不修 SH-73。

## 5. E4 代价：A vs B

| 成本 | A | B |
| --- | --- | --- |
| lexer | 在 `Lexer.h.ct:112` 的标识符分支前加 `$` 路径；`$` 单独时仍退回 `:369` 的单字符 punct | 0 |
| parser | 在 `Expr.h.ct:4500-4515` 的 `N_MCALL` 后识别 `$name`；同时在 range/into/尾随三处（`Expr.h.ct:5363`、`Stmt.h.ct:1505/3366`）排除；还要禁止链尾 `$name` | 0 |
| 类型/所有权 | 赋值给已声明变量：vptr、接口装箱、`own`、`?.` 跳过、未初始化；A 的“纯 desugar”实际是赋值语义 | 0（声明/赋值已有） |
| emit | 把赋值提升到语句前；受 `docs/language-spec.md:323-326` 的位置限制；`?.` 还要条件赋值 | 0 |
| 测试/规格 | 至少新增 mid/end、range、into、尾随、`?.`、类型不匹配、重复物化等夹具 | 0；仅 `into { $ = … }` 的规格缺口（见下） |
| 兼容 | `$` 从 3 个义项变 4 个；无合法代码被破坏的强证据，但错误文案与上下文判定都要重审 | 不动 golden，不动生成物 |

量化：A 至少触及 4 个文件（`Lexer.h.ct` 383 行、`Expr.h.ct` 7280 行、`Stmt.h.ct` 4154 行、`Emitter.h.ct` 6613 行），估算 150–400 行 + 10–20 个夹具；B 是 0 行源码。A 还有两个未闭合前提：

```console
$ cd /Users/samxx/dsh-ws/ct-lang && grep -rn "uninitialized\|未初始化" selfhost/ct-ast docs/language-spec.md
[exit 1]
```

即 A 的第 5 条“未初始化使用按既有检查报错”**没有既有检查**；要兑现就得新增 definite-assignment 分析。另，A 第 6 条的 desugar 写 `T x = <call>`，但第 2 条说 `name` 已声明；若真是声明，它就是 B 的第一行；若是赋值，就要承担上表的赋值语义，不能叫“纯 desugar”。A 的第 5 条 `?.m()$x` 还依赖未实现的 L53-7（`docs/language-spec.md:2735`）。

B 的规格缺口也如实记账：`test/ast/155` 的 `$ = .add(...)` 在 §4.52 正文没有描述（`:2442-2466`），B 若长期依赖它，应补 2–3 行文档；这是文档修正，不是新语法。

## 6. E5 steelman A 与逐条反驳

| A 的最强论点 | 反驳 |
| --- | --- |
| CT 鼓励链式，`examples/47` 的 6 跳就是标准形态；拆链反语言习惯 | `examples/47` 是静态宿主，整条链**现在就能跑**，不需要 `$name`；接口链被 SH-73 挡住，A 不修 SH-73，所以 A 不能把 `examples/47` 的形态推广到接口 |
| `into` 换不了类型，这是真实缺口，`$name` 正好补上 | 缺口真实，但补法是“声明/赋值 + 继续”，`split2` 已通过；A 也要先声明变量、也要写名字，完整形态里不减少语句总数，只把 `=` 换成 `$` |
| `$name` 是纯 desugar，无运行时成本、不动所有权 | 提升赋值会动求值顺序（`:323-326` 已把提升限制在行首/赋值右值）；`?.` 短路、vptr、接口装箱、未初始化都要定义；这不是“纯” |
| `$name` 与 `into` 互补：into 管兄弟，`$name` 管换类型 | 互补成立，但边界很窄：只允许“方法调用后”，不允许链尾、字段、下标；用户要记 4 个 `$` 义项和一条链尾禁令，学习成本高于两条语句 |
| 用户已明确要求 inline，battle 就是为它开的 | 用户要求的是评估，不是语法命令；J-1 要求真实价值而非“少一个分号”。本仓 0 处真实 `$name` 需求，13 个 into 夹具已覆盖现有形态 |

## 7. 结论

**B 在当前基线胜出。** 理由：A 的动机例子在静态宿主上已可一条链（`examples/47`），在接口链上仍被 SH-73 挡住；A 在完整形态里不减少名字/类型/语句总数，只移动语句边界；A 的 `?.m()$x` 依赖未实现的 L53-7，A 的“未初始化既有检查”不存在；A 要改 lexer/parser/emit/测试，B 零源码改动。B 的拆链/into 已被 `152`、`155`、`examples/29`、`split2`、`multihop` 实测覆盖。

**B 不成立的条件**（出现任一，应重开而不是直接采纳 A）：

1. 把“参数/返回位置的一条表达式 + 类型改变”列为硬需求（反例 C2）；
2. 把 `?.m()$x` 的短路内联列为硬需求（反例 C3，需先做 L53-7）；
3. 要求接口链保持一条表达式（这应修 SH-73，不是加 `$name`）；
4. 真实语料显示逐跳拆链的维护成本显著高于新增语法的成本（需给出样例与度量，不能只用“僵化”）。

建议：采纳 B；若 B 被采纳，顺手把 `test/ast/155` 的 `$ = …` 写进 §4.52（文档修正），并用现有 `$name` 报错加一条负例钉住 J-2。
