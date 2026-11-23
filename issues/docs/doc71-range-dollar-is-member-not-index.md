# DOC-71 · range 初值的 `$` 被写成「下标」，实现绑定的是当前成员值

| 项 | 值 |
| --- | --- |
| 模块 | docs / lang |
| 严重度 | Low（纯文档措辞；实现正确） |
| 锚点 | `v0.26.4`（Phase 24 实现，未 bump） |
| 文件 | [language-spec.md:1847-1848](../../docs/language-spec.md#447-数组-range-初值-abphase-24仅-ct-ast)、[language-spec.md:1864-1868](../../docs/language-spec.md#447-数组-range-初值-abphase-24仅-ct-ast)、[language-spec.md:4248](../../docs/language-spec.md#9-诊断与退出码)、[phase24.md:145-160](../../docs/history/design/phase24.md#L145-L160)、[Emitter.h.ct:2018-2038](../../selfhost/ct-ast/backend/emit/Emitter.h.ct#L2018-L2038)、[range_init.ct:21](../../examples/15_range_init/range_init.ct#L21) |
| 状态 | verified |
| 处置证据 | **verified**（2026-11-20，REV；deferred 子项见复核段） |

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

- [language-spec.md:1847-1848](../../docs/language-spec.md#447-数组-range-初值-abphase-24仅-ct-ast) 的 `((int)k)` 本身正确，
  但 `k` 在上下文中被读成「下标」；
- [language-spec.md:1864-1868](../../docs/language-spec.md#447-数组-range-初值-abphase-24仅-ct-ast) 与英文段
  [language-spec.md:4248](../../docs/language-spec.md#9-诊断与退出码) 的诊断文案
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

1. [language-spec.md:1864](../../docs/language-spec.md#447-数组-range-初值-abphase-24仅-ct-ast) 改为「`$` 是当前成员的占位，
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

## 处置（2026-11-20，DEV #2）

范围：只改叙述与词表，**不改实现、不改诊断文案、不改 `check-ast` 断言**；发射器注释按 issue 的建议
随下次实现提交，本提交不碰代码。

| # | 建议收口项 | 结论 | 落点 |
| --- | --- | --- | --- |
| 1 | `$` 改为「当前成员的占位」 | **fixed** | [language-spec §4.47](../../docs/language-spec.md#447-数组-range-初值-abphase-24仅-ct-ast)：`$` 绑定当前序列成员的值 `k`（从 `a` 起，不是 0 起偏移）；给出 `2..5($)` → `2 3 4`、`1..6($ * $)` → `1 4 9 16 25`，并说明只有 `0..b` 时成员值才等于 0 起偏移 |
| 2 | 英文段同位补澄清 | **n/a（已无英文段）** | 文档语言政策（AGENTS §0.4）已删除 `## English`；`grep -rn '^## English' docs/language-spec.md` 无命中，不需补 |
| 3 | 诊断文案保留并注明历史措辞 | **fixed** | 同 §4.47：`the range index '$' is not a variable` 保留，注明是 Phase 24 发布时的历史措辞、`$` 并非标识符、文案被精确断言故不改 |
| 4 | glossary 增加 `$` 条目 | **fixed** | [glossary](../../docs/glossary.md#1-语言构造)：新增「`$`（当前成员 / 自身）」，列 range 初值 / `into` 两个绑定语境，注明 range 中只读 |
| 5 | `phase24.md` 与发射器注释改「current member」 | **fixed（phase24）/ deferred（代码注释）** | [phase24.md:160](../../docs/history/design/phase24.md#L160) 改为「当前成员值」；`Emitter.h.ct:312` / `:3101` 的 `index` 注释属代码，按 issue 原文「可随下次实现提交，不单独立项」，本次不碰代码，已在本文登记为剩余项 |

实测命令与原始输出（证明实现绑定成员值，不是 0 起下标）：

```console
$ .temp/p77/ct-ast -v
ct-ast v0.77.1
$ cat .temp/doc71/p.ct
#include <stdio.h>
int main(void) {
    int a[] = 2..5($);
    int b[] = 0..3($);
    ...
}
$ .temp/p77/ct-ast compile .temp/doc71/p.ct --c-boundary=allow -o .temp/doc71/p3.c
$ sed -n '6,7p' .temp/doc71/p3.c
    int a[] = { ((int)2), ((int)3), ((int)4) };
    int b[] = { ((int)0), ((int)1), ((int)2) };
$ cc .temp/doc71/p3.c -o .temp/doc71/p3 && ./.temp/doc71/p3
a[0]=2
a[1]=3
a[2]=4
b 0 1 2
$ grep -n 'squares' examples/15_range_init/range_init.expected.out
16:squares 1 4 9 16 25
```

若 `$` 是 0 起下标，`2..5($)` 会得到 `0 1 2`；实测 `2 3 4`，与改后叙述一致。

验证：`python3 test/docs/check-docs.py` → OK；`bash tools/check.sh g0` → OK。

## 复核（2026-11-20，REV）

**结论：verified**（内容正确；新增链接有锚点瑕疵，见下，不阻断）。

```console
$ grep -n '当前成员的占位' docs/language-spec.md
2154:- **`$` 是当前成员的占位，不是下标**：...
$ grep -n '当前成员值' docs/history/design/phase24.md
160:4. **可多次出现**：... 同一个当前成员值 ...
$ grep -n '`\$`（当前成员 / 自身）' docs/glossary.md
69:| `$`（当前成员 / 自身） | ... | ... |
$ grep -n 'current index\|current member' selfhost/ct-ast/backend/emit/Emitter.h.ct
3101:       `range_k` set to the current index, ...
```

独立实测（v0.77.2 归档二进制）：

```console
$ /tmp/rev-v0772/ct-ast compile /tmp/rev-doc71/p.ct --c-boundary=allow -o /tmp/rev-doc71/p.c
$ sed -n '6,7p' /tmp/rev-doc71/p.c
    int a[] = { ((int)2), ((int)3), ((int)4) };
    int b[] = { ((int)0), ((int)1), ((int)2) };
$ /tmp/rev-doc71/p
a 2 3 4
b 0 1 2
```

逐条：spec §4.47 已改为「当前成员」并注明 `the range index '$' is not a variable` 是历史措辞；
glossary 新增 `$` 条目（range / `into` 两个绑定语境、range 只读）；phase24 改为「当前成员值」；
英文段按 §0.4 已不存在，`n/a` 成立；发射器注释未改，处置已登记为 deferred，触发条件
「随下次实现提交」明确，属代码提交范围，REV 不据此打回。

**锚点瑕疵（不阻断）**：本批新增的两处 `§4.47` 链接写成
`#447-数组-range-初值-ab-phase-24仅-ct-ast`。按 GitHub `github-slugger` 对标题
「4.47 数组 range 初值 `a..b($)`（Phase 24，仅 ct-ast）」的计算，实际锚点是
`#447-数组-range-初值-abphase-24仅-ct-ast`（`ab` 与 `phase` 之间没有连字符）。
两处分别在 [phase24.md:160-161](../../docs/history/design/phase24.md#L160-L161) 与本文件处置项 1；
`check-docs` 只校验相对路径存在，不校验 `#fragment`，故门禁未红。全仓同类 fragment
链接共 89 条，不合规 10 条（本批新增 2 条，其余 8 条为既有），建议下一次文档提交统一修正，
不影响本条内容结论。
