# Phase 76 — 链中 inline 物化 `$name`

> **状态：规划中（未开卡，排队）**（2026-11-19 立项；`v0.75.0` 拟）。
> **前置**：Phase 70–75 先按现队列收口；本卡不插队。
> **布局说明**：phase-ID 迁移仍被 blocker 挡住，本卡暂用 legacy 路径 `docs/design/phase76.md`，迁移时统一改名。
> **依据**：[battle inline-materialize-2](../../battle/inline-materialize-2/verdict.md)、[battle inline-materialize-1](../../battle/inline-materialize-1/verdict.md)。

## 0 卡片字段（冻结）

| 项 | 值 |
| --- | --- |
| 编号 | v0-PH-76（legacy 文件 `phase76.md`） |
| 目标 | 方法链中 `.m(args)$name` 把该跳返回值物化到已声明变量，链继续以该变量为接收者 |
| 范围 | 同单元 trait/interface + 具体 struct；多变量；链尾；纯赋值；不接管所有权 |
| 非目标 | type-host / `.m.ct` recipe / 泛型实例；`?.`；own/borrow/const 目标；条件/实参/下标；SH-73 修复 |
| 交付物 | 编译器改动、`test/ast/p76_*`、spec §4.x、tutorial/README 的 into 入口 |
| 任务清单 | §3（S1–S3） |
| 退出判据 | E76-1…E76-5（§4） |
| version-minor | 75（PH-76，`d=1`） |
| 已知风险 | R76-1…R76-4（§5） |

## 1 语法与语义

```ct
M x;
N y;

a.m()$x.n()$y;
```

语义：

```ct
x = a.m();
y = x.n();
```

- `$name` 只出现在方法调用 `)` 之后；链尾也允许；
- 一个链可多个 `$name`；同名重复按顺序覆盖；
- `name` 必须已声明；**不要求初始化**；
- `name` 类型必须等于该跳返回类型；
- 方法调用只求值一次；纯赋值，不改 vptr/装箱/AutoDrop；
- 不依赖 SH-73；变量接收者可能绕过它，但本卡不宣称修复。

## 2 类型与初始化矩阵

| 目标 | 合法写法 | 说明 |
| --- | --- | --- |
| trait 接口 | `T t;` | 只能声明；`T t = {};` 拒绝 |
| 具体 struct/容器 | `S s;` / `S s = {};` | 均可；有 vptr 时 `S s;` 补 vptr，其余零 |
| 普通 struct | `P p;` / `P p = {};` | 声明本身不保证字段零；`{}` 显式零 |
| 标量 | `int i;` | 未初始化，不是 0；`$i` 赋值后才安全 |
| 指针 | `M *p = 0;` | 空指针用 0；不用 `{}` |
| own/borrow/const | — | 拒绝作为 `$` 目标 |

## 3 任务

| 任务 | 交付 | 验收 | effort |
| --- | --- | --- | --- |
| S1 | 语法：`$NAME` postfix、上下文边界、多变量/链尾；parser 负例 | `$NAME` 仅在方法调用后；range/into/errdefer 不受影响 | M |
| S2 | 类型：已声明、类型精确匹配、trait vs 具体 struct、trait `{}` 拒绝；`--types` 在 `$` 报错 | 类型负例/正例；不依赖 definite-assignment | M |
| S3 | 降级/发射：`x = call; x.next()`；单次求值；多变量；ASan | 与拆链生成 C 等价；无泄漏/悬挂；golden 不变 | M |
| S4 | 文档：spec 新节；tutorial/README 补 into；SH-73 caveat | 文档门禁；into 可发现 | S |

> S1–S4 同一 phase 的 stage；每个 stage 独立红/绿提交与回滚，只 bump 一次 MINOR。

## 4 退出判据

| ID | 断言 |
| --- | --- |
| E76-1 | `M x; N y; a.m()$x.n()$y;` 编译运行；与拆链逐字节等价 |
| E76-2 | `M x; a.m()$x;` 链尾合法；多变量合法；同名覆盖符合顺序 |
| E76-3 | 类型不匹配、void、`?.`、own/borrow/const、type-host、条件/实参/下标均硬错；trait `T t = {};` 拒绝 |
| E76-4 | `--types` 在 `$` 处报类型错误；同单元 trait/interface 与具体 struct 均覆盖；type-host 明确不在 v1 |
| E76-5 | 全量 golden 不变；ASan 无泄漏/悬挂；`into` 教程入口存在 |

## 5 风险

| 风险 | 缓解 |
| --- | --- |
| `$` 第 4 义项与 range/into/errdefer 混淆 | 上下文隔离 + 文档三义项表；S1 负例 |
| `--types` 对 type-host 静默通过 | v1 直接拒绝 type-host；不让它进入 emit |
| 未初始化变量被当作安全 | 明确“`$` 是赋值”；`name` 在 `$` 前被读仍是既有未初始化问题 |
| 多变量/链尾求值顺序 | 固定“调用→赋值→下一跳”；LHS 只允许简单变量 |
| SH-73 被误读为已修 | spec 写 one-hop caveat；E76-4 文档检查 |

## 6 不做什么

- 不做 type-host/recipe/泛型实例；
- 不做 `?.m()$x`；
- 不做声明形态 `T y = ...$x`；
- 不做条件/实参/下标/loop 初始化；
- 不把 `$name` 当 `into` 的替代；
- 不宣称修复 SH-73。
