# Phase 78 — `ref` / `out` 参数（S2）

> **状态：完成（S2a–S2c / E78-1–E78-6；`v0.78.0`）**（2026-11-20 开卡并收口）。
> **前置（口径写死）**：本卡入口只要求 **P-7.1a 自由函数 + P-7.1b 方法/trait 原型**，
> 二者已由 `docs/planning/j6-evidence/ref_out/` 覆盖（基线 `2c87179a`，7 文件 369 行）。
> **P-7.2（S3 切片）/ P-7.3（S5 最小垂直切片）不在本卡入口，J-6 也未全量通过**；
> 卡内不据此声称 J-6 已过（J-6 见 [phase 安排](../planning/pointer-free-phase-plan.md) §3）。
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

## 5 T-7 红证（S2a–S2c）

- **baseline**：`07693e47`（v0.77.2；PH-78 任何源码改动之前）。
- **编译器**：由 baseline 源码构建的 ct-ast（`v0.77.2`）；完整原始输出见
  [test/ast/p78_red.log](../../test/ast/p78_red.log)。
- **命令与退出码**：

```console
$ CC=cc sh test/ast/p78_basic.sh  /tmp/p78/ct-ast   # exit 1
$ CC=cc sh test/ast/p78_method.sh /tmp/p78/ct-ast   # exit 1
$ CC=cc sh test/ast/p78_types.sh  /tmp/p78/ct-ast   # exit 1
$ CC=cc sh test/ast/p78_docs.sh                      # exit 1
```

原始输出（节选，逐字）：

```text
FAIL p78/basic: E78-2 ref/out free function (run)
prog.ct:5:10: error: unknown type name 'ref'
    5 | void inc(ref int);
FAIL p78/basic: E78-2 emission shape
void inc(ref int x) {
    x = (x + 1);
}
...
FAIL p78/basic: E78-5 loop is conservative
  wrong diagnostic: ... bad_loop.c ...
bad_loop.ct:5:10: error: unknown type name 'out'
FAIL p78/basic: E78-5 ct check uses the same rule
  accepted (expected a hard error)

FAIL p78/method: E78-6 trait method ref/out (dispatch, run)
methods.ct:3:26: error: unknown type name 'ref'
    3 |     void (*bump)(void *, ref int, out int);
FAIL p78/method: E78-6 method out must be assigned on every path
  wrong diagnostic: ... bad_out.c ...
bad_out.ct:3:26: error: unknown type name 'ref'
    3 |     void (*bump)(void *, ref int, out int);

FAIL p78/types: ref base type mismatch
  wrong diagnostic: ... ref_type.c ...
ref_type.ct:6:10: error: unknown type name 'ref'
    6 | void inc(ref int);
FAIL p78/types: out does not disturb own/AutoDrop
own_sem.ct:8:10: error: unknown type name 'out'

FAIL p78/docs: spec section 4.68 (ref/out) missing
FAIL p78/docs: tutorial section 15 (ref/out) missing
FAIL p78/docs: tutorial does not show ref/out spelling
```

红证断言的判据：baseline 上四个探针均非零；实现后四个探针全绿（见 §7 收口对照表）。

## 6 未完成 / 简化 / 边界（诚实清单）

- `out` 的**调用方 owning 初始化**只检查直接变量实参；字段、数组元素、Vec/Map 元素作为
  owning 实参时按"已初始化"处理（L1 不做逐字段/逐元素定值）。
- 把 `out` owning 形参在赋值前**转发**给另一个 `out` 形参会被保守拒绝；不做跨过程/形参数据流。
- `out` L1 只建模语句位置与 if/else（含条件内赋值）；直接三元分支取交集；短路表达式内部、
  `into` 块内部和跨过程调用不建模；循环/switch 保守；`goto` 要求跳转时已赋值。
- `Map` 元素在语言里的静态类型是 `V *`，可写 place 的拼写是 `*m[k]`；裸 `m[k]` 不是
  `ref V` 的 place。自定义下标（Phase 52 的 `get/set` 协议）不是 place。
- 数组与函数指针形态的 ref/out 形参硬错；`ref` 不做借用检查，存储/透传风险仍由契约与
  直接 lint 承担（J-4b）。
- 泛型自由函数的 ref/out、跨单元高阶形态与闭包实参不在本卡验收范围；本卡验收的是
  自由函数、trait/默认体/impl、固有方法与泛型 impl（含静态固有方法）。
- L2 的 `--emit-map` 直接调用边上限 1024→4096 是容量修正（ct-ast 源码在加本卡代码后
  超过旧上限）；不改 L2 的语义或产物。

## 7 收口对照（E78-1…E78-6）

- 编译器：`ct-ast v0.78.0`（`bash selfhost/check-all.sh` 自建链）。
- 探针：`test/ast/p78_basic.sh` / `p78_method.sh` / `p78_types.sh` / `p78_docs.sh`
  （已接入 `selfhost/check-ast.sh` 的 PH-78-S2a/S2b/S2c 四项）。
- 红证：`07693e47`，见 §5 与 [test/ast/p78_red.log](../../test/ast/p78_red.log)。

| ID | 命令 | 结果（原始输出） |
| --- | --- | --- |
| E78-1 | `CC=cc sh test/ast/p78_basic.sh <ct-ast>` | `ok   E78-1 contextual keyword (int out; time_t *ref; parameter named out)`；`p78_basic: OK`，exit 0 |
| E78-2 | 同上 | `ok   E78-2 ref/out free function (run)`；`ok   E78-2 signature T *, body (*name), call &`；`ok   E78-2 hand-written pointer C behaves the same`；`ok   E78-2 ABI header spells T *` |
| E78-3 | 同上 | `ok   E78-3 places: variable/field/*p/array/Vec/Map element`；literal / expression / call result / cast 四条 `ref/out argument must be an assignable place` 负例全绿 |
| E78-4 | 同上 | trivial 未初始化、owning 已初始化、owning 后续赋值、owning 未初始化硬错、非 owning 指针未初始化五条全绿 |
| E78-5 | 同上 | if/else、赋值后 return、单边 if 硬错、提前 return 硬错、循环保守、switch 保守、goto 保守、`ct check` 同规则八条全绿 |
| E78-6 | `CC=cc sh test/ast/p78_method.sh <ct-ast>` | 12 条 `ok`：trait 方法、vtable/定义/体/调用点、泛型 impl、默认体、固有、泛型固有、静态固有，以及 4 条负例；`p78_method: OK`，exit 0 |
| S2c | `CC=cc sh test/ast/p78_types.sh <ct-ast>`；`CC=cc sh test/ast/p78_docs.sh` | types：9 条 `ok`（基类型/数组/函数指针/重声明/指针/defer/own 语义），`p78_types: OK`；docs：8 条 `ok`，`p78_docs: OK` |
| 全量 | `bash selfhost/check-all.sh` | `check-all: OK (11 hard gates green)`，exit 0；G0 `g0: OK`、G8 `g8: OK`；`python3 test/docs/check-docs.py` → `check-docs: OK (..., v0.78.0, 11 hard gates, ...)` |
| ASan | `bash selfhost/check-sanitizers.sh` | 见 §7.1（本机实测结果） |

### 7.1 ASan / UBSan

```console
$ bash selfhost/check-sanitizers.sh
...
check-sanitizers: OK (581 checks, no sanitizer report)
```

覆盖：ASan/UBSan 重建 L0→L1→L2→ct-ast，跑 `test/run.sh`、全部 `test/ast/*/prog.ct`
与 `test/ast/errors/*.ct`；`detect_leaks=0`（编译器 arena 常驻，泄漏语义由编译期
`check-warnings.sh` 负责），退出码 0。注意：该门禁覆盖既有语料，p78 的四个探针不在
其 fixture 循环内（它们是独立 shell 探针，生成的新 C 同样只是普通指针/`(*name)`）。

红证基线之上、跑本卡前，`ref/out` 的 C 签名不成立，p78 探针全部红；实现后四个探针
全绿，且全量 `check-all` 11/11。
