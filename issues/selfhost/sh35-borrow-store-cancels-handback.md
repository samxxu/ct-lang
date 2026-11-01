# SH-35 · 同作用域 `q = c;` 取消 `borrow` 的出口归还，池槽位静默泄漏

| 项 | 值 |
| --- | --- |
| 模块 | selfhost（ct-ast 内存分析 / 语句解析） |
| 严重度 | **High**（`borrow` 的核心承诺失效，且无任何告警） |
| 锚点 | commit `8b047f5`（2026-11-01）+ 工作树在途改动 |
| 文件 | [backend/mem/Memory.h.ct:277-287](../../selfhost/ct-ast/backend/mem/Memory.h.ct#L277-L287)（`leak_assign`）、[frontend/parse/Stmt.h.ct:226-257](../../selfhost/ct-ast/frontend/parse/Stmt.h.ct#L226-L257)（`check_borrow_store`）、[:1419](../../selfhost/ct-ast/frontend/parse/Stmt.h.ct#L1419) / [:1451](../../selfhost/ct-ast/frontend/parse/Stmt.h.ct#L1451)（两条赋值路径） |
| 状态 | 已修（2026-11-01）：`leak_assign` / `leak_decl` 跳过 `borrowed`，`check_borrow_store` 拒绝重赋值（`a borrowed pointer cannot be reassigned`）；门禁 `bw_neg borrow_reassign` 与正例 `bw_copy.ct` |

## 现象

`check_borrow_store` 有意放行**同作用域**的赋值（兄弟变量与借用同生共死，不算逃逸）：

```c
if (!self->sym->vars[lv].is_global && ls >= bs) return 0;
```

紧接着同一语句继续走 `leak_assign`，而它对「右值以独立变量形态出现」的变量一律清 `autodrop`：

```c
if (self->expr_returns(rhs, self->sym->vars[i].name)) self->sym->vars[i].autodrop = 0;
```

借用变量同样用 `autodrop = 1` 标记出口行为，于是 `struct Conn *q = c;` 把 `c` 的 `autodrop` 清掉，
**出口不再注入 `Conn_Handback_handback(c)`**。`owned` 本来就是 0（`mark_borrow` 设置），
所以 `leak_scope` 也不会告警——池槽位永久停在 `in_use = 1`，且用户看不到任何提示。

同一根因还覆盖重新赋值：`c = acq(2);` 走 `i == bv` 分支（[:279](../../selfhost/ct-ast/backend/mem/Memory.h.ct#L279)），
同样把 `autodrop` 清零，第一个对象既没归还也不报错。

## 证据

```ct
#include <stdio.h>
struct Conn { int fd; int in_use; } use Handback;
impl Handback for Conn { void handback() { self->in_use = 0; printf("hb\n"); } }
static struct Conn g_c;
static struct Conn *acq(void) { g_c.fd = 1; g_c.in_use = 1; return &g_c; }
int main(void) {
    borrow struct Conn *c = acq();
    struct Conn *q = c;
    printf("q %d\n", q->fd);
    return 0;
}
```

```text
$ ./ct-ast b11.ct -o b11.c ; echo $?
0
# 生成的主函数：末尾没有任何 handback（也没有告警）
int main(void) {
    struct Conn * c = acq();
    struct Conn * q = c;
    printf("q %d\n", q->fd);
    return 0;
}
```

对照：同样代码把 `q = c;` 删掉，出口就会正常出现
`if (c) { Conn_Handback_handback(c); c = 0; }`。

## 建议

二选一（推荐前者）：

1. `leak_assign` / `leak_return` 只对 `!borrowed` 的变量清 `autodrop`——借用的「逃逸」语义由
   `check_borrow_store` 单独负责，两套判定不应共用同一个标志位；
2. 让 `borrow` 走独立字段（如 `handback_at_exit`），彻底与 `own` 的逃逸分析解耦。

不论哪种，都应补两条探针：同作用域赋值后出口仍有 handback；重新赋值时报错或至少归还旧对象。

## 关联

- [SH-36](sh36-return-mention-cancels-autodrop.md)（同一族：出口行为被逃逸分析误清）
- [SH-37](sh37-static-local-holds-borrow.md)（`static` 局部把这条漏洞变成悬垂指针）
