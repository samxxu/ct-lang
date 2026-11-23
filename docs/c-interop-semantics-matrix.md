# 附录：C Interop Semantics Matrix（DOC-92）

> 中文
>
> 本文是 [guide-for-c-programmers](guide-for-c-programmers.md) 的附录（g4 拆分，guide §10 有入口），
> **不是平行规范**：它只做索引与判定，语义仍以 [language-spec](language-spec.md) 的节号为准。
> `stable-subset` 的档位表也不因本表改动；本表只回答“这条 C 语义走哪条边界”。
>
> **边界三值**
>
> - **透传**：Ct 接受并原样交给 C 编译器，语义由 C 决定；
> - **strict 禁区**：`.ct` / `.h.ct` 在默认 strict 下硬错，出口是 `.m.ct`、shim 或 `#ct-raw`
>   （`#ct-raw` 只在 `.m.ct` / `.shim.c` 合法）；
> - **shim**：必须经手写 C 适配层；作者义务见 [C Shim 契约](c-shim-contract.md)。
>
> 证据等级：测试/探针证明“当前 Ct 这样做”，不证明真板行为；DMA 真搬运仍归
> [TEST-22](../issues/testing/test22-dma-real-transfer-hardware-gated.md)。

## 1. 矩阵

| 语义项 | Ct 行为 | 边界（透传 · strict 禁区 · shim） | 权威节 + 证据 |
| --- | --- | --- | --- |
| 指针与空指针 | 指针是一等类型；`0` 是空指针常量；`NULL` 只是全大写宏名，Ct 不定义；`own p = 0` 的释放有 `if (p)` 守卫 | **透传**（指针/`0`）；`NULL` 来自系统头，在 strict `.ct` 里属**禁区**，由 shim 或 `0` 提供 | [§1.2](language-spec.md#12-兼容承诺v10-起不再自称-c-超集)、[§4.66](language-spec.md#466-c-边界c-boundary-与-shimphase-65仅-ct-ast)；[246_own_null](../test/ast/246_own_null/prog.ct)、[17_param_array](../test/ast/17_param_array/prog.ct) |
| `const` / `volatile` | 类型限定词原样发射；`volatile` 用于 MMIO；`const` 只表示不写；无额外别名/数据竞争检查 | **透传**；语义由 C 与目标编译器负责 | [§4.23](language-spec.md#423-内置类型词与-inlinect-ast)；[39_builtin_types](../test/ast/39_builtin_types/prog.ct)、[56_header_compat](../test/ast/56_header_compat/prog.ct) |
| 数组与指针衰变（`T a[]` 弃用口径） | `T a[N]` 是 C 数组；`T[]` 是切片 `{ptr,len}`；`T a[]` 作形参/字段/无初值声明 v0.x 警告、v1.0 起硬错；`T a[] = { … }` 保留为推断长度数组；`--lib` 导出数组参数 decay 成指针 | **透传**（`T a[N]`）；`T a[]` 弃用位置是 **strict 禁区（v1.0 起）**；shim 侧只用 `T *` / `T a[N]`，不用 `T[]` | [§4.69](language-spec.md#469-切片-tphase-79仅-ct-ast)、[§1.2](language-spec.md#12-兼容承诺v10-起不再自称-c-超集)；[06_arrays](../test/ast/06_arrays/prog.ct)、[17_param_array](../test/ast/17_param_array/prog.ct)、[p108_multidim_param.sh](../test/ast/p108_multidim_param.sh) |
| struct 布局、padding、alignment | 纯 C struct 按 C 规则；`_Alignas` / `__attribute__((aligned/packed))` 原样透传；`use Trait` 会追加 vptr，布局与纯 C 不同；ADT 布局冻结且无 vtable | **透传**（纯 C struct）；含 vptr 的 Ct struct **不能**直接当 C ABI；跨边界用显式字段镜像 | [§4.35](language-spec.md#435-c11-对齐与泛型选择ct-ast)、[§4.36](language-spec.md#436-gnu-__attribute__ct-ast)、[§4.73](language-spec.md#473-最小-adt-与-matchphase-84仅-ct-ast)；[53_c11_align_generic](../test/ast/53_c11_align_generic/prog.ct)、[56_header_compat](../test/ast/56_header_compat/prog.ct) |
| enum 与整数转换 | 无负载 `enum` 保持 C enum：成员是 file-scope `int` 常量，隐式整数转换同 C；有负载 = ADT，不是 C enum；C 头里的 enum 常量默认不识别（全大写宏名除外），需映射单元包一层 | **透传**（无负载 enum）；C 头 enum 常量是 **strict 禁区 → shim**；ADT 不映射成 C enum | [§4.14](language-spec.md#414-enum常量表达式与-offsetofct-ast)、[§4.43](language-spec.md#443-外部-c-符号ct-认识哪些不认识哪些doc-64)、[§4.73](language-spec.md#473-最小-adt-与-matchphase-84仅-ct-ast)；[30_enum](../test/ast/30_enum/prog.ct)、[271_qualified_enum](../test/ast/271_qualified_enum/prog.ct)、[p72_qualified.sh](../test/ast/p72_qualified.sh) |
| bit-field | 支持位宽、无名填充、整数类型；宽度是整数常量表达式且不折叠；`offsetof` 取位域是 C 的 UB；`ref/out` 不能取位域 | **透传**（C struct/union 内）；共享 ABI struct 不建议用位域；shim 侧由 C 自行处理 | [§4.17](language-spec.md#417-位域ct-ast)、[§4.68](language-spec.md#468-ref--out-参数phase-78仅-ct-ast)；[33_bitfield](../test/ast/33_bitfield/prog.ct)、[p78_basic.sh](../test/ast/p78_basic.sh)（位域不可作 `ref/out` 实参） |
| 函数指针与调用约定 | 声明/调用/字段/typedef/数组均支持；不返回函数指针、不支持嵌套函数指针；闭包发射 `(fn, env)`；调用约定是 C 默认；`--lib` 可导出函数指针签名 | **透传**（C 函数指针）；Ct 闭包不是 C 函数指针，跨边界要 `void *env` 协议；C++ 调用约定**不承诺** | [§4.12](language-spec.md#412-函数指针ct-ast)、[§4.44](language-spec.md#444-闭包phase-21仅-ct-ast)、[§4.57](language-spec.md#457-c-abi-静态库ct-build---libphase-39仅-ct-ast)；[21_fnptr](../test/ast/21_fnptr/prog.ct)、[27_fnptr_forms](../test/ast/27_fnptr_forms/prog.ct)、[25_fnptr_libfn](../test/ast/25_fnptr_libfn/prog.ct) |
| variadic | 参数表末尾可写 `...`，前面至少一个具名参数；`va_list` / `va_arg` 内建；trait 方法不能变参（`.m.ct` 静态 trait 例外）；C 变参 API 要 shim 包成固定参数 | **透传**（直接调用 C 变参函数）；trait/vtable 变参是 **strict 禁区**；`.m.ct` 可把 `...` 原样转发给 shim | [§4.22](language-spec.md#422-变参函数ct-ast)、[§4.31](language-spec.md#431-变参函数指针ct-ast)；[38_variadic](../test/ast/38_variadic/prog.ct)、[47_vararg_fnptr](../test/ast/47_vararg_fnptr/prog.ct) |
| `setjmp` / `longjmp` | Ct 不定义 `jmp_buf` / `setjmp` / `longjmp`；longjmp 跨 Ct 帧会跳过 `defer` / `errdefer` / Drop，**禁止**；编译器内部自用不算用户契约 | **strict 禁区**（`#include <setjmp.h>`、`jmp_buf` 类型、extern 原型）**→ shim**；shim 只能在 C 侧内部跳转，不得跳回 Ct 调用者 | [§4.66](language-spec.md#466-c-边界c-boundary-与-shimphase-65仅-ct-ast)、[§4.58](language-spec.md#458-errdefererr-错误出口与尾随声明phase-40仅-ct-ast)、[§4.9](language-spec.md#49-autodropphase-5-新增仅-ct-线)；[core.ct](../selfhost/l2/core.ct) 的内部用法、[p65_include.sh](../test/ast/p65_include.sh) |
| `restrict` | `restrict` / `__restrict` / `__restrict__` 是类型限定词，原样发射；不做别名检查，别名 UB 由 C 承担 | **透传** | [§4.23](language-spec.md#423-内置类型词与-inlinect-ast)、[§4.37](language-spec.md#437-整数字面量后缀与其余-c-拼写ct-ast)；[39_builtin_types](../test/ast/39_builtin_types/prog.ct)、[55_c_compat](../test/ast/55_c_compat/prog.ct) |
| 宏与预处理器（strict 边界） | Ct 无预处理器：`#include` 只整行透传；全大写标识符按宏放行；小写 `#define` 不展开；对象式宏可在 `.m.ct`；函数式宏只在 `.m.ct` / `.shim.c` | **透传**（全大写宏、`#include` 整行）；`.ct` 内 `#include` 与函数式宏是 **strict 禁区 → `.m.ct` / shim**；对象式宏在 `.m.ct` 允许 | [§4.66](language-spec.md#466-c-边界c-boundary-与-shimphase-65仅-ct-ast)、[§4.43](language-spec.md#443-外部-c-符号ct-认识哪些不认识哪些doc-64)、[§4.41](language-spec.md#441-raw-透传ct-rawphase-173仅-ct-ast)；[p65_raw_extern.sh](../test/ast/p65_raw_extern.sh)、[p65_map.sh](../test/ast/p65_map.sh)、[08_shim/header_inline](../examples/tour/08_shim/header_inline/csv/fields.shim.h)、[65_raw](../test/ast/65_raw/prog.ct) |
| attribute / section / interrupt | `__attribute__((…))` 原样捕获并按声明尾部/前缀位置重发；Ct 不解释 `section` / `interrupt`；向量表与中断处理函数放 C（`startup.c` / `board.c`）或 `.m.ct` 的 `#ct-raw` | **透传**（属性文本）；`.ct` 内 `#ct-raw` 是 **strict 禁区 → shim / `.m.ct`**；`interrupt` 语义由 C 编译器与启动文件决定 | [§4.36](language-spec.md#436-gnu-__attribute__ct-ast)、[§4.41](language-spec.md#441-raw-透传ct-rawphase-173仅-ct-ast)、[§4.66](language-spec.md#466-c-边界c-boundary-与-shimphase-65仅-ct-ast)；[54_attribute](../test/ast/54_attribute/prog.ct)、[startup.c](../test/baremetal-renode/startup.c)、[board.c](../test/baremetal-renode/board.c) |
| inline assembly | Ct 无内联汇编语法；`__asm__ volatile` 只能出现在 `.m.ct` 的 `#ct-raw` 或 `.shim.c`；无分析、无跨平台承诺 | **strict 禁区**（`.ct` / `.h.ct`）**→ shim / `.m.ct`**；`#ct-raw` 内容原样交给 C | [§4.41](language-spec.md#441-raw-透传ct-rawphase-173仅-ct-ast)、[§4.66](language-spec.md#466-c-边界c-boundary-与-shimphase-65仅-ct-ast)；[65_raw](../test/ast/65_raw/prog.ct)、[board.c](../test/baremetal-renode/board.c)（`wfi`） |
| C++ 头文件兼容范围 | Ct 不解析 C++：类、模板、重载、异常、`namespace`、引用都不在语法内；shim 只按 C ABI 导出 | **不承诺**（不是透传，也不是“以后再说”）；需要 C++ 时在 Ct 外写 `extern "C"` 包装，Ct 侧仍只看到 C | [§1.2](language-spec.md#12-兼容承诺v10-起不再自称-c-超集)、[§4.57](language-spec.md#457-c-abi-静态库ct-build---libphase-39仅-ct-ast)；[bindings 分层表](../test/bindings/README.md)（“不支持 C++ ABI”） |

## 2. 读表规则

1. **先看边界列，再看行为列**：同一行可能“C 写法透传，但 Ct 类型不允许”，例如数组参数
   在 C 侧是 `T *`，在 Ct 侧新代码应写 `T[]`。
2. **strict 禁区不是“永远不能”**：把该行代码移进 `.m.ct` / shim / `.shim.c` 即可；移动后
   按 [C Shim 契约](c-shim-contract.md) 的 N/O/E/D/C/A 条款标注所有权、错误码与上下文。
3. **证据只证明当前实现**：测试路径指向可运行的冒烟或探针；行为若与权威节冲突，以 spec 为准，
   并在本表加一条 issue 链接，不静默改口径。
4. **不新增语义**：本表不改变任何 strict 边界、生成物或语言关键字；需要改边界时走
   [stable-subset](stable-subset.md) 的授权矩阵，不在附录里“顺手放开”。

## 3. 覆盖与未覆盖

- 覆盖 DOC-92 issue 列表的 **14 项**（指针/空指针、`const`/`volatile`、数组衰减、结构布局、
  enum、bit-field、函数指针、变参、`setjmp`/`longjmp`、`restrict`、宏/预处理、attribute/
  section/interrupt、内联汇编、C++ 头文件）；每行都有权威节与至少一条证据。
- **无 `unknown` 行**：`setjmp`/`longjmp` 判为“strict 禁区 → shim”，C++ 判为“不承诺”，
  两者都是明确边界而非未知；若将来出现无法判定的项，必须标 `unknown` 并写阻塞依据
  （issue 或外部规范缺位），不得留空。
- **未覆盖**：厂商 SDK 的逐函数兼容、跨平台 ABI 字节级一致、C++ 互操作、真板 DMA 数据流。
  前三项是明确不承诺；最后一项归 [TEST-22](../issues/testing/test22-dma-real-transfer-hardware-gated.md)。
- 维护：新增 C 语义先在矩阵加行，再补权威节与证据；行数增长超过 300 行时按 g4 再拆，
  不把本表并回 guide 正文。
