# PH-79 收口复核（REV）

- 复核对象：`v0.79.1`（`effbf6f7`，annotated tag，peeled `effbf6f7`）——PH-79 S3 切片 `T[]` + SH-98 修复。
- 基线：`v0.79.0`（`dda27c19`），用于复现 SH-98 红。
- 环境：macOS arm64；`Apple clang version 21.0.0 (clang-2100.4.1.1)`；`CC=cc`；python3。
- 方法：`git archive v0.79.0|v0.79.1 | tar -x -C /tmp/...`，分别按项目自举链独立重建
  L0→L1→L2→ct-ast；所有探针只用归档构建出的二进制；未改任何实现代码。
- 结论：**不通过（打回）**。SH-98 的 fix 本身通过并置 `verified`；PH-79 的 E79-2/E79-3 有可复现
  的验收缺口，卡面任务/红证声明也与仓库不符。

```text
REV: 打回
```

本轮不是“只复跑夹具变绿”：`p79_basic` 15/15 确实绿，但它没有覆盖卡面 §2.1 声称的
`a[1..]`，也没有覆盖 E79-3 的“借用”；最小反例分别命中“数组基座开区间子切片发射非法 C”、
“数组→切片只在局部声明转换”、“切片元素不能作 ref/out 实参”。这些不是边界简化，卡面
§1.1 的“本卡首轮不覆盖”也没有把它们列进去。

## 0 阻断项

| # | 判据 | 结论 | 证据 |
| --- | --- | --- | --- |
| B1 | E79-2 子切片半开区间 | `a[1..]`（数组基座、省略上界）发射缺右括号的 C；`ct check` 0、`ct build` 1 | §2.1；[SH-99](../../issues/selfhost/sh99-p79-array-open-subslice.md) |
| B2 | E79-2 数组→切片自动补 len | 只有局部声明转换；`sum(a)` 与 `return a;` 都发射非法 C，`ct check` 仍 0 | §2.2；[SH-100](../../issues/selfhost/sh100-p79-array-to-slice-conversion.md) |
| B3 | E79-3 `s[i]` 读/写/借用 | 读/写可用；“借用”`bump(s[1])` 被拒 `ref/out argument must be an assignable place` | §2.3；[SH-101](../../issues/selfhost/sh101-p79-slice-element-borrow.md) |
| B4 | G1/G5/T-7/PN-10 证据 | 卡面 `p79_index`/`p79_places`/`p79_migrate`/`p79_docs` 全不存在；无 `baseline`、无红证原始输出；实现提交又往测试里加 7 个未跑红的用例 | §6；[TEST-24](../../issues/testing/test24-phase79-evidence-gaps.md) |

## 1 自举与夹具

### 1.1 构建

```console
$ rm -rf /tmp/rev-ph79 && mkdir -p /tmp/rev-ph79
$ git archive v0.79.1 | tar -x -C /tmp/rev-ph79
$ cd /tmp/rev-ph79
$ cc -Wall -Wextra -std=c99 selfhost/l0/ctc.c -o ctc
$ ./ctc selfhost/l1/ctc.ct -o l1.c
$ cc -Wall -Wextra -std=c99 l1.c -o l1
$ ./l1 build selfhost/l2/driver.ct -o l2src
$ cc -Wall -Wextra -std=c99 l2src/*.c -o l2
$ ./l2 build -I selfhost/ct-ast selfhost/ct-ast/main.ct -o astsrc
$ cc -Wall -Wextra -std=c99 astsrc/*.c -o ct-ast
BUILD_OK
l0.log/l1a.log/l1b.log/l2b.log/astb.log: 0 行（零警告）
$ ./ct-ast -v
ct-ast v0.79.1
```

### 1.2 `test/ast/p79_*.sh`（全部）

```console
$ ls test/ast/p79_*.sh
test/ast/p79_basic.sh
$ sh test/ast/p79_basic.sh ./ct-ast; echo EXIT=$?
ok   E79-2/3: array->slice, write, subslice, foreach, get, const read, struct element
ok   E79-4: const T[] write is a hard error
ok   E79-3: s[i] out of range traps at run time
ok   E79-5: slice as a struct field is a hard error
ok   E79-5: slice as a global is a hard error
ok   E79-5: slice as a generic argument is a hard error
ok   E79-1: T a[] parameter warns
ok   E79-1: T a[] = {...} stays an inferred-length array
ok   E79-5: slice as a container element is a hard error
ok   E79-5: slice in Option is a hard error
ok   E79-5: slice in Result is a hard error
ok   E79-5: slice as an array element is a hard error
ok   E79-5: slice as an interface value is a hard error
ok   E79-5: a closure cannot capture a slice
ok   E79-6: returning a view of a local array lints
EXIT=0
```

注意：15/15 的 `basic` 用的是 `int[] t = s[1..]`（slice 基座），不是卡面 §2.1 写的 `a[1..]`；
它也没有 `Vec.as_slice`、`box` 与 ref/out 借用。绿夹具不能推出 E79-2/E79-3 全绿。

### 1.3 SH-96/98（`p78_method.sh`）

```console
$ sh test/ast/p78_method.sh ./ct-ast; echo EXIT=$?
ok   E78-6 trait method ref/out (dispatch, run)
ok   E78-6 vtable slot, definition, body and call site
ok   E78-6 generic trait impl ref/out (run)
ok   E78-6 trait default body ref/out (run)
ok   E78-6 inherent method ref/out (run)
ok   E78-6 generic inherent method ref/out (run)
ok   E78-6 static inherent method ref/out (run)
ok   SH-96 method self passed to ref without & (run)
ok   SH-98 method self receiver is not addressed
ok   E78-6 method out must be assigned on every path
ok   E78-6 method actual must be a place
ok   E78-6 method actual base type is checked
ok   E78-6 impl annotation must match the trait
ok   E78-6 default body obeys out L1
p78_method: OK
EXIT=0
```

SH-98 基线的红见 §4。

## 2 缺口复现

探针目录 `/tmp/rev-ph79-probes`，全部用 `v0.79.1` 归档构建的 `ct-ast`；`ct-ast check` 与
`ct-ast build` 分别执行。

### 2.1 B1：`a[1..]` 数组基座开区间子切片

```ct
int main(void)
{
    int a[] = { 1, 2, 3 };
    int[] t = a[1..];
    return t[0] - 2;
}
```

```console
$ /tmp/rev-ph79/ct-ast check a1open.ct; echo check=$?
check=0
$ /tmp/rev-ph79/ct-ast build a1open.ct -o a1open.bin; echo build=$?
'cc' -std=c99 -I '.ctbuild' '.ctbuild/a1open.c' '-o' 'a1open.bin'
a1open.ct:36:95: warning: cast to smaller integer type 'int' from 'char *' [-Wpointer-to-int-cast]
a1open.ct:36:156: error: expected ')'
build=1
```

生成的 C：

```c
struct __ct_slice t = __ct_slice_range((void *)(a),
    (int)(sizeof(a) / sizeof((a)[0])), 1,
    (int)(sizeof(a) / sizeof((a)[0]), sizeof(int), "a1open.ct:4");
```

`(int)(` 缺一个右括号。`selfhost/ct-ast/backend/emit/Emitter.h.ct:5212` 写的是
`fputs(")[0])", ...)`，同函数显式上界分支（`:5196`）写的是 `)[0]))`。slice 基座
`s[1..]` 走 `).len` 分支，所以 `p79_basic` 的 `s[1..]` 绿而 `a[1..]` 红。
`a[lo..hi]` 与 `s[lo..]` 正常。

### 2.2 B2：数组→切片的实参/返回值

```ct
int sum(int[] s) { return s[0]; }
int main(void)
{
    int a[] = { 7 };
    return sum(a) - 7;
}
```

```console
$ /tmp/rev-ph79/ct-ast check arr_arg.ct; echo check=$?
check=0
$ /tmp/rev-ph79/ct-ast build arr_arg.ct -o arr_arg.bin; echo build=$?
'cc' -std=c99 -I '.ctbuild' '.ctbuild/arr_arg.c' '-o' 'arr_arg.bin'
arr_arg.ct:40:17: error: passing 'int[1]' to parameter of incompatible type 'struct __ct_slice'
build=1
```

```ct
int[] f(void)
{
    int a[] = { 1, 2 };
    return a;
}
```

```console
$ /tmp/rev-ph79/ct-ast check arr_ret.ct; echo check=$?
check=0
$ /tmp/rev-ph79/ct-ast build arr_ret.ct -o arr_ret.bin; echo build=$?
arr_ret.ct:37:12: error: returning 'int[2]' from a function with incompatible result type 'struct __ct_slice'
build=1
```

局部声明 `int[] s = a;` 是唯一做了转换的路径（`Stmt.h.ct:4120-4137` 的
`(struct __ct_slice){ (void *)(a), (int)(sizeof(a)/sizeof((a)[0])) }`）；实参/返回值没有同样的
coercion，`ct check` 也不报错。`int[] s = a; sum(s);` 可用，说明底层表示没问题，缺的是调用点/返回点。

### 2.3 B3：`s[i]` 作 ref/out 实参

```ct
void bump(ref int x) { x = x + 1; }
int main(void)
{
    int a[] = { 1, 2 };
    int[] s = a;
    bump(s[1]);
    return (a[1] == 3) ? 0 : 1;
}
```

```console
$ /tmp/rev-ph79/ct-ast check borrow_elem.ct; echo check=$?
borrow_elem.ct:6:1: error: ref/out argument must be an assignable place
check=1
$ /tmp/rev-ph79/ct-ast build borrow_elem.ct -o borrow_elem.bin; echo build=$?
borrow_elem.ct:6:1: error: ref/out argument must be an assignable place
build=1
```

`bump(s[0].x)` 同样被拒；对照 `bump(a[1])`（C 数组元素）可以，`&s[1]` 也可以。
`selfhost/ct-ast/frontend/parse/Expr.h.ct:1257-1297` 的 `ref_arg_place()` 没有
`N_SLICE_INDEX` 分支，slice index 落到末尾 `return 0`。spec §4.69 与 E79-3 都写明
`s[i]` 是 place、“读、写、借用都作用于底层元素”。

## 3 E79-1…E79-6 逐条结论

| ID | 结论 | 依据 |
| --- | --- | --- |
| E79-1 | 通过（带观察） | `T[]` 局部/形参/返回可用；`T a[] = {...}` 静默为推断长度数组；`T a[]` 形参/字段/无初始化器声明告警；`ct check` 把告警升 error。观察：无初始化器局部 `int xs[];` 告警后生成的 C 仍被 cc 拒绝（§7）。 |
| E79-2 | **打回** | 表示 `{ptr,len}`、空视图、数组→切片的局部声明、`a[lo..hi]`/`s[lo..]` 绿；但 `a[1..]` 发射非法 C（B1），`sum(a)`/`return a` 缺转换（B2）。 |
| E79-3 | **打回** | `s[i]` 读/写、trap（`ct: slice index 5 out of bounds` + exit 1）、`get` 越界 0、`const` 写硬错均绿；`bump(s[1])`/`bump(s[0].x)` 被拒（B3）。 |
| E79-4 | 通过（带观察） | `const int[]` 局部与 `const int[]` 形参的元素写都在 CT 层硬错；C 数组 `a[5]` 保持 C 下标、不 trap。观察：可探知越界只由 cc 的 `-Warray-bounds` 提示，`ct-ast` 自身不报（§7）。 |
| E79-5 | 基本通过，覆盖有缺口 | 字段/全局/接口/box/Option/Result/Vec/数组元素/泛型实参/闭包捕获十类行为均硬错（box 与 Map 用独立探针确认）；`p79_basic` 只测了九类，未测 box。观察：函数内 `static int[] s;` 被接受（§7）。 |
| E79-6 | 部分通过 | 直接 `return s;`（局部数组的 slice 视图）触发 `slice escape` lint；`check-ast` 1526/0/4、`check-sanitizers` 581/0、`check-goldens`、`check-warnings`、L0 均绿。但 `return a;`（直接数组）落到 B2，连 lint 都到不了；全量 `check-all` 未整跑，关键段已自跑。 |

## 4 SH-98 复核

独立用 `git archive v0.79.0` 构建基线（`ct-ast v0.79.0`），把 `v0.79.1` 的
`test/ast/p78_method.sh` 放到基线里跑：

```console
$ sh test/ast/p78_method.sh ./ct-ast; echo exit=$?
FAIL p78/method: SH-98 method self receiver is not addressed
  static __attribute__((unused)) void S_bump(struct S *self, struct S * s) {
exit=1
$ grep -n 'S_bump(&_self' .ctbuild/self_ref.c
19:    S_bump(&_self, _self);
$ cc -std=c99 -Wall -Wextra -Werror .ctbuild/self_ref.c -o x
error: incompatible pointer types passing 'struct S **' to parameter of type 'struct S *'
```

v0.79.1：

```console
$ sh test/ast/p78_method.sh ./ct-ast; echo exit=$?
ok   SH-98 method self receiver is not addressed
p78_method: OK
exit=0
$ grep -n 'S_bump(_self, _self)' .ctbuild/self_ref.c
19:    S_bump(_self, _self);
$ cc -std=c99 -Wall -Wextra -Werror .ctbuild/self_ref.c -o x; echo cc=$?
cc=0
$ ./self_ref.bin; echo run=$?
run=0
$ ct-ast build self_ref.ct -o self_ref.bin; echo build=$?
build=0（无警告；日志只有 cc 命令行）
```

结论：`v0.79.0` 的 receiver 是 `&_self`（`struct S **`）→ gcc/clang 告警；`v0.79.1` 发 `_self`
（`struct S *`），与 ref 实参一致，`ct build` 零警告、运行 exit 0。不是压掉告警，receiver 语义正确。
SH-98 置 `verified`。

> 范围说明：fix 覆盖 inherent/泛型 mcall 的 `self` receiver。trait vtable 路径的
> `self.bump(...)` 仍发 `_self.__t_vptr->bump(&_self, ...)`（且对指针用 `.`，本身是非法 C）；
> 那是 PH-78 遗留的 trait 自调用 codegen 路径，不是 SH-98 的复现/fix 范围，未据此打回 SH-98，
> 记在 §7。

## 5 版本 / tag / 门禁

```console
$ grep -c 'CTC_VERSION "0.79.1"' selfhost/l0/ctc.c selfhost/l1/ctc.ct \
    selfhost/l2/core.ct selfhost/l2/driver.ct selfhost/ct-ast/main.ct
selfhost/l0/ctc.c:1
selfhost/l1/ctc.ct:1
selfhost/l2/core.ct:1
selfhost/l2/driver.ct:1
selfhost/ct-ast/main.ct:1

$ git cat-file -t v0.79.1
tag
$ git rev-parse 'v0.79.1^{commit}'
effbf6f7f568fd1cba30f7a995f9e8361f4dc17c
$ git ls-remote origin 'refs/tags/v0.79.1*'
bba580fb3499140926f9eed9948c36c77f3fd1da  refs/tags/v0.79.1
effbf6f7f568fd1cba30f7a995f9e8361f4dc17c  refs/tags/v0.79.1^{}
$ git branch -r --contains effbf6f7
  origin/HEAD -> origin/main
  origin/main
```

门禁（`tools/check.sh g0/g8` 在仓内跑；其余在 `/tmp/rev-ph79` 归档内跑）：

```console
$ sh tools/check.sh g0
g0: OK (block 1.17.0, session-map present)
$ sh tools/check.sh g8
g8: OK (PN-2 version coherence; 9 legacy offsets)
$ python3 test/docs/check-docs.py
check-docs: OK (2078 relative links in 345 files, v0.79.1, 11 hard gates, ... 5 signoff(s))
$ sh selfhost/check-goldens.sh
check-goldens: OK (no regression, and the self-hosted rebuild agrees)
$ sh selfhost/check-ast.sh
== summary: 1526 passed, 0 failed, 4 skipped ==
  ok    PH-79-S3 slices (E79-1…5 T[], place, get, const, migration)
$ sh selfhost/check-sanitizers.sh
check-sanitizers: OK (581 checks, no sanitizer report)
$ CT_C_BOUNDARY=allow sh selfhost/check-warnings.sh
check-warnings: 493 ok, 0 failed
$ sh test/run.sh
== summary: 156 passed, 0 failed ==
```

说明：`check-ast` 的 4 skipped 是环境跳过（`baremetal_renode` 等），卡面写的 1 failed/3 skipped
是另一环境的口径；本机没有失败。全量 `check-all.sh` 没有整跑，上列是它的关键段（1、2、8、9、11
加 sanitizer）；这不影响 §0 的代码缺口结论。

## 6 卡面 / 证据核对（B4）

卡面 `docs/design/phase79.md:67-73` 写了五个验收脚本，仓库只有 `p79_basic`：

```console
$ ls test/ast/p79_*.sh
test/ast/p79_basic.sh
$ for f in p79_basic p79_index p79_places p79_migrate p79_docs; do
    [ -f test/ast/$f.sh ] && echo "present $f" || echo "MISSING $f"
  done
present p79_basic
MISSING p79_index
MISSING p79_places
MISSING p79_migrate
MISSING p79_docs
```

卡面 §2.1 还说 `p79_basic` 断言 `a[1..]` 与 `Vec.as_slice`；实际夹具用的是 `s[1..]`，也没有
`Vec.as_slice`（§1.1 已延期）。卡面 §5 只列 `p79_basic` 的 15 条绿输出。

红证也不存在：

```console
$ git show 255016e0 --format='%B' --no-patch
test(ct-ast): p79 S3 红
$ git show 255016e0:test/ast/p79_basic.sh | grep -c baseline
0
$ ls test/ast/p79_red* 2>/dev/null || echo "no p79 red log"
no p79 red log
```

`255016e0` 正文没有 `baseline:`、命令、原始输出、退出码；实现提交 `dda27c19` 又往
`p79_basic.sh` 加了 `container`/`option`/`result`/`arrelem`/`iface`/`closure`/`ret` 七个用例，
这些用例从未在实现前跑红。卡面 §2 要求“每项任务先提 `test(...) 红`（含 `baseline: <sha>`）”，
PN-10 要求每个 stage 独立红/绿；实际只有一个红提交且无红证。卡面“S3a–S3e 已落”“实现红证
VERIFY 见 §5”与仓库证据不符。

另有一处文档漂移（不阻断）：`AGENTS.md:452` 的实例化行仍写 `phase=PH-78`，而当前版本已是
`v0.79.1`、PH-79 已收口；G0 只校验该行存在，不校验值。

## 7 不阻断观察

1. **`T a[]` 无初始化器局部**：`int xs[];` 先给 deprecation warning，随后 cc 报
   `definition of variable with array type needs an explicit size or an initializer`。E79-1 只要求
   “告警”，但用户实际拿到的是 warning + build 失败。建议在 CT 层直接硬错或给零长度数组语义。
2. **`static int[] s;` 被接受**：提案 §2.1 的禁用列表含“静态”，spec §4.69 的禁用列表没有；
   实现两者都没有检查。当前生成 `static struct __ct_slice s;`（零初始化），没有立即危险，但白名单
   口子应补上或在 spec 明确允许。
3. **`int[] s;` 未初始化为 `{0,0}`**：生成 `struct __ct_slice s;`，依赖栈内容；`len` 恰为 0 时
   `get` 返回 0，但不保证。spec 写“空 `{0,0}`”，没有显式构造语法（p72 证据也承认）。
4. **C 数组可探知越界只在 build 的 cc 阶段报警**：`int a[2]; a[5]` 的 `ct-ast build` 日志有
   clang `-Warray-bounds`，`ct-ast` 编译模式不报。E79-4 的“报警”若要求 CT 诊断，这一条未做到。
5. **`const` 剥离**：`const int[] ro = a; int[] rw = ro; rw[0] = 9;` 可编译并写。spec 只要求
   `const T[]` 直接写硬错，未规定 const→non-const 的视图转换；建议明确。
6. **`pick(s)[0]`**：对 slice-returning call 的结果直接下标报
   `type '__ct_slice' has no subscript`。卡面 §1.1 只排除了 `f().get(i)`/`s.field[i]`；这是
   相邻边界，建议写进 spec 或在 check 阶段给更准确诊断。
7. **box/Map 夹具缺口**：`box<int[]>` 与 `Map<int,int[]>` 的行为已用独立探针确认硬错，但
   `p79_basic` 没有 box；`Map` 只通过“泛型实参”间接覆盖。属 TEST-24 的覆盖清单。
8. **trait 自调用 codegen**：`impl T for S { void go(void){ self.bump(self); } }` 生成
   `_self.__t_vptr->bump(&_self, _self)`，对 `_self`（`S *`）用 `.`，且 receiver 仍取址；
   与 §4 的 inherent 路径不同。这是 PH-78 遗留路径，不在 SH-98 范围，但会挡住 trait 内的
   `self` 方法调用，建议另立条目。

## 8 处置

- SH-98：[`issues/selfhost/sh98-self-method-receiver-address.md`](../../issues/selfhost/sh98-self-method-receiver-address.md)
  置 `verified`（§4）。
- 新建并置 `open`（仓内没有可 `reopened` 的既有 PH-79 issue；按 5.4 由 REV 立案并附失败复现）：
  - [`SH-99`](../../issues/selfhost/sh99-p79-array-open-subslice.md) B1（E79-2）；
  - [`SH-100`](../../issues/selfhost/sh100-p79-array-to-slice-conversion.md) B2（E79-2）；
  - [`SH-101`](../../issues/selfhost/sh101-p79-slice-element-borrow.md) B3（E79-3）；
  - [`TEST-24`](../../issues/testing/test24-phase79-evidence-gaps.md) B4（证据/任务声明）。
- 复评门槛：B1–B3 各有独立红证并用 `v0.79.1+fix` 转绿；`p79_basic` 增加 `a[1..]`、
  `sum(a)`/`return a`、`bump(s[1])` 的断言（或更正卡面声明）；B4 的脚本/红证按 T-7 补齐。
- 本轮未改实现代码、未 push、未打 tag。

## 9 附：原始日志位置（一次性，可丢弃）

- `/tmp/rev-ph79/check-ast-rev.log`（1526/0/4）
- `/tmp/rev-ph79/check-san-rev.log`（581/0）
- `/tmp/rev-ph79/check-warnings-rev2.log`（493/0）
- `/tmp/rev-ph79/check-goldens-rev.log`
- `/tmp/rev-ph79-probes/*.check.log`、`*.build.log`（B1–B3）
- `/tmp/rev-ph79-base/`（v0.79.0 基线，SH-98 红）
