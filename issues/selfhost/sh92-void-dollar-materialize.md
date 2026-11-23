---
id: SH-92
title: "void 方法跳后 `$x` 未在 ct 内拒绝，直到宿主 cc 才报错"
status: verified
area: selfhost
severity: P2
opened: 2026-11-19
confirmed-by: REV-PH-76
---

# SH-92 void 方法跳后 `$x` 未在 ct 内拒绝

## 复现

```ct
trait V { void v(void); }
struct S { int n; } use V;
impl V for S { void v(void) { } }
int main(void) { struct S s = {}; int x; s.v()$x; return 0; }
```

`ct check --types void.ct` 返回 0；`ct build` 生成 `x = s.__m_vptr->m(&s);`，宿主 cc
报 void 赋值错误（v0.76.0，`247ade5b`）。

## 期望

`$` 处硬错：该跳没有可赋值结果（E76-3）。

## 原因

`static_ctype` 对 void 返回 0，`$` 分支只在其返回非 0 时做类型检查，于是 void 被跳过。

## 处置

- 提交：见 `git log --grep "SH-92"`（实现 `$` 分支对 `static_ctype` 返回 0/空类型显式拒绝）
- 验证：`sh test/ast/p76_chain.sh <ct-ast>` → `OK p76/chain ...`（含 void 负例）

## 复核（REV，2026-11-19）

| 项 | 值 |
| --- | --- |
| 复核人 | REV / rev-ph76 |
| 修复 | `d16d6ffa`（fix，v0.76.1）；红证 `b2aefc6b`（父提交；baseline `247ade5b`，v0.76.0） |
| tag | `v0.76.1`（peeled `d16d6ffa`；本地对象/远端一致） |
| 结论 | `verified` |

独立复现：从 `git archive v0.76.1` 的 clean 副本（`/tmp/rev-ph76-1`）重新自举
L0→L1→L2→ct-ast（`ct-ast v0.76.1`，零警告），再跑探针与负例：

```console
$ sh test/ast/p76_chain.sh /tmp/rev-ph76-1-work/ct-ast; echo $?
OK p76/chain (tail, multi-hop, type/const/non-call/argument negatives)
0
$ /tmp/rev-ph76-1-work/ct-ast check --types void.ct; echo rc=$?
void.ct:4:47: error: '$' needs a non-void result; this hop has none (v0-PH-76)
ctc: 1 error(s) generated
rc=1
$ /tmp/rev-ph76-1-work/ct-ast check void.ct; echo rc=$?
void.ct:4:47: error: '$' needs a non-void result; this hop has none (v0-PH-76)
ctc: 1 error(s) generated
rc=1
$ /tmp/rev-ph76-1-work/ct-ast build -o void.bin void.ct; echo rc=$?
void.ct:4:47: error: '$' needs a non-void result; this hop has none (v0-PH-76)
ctc: 1 error(s) generated
rc=1
```

红证：把 `b2aefc6b` 的 `p76_chain.sh` 放到 `247ade5b`（v0.76.0）的归档副本上，用其
`ct-ast v0.76.0` 复跑：

```console
$ sh test/ast/p76_chain.sh /tmp/rev-ph76-work/ct-ast; echo $?
FAIL p76/chain: void-returning hop accepted
1
```

回归：接口接收者 `iface.m()$x`、指针接收者 `p->m()$x`、多跳带实参
`s.m()$x.n(2)$y` 均仍 rc=0 且运行正确；类型不符仍报
`'$' target: expected 'int', got 'struct B'`。修复点在
`selfhost/ct-ast/frontend/parse/Expr.h.ct:4366-4377`（`static_ctype` 返回 0/空类型时显式拒绝），
与 `test/ast/p76_chain.sh` 的 void 负例一致。逐条对照见
[v0-PH-76 复核补正](../../docs/reviews/2026-11-19-phase76-rev-verdict.md) §10。
