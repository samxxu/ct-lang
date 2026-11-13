# DOC-71 · range 初值的 `$` 被写成「下标」，实现绑定的是当前成员值

| 项 | 值 |
| --- | --- |
| 模块 | docs / lang |
| 严重度 | Low（纯文档措辞；实现正确） |
| 锚点 | `v0.26.4`（Phase 24 实现，未 bump） |
| 文件 | [language-spec.md:1847-1848](../../docs/language-spec.md#L1847-L1848)、[language-spec.md:1864-1868](../../docs/language-spec.md#L1864-L1868)、[language-spec.md:4248](../../docs/language-spec.md#L4248)、[phase24.md:145-160](../../docs/history/design/phase24.md#L145-L160)、[Emitter.h.ct:2018-2038](../../selfhost/ct-ast/backend/emit/Emitter.h.ct#L2018-L2038)、[range_init.ct:21](../../examples/15_range_init/range_init.ct#L21) |
| 状态 | **open**（待改叙述；不改实现、不改诊断文案） |

## 触发场景

需求侧在讨论「接收者语境块」时提出：`$` 是「自身 / 当前成员」的占位，不是下标记号；
range 初值里的 `$` 与将来语境块里的 `$` 是同一个语义，只是绑定语境不同。核对仓库后发现
文档把它称作「下标 / index」，与实现对不上。

## 实测（ct-ast `v0.26.4`）

| 证据 | 内容 |
| --- | --- |
| [Emitter.h.ct:2034](../../selfhost/ct-ast/backend/emit/Emitter.h.ct#L2034) | `for (k = start; k < start + count; k++)`，循环变量从 `start` 起，`range_k = k` |
| [Emitter.h.ct:2020](../../selfhost/ct-ast/backend/emit/Emitter.h.ct#L2020) | 注释写「`range_k` set to the current index」，把 `k` 称作 index |
| [range_init.ct:21](../../examples/15_range_init/range_init.ct#L21) | `int squares[] = 1..6($ * $);` |
| [range_init.expected.out:16](../../examples/15_range_init/range_init.expected.out#L16) | 实际输出 `squares 1 4 9 16 25` |

若 `$` 是 0 起的下标，`1..6($ * $)` 会得到 `0 1 4 9 16`；实际得到 `1 4 9 16 25`，
说明 `$` 绑定的是**序列成员的值**（`start + offset`）。`0..3` 这类从 0 开始的区间里
成员值恰好等于偏移，所以措辞问题一直没被暴露。

## 错在哪

- [language-spec.md:1847-1848](../../docs/language-spec.md#L1847-L1848) 的 `((int)k)` 本身正确，
  但 `k` 在上下文中被读成「下标」；
- [language-spec.md:1864-1868](../../docs/language-spec.md#L1864-L1868) 与英文段
  [language-spec.md:4248](../../docs/language-spec.md#L4248) 的诊断文案
  `the range index '$' is not a variable` 把 `$` 命名为 index；
- [phase24.md:160](../../docs/history/design/phase24.md#L160) 写「每个 `$` 都是同一个当前下标」；
- 发射器注释 [Emitter.h.ct:2020](../../selfhost/ct-ast/backend/emit/Emitter.h.ct#L2020) 写 current index。

正确表述应是：**`$` = 当前成员（当前语境的自身）**。在 `a..b(expr)` 中，成员是序列
`a, a+1, …, b-1` 的每个整数；起点非 0 时成员值不等于 0 起偏移（`2..5($)` → `2 3 4`）。

## 影响

1. 读者会据文档误判 `2..5($)` 产出 `0 1 2`，实际是 `2 3 4`；
2. 会误导后续语言设计——「接收者语境块」若沿用「`$` 是下标」的解释，会把同一个 sigil
   拆成两个互不相关的含义，而不是「同一语义、不同绑定语境」；
3. 不影响编译产物：实现与 golden 都是正确的，属纯文档漂移。

## 建议收口

只改叙述，**不改实现、不改诊断文案、不改 `check-ast` 断言**：

1. [language-spec.md:1864](../../docs/language-spec.md#L1864) 改为「`$` 是当前成员的占位，
   在 range 初值里绑定为当前元素的值 `k`；`0..b` 时它恰好等于 0 起偏移」；
2. 在英文段同位补同义澄清；
3. 诊断文案 `the range index '$' is not a variable` 保留（已发布、被精确断言），
   在 spec 中注明它是历史措辞，`$` 并非标识符；
4. [glossary.md](../../docs/glossary.md) 增加 `$` 条目：当前语境的自身／当前成员，
   并列出绑定语境（range 初值；将来的接收者语境块）与能力差异（range 中只读）；
5. [phase24.md:160](../../docs/history/design/phase24.md#L160) 与发射器注释的「current index」
   改为「current member」（注释改动可随下次实现提交，不单独立项）。

## 处置

未处置。等文档轮统一修订；本条不触碰编译器行为。
