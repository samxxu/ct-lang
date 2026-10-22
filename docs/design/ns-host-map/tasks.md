# 任务：命名空间宿主 map（SH-20）

依据：`docs/design/ns-host-map/spec.md`
顺序即依赖顺序；每步完成后保持工作树可编译。

## [x] T1 数据结构

- `frontend/module/Map.h.ct`：`struct Map` 增加 `char prefix[160]`、`char vtable[160]`、
  `int ns_host`（vtable 名由 `prefix` 派生，实例宿主与命名空间宿主共用同一套字段）。
- 验收：`check-ast.sh` 的构建段能编过（此步无行为变化）。

## [x] T2 map 声明解析

- `frontend/parse/MapBuild.h.ct` 的 `parse`：
  - `for` 后接受 `instance` | `namespace`；
  - namespace 分支累积源路径与 `_` 前缀；
  - 计算 `prefix` / `vtable` / `ns_host`；
  - 重复检测改用 `prefix`；
  - wrapper 名改用 `m->prefix`；
  - 拒绝命名空间宿主的直绑。
- 验收：既有 `test/ast/22_map_direct`、`test/ast/15_map_args`、
  `test/modules/map_ns` 仍通过（回归无变化）。

## [x] T3 装箱表达式解析

- `frontend/parse/Expr.h.ct`：
  - `parse_qual_path` 增加 `int *form` 出参；
  - trait + 命名空间路径（非调用）返回 form=2，并给出 trait C 名、宿主前缀、宿主源路径；
  - `parse_primary` 构造 `N_BOX`（`a = -1`、`aux = 4`、`b = -1`、`text3` 打包诊断名）。
- 验收：`Writer::hal` 能被解析为装箱节点；`Writer::hal(...)` 仍走限定调用。

## [x] T4 类型检查

- `frontend/type/TypeCheck.h.ct`：
  - `expr_type` 的 `N_BOX` 指针判定改为 `aux & 2`；
  - `maybe_box` 的 `N_BOX` 快速路径校验 trait 并置 `aux |= 8`（`aux` bit3 = 已被接口上下文接收；
    不能用 `b`，它是 AST 子槽，`hoist_scan` 会当作节点索引遍历）。
- 验收：`test/ast/14_map_dispatch`、`test/ast/15_map_args`、`test/modules/xunit_box`
  的装箱行为不变。

## [x] T5 发射

- `backend/emit/Emit.h.ct`：
  - `N_BOX` 按位发射，`aux & 4` 时 self 为 `0`；
  - 发射期两条校验（非接口目标、缺 map），使用 `fail_from` 保证 `file:line:col:`
    归属到声明装箱的单元；
  - `map_vtable_exported` 支持命名空间宿主；
  - `write_map` 增加 `"host"` 字段。
- 验收：生成物 `-Wall -Wextra -std=c99` 零告警；`--emit-map` JSON 合法。

## [x] T6 测试与关卡

- 新增 `test/ast/26_ns_host/`、`test/ast/errors/ns_host_no_map.ct`、
  `test/ast/errors/ns_host_direct.ct`、`test/modules/ns_host/`。
- `selfhost/check-ast.sh`：新增模块断言块（extern vtable、static wrapper、`(void *)0`、
  运行输出）与两条负例的精确消息断言。
- `selfhost/check-warnings.sh`：按既有枚举方式补入新模块用例。
- 验收：`bash selfhost/check-ast.sh` 全绿、`check-warnings.sh` 零告警。

## [x] T7 文档

- `docs/language-spec.md` §4.10（中英对称）：两种宿主形态、NULL self、命名规则、
  导出规则、禁止直绑、新诊断；修订「不合成宿主」段落。
- `issues/selfhost/ct-ast-map-requires-instance.md`：状态与最终方案。
- `issues/README.md`：SH-20 处置行。
- 验收：`grep` 无残留「命名空间级绑定不可用」表述。

## T8 全量门禁与提交

- `bash selfhost/check-all.sh` → 九关全绿、`ALL_EXIT=0`。
- 提交拆分：`feat(codegen): bind a trait to a namespace`（代码 + 测试）、
  `docs(spec): record the namespace-host map`（文档）。
- 不 bump 版本、不动 golden。
