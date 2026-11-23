# TEST-25 · 覆盖率报告与 ct-ast 白盒单测缺口

| 项 | 值 |
| --- | --- |
| 模块 | testing |
| 定性 | 能力缺口（P2，非 v1-PH-0 门禁） |
| 严重度 | Low |
| 锚点 | v0.88.0（2026-11-21） |
| 依据 | [v0.88.0 评审](../../docs/reviews/full-review-v0.88.0.md) §2、P2-10 |
| 状态 | deferred |
| 处置证据 | **deferred**（v1.1 起；触发：nightly 覆盖率 job 或 v1.1 立项窗口；owner DEV + VERIFY） |

## 现象

1. **没有行/分支覆盖率**：行为/golden 覆盖很广，但无法回答 45k 行里哪些没跑到；
2. **ct-ast 无白盒单测**：Lexer/Parser/TypeCheck/Emitter 只经端到端；切片重写后
   `em_*` / `ctype_*` / `tc_expr_*` 的单函数行为没有白盒钉住；
3. 容量上限只覆盖 `MAX_CALLS`；`MAX_FUNCS` 501/512、`io_names[1024]`、
   `MAX_PARAMS`/`MAX_CLOSURES` 缺边界夹具（`MAX_FUNCS` 已并入
   [SH-109](../../issues/selfhost/sh109-max-funcs-capacity.md)）。

## 期望

| 项 | 做法 | 验收 |
| --- | --- | --- |
| 覆盖率 | nightly 跑 `llvm-cov`/`gcov`，**只报告、不设阈值** | 报告可下载；趋势可见 |
| ct-ast 单测 | 先选 `em_*` / `ctype_*` / `tc_expr_*` 各 1–2 个纯函数试点 | 有最小白盒夹具；不改端到端门禁 |
| 容量夹具 | `io_names` 临界 + 越界两条；`MAX_PARAMS`/`MAX_CLOSURES` 评估 | 至少补 `io_names`；其余列后续 |

## 非目标

- 不把覆盖率设成硬门禁（避免为数字写测试）；
- 不重写现有端到端门禁；
- 不阻塞 v1-PH-0 / v1.0 发布。

## 关联

- [v1-readiness-1 判决](../../battle/v1-readiness-1/verdict.md)（P2，非门禁）
- [SH-109](../../issues/selfhost/sh109-max-funcs-capacity.md)（MAX_FUNCS 容量）
- [check-all](../../selfhost/check-all.sh)

## 处置（2026-11-22，REV/REQ）

**结论：`deferred`（v1.1 起；不阻塞 v1.0 / `v1-PH-0`，与本条「非目标」一致）。**
三项里没有一项能在离线单机自证为已完成：覆盖率报告要 nightly runner 扩一个 job，
ct-ast 白盒单测要先定「CT 源码怎么被单测」的形态（L0 的做法不能直接照搬），
`io_names` 夹具则是小改动但需与容量门禁段同批落地。挂在 `open` 会让台账读成
「本轮就能做」，因此按 §5.4 记 `deferred` 并写死触发条件与 owner。

现状核对（2026-11-22，离线可复核）：

| 项 | 现状 | 证据 |
| --- | --- | --- |
| 行/分支覆盖率 | **仍无**：nightly 只有 `sanitizers` 与 `fuzz` 两个 job | `grep -n 'llvm-cov\|gcov' .github/workflows/nightly.yml` → 0 命中（rc=1） |
| 白盒单测 | **L0 已有、ct-ast 没有**：`test/unit/test_helpers.c` 用 `#include ../../selfhost/l0/ctc.c` 触达 `static` 纯函数，由 `test/run.sh` 的 `unit` 段执行；ct-ast 是 CT 源码，`em_*` / `ctype_*` / `tc_expr_*` 仍只经端到端 | `cc -Wall -Wextra -std=c99 test/unit/test_helpers.c -o /tmp/unit && /tmp/unit` → `unit: 112 checks, 0 failed`；`test/run.sh` unit 段 |
| 容量夹具 | **大部分已覆盖**：9 条 `cap_check` 夹具——params(16) / methods / funcs(512，含 512 边界) / scopes / vars / fields / structs / closures(64) / closure_nest(16)；**`io_names[1024]` 仍缺临界 + 越界两条**，且越界文案 `too many distinct calls` 不带上限值与单元名 | `selfhost/check-ast.sh` 的 `capacity limits (generated)` 段；`selfhost/ct-ast/frontend/parse/Expr.h.ct:1284` |

```console
$ cc -Wall -Wextra -std=c99 test/unit/test_helpers.c -o /tmp/unit && /tmp/unit
unit: 112 checks, 0 failed
$ grep -n 'llvm-cov\|gcov' .github/workflows/nightly.yml ; echo rc=$?
rc=1
$ grep -c 'cap_check' selfhost/check-ast.sh
10                                        # 9 条夹具 + 1 处函数定义
```

为什么不是 `rejected`：覆盖率报告只是「nightly 多一个 job + 产物下载」，成本明确、不设阈值
就不会诱发「为数字写测试」；`io_names` 夹具是纯测试改动。两者都属于**排期**问题，不是取舍问题。
为什么不是 `verified`：L0 的 112 条白盒断言只覆盖 `ctc.c`，对 ct-ast 的单函数行为零覆盖；
覆盖率仍无法回答「45k 行里哪些没跑到」。

- owner：DEV（nightly 覆盖率 job、`io_names` 夹具）+ VERIFY（白盒试点选型与红证）。
- 触发条件：**v1.1 立项窗口**（或 v0-PH-88 之后第一个非冻结 MINOR，先到先用）——
  ① nightly 增加 `llvm-cov`/`gcov` **只报告不设阈值**的 job，报告可下载；
  ② `em_*` / `ctype_*` / `tc_expr_*` 各选 1–2 个纯函数做最小白盒夹具（不改端到端门禁）；
  ③ 补 `io_names` 临界 + 越界两条夹具（上限 1024 个不同被调名，越界须报错并补上限文案；
  具体可达形态——声明函数或裸名——由 DEV 在夹具里定，本条只钉「临界放行 / 越界报错」）。
- 若 v1.1 前有人先落 ③，本条只保留覆盖率与白盒半边，不重复立案；
  `MAX_FUNCS` 512 边界已由 [SH-109](../../issues/selfhost/sh109-max-funcs-capacity.md) 覆盖，不再计入本条。
