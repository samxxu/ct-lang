# 语言特性样例矩阵（特性 × example × test × docs）

> 状态：**S8c 收口版（2026-11-27）**，对应 [TEST-27](../../issues/testing/test27-feature-examples-pointer-free.md)
> 的 A 轨道交付。每一行是一个语言特性；`状态` 只有 `有` / `薄` 两档，**不允许 `缺` / `待实现`**
> （S2–S6 落地后已全部补样例）。
> 一致性由 `python3 tools/check-feature-matrix.py` 断言（先 `warn`，`--strict` 转硬）：
> 每行四列非空、example/test 代表路径存在、状态合法、S2–S6 行各有 ≥1 个 example。

## 0 口径

- 一行的 `example` 给**代表目录**（完整清单见 [examples/README](../../examples/README.md)），
  `test` 给**代表夹具**（`test/ast/<name>`，脚本夹具写 `.sh`）；
- `doc` 给规范节号与 README 小节；README 的代码块带 `// source:`，由 `check-docs` 校验；
- `有` = example ≥ 3 且 test ≥ 5；`薄` = example 1–2 或 test < 5；两者都算**有覆盖**；
- 计数的复现口径（文件数）：
  ```sh
  grep -rlE '^[A-Za-z_][A-Za-z0-9_ \*]*[A-Za-z_][A-Za-z0-9_]*<[A-Za-z_][A-Za-z0-9_]*>[ \t]*\(' examples --include='*.ct' | wc -l
  grep -rl 'char \*' examples --include='*.ct' | wc -l
  ```

**新增样例会改变语料 pin**：`p85/m0` 与 `p88/emit` 用 `test/probes/p85_corpus_sha.tsv`
钉住 `examples/*/*.ct` 的清单与 sha256。新增或改写 example 必须在**同一提交**里重生成：

```sh
python3 tools/p85_inventory.py --root . corpus-manifest --ct <ct-ast 二进制> > test/probes/p85_corpus_sha.tsv
```

## 1 矩阵

| # | 特性 | example（代表） | test（代表） | doc | 状态 |
| --- | --- | --- | --- | --- | --- |
| 1 | `trait` / `impl` | [01_greeter](../../examples/01_greeter) | [01_hello](../../test/ast/01_hello) | spec §4.1、§4.8；README §0.3 | 有 |
| 2 | 泛型函数 | [16_generic_min](../../examples/16_generic_min) | [123_generic_identity](../../test/ast/123_generic_identity) | spec §4.48；README §0.7 | 有 |
| 3 | 泛型 struct | [23_generic_stack](../../examples/23_generic_stack) | [124_generic_struct](../../test/ast/124_generic_struct) | spec §4.51；README §0.10 | 有 |
| 4 | 有界泛型（`T: Trait`） | [21_generic_bound](../../examples/21_generic_bound) | [136_generic_bound](../../test/ast/136_generic_bound) | spec §4.50；README §0.7 | 有 |
| 5 | 泛型 trait | [39_generic_trait](../../examples/39_generic_trait)、[65_generic_trait_instances](../../examples/65_generic_trait_instances) | [219_generic_trait](../../test/ast/219_generic_trait) | spec §4.55；README §0.10 | 薄 |
| 6 | ADT `enum` | [53_match_adt](../../examples/53_match_adt) | [290_adt_match](../../test/ast/290_adt_match) | spec §4.73；README §0.5.1 | 有 |
| 7 | `match` | [64_match_expr](../../examples/64_match_expr)、[67_adt_patterns](../../examples/67_adt_patterns) | [302_adt_match_expr](../../test/ast/302_adt_match_expr) | spec §4.73；README §0.5.1 | 有 |
| 8 | 模式扩展 A：字面量 / 嵌套 / 结构体（S4） | [67_adt_patterns](../../examples/67_adt_patterns) | [303_adt_literal_pattern](../../test/ast/303_adt_literal_pattern)、[304_adt_nested_pattern](../../test/ast/304_adt_nested_pattern)、[305_adt_struct_pattern](../../test/ast/305_adt_struct_pattern) | spec §4.73「S4 模式扩展」；README §0.12 | 薄 |
| 9 | 模式扩展 B：or / 守卫（S5） | [68_adt_guards](../../examples/68_adt_guards) | [306_adt_or_pattern](../../test/ast/306_adt_or_pattern)、[307_adt_guard](../../test/ast/307_adt_guard) | spec §4.73「S5 模式扩展」；README §0.12 | 薄 |
| 10 | 泛型 ADT（S6） | [69_generic_adt](../../examples/69_generic_adt) | [308_adt_generic_option](../../test/ast/308_adt_generic_option)…[314_adt_shadow_result](../../test/ast/314_adt_shadow_result) | spec §4.73「S6 泛型 ADT」；README §0.12 | 薄 |
| 11 | `String`（owning） | [48_string_steps](../../examples/48_string_steps) | [231_str_ops](../../test/ast/231_str_ops) | spec §4.70；README §0.5 | 薄 |
| 12 | `Str`（借用视图） | [40_str_ownership](../../examples/40_str_ownership) | [230_str_embedded_nul](../../test/ast/230_str_embedded_nul) | spec §4.70；README §0.5 | 薄 |
| 13 | 切片 `T[]` | [51_slice](../../examples/51_slice) | [p79_basic.sh](../../test/ast/p79_basic.sh) | spec §4.69；README §0.10 | 有 |
| 14 | `ref` | [50_ref_out](../../examples/50_ref_out)、[63_ref_out_places](../../examples/63_ref_out_places) | [p78_basic.sh](../../test/ast/p78_basic.sh) | spec §4.68；README §0.5 | 薄 |
| 15 | `out` | [50_ref_out](../../examples/50_ref_out) | [p78_basic.sh](../../test/ast/p78_basic.sh) | spec §4.68；README §0.10 | 有 |
| 16 | `Box<T>` / `new` | [52_box_new](../../examples/52_box_new) | [p81_box.sh](../../test/ast/p81_box.sh) | spec §4.71；README §0.5 | 有 |
| 17 | 可选链 `?.` | [58_optional_chain](../../examples/58_optional_chain) | [p53_chain](../../test/ast/p53_chain) | spec §4.65；README §0.8 | 薄 |
| 18 | `Map` / map 构造 | [34_map_literal](../../examples/34_map_literal) | [180_map_brace_init](../../test/ast/180_map_brace_init) | spec §4.51；README §0.10 | 有 |
| 19 | `map` 绑定 | [08_map_binding](../../examples/08_map_binding) | [14_map_dispatch](../../test/ast/14_map_dispatch) | spec §4.10；README §0.11 | 有 |
| 20 | `foreach` | [20_foreach_statement](../../examples/20_foreach_statement) | [141_foreach_map](../../test/ast/141_foreach_map) | spec §4.49；README §0.3 | 有 |
| 21 | `defer` | [42_defer](../../examples/42_defer)、[60_defer_snapshot](../../examples/60_defer_snapshot)、[61_errdefer_vs_return](../../examples/61_errdefer_vs_return)、[62_try_cleanup](../../examples/62_try_cleanup) | [220_defer_order](../../test/ast/220_defer_order) | spec §4.9.1；README §0.6 | 有 |
| 22 | `errdefer` | [43_errdefer](../../examples/43_errdefer)、[45_error_return_contract](../../examples/45_error_return_contract)、[61_errdefer_vs_return](../../examples/61_errdefer_vs_return)、[62_try_cleanup](../../examples/62_try_cleanup) | [234_err_return_contract](../../test/ast/234_err_return_contract) | spec §4.58；README §0.6 | 有 |
| 23 | 后缀 `?` | [46_result_try](../../examples/46_result_try)、[62_try_cleanup](../../examples/62_try_cleanup) | [235_result_try](../../test/ast/235_result_try) | spec §4.62；README §0.6 | 薄 |
| 24 | 自定义下标（S2，§4.64） | [59_custom_subscript](../../examples/59_custom_subscript) | [index_overload_both](../../test/ast/index_overload_both)、[jsaccess_overload_both](../../test/ast/jsaccess_overload_both) | spec §4.64；README §0.8 | 薄 |
| 25 | 函子 `(A,B) => R`（S3） | [66_functor](../../examples/66_functor) | [p3_functor_forms](../../test/ast/p3_functor_forms) | spec §4.77；README §0.10 | 薄 |

## 2 缺口清单（S8c 收口）

| 片 | 缺口 | 动作 | 状态 |
| --- | --- | --- | --- |
| B-1 | 可选链 `?.` 无样例 | `examples/58_optional_chain`（compile + 运行） | 已补 |
| B-1b | 自定义下标（§4.64）无样例 | `examples/59_custom_subscript`；S2 按键分派的并存形态由 `test/ast/index_overload_both` / `jsaccess_overload_both` 钉住 | 已补 |
| B-2 | `match` / `defer` / `errdefer` / `?` / `ref` / 泛型 trait 只有 1–2 个样例 | `60`–`65`；defer / errdefer 升「有」，其余按需补反例 | 已补 |
| B-3 | `String` / `Str` 样例仍以 `char *` 混写 | `40_str_ownership` 去 `cstr` + `free`，改 `as_str()`；`48_string_steps` 判为 C 类型宿主例外并注明理由 | 已补 |
| B-4 | 非 C 互操作用例的指针 | 逐文件判定见 [pointer-free-exemptions](pointer-free-exemptions.md)；`40` / `59` 已改写；2026-11-27 LANG-30 落地后 E3 迁 21、保留 5（逐条理由见该文件 §2.1） | 部分 |
| B-5 | 文档可执行片段偏少 | README 现有 13 个 `// source:` 片段（`0.1`–`0.12`；`check-docs` 实测）；H1–H4 见 [TEST-27 §8](../../issues/testing/test27-feature-examples-pointer-free.md) | 部分 |
| B-6 | S2 下标协议、S3 函子、S4–S6 模式 | `59`（S2）、`66`（S3）、`67`（S4）、`68`（S5）、`69`（S6）各 ≥1 个 example | 已补 |
| B-7 | 文档去指针 | README / tutorial / guide / idioms / snippets 的 C 互操作段保留并标注；非互操作段优先 `String` / `Str` / `Vec` / `Map` / `Box` / 切片 / `ref`·`out` | 进行中 |

## 3 保留的 C 互操作例外（不要求去指针）

`examples/55_c_boundary_shim`、`examples/c-superset/**`、`examples/54_freestanding_alloc`、
`examples/tour/**` 的 shim 段、`.m.ct` / `.shim.*` / `#ct-raw` 相关夹具——每条例外都要在
改写提交里写明「为什么必须指针」。逐文件分类与理由见 [pointer-free-exemptions](pointer-free-exemptions.md)。

## 4 指针现数（S8c 收口实测）

| 指标 | 数值 |
| --- | --- |
| `examples/**/*.ct` | 237 个文件 / 71 个目录 |
| 含 `char *` | 60 |
| 含非 `self->` 的 `->` | 56 |
| 含 `malloc` | 12 |

新增的 `67`–`69` 三个样例零 `char *` / `->` / `malloc`。E3 类 26 个文件已由
[LANG-30](../../issues/lang/lang-30-str-print-api.md) 解锁：21 个改成 `print()` / `println()`，
5 个（`18` / `19` / `21` / `23` / `tour/11_variadic/forward`）因泛型 struct 实例化或 C 互操作
保留，理由见 [pointer-free-exemptions](pointer-free-exemptions.md) §2.1；不得用 `cstr()` + `free` 假删。

## 5 关联

- [TEST-27](../../issues/testing/test27-feature-examples-pointer-free.md)（B 轨道）
- [`v1-PH-2`](../phases/v1-PH-2/card.md)（S8c）
- [dogfooding](dogfooding.md)（S8b，源码侧；与本矩阵文件集不重叠）
- [language-spec](../language-spec.md)（每行 § 引用）
- [pointer-free-v2](../proposals/pointer-free-v2.md)
