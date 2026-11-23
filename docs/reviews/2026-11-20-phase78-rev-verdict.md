# v0-PH-78 收口复核（REV）

- 首轮复核：`v0.78.0`（annotated tag `7f621315`，peeled `1d466c0a960abd8272e179f8bcceb469ae9ff13b`）；原结论 `REV: 打回`，完整记录保留在 §0.1。
- 本轮复核：`v0.78.1`（`c75e55df`，SH-95/96/97 修复；annotated tag `360788acc`，peeled `c75e55df`）。
- 基线：`07693e47`（`v0.77.2`，v0-PH-78 源码改动之前）。
- 环境：macOS arm64；`Apple clang version 21.0.0 (clang-2100.4.1.1)`；`CC=cc`。
- 方法：`git archive v0.78.1 | tar -x -C /tmp/rev-ph78-1`，按项目自举链独立重建 L0→L1→L2→ct-ast；所有本轮探针只使用该归档构建出的二进制。
- 结论：**通过**。三条原打回项已在 v0.78.1 修复并独立复现；原打回记录原样保留，修复证据见 §0.2、§2.1、§4.1。

```text
REV: 通过
```

本轮不是“只看探针变绿”：§0.2 逐条复跑了原 B1/B2/B3 的最小反例；`p78_basic` / `p78_method` / `p78_docs` 新增的 SH-95/96/97 断言也独立复跑。原打回记录（v0.78.0）保留在 §0.1，便于追溯。

## 0.1 原打回记录（v0.78.0，保留）

首轮只看四条 p78 探针会得到“通过”，但下列最小反例分别命中“调用点非 place 未硬错”“bit-field/const 不是可写 place”“方法 `self` 实参发射 `&_self`”。这些是卡内 E78-3 与 R78-5 的直接判据；本节的 v0.78.0 原始输出不删改。

原结论（v0.78.0）：`REV: 打回`。

### B1（最高，v0.78.1 已修，见 §0.2）`ref S` 的实参 `self` 发射成 `&_self`，构建成功但运行结果错

`Emitter.h.ct:4931` 的 `emit_ref_arg()` 对任何非 Vec 实参无条件写 `&`；而方法里的 `self` 在源码语义中已经是 `S *`（p78 自己的方法体都用 `self->v`），`Emitter.h.ct:4999-5000` 把 `self` 发射为 `_self`。两者叠加得到 `&_self`（`S **`），而不是 `_self`（`S *`）。

```console
$ cd /tmp/rev-ph78-repro
$ /tmp/rev-ph78-build/ct-ast check self_ref.ct; echo check=$?
check=0
$ /tmp/rev-ph78-build/ct-ast build self_ref.ct -o self_ref.bin; echo build=$?
build=0
self_ref.ct:15:12: warning: incompatible pointer types passing 'struct S **' to parameter of type 'struct S *'; remove & [-Wincompatible-pointer-types]
   15 |     S_bump(&_self, &_self);
      |            ^~~~~~
self_ref.ct:7:54: note: passing argument to parameter 'self' here
    7 | static __attribute__((unused)) void S_bump(struct S *self, struct S * s) {
$ ./self_ref.bin; echo run=$?
run=1
```

（`self_ref.ct`：`impl S { void bump(ref S s) { s.v = 1; } void go(void) { self.bump(self); } }`；期望 `run=0`。）`ct build` 只给 C 警告，不失败；`ct check` 退出 0；用户看到的是静默错误。此路径属于 E78-6“方法/trait 同一规则”和 E78-2“调用点 `&`”。

### B2（高，v0.78.1 已修，见 §0.2）调用点 place 检查只看节点种类，`f().x` / bit-field / `const` 变量均被接受

`Expr.h.ct:1134-1163` 的 `ref_arg_place()` 对 `N_MEMBER` / `N_ARROW` 只检查 Vec/Map 下标糖，对 `N_INDEX` 直接返回 1；不检查成员基址是否可寻址，也不识别 bit-field 与 `const` 限定。结果：`ct check` 接受，`ct build` 在 C 层报错（或运行崩溃）。

```console
$ /tmp/rev-ph78-build/ct-ast check member_rvalue.ct; echo check=$?
check=0
$ /tmp/rev-ph78-build/ct-ast build member_rvalue.ct -o member_rvalue.bin; echo build=$?
build=1
member_rvalue.ct:17:9: error: cannot take the address of an rvalue of type 'int'
   17 |     inc(&mk().x);
```

```console
$ /tmp/rev-ph78-build/ct-ast check bitfield_ref.ct; echo check=$?
check=0
$ /tmp/rev-ph78-build/ct-ast build bitfield_ref.ct -o bitfield_ref.bin; echo build=$?
build=1
bitfield_ref.ct:13:9: error: address of bit-field requested
   13 |     inc(&s.x);
```

```console
$ /tmp/rev-ph78-build/ct-ast check const_ref.ct; echo check=$?
check=0
$ /tmp/rev-ph78-build/ct-ast build const_ref.ct -o const_ref.bin; echo build=$?
build=0
const_ref.ct:8:9: warning: passing 'const int *' to parameter of type 'int *' discards qualifiers [-Wincompatible-pointer-types-discards-qualifiers]
$ ./const_ref.bin; echo run=$?
Bus error: 10
run=138
```

（`member_rvalue.ct`：`inc(mk().x)`；`bitfield_ref.ct`：`struct S { int x : 3; }; inc(s.x);`；`const_ref.ct`：`const int g = 1; inc(g);`。）这三条分别是“调用结果/字段基址不可寻址”“字段不可取址”“变量不是常量”的 E78-3 白名单边界；其中 `const` 一条不是 C 编译错误而是运行 Bus error，风险更高。R78-5 写明缓解是“E78-3 硬错在 CT 层”，此处未做到。

### B3（中，v0.78.1 已修，见 §0.2）E78-6 的 `spec/package-guide 同步` 未落地

卡 E78-6 明确要求“spec/package-guide 同步”，但实现提交只改了 `docs/language-spec.md` 与 `docs/tutorial.md`：

```console
$ git show --stat --oneline f65b1cc4 -- docs
 docs/language-spec.md | 52 ++++++++++++++++++++++++++++++
 docs/tutorial.md      | 69 +++++++++++++++++++++++++++++++++++++++++++++++++--
 2 files changed, 119 insertions(+), 2 deletions(-)
```

`docs/package-guide.md` 无 `ref`/`out` 字样；`p78_docs.sh` 只断言 spec §4.68 与 tutorial §15，不检查 package-guide。包作者从 §5“C ABI 静态库”读不到 `pub int f(ref int)` 的 ABI 形态（虽然发射的是普通指针，但“同步”判据未满足）。此项可单独修，不改变 B1/B2 的性质。

## 0.2 v0.78.1 修复复核（最终）

修复提交：SH-95 [`488d99b3`]（closeout `c75e55df` 另补泛型实例 bit-field 标记）、SH-96 [`a9063e34`]、SH-97 [`5736f0d5`]；红证提交 `4bcbe5a3`（父提交，baseline `ca3354a5`），日志 `test/ast/p78_red_rev.log`。三条 issue 已由 REV 置 `verified`。

从 `v0.78.1` clean 归档重建（`ct-ast v0.78.1`，零构建警告）后，复跑原 B1/B2/B3 的最小反例：

### B2 → SH-95（place 递归到基址/bit-field/const）

```console
$ /tmp/rev-ph78-1-build/ct-ast check member_rvalue.ct; echo check=$?
member_rvalue.ct:4:1: error: ref/out argument must be an assignable place
check=1
$ /tmp/rev-ph78-1-build/ct-ast check bitfield_ref.ct; echo check=$?
bitfield_ref.ct:3:1: error: ref/out argument must be an assignable place
check=1
$ /tmp/rev-ph78-1-build/ct-ast check const_ref.ct; echo check=$?
const_ref.ct:3:1: error: ref/out argument must be an assignable place
check=1
```

`ct build` 同样在 CT 层退出 1（不再落到 cc）。`p78_basic` 新增三条断言均绿：

```console
ok   SH-95 call-result member rejected
ok   SH-95 bit-field member rejected
ok   SH-95 const variable rejected
```

代码上 `ref_arg_place()` 现在递归检查基址，`N_MEMBER`/`N_ARROW` 查 bit-field 与顶层 `const`，`N_INDEX`/`N_DEREF` 递归基址；`Symbols.h.ct` 的 `Field.is_bitfield` 记录字段属性。

### B1 → SH-96（`self` 作 ref 实参不取址）

```console
$ /tmp/rev-ph78-1-build/ct-ast check self_ref.ct; echo check=$?
check=0
$ /tmp/rev-ph78-1-build/ct-ast build self_ref.ct -o self_ref.v781.bin; echo build=$?
build=0
$ ./self_ref.v781.bin; echo run=$?
run=0
$ grep -n 'S_bump(&_self' .ctbuild/self_ref.c
19:    S_bump(&_self, _self);
```

`p78_method` 新增 `ok SH-96 method self passed to ref without & (run)`。注意第一实参（receiver）仍是 `&_self`，cc 仍给一条 `struct S **` 不兼容警告；这是首轮已记录的 pre-existing self-call receiver 问题，SH-96 只修第二实参，运行断言通过（不阻断本轮，见 §7.1）。

### B3 → SH-97（package-guide）

```console
$ grep -n 'ref.*out' docs/package-guide.md | head
207:- `ref` / `out` 形参在 C ABI 里就是普通指针：`pub int bump(ref int x)` 发射为
$ CC=cc sh test/ast/p78_docs.sh; echo exit=$?
ok   package-guide documents ref/out at the C ABI boundary
p78_docs: OK
exit=0
```

`p78_docs.sh:53-57` 新增 package-guide 断言；package-guide §5 写明 ABI 头是普通 `T *`、C 消费者传 `&value`、`out` 的初始化/定值只在 CT 源层检查。

**§0.2 结论**：原 B1/B2/B3 三条均已在 v0.78.1 修复；`ct check` 对 `inc(mk().x)`、bit-field、`const int g` 全部硬错，`self.bump(self)` 发射 `S_bump(&_self, _self)` 且 run 0，package-guide/p78_docs 覆盖。

## 1 首轮（v0.78.0）自举构建与四条探针

```console
$ git archive v0.78.0 | tar -x -C /tmp/rev-ph78
$ cc -Wall -Wextra -std=c99 selfhost/l0/ctc.c -o /tmp/rev-ph78-build/ctc
$ /tmp/rev-ph78-build/ctc selfhost/l1/ctc.ct -o /tmp/rev-ph78-build/l1.c
$ cc -Wall -Wextra -std=c99 /tmp/rev-ph78-build/l1.c -o /tmp/rev-ph78-build/l1
$ /tmp/rev-ph78-build/l1 build selfhost/l2/driver.ct -o /tmp/rev-ph78-build/l2src
$ cc -Wall -Wextra -std=c99 /tmp/rev-ph78-build/l2src/*.c -o /tmp/rev-ph78-build/l2
$ /tmp/rev-ph78-build/l2 build -I selfhost/ct-ast selfhost/ct-ast/main.ct -o /tmp/rev-ph78-build/astsrc
$ cc -Wall -Wextra -std=c99 /tmp/rev-ph78-build/astsrc/*.c -o /tmp/rev-ph78-build/ct-ast
BUILD_OK
ct-ast v0.78.0
```

四条探针原始结论：

```console
$ CC=cc sh test/ast/p78_basic.sh  /tmp/rev-ph78-build/ct-ast; echo exit=$?
ok   E78-1 contextual keyword (int out; time_t *ref; parameter named out)
ok   E78-2 ref/out free function (run)
ok   E78-2 signature T *, body (*name), call &
ok   E78-2 hand-written pointer C behaves the same
ok   E78-2 ABI header spells T *
ok   E78-3 places: variable/field/*p/array/Vec/Map element
ok   E78-3 literal rejected
ok   E78-3 expression rejected
ok   E78-3 call result rejected
ok   E78-3 cast rejected
ok   E78-4 trivial out actual may be uninitialised
ok   E78-4 owning out actual initialised
ok   E78-4 owning actual initialised by assignment
ok   E78-4 owning actual uninitialised rejected
ok   E78-4 non-owning pointer actual may be uninitialised
ok   E78-5 if/else assigns on both paths
ok   E78-5 assignment before return
ok   E78-5 one if path leaves out unset
ok   E78-5 early return before assignment
ok   E78-5 loop is conservative
ok   E78-5 switch is conservative
ok   E78-5 goto is conservative
ok   E78-5 ct check uses the same rule
p78_basic: OK
exit=0
```

```console
$ CC=cc sh test/ast/p78_method.sh /tmp/rev-ph78-build/ct-ast; echo exit=$?
ok   E78-6 trait method ref/out (dispatch, run)
ok   E78-6 vtable slot, definition, body and call site
ok   E78-6 generic trait impl ref/out (run)
ok   E78-6 trait default body ref/out (run)
ok   E78-6 inherent method ref/out (run)
ok   E78-6 generic inherent method ref/out (run)
ok   E78-6 static inherent method ref/out (run)
ok   E78-6 method out must be assigned on every path
ok   E78-6 method actual must be a place
ok   E78-6 method actual base type is checked
ok   E78-6 impl annotation must match the trait
ok   E78-6 default body obeys out L1
p78_method: OK
exit=0
```

```console
$ CC=cc sh test/ast/p78_types.sh /tmp/rev-ph78-build/ct-ast; echo exit=$?
[... 9 条 ok ...]
p78_types: OK
exit=0
$ CC=cc sh test/ast/p78_docs.sh; echo exit=$?
[... 8 条 ok ...]
p78_docs: OK
exit=0
```

## 2 E78-1…E78-6 逐条结论

### 2.0 v0.78.0 原逐条（保留）

| ID | 结论 | 依据 |
| --- | --- | --- |
| E78-1 | 通过 | `int out;`、`time_t *ref;`、`void f(int out)` 合法；`p78_basic` E78-1 绿。注解只在形参表第一 token 生效（`Parser.h.ct:2110-2125`、`3155-3165`）。 |
| E78-2 | **打回** | 普通函数的 `T *` / `(*name)` / `&place`、ABI 头、手写指针等价均绿；但方法内 `self` 实参发射 `&_self`（B1），同一判据不成立。 |
| E78-3 | **打回** | 变量/字段/`*p`/数组/Vec/Map 元素与四个直接负例绿；但 `f().x`、bit-field、`const` 变量被 `ct check` 接受（B2），分别导致 C 错误或 Bus error。 |
| E78-4 | 基本通过，需澄清 | 直接变量 trivial/owning/非 owning 指针五条探针绿；`check_refout_arg` 的 owning 判定只对 `N_VAR` 且 `initialized` 是“曾经赋值”的单调标志（`Expr.h.ct:1201-1215`；`Stmt.h.ct:3954/3996/4256/4401`），条件分支里只赋值一次也会被当作已初始化（见 §7）。 |
| E78-5 | 通过（保守边界内） | if/else、return/末尾、循环/switch/goto、`ct build`/`ct check`/`--types` 均按卡实现；但“先读后写”未检查，for-init/do-while 等保守拒绝见 §7。 |
| E78-6 | **打回** | trait/impl/默认体/固有/泛型/静态固有共 12 条绿；但方法 `self` 的 ref/out 实参错误（B1），且 package-guide 未同步（B3）。 |

### 2.1 v0.78.1 最终逐条（本轮结论）

| ID | 最终结论 | v0.78.1 依据 |
| --- | --- | --- |
| E78-1 | 通过 | 首轮 E78-1 绿；v0.78.1 未改上下文关键字路径，p78_basic E78-1 仍绿。 |
| E78-2 | 通过 | 普通函数 `T *`/`(*name)`/`&place`/ABI 头/手写指针等价仍绿；SH-96 后 `self` 作 ref 实参发射 `S_bump(&_self, _self)`，run 0（p78_method SH-96 绿）。receiver `&_self` 的 pre-existing 警告不属本项。 |
| E78-3 | 通过 | 首轮 4 条直接负例仍绿；SH-95 后 `inc(mk().x)`、bit-field、`const int g` 均在 `ct check`/`ct build` 硬错；数组/Vec/Map 元素仍合法。 |
| E78-4 | 通过（原语义） | 五条探针仍绿；owning 初始化仍是“直接变量 + 曾经赋值”的 L1 边界（§7.1），本轮未改变，也未把它冒充成 flow-sensitive。 |
| E78-5 | 通过 | if/else/return/循环/switch/goto、`ct build`/`ct check`/`--types` 均按卡；原 §7 的过度拒绝与先读后写仍是非阻断边界。 |
| E78-6 | 通过 | trait/impl/默认体/固有/泛型/静态固有全绿；SH-96 self 断言绿；SH-97 package-guide + p78_docs 绿。 |

## 3 首轮（v0.78.0）红证复现

提交拓扑：`4a3b8b5d` 是 `f65b1cc4` 的**父**（`git merge-base --is-ancestor` 为真），但 `4a3b8b5d^ = cec61c22` 不是 baseline `07693e47`；`07693e47` 是 `cec61c22` 的祖先，且两者版本同为 0.77.2。

```console
$ git rev-parse 4a3b8b5d^
cec61c227f98bd0f3c9d67bff56a7ad6c606f9fb
$ git merge-base --is-ancestor 4a3b8b5d f65b1cc4 && echo yes
yes
$ git merge-base --is-ancestor 07693e47 HEAD && echo yes
yes
$ git show 07693e47:selfhost/l0/ctc.c | grep -m1 CTC_VERSION
#define CTC_VERSION "0.77.2"
```

用 `git archive 07693e47` 重建基线 ct-ast（L0→L1→L2→ct-ast，`ct-ast v0.77.2`）后复跑：

```console
$ cd /tmp/rev-ph78 && CC=cc sh test/ast/p78_basic.sh /tmp/rev-ph78-base-build/ct-ast; echo exit=$?
FAIL p78/basic: E78-2 ref/out free function (run)
prog.ct:5:10: error: unknown type name 'ref'
...
p78_basic: 1 failed
exit=1
$ CC=cc sh test/ast/p78_method.sh /tmp/rev-ph78-base-build/ct-ast; echo exit=$?
FAIL p78/method: E78-6 trait method ref/out (dispatch, run)
methods.ct:3:26: error: unknown type name 'ref'
...
exit=1
```

红证可复现。注意：T-7 字面要求 baseline 是 test 提交的**父**提交；此处 `4a3b8b5d^ = cec61c22`（仅 docs/phases/v0-PH-78/card.md 开卡，源码与 07693e47 相同），所以行为上等价，但字面判据未满足。另 `4a3b8b5d` 的路径集合含 `docs/phases/v0-PH-78/card.md` 与 `selfhost/check-ast.sh`，不纯是“只含测试/夹具/红证”。

## 4 首轮（v0.78.0）版本、tag 与门禁

```console
$ git cat-file -t v0.78.0
tag
$ git rev-parse v0.78.0
7f621315939d1efb0a46fbcc126ee0d60079cbcb
$ git rev-parse v0.78.0^{}
1d466c0a960abd8272e179f8bcceb469ae9ff13b
$ git ls-remote origin 'refs/tags/v0.78.0' 'refs/tags/v0.78.0^{}'
7f621315939d1efb0a46fbcc126ee0d60079cbcb	refs/tags/v0.78.0
1d466c0a960abd8272e179f8bcceb469ae9ff13b	refs/tags/v0.78.0^{}
$ git branch -r --contains 1d466c0a | head
  origin/HEAD -> origin/main
  origin/main
```

五处版本一致：

```console
$ grep -h 'define CTC_VERSION "0.78.0"' \
    selfhost/l0/ctc.c selfhost/l1/ctc.ct selfhost/l2/core.ct \
    selfhost/l2/driver.ct selfhost/ct-ast/main.ct | wc -l
5
```

```console
$ bash tools/check.sh g0
g0: OK (block 1.17.0, session-map present)
$ bash tools/check.sh g8
g8: OK (PN-2 version coherence; 0 legacy offsets)
$ python3 test/docs/check-docs.py
check-docs: OK (2047 relative links in 341 files, v0.78.0, 11 hard gates, 12 phase status, ...)
$ bash selfhost/check-ast.sh
== summary: 1525 passed, 0 failed, 4 skipped ==   （exit 0）
$ bash selfhost/check-sanitizers.sh
check-sanitizers: OK (581 checks, no sanitizer report)
```

ASan/UBSan 覆盖既有语料，但没有覆盖 §0 的新反例（p78 探针不在其 fixture 循环内；§0 的 fixture 也不在 p78 探针内）。全量 `check-all.sh` 已启动但未在本次复核窗口内跑完；AST 段、sanitizer、G0/G8、check-docs、check-warnings、check-semantics 均为独立复跑绿。`check-ast` 汇总为 1525 passed / 4 skipped，与卡上 1524 / 5 的差异是主机/跳过项差异，不影响结论。v0.78.1 的本轮版本/tag/门禁见 §4.1。

### 4.1 v0.78.1 复核（最终）

```console
$ git cat-file -t v0.78.1
tag
$ git rev-parse v0.78.1
360788acc0c8e9f0dcb9d27c2f1857295cb5ceef
$ git rev-parse v0.78.1^{}
c75e55dfc8e17923b94a9842c8397ea16cfbc8d4
$ git ls-remote origin 'refs/tags/v0.78.1' 'refs/tags/v0.78.1^{}'
360788acc0c8e9f0dcb9d27c2f1857295cb5ceef	refs/tags/v0.78.1
c75e55dfc8e17923b94a9842c8397ea16cfbc8d4	refs/tags/v0.78.1^{}
$ git branch -r --contains c75e55df | head
  origin/HEAD -> origin/main
  origin/main
```

五处 `CTC_VERSION` 均为 `0.78.1`：

```console
$ grep -h 'define CTC_VERSION "0.78.1"' \
    selfhost/l0/ctc.c selfhost/l1/ctc.ct selfhost/l2/core.ct \
    selfhost/l2/driver.ct selfhost/ct-ast/main.ct | wc -l
5
```

```console
$ bash tools/check.sh g0
g0: OK (block 1.17.0, session-map present)
$ bash tools/check.sh g8
g8: OK (PN-2 version coherence; 0 legacy offsets)
$ python3 test/docs/check-docs.py
check-docs: OK (2049 relative links in 342 files, v0.78.1, 11 hard gates, 12 phase status, ...)
$ CC=cc sh test/ast/p78_basic.sh  /tmp/rev-ph78-1-build/ct-ast   # p78_basic: OK, exit 0
$ CC=cc sh test/ast/p78_method.sh /tmp/rev-ph78-1-build/ct-ast   # p78_method: OK, exit 0
$ CC=cc sh test/ast/p78_types.sh  /tmp/rev-ph78-1-build/ct-ast   # p78_types: OK, exit 0
$ CC=cc sh test/ast/p78_docs.sh                                  # p78_docs: OK, exit 0
```

`check-ast` 与 `check-sanitizers` 的本轮独立结果：

```console
$ bash selfhost/check-ast.sh
...
ok    v0-PH-78-S2a basic (E78-1…5 ref/out free functions)
ok    v0-PH-78-S2b method (E78-6 methods/trait/default/inherent)
ok    v0-PH-78-S2c types (base-type negatives, shapes, semantics)
ok    v0-PH-78-S2c docs (spec + tutorial)
== summary: 1525 passed, 0 failed, 4 skipped ==   （exit 0）
$ bash selfhost/check-sanitizers.sh
...
check-sanitizers: OK (581 checks, no sanitizer report)   （exit 0）
```

全量 `selfhost/check-all.sh` 未在本轮窗口内重跑；AST 段、sanitizer、G0/G8、check-docs 与四条 p78 探针均为上述独立结果。DEV 日志声称的全量 11/11 未逐门复核。

## 5 代码审查：根因与 v0.78.1 修复位置

以下前三条是 v0.78.0 的根因记录；v0.78.1 已按下述提交修复，并在 §0.2 独立复现。

- `Emitter.h.ct:4931-4954`：v0.78.0 的 `emit_ref_arg()` 只区分 Vec 下标糖，其余一律 `fputs("&")`；没有 `self` 分支。v0.78.1 在 `Emitter.h.ct:4944-4949` 对 `self_mode` 下的 `self` 直接 `emit_expr`，SH-96。
- `Expr.h.ct:1134-1163`：v0.78.0 的 `ref_arg_place()` 对 `N_MEMBER` / `N_ARROW` 只做 Vec/Map 糖检查，`N_INDEX` 直接 1；v0.78.1 改为递归基址，并查 `Field.is_bitfield` 与顶层 `const`（SH-95，`488d99b3` + `c75e55df`）。
- `Expr.h.ct:1141-1142`：v0.78.0 的 `N_VAR` 只拒绝 `vars[vi].is_const`（enum）；v0.78.1 增加 `ref_type_is_const_value()`，拒绝顶层 `const` 值、保留 `const int *`（SH-95）。
- `Expr.h.ct:1201-1215`：`out` owning 初始化仍只处理 `N_VAR`，且用单调 `initialized`；这与卡 §6 的“只检查直接变量”一致，但“条件分支只赋值一次”未被计入诚实清单（见 §7.1）。
- `Parser.h.ct:1968-1982` / `2018-2045`：`out` 的 if/else 与循环/switch/goto 保守模型本身没有发现“漏接受”；§7 列出的是过度拒绝。

## 6 诚实性清单核对

| DEV 声明 | 与代码/卡一致？ |
| --- | --- |
| `Map` 元素的 place 拼写是 `*m[k]`，裸 `m[k]` 拒绝 | 是；`p78_basic` places 覆盖 `inc(*m["a"])`，`ref_arg_place` 对 Map 糖返回 0。 |
| 无切片 fixture | 是；p78 四个脚本无 slice fixture，卡 §6 明写。 |
| `out` owning 仅检查直接变量，字段/元素按已初始化 | 是；`check_refout_arg` 只在 `N_VAR` 上做 owning 检查。 |
| L1 不建模短路/`into`/跨过程；循环/switch 保守 | 是；`out_scan` 不下降一般表达式、无 `N_INTO`，循环/switch 重置 mask。 |
| 泛型自由函数的 ref/out 未验收 | 是；无 fixture；卡只声明自由函数/trait/impl/固有/泛型 impl/静态固有。 |
| S2a–S2c 共用一个红提交 | 是；`4a3b8b5d` 同时含四个 p78 脚本与红证。 |
| E78-6 spec/package-guide 同步 | **是（v0.78.1）**；package-guide §5:207-209 + `p78_docs.sh:53-57`，SH-97。 |
| `out` 只在退出路径检查，未声明“先读后写” | **未声明**；`f(out int y) { int z = y; y = 1; return z; }` 被接受（见 §7.1）。 |
| 调用点 place 白名单含“字段” | **v0.78.1 已修**；递归基址 + bit-field/const（SH-95）；`f().x`、bit-field、`const int g` 现均硬错。 |
| SH-95/96/97 处置与状态 | **verified**；修复 `488d99b3` / `a9063e34` / `5736f0d5`，红证 `4bcbe5a3`，v0.78.1 独立复现见 §0.2。 |

## 7 不阻断观察

1. **`out` owning 初始化是“曾经赋值”而非“必然已初始化”**：`R r; if (argc > 1) { r = g; } set(r);` 被接受（`ct check`/`build` 均 0）。若设计意图是“必须已有值”，这是一条漏路径；若意图是语法上的“后续赋值即可”，应在卡/规范里写明是 flow-insensitive。
2. **`out` 形参可先读后写**：`f(out int y) { int z = y; y = 1; return z; }` 被接受；调用方可以传未初始化的 trivial 实参，运行时读未初始化。E78-5 只承诺“退出路径赋值”，但这是 out 语义的安全缺口，建议至少文档化或后续 L2 补。
3. **for-init / do-while 的保守过强**：`for (y = 0; ...)` 的初始化一定执行，但 `out_scan` 在循环后把 mask 重置为进入值，仍报未赋值；`do { y = 1; } while (0);` 同理。卡只说“循环体内的赋值不证明循环后有值”，for-init 不是体内，建议收窄措辞或实现。

```console
$ /tmp/rev-ph78-1-build/ct-ast build for_init.ct -o for_init.bin; echo build=$?
for_init.ct:4:1: error: out parameter 'y' is not assigned on every path
build=1
$ /tmp/rev-ph78-1-build/ct-ast build do_while.ct -o do_while.bin; echo build=$?
do_while.ct:4:1: error: out parameter 'y' is not assigned on every path
build=1
```
4. **条件内赋值只识别直接 `N_ASSIGN`**：`if ((y = c))` 通过，`if ((y = c) != 0)` 被拒绝；规范写“条件里的赋值也算”，实际是“条件节点本身是赋值才算”。
5. **测试覆盖已补（v0.78.1）**：新增 `self`、`f().x`、bit-field、`const int g`、package-guide 的负例；仍缺 `const` 指针/pointee、for-init/do-while、先读后写等（见 §7.1）。
6. **T-7 形式**：v0.78.1 的三条 fix 另有红证 `4bcbe5a3`（父提交，baseline `ca3354a5`）；首轮 `4a3b8b5d` 的 baseline 是祖先而非父（`cec61c22` 为 docs-only 开卡），字面 T-7 仍不完美。
7. **tag 指向**：`v0.78.0` peel 到 `1d466c0a`（battle 判决 docs 提交），版本 bump/卡收口在父提交 `6a63e1e4`；`v0.78.1` peel 到 `c75e55df`（版本 bump/收口提交）。按用户定义 `1d466c0a` 是 v0.78.0 收口提交则成立；按 V-7 严格读法可再确认。
8. **pre-existing（非 v0-PH-78 引入）**：trait default body / inherent method 的 `self.a(...)` 发射 `_self.__t_vptr` / `S_a(&_self, ...)` receiver 错误，在 baseline、v0.78.0、v0.78.1 上都存在；静态固有方法的语句式调用 `S.mark(n);` 也被误判为声明。它们不是本卡新增，但会被 p78 的“方法/trait 同一规则”暴露，建议另立 issue。
9. **E78-1 边界**：形参第一 token 的 `ref`/`out` 按设计总是注解，因此一个名为 `ref`/`out` 的 typedef 不能作形参类型；与“上下文关键字”一致，不阻断。

### 7.1 v0.78.1 复核新增/残余（不阻断本轮三项验收）

1. **`const` 指向对象的 `*p` / `pp->x` 仍可绕过**（同类、非本轮三项）：`const int *p; inc(*p)` 与 `const struct P *pp; inc(pp->x)` 仍被 `ct check` 接受，`ct build` 仅给 const 丢弃警告，运行 Bus error 138。SH-95 的验收点是“顶层 const 变量/字段”，`N_DEREF` 的 pointee const 未覆盖；建议另立 SH-98，而不是把它算作本轮三项未修。

```console
$ /tmp/rev-ph78-1-build/ct-ast check const_deref.ct; echo check=$?
check=0
$ /tmp/rev-ph78-1-build/ct-ast build const_deref.ct -o const_deref.bin; echo build=$?
const_deref.ct:9:9: warning: passing 'const int *' to parameter of type 'int *' discards qualifiers
build=0
$ ./const_deref.bin; echo run=$?
Bus error: 10
run=138
```
2. **`self` 作 receiver 的 `&_self` 仍在**：SH-96 只修第二实参（ref/out 实参），`self.bump(self)` 的第一个 receiver 仍发 `&_self`，cc 有一条不兼容指针警告；当前 fixture 的 `bump` 不用 `self`，所以 run 0。若方法体使用 `self->v`，仍是 pre-existing 错误；建议另立 issue。
3. **原 §7 的 out 边界仍在**：owning 初始化为“曾经赋值”、`out` 先读后写、for-init/do-while 过度保守、条件内嵌套赋值不识别；这些是 v0-PH-78 的 L1 边界/文档问题，不因 v0.78.1 改变。

## 8 复核边界

- 未修改代码、未 push、未改 phase 卡；只落 verdict 与 SH-95/96/97 状态。
- 本轮从 `v0.78.1` clean 归档重建；已独立跑四条 p78 探针、AST 段、sanitizer、G0/G8、check-docs。未独立跑全量 `selfhost/check-all.sh`，11 道门的 DEV 日志未逐门复核。
- ASan 只覆盖既有 fixture 与 `test/ast/*`；p78 的 shell 探针不在其循环内，SH-95/96/97 的针对性探针是本轮单独复跑。
- 本报告按 2026-11-20 新版 `AGENTS.md` 0.7 的席位签收口径，`签收: 待 EDITOR`（REV 不自签）。
