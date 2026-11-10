# DOC-70 · 语句级 `each (container) { … item … }` 未实现、未排期

| 项 | 值 |
| --- | --- |
| 模块 | docs / lang |
| 严重度 | Low（需求登记；现有库层 `each` 已可用，缺的是另一套形态） |
| 锚点 | `v0.26.4` / `7c58192`（HEAD = `main`） |
| 文件 | [phase24.md:45](../../docs/design/phase24.md#L45)、[phase24.md:462](../../docs/design/phase24.md#L462)、[phase25.md:63](../../docs/design/phase25.md#L63)、[phase25.md:283](../../docs/design/phase25.md#L283) |
| 状态 | **open**（已设计评估，明确不排期；本轮只登记，不实现语言特性） |

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

- [phase24.md:45](../../docs/design/phase24.md#L45)：`each (nums) { … item … }` 语句形态「需要隐式名字与块参数，
  属语言级语法糖；SHIM / 宏做不到。**方法形态 `a.each(n, closure)` 已由 Phase 25 落地**」。
- [phase24.md:462](../../docs/design/phase24.md#L462)：「仍不做、不排期」。
- [phase25.md:63](../../docs/design/phase25.md#L63)：「需要隐式名字、块参数与 `break`/`continue`，是语言级
  语法糖，未排期」。
- [phase25.md:283](../../docs/design/phase25.md#L283)：D25-8「不做语句形态 `each (…) { … }`」。

## 结论

**未实现；设计过但明确未排期。** 它与 `for`、`loop(n)`、库层 `each` 的关系是：

- `for` / `loop(n)`：语言语句构造，显式循环变量或计数；
- 库层 `each`：trait 方法 / 静态映射的方法名约定（Phase 25），`a.each(closure)` 是普通方法调用，
  闭包按 `(fn, env)` 展开；
- 语句级 `each (container) { … item … }`：从未实现，也未排期。

## 命名决策（2026-11-10，battle 记录）

因为语句形态不存在，这是「未来语法的命名预留」，不是既有冲突。两方案：

| 判据 | A. 共用 `each` | B. 分名（库层 `each`，未来语句用 `foreach` / `for … in`） |
| --- | --- | --- |
| 可读性 | 同一心智模型，直观 | 两个名字，需一句解释 |
| 与 `for` / `loop(n)` 一致 | 语句构造却复用方法名，形态不一致 | 语句构造用构造名，一致 |
| 既有约定 | 与 Phase 25 方法名约定冲突 | 保留 `each` 作为方法名 |
| 改动面 / 兼容 | 需把 `each` 升为上下文关键字，和自由泛型函数 `each<T>(...)`（示例 18/19）歧义，属破坏性改动 | 零改动；仅在排期时新增 `foreach` |
| 进化空间 | 两套机制永久耦合在一个词上 | 方法链 `seq.each(fn)` 与块构造 `foreach` 各自演进 |

**代决：B（分名）**。向后兼容与「不把 `each` 升成关键字」是决定性判据；「同名直观」不足以抵消
破坏既有 `each<T>` / `a.each(...)` 的代价。已写入 [phase25.md](../../docs/design/phase25.md) D25-12。
**本轮不改任何现有样例或方法名**；命名一旦要动，是独立一次改动。

## 建议收口

- 保持「未排期」；若未来排期，按 D25-12 使用 `foreach` / `for … in`，并以语句构造实现；
- 文档中继续只承诺库层 `a.each(closure)`，不暗示语句形态存在。

## 验证

- 探针退出码与诊断见上表；
- `docs/design/phase25.md` D25-12 存在；
- 不涉及代码、样例与门禁改动。
