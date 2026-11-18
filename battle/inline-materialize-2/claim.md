# battle/inline-materialize-2 主张书（A：最小 `$name`）

> 主张席 REQ；基线 `0c449d2e`（v0.65.1，实测 `ct-ast v0.65.1`）。只评“最小可实现方案”，不复论价值；A 不宣称 C1（外部语料），也不宣称修 SH-73。

## 1 A 的完整方案
### 1.1 语法
- `$NAME` 只在**方法调用右括号之后**识别；自由函数、字段/下标/字面量/括号表达式之后不引入新义。
- `$NAME` 后必须紧跟至少一个链后缀（`.`/`->`/`[`/`(`/`++`/`--`）；链尾 `$NAME` 报错。
- 允许的方法：trait、固有（含泛型实例）、`map ... for instance`、`map ... for type` 宿主方法；静态 `T::m()`、函数指针调用不接受。
- 上下文：只允许语句级表达式根、赋值右值、非 `static` 本地声明初始化式，且 `$` 在该表达式的**接收者脊柱**上（不进入实参/下标/三目分支）。条件、`return`、全局/静态初始化式、`into` 块、尾随块、range 元素内不启用。
- `NAME` 必须是当前作用域此前已声明的变量绑定；不新建变量、不推断、不隐式转换/装箱。

### 1.2 语义（纯赋值，不改所有权）
`P m(args) $x S` 精确降为：
```c
x = <P m(args)>;      /* 语句之前，恰好一次 */
<x> S                  /* 原链继续，接收者是 x */
```
- 方法调用及接收者前缀只求值一次；结果赋给 `x`；链继续以 `x` 为接收者，走 §4.5 的既有变量接收者路径。
- 同一链可多次物化，按左到右赋值；同名后者覆盖前者，每次按当时类型检查。
- 赋值置于该语句之前；因 `$` 限于语句表达式接收者脊柱，前缀是该语句最先求值的部分，提升不改变求值次数/顺序。
- 生成 C 即手写 `x = <prefix>; <rest>`；不为目标新增临时量、不改 vtable/装箱、不改 AutoDrop 记账。`x` 旧值被普通赋值覆盖；指针不深拷贝、接口值只复制 `_iface` 指针。
- 目标不得是 `own`/`borrow`/`const`/数组/`self`：`own` 赋值会取消 autodrop，属所有权变化，A 报错而非静默改。
### 1.3 类型
- 方法结果静态类型须可求：trait 签名、固有签名（泛型代入后）、`for instance`/`for type` 签名；求不出则硬错，不生成 C、不退到 C 编译。
- `NAME` 声明类型须与结果类型**完全相等**（同一 C 拼写规范化后）；不做指针/值、接口/具体 struct 隐式转换。
- `ct check --types` 必须在 `$` 处报不匹配（两侧拼写）；默认模式沿用 Phase 32 opt-in 约定，但声明/初始化/目标类别/上下文/链尾五类前提在任何模式下都是硬错。
- “已初始化”定义为语法可判定：参数、全局变量（C 零初始化）、带初始化式声明、`for`/`foreach` 归纳变量；不做数据流。故 `T x; x = make();` 被拒，这是明确假阳性，也是不引入数据流的代价。
### 1.4 边界矩阵
| 形态 | 结果 |
| --- | --- |
| `req.send()$res.status()`（`res` 已声明+初始化，类型相同） | 允许；接收者变变量，绕过该跳 SH-73 |
| `"url".method("GET")$req.header(...)`（宿主首跳） | 允许；需类型表覆盖 `for type` 结果 |
| `a.m()$x`（链尾）/ `T x = a.m()$x.n()`（声明形态）/ `f()$x` / `T::m()$x` | 错（无后续后缀 / 声明形态 / 非实例方法） |
| `a.m()$x` 在条件/实参/下标/三目/`return` 中 | 错（语句级脊柱限制） |
| `?.m()$x` | 错（L53-7 未实现；A 不新增） |
| `own`/`borrow`/`const`/数组/`self` 作 `NAME` | 错 |
| `a.m()$x.n()$y.o()` | 允许；各自检查、按序赋值 |
| `a.m()$x` 在 `into`/尾随块/range 元素内 | 错（`$` 保持既有义项） |
| 结果类型不可求 | 硬错（`cannot determine the static type of the method result`） |

## 2 E1：命令与原始输出
以下在基线只读快照 `/tmp/ct-battle-baseline/{src,build}` 执行，探针在 `/tmp/im2/`，`CT_C_BOUNDARY=allow` 用于带 `#include` 的探针。
**(1) `$` 现有三义项（不利：第 4 义项是新增负担）。**
```console
$ CT_C_BOUNDARY=allow /tmp/ct-battle-baseline/build/ct-ast check /tmp/im2/p1_dollar_positions.ct; echo $?
0
$ CT_C_BOUNDARY=allow /tmp/ct-battle-baseline/build/ct-ast build /tmp/im2/p1_dollar_positions.ct -o /tmp/im2/p1b.bin && /tmp/im2/p1b.bin
'cc' -std=c99 -I '.ctbuild' '.ctbuild/p1_dollar_positions.c' '-o' '/tmp/im2/p1b.bin'
7
5 7 1
1
```
依次对应 `b into { take($); }`、`0..3($ * 2 + 1)`、`int x = 1 defer { printf("%d\n", $); };`。

**(2) 今天 `$NAME` 是语法错误（不利：新增解析分支）。**
```console
$ CT_C_BOUNDARY=allow /tmp/ct-battle-baseline/build/ct-ast check /tmp/im2/p2_dollar_name.ct
/tmp/im2/p2_dollar_name.ct:12:14: error: unexpected token
$ CT_C_BOUNDARY=allow /tmp/ct-battle-baseline/build/ct-ast check /tmp/im2/p6_sh73_dollar.ct
/tmp/im2/p6_sh73_dollar.ct:29:23: error: unexpected token
```

**(3) 无 definite-assignment（不利：A 的“已初始化”只能做语法近似）。**
```console
$ CT_C_BOUNDARY=allow /tmp/ct-battle-baseline/build/ct-ast check /tmp/im2/p3_uninit.ct; echo $?
0
$ CT_C_BOUNDARY=allow /tmp/ct-battle-baseline/build/ct-ast --emit-c /tmp/im2/p3_uninit.ct -o /tmp/im2/p3.c >/dev/null 2>&1; grep -n "int y" /tmp/im2/p3.c
7:    int y = x;
$ CT_C_BOUNDARY=allow /tmp/ct-battle-baseline/build/ct-ast check /tmp/im2/p4_uninit_iface.ct; echo $?
0
$ CT_C_BOUNDARY=allow /tmp/ct-battle-baseline/build/ct-ast --emit-c /tmp/im2/p4_uninit_iface.ct -o /tmp/im2/p4.c >/dev/null 2>&1; grep -n "c.vt->send" /tmp/im2/p4.c
31:    return c.vt->send(c.self, "x", 4);
```

**(4) SH-73 仍不修：`check --types` 放行、`build` 才拒绝；`p5b` 即 A 的降级形态（`res = req.send(); res.status();`）。**
```console
$ CT_C_BOUNDARY=allow /tmp/ct-battle-baseline/build/ct-ast check --types /tmp/im2/p5_sh73.ct; echo $?
0
$ CT_C_BOUNDARY=allow /tmp/ct-battle-baseline/build/ct-ast build /tmp/im2/p5_sh73.ct -o /tmp/im2/p5x.bin
/tmp/im2/p5_sh73.ct:26:1: error: method receiver must be a variable, an element, a call or a field chain
$ CT_C_BOUNDARY=allow /tmp/ct-battle-baseline/build/ct-ast build /tmp/im2/p5b_split.ct -o /tmp/im2/p5b2.bin && /tmp/im2/p5b2.bin
'cc' -std=c99 -I '.ctbuild' '.ctbuild/p5b_split.c' '-o' '/tmp/im2/p5b2.bin'
200
```

**(5) 成本锚点（不利：并非零成本）。**
```console
$ git -C /Users/samxx/dsh-ws/ct-lang show --shortstat --format= 1ef37e23 -- selfhost/ct-ast
 4 files changed, 342 insertions(+), 4 deletions(-)
```
同类 postfix 特性 `into` 源文件改动 346 行；A 估计为其 1/2–2/3。基线代码 `$NAME` 站点为 0（7 处 `$ident` 全在注释）。

## 3 E2：file:line（行号在 `0c449d2e` 核对；当前 HEAD 同内容，行号可能 +2–3）
| 方向 | 锚点 | 内容 |
| --- | --- | --- |
| 支持 A | `frontend/lex/Lexer.h.ct:371`；`frontend/parse/Expr.h.ct:5348-5365` | `$` 已是 `T_PUNCT`，且已按 `range_ctx`/`into_node`/`dollar_ok` 分派；加第 4 分支即可 |
| 支持 A | `backend/emit/Emitter.h.ct:2464-2526` | 已有“结果只求值一次→命名→链继续”的 hoist 机制，A 复用 |
| 支持 A | `frontend/type/TypeCheck.h.ct:364-420` | `N_MCALL` 静态返回类型可从 trait/固有签名取得 |
| 不利 A | `backend/emit/Emitter.h.ct:5511` | 接收者白名单只收 var/index/call/field-chain；`N_MATERIALIZE` 须新增一条 |
| 不利 A | `backend/emit/Emitter.h.ct:2518` | 只允许语句行首/赋值初始化式提升；A 的上下文受此约束 |
| 不利 A | `frontend/sym/Symbols.h.ct:120-133` | `Var` 无“带初始化式”位；须加字段并在参数/全局/本地声明处置位 |
| 不利 A | `docs/language-spec.md:316` | “接收者本身是方法调用一律拒绝”的 SH-73 边界；A 不碰它 |
| 支持 A（反驳 B） | `docs/language-spec.md:2465` | `into` 禁止接口值/`own` 接收者；B 的 `into` 不能覆盖本需求 |

## 4 E3：可证伪预测与反例
| # | 预测（实现后一次性可验） |
| --- | --- |
| P1 | 每个合法 A 站点的 `--emit-c` 两行与手写 `x = <prefix>; <rest>` 逐字相同；出现额外 `__ct_tmp`/不同求值次数即失败 |
| P2 | 既有 1297 个 `.ct`（75072 行）代码 `$NAME` 为 0；实现后除新增夹具外旧 golden 不得变化，`check-ast.sh`/`check-warnings.sh` 全绿 |
| P3 | 链尾、声明形态、非方法调用、条件/实参上下文、`?.`、`own/borrow/const/数组/self`、未声明、未初始化声明、类型不匹配十类都在 `$` 处报错，退出 1，不产出 `.c` |
| P4 | 实现后 `p5_sh73.ct` 的 `build` 仍以同一条“method receiver must be …”失败，`p6` 通过；若 `p5` 意外通过则 A 越权改 SH-73 |
| P5 | `req.send()$req.status()`（`req` 接口类型，`status` 属另一 trait）在 `ct check --types` 下须在 `$` 处报类型不匹配；只在 C 编译期失败即不成立 |

| # | 反例（使 A 失效的构造） |
| --- | --- |
| C1 | `while (q.send()$r.status() == 200) { … }`：A 必须拒绝；若接受并提前赋值，从每次迭代求值变一次，语义错 |
| C2 | `T x; x = make(); q.send()$x.status();`：流敏感已初始化但 A 的语法规则拒绝；若接受则“已初始化”无检查，若拒绝则对合法代码有假阳性（本稿承认） |
| C3 | `q.send()$x;`：链尾无后缀；若接受，`$` 只是普通赋值拼写，该形态应删 |
| C4 | `own T x = make(); q.send()$x.status();`：若接受，语句级赋值取消 autodrop，所有权变了 |
| C5 | `"url".method("GET")$req.header(...)`：宿主方法结果若不在 `static_ctype` 的 `N_MCALL` 分支内，A 主用例报 type unknown；必须补该分支 |

## 5 E4：代价、阶段、回退
| 项 | 估算（基线 `0c449d2e`） |
| --- | --- |
| 源文件 | 6–8 个：`parse/Expr.h.ct`、`parse/Stmt.h.ct`（node 号）、`emit/Emitter.h.ct`、`type/TypeCheck.h.ct`、`sym/Symbols.h.ct`（init 位及置位）、`editors/vscode/syntaxes/ct.tmLanguage.json`（高亮） |
| 源行数 | 150–250 行（不含测试/文档）；其中 `static_ctype` 的 `for type` 分支 +15–30，发射器物化 +50–90 |
| 测试/文档 | 3 正例 + 8–10 负例 + `--types` 夹具 + SH-73 对照，约 120–220 行；`check-ast.sh` 接线 +20–40；spec §4.5/§4.10.1 增一小节（20–35 行）+ tutorial 入口 + 诊断文案 |
| 门禁 | `check-ast.sh`、`check-warnings.sh`（生成 C 零警告）、`check-semantics.sh`（`ct check --types`）、VSCode grammar test、`check-docs.py`；L1/L2 golden 不受影响 |
| 阶段 | **S1** 解析+AST+硬错（上下文/链尾/声明形态）；**S2** 发射器降级+正例/golden；**S3** 类型匹配（`--types`）+宿主方法类型+所有权/接口矩阵；每阶段独立红/绿（T-7），S 或 M |
| 回退 | `git revert` 各阶段提交：A 是纯新增语法，基线代码 `$NAME` 站点为 0，现有合法程序不依赖；回退后这些形态恢复 `unexpected token`，无迁移；删新增夹具后重跑 `check-ast.sh`/`check-warnings.sh` 应回基线全绿 |

## 6 E5：steelman B 与逐条回应
B 最强论述（引 `question.md` §方案 B 原文）：“1. 用两行拆链：`HttpRequest req = \"...\".method(\"GET\");` / `req.header(...).send();` 2. 兄弟方法用 `a into { .m(); .n(); }`；3. `$` 不再增加第 4 义项；零 lexer/parser 风险；4. 若认为两行不可接受，先补真实外部语料，再另立提案。”另引前场判决：“B 为 0 行源码”“`into` 不能换类型、不能接接口/own 接收者”。

- **B1 拆链**：它是合法回退，但没有实现“inline”这一已确认需求；A 的降级恰是 `x = <prefix>; <rest>`，只删中间声明、保留同一表达式与既有绑定，不新增绑定、不延长生命周期、不占新名字。若没有既有绑定，A 也不适用（见 C2），此时 B1 仍是唯一解。
- **B2 `into`**：`into` 返回同一接收者、不能换类型，且 spec:2465 禁止接口值/`own` 接收者；本需求的链每跳换类型（`char *`→请求→响应）且含接口值。故 `into` 不是替代方案，最多补兄弟方法。
- **B3 第 4 义项/零风险**：`$` 已是 `T_PUNCT`（Lexer:371），A 不加 token；第 4 义项与 range/into/尾随块上下文不相交，解析是一个 postfix 分支，不是歧义。真实成本在文档、诊断、编辑器高亮（E4 已量化）；“零风险”是 B 的性质，不是对已确认需求的证伪。
- **B4 先补外部语料**：这是价值门槛（前场 C1），不是可实现性门槛；A 本场不宣称满足 C1。若裁判仍以 C1 阻断，B 胜——A 把它写进胜出条件，而非绕过。
- **B5 “SH-73 仍不修”**：A 同意且不碰 Emitter:5514；A 只把某一跳接收者换成变量，文档必须写“one-hop materialization，不是链式能力”。若文案暗示修了 SH-73，A 自己失败。

## 7 结论：A 胜出条件
A 胜出当且仅当以下同时成立：
1. 需求是“把**已存在的绑定**作为链的继续接收者”，不是声明形态、不是 `T x = chain$ x`、不需要链尾物化；
2. 裁判接受 C2 的**语法初始化**（参数/全局/带初始化式声明），不要求流敏感 definite-assignment；
3. 类型匹配只覆盖可求静态类型的方法，`--types` 报不匹配；接受默认模式仍可能由 C 编译器兜底；
4. 接受第 4 个 `$` 义项与 6–8 文件/150–250 行的代价，且不要求 A 修 SH-73；
5. 前场 C1（外部语料）不作为本场阻断，或另有证据满足。

任一不成立，B 胜：拆链/`into` 仍是当前语料下的正确落法，A 不应进入实现；A 的可加性与单提交回退只保证“试了能退”，不构成“值得试”的理由。
