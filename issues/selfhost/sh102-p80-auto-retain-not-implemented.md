---
id: SH-102
title: "D-013 §3：String 按值传参/返回/字段赋值未自动 retain（浅拷贝，ASan UAF）"
status: open
area: selfhost
severity: P1
opened: 2026-11-20
confirmed-by: REV-PH-80
---

# SH-102 · `String` 按值传参 / 返回 / 字段赋值未自动 retain

## 来源

[PH-80 收口复核](../../docs/reviews/2026-11-20-phase80-rev-verdict.md) §4.3、B1；
[D-013](../../docs/decisions/D-013.md) §3“复制 / retain 合同（C-6）”；
[phase80 卡 §7.9.1](../../docs/design/phase80.md#L364)。

## 结论

D-013 §3 要求“按值传参、按值返回、字段赋值、容器插入 `String` 时，按静态类型 retain”。当前
`v0.80.0` 只实现容器插入（`Vec` / `Map` 元素 glue 调 `retain`）与显式 `copy()` / `retain()`；
按值传参、返回、字段赋值仍是浅 struct 拷贝，**不 bump `refs`**。这不是纯文档口径问题：被调方
按协议 `release()` 参数、或调用方释放源句柄后，另一方仍持有同一块 buffer，构成 use-after-free。

项目自己在以下位置承认该缺口：

- [`lib/std/Str.h.ct:23-28`](../../lib/std/Str.h.ct#L23-L28)：`a plain by-value parameter, return or field assignment is a shallow struct copy and is not retained automatically in this phase`；
- [`docs/language-spec.md:2918`](../../docs/language-spec.md#L2918)：同文；
- [`docs/design/phase80.md:364-366`](../../docs/design/phase80.md#L364-L366)：`自动 retain（D-013 §3）未实现 ... 自动半部不满足`。

`p80_layout` 的 `gap param_refs=1`（[`test/ast/p80_layout/expected.trace.out:3`](../../test/ast/p80_layout/expected.trace.out#L3)）
把该事实钉成回归断言，因此探针全绿不能证明 D-013 §3 满足。

## 复现（`v0.80.0`，`60c6a2c`，归档独立构建的 ct-ast）

### 1. 按值传参

```ct
#include <stdio.h>

void drop_it(String a)
{
    printf("param refs=%d\n", a.refs());
    a.release();            /* 应先 retain 参数；实际没有 */
}

int main(void)
{
    Str lit = "hello";
    String s = lit.to_string();
    printf("before refs=%d len=%d live=%d\n", s.refs(), s.len(), ct_str_live_count());
    drop_it(s);
    printf("after refs=%d len=%d live=%d\n", s.refs(), s.len(), ct_str_live_count());
    return s.len();
}
```

```console
$ CT_STD_DIR=<v0.80.0>/lib/std ct-ast --allow-c-boundary gap.ct -o gap.c
$ cc -std=c99 -fsanitize=address -g gap.c -o gap
$ ASAN_OPTIONS=detect_leaks=0 ./gap; echo exit=$?
before refs=1 len=5 live=1
param refs=1
exit=134
=================================================================
ERROR: AddressSanitizer: heap-use-after-free on address 0x602000000970
READ of size 4 at 0x602000000970 thread T0
    #0 String_refs gap.c:513
    #1 main gap.c:1669
freed by thread T0 here:
    #1 String_release gap.c:545
    #2 drop_it gap.c:1662
    #3 main gap.c:1668
=================================================================
```

生成的 C 也直接显示没有 retain：

```c
void drop_it(struct String a) {
    printf("param refs=%d\n", String_refs(&a));
    String_release(&a);
}
```

### 2. 字段赋值

```ct
struct Holder { String tag; }
int main(void)
{
    Str lit = "tag";
    String s = lit.to_string();
    Holder h;
    h.tag = s;                 /* 应 retain */
    printf("field refs=%d s=%d\n", h.tag.refs(), s.refs());
    s.release();
    printf("field after s.release data0=%d\n", h.tag.data[0]);
    return h.tag.len();
}
```

```console
$ ASAN_OPTIONS=detect_leaks=0 ./field; echo exit=$?
field refs=1 s=1
exit=134
ERROR: AddressSanitizer: heap-use-after-free on address 0x602000000978
READ of size 1 at 0x602000000978 thread T0
```

生成的 C 是 `h.tag = s;` 的直接 struct 拷贝，没有 `String_retain`。

### 3. 非局部按值返回

```ct
String pass_through(String a)  /* 非局部 owning return = retain→return→release */
{
    return a;
}
int main(void)
{
    Str lit = "ret";
    String s = lit.to_string();
    String r = pass_through(s);
    printf("after return s=%d r=%d\n", s.refs(), r.refs());
    s.release();
    printf("r after caller release data0=%d\n", r.data[0]);
    return r.len();
}
```

```console
$ ASAN_OPTIONS=detect_leaks=0 ./ret; echo exit=$?
after return s=1 r=1
exit=134
ERROR: AddressSanitizer: heap-use-after-free on address 0x602000000978
READ of size 1 at 0x602000000978 thread T0
```

## 期望行为

按 D-013 §3：

- 按值传参：入口对参数按静态类型 `retain`，被调方 `release()` 只释放自己那一份；
- 按值返回：非局部 owning 返回 `retain → return → release`；局部句柄返回按 move；
- 字段赋值：先 `retain` 右值，再 `release` 旧值；
- 重新赋值：先 `retain` 右值，再 `release` 旧值；
- `refs = -1` immortal 仍直接返回。

## 影响

- D-013 §3 是 USER 2026-11-20 签收的 C-6 合同；未实现意味着 PH-80 不能按“D-013 满足”收口。
- 当前 API 文档要求使用者在参数 / 返回 / 字段位置显式 `retain()`，但这与 D-013 的“自动 retain”相反；
  按文档正常使用（被调方 `release()` 参数）会触发 UAF，ASan 可稳定捕获。
- 容器插入不受影响（`Vec` / `Map` glue 已 retain），`p80_layout` 的 trace 已覆盖。

## 处置建议

1. 在 `String` / `U16String` 的按值传参、返回、字段赋值三个位置补自动 retain；局部 `return` 保持 move。
2. 为三个位置各加正例（refs 递增、release 后源仍有效）与至少一个 ASan 负例（当前 `gap` / `field` / `ret` 可作候选）。
3. 更新 `p80_layout` 的 `expected.trace.out`：把 `gap param_refs=1` 改为 retain 后的期望值，并删除
   `trace.ct` 顶部“NOT auto-retained yet”的说明。
4. 同步 spec §4.70、lib/std README、phase80 卡 §7.9；实现前不得把 E80 / D-013 §3 标为满足。
