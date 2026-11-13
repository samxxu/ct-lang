# p41-1 反对席：A 现草案

> 席位：REVIEW；反对 B，主张 A（保留名/关键字）；HEAD `bd8b74f3`；未改源码/测试/卡面。

## 0 立场

A 的收益是调用点最短：`atomic_load` / `atomic_store` / `atomic_cas` 直接像语言内建；`atomic` 作为关键字可用 `is_type_word` 统一识别。`atomic_int` 兼容性可以通过把 `<stdatomic.h>` typedef 归一化解决；`atomic_load(p)` 可以放宽为类型检查；C11 是原子能力的自然标准。B 的 `ct_atomic_*` 更长，且需要两套名字。

## 1 失效条件

1. 如果项目必须保持 C99 严格编译，A 的 `_Atomic` 不成立。
2. 如果 `<stdatomic.h>` 的 `atomic_load` 正例必须原样可用，A 的保留名不成立。
3. 如果没有 battle/ADR 记录，A 的 breaking change 不成立。
4. 如果 `atomic_int` typedef 无法在 CT 不解析头文件的情况下归一化，A 的“裸 C11 仍可用”不成立。

## 2 证据

- A 直接冲突现有 [bindings-and-patterns.md](../../docs/bindings-and-patterns.md) §7；保留名会让 `int atomic_load(int *)` 被 L41-4 拒绝。
- `cc -std=c99 -pedantic-errors` 对 `_Atomic` 报 C11 extension；A 没有标准切换。
- 仓库内 `battle/p41-1` 之外没有 p41 battle/ADR；A 的 breaking change 缺少可审计决策。
- `atomic_load(p)` 的 L41-7 与 helper `_Atomic(T)*` 签名冲突。

## 3 代价对比

| 项 | A | B |
| --- | --- | --- |
| 调用点 | 短 | 多 `ct_` 前缀 |
| 现有 `<stdatomic.h>` | 破坏 | 保留 |
| 现有同名函数 | L41-4 拒绝 | 保留 |
| C99 严格 | 失败 | 显式 C11 |
| 实现 | 关键字 + 保留名 | 上下文 + 前缀 + C11 |

A 在调用点更短，但 J-1/J-4 均红；本席不推荐在未批准 breaking change 的情况下采用 A。
