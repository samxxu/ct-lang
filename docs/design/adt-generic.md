# 泛型 ADT：`enum Opt<T>`（v1-PH-2 S6）

> 状态：**实现设计（2026-11-27）**。对应 [v1-PH-2](../phases/v1-PH-2/card.md) 的 S6、
> [REQ-ADT-PATTERN-1](../planning/requirements-pool.md) 的最后一段。语言口径落在
> [spec §4.73](../language-spec.md#473-最小-adt-与-matchphase-84仅-ct-ast) 的
> 「S6 泛型 ADT」小节；S4/S5 的模式文法见 [adt-patterns](adt-patterns.md)。

## 1 范围

| 能力 | S6 | 说明 |
| --- | --- | --- |
| `enum Opt<T> { Some(T v), None() }` | 做 | 参数可带一个 trait bound（与泛型 struct 同规则） |
| `enum Res<T, E>` | 做 | 任意参数个数，元数由声明决定 |
| 类型实参替换 | 做 | 负载字段逐参数替换；嵌套实例解析到 C 标签 |
| 构造 `Opt<int>.Some(v)` | 做 | 模板 impl 体内可写 `Opt<T>.Some(v)` |
| 模式 `Opt.Some(v)` / `Opt<int>.Some(v)` | 做 | 前者从主语推断实例，后者显式 |
| 布局 | 做 | 每个 `(模板, 实参)` 一个 `struct <encoded>`，tag + union |
| `impl<T> Opt<T>` 方法 / 下标 | 做 | 与非泛型 ADT 的固有方法同一条路径 |
| `Box<Opt<int>>` / `Vec<Opt<int>>` | 做 | 实例是普通 ADT 值；owning 负载触发实例 retain/release |
| 递归 | 按值拒绝 | 指针 / 容器可以递归 |
| 泛型 C enum | 仍拒绝 | 保持 L34-3 的 `generic enums are not supported` |
| 与内置 `Option` / `Result` 同名 | 拒绝 | 内置层已是泛型 struct；同名会在实例表里冲突 |

## 2 数据模型

- `struct Adt` 增加模板侧字段：`is_template`、`ntparams`、`tparams`、`tmpl`、`emitted`。
- 模板行：源码名 / `full` 是声明名，变体与负载保留 `T` 等符号拼写；**不发射布局**。
- 实例行：`name == full == <encoded>`（如 `Opt_int`），`tmpl` 指向模板行，变体按声明
  顺序复制，负载字段是替换后的具体 C 拼写；`emitted` 保证一个实例只写一次。
- 模板同时登记进 `StructTmpl`（`is_adt = 1`、`adt = <模板行>`），这样
  `parse_type_text` 的 `Name<args>` 分支、`ct_inst_add` 的实例身份和泛型 impl 查找
  都复用泛型 struct 的既有机制。

## 3 实例化

1. `parse_enum_def` 在读到 `pre_adt` 后、读成员前先登记模板行：负载可能自引用
   （`List<T> *next`），必须先让 `List<...>` 能被类型解析器识别。
2. `parse_type_text` 把 `Opt<int>` 交给 `parse_inst_type`；`inst_make` 创建
   `StructInst` 身份，并调用 `ct_adt_inst_add` 生成具体 ADT 实例行。
3. 替换用 `ct_generic_subst_text`，实参用 `cargs`（C 拼写，`struct Vec_int`）。
4. 负载里的嵌套实例先经 `inst_register_nested` 登记，再由 `ct_inst_resolve` 变成
   `struct <encoded>`；布局闭包与打印器只看到具体拼写。
5. 同一个编码名只建一行（`ct_adt_find(full)` 命中即复用）。

## 4 布局

实例的 C 形状与非泛型 ADT 完全一致：

```c
struct Opt_int {
    int tag;
    union {
        struct { int v; } Some;
    } u;
};
```

四条 `_Static_assert` 同一份 `emit_adt_layout_body` 写出；owning 负载（`String` /
容器 / `Box` / 嵌套 ADT）生成 `Opt_int_retain` / `Opt_int_release`。按值嵌套的实例
（`Opt<Opt<int>>`）由 `preemit_adt_payload` 先写内层；指针/数组负载不是布局依赖。
按值自引用 / 互引用由 `adt_layout_closure` 判为硬错。

## 5 构造与模式

- **构造**：`Opt<int>.Some(expr)`。`parse_adt_ctor` 先用 `parse_type_text` 读完整类型，
  因而实例一定已登记；模板 impl 体内的 `Opt<T>.Some(...)` 保留符号拼写，由发射器的
  `adt_row_for_emit` 在 `ginst` 绑定的实例上解析。
- **模式**：`pat_parse_atom` 以原始源码判断 `Type<...>.Variant(`；显式形式用
  `parse_type_text`，推断形式仍走旧路径。模板与实例视为同一个和类型（实例的
  `tmpl` 指向模板），变体顺序与负载类型取实例行。
- **穷尽**：实例是普通 ADT 行，S4/S5 的算法直接适用；S6 不新增穷尽规则。

## 6 AST / TIR / LIR

- AST：`N_ADTCTOR.text` 对具体实例存 `adts[adi].full`（`Opt_int`），对模板 impl 体
  存符号拼写（`Opt<T>`）；`N_MATCH.text` 对具体实例存实例 tag，对模板 impl 体存模板
  tag。发射器统一经 `adt_row_for_emit` 解析。
- TIR：`tb_record_adts` 把模板与实例行都复制进模块 ADT 表；具体实例的
  `TK_ADT_CTOR` / `TK_MATCH_ARM` 用实例 tag 直接命中。
- LIR：泛型 impl 方法本身不在 `ct_lir_try_body` 的可发射集合里，整函数回退 AST body
  seam；具体实例的构造/匹配走 LIR 的既有 `LE_ADTCTOR` / `LE_MATCHEXPR`。
  `--ir=on` 与 AST 路径逐字节相同（308–312 五个夹具逐一 `cmp`）。

## 7 容量与诊断

- ADT 表、模板表、实例表都倍增到 `CAP_LIMIT`（65536）；`cap_adt.sh` 新增 70 个泛型
  ADT 模板的生成用例。
- 新增/改写的诊断：
  - `generic ADT '<N>' needs type arguments in a type position`
  - `generic ADT '<N>' takes <n> type arguments, <m> given`
  - `generic ADT '<N>' conflicts with an existing generic type of the same name`
  - `ADT '<N>_…' is recursive by value; store a pointer or a container instead`（沿用
    布局闭包的既有文本）
- 泛型 C enum 仍报 `generic enums are not supported`（L34-3）。

## 8 测试

| 夹具 | 覆盖 |
| --- | --- |
| `test/ast/308_adt_generic_option` | `Opt<T>` 声明 / 构造 / 推断与显式模式 |
| `test/ast/309_adt_generic_result` | 双参数、`char *` 列、变体负载 |
| `test/ast/310_adt_generic_nested` | `Opt<Pair<int>>`、`Opt<Opt<int>>`、嵌套布局 |
| `test/ast/311_adt_generic_box_vec` | `Vec<Opt<int>>`、`Box<Opt<int>>`、`at()` |
| `test/ast/312_adt_generic_methods` | `impl<T> Opt<T>` 方法、静态方法、下标读 |
| `test/ast/p86_adt_generic.sh` | 去重、容器、裸类型、元数、`void`、递归、泛型 C enum、同名冲突 |
| `test/ast/cap_adt.sh` | 70 个泛型 ADT 模板跨旧容量 |

## 9 边界（诚实登记）

- 内置 `Option` / `Result` 是泛型 **struct**（`{1, v}` 初始化、`has`/`value` 字段）；
  同名泛型 ADT 会与既有泛型类型冲突，S6 报硬错而不是合并两套实例。
- 泛型 typedef ADT 未扩展；`typedef enum Opt<T> { … } Alias;` 仍只得到具体别名。
- 泛型 ADT 的模式里 `Type<...>` 只接受类型实参；结构体模式 `S<...> { … }` 不在 S6。
- 下标写（`a[0] = v`）仍按 ADT 固有 `set` 方法；负载按值绑定，方法内改绑定不会回写，
  与非泛型 ADT 相同。
