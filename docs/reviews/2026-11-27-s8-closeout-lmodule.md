# v1-PH-2 S8 最终收尾：LModule 行化收口（2026-11-27）

> 状态：**DEV 提交，待 REV 签字**。本文清掉
> [S8 IR-2 差异清单](2026-11-27-s8-ir2-diff-list.md) §3b 末段与 §3d 第 1 条的
> 剩余项：`write_map` / `write_model` 的 JSON 六段 / 三段，以及九个写者的
> **选择**（`emit_struct_fwd`、`emit_trait_decls/range`、`emit_vtable_fwd`、
> `emit_link_externs`、`emit_impls`、`emit_maps`、`emit_generic_defs`、
> `emit_unit_init`、`emit_string_literals`）。
> 对应 stage：[v1-PH-2 S8](../../docs/phases/v1-PH-2/card.md)；契约：
> [tir-lir-contract](../../docs/design/tir-lir-contract.md) §6。
> 本分支**未 push、未打 tag、未改版本号**。

## 1 结论

| 项 | 结果 |
| --- | --- |
| map JSON 六段 | traits / structs / functions / impls / calls / maps 全部由 `LModulePlan` 行驱动；写者零 `sym` / `arena` 读 |
| model JSON 三段 | structs(+fields) / enums(+members) / functions(+params) 同上 |
| 九个写者选择 | 每处一行 `LPS_*` 行表；写者只遍历行并渲染选中的行 |
| 四个产品入口 | `emit_program` / `emit_unit_body` / `write_unit_header_body` / `write_map`（`write_model` 同）的选择不再扫 AST/符号表 |
| 等价 | 82 语料、403 个可编译 `test/ast` 夹具、7 个模块工程、`--lib`、自举 C 树：map/model/C 逐字节不变 |
| seed | 重生成后两轮逐字节 + 手改负例红（`check-seed`） |

## 2 map / model：行表与 API

`backend/lir/LModule.h.ct` 新增一张与 shell 行分开的表（`LModulePlan.mrows`）：

```console
struct LMapRow { int kind; int unit; int parent; int line; int a; int b;
                 const char *t1..t5; }
```

`LMP_*` 共 15 种：一个 JSON 记录一行，嵌套列表（trait 方法、struct uses、
map bindings、model 字段 / 枚举成员 / 函数形参）用 `parent` 指向父行。
API：`lmod_map_plan_reset` / `lmod_map_plan_add` / `lmod_map_plan_count` /
`lmod_map_plan_row`；空串不进 interning 池（不改变 `intern_pool` 计数）。

选择在 **module 层**，两处 builder 就在写者调用前：

| builder | 位置 | 覆盖的选择 |
| --- | --- | --- |
| `ct_map_plan_build` | `frontend/module/Module.h.ct` | 单元范围 `tr_start/tr_end`、`fn_start/fn_end`、`call_start/call_end`；prog 的 `N_STRUCT` / `N_IMPL`；`maps[]` 的 `is_binding` / `is_static` / `unit` / shim；静态 recipe 的 callee 文本 |
| `ct_model_plan_build` | 同上 | prog 的 `N_STRUCT` / `N_UNION` / `N_ENUM`（`aux & 2` 跳过）、内建单元节点跳过、容器名白名单、函数名前缀白名单 |

写者（`EmitHeader.h.ct` 的 `write_map` / `write_model`）只剩 `path` /
`version` / `no_write` 与 JSON 转义；`self->sym`、`self->arena`、`self->units`
在这两个函数体内**零出现**（`p88_metrics` 之外另以脚本断言过）。

## 3 九个写者的选择

| 写者 | 新行 | 选择谓词（现位置） | 打印仍读 |
| --- | --- | --- | --- |
| `emit_struct_fwd` | `LPS_STRUCTFWD` | `ct_shell_plan_add_surface` | `sym->structs[si].name` |
| `emit_trait_decls`（原 `range`） | `LPS_TRAITDECL` + `hdr` | 同上：compile 全量 / `.c` 非 pub / `.h` pub；`is_static` / `ntparams` 过滤 | `sym->traits[t]` |
| `emit_vtable_fwd` | `LPS_VTBLFWD` / `LPS_DROPPROTO` / `LPS_HANDBAK` | `ct_vtable_exported`、`ct_adoption_default_only`、PH-48 D48-2 的 static/owner/extern 四态 | `sym->structs[si].name` |
| `emit_link_externs` | `LPS_LINKEXTERN` | 同上 + `ct_map_vtable_exported` | trait / struct 名 |
| `emit_impls` | `LPS_IMPLDEF` aux 1/2/3 | trait impl / inherent-ADT impl / 全默认 `use` 展开的结构 | 选中 `N_IMPL` / `N_STRUCT` 节点 |
| `emit_maps` | `LPS_MAPDEF`（`aux` = vtable 导出） | 单元 + 非 static + 非 binding | `maps[i]` |
| `emit_generic_defs` | `LPS_GINIT` | `owner == u` 且函数体 >= 0 | `sym->ginsts[i]` |
| `emit_unit_init` | `LPS_UNITINIT` | `ct_unit_init_needed`（同 `unit_init_needed` 谓词，module 侧复刻） | 选中 `N_GLOBAL` 节点 |
| `emit_string_literals` | `LPS_STRLIT` | `N_STR` + `aux == 1`（全 arena，按产品单元过滤） | 选中 `N_STR` 节点 |

`emit_trait_range(start, end, mode)` 从 `EmitHeader` trait 删除；两处调用
改为 `emit_trait_decls()`，由 `LModulePlan.shell_u` / `shell_header` 选行。

**边界（有意保留）**：本片迁的是“**选择**”，不是“拼写”。写者在选中行之后
仍读该行的符号 / AST 内容来打印（与既有 `LPS_PROTO` / `LPS_TYPE` 同一口径）；
函数体仍由 LIR 打印，未覆盖形状按 §3e.3 回退 AST。这与
“emitter 不再做类型/实例化/生命周期**判定**”不冲突，也不把回退计成已降级。

## 4 四入口边界与仍未迁的写者

| 入口 | 选择 | 说明 |
| --- | --- | --- |
| `emit_program` | 行 | PP / 类型 / 全局 / 断言 / 函数 / 原型 / 外壳行 |
| `emit_unit_body` | 行 | 同上 + 实例闭包 / ADT-Box 胶水 / include 块 |
| `write_unit_header_body` | 行 | 导出类型 / 全局 / Drop / include / 原型 |
| `write_map`（+`write_model`） | 行 | 本片新迁，六段 / 三段 |

仍未迁（不在本片清单，原样保留）：

- `write_abi_header`：导出集的**选择**已在 plan（`LPS` 之外），但拼写仍读
  `sym->funcs` 与 `units[root]`；ABI 头不是四个产品入口之一。
- `emit_drop_defs` 的 Drop 体选择仍扫 `sym->nstructs` + prog 的 `N_IMPL`
  （`EmitDecl.h.ct` 的 `emit_drop_defs` 段）；它属 D2 尾的寿命判定，不在本片
  九项内。
- `emit_map_prologues` 仍按 units / shim 组装 map 单元的 include 序（模块表，
  非 AST/符号表）。
- body writer 的节点内容读（设计如此，见 §3 边界）。

## 5 等价证据（原始输出）

基线 = 改动前的冻结 seed（`ct-ast v1.1.0`，`bootstrap/ct-ast` 与 HEAD 源码
逐字节一致）；新 = 用该 seed 从本分支源码 emit 后 `cc` 出的编译器。

```console
$ # 82 语料（--emit-map / --emit-model / C）
corpus=82 diffs=0
$ # test/ast 全部 882 个夹具：403 个可编译，map/model/C 三份都逐字节
compilable=403 same=403 diffs=0
$ # 7 个模块工程（split / autodrop / map_unit / map_unit_type / map_ns /
$ # map_unit_shim / foreach）：C 树 + map + model
split rc=0/0 C=same map=same model=same
autodrop rc=0/0 C=same map=same model=same
map_unit rc=0/0 C=same map=same model=same
map_unit_type rc=0/0 C=same map=same model=same
map_ns rc=0/0 C=same map=same model=same
map_unit_shim rc=0/0 C=same map=same model=same   # shim JSON 段
foreach rc=0/0 C=same map=same model=same
$ # --lib（map / model / 产品树）
seed=0 / new=0 / map same / model same / tree same
$ # 自举：新编译器 emit 自身 vs seed emit 同一份源码
C fixpoint / map same / model same
$ bash test/ast/p88_metrics.sh <new>
p88metrics: 9 passed, 0 failed          # pin: emitted C 94195 -> 94941
$ bash selfhost/check-seed.sh
check-seed: OK (73 .c + 140 .h, two rebuild rounds byte-identical, hand-edit negative red)
```

`p88_metrics` 的 pin 已随本片更新（仅“编译器自身发射 C 行数”，用户语料不变）。

## 6 回滚

源码与 `bootstrap/**` 分两个提交：revert seed 提交回旧种子；revert 源码提交
回旧 emit 路径。两个提交都独立，无版本号 / tag / issue 变更。

## 7 签字

| 角色 | 结论 | 日期 | 依据 |
| --- | --- | --- | --- |
| DEV | map/model 六段三段 + 九处写者选择迁 `LModulePlan`；四入口选择不再扫 AST/符号表；全语料/夹具/模块/自举逐字节 | 2026-11-27 | §5 原始输出；`check-all` 8 门、`check-seed`、`check-sanitizers`、`check-docs`、`g0/g1/g8` |
| REV | 待签字 | — | 逐条复核 §2 行表与 §3 的选择谓词、“选择迁 ≠ 拼写迁”的边界与 §4 剩余清单 |
