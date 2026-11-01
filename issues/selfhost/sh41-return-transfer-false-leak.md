# SH-41 · 归还所有权的 `return p;` 被误报为泄漏（L2 不报）

| 项 | 值 |
| --- | --- |
| 模块 | selfhost（ct-ast 内存分析） |
| 严重度 | Medium（误报会训练用户忽略泄漏告警；与 L2 行为分叉） |
| 锚点 | commit `8b047f5`（2026-11-01）+ 工作树在途改动 |
| 文件 | [backend/mem/Memory.h.ct:299-305](../../selfhost/ct-ast/backend/mem/Memory.h.ct#L299-L305)（`leak_return`）、[:248-256](../../selfhost/ct-ast/backend/mem/Memory.h.ct#L248-L256)（`leak_scope`）、[frontend/parse/Stmt.h.ct:172-195](../../selfhost/ct-ast/frontend/parse/Stmt.h.ct#L172-L195)（`retire_before_return`） |
| 状态 | 已修（2026-11-01）：同 SH-36 的 `expr_returns` 判定，`return b;` 不再误报 `potential leak`；门禁正例 `bw_handoff.ct` |

## 现象

`own` 变量以独立值被 `return` 时，所有权移交给调用者，这是规范允许的转移形态
（`docs/language-spec.md` §4.9「`return p;` 取消 autodrop（交给调用者）」）。

`leak_return` 的 `autodrop` 分支只清 `autodrop`、**不清 `owned`**：

```c
if (self->sym->vars[i].autodrop) {
    if (ret >= 0 && self->expr_mentions(ret, self->sym->vars[i].name))
        self->sym->vars[i].autodrop = 0;
    continue;
}
```

随后的 `retire_before_return` 只处理 `autodrop == 1` 的变量（`continue` 跳过），也不会清 `owned`；
于是函数收尾的 `leak_scope` 看到 `owned == 1 && !autodrop`，报
`warning: potential leak: 'b' (Box*) allocated but never deleted`。
L2 对同一输入保持沉默。

## 证据

```ct
struct Box *make(void) {
    own Box *b = malloc(sizeof(struct Box));
    b->n = 5;
    return b;                    /* 所有权交给调用者 */
}
```

```text
$ ./ct-ast n1.ct -o n1.c
n1.ct:6: warning: potential leak: 'b' (Box*) allocated but never deleted
$ ./l2 n1.ct -o l2n1.c
（无告警）
```

运行结果正确（调用方 `delete` 时 `drop 5` 触发一次），只是告警噪点。

## 建议

在 `leak_return` 的 `autodrop` 分支里，判定「确实移交」时同时清 `owned`（与
[SH-36](sh36-return-mention-cancels-autodrop.md) 的修法合并即可）：

```c
if (ret >= 0 && self->expr_returns(ret, self->sym->vars[i].name)) {
    self->sym->vars[i].autodrop = 0;
    self->sym->vars[i].owned = 0;
}
```

补一条 `test/modules/leak` 风格的负向对照：`return p;` 无告警、`printf("%d", p->n); return 0;` 有告警。

## 关联

- [SH-36](sh36-return-mention-cancels-autodrop.md)
