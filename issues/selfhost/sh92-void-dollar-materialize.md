---
id: SH-92
title: "void 方法跳后 `$x` 未在 ct 内拒绝，直到宿主 cc 才报错"
status: open
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
