---
id: SH-99
title: "E79-2：数组开区间子切片 `a[1..]` 发射非法 C（Emitter.h.ct:5212 缺右括号）"
status: open
area: selfhost
severity: P1
opened: 2026-11-20
confirmed-by: REV-PH-79
---

# SH-99 · `a[1..]` 发射非法 C

## 来源

[PH-79 收口复核](../../docs/reviews/2026-11-20-phase79-rev-verdict.md) B1（E79-2）。

## 复现（`v0.79.1` `effbf6f7`，ct-ast 独立自举）

```ct
int main(void)
{
    int a[] = { 1, 2, 3 };
    int[] t = a[1..];
    return t[0] - 2;
}
```

```console
$ ct-ast check a1open.ct; echo check=$?
check=0
$ ct-ast build a1open.ct -o a1open.bin; echo build=$?
'cc' -std=c99 -I '.ctbuild' '.ctbuild/a1open.c' '-o' 'a1open.bin'
a1open.ct:36:95: warning: cast to smaller integer type 'int' from 'char *' [-Wpointer-to-int-cast]
a1open.ct:36:156: error: expected ')'
build=1
```

生成的 C（`a[1..]` 的 hi 省略分支）：

```c
struct __ct_slice t = __ct_slice_range((void *)(a),
    (int)(sizeof(a) / sizeof((a)[0])), 1,
    (int)(sizeof(a) / sizeof((a)[0]), sizeof(int), "a1open.ct:4");
```

`(int)(` 没有闭合：`Emitter.h.ct:5212` 写的是 `fputs(")[0])", ...)`，同函数显式上界分支
（`Emitter.h.ct:5196`）写的是 `)[0]))`。slice 基座 `s[1..]` 走 `).len` 分支，不触发该缺陷，
因此 `p79_basic` 的 `int[] t = s[1..]` 仍是绿的。

## 期望

`ct-ast check` 与 `ct-ast build` 均 exit 0；`t` 为 `{a+1, 2}`，运行 exit 0。
卡面 §2.1 明确把 `a[1..]` 列为 `p79_basic` 的断言，但实际夹具用的是 `s[1..]`（见 TEST-24）。

## 影响

数组基座的省略上界子切片完全不可用；调用方拿到的是 C 编译错误而不是 CT 诊断。
`a[lo..hi]` 与 `s[lo..]` 不受影响。

## 处置（DEV，2026-11-20，v0.79.2）

`fixed` 主张：数组基座省略上界的子切片分支补齐了 `(int)(` 的右括号：
`selfhost/ct-ast/backend/emit/Emitter.h.ct` 的 `c < 0 && aux == 1` 分支由
`fputs(")[0])", ...)` 改为 `fputs(")[0]))", ...)`，与同函数显式上界分支一致。
半开语义不变：`a[1..]` 生成 `__ct_slice_range((void *)(a), len, 1, len, sizeof(int), ...)`，
即 `{a + 1, len - 1}`。

红证（baseline `2a2f3933`，独立自举构建；完整输出见
[test/ast/p79_red_rev.log](../../test/ast/p79_red_rev.log)）：

```console
$ sh test/ast/p79_basic.sh <baseline>/build/ct-ast ; echo exit=$?
FAIL p79/basic: E79-2/SH-99: array-base open subslice a[1..] is half-open and valid C
  a1open.ct:40:95: warning: cast to smaller integer type 'int' from 'char *' [-Wpointer-to-int-cast]
    struct __ct_slice t = __ct_slice_range((void *)(a), (int)(sizeof(a) / sizeof((a)[0])), 1, (int)(sizeof(a) / sizeof((a)[0]), sizeof(int), "a1open.ct:4");
exit=1
```

绿输出（v0.79.2）：

```console
$ sh test/ast/p79_basic.sh <ct-ast> ; echo exit=$?
ok   E79-2/SH-99: array-base open subslice a[1..] is half-open and valid C
ok   E79-2: array-base bounded subslice a[1..3] stays half-open
exit=0
```

生成 C：

```c
struct __ct_slice t = __ct_slice_range((void *)(a), (int)(sizeof(a) / sizeof((a)[0])), 1,
    (int)(sizeof(a) / sizeof((a)[0])), sizeof(int), "a1open.ct:4");
```

回归：`p79_basic` 的 `s[1..]`、`a[1..3]` 与既有 goldens 不变。
红提交 `f9294448`；修复提交见 `git log --grep 'SH-99'`。
