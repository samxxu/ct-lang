# P-7.4-3：既有 `test/ast` / `examples` / std 消费者逐项跑

baseline: c3f2e0ea

> 日期：2026-11-20；DEV（隔离原型 `/tmp/p74`，由 [run.sh](run.sh) 重建）
> 原型补丁：[prototype.patch](prototype.patch)；[D-013](../../../decisions/D-013.md) §1.3。
> 主仓未改 `selfhost/**`、`lib/std/**`、`test/**`；本文件只记录消费者清单与实测结果。

## 0. 结论

| 项 | 结果 |
| --- | --- |
| 消费者清单 | `test/ast` **11** 个、`examples` **1** 个、`lib/std` 层 1 处 key 块；见 §1 |
| 逐项跑（11 + 1） | **11/11 + 1/1 全部命中迁移清单**：每个都给出预期类别的硬错，见 §3 |
| 非消费者对照 | `examples/27_map_keys` 仍编译通过（只在注释里提 `Str`） |
| std 消费者 | `Vec`/`Option`/`Result` + `Map<String,V>` 冒烟通过；`Map<Str,V>` 硬错见 `map_str.md` |
| 全量 `check-ast.sh` | **1502 passed / 25 failed / 3 skipped**（25 个 FAIL 全部归类，见 §4；无未归类失败） |
| 退出码 | 消费者 harness 0；全量 suite 1（预期，因 25 个 FAIL） |

迁移清单是 P-7.4-3 的产物；按 0.7 的签收规则，清单本身随 C-5 证据交 EDITOR 签收，本文件只给
逐项原始结果，不代替签收。

## 1. 消费者清单

判据：`test/ast` / `examples` / `lib/std` 的 `.ct` 源码中出现 `Str` 类型或旧 `str_*` 函数。

| # | 文件 | 旧用法 | 迁移动作 |
| --- | --- | --- | --- |
| 1 | `test/ast/225_generic_drop/prog.ct` | `Str` 作为泛型实参/字段，依赖 owning 的赋值语义 | 改 `std::str::Str`；或在 S5b 改 `String` |
| 2 | `test/ast/227_vec_element_release/prog.ct` | `str_from(...)` 返回 owning `Str` | `String s = str_dup(...)` / `Str v = "..."` |
| 3 | `test/ast/230_str_embedded_nul/prog.ct` | `str_from_len` 后直接链式取 `.data` | 先绑定 `Str`，再 `.data`/`.byte_slice` |
| 4 | `test/ast/231_str_ops/prog.ct` | `str_slice`/`str_concat`/`release` | `str_slice`→借用视图；深拷贝→`str_dup`；`release`→`String.release` |
| 5 | `test/ast/232_str_own_pointer/prog.ct` | `own Str *` + `delete` | 旧 owning 改 `std::str::Str`（有 Drop），或 `String` |
| 6 | `test/ast/241_map_str_key/prog.ct` | `Map<Str,int>` + owning key | `Map<String,int>`，key 深拷贝由 `put` 内部完成 |
| 7 | `test/ast/242_map_str_release/prog.ct` | `Map<Str,...>` 的 release 语义 | 同上；key 由条目释放 |
| 8 | `test/ast/286_generic_ptr_field/prog.ct` | `Map<Str,...>` | 同上 |
| 9 | `test/ast/p50_sanitize/prog.ct` | `Map<Str,...>` | 同上 |
| 10 | `test/ast/p50_str_has/prog.ct` | `Map<Str,...>.has` | 同上（借用查找签名不变） |
| 11 | `test/ast/p50_table/prog.ct` | `Map<Str,...>` | 同上 |
| 12 | `examples/40_str_ownership/str_ownership.ct` | 旧 `Str` 的 retain/release/Drop/`own Str *` | 旧 owning 改 `std::str::Str`，或整体改 `String` |
| — | `lib/std/Vec.h.ct` 的 `impl<V> Map<Str,V>` 块 | 把 `Str` 当 owning key（`str_from_len`/`Str_retain`） | S5b 删除该块，改由 `Map<String,V>`（本原型在 `lib/std/Str.h.ct` 新块） |

`lib/std/Str.h.ct` 是类型定义本体，不算消费者；`lib/std/README.md` 的文字不在编译范围。

## 2. 命令

```console
$ cd /tmp/p74-evidence
$ CT_AST=test/p74/.build/ct-ast bash test/p74/migration.sh   # 11+1 消费者 + 非消费者 + std 冒烟

# 全量（约 10 分钟）：
$ bash selfhost/check-ast.sh
```

## 3. 逐项原始输出（消费者 harness）

```console
$ CT_AST=test/p74/.build/ct-ast bash test/p74/migration.sh
PASS test/ast/225_generic_drop/prog.ct (migration required: assignment target is not assignable)
PASS test/ast/227_vec_element_release/prog.ct (migration required at cc: str_from)
PASS test/ast/230_str_embedded_nul/prog.ct (migration required: method call on a temporary)
PASS test/ast/231_str_ops/prog.ct (migration required: no method 'release')
PASS test/ast/232_str_own_pointer/prog.ct (migration required: does not use trait 'Drop')
PASS test/ast/241_map_str_key/prog.ct (migration required: borrowed view)
PASS test/ast/242_map_str_release/prog.ct (migration required: borrowed view)
PASS test/ast/286_generic_ptr_field/prog.ct (migration required: borrowed view)
PASS test/ast/p50_sanitize/prog.ct (migration required: borrowed view)
PASS test/ast/p50_str_has/prog.ct (migration required: borrowed view)
PASS test/ast/p50_table/prog.ct (migration required: borrowed view)
PASS examples/40_str_ownership/str_ownership.ct (migration required: does not use trait 'Drop')
PASS examples/27_map_keys (no bare Str value, still compiles)
PASS lib/std consumers (Vec/Option/Result + Map<String,V>) behave
summary: 14 passed, 0 failed (13 consumers on the migration list)
$ echo $?
0
```

几个代表性原始诊断：

```console
$ test/p74/.build/ct-ast --allow-c-boundary test/ast/231_str_ops/prog.ct -o /tmp/n.c
test/ast/231_str_ops/prog.ct:22:1: error: no method 'release' for type 'struct Str'
$ echo $?
1

$ test/p74/.build/ct-ast --allow-c-boundary test/ast/241_map_str_key/prog.ct -o /tmp/n.c
test/ast/241_map_str_key/prog.ct:15:19: error: Map key type 'Str' is a borrowed view; use 'String' (owning) or the legacy 'std::str::Str'
$ echo $?
1

$ test/p74/.build/ct-ast --allow-c-boundary examples/40_str_ownership/str_ownership.ct -o /tmp/n.c
examples/40_str_ownership/str_ownership.ct:26:1: error: struct 'Str' does not use trait 'Drop'
$ echo $?
1
```

`227_vec_element_release` 是**唯一在 cc 阶段**失败的消费者：ct-ast 把未知的 `str_from` 当作 C 透传，
生成的 C 在 `-Wall -Wextra -std=c99` 下报 `call to undeclared function 'str_from'`；harness 因此按
cc 阶段断言。

std 冒烟输出：

```console
$ /tmp/std_smoke
vec=3 option=7 result=9 map=1
map_release=0
$ echo $?
0
```

## 4. 全量 `check-ast.sh`

```console
$ bash selfhost/check-ast.sh
...
== summary: 1502 passed, 25 failed, 3 skipped ==
$ echo $?
1
```

25 个 FAIL 逐条归类（无未归类项）：

| 组 | 项 | 分类与原因 |
| --- | --- | --- |
| A（11） | `225_generic_drop`、`227_vec_element_release`、`230_str_embedded_nul`、`231_str_ops`、`232_str_own_pointer`、`241_map_str_key`、`242_map_str_release`、`286_generic_ptr_field`、`p50_sanitize`、`p50_str_has`、`p50_table` | **迁移清单**（§1）：旧 owning `Str` 用法，逐个硬错/cc 失败 |
| B（1） | `examples/40_str_ownership/str_ownership.ct` | **迁移清单**（§1）：`delete` 借用 `Str` 硬错 |
| C（7） | `p39 r5`、`p39 r8`、`p44/drop`、`p47/map-str-key`、`p50/has`、`p36 E36-8 (own Str product)`、`p36 E36-1 (generic Drop product)` | **同一批消费者的 gate 复跑**：p36/p39/p44/p47/p50 的探针复用 A/B 的 `Str` 夹具或符号基线；失败点与 A 相同（`no method 'release'` / `struct 'Str' does not use trait 'Drop'` / `assignment target is not assignable`），不是新问题 |
| D（2） | `p29`（`L31_nested_map_key`、`map_key_bad`） | **诊断文本 golden 更新**：`Map` 允许 key 列表从 `int, long, char *, Str` 改为 `..., String`，两个负例断言的是旧文本；S5b 随迁移同步更新 golden |
| E（4） | `p64_on_demand`、`p64_freestanding`、`baremetal_qemu`、`baremetal_renode` | **原型回归**（见下） |

**4 个原型回归的根因**：本原型的 `U16String.split` 返回 `Vec<U16String>`，而 `Vec` 在
`Str.h.ct` 之前解析；为了让内建层能解析 `Vec`，compile 模式的 `layer_wanted` 在源码含
`Str`/`String`/`U16String` 时也拼接 `Vec`，build 模式又把 `Vec` 单元带进 freestanding/baremetal
产物。于是：

- 裸程序（`p64_on_demand`）多带一个 `Vec` 单元；
- `Str.c` 因 `split` 的实例化需要 `abort`/`realloc`（`p64_freestanding` 的白名单拒绝）；
- 交叉构建（`baremetal_*`）的 `Vec.h` 又 `#include <stdio.h>`，freestanding 环境没有该头。

这 4 项**不是** P-7.4-3 的迁移清单，而是隔离原型把「U16 `split` 放在内建层」的代价。产品化时
`split` 应在 `String/Str` 层之外用一个不依赖 `Vec` 的返回形态（或在 S5b 再引入容器），不能沿用
本原型的层顺序。它们出现在全量日志里，故按失败证据保留，不写成「全绿」。

## 5. 限制

1. **没有“既有测试套件全绿”**：本原型的兼容窗口只到 `std::str::Str` 限定名，旧消费者不改代码
   必然失败；这正是 P-7.4-3 的迁移清单存在的原因。S5b 删除旧类型时必须先完成这 12 个消费者迁移。
2. **“经批准”是流程项**：清单交 EDITOR 签收；本文件不代替签收，也不声称已批准。
3. **消费者判定是文本扫描**（`\bStr\b`），可能含注释命中；上表已人工核对每个文件的真实用法，
   注释命中（`examples/27_map_keys`）被归入非消费者。
4. **examples 只跑了 2 个含 `Str` 的文件**，其余 examples 不含 `Str`；没有逐个跑全量 examples
   （全量 `check-ast.sh` 的 corpus 段覆盖了它们）。
5. **全量 suite 是 Apple clang 21/arm64 一次实测**；换编译器 `p64_*`/baremetal 的行为可能不同。
6. 4 个原型回归不随本证据“修复”，因为修复它们要么把 `split` 移出内建层（改变证据面），要么
   改 freestanding 白名单（改产品 gating）；两者都超出 C-5 的隔离原型范围。
