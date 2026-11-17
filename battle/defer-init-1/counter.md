# counter.md — 反对席（REVIEW）：主张 B

- **主张**：B —— `defer` 只保留块级语句；创建+清理用 `own`/尾随块/两条语句；要简写则另立关键字，不复用 `defer`。未读 `claim.md`，未改源码/规范/测试。
- **HEAD**：`91aeb189`（题面基线 `ce6aa436`，源码相同，仅多一个 docs 提交）；**环境**：Darwin arm64 / Apple clang 21.0.0 / ct-ast v0.65.1；产物在 `/tmp/defer-battle`。

## 1. B 的语义边界与覆盖
`defer` 的既有语义是“把执行推迟到作用域退出”：只收 `defer { … }`（§4.9.1），四条出口 LIFO，其它位置是普通标识符（D38-7）。B 不让同一关键字在初始化式里表示“立即求值 + 赋值 + 退出时清理”——那是相反的时间语义。

- 有 `Drop` 的 struct：`own Some *s = Some_new();`（已有，p14）。
- 无 Drop / 自定义清理：`T *s = expr; defer { cleanup(s); }`（已有，p8）或 `T *s = expr defer { cleanup(s); };`（已有，p9）。
- 还要更短：新关键字/限定符（如 `owned`/`with`），不复用 `defer`（另立，不在本 battle）。

对用户的 `Some`（Drop）例子，`own` 已经是一行且比 A 短 2 字符（25 vs 27，E1）。对无 Drop 的资源，`defer expr` 没有位置写 `close_fd(fd)`；若默认 `delete`/`free`，对 `int fd` 或自定义 close 就是错的（p8、p13）。所以 A 不是“创建+清理”的通用简写，只是“可 free 指针”的局部糖。

不复用 `defer` 的四条理由：
1. **语义反转**：块级 defer 延迟执行；初始化式 defer 立即执行、延迟清理。J-1 直接受损。
2. **清理动作不可判定**：A 第 3 点说由 Drop/delete 或“显式尾随块”决定；有显式块就已经是长写法，没有块就必须猜 `delete`/`free`，而 `defer expr` 没有清理表达式的位置。
3. **标识符兼容**：`defer` 现在是合法变量名（仓库夹具 `test/ast/224_defer_branches/prog.ct:72`），`int y = defer(41);` 今天调用名为 `defer` 的函数（p2c）。A 必须在同一位置容纳两种读法。
4. **第三套机制**：已有 `own`（Drop）、尾随块/块级 defer（显式清理）、`errdefer`；A 第 4 点还要新增“二者不能同时登记”的检查，资源机制从两套变三套。

## 2. E1 命令与原始输出
构建（基线源码，产物只在 `/tmp`）：
```console
$ cc -Wall -Wextra -std=c99 selfhost/l0/ctc.c -o /tmp/defer-battle/ctc
$ /tmp/defer-battle/ctc selfhost/l1/ctc.ct -o /tmp/defer-battle/l1.c && cc -Wall -Wextra -std=c99 /tmp/defer-battle/l1.c -o /tmp/defer-battle/l1
$ /tmp/defer-battle/l1 build selfhost/l2/driver.ct -o /tmp/defer-battle/l2src && cc -Wall -Wextra -std=c99 /tmp/defer-battle/l2src/*.c -o /tmp/defer-battle/l2
$ /tmp/defer-battle/l2 build -I selfhost/ct-ast selfhost/ct-ast/main.ct -o /tmp/defer-battle/astsrc && cc -Wall -Wextra -std=c99 /tmp/defer-battle/astsrc/*.c -o /tmp/defer-battle/ct-ast
$ CT=/tmp/defer-battle/ct-ast; P=/tmp/defer-battle/probes
$ $CT --version
ct-ast v0.65.1
```

既有探针与夹具（回归基线）：
```console
$ CT=/tmp/defer-battle/ct-ast; P=/tmp/defer-battle/probes
$ bash test/ast/p49_own.sh $CT | tail -1
p49/own: 0 failure(s)
$ bash test/ast/p40_errdefer_scope.sh $CT
p40_r2: OK
$ run() { $CT "$1" -o /tmp/defer-battle/o.c && cc -Wall -Wextra -std=c99 /tmp/defer-battle/o.c -o /tmp/defer-battle/o.bin && /tmp/defer-battle/o.bin; }
$ neg() { $CT check "$1" 2>&1; echo rc=$?; }
$ run test/ast/220_defer_order/prog.ct
body
b
a
$ run test/ast/224_defer_branches/prog.ct | tail -1
defer=1
```

支持 B：
```console
$ neg $P/p1_defer_init.ct
$P/p1_defer_init.ct:11:28: error: use of an undeclared variable
rc=1
$ run $P/p2_defer_ident.ct
x=4 y=6
$ run $P/p2c_defer_fnarg.ct
y=42
```

B 的不利证据（尾随块仍啰嗦、`own` 只适用 Drop、用户要简写）：
```console
$ neg $P/p3_own_nondrop.ct
$P/p3_own_nondrop.ct:3:1: error: struct 'char' does not use trait 'Drop'
ctc: 1 error(s) generated
rc=1
$ neg $P/p5_trailing_multi.ct
$P/p5_trailing_multi.ct:2:22: error: a trailing defer needs a single declaration
ctc: 1 error(s) generated
rc=1
$ neg $P/p6_trailing_assign.ct
$P/p6_trailing_assign.ct:4:29: error: a trailing defer needs a single declaration
ctc: 1 error(s) generated
rc=1
$ neg $P/p7_trailing_for.ct
$P/p7_trailing_for.ct:2:20: error: a trailing defer needs a single declaration
ctc: 1 error(s) generated
rc=1
$ printf '%s\n' 'own Some *s = Some_new();' 'Some *s = defer Some_new();' 'Some *s = Some_new() defer { delete s; };' | awk '{print length($0), $0}'
25 own Some *s = Some_new();
27 Some *s = defer Some_new();
41 Some *s = Some_new() defer { delete s; };
```

B 的三条覆盖路径（同一用户场景）：
```console
$ run $P/p14_own_drop.ct
n=7
drop 7
$ run $P/p8_two_stmt_fallback.ct
fd=3
close 3
$ run $P/p9_trailing_drop.ct
n=7
drop 7
```

## 3. E2 `file:line` 锚点
支持 B：
- `docs/language-spec.md:498-499`：`defer { … }` 后必须紧跟 `{`，其它位置是普通标识符；“只收块形态，没有 `defer expr;`”。
- `selfhost/ct-ast/frontend/parse/Stmt.h.ct:1384-1390`：`defer_ahead()` 只看 token 后首个非空白字符是否为 `{`；A 必须改这里。
- `selfhost/ct-ast/frontend/parse/Stmt.h.ct:1472-1523`：`parse_trailing_defer()` 已实现“声明 + 尾随清理块”，A 声称的简写已有等价长形式。
- `test/ast/224_defer_branches/prog.ct:72`：`int defer = 1;`，现有夹具把 `defer` 当变量名钉住。
- `test/ast/220_defer_order/prog.ct:5-6`：块级 defer LIFO。

不利于 B：
- `docs/language-spec.md:467-470`：`own` 初始化式只接受 `malloc`/`calloc`/返回 `struct X *` 的自由函数，且必须是 `use Drop` 的 struct 指针；`char *`/`int fd` 不行（p3）。
- `docs/language-spec.md:2580`：尾随块只允许单声明符；赋值形式、多声明符、`for` 初始化都报 L40-9（p5–p7）。
- `selfhost/ct-ast/frontend/parse/Stmt.h.ct:1498`：上述单声明符限制的实现点。

## 4. E3 可证伪预测与反例
P1（B 的强形式，易被攻击）：每个“创建+清理”场景，`own` 或尾随块都能一行无歧义写出。四个反例（均已跑）：

| # | 场景 | 结果 | 说明 |
| --- | --- | --- | --- |
| C1 | `own char *p = malloc(8);` | p3 报 L49-1 | `own` 只覆盖 Drop struct |
| C2 | `int a = 1, b = 2 defer { … };` | p5 报 L40-9 | 尾随块只覆盖单声明符 |
| C3 | `p = malloc(…) defer { … };` | p6 报 L40-9 | 尾随块不覆盖赋值 |
| C4 | `for (int i = 0 defer { … }; …)` | p7 报 L40-9 | 尾随块不覆盖 for 初始化 |

P2（B 的实际主张，可被证伪）：上述每个场景都能用“声明 + 块级 defer”两条语句（或拆分声明/外包块）在相同作用域与出口语义下表达：C1/C3 用 p8 的形式，C4 用循环外包块 + 声明/defer，C2 拆两行。没有一条必须靠 `defer expr` 才有语义；真正只有 A 能写的是“单行/for-init 简写”，不是表达能力。要这个简写应按 B 第 3 点另立关键字。
证伪 P2 的条件：给出一个 A 能表达、且两条语句/尾随块无法在相同作用域与出口语义下复现的场景。就“立即求值、退出清理”的定义，本席没有找到：`for` 初始化可用循环外块 + 声明/defer 复现，`break/continue/return` 的清理由块级 defer 同一套出口机制覆盖。

## 5. E4 代价
A（新增 `defer expr`）：
- **parser**：`defer_ahead()` 改为识别初始化式，并在声明解析处接入；同时区分 `defer` 变量/函数调用（p2/p2c）。至少触及 `frontend/parse/Stmt.h.ct`（4144 行）与 `frontend/parse/Expr.h.ct`（7217 行）。
- **语义/发射**：复用 `N_DEFER` 时要在声明点登记，定义与 `own`/尾随块/`errdefer` 的顺序；`Emitter.h.ct` 6593 行，`N_DEFER` 触点在 `Emitter.h.ct:4023-4025`、`5068`。还要定义空指针/构造失败、`for` 初始化、多声明符、赋值形式的规则。
- **文档/测试**：§4.9.1（486-510）、§4.58（2575-2582）加语义；新增正/负夹具与 golden；重跑 `check-ast`（含自举 fixpoint）与文档门禁。
- **量级**：最近似的 `parse_trailing_defer()` 51 行（1472-1522），`defer_ahead()` 12 行（1380-1391）；A 至少新增同类分支 + 诊断 + 文档 + 夹具，估计 100–200 行源码（不含 golden/文档），影响 3 个源码文件 + 1 个规范 + 测试门禁。**回退**：一个提交 revert。

B：源码 0 行、规范 0 行、测试 0 行、门禁 0 个。可选只加一条诊断（“defer initializer is not supported; use own or trailing defer”），不改语义。**迁移**：无；`test/ast/224_defer_branches/prog.ct:72` 的 `int defer` 与 p2c 的 `defer(41)` 保持原义。
## 6. E5 steelman A 与逐条反驳
A 最强原文（`question.md`）：
- “用户希望把‘创建 + defer 清理’合并成一条语法”（第 7 行）。
- “`defer expr` 是它的简写”（A 第 5 点）；“清理动作由 Drop/delete 或显式尾随块决定”（A 第 3 点）；“own 自动 Drop，defer 负责无 Drop 的显式释放”（A 第 4 点）。

Steelman：一行完成创建+清理，声明与清理相邻，不用记得补 defer；对 `for` 初始化、多声明符、赋值这些尾随块不收的位置，A 是唯一的一行写法；对非 Drop 资源，`own` 不适用，A 提供统一的“创建处登记”心智模型。

逐条反驳：
1. **Drop 场景**：`own` 已是一行且更短（25 vs 27，E1），A 没有收益；`own` 还自动处理 null/逃逸/重赋值。
2. **非 Drop 场景**：A 没有写清理动作的位置。默认 `delete`/`free` 对 `int fd` 会发射 `if (fd) { free(fd); fd = 0; }`（p13 生成的 C，`free` 收 int 是错的），对自定义 close 直接错；若要显式尾随块，就退回 41 字符长形式，A 第 5 点的“简写”不成立。
3. **防遗漏/统一心智**：A 相比 `own` 不增加安全性，只是把清理写成关键字前缀，仍可能写错/写漏清理动作；用 `defer` 承载“立即构造”又与块级 defer 的“延迟执行”冲突，J-1 不划算。
4. **简写需求真实**：B 不否认 `for`-init/多声明符的空白；正因如此应另立关键字（第 3 点），把清理动作显式化，而不是让 `defer` 猜。
## 7. 结论
B 在 J-1（语义清晰）、J-2（不增第三套机制）、J-3（标识符/语法无歧义）、J-5（零兼容风险）、J-6（零改动）胜出；J-4 由既有 defer 四条出口覆盖，A 反而要新增顺序/失败/多声明符规则。B 的代价是 C1–C4：`own` 只覆盖 Drop struct，尾随块不收多声明符/赋值/for-init；这些场景用两条语句或拆行可表达，损失的是字符数，不是语义。

B 不成立的条件（交给裁判）：
- 用户/裁判把“非 Drop 资源的一行简写”列为硬需求，且拒绝新关键字，只接受 `defer expr`；
- 或给出一个 A 能表达、B 的两条语句/尾随块在相同作用域与出口语义下无法复现的场景（本席未找到）。
若触发，应走 §7.10 的 C 方案（新关键字/限定符），而不是直接把 A 判为 B 的替代。
