# SH-31 · `emit_cond` 的 `B_AND` / `B_OR` / `B_XOR` 分支永远不可达

| 项 | 值 |
| --- | --- |
| 模块 | selfhost（ct-ast 发射器） |
| 严重度 | Info |
| 锚点 | commit `524ba99`（2026-10-31） |
| 文件 | [backend/emit/Emitter.h.ct:2147-2167](../../selfhost/ct-ast/backend/emit/Emitter.h.ct#L2147-L2167) |
| 状态 | 已修（2026-10-31）：删除 `emit_cond` 的三个不可达分支 |

## 现象

```c
if (self->arena->nodes[n].kind == N_BIN
    && self->arena->nodes[n].aux >= B_LT && self->arena->nodes[n].aux <= B_NE) {
    op = "<";
    … else if (aux == B_GT) … B_LE … B_GE … B_EQ … B_NE …
    else if (aux == B_AND) op = "&&";     /* 不可达：B_AND 不在 [B_LT, B_NE] 内 */
    else if (aux == B_OR)  op = "||";     /* 同上 */
    else if (aux == B_XOR) op = "^";      /* 同上 */
```

`B_LT … B_NE` 是 5–10，`B_AND` / `B_OR` / `B_XOR` 是 12 / 13 / 14，外层守卫已经把它们排除。
因此 `a && b` 实际落到 `return self->emit_expr(n)`，由 `emit_expr` 的「总是加括号」得到正确输出
（`((a) && (b))`）。功能正确，但三段死代码与注释表达的设计意图相反，后来者按它调整优先级会踩坑。

## 证据

读码确认：

```text
$ grep -n '#define B_' selfhost/ct-ast/backend/emit/Emitter.h.ct
…#define B_LT 5 … B_NE 10 … B_AND 12 … B_OR 13 … B_XOR 14
```

实测 `if (a && b)` 的生成物只由 `emit_expr` 的括号化路径产生（无 `emit_cond` 的 `" && "` 分支参与）。

## 建议

删掉三个不可达分支（并在守卫写成 `aux >= B_LT && aux <= B_NE` 处注明「按位 / 逻辑运算走 `emit_expr`」），
或把守卫扩到 `B_XOR` 并确认位运算也走这里——二者选其一，避免「看起来在分支里、实际不在」。
