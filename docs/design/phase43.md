# Phase 43 — 错误出口类型契约（`return err:` 载荷检查）

> **状态：完成（2026-11-14；v0.43.0；R1–R6、E43-1–E43-6 全绿）。**
> **基线**：`v0.42.1` / `7e998150`；S0 已复核。
> **依赖**：无前置相；PH-44 依赖本相收口。判据输入 = [v043-split-plan.md](v043-split-plan.md) §3 与两份 battle 材料
> （`/Users/samxx/.trae-cn/assistant/2026-11-14/ct-43-44-battle/outputs/design.md`、`.../rebuttal.md`）。
> **规模**：编译器 20–40；夹具 100–180；文档 40–70；门禁 20–30；合计 **180–320**（±40%）。
> **版本**：收口 bump `v0.43.0`（五处 `CTC_VERSION` + 两处 README + 受影响 golden 重生成）；phase tag 按 6.7 V-7，分支推送按 6.5。
> **纪律**：只做 `err:` 分支；闭包返回类型缺陷**记录不修**（§0.2）；不改 `ctc.c` / L1 / L2；不动 PH-32 的 D32-6 指针豁免。
> **实施**：任务清单与排期由主编安排；本卡只冻结语义、判据与任务粒度。

## 0 卡片字段（冻结）

| 项 | 值 |
| --- | --- |
| 编号 | PH-43 |
| 目标 | `return err: expr;` 的载荷在所有入口判「可赋给当前函数返回类型」；不一致硬错、不写 `.c`；发射与清理不变 |
| 范围 | O1/O2/O3；只做 `err:` 分支；不做普通 `return`、闭包 `ret_type`、新类型内核、指针基类型 |
| 交付物 | `Stmt.h.ct` / `Expr.h.ct`；`test/ast/p43_*` 与 `test/ast/errors/p43_*`；`examples/45_*`；文档 |
| 任务清单 | §6（R1–R6，共 6 项） |
| 退出判据 | E43-1…E43-6（§7.1） |
| 依赖 | 无前置相；PH-44 依赖本相 |
| 规范版本 | 1.9.0 |
| version-minor | 43 |
| 已知风险 | R43-1…R43-8（§9） |

## 0 背景与解决的问题

### 0.1 现状实测

`return err: expr;` 今天在默认路径完全不判载荷类型，编译器判得出冲突却静默写出 `cc` 拒绝的 C，违反仓库「禁发射坏 C」的底线。

| 事实 | 数值 / 证据 |
| --- | --- |
| `err:` 只在 `return` / `break` / `continue` 之后识别 | `frontend/parse/Stmt.h.ct:1388-1397`（`err_ahead`），消费点 `:1941-1946` |
| 载荷类型检查整段被 `types_mode` 包住 | `frontend/parse/Stmt.h.ct:1993-2014` |
| 判定内核 | `frontend/parse/Expr.h.ct:6059-6099`（`chk_type`）→ `:6108-6139`（`chk_assignable`） |
| 失败通道今天是 `ct_type_warn` | `Expr.h.ct:6137`；`ct check` 把 warning 升为 error（`tool/driver/Driver.h.ct:223-226`），`ct compile` 返回 0（`:546-547`） |
| `return err:` 的发射不包装 | `backend/emit/Emitter.h.ct:3623-3678`：载荷为负时 `return;`，否则 `return <expr>;` |
| 默认路径现状 | `Result<int, char *>` 函数里 `return err: 1;` / `return err: p;`（`p` 为 `char *`）→ `ct compile` rc=0，照写 `.c`，`cc` 报 incompatible result type（design A.1、rebuttal A.1） |
| `ct check --types` 现状 | 四种变体（`int`→`int`、`int`→`char *`、`struct T`→`struct S`、载荷填入 `Result` 槽）全部判得出（rebuttal A.2） |
| 全仓 `return err:` 站点 | **8 处 / 8 文件**（`grep -rn --include="*.ct"`）；加 `test/ast/p40_err_syntax.sh` 内联字符串 4 处 = 12 处 / 9 文件 |
| `break err:` / `continue err:` | 2 处 `.ct` + 5 处探针 = 7；无载荷，不在本相范围 |
| 受影响语料 | 461 文件（`test/ast/*/prog.ct` + `examples/*/*.ct` = 277，`test/cases` + `test/modules/**` + `test/bindings/**` = 184），补丁口径 rc 平价 **0 差异**（design A.3） |
| 补丁对 933 个 `.ct` 的 `ct compile` 差集 | `new_red=0`、`new_stderr=0`（rebuttal A.5，只对 `err:` 去门槛的 variant A） |
| 全量默认开（普通 `return` 也查） | 多出 `examples/18_generic_string_table/generic_string_table.ct:103:20` 假阳性（rebuttal A.4）→ 必须用 `is_err` 收窄 |
| `--types` 去重 | `is_err` 恒判后，同一调用点只打印一行、`1 error(s) generated`（design A.5） |

### 0.2 既有缺陷（记录在案，本相不修）

**缺陷**：闭包块体内的 `return` 沿用外层函数的 `ret_type`。

- **根因**：`parse_closure`（`frontend/parse/Expr.h.ct:4560-4646`）从不设置 `sym->ret_type`；`ret_type` 只在函数 / 方法体设置
  （`frontend/parse/Parser.h.ct:283`、`:1643`、`:3061`、`:3215`、`:3582`）。闭包块体的 `return` 走 `Stmt.h.ct:1993`，读到的仍是外层函数的返回类型。
- **表现 ①（假阳性）**：`examples/18_generic_string_table/generic_string_table.ct:103`（及 `:105`）里合法的 `char *` 被报
  `expected 'int'`；只在 `ct check --types` 下出现（`baseline --types rc=1`，默认 `ct check` rc=0）。
- **表现 ②（漏判）**：外层函数返回 `void` 时，闭包体内 `return err:;` rc=0 通过，并给返回 `int` 的 trampoline 发出 `return;`，
  `cc` 报 `non-void function ... should return a value`（design A.6 的 V5）。
- **来源**：以上两条均为两份 battle 材料的实测结论（`design.md` §1.7 / 附录 A.6，`rebuttal.md` R43-3 / A.4）。
- **归属**：**记录在案，待另立单子修；不计入 PH-43 的任务切分与验收。** 修法是给闭包独立的 `ret_type`（闭包返回类型推断 + 闭包表 + 上下文传播），
  属独立特性；塞进本相会把一个补丁扩成类型系统相。PH-43 落地后该路径仍可能以 rc=0 穿过 `err:` 检查（见 §9 R43-1）。

## 1 目标 / 非目标

### 1.1 目标

| 编号 | 内容 |
| --- | --- |
| O1 | `return err: expr;` 的载荷在所有入口（`ct build` / `ct compile` / `ct check` / `ct check --types`）判「可赋给当前函数返回类型」，不一致即硬错 |
| O2 | 诊断走 `ct_sem_error`：rc=1、不写 `.c`；`--types` 不重复报告同一条 |
| O3 | 零回归：461 语料 rc 平价 0 差异；8 个既有 `return err:` 站点全绿；生成 C 逐字节不变（诊断不改发射） |

### 1.2 非目标

| 不做 | 理由 |
| --- | --- |
| 给普通 `return` 打开默认检查 | 全量默认开会把 `examples/18:103` 的闭包假阳性变成合法程序硬错（§0.2）；属策略变更，另案 |
| 修闭包 `ret_type` 缺陷 | 见 §0.2；记录不修，另立单子 |
| 要求载荷是 `Result::err(...)` 形状 | `return err: t;`（`t` 是 Result 变量）合法且是唯一合理写法；形状匹配会造第二套规则 |
| 自动把载荷包进 `Result::err()` | 改 PH-40 冻结的「原样返回 + 单栈 LIFO」，且要求编译器认识 `Result`，与 PH-34 冲突 |
| 为类型内核补数组 / 闭包 / 函数指针 / `sizeof` / 强转模型 | 沿用 §4.53 的判不出即跳过边界；仍交 `cc`，不伪装有覆盖 |
| 改 `break err:` / `continue err:` | 无载荷，行为不变 |
| 改 `chk_type` / `chk_assignable` 判定体、`Emitter.h.ct`、`Diag.h.ct` | 本相只去门槛 + 换诊断通道 |
| 改动 PH-32 D32-6 的指针豁免 | 已冻结；借机改会让 `ct check --types` 与 build 不一致 |

## 2 设计决定清单

| 编号 | 决定 | 为什么不用另一种 |
| --- | --- | --- |
| **D43-1** | 诊断一律 `ct_sem_error` 硬错，四入口一致 | 实测只去门槛会得到 `warning`、rc=0、坏 `.c` 照写（rebuttal R43-1 / A.3），达不到「禁发射坏 C」；本相范围极窄（只在 `err:` 标记后），不需要 warning 缓冲期 |
| **D43-2** | 检查位置 = 解析期 `return` 分支（`Stmt.h.ct:1993-2014`），复用 `chk_type` / `chk_assignable`；只对 `err:` 分支恒判 | 发射期拿不到局部变量的静态类型（`static_ctype` 依赖解析期 `sym`，见 `Expr.h.ct:4065-4068` 的注释），只能对 C 文本猜类型，违反「禁止字符串前缀匹配猜类型」；新建独立 pass 等于第二套类型内核 |
| **D43-3** | 判定口径 = 只判「可赋值」，不要求 `::err()` 形状、不自动包装 | `return err:` 的语义是「求值到临时量 → 跑 errdefer / defer → 原样返回」（PH-40 冻结）；对 `Result<T,E>` 返回类型，唯一合法载荷就是整个 Result 值，这是「可赋值」的自然结果，不是额外规则 |
| **D43-4** | 门槛用 `is_err` 收窄：`is_err` 恒判，普通 `return` 仍只在 `--types` 下判 | 全量收紧会多出 `examples/18:103` 假阳性（§0.2 的闭包 bug），把合法程序判红 |
| **D43-5** | `--types` 去重：`is_err` 恒真时短路 `types_mode`，同一调用点只报一次 | 两条路径各报一次会改变既有 `--types` 的计数与夹具 |
| **D43-6** | 复用 `chk_assignable` 的既有豁免：接口槽、裸 `0` 填指针、任意两指针互不比较（D32-6） | 这些是 PH-32 冻结的口径；本相只改触发面，不新增判定分支 |
| **D43-7** | 文案复用 L32-3 的 `return: expected '<T>', got '<U>'`，用 C 拼写 | 内核只拿到 `ret_type` 字符串；反查成人话拼写要读实例表 `carg`，是可选项，不进本相判据 |
| **D43-8** | `break err:` / `continue err:` 行为不变 | 无载荷，与返回类型契约无关 |
| **D43-9** | 闭包返回类型缺陷只记录、不修（§0.2） | 用户 2026-11-14 补充裁定；修复属独立特性，不进任务与验收 |
| **D43-10** | 不动发射：生成 C 与 golden 不变，只有 stderr 诊断变化 | 本相是「把已冻结的 opt-in 检查挪进默认路径」，不是新发射语义 |

## 3 语法与语义

### 3.1 契约

- `return err: expr;`（非 void 函数）：`expr` 的静态 C 类型必须可赋给当前函数的 `ret_type`。
- 判定链：`chk_type(expr)` 判不出 → **跳过**（沿用 §4.53 边界，交 `cc`）；判得出 → `chk_assignable(ret_type, actual, is_zero, diag=7)`。
- 不一致 → **L43-1 硬错**，位置在表达式起点（实测列 21，指向 `first.err` 的 `f`），不写 `.c`。
- 一致 → 发射与清理语义完全不变：`return (expr);`，errdefer / defer 单栈 LIFO、`own` 泄漏分析、`retire_before_return` 全部复用。

### 3.2 判定与豁免

- 同 struct / 同泛型实例：通过。
- 不同 struct、struct 与标量、算术类与指针：L43-1。
- 接口槽：沿用 `is_iface_type` 豁免（`Expr.h.ct:6116`）。
- 裸 `0` 填指针槽：沿用 `is_zero` 豁免（`:6117`）。
- 两个指针互不比较基类型与层数：沿用 D32-6（`:6120`）。**推论**：返回 `Result<...> *` 时任意指针载荷仍 rc=0，属契约保证之外（§9 R43-2）。
- 数组、闭包、函数指针、`sizeof` / `_Generic` / 宏：`chk_type` 判不出 → 跳过，仍由 `cc` 兜底（§9 R43-3）。

### 3.3 void 一致性（既有行为，不变）

| 形态 | 现状 | 本相 |
| --- | --- | --- |
| `void f(void) { return err:; }` | rc=0 | 不变 |
| `int f(void) { return err:; }` | L40-1 硬错 | 不变 |
| `void f(void) { return err: 1; }` | L40-2 硬错 | 不变 |
| 非 void + `return err: expr;` | 默认 rc=0（本相缺口） | 新增 L43-1 |

### 3.4 闭包边界

- 闭包块体内的 `return err:` **不在本相契约保证内**：它读的是外层 `ret_type`（§0.2）。
- 本相不加闭包专用诊断、不改 `parse_closure`、不加闭包夹具；全仓闭包体内目前没有 `return err:` 站点，破坏面为 0。

### 3.5 清理语义不变

失败返回仍然先求值到临时量、再跑 errdefer / defer、最后返回该临时量；`err:` 只是标记，不改变单栈 LIFO（PH-40 冻结）。

## 4 诊断清单（L43-n）

| 编号 | 触发 | 文案 | 位置 | 级别 |
| --- | --- | --- | --- | --- |
| **L43-1** | `return err:` 载荷与返回类型不相容 | `return: expected '<T>', got '<U>'`（复用 L32-3 文案，C 拼写） | 表达式起点 | 硬错，四入口一致 |
| L40-1（不变） | 非 void 写 `return err:;` | `an error return needs a value` | `return` 关键字 | 硬错 |
| L40-2（不变） | void 写值 | `a void function cannot return a value` | `return` 关键字 | 硬错 |

`--types` 不新增编号、不重复报告；L43-1 在 `ct check` 下也走 `ct_sem_error`，不依赖 strict 升级。

## 5 完整性边界

| 维度 | 内容 |
| --- | --- |
| 交付后能写 | 任何返回类型的函数都可写 `return err: expr`；载荷与返回类型一致时编译通过，清理语义不变 |
| 不能写 | 载荷与返回类型不一致（不同 struct、struct↔标量、算术↔指针）；返回 `Result` 却用 `int` / `char *` 载荷 |
| 不能写的反馈 | `file:line:col: error: return: expected '<T>', got '<U>'`，列指向表达式起点；rc=1，不写 `.c`；四入口一致 |
| 明确仍不判 | 数组、闭包、函数指针、`sizeof` / `_Generic` / 宏；指针返回形态的基类型；闭包块体内的 `return err:`（§0.2）。全部写进 §9，不在实现里偷偷放宽 |
| 为什么指针形态不判 | PH-32 D32-6 已冻结「任意两个指针互转均跳过」；本相不能改，只能在规范里写明「指针返回形态不在契约保证内」 |

## 6 任务切分

**S0（不占任务行）**：只读核查 §0 行号、461 语料基线、8 个站点与四入口现状；在 `e086fa09` 上冷构建并记录 `baseline.sha`；不产提交。

| 任务 | 交付物（路径） | 验收命令 | effort | 回滚 |
| --- | --- | --- | --- | --- |
| R1 | 负例夹具 + 探针（`test/ast/p43_err_return_type.sh`、`test/ast/errors/p43_*`） | `ok p43/errors`，4/4；stderr 逐字匹配 | M | revert |
| R2 | 正例夹具 + 样例（`test/ast/234_err_return_contract/`、`examples/45_*`、`test/run.sh` 接线） | `ok p43/positive`，4/4 + 样例运行；`no-test:` 正向夹具在实现前已绿（3.9 test-fix） | S | revert |
| R3 | 实现：门槛收窄 + L43-1 走 `ct_sem_error`（`Stmt.h.ct` / `Expr.h.ct`） | `ok p43/diag`，1/1；≤3 文件、≤150 行 | S | revert |
| R4 | 四入口一致 + `--types` 去重（同两文件 + p43 探针） | `ok p43/entry`，1/1；单点只报一行；`ct compile` 不写 `.c` | S | revert |
| R5 | 461 语料平价 + 8 个既有站点 + p40 回归 | `ok p43/corpus`，461/461 + 8/8；`p43/regression` 11/11 | S | revert |
| R6 | 文档四件套 + 样例接线（`language-spec` / `tutorial` / `README*` / `glossary`） | `python3 test/docs/check-docs.py` rc=0；`ok p43/docs`；`no-test:` 纯文档 | S | revert |

依赖：R1/R2 → R3 → R4 → R5 → R6；R2 可与 R1 并行。每项至多覆盖 1 条退出判据（6.6 T-5）；每笔实现提交的父提交是它的 `test(p43): <task-id> 红`。

## 7 验收

### 7.1 退出判据

| ID | 断言 | 命令 / 阈值 | 夹具 |
| --- | --- | --- | --- |
| **E43-1** | L43-1 覆盖四种负例，文案与位置精确；四入口 rc=1；`ct compile` 不写 `.c` | `ok p43/errors`，4/4；stderr 逐字匹配 | `test/ast/errors/p43_*` |
| **E43-2** | 正例通过并运行：`int`→`int`、`char *`→`char *`、Result 值→Result 返回、带 errdefer 的正确路径 | `ok p43/positive`，4/4；rc=0 且输出匹配 | `test/ast/234_err_return_contract/`、`examples/45_*` |
| **E43-3** | 461 语料 rc 平价 0 差异；8 个既有站点全绿 | `ok p43/corpus`，461/461 + 8/8；`rc_diff=0` | §0.1 清单 |
| **E43-4** | `--types` 不重复报告；`p40_*` 6 目录 + 4 探针 + `examples/43` 全绿 | `ok p43/entry`，1/1；`ok p43/regression`，11/11 | §0.1 清单 |
| **E43-5** | 文档四件套同步；`check-docs` 绿；样例进 `test/run.sh` | `python3 test/docs/check-docs.py` rc=0；`ok p43/docs` | `docs/**`、`examples/45_*` |
| **E43-6** | **任务清单每项可独立验收（6.6 T-6）** | 逐项跑 §6，6/6 exit 0；收口对照表逐行贴输出 | §6 |

### 7.2 正向夹具

- `int f(int n)` 里 `return err: n;`（同类型）。
- `char *f(void)` 里 `return err: p;`（`p` 为 `char *`）。
- `Result<int, char *> f(...)` 里 `return err: t;`（`t` 是 `Result<int, char *>` 变量）。
- 带 `errdefer` 的错误返回路径：`errdefer` 执行一次，返回载荷正确。

### 7.3 负例夹具

- `Result<int, char *>` 函数里 `return err: 1;`。
- `Result<int, char *>` 函数里 `return err: p;`（`p` 为 `char *`）。
- `struct S f(void)` 里 `return err: t;`（`t` 为 `struct T`）。
- `Result<int, char *>` 函数里 `return err: other;`（`other` 为 `Result<long, int>`）。

### 7.4 门禁接线

| 门禁 | 接线 |
| --- | --- |
| `test/run.sh` | `examples/45_error_return_contract`（`//@ct-requires: ct-ast`） |
| `check-ast.sh` | `test/ast/p43_err_return_type.sh` 探针 + `test/ast/234_err_return_contract/` 目录 |
| `check-warnings.sh` | 新增夹具零告警 |
| `check-docs` | spec / tutorial / README / glossary 同步 |
| `check-all.sh` | 收口 11 道全绿（不新增门禁条数） |

### 7.5 可量化平价

- **461 语料 rc 平价**：277（`test/ast/*/prog.ct` + `examples/*/*.ct`）+ 184（`test/cases` + `test/modules/**` + `test/bindings/**`），`rc_diff=0`。
- **8 个既有 `return err:` 站点全绿**：载荷都是 `int`→`int` 函数（§0.1）。
- **生成 C 不变**：补丁不碰发射，产物逐字节比对为 0 差异。

## 8 完成定义（DoD）

| 面 | 交付 | 缺一不算完成 |
| --- | --- | --- |
| 实现 | 门槛收窄 + `ct_sem_error` 通道 + `--types` 去重；无 TODO、无「暂不支持」分支 | ✓ |
| 诊断 | L43-1 四负例、精确文案与位置、四入口一致、`ct compile` 不写 `.c` | ✓ |
| 文档 | `language-spec.md` §4.53 / §4.58、`tutorial.md`、`README.md` / `README.en.md`、`glossary.md`（如需）；`check-docs` 绿 | ✓ |
| 门禁 | 夹具进入 `test/run.sh` / `check-ast.sh`；`check-warnings` 零告警；`check-all` 11 道全绿；收口 bump `0.43.0`；红证按 T-7 提交 | ✓ |

## 9 风险与不做项

| 编号 | 风险 / 不做项 | 触发信号 / 处置 |
| --- | --- | --- |
| R43-1 | **闭包路径仍可能以 rc=0 穿过 `err:` 检查**：闭包块体的 `return` 继续读外层 `ret_type`（§0.2），外层 `void` + 闭包内 `return err:;` 仍会发非法 C | 记录在案，另立单子修；本相不以任何方式兜底，也不加夹具锁死 |
| R43-2 | 指针返回形态（`Result<...> *`）接受任意指针载荷 | D32-6 冻结；写进 spec「不在契约保证内」，不借机改 |
| R43-3 | 判不出的形态（数组 / 闭包 / 函数指针 / `sizeof` / `_Generic` / 宏）仍 rc=0 交 `cc` | 沿用 §4.53 边界；写进 non-goals 与 spec，不静默声称覆盖 |
| R43-4 | 文案用 C 拼写（`struct Result_int_char_p`）而非源码拼写 | 内核口径；反查 `carg` 是可选改进，不进本相 |
| R43-5 | `--types` 重复报告回归 | R4 专项断言；同一调用点只允许一行 |
| R43-6 | 文档漂移：§4.53 的「逐字节不变」必须限定为其余三类检查点 | R6 逐句改，不整段重写；与其他文档线按句协作 |
| R43-7 | 改到 PH-32 D32-6 / PH-40 清理语义 | 冻结项；任何改动停下来报用户 |
| R43-8 | 闭包返回类型的真修法（给闭包独立 `ret_type`）被误当本相范围 | 明确另案；本相任务表与验收表都不含闭包项 |

### 7.6 收口记录（2026-11-14）

| 任务 | 验收命令 | 结果 |
| --- | --- | --- |
| R1 | `p43/errors` | 4/4；L43-1 硬错、`compile` 不写 `.c` |
| R2 | `234_err_return_contract` + `examples/45_error_return_contract` | 4/4；运行输出匹配 |
| R3 | `ct check` / `ct compile` | 差载荷 rc=1；正例 rc=0 |
| R4 | `--types` / 四入口 | 单次报告；四入口一致 |
| R5 | 既有语料 / p40 | 全量 `check-all` 11/11 |
| R6 | `check-docs` | 1010 links / 223 files |

收口总量：check-ast 1364/0、test/run 155、warnings 616/0、docs 1010/223、grammar 169/0、acceptance 20/0。

tag/push：`v0.43.0` annotated tag 与分支自动 push。
