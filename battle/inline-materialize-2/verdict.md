# battle/inline-materialize-2 判决

> **状态：`closed`**（2026-11-19；裁判 EDITOR；1 轮 claim/counter/evidence）。
> **结论：A′ 有条件胜出——采用最小 `$name`：已声明即可（不要求初始化）、允许多变量与链尾；trait 只能声明，具体 struct/容器可用 `{}`；type-host、`?.`、own、条件/实参位置移出 v1。若这些收缩不可接受，则 B 胜。**

## 1 逐项判决

| J | 结论 | 依据 |
| --- | --- | --- |
| J-1 语义闭合 | **A′ 可闭合，需限制** | 单跳降级 `j = i.next()` 的生成 C 与拆链 RHS 逐字相同；但 LHS 带副作用、`for` 初始化式、多次物化无原型。v1 限定简单变量 LHS、语句/声明/return，不做条件/实参/下标。 |
| J-2 类型闭合 | **A 原稿 fail；A′ 可救** | 同单元 trait/interface 的 `--types` 已能报 `expected 'int', got 'struct M_iface'`；type-host 在 v0.65.1 直接拒绝 import，v0.68.0 对 `int bad = "...".method("GET")` 静默 rc=0，错误只在 build/cc。v1 **排除 type-host/recipe**，只支持同单元 trait/interface；`--types` 必须报在 `$`。 |
| J-3 语法闭合 | **A 胜** | `$` 已是 `T_PUNCT`，primary 仅三分支；增加 postfix `$NAME` 分支即可；into/range/dollar_ok 可隔离三义项；`?.m()` 已拒绝；静态调用 `a=-1, aux=11` 可排除。 |
| J-4 所有权 | **A′ 可闭合，需负例** | 普通赋值复制接口 fat pointer / struct 值 / boxed 指针，不自动 free；`own` 目标必须拒绝（实测 own 再赋值抑制 drop）；强制预填初值可能泄漏 box，需 ASan 矩阵。 |
| J-5 SH-73 | **A 胜** | SH-73 仍拒临时接收者；变量接收者绕过；A 明确不宣称修复，必须写 one-hop caveat。 |
| J-6 成本 | **A′ 可分期** | 6–8 源文件成立；150–250 行偏乐观，按 180–320 估；grammar 169 checks 需同步；旧 golden/revert 成立。 |

## 2 方案 A′（v1 范围）

```ct
M x = init();                     /* 必须带初始化式 */
a.m()$x.n();                      /* 仅同单元 trait/interface；x 已声明 */
```

规则：

1. **只允许同单元 trait/interface 与具体 struct 方法链**；type-host、`.m.ct` recipe、泛型实例暂不支持。
2. `name` 必须在同一函数内**已声明**；初始化可选。`M x;`、`M x = {};`、`M *p = 0;` 都可；trait 接口只能 `T t;`，不能 `T t = {};`。
3. `name` 类型必须精确等于方法返回类型；`ct check --types` 在 `$` 处报错。
4. 只允许在**语句表达式 / 声明初始化式 / return** 的链中；禁止 `if/while/for` 条件、实参、下标、`into`/range/errdefer 内部。
5. **允许多变量与链尾物化**：`M x; N y; a.m()$x.n()$y;` 合法；同链可多次物化；重复变量按顺序覆盖。
6. 不支持 `?.m()$x`、`own/borrow/const` 目标、声明形态 `T y = ...$x`。
7. 方法调用只求值一次；LHS 只能是简单变量；不改变所有权/生命周期。
8. **不依赖 SH-73，也不宣称修复 SH-73**；变量接收者只是绕法，文档写 one-hop caveat。

## 3 实施切片

| 阶段 | 交付 | 验收 |
| --- | --- | --- |
| S1 语法/类型 | `$NAME` postfix、上下文边界、多变量/链尾、同单元 trait/interface 与具体 struct 类型检查、负例 | `--types` 在 `$` 报类型/位置错误；`?.`/type-host/own/条件负例；多变量/链尾正例 |
| S2 降级/发射 | `x = <call>; x.next()` 单次求值；简单变量 LHS；多次物化 | 与拆链生成 C 等价；ASan 无泄漏/悬挂；golden 不变 |
| S3 文档/边界 | spec 新节、tutorial/README 补 into、SH-73 caveat、迁移说明 | 文档门禁；`into` 可发现；`$` 第 4 义项有边界表 |

## 4 不采纳/延后

- type-host / recipe / 泛型实例的 `$name`：等 `--types` 覆盖后再议；
- `?.m()$x`：L53-7 未实现；
- `for` 初始化式、条件/实参/下标内的 `$name`：求值顺序未闭合；
- 链尾 `$name`：直接赋值更清楚；
- 用 `$name` 替代 `into` 处理兄弟方法：职责不同；
- 宣称 `$name` 修复 SH-73：不成立。

## 5 B 成立条件

若用户/REQ 不接受“同单元 trait/interface + 具体 struct + 已声明（初始化可选）+ 无 `?.`/type-host”的收缩，则 B 胜：两行拆链/into 是当前唯一安全路径，不进入实现。

## 6 证据限制

- A 未实现；语义结论来自代码结构与手工降级等价性；未跑 ASan 全矩阵。
- type-host 的 `--types` 静默通过是当前缺陷，不作为 A 的可用范围。
- 基线 `0c449d2e` 实为 v0.65.1；HEAD 已到 v0.68.0；行为探针在基线快照复跑。
