# 任务：`union`（第六批）

依据：`docs/design/batch6-union/spec.md`
顺序即依赖顺序；每步完成后保持工作树可编译。

## [x] T1 类型类别（`frontend/sym/Symbols.h.ct`）

- `type_kind` 注释补 `6 = union tag`；不改 `add_type`。

## [x] T2 记录文法泛化（`frontend/parse/Parser.h.ct`）

- `N_UNION 48`。
- `parse_struct_def(void)` 泛化为 `parse_record_def(int is_union)`：关键字照样消费一次；
  `add_type` 按 1 / 6 分流；节点 kind 按 `N_STRUCT` / `N_UNION` 分流；重复诊断按
  `duplicate struct` / `duplicate union` 分流；`use` 子句只对 struct 生效，union 命中
  `a union cannot use a trait`。
- `top_decl` 在 struct 分支之后加 union 分支（`struct_def_ahead()` 对两者通用）。
- `parse_typedef` 的 struct 分支改为同时认 `struct` / `union`，把 `is_union` 传给
  `parse_record_def`；别名侧的字段 / `use` 拷贝逻辑对 union 自然成立（`nuse == 0`）。

## [x] T3 类型名与 `offsetof`（`frontend/parse/Expr.h.ct`）

- `parse_type` 的类型词分支：`union` 与 `struct` 对称（读标签、`resolve_type`、`type_append`、
  `add_type(sname, 6)`，缺标签报 `expected a union name`）。
- 裸标签分支：`type_kind == 6` 时补 `"union"` 前缀。
- `offsetof`：剥离 `union ` 前缀；缺失字段的消息按类型关键字打印
  （`union 'V' has no field 'd'` / 原来的 `struct 'S' has no field 'b'`）。

## [x] T4 发射（`backend/emit/Emit.h.ct`）

- `N_UNION 48`（与 Parser / Module 各写一份）。
- `emit_type_decl` 新增 `N_UNION` 分支：`union <text2> { … };` 或
  `typedef union [<text>] { … } <text2>;`，无 vptr 字段。
- `emit_struct_fwd` 按类别分流：kind 1 → `struct X;`，kind 6 → `union X;`。
- `emit_program`、`emit_unit` 的私有类型循环、头文件 `pub` 循环的条件都加上 `N_UNION`。

## [x] T5 跨单元导出（`frontend/module/Module.h.ct`）

- `N_UNION 48`；裸名类型导出循环加入 `N_UNION`（`text2` 已是 mangling 后的 C 名，
  去前缀即裸名，与 struct / enum 共用一套代码）。

## [x] T6 fixture、关卡、文档与提交

- `test/ast/31_union`：标签 union、`typedef union Tag { … } Alias;`、无名 typedef union、
  嵌在 struct 里的 union、裸名与带关键字两种写法、`sizeof` 与 `offsetof`。
- 负例：`union_duplicate`、`union_use`、`offsetof_union_field`；`check-ast.sh` 三组精确消息。
- `test/modules/union_export`：`pub union` 进头文件、消费单元裸名引用；`check-ast.sh` 挂断言。
- `docs/language-spec.md`：新增 §4.15（中英对称），顶部「其它 C 透传」表去掉 `union`。
- `bash selfhost/check-all.sh` → 九关全绿；`bash selfhost/check-warnings.sh` 零告警。
- 提交拆分：`feat(codegen): add union to the record grammar`、`docs(spec): record the union form`。
  不 bump 版本、不动 golden。
