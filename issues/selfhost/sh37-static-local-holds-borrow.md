# SH-37 · `static` 局部变量可以接收借用指针，逃逸检查漏判

| 项 | 值 |
| --- | --- |
| 模块 | selfhost（ct-ast 语句解析） |
| 严重度 | Medium（正是 `borrow` 要堵的悬垂场景） |
| 锚点 | commit `8b047f5`（2026-11-01）+ 工作树在途改动 |
| 文件 | [frontend/parse/Stmt.h.ct:197-207](../../selfhost/ct-ast/frontend/parse/Stmt.h.ct#L197-L207)（`var_scope`）、[:226-257](../../selfhost/ct-ast/frontend/parse/Stmt.h.ct#L226-L257)（`check_borrow_store`） |
| 状态 | 已修（2026-11-01）：`Symbols.h.ct` 的 `Var` 新增 `is_static` 并由 `parse_var` 置位，`check_borrow_store` 拒 `static` / 全局目标；门禁 `bw_neg store_static` |

## 现象

`check_borrow_store` 用「目标变量的作用域是否比借用更浅」来判断存活期：同层或更深的局部放行，
全局与更浅的作用域报错。`var_scope` 只看 `sym->scope[s] <= vi`，**不区分静态存储**：

```c
static struct Conn *s;
borrow struct Conn *c = acq();
s = c;                 /* 接受：s 与 c 同作用域 */
```

`static` 局部活到程序结束，是标准的悬垂来源，却因为「同作用域」被放行。
`own` 侧有 `a static local cannot be 'own'` 的专门拒绝，`borrow` 侧对**声明**也拒绝
（`a static local cannot be 'borrow'`），但对**赋值目标**没有对应判断。

## 证据

```ct
struct Conn { int fd; } use Handback;
impl Handback for Conn { void handback() { self->fd = 0; } }
static struct Conn g_c;
static struct Conn *acq(void) { return &g_c; }
void f(void) {
    static struct Conn *s;
    borrow struct Conn *c = acq();
    s = c;
}
int main(void) { return 0; }
```

```text
$ ./ct-ast b8.ct -o b8.c ; echo $?
0
$ sed -n '/^void f/,/^}/p' b8.c
void f(void) {
    static struct Conn * s;
    struct Conn * c = acq();
    s = c;
}
```

（同一份产物里连 handback 都没有——那是 [SH-35](sh35-borrow-store-cancels-handback.md)。）

## 建议

记录变量的静态性（`N_DECL.aux == 1` 已标记静态局部），在 `check_borrow_store` 里把静态目标视同全局：
命中即报 `a borrowed pointer cannot be stored in '<name>' (its scope outlives the borrow)`。

## 关联

- [SH-35](sh35-borrow-store-cancels-handback.md)
