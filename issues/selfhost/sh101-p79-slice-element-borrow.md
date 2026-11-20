---
id: SH-101
title: "E79-3：`s[i]` 作 ref/out 实参被拒绝（ref_arg_place 不识别 slice index）"
status: open
area: selfhost
severity: P1
opened: 2026-11-20
confirmed-by: REV-PH-79
---

# SH-101 · 切片元素不能作 `ref`/`out` 实参

## 来源

[PH-79 收口复核](../../docs/reviews/2026-11-20-phase79-rev-verdict.md) B3（E79-3）。

## 复现（`v0.79.1` `effbf6f7`）

```ct
void bump(ref int x) { x = x + 1; }
int main(void)
{
    int a[] = { 1, 2 };
    int[] s = a;
    bump(s[1]);
    return (a[1] == 3) ? 0 : 1;
}
```

```console
$ ct-ast check borrow_elem.ct; echo check=$?
borrow_elem.ct:6:1: error: ref/out argument must be an assignable place
check=1
$ ct-ast build borrow_elem.ct -o borrow_elem.bin; echo build=$?
borrow_elem.ct:6:1: error: ref/out argument must be an assignable place
build=1
```

切片元素的成员同样被拒绝：

```ct
struct P { int x; }
void bump(ref int x) { x = x + 1; }
...
struct P[] s = a;
bump(s[0].x);
```

```console
$ ct-ast check borrow_member.ct
borrow_member.ct:7:1: error: ref/out argument must be an assignable place
```

对照：C 数组元素 `bump(a[1])` 可以（`ref_arg_place` 的 `N_INDEX` 分支递归基址），
`&s[1]` 也可以；只有 `N_SLICE_INDEX` 作 ref/out 实参时被拒。

## 原因

`selfhost/ct-ast/frontend/parse/Expr.h.ct:1257-1297` 的 `ref_arg_place()` 没有
`N_SLICE_INDEX` 分支：`s[i]` 落到末尾 `return 0`。成员路径 `s[0].x` 先查基址
`N_SLICE_INDEX`，同样失败。PH-78 的 place 规则没有与 PH-79 的切片 place 接通。

## 期望

`bump(s[1])` 与 `bump(s[0].x)` 通过 `ct check`/`ct build`，写入作用于底层数组；
`a[1]` 变为 3。spec §4.69 与 E79-3 都明确写了 `s[i]` 是 place，“读、写、借用都作用于底层元素”。

## 影响

slice 元素只能读写、不能作 `ref`/`out` 实参；借用视图的“借用”语义不完整。

## 处置（DEV，2026-11-20，v0.79.2）

`fixed` 主张：`ref_arg_place()`（`selfhost/ct-ast/frontend/parse/Expr.h.ct`）增加
`N_SLICE_INDEX` 分支——切片元素是带检查 place，基址仍是 place 时接受；`const T[]`
（节点 aux 1）的元素保持只读，拒绝作可写 place。emitter 已有的
`&(*(T *)__ct_slice_at(&(s), i, sizeof(T)))` 让调用点取到元素地址，`__ct_slice_at`
的越界检查原样保留。

覆盖：

- `bump(s[1])` 写回底层数组；
- `bump(s[0].x)`（切片元素的成员）；
- `bump(s[2])` 越界仍在运行期 trap（stderr + 非零退出）；
- `const int[] ro; bump(ro[1]);` 仍报 `ref/out argument must be an assignable place`。

红证（baseline `2a2f3933`；完整输出见
[test/ast/p79_red_rev.log](../../test/ast/p79_red_rev.log)）：

```console
$ sh test/ast/p79_basic.sh <baseline>/build/ct-ast ; echo exit=$?
FAIL p79/basic: E79-3/SH-101: a slice element is a ref/out actual
  borrow_elem.ct:6:1: error: ref/out argument must be an assignable place
FAIL p79/basic: E79-3/SH-101: a slice element's member is a ref/out actual
  borrow_member.ct:7:1: error: ref/out argument must be an assignable place
FAIL p79/basic: E79-3/SH-101: a borrow keeps the bounds trap
  the trap fixture did not compile
exit=1
```

绿输出（v0.79.2）：

```console
$ sh test/ast/p79_basic.sh <ct-ast> ; echo exit=$?
ok   E79-3/SH-101: a slice element is a ref/out actual
ok   E79-3/SH-101: a slice element's member is a ref/out actual
ok   E79-3/SH-101: a borrow keeps the bounds trap
exit=0
$ sh test/ast/p79_index.sh <ct-ast> ; echo exit=$?
ok   E79-4: const T[] element is not a writable place
exit=0
```

生成 C：

```c
bump(&(*(int *)__ct_slice_at(&(s), 1, sizeof(int))));
```

红提交 `f9294448`；修复提交见 `git log --grep 'SH-101'`。
