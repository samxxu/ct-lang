# SH-36 · `return` 表达式里「提到」变量就取消出口释放：`return b->n;` / `return c->fd;` 静默泄漏

| 项 | 值 |
| --- | --- |
| 模块 | selfhost（ct-ast 内存分析） |
| 严重度 | **High**（对 `borrow` 是静默槽位泄漏；对 `own` 是静默内存泄漏，两侧都无告警） |
| 锚点 | commit `8b047f5`（2026-11-01）+ 工作树在途改动 |
| 文件 | [backend/mem/Memory.h.ct:299-305](../../selfhost/ct-ast/backend/mem/Memory.h.ct#L299-L305)（`leak_return` 的 `autodrop` 分支）、对照 [:151-169](../../selfhost/ct-ast/backend/mem/Memory.h.ct#L151-L169)（`expr_returns`：成员读取**不**算移交） |
| 状态 | 已修（2026-11-01）：`leak_return` 的 `autodrop` 分支改用 `expr_returns`（真正移交才取消）并同时清 `owned`；门禁正例 `bw_ret.ct` |

## 现象

`leak_return` 处理带出口行为的变量时用的是 `expr_mentions`，而不是判定所有权的 `expr_returns`：

```c
if (self->sym->vars[i].autodrop) {
    if (ret >= 0 && self->expr_mentions(ret, self->sym->vars[i].name))
        self->sym->vars[i].autodrop = 0;            /* ← 提到就取消 */
    continue;
}
```

`expr_returns` 明确把 `p->n` / `p.n` 视为「读字段、不是移交」（:157），`expr_mentions` 却对成员访问的
基对象返回真（:131-133）。两条判定在这里走岔：`return b->n;` 既不收 `owned`、也不留 `autodrop`，
于是 `retire_before_return` 与 `}` 两条出口都不注入，对象直接漏掉。

对 `own` 变量，`leak_scope` 仍会补一条 `potential leak` 告警（所以是「静默泄漏 + 一条误报可能的告警」）；
对 `borrow` 变量，`mark_borrow` 把 `owned` 置 0，**连告警都没有**——`in_use` 永远停在 1。

## 证据

`own`（`/tmp/rev2/p/retfield.ct`）：

```ct
int f(void) {
    own Box *b = malloc(sizeof(struct Box));
    b->n = 7;
    return b->n;
}
```

```text
$ ./ct-ast retfield.ct -o retfield.c
retfield.ct:6: warning: potential leak: 'b' (Box*) allocated but never deleted
# 生成的函数体：return 之前没有任何 release，return 之后也没有
```

`borrow`（`/tmp/rev2/p/h1.ct`）：

```ct
int work(void) {
    borrow struct Conn *c = acq();
    return c->fd;
}
```

```text
$ ./ct-ast h1.ct -o h1.c ; echo $?
0                       # 没有任何告警
$ sed -n '/int work/,/^}/p' h1.c
int work(void) {
    struct Conn * c = acq();
    return c->fd;                      # 没有 handback
}
$ ./h1
9
in_use 1                # 槽位泄漏
```

对照：把 `return c->fd;` 换成 `return 0;`，出口立即出现
`if (c) { Conn_Handback_handback(c); c = 0; }`。

## 建议

把 `leak_return` 的 `autodrop` 分支改用 `expr_returns`，与 `leak_assign` 的选择保持一致：

```c
if (ret >= 0 && self->expr_returns(ret, self->sym->vars[i].name)) {
    self->sym->vars[i].autodrop = 0;
    self->sym->vars[i].owned = 0;      /* 见 SH-41：移交不该再报泄漏 */
}
```

修完后 `return b->n;` 会在 `return` 前释放并置空；`return b;` 仍按移交处理。

## 关联

- [SH-35](sh35-borrow-store-cancels-handback.md)（同族，赋值路径）
- [SH-41](sh41-return-transfer-false-leak.md)（同族，移交被误报为泄漏）
