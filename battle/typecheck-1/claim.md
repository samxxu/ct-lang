# battle/typecheck-1 — 主张书 A（全量检查进编译路径、强制）

| 字段 | 值 |
| --- | --- |
| 席位 | 主张席 REQ（主张 A） |
| 基线 | `ed172075` / v0.65.1（Phase 66 已收口） |
| 证据环境 | macOS arm64；`cc` = clang；ct-ast 由 L0→L1→L2→ct-ast 本地自举 |
| 本席写入 | 仅 `battle/typecheck-1/claim.md`（未改源码/规范/测试，未读 counter.md） |

## 0. 主张、覆盖清单与验收判据
A：1.0 前把全量表达式类型检查 + CFG/定值 + own/borrow/Drop 语义检查放进 `ct compile`/`ct build`，
**编译路径默认强制**；`ct check --types` 不再是唯一入口。分相交付不等于 opt-in：每相一落地即进编译路径，
只允许一张有到期日的临时豁免清单，1.0 前清空。覆盖清单（对应 ACC-A1）：表达式（字面量/算术/比较/逻辑/三元/
下标/取址/解引用）、转换与 cast、指针与数组衰减、struct/union/enum、函数指针、闭包、`map`、`into`、`?`/`err`、
泛型/trait/容器；CFG（return/break/goto/switch/不可达）、定值与初始化、impl 完整性、`own`/`borrow`/`Drop`
逃逸与释放顺序、跨单元签名。

| ID | 判据（映射 question J-1..J-6） | 通过方式 |
| --- | --- | --- |
| ACC-A1 | 反例矩阵 M1–M8 在 `ct compile` 下全部给 `file:line:col: error:`（§3） | 逐行跑矩阵贴 rc |
| ACC-A2 | 合法语料 0 误报：289 个 `test/ast/*/prog.ct`、`examples/**` 216 个全绿 | `ct compile` 全量 sweep |
| ACC-A3 | `ct build`/`ct compile` 与 `ct check` 对同一单元给同一诊断集（同一 `file:line:col`） | 两命令 diff |
| ACC-A4 | 445 个 golden 逐字节不变；1,268 个 `.ct`（test 1,052 + examples 216）全量回归绿 | `check-goldens.sh` + `check-ast.sh` |

## 1. E1 命令与原始输出
### 1.1 编译路径不做类型检查：ct 绿 / C 红（对 A 有利）
```console
$ /tmp/tc1/ct-ast --version
ct-ast v0.65.1
$ /tmp/tc1/ct-ast compile bad_expr.ct -o bad_expr.c; echo rc=$?     # char *p; long n = p + p;
rc=0
$ cc -Wall -Wextra -std=c99 bad_expr.c -o bad_expr; echo rc=$?
bad_expr.c:6:17: error: invalid operands to binary expression ('char *' and 'char *')
    6 |     long n = (p + p);
      |               ~ ^ ~
1 error generated.
rc=1
$ /tmp/tc1/ct-ast check --types bad_expr.ct; echo rc=$?
rc=0                                                                # 三处之外，--types 也静默
```

对照 `bad_assign`（`struct A a; struct B b; a = b;`）：`ct compile rc=0`、`cc rc=1`，而 `--types` 报
`assignment: expected 'struct A', got 'struct B'`、`rc=1`。`ct build --types` 则报
`ctc: --types is only valid with 'ct check'`、`rc=1`。`--types` 只挡声明初值/赋值/`return`/容器实参（§4.53 三处），
挡不住三处之外的任何表达式类型。

### 1.2 CFG/定值缺口（对 A 有利，且 `--types` 也挡不住）
```console
$ /tmp/tc1/ct-ast compile break_outside.ct -o b.c; echo rc=$?
rc=0
$ cc -Wall -Wextra -std=c99 b.c -o x; echo rc=$?
b.c:5:5: error: 'break' statement not in loop or switch statement
rc=1
```

`break` 越界是纯 CFG 错误，C 硬红（`rc=1`）而 ct 绿（`rc=0`）。同类：`dup_case.ct`（`switch` 两个 `case 1`）
`ct compile rc=0`、`cc` 报 `d.c:9:14: error: duplicate case value '1'`；`int x; return x;` `ct compile rc=0`，
`cc` 只告警 `u.c:6:12: warning: variable 'x' is uninitialized when used here [-Wuninitialized]`、`rc=0`。

### 1.3 对 A 不利的证据（必须由 A 的判据吸收）
现有**绿夹具**被 `--types` 误报，证明“检查器已成熟、只差强制”不成立：

```console
$ ct check --types test/ast/234_err_return_contract/prog.ct; echo rc=$?
test/ast/234_err_return_contract/prog.ct:9:23: error: initializer: expected 'char', got 'char *'
rc=1
$ ct build --emit-c test/ast/234_err_return_contract/prog.ct -o /tmp/tc1/f234; echo rc=$?
rc=0
$ cc -std=c99 /tmp/tc1/f234/prog.c -o /tmp/tc1/f234/p && /tmp/tc1/f234/p
3 x                                                                 # 与 prog.expected.out 一致
```

不带 `--types` 的 `ct check` 对同一文件 `rc=0`，故它是现有绿夹具。误报点是
`static char s[] = "x";`：合法 C 的字符串初始化数组，§4.53 称“数组跳过”实际漏判。语料 sweep
（`for f in test/ast/*/prog.ct`，`check --types`）：289 个中 262 绿、27 红——21 个是
`'import' requires multi-file mode`、4 个 loop 遮蔽与 1 个 loop 计数是既有硬错、**1 个是 234 的真误报**
（0.35%）；同 sweep 下 `examples/**` 216 个全绿。基线规模：`ct check --types` 只有三处粗检；
`TypeCheck.h.ct` 1,061 行、`Expr.h.ct` 7,217、`Stmt.h.ct` 4,144、`Parser.h.ct` 3,978；AutoDrop/leak 的
`Memory.h.ct` 只有 481 行。语义硬错已有先例：`err:`/`?`/atomic/own 的多数违例走 `ct_sem_error`
（`selfhost/ct-ast` 内 246 处），不带 `--types` 也硬错——A 是延续既有模式，不是新开一类行为。

## 2. E2 `file:line`
- 利 A：`selfhost/ct-ast/tool/driver/Driver.h.ct:277-284` —— `--types` 被限定成 `ct check` 专属（注释原文
  “opt-in gate on `ct check` only”）；`ct build|compile` 永不设 `types_mode`，故 §1.1/1.2 的绿是设计结果。
- 利 A：`docs/language-spec.md:2480-2483` —— “只在三处做粗粒度类型校验……`ct build` / `ct compile` 的输出、
  诊断和 golden 逐字节不变”；基线把不检查写成契约，1.0 前不翻掉它，“ct 绿、C 红”就永续。
- 利 A：`selfhost/ct-ast/frontend/parse/Stmt.h.ct:2059-2064` —— `err:` 载荷“judged on every path, not only
  under `--types`”，`ct compile` 已拒绝坏 `err:`。
- **不利 A**：`docs/language-spec.md:2488-2490` —— 数组、函数指针、`void`、`sizeof`/`_Generic`/宏一律静默，
  **跨单元函数体与 `import` 单元不检查**；`selfhost/ct-ast/frontend/parse/Expr.h.ct:6874-6990`（`chk_type`）
  只对 12 种表达式节点给类型，其余 `return -1` 跳过，`static_ctype`（`Expr.h.ct:3873`）只覆盖 10 种。
  这是 A 必须补齐的空白；全量要补到 Expr 32 种 + Stmt 44 种节点，且跨单元是最大一块。

## 3. E3 可证伪预测与反例矩阵
**预测 P**：若 A 成立，下表“现状 ct 绿 / C 红”的行在 `ct compile` 下转 `rc=1` 且带 `file:line:col: error:`；
“合法 C”行保持 `rc=0`。任何一行不符即 A 不成立。

| # | 反例 | 现状（HEAD，实测） | A 成立时应为 |
| --- | --- | --- | --- |
| M1 | `struct A a; struct B b; a = b;` | ct compile 0，cc 1 | ct compile 1 |
| M2 | `char *p; long n = p + p;` | ct compile 0，`--types` 0，cc 1 | ct compile 1 |
| M3 | `int f(void){return p;}`（`char *p`） | ct compile 0，cc 1 | ct compile 1 |
| M4 | `int f(int x){if(x>0)return 1;}` 缺返回 | ct compile 0，cc 仅告警，运行 UB | ct compile 1 |
| M5 | 循环外 `break;` / `switch` 重复 `case 1` | ct compile 0，cc 1 | ct compile 1 |
| M6 | `int x; return x;`（定值） | ct compile 0，cc 告警，运行得垃圾 | ct compile 1 |
| M7 | `char s[] = "x";`（合法 C） | `--types` 误报 1 | **ct compile 0**（不得误报） |
| M8 | `void *` 往返 `struct A *`（`test/ast/p45_contract/prog.ct`） | 全绿 | ct compile 0 |

M7/M8 是 A 的反证行：A 必须把它们守成 0，否则“强制”只是把误报转成全量拒绝。

## 4. E4 代价
- **改动文件数**：8–12 —— `frontend/type/TypeCheck.h.ct`、`frontend/parse/{Expr,Stmt,Parser,ParseSupport}.h.ct`、
  `tool/driver/Driver.h.ct`、`tool/diag/Diag.h.ct`、`frontend/module/Module.h.ct`（跨单元）、`backend/mem/Memory.h.ct`、
  `frontend/sym/Symbols.h.ct`。
- **LOC**：现有类型设施 = TypeCheck 1,061 + `chk_type`/`chk_assignable`/`arg_class` ≈ 300 + Memory 481；
  待补 = 表达式 20 种节点 + 语句 40 种节点 + CFG/定值独立 pass，净增估 **4,000–7,000 行**（含 250–400 个负例夹具）。
- **测试/门禁**：`check-ast`（299 目录 / 289 `prog.ct`）、`check-goldens`（445 golden）、`check-semantics`、
  `check-warnings`；语料 1,268 个 `.ct` 全量回归；每相必须带红证（T-7）。
- **phase 数/周期**：**4 相，不是 1 相**——(1) 表达式类型核心；(2) 调用/泛型/trait/容器/跨单元；(3) CFG/return/
  break/goto/switch/定值；(4) own/borrow/Drop 与包级。每相 4–6 周（含评审返工），合计 **4–6 个月**。
- **风险/回退**：234 类误报（已实测）；跨单元/`import` 未覆盖；`ctc.c` 冻结不可改；L1/L2 的 `MAX_*` 上限；
  golden 逐字节不变；§4.53 契约要改（单独立项）。每相独立提交，revert 单相回到上一相；强制化只允许一张
  1.0 到期的临时豁免清单，清单进 Issue 台账。

## 5. E5 steelman B（增量 opt-in）与逐条反驳
B 原文（`battle/typecheck-1/question.md:22-29`）：“编译路径保持现状（C 超集兼容）；`ct check` 增
`--types=strict` / `--semantics`……分 3–4 个 phase……全部 opt-in；等 false positive 与误报率稳定后，
再讨论是否进编译路径……不承诺 Rust 级借用检查”。

**Steelman**：B 最强点是 234 类误报无法在 1.0 前保证清零；opt-in 让误报只伤主动开启的人，不阻断存量包生态，
也不把 §4.53 契约一次性推翻；B 的 3–4 相与 A 的 4 相几乎同构，成本更低。

**反驳**：
1. B 的第一交付物是开关，不是覆盖率；`--types` 只有 3 个判定点，§1.1/1.2 的 4 个反例在 opt-in 下依然全绿，
   只是把“ct 绿、C 红”命名为“未来再说”。
2. B 说“等误报率稳定后再讨论进编译路径”，没有阈值、日期、owner；A 给机械闸：289 个 `prog.ct` + 1,268 个
   `.ct` 零误报才切换。没有闸的“等稳定”等于把决定推到 1.0 之后。
3. B 的相数与 A 相同，差别只在默认值；B 不是替代方案，是 A 的子集加一条无期限尾；相数一样，“先 opt-in
   再强制”只多付一次开关/双路径/双诊断的维护费。
4. B 自述“按已有 `own/borrow/Drop` 契约做可达子集”，这正是 A 的范围；A 不要求 Rust 级借用检查。
5. opt-in 的语料永不在 strict 下跑，检查器回归不可见；强制后 1,268 个 `.ct` 就是免费 oracle。

## 6. 结论
**A 胜出**：现状实测存在 6 类“ct 绿、C 红/运行错”（M1–M6），opt-in 只覆盖其中 2 类；1.0 目标要求编译路径
自身拒绝，因此必须强制。A 成立的前置闸写死：**234 类误报清零 + 跨单元落地 + 4 相在 6 个月内**。

**A 不成立的条件**（任一成立则退回 B，但保留 1.0 强制切换点）：
1. 1.0 前 234 类（数组/字符串初始化、函数指针、`void`）误报无法清零 → 强制即全量拒绝；
2. 跨单元/`import` 检查在 1.0 前无法落地 → 只能覆盖单文件，达不到 J-1；
3. 4 相超 6 个月或阻塞 1.0 其它交付 → 按 B 的 opt-in 过渡，但切换点不得晚于 1.0。
