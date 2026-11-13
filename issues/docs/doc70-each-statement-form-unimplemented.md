# DOC-70 · 语句级 `foreach (array) { … item … }`（旧名 `each` 已作废）

| 项 | 值 |
| --- | --- |
| 模块 | docs / lang |
| 严重度 | Low（需求登记；现有库层 `each` 已可用，缺的是另一套形态） |
| 锚点 | `v0.26.4`（Phase 27 实现，未 bump） |
| 文件 | [phase24.md:45](../../docs/history/design/phase24.md#L45)、[phase24.md:462](../../docs/history/design/phase24.md#L462)、[phase25.md:63](../../docs/history/design/phase25.md#L63)、[phase25.md:283](../../docs/history/design/phase25.md#L283)、[phase27.md](../../docs/history/design/phase27.md) |
| 状态 | **closed**（Phase 27 在 ct-ast 落地数组形态；容器协议经 D27-4 延后） |

> **命名现状（2026-11-10 用户确认）**：语句级迭代形态一律写 **`foreach (map) { … item … }`**；
> 老规划里的 `each(map){…}` **关键字名作废，不得再作为关键字使用**。`each` 这个标识符只保留为
> 库层——trait / 静态映射的方法名（示例 17、19）与泛型自由函数名（示例 18）。文中
> 「实测 / 结论」两节记录的是 Phase 27 之前的原始状态（当时 `foreach (…) { … }` 不存在），
> 保留为历史证据；现状见文末「处置」。

## 触发场景

用户提出下面这种「带块 + 隐式绑定」的迭代写法：

```ct
each (map) {
    str = item.key;
    number = item.value;
}
```

它和现有库层方法 `a.each(closure)` 名字相同、功能相近，容易被当成同一机制。

## 实测（ct-ast `v0.26.4`，探针在临时目录）

| 探针 | 写法 | 结果 |
| --- | --- | --- |
| G | `each(map) { printf("%d\n", item); }` | `g.ct:8:15: error: unexpected token`，rc=1 |
| H | 先声明 `int each(int *)`，再 `each(map) { var str = item.key; … }` | `h.ct:13:15: error: unexpected token`，rc=1 |
| I | 只写 `each(map);` | rc=0，产物原样保留 `each(map);` |
| J | 独立块 `{ int item = map[0]; … }` | rc=0，块语句本身合法 |
| L | `var str = 1;` | rc=0（`var` 被当作类型名写进 C，不是关键字） |

结论：失败点是 **`each(...)` 调用之后紧跟 `{` 不接受**，不是 `each` 被识别为关键字；`each` 在解析器里
就是一个普通标识符（I 能原样通过），`item` / `var` 也没有隐式绑定或关键字语义。

## 设计侧原文

- [phase24.md:45](../../docs/history/design/phase24.md#L45)：`each (nums) { … item … }` 语句形态「需要隐式名字与块参数，
  属语言级语法糖；SHIM / 宏做不到。**方法形态 `a.each(n, closure)` 已由 Phase 25 落地**」。
- [phase24.md:462](../../docs/history/design/phase24.md#L462)：「仍不做、不排期」。
- [phase25.md:63](../../docs/history/design/phase25.md#L63)：「需要隐式名字、块参数与 `break`/`continue`，是语言级
  语法糖，未排期」。
- [phase25.md:283](../../docs/history/design/phase25.md#L283)：D25-8「不做语句形态 `each (…) { … }`」。

以上引文均成文于 D25-12 之前，原文中的 `each` 指当时的暂定名；该名已作废，语句形态现为 `foreach`。

## 结论（Phase 27 之前的原始结论）

**当时未实现；设计过但明确未排期。** 它与 `for`、`loop(n)`、库层 `each` 的关系是：

- `for` / `loop(n)`：语言语句构造，显式循环变量或计数；
- 库层 `each`：trait 方法 / 静态映射的方法名约定（Phase 25），`a.each(closure)` 是普通方法调用，
  闭包按 `(fn, env)` 展开；
- 语句级 `foreach (array) { … item … }`（旧名 `each`，已由 D25-12 作废）：Phase 27 前从未实现、
  也未排期；Phase 27 已实现数组形态，容器协议仍延后。

## 命名决策（2026-11-10，battle 记录）

因为语句形态不存在，这是「未来语法的命名预留」，不是既有冲突。两方案：

| 判据 | A. 共用 `each` | B. 分名（库层 `each`，未来语句用 `foreach`） |
| --- | --- | --- |
| 可读性 | 同一心智模型，直观 | 两个名字，需一句解释 |
| 与 `for` / `loop(n)` 一致 | 语句构造却复用方法名，形态不一致 | 语句构造用构造名，一致 |
| 既有约定 | 与 Phase 25 方法名约定冲突 | 保留 `each` 作为方法名 |
| 改动面 / 兼容 | 需把 `each` 升为上下文关键字，和自由泛型函数 `each<T>(...)`（示例 18/19）歧义，属破坏性改动 | 零改动；仅在排期时新增 `foreach` |
| 进化空间 | 两套机制永久耦合在一个词上 | 方法链 `seq.each(fn)` 与块构造 `foreach` 各自演进 |

**代决：B（分名）**。向后兼容与「不把 `each` 升成关键字」是决定性判据；「同名直观」不足以抵消
破坏既有 `each<T>` / `a.each(...)` 的代价。已写入 [phase25.md](../../docs/history/design/phase25.md) D25-12。
**本轮不改任何现有样例或方法名**；命名一旦要动，是独立一次改动。

## 建议收口

- ~~保持「未排期」~~ **已于 Phase 27 排期并实现**；按 D25-12 使用 **`foreach`**，以语句构造实现；
- 旧关键字名 `each(map){…}` 作废，不得在文档、样例或未来实现中复用；
- 库层 `a.each(closure)` 与语句形态 `foreach` 并存，两者互不替代。

## 处置（2026-11-10，Phase 27）

- 语法与语义：[language-spec §4.49](../../docs/language-spec.md)、[tutorial 10.6](../../docs/tutorial.md)、[phase27.md](../../docs/history/design/phase27.md)（D27-1–D27-11）。
- 实现只在 `selfhost/ct-ast/**`：`foreach` 为上下文关键字；展开为单个 `for`，长度取
  `sizeof(x) / sizeof((x)[0])`；`item` 按值拷贝、块内可见；`break` / `continue` / `return` 直通。
- 容器协议（`len()` + `get(int)` / `entry(int)`）按 D27-4 **延后**：本仓没有 std 容器，
  无消费者就无红证；非数组容器当前按 L27-2/L27-4 拒绝。
- 红证：baseline `855 passed, 17 failed`（3 个正例 + 14 条 Phase 27 断言全红）；
  实现后 `872 passed, 0 failed`。

## 验证

- 正例 `test/ast/132`–`135`，负例 `test/ast/errors/foreach_*.ct`（10 条）；
- `selfhost/check-ast.sh` 断言覆盖逐条文案、生成 C 形状、与手写 `for` 的逐字节一致、
  `ct check` 下遮蔽升为 error；
- `docs/history/design/phase25.md` D25-12 与本文的命名结论一致。
