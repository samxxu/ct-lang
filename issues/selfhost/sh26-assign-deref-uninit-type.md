# SH-26 · `*p = v;` 的赋值路径读取未初始化的 `tt`

| 项 | 值 |
| --- | --- |
| 模块 | selfhost（ct-ast 语句解析） |
| 严重度 | Medium |
| 锚点 | commit `524ba99`（2026-10-31） |
| 文件 | [frontend/parse/Stmt.h.ct:1119-1141](../../selfhost/ct-ast/frontend/parse/Stmt.h.ct#L1119-L1141) |
| 状态 | 已修（2026-10-31）：`Stmt.h.ct` 的 `=` 分支初始化 `tt`，`iface_ref_type` 增空串短路 |

## 现象

普通 `=` 赋值分支里：

```c
char tt[MAX_TEXT];        /* 1121：未初始化 */
...
if (((k == N_VAR && var_type(...tt...) == 0)
     || ((k == N_INDEX || k == N_MEMBER || k == N_ARROW) && expr_type(e, tt, ...) == 0))
    && strstr(tt, "(*"))
    self->ex->fnval_ok = 1;
...
if (self->sup->iface_ref_type(tt, tr, sizeof tr, &ip)) {   /* 1138：无条件读 tt */
```

`N_DEREF` 是合法的赋值目标（1125 行显式允许），但它不满足 1130-1132 的任何一个析取，
于是整个条件短路、`tt` 保持未初始化；`var_type` / `expr_type` 失败时同样。

`iface_ref_type` 内会 `snprintf(buf, sizeof buf, "%s", type)`（[TypeCheck.h.ct:135](../../selfhost/ct-ast/frontend/type/TypeCheck.h.ct#L135)），
即对栈垃圾做字符串读取；若垃圾恰好以 `struct …_iface` 开头，`maybe_box` 还会对普通指针赋值
走装箱路径并报出伪错误。

## 证据

触发面是任意普通函数体：

```ct
void f(int *p) { *p = 1; }
int main(void) { int x = 0; f(&x); return x - 1; }
```

```text
$ ./ct-ast deref.ct -o deref.c ; echo $?
0
$ cc -Wall -Wextra -std=c99 deref.c -o deref && ./deref ; echo $?
0
```

本轮未能构造出可观察的错误输出（未初始化栈内容依赖编译环境，多数时候「碰巧」不含 `_iface`），
因此定为 Medium 而不是 High：它是确定的未定义行为，且诊断结果不可复现地依赖栈内容。

## 建议

在 1121 行初始化为空串（`char tt[MAX_TEXT]; tt[0] = 0;`），或在 1138 前加 `k != N_DEREF` 守卫；
同时让 `iface_ref_type` 对空串直接返回 0（防御性，避免任何调用点漏初始化）。
补一条 `test/ast` 探针：`*p = 1;` 与 `*p = &other;` 均应照常编译、不触发装箱。
