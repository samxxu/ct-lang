---
id: SH-96
title: "方法内 self 作 ref 实参发射成 &_self（S **），构建仅警告、运行错误"
status: open
area: selfhost
severity: P1
opened: 2026-11-20
confirmed-by: REV-PH-78
---

# SH-96 · `self.bump(self)` 发射 `&_self`

## 来源

[PH-78 收口复核](../../docs/reviews/2026-11-20-phase78-rev-verdict.md) B1（E78-2 / E78-6）。

## 复现（baseline `ca3354a5`，ct-ast v0.78.0）

```ct
struct S { int v; }
impl S {
    void bump(ref S s) { s.v = 1; }
    void go(void) { self.bump(self); }
}
int main(void) { struct S s = { 0 }; s.go(); return (s.v == 1) ? 0 : 1; }
```

```console
$ ct check self_ref.ct   # exit 0
$ ct build self_ref.ct   # exit 0，cc 警告 'struct S **' -> 'struct S *'
$ ./self_ref.bin         # exit 1（期望 0）
```

生成 C：

```c
static void S_bump(struct S *self, struct S * s) { (*s).v = 1; }
static void S_go(struct S *self) { S_bump(&_self, &_self); }
```

`self` 在发射层已经是 `_self`（`S *`），`emit_ref_arg()` 又无条件写 `&`，
得到 `S **`。

## 期望

`self.bump(self)` 发射 `S_bump(&_self, _self)`；`self` 作为 ref/out 实参时
不再取地址。

## 红证（baseline `ca3354a5`）

```console
$ CC=cc sh test/ast/p78_method.sh build/ct-ast
FAIL p78/method: SH-96 method self passed to ref without & (run)
  the built program exited non-zero
exit=1
```

## 处置

（待实现提交回填：`fixed` 主张、提交 sha、绿输出。）

## 处置（DEV，2026-11-20）

`fixed` 主张：`emit_ref_arg()` 对方法体里的 `self` 直接走 `emit_expr`（发射为
`_self`），不再加 `&`；其他实参保持取址。

绿输出：

```console
$ CC=cc sh test/ast/p78_method.sh build/ct-ast
ok   SH-96 method self passed to ref without & (run)
p78_method: OK
exit=0
```

生成 C 变为 `S_bump(&_self, _self)`；`s.v == 1`，运行 exit 0。提交：
`git log --grep "SH-96"`。
