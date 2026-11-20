# P-7.2 证据：S3 切片最小垂直原型（J-6）

| 项 | 值 |
| --- | --- |
| 任务 | J-6 证据 P-7.2（S3 切片最小垂直原型） |
| 日期 | 2026-11-20 |
| 基线 | `dff5a0dfc0ee1698d538bf95d07ce39084b75b03`（主仓 HEAD） |
| 隔离副本 | `/tmp/p72`（`git clone` 基线；主仓源码未改） |
| 环境 | Darwin arm64；Apple clang 21.0.0（`arm64-apple-darwin27.2.0`）；`ct-ast v0.77.2` |
| 复现入口 | `bash evidence/p72/run.sh`（一条命令：自举链 + 16 项断言 + 自举不动点） |
| 结果 | **16 passed, 0 failed**（退出码 0） |
| patch | `p72.patch`（相对基线 `dff5a0df`，含源码、夹具与 runner） |

## 0. 判定摘要（先说结论）

P-7.2 要求的最小垂直原型**已实现并且可复现**：`T[]` 的 `{ptr,len}` 表示、
`get(i)` 软访问、`s[i]` 检查 place 与越界 trap、`const T[]` 写硬错、
越界构造硬错、返回局部视图 lint、`foreach`、C 数组行为不变。

但 **A.4 不是全绿**：A.4 P-4.1 的 10 类存储位置只覆盖 4 类
（字段 / 全局 / 泛型实参 / 数组元素），接口、box、Option、Result、容器、
闭包捕获未实现或未验证；P-4.2 只验证了 `Vec<int[]>`，复合递归未全测；
P-4.3 只覆盖直接返回局部数组视图的 lint。

因此：**可以把 P-7.2 判为「最小垂直原型通过」；不能据此判「S3 全量 / A.4 全绿通过」。**
J-6 整体仍不能只凭本证据升 A（还需 P-7.1a/b、P-7.3，以及补齐 A.4 未覆盖类）。

## 1. P-7.2 逐项对照

| 判据 | 结论 | 证据 |
| --- | --- | --- |
| `T[]` 表示 `{ptr,len}` | **通过** | 生成 C 的 `struct __ct_slice`；LP64 下 `sizeof=16 align=8`；`Emitter.h.ct:2414` |
| `T a[] = {...}` 仍是推断长度 C 数组 | **通过** | `pos_arrays_unchanged`；`pos_basic` 的 `int a[] = {1,2,3}` |
| 数组→切片 `T[] s = a` | **通过** | `pos_basic`；生成 `(struct __ct_slice){ (void *)(a), sizeof(a)/sizeof(a[0]) }` |
| `s.get(i)` 软访问（越界 0） | **通过** | `pos_basic` 输出 `get9=-1`；`Expr.h.ct:4813`；`Emitter.h.ct:5070` |
| `s[i]` 读/写 + 越界 trap | **通过** | `pos_basic` 写回 `a[0]=9`；`neg_trap` 运行退出 1，stderr `slice index 5 out of bounds (length 3)` |
| `const T[]` 写硬错 | **通过** | `neg_const_write` 退出 1：`cannot write to an element of a const slice` |
| 越界构造硬错 | **通过（静态可判定部分）** | `neg_subslice_oob` 退出 1：`slice construction out of bounds: [1,4) for length 3`；`[]` 推断长度与 slice 基座走运行期 `__ct_slice_range` trap |
| 返回局部数组/视图 lint | **通过（直接形态）** | `neg_return_lint` 退出 0，stderr `warning: slice escape: 'return' hands back a view of a local array` |
| `foreach` over slice | **通过** | `pos_basic` / `pos_param` / `pos_const`；`Emitter.h.ct:4613` |
| C 数组 `T[N]` 行为不变 | **通过** | `pos_arrays_unchanged` 输出 `12 5 2`；L0/L1/L2 未改语义 |
| 至少 4 正例 + 6 负例 | **通过** | 6 正例 + 9 负例，共 15 个夹具；见 §3 |
| 可编译、可运行、负例可复现 | **通过** | 自举链退出 0；16/16 断言通过；自举不动点 diff 为空 |

## 2. 实现范围与锚点

只改 `selfhost/ct-ast/**`（slice 实现）和 `selfhost/l2/core.ct` 的一行容量
（见 §6 第 11 条）；L0 `ctc.c`、L1 `ctc.ct` 未改。

| 关注点 | 位置 |
| --- | --- |
| 符号表的 slice 元数据 | `selfhost/ct-ast/frontend/sym/Symbols.h.ct:176`（`is_slice` / `slice_elem` / `slice_const` / `slice_escape`） |
| `[` `]` 前瞻 | `selfhost/ct-ast/frontend/parse/ParseSupport.h.ct:126` |
| 声明位置（局部 / 形参 / 返回） | `selfhost/ct-ast/frontend/parse/Stmt.h.ct:3940`；`Parser.h.ct:1897`（形参）、`Parser.h.ct:1516`（返回） |
| 字段 / 全局 / 泛型实参硬错 | `Parser.h.ct:2176` / `Parser.h.ct:1627` / `Expr.h.ct:2347`、`Expr.h.ct:7367` |
| `s[i]`、`s.get(i)`、`a[lo..hi]` | `Expr.h.ct:4525` 起；节点定义 `Expr.h.ct:115` |
| const 写硬错 | `Stmt.h.ct:4399`、`Stmt.h.ct:4510`；值位置 `Expr.h.ct:3227` |
| 返回 lint | `Stmt.h.ct:2297`；warning 通道 `Diag.h.ct:215`、`Diag.h.ct:544` |
| `{ptr,len}` + 三个 helper | `Emitter.h.ct:2414`（`emit_slice_helpers`） |
| `s[i]` / `get` / `range` 发射 | `Emitter.h.ct:5055` 起（`N_SLICE_*`） |
| slice `foreach` | `Emitter.h.ct:4613` |
| L2 容量 | `selfhost/l2/core.ct:53`（`MAX_CALLS` 1024 → 4096） |

## 3. 用例与原始结果

正例（6）：`pos_basic`（数组→切片/读写/foreach/get）、`pos_struct`（struct 元素）、
`pos_param`（切片形参、形参子切片、切片返回与调用绑定）、`pos_subslice`
（半开区间、开放上界、slice 子切片）、`pos_const`（const 只读）、
`pos_arrays_unchanged`（C 数组控制组）。

负例（9）：`neg_trap`（运行期 trap）、`neg_const_write`、`neg_field`、
`neg_global`、`neg_generic`、`neg_arrelem`、`neg_subslice_oob`、
`neg_return_lint`（lint 不是硬错）、`neg_bad_init`。

| 用例 | 类型 | 期望 | 实测 |
| --- | --- | --- | --- |
| pos_basic | 正 | `s0=9 s2=3 k=14 get1=2 get9=-1` | 一致 |
| pos_struct | 正 | `7 20 7` | 一致 |
| pos_param | 正 | `sum=10 a0=100 t0=2 t2=4` / `a1=20` | 一致 |
| pos_subslice | 正 | `2 4 3 4` / `a1=20` | 一致 |
| pos_const | 正 | `4 6 15` | 一致 |
| pos_arrays_unchanged | 正 | `12 5 2` | 一致 |
| neg_trap | 运行负 | 编译 0；运行非 0；stderr 含 `out of bounds` | 编译 0；运行 1；`ct: slice index 5 out of bounds (length 3)` |
| neg_const_write | 编译负 | 非 0；const 写诊断 | 1；`cannot write to an element of a const slice` |
| neg_field | 编译负 | 非 0；字段放置诊断 | 1；`cannot be a struct field` |
| neg_global | 编译负 | 非 0；全局放置诊断 | 1；`cannot be a file-scope variable` |
| neg_generic | 编译负 | 非 0；泛型实参诊断 | 1；`cannot be a generic type argument` |
| neg_arrelem | 编译负 | 非 0；数组元素诊断 | 1；`cannot be an array element` |
| neg_subslice_oob | 编译负 | 非 0；构造越界诊断 | 1；`slice construction out of bounds: [1,4) for length 3` |
| neg_return_lint | lint | 编译 0；stderr 含 `slice escape` | 0；`warning: slice escape: ...` |
| neg_bad_init | 编译负 | 非 0；来源诊断 | 1；`can only be initialized from an array` |

## 4. 复现命令与完整原始输出

从基线复现：

```console
$ cd /tmp/p72
$ git apply docs/planning/j6-evidence/p72/p72.patch   # 若从干净基线开始
$ bash evidence/p72/run.sh
...
P-7.2 evidence: 16 passed, 0 failed
$ echo $?
0
```

以下是本次实跑的完整输出（`bash evidence/p72/run.sh`，退出码 0）：

```text
== bootstrap: L0 -> L1 -> L2 -> ct-ast ==
  $ cc -Wall -Wextra -std=c99 selfhost/l0/ctc.c -o /var/folders/dm/hftq00ms7sb5_67xhdgbw92r0000gn/T//p72-evidence.20471/ctc
  $ /var/folders/dm/hftq00ms7sb5_67xhdgbw92r0000gn/T//p72-evidence.20471/ctc selfhost/l1/ctc.ct -o /var/folders/dm/hftq00ms7sb5_67xhdgbw92r0000gn/T//p72-evidence.20471/l1.c
  $ cc -Wall -Wextra -std=c99 /var/folders/dm/hftq00ms7sb5_67xhdgbw92r0000gn/T//p72-evidence.20471/l1.c -o /var/folders/dm/hftq00ms7sb5_67xhdgbw92r0000gn/T//p72-evidence.20471/l1
  $ /var/folders/dm/hftq00ms7sb5_67xhdgbw92r0000gn/T//p72-evidence.20471/l1 build selfhost/l2/driver.ct -o /var/folders/dm/hftq00ms7sb5_67xhdgbw92r0000gn/T//p72-evidence.20471/l2src
cc /var/folders/dm/hftq00ms7sb5_67xhdgbw92r0000gn/T//p72-evidence.20471/l2src/core.c /var/folders/dm/hftq00ms7sb5_67xhdgbw92r0000gn/T//p72-evidence.20471/l2src/driver.c -o a.out
  $ cc -Wall -Wextra -std=c99 /var/folders/dm/hftq00ms7sb5_67xhdgbw92r0000gn/T//p72-evidence.20471/l2src/*.c -o /var/folders/dm/hftq00ms7sb5_67xhdgbw92r0000gn/T//p72-evidence.20471/l2
  $ /var/folders/dm/hftq00ms7sb5_67xhdgbw92r0000gn/T//p72-evidence.20471/l2 build -I selfhost/ct-ast selfhost/ct-ast/main.ct -o /var/folders/dm/hftq00ms7sb5_67xhdgbw92r0000gn/T//p72-evidence.20471/astsrc
cc -std=c99 /var/folders/dm/hftq00ms7sb5_67xhdgbw92r0000gn/T//p72-evidence.20471/astsrc/Symbols.c /var/folders/dm/hftq00ms7sb5_67xhdgbw92r0000gn/T//p72-evidence.20471/astsrc/Init.c /var/folders/dm/hftq00ms7sb5_67xhdgbw92r0000gn/T//p72-evidence.20471/astsrc/Lexer.c /var/folders/dm/hftq00ms7sb5_67xhdgbw92r0000gn/T//p72-evidence.20471/astsrc/MapTable.c /var/folders/dm/hftq00ms7sb5_67xhdgbw92r0000gn/T//p72-evidence.20471/astsrc/Unit.c /var/folders/dm/hftq00ms7sb5_67xhdgbw92r0000gn/T//p72-evidence.20471/astsrc/Arena.c /var/folders/dm/hftq00ms7sb5_67xhdgbw92r0000gn/T//p72-evidence.20471/astsrc/Diag.c /var/folders/dm/hftq00ms7sb5_67xhdgbw92r0000gn/T//p72-evidence.20471/astsrc/Memory.c /var/folders/dm/hftq00ms7sb5_67xhdgbw92r0000gn/T//p72-evidence.20471/astsrc/TypeCheck.c /var/folders/dm/hftq00ms7sb5_67xhdgbw92r0000gn/T//p72-evidence.20471/astsrc/ParseSupport.c /var/folders/dm/hftq00ms7sb5_67xhdgbw92r0000gn/T//p72-evidence.20471/astsrc/Expr.c /var/folders/dm/hftq00ms7sb5_67xhdgbw92r0000gn/T//p72-evidence.20471/astsrc/Emitter.c /var/folders/dm/hftq00ms7sb5_67xhdgbw92r0000gn/T//p72-evidence.20471/astsrc/MapBuild.c /var/folders/dm/hftq00ms7sb5_67xhdgbw92r0000gn/T//p72-evidence.20471/astsrc/Stmt.c /var/folders/dm/hftq00ms7sb5_67xhdgbw92r0000gn/T//p72-evidence.20471/astsrc/Parser.c /var/folders/dm/hftq00ms7sb5_67xhdgbw92r0000gn/T//p72-evidence.20471/astsrc/Cache.c /var/folders/dm/hftq00ms7sb5_67xhdgbw92r0000gn/T//p72-evidence.20471/astsrc/Sh.c /var/folders/dm/hftq00ms7sb5_67xhdgbw92r0000gn/T//p72-evidence.20471/astsrc/Module.c /var/folders/dm/hftq00ms7sb5_67xhdgbw92r0000gn/T//p72-evidence.20471/astsrc/Pkg.c /var/folders/dm/hftq00ms7sb5_67xhdgbw92r0000gn/T//p72-evidence.20471/astsrc/Driver.c /var/folders/dm/hftq00ms7sb5_67xhdgbw92r0000gn/T//p72-evidence.20471/astsrc/main.c -o a.out
  $ cc -Wall -Wextra -std=c99 /var/folders/dm/hftq00ms7sb5_67xhdgbw92r0000gn/T//p72-evidence.20471/astsrc/*.c -o /var/folders/dm/hftq00ms7sb5_67xhdgbw92r0000gn/T//p72-evidence.20471/ct-ast
ct-ast: ct-ast v0.77.2

== self-host fixpoint (the compiler's own sources carry no slice syntax) ==
  $ /var/folders/dm/hftq00ms7sb5_67xhdgbw92r0000gn/T//p72-evidence.20471/ct-ast build --emit-c -I selfhost/ct-ast selfhost/ct-ast/main.ct -o /var/folders/dm/hftq00ms7sb5_67xhdgbw92r0000gn/T//p72-evidence.20471/self1
  $ cc -Wall -Wextra -std=c99 /var/folders/dm/hftq00ms7sb5_67xhdgbw92r0000gn/T//p72-evidence.20471/self1/*.c -o /var/folders/dm/hftq00ms7sb5_67xhdgbw92r0000gn/T//p72-evidence.20471/ct-ast2
  $ /var/folders/dm/hftq00ms7sb5_67xhdgbw92r0000gn/T//p72-evidence.20471/ct-ast2 build --emit-c -I selfhost/ct-ast selfhost/ct-ast/main.ct -o /var/folders/dm/hftq00ms7sb5_67xhdgbw92r0000gn/T//p72-evidence.20471/self2
  exits: gen1=0 cc=0 gen2=0
PASS  selfhost

== negative: neg_trap (compile, then trap at run time) ==
  $ CT_C_BOUNDARY=allow /var/folders/dm/hftq00ms7sb5_67xhdgbw92r0000gn/T//p72-evidence.20471/ct-ast evidence/p72/cases/neg_trap.ct -o /var/folders/dm/hftq00ms7sb5_67xhdgbw92r0000gn/T//p72-evidence.20471/neg_trap.c
  compile exit=0
  host-cc exit=0
  $ /var/folders/dm/hftq00ms7sb5_67xhdgbw92r0000gn/T//p72-evidence.20471/neg_trap.bin
  run exit=1
  stderr: ct: slice index 5 out of bounds (length 3)
PASS  neg_trap

== negative: neg_return_lint (compile succeeds, lint on stderr) ==
  $ CT_C_BOUNDARY=allow /var/folders/dm/hftq00ms7sb5_67xhdgbw92r0000gn/T//p72-evidence.20471/ct-ast evidence/p72/cases/neg_return_lint.ct -o /var/folders/dm/hftq00ms7sb5_67xhdgbw92r0000gn/T//p72-evidence.20471/neg_return_lint.c
  exit=0
  evidence/p72/cases/neg_return_lint.ct:7: warning: slice escape: 'return' hands back a view of a local array
PASS  neg_return_lint

== positive: pos_basic ==
  $ CT_C_BOUNDARY=allow /var/folders/dm/hftq00ms7sb5_67xhdgbw92r0000gn/T//p72-evidence.20471/ct-ast evidence/p72/cases/pos_basic.ct -o /var/folders/dm/hftq00ms7sb5_67xhdgbw92r0000gn/T//p72-evidence.20471/pos_basic.c
  exit=0
  $ cc -std=c99 -Wall -Wextra /var/folders/dm/hftq00ms7sb5_67xhdgbw92r0000gn/T//p72-evidence.20471/pos_basic.c -o /var/folders/dm/hftq00ms7sb5_67xhdgbw92r0000gn/T//p72-evidence.20471/pos_basic.bin
  exit=0
  $ /var/folders/dm/hftq00ms7sb5_67xhdgbw92r0000gn/T//p72-evidence.20471/pos_basic.bin
  exit=0
  s0=9 s2=3 k=14 get1=2 get9=-1
PASS  pos_basic

== positive: pos_struct ==
  $ CT_C_BOUNDARY=allow /var/folders/dm/hftq00ms7sb5_67xhdgbw92r0000gn/T//p72-evidence.20471/ct-ast evidence/p72/cases/pos_struct.ct -o /var/folders/dm/hftq00ms7sb5_67xhdgbw92r0000gn/T//p72-evidence.20471/pos_struct.c
  exit=0
  $ cc -std=c99 -Wall -Wextra /var/folders/dm/hftq00ms7sb5_67xhdgbw92r0000gn/T//p72-evidence.20471/pos_struct.c -o /var/folders/dm/hftq00ms7sb5_67xhdgbw92r0000gn/T//p72-evidence.20471/pos_struct.bin
  exit=0
  $ /var/folders/dm/hftq00ms7sb5_67xhdgbw92r0000gn/T//p72-evidence.20471/pos_struct.bin
  exit=0
  7 20 7
PASS  pos_struct

== positive: pos_param ==
  $ CT_C_BOUNDARY=allow /var/folders/dm/hftq00ms7sb5_67xhdgbw92r0000gn/T//p72-evidence.20471/ct-ast evidence/p72/cases/pos_param.ct -o /var/folders/dm/hftq00ms7sb5_67xhdgbw92r0000gn/T//p72-evidence.20471/pos_param.c
  exit=0
  $ cc -std=c99 -Wall -Wextra /var/folders/dm/hftq00ms7sb5_67xhdgbw92r0000gn/T//p72-evidence.20471/pos_param.c -o /var/folders/dm/hftq00ms7sb5_67xhdgbw92r0000gn/T//p72-evidence.20471/pos_param.bin
  exit=0
  $ /var/folders/dm/hftq00ms7sb5_67xhdgbw92r0000gn/T//p72-evidence.20471/pos_param.bin
  exit=0
  sum=10 a0=100 t0=2 t2=4
  a1=20
PASS  pos_param

== positive: pos_subslice ==
  $ CT_C_BOUNDARY=allow /var/folders/dm/hftq00ms7sb5_67xhdgbw92r0000gn/T//p72-evidence.20471/ct-ast evidence/p72/cases/pos_subslice.ct -o /var/folders/dm/hftq00ms7sb5_67xhdgbw92r0000gn/T//p72-evidence.20471/pos_subslice.c
  exit=0
  $ cc -std=c99 -Wall -Wextra /var/folders/dm/hftq00ms7sb5_67xhdgbw92r0000gn/T//p72-evidence.20471/pos_subslice.c -o /var/folders/dm/hftq00ms7sb5_67xhdgbw92r0000gn/T//p72-evidence.20471/pos_subslice.bin
  exit=0
  $ /var/folders/dm/hftq00ms7sb5_67xhdgbw92r0000gn/T//p72-evidence.20471/pos_subslice.bin
  exit=0
  2 4 3 4
  a1=20
PASS  pos_subslice

== positive: pos_const ==
  $ CT_C_BOUNDARY=allow /var/folders/dm/hftq00ms7sb5_67xhdgbw92r0000gn/T//p72-evidence.20471/ct-ast evidence/p72/cases/pos_const.ct -o /var/folders/dm/hftq00ms7sb5_67xhdgbw92r0000gn/T//p72-evidence.20471/pos_const.c
  exit=0
  $ cc -std=c99 -Wall -Wextra /var/folders/dm/hftq00ms7sb5_67xhdgbw92r0000gn/T//p72-evidence.20471/pos_const.c -o /var/folders/dm/hftq00ms7sb5_67xhdgbw92r0000gn/T//p72-evidence.20471/pos_const.bin
  exit=0
  $ /var/folders/dm/hftq00ms7sb5_67xhdgbw92r0000gn/T//p72-evidence.20471/pos_const.bin
  exit=0
  4 6 15
PASS  pos_const

== positive: pos_arrays_unchanged ==
  $ CT_C_BOUNDARY=allow /var/folders/dm/hftq00ms7sb5_67xhdgbw92r0000gn/T//p72-evidence.20471/ct-ast evidence/p72/cases/pos_arrays_unchanged.ct -o /var/folders/dm/hftq00ms7sb5_67xhdgbw92r0000gn/T//p72-evidence.20471/pos_arrays_unchanged.c
  exit=0
  $ cc -std=c99 -Wall -Wextra /var/folders/dm/hftq00ms7sb5_67xhdgbw92r0000gn/T//p72-evidence.20471/pos_arrays_unchanged.c -o /var/folders/dm/hftq00ms7sb5_67xhdgbw92r0000gn/T//p72-evidence.20471/pos_arrays_unchanged.bin
  exit=0
  $ /var/folders/dm/hftq00ms7sb5_67xhdgbw92r0000gn/T//p72-evidence.20471/pos_arrays_unchanged.bin
  exit=0
  12 5 2
PASS  pos_arrays_unchanged

== negative: neg_const_write (expect hard error containing: cannot write to an element of a const slice) ==
  $ CT_C_BOUNDARY=allow /var/folders/dm/hftq00ms7sb5_67xhdgbw92r0000gn/T//p72-evidence.20471/ct-ast evidence/p72/cases/neg_const_write.ct -o /var/folders/dm/hftq00ms7sb5_67xhdgbw92r0000gn/T//p72-evidence.20471/neg_const_write.c
  exit=1
  evidence/p72/cases/neg_const_write.ct:6:7: error: cannot write to an element of a const slice
  ctc: 1 error(s) generated
PASS  neg_const_write

== negative: neg_field (expect hard error containing: cannot be a struct field) ==
  $ CT_C_BOUNDARY=allow /var/folders/dm/hftq00ms7sb5_67xhdgbw92r0000gn/T//p72-evidence.20471/ct-ast evidence/p72/cases/neg_field.ct -o /var/folders/dm/hftq00ms7sb5_67xhdgbw92r0000gn/T//p72-evidence.20471/neg_field.c
  exit=1
  evidence/p72/cases/neg_field.ct:2:15: error: a slice 'T[]' cannot be a struct field; it is a non-owning view
  ctc: 1 error(s) generated
PASS  neg_field

== negative: neg_global (expect hard error containing: cannot be a file-scope variable) ==
  $ CT_C_BOUNDARY=allow /var/folders/dm/hftq00ms7sb5_67xhdgbw92r0000gn/T//p72-evidence.20471/ct-ast evidence/p72/cases/neg_global.ct -o /var/folders/dm/hftq00ms7sb5_67xhdgbw92r0000gn/T//p72-evidence.20471/neg_global.c
  exit=1
  evidence/p72/cases/neg_global.ct:3:1: error: a slice 'T[]' cannot be a file-scope variable; keep it a local or a parameter
  ctc: 1 error(s) generated
PASS  neg_global

== negative: neg_generic (expect hard error containing: cannot be a generic type argument) ==
  $ CT_C_BOUNDARY=allow /var/folders/dm/hftq00ms7sb5_67xhdgbw92r0000gn/T//p72-evidence.20471/ct-ast evidence/p72/cases/neg_generic.ct -o /var/folders/dm/hftq00ms7sb5_67xhdgbw92r0000gn/T//p72-evidence.20471/neg_generic.c
  exit=1
  evidence/p72/cases/neg_generic.ct:4:12: error: a slice 'T[]' cannot be a generic type argument; it is a non-owning view
  ctc: 1 error(s) generated
PASS  neg_generic

== negative: neg_arrelem (expect hard error containing: cannot be an array element) ==
  $ CT_C_BOUNDARY=allow /var/folders/dm/hftq00ms7sb5_67xhdgbw92r0000gn/T//p72-evidence.20471/ct-ast evidence/p72/cases/neg_arrelem.ct -o /var/folders/dm/hftq00ms7sb5_67xhdgbw92r0000gn/T//p72-evidence.20471/neg_arrelem.c
  exit=1
  evidence/p72/cases/neg_arrelem.ct:5:8: error: a slice 'T[]' cannot be an array element
  ctc: 1 error(s) generated
PASS  neg_arrelem

== negative: neg_subslice_oob (expect hard error containing: slice construction out of bounds) ==
  $ CT_C_BOUNDARY=allow /var/folders/dm/hftq00ms7sb5_67xhdgbw92r0000gn/T//p72-evidence.20471/ct-ast evidence/p72/cases/neg_subslice_oob.ct -o /var/folders/dm/hftq00ms7sb5_67xhdgbw92r0000gn/T//p72-evidence.20471/neg_subslice_oob.c
  exit=1
  evidence/p72/cases/neg_subslice_oob.ct:6:16: error: slice construction out of bounds: [1,4) for length 3
  ctc: 1 error(s) generated
PASS  neg_subslice_oob

== negative: neg_bad_init (expect hard error containing: can only be initialized from an array) ==
  $ CT_C_BOUNDARY=allow /var/folders/dm/hftq00ms7sb5_67xhdgbw92r0000gn/T//p72-evidence.20471/ct-ast evidence/p72/cases/neg_bad_init.ct -o /var/folders/dm/hftq00ms7sb5_67xhdgbw92r0000gn/T//p72-evidence.20471/neg_bad_init.c
  exit=1
  evidence/p72/cases/neg_bad_init.ct:6:5: error: a slice can only be initialized from an array or another slice
  ctc: 1 error(s) generated
PASS  neg_bad_init

=============================================================
P-7.2 evidence: 16 passed, 0 failed
```
## 5. 对照 A.4（逐项，不把未做写成通过）

| A.4 | 结论 | 依据 / 缺口 |
| --- | --- | --- |
| P-4.1 存储位置硬错 | **部分通过（4/10 类）** | 字段、全局、泛型实参、数组元素有硬错与负例；接口、box、Option、Result、容器、闭包捕获未实现/未验证。`Vec<int[]>` 走泛型实参检查，`Option<int[]>`/`Result<int[],E>` 未实测 |
| P-4.2 复合类型递归 | **部分通过** | `Vec<int[]>` 红；`Map<char *, int[]>`、`Vec<Vec<int[]>>`、`struct { int[] s; }` 未逐一实测（字段一类的直接形态已红） |
| P-4.3 返回值契约 | **部分通过** | 直接 `return` 局部数组视图 lint 通过；返回形参视图（`tail`）正例通过；`as_str()`（S5）与字面量视图不在本原型范围 |
| P-4.4 诊断质量 | **部分通过** | 已覆盖的 4 类都指向具体 `[`/赋值位置并给出放置名；未覆盖类没有诊断可评 |
| P-4.5 残留风险 | **通过（已文档化）** | 透传（调用结果、指针别名）由作者负责；slice→slice 的 `slice_escape` 会传播，call 结果视为 callee 契约（§6 第 9 条） |
## 6. 简化与未覆盖（逐条列出）

1. `T[]` 的 C 表示是**擦除元素类型**的 `struct __ct_slice { void *ptr; int len; }`；元素类型只保存在符号表，使用时靠 cast 恢复，不是 typed ABI。
2. 只支持局部变量、形参、切片返回类型；字段/全局/泛型实参/数组元素是硬错，接口/box/Option/Result/容器/闭包捕获没有实现（部分会落到泛型实参或字段检查）。
3. 元素类型只实测 `int` 与具名 `struct`；数组/指针/typedef 别名元素、`char`/`Str`（S5）未支持。
4. 子切片语法 `a[lo..hi]` / `a[lo..]` 已实现；**编译期**越界硬错只在基座是字面 `[N]` 数组且两端都是整数字面量时触发；`T a[] = {…}`、slice 基座和非常量边界走运行期 helper（越界 trap）。
5. `s[i]` / `s.get(i)` 的基座必须是**裸 slice 变量**；`s.field[i]`、`f().get(i)` 未支持。数组→切片只在声明初始化时成立，`int[] s; s = a;` 未支持（`s = a[1..4]` 可以）。
6. `foreach` 沿用项目既有规则，body 必须是块；slice 的 `item` 是按值拷贝，`i` 只读。
7. `s[i]` 越界用 helper 打印后 `exit(1)`（无恢复）；`get` 越界返回 0 指针，解引用由调用者负责。
8. `const T[]` 只是编译期标志；C 类型仍是可写 struct，`const` 不进入 ABI。
9. 无借用/生命周期分析；`slice_escape` 只沿直接赋值/直接子切片传播，调用返回的视图按 callee 契约信任（P-4.5 的透传水位）。
10. 允许切片返回类型并被调用；返回值视图的生命周期不做检查，只对“返回本地数组视图”的直接形态 lint。
11. **`selfhost/l2/core.ct` 的 `MAX_CALLS` 1024→4096**：L2 是冻结自举编译器，加入 slice 代码后其 call-edge 表溢出；只改容量，不改语义。这是 `ct-ast/**` 之外的唯一改动，必须在评审时单列。
12. 未跑 `selfhost/check-all.sh` 全量、corpus、ASan/sanitizer；只跑了自举链、15 个夹具和自举不动点。
13. 未测 `ct check` 严格模式下的 lint 升级（本证据的 lint 是 compile 模式 warning，退出码 0）。
14. 未测 build 模式下含 slice 的多单元工程；helper 按单元发射、slice 形参的跨单元头文件形状未验证。
15. 空 slice `{0,0}` 没有显式构造语法；`len` 不是语言成员（生成 C 里是 `struct` 字段）。
16. 数组形参不能作为 slice 来源（长度已丢失）；`int a[]` 局部/全局数组可用 `sizeof` 取推断长度。
## 7. 证据格式 E1–E5

- **E1**：命令、原始输出、退出码、基线 sha、环境均在 §1–§4；`run.sh` 一条命令复跑，退出码 0。
- **E2**：`file:line` 锚点见 §2；**对己方不利的一条**：A.4 的 10 类只覆盖 4 类，且 `T[]` ABI 擦除了元素类型/const，不能据此宣称“S3 全量”。
- **E3 可证伪预测**：任一正例编译/运行失败、任一编译负例退出 0 或缺诊断、trap 用例不非零、lint 用例无 `slice escape`，则 P-7.2 失败；本次这些条件均未出现。
- **E4 代价**：源码 9 文件 +753/−15 行；夹具 15 个 + `run.sh` + 6 个 expected；`struct __ct_slice` 在 arm64 LP64 下 `sizeof=16 align=8`；新增 helper 约 1.2 KB 生成 C（仅 slice 程序发射）。
- **E5 失败时替代/收缩**：若要求 A.4 全量，可先把未覆盖类降为“直接形态 lint + 四类硬错”的契约水位（P-4.5），或把 slice 字段/容器改为显式 `Slice` 句柄；本原型已证明表示、检查 place、构造边界与返回 lint 的最小闭环。
## 8. patch、主仓边界与 J-6 结论

- patch：`docs/planning/j6-evidence/p72/p72.patch`（1689 行；相对 `dff5a0df`）。应用：`git apply docs/planning/j6-evidence/p72/p72.patch`。
- 主仓只新增 `docs/planning/j6-evidence/p72/evidence.md` 与 `p72.patch`，未改其他文件，未 commit、未 push、未打 tag。
- **P-7.2（最小垂直原型）**：通过，16/16 断言可复现。
- **P-7.2（S3 全量 / A.4）**：未通过——A.4 的 P-4.1 只覆盖 4/10 类，P-4.2/P-4.3/P-4.4 也只是部分覆盖；不能把“最小原型通过”写成“A.4 全绿”。
- **J-6**：本证据足以支撑 P-7.2 的**最小原型门槛**，但不足以便 J-6 升 A；还需 P-7.1a/P-7.1b、P-7.3 以及 A.4 未覆盖类的补证（或由 lead 明确把 P-7.2 收缩为“最小垂直原型”口径）。
