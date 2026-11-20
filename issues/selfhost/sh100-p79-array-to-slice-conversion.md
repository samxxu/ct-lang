---
id: SH-100
title: "E79-2：数组→切片转换只在局部声明生效，实参/返回值发射非法 C"
status: open
area: selfhost
severity: P1
opened: 2026-11-20
confirmed-by: REV-PH-79
---

# SH-100 · 数组→切片的实参/返回值没有转换

## 来源

[PH-79 收口复核](../../docs/reviews/2026-11-20-phase79-rev-verdict.md) B2（E79-2）。

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
