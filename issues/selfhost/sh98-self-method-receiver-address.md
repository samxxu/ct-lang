---
id: SH-98
title: "`self.bump(self)` 的 receiver 仍发射 `&_self`（S**）"
status: open
area: selfhost
severity: P1
opened: 2026-11-20
confirmed-by: CI-44689834317
---

# SH-98 self 作方法 receiver 仍被取址

## 现象

`impl S { void bump(ref S s) ... void go(void) { self.bump(self); } }` 在
v0.79.0 发射 `S_bump(&_self, _self)`；receiver 位是 `struct S **`，gcc 告警
`incompatible pointer types passing 'struct S **' to parameter of type 'struct S *'`，
CI `ubuntu-gcc` 的 `p78/method` 因此变红（macOS clang 仅告警、运行碰巧通过）。

## 期望

receiver 与 ref 实参都发 `_self`：`S_bump(_self, _self)`，`ct build` 无告警、运行正确。

## 处置

- 提交：见 `git log --grep "SH-98"`（`emit_expr` 的 mcall receiver 在 self_mode 下不取址）
- 验证：`p78_method.sh` 新增 `SH-98` 生成 C 断言；红→绿；`check-all` 11/11
