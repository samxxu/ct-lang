---
id: SH-100
title: "E79-2：数组→切片转换只在局部声明生效，实参/返回值发射非法 C"
status: verified
area: selfhost
severity: P1
opened: 2026-11-20
confirmed-by: REV-PH-79
---

# SH-100 · 数组→切片的实参/返回值没有转换

## 来源

[v0-PH-79 收口复核](../../docs/reviews/2026-11-20-phase79-rev-verdict.md) B2（E79-2）。

## 复现（`v0.79.1` `effbf6f7`）

### 实参

```ct
int sum(int[] s) { return s[0]; }
int main(void)
{
    int a[] = { 7 };
    return sum(a) - 7;
}
```

```console
$ ct-ast check arr_arg.ct; echo check=$?
check=0
$ ct-ast build arr_arg.ct -o arr_arg.bin; echo build=$?
'cc' -std=c99 -I '.ctbuild' '.ctbuild/arr_arg.c' '-o' 'arr_arg.bin'
arr_arg.ct:40:17: error: passing 'int[1]' to parameter of incompatible type 'struct __ct_slice'
build=1
```

### 返回值

```ct
int[] f(void)
{
    int a[] = { 1, 2 };
    return a;
}
```

```console
$ ct-ast check arr_ret.ct; echo check=$?
check=0
$ ct-ast build arr_ret.ct -o arr_ret.bin; echo build=$?
arr_ret.ct:37:12: error: returning 'int[2]' from a function with incompatible result type 'struct __ct_slice'
build=1
```

局部声明 `int[] s = a;` 是唯一做了 `{ptr,len}` 转换的路径（`Stmt.h.ct:4120-4137` 的
`(struct __ct_slice){ (void *)(a), (int)(sizeof(a)/sizeof((a)[0])) }`）。实参、返回值与
`return a[1..]` 之外的数组表达式都没有同样的 coercion；`ct check` 也不报错，类型错误落到 cc。

## 期望

E79-2 写的是“数组→切片自动补 len”。至少以下位置应与局部声明一致：

- `f(a)` 的 `int[]` 形参；
- `return a;` 的 `int[]` 返回类型；
- 返回值/实参中的 `T a[]` 推断长度数组。

若设计上要求先写 `int[] s = a;` 再传，必须写进 spec §4.69 的边界，并让 `ct check` 在
未转换的位置硬错；当前是“check 放行、build 落到 cc”。

## 影响

切片形参无法直接接收数组；这是切片作为“借用视图”在函数边界上的主用法。
`int[] s = a; sum(s);` 可用，说明缺的是调用点/返回点的 coercion，而不是底层表示。

## 处置（DEV，2026-11-20，v0.79.2）

`fixed` 主张：新增“整数组→视图”节点（`N_SLICE_RANGE` aux 3）与
`ExprTypes.slice_view_from_array()`（`selfhost/ct-ast/frontend/parse/Expr.h.ct`）。
自由函数实参在 arity/类型/ref-out/boxing 检查之后转换；`return` 在 escape lint 之后转换
（`Stmt.h.ct`）。emitter 对 aux 3 发与局部声明相同的
`(struct __ct_slice){ (void *)(a), (int)(sizeof(a) / sizeof((a)[0])) }`；
`static_ctype` 把三种切片节点统一读成 `struct __ct_slice`。

覆盖：

- `sum(a)`（`int[]` 形参）与 `sum(o.xs)`（结构体数组字段）；
- `return g_arr;` / `return p->xs;`（`int[]` 返回）；
- `return a;`（局部数组）：转换后同时触发 `slice escape` lint（E79-6 的直接数组形式）；
- 静态/全局数组的视图不 lint。

边界（不改）：

- 多维数组→切片、`T a[]` 形参（已退化为指针）→切片不做长度推断；
- inherent/static 方法的形参类型不在 `MethAnn`，方法实参的本地数组→切片未扩
  （自由函数与 trait 方法、全局数组已覆盖）。见卡 §6 B-4/B-7。

红证（baseline `2a2f3933`；完整输出见
[test/ast/p79_red_rev.log](../../test/ast/p79_red_rev.log)）：

```console
$ sh test/ast/p79_basic.sh <baseline>/build/ct-ast ; echo exit=$?
FAIL p79/basic: E79-2/SH-100: an array actual fills a T[] parameter
  arr_arg.ct:44:17: error: passing 'int[2]' to parameter of incompatible type 'struct __ct_slice'
FAIL p79/basic: E79-2/SH-100: an array return fills a T[] result
  arr_ret.ct:41:12: error: returning 'int[2]' from a function with incompatible result type 'struct __ct_slice'
FAIL p79/basic: E79-2/SH-100: a struct's array field fills a T[] parameter
  field_arg.ct:48:17: error: passing 'int[2]' to parameter of incompatible type 'struct __ct_slice'
FAIL p79/basic: E79-6/SH-100: a converted local-array return lints
  the warning fixture did not build
exit=1
```

绿输出（v0.79.2）：

```console
$ sh test/ast/p79_basic.sh <ct-ast> ; echo exit=$?
ok   E79-2/SH-100: an array actual fills a T[] parameter
ok   E79-2/SH-100: an array return fills a T[] result
ok   E79-6/SH-100: a converted local-array return lints
ok   E79-2/SH-100: a struct's array field fills a T[] parameter
exit=0
$ sh test/ast/p79_places.sh <ct-ast> ; echo exit=$?
ok   E79-6: returning a local array (converted) lints
ok   E79-6: a view of a global array does not lint
ok   E79-6: a view of a static array does not lint
exit=0
```

生成 C 例：

```c
return (struct __ct_slice){ (void *)(o.xs), (int)(sizeof(o.xs) / sizeof((o.xs)[0])) };
```

红提交 `f9294448`；修复提交见 `git log --grep 'SH-100'`。


## REV 复核（2026-11-20，v0.79.2 `13dcb594`）

`git archive v0.79.2` 独立自举（`ct-ast v0.79.2`，零构建警告）后复跑：

```console
$ /tmp/rev-ph79v2/ct-ast check arr_arg.ct; echo check=$?
check=0
$ /tmp/rev-ph79v2/ct-ast build arr_arg.ct -o arr_arg.bin; echo build=$?
build=0
$ ./arr_arg.bin; echo run=$?
run=0
$ /tmp/rev-ph79v2/ct-ast build arr_field_arg.ct -o arr_field_arg.bin && ./arr_field_arg.bin; echo field_run=$?
field_run=0
$ /tmp/rev-ph79v2/ct-ast build arr_ret_global.ct -o arr_ret_global.bin && ./arr_ret_global.bin; echo ret_global_run=$?
ret_global_run=0
```

生成 C 采用与局部声明相同的 `{ptr,len}` compound literal：

```c
return (sum((struct __ct_slice){ (void *)(a), (int)(sizeof(a) / sizeof((a)[0])) }) - 7);
...
return (struct __ct_slice){ (void *)(g), (int)(sizeof(g) / sizeof((g)[0])) };
```

直接返回局部数组 `return a;` 现在先转换再触发 lint：

```console
$ /tmp/rev-ph79v2/ct-ast check arr_ret_local.ct; echo check=$?
arr_ret_local.ct:4:12: error: slice escape: 'return' hands back a view of a local array
check=1
$ /tmp/rev-ph79v2/ct-ast build arr_ret_local.ct -o arr_ret_local.bin; echo build=$?
arr_ret_local.ct:4:12: warning: slice escape: 'return' hands back a view of a local array
build=0
```

自由函数实参/返回值与结构体数组字段均通过。卡面 §6 B-7 明确记录 inherent/static 方法实参
的本地数组→切片未扩（trait 方法签名当前拒绝 `T[]` 形参），不属本轮声称覆盖的范围。
SH-100 已修，REV 置 `verified`。
