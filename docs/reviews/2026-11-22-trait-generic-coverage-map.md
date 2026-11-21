# Trait / 泛型组合：报告 7 项 × 现有用例映射

> 目的：回答外部架构评估 P1-3“Trait/泛型组合边界需要系统验证”，先盘点现有证据，
> 只对真实空缺开卡。
>
> 方法：静态盘点 `test/ast` 的用例名与夹具头注释；**本轮未新增/执行探针**，
> 标“部分”的行表示未找到直接对应用例，不等于已确认失败。
>
> 基线：v0.88.3（2026-11-22）。

## 映射表

| # | 报告检查项 | 现有用例 | 判定 | 缺口 / 动作 |
| --- | --- | --- | --- | --- |
| 1 | 泛型实参替换在所有类型位置一致 | [125_generic_type_positions](../../test/ast/125_generic_type_positions/prog.ct)（返回/形参/局部/强转/`sizeof`/`_Alignof`/`offsetof`/`va_arg`）、[128_generic_type_operands](../../test/ast/128_generic_type_operands/prog.ct)、[126_generic_struct_tag](../../test/ast/126_generic_struct_tag/prog.ct) | **已覆盖** | 无 |
| 2 | 函数值、函数指针、返回、字段、数组维度处理类型参数 | 125（返回/形参）、[147_generic_impl](../../test/ast/147_generic_impl/prog.ct)（`T items[4]` 字段/数组）、[145_generic_closure](../../test/ast/145_generic_closure/prog.ct)（闭包对）、[228_pub_generic_fn](../../test/ast/228_pub_generic_fn/prog.ct)（`pub` 泛型函数）；fnptr 下标见 170/171/175/176（非泛型） | **部分** | 未找到“泛型实例作为函数指针/回调槽”的用例（如 `int (*f)(int) = id<int>`）；建议一条探针 |
| 3 | 泛型模板在声明/定义顺序下正确实例化 | [127_generic_name_retry](../../test/ast/127_generic_name_retry/prog.ct)（实例名冲突重试）、[130_generic_build_mode](../../test/ast/130_generic_build_mode/prog.ct)（build 产物扫描）、[131_generic_cross_unit](../../test/ast/131_generic_cross_unit/prog.ct)（跨单元实例体）、147（`impl` 在 struct 后） | **部分** | 未找到“先用后定义 / 前向声明”的泛型模板用例；普通函数有 `order.ct` 口径，泛型未见对应夹具 |
| 4 | Trait impl 完整、方法签名严格匹配 | [57_trait_default](../../test/ast/57_trait_default/prog.ct)、[58_trait_all_default](../../test/ast/58_trait_all_default/prog.ct)、147、[229_inherent_impl](../../test/ast/229_inherent_impl/prog.ct)、`test/ast/errors/generic_impl_missing_method.ct`、[p42_pub](../../test/ast/p42_pub.sh)（pub trait impl 规则） | **已覆盖** | 缺方法已钉；若要把“签名漂移”单独钉成负例，可在既有错误夹具补一条，不必新卡 |
| 5 | 多 Trait 同名方法消歧 | [p69_traits](../../test/ast/p69_traits.sh)：单 trait 静态派发确定；两个 used trait 同名 → `ambiguous method` 硬错 | **已覆盖** | 无 |
| 6 | 动态接口值生命周期、装箱、返回、跨单元 ABI | [12_rvalue_iface](../../test/ast/12_rvalue_iface/prog.ct)、[16_iface_field_box](../../test/ast/16_iface_field_box/prog.ct)、[10_iface_array](../../test/ast/10_iface_array/prog.ct)、[181_iface_vec](../../test/ast/181_iface_vec/prog.ct)、[198_container_iface](../../test/ast/198_container_iface/prog.ct)、[217_option_iface](../../test/ast/217_option_iface/prog.ct)、[237_iface_ret_self](../../test/ast/237_iface_ret_self/prog.ct)、[238_iface_ret_value](../../test/ast/238_iface_ret_value/prog.ct)、[239_local_iface_return](../../test/ast/239_local_iface_return/prog.ct) | **部分** | 生命周期/装箱/返回已密；**跨单元接口值 ABI**（`.h.ct` 边界返回/字段）未见专门夹具；[p73_abi](../../test/ast/p73_abi.sh) 只钉重复 struct 布局 |
| 7 | 错误在 CT 阶段拒绝，不留给 C 编译器 | p69_traits（歧义）、128/129（类型操作数/误报）、[136_generic_bound](../../test/ast/136_generic_bound/prog.ct)/137（约束）、`errors/generic_*`、p42_pub（可见性负例）、p73_abi（重复 struct） | **已覆盖** | 无 |

## 结论

- **已覆盖 4 项**：1、4、5、7。
- **部分 3 项**：2（泛型函数指针）、3（泛型先用后定义）、6（跨单元接口值 ABI）。
- 现有 37 个 trait/generic/impl 用例已覆盖大头，不建议按报告 7 项整批重写。

## 建议

1. 先为 3 个“部分”各写一条**最小探针**（不改产品代码）：
   - `int (*f)(int) = id<int>;` 能否编译/调用；
   - `main` 先调 `twice<int>(3)`、模板后置，是否与普通函数同样放行；
   - `.h.ct` 发布返回接口值的函数，跨单元调用/字段读写是否可用。
2. 探针红（或未定义）才开一张小卡，按缺口分条；三项全绿则只在本文记“已验证”，不开卡。
3. 若第 4 项要更严，把“签名漂移”负例并入现有 `errors/` 夹具，不新卡。
