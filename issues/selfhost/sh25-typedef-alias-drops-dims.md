# SH-25 · 带 tag 的 `typedef` 别名漏拷 `dims`，数组字段生成编译不过的 C

| 项 | 值 |
| --- | --- |
| 模块 | selfhost（ct-ast 解析器 / 发射器） |
| 严重度 | **High** |
| 锚点 | commit `524ba99`（2026-10-31） |
| 文件 | [frontend/parse/Parser.h.ct:1445-1473](../../selfhost/ct-ast/frontend/parse/Parser.h.ct#L1445-L1473) |
| 状态 | 已修（2026-10-31）：`Parser.h.ct` 的 tag→别名复制补上 `dims`；探针 [test/ast/59_typedef_alias_array](../../test/ast/59_typedef_alias_array/)，`check-ast.sh` 的语料等价段覆盖 |

## 现象

`typedef struct Tag { Inner items[2]; } Alias;` 时，解析器把 tag 行的 `nuse` / `nfields` /
`fields[].name` / `fields[].type` 复制到 `Alias` 行，**唯独没有复制 `fields[].dims`**；
而无 tag 的分支（:1461-1471）是复制 `dims` 的。

`dims` 是「该字段是数组」的唯一标记（`Init.h.ct` 的 `emit_field_vptrs` / `emit_array_field_vptrs`、
`TypeCheck.h.ct` 的 `type_has_array_init` 都读它）。别名行缺 `dims` 后：

- `type_has_array_init(Alias)` 为假 → 不走逐元素 vptr 循环；
- 但 `needs_init(Alias)` 仍为真（`nuse` 已复制）→ 落进 `emit_inline` 的 `N_DECL` 分支，
  对数组字段生成 `.items.__<trait>_vptr = &…`。

结果是对数组做成员访问，C 编译器直接拒绝。

## 证据

```ct
trait T { int m(); }
struct Inner { int x; } use T;
impl T for Inner { int m() { return 0; } }
typedef struct Wrap { Inner items[2]; } WrapT;
int main(void) { WrapT w; w.items[0].x = 1; return 0; }
```

```text
$ ./ct-ast td.ct -o td.c ; echo $?
0
$ grep -n 'WrapT w' td.c
34:    WrapT w = { .items.__t_vptr = &Inner_T_vtable };
$ cc -Wall -Wextra -std=c99 -c td.c
td.c:34:23: error: field designator cannot initialize a non-struct, non-union type 'struct Inner[2]'
```

同一源码写成 `struct Wrap w;`（走 tag 行，`dims` 完整）即正常；`test/cases/**` 与
`test/ast/**` 都没有「带 tag 的 typedef + 数组字段」组合，所以 403 项全绿也没暴露。

## 建议

在 :1455-1460 的复制循环里补一行 `snprintf(...fields[ui].dims, MAX_TEXT, "%s", structs[tagi].fields[ui].dims);`，
与无 tag 分支保持同构；并补两条用例（`test/ast` 一条行为探针 + `test/ast/errors` 不必），
最好再在 `check-ast.sh` 的负例或行为层加一条 `typedef` 别名派发断言。
