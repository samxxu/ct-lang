# 第九批特性：匿名成员（2026-10-29）

> 锚点：`3f4aa7f`（第八批收口），工作树干净。
> 本规格只做 C11 的**匿名 struct / union 成员**（`struct S { union { int i; }; };`），
> 不做「无名记录类型的具名字段」（`union { int i; } u;`）。

## 1. 实测现状

- `struct Outer { int tag; union { int i; char c; }; };` 报 `expected a union name`：
  `parse_field_def` → `parse_type` 的 `union` 分支要求标签。
- 成员的表征只有 `structs[].fields[]`（name / type / dims 三个字符串），成员访问的类型推断
  （`TypeCheck::expr_type` 的 N_MEMBER / N_ARROW 分支）与 vptr 初始化
  （`Init::emit_field_vptrs`、`emit_array_field_vptrs`）都按这张表逐个字段拼 `.name`。
- 记录体的字段发射只有 `emit_type_decl` 的两处循环（N_STRUCT 与 N_UNION），
  每条字段都是 `emit_indent(ind + 1); emit_inline(m); ";\n"`。

## 2. 决策

- **D-1 复用 `N_FIELD`，`aux = 2`**：`text` 存关键字（`struct` / `union`），`a` 存内层字段链。
  `aux = 1` 仍是位域（第八批），两者不冲突。
- **D-2 成员名提升 = 解析期拍平**。内层字段（含多层嵌套匿名成员）的名字按 C11 的规则提升进
  **外层**记录的表：`structs[].fields[]`（有标签的记录）或 `pend_fields`（`typedef` 的匿名体）。
  于是 `o.i` 的类型推断、`offsetof(struct Outer, i)` 的字段校验、vptr 初始化里的
  `.obj.__x_vptr` 全部不需要第二套代码——C 本身也按提升后的名字接受它们。
- **D-3 重复成员名报错**。拍平后同名（含与已有具名字段同名、两个匿名成员之间同名）报
  `duplicate member '<name>'`，位置取该字段所在行；C 同样要求拍平后唯一。
  无名位域的填充项（`text2` 为空）不参与查重与登记。
- **D-4 语法**：记录体内出现 `struct` / `union` 且**紧跟 `{`** 时按匿名成员解析；
  `}` 之后必须是 `;`。带标签的 `struct Foo { … } f;` 与具名声明仍走原来的路径。
- **D-5 拒绝的形态**（均给明确消息）：
  - `union { int i; } u;`（无名类型的具名字段）→ `an anonymous record member cannot have a name; tag the record instead`；
  - `union { };`（空体）→ `an anonymous record needs a member`。
- **D-6 发射**：`emit_field(m, ind)`——匿名成员发 `union {`，内层逐条 `emit_field` 缩进一级，
  再发 `}`（由调用方的 `;\n` 收尾）。`emit_type_decl` 的两处字段循环改用它，
  因此 struct / union 嵌套任意深都同形。
- **D-7 与既有特性共存**：位域可以在匿名成员里（外层按提升规则登记）；
  `use` 的 vptr 字段仍排在**外层**记录的最后；`own` / `Drop` 不影响。
  匿名成员里的 struct 成员若带 trait，vptr 初始化照旧写 `.member.__x_vptr`（提升后的名字）。

## 3. 影响面

- 改：`frontend/parse/Parser.h.ct`（`cur_record` 状态、`record_body_ahead`、`parse_record_body`、
  `parse_anon_member`、`register_field`，`parse_record_def` 改用它们）、
  `backend/emit/Emitter.h.ct`（`emit_field` 方法，`emit_type_decl` 两处循环）。
- **impl 方法预算**：L2 构建 ct-ast 时 `MAX_MAP_IMPLS` 是 256（基线 250）。本批最终只新增 5 个
  impl 方法（`parse_record_body` / `parse_anon_member` / `record_body_ahead` / `register_field` /
  `emit_field`），总数 255；最初拆出的 `field_dup` / `field_add` 两个 helper 已合并进
  `register_field` 才装得下。后续批次要先看这个预算。
- 不动：`frontend/type/TypeCheck.h.ct`、`backend/emit/Init.h.ct`（拍平后即可复用）、
  `frontend/sym/Symbols.h.ct`、`ctc.c` / `l1` / `l2`、`CTC_VERSION`、golden。

## 4. 验证

- 新增 `test/ast/34_anon_member`：单层匿名 union、双层嵌套（匿名 union 里再放匿名 struct）、
  匿名成员与位域混排、`typedef struct { … }` 匿名体里的匿名成员、带 trait 的成员通过提升名
  调用方法、`sizeof` 体现布局。
- 新增三个负例：`anon_member_name`、`anon_member_dup`、`anon_member_empty`，在
  `check-ast.sh` 里逐条 `grep` 精确消息。
- `bash selfhost/check-ast.sh` / `check-warnings.sh` / `check-all.sh` 全绿。
