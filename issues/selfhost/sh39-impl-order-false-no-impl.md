# SH-39 · `impl Handback` 写在 `borrow` 之后被误报「has no impl」

| 项 | 值 |
| --- | --- |
| 模块 | selfhost（ct-ast 语句解析） |
| 严重度 | Low（有既有约定兜底，但消息误导） |
| 锚点 | commit `8b047f5`（2026-11-01）+ 工作树在途改动 |
| 文件 | [frontend/parse/Stmt.h.ct:365-372](../../selfhost/ct-ast/frontend/parse/Stmt.h.ct#L365-L372)；对照 README「Definitions must precede use」 |
| 状态 | 已修（2026-11-01）：`mark_borrow` 的失败消息改为 `struct '<S>' uses trait 'Handback' but this unit has no impl`（impl 在 borrow 之后也不再误报）；门禁 `bw_neg no_impl` |

## 现象

`has_handback_impl` 在解析 `impl Handback for S` 时才置位，而 `mark_borrow` 在解析 `borrow` 声明时就检查。
同一文件里把 `impl` 放在使用点之后，会得到与事实相反的诊断：

```text
k1.ct:5:5: error: struct 'Conn' uses trait 'Handback' but has no impl
```

（`impl Handback for Conn` 就在文件末尾。）

README 确实有一条「`impl` 必须先于任何调用它的函数出现」的通用约定，所以行为不算违背既有规则；
但消息说的是「没有 impl」，用户看到的是「明明有」，排查方向会被带偏。`Drop` 侧没有对应消息可对照。

## 证据

```ct
struct Conn { int fd; int in_use; } use Handback;
static struct Conn g;
int main(void) {
    borrow struct Conn *c = &g;
    c->in_use = 1;
    return 0;
}
impl Handback for Conn {
    void handback() { self->in_use = 0; }
}
```

```text
$ ./ct-ast k1.ct -o k1.c ; echo $?
k1.ct:5:5: error: struct 'Conn' uses trait 'Handback' but has no impl
1
```

## 建议

- 最小改动：把消息改成 `struct '<S>' has no 'impl Handback' before this borrow`，与「先定义后用」的约定对齐；
- 或在函数体解析结束后统一复检 `borrow` 过的类型，把顺序依赖去掉（与 [SH-38](sh38-borrow-cross-unit.md) 一起修）。
