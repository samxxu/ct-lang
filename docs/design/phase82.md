# Phase 82 — 泄漏防护（`leaks` 配置 + 直接环告警 + 树模式）

> **状态：实施中（准备；施工入口未过）**（2026-11-20 立项并开卡；`v0.82.0`）。
> **签收：EDITOR 2026-11-20**（主编统一签收；卡作者 REQ）。
> **施工闸门**：PH-81 `box<T>` 未收口；未过前只做配置/检测设计与夹具，不落实现代码。
> **前置**：PH-81 `box<T>` 收口；[D-012](../decisions/D-012.md) accepted；battle leak-guards-1 closed。
> **布局说明**：phase-ID 迁移仍被 blocker 挡住，本卡暂用 legacy 路径 `docs/design/phase82.md`。
> **依据**：[提案草案](../proposals/leak-guards.md)、[D-012](../decisions/D-012.md)、
> [battle 判决](../../battle/leak-guards-1/verdict.md)、[D-011](../decisions/D-011.md) J-4c。

## 0 卡片字段（冻结）

| 项 | 值 |
| --- | --- |
| 编号 | v0-PH-82（legacy 文件 `phase82.md`） |
| 目标 | 把「环 = 作者责任」升级为可见风险：包级泄漏告警可强制、`box` 字段直接环可静态告警、父子结构有官方写法 |
| 范围 | `leaks` 两档（`warn` / `error`）配置；`box<X>` 字段直接环检测（限深 3）；`/* ct: allow-cycle */` 豁免；`patterns.md` 树模式 |
| 非目标 | 运行期环检测/`--debug-leaks` 语义变更；GC；weak；跨过程/容器/泛型间接环；自动解环；句柄运行期泄漏分析 |
| 交付物 | 编译器改动、`test/ast/p82_*`、`patterns.md`/spec 文档、`check-all` |
| 任务清单 | §2（S82a–S82d） |
| 退出判据 | E82-1…E82-8（§3） |
| version-minor | 82（PH-82，`d=0`） |
| 已知风险 | R82-1…R82-5（§4） |

## 1 需求与边界

```ct
/* ct.pkg */
leaks = error          /* error：本包泄漏诊断与直接环告警构建失败；缺省 warn */

struct A { box<B> b; }
struct B { box<A> a; }        /* warning: potential reference cycle: A → B → A */

struct C { box<C> self; }     /* warning: potential reference cycle: C → C */

struct D { box<A> a; }        /* OK：单向，不构成环 */

/* 手工破环的合法写法 */
struct Node {                 /* ct: allow-cycle */
    box<Node> first_child;
    Node *parent;
}
```

- `leaks = warn|error`：缺省 `warn`；`error` 同时升级现有 `potential leak` 诊断与直接环告警；与 `c-boundary = strict` 无关。
- 直接环：只展开 `box<X>` 字段，相邻边计 1，限深 3；同一环只报一次。
- 豁免：`/* ct: allow-cycle */` 必须与 `struct` 声明同一行；`ct check` 输出被抑制点，便于审计。
- `--debug-leaks` 不在本卡：维持 D-011 J-4c，只报未配对 alloc/release 计数，不叫环检测。
- 本卡不改 `c-boundary`、不改 `--debug-leaks`、不引入 GC/weak。

### 1.1 分期

| stage | 内容 | 入口 |
| --- | --- | --- |
| S82a 配置/诊断 | `leaks` 两档（`warn` / `error`）解析与严重级别 | D-012；无代码前置 |
| S82b 环检测 | `box<X>` 字段图、限深 3、去重 | S82a；PH-81 收口 |
| S82c 豁免/负例 | `allow-cycle`；非目标路径不误报 | S82b |
| S82d 文档/门禁 | `patterns.md` 树模式、spec 配置说明、`check-all` | S82c |

### 1.2 施工前准备清单（准备态可做，不落实现代码）

| # | 项 | 通过方式 |
| --- | --- | --- |
| P82-pre-1 | `ct.pkg` 未知键行为：新键 `leaks` 可读、旧编译器静默忽略 | 审读 manifest 解析 + 夹具 |
| P82-pre-2 | 注释 pragma 可行性：词法器当前丢弃注释，确定扫描入口 | 词法只读审查 / 最小探针 |
| P82-pre-3 | `box` 字段图来源：Symbols 的 struct/field 表、build 模式跨单元 | 类型表审查 |
| P82-pre-4 | 严重级别通道：`leaks = error` 不污染 `c-boundary = strict` | Diag/Module 审查 + 负例计划 |
| P82-pre-5 | 默认 `warn` 下既有 leak golden 不变 | `test/modules/leak` 基线 |

## 2 任务

| 任务 | 交付 | 验收 | effort |
| --- | --- | --- | --- |
| S82a 配置 | `ct.pkg` 读 `leaks`；warn/error 两档 | `p82_config` | S |
| S82b 环检测 | `box` 字段图、限深、去重、诊断文案 | `p82_cycle` | M |
| S82c 豁免/负例 | `allow-cycle`；容器/泛型/接口/typedef 不报 | `p82_allow` / `p82_errors` | M |
| S82d 文档 | 树模式、spec `leaks` 说明 | `p82_docs` | S |

每项任务先提 `test(<scope>): <task-id> 红`（含 `baseline: <sha>`），实现提交随后转绿；S82d 为纯文档任务，写 `no-test:` 并由 REVIEW 签字。

## 3 退出判据

| ID | 断言 |
| --- | --- |
| E82-1 | `leaks` 两档（`warn` / `error`）从 `ct.pkg` 读取；缺省 `warn`；存量包无变化 |
| E82-2 | `warn` 下泄漏/环告警不失败；`error` 下同一代码构建失败；`c-boundary` 语义不变 |
| E82-3 | 自环、A→B→A、A→B→C→A 均命中；同一环只报一次；仅 `box<X>` 字段 |
| E82-4 | `Vec<box<T>>`、泛型参数、接口字段、typedef、间接环不报；语料零误报 |
| E82-5 | `/* ct: allow-cycle */` 抑制告警并在 `ct check` 报告；移除后重新告警 |
| E82-6 | 文案为「可能泄漏，除非手工破环」，不写「会泄漏」；`--debug-leaks` 不被改称环检测 |
| E82-7 | `patterns.md` 有父子结构一节；spec 记录 `leaks` 与检测范围/限深 |
| E82-8 | 旧 golden 不变；`check-all` 通过；单卡回滚（配置/检测/文档同退） |

## 4 风险与回滚

| ID | 风险 | 缓解 |
| --- | --- | --- |
| R82-1 | 手工破环被误报 | 默认 warning；`allow-cycle` 豁免；`ct check` 可审计 |
| R82-2 | 限深 3 漏检造成假安全感 | 文案明示范围；L3 已 descope，不承诺运行期 |
| R82-3 | `leaks` 与 `c-boundary = strict` 混淆 | 窄键、专测；文档并列说明 |
| R82-4 | 跨单元类型缺失导致漏报 | `ct build` 全单元在场；`ct check` 单单元缺类型时静默跳过并记录 |
| R82-5 | v1.0 再顺延一个 MINOR | roadmap/D-012 明确；v1.0 范围不变 |

回滚：单卡回滚；`leaks` 配置、环检测、文档同退；`--debug-leaks` 与 D-011 不受影响。
