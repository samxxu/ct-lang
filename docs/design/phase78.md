# Phase 78 — `ref` / `out` 参数（S2）

> **状态：规划中（未开卡；J-6 门槛）**（2026-11-20 立项；`v0.78.0` 拟）。
> **前置**：J-6 证据通过（P-7.1a 自由函数 + P-7.1b 方法/trait 原型）；PH-77 已收口。
> **布局说明**：phase-ID 迁移仍被 blocker 挡住，本卡暂用 legacy 路径 `docs/design/phase78.md`。
> **依据**：[提案 v2](../proposals/pointer-free-v2.md)、[D-011](../decisions/D-011.md)、
> [phase 安排](../planning/pointer-free-phase-plan.md)、[battle s2-scope-1](../../battle/s2-scope-1/verdict.md)。

## 0 卡片字段（冻结）

| 项 | 值 |
| --- | --- |
| 编号 | v0-PH-78（legacy 文件 `phase78.md`） |
| 目标 | 源码层无 `&`/`*` 的 `ref` / `out` 参数：上下文关键字、指针发射、调用点 place 检查、`out` 定值 |
| 范围 | 普通函数（S2a）；方法/trait（S2b）；标量、struct、指针；`out` 调用方初始化与 L1 定值 |
| 非目标 | 切片、`String/Str`、`box/new`；借用检查；跨过程定值；数组/函数指针形态的 ref/out |
| 交付物 | 编译器改动、`test/ast/p78_*`、`test/proto` 证据、文档 |
| 任务清单 | §2（S2a–S2c） |
| 退出判据 | E78-1…E78-6（§3） |
| version-minor | 78（PH-78，`d=0`） |
| 已知风险 | R78-1…R78-5（§4） |

## 1 需求与边界

```ct
void inc(ref int x) { x = x + 1; }
bool parse(Str s, out int len) { len = s.len; return len != 0; }

int v = 1;
inc(v);          /* 调用点不写 & */
int n;
parse("ab", n);  /* 调用点不写 out */
```

- `ref`/`out` 是**上下文关键字**，只在形参表生效；`int out;`、`time_t *ref;` 继续合法。
- `ref` 可读写；`out` 必须在每条退出路径赋值。
- 签名发射 `T *`；函数体内读写发射 `(*name)`；调用点自动 `&`。
- 调用点 lvalue 白名单：变量、字段、`*p`、数组/切片/Vec/Map 元素；字面量/表达式/调用结果/cast 硬错。
- `out` 调用方初始化：trivial 可未初始化；owning（`String`/`box`/`Vec`/`use Drop`）必须已初始化；
  借用类型可未初始化。
- `out` 定值：L1（顺序 + if/else 精确；循环/switch/goto 保守），`ct build` 默认硬错。
- 不做借用检查；`ref` 可被存储的透传风险由契约/直接 lint 承担（J-4b）。

### 1.1 分期

| stage | 内容 | 入口 |
| --- | --- | --- |
| S2a | 普通函数：语法、签名、`(*name)`、调用 `&`、lvalue、`out` 初始化/L1 | P-7.1a 原型 |
| S2b | 方法/trait：方法形参、trait 默认体、接口实现签名 | S2a 收口 + P-7.1b 方法/trait 原型 |
| S2c | 类型匹配、负例、文档与门禁 | S2a/S2b |

## 2 任务

| 任务 | 交付 | 验收 |
| --- | --- | --- |
| S2a 普通函数 | 上下文关键字、`T *` 签名、`(*name)`、调用 `&`、lvalue 硬错、`out` 初始化/L1 | `p78_basic`：正例/反例 |
| S2b 方法/trait | 方法形参、trait 默认体、impl 签名；与普通函数同一规则 | `p78_method` / `p78_trait` |
| S2c 类型与文档 | `ref/out` 类型匹配；AST/typecheck 诊断；spec/package 文档 | `p78_types` / `p78_docs` |

## 3 退出判据

| ID | 断言 |
| --- | --- |
| E78-1 | `ref`/`out` 上下文关键字：形参表外仍是标识符；`int out;` 合法 |
| E78-2 | 签名/发射：定义、原型、ABI 头为 `T *`；函数体 `(*name)`；调用点 `&`；与手写指针 C 等价 |
| E78-3 | 调用点 place：变量/字段/`*p`/数组/切片/Vec/Map 元素通过；字面量/表达式/调用结果/cast 硬错 |
| E78-4 | `out` 初始化：trivial 未初始化通过；owning 未初始化硬错；借用未初始化通过 |
| E78-5 | `out` L1 定值：`if/else` 全路径；`return`/末尾检查；循环/switch/goto 保守；`ct build` 默认硬错 |
| E78-6 | 方法/trait 同一规则；S2b 未完成或显式 descope 前 PH-78 不得收口；全量 `check-all` 与 ASan 通过；spec/package-guide 同步 |

## 4 风险与回滚

| ID | 风险 | 缓解 |
| --- | --- | --- |
| R78-1 | Var 行复用导致 ref/out 标志串味 | 每次 `declare_var` 清零；负例 |
| R78-2 | `out` owning 初始化只认声明初始化式，误拒先声明后赋值 | 卡内记录限制；后续数据流补 |
| R78-3 | L1 循环保守误拒「循环内赋值再 return」 | 文档写清；L2 另立 |
| R78-4 | 方法/trait 的签名/默认体与普通函数不一致 | S2b 独立探针；同一发射路径 |
| R78-5 | 调用点 `&` 对非 place 生成坏 C | E78-3 硬错在 CT 层 |

回滚：单卡回滚，去掉关键字、`T *` 发射与调用 `&`；旧 golden 不变。
