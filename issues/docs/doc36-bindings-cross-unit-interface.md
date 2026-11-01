# DOC-36 · `bindings/README.md` 中文 §5 仍称接口值不能跨单元，与英文 §5 和实现相反

| 项 | 值 |
| --- | --- |
| 模块 | docs（binding 指南） |
| 严重度 | **High** |
| 锚点 | commit `524ba99`（2026-10-31） |
| 文件 | [bindings/README.md:110-113](../../bindings/README.md#L110-L113)、[:129](../../bindings/README.md#L129)、[:157](../../bindings/README.md#L157)（中文）；对照 [:253-271](../../bindings/README.md#L253-L271)（英文） |
| 状态 | 已修（2026-10-31）：文档已按建议更新（见 [issues/README.md](../README.md) 的 2026-10-31 处置表） |

## 现象

中文 §5「跨单元限制（v1）」：

> `build` 模式的生成头只**前置声明**接口类型（`struct <Trait>_iface` 没有定义），因此**接口值不能
> 跨单元传递**；……消费方 `import uart;` 后调用 `mock_hal_send(...)`。等跨单元接口值可用后，这一层可以去掉。

同文件英文 §5 的结论相反：「Since Batch 2 a `pub` trait implemented for a `pub` struct exports its
vtable, and the generated header defines the interface type, so a consumer may declare an interface value …」。
检查清单第 157 行也仍在要求「不要把接口值传出单元（v1）」——英文对应条（:293）已经改成「mark the trait
and the instance `pub` if consumers should box the instance themselves」。

术语表同样记着「跨单元消费已由 Batch 2 解除限制」（[glossary.md:191](../../docs/glossary.md#L191)）。

## 证据

实现：`Emitter.h.ct` 在 `mode == 1`（`pub` trait）时把 `struct <T>_iface { void *self; … }` 发射进头文件；
`pub trait` + `pub struct` 的 vtable 以 `extern` 声明进 `.h`（language-spec §4.11）。

语料：[test/modules/xunit_box/main.ct:13](../../test/modules/xunit_box/main.ct#L13) 在消费单元直接声明
`Stream s;`，并接住 [net.h.ct:22](../../test/modules/xunit_box/net.h.ct#L22) 的
`pub Stream stream_open(void)`；该用例是第 8 关的常规成员（403 项全绿）。

## 建议

中文 §5 按英文重写：说明「Batch 2 起接口类型与 vtable 随 `pub` 导出，消费单元可以直接声明接口值、
接住返回的接口、并自行装箱」，并把 mock-hal 的标量入口解释为「该 binding 刻意保持私有」
（`trait` 与实例未标 `pub`），而不是「编译器限制」。第 157 行同步改写。
