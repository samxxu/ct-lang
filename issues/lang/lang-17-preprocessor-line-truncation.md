# LANG-17 · 超长预处理行被静默截断（`#define` / `#include` 超过 159 字节）

| 项 | 值 |
| --- | --- |
| 模块 | lang（词法 / 预处理行透传） |
| 定性 | **实现缺陷**（静默改行为：编译通过，产物与源码不一致） |
| 严重度 | **High** |
| 优先级 | **P0** —— 截断点落在合法边界时 `ct`、`cc`、运行全部 rc=0，宏语义已被改掉 |
| 状态 | **open**（由 `docs/proposals/ct-build-frontend-defects.md` 的 DF-1 转入台账；58 后重排第 0 批） |
| 锚点 | 提案基线 `v0.44.1`（`13db6cad`）；代码注释在 HEAD 仍自认该限制 |
| 文件 | [Expr.h.ct](../../selfhost/ct-ast/frontend/parse/Expr.h.ct)（`:806` 注释）、[Stmt.h.ct](../../selfhost/ct-ast/frontend/parse/Stmt.h.ct)（`:402` 注释） |

## 现象

以 `#` 开头的预处理行超过 159 字节时，`ct` 正常退出，但生成的 C 里该行被截短。截断点落在
合法边界时，`cc` 不报错，宏的返回值已被改掉；落在字符串中间时，`cc` 才报语法错，且位置指向
截断处，不提示「前端截断了它」。

## 最小复现

见 [ct-build-frontend-defects.md §1](../../docs/proposals/ct-build-frontend-defects.md)：510 字节的
`#define is_kw(x) …` 在生成物里只剩 159 字节；162 字节且 `* 2` 落在 160 之后的版本则
`ct` / `cc` / 运行全部 rc=0，返回值从 6 变成 3。

## 期望行为

- 超长预处理行**原样透传**，或在不透传时给出硬错并指名字节上限；不得静默截断。
- 错误文案给出行号与上限；落半份 `.c` 的行为与 SH-79 一致处理。

## 交叉引用

- [DF-1](../../docs/proposals/ct-build-frontend-defects.md)（原始修复单）
- [G-8](../../docs/proposals/language-capability-gaps.md)（能力缺口总账；该册基线已过期，仅作背景）
- [post-58-plan.md](../../docs/planning/post-58-plan.md) §4 第 0 批

## 修复排期

58 后第 0 批（静默错误）。与 LANG-16 / LANG-8 同属词法族，**串行**发版；修复须带
「510 字节透传」与「162 字节合法边界」两条夹具。

## 处置（2026-11-19，PH-72）

- 提交：`2a4c632f`
- 改动：超长 `#` 行记 `toktrunc` 并在 Parser 硬错
- 验证：`sh test/ast/p72_diagpos.sh <ct-ast>` → `preprocessor line exceeds 159 bytes`
