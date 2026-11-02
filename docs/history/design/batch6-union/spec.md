# 第六批特性：`union`（2026-10-29）

> 锚点：`aefea03`（第五批收口），工作树干净。
> 本规格只做 `union`：它是「类型声明」里最后一个仍被 ct-ast 拒绝的构造
> （`union X u;` 在 L2 里原样透传，在 ct-ast 里落进表达式解析后报错）。

## 1. 实测现状

- `union` 已在 `is_type_word` 里，因此 `union U u;` 不会被当成未知词，但标签不做命名空间
  mangling、也不进类型表；带函数体的 `union U { … };` 在顶层没有任何分支，落到「原样透传 /
  unexpected token」。
- `struct` 的整套设施（`parse_record_def`、`add_struct` 字段表、`emit_type_decl`、
  头文件导出循环、`offsetof` 的字段校验）都可以复用，差别只在关键字、类型类别与 `use` 子句。

## 2. 决策

- **D-1 节点 48 `N_UNION`**。布局与 `N_STRUCT` 相同：`text` = typedef 形态的标签、
  `text2` = 对外类型名、`d` = `pub`、`aux` = typedef 形态标记、`a`/`next` = 字段链。
- **D-2 类型类别 6 = union tag**。`type_kind` 增第 6 类，语义与 1（struct tag）并列：
  裸标签由编译器补回 `union ` 前缀，`union <tag>` 直接发射。
- **D-3 标签与 struct 共享 `structs` 表**。union 的字段信息同样登记进 `structs[]`（`nuse` 为 0、
  `uses_drop` 为 0），于是字段链的类型推断与 `offsetof` 的字段校验不需要第二套表；`4`
  （`emit_struct_fwd` 按 kind 分流）仍然只前向声明 struct，D-2 的类别判断负责把 union 分流。
- **D-4 不支持 `use` 子句**。union 的成员共享同一块存储，追加 `__<trait>_vptr` 会与用户成员冲突，
  因此 `union X { … } use T;` 直接报 `a union cannot use a trait`，而不是静默忽略。
- **D-5 发射**：`union <text2> { … };` 或 `typedef union [<text>] { … } <text2>;`，字段逐行缩进，
  不接受任何 vptr 字段。`union` 的前向声明按 `union <name>;` 发射。
- **D-6 诊断**（均带 `file:line:col:`）：`duplicate union '<name>'`、
  `a union cannot use a trait`、`union '<S>' has no field '<f>'`、`expected a union name`。
- **D-7 匿名成员**（`union { int a; float b; };` 这类无名成员，或声明里的 `union { … } u;`）
  不在支持的子集内：`union` 作类型词出现时标签必填，缺标签报 `expected a union name`（与 struct
  的 `expected a struct name` 同一条路径），不改动其它诊断。
- **D-8 形态**：`union Value;`（前置声明）、`union Value { … };`、`typedef union Tag { … } Alias;`、
  `typedef union { … } Alias;` 全部与 struct 对称；顶层缺标签沿用 struct 的现状（不额外加诊断）。

## 3. 影响面

- 改动：`frontend/parse/Parser.h.ct`（`parse_struct_def` 泛化为 `parse_record_def(is_union)`、
  `top_decl` 与 `parse_typedef` 各加一条分支）、`frontend/parse/Expr.h.ct`（`parse_type` 的
  `union` 与 kind 6、`offsetof` 的 `union` 前缀与消息关键字）、`frontend/sym/Symbols.h.ct`
  （类别注释）、`backend/emit/Emitter.h.ct`（`N_UNION` 宏、三处类型循环、`emit_type_decl`、
  `emit_struct_fwd`）、`frontend/module/Module.h.ct`（裸名导出循环）。
- 不动：`ctc.c` / `l1` / `l2`（union 在 L2 仍按原样透传）、`CTC_VERSION`、`test/cases/**`
  与 `examples/**` 的 golden。

## 4. 验证

- 新增 `test/ast/31_union`：标签 / typedef / 无名 typedef / 嵌在 struct 里、裸名与带关键字两种写法、
  `sizeof` 与 `offsetof`。
- 新增三个负例：`union_duplicate`、`union_use`、`offsetof_union_field`，并在 `check-ast.sh`
  里逐条 `grep` 精确消息。
- 新增 `test/modules/union_export`：`pub union` 进头文件、消费单元按裸名引用，`check-ast.sh`
  挂生成 + 运行断言。
- `bash selfhost/check-ast.sh` / `check-warnings.sh` / `check-all.sh` 全绿。
