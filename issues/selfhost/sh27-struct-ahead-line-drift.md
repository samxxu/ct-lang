# SH-27 · `struct_def_ahead` 不回滚行号状态，跨行前瞻后诊断行号永久偏移

| 项 | 值 |
| --- | --- |
| 模块 | selfhost（ct-ast 解析器） |
| 严重度 | Medium |
| 锚点 | commit `524ba99`（2026-10-31） |
| 文件 | [frontend/parse/Parser.h.ct:230-254](../../selfhost/ct-ast/frontend/parse/Parser.h.ct#L230-L254) |
| 状态 | 已修（2026-10-31）：`struct_def_ahead` 回滚 `line` / `tokline` / `tokstart` / `lstart`；门禁断言 `struct lookahead line`（`check-ast.sh`） |

## 现象

`struct_def_ahead()` 做一次「`struct` 后面跟 `{` 或 `;` 吗」的前瞻，结束后只恢复了
`pos` / `bol` / `tok` / `toknum` / `toktext`，**没有**恢复 `line` / `tokline` / `tokstart` / `lstart`。

`Lexer.next()` 里 `line` 是「遇到 `\n` 就自增」的运行计数器，回退 `pos` 不会让它回退。
因此只要前瞻跨过换行（`struct` 与 tag 不在同一行），`line` 就多加 1；随后重新读到同一 token 时
`tokline = line`，从此整份文件的 `tokline` 全部偏大。

同一文件的 `record_body_ahead`（:951-981）与 `label_ahead`（:805-835）都完整保存/恢复了这些字段，
本函数是唯一漏项的。

## 证据

```ct
struct
S { int x; };
struct S { int y; };     /* 实际在第 3 行 */
int main(void) { return 0; }
```

```text
$ ./ct-ast ln.ct -o ln.c
ln.ct:4:10: error: duplicate struct 'S'
ctc: 1 error(s) generated
```

行号 4 ≠ 实际 3；`--emit-map` 的 `line` 字段与后续所有诊断会继续沿用偏移后的计数器。

## 建议

按 `record_body_ahead` 的写法补齐保存/恢复（`sline = self->lex->line; stokline = …; sstart = …; slstart = …;`），
并加一条 `check-ast.sh` 断言：跨行 `struct` 头之后的重复定义诊断必须报在实际行。
