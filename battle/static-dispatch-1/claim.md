# battle/static-dispatch-1 · 主张席（外部观察者）

| 项 | 值 |
| --- | --- |
| 主张 | 外部提案 R1/R2/R3 原案：静态派发、链式接收者、1.0 前治理 |
| 基线 | 提案自述 v0.63.2；本轮对照 HEAD `c5d42b91`（v0.65.1） |
| 外部只读件 | `/tmp/battle-static-dispatch-1/proposal.md`（用户转交件副本；sha256 `5e74d15b…f5977`） |
| 定性 | **R1 方向真、R2 一半旧、R3b 已过时**；主张席按原案完整陈述，不替反证席收窄 |

## E1 主张与复现入口

```console
$ git rev-parse --short HEAD
c5d42b91
$ ~/.local/bin/ct -v
ct v0.65.1
$ shasum -a 256 /tmp/battle-static-dispatch-1/proposal.md
5e74d15bbb1b0f738ceb913e043b72b3815e41d92a4f63a8a51cd6eae29f5977  /tmp/battle-static-dispatch-1/proposal.md
$ sed -n '21,34p' /tmp/battle-static-dispatch-1/proposal.md
## 2. R1：非泛型 impl 的派发静态化（去虚化）
...
- 普通（非泛型）`impl T for S` 一律经 vptr：`recv.__T_vptr->m(&recv, …)`，即使接收者的
  静态类型就是具体 struct `S`。vtable 在编译期完全可知，虚调用在这里不产生任何多态收益。
...
## 3. R2：方法结果作接收者（SH-73）——打通 README §0.1 的完整路径
...
## 4. R3：1.0 前收敛治理——稳定子集冻结清单与版本位规整
```

原案的四个承诺：

1. **R1**：具体 struct 接收者的 trait 调用改直呼；“纯发射端改动，不动解析与符号表”。
2. **R2a**：局部接口返回仍是静默悬垂（提案写“实测 200 ≠ 201”），应硬错。
3. **R2b**：方法结果作接收者（`f().m()` / `chain().next()`）落地后，README §0.1 完整路径只剩“断点 1”。
4. **R3a/R3b/R3c**：稳定子集清单、版本位规整、包仓只读索引页。

## E2 依据与锚点

| 锚点 | 原文 / 事实 | 支撑 |
| --- | --- | --- |
| [README.md:62](../../README.md#L62) | “impl / 自由函数返回**局部**接口值……实测 `200`，期望 `201`” | R2a 的现状句（**已过时**，见反证 E2） |
| [issues/selfhost/sh73-temp-receiver-dynamic-dispatch.md:8](../../issues/selfhost/sh73-temp-receiver-dynamic-dispatch.md#L8) | “状态：保持（有意限制）；建议：**延后**” | R2b 的 SH-73 定性 |
| [docs/language-spec.md:323](../../docs/language-spec.md#45-方法调用重写) | 临时值接收者只允许在语句行首 / 赋值初始化式提升 | R2b 的规约依据 |
| [docs/roadmap.md:147](../../docs/roadmap.md#L147) | “稳定子集清单……属文档治理，不占 Phase 编号” | R3a 仍是未排期治理项 |
| [docs/planning/post-58-plan.md:190](../../docs/planning/post-58-plan.md#L190) | “待裁定（不自行决定）” | R3b 的“待裁定”出处（**已部分过时**） |

**不利于己方**（主张席主动登记，供裁判核对）：

- [issues/selfhost/sh75-local-iface-return-dangling.md:9](../../issues/selfhost/sh75-local-iface-return-dangling.md#L9)
  写“**fixed**（`b5797cbf`，2026-11-15；回归 `test/ast/239_local_iface_return`）”，直接反驳 R2a 的“仍未修”。
- [test/modules/split/main.expected.c:16](../../test/modules/split/main.expected.c#L16) 的
  `__ct_tmp0->__speak_vptr->hi(__ct_tmp0)` 说明跨单元具体接收者今天依赖 vptr；这支持 R1 的“现状”句，
  但同时是 R1“纯发射端”承诺的反例（见反证 E2）。

## E3 收益与代价（主张席自估）

- **R1 收益**：具体接收者的 trait 调用少一次间接跳转与一次 vptr 载入；Cortex-M0 / 小 Flash 上直接调用
  更小。代价按提案自估为“纯发射端”，不改 ABI。
- **R2a 收益**：把“静默悬垂 / 隐藏堆盒子”变成显式失败，符合零隐藏分配。代价：现有可能依赖物化的代码
  需要迁移；提案承认可加 `--compat` 过渡。
- **R2b 收益**：README §0.1 的“一行链”可用，动态派发的表达力补齐。代价：SH-73 估计 100–300 行，
  且改所有动态派发调用点的临时值提升规则。
- **R3 收益**：把 1.0 冻结清单与版本位从“待裁定”变成机械可查；代价是文档与门禁工作，不占版本位。

## E4 对反证席最强论点的回应（steelman）

反证席最强的两点是：**（a）跨单元 impl 的方法符号是 `static`，静态直呼需要导出方法，因而不是“纯发射端”**；
**（b）R2a/R2b 的现状引用了过期文档（v0.63.2 基线），SH-75 已修、SH-73 是判过的设计拒绝**。

主张席的回应：

- 对（a）：R1 可先做**同单元子集**，覆盖多数调用点；跨单元是否导出方法应作为独立 ABI 决策，不必阻塞 R1。
  判据 J1 可收窄为“同单元具体接收者夹具”，而不是“全部 golden”。
- 对（b）：提案基线 v0.63.2 确实早于 v0.65.1；R2a 应改成“文档/策略项”，R2b 应重开 SH-73 的
  **设计裁决**而不是当补丁。R3b 应重基线到 1.16.0/PH-67。

## E5 范围与风险

- 本席只主张“方向与原案”，不替提案补实现细节；R1 的跨单元、R2b 的求值顺序、R3b 的版本位均需裁判裁定。
- 风险：R1 的“全部 golden”判据不可机械区分接口与具体接收者；R2a 的硬错会破坏已修夹具；
  R2b 会改所有动态派发调用点的生成形状；R3b 若按旧偏移模型落地，会与 1.16.0 的 `v<M>-PH-<n>` 冲突。
