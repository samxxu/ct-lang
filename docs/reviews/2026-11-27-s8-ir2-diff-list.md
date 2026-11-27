# v1-PH-2 S8 IR-2 差异清单（2026-11-27）

> 状态：**DEV 提交，待 REV 签字**。本清单是 E-V3-9「全语料等价或差异清单签字」的
> 证据表。S8r2 把**单文件编译路径**也切到 LIR 默认，并把 `--ir=on` 的 10 个
> known-gap / 44 条失败清零；不能证明等价的形状按函数或单元**保守回退**到 AST
> body writer，回退函数不冒充“已降级”，逐类列在 §3d。
> 对应 stage：[v1-PH-2 S8](../phases/v1-PH-2/card.md)；设计：[tir-lir-contract](../design/tir-lir-contract.md) §6–§7。

## 1 切换边界（S8r2 结论）

| 路径 | 默认 | 等价证据 |
| --- | --- | --- |
| `ct build`（多单元 / 自举 / seed） | **LIR 打印函数体** | 自举 C 树逐字节；82 语料 + 2 个模块工程逐字节；seed 两轮逐字节 |
| `ct <file>.ct`（单文件编译） | **LIR 打印函数体** | 82 语料、839 个 `test/ast/**` 可编译夹具逐字节；`check-ast` 全绿 |
| `--ir=off` / `CT_LIR=0` | AST→C oracle | 与切换前逐字节相同（一提交可回滚，§4） |

- 默认只在 `Module::build_main` / Driver 的编译入口生效；显式 `--ir=` 或 `CT_LIR`
  永远优先。
- 默认不会进入的路径（仍由 emitter 拥有，保持 AST）：map / model / ABI / `#line`
  / `.h.ct` / `.m.ct`、`--freestanding` / `--alloc`、`--runtime-checks`。
- 默认路径上 LIR/TIR 验证器报错时**静默回退**到 AST（不打印 `E-IR-*`），因此
  `check-ast` 的诊断与 AST oracle 逐字相同；`--ir=on`（显式）与
  `CT_LIR_STRICT=1` 仍是致命，供 `test/ir` 的负例使用。
- 自举 2 轮（tag 前 3 轮）与 seed 两轮逐字节；本轮未打 tag、未 push、未改版本号。

## 2 已证明等价的集合

```console
$ bash test/ir/run.sh ./ct-ast
ir: 400 mirrored defines agree across the TIR/LIR units
ir: corpus 82 files, 0 byte-differences
ir: module builds 2
ir: self-host 78 units, TIR shadow C tree byte-identical
ir: self-host LIR 73 units, 78 ready, C tree byte-identical
ir: LIR corpus 82 files, 0 failures, 80 unit-ready, functions 498/498, bodies printed 498
ir: LIR 7 fixtures, 0 failures
ir: LIR builds 2
ir: build defaults to LIR (lir: bodies printed=7 skipped=0)
ir: OK (82 corpus byte-identical, 4 TIR negatives, 6 LIR negatives, 7 LIR fixtures, 2 module builds, selfhost=1, 15 checks)
```

- 语料：`test/cases/*.ct` + `examples/*/*.ct`（82 个，方言演示除外），`--ir=on`
  与 `CT_LIR=0` 逐字节相同；S8 起新纳入的 10 个 owning/字段胶水样例也在内，
  known-gap 清单已删除。
- `test/ast/**`：839 个可编译 `.ct` 夹具逐个比较默认与 `CT_LIR=0`，0 差异；
  其余夹具的编译退出码相同。
- 自举：78 个 unit **全部 `ready=1`**、**1638/1638 个函数体**由 LIR 打印；
  整棵 C 树与 AST oracle 逐字节相同（`diff -r -x .ctcache`）。S8 尾的 20 个
  回退函数已全部转真 lowering，见 §3e。
- seed：`bootstrap/ct-ast` 由默认 LIR 路径重生成；`check-seed` 两轮逐字节 +
  手改负例（73 `.c` + 140 `.h`）。
- 脚本探针（直接跑）：`p88_metrics` 9/9、`p122_types_default` 44/44、
  `p111_invariants` 0 failure、`p64_alloc` OK、`p80_{layout,methods,retain}` OK、
  `p81_box` OK、`l29b3`/`l29b5` OK、`p85_{spike,m0}` OK、`p88_emit` OK、
  `p69_fp` 30 units clean、`p86_errors` 342 诊断 0 differ、`c2p_limits` 58/58、
  `intern_pool` 11/11。
- **S8 收尾（D-013 真 lowering 后复跑，seed 已重生成）**：`test/ir/run.sh` 15
  checks OK；82 语料 **498/498** 函数体、**80/80** unit `ready=1`、0 差异；
  自举 TIR shadow 78 units C 树逐字节；自举 LIR **1638/1638 个函数体、78/78
  ready 单元**、0 回退；`check-seed` 73 `.c` + 140 `.h` 两轮逐字节；`p88_metrics`
  9/9。

## 3 44 条失败的逐条分诊（清零）

S8r2 起点（文档记录值，`CT_LIR=1 CT_LIR_STRICT=1`）：

```console
$ CT_LIR=1 CT_LIR_STRICT=1 bash selfhost/check-ast.sh
== summary: 1696 passed, 44 failed, 7 skipped ==
```

终点：默认 LIR 的 `check-ast`：

```console
$ bash selfhost/check-ast.sh
== summary: 1740 passed, 0 failed, 7 skipped ==
```

`check-all` 8 门全绿；`check-seed` 两轮逐字节；`check-sanitizers` 662 checks、
无 sanitizer 报告；`check-docs` OK；`g0`/`g1`/`g8` OK。
分诊按**根因**归并，不逐夹具堆补丁：

| # | 根因 | 代表夹具 | 处置 | 类型 |
| --- | --- | --- | --- | --- |
| 1 | D-013 owning 胶水：by-value owning 形参/结果、owning 字段赋值/初始化、struct 局部 owning 字段 | 10 个 known-gap、`300`、`313`、`l29b3`、`l29b5`、`p80/*`、`p81/box` | lowerer 保守回退（`Lglue` / `Lownfield` / `Lglue*`） | 回退 |
| 2 | TIR/LIR 验证器假阳性 | `21_fnptr`、`p40_return_case`、`224_defer_branches`、`p122 b_void`、`generic_payload`、`two_dim` | 默认路径静默回退到 AST；显式/strict 仍红 | 回退 |
| 3 | 多段 `into` 链 | `157_into_chain`、`cap intos` | 单元级预判 `TK_INTO_TARGET`/`TK_INTO_SELF`，不建任何行直接走 AST | 回退 |
| 4 | 表达式 `match` 的 `__ct_mres` 占位名 | `302_adt_match_expr`、`l29b5` | 在 arm 任意位置识别占位名并降成 `LS_MATCHYIELD`（真修复） | 修复 |
| 5 | 函数指针返回 struct / 容器下标 | `170`、`171`、`176` | 空 `kids` 防护 + owning/field 回退；`171` 不再崩溃 | 修复 + 回退 |
| 6 | struct 局部 vptr / Handback / 数组、匿名成员 | `18`、`34`、`59`、`62`、`237`、`239` | 单元/函数级保守回退（`Lglue` / `_iface` 返回） | 回退 |
| 7 | `for (static …)` / 显式 GNU 局部属性 | `37_empty_stmt`、`56_header_compat` | 函数级回退（`Lstaticfor` / `Lattr`） | 回退 |
| 8 | 超长标识符/类型拼写（c2p 的 700–2000 字节） | `c2p/limits`、`c2n/intern` | 单元级 `LW_NAME_MAX=256` 检查，超过即 AST | 回退 |
| 9 | 命名空间 host 的 map 检查只在 emitter | `ns_host_no_map`、`p86/errors` | `TK_BOX` aux bit 2 回退，让 AST 报原文诊断 | 回退 |
| 10 | 逗号表达式的上下文括号 | `52_assign_value`、自举 `EmitHeader.c` | 按 `PW_INLINE` / `PW_EXPR` 复刻 AST 上下文（真修复） | 修复 |
| 11 | 闭包绑定 >64 触发 LIR 池 hard 失败 | `cap closure_bind` | 改为函数回退，由 emitter 报 “too many closure bindings” | 回退 |
| 12 | 其它输出/诊断 | `p85/p88` 语料 hash、`p69/fp`、`p86/errors`、`p111 I4` | 由上述等价性直接转绿；逐脚本复跑 | 验证 |
| 13 | 特殊模式（freestanding/alloc/runtime-checks/map/model/abi/line/hdr/map） | `p64_alloc`、map/model 夹具 | 默认不进入 LIR（保持 AST） | 边界 |

> 归因是 DEV 分诊结果，不是最终结论；REV 复核时以夹具的实际 diff 与
> `CT_LIR=0` 的对照为准。**“回退”不是“已降级”**：这些函数不计入
> `bodies printed`，也不计入 `ready=1`。

## 3b emitter 契约与 D4–D6 的边界（S8 尾已推进）

| 判定 | 原位置 | 现状 |
| --- | --- | --- |
| 内建层判活 | 文本扫描 | `backend/tir/TGraph.h.ct`（S8，已移） |
| 函数体生命周期 / 类型 / 临时名 | AST body writer | LIR writer（`ct build` 与单文件默认） |
| 内建头文件清单 | emitter 循环 | `LModulePlan.bhead[]`（已移） |
| `.abi.h` / map JSON | emitter | `EmitHeader.h.ct`（D4，已移） |
| 类型/全局声明、泛型实例闭包与胶水 | emitter | `EmitDecl.h.ct`（D5） + `EmitShell.h.ct`（外壳） |
| `write_unit_header(_body)` / `emit_unit_body` | emitter | `EmitShell.h.ct`（外壳，已移） |
| `emit_type_decl` / `emit_impls` / `em_decl_*` | emitter | `EmitDecl.h.ct`（D5 尾，已移） |
| `emit_expr` / `emit_node` / `emit_field` / `emit_inline` / `emit_outconv` / `em_*` | emitter | `EmitExpr.h.ct`（D6 尾，已移） |

`Emitter.h.ct` 现在 1590 行（原 9872 行），只剩 `emit_program` / `emit_unit` /
fail 与 `ct_emit_*` 绑定；`g_sb` / `g_body_hook` / `g_plan` / `g_slice_used` 的
定义都在子单元，宿主只按名读写。**S8 外壳收尾后**，三个产品入口
（`emit_program` / `emit_unit_body` / `write_unit_header_body`）已不再扫描 AST
或符号表来决定顶层顺序、include 块、函数原型与实例/胶水集合，见 §3f。

**2026-11-27 最终收尾已把上段剩余项清零**：map/model JSON 六段 / 三段与
九个写者的选择都已迁入 `LModulePlan` 行，见
[S8 最终收尾](2026-11-27-s8-closeout-lmodule.md)；§3d 第 1 条保留为历史记录。

### 3c 施工记录（S8/S8r2 + S8 尾）

| 片 | 交付 | 判据 |
| --- | --- | --- |
| S8 判活 + build 默认 | TGraph 判活、`ct build` 默认 LIR、差异清单 | 语料/自举逐字节；`test/ir` 15 checks |
| 外壳 LModule 第一步 | 写者身份 `g_shell_*` → `LModulePlan.shell_*`；走查状态入 `Emitter` | 单文件 + 自举 C 树逐字节 |
| D4 EmitHeader（部分） | `backend/emit/EmitHeader.h.ct`、`pub trait EmitHeader`；10 方法 + 自由函数 | body 多重集不变；cycles 0 |
| D5 EmitDecl（部分） | `EmitDecl.h.ct`；13 方法 + 3 自由函数 | 同上 |
| D6 EmitExpr（部分） | `EmitExpr.h.ct`；6 个无 kind 依赖 helper | 同上 |
| **S8r2 单文件默认 LIR** | Driver 编译入口默认 LIR；默认路径验证器静默回退；D-013/vptr/into/static/attr/长名/闭包容量保守回退；`match` 占位名与逗号上下文修复 | 82 语料 + 839 个 `test/ast` 夹具逐字节；`check-ast` 0 失败；`check-all` 8 门；seed 两轮 |
| **S8 尾 D6** | `emit_expr`/`emit_node`/`emit_field`/`emit_inline`/`emit_outconv` + 147 个 `em_*`/`sb_*`/`match_*`/`eb_*` 自由函数 → `EmitExpr.h.ct`；`StrRetain`/`FldSnap`/`EmitBuf`/`g_sb`/`g_body_hook`/`g_oc_bypass_node` 随走；`emit_gsub_type_text`/`emit_overload_suffix` 从 Decl 下调 | body 多重集不变（tool 仅 skeleton 差异）；82 语料逐字节；自举 2 轮 |
| **S8 尾 D5** | `emit_type_decl` + 六个 `em_decl_*` + `emit_impls` + 27 个实例/闭包/ADT 胶水函数 → `EmitDecl.h.ct`；`g_adt_layout_state`/`g_inst_layout_state` 随走 | body 多重集不变（仅 3 条宏 skeleton）；82 语料逐字节；自举 2 轮 |
| **S8 尾外壳** | `write_unit_header(_body)`、`emit_unit_body` 与 28 个外壳胶水函数 → 新单元 `EmitShell.h.ct`；`write_unit_header` 移入新 `EmitShell` trait；`g_plan`/`g_slice_used` 随走并导出 | 82 语料逐字节；自举 2 轮；`Emitter.h.ct` 9872 → 1545 行 |
| **S8 尾回退收窄** | 长文本预判跳过字符串字面量与 `#ct-raw` 载荷（9 个整单元回退消失）；指针局部不再走 by-value owning/vptr 预判；GNU 局部属性入 `LS_DECL.attr`；`for (static …)` 入 `LS_FOR.aux` 包裹块；owned 清理集改为表内顺序（parser 已反声明序注入），修正多个 `own`/`borrow` 的退出顺序 | 自举 1190/1622 → 1618/1638；82 语料 + `#56`/`#37`/`#62` 逐字节；新增 `c8`/`c9` LIR 夹具 |
| **S8 尾 shell 行** | `LModulePlan` 增 `ct_lshellrow` 行（PP / INCLUDE / TYPE / GLOBAL / SASSERT / FUNC / DROP / RAW）与 ABI 导出表；`emit_program`、`emit_unit_body`、`write_unit_header_body` 的类型/全局/断言/函数/ Drop 面改读行；`write_abi_header` 读 plan 的导出表 | 82 语料 + 自举 LIR/AST 逐字节；`test/ir` 15 checks；ABI 夹具 |

每片后 `gen-seed.sh` 重生成；本分支**未 push、未打 tag、未改版本号**。

### 3d 仍未做（剩余清单）

1. **外壳 LModule 化**：S8 外壳收尾迁完五项（§3f），最终收尾把 map/model
   JSON 与九个写者的选择迁完，见
   [S8 最终收尾](2026-11-27-s8-closeout-lmodule.md)。
2. **回退改真修复**（让覆盖率回到 100%）：D-013 owning 字段写
   （`Lownfield`，14 个自举函数）与 owning 句柄局部 / 参数 / 结果
   （`Lglue` 等，6 个）**已在 S8 收尾转为真 lowering**（§3e）；仍保留的函数级
   回退见 §3e.3（owning struct 的 `.` 字段写状态机、`ref`/`out` owning 形参、
   typedef 别名的 vptr 局部、视图返回、Box raw init、多段 `into`、超长名）。
3. `test/ir/README.md` 的覆盖率数字随本清单 §2 更新；REV 需签字确认“回退 ≠
   已降级”。
4. DOC-89 的历史行锚点：Emitter 拆分使 26 个历史记录（battle / phase 卡 /
   issue / proposal / review）里的 `Emitter.h.ct#L…` 超出新行数；按 DOC-89
   的既有机制登记为**精确 (文件, 原始锚点)** 豁免，不改写历史记录正文。

### 3e S8 收尾：D-013 真 lowering（2026-11-27）

S8 尾仍有 20 个函数级回退（14 `Lownfield` + 6 `Lglue`）。收尾把 D-013 §3 的
数据流搬进 LIR，**自举 1638/1638、语料 498/498**，0 回退、0 字节差异。

| 片 | LIR 机制 | 判据 |
| --- | --- | --- |
| owning 局部 | `lw_own_kind` 只认 `String` / `U16String` / owning 用户 ADT（容器走容器胶水，不持有）；无初值 `= { 0 }`；块尾与出口按表内顺序 `P_release(&x)` | 6 个 `lib/core` / `runtime` 句柄函数逐字节 |
| by-value owning 形参 | 入口 `name = P_retain(&name)`；impl 方法由 emitter 打 prologue、LIR 只登记释放；return / break / continue 的释放集一致 | `greet_name` / `person` / U16 工厂逐字节 |
| owning 结果 | `__ct_sretN` 物化；本地 move（跳过自身释放）不 retain；字段 / 全局 / 解引用 place 补 `__ct_sretN = P_retain(&__ct_sretN)`；`sflags&2`（借用根）强制 retain | `p80_retain/retain`、`jump`、`out_ref_owning` 探针 |
| 本地 rebind / 初始化 | `{ struct T __ct_soldN = x; x = [retain]rhs; P_release(&__ct_soldN); }`；`T y = <place>` 写 `P_retain(&(<place>))`；借用视图（container `get`）不持有 | `wordcount` / `map_literal` / `p80_retain` 逐字节 |
| struct raw init 字段 retain | `lw_rewrite_struct_init`：owning `String` / `U16String` 字段的字面量 → `str_dup_len(...)`，place → `P_retain(&(...))`；之后再由 vptr items 追加（顺序与 `emit_raw_init` 一致） | `generic_trait` / `generic_trait_instances` 逐字节 |
| 跳转清理 | `break` / `continue`：defer 清理 → 循环/switch 体内句柄释放 → 跳转（`sb_jump_release` 顺序） | `p80_retain/jump`、`c2_break` / `c3_continue` |
| match S5 | or-pattern（组条件 `(a) || (b)` + 三元绑定）、守卫（`__ct_matchedN` flag + `if (guard) { … }`）；表达式 match 的 `__ct_mresN` 与 flag 同号 | `examples/68_adt_guards` 5/5 且逐字节 |
| 修正 | 块表 `realloc` 后沿用旧指针导致 `ret_expr` 丢失（`return` 变 `return;`）；`lmod_temp_name` 的静态缓冲在嵌套打印中被覆盖；方法形参 retain 重复 | `nested_guard` / `68_adt_guards` |

**3e.1 复查命令**

```console
$ bash test/ir/run.sh ./ct-ast
ir: LIR corpus 82 files, 0 failures, 80 unit-ready, functions 498/498, bodies printed 498
ir: self-host LIR 73 units, 78 ready, C tree byte-identical
ir: OK (82 corpus byte-identical, 4 TIR negatives, 6 LIR negatives, 9 LIR fixtures, 2 module builds, selfhost=1, 15 checks)
$ bash selfhost/check-seed.sh
check-seed: OK (73 .c + 140 .h, two rebuild rounds byte-identical, hand-edit negative red)
```

**3e.2 语料 / 自举**：82 语料 + 78 unit 自举树的 C 与 AST oracle 逐字节相同；
`82 × 498` 个函数体全部由 LIR 打印（`printed == lowered`，`skipped=0`）。

**3e.3 仍保留的函数级回退（默认静默回退到 AST，`--ir=on` 下不再出现）**

| 形状 | 回退点 | 原因 |
| --- | --- | --- |
| owning struct 的 `.` 字段写 | `Lownfield` | `sb_field_*` 字段状态机（初始化 / `if` 合并 / 循环 unsafe / maybe 诊断）未搬入 LIR；保留 emitter 的 “field may be undefined” 硬错 |
| `ref` / `out` owning 句柄形参 | `Lrefown`（形参入口） | `param_own` 的 hold-old / retain / release-old 契约只做了本地 rebind |
| typedef 别名的 vptr / owning-field struct 局部 | `Lgluealias` | 别名没有 `struct <tag>` 拼写，vptr item 行写不进去 |
| `Str` / `U16Str` 视图作为 owning 返回值 | `Lviewret` | SH-106 escape 诊断路径仍归 emitter |
| `new T { … }` 的 owning 字段 raw init | `Lnewinit` | 与 decl raw init 同一改写未覆盖 `new` 载荷 |
| 多段 `into` 链 | `Linto`（单元级预判） | 未物化每段接收者 |
| >256 字节标识符 / 拼写 | `LW_NAME_MAX` | 打印器仍有有界 scratch 行 |

DEV 的 `test/ast` 逐字节探针（非门禁，882 个夹具）：**4 个仍有差异**
（`p106_str_escape/ret_u16str`、`p80_literal`、`p80_methods`、
`p80_retain/field_ptr`）。前 3 个是 hoist 接收者临时与 AST 的内联参数形状
不同（值语义相同，临时类型是 `U16Str` 视图，不持有引用）；`field_ptr` 只差
箭头字段写的 `{ … }` brace。其余形状已全部回退到 AST（0 差异、0 退出码差异）。
这些夹具的**行为**由 `check-ast` 兜底；本清单不把它们计作“已降级”。

## 3f S8 外壳收尾：LModule 行化 + `test/ast` 逐字节清零（2026-11-27）

### 3f.1 LModule 字段与迁移

`ct_lshellrow` 增加 `int hdr;`（0 = `.c` 写者消费，1 = `.h` 写者消费），新增
行种类与位置常量：

| 行 / API | 含义 |
| --- | --- |
| `LPS_INC` + `LINC_C_IO` / `LINC_C_PRE` / `LINC_C_POST` / `LINC_H_PRE` / `LINC_H_POST` | include 块逐行数据；`text` 为空串即空行，空行分组由模块层决定 |
| `LPS_PROTO` | 符号表函数行；`hdr` 选 `.c` 全量 / `.h` 导出 |
| `LPS_INPROTO` | `N_IMPL` 节点；pub 非模板 inherent 块的原型 |
| `LPS_INST` / `LPS_INSTPROTO` / `LPS_INSTHELP` | 实例闭包：结构外壳 / 元素原型 / 元素 helpers |
| `LPS_IMPL` | `node` = impl 行、`aux` = 实例行；模板方法（原型或定义） |
| `LPS_BOXPROTO` / `LPS_BOXHELP` | 内建 `Box<T>` 胶水 |
| `LPS_ADTLIFE` | owning ADT 的 `retain` / `release` |
| `LPS_STRPROTO` | 编译模式 `String` / `U16String` 入口声明（`aux` 1 = 胶水处重复的一份） |
| `lmod_plan_shell_add_stage(kind, unit, node, aux, hdr, text)` / `lmod_plan_row_hdr(i)` | 写带 `hdr` 的行 / 读 `hdr` |

迁移后的读者（原位置 → 现数据）：

| 判定 | 原读者 | 现数据 |
| --- | --- | --- |
| 编译/.c/.h 的 include 块（I/O、`<stddef.h>`、`CT_UNIT_PRIVATE`、自身头、deps、层头、空行） | `emit_unit_body` / `write_unit_header_body` 扫 AST + unit 表 | `LPS_INC` 行（§3f.1 位置） |
| 函数原型 | `for (fn_start..fn_end)` / `sym->nfunc` + `emit_proto` | `LPS_PROTO` 行 |
| inherent 原型 | `emit_inherent_protos(prog)` 扫 `N_IMPL` | `LPS_INPROTO` 行 |
| 实例闭包 | `emit_struct_insts` / `emit_struct_impls` 扫 `ct_insts` / `ct_impls` / `ct_tmpls` | `LPS_INST` / `LPS_IMPL` / `LPS_INSTPROTO` / `LPS_INSTHELP` 行 |
| Box 胶水 | 两个写者各扫一遍 `ct_insts` | `LPS_BOXPROTO` / `LPS_BOXHELP` 行 |
| ADT 胶水 | `emit_adt_life_defs` 扫 `ct_adts` + `adt_owns` | `LPS_ADTLIFE` 行 |

选择逻辑（`via_hdr`、foreign-element、instance helper 归属、Box 归属、ADT owns）
搬进 `frontend/module/Module.h.ct` 的 `ct_shell_plan_add_*` 系列；`EmitShell` /
`Emitter` 里对应的 AST/符号表兜底分支已删除。`write_map`（map JSON）未迁，
见 §3d。

### 3f.2 四个 `test/ast` 差异（清零）

| 夹具 | 差异 | 根因 | 修复 |
| --- | --- | --- | --- |
| `p106_str_escape/ret_u16str`、`p80_literal/literal`、`p80_methods/prog` | 多出 `struct U16Str __ct_tmpN = U16String_as_str(...)` | LIR 的 receiver-chain 把 **receiverless inherent static call**（`Node.aux == 11`，`a == -1`）的 `kids[0]`（第一个实参）当成 receiver 提升 | 链扫描排除 `aux == 11`；实参按 AST 的 type-host 规则内联 |
| `p80_methods/prog`、`p80_retain/field_ptr` | owning 句柄赋值少一层 `{ … }` | `sb_assign` 对 String / owning ADT 目标总是加 brace；LIR 只在 `__ct_sold` / retain 路径加 | `ct_lstmt.brace`：本地 tracked 目标或 plain struct 的 `->` 字段加 brace；deref 目标与泛型实例字段（`Box<String>.value`）保持无 brace |

逐字节探针（882 个 `test/ast/**/*.ct`，可编译 403 个）：

```console
$ CT_LIR=0 ct <f> -o a.c; ct <f> -o b.c   # 每个夹具
test/ast total 882 same 403 diffs 0 noncompile 479
```

### 3f.3 复查命令

```console
$ bash test/ir/run.sh ./ct-ast
ir: OK (82 corpus byte-identical, 4 TIR negatives, 6 LIR negatives, 9 LIR fixtures, 2 module builds, selfhost=1, 15 checks)
$ ct build --emit-c -I selfhost/ct-ast selfhost/ct-ast/main.ct -o <dir>
$ diff -r -x .ctcache bootstrap/ct-ast <dir>   # 无差异 = 自举不动点
```

## 4 回滚

| 回滚对象 | 动作 | 结果 |
| --- | --- | --- |
| 单文件默认切换 | `git revert <S8r2-commit>` | 单文件回到 AST；build 默认仍 LIR |
| 只要 AST oracle | `--ir=off` / `CT_LIR=0` | 与切换前逐字节相同 |
| 保守回退 | revert `Lower.h.ct` 的 `lw_spelling_*` / 预判块 | 回到“逐条差异”状态；语料不再保证逐字节 |
| seed | 随源码提交一并 revert | `check-seed` 两轮回到旧种子 |

## 5 签字

| 角色 | 结论 | 日期 | 依据 |
| --- | --- | --- | --- |
| DEV | S8 收尾：D-013 真 lowering（owning 局部/形参/结果/rebind/字段初始化/sret/跳转清理）+ S5 守卫与 or-pattern；自举 **1638/1638、78/78 ready**，语料 **498/498、80/80 ready**，0 字节差异；剩余 4 个 `test/ast` 探针差异见 §3e.3 | 2026-11-27 | 本文件 §1–§3e；`test/ir/run.sh` 15 checks OK；`check-seed OK`；`check-all` 8 门；`check-ast`、`check-sanitizers`、`check-docs`、`g1/g8` 见交付报告；源码 + seed 提交 `85f0f80f` |
| DEV | S8 外壳收尾：实例闭包 / ADT/Box 胶水 / header include-dep-shim / 函数原型（含 inherent）改为 `LModulePlan` 行；三个产品入口删除 AST/符号表兜底；4 个 `test/ast` 探针差异清零（882 夹具 0 差异）；语料 498/498、自举 1638/1638 与 C 树逐字节不变；剩余 map JSON 与 §3b 末段列出的写者选择 | 2026-11-27 | 本文件 §3f；`test/ir/run.sh` 15 checks；`check-all` 8 门；`check-seed` 两轮；`check-sanitizers`；`check-docs`；`g0/g1/g8` |
| REV | 复核通过：§3/§3e 回退类型、§3d 剩余边界、§3e.3 保留的 6 类函数级回退（另 >256 名为单元级）、§3f「行化 ≠ 只换读取位置」逐条核对；“回退 ≠ 已降级”成立；DOC-89 锚点豁免仅限已发生拆分的历史记录 | 2026-11-28 | 本文件 §3–§3f；`test/ir/run.sh` 15 checks、`check-goldens-ast` 25/25、`check-seed` 两轮、`check-docs` + `--selftest`、`g0/g1/g6/g8` OK |
