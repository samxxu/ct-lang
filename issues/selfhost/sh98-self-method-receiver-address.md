---
id: SH-98
title: "`self.bump(self)` 的 receiver 仍发射 `&_self`（S**）"
status: verified
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

## REV 复核（2026-11-20，`v0.79.1` `effbf6f7`）

独立 `git archive v0.79.0` / `v0.79.1` 各自自举 L0→L1→L2→ct-ast，用 `v0.79.1` 的
`test/ast/p78_method.sh` 跑基线，并检查生成 C：

```console
# v0.79.0 baseline
$ sh test/ast/p78_method.sh ./ct-ast; echo exit=$?
FAIL p78/method: SH-98 method self receiver is not addressed
  static __attribute__((unused)) void S_bump(struct S *self, struct S * s) {
exit=1
$ grep -n 'S_bump(&_self' .ctbuild/self_ref.c
19:    S_bump(&_self, _self);
$ cc -std=c99 -Wall -Wextra -Werror .ctbuild/self_ref.c -o x
error: incompatible pointer types passing 'struct S **' to parameter of type 'struct S *'
```

```console
# v0.79.1
$ sh test/ast/p78_method.sh ./ct-ast; echo exit=$?
ok   SH-98 method self receiver is not addressed
p78_method: OK
exit=0
$ grep -n 'S_bump(_self, _self)' .ctbuild/self_ref.c
19:    S_bump(_self, _self);
$ cc -std=c99 -Wall -Wextra -Werror .ctbuild/self_ref.c -o x; echo cc=$?
cc=0
$ ./self_ref.bin; echo run=$?
run=0
```

结论：receiver 位从 `&_self`（`struct S **`）改为 `_self`（`struct S *`），与 ref 实参一致；
不是压警告，receiver 语义正确。`ct check` exit 0，`ct build` 零警告、运行 exit 0。
REV 置 `verified`。完整的 v0-PH-79/SH-98 复核见
[2026-11-20-phase79-rev-verdict.md](../../docs/reviews/2026-11-20-phase79-rev-verdict.md)。

> 范围说明：本 fix 覆盖 inherent/泛型 mcall 的 `self` receiver。trait vtable 路径的
> `self.bump(...)` 仍发射 `_self.__t_vptr->bump(&_self, ...)`，并另有非法 C（`_self.__t_vptr`
> 对指针用 `.`）；那是 v0-PH-78 遗留的 trait 自调用 codegen 路径，不在 SH-98 的复现与 fix 范围内，
> 记在 verdict 的不阻断观察里，未据此把 SH-98 打回。
