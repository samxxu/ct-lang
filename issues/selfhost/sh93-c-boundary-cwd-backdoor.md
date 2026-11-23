---
id: SH-93
title: "c-boundary 的 cwd 后门：从 CT 仓根看外部输入也被 allow"
status: verified
area: selfhost
severity: P2
opened: 2026-11-20
confirmed-by: REQ-review-v077-1
---

# SH-93 · c-boundary cwd 后门

## 来源

[full-review-v0.77.0](../../docs/reviews/full-review-v0.77.0.md) §6 风险 4；battle [review-v077-1](../../battle/review-v077-1/verdict.md)。

## 现象

`c_boundary_for` 在 `c_cwd_in_tree()` 为真时对所有输入返回 allow（[Module.h.ct:392](../../selfhost/ct-ast/frontend/module/Module.h.ct#L392)、[:2427](../../selfhost/ct-ast/frontend/module/Module.h.ct#L2427)）。同一 `/tmp/p65x.ct` 从 `/tmp` 看是 strict，从 CT 仓根看是 allow；spec §4.66 只写四个仓内路径豁免，未写 cwd 规则。

## 期望

- 收紧到 `c_path_is_core`（只看输入路径，不看 cwd）；或
- 若 cwd 规则是有意的，写进 spec §4.66 并补负例；
- 不得让“在仓根运行”静默放宽外部输入的 C 边界。

## 验收

- 仓根 + `/tmp` 外部输入：`--show-c-boundary` 为 strict（或文档化 allow 并签字）；
- 仓内四路径豁免不回归；
- 负例进入 `test/ast/p65_*`。

## 范围

P2；可与 v0-PH-65 C 边界修复同批。

## 处置（2026-11-20，DEV）

**结论：fixed（待 REV 复核）。** 红证提交 `fd509b06`，实现提交 `1be81be9`，
探针适配提交 `4553ec15`。

已核实：`c_boundary_for` 先看 `c_cwd_in_tree()`，为真则全量 allow；同一个
`/tmp/…/x.ct` 从 CT 仓根看是 `allow`，从 `/tmp` 看是 `strict`。依据
`docs/language-spec.md` §4.66：默认只有 `selfhost/**`、`lib/std/**`、
`test/**`、`examples/**` 四个目录豁免，没有 cwd 规则。

改法：删除 `c_cwd_in_tree()` 及其调用；策略只由输入路径（外加 CLI 与包
manifest）决定。负例：`test/ast/p65_policy.sh` 增加“仓根 cwd + 仓外 `.ct`
→ strict”。

验证（实现后，本轮重建的 ct-ast）：

```console
$ env -u CT_C_BOUNDARY bash test/ast/p65_policy.sh /tmp/ci9-sh93-build/ct-ast
OK p65/policy
$ env -u CT_C_BOUNDARY bash test/ast/p65_regression.sh /tmp/ci9-sh93-build/ct-ast
OK p65/regression (1299 grandfathered .ct sources)
$ env -u CT_C_BOUNDARY bash test/ast/p65_include.sh /tmp/ci9-sh93-build/ct-ast
OK p65/include
$ env -u CT_C_BOUNDARY bash test/ast/p65_raw_extern.sh /tmp/ci9-sh93-build/ct-ast
OK p65/raw-extern
$ env -u CT_C_BOUNDARY bash test/ast/p65_map.sh /tmp/ci9-sh93-build/ct-ast
OK p65/map
$ env -u CT_C_BOUNDARY bash test/ast/p66_io_empty.sh /tmp/ci9-sh93-build/ct-ast
OK p66/io-empty
$ env -u CT_C_BOUNDARY bash test/ast/p66_io_boundary.sh /tmp/ci9-sh93-build/ct-ast
OK p66/io-boundary
```

既有 strict/豁免用例全部保留并通过（上列均 `env -u CT_C_BOUNDARY`）。

附带：12 支早于 v0-PH-65 的探针（p44_try_drop、p46/p47/p48、p64_alloc/
const_vtable/no_init_array/on_demand、p71_drop/own、p72_outputcollision/
subscript）fixture 自由 `#include`，以前靠 cwd 后门单独运行也会得到 allow；
现改为显式 `export CT_C_BOUNDARY=allow`（它们不是边界探针），提交
`4553ec15`。12/12 单独运行 rc=0。

整门禁：`bash selfhost/check-all.sh` → `check-all: OK (11 hard gates green)`，
`check-ast` 1519 passed / 0 failed / 4 skipped（本会话 2026-11-20）。

## 复核（2026-11-20，REV）

**结论：verified。** 独立自举（`ct-ast v0.77.1`）后运行：

```console
$ cd /tmp/rev-v0771 && env -u CT_C_BOUNDARY bash test/ast/p65_policy.sh /tmp/rev-v0771-build/ct-ast
OK p65/policy
$ echo $?
0
```

探针含仓根 cwd 负例：`check "external from repo root" strict ...`。红/绿对照：v0.77.0
基线二进制配同一探针 → `FAIL p65/policy: external from repo root: want 'strict', got
'allow' ()`（rc=1）；v0.77.1 通过。`grep -rn c_cwd_in_tree selfhost/ct-ast` 0 命中；
四目录豁免未回归：`p65_regression`（1299 源）、`p65_include`、`p65_raw_extern`、
`p65_map`、`p66_io_empty`、`p66_io_boundary` 全 `OK`。红证 `fd509b06` 是 `1be81be9`
父提交，适配提交 `4553ec15` 可达。
