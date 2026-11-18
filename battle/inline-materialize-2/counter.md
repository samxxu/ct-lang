# battle/inline-materialize-2 · 反证（B：不做新语法）

| 项 | 值 |
| --- | --- |
| 席位 | REVIEW（主张 B） |
| 锚点 | HEAD `f6b4520c`（v0.67.0）。question 写的 `0c449d2e` 实际是 v0.65.1；工作树另有 v0.68.0 版本号/文档改动，`selfhost/ct-ast/{backend,frontend,tool,runtime}` 与 HEAD 逐字节相同 |
| 证据二进制 | `/tmp/b2/ct`（v0.68.0，按 `selfhost/README.md:44-52` 自举；未改仓库） |

## 0 结论

**B 胜**：不新增 `$name`。用户已确认的那类站点（语句/赋值位置）用两行拆链，兄弟方法用 `into`，源码改动 0 行。
A 的增量只在“表达式内的链”和“动态派发多跳压成一行”，而 A 的三条承重墙没有闭合：“已初始化”无可执行判据、类型相等无现成检查、表达式位置没有发射语义；B 的不成立条件见 §7。

## 1 B 的边界：两行 / into 各自适用

| 站点 | 现有写法 | 判定 |
| --- | --- | --- |
| 语句/赋值位置的静态宿主链（examples/47 五跳） | 按类型边界拆 2–3 行 | 等价：spec:323-324 保证只在这两类位置提升、不改变语义；E1-b 输出相同 |
| 同一接收者上的兄弟方法 | `a into { .m(); .n(); }` | 覆盖：test/ast/157:15-21、152:22-26 可跑（E1-b） |
| 动态派发多跳（接口值） | 每跳一个具名变量 | B 的代价是 O(跳数) 行，不是“两行”（E1-a；spec:736-740） |
| 接口值 / `own` 接收者 | 只能逐跳变量 | `into` 不适用（spec:2465，L30-4；E1-d） |
| 短路 / 条件表达式内的静态宿主链 | 两行拆链会把求值移出条件 | **不等价**（E1-c 实测 0 vs 2）；B 不覆盖，A 也未定义此处发射形态 |

## 2 E1 命令与原始输出

### E1-a（B 不利）：动态多跳的真实拆分负担，需求已确认

probe 与 `test/ast/errors/temp_receiver_trait_chain.ct` 同形（去掉 self 解引用，使拆分版能过 cc；以下为 `main` 体）：

```ct
trait M { M next(void); int val(void); }
struct S { int n; } use M;
impl M for S { M next(void) { struct S t; t.n = 2; return t; } int val(void) { return 7; } }
/* 一行版 */  struct S s; s.n = 1; M i = s; return i.next().val();
/* 拆分版 */  struct S s; s.n = 1; M i = s; M j = i.next(); return j.val();
```

```console
$ CT_C_BOUNDARY=allow /tmp/b2/ct build dyn2_fail.ct -o /tmp/b2/p/dyn2_fail
dyn2_fail.ct:12:1: error: method receiver must be a variable, an element, a call or a field chain
rc=1
$ CT_C_BOUNDARY=allow /tmp/b2/ct build dyn2_split.ct -o /tmp/b2/p/dyn2_split
'cc' -std=c99 -I '.ctbuild' '.ctbuild/dyn2_split.c' '-o' '/tmp/b2/p/dyn2_split'
rc=0
$ /tmp/b2/p/dyn2_split; echo exit=$?
exit=7
```

2 跳 = 2 条语句 + 2 个具名变量；spec:736-740 明确“每个中间结果都必须落变量”，5 跳就是 6 条语句。
用户需在 `question.md:7` 已确认。这条对 B 不利，但不构成 A 的胜利：见 §6。

### E1-b（B 有利）：确认站点等价

```console
$ CT_C_BOUNDARY=allow /tmp/b2/ct build -I examples/47_chain_factory/src \
    examples/47_chain_factory/src/main.ct -o /tmp/b2/p/ex47
'cc' -std=c99 -I 'examples/47_chain_factory/src/http' -I '.ctbuild' '.ctbuild/main.c' '-o' '/tmp/b2/p/ex47'
$ /tmp/b2/p/ex47
200 {"users":3}
```

同一副本把 `main.ct:27-32` 拆成 `HttpRequest req = …timeout(3000); HttpResponse res = req.send(); int status = res.status();` 后，`200 {"users":3}` 逐字节相同；`into` 侧：`test/ast/157_into_chain` 构建 rc=0，输出三行 `1 2 3`、`5 7 3 / 3`、`7 7`，`test/ast/152_into_trait_method` 构建 rc=0 输出 `Tom says hi to Ann`。

### E1-c（B 不利，边界）：短路表达式里拆链不等价

`c && "x".tap().tap()`（`tap` 计数并返回原指针；构造探针，非仓内语料）：

```ct
/* one() */   int c = 0; int r = c && "x".tap().tap();
/* split() */ int c = 0; char *t = "x".tap().tap(); int r = c && t;
```

```console
$ cd /tmp/b2/p/sc && CT_C_BOUNDARY=allow /tmp/b2/ct build -I . one.ct -o /tmp/b2/p/sc_one && /tmp/b2/p/sc_one
'cc' -std=c99 -I './side' -I '.ctbuild' '.ctbuild/one.c' '-o' '/tmp/b2/p/sc_one'
0 0
$ cd /tmp/b2/p/sc && CT_C_BOUNDARY=allow /tmp/b2/ct build -I . split.ct -o /tmp/b2/p/sc_split && /tmp/b2/p/sc_split
'cc' -std=c99 -I './side' -I '.ctbuild' '.ctbuild/split.c' '-o' '/tmp/b2/p/sc_split'
0 2
```

两者都编译（rc=0）；拆分把副作用从“条件为真才执行”变成“无条件执行”。所以“已等价”必须限定到语句/赋值位置，不能写成无条件命题。

### E1-d（A 现状 / into 边界）

```console
$ CT_C_BOUNDARY=allow /tmp/b2/ct build dollar.ct -o /tmp/b2/p/dollar
dollar.ct:12:20: error: unexpected token
$ CT_C_BOUNDARY=allow /tmp/b2/ct build into_iface.ct -o /tmp/b2/p/into_iface
into_iface.ct:8:7: error: 'into' cannot take an interface or 'own' receiver
```

`dollar.ct` 把 `i.next().val()` 写成 `i.next()$j.val()`；parser 没有 `$name` 分支，“零新分支”不成立。

## 3 E2：file:line（当前 HEAD）

| 方向 | 锚点 | 内容 |
| --- | --- | --- |
| 利 B | `docs/language-spec.md:323-324` | 物化只在语句行首/赋值右值，提升不改语义 → 拆链等价有规约基础 |
| 利 B | `test/ast/157_into_chain/prog.ct:15-21` | 连续 `into` 段合法（兄弟方法） |
| 利 B | `test/ast/152_into_trait_method/prog.ct:22-26` | `into` 块内 trait 派发可跑 |
| 不利 B | `docs/language-spec.md:736-740` | “每个中间结果都必须落变量” → 动态链 O(跳数) 行 |
| 不利 B | `docs/language-spec.md:2465` | `into` 禁止接口/own 接收者 → 替代方案不完整 |
| 不利 B | `docs/language-spec.md:318` | 类型宿主不受接收者限制 → 可进入短路表达式（E1-c） |
| 不利 B | `selfhost/ct-ast/backend/emit/Emitter.h.ct:5514` | `N_MCALL` 接收者被白名单拒，动态链只能拆 |

## 4 E4：代价对比

| 项 | A（最小 `$name`） | B |
| --- | --- | --- |
| 源码 | 3–4 文件：`frontend/parse/Expr.h.ct:4479`（后缀链）、`Expr.h.ct:675`（`arg_class`）、`backend/emit/Emitter.h.ct:2520/5514`；150–400 行（battle-1 verdict:14） | 0 文件 / 0 行 |
| 规范 | 5 节：§4.5、§4.10.1、§4.47、§4.52、§4.58，`$` 增第 4 义项 + 诊断表 | 0（可选 into 教程） |
| 测试/golden | 正例、`--types` 负例、ASan/所有权矩阵、`--emit-c` golden | 0 |
| 门禁 | g3/g4/g5/g8 + check-ast + check-all + 全量 golden | 不变 |
| 回退 | 无 flag，一次提交全有/全无；revert + 重生成 golden | 无需回退 |
| 风险 | AutoDrop 覆盖赋值、接口装箱（SH-72/74）、短路表达式的逗号发射 | 0 |

## 5 E3：可证伪预测与反例

- P1：若 B 的“等价”成立，把 examples/47 的链按类型边界拆分后编译运行，输出应与原版逐字节相同 → 实测同 `200 {"users":3}`（成立）。
- P2：若 B 的“等价”无位置限制，E1-c 的拆分版应与一行版同输出 → 实测 `0 2` vs `0 0`（**被证伪**）；所以 B 的等价只覆盖语句/赋值位置，而这正是用户确认的站点。
- P3：若 A 的“已初始化”是可执行规则，`int x; return x;` 应被拒 → 实测 `rc=0`（**被证伪**）；该规则目前只是文档前置条件。

**反例（B 的失效条件，≥3）**
- F1：短路/条件表达式内的静态宿主链。E1-c 已构造并实测；若真实语料出现此类站点，B 的两行拆链不再等价。正则扫描 36 命中/20 文件（含注释与负例）未发现短路形态；表达式位置是 printf 实参（如 examples/14:21、13:21），可先落临时量、语义不变；负例 `test/ast/errors/temp_receiver_trait_chain.ct:17` 仍按预期报错。
- F2：要求一行且每跳类型都变的动态链。仓内只有 SH-73 记录的 ct-http 外部需求（spec:736-740），本仓语料无法复现 3 跳以上；若该形态确为普遍需求，B 的 O(跳数) 行是实质负担。
- F3：接口值/`own` 接收者的兄弟方法。`into` 被 L30-4 拒（E1-d），此时 B 只剩逐跳变量；若需求包含它，B 无对应写法。
- F4（对 A）：`int x; return x;` rc=0，且 `--types` 在“判不出就跳过/跨单元不检查”（spec:2488-2490），A 的“已初始化 + 类型相等”没有可复用检查。

## 6 E5：steelman A 与逐条反驳

A 最强版（`question.md:24-29`）：

1. “`name` 必须**已声明且已初始化**；不新建变量、不做类型推断。”
2. “方法调用只求值一次；结果赋给 `name`；链继续以 `name` 为接收者。”
3. “不改变所有权/生命周期；`name` 是普通变量，赋值规则与普通赋值一致。”
4. “同一链可多次物化；重复变量按顺序覆盖；不允许链尾物化。”

反驳：

1. **“已初始化”不可判。** 无 definite-assignment 分析（`int x; return x;` rc=0）；若按语法只认带初始化式的声明，会拒绝 `T x; if (c) x = …; $x` 这类合法写法；若接受所有已声明，`T x; $x` 就是 UB。更糟的是它要求用户先给每个物化目标一个合法初值：接口/struct 返回值没有自然初值，HTTP 例子里的 `HttpRequest` 只能拿一个真实请求或悬空值预填。A 要么新增数据流分析（超出 150–400 行），要么承认规则只是文档承诺。
2. **类型相等不是现成检查。** `--types` 只在声明初值/赋值/return/固有实参四处判，`判不出就跳过`、`跨单元与 import 不检查`（spec:2488-2490）；A 的规则 3 自己也承认 build 模式会退化为 cc 错误。J-2 的“`--types` 报错”只在子集成立。
3. **“普通赋值”对 struct/接口/AutoDrop 不普通。** 覆盖已有 `name` 需要先释放旧值；多次物化就是多次带 Drop/装箱的赋值。SH-72/74 已证明接口装箱路径会出静默 UB；J-4 的 ASan 矩阵是必需项，不是附录。
4. **单次求值只在语句位置闭合。** 静态宿主链可出现在 `&&`/三元（spec:318，E1-c）；若 A 把赋值提升为前一条语句，就重现 E1-c 的语义变化；若用逗号赋值保留求值点，则要新增“表达式内赋值”发射路径与 golden——A 的 8 条规则没写这一半。于是 A 闭合的范围恰好是 B 已等价的语句/赋值位置，唯一增量（表达式内）没有闭合。
5. **`$` 第 4 义项不是零成本。** 现有三义：range 下标（§4.47）、`into` 接收者（§4.52）、尾随声明别名（§4.58）；加“链中物化”后，parser 需要在后缀链里按 `N_MCALL` 分流（今天 `$` 直接落到 `unexpected token`，E1-d），规范五节、诊断与负例都要同步。lexer 不新增 token 不等于 parser/doc 零成本。

## 7 结论

- **B 胜出**（当前稿）：用户确认的站点全部落在语句/赋值位置，B 用两行拆链 + `into` 覆盖；A 的唯一增量在表达式内，而其“已初始化/类型相等/表达式发射”三项都未闭合；代价 0 vs 3–4 文件 / 150–400 行 / 5 节规范 / 全量门禁。不重复上一场的价值判断（见 `battle/inline-materialize-1/verdict.md`）；B 的等价声明限定为语句/赋值位置，不宣称覆盖短路表达式。
- **B 不成立条件**（任一成立则应改判 A）：① A 给出可执行的 definite-assignment 判据与负例，且成本仍 ≤400 行；② A 定义表达式位置（短路/三元/实参）的物化发射语义并通过 E1-c 的 `0 2` 反例；③ 真实外部语料给出 ≥3 个“两行/逐跳变量不可用”的站点。当前 A 稿三项均无。
