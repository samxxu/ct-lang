# Phase 49 — `own` 所有权转移（初始化式接工厂返回值）

> **状态：完成（2026-11-15；v0.49.0；S1–S5 全绿）**
> **归属**：本仓库维护规格与判据；实现由外部 harness 交付（[手册](phase46-52-handoff.md)）。
> **基线**：本卡最后一次提交；起点为 PH-48 收口提交（AutoDrop 与 Drop 体同一出口）。
> **规模**：200–380 行。
> **版本**：`v0.49.0`（若采纳 U-4 A）。

## 0 一句话目标

让 `own struct P *p = make();` 可编译并按既有 AutoDrop 释放，同时把「返回位置 `own`」的拒绝文案改成可操作。

## 1 本卡做 / 本卡不做

| 做 | 不做 |
| --- | --- |
| 初始化式放行「返回 `struct X *` 的函数调用」（`N_CALL` 形态） | 不支持返回类型位置 `own`（语义维持拒绝，只改文案） |
| 零值（`0`）不计账，块尾不释放 | 不做借用检查 / 生命周期 |
| 可静态判定的重复 `own` 硬错 L49-2 | 不接受任意指针表达式（`&x`、`arr+1`） |
| 与 `?` / `defer` / `errdefer` 的清理顺序不变 | 不改 AutoDrop 记账顺序 |

**前置（冻结）**：`struct P` 必须有 `impl Drop`；没有则 `own` 仍硬错（沿用现状），卡内夹具必须显式带上。

## 2 前置依赖

PH-48 收口（跨单元 Drop 真实体）。48 未收口时，本卡只交付单单元夹具并在交付报告注明。

## 3 现状（实测）

```text
g2_own_return.ct:15:1: error: 'own' requires a malloc or calloc initialiser
g6_own_in_sig.ct:7:1: error: 'own' is only allowed inside a function body
```

复现：

```sh
mkdir -p /tmp/p49 && cd /tmp/p49
"$work/ct-ast" g2.ct -o g2.c ; echo "g2=$?"     # 1
"$work/ct-ast" g6.ct -o g6.c ; echo "g6=$?"     # 1
```

锚点：`own` 判定在 `selfhost/ct-ast/frontend/sema/Memory.h.ct:45-52`；符号表返回类型
`Symbols.h.ct:782-805`；AutoDrop 的 `if (p)` 守卫 `Emitter.h.ct:3799-3815`。

## 4 修法方向（四条字面规则，不新增类型器）

| # | 规则 |
| --- | --- |
| **D49-1a** | 接受形态只有两种：`malloc(...)` / `calloc(...)` 调用；`N_CALL` 且被调符号的返回类型字面量为 `struct X *` |
| **D49-1b** | 判定只看 `N_CALL` 的 callee `Symbols` 记录与返回类型字符串，不引入表达式类型推导 |
| **D49-1c** | 其余指针表达式（`&x`、字段取址、算术）→ L49-1 |
| **D49-1d** | 零值初始化不记账；AutoDrop 已有 `if (p)` 守卫，复用不改 |

| 点 | 位置 | 改法 |
| --- | --- | --- |
| 判定 | `Memory.h.ct:45-52` | 增加 `N_CALL` 分支，按 `Symbols.h.ct:782-805` 的返回类型判定 |
| 文案 | 同处 | L49-1 / L49-3 |
| 重复绑定 | 同处 | 同作用域两个 `own` 绑定同一标识符 → L49-2 |

## 5 任务切分

| 切片 | 内容 | 出口 |
| --- | --- | --- |
| S0 | 核对 `Memory` 判定点、`Symbols` 返回类型表示、AutoDrop 路径；产出「为什么不能只靠 `cc`」一句 | 无提交 |
| S1 | 红证：工厂返回值（rc=1）+ 重复绑定（rc=1） | `test: PH-49 红` |
| S2 | `N_CALL` 判定 + L49-1 | ≤2 文件 |
| S3 | L49-2 + L49-3 文案 | ≤2 文件 |
| S4 | 文档：`own` 一节与失败语义 | 或 `blocked-by` |
| S5 | 收口 | §6 |

## 6 验收判据

| ID | 命令 / 比对 | 通过条件 | 失败条件 |
| --- | --- | --- | --- |
| E49-1 | `p49_own_factory`：分配计数 1、Drop 计数 1，运行 stdout `cmp` | 计数相等且 `cmp` rc=0 | 任一不等 |
| E49-2 | `p49_own_null`：工厂返回 0，Drop 计数 0，生成 C 含 `if (p)` 守卫 | 计数 0 且守卫存在 | 释放 0 或守卫消失 |
| E49-3 | `p49_errors.sh`：`own int *p = &x;` rc=1、文案 L49-1、不落 `.c` | 逐字命中 | 放行或落 `.c` |
| E49-4 | 返回位置 `own` rc=1、文案 L49-3 | 逐字命中 | 旧文案或放行 |
| E49-5 | 既有 `own p = malloc(...)` 夹具快照 `/tmp` `cmp` | rc=0 | 任一 diff |
| E49-6 | `p49_own_try`：`own` + `?` + `errdefer` 三行输出 `cmp`（顺序锁定 PH-40） | `cmp` rc=0 | 顺序变化 |
| E49-7 | `bash selfhost/check-all.sh` | 11 green | 任一失败 |

## 7 范围外归属

| 项 | 归属 |
| --- | --- |
| 返回类型 `own` / 所有权注解 | 不做（D49-3） |
| 借用检查 | REQ-MEM-2 |
| 容器的 `release` | PH-50 |
| 跨单元 Drop 体 | PH-48 |

## 8 风险与回滚

| 风险 | 信号 | 回滚 |
| --- | --- | --- |
| 放行后双释放（两个 `own` 指向同一指针） | ASAN double-free | 回滚 S2；只保留可判定形态的 L49-2 |
| `?` 提前返回清理链错序 | E49-6 输出 diff | 回滚 S3；顺序以 PH-40 冻结为准 |
| 把「返回位置 own」顺手放开 | 评审提出 | 明确属非目标；回滚任何相关改动 |
| golden 漂移 | `check-goldens` 红 | 逐字节核对后重生成；否则回滚 |

### 9 收口记录（2026-11-15）

| 项 | 结果 |
| --- | --- |
| E49-1 | 单单元/跨单元工厂返回值：allocs=1 drops=1，Drop 体执行 |
| E49-2 | 零初始化不记账、不释放；生成 C 保留 `if (p)` 守卫 |
| E49-3 | `&x` 等指针表达式 L49-1，不落 `.c` |
| E49-4 | 返回位置 `own` 保持拒绝，L49-3 新文案 |
| E49-5 | 34 个既有 `own` 夹具产物逐字节一致 |
| E49-6 | `own` + `?` + errdefer 顺序不变 |
| E49-7 | check-all 11/11；check-ast 1394/0、warnings 656/0 |

tag/push：`v0.49.0` annotated tag 与分支自动 push。
