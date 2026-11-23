# v0-PH-76 收口复核（REV）

> **结论（补正后）：`REV: 通过`**（SH-92 已修复并复核；原 `REV: 不通过` 记录保留在 §5/§9，
> 补正证据见 §10）
> **复核对象**：`247ade5bd5a2c7e4278d29df9c1ebcd16d302c67`
> （``feat(ast): v0-PH-76 链中物化 `$name` 收口（v0.76.0）``），tag `v0.76.0`。
> **补正对象**：`d16d6ffab8661e0ccc87f1b8f2ffbfcbe7e81ce8`（SH-92 fix，tag `v0.76.1`），
> 红证 `b2aefc6b3117a5b2f4008daadead4159b1e21e36`；补正复核于 2026-11-19 18:42。
> **复核者**：REV / rev-ph76；日期 2026-11-19。
> **方法**：只依据 tag 归档与 clean 副本。用
> `git archive v0.76.0 | tar -x -C /tmp/rev-ph76` 取源码，在 `/tmp/rev-ph76` 重新自举
> L0→L1→L2→ct-ast；红证在 `6591aa65` 的归档副本 `/tmp/rev-ph76-base` 上重建编译器复现；
> 不使用工作树当前产物，也不采信提交正文的转述。
> **并行说明**：复核期间工作树只有另一会话的未跟踪目录 `battle/static-dispatch-1/`；本报告全部
> 验收都在归档副本上做，verdict 提交只含本文件。

## 1 环境与自举

```console
$ uname -m; uname -sr; cc --version | head -1; gcc --version | head -1; git --version
arm64
Darwin 27.2.0
Apple clang version 21.0.0 (clang-2100.4.1.1)
Apple clang version 21.0.0 (clang-2100.4.1.1)
git version 2.54.0 (Apple Git-157)

$ cd /tmp/rev-ph76
$ gcc -Wall -Wextra -std=c99 selfhost/l0/ctc.c -o /tmp/rev-ph76-work/ctc
$ /tmp/rev-ph76-work/ctc selfhost/l1/ctc.ct -o /tmp/rev-ph76-work/l1.c
$ gcc -Wall -Wextra -std=c99 /tmp/rev-ph76-work/l1.c -o /tmp/rev-ph76-work/l1
$ /tmp/rev-ph76-work/l1 build selfhost/l2/driver.ct -o /tmp/rev-ph76-work/l2src
$ gcc -Wall -Wextra -std=c99 /tmp/rev-ph76-work/l2src/*.c -o /tmp/rev-ph76-work/l2
$ /tmp/rev-ph76-work/l2 build -I selfhost/ct-ast selfhost/ct-ast/main.ct -o /tmp/rev-ph76-work/astsrc
$ gcc -Wall -Wextra -std=c99 /tmp/rev-ph76-work/astsrc/*.c -o /tmp/rev-ph76-work/ct-ast
$ /tmp/rev-ph76-work/ct-ast --version
ct-ast v0.76.0
```

自举链全程零警告；归档版本与 `CTC_VERSION` 一致。

## 2 卡 §3/§7：`p76_chain.sh`

```console
$ cd /tmp/rev-ph76 && sh test/ast/p76_chain.sh /tmp/rev-ph76-work/ct-ast
OK p76/chain (tail, multi-hop, type/const/non-call/argument negatives)
EXIT=0
```

该脚本覆盖卡 §7 的 tail、multi、type/const/非调用/实参六组；结果 OK（但见 §5：脚本没有 void 负例）。

## 3 行为复核（正例）

卡 §7 的 tail 与多跳均在归档二进制上复现：

```console
$ cd /tmp/rev-ph76-work/t
$ /tmp/rev-ph76-work/ct-ast build -o once.bin once.ct     # a.make()$x.n()$y
$ ./once.bin; echo $?
mcalls=1 ncalls=1 x=7 y=7
0
$ /tmp/rev-ph76-work/ct-ast --emit-c -o once3.c once.ct
$ sed -n '/int main/,/^}/p' once3.c
int main(void) {
    struct A a = { 5 , .__make_vptr = &A_Make_vtable};
    struct B x = { .__n_vptr = &B_N_vtable };
    int y;
{
        x = a.__make_vptr->make(&a);
        y = x.__n_vptr->n(&x);
    }
    printf("mcalls=%d ncalls=%d x=%d y=%d\n", mcalls, ncalls, x.w, y);
    return 0;
}
```

生成物是 `{ x = call; y = x.n(); }`，`make`/`n` 各恰好求值一次；与显式拆链
（`x = a.make(); y = x.n();`）运行输出逐字相同（`mcalls=1 ncalls=1 x=7 y=7`，rc=0）。
tail 用例 `s.m()$x` 由 §2 的脚本验证（`return x` 得 1）。

## 4 行为复核（负例）

在归档二进制上逐条复现（fixture 为我独立编写，非复用脚本内的临时文件）：

```console
$ /tmp/rev-ph76-work/ct-ast check --types tm.ct
tm.ct:6:53: error: '$' target: expected 'int', got 'struct B'
ctc: 1 error(s) generated
rc=1
$ /tmp/rev-ph76-work/ct-ast check --types cn.ct
cn.ct:4:60: error: a const value cannot be a '$' target (v0-PH-76)
ctc: 1 error(s) generated
rc=1
$ /tmp/rev-ph76-work/ct-ast check --types nc.ct
nc.ct:4:46: error: '$name' must follow a method call (v0-PH-76)
ctc: 1 error(s) generated
rc=1
$ /tmp/rev-ph76-work/ct-ast check --types ag.ct
ag.ct:5:62: error: '$name' is only allowed in a statement expression (v0-PH-76)
ctc: 1 error(s) generated
rc=1
$ /tmp/rev-ph76-work/ct-ast check --types own2.ct   # own struct S *p = malloc(...)，类型匹配
own2.ct:9:10: error: own/borrow cannot be a '$' target (v0-PH-76)
ctc: 1 error(s) generated
rc=1
$ /tmp/rev-ph76-work/ct-ast check --types borrow.ct # borrow struct S *p
borrow.ct:5:50: error: own/borrow cannot be a '$' target (v0-PH-76)
ctc: 1 error(s) generated
rc=1
$ /tmp/rev-ph76-work/ct-ast check --types th/prog.ct       # import lib::ops 的 type-host
th/prog.ct:8:13: error: '$name' does not support type-host / .m.ct recipes in v1 (v0-PH-76)
ctc: 1 error(s) generated
rc=1
$ /tmp/rev-ph76-work/ct-ast check --types th/recipe.ct     # lib::FileOps.tell(h)$x
th/recipe.ct:8:25: error: '$name' does not support type-host / .m.ct recipes in v1 (v0-PH-76)
ctc: 1 error(s) generated
rc=1
$ /tmp/rev-ph76-work/ct-ast check --types cond.ct
cond.ct:4:54: error: '$name' is only allowed in a statement expression (v0-PH-76)
ctc: 1 error(s) generated
rc=1
$ /tmp/rev-ph76-work/ct-ast check --types decl.ct
decl.ct:4:58: error: '$name' is only allowed in a statement expression (v0-PH-76)
ctc: 1 error(s) generated
rc=1
$ /tmp/rev-ph76-work/ct-ast check --types ret.ct
ret.ct:4:40: error: '$name' is only allowed in a statement expression (v0-PH-76)
ctc: 1 error(s) generated
rc=1
$ /tmp/rev-ph76-work/ct-ast check --types opt2.ct          # q?.v$y
opt2.ct:6:9: error: '$name' must follow a method call (v0-PH-76)
ctc: 1 error(s) generated
rc=1
$ /tmp/rev-ph76-work/ct-ast check --types opt3.ct          # a.m()$x?.n()$y
opt3.ct:12:12: error: optional method calls are not supported; assign the receiver to a variable first
ctc: 1 error(s) generated
rc=1
```

`$` 只在语句表达式的链首被接受：条件、声明初始化式、`return`、实参、下标与非方法调用均硬错；
`?.` 之后、own/borrow/const、type-host 与 `.m.ct` recipe 均硬错。这部分与卡 §4/§7 一致。

## 5 阻断项（原）：`void` 返回不是硬错（E76-3 未满足；已在 SH-92 / `d16d6ffa` 修复，见 §10）

卡 §4 的冻结判据 E76-3 明写「类型不匹配、**void**、`?.`、own/borrow/const、type-host、
条件/实参/下标均硬错」（[phase76.md:86](../phases/v0-PH-76/card.md)），tutorial §13.3 也把
`a.void_method()$x.n();  /* 返回 void，无可赋值结果 */` 列在「拒绝的形态」
（[tutorial.md:1842](../tutorial.md)）。实测**不是**硬错：

```console
$ cat void_min.ct
trait M { void m(void); }
struct S { int v; } use M;
impl M for S { void m(void) { } }
int main(void) { struct S s = { 1 }; int x; s.m()$x; return 0; }

$ /tmp/rev-ph76-work/ct-ast check void_min.ct; echo rc=$?
rc=0
$ /tmp/rev-ph76-work/ct-ast check --types void_min.ct; echo rc=$?
rc=0
$ /tmp/rev-ph76-work/ct-ast build -o void_min.bin void_min.ct
'cc' -std=c99 -I '.ctbuild' '.ctbuild/void_min.c' '-o' 'void_min.bin'
void_min.ct:30:11: error: assigning to 'int' from incompatible type 'void'
   30 |         x = s.__m_vptr->m(&s);
      |           ^ ~~~~~~~~~~~~~~~~~
1 error generated.
rc=1
```

`ct check` 与 `ct check --types` 都放行；`ct build` 生成的 C 是
`x = s.__m_vptr->m(&s);`，把 void 表达式赋给 int，直到宿主 `cc` 才报错——这正是
语言规范 §4.11 所禁止的「明知编不过的 C」，不是 `ct` 的硬错。

根因：`$` 分支的类型检查以 `static_ctype(n, …) != 0` 为前提
（[Expr.h.ct:4369](../../selfhost/ct-ast/frontend/parse/Expr.h.ct)），而 `static_ctype` 对
`void` 返回 0（函数返回 void 见
[Expr.h.ct:4022](../../selfhost/ct-ast/frontend/parse/Expr.h.ct)，trait 方法见
[Expr.h.ct:4071-4072](../../selfhost/ct-ast/frontend/parse/Expr.h.ct)），于是 guard 直接跳过，
`chk_assignable` 从未运行，也没有任何显式的 void 拒绝分支。卡 §7 的 S2 证据只写了
`'$' target: expected 'int', got 'struct B'`，没有覆盖 void；`p76_chain.sh` 也没有 void 负例，
因此门禁全绿掩盖了这条冻结判据的缺口。

**必须补做**：在 `$` 处显式拒绝 void 返回（ct 诊断，例如
`'$' target: ... got 'void'` 或专用文案），在 `test/ast/p76_chain.sh` 增加 void 负例，
并补卡 §7 的 E76-3 证据；修好后按 6.7 V-3/`fix-tags` 走一次 fix（v0.76.0 已推 tag，不可回改）。

## 6 红证与祖先链

```console
$ git log -1 --format='%H%n%P%n%s' d8570e92
d8570e92c070d5f0175c8c5eacd8793a3dac687c
6591aa651d36fac2c6aca67ad8f9469dfed4da26
test(ast): v0-PH-76-S1 红（`$name` 链中物化）
$ git log -1 --format='%H%n%P%n%s' c3889bda
c3889bda27649beda458488873c29077094aaeb3
d8570e92c070d5f0175c8c5eacd8793a3dac687c
feat(ast): v0-PH-76-S1..S3 `$name` 链中物化
$ git merge-base --is-ancestor 6591aa65 HEAD && echo baseline_is_ancestor=yes
baseline_is_ancestor=yes
$ git merge-base --is-ancestor d8570e92 c3889bda && echo red_is_impl_parent=yes
red_is_impl_parent=yes
```

红提交只改 `test/ast/p76_chain.sh`（110 行新增，测试夹具），是实现的父提交；baseline 是红提交父提交。
在 `6591aa65` 的归档副本上重建 `ct-ast v0.74.0` 后复跑红证：

```console
$ cd /tmp/rev-ph76-base && sh test/ast/p76_chain.sh w/ct-ast; echo RED_EXIT=$?
FAIL p76/chain: tail build failed
  tail.ct:4:50: error: unexpected token
FAIL p76/chain: multi build failed
  multi.ct:12:13: error: unexpected token
FAIL p76/chain: type mismatch not diagnosed
  type.ct:6:53: error: unexpected token
FAIL p76/chain: const target not refused
  const.ct:4:60: error: unexpected token
FAIL p76/chain: non-call base accepted
  noncall.ct:4:46: error: unexpected token
FAIL p76/chain: argument-position '$' accepted
  arg.ct:5:62: error: unexpected token
RED_EXIT=1
```

红→绿的提交关系与复现均成立。

## 7 版本、tag 与 G8

五处 `CTC_VERSION`（归档内）全部为 0.76.0：

```console
$ grep -n 'define CTC_VERSION' selfhost/l0/ctc.c selfhost/l1/ctc.ct selfhost/l2/core.ct selfhost/l2/driver.ct selfhost/ct-ast/main.ct
selfhost/l0/ctc.c:61:#define CTC_VERSION "0.76.0"
selfhost/l1/ctc.ct:108:#define CTC_VERSION "0.76.0"
selfhost/l2/core.ct:55:#define CTC_VERSION "0.76.0"
selfhost/l2/driver.ct:36:#define CTC_VERSION "0.76.0"
selfhost/ct-ast/main.ct:36:#define CTC_VERSION "0.76.0"
```

tag 对象 / peeled / 远端一致：

```console
$ git cat-file -t v0.76.0
tag
$ git rev-parse v0.76.0
8bdfbfaee8a236854d96412783c699b9b390c052
$ git rev-parse v0.76.0^{commit}
247ade5bd5a2c7e4278d29df9c1ebcd16d302c67
$ git ls-remote origin 'refs/tags/v0.76.0*'
8bdfbfaee8a236854d96412783c699b9b390c052	refs/tags/v0.76.0
247ade5bd5a2c7e4278d29df9c1ebcd16d302c67	refs/tags/v0.76.0^{}
$ git branch -r --contains 247ade5b
  origin/HEAD -> origin/main
  origin/main
```

G8：

```console
$ bash tools/check.sh g8; echo G8=$?
g8: OK (PN-2 version coherence; 9 legacy offsets)
G8=0
```

（上述 9 条 legacy offset 警告均针对 v0.66.0–v0.74.0 的历史相位，不涉及 v0-PH-76。）

工作树与 tag 无差异；`git show 247ade5b -- test/cases` 的非 banner 行为空，golden 只改了
`v0.74.0`→`v0.76.0` 的 banner 两行/例（v0.75.0 为已登记的历史空位）。

## 8 非阻断观察

1. **tutorial §13 的标题/状态块仍是旧文案。** [tutorial.md:1780](../tutorial.md) 仍写
   「规划预览……（Phase 76，未实现）」，1782 行仍写「Phase 76 规划中，当前 `ct` 不接受
   `$name`」；同节 §13.4（1856 行）却写「v0.76.0 起可用（语句表达式内）」。功能已实现，
   标题/状态是反向过时，不影响本次 E76-3 的判定，但应在补 void 的同一 fix 中一并改掉。
2. **赋值右值不是「语句表达式」的接受面。** `int y; y = s.m()$x;` 报
   `'$name' is only allowed in a statement expression (v0-PH-76)`（rc=1）：
   `parse_expr_stmt_node` 在解析语句顶层后先把 `mat_state` 清零
   （[Stmt.h.ct:4180-4183](../../selfhost/ct-ast/frontend/parse/Stmt.h.ct)），再解析 `=` 右侧，
   所以 `$` 只接受「整条语句就是该链」的形态。实现比规范 §4.11.3 的字面「语句表达式」
   更窄；现行文档没有承诺 `y = …$x;`，故非阻断，建议在 §4.11.3 写清「链必须占满整条
   语句表达式」。

## 9 原结论（2026-11-19 首轮，保留）

`p76_chain` 绿、正例/多数负例、红证、版本、tag、G8 均通过；但冻结判据 E76-3 明确要求的
**void 硬错**没有实现：`ct check --types` 放行，`ct build` 产出把 void 赋给 int 的坏 C，
直到宿主 `cc` 才失败。按「phase 退出判据未满足不得宣称完成」的口径，本次收口复核不通过。

**`REV: 不通过`**

---

## 10 补正复核（SH-92 / v0.76.1，2026-11-19）

> 首轮阻断项（§5）由 DEV 以 `b2aefc6b`（test 红）→ `d16d6ffa`（fix）修复，tag `v0.76.1`
> 已推。本节给出独立复核；§1–§9 保留首轮记录，不改写。

### 10.1 提交与红证

```console
$ git log -1 --format='%H%n%P%n%s' b2aefc6b
b2aefc6b3117a5b2f4008daadead4159b1e21e36
6d51276e23ed0251cb406020bdb0bce1f5dbccea
test(ast): SH-92 红（void 跳 `$x` 未拒绝）
$ git log -1 --format='%H%n%P%n%s' d16d6ffa
d16d6ffab8661e0ccc87f1b8f2ffbfcbe7e81ce8
b2aefc6b3117a5b2f4008daadead4159b1e21e36
fix(ast): SH-92 void 跳 `$x` 在 `$` 处拒绝（v0.76.1）
$ git merge-base --is-ancestor 247ade5b HEAD && echo baseline_is_ancestor=yes
baseline_is_ancestor=yes
```

红提交只改 `test/ast/p76_chain.sh`（+13 行，void 负例），是 fix 的父提交。
在 `247ade5b`（v0.76.0）的归档副本上，用它 `ct-ast v0.76.0` 复跑新脚本：

```console
$ sh test/ast/p76_chain.sh /tmp/rev-ph76-work/ct-ast; echo $?
FAIL p76/chain: void-returning hop accepted
1
```

（T-7 字面要求 baseline 为 test 提交的父提交；这里 baseline `247ade5b` 是 test 提交父提交
`6d51276e` 的父，二者行为等价——`6d51276e` 只含首轮 verdict 文档。已按 T-7 的意图在
v0.76.0 归档上复现红，记录为不阻断观察。）

### 10.2 从 v0.76.1 归档自举并跑探针

同一 L0→L1→L2→ct-ast 自举链（命令同 §1，源码取 `git archive v0.76.1`，零警告）：

```console
$ /tmp/rev-ph76-1-work/ct-ast --version
ct-ast v0.76.1
$ cd /tmp/rev-ph76-1 && sh test/ast/p76_chain.sh /tmp/rev-ph76-1-work/ct-ast; echo EXIT=$?
OK p76/chain (tail, multi-hop, type/const/non-call/argument negatives)
EXIT=0
```

新脚本含 void 负例；OK 覆盖原五组 + void。

### 10.3 手工 void 复核

```console
$ /tmp/rev-ph76-1-work/ct-ast check --types void.ct; echo rc=$?
void.ct:4:47: error: '$' needs a non-void result; this hop has none (v0-PH-76)
ctc: 1 error(s) generated
rc=1
$ /tmp/rev-ph76-1-work/ct-ast check void.ct; echo rc=$?
void.ct:4:47: error: '$' needs a non-void result; this hop has none (v0-PH-76)
ctc: 1 error(s) generated
rc=1
$ /tmp/rev-ph76-1-work/ct-ast build -o void.bin void.ct; echo rc=$?
void.ct:4:47: error: '$' needs a non-void result; this hop has none (v0-PH-76)
ctc: 1 error(s) generated
rc=1
```

`check`、`check --types`、`build` 三条路径都在 `$` 处硬错，不再产出把 void 赋给 int 的 C。
修复点在 [`Expr.h.ct:4366-4377`](../../selfhost/ct-ast/frontend/parse/Expr.h.ct)：`static_ctype`
返回 0 或空类型时显式拒绝（void 与不可解析调用），不再以「类型未知」跳过。

### 10.4 回归与其它判据

- 接口接收者 `iface.m()$x`（运行得 7）、指针接收者 `p->m()$x`（运行得 9）、多跳带实参
  `s.m()$x.n(2)$y`（运行得 0）均 rc=0；类型不符仍报
  `'$' target: expected 'int', got 'struct B'`——原正例/负例未被新检查误伤。
- 五处 `CTC_VERSION` 均为 `0.76.1`；tag `v0.76.1` 的本地对象 `9b579c33…`、peeled
  `d16d6ffa…` 与 `git ls-remote origin 'refs/tags/v0.76.1*'` 两行逐字一致；G8 绿
  （`g8: OK (PN-2 version coherence; 9 legacy offsets)`）。
- `issues/selfhost/sh92-void-dollar-materialize.md` 的 `status` 已按 5.4 由 REV 改为
  `verified`，复核证据见该条。

### 10.5 非阻断观察（补正后）

1. tutorial §13 的标题/状态块仍是「规划……未实现」旧文案（[tutorial.md:1780](../tutorial.md)），
   与 §13.4 的「v0.76.0 起可用」矛盾；SH-92 未触及，建议另立文档 fix。
2. `d16d6ffa` 同时落库了 `battle/static-dispatch-1/**`（另一会话的在途材料），超出 SH-92
   的修复范围；G8 绿，但「一提交一事」的账可在下次提交时留意。

### 10.6 结论

首轮阻断项已消除：void 跳在 `$` 处三路硬错，p76_chain（含 void 负例）绿，红证可复现，
版本/tag/G8 一致，SH-92 已 `verified`。

**`REV: 通过`**
