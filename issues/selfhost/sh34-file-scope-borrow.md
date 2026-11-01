# SH-34 · 文件作用域的 `borrow` 被静默接受，`borrow` 原样写进生成的 C

| 项 | 值 |
| --- | --- |
| 模块 | selfhost（ct-ast 语句解析 / 发射） |
| 严重度 | **High**（接受非法输入，退出码 0，产物不可编译） |
| 锚点 | commit `8b047f5`（2026-11-01）+ 工作树在途改动 |
| 文件 | [frontend/parse/Stmt.h.ct:826-843](../../selfhost/ct-ast/frontend/parse/Stmt.h.ct#L826-L843)（`borrow` 只在 `parse_stmt` 里识别）、对照 [frontend/parse/Parser.h.ct:556-558](../../selfhost/ct-ast/frontend/parse/Parser.h.ct#L556-L558)（`own` 的文件作用域拒绝） |
| 状态 | 已修（2026-11-01）：`Parser.h.ct` 的顶层声明入口拒绝 `borrow`（`'borrow' is only allowed inside a function body`）；门禁 `bw_neg borrow_file_scope` |

## 现象

`borrow` 的识别只挂在语句层（`parse_stmt`）。文件作用域的声明走的是 `Parser` 的顶层声明路径，
那里对 `own` 有专门拒绝（`'own' is only allowed inside a function body`），**对 `borrow` 没有**：

```c
if (self->lex->tok == T_ID && strcmp(self->lex->toktext, "own") == 0)
    return tool::diag::ct_sem_error(..., "'own' is only allowed inside a function body", ...);
```

于是全局声明 `borrow T *g = …;` 落进普通声明路径，`borrow` 被当作类型名的一部分原样透传，
既不报错，也不登记为借用（没有出口，也就永远不归还）。

`docs/language-spec.md` §4.40 明确写着「数组、`static` 局部、**文件作用域**、`switch` 体内一律报错」——
实现与规范相反。

## 证据

```ct
struct Conn { int fd; } use Handback;
impl Handback for Conn { void handback() { self->fd = 0; } }
borrow struct Conn *g = 0;
int main(void) { return 0; }
```

```text
$ ./ct-ast b2.ct -o b2.c ; echo $?
0
$ grep -n borrow b2.c
10:borrow struct Conn * g = 0;
$ cc -std=c99 -c b2.c
b2.c:10:1: error: unknown type name 'borrow'
```

编译器退出码 0，产物是 C 编译器无法接受的源码。`check-ast.sh` 只覆盖 `switch` / `static` / 数组三种
拒绝，没有文件作用域用例。

## 建议

1. 在 `Parser` 的顶层声明入口照 `own` 补一条拒绝，消息与其它 `borrow` 诊断同族，例如
   `'borrow' is only allowed inside a function body`；
2. `check-ast.sh` 的 `bw_neg` 表加一条文件作用域负例。

## 关联

- [DOC-45](../docs/doc45-tutorial-memory-delete-null.md)（教程对 `delete` / `return` 的陈述同样过期）
- `docs/language-spec.md` §4.40 的约束清单在该条修复前与实现不符
