# Phase 45 — 类型契约一致性（闭包 `return` 与指针基类型判据）

> **状态：完成（2026-11-15；v0.45.0；S1–S5 全绿）**
> **基线（v0.44.2 复核，2026-11-15）**：`/Users/samxx/trae-ws/ct-lang`，`CTC_VERSION 0.44.2`；
> 卡内行号已全部按当前 `selfhost/` 重取（见 §0.4）。原规划基线 `e086fa09`（v0.42.1）只作历史记录。
> **依赖**：无硬前置。用户 2026-11-15 直接签字立案，排在本波 **PH-46 之前**；PH-43 已收口，无并发门禁冲突。
> **规模**：S1 **2–6 行** + S2 **≈50 行**；夹具 60–120；文档 30–60。合计 **100–190**（小相，±40%）。
> **编号来源**：45 号此前只被用于**评估**「用 ABI 哈希做导出面校验」，该方案已判不采纳并转入
> `REQ-ABI-1`（[requirements-pool.md](../planning/requirements-pool.md)）；45 号从未立项，**本卡为首次占用**。
> **版本**：收口 bump `v0.45.0`（五处 `CTC_VERSION` + 两处 README + 受影响 golden 重生成）；
> `v0.44.2` 已发版，45 的 bump 是**下一版**；tag / push 需用户单独授权。
> **签字记录**：本条只记「用户直接签（2026-11-15）」，未走 PH-46–52 的主张/反证/裁决流程，
> 本卡不引用裁决记录，也不把结论写成 battle 产物。
> **纪律**：只收紧已判得出的两类判据；**不得因本相放宽既有 golden**；不引入新 pass / CFG / 数据流。

## 0 背景与解决的问题

### 0.1 缺口①：闭包块体 `return` 误用外层 `ret_type`

规范已写下的契约（[language-spec.md §4.53](../language-spec.md)，`:2255`；「判不出就跳过」在 `:2264-2265`）：
数组、闭包、函数指针等静态类型判不出的位置**一律静默**。实现没有做到：

| 事实 | 证据（v0.44.2 行号） |
| --- | --- |
| return 的判定直接读 `self->sym->ret_type` | `frontend/parse/Stmt.h.ct:1996-2002`（L32-4 分支：非 void 的 `return;`）、`:2038-2060`（L32-3 / L32-5 分支） |
| `parse_closure` 从不设置 `sym->ret_type` | `frontend/parse/Expr.h.ct:4667-4755`（`ret_type` 只在函数 / 方法体设置：`Parser.h.ct:283`、`:1643`、`:3060`、`:3214`、`:3581`） |
| 现成的闭包深度计数器 | `Expr.h.ct:422`（`ncl_stack`）、`:4722-4726`（压栈）、`:4748-4749`（弹栈） |
| 假阳性 | `examples/18_generic_string_table/generic_string_table.ct:103`、`:105`：合法的 `char *` 被报 `expected 'int'`，只在 `ct check --types` 下出现（v0.44.2 复跑仍 rc=1，两条） |
| 漏判 | 外层 `void` 时闭包体 `return err:;` 通过，并给返回 `int` 的 trampoline 发出 `return;`，`cc` 报 `non-void function ... should return a value` |

**判定**：这是「规范已承诺、实现未兑现」，不是新特性。S1 在 return 判定前置 `ncl_stack == 0`，恢复
§4.53 已写下的跳过契约；**不**给闭包做返回类型推断（那是 [phase43.md](phase43.md) §0.2 记录的独立缺陷，
本相只按契约绕过，不宣称修复）。

### 0.2 缺口②：指针基类型 / 层数在五个位置两种判据

| 事实 | 证据（v0.44.2 行号） |
| --- | --- |
| 通用内核在「两侧都是指针」时直接放行 | `frontend/parse/Expr.h.ct:6281`：`if (strchr(formal, '*') && strchr(actual, '*')) return 0;` |
| 调用实参位置却能判基类型 | `Expr.h.ct:1396-1449`（`argtype_mismatch`）：`arg_class` 得 `r == 2` 后按 `find_struct` 比较（`:1433-1437`），不一致报 `argument <n>: expected '…', got '…'`（`:1438-1442`） |
| 四处放行 | 初值 / 赋值 / `return` / 容器与泛型固有方法实参都走 `chk_assignable`，全部被 `:6281` 短路 |
| 一处必报 | 普通函数调用实参走 `argtype_mismatch`（`Expr.h.ct:1396-1449`） |
| 触发条件已满足 | `phase32-draft.md:423`（T32-1）写「出现真实误用且容器元素形态稳定后再做层数 / 基类型比较」；实测 `struct User *u; struct Admin *a; u = a;` 在 `check` / `check --types` / `build` 三入口均 rc=0 |

**判定**：同一条 `chk_assignable` 内核在两个调用点两套判据，内部不自洽。S2 让 `:6281` 复用
`:1396-1449` 已有的 `r == 2` 解析逻辑（不新建第二个兼容内核），把四个位置拉到与调用实参同一判据。

### 0.3 出口一致性：v0.43.0 已覆盖，本条为回归约束

**要求**：错误出口在**默认路径**（`ct build` / `ct compile` / 不带 `--types` 的 `ct check`）上不得以
rc=0 写出 `cc` 拒收的 C；`ct check --types` 判得出的错误必须与默认路径同判据（同文案、同位置、rc=1）。

**核查（2026-11-14，`ct-ast v0.43.0`，探针在 `/tmp/ctv`）**：`Result<int, char *> f(void) { return err: 1; }`

```console
$ ct-ast compile p43a.ct -o p43a.c
p43a.ct:3:17: error: return: expected 'struct Result_int_char_p', got 'int'
ctc: 1 error(s) generated          rc=1；未写出 p43a.c

$ ct-ast check p43a.ct             -> 同一行，rc=1
$ ct-ast check --types p43a.ct     -> 同一行，rc=1（不重复报告）
$ ct-ast compile p43b.ct（`char *` 载荷）-> ... got 'char *'，rc=1，未写出 .c
```

**结论**：**已被 v0.43.0 覆盖，本条仅为回归约束**，PH-45 不重复实现出口判定。S2 改动
`chk_assignable` 的指针短路后，`err:` 载荷走同一内核，必须复跑上述探针，确保默认路径仍 rc=1 且不写 `.c`
（列入 E45-5）。本相与 S2 的关系仅此一条：**S2 收窄指针豁免，不得让已覆盖的 `err:` 出口退回 rc=0**。

**v0.44.2 复核（2026-11-15）**：`Result<int, char *> load(int n){ if (n < 0) return err: 1; ... }`
在 `compile` / `check` / `check --types` 三入口均 rc=1，文案同为
`return: expected 'struct Result_int_char_p', got 'int'`，且 `compile` 未写出 `.c`。回归约束成立。
**探针拼写需修正**：原文写作 `f(void)`，v0.44.2 下该参数表本身即 rc=1（`:1:7: error: expected a name`），
复跑必须用 `load(int n)` 这类带参形态；这是探针写法失效，不是结论失效。

### 0.4 基线 v0.44.2 复核（行号漂移表）

原卡按 `e086fa09`（v0.42.1）取行号；下表是 2026-11-15 在 `CTC_VERSION 0.44.2` 上逐条重取的结果。
**所有代码锚点在 v0.44.2 仍存在，无一条被删除或改写**；漂移只是行号位移，另有一处定量断言已不成立。

| 卡内原引用 | v0.44.2 现位置 | 结论 |
| --- | --- | --- |
| `Stmt.h.ct:1955`（L32-4） | `:1996-2002` | 漂移 |
| `Stmt.h.ct:1993`（L32-3 / L32-5） | `:2038-2060`；void 返回值硬错在 `:2021-2024` | 漂移 |
| `Expr.h.ct:6120`（指针短路） | `:6281` | 漂移 |
| `Expr.h.ct:1402-1414`（`arg_class`） | `argtype_mismatch` `:1396-1449`；`r == 2` 判定 `:1433-1437` | 漂移 |
| `Expr.h.ct:402`（`ncl_stack`） | `:422` | 漂移 |
| `Expr.h.ct:4615-4619`（压栈） | `:4722-4726` | 漂移 |
| `Expr.h.ct:4638-4639`（弹栈） | `:4748-4749`；`parse_closure` 起于 `:4667` | 漂移 |
| `Parser.h.ct:283` | `:283` | 不变 |
| `Parser.h.ct:1643` | `:1643` | 不变 |
| `Parser.h.ct:3061` | `:3060` | 漂移（−1） |
| `Parser.h.ct:3215` | `:3214` | 漂移（−1） |
| `Parser.h.ct:3582` | `:3581` | 漂移（−1） |
| `language-spec.md §4.53 :2190-2191` | §4.53 起于 `:2255`；「判不出就跳过」在 `:2264-2265` | 章节整体后移，不是失效 |
| `examples/18…:103` / `:105` | 两行未变；v0.44.2 复跑仍 rc=1、两条 `expected 'int', got 'char *'` | 不变 |
| `check_only/struct_ptr.ct`（209 / 210） | 路径未变，正文仍是「两指针不比较基类型」 | 不变 |
| 「40 个 example」 | **已不成立**：v0.44.2 实测 `examples/*/*.ct` 共 **42** 个（其中 34 个带 `@ct-requires: ct-ast`） | 定量断言过期，判据改用 42 |
| 「461 语料」 | 口径不明；当前 `test/cases/*.ct` 为 **25** | 数字不沿用，S0 重取全量基线 |
| §0.3 探针 `f(void)` | v0.44.2 下 `f(void)` 参数表本身 rc=1（`expected a name`）；改 `load(int n)` 后复现 | 探针拼写失效，结论不变 |
| `phase32-draft.md:423`（T32-1） | `:423`，措辞未变 | 不变 |

**没有一条代码锚点「已经不成立」**（都还在）；失效的是两处外围描述：「40 个 example」计数与 `f(void)`
探针拼写，见上表。S0 开工时仍需重跑一次本表，`baseline:` 记录开工 HEAD。

## 1 目标 / 非目标

### 1.1 目标

| 编号 | 内容 |
| --- | --- |
| O1 | 闭包块体内的 `return` 不再按外层 `ret_type` 判，恢复 §4.53「闭包一律静默」；`--types` 在 **42** 个 example 上不再出现该假阳性（v0.44.2 计数） |
| O2 | 指针基类型 / 层数在初值 / 赋值 / `return` / 容器实参四个位置与调用实参同判据；`void *` ↔ 任意对象指针、裸 `0`、typedef、数组、闭包、函数指针的跳过面不变 |
| O3 | 零回归：正例语料 `--types` 输出除该假阳性消失外逐字不变；全量语料 rc 平价（新增负例除外，计数以 S0 记录为准）；生成 C 与既有 golden 不变 |
| O4 | 错误出口回归约束：默认路径不得以 rc=0 写出 `cc` 拒收的 C，`--types` 判得出的错与默认路径同判据（v0.43.0 已覆盖，本相不重复实现，只守回归，见 §0.3） |

### 1.2 非目标

| 不做 | 理由 |
| --- | --- |
| 闭包返回类型推断 / 闭包独立 `ret_type` | 独立特性；见 phase43 §0.2，本相只按契约跳过 |
| 默认路径全量类型检查 | 策略变更 + 全量 golden 重生成，见 `REQ-TYPE-1` |
| CFG / 数据流所有权分析 | 仓库无 CFG、无 pass 框架，见 `REQ-MEM-1` |
| 跨过程逃逸 / 借用经调用或字段逃逸 | 需写入摘要，见 `REQ-MEM-2` |
| 比较运算符、条件、`switch`、`sizeof`、`_Generic`、宏、struct 字段初值 | 沿用 §4.53 的判定面，不扩写 |
| 改 `build` / `compile` 的严重级或把 `--types` 设为默认 | 策略变更，另案 |
| 改 `void *` 双向转换、裸 `0`、typedef、数组、闭包、fnptr 的跳过面 | 沿用 D32-4 / D32-6 冻结口径 |

## 2 设计决定

| 编号 | 决定 | 为什么不用另一种 |
| --- | --- | --- |
| **D45-1** | S1 用现成的 `ncl_stack == 0` 作为 return 判定的前置条件，不新增字段、不改 `parse_closure` | 新增闭包 `ret_type` 是类型系统相；契约要求的是「不判」，跳过即可 |
| **D45-2** | S2 只替换 `Expr.h.ct:6281` 的短路：`r == 0` 放行，`r == 2` 走 `find_struct`，`r == 1` 且两侧星数相同则报错 | 照抄 `argtype_mismatch`（`:1396-1449`，`r == 2` 在 `:1433-1437`）的既有逻辑，不引入第二个兼容内核 |
| **D45-3** | 诊断编号沿用 `L32-3` / `L32-2` / `L32-1` / `L32-6` 的文案形态，不新造句式 | 本相是同一内核的覆盖面修正，不是新诊断族 |
| **D45-4** | 两个 `check_only/struct_ptr.ct`（209 / 210）从「合法」改判为负例 | 它们的正文正是本相关掉的口子；改判写进夹具清单，不保留「cc 是裁判」的旧口径 |
| **D45-5** | 不动发射与 golden | 本相只改解析期判定与 stderr |

## 3 诊断

| 编号 | 触发 | 文案 | 位置 |
| --- | --- | --- | --- |
| **L45-1** | 同层数、两侧指针、基类型不同（`struct A *` ← `struct B *`、`struct A *` ← `char *`） | `initializer: expected '<T>', got '<U>'` / `assignment:` / `return:` / `argument <n>:` | 表达式起点（实参为实参起点） |
| **L45-2** | 层数不同（`int *` ← `int **`） | 同上，`expected` / `got` 各自带星数 | 同上 |
| — | `void *` ↔ 任意对象指针、裸 `0`、typedef、数组、闭包、fnptr | **不报**（保持既有跳过面） | — |

严重级不变：`ct check` 里为 error（strict=1），`build` / `compile` 不进入这些判定。

## 4 两刀切分（各自可独立验收）

依赖：S0（只读复核）→ **S1** → **S2** → S3 → S4 → S5。两刀不共享代码路径，可分别红/绿、分别回滚；
S1 不做完也可以先做 S2，但门禁必须串行。

**S0（只读核查）**：重跑 §0.4 行号表、确认 `ncl_stack` 用法、四位置现状与 42 个 example 的 `--types`
基线；只出结论，不产提交。`baseline:` 由 S0 现场记录开工 HEAD。

### 4.1 S1 — 闭包 `return` 跳过（2–6 行）

| 项 | 内容 |
| --- | --- |
| **入口条件** | 干净克隆；`export CT_STD_DIR=<repo>/lib/std`；先复跑基线并存 `/tmp/p45-base/`：`ct-ast check --types examples/18_generic_string_table/generic_string_table.ct` 当前 rc=1、两条 `expected 'int', got 'char *'`（`:103` / `:105`）；`examples/*/*.ct` 共 42 个，基线仅该文件失败 |
| **出口证据** | `Stmt.h.ct` 的两处 return 判定（v0.44.2：`:1996-2002`、`:2038-2060`）前置 `self->ex->ncl_stack == 0`；`ncl_stack` 读取自 `Expr.h.ct:422`（压/弹在 `:4722-4726` / `:4748-4749`）；**不改** `parse_closure`（`:4667-4755`）与 `sym->ret_type` |
| **可执行判据** | ① `ct-ast check --types examples/18_generic_string_table/generic_string_table.ct` → rc=0 且输出为空；② 42/42 `examples/*/*.ct` 的 `--types` rc=0（循环脚本，见 E45-1）；③ 漏判负例：外层 `void` + 闭包体 `return err:;`，修复后 `ct-ast compile` rc=1、文案命中 `an error return needs a value`（现 `Stmt.h.ct:1990-1993`），且不写 `.c`；④ 红证按 T-7：父提交贴 rc=1 原文，子提交贴 rc=0 |
| **范围外归属** | 闭包返回类型推断 / 独立 `ret_type` → phase43 §0.2 另案，本刀只按 §4.53 契约跳过；`--types` 默认化 → `REQ-TYPE-1`；指针四位置 → S2；`err:` 出口判定 → v0.43.0 已覆盖，本刀只守回归（E45-5） |

### 4.2 S2 — 指针四位置判据（≈50 行）

| 项 | 内容 |
| --- | --- |
| **入口条件** | S1 收口提交（或经批准的独立基线）；先记录 209/210 的 `check_only/struct_ptr.ct` 现状（`--types` rc=0）与四位置探针；确认 v0.44.2 的 `:6281` 短路与 `argtype_mismatch`（`:1396-1449`）都可直接复用 |
| **出口证据** | 替换 `Expr.h.ct:6281` 的「两侧指针就放行」：`r == 0` 放行、`r == 2` 走 `find_struct`、`r == 1` 且两侧星数相同报 L45-1；跳过面（`void *`、裸 `0`、typedef、数组、闭包、fnptr）逐项保留；`check-ast.sh` 三处硬编码同步（`:3458-3459` 的 `p32_legal` 调用、`:3460-3470` 的 `check_only` 循环、`:3476-3504` 的期望 tsv + `cmp` 与 `test/ast/check_coverage.tsv`） |
| **可执行判据** | ① 四位置负例 4/4 命中 L45-1（初值 / 赋值 / `return` / 容器实参）；② 层数负例 1/1 命中 L45-2；③ `struct User *u; struct Admin *a; u = a;` 在 `check` / `check --types` / `compile` 三入口 rc=1（v0.44.2 实测当前三入口均 rc=0）；④ `check-ast.sh 2>&1 \| tail -1` = `0 failed`；⑤ `check-warnings.sh` = `0 failed`；⑥ E45-5 三条出口探针仍 rc=1 且不写 `.c`；⑦ 生成 C 与 golden 不变（收口前后快照 `cmp`） |
| **范围外归属** | §4.53 / D32-6 的**规范措辞**（现 `language-spec.md:2424` 写「任意两指针不比较基类型」）→ S4 更新，本刀不动规范；跨过程 / 默认路径全量检查 → `REQ-TYPE-1`；严重级调整 → 另案；闭包 → S1 |

### 4.3 收口切片（两刀之后）

| 切片 | 内容 | 边界 |
| --- | --- | --- |
| **S3** | 正负例补齐：新增 `check_errors/` 四位置负例 + 层数负例；209 / 210 的 `check_only/struct_ptr.ct` 改判（D45-4） | 只含夹具 |
| **S4** | 文档：§4.53 指针与闭包措辞（含 `:2424` 的 D32-6 句）、`tutorial.md` / `glossary.md` 对应句、README「明确不做」如需 | 与实现同收口 |
| **S5** | 门禁与收口：夹具注册、`check-warnings` 零告警、`check-docs` 绿、`check-all` 11 道全绿、bump `0.45.0` | 收口 |

每片 ≤150 行、≤3 文件，仓库随时可构建。

## 5 完成定义（四件套）

| 面 | 交付 | 缺一不算完成 |
| --- | --- | --- |
| 实现 | S1 闭包跳过 + S2 指针四位置判据；无 TODO、无「暂不支持」分支 | ✓ |
| 诊断 | L45-1 / L45-2 在四个位置各自命中；文案与位置精确；跳过面逐项列在夹具里 | ✓ |
| 文档 | §4.53 措辞（指针改为「比较基类型与层数」，闭包注明按契约静默；含 `language-spec.md:2424` 的 D32-6 句）、`tutorial.md` / `glossary.md` 对应句 | ✓ |
| 门禁 | 负例进 `check-ast.sh`；正例语料 `--types` 平价；`check-all` 11 道全绿；红证按 T-7 提交 | ✓ |

**硬约束**：本相**不得因本相放宽既有 golden**，也不得以「改 golden 让新判据变绿」的方式收口；任何
golden 变化必须是重生成后的逐字节核对结果，且提交正文写明原因。

## 6 验收

| ID | 断言 | 命令 / 阈值 |
| --- | --- | --- |
| **E45-1** | 闭包契约恢复：`examples/18_generic_string_table` 的 `--types` rc=0；42 个 example `--types` 全绿 | 逐文件跑 `ct check --types`，42/42（v0.44.2 计数） |
| **E45-2** | 四位置负例全报 L45-1：初值 / 赋值 / `return` / 容器实参 | 4/4，stderr 逐字匹配 |
| **E45-3** | 层数负例报 L45-2；`void *` / 裸 `0` / typedef / 数组 / 闭包 / fnptr 仍静默 | 正负例各一组 |
| **E45-4** | 零回归：全量语料 rc 平价（新增负例除外，基线计数由 S0 记录）；`check-warnings` 零告警；生成 C 与 golden 不变 | `rc_diff=0`、`check-all` 绿 |
| **E45-5** | 出口回归：`return err:` 载荷与返回类型不符时，`ct compile` / `ct check` / `ct check --types` 均 rc=1、同文案，且不写 `.c`（S2 后复跑 §0.3 探针） | 两条最小用例 × 三入口 |

## 7 风险与不做项

| 编号 | 风险 / 不做项 | 触发信号 / 处置 |
| --- | --- | --- |
| R45-1 | 覆盖率矩阵硬编码在 `check-ast.sh` 三处（`:3458-3459` 调用、`:3460-3470` 循环、`:3476-3504` 期望 tsv + `cmp`），加行易漏 | S2 同步三处并逐字节比对 |
| R45-2 | 两个 `check_only/struct_ptr.ct` 改判会让既有「合法形态」清单变短 | S3 显式改判并把新负例放进 `check_errors/` |
| R45-3 | 误把闭包假阳性当成 S2 的回归 | 先做 S1，矩阵基线在闭包干净后再建 |
| R45-4 | 与 PH-46 的门禁并发 | 两相串行跑 `check-all.sh`；代码可并行开发 |
| R45-5 | 指针判据回退的口子被重新打开 | 夹具锁死四位置负例；`--types` 之外不改严重级 |

### 4.4 收口记录（2026-11-15）

| 切片 | 验收 | 结果 |
| --- | --- | --- |
| S1 | 闭包 return 跳过 | `examples/18` `--types` rc=0；42/42 examples 绿 |
| S2 | 指针四位置判据 | `p45/contract` 6/6；初值/赋值/return/容器/层数负例全报 |
| S3 | 209/210 `struct_ptr` 改判 | 两个旧 skip 夹具删除，负例进 p45 |
| S4 | 文档 | spec §4.53/§4.61/§4.63、tutorial §10.19 |
| S5 | 门禁 | check-ast 1376/0、test/run 156、warnings 632/0、docs 1217/243 |

tag/push：`v0.45.0` annotated tag 与分支自动 push。
