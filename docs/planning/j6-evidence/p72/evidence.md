# P-7.2 证据：S3 切片最小垂直原型（J-6）

| 项 | 值 |
| --- | --- |
| 任务 | J-6 证据 P-7.2（S3 切片最小垂直原型，A.4 全量） |
| 日期 | 2026-11-20 |
| 基线 | `dff5a0dfc0ee1698d538bf95d07ce39084b75b03`（主仓 HEAD） |
| 隔离副本 | `/tmp/p72`（`git clone` 基线；主仓源码未改） |
| 环境 | Darwin arm64；Apple clang 21.0.0（`arm64-apple-darwin27.2.0`）；`ct-ast v0.77.2` |
| 复现入口 | `bash evidence/p72/run.sh`（自举链 + 25 项断言 + 自举不动点） |
| 结果 | **25 passed, 0 failed**（退出码 0）；A.4 P-4.1 **10/10 放置类** |
| patch | `p72.patch`（相对 `dff5a0df`，含源码、夹具、runner、完整 `raw.log`）；当前基线重放见 §7 |

## 0. 判定摘要

- **P-4.1 放置矩阵 10/10**：字段、全局、接口值、box、Option、Result、容器（Vec/Map）、数组元素、泛型实参、闭包捕获，每类都有硬错与负例，诊断指向 `[` 或赋值位置。
- **P-4.2 嵌套泛型**：`Option<Option<int[]>>`、`Map<char *, Vec<int[]>>` 均在递归参数位置报红。
- **P-4.3 返回契约**：直接返回局部数组视图 lint；返回形参视图为正例。`as_str()`/字面量视图按 lead 指示留给 P-7.3，本证据不声称覆盖。
- **box 的限定**：`box<T>` 本身是 PH-81 的未来类型，本原型未实现其存储/句柄语义；只实现了 `box<int[]>` 的**解析期放置拒绝**（`box<int>` 会报 "not implemented"）。因此“放置硬错”通过，“box 存储语义”未覆盖（见 §6）。
- **J-6**：P-7.2 可按本证据判过；J-6 整体仍需 P-7.1a/P-7.1b、P-7.3，不能仅凭 P-7.2 升 A。

## 1. P-7.2 逐项

| 判据 | 结论 | 证据 |
| --- | --- | --- |
| `T[]` = `{ptr,len}` | 通过 | `struct __ct_slice`，arm64 `sizeof=16 align=8` |
| `T a[] = {...}` 仍为推断长度 C 数组 | 通过 | `pos_arrays_unchanged`、`pos_basic` |
| 数组→切片 | 通过 | `pos_basic`，`sizeof` 取推断长度 |
| `s.get(i)` 软访问 | 通过 | `pos_basic`：`get9=-1` |
| `s[i]` 读/写 + 越界 trap | 通过 | `pos_basic` 写回；`neg_trap` 运行退出 1 |
| `const T[]` 写硬错 | 通过 | `neg_const_write` |
| 构造越界硬错 | 通过（静态可判定部分） | `neg_subslice_oob`；未知长度走运行期 trap |
| 返回局部视图 lint | 通过（直接形态） | `neg_return_lint`，退出 0 + warning |
| `foreach` over slice | 通过 | `pos_basic`/`pos_param`/`pos_const` |
| C 数组行为不变 | 通过 | `pos_arrays_unchanged` |
| A.4 P-4.1 十类放置 | **通过 10/10** | 见 §3/§5 |
| 正例 ≥4、负例 ≥6 | 通过 | 6 正例 + 18 负例 |

## 2. 实现锚点

只改 `selfhost/ct-ast/**` 与 `selfhost/l2/core.ct` 的容量行；L0/L1 未改。

| 关注点 | 位置 |
| --- | --- |
| slice 符号元数据 | `Symbols.h.ct:176` |
| `[` `]` 前瞻 / slice 表达式判定 | `ParseSupport.h.ct:126`、`ParseSupport.h.ct:130` |
| 局部 / 形参 / 返回声明 | `Stmt.h.ct:3940`、`Parser.h.ct:1897`、`Parser.h.ct:1516` |
| 字段 / 全局 / 数组元素 | `Parser.h.ct:2176`、`Parser.h.ct:1623`、`Stmt.h.ct:4054` |
| 泛型实参（含嵌套） | `Expr.h.ct:2347`、`Expr.h.ct:7367` |
| Option / Result / Vec / Map | 同一泛型实参检查；负例 `neg_option`/`neg_result`/`neg_container_*` |
| 接口值（声明/赋值/其它 boxing） | `Stmt.h.ct:4340`、`Stmt.h.ct:4581`、`ParseSupport.h.ct:573` |
| box 放置拒绝 | `Expr.h.ct:1857`（parse_type）；`Stmt.h.ct:1708`、`Expr.h.ct:2965`（声明识别） |
| 闭包捕获 | `Expr.h.ct:954`（`closure_capture_add`） |
| `s[i]` / `get` / 子切片 | `Expr.h.ct:4525`；`Emitter.h.ct:5055` 起 |
| 返回 lint | `Stmt.h.ct:2297`；`Diag.h.ct:215`、`Diag.h.ct:544` |
| `{ptr,len}` + helpers | `Emitter.h.ct:2414` |
| L2 容量 | `selfhost/l2/core.ct:53`（`MAX_CALLS` 1024→4096） |

## 3. 用例矩阵

正例（6）：`pos_basic`、`pos_struct`、`pos_param`、`pos_subslice`、`pos_const`、`pos_arrays_unchanged`。

负例（18）：`neg_trap`、`neg_return_lint`、`neg_const_write`、`neg_subslice_oob`、
`neg_bad_init`、`neg_field`、`neg_global`、`neg_interface`、`neg_box`、
`neg_option`、`neg_result`、`neg_container_vec`、`neg_container_map`、
`neg_arrelem`、`neg_generic`、`neg_closure_capture`、`neg_nested_generic`、
`neg_nested_map`。

| 放置类 | 夹具 | 诊断（退出 1） |
| --- | --- | --- |
| 字段 | `neg_field` | `cannot be a struct field` |
| 全局 | `neg_global` | `cannot be a file-scope variable` |
| 接口值 | `neg_interface` | `cannot be stored in interface 'Show'` |
| box | `neg_box` | `cannot be stored in box<T>` |
| Option | `neg_option` | `cannot be a generic type argument` |
| Result | `neg_result` | `cannot be a generic type argument` |
| 容器 Vec | `neg_container_vec` | `cannot be a generic type argument` |
| 容器 Map | `neg_container_map` | `cannot be a generic type argument` |
| 数组元素 | `neg_arrelem` | `cannot be an array element` |
| 泛型实参 | `neg_generic` | `cannot be a generic type argument` |
| 闭包捕获 | `neg_closure_capture` | `cannot capture the slice 's'` |
| P-4.2 嵌套 | `neg_nested_generic` / `neg_nested_map` | `cannot be a generic type argument` |

## 4. 关键原始输出（完整输出见 patch 内 `evidence/p72/raw.log`）

```text
$ bash evidence/p72/run.sh
== bootstrap: L0 -> L1 -> L2 -> ct-ast ==
...
ct-ast: ct-ast v0.77.2
== self-host fixpoint ... ==
PASS  selfhost

neg_trap:        compile exit=0; run exit=1
                 stderr: ct: slice index 5 out of bounds (length 3)
neg_return_lint: exit=0
                 warning: slice escape: 'return' hands back a view of a local array

neg_interface:   exit=1  neg_interface.ct:13:14: error: a slice 'T[]' cannot be stored in interface 'Show'; it is a non-owning view
neg_box:         exit=1  neg_box.ct:7:12: error: a slice 'T[]' cannot be stored in box<T>; it is a non-owning view
neg_option:      exit=1  neg_option.ct:4:15: error: a slice 'T[]' cannot be a generic type argument; it is a non-owning view
neg_result:      exit=1  neg_result.ct:4:15: error: a slice 'T[]' cannot be a generic type argument; it is a non-owning view
neg_container_vec: exit=1 neg_container_vec.ct:4:12: error: ... cannot be a generic type argument ...
neg_container_map: exit=1 neg_container_map.ct:4:20: error: ... cannot be a generic type argument ...
neg_closure_capture: exit=1 neg_closure_capture.ct:7:1: error: a closure cannot capture the slice 's' (a view cannot outlive its array)
neg_nested_generic: exit=1 neg_nested_generic.ct:5:22: error: ... cannot be a generic type argument ...
neg_nested_map:  exit=1  neg_nested_map.ct:5:24: error: ... cannot be a generic type argument ...

== A.4 P-4.1 placement classes (10/10) ==
  field / global / interface / box / Option / Result / container /
  array element / generic actual / closure capture
  10/10 classes exercised; every one has a hard-error negative.

P-7.2 evidence: 25 passed, 0 failed
$ echo $?
0
```

## 5. 对照 A.4

| A.4 | 结论 | 依据 / 缺口 |
| --- | --- | --- |
| P-4.1 十类放置 | **通过（10/10）** | 每类 1+ 负例，硬错并带 `file:line:col`；box 为放置拒绝，非 box 存储实现 |
| P-4.2 复合递归 | **通过（嵌套泛型/Map）** | `Option<Option<int[]>>`、`Map<char *, Vec<int[]>>` 均红；字段/数组元素直接形态亦红 |
| P-4.3 返回值契约 | **部分通过** | 直接返回局部数组视图 lint、返回形参视图正例；`as_str()`/字面量视图按 lead 指示留给 P-7.3 |
| P-4.4 诊断质量 | **部分通过** | 声明/赋值/泛型/box 指向具体 `[` 或赋值列；闭包捕获与“非直接接口 boxing”只有行号（列 1） |
| P-4.5 残留风险 | **通过（文档化）** | 透传（调用结果、指针别名）由作者负责；`slice_escape` 沿直接赋值/子切片传播 |

## 6. 简化、限定与未覆盖

1. `T[]` ABI 是擦除元素类型/const 的 `{void *ptr; int len;}`；元素类型只在符号表，使用处 cast。
2. 只支持局部、形参、切片返回类型；字段/全局/泛型实参/数组元素/接口/box 是硬错；容器/闭包由同一检查覆盖。
3. **box**：`box<T>` 的存储/句柄语义未实现（PH-81）；只加了 `box<int[]>` 的解析期放置拒绝。最小补法：PH-81 实现时复用该检查点，并把 `box<int>` 从“not implemented”切换到真实类型。
4. 元素类型只实测 `int` 与具名 `struct`；数组/指针/typedef 别名元素、`char`/`Str`（S5）未支持。
5. 子切片编译期越界硬错只在基座是字面 `[N]` 且两端为整数字面量时触发；`T a[] = {…}`、slice 基座走运行期 trap。
6. `s[i]`/`s.get(i)` 基座必须是裸 slice 变量；`s.field[i]`、`f().get(i)` 未支持；`int[] s; s = a;` 未支持（`s = a[1..4]` 可以）。
7. `s[i]` 越界 helper 打印后 `exit(1)`；`get` 越界返回 0 指针，解引用由调用者负责。
8. `const T[]` 只是编译期标志，不进入 ABI。
9. 无借用/生命周期分析；`slice_escape` 只沿直接赋值/子切片传播，调用返回视图信任 callee 契约。
10. 接口/闭包检查覆盖直接表达式；`Vec<Show>.push(s)` 这类非直接 boxing 由 `ParseSupport::maybe_box` 兜底，位置只有行号。
11. **`selfhost/l2/core.ct` 的 `MAX_CALLS` 1024→4096**：L2 冻结自举编译器，slice 代码使 call-edge 表溢出；只改容量，不改语义，是 `ct-ast/**` 外唯一改动。
12. 未跑全量 `check-all`/corpus/ASan；只跑自举链、24 个夹具、自举不动点。
13. 未测 `ct check` 严格模式下的 lint 升级（本证据的返回 lint 是 compile 模式 warning，退出 0）。
14. 未测 build 模式下含 slice 的多单元工程；helper 按单元发射，跨单元 slice 形参头文件形状未验证。
15. 空 slice `{0,0}` 无显式构造语法；`len` 不是语言成员。
16. 数组形参不能作为 slice 来源（长度已丢失）；`int a[]` 局部/全局数组可用 `sizeof` 取推断长度。

## 7. 证据格式 E1–E5

- **E1**：命令、原始输出、退出码、基线 sha、环境见 §1–§4；完整输出在 patch 内 `evidence/p72/raw.log`；`run.sh` 退出 0。
- **E2**：锚点见 §2；**不利一条**：`box<T>` 本体未实现，A.4 的 box 类只证明了“放置拒绝”，没有 box 存储语义；P-4.3 的 `as_str()`/字面量视图未做。
- **E3 可证伪预测**：任一正例失败、任一放置负例退出 0 或缺诊断、trap 不非零、lint 无 `slice escape`，则 P-7.2 失败；本次均未出现。
- **E4 代价**：源码 9 文件（新增行数见 patch stat）；夹具 24 个 + runner + expected；`struct __ct_slice` 16 字节/align 8；helper 仅 slice 程序发射。
- **E5 失败时替代/收缩**：box 可降级为“PH-81 前只做放置拒绝”；闭包/接口的透传路径可降为契约 + lint（P-4.5）。

## 8. patch 与结论

- patch：`docs/planning/j6-evidence/p72/p72.patch`；应用：`git apply docs/planning/j6-evidence/p72/p72.patch`。
- 主仓本次只写 `docs/planning/j6-evidence/p72/evidence.md` 与 `p72.patch`（覆盖旧版），未改其他文件，未 commit、未 push、未打 tag。
- **A.4 P-4.1**：10/10 放置类有硬错负例；**P-4.2** 嵌套泛型/Map 通过；**P-4.3** 直接返回 lint 通过；**P-4.4/P-4.5** 部分/文档化。
- **P-7.2**：可按“A.4 放置矩阵 + get + 构造边界 + 返回 lint”判过；唯一限定是 box 存储语义未实现（放置拒绝已实现）。
- **J-6**：仍需 P-7.1a/P-7.1b、P-7.3（含 `as_str()`/字面量视图）才能整体升 A；P-7.2 本身可判通过。

## 7. rebase 到当前 HEAD（2026-11-20）

- 基线：`ca3354a5`（PH-78 收口复核，`v0.78.0`）。
- 方法：在 `dff5a0df` 上应用原 `p72.patch` 并提交，再 rebase 到 `ca3354a5`；唯一冲突是 `Parser.h.ct` 的 `parse_params`（PH-78 的 `ref/out` 与 P-7.2 的 slice 标注），已合并保留两者。
- 复现：`bash evidence/p72/run.sh` → **25 passed, 0 failed**（自举链 + 25 项断言 + A.4 放置 10/10）。
- 产物：[`p72-rebased-ca3354a5.patch`](p72-rebased-ca3354a5.patch)（仅 `selfhost/**`，8 文件，878+/14-）。
- 回归：`examples/01_greeter`、`05_body_dispatch`、`24_vec_ops`、`48_string_steps` 均编译通过，greeter 运行输出正常。
- 结论：P-7.2 可直接移植到 PH-79 当前基线；`evidence/` 目录不随主仓入库。
