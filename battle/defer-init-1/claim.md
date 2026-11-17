# 主张席（REQ）：`Some *s = defer Some::new();` 成立（A）

> 立场：A 是 §4.58 尾随声明的“缺省动作”形式，不是新的资源模型——`expr` 立即求值并赋值，退出时按 `delete` 语义释放，登记进既有 defer 栈；本席主动给出 A 的不利证据与不成立条件。

## A 的精确语义（v1）

| 项 | 规则 |
| --- | --- |
| 位置/判定 | 仅函数体内**单声明符**局部声明的初始化式：`T *name = defer expr ;`。`=` 后 token 为 `defer` 且其后不是 `{` 才算 A；`defer { … }` 语句与 `defer` 标识符不变（`defer_ahead` 不动） |
| 求值/登记 | `expr` 立即求值一次，结果赋 `name`，登记在赋值**之后**（同 §4.58:2580）；空值与失败构造由 `if (name)` 守卫在退出时跳过，不引入注册期检查 |
| 初始化式限制 | 只收堆来源：`malloc`/`calloc`/返回 `struct X *` 的工厂调用（复用 own 白名单 §4.9:467-469）；`&x`、指针算术、字面 0 报错——否则退出时非法 free（实测 `delete &x` 当前可编译） |
| 释放动作 | 等价 `delete name;`：`if (name) { [X_Drop_drop(name);] free(name); name = 0; }`（§4.9:374、§4.56:2554） |
| LIFO/出口 | 登记进声明所在块的 defer 栈的**声明点**；同块源码逆序、内层先于外层；与 `defer { }` 混排整体逆序；全部 defer（含 A）先于 `own` 释放（D38-4）。落出 `}`、`return`、`break`、`continue` 都跑，`return expr` 先求值到临时量（§4.9.1:501-502）；`return err:` 按 §4.58 跑全部活跃条目，A 无条件执行；不新增 `errdefer expr` |
| 与 `own` | 互斥：`own T *s = defer e;` 报错。A 不是所有权转移：`s = …;`、`q = s;`、`return s;` 报错；`delete s;` 允许并取消退出动作（同 §4.9:461） |
| 禁止位置/分工 | 多声明符、`for` 初始化、`switch` 内、文件作用域、`.m.ct` 沿用既有诊断（§4.58:2580、§4.9.1:505-509）；`.h.ct` 允许（:510-511）。所有权转移/逃逸 → `own`；**非 Drop 堆对象与标量指针只有 A**（own 拒绝，E1-4）；任意动作（close/unlock/自定义）→ `defer { }` / 尾随块 |

## E1 命令与原始输出

环境 `Darwin 27.2.0 arm64`、`Apple clang 21.0.0`；工作树 `91aeb189`（基线 `ce6aa436` + 一个 docs 提交），只读，产物只在 `/tmp`；复现链见文末（输出 `BUILD_OK`）。

**E1-1（不利 A：现有 `defer` 只收块，用户字面写法直接报错）**
```console
$ /tmp/di/ct-ast check /tmp/di/exact/m1_defer_init.ct; echo "exit=$?"
/tmp/di/exact/m1_defer_init.ct:4:41: error: use of an undeclared variable
exit=1
```
`m1` 即用户字面形态 `struct Some *s = defer Some_new(7);`；原因：`defer` 只有紧跟 `{` 才是关键字（§4.9.1:498-499、Stmt.h.ct:1385-1390）。A 还必须保持：语句位 `defer Some_new(7);` 报 `unexpected token`，`int defer = 3;` 编译通过。

**E1-2（不利 A：`own` 已覆盖 Drop + 工厂 + 零值）**
```console
$ bash test/ast/p49_own.sh /tmp/di/ct-ast | sed -n '1p;3p;9p'
ok E49-1 factory initializer (allocs=1 drops=1, guarded release)
ok E49-2 zero initializer (not registered, guarded factory null)
p49/own: 0 failure(s)
```

**E1-3（不利 A：尾随块已存在，四条出口都跑）**
```console
$ bash test/ast/p40_trailing.sh /tmp/di/ct-ast && /tmp/di/ct-ast /tmp/di/exact/b2_trailing_break.ct 2>/dev/null -o /tmp/di/exact/b2.c && cc -Wall -Wextra -std=c99 /tmp/di/exact/b2.c -o /tmp/di/exact/b2 && /tmp/di/exact/b2
p40_r5: OK
body 0
free 0
free 1
```
`break` 只跑退出到的那层块（i=1 之后无 `free 2`）；`return` 同理（b1）。`test/ast/220_defer_order` 的 LIFO 为 `body / b / a`，与 expected 一致。

**E1-4（利 A：`own` 覆盖不完整——非 Drop 与标量指针被拒）**
```console
$ for f in m2_own_nodrop m3_own_int; do /tmp/di/ct-ast check /tmp/di/exact/$f.ct 2>&1 | grep -F 'error:'; done
/tmp/di/exact/m2_own_nodrop.ct:3:1: error: struct 'Some' does not use trait 'Drop'
/tmp/di/exact/m3_own_int.ct:2:1: error: struct 'int' does not use trait 'Drop'
```
非 Drop 结构体与 `int *` 等标量指针 `own` 全拒；A 是唯一一条声明完成“创建+登记”的形式（`delete` 对两者都正确）。

**E1-5（利 A：尾随块 + `return s;` 是静默 UAF；A 的逃逸诊断可消除）**
```console
$ /tmp/di/ct-ast /tmp/di/exact/m4_trailing_return.ct -o /tmp/di/exact/m4.c 2>&1 | tail -1
/tmp/di/exact/m4_trailing_return.ct:3: warning: potential leak: 'p' (Some*) allocated but never deleted
$ cc -Wall -Wextra -std=c99 -fsanitize=address /tmp/di/exact/m4.c -o /tmp/di/exact/m4_asan && /tmp/di/exact/m4_asan 2>&1 | grep -m1 -o 'ERROR: AddressSanitizer: heap-use-after-free'
ERROR: AddressSanitizer: heap-use-after-free
```
编译器只报一个与 UAF 无关的 leak 警告并照常出产物；ASan 抓到返回已释放对象。A 标记声明后可在编译期对 `return s;` / `q = s;` 报错（复用 §4.9:483-484 的保守逃逸扫描）。

## E2 锚点（HEAD `91aeb189`，基线 `ce6aa436`）

| 判定 | `file:line` | 内容（匹配） |
| --- | --- | --- |
| 利 A | `docs/language-spec.md:374` | `delete q;` → `if (q) { free(q); q = 0; }`：A 的释放策略现成且带守卫 |
| 利 A | `docs/language-spec.md:2580` | 尾随声明 `Type name = expr defer { … };`、“在初始值之后注册”：A 的登记时机照抄此句 |
| 不利 A | `docs/language-spec.md:498-499` | “只收块形态，没有 `defer expr;`”——现行规范明文拒绝 A |
| 不利 A | `selfhost/ct-ast/frontend/parse/Stmt.h.ct:1385-1390` | `defer_ahead` 只在下一非空字符为 `{` 时认关键字；E1-1 的报错由此而来 |
| 不利 A | `selfhost/ct-ast/frontend/parse/Stmt.h.ct:1498` | “a trailing defer needs a single declaration”：A 必须继承单声明符限制 |

## E3 可证伪预测与反例（实现后一次性验证）

| # | 夹具 | A 成立时预测 | 反例（预测失败即 A 不成立） |
| --- | --- | --- | --- |
| 1 | `Some *s = defer Some_new(7);` | 编译、退出释放、`printf` 正常；今天报 4:41 错 | 仍报 `undeclared variable` → A 未实现 |
| 2 | `own Some *s = defer Some_new(7);` | 报错（不得双重登记） | 编译通过 → 双重释放 |
| 3 | `int *p = defer &x;` | 报错（非堆初始化） | 编译通过 → 退出时非法 free（ASan 必红） |
| 4 | `Some *s = defer Some_new(0);` | 编译、运行不崩、退出跳过 | 崩溃/重复 free → 守卫未生效 |
| 5 | Drop 类型工厂 + `defer` | 退出时 `drop` 出现一次 | 只有 `free` 无 `drop` → 释放动作错（§4.56:2554） |
| 6 | `Some *s = defer Some_new(7); return s;` | 编译期报错（逃逸） | 编译通过且 ASan 抓 UAF → 与 E1-5 同缺陷 |
| 7 | 同上前提 `s = Some_new(8);` | 编译期报错（不得重赋值） | 编译通过 → 泄漏旧对象/释放错对象 |
| 8 | 同上前提 `delete s;` | 恰好一次释放（delete 取消登记） | 双重释放 → 与 §4.9:461 不一致 |
| 9 | 语句位 `defer Some_new(7);` / `int defer = 3;` | 仍 `unexpected token` / 仍编译 | 任一改变 → 破坏 `defer` 标识符兼容 |

关键：A 若 desugar 到 `N_DEFER`，**没有运行时夹具能区分 A 与尾随块**（同一节点、栈、`delete`）；能区分的只有上表语法/诊断行（2、3、6、7、8、9）。因此 J-2 是决定性判据，J-4/J-5 只是回归保证。

## E4 代价

| 面 | 量 | 说明/风险 |
| --- | --- | --- |
| parser `Stmt.h.ct` | +80–100 行 | 新 `defer_init_ahead()` ~10、初始化式分支 ~45、逃逸/重赋值/own 互斥诊断 ~30；复用 `parse_trailing_defer`、`defer_add`、`defer_run_node` |
| `Memory.h.ct` / `Parser.h.ct` / `Diag.h.ct` | +28 行 | 登记时调用既有 `leak_delete`（:428）让 leak 分析看见释放；文件作用域专用诊断；4 条新文案 |
| emitter | **0** | 释放体是普通 `delete` 形状，`N_DEFER` 发射不变（Emitter.h.ct:4023-4025） |
| 文档/测试 | ~15 行 / ~200–250 行 | §4.9.1 一条、§4.58 交叉引用、§4.9 own 表加“不能与 defer 同用”；1 正例 + 8 负例 + probe + `check-ast.sh` 一行；现有夹具/golden **零改动** |
| phase/风险 | 1 stage（S1），effort M | 无 CFG/ABI/产物变更；风险：逃逸诊断假阳性（中）、J-2 概念重复（中高）、`defer` 标识符兼容（低，实测 `int defer` 仍编译） |
| 回退/门禁 | 3 个提交（test 红 + feat + docs） | revert feat 即回现状；无生成物入库、无 golden 重生成、版本位不动；不新增门禁编号（挂 G1/G3/G4/G5/G8，G5 负例随 feat） |

## E5 对 B 最强论点的 steelman 与回应

B 原文（`question.md:33-39`）：「`defer` 保持块级语句」「有 `Drop`：`own …`；无 `Drop`：`Some *s = Some::new() defer { delete s; };`」「若确实需要简写，新增明确关键字/限定符（如 `owned`/`with`），不要复用 `defer`」「`defer` 的语义是“延迟执行”，不是“立即构造 + 自动清理”」。

1. **最强的是 B2“现有机制已覆盖”。** 承认：`own` 覆盖 Drop 的本地/逃逸，尾随块覆盖非 Drop 与任意动作，p49/p40 全绿。但覆盖不完整且不安全：`own` 拒绝非 Drop 与标量指针（E1-4），尾随块在 `return s;` 上静默 UAF（E1-5），手写释放还要在 `free`/`delete` 之间选对（`:2554`）。A 的增量不是“能表达”，而是“**缺省就正确**”。
2. **B4“延迟直觉”。** 延迟的是**释放动作**，不是构造；赋值 `s =` 明示构造立即发生，语句位 `defer expr;` 仍是 `unexpected token`，不存在“两种位置两种含义”。先例：Go 的 `defer f(g())` 也是 g 立即、f 延迟；若仍嫌拼写误导可改拼写（B3），那是命名分歧。
3. **B3“换关键字”。** `owned` 与 `own` 语义撞车，`with` 引入全新词汇；`defer` 已命名“作用域出口”，初始化式只是给它一个缺省动作。新增关键字的规范面（关键字表、编辑器、迁移）大于一次 lookahead。
4. **B1“不要复用”。** A 不改 `defer_ahead`、不保留 `defer`、不新增语句位语义；`int defer = 3;` 实测通过，与 D38-7 的上下文关键字策略同构。
5. **J-2 最强形式是“同一机制第三种拼写”。** 不回避：A 确实增加一种拼写。若 J-2 的“两套资源机制”按**拼写数**解释，A 输；按**资源模型数**解释，A 赢——A 不新增模型、栈与释放规则，规范一句话即可写成 `T *s = defer e;` ≡ `T *s = e defer { delete s; };`。

## 结论

**判据判定**：J-1 成立（位置受限、可区分）；J-3 成立（上下文关键字 + 单点 lookahead）；J-4 成立（继承 §4.58 四条出口，并以逃逸诊断消除 E1-5 类 UAF）；J-5 成立（零 golden 改动）；J-6 成立（~150 源行、1 stage、emitter 零改动）。**J-2 取决于解释**：按“资源模型”成立，按“拼写数”不成立。

**A 胜出条件**（全部满足）：(a) 严格 desugar 到 §4.58 尾随块 + 隐式 `delete`，不新增运行期规则、LIFO 段或 emitter 路径；(b) 实现 E3 第 2/3/6/7/8 行的诊断，不允许静默 UAF/双释放；(c) 不改 `defer_ahead` 与语句位语义；(d) 代价 ≤ ~250 源行 + 1 stage，现有夹具/golden 零改动。

**A 不成立条件**（任一成立即判 B）：(1) 实现必须动 emitter/CFG 或改 `own` 语义；(2) 无法在 L40-9 的单声明符限制内解析，或 `int defer = 3;`/语句位行为被改变；(3) 逃逸/重赋值不能诊断，留下 E1-5 类静默 UAF；(4) 裁判把“同一机制的第二种拼写”按 J-2 计为失败——这是价值判断，按 §7.9 交 EDITOR/用户；若从严，B 胜，最小替代是放宽 `own` 的 Drop 前置（非本席主张）。

## 夹具与复现链（E1 用；只写 `/tmp`，未改仓库）

夹具依次为 `m1_defer_init.ct`、`m2_own_nodrop.ct`、`m3_own_int.ct`、`m4_trailing_return.ct`、`b2_trailing_break.ct`；`b1` 与 b2 同型，把循环换成 `f(int early)` 的两次调用。

```ct
/* m1 */ #include <stdio.h>
#include <stdlib.h>
struct Some { int n; }; static struct Some *Some_new(int n) { struct Some *p = malloc(sizeof(struct Some)); p->n = n; return p; }
int main(void) { struct Some *s = defer Some_new(7); printf("%d\n", s->n); return 0; }
/* m2 */ #include <stdlib.h>
struct Some { int n; }; static struct Some *Some_new(int n) { struct Some *p = malloc(sizeof(struct Some)); p->n = n; return p; }
int main(void) { own struct Some *s = Some_new(7); return 0; }
/* m3 */ #include <stdlib.h>
int main(void) { own int *p = malloc(sizeof(int)); return 0; }
/* m4 */ #include <stdio.h>
#include <stdlib.h>
struct Some { int n; }; static struct Some *Some_new(int n) { struct Some *p = malloc(sizeof(struct Some)); p->n = n; return p; }
static struct Some *make(void) { struct Some *s = Some_new(7) defer { delete s; }; return s; }
int main(void) { struct Some *p = make(); printf("n=%d\n", p->n); return 0; }
/* b2 */ #include <stdio.h>
#include <stdlib.h>
struct Some { int n; }; static struct Some *Some_new(int n) { struct Some *p = malloc(sizeof(struct Some)); p->n = n; return p; }
int main(void) { int i; for (i = 0; i < 3; i = i + 1) { struct Some *s = Some_new(i) defer { printf("free %d\n", s->n); delete s; }; if (i == 1) { break; } printf("body %d\n", i); } return 0; }
```

复现链（仓库根执行，产物在 `/tmp`；`selfhost/check-ast.sh:398-431` 同形）：

```console
$ cc -Wall -Wextra -std=c99 selfhost/l0/ctc.c -o /tmp/di/ctc && /tmp/di/ctc selfhost/l1/ctc.ct -o /tmp/di/l1.c && cc -Wall -Wextra -std=c99 /tmp/di/l1.c -o /tmp/di/l1 && /tmp/di/l1 build selfhost/l2/driver.ct -o /tmp/di/l2src && cc -Wall -Wextra -std=c99 /tmp/di/l2src/*.c -o /tmp/di/l2 && /tmp/di/l2 build -I selfhost/ct-ast selfhost/ct-ast/main.ct -o /tmp/di/astsrc && cc -Wall -Wextra -std=c99 /tmp/di/astsrc/*.c -o /tmp/di/ct-ast && echo BUILD_OK
BUILD_OK
```
