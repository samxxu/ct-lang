# 语言特性样例矩阵（特性 × example × test × docs）

> 状态：**首版矩阵（2026-11-26）**，对应 [TEST-27](../../issues/testing/test27-feature-examples-pointer-free.md) 的 A 轨道交付。
> 用法：每一行代表一个语言特性；`缺` / `薄` 行就是 S8c 的施工清单。新特性（S2–S6）在实现落地时补行、补样例。
> 本文件只记录现状与缺口，不改样例、不改文档；改写动作在 S8c 分片执行。

## 0 口径

```sh
# 某个特性在 examples / test 里的覆盖（示例：泛型函数）
grep -rlE '^[A-Za-z_][A-Za-z0-9_ \*]*[A-Za-z_][A-Za-z0-9_]*<[A-Za-z_][A-Za-z0-9_]*>[ \t]*\(' examples --include='*.ct' | wc -l
# 指针用量
grep -rl 'char \*' examples --include='*.ct' | wc -l
```

计数单位是**文件数**（一个 example 目录可能有多份 `.ct`）；`test` 列含 `test/ast/**`、`test/probes/**`、
`test/docs/tutorial_cases/**`、`test/cases/**`。判档：

| 档 | 含义 |
| --- | --- |
| 有 | example ≥ 3 且 test ≥ 5 |
| 薄 | example 1–2 或 test < 5 |
| 缺 | example = 0 |
| 待实现 | 语言侧还没落地（S2–S6） |

**新增样例会改变语料 pin（2026-11-26 实测踩坑）**：`p85/m0` 与 `p88/emit` 用
`test/probes/p85_corpus_sha.tsv` 钉住 `examples/*/*.ct` 的清单与 sha256。新增或改写 example 必须在
**同一提交**里重生成该文件，否则两段门禁会红：

```sh
python3 tools/p85_inventory.py --root . corpus-manifest --ct <ct-ast 二进制> > test/probes/p85_corpus_sha.tsv
```

## 1 矩阵

| # | 特性 | example（数 / 代表） | test（数） | docs | 档 |
| --- | --- | --- | --- | --- | --- |
| 1 | `trait` / `impl` | 76 / `examples/01_greeter` | 334 | spec §4.1、§4.8、§4.39；README 快速开始 | 有 |
| 2 | 泛型函数 | 4 / `examples/16_generic_min` | 28 | spec §4.48 | 有 |
| 3 | 泛型 struct | 5 / `examples/23_generic_stack` | 48 | spec §4.51 | 有 |
| 4 | 有界泛型（`T: Trait`） | 3 / `examples/21_generic_bound` | 29 | spec §4.50、§4.54 | 有 |
| 5 | 泛型 trait | 1 / `examples/39_generic_trait` | 13 | spec §4.55 | 薄 |
| 6 | ADT `enum` | 7 / `examples/53_match_adt` | 29 | spec §4.73 | 有 |
| 7 | `match` | 1 / `examples/53_match_adt` | 12 | spec §4.73 | 薄 |
| 8 | 模式扩展（字面量 / 嵌套 / 结构体 / or / 守卫 / 泛型 ADT） | 0 | 0 | 无 | 待实现（S4–S6） |
| 9 | `String`（owning） | 2 / `examples/48_string_steps` | 81 | spec §4.70 | 薄 |
| 10 | `Str`（借用视图） | 3 / `examples/40_str_ownership` | 72 | spec §4.56、§4.70 | 薄 |
| 11 | 切片 `T[]` | 9 / `examples/51_slice` | 35 | spec §4.69 | 有 |
| 12 | `ref` | 1 / `examples/50_ref_out` | 7 | spec §4.68 | 薄 |
| 13 | `out` | 5 / `examples/50_ref_out` | 16 | spec §4.68 | 有 |
| 14 | `Box<T>` / `new` | 4 / `examples/52_box_new` | 53 | spec §4.71 | 有 |
| 15 | 可选链 `?.` | 1 / `examples/58_optional_chain`（2026-11-26 补） | 10（`test/ast/p53_eval_once`） | spec §4.65 | 薄 |
| 16 | `Map` / map 构造 | 7 / `examples/34_map_literal` | 49 | spec §4.51.1 | 有 |
| 17 | `map` 绑定 | 20（含 `.m.ct`）/ `examples/08_map_binding` | 52 | spec §4.10 | 有 |
| 18 | `foreach` | 7 / `examples/20_foreach_statement` | 29 | spec §4.49 | 有 |
| 19 | `defer` | 2 / `examples/42_defer` | 23 | spec §4.9.1 | 薄 |
| 20 | `errdefer` | 2 / `examples/45_error_return_contract` | 22 | spec §4.58 | 薄 |
| 21 | 后缀 `?` | 1 / `examples/46_result_try` | 10 | spec §4.62 | 薄 |
| 22 | 自定义下标（§4.64） | 1 / `examples/59_custom_subscript`（2026-11-26 补；`28_subscript_forms` 是 C 数组 / 容器下标形态，不算） | 6（`test/ast/p52_read`、`p52_write`、`p52_generic`、`p52_private`、`p52_str_only`、`p52_c_passthrough`） | spec §4.64 | 薄 |
| 23 | 函子 `(A,B) => R` | 0 | 0 | 无 | 待实现（S3） |

## 2 缺口清单（按 S8c 分片顺序）

| 片 | 缺口 | 动作 | 依赖 |
| --- | --- | --- | --- |
| B-1 | ~~可选链 `?.` 无样例~~ | **已补** `examples/58_optional_chain`（2026-11-26，compile + 运行）；S8c 复核是否需要补 `?[` 与 `m?["k"]` 形态 | 无（语言已实现） |
| B-1b | ~~自定义下标（§4.64）无样例~~ | **已补** `examples/59_custom_subscript`（2026-11-26，读 + 写一对）；S8c 待补「只读报错、`+=` / `&x[k]` 拒绝」的说明段与 S2 的按键分派样例 | 无（语言已实现） |
| B-2 | `match` / `defer` / `errdefer` / `?` / `ref` / 泛型 trait 各只有 1–2 个样例 | 每个特性补一份「正常路径 + 一个反直觉点」的样例 | 无 |
| B-3 | `String` / `Str` 样例仍以 `char *` 混写 | 改写 `40_str_ownership`、`48_string_steps`，只保留 C 互操作处的指针 | 无 |
| B-4 | 非 C 互操作用例的指针 | 59 个 `char *` / 83 个 `->` / 14 个 `malloc` 逐条判定：迁 `String`/`Vec`/`Box` 或写例外理由 | B-3 |
| B-5 | 文档可执行片段只有 3 个（`docs/snippets/README/`）+ 2 个教程用例 | 为矩阵里每个「有」档特性至少一个 `// source:` 片段 | B-1…B-4 |
| B-6 | S2 下标协议、S3 函子、S4–S6 模式 | 实现落地时同批补样例（先负例后正例） | S2–S6 |

## 3 保留的 C 互操作例外（不要求去指针）

`examples/55_c_boundary_shim`、`examples/c-superset/**`、`examples/54_freestanding_alloc`、
`examples/tour/**` 的 shim 段、`.m.ct` / `.shim.*` / `#ct-raw` 相关夹具——每条例外都要在 S8c 的
改写提交里写明「为什么必须指针」。完整清单在 S8c 首片落盘。

## 4 指针现数（2026-11-26）

| 指标 | 数值 |
| --- | --- |
| `examples/**/*.ct` | 225 个文件 / 59 个目录 |
| 含 `char *` | 59 |
| 含 `->` | 83 |
| 含 `malloc` | 14 |

与 [TEST-27](../../issues/testing/test27-feature-examples-pointer-free.md) §1.1 的 2026-11-26 快照一致；
指针清零的目标与例外规则见该 issue §3。

## 5 关联

- [TEST-27](../../issues/testing/test27-feature-examples-pointer-free.md)（B 轨道）
- [`v1-PH-2`](../phases/v1-PH-2/card.md)（S8c）
- [dogfooding](dogfooding.md)（S8b，源码侧；与本矩阵文件集不重叠）
- [language-spec](../language-spec.md)（每行 § 引用）
- [pointer-free-v2](../proposals/pointer-free-v2.md)
