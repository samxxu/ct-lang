# battle/inline-materialize-1 · 主张席 claim（A：`.m(args)$name`）

| 项 | 值 |
| --- | --- |
| 主张 | 给 CT 方法链加 `.m(args)$name`：`name` 已声明、类型可赋值，调用只求值一次，赋值后链以 `name` 为接收者；不改所有权、不处理兄弟方法、不要求先修 SH-73 |
| 基线 | 题面钉 `0c449d2e`；实测 `git describe` = `v0.65.1-32-g0c449d2e`（`CTC_VERSION`=0.65.1）。工作树 HEAD `1cbc5f53` 的 `CTC_VERSION`=0.67.0（`v0.67.0-7-g1cbc5f53`）。E1/E2 按题面指定的 `0c449d2e` 构建/取锚点；同组探针在 `1cbc5f53` 输出逐字相同 |
| 结论 | A 在 C1–C4 同时成立时胜出；当前证据未满足 C1（repo 0，外部未提供），故本轮 A 暂不成立（B 的“两行/into”是当前默认，但 into 不能接接口/`own` 接收者） |

## 0. A 的精确语义（修正题面两处）
- **语法/范围**：`<recv>.m(args)$name` 只作为后缀出现在**有接收者的方法调用**（`N_MCALL`，`a >= 0`）之后；`name` 是当前作用域已声明的变量/参数，不是字段、不是新声明。静态调用 `S.m()`（无接收者）、自由函数 `f()` 后的 `$name` 一律不用 A。
- **必须后接方法调用**：只允许 `$name` 后接 `.m(...)` / `->m(...)`；`x.m()$r;`（链尾）、`x.m()$r + 1`、`x.m()$r[0]`、`x.m()$r.field` 均报错。这样 A 始终是“链的中途物化”，不是赋值糖。
- **位置**：只在可无条件求值处——语句根、`return`、`if`/`while` 条件、声明/赋值初始化式；`&&`/`||` 右侧、三元分支、函数实参内报错。判据与既有 hoist 的 `top` 规则同源（`Emitter.h.ct:2518`）。
- **语义**：`name = <call>; name.<next>()`。call 求值恰好一次、赋值恰好一次；下一跳接收者是 `name`；多跳按源码顺序 `a.m()$x.n()$y.o()` → `x=a.m(); y=x.n(); y.o();`；同名重复按顺序覆盖。
- **`?.`**：当前 `?.m()` 被 PH-53 L53-7 硬拒（`Expr.h.ct:4503-4508`），`?.field` 后的方法调用也被拒。因此题面 A.5 的 `?.m()$x` 在本基线**不可实现**，必须从 A 的范围删除，或等 PH-53 先落（另计 100–300 行与求值次数语义）。
- **类型**：`name` 的声明类型必须与调用结果可赋值；复用 §4.53 L32-2 的 `chk_assignable`（`Stmt.h.ct:4044-4051`），但只在 `ct check --types` 生效；`ct build`/`ct compile` 维持 §4.53“不检查”，由 `cc` 兜底。若要求 build 也强制，另加 40–60 行。
- **未初始化**：A 先赋值后使用；不新增 definite-assignment 分析。未走到的分支不赋值，之后读 `name` 按既有 C 规则。
- **所有权**：不改规则。`own` 目标、容器句柄目标一律拒绝（§4.9 `own` 只允许语句赋值；L29-9 容器绑定不可复制）；接口值按值拷贝 `{self, vt}`，不 retain/release。
- **上下文禁用**：`into` 块、range 初值、尾随声明块内禁用 `$name`（`$` 已被接收者/下标/别名占用）；全局变量可作目标。
- **题面修正**：题面 A.6 写 `T x = <call>;`，与 A.2“`name` 已声明”矛盾；按 A.2，desugar 必须是 `name = <call>; name.next()`，不引入声明/推断。

## 1. E1 命令 + 原始输出（基线 `0c449d2e`，macOS arm64，`cc`=clang）
构建（与 `selfhost/check-ast.sh:407-431` 同款）：

```console
$ mkdir -p /tmp/ctb && git archive 0c449d2e | tar -x -C /tmp/ctb && cd /tmp/ctb
$ cc -Wall -Wextra -std=c99 selfhost/l0/ctc.c -o ctc && ./ctc selfhost/l1/ctc.ct -o l1.c && cc -Wall -Wextra -std=c99 l1.c -o l1 && ./l1 build selfhost/l2/driver.ct -o l2src && cc -Wall -Wextra -std=c99 l2src/*.c -o l2 && ./l2 build -I selfhost/ct-ast selfhost/ct-ast/main.ct -o astsrc && cc -Wall -Wextra -std=c99 astsrc/*.c -o ct-ast
$ export CT=/tmp/ctb/ct-ast CT_C_BOUNDARY=allow
```

**（1）`$` 不是标识符；`.m()$name` 当前是解析错误（不利 A）**

```console
$ printf 'struct S{int n;}\nimpl S { S add(int k){struct S t={self->n+k};return t;} int get(void){return self->n;} }\nint main(void){struct S s={1};struct S r;s.add(1)$r.get();return 0;}\n' > /tmp/d.ct
$ $CT /tmp/d.ct -o /tmp/d.c; echo rc=$?
/tmp/d.ct:3:50: error: unexpected token
rc=1
$ printf 'int main(void){int $x=1;return $x;}\n' > /tmp/d2.ct
$ $CT /tmp/d2.ct -o /tmp/d2.c; echo rc=$?
/tmp/d2.ct:1:20: error: expected a variable name
rc=1
```

**（2）两行写法已等价（规约标准落法）；SH-73 仍限制纯链（不利 A）**

```console
$ $CT test/ast/238_iface_ret_value/prog.ct -o /tmp/p8.c && cc -Wall -Wextra -std=c99 /tmp/p8.c -o /tmp/p8 && /tmp/p8; echo rc=$?
1
200
rc=0
$ $CT test/ast/errors/temp_receiver_trait_chain.ct -o /tmp/p10.c; echo rc=$?
test/ast/errors/temp_receiver_trait_chain.ct:17:1: error: method receiver must be a variable, an element, a call or a field chain
rc=1
```

`docs/language-spec.md:736-740` 明写：“接口值落变量后逐跳调用成立……每个中间结果都必须落变量”。238 的 `HttpRequest r2 = req.header(...); HttpResponse res = r2.send();`（`:49-50`）就是两行等价。

**（3）`into` 已覆盖兄弟方法（不利 A；A 自己也不处理兄弟）**
```console
$ $CT test/ast/152_into_trait_method/prog.ct -o /tmp/p6.c && cc -Wall -Wextra -std=c99 /tmp/p6.c -o /tmp/p6 && /tmp/p6; echo rc=$?
Tom says hi to Ann
rc=0
$ $CT build test/ast/155_into_value_host/prog.ct -o /tmp/p7 >/dev/null && /tmp/p7; echo rc=$?
mid 16
done 16 3
v 6
rc=0
```

**（4）`?.m()` 被硬拒，题面 A.5 无落点（不利 A）**：`$ $CT test/ast/errors/p53_method.ct -o /tmp/p5.c` → `test/ast/errors/p53_method.ct:18:13: error: optional method calls are not supported; assign the receiver to a variable first`（rc=1）。
**（5）真实语料中 A 的“显著收益”为 0（不利 A 的 J-1）**
```console
$ python3 - <<'PY'
import re,pathlib
D=re.compile(r'^\s*(?:struct\s+|const\s+|own\s+)?([A-Za-z_]\w*(?:\s*\*)?)\s+([A-Za-z_]\w*)\s*=\s*([^;]+);\s*$')
U=re.compile(r'^\s*([A-Za-z_]\w*)\s*(?:\.|->)\s*([A-Za-z_]\w*)\s*\(')
n=h=0
for p in [*pathlib.Path('examples').rglob('*.ct'),*pathlib.Path('test/ast').rglob('*.ct')]:
 L=p.read_text(errors='replace').splitlines()
 for i in range(len(L)-1):
  m=D.match(L[i]); n+=bool(m)
  if m and (u:=U.match(L[i+1])) and u.group(1)==m.group(2): h+=1
print(n,h)
PY
483 6
```

6 处全部是 `T v = <初始化式>; v.m();`（自由函数/静态方法/聚合初始化，如 `examples/01_greeter/greeter.ct:36-37`、`test/ast/229_inherent_impl/prog.ct:19-20`）；6/6 都在前一行声明，没有一处能省掉声明，A 写成 `T v; <call>$v.m();` 仍是 2 行。最大收益只是“每个 hop 少 1 行”，而 J-1 明确排除“仅少写一行”。

## 2. E2 `file:line`（基线 `0c449d2e`；下表“不利于己方”行）
| 方向 | 锚点 | 内容 |
| --- | --- | --- |
| 利 A | `docs/language-spec.md:736-740` | 规约承认“每个中间结果都必须落变量”，A 把落变量内联，需求真实存在 |
| 利 A | `selfhost/ct-ast/backend/emit/Emitter.h.ct:2504-2527` | 已有 `__ct_tmpN` 接收者物化与单次求值机制，A 可把临时名换成用户 `name`，不必新造求值规则 |
| 利 A | `selfhost/ct-ast/frontend/parse/Expr.h.ct:4496-4516` | `N_MCALL` 的接收者/实参/aux 已就位，`$name` 只需在此后接一个后缀 |
| 利 A | `selfhost/ct-ast/frontend/parse/Stmt.h.ct:4044-4051` | L32-2 的 `chk_assignable` 可直接复用为 `$name` 的类型判据 |
| 不利于己方 | `selfhost/ct-ast/frontend/parse/Expr.h.ct:4503-4508` | `?.m()` 被 PH-53 L53-7 硬拒，A.5 的 `?.m()$x` 无实现基础 |
| 不利于己方 | `selfhost/ct-ast/backend/emit/Emitter.h.ct:5510-5514` | 接收者白名单不含 `N_MCALL`；A 必须把后续接收者改成变量，纯链仍被 SH-73 拒 |
| 不利于己方 | `docs/language-spec.md:2131-2132` | “`$` 不是标识符……在 range/into 之外仍走 `unexpected token`”；A 要加第 5 个 `$` 义项并改写这条冻结判据 |
| 不利于己方 | `docs/language-spec.md:1446-1447` | `own` 只允许语句层赋值；A 若嵌在表达式里会绕过 AutoDrop 记账 |
| 不利于己方 | `docs/language-spec.md:2480-2482` | 类型检查只在 `ct check --types`；build 不检查，A 的“必须类型匹配”无法在 build 兑现 |
| 不利于己方 | `docs/language-spec.md:1847` | 语言不引入 `auto`/返回类型推断；`$name` 仍要求作者写出中间变量的类型 |

## 3. E3 可证伪预测
- **P1（A 的正例，落地后一次验证）**：把 `test/ast/238_iface_ret_value/prog.ct:49-50` 的 `r2`/`res` 预先声明，改写为 `req.header("Accept", "application/json")$r2.send()$res.status();`，应编译、运行输出 `1`、`200`，且 `req.header(...)` 只求值一次。
- **P2（J-1 的判定式，可立即在任意语料重跑）**：若 A 的 J-1 成立，真实语料应出现 ≥3 处“变量已预先声明并被复用、两行写法要 ≥2 行”的站点。当前 repo 扫描是 **0**（E1-5）；外部 `ct-http` 消费方须给出同类计数，否则 J-1 不成立。
- **P3（兼容性）**：A 落地后不含 `$` 的 `test/ast/**` 与 `examples/**` golden 应逐字节不变，`bash selfhost/check-ast.sh` 全绿，`git diff --stat` 只多新夹具/文档。
- **P4（负例控制）**：`f()$x`（自由函数后）、`x.m()$r;`（链尾）、`own` 目标、`&&` 右侧的 `$name` 必须全部报错；任一编译通过即 A 的范围声明失败。

**反例（A 不显著更好，至少 3 个真实样例）**
1. `examples/47_chain_factory/src/main.ct:27-32`：静态 map 链本来就是一行；要写 `$req` 反而必须把 `.m.ct` 隐藏的宿主类型 `CRequest` 写出来，A 更差。
2. `examples/48_string_steps/src/main.ct:14,17`：`int n = ...;` / `char *last = ...;` 已是“链尾一行物化”；A 要求后接方法调用，无法表达链尾，A 更差。
3. `test/ast/155_into_value_host/prog.ct:10-18`：`into` 已覆盖 `$ = .add(1).add(2).add(3)` 与块后 `.value()`；A 明确不处理兄弟方法，无法改进。
4. `test/ast/262_inherent_mcall_receiver/prog.ct:15-16`：`doc.get(2).get(4)`、`doc[2].has(3)` 已一行可写，A 无收益。
5. `examples/13_builder_chain/src/main.ct:17`：`int r = "10".builder().add(1).add(2).add(3).value();` 已一行，A 无收益。

## 4. E4 代价
| 面 | 估计 | 依据/说明 |
| --- | --- | --- |
| lexer | 0–30 行 | `$` 已是单字符 `T_PUNCT`（`Lexer.h.ct:369-372`），`$`+ID 可复用；若要独立 token 才加 20–30 行 |
| parser/诊断 | 60–100 行 | 后缀分支（`Expr.h.ct:4496-4516`）、名字存在性、位置/后缀限制、into/range/trailing 禁用、3 条新诊断 |
| type | 20–40 行 | 复用 `chk_assignable`（`Stmt.h.ct:4044-4051`）；`--types` 下强制，build 不强制；拒绝 `own`/容器目标 |
| emit | 70–120 行 | 复用 hoist 表（`Emitter.h.ct:2504-2527`、`:2538-2570`），把 `__ct_tmpN` 声明改成 `name = call;`；关键是不把赋值表达式当接收者打印两次 |
| tests | 120–180 行 | 1 正例、4 负例（链尾/自由函数/`?.`/`own`）、1 个 example、`check-ast.sh` 注册 |
| 文档 | 50–70 行 | 新增一节 + §4.47/§4.52/§4.58/§4.10.1 的交叉说明 |
| **合计** | **4 个源文件（Expr/Stmt/Emitter/Lexer）+ 诊断/测试/文档；核心 150–290 行，含测试/文档 320–500 行** | 3 个阶段：S1 parser/AST/诊断（M）；S2 emit/所有权（M）；S3 测试/文档/example（S/M） |
| 门禁 | G3（warning-free）、G4（docs）、G5（负例）、G8（范围/一提交一事）；`check-ast.sh`、`test/run.sh`、`check_eval_order.py` | 旧 golden 应不变；新增负例必须先红后绿（T-7） |
| 风险 | 中 | ①接收者被打印两次 → 求值两次（必须用变量/hoist，不能用赋值表达式直接作接收者）；②位置限制与“表达式内可用”的直觉冲突；③`?.` 被 PH-53 挡；④`own`/容器目标；⑤`$` 第 5 义与 into/range/trailing 的上下文；⑥golden 漂移 |
| 回退 | 逐个 revert S3→S2→S1 | 纯加法语法，无持久化格式；若旧 golden 变化即为缺陷，不是“预期升级” |

## 5. E5 steelman B（引用 `battle/inline-materialize-1/question.md:40-48`）并逐条反驳

- **B1“现有拆链已等价：`HttpRequest req = "...".method("GET"); req.header(...).send();`”**——在语句位置、类型可写时确实等价，238 已实测（E1-2）。**反驳**：等价物的成本是“每个 hop 一行 + 一个临时名”；A 的唯一超出是复用预先声明的变量/避免再命名，但 repo 0 例（E1-5），所以 B1 在基线上成立，A 只在外部语料 C1 满足时才有净收益。
- **B2“兄弟方法用 `into`，不是链。”**——`into` 确实已覆盖兄弟方法（152/155，E1-3）。**反驳**：§4.52 `language-spec.md:2465` 明确禁止接口值/`own` 接收者；`into` 不能替代接口链。B2 不是 A 的反证，只是把问题推回给 B1 的两行写法。
- **B3“`$` 当前不是标识符，新增 `$name` 要改 lexer/parser/上下文，成本与歧义不值。”**——**反驳**：lexer 不必改，`$` 已是单字符 token（`Lexer.h.ct:369-372`）；`$`+ID 在 `N_MCALL` 后可与 into/range/trailing 的 `$` 区分。真实成本在 parser 60–100 行与上下文禁用，不是“改 lexer”；歧义可控但非零。
- **B4“链式鼓励不等于必须内联物化；两行写法清楚且零语言改动。”**——**反驳**：零改动是真实优势，但“清楚”不等于“够用”；A 的诉求是复用已声明变量与 return/条件位置少一行。只是该诉求在 repo 无量化证据，B4 在基线上胜出。
- **B5“若一定要内联，先证明两行写法在真实代码中造成显著负担。”**——**反驳**：A 接受该举证责任，并把判据量化为 P2（≥3 个预声明复用站点）；基线 repo 为 0，因此 A 未满足 B5。若外部 `ct-http` 语料给出 ≥3，B5 被满足，A 才成立。

## 6. 结论：A 胜出/不成立条件
**A 的最强形态**不是“修链式”，而是“给既有 `__ct_tmpN` 一个用户名字”：不新增求值规则，不碰 SH-73，不改变所有权；核心 150–290 行，3 阶段可交付。它比 B 多的只是“每个 hop 少一行 / 可复用已声明变量”。

**当前证据集判定：A 暂不成立（未满足 J-1、J-3、J-4；J-2 可控；J-5 可承受；J-6 可过）。** 理由：repo 真实语料 0 个显著收益站点；A 的最大收益正是 J-1 排除的“仅少写一行”；题面 `?.m()$x` 被 PH-53 硬拒；A 不修 SH-73，且容易让读者误以为链式已修。

**A 胜出的条件（C1–C4，需同时满足）**：

1. **C1（J-1）**：外部真实语料（首选 `ct-http` 消费方）出现 ≥3 处“变量预先声明并被复用、两行写法需 ≥2 行”的站点；repo 当前为 0。
2. **C2（J-3）**：删除 `?.m()$x`，或先落 PH-53 L53-7（另计 100–300 行与求值次数语义）。
3. **C3（范围）**：接受 A 的限制——语句根/return/条件/初始化式、后接方法调用、禁用 into/range/trailing、禁 `own`/容器目标、类型匹配只在 `--types` 强制。
4. **C4（J-4）**：文档明写“A 不修 SH-73；每个 hop 仍是一次显式落变量”，不宣称一行动态链。

**B 不自动胜出**：`into` 不能接接口/`own` 接收者（`language-spec.md:2465`），两行写法仍是当前唯一通用绕法；若 C1 被外部语料满足，A 应优先于 B。
