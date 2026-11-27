# examples 去指针：逐文件判定与例外清单（S8c 输入）

> 状态：**判定完成（2026-11-27）**，对应 [TEST-27](../../issues/testing/test27-feature-examples-pointer-free.md) 的 B 轨道 B-3/B-4。
> 本文件只做**逐文件判定**与例外理由；改写动作在 S8c 按分片执行，已完成的改动在 §5 记录。

## 0 口径

```sh
# 有真实指针用法的文件（排除 impl 的 self-> 接收者语法与 cstr() 返回）
python3 - <<'PY'
# 见 §1 的规则；等价手写命令：
grep -rlE '\bchar\s*\*|(?<!self)->|\bmalloc\s*\(' examples --include='*.ct'
PY
```

- `examples/**/*.ct` 共 **225** 个文件；含上述模式的 **116** 个，去掉只有 `self->` 与
  `x.cstr()` 的以后，**101** 个文件有真实指针用法；
- `self->field` 是 Ct 的接收者语法，不算用户指针；`cstr()` 是 String/Str 的 C 字符串出口，
  单独归入 E3（见 §2）；
- 判档只看**文件**，不按行数；一个文件可同时命中两类，按「最需要保留指针的理由」归类。

## 1 分类结果

| 类 | 含义 | 文件数 | 处置 |
| --- | --- | --- | --- |
| E1 | C 互操作 / 边界：`.m.ct`、`*.shim.h`、板级头、`c-superset`、type host | 41 | **保留**，显式 allow + 理由（§3） |
| E2 | 生命周期与句柄语义演示：`own` / `delete` / Drop / 构造位置 | 11 | **保留**，指针是课题本身（§3） |
| E3 | 字符串打印受阻：`char *` 只用于 `%s` / `cstr()` | 26 | **阻塞**：等 print API 决策（§4） |
| E4 | 结构体 / 接口值指针：只有 `p->f`，没有 `char *` | 15 | **保留**：语言暂无等价引用形态（§3） |
| M | 可迁移 | 8 | 已迁 2 个，其余 6 个各有结构理由（§5） |

## 2 E3：打印受阻（26 个）

这些文件的 `char *` 全部来自「字符串字段 / 字符串形参 → `printf("%s", …)`」。
语言目前**没有** `Str` / `String` 的直接打印入口：

| 事实 | 位置 |
| --- | --- |
| `String.cstr()` / `Str.cstr()` 分配一份 C 字符串，调用方负责 `free` | `lib/core/String.h.ct:118-119`、`lib/core/Str.h.ct:122` |
| `lib/core` 没有 `print` / `puts` 一类文本出口 | `grep 'pub .*print' lib/core/*.ct` → 无命中 |
| `printf` 的 `%s` 需要 C 字符串 | C 语义，`spec §4.67` 只补头，不做格式转换 |

因此把 E3 的字符串改成 `Str` 只会把 `char *` 换成 `.cstr()` + `free`，**指针没有消失，反而多一次分配**。
在拿到打印入口之前，E3 的 26 个文件保持现状，并在 S8c 标注「等 print API」。

涉及文件：`01_greeter`、`02_market`、`03_receivers`、`04_rvalue`、`18_generic_string_table`、
`19_container_each_generic`、`21_generic_bound`、`22_foreach_map`、`23_generic_stack`、`25_wordcount`、
`26_range_vec`、`27_map_keys`、`29_into_block`、`30_iface_container`、`32_container_subscript`、
`34_map_literal`、`35_type_safety`、`39_generic_trait`、`45_error_return_contract`、`46_result_try`、
`62_try_cleanup`、`65_generic_trait_instances`、`tour/01_vtable/two_impls`、`tour/02_iface_value/param`、
`tour/02_iface_value/return_pick`、`tour/11_variadic/forward`。

## 3 保留类：E1 / E2 / E4（67 个）

### 3.1 E1 C 互操作与边界（41 个）

理由：这些文件本身就是「Ct ↔ C」的接缝，指针是 ABI 的一部分。

| 子类 | 文件 |
| --- | --- |
| `.m.ct` 映射单元（`#include` + recipe） | `08_map_binding/src/type_bridge`、`13_builder_chain/src/builder`、`14_scalar_host/src/host`、`17_static_map_closure/src/seq`、`47_chain_factory/src/http`、`48_string_steps/src/text`、`55_c_boundary_shim/src/lib`、`tour/05_map_type/chain/route`、`tour/05_map_type/scalars/units`、`tour/06_type_alias/handle/io`、`tour/07_map_namespace/static/sys`、`tour/08_shim/compiled_source/tick`、`tour/08_shim/header_inline/csv` |
| 宿主入口 / 消费方（`char *` 来自映射签名） | `13_builder_chain/src/main`、`14_scalar_host/src/main`、`47_chain_factory/src/main`、`48_string_steps/src/main`、`tour/05_map_type/scalars/main`、`tour/07_map_namespace/dynamic`、`tour/08_shim/header_inline/main`、`tour/15_memory/manual_shim/main`、`38_ecosystem_reuse/src/main` |
| `c-superset`（C 形态逐条对照） | `s05_union/nested`、`s05_union/tagged`、`s08_static_local/counter`、`s08_static_local/lazy_table`、`s09_compound_literal/designated`、`s09_compound_literal/neg_ptr`、`s11_type_words_inline/regs`、`s11_type_words_inline/words`、`s15_multi_declarators/list`、`s17_init_length/keywords`、`s17_init_length/long_item`、`s20_c11/generic`、`s21_attribute/packed`、`s22_int_suffixes/suffixes`、`s25_assignment_value/parse`、`s25_assignment_value/targets`、`s26_variadic_fnptr/logger`、`s26_variadic_fnptr/table` |
| 裸机 / freestanding | `54_freestanding_alloc/src/main` |

### 3.2 E2 生命周期与句柄演示（11 个）

理由：课题就是「所有权在指针上如何转移 / 何时释放」，改掉指针等于删掉样例。

`52_box_new`、`tour/15_memory/borrow_delete`、`tour/15_memory/borrow_handback`、
`tour/15_memory/drop_loop_break`、`tour/15_memory/drop_paths`、`tour/15_memory/field_cascade`、
`tour/15_memory/field_cascade_missed`、`tour/15_memory/leak_warning`、`tour/15_memory/own_factory`、
`tour/18_ctor/four_positions`、`tour/18_ctor/heap_row`。

### 3.3 E4 结构体 / 接口值指针（15 个）

理由：`p->f` 出现在结构体指针、接口值字段（`Node *node` + `w.node->show()`）与回调环境上；
Ct 目前没有「结构体引用」这一形态，`ref struct` 只在形参位置可用，不能替代字段与局部变量。

`05_body_dispatch`、`06_iface_field`、`07_dialect/registry`、`09_callback/callback`、
`09_callback/callback_tier2`、`28_subscript_forms`、`36_bounded_struct`、`tour/01_vtable/minimal`、
`tour/03_iface_field/ptr_field`、`tour/03_iface_field/value_field`、`tour/04_map_instance/ns_qualified`、
`tour/04_map_instance/two_instances`、`tour/09_closure/pair_by_hand`、
`tour/12_multiunit/cross_unit_iface/main`、`tour/17_cli/emit_map_instance`。

## 4 M：可迁移的 8 个

| 文件 | 判定 | 处置 |
| --- | --- | --- |
| `40_str_ownership` | `char *uc = u.cstr(); free(uc)` 是唯一的混写 | **已改**：改用 `as_str()` 取借用视图；`own String *` 段保留（`new String` 明确不支持，Drop-on-handle 只能堆上演示） |
| `59_custom_subscript` | 旧版用 `char *` 键（方案 A 只能字符串键） | **已改**：S2 起按参数类型分派，改用 `get(int)` / `set(int,int)`，`string.h` 与指针一起消失 |
| `08_map_binding` | `char *buf` 来自被映射的 C 函数签名 | 保留（C 互操作） |
| `tour/01_vtable/neg_missing_method` | 负例：trait 方法返回 `char *` 属被测形态 | 保留（负例） |
| `tour/04_map_instance/neg_unbound` | 负例：未绑定实例的 `char *` 形参 | 保留（负例） |
| `tour/16_diagnostics/sig_return` | 负例：impl 返回类型写成 `char *` 是诊断主题 | 保留（负例） |
| `tour/17_cli/emit_map_namespace` | `char *buf` 来自被映射的 C 函数签名 | 保留（C 互操作） |
| `wave1-demo` | 外部包 `std::io` 无 `printf`，靠 `char[]` 手工格式化 | 保留（外部包能力缺口） |

## 5 已完成与剩余

| 项 | 状态 |
| --- | --- |
| `40_str_ownership` 去掉 `char *` + `free` | ✅ 2026-11-27（输出改为 `u len=5 view len=5 (source released)`） |
| `59_custom_subscript` 改 int 键（S2 能力） | ✅ 2026-11-27（输出改为 `zero=7 one=8`） |
| `48_string_steps` 标注「为什么必须指针」 | ✅ 2026-11-27（C 类型宿主 + shim，代码不动） |
| `67_adt_patterns` / `68_adt_guards` / `69_generic_adt` | ✅ 2026-11-27（S4/S5/S6 样例，零 `char *` / `->` / `malloc`） |
| E1/E2/E4 的 C 边界显式 allow | ✅ S9 M4 起登记在 `test/c-boundary-allow.tsv`（逐路径 + 理由），不再用文件内注释；`--c-boundary=allow` 只对这些路径生效 |
| E3 的 26 个文件 | ⬜ 等 [LANG-30](../../issues/lang/lang-30-str-print-api.md)（`Str.print()` / `println()`，v1.2 必做） |

## 6 建议的下一步

1. **落地 print API**（方案 A 已批准，见 [LANG-30 施工卡](../design/lang30-str-print-construction.md)），
   否则 E3 的 26 个文件无法真正去指针；已立 [REQ-PRINT-1](requirements-pool.md) /
   [LANG-30](../../issues/lang/lang-30-str-print-api.md)；
2. E1/E2/E4 的 C 边界 allow 已在 `test/c-boundary-allow.tsv` 登记，不再逐文件加注释；
3. E4 的长期解是「结构体引用」形态；在那之前不要为去指针而把样例改成 `self` 方法（会改变教学点）。

## 7 关联

- [TEST-27](../../issues/testing/test27-feature-examples-pointer-free.md)
- [feature-examples-matrix](feature-examples-matrix.md)（特性维度；本文件是文件维度）
- [pointer-free-v2](../proposals/pointer-free-v2.md)
- [S8c](../phases/v1-PH-2/card.md)
