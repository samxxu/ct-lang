# Phase 66 — libc I/O 内置例外（按调用补头）

> **状态：实施中**（2026-11-18 立项；卡已冻结；R1 待做）。
> **依据**：[D-008](../decisions/D-008.md)（accepted，2026-11-17）、[SH-89](../../issues/selfhost/sh89-libc-io-auto-include.md)。
> **前置**：PH-65 收口（`v0.64.0`）。
> **纪律**：不收口不 bump；tag/push 按 6.7 V-7 / 6.5。

## 0 卡片字段（冻结）

| 项 | 值 |
| --- | --- |
| 编号 | PH-66 |
| 目标 | `printf` 族按**直接调用**补 `<stdio.h>`，宽字符组补 `<wchar.h>`；没有调用就不带系统头；strict 下这是显式 libc 例外 |
| 范围 | D-008 §1/§2/§4 的闭集与边界；不做 §3 的 POSIX 集、不做格式串检查、不改 `--freestanding` 承诺 |
| 交付物 | `backend/emit/Emitter.h.ct`（补头与层 prologue）、`frontend/module/Module.h.ct`（调用扫描与去重）、`test/ast/**`、`docs/**`、golden |
| 任务清单 | §4（R1–R5，共 5 项） |
| 退出判据 | E66-1…E66-6（§5） |
| 依赖 | D-008；PH-65 `v0.64.0`；规范 1.15.0 |
| version-minor | 65（PH-66，`d=1`，见 AGENTS §0.3） |
| 已知风险 | R66-1…R66-5（§7） |

## 1 需求与边界

### 1.1 一句话

生成物只带它**用得到**的系统头：直接调用了 `printf`/`fprintf`/`sprintf`/`snprintf`/
`scanf`/`fscanf`/`sscanf`/`puts`/`putchar`/`fputs`/`fputc`/`fflush`/`perror` 才补
`<stdio.h>`；宽字符组补 `<wchar.h>`；其余（`syslog`、`open`、`fcntl`…）不补。

### 1.2 非目标

- 不做 POSIX/GNU 集（`dprintf`、`asprintf`）与 §3 的"不自动补头"清单；
- 不做格式串与实参类型检查；
- 不改 `--freestanding`：该模式下不自动补头，未由 shim 提供则硬错；
- 不把本相塞进 PH-65 的冻结卡面（D-008 已裁定另行实施）。

### 1.3 关键决策

| 编号 | 决策 | 理由 |
| --- | --- | --- |
| D66-1 | 触发条件是**直接调用**：仅取地址/函数指针不触发 | D-008 §4 |
| D66-2 | 用户已定义同名函数/宏时不抢，按用户声明处理 | 同上 |
| D66-3 | 每个头只补一次，位置在 banner 后、内置层 prologue 前 | 同上 |
| D66-4 | 先让"未调用不带 stdio"成立，再补头 | D-008 的差距说明：否则只是换理由 |
| D66-5 | 内置层自身的 `printf` 走同一检测 | 收掉无条件 include 后层要能编 |

## 2 现状（S0 基线）

- `v0.64.0`：`check-ast` 1472 passed；空程序生成物带 `<stdio.h>/<stdlib.h>/<string.h>`；
- 来源：内置层头文件的 `#include` 被逐字带进 `.c`（`emit_map_prologues` 与层 splice），
  不是调用检测；
- strict 已在 PH-65 落地：`.ct/.h.ct` 不得直接 `#include`，所以"用户自己 include stdio"
  在外部代码里不可用——这正是本相要补的洞。

## 3 语义与落码

- 闭集表（名字 → 头）放 `Module`（或发射器）内的静态函数，**不含**前缀匹配；
- 检测面：build 模式逐单元 AST 的 `N_CALL`（`cur_unit` 内），compile 模式同；
- 去重：每个头一次；顺序固定 `stdio` → `wchar`；
- 层自身：层单元按同一张表检测，不特殊对待；
- 不抢：符号表里已有用户定义的同名函数时不补头；
- `--freestanding`：跳过补头；调用未由 shim 提供 → 现有"未声明函数"诊断即可。

## 4 任务清单

| 任务 | 交付物（路径） | 验收命令 | effort | 回滚 |
| --- | --- | --- | --- | --- |
| R1 | 闭集表 + 调用检测（`Module.h.ct`） | `p66/io-detect`：直接调用命中、取地址不命中、未调用不命中 | M | revert |
| R2 | 补头发射（`Emitter.h.ct`：banner 后、层前，去重） | `p66/io-emit`：`printf` 产物含一次 `<stdio.h>` | M | revert |
| R3 | 收掉无条件 include，保持层自编 | `p66/io-empty`：空程序零系统头；`check-ast` 全绿 | M | revert |
| R4 | 边界负例（同名不抢、freestanding、`syslog` 不补） | `p66/io-boundary`：四条边界 | M | revert |
| R5 | 文档 + golden | `p66/io-docs`；`check-docs.py`；banner golden 随版本 | S | revert |

映射：R1→E66-1；R2→E66-2；R3→E66-3；R4→E66-4；R5→E66-5；E66-6 为总门禁。每项至多覆盖 1 条判据（T-5）。

## 5 退出判据

| ID | 断言 | 命令与阈值 | 夹具 |
| --- | --- | --- | --- |
| E66-1 | 直接调用命中、取地址不命中 | `ok p66/io-detect`，2/2 | `test/ast/p66_*` |
| E66-2 | 按需补头且每个头一次 | `ok p66/io-emit`，2/2 | 同上 |
| E66-3 | 空程序零系统头 | `ok p66/io-empty`，1/1 | 同上 |
| E66-4 | 同名不抢 / `syslog` 不补 / freestanding 硬错 | `ok p66/io-boundary`，3/3 | 同上 |
| E66-5 | 文档与版本落点 | `ok p66/io-docs`；`check-docs.py` rc=0 | `docs/**` |
| E66-6 | 全量门禁 | `check-all` 11/11；`check-ast` 全绿 | 全量 |

## 6 负例台账

| 编号 | 触发 | 文案要点 |
| --- | --- | --- |
| L66-1 | `--freestanding` 下调用 `printf` 且无 shim | 复用未声明函数诊断（不新增文案） |

## 7 风险与开放项

| 编号 | 风险 | 处置 |
| --- | --- | --- |
| R66-1 | 收掉无条件 include 后内置层自己编不过 | 层按同一检测补头；R3 出口含层自编 |
| R66-2 | golden 变化面大（banner + 头行） | 只重生成 `test/cases/**` 与 p39 ABI 头，逐文件确认只多/少 include 行 |
| R66-3 | 用户同名函数/宏抢头 | R4 负例；按用户声明处理 |
| R66-4 | 取地址被误判成调用 | AST 只认 `N_CALL`，不认 `N_VAR/ID` 取址 |
| R66-5 | `--check`/`--emit-map` 也走检测导致行为分支 | 检测放在发射前，与输出模式无关 |

## 8 估算与收口

- 编译器 120–220；夹具 80–140；文档 30–50；合计 230–410（±40%）。
- 收口：E66-1…6 全绿、11 道门禁、五处 `CTC_VERSION` 到 `v0.65.0`、流水账/对照表；
  tag 与分支推送按 6.7 V-7 / 6.5。
