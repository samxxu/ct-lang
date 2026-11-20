---
id: SH-102
title: "D-013 §3：String 按值传参/返回/字段赋值未自动 retain（浅拷贝，ASan UAF）"
status: reopened
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

## 处置（DEV，2026-11-20）：**fixed**

`status` 保持 `open`（5.4：`fixed` 只写正文，由 REV 复核后改 `verified`）。D-013 §3 的自动半部
已在 v0.80.1 实现，三处 ASan 复现全部转绿，ABI 未变。

### 实现

- **按值传参**：`String` / `U16String` 形参在函数入口 `a = String_retain(&a)`，所有出口
  （`return` / `break` / `continue` / 末尾 `}`）`release`；被 move / return 的那一份不释放。
  显式 `a.release()` 会把形参 `ptr` 置空，出口释放因此是空操作，不会双重释放。
- **按值返回**：局部句柄 = move；非局部 owning（字段 / 全局 / 解引用）= retain；返回聚合
  （`Result<String,E>` 等）时表达式命中的局部按 move 处理，不先释放。借用视图作为 owning
  返回值硬错（`cannot return a borrowed view as an owning string; call to_string()`）。
- **字段赋值**：右值是 place 时 retain（借用视图也 retain，存储位置要自己持有一份）；构造结果
  （call / `retain()` / 字面量）直接 move。旧值不自动 release（字段无自动 Drop，沿用 §7.9.4
  的既有边界；容器模板自己的 `__ct_elem_release` 仍生效）。
- **重新赋值**：先 retain 右值、再 release 旧值；无初始化器的句柄补 `= { 0 }`，因此旧值 release
  与作用域释放恒安全。
- **作用域**：释放 owning 局部；借用视图（`Vec.get` / `Map.get` 结果）既不 retain 也不 release，
  cview 语义不变。
- `refs = -1` immortal 在 retain / release 两侧都跳过；`refs` 布局、8 字节头、`_Static_assert`
  均未改。

设计取舍（D-013 未逐字规定、按 §3 与提案 Q5 决定）：

1. 局部初始化 / 局部副本按“**复制即 retain**”处理（`String b = a;` 共享缓冲、双方各自 release），
   重新赋值先 retain 后 release 旧值；D-013 只对“重新赋值”写了顺序，这里把它同样用于局部
   初始化。
2. 字段赋值的旧值不自动 release——D-013 的第一条只要求“字段赋值 retain”，把“先 retain 再
   release 旧值”限定在变量重新赋值，避免对未初始化字段 release。
3. 容器模板（`Vec` / `Map`）的 `T` 位置仍由 `__ct_elem_retain` / `__ct_elem_release` 显式管理，
   发射器在模板形参位置不重复 retain；`Vec.get` / `Vec.pop` / `Map.entry` 保持借用 / move。

### 提交

- `3841cedf` `test(ct-ast): SH-102 红`（只含夹具与红证，baseline `02cf32d5`）
- `07cafee1` `fix(ct-ast): SH-102 自动 retain（D-013 §3）`
- 收口提交：本提交（v0.80.1 版本与文档）

### 验证（原始输出）

```console
$ bash selfhost/check-ast.sh
== summary: 1538 passed, 0 failed, 4 skipped ==

$ CT_C_BOUNDARY=allow sh test/ast/p80_retain.sh <ct-ast>
ok   retain (automatic retain / release trace)
ok   retain -fsanitize=address
ok   retain -fsanitize=undefined
ok   neg_escape (rejected: escape of a borrowed view)
ok   neg_double_free (rejected: double free of a borrowed element)
p80_retain: OK
```

三个 ASan 复现（`cc -std=c99 -fsanitize=address -g`，`ASAN_OPTIONS=detect_leaks=0`）：

```console
# 修复前（baseline 02cf32d5）
$ ./gap   -> before refs=1 len=5 live=1 / param refs=1
             exit=134 ERROR: AddressSanitizer: heap-use-after-free … String_refs … main
$ ./field -> field refs=1 s=1
             exit=134 ERROR: AddressSanitizer: heap-use-after-free … READ of size 1
$ ./ret   -> after return s=1 r=1
             exit=134 ERROR: AddressSanitizer: heap-use-after-free … READ of size 1
# 修复后（v0.80.1）
$ ./gap   -> before refs=1 len=5 live=1 / param refs=2 / after refs=1 len=5 live=1  exit=5
$ ./field -> field refs=2 s=2 / field after s.release data0=116                      exit=3
$ ./ret   -> after return s=2 r=2 / r after caller release data0=114                 exit=3
```

### 仍未覆盖（沿用作者负责口径，不阻断本条）

- 结构体字面量 / 复合字面量里的 `String` 字段仍是浅拷贝；返回这类聚合时按 move 处理，不先释放
  命中的局部，但作为普通局部初始化器时源句柄仍需作者 `retain()`。
- `foreach` 的 `item`、多声明符局部、`for` 初始化器里的句柄不登记；`goto` 跨块不释放。
- 泛型实例里 `T` 位置的局部只按容器 glue 的显式协议处理。
- 字段 / 全局 `String` 仍无自动 Drop（卡 §7.9.4）。

## 复核（REV，2026-11-20，v0.80.1）：**reopened**

复核记录见 [PH-80 次轮复核](../../docs/reviews/2026-11-20-phase80-rev-verdict.md) §11。三个原 ASan
复现（参数 / 字段赋值 / 非局部返回）与 `p80_retain` 已在 v0.80.1 转绿；但该修复仍有新的漏 release /
UAF，故不置 `verified`，SH-102 置 `reopened`。

### R1 嵌套 `break` / `continue` 漏 release（阻断）

```ct
for (i = 0; i < 2; i++) {
    String s = lit.to_string();
    if (i == 0) { continue; }
    if (i == 1) { break; }
}
```

```console
$ ./jump2; echo exit=$?
iter 0 refs=1 live=1
iter 1 refs=1 live=2
after loop live=2
exit=0
```

生成的 C 在嵌套分支里直接 `continue;` / `break;`，没有 `String_release(&s)`；`sb_jump_release()`
只释放最内层 block（[`Emitter.h.ct:717-723`](../../selfhost/ct-ast/backend/emit/Emitter.h.ct#L717-L723)），
与 SH-102 处置段和卡 §7.9.1 的“所有出口（return / break / continue / 末尾 `}`）release”不符。
直接写在循环体顶层的 `continue` 会正确释放，故这是嵌套 block 的路径覆盖缺口。

### R2 字段重赋旧值不 release（泄漏）

```ct
h.tag = x;                 /* retain x */
h.tag = b.to_string();     /* 旧值没有 release */
```

```console
$ ./field_reassign
after1 tag=2 x=2 live=1
after2 tag=1 x=2 live=2
after_x_release tag=1 live=2
final live=1
```

`sb_assign` 只对局部绑定计算 `release_old`（[`Emitter.h.ct:805`](../../selfhost/ct-ast/backend/emit/Emitter.h.ct#L805)），
字段 / 全局 / 解引用目标不释放旧值。D-013 §3 “重新赋值：先 retain 右值，再 release 旧值”未限定
“仅局部变量”；若按 DEV 的窄解释，应在 D-013/卡上补明，否则未满足。

### R3 已登记边界仍含 UAF / 双重释放

- `Holder h = { x };`（结构体字面量字段）→ 浅拷贝，`x.release()` 后读 `h.tag` 报 ASan heap-use-after-free；
- `String y = x, z = y;`（多声明符局部）→ 浅拷贝，`y.release(); z.release();` 报 ASan UAF / double free；
- `goto` 跨块 → `after goto live=1`（泄漏）。

卡 §7.9.7 已登记这些位置为“作者负责”，但其中两项是 UAF/双重释放而非普通泄漏；建议至少加硬错 /
lint 或另立 issue，不能作为“D-013 §3 满足”的依据。

### R4 未发现过度 retain

`p80_retain` 的 copy / field / stolen / pass / reassign / U16 / immortal 轨迹与额外全局 / 解引用 /
自赋值 / 提前 return / U16 split 复现均未出现双 retain；`refs=-1` 在 retain / release 两侧跳过。
问题集中在漏 release（R1/R2）与未登记的 UAF 边界（R3），不是过度 retain。
