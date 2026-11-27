# SH-94 S1 方法级拆分：Core 布局与纯搬移记录（v1-PH-1）

> **v1-PH-1 S1 / SH-94 第二轮交付物**。第一轮把 host-free 纯函数搬进
> `ExprPure` / `EmitterQuery` / `EmitterMapText` / `StmtRangeScan` / `StmtScope`
> （见 [phase85 卡](../../docs/phases/v0-PH-85/card.md) 之后的第一轮提交）。
> 本轮处理**方法**：把 `pub struct` 与 trait 抽到 `<Subsystem>Core.h.ct`，再把整段
> `impl` 方法组搬到按职责命名的子单元。
> 判据依据：[D-017](../decisions/D-017.md) B1（接口可变、状态暴露、命名）、
> A3（函数体哈希集合不变）、A4（不新增环）、A1（两级逐字节）；
> 任务出处：[SH-94](../../issues/selfhost/sh94-giant-units-duplicate-constants.md)、
> [v1-PH-1 卡](../phases/v1-PH-1/card.md) S1。
> 机械验收：[tools/sh94_split_check.py](../../tools/sh94_split_check.py)。

## 1 为什么需要 Core

ct 的 `.h.ct` 是独立编译单元：宏不跨单元，方法调用经 `<Trait>_vtbl` 派发，
`impl` 的唯一性按 `(struct, trait)` 全局判。因此方法搬移只有一条安全形状：

1. 宿主类型 `pub struct X` 与它 `use` 的 trait 必须在**不含方法体**的单元里
   （Core），子单元 import Core 才有 `struct X *` 的完整布局与派发面；
2. 子单元持有**整段** `impl <Trait> for X`，宿主 import 子单元（`g_*` 静态实例
   的 vptr 初始化需要子单元头发布的 `extern ..._vtable`）；
3. 子单元不 import 宿主 → 不成环；宿主单向 import 子单元。

trait 必须是 `pub`：私有 trait 的 `_vtbl` 结构只写进**声明单元**的 `.c`，声明
搬到 Core 后，实现单元只剩前置声明，无法定义 vtable（实测 cc 报
`incomplete definition of 'struct ..._vtbl'`）。vtable 外部链接仍要求
"`pub` trait + `pub` struct" 同时成立。

## 2 布局

| Core（类型 + trait） | 行数 | 子单元（职责） | 行数 | 搬走的方法/函数 |
| --- | --- | --- | --- | --- |
| `frontend/parse/ExprCore.h.ct` | 459 | `ExprAdtCtor.h.ct`（ADT 构造语法） | 167 | `ExprAdt`：`adt_ctor_ahead`、`parse_adt_ctor` |
| | | `ExprNewObject.h.ct`（`new` 构造 + Box 自动解引用） | 264 | `ExprNew`：`Box_member_deref`、`new_ahead`、`parse_new_expr` |
| `frontend/parse/StmtCore.h.ct` | 195 | `StmtDefer.h.ct`（defer / errdefer / AutoDrop 释放） | 389 | `StmtDeferOps` 13 个方法 + `autodrop_append` |
| `backend/emit/EmitterCore.h.ct` | 248 | `EmitterTry.h.ct`（postfix `?` 支持） | 151 | `EmitterTryOps`：`try_result_tag`、`try_result_cols`、`try_cleanup`、`try_release_payload` |

- 新 trait：`StmtDeferOps`、`EmitterTryOps` 都是 `pub`，与 `StmtOps` / `EmitOps`
  并列在各自 Core 里；struct 的 `use` 子句按追加顺序登记。
- `ExprCore` 的 `ExprTraitInst` / `ExprTry` 由私有改 `pub`；`EmitterCore` 的
  `struct Emitter` 与 `EmitOps` 由私有改 `pub`（D-017 B1 允许）。后者的直接
  后果是生成头首次带 `FILE *out;`——单元保留 `#include <stdio.h>`，生成头复制
  单元的 include，因此仍可编译；编译器自身的 C 允许差异（D-017 A1 第 2 层）。
- 宿主的公开 API 不变：`expr_get` / `stmt_get` / `ct_emit_*` 的签名与行为不动。

## 3 纯搬移证据

函数体多重集与基线 `2f70c862` **完全一致**（1046 个函数体，逐字节）：

```console
$ python3 tools/sh94_split_check.py --baseline 2f70c862
sh94_split: 1046 bodies, multiset identical; 0 moved function(s) in place; skeletons mechanical

$ python3 tools/sh94_split_check.py --methods --baseline 2f70c862 \
    --skeleton-baseline <parent> \
    --map 'selfhost/ct-ast/frontend/parse/Expr.h.ct=ExprAdt:adt_ctor_ahead,parse_adt_ctor:selfhost/ct-ast/frontend/parse/ExprAdtCtor.h.ct'
sh94_split: 1046 bodies, multiset identical; 2 moved function(s) in place; skeletons mechanical
```

每个切片（提交）都单独复跑同一判据；`--skeleton-baseline` 取父提交，函数体
多重集始终对冻结基线，所以“骨架只动 import / `impl` 头 / 注释”和“函数体
一处没改”分别可判。

| 切片 | 搬移 | 产品单元 | 函数体多重集 |
| --- | --- | --- | --- |
| S1-1 | 无（只抽 Core） | 32 → 33 .c | 1046 一致 |
| S1-2 | `ExprAdt` 2 个方法 | 33 → 34 .c | 1046 一致 |
| S1-3 | `ExprNew` 3 个方法 | 34 → 35 .c | 1046 一致 |
| S1-4 | 无（只抽 StmtCore） | 35 → 36 .c | 1046 一致 |
| S1-5 | defer 13 个方法 + `autodrop_append` | 36 → 37 .c | 1046 一致 |
| S1-6 | 无（只抽 EmitterCore） | 37 → 38 .c | 1046 一致 |
| S1-7 | `?` 支持 4 个方法 | 38 → 39 .c | 1046 一致 |

生成物：

- **测试语料**（`test/probes/p85_corpus_sha.tsv`：25 个 `test/cases` + 45 个
  `examples/*/*.ct`，共 70 个 `.ct`；D-017 成文时记为 66 个，manifest 是 live 权威）
  逐字节不变；
  `bash selfhost/check-goldens-ast.sh` 25/25；
- **编译器自身**的发射 C 按 D-017 A1 第 2 层允许差异：单元集合 32 → 39 `.c`
  （+7：四个 Core 与三个方法子单元），发射 C 57158 → 57769 行；seed 按
  [gen-seed.sh](../../selfhost/gen-seed.sh) 重生成，`check-seed` 两轮逐字节且
  手改负例红；
- 导入图环数 0（`python3 tools/p85_inventory.py cycles`）。

## 4 剩余拆分计划（2026-11-25）

### 4.1 盘面

| 宿主 | 行数 | impl 区间 | 方法 |
| --- | --- | --- | --- |
| `Expr.h.ct` | 9510 | `ExprOps` 1740–8139；`ExprSubscript` 8140–8241；`ExprOptional` 8242–8448；`ExprTraitInst` 8449–8586；`ExprRecvMut` 8587–8624；`ExprTypes` 8625–9342；`ExprTry` 9343–9438；`ExprBinding` 9439–9510 | `ExprOps` 64（顶 `MAX_METHODS`）+ 7 个小 trait |
| `Stmt.h.ct` | 5307 | `StmtOps` 1167–5307 | 38 + 28 个 host-free |
| `Emitter.h.ct` | 10749 | `EmitOps` 7280–10749 | 56 + 201 个 host-free（含 76 个 `em_*`） |

### 4.2 Phase A：Expr 的 7 个小 trait（低风险，先做 spike）

| 片 | 新单元 | trait | 方法组 | 约行数 |
| --- | --- | --- | --- | --- |
| A1 | `frontend/parse/ExprTypes.h.ct` | `ExprTypes` | `chk_type` / `chk_assignable` / `chk_mcall_args` / `chk_callptr_args` / `chk_brace_init` / `slice_view_from_array` / `lit_coerce` 等 7 | 718 |
| A2 | `ExprSubscript.h.ct` | `ExprSubscript` | `custom_index_label` / `custom_index_method` | 102 |
| A3 | `ExprOptional.h.ct` | `ExprOptional` | `opt_suffix_kind` / `opt_field` / `opt_subscript` / `opt_lvalue_check` / `opt_result_ok` | 207 |
| A4 | `ExprTraitInst.h.ct` | `ExprTraitInst` | `parse_trait_inst_type` | 138 |
| A5 | `ExprRecvMut.h.ct` | `ExprRecvMut` | `recv_mut_check` | 38 |
| A6 | `ExprTry.h.ct` | `ExprTry` | `q_suffix_ahead` / `result_tag` / `result_cols` 等 3 | 96 |
| A7 | `ExprBinding.h.ct` | `ExprBinding` | `binding_convert` | 72 |

A1 是 spike：先验证“子单元只 import Core、宿主 import 子单元、跨 trait 调用可解析”的形状；
通过后 A2–A7 照抄。

### 4.3 Phase B：拆 `ExprOps`（约 6.4k 行）

`ExprOps` 按职责拆 5 个新 trait，**`ExprOps` 只保留表达式文法**：

| 片 | 新 trait | 方法组 | 约方法数 |
| --- | --- | --- | --- |
| B1 | `ExprCallCheck` | `record_call` / `arity_check` / `map_arity` / `argtype_check` / `argtype_check_static` / `argtype_mismatch` | 6 |
| B2 | `ExprClosure` | `type_is_fnptr` / `type_is_void_ptr` / `formal_is_env_fn` / `arg_is_closure` / `closure_arg_count` / `closure_arg_check` / `map_closure_check` / `decl_type_compat` / `parse_closure` / `closure_bind` / `closure_arg_bind` | 11 |
| B3 | `ExprInstantiate` | `inst_make` / `inst_register_nested` / `generic_instance` / `inst_inherent_method` / `inst_static_method` / `static_call_ahead` / `inst_subst_type` / `container_elem_foreign` / `container_vptr_type` / `container_iface_ptr` | 10 |
| B4 | `ExprTypeParse` | `is_type_word` / `type_append` / `parse_type` / `parse_inst_type` | 4 |
| B5 | `ExprStaticType` | `static_ctype` / `ctype_expand` / `fnptr_ret` / `peel_ptr` / `container_init_check` / `container_global_init_check` / `container_subscript_kind` / `container_write_check` / `container_addr_check` / `brace_arg_ok` / `parse_array_dims` / `next_is_type_name` / `tok_is_type_name` / `offsetof_ahead` / `fnptr_field` / `const_ok` | 16 |
| — | 剩余 `ExprOps` | `parse_expr` / `into_tail` / `into_block` / `into_member_check` / `parse_bitor`…`parse_primary` / `parse_args` / `parse_qual_path` | 约 17 |

顺序 B1 → B2 → B3 → B4 → B5。若某两组存在双向调用（如 `ExprStaticType` ↔ `ExprInstantiate`），
先把两组放同一片，或把共用方法留在 `ExprOps`，**不允许造环**。

### 4.4 Phase C：拆 `StmtOps`（5.3k 行 / 38 方法）

| 片 | 新 trait | 方法组 | 方法数 |
| --- | --- | --- | --- |
| C1 | `StmtMatch` | `match_ahead` / `parse_match` / `expr_match_ahead` / `parse_match_expr` | 4 |
| C2 | `StmtLoop` | `loop_ahead` / `parse_loop` / `foreach_ahead` / `parse_foreach` / `range_init_ahead` / `parse_range_init` | 6 |
| C3 | `StmtSwitch` | `parse_switch_body` / `parse_case_value` / `parse_label` / `label_ahead` / `label_find` / `parse_named_label` / `parse_goto` | 7 |
| C4 | `StmtControl` | `missing_return_check` / `stmt_terminates` / `body_has_jump` / `func_begin` / `func_end` | 5 |
| C5 | `StmtUninit` | `u_reset` / `u_add` / `u_mark_lvalue` / `u_scan` / `uninit_check` / `del_base` / `del_take` | 7 |
| — | 剩余 `StmtOps` | `is_decl_start` / `parse_block` / `parse_stmt` / `parse_branch` / `parse_decl_node` / `parse_expr_stmt_node` / `string_raw_write_check` / `closure_global_init` | 约 8 |

顺序 C1 → C2 → C3 → C4 → C5。

### 4.5 Phase D：Emitter（分两段，避免与 IR 重复劳动）

**IR 前（S1a-1）只拆稳定组：**

| 片 | 新 trait | 方法组 |
| --- | --- | --- |
| D1 | `EmitHoist` | `expr_unstable` / `hoist_rvalue` / `hoist_scan` / `emit_hoists` / `hoist_expr` |
| D2 | `EmitInvariant` | `invariant_check` / `invariant_scan` / `invariant_edge` / `invariant_temp_check` |
| D3 | `EmitInit` | `emit_raw_init` / `emit_range_init` / `emit_brace_init` / `emit_map_brace_init` |

**IR 后（S8 之后）按 `LModule` 新形状再拆：**

| 片 | 候选 trait | 方法组 |
| --- | --- | --- |
| D4 | `EmitHeader` | `write_unit_header` / `emit_struct_fwd` / `emit_trait_range` / `emit_proto` / `emit_vtable_fwd` / `header_guard` / `write_map` / `write_model` / `emit_json_str` / `write_header` / `write_abi_header` |
| D5 | `EmitDecl` | `emit_type_decl` / `emit_global_decl` / `emit_global_extern` / `decl_is_pub` / `emit_inherent_protos` / `emit_trait_decls` / `emit_impls` / `emit_maps` / `emit_unit_init` / `emit_link_externs` / `vtable_exported` / `map_vtable_exported` / `unit_has_drop_impl` / `drop_visible` / `node_mentions` |
| D6 | `EmitExpr` | `emit_node` / `emit_field` / `emit_inline` / `emit_type_name` / `emit_type_name_dims` / `emit_expr` / `emit_outconv` / `emit_ref_arg` / `emit_value_for` / `emit_cond` / `emit_indent` |

`emit_program` / `emit_unit` / `fail` / `fail_from` 留在 `EmitOps` 作入口。

**施工状态（2026-11-27，S8 尾）**：D4 已落 10/11 方法 + 依赖自由函数
`adoption_default_only` 到 `backend/emit/EmitHeader.h.ct`；D5 全部落盘
（`emit_type_decl` + 六个 `em_decl_*` + `emit_impls` + 实例/闭包/ADT 胶水
27 个自由函数）到 `EmitDecl.h.ct`；D6 全部落盘（五个分发器 + 全部
`em_*` / `sb_*` / `match_*` / `eb_*` 切片）到 `EmitExpr.h.ct`。
`write_unit_header(_body)`、`emit_unit_body` 与外壳胶水（Box / ADT
生命周期 / 字面量 / 实例方法）落到新单元 `EmitShell.h.ct`；
`Emitter.h.ct` 从 9872 行降到 1623 行，只剩 `emit_program` / `emit_unit` /
fail、shell 行的消费与 `ct_emit_*` 绑定。写者身份由 `LModulePlan.shell_u` / `shell_header`
提供；`g_sb` / `g_body_hook` / `g_plan` / `g_slice_used` 的定义已移入子单元，
宿主只按名读写，不再自己判定。S8 尾把 PP / 类型 / 全局 / 断言 / 函数的顶层判定搬进 `LModulePlan` 的 shell 行，
`emit_program` / `write_unit_header_body` / `write_abi_header` 读行渲染；实例闭包、
ADT 胶水与 map JSON 仍读符号表，“只消费 LModule”未完成，见
[S8 差异清单 §3d](../reviews/2026-11-27-s8-ir2-diff-list.md)。

### 4.5.1 D1–D3 施工单（S1a-1 内，IR 之前）

**执行顺序：D2 → D1 → D3**（编号不变；先自包含组，再跨 trait 调用组）。

| 片 | 方法（定义行） | 约行数 | 新单元 | 对外调用 |
| --- | --- | --- | --- | --- |
| D2 `EmitInvariant` | `invariant_edge` 10261 / `invariant_scan` 10304 / `invariant_check` 10392 / `invariant_temp_check` 10478 | 263 | `backend/emit/EmitInvariant.h.ct` | 组内互调；由 host `emit_unit` 调用 |
| D1 `EmitHoist` | `expr_unstable` 7285 / `hoist_rvalue` 7319 / `hoist_scan` 7341 / `emit_hoists` 7449 / `hoist_expr` 7529 | 243 | `backend/emit/EmitHoist.h.ct` | 调用留在 `EmitOps` 的 `emit_indent`（7302–7318）与 `emit_expr` |
| D3 `EmitInit` | `emit_raw_init` 7982 / `emit_range_init` 8050 / `emit_brace_init` 8086 / `emit_map_brace_init` 8113 | 159 | `backend/emit/EmitInit.h.ct` | 调用 `emit_expr` / `emit_brace_init` 组内 |

每片固定六步：

1. **Core**：在 `EmitterCore.h.ct` 增 `pub trait <Name> { … }`，把这组声明从 `EmitOps` 移出；
   把新 trait 追加到 `pub struct Emitter` 的 `use` 列表（与 `EmitOps` / `EmitterTryOps` 并列）；
2. **子单元**：新建 `backend/emit/<Name>.h.ct`：
   `namespace backend::emit; import backend::emit::EmitterCore; impl <Name> for Emitter { … }`；
   只 import Core，不 import 宿主；
3. **宿主**：`Emitter.h.ct` 删除被搬走的方法体，加 `import backend::emit::<Name>;`
   （`g_emitter` 的 vptr 初始化依赖子单元头 `extern` 发布的 vtable）；
4. **静止检查**：`python3 tools/p85_inventory.py cycles` 必须仍为 0；单元名全局唯一；
5. **判据**：`tools/sh94_split_check.py --methods --baseline 2f70c862 --skeleton-baseline <parent> --map …`
   函数体多重集不变；`check-goldens-ast.sh` 25/25；`check-ast.sh` fixpoint；
6. **seed 与提交**：`gen-seed.sh` + `check-seed.sh` 两轮逐字节；单提交
   `refactor(sh94-d2): 拆 EmitInvariant 方法组`（D1/D3 同形）。

**跳过条件**：若某组在 S1b 设计时被 LIR 判定为整体消失（例如 invariant 被验证器替代），
则记录“D-x 取消”并把该组从 D4–D6 一并删除；不允许先拆再删。

### 4.6 每切片判据

```sh
python3 tools/sh94_split_check.py --methods --baseline 2f70c862 \
  --skeleton-baseline <parent> \
  --map 'selfhost/ct-ast/frontend/parse/Expr.h.ct=ExprTypes:<methods>:selfhost/ct-ast/frontend/parse/ExprTypes.h.ct'
bash selfhost/check-goldens-ast.sh          # 25/25
bash selfhost/check-ast.sh                  # fixpoint + 门禁
python3 tools/p85_inventory.py cycles       # 必须 0
bash selfhost/gen-seed.sh && bash selfhost/check-seed.sh
```

- `--baseline 2f70c862` 是函数体多重集冻结基线；`--skeleton-baseline` 取父提交；
- 每片一个提交，独立回滚；行号随切片漂移，每片以父提交重新取区间。

### 4.7 风险

| 风险 | 应对 |
| --- | --- |
| 跨 trait 调用需要额外 import，可能成环 | A1 先 spike；`p85_inventory.py cycles` 必须 0；双向调用组合并 |
| `pub` trait/struct 的 vtable 可见性 | 沿用本轮规则：`pub trait` + `pub struct`；新 trait 必须 `pub` |
| 宿主 import 子单元顺序导致 vptr 初始化缺失 | 宿主单向 import 子单元；子单元头 `extern` 发布 vtable |
| `MAX_METHODS` 仍挡新增方法 | S1a-0 先放开；方法组拆分本身也会先降下来 |
| Emitter 拆完又被 LIR 重写 | D1–D3 先做，D4–D6 等 S8 后按新形状做 |
| 行数/方法数估算偏差 | 以每片实测 `sh94_split_check.py` 与 `wc -l` 记录，不按估算验收 |

## 5 回滚

每个切片一个提交；回滚一个方法组 = revert 该提交（子单元消失、宿主恢复整段
`impl`），再按 [gen-seed.sh](../../selfhost/gen-seed.sh) 重生成 seed。Core 的
提交也可单独 revert（方法定义仍在宿主，Core 只是声明所在单元）。seed 是源码
集合的派生物，回滚源码切片时必须一并重生成，判据仍是 `check-seed` 两轮逐字节。
