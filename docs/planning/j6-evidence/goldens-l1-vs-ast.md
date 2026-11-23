# ct-ast 静态 golden 与 L1 的差异清单（SH-105）

> 目的：说明 `test/goldens/ast/<case>.c` **不能**复用 L1 的 `test/cases/<case>.expected.c`。
> 实测：25/25 用例字节不同；差异全部来自两代发射器（ct-ast 与 L1），不是回归。
> 本表按 2026-11-23 的 `ct-ast 0.88.3` 与仓库内 L1 golden 逐例比对。

| 用例 | 注释丢弃 | const vtable | 指针空格 | 前向声明 | 原型 | 其他 |
| --- | --- | --- | --- | --- | --- | --- |
| 01_trait_basic | ✅ | ✅ | ✅ | ✅ | ✅ | — |
| 02_multi_trait | ✅ | ✅ | ✅ | ✅ | ✅ | — |
| 03_passthrough | ✅ | — | ✅ | ✅ | ✅ | — |
| 04_signatures | ✅ | ✅ | ✅ | ✅ | ✅ | — |
| 05_declarations | ✅ | ✅ | ✅ | ✅ | ✅ | — |
| 06_name_collision | ✅ | ✅ | ✅ | ✅ | ✅ | — |
| 07_positional_init | ✅ | ✅ | ✅ | ✅ | ✅ | — |
| 08_self_call | ✅ | ✅ | — | ✅ | ✅ | — |
| 09_pointer_receiver | ✅ | ✅ | ✅ | ✅ | ✅ | — |
| 10_uninit_decl | ✅ | ✅ | ✅ | ✅ | ✅ | — |
| 11_value_param | ✅ | ✅ | ✅ | ✅ | ✅ | — |
| 12_pointer_param | ✅ | ✅ | — | ✅ | ✅ | — |
| 13_signature_types | ✅ | ✅ | ✅ | ✅ | ✅ | — |
| 14_scope_shadow | ✅ | ✅ | ✅ | ✅ | ✅ | — |
| 15_composition | ✅ | ✅ | ✅ | ✅ | ✅ | — |
| 16_arrays | ✅ | ✅ | — | ✅ | ✅ | — |
| 17_heap | ✅ | ✅ | — | ✅ | ✅ | — |
| 18_polymorphism | ✅ | ✅ | ✅ | ✅ | ✅ | — |
| 21_empty_init_iface | ✅ | ✅ | ✅ | ✅ | ✅ | — |
| 23_file_scope | ✅ | ✅ | ✅ | ✅ | ✅ | — |
| 24_receiver_forms | ✅ | ✅ | ✅ | ✅ | ✅ | — |
| 25_rvalue_receiver | ✅ | ✅ | ✅ | ✅ | ✅ | — |
| 26_method_body_dispatch | ✅ | ✅ | — | ✅ | ✅ | — |
| 27_static_file_scope | ✅ | ✅ | ✅ | ✅ | ✅ | — |
| 28_iface_field | ✅ | ✅ | — | ✅ | ✅ | — |

- **注释丢弃**：L1 保留源码 `//` 注释，ct-ast 不保留；
- **const vtable**：ct-ast 在 vtable 指针前加 `const`；
- **指针空格**：ct-ast 写 `char * name`，L1 写 `char *name`；
- **前向声明**：ct-ast 提前补 `struct X;`；
- **原型**：ct-ast 把原型提前或归一 `static` 形态；
- **其他**：本批 25 例均为 `—`（无额外类别）。新增类别必须逐行写明，不允许“同上”。

比对命令（无 L1/L2 依赖）：

```sh
bash selfhost/check-goldens-ast.sh /path/to/ct-ast
```
