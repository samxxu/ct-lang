# battle/leak-guards-1 主张席（REQ）

- 主张：**A — 窄键 + 砍 L3 + 注释豁免 + 默认 warning/限深 3**。
- 理由：把「可确定的部分」限制在编译期可见性，不碰运行期根集，不修订 D-011 J-4c。

## E1 — 既有 manifest 只有一个 strict 值，没有 strict 键

```console
$ grep -n "c-boundary" docs/package-guide.md | head -3
89:| `c-boundary` | 否 | `strict` \| `allow`：本包单元的 C 边界策略。缺省按外部 `strict`；**有 manifest 但缺这个键**的旧包保留 `allow` 窗口 |
102:`c-boundary` 由 `ct build` / `ct pkg check` 读取：`strict` 时包内 `.ct/.h.ct` 不得直接
```

新增 `strict = on` 会与 `c-boundary = strict` 的取值语义撞车；窄键 `leaks = warn|error` 排他。

## E2 — 锚点（含不利于己方）

- 有利于 A：[D-011.md:33](../../docs/decisions/D-011.md#L33)（`--debug-leaks` 只报未配对计数，不叫环检测）；
  [phase81.md:64](../../docs/design/phase81.md#L64)（E81-5 同口径）。
- **不利于己方**：`box<T>` 尚未落地，PH-82 的环检测只能等 PH-81 收口；
  [Expr.h.ct:1172](../../selfhost/ct-ast/frontend/parse/Expr.h.ct#L1172) 目前只有类型名判断，没有存储/释放实现。

## E3 — 可证伪预测

若 A 成立，PH-82 只需读 manifest 键 + 复用现有 struct 字段表；不需要新增运行期根注册。
若实测必须枚举栈/寄存器里的句柄副本才能给出「环」结论，A 的「砍 L3」成立。

## E4 — 代价

- A：一个 MINOR（PH-82）；L1 配置 + L2 类型图检测 + L4 文档，单卡可回滚。
- 宽键 `strict = on`：`c-boundary` 语义、旧包默认、文档三处都要改，且会与 C 边界 strict 混淆。

## E5 — 对 B 最强论点的 steelman

B 最强：`leaks = error` 只覆盖编译期诊断，`box` 落地后运行期泄漏仍不可见，作者责任风险变大。
回应：运行期可见性需要根注册/保守扫描，属于新机制；PH-82 不承诺它，D-011 J-4c 的契约仍然有效。
