# v1-PH-2 S8 IR-2 差异清单（2026-11-27）

> 状态：**DEV 提交，待 REV 签字**。本清单是 E-V3-9「全语料等价或差异清单签字」的
> 证据表：能证明等价的集合已切换默认，不能证明等价的集合保留 AST 默认并逐条登记。
> 对应 stage：[v1-PH-2 S8](../phases/v1-PH-2/card.md)；设计：[tir-lir-contract](../design/tir-lir-contract.md) §6–§7。

## 1 切换边界（本轮结论）

| 路径 | 默认 | 等价证据 |
| --- | --- | --- |
| `ct build`（多单元 / 自举） | **LIR 打印函数体** | 自举 3 轮逐字节；79 语料 + 2 个模块工程逐字节；seed 两轮逐字节 |
| `ct <file>.ct`（单文件编译） | AST（`--ir=on` 可选） | 本清单 §3 的差异未清零，故不切换 |
| `--ir=off` / `CT_LIR=0` | AST oracle | 一提交可回滚（本文件 §4） |

- 默认只在 `Module::build_main` 入口生效；显式 `--ir=` 或 `CT_LIR` 永远优先。
- 自举 3 轮：seed → 编译器 → 再发射自身 → 逐字节；见 §2 的命令与输出。
- 单文件路径不切换不是遗漏：`--ir=on` 在这 37 个夹具上仍有差异（§3，38 条断言），
  切换会破坏 `check-ast` 门禁；登记后由 S8 后续切片逐条清零。

## 2 已证明等价的集合

```console
$ bash test/ir/run.sh ./ct-ast
ir: 399 mirrored defines agree across the TIR/LIR units
ir: corpus 79 files, 0 byte-differences
ir: module builds 2
ir: self-host ... TIR shadow C tree byte-identical
ir: self-host LIR ... C tree byte-identical
ir: LIR corpus 79 files, 0 failures, 79 unit-ready, functions 299/299, bodies printed 299
ir: OK (79 corpus byte-identical, 4 TIR negatives, 6 LIR negatives, 7 LIR fixtures, 2 module builds, selfhost=1, 13 checks)
```

- 语料：`test/cases/*.ct` + `examples/*/*.ct`（79 个，方言演示除外）；
- 自举：`selfhost/ct-ast/main.ct` 的 74 个单元、全部函数体由 LIR 打印；
- seed：`bootstrap/ct-ast` 由 LIR 默认路径重生成，且与 `CT_LIR=0` 的 AST 产物
  `diff -r` 只差 `.ctcache/`（即逐字节相同）。
- 自举 3 轮（tag 前口径，本轮未打 tag）：seed 编译出 `ct1` → `ct2` → `ct3`，
  每轮重新发射 `selfhost/ct-ast` 的 C；`round1/2/3 identical` 三行均通过。

## 3 单文件路径剩余差异（38 条断言，AST 默认）

复现：

```console
$ CT_LIR=1 CT_LIR_STRICT=1 bash selfhost/check-ast.sh
...
== summary: 1697 passed, 38 failed, 6 skipped ==
```

| # | 类别 | 代表夹具 | 现象 | 初步归因 |
| --- | --- | --- | --- | --- |
| 1 | 降级丢语句 / 临时名 | `157_into_chain`、`302_adt_match_expr`、`l29b5`、`p44/drop` | `__ct_recv4` / `__ct_mres` 未声明；`into` 链少一条赋值 | lowerer 对 `into` 链、`match` 表达式、`out` 转换的临时声明与语句建模不完整 |
| 2 | 验证器假阳性 | `21_fnptr`、`p40_return_case`、`224_defer_branches`、`p122 b_void` | `E-IR-102/105/106/109` 拒绝合法程序 | V2/V5/V6/V9 在函数指针、返回临时、分支清理上的判定过严 |
| 3 | 接口返回 / 派发 | `239_local_iface_return` | 输出值不同 | `vmcall` 返回接口的 `self` 打包形状 |
| 4 | ADT payload / 影子 | `300_adt_payload_glue`、`313_adt_shadow_option`、`l29b3`、`p81/box` | 生命周期 trace / 未声明 release 符号 | ADT 构造的 owning payload、`Option` 影子实例的胶水未进 LIR |
| 5 | 容器下标函数指针 | `170`、`171`、`176_vec_subscript_fnptr_field` | 编译失败 / C 语法错误 | 下标糖 + 函数指针字段的组合未降级 |
| 6 | 内建字符串生命周期 | `p80/layout`、`p80/methods`、`p80/retain` | 运行期 trace 不同 / 崩溃 | SH-102 retain/release 顺序在 LIR 中与 AST 不同 |
| 7 | 其它输出 / 诊断差异 | `18_struct_array_field`、`34_anon_member`、`37_empty_stmt`、`59_typedef_alias_array`、`62_borrow_handback`、`c2n/intern`、`c2p/limits`、`PH-69-E69-2`、`p86/errors`、`p111 I4` | 退出码 / 输出 / 诊断行不同 | 逐条待分诊；不影响 build 路径的等价性 |

> 归因是 DEV 分诊结果，不是最终结论；REV 复核时以夹具的实际 diff 为准。
> 这 37 个条目全部在**单文件编译路径**；`ct build`（含自举与 seed 生成）已经
> 0 失败（`== summary: 1735 passed, 0 failed`）。切换默认只覆盖 build 路径，
> 单文件路径保留 AST 默认，直到本表清零。

## 3b emitter 契约与 D4–D6 的边界

已移出 emitter 的判定（本轮）：

| 判定 | 原位置 | 现位置 | 证据 |
| --- | --- | --- | --- |
| 内建层判活 | `Module::builtin_live_for` 的整文件文本扫描 | `backend/tir/TGraph.h.ct`（AST 节点区间 + 实例表 + layer-needs） | SH-113 8/8；语料/自举逐字节 |
| 函数体生命周期 / 类型 / 临时名 | emitter 的 AST body writer | LIR writer（`ct build` 默认） | `bodies printed=N skipped=0`；`--ir=off` 逐字节 |
| 内建头文件清单 | emitter 循环 `builtin_units` + `builtin_live` | `LModulePlan.bhead[]`（由 module 层填） | 自举 seed 与 AST 产物逐字节 |

仍在外壳的判定（未迁，S8 之后切片）：类型/全局声明、泛型实例闭包与胶水、
`.abi.h` 导出表、map/model JSON、单文件路径的诊断优先序。四入口
`emit_module` / `write_header` / `write_abi_header` / `write_map` 的
**纯 LModule 化**因此尚未完成；它们目前只消费 `LModulePlan` 的判活与头文件。

**D4–D6（EmitHeader / EmitDecl / EmitExpr）未执行**。原因：纯搬移的判据是
函数体哈希不变，而 `write_unit_header` 经静态助手 `write_unit_header_body`
与宿主全局 `g_shell_u` / `g_shell_header` 耦合；本语言没有跨单元 `pub` 全局，
搬移必然改宿主函数体或引入访问器，违反纯搬移。设计 §4.5 也把 D4–D6 排在外壳
LModule 化之后。记录为剩余项，不在本 stage 用非纯搬移冒充。

### 3c S8 剩余子集（2026-11-27，DEV 施工记录）

本表在 S8 之后补齐两个独立片（分支 `issue/s8r`；**未 push、未打 tag、未改版本号**）：

| 片 | 提交 | 交付 | 判据 |
| --- | --- | --- | --- |
| 外壳 LModule 第一步 | `d75557fb` | 写者身份 `g_shell_u` / `g_shell_header` → `LModulePlan.shell_u` / `shell_header`（`lmod_plan_set_shell` / `lmod_plan_shell_u` / `lmod_plan_shell_header`）；走查状态 `g_shell_emit_state` / `g_shell_emit_cap` → `struct Emitter` | 82 语料单文件 + 自举 75 单元 C 树逐字节；`test/ir/run.sh` 15 checks；`g0/g1/g8` |
| D4 EmitHeader | `96dcb656` | `backend/emit/EmitHeader.h.ct`（+ `.shim.h`）、`pub trait EmitHeader`；10 方法 + `adoption_default_only` 纯搬移 | 1585 body 多重集不变；10 方法 body sha 同父提交 `d75557fb`；`sh94_split_check` 6 个唯一名 + 独立脚本 4 个与 `Module` 同名者；cycles 0；unit-name lint；goldens 25/25；`test/ir/run.sh` OK |
| seed | `3f73814e` | `gen-seed.sh` 重生成 | `check-seed` 两轮逐字节 + 手改负例 |

**D4 的边界（仍未做）**：`write_unit_header` 与 `write_unit_header_body` 留在
宿主——后者的实例闭包 / ADT 胶水走查仍读宿主 `g_sb` 生命周期状态，纯搬移须先
把外壳的实例闭包判定移出（本子集只清掉跨单元 shell 全局，不冒充完成）。
D5 `EmitDecl` / D6 `EmitExpr` 未开工。

**单文件路径**：仍 AST 默认；§3 的 38 条差异**未清零**，`--ir=off` 回滚口径不变。

## 4 回滚

| 回滚对象 | 动作 | 结果 |
| --- | --- | --- |
| 默认切换（本 stage） | `git revert <S8-commit>` | 默认回到 AST；TGraph 判活与 seed 一并回滚 |
| 只要 AST oracle | `--ir=off` / `CT_LIR=0` | 与切换前逐字节相同 |
| TGraph 判活 | 回滚 S8 的首个提交 | `builtin_live_for` 恢复文本扫描；SH-113 仍绿 |

## 5 签字

| 角色 | 结论 | 日期 | 依据 |
| --- | --- | --- | --- |
| DEV | 提交等价证据与差异清单（§2、§3） | 2026-11-27 | 本文件 + `test/ir/run.sh`、`check-seed.sh` 原始输出 |
| DEV（S8 剩余子集） | 外壳 LModule 第一步 + D4 完成；§3 的 38 条差异仍在 | 2026-11-27 | §3c + 提交 `d75557fb` / `96dcb656` / `3f73814e` |
| REV | 待签字 | — | 逐条复核 §3c 的边界与 §3 的分诊 |
