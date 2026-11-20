# P-7.5 证据：S1 `box<T>` + `new` 隔离原型

baseline: a18e7323

> 日期：2026-11-21；DEV（隔离原型 `/tmp/p75`，由 [run.sh](run.sh) 重建）
> 原型补丁：[prototype.patch](prototype.patch)；[phase81 卡](../../../design/phase81.md) §1.2；
> [提案 v2](../../../proposals/pointer-free-v2.md) A.7；[D-011](../../../decisions/D-011.md)、
> [D-013](../../../decisions/D-013.md)。
> 主仓未改 `selfhost/**`、`lib/std/**`、`test/**`；本目录只落证据、补丁与复现脚本。

## 0. 结论

| P-7.5 项 | 结果 | 证据 |
| --- | --- | --- |
| -1 `box<T>` 布局与 `{refs,aux}` 头对齐 | **通过**：句柄 16 字节（两个指针）、头 8 字节、payload 偏移 = `round_up(8, alignof(T))`，`_Static_assert` + 运行输出 | §4.1、§4.2 |
| -2 release 按静态类型；`box` 不使用 `refs=-1` immortal | **通过**：`box<Record>` 的 `String` 字段在归零时释放（`live` 1→0）；`box<String>` 的 `of` 自己 retain，release 归零；`refs` 从 1 起 | §4.2、§4.3 |
| -3 `new T { ... }` 仅具名 struct；`new String` / 数组 / 容器 / 内建句柄硬错 | **通过**：逐类负例退出码 1，诊断指名 | §4.4 |
| -4 Drop、借用视图 / 失效检测与 Vec 同构 | **通过**：`at()` 借用、release 后 ASan 报 `heap-use-after-free`；`use Drop` 宿主字段 glue 调 box Drop；ASan/UBSan 正例全绿 | §4.5、§4.6 |
| -5 `T` 含借用字段在 struct 声明层硬错 | **通过**：`struct Bad { Str tag; }` 硬错；`box<Str>` 在类型实参层硬错 | §4.4 |
| -6 引用环作者责任；`--debug-leaks` 只报计数 | **通过（契约）**：环保留 `refs=1`、无编译期告警、无环检测；`--debug-leaks` 在 ct-ast 仍未实现（非本轮引入），证据不称其为环检测 | §4.7 |
| -7 旧 golden 不变；ASan 无泄漏 / 悬挂 | **通过**：`check-ast` 全量 `1539 passed, 0 failed, 4 skipped`（§4.8），正例 ASan/UBSan stderr 0 字节 | §4.6、§4.8 |

一句话：句柄布局、静态 release、`new` 的语法/类型边界、Drop/借用失效、借用字段硬错、环泄漏契约都有原始输出；
**未覆盖**：`ct build` 跨单元 `box`（本原型仅单文件 compile 模式）、`--debug-leaks` 本身、自动 retain 插入
（box 按 `Vec` 的显式协议），见 §6。

## 1. 环境与基线

```console
$ uname -m
arm64
$ cc --version
Apple clang version 21.0.0 (clang-2100.4.1.1)
Target: arm64-apple-darwin27.2.0
$ sw_vers
ProductName:		macOS
ProductVersion:		27.2.1
BuildVersion:		26B131
$ git -C /Users/samxx/dsh-ws/ct-lang rev-parse HEAD
a18e7323...
$ git -C /tmp/p75 log --oneline -1
e021b7f baseline: a18e7323
```

隔离副本由主仓 `git archive a18e7323` 建立，`/tmp/p75` 内 `git init` 后提交基线；原型补丁只在副本内应用。
主仓 `git apply --check /tmp/p75-prototype.patch` 退出码 0（只读校验，未应用）。

## 2. 复现命令

```console
$ bash docs/planning/j6-evidence/p75/run.sh
```

`run.sh` 自己构建 L0 → L1 → L2 → ct-ast，再跑 `test/ast/p81_box.sh` 与
`test/ast/p80_layout.sh`、`test/ast/p80_retain.sh`；不依赖工作树里的二进制。产物在
`/tmp/p75-evidence`。手工复跑单条：

```console
$ cd /tmp/p75-evidence
$ CT_STD_DIR=$PWD/lib/std .build/ct-ast --allow-c-boundary \
      test/ast/p81_box/layout.ct -o /tmp/layout.c
$ cc -Wall -Wextra -std=c99 /tmp/layout.c -o /tmp/layout && /tmp/layout
```

## 3. 原型改动

| 文件 | 改动 |
| --- | --- |
| `lib/std/Box.h.ct` | 新内建单元：`ct_box_hdr`、`box<T>`、`of` / `retain` / `refs` / `release` / `drop` / `at` / `payload_offset`、泛型 `Drop` |
| `lib/std/Vec.h.ct` | 不变（box 不放进容器单元，避免未用 box 的程序产物变化） |
| `frontend/parse/Expr.h.ct` | `box<T>` 类型解析、`b.f` / `b.f =` 自动解引用、`b.ptr`/`b.h` 关闭、`new` 上下文关键字与 `new T { ... }`、借用实参拒绝 |
| `frontend/parse/Stmt.h.ct` | `static` 局部初始化器的 `new` 拒绝标志；裸 `box` 标识符与类型区分 |
| `frontend/parse/Parser.h.ct` | `struct Bad { Str tag; }` 声明层硬错 |
| `frontend/type/TypeCheck.h.ct` | `N_NEWOBJ` 的静态类型 = `box<T>` |
| `backend/emit/Emitter.h.ct` | 每实例 `box_X__new` / `box_X__copy` / `box_X__payload_release`；`__ct_box_*` 绑定；`new` 语句表达式；结构体初始化器的 `String` 字面量拥有化 |
| `tool/driver/Driver.h.ct` | 第 5 个内建单元 `Box.h.ct` 的按需加载（跳过注释/字符串/变量名 `box`） |
| `frontend/module/Module.h.ct` | build 模式同样按输入源码决定是否加载 `Box.h.ct`（未用时不加 `struct ct_box_hdr;` 前向声明） |
| `test/ast/p81_box.sh` + `test/ast/p81_box/**` | E81 探针与夹具 |

原型补丁：`prototype.patch`（32 文件、1325 insertions / 65 deletions）。

## 4. 原始输出

### 4.1 工具链

```console
$ sh .temp/build-ct-ast.sh /tmp/p75 /tmp/p75/.build2
built /tmp/p75/.build2/ct-ast
$ echo $?
0
```

### 4.2 布局（P-7.5-1、-2）

```console
$ CT_STD_DIR=/tmp/p75/lib/std .build2/ct-ast --allow-c-boundary \
      test/ast/p81_box/layout.ct -o t/layout.c
$ cc -Wall -Wextra -std=c99 t/layout.c -o t/layout     # stderr 0 字节
$ ./t/layout
sizeof(box)=16 sizeof(header)=8 alignof(box)=8
payload_offset=8 expected=8
refs=1 tag_refs=1 tag_len=1
after release refs=0
$ echo $?
0
```

`layout.ct` 里的 `_Static_assert` 在 `cc` 编译期钉住：`sizeof(box<Record>) == 2 * sizeof(void *)`、
`sizeof(box<Record>) == 16`、`sizeof(struct ct_box_hdr) == 8`；`payload_offset` 由 `box<T>` 方法读出，
与 `round_up(8, _Alignof(Record))` 相等（8）。

### 4.3 release 按静态类型（P-7.5-2）

`box<Record>` 的 payload-release helper（生成的 C）：

```c
static void __attribute__((unused)) box_Record__payload_release(struct Record *p)
{
    String_Drop_drop(&((p)->tag));
}
```

`record.ct` 的 refcount 轨迹（`String` 字段）：

```console
$ ./t/record
id=7 tag=5 refs=1 tag_refs=2
after source release tag_refs=1 live=1
id_after_set=8
point=1,2
point_after_set=5,2
designated id=9 tag=7 tag_refs=1
before release refs=1 live=2
after release refs=0 live=0
$ echo $?
0
```

`box<String>` 的 `of` 自带 retain（D-013 回填）：

```console
$ ./t/boxstr
len=2 box_refs=1 s_refs=2 live=1
after s release len=2 live=1
borrowed len=2
after b release refs=0 live=0
$ echo $?
0
```

`box` 从 `refs=1` 起，没有 `refs=-1` 路径；immortal 只属于 `String` 字面量 / 空串。

### 4.4 负例（P-7.5-3、-5）

```console
$ for n in neg_new_string neg_new_int neg_new_vec neg_new_no_brace neg_box_slice \
           neg_box_str neg_field_str neg_raw_field neg_new_global neg_new_static; do
      CT_STD_DIR=$PWD/lib/std .build2/ct-ast --allow-c-boundary test/ast/p81_box/$n.ct \
          -o /tmp/$n.c; echo "$n exit=$?"; done
neg_new_string exit=1 :: error: 'new String' / 'new Str' is not supported; use the literal, 'to_string()' or 'as_str()'
neg_new_int exit=1 :: error: 'new' only accepts a named struct type; scalars, pointers, arrays, unions, enums and built-in handles are not boxed
neg_new_vec exit=1 :: error: 'new' only accepts a named non-generic struct type; instantiate the generic first and box the value
neg_new_no_brace exit=1 :: error: 'new R' needs a brace initializer; only 'new T { ... }' is supported
neg_box_slice exit=1 :: error: a slice 'T[]' cannot be stored in box<T>; it is a non-owning view
neg_box_str exit=1 :: error: a borrowed view cannot be boxed; box<T> owns its payload (use String for an owning string)
neg_field_str exit=1 :: error: a borrowed 'Str' view cannot be a struct field; store an owning 'String' and call as_str() at the use site
neg_raw_field exit=1 :: error: '.h' / '.ptr' are raw implementation fields; use the box's methods or at()
neg_new_global exit=1 :: error: 'new' is only supported in a local initializer; a file-scope or static object cannot allocate at run time
neg_new_static exit=1 :: error: 'new' cannot initialize a static object; it allocates at run time, so assign it in the function body
```

`int new;` / `r.new` / 形参 `new` / `new = ...` 仍合法（`ctx.ct`，`E81-2` 的上下文关键字一侧）：

```console
$ ./t/ctx
var=4 field=7 param=5
$ echo $?
0
```

### 4.5 Drop / 字段 glue 与借用失效（P-7.5-4）

`struct Holder { box<Item> child; int n; } use Drop` + `own Holder *` + `delete`：

```console
$ ./t/vecbox
after push a_refs=2 len=1
got id=1 refs=2 name=3
after got release len=1
after v release len=0
holder before delete refs=2
holder after delete refs=1 id=2
keep released refs=0 live=0
$ echo $?
0
```

借用视图 `at()` 在 `release()` 后失效，ASan 灵敏度：

```console
$ cc -Wall -Wextra -std=c99 -fsanitize=address -g t/uaf.c -o t/uaf.asan
$ ASAN_OPTIONS=detect_leaks=0 ./t/uaf.asan
=================================================================
==...==ERROR: AddressSanitizer: heap-use-after-free on address 0x...
$ echo $?
134
```

### 4.6 正例 ASan / UBSan（P-7.5-7）

```console
$ CT_STD_DIR=$PWD/lib/std sh test/ast/p81_box.sh .build2/ct-ast
ok   layout -fsanitize=address
ok   layout -fsanitize=undefined
ok   layout (behaviour + sanitizers)
ok   record -fsanitize=address
ok   record -fsanitize=undefined
ok   record (behaviour + sanitizers)
ok   vecbox -fsanitize=address
ok   vecbox -fsanitize=undefined
ok   vecbox (behaviour + sanitizers)
ok   boxstr -fsanitize=address
ok   boxstr -fsanitize=undefined
ok   boxstr (behaviour + sanitizers)
ok   cycle -fsanitize=address
ok   cycle -fsanitize=undefined
ok   cycle (behaviour + sanitizers)
ok   ctx -fsanitize=address
ok   ctx -fsanitize=undefined
ok   ctx (behaviour + sanitizers)
ok   asan sensitivity (at() view after release -> heap-use-after-free)
ok   neg_new_string (rejected: new of a built-in handle)
...
ok   neg_new_static (rejected: new in a static local)
p81_box: OK
$ echo $?
0
```

每个正例的 `-fsanitize=address` / `-fsanitize=undefined` stderr 均为 0 字节。

### 4.7 环与 `--debug-leaks`（P-7.5-6）

```console
$ ./t/cycle
before: a_refs=2 b_refs=2
after handles: a_refs=1 b_refs=1 (cycle is author-owned)
ids still live: a=2 b=1
$ echo $?
0
```

两个节点互持 `retain()` 引用后，释放两个句柄仍各剩 `refs=1`；编译器没有环告警，也不做环检测。
`--debug-leaks` 在 baseline 的 ct-ast 尚不存在：

```console
$ .build2/ct-ast --debug-leaks t/cycle.ct -o /tmp/x.c
ctc: unknown option '--debug-leaks'
$ echo $?
1
```

本证据不把任何计数输出称为「环检测」；若将来实现，它只报未配对 alloc/release 计数（D-011 J-4c）。

### 4.8 旧 golden（P-7.5-7）

隔离副本内跑完整 `selfhost/check-ast.sh`：

```console
$ bash selfhost/check-ast.sh
...
== summary: 1539 passed, 0 failed, 4 skipped ==
$ echo $?
0
```

`p39 r8`（`--emit-c` 与基线逐字节比较）单独复跑：

```console
$ bash test/modules/p39_lib/r8_probe.sh .build2/ct-ast
p39_r8: OK
$ echo $?
0
```

## 5. 逐项对照

| 项 | 命令 | 结果 |
| --- | --- | --- |
| P-7.5-1 | `layout.ct` + `_Static_assert` | 16 / 8 / offset 8 |
| P-7.5-2 | `record.ct`、`boxstr.ct`、ASan | `live` 归零；`refs` 从 1 起 |
| P-7.5-3 | 10 个负例 | 全 exit 1，诊断指名 |
| P-7.5-4 | `vecbox.ct`、`uaf.ct`、ASan | Drop glue 生效；UAF 被抓 |
| P-7.5-5 | `neg_field_str.ct`、`neg_box_str.ct` | 声明层 / 类型实参层硬错 |
| P-7.5-6 | `cycle.ct` + `--debug-leaks` 探测 | 环保留 refs=1；flag 未实现 |
| P-7.5-7 | `check-ast`、`p39 r8`、ASan/UBSan | 1539/0；r8 OK；stderr 0 |

## 6. 限制与未覆盖（诚实）

1. **`ct build` 跨单元 `box<T>` 未支持**：box 实例按「外来元素」写在命名它的单元里，方法/助手是
   `static`；`box<T>` 出现在导出签名或另一个单元时，头里只有前向声明，链接失败。
   本轮 E81 不要求跨单元；compile 模式（单文件）与 build 模式单单元可用。文档明示。
2. **自动 retain 未插入**：box 采用 `Vec` 的显式协议（`retain()` / `release()`）；按值传参、字段赋值、
   容器元素插入都不会自动 retain。`of()` 会对 payload 的 owning 叶做 retain；`new` 按 move。
3. **`--debug-leaks` 未实现**：baseline 的 ct-ast 没有该选项；本证据只证明「未把计数叫环检测」，
   不声称 flag 可用。
4. **`box<String>` 只能经 `box<String>::of`**：`new String` 仍是硬错；D-013 的
   `box<String>` 回填以 `of` 满足。
5. **payload-release 的数组覆盖有限**：单维 owning 数组会逐元素释放；多维数组留给显式 Drop
   （与现有 Drop glue 的规则一致）。
6. **文档未落**：spec §4.71 / tutorial / package-guide 属 PH-81 S1c，不在 P-7.5 原型内。
7. **ASan 泄漏检测关闭**：harness 用 `ASAN_OPTIONS=detect_leaks=0`（与 PH-80 一致），环泄漏用
   `refs` 轨迹证明，不用 LeakSanitizer（Darwin 上也不稳定）。

## 7. E1–E5（提案 A.0）

- **E1 命令/输出/退出码**：§4 全部命令、原始 stdout/stderr、退出码；基线 `a18e7323`，clang 21。
- **E2 锚点**：`lib/std/Box.h.ct:29`（header）、`:34`（`box<T>`）；`frontend/parse/Expr.h.ct:7606`
  （自动解引用）、`:7656`（`new` 前瞻）、`:7716`（`new T { ... }`）；`backend/emit/Emitter.h.ct:2513`
  （静态 release 判定）、`:2554`（payload release）、`:2616`（payload copy）、`:7294`（`new` 发射）。
- **E3 可证伪预测**：若出现下列任一结果，则 P-7.5 失败——`sizeof(box<T>) != 16`、
  payload offset != `round_up(8, alignof(T))`、`box<Record>` 释放后 `ct_str_live_count()` 不归零、
  `new String` / `new int` / `new Vec<int>` 被接受、`box<Str>` 被接受、release 后 `at()` 读取未被
  ASan 抓到、`check-ast` 或 `p39 r8` 变红。
- **E4 代价**：patch 32 文件、1325 insertions / 65 deletions；新增 fixture 17 个；ABI 增量 =
  句柄 16 字节 + 头 8 字节 + `Box.h.ct` 一个内建单元；`check-ast` 1539 项无回归。
- **E5 失败时的替代解释 / 收缩**：若布局断言失败，先核对 `_Alignof(T)` 与 `header_size(T)`，
  再把 handle 收缩为 `{T *ptr}`（放弃 16 字节对齐目标）；若跨单元需求提前，改为把 box 实例写进
  命名单元的头（工作量更大）；若 `of` 的 retain 语义无法证明，删掉 `box<String>::of` 并把
  D-013 回填记为未满足。

## 8. 判定

P-7.5 **通过**：E81-1…5 的机制在隔离原型中可编译、可运行、ASan/UBSan 干净，负例与旧 golden 都稳定。
PH-81 主仓实现按 S1a/S1b/S1c 进入施工；§6 的跨单元与自动 retain 限制不阻塞 E81。

## 附：证据可复现的源码位置

- 原型补丁：`prototype.patch`（`git apply --check` 于 `a18e7323` 通过）。
- 驱动脚本：`run.sh`。
- 探针：`test/ast/p81_box.sh`；夹具：`test/ast/p81_box/*.ct` 与 `expected.*.out`。
