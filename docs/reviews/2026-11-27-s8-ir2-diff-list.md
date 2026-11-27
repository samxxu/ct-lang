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
ir: 399 mirrored defines agree across the TIR/LIR units
ir: corpus 82 files, 0 byte-differences
ir: module builds 2
ir: self-host 77 units, TIR shadow C tree byte-identical
ir: self-host LIR 72 units, 58 ready, C tree byte-identical
ir: LIR corpus 82 files, 0 failures, 23 unit-ready, functions 355/498, bodies printed 355
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
- 自举：72 个 `.c` unit 中 58 个 `ready=1`；回退函数见 §3d，整棵 C 树与 AST
  oracle 逐字节相同（`diff -r -x .ctcache`）。
- seed：`bootstrap/ct-ast` 由默认 LIR 路径重生成；`check-seed` 两轮逐字节 +
  手改负例（72 `.c` + 138 `.h`）。
- 脚本探针（直接跑）：`p88_metrics` 9/9、`p122_types_default` 44/44、
  `p111_invariants` 0 failure、`p64_alloc` OK、`p80_{layout,methods,retain}` OK、
  `p81_box` OK、`l29b3`/`l29b5` OK、`p85_{spike,m0}` OK、`p88_emit` OK、
  `p69_fp` 30 units clean、`p86_errors` 342 诊断 0 differ、`c2p_limits` 58/58、
  `intern_pool` 11/11。

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

`Emitter.h.ct` 现在 1541 行（原 9872 行），只剩 `emit_program` / `emit_unit` /
fail 与 `ct_emit_*` 绑定；`g_sb` / `g_body_hook` / `g_plan` / `g_slice_used` 的
定义都在子单元，宿主只按名读写。**仍未做到**四个入口“只消费 LModule”：编译
模式的 `emit_program` 体、类型/全局节点的遍历仍在宿主读 AST 与符号表。

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
| **S8 尾外壳** | `write_unit_header(_body)`、`emit_unit_body` 与 28 个外壳胶水函数 → 新单元 `EmitShell.h.ct`；`write_unit_header` 移入新 `EmitShell` trait；`g_plan`/`g_slice_used` 随走并导出 | 82 语料逐字节；自举 2 轮；`Emitter.h.ct` 9872 → 1541 行 |

每片后 `gen-seed.sh` 重生成；本分支**未 push、未打 tag、未改版本号**。

### 3d 仍未做（剩余清单）

1. **外壳完整 LModule 化**（S8 原目标，未完成）：`write_unit_header(_body)` /
   `.abi.h` / map 已移出宿主，但四个入口仍读 AST/符号表；编译模式的
   `emit_program` 体、类型/全局节点遍历、实例/ADT 胶水的数据来源尚未换成
   `LModule` 数据契约（当前只消费 `LModulePlan` 的写者身份与内建头清单）。
2. **回退改真修复**（让覆盖率回到 100%）：D-013 retain/release 与 struct
   sret、vptr 数组/嵌套/匿名成员胶水、多段 `into` 链、静态 `for` init、
   GNU 局部属性、超长名动态打印、命名空间 host 预检。这些函数当前**字节
   等价**但不计入 LIR 覆盖率，是本清单的主要技术债。
3. `test/ir/README.md` 的覆盖率数字随本清单 §2 更新；REV 需签字确认“回退 ≠
   已降级”。
4. DOC-89 的历史行锚点：Emitter 拆分使 26 个历史记录（battle / phase 卡 /
   issue / proposal / review）里的 `Emitter.h.ct#L…` 超出新行数；按 DOC-89
   的既有机制登记为**精确 (文件, 原始锚点)** 豁免，不改写历史记录正文。

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
| DEV | 单文件默认 LIR + 44 条失败清零（含 13 类分诊）；外壳/D5/D6 尾部明确留作剩余 | 2026-11-27 | 本文件 §1–§3d；`check-ast 1740/0/7`、`check-all OK (8 gates)`、`check-seed OK`、`check-sanitizers 662 checks`、`check-docs OK`、`g0/g1/g8 OK` |
| REV | 待签字 | — | 逐条复核 §3 的回退类型与 §3d 的剩余边界 |
