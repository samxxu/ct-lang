# 语言特性样例矩阵（特性 × example × test × docs）

> 状态：**S8c 收口版（2026-11-28；B-5/B-7 补齐）**，对应 [TEST-27](../../issues/testing/test27-feature-examples-pointer-free.md)
> 的 A 轨道交付。每一行是一个语言特性；`状态` 只有 `有` / `薄` 两档，**不允许 `缺` / `待实现`**
> （S2–S6 落地后已全部补样例）。
> 一致性由 `python3 tools/check-feature-matrix.py` 断言（先 `warn`，`--strict` 转硬）：
> 每行四列非空、example/test 代表路径存在、状态合法、S2–S6 行各有 ≥1 个 example。

## 0 口径

- 一行的 `example` 给**代表目录**（完整清单见 [examples/README](../../examples/README.md)），
  `test` 给**代表夹具**（`test/ast/<name>`，脚本夹具写 `.sh`）；
- `doc` 给规范节号与 README 小节；README 的代码块带 `// source:`，由 `check-docs` 校验；
- README 的**独立可执行片段**在 `docs/snippets/README/`（2026-11-28：10 个 `.ct` + `.expected.out`，
  覆盖 trait / 泛型 / String / 切片 / ref·out / Box / ADT / match / S4–S6 / C 边界对照）；
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
| 26 | 常量键折叠（S8a） | [70_const_key_fold](../../examples/70_const_key_fold) | [320_const_key_fold](../../test/ast/320_const_key_fold)、[321_const_key_fold_chain](../../test/ast/321_const_key_fold_chain) | spec §4.79；README — | 薄 |

## 2 缺口清单（S8c 收口）

| 片 | 缺口 | 动作 | 状态 |
| --- | --- | --- | --- |
| B-1 | 可选链 `?.` 无样例 | `examples/58_optional_chain`（compile + 运行） | 已补 |
| B-1b | 自定义下标（§4.64）无样例 | `examples/59_custom_subscript`；S2 按键分派的并存形态由 `test/ast/index_overload_both` / `jsaccess_overload_both` 钉住 | 已补 |
| B-2 | `match` / `defer` / `errdefer` / `?` / `ref` / 泛型 trait 只有 1–2 个样例 | `60`–`65`；defer / errdefer 升「有」，其余按需补反例 | 已补 |
| B-3 | `String` / `Str` 样例仍以 `char *` 混写 | `40_str_ownership` 去 `cstr` + `free`，改 `as_str()`；`48_string_steps` 判为 C 类型宿主例外并注明理由 | 已补 |
| B-4 | 非 C 互操作用例的指针 | 逐文件判定见 [pointer-free-exemptions](pointer-free-exemptions.md)；`40` / `59` 已改写；2026-11-27 LANG-30 落地后 E3 迁 22、保留 4（`23` 于 2026-11-28 迁出；逐条理由见该文件 §2.1） | 部分 |
| B-5 | 文档可执行片段偏少 | README 现有 12 个 `// source:` 来源（10 个 `docs/snippets/README/` standalone + 2 个 examples 摘录）；新增 `0.12_adt_tour`（S4/S5/S6）与 `0.13_c_boundary`（C 边界对照），矩阵 26 行的 doc 单元全部落到 README 小节；`check-docs` 12 sources、`check-warnings` 逐片段编译运行（H1–H4 逐片表仍在 TEST-27 §8，issue 状态由 REV 复核；本轮按指示不改 issue） | 已补 |
| B-6 | S2 下标协议、S3 函子、S4–S6 模式 | `59`（S2）、`66`（S3）、`67`（S4）、`68`（S5）、`69`（S6）各 ≥1 个 example | 已补 |
| B-7 | 文档去指针 | README / tutorial / guide / idioms 的非互操作段改 `String` / `Str` / `Vec` / `Map` / `Box` / 切片 / `ref`·`out`；C 互操作段（README §0.1/§0.2/§0.11/§0.13、tutorial §0/§9、guide §1.1/§10、idioms §11.1）保留并逐段标注理由；`Map<char *, V>` 词表改 `Map<String, V>` | 已补 |

## 3 保留的 C 互操作例外（不要求去指针）

`examples/55_c_boundary_shim`、`examples/c-superset/**`、`examples/54_freestanding_alloc`、
`examples/tour/**` 的 shim 段、`.m.ct` / `.shim.*` / `#ct-raw` 相关夹具——每条例外都要在
改写提交里写明「为什么必须指针」。逐文件分类与理由见 [pointer-free-exemptions](pointer-free-exemptions.md)。

文档侧的 C 互操作段是**显式对照**，不是遗漏：README §0.13 给出「普通 Ct / C 边界」逐行对照，
`docs/snippets/README/0.13_c_boundary.ct` 是可编译的边界样例（`test/c-boundary-allow.tsv` 已登记）。

## 4 指针现数（S8c 收口实测）

| 指标 | 数值 |
| --- | --- |
| `examples/**/*.ct` | 238 个文件 / 72 个目录 |
| 含 `char *` | 39 文件 / 117 次（`grep -o`） |
| 含非 `self->` 的 `->` | 56 文件（S8c 口径；`->` 仍是 E4 语言边界） |
| 含 `malloc(` | 11 文件 / 19 次（`grep -o 'malloc('`） |

新增的 `67`–`69` 三个样例零 `char *` / `->` / `malloc`。E3 类 26 个文件已由
[LANG-30](../../issues/lang/lang-30-str-print-api.md) 解锁：22 个改成 `print()` / `println()`，
4 个（`18` / `19` / `21` / `tour/11_variadic/forward`）因泛型 struct 实例化或 C 互操作保留；
`23_generic_stack` 已于 2026-11-28 改 `Stack<String>`，`char *` 清零、输出不变。逐条编号见
[pointer-free-exemptions](pointer-free-exemptions.md) §2.2；不得用 `cstr()` + `free` 假删。

文档指针现数（本次改动后，`grep -o` 计数；`self->` 不计入箭头）：

| 文档 | `char *` | 非 `self->` 箭头 | `malloc` | 说明 |
| --- | --- | --- | --- | --- |
| `README.md` | 16 | 34 | 0 | 集中在 §0.1/§0.2/§0.8/§0.11/§0.13 的标注边界或对照表；§0.4 已改 `Map<String,int>`，§2/§3 只剩命令占位符与类型名说明 |
| `docs/tutorial.md` | 70 | 49 | 7 | 集中在 §0 核心范式与 §9 map/bindings（已标注 C 互操作），§8 生命周期（E2），以及诊断文本里的 `got 'char *'` |
| `docs/guide-for-c-programmers.md` | 17 | 5 | 3 | 全部在 §1.1 C 对照左列与 §10 C 互操作 |
| `docs/idioms.md` | 7 | 2 | 0 | §1 语言事实与 §11.1 C 互操作表 |

去指针不是“把计数压到 0”：`README` 新增的 §0.13 与 `char *` 计数是**显式 C 边界对照**，
这正是 B-7 要求的“保留 C 互操作段并说明”。

## 5 关联

- [TEST-27](../../issues/testing/test27-feature-examples-pointer-free.md)（B 轨道）
- [`v1-PH-2`](../phases/v1-PH-2/card.md)（S8c）
- [dogfooding](dogfooding.md)（S8b，源码侧；与本矩阵文件集不重叠）
- [language-spec](../language-spec.md)（每行 § 引用）
- [pointer-free-v2](../proposals/pointer-free-v2.md)
