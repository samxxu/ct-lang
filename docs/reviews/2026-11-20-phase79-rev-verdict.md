# PH-79 收口复核（REV）

- 首轮复核：`v0.79.1`（`effbf6f7`，annotated tag）——原结论 `REV: 打回`（B1–B4）；原记录保留在 §7。
- 本轮复核：`v0.79.2`（`13dcb594`，annotated tag `06117fe1`，peeled `13dcb594`）——SH-99/100/101、
  TEST-24 修复 + SH-98 不回归。
- 红证基线：`2a2f3933`（v0.79.1 首轮打回对象）；SH-98 基线：`v0.79.0`（`dda27c19`）。
- 环境：macOS arm64；`Apple clang version 21.0.0 (clang-2100.4.1.1)`；`CC=cc`；python3。
- 方法：`git archive v0.79.2 | tar -x -C /tmp/rev-ph79v2`，按项目自举链独立重建
  L0→L1→L2→ct-ast；五个 `p79_*` 脚本与全部最小反例只用该归档构建出的二进制；未改实现代码。
- 结论：**通过**。首轮四条打回项均已独立复现为绿；SH-98 的 fix 在 v0.79.2 不回归；版本、tag、
  五处 `CTC_VERSION`、G8 与关键门禁均一致。剩余事项见 §6（卡面已登记边界，或为不阻断观察）。

```text
REV: 通过
```

本轮不是“只复跑绿夹具”：§2 用首轮同一组最小反例逐条复现，§2.4 核对 T-7 红证的提交拓扑与
逐字输出；§3 再把 E79-1…E79-6 逐项对回实现与夹具。首轮打回记录未删除，见 §7。

## 0 复核摘要

| 首轮项 | v0.79.2 结论 | 独立证据 |
| --- | --- | --- |
| B1 `a[1..]` 数组基座开区间子切片 | 已修 | `ct check` 0、`ct build` 0；生成 `__ct_slice_range(..., 1, len, ...)`；`t[0]=2`、`t[1]=3`、`t[2]` trap（length 2） |
| B2 数组→切片实参/返回值 | 已修 | `sum(a)`、`sum(o.xs)`、`return g_arr`、`return a`（局部，带 lint）全部 `ct check`/`build`/`run` 正确；生成 `{ptr,len}` compound literal |
| B3 `s[i]` 作 `ref`/`out` 实参 | 已修 | `bump(s[1])`、`bump(s[1].f)` run 0；`bump(s[2])` trap；`const int[]` 仍拒写/拒借用 |
| B4 任务脚本与红证 | 已修 | 五个 `p79_*` 脚本存在；24/10/17/7/15 全绿；红提交 `f9294448` 父提交 `2a2f3933`，`p79_red_rev.log` 144 行逐字红证 |
| SH-98 receiver 语义 | 不回归 | `p78_method.sh` 14/14，`SH-98 method self receiver is not addressed` 绿 |
| 版本 / tag / G8 | 一致 | 五处 `CTC_VERSION=0.79.2`；tag annotated、peeled `13dcb594`、远端一致；`g8: OK` |

## 1 自举与夹具

### 1.1 构建

```console
$ rm -rf /tmp/rev-ph79v2 && mkdir -p /tmp/rev-ph79v2
$ git archive v0.79.2 | tar -x -C /tmp/rev-ph79v2
$ cd /tmp/rev-ph79v2
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
ct-ast v0.79.2
```

### 1.2 五个 `p79_*` 脚本（全部存在并独立跑绿）

```console
$ ls test/ast/p79_*.sh
test/ast/p79_basic.sh
test/ast/p79_docs.sh
test/ast/p79_index.sh
test/ast/p79_migrate.sh
test/ast/p79_places.sh
$ for f in p79_basic p79_index p79_places p79_migrate p79_docs; do
    printf '%s: ' $f; sh test/ast/$f.sh ./ct-ast 2>&1 | grep -c '^ok'; done
p79_basic: 24
p79_index: 10
p79_places: 17
p79_migrate: 7
p79_docs: 15
```

五者均 exit 0。关键新增断言：

```console
ok   E79-2/SH-99: array-base open subslice a[1..] is half-open and valid C
ok   E79-2: array-base bounded subslice a[1..3] stays half-open
ok   E79-2/SH-100: an array actual fills a T[] parameter
ok   E79-2/SH-100: an array return fills a T[] result
ok   E79-6/SH-100: a converted local-array return lints
ok   E79-2/SH-100: a struct's array field fills a T[] parameter
ok   E79-3/SH-101: a slice element is a ref/out actual
ok   E79-3/SH-101: a slice element's member is a ref/out actual
ok   E79-3/SH-101: a borrow keeps the bounds trap
```

`p79_index` / `p79_places` / `p79_migrate` / `p79_docs` 分别覆盖 E79-3/4、E79-5/6、E79-1、S3e；
`selfhost/check-ast.sh` 已接入 `PH-79-S3`/`S3b`/`S3c`/`S3d`/`S3e` 五项，全量运行五项均 `ok`。

### 1.3 `p78_method.sh`（SH-96/98 不回归）

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

## 2 首轮打回项逐条复现（v0.79.2）

探针目录 `/tmp/rev-ph79v2-probes`；全部用 §1.1 自举出的 `ct-ast`。

### 2.1 B1 → SH-99：`a[1..]` 合法 C 且半开

```ct
int main(void)
{
    int a[] = { 1, 2, 3 };
    int[] t = a[1..];
    if (t[0] != 2 || t[1] != 3) return 1;
    return t[2];   /* len must be 2: this traps */
}
```

```console
$ /tmp/rev-ph79v2/ct-ast check a1open.ct; echo check=$?
check=0
$ /tmp/rev-ph79v2/ct-ast build a1open.ct -o a1open.bin; echo build=$?
build=0
$ ./a1open.bin; echo run=$?
ct: slice index 2 out of bounds (length 2)
run=1
```

生成的 C 已是合法半开区间：

```c
struct __ct_slice t = __ct_slice_range((void *)(a),
    (int)(sizeof(a) / sizeof((a)[0])), 1,
    (int)(sizeof(a) / sizeof((a)[0])), sizeof(int), "a1open.ct:4");
```

`t[0]=2`、`t[1]=3` 通过；`t[2]` trap 且报 `length 2`，证明 `[1,len)` 的右端排除。
`a[1..3]` 由 `p79_basic` 的 `a1range` 同样覆盖。

### 2.2 B2 → SH-100：数组→切片实参/返回值

```ct
int sum(int[] s) { return s[0] + s[1]; }
int main(void)
{
    int a[] = { 3, 4 };
    return sum(a) - 7;
}
```

```console
$ /tmp/rev-ph79v2/ct-ast check arr_arg.ct; echo check=$?
check=0
$ /tmp/rev-ph79v2/ct-ast build arr_arg.ct -o arr_arg.bin; echo build=$?
build=0
$ ./arr_arg.bin; echo run=$?
run=0
```

结构体数组字段与全局数组返回值：

```console
$ /tmp/rev-ph79v2/ct-ast build arr_field_arg.ct -o arr_field_arg.bin && ./arr_field_arg.bin; echo field_run=$?
field_run=0
$ /tmp/rev-ph79v2/ct-ast build arr_ret_global.ct -o arr_ret_global.bin && ./arr_ret_global.bin; echo ret_global_run=$?
ret_global_run=0
```

生成 C 与局部声明同一 `{ptr,len}` 形式：

```c
return (sum((struct __ct_slice){ (void *)(a), (int)(sizeof(a) / sizeof((a)[0])) }) - 7);
...
return (struct __ct_slice){ (void *)(g), (int)(sizeof(g) / sizeof((g)[0])) };
```

直接返回局部数组先转换、再触发 lint：

```console
$ /tmp/rev-ph79v2/ct-ast check arr_ret_local.ct; echo check=$?
arr_ret_local.ct:4:12: error: slice escape: 'return' hands back a view of a local array
check=1
$ /tmp/rev-ph79v2/ct-ast build arr_ret_local.ct -o arr_ret_local.bin; echo build=$?
arr_ret_local.ct:4:12: warning: slice escape: 'return' hands back a view of a local array
build=0
```

### 2.3 B3 → SH-101：`s[i]` 作 ref/out 实参

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
$ /tmp/rev-ph79v2/ct-ast check borrow_elem.ct; echo check=$?
check=0
$ /tmp/rev-ph79v2/ct-ast build borrow_elem.ct -o borrow_elem.bin; echo build=$?
build=0
$ ./borrow_elem.bin; echo run=$?
run=0
$ /tmp/rev-ph79v2/ct-ast build borrow_member.ct -o borrow_member.bin && ./borrow_member.bin; echo member_run=$?
member_run=0
```

生成 C 保留 `__ct_slice_at` 的边界检查：

```c
bump(&(*(int *)__ct_slice_at(&(s), 1, sizeof(int))));
```

越界仍 trap，`const T[]` 仍只读：

```console
$ /tmp/rev-ph79v2/ct-ast build borrow_trap.ct -o borrow_trap.bin && ./borrow_trap.bin; echo run=$?
ct: slice index 2 out of bounds (length 1)
run=1
$ /tmp/rev-ph79v2/ct-ast check const_borrow.ct
const_borrow.ct:6:1: error: ref/out argument must be an assignable place
$ /tmp/rev-ph79v2/ct-ast check const_write.ct
const_write.ct:5:7: error: cannot write to an element of a const slice
```

### 2.4 B4 → TEST-24：脚本与红证

```console
$ git rev-parse f9294448^
2a2f3933
$ git merge-base --is-ancestor 2a2f3933 HEAD && echo baseline-ancestor=yes
baseline-ancestor=yes
$ wc -l test/ast/p79_red_rev.log
144 test/ast/p79_red_rev.log
```

`f9294448` 是 `13dcb594` 的父提交（`2a2f3933` 是 `f9294448` 的父提交），红证正文含
`baseline: 2a2f3933`、命令、退出码，逐字输出在 `test/ast/p79_red_rev.log`：四个脚本在基线缺失，
`p79_basic` 九条新断言全红；实现提交随后转绿。`p79_basic` 由 15 条增至 24 条，新增断言没有
再混进实现提交。

## 3 E79-1…E79-6 逐条结论

| ID | 结论 | 依据 |
| --- | --- | --- |
| E79-1 | 通过 | `p79_migrate` 7/7：`T a[]` 形参/字段/无初始化器告警；`T a[] = {...}` 与 `T a[N]` 静默；`ct check` 把无初始化器告警升 error；`T[]` 形参/返回静默。 |
| E79-2 | 通过 | `p79_basic` 的 `a[1..]`/`a[1..3]`、`sum(a)`、`sum(o.xs)`、`return g_arr`、`return a` 全绿；生成 `{ptr,len}`；子切片 `[lo,hi)`；§2.1/2.2 独立复现。 |
| E79-3 | 通过 | `p79_index` 10/10：读写底层、元素类型、参数下标、上/下/runtime trap、`get` 软访问、`const` 借用拒绝；`bump(s[1])`/`bump(s[1].f)` 通过且越界 trap（§2.3）。 |
| E79-4 | 通过 | `const int[]` 元素写与借用都在 CT 层硬错；C 数组 `a[5]` 保持 C 下标、不 trap（build 有 cc `-Warray-bounds` 提示，见 §6）。 |
| E79-5 | 通过 | `p79_places` 17/17：参数/局部/临时/返回允许；字段/全局/接口/`box`/`Option`/`Result`/`Vec`/`Map`/数组元素/泛型实参/闭包捕获全红。 |
| E79-6 | 通过 | `p79_places` 的 `ret_slice`/`ret_sub`/`ret_array` 触发 `slice escape`；全局/静态数组视图不 lint；`check-ast` 1529/0/5（本机，PH-77-S5 外部索引超时跳过）、`check-sanitizers` 581/0（见 §5）。 |

## 4 SH-98 不回归

`v0.79.1` 已独立复现：基线 `v0.79.0` 发 `S_bump(&_self, _self)`，cc 报
`incompatible pointer types passing 'struct S **'`；`v0.79.1` 发 `S_bump(_self, _self)`，
`cc -Werror` 通过、运行 exit 0。v0.79.2 重新自举后 `p78_method` 仍全绿（§1.3），没有再改动
receiver 语义；SH-98 保持 `verified`。

## 5 版本 / tag / 门禁

```console
$ grep -c 'CTC_VERSION "0.79.2"' selfhost/l0/ctc.c selfhost/l1/ctc.ct \
    selfhost/l2/core.ct selfhost/l2/driver.ct selfhost/ct-ast/main.ct
selfhost/l0/ctc.c:1
selfhost/l1/ctc.ct:1
selfhost/l2/core.ct:1
selfhost/l2/driver.ct:1
selfhost/ct-ast/main.ct:1

$ git cat-file -t v0.79.2
tag
$ git rev-parse 'v0.79.2^{commit}'
13dcb5948339ce1864ffea7ade184ae5fd3dc8c6
$ git for-each-ref refs/tags/v0.79.2 --format='%(objecttype) %(objectname) %(*objectname) %(subject)'
tag 06117fe1ab774a0b087221930e10f1147a234d50 13dcb5948339ce1864ffea7ade184ae5fd3dc8c6 SH-99/100/101 + TEST-24 fix (13dcb59)
$ git ls-remote origin refs/heads/main 'refs/tags/v0.79.2*'
13dcb5948339ce1864ffea7ade184ae5fd3dc8c6  refs/heads/main
06117fe1ab774a0b087221930e10f1147a234d50  refs/tags/v0.79.2
13dcb5948339ce1864ffea7ade184ae5fd3dc8c6  refs/tags/v0.79.2^{}
```

门禁（`tools/check.sh g0/g8` 在仓内跑；其余在 `/tmp/rev-ph79v2` 归档内跑）：

```console
$ sh tools/check.sh g0
g0: OK (block 1.17.0, session-map present)
$ sh tools/check.sh g8
g8: OK (PN-2 version coherence; 9 legacy offsets)
$ python3 test/docs/check-docs.py
check-docs: OK (2079 relative links in 346 files, v0.79.2, 11 hard gates, ... 5 signoff(s))
$ CT_C_BOUNDARY=allow sh selfhost/check-goldens.sh
check-goldens: OK (no regression, and the self-hosted rebuild agrees)
$ CT_C_BOUNDARY=allow sh selfhost/check-warnings.sh
check-warnings: 493 ok, 0 failed
$ sh test/run.sh
== summary: 156 passed, 0 failed ==
$ CT_C_BOUNDARY=allow sh selfhost/check-semantics.sh
check-semantics: OK (23 assertions)
$ sh selfhost/check-ast.sh
== summary: 1529 passed, 0 failed, 5 skipped ==
  ok    PH-79-S3 slices (E79-1…5 T[], place, get, const, migration)
  ok    PH-79-S3b index (E79-3/4 checked place, trap, get, const)
  ok    PH-79-S3c places (E79-5 whitelist, E79-6 escape lint)
  ok    PH-79-S3d migrate (E79-1 T a[] warnings, inferred array)
  ok    PH-79-S3e docs (spec 4.69 + package-guide 7.6)
$ sh selfhost/check-sanitizers.sh
check-sanitizers: OK (581 checks, no sanitizer report)
```

说明：5 skipped 是环境跳过（`baremetal_renode` 与 PH-67-R2/R3/R5 需要 Linux Renode；
PH-77-S5 外部索引因网络超时跳过）。全量 `check-all.sh` 未整跑，上列覆盖其
1、2、8、9、11 与 sanitizer 关键段；`g0`/`g8` 另在仓内跑。各段均 exit 0。

## 6 边界、诚实性与不阻断观察

v0.79.2 的 phase 卡新增 §6“未完成 / 简化 / 边界（诚实清单）”，把首轮未写明的限制登记为 B-1…B-8，
包括 `Vec.as_slice`、`s.field[i]`/`f().get(i)`/`f()[i]`、`int[] s; s = a;`、多维数组、
`T a[]` 形参、`static int[]`、无初始化器 `int xs[]`、inherent/static 方法实参与切片元素值接收者方法。
这些均为“未覆盖”的明示，不再冒充 E79 已覆盖；本轮未发现新的隐藏简化。

不阻断观察（不改变 `REV: 通过`）：

1. **inherent/static 方法实参的数组→切片未扩**（卡 §6 B-7）：`self.sum(a)` 仍由 cc 报
   `incompatible type 'struct __ct_slice'`；自由函数、trait 方法与返回值已覆盖。这是已登记边界，
   不是本轮声称修复的 SH-100 主路径。
2. **`static int[] s;` 被接受**（卡 §6 B-5）：生成零初始化 `{0,0}` 的静态视图；spec §4.69 的
   位置列表没有“静态”，提案 §2.1 则把静态列入禁用。当前按卡面“spec 未列、维持现状并记录”处理。
3. **无初始化器 `int xs[];`**（卡 §6 B-6）：`ct check` 升 error，`ct build` 仍先告警、再落到 cc 的
   `needs an explicit size`。E79-1 只要求告警，未要求 build 成功。
4. **`int[] s;` 未零初始化**：生成 `struct __ct_slice s;`，`{0,0}` 依赖栈；`a[0..0]`/`a[1..1]`
   的空视图正常。spec 的“空 `{0,0}`”没有显式构造语法（p72 证据同）。
5. **`const` 剥离**：`const int[] ro = a; int[] rw = ro; rw[0] = 9;` 可编译；spec 只要求
   `const T[]` 直接写硬错，未规定 const→non-const 视图转换。
6. **C 数组可探知越界只由 cc 报警**：`int a[2]; a[5]` 的 `ct-ast build` 日志有 clang
   `-Warray-bounds`，`ct-ast` 编译模式不报；E79-4 的“报警”在 build 路径可见。
7. **phase 卡 §5 的计数已过期**：还写 `check-ast 1526 passed, 1 failed, 3 skipped` 与
   `check-docs … v0.79.0`；v0.79.2 本轮实测为 `1529/0/5`、`v0.79.2`（0 failed；多出的 skip 是网络/环境）。这是卡片文档漂移，非 E79 行为缺口。

## 7 原打回记录（v0.79.1 `effbf6f7`，保留）

首轮结论：`REV: 打回`。以下命令与输出为首轮原文，未改。

### 7.1 B1 `a[1..]` 发射非法 C

```console
$ /tmp/rev-ph79/ct-ast check a1open.ct; echo check=$?
check=0
$ /tmp/rev-ph79/ct-ast build a1open.ct -o a1open.bin; echo build=$?
'cc' -std=c99 -I '.ctbuild' '.ctbuild/a1open.c' '-o' 'a1open.bin'
a1open.ct:36:95: warning: cast to smaller integer type 'int' from 'char *' [-Wpointer-to-int-cast]
a1open.ct:36:156: error: expected ')'
build=1
```

```c
struct __ct_slice t = __ct_slice_range((void *)(a),
    (int)(sizeof(a) / sizeof((a)[0])), 1,
    (int)(sizeof(a) / sizeof((a)[0]), sizeof(int), "a1open.ct:4");
```

`(int)(` 缺右括号；`Emitter.h.ct:5212` 的 `fputs(")[0])", ...)` 与 `:5196` 的 `)[0]))` 不一致。

### 7.2 B2 数组→切片的实参/返回值

```console
$ /tmp/rev-ph79/ct-ast check arr_arg.ct; echo check=$?
check=0
$ /tmp/rev-ph79/ct-ast build arr_arg.ct -o arr_arg.bin; echo build=$?
arr_arg.ct:40:17: error: passing 'int[1]' to parameter of incompatible type 'struct __ct_slice'
build=1
$ /tmp/rev-ph79/ct-ast check arr_ret.ct; echo check=$?
check=0
$ /tmp/rev-ph79/ct-ast build arr_ret.ct -o arr_ret.bin; echo build=$?
arr_ret.ct:37:12: error: returning 'int[2]' from a function with incompatible result type 'struct __ct_slice'
build=1
```

局部声明 `int[] s = a;` 是唯一转换路径；实参/返回值没有 coercion，`ct check` 也不报错。

### 7.3 B3 `s[i]` 作 ref/out 实参被拒

```console
$ /tmp/rev-ph79/ct-ast check borrow_elem.ct; echo check=$?
borrow_elem.ct:6:1: error: ref/out argument must be an assignable place
check=1
$ /tmp/rev-ph79/ct-ast check borrow_member.ct; echo check=$?
borrow_member.ct:7:1: error: ref/out argument must be an assignable place
check=1
```

`ref_arg_place()` 没有 `N_SLICE_INDEX` 分支；`bump(a[1])`（C 数组）与 `&s[1]` 可以。

### 7.4 B4 任务脚本与红证缺失

```console
$ ls test/ast/p79_*.sh
test/ast/p79_basic.sh
present p79_basic
MISSING p79_index
MISSING p79_places
MISSING p79_migrate
MISSING p79_docs
$ git show 255016e0 --format='%B' --no-patch
test(ct-ast): p79 S3 红
$ git show 255016e0:test/ast/p79_basic.sh | grep -c baseline
0
$ ls test/ast/p79_red* 2>/dev/null || echo "no p79 red log"
no p79 red log
```

卡面 §2 写了五个验收脚本，仓库只有 `p79_basic`；`255016e0` 无 `baseline:`、命令、原始输出；
实现提交 `dda27c19` 又加了 7 个未跑红的用例。

## 8 处置

- SH-98：保持 `verified`（v0.79.2 无回归）。
- SH-99/100/101、TEST-24：本轮独立复核通过，`status: verified`；四条目已附 REV 复核段。
- 版本：`v0.79.2`，五处 `CTC_VERSION=0.79.2`；annotated tag `v0.79.2` peeled `13dcb594`，
  远端 `origin/main` 与 tag 一致；`g8` 绿。
- 本轮只改 verdict 与四个 issue 状态；未改实现代码、未 push。
- 复评结论：PH-79 S3 可按 v0.79.2 收口；§6 的已登记边界留给后续 phase，不阻断本轮。
