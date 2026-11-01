# SH-38 · `borrow` 无法跨单元使用：`impl Handback` 必须与借用点同单元

| 项 | 值 |
| --- | --- |
| 模块 | selfhost（ct-ast 符号表 / 发射器 / 模块） |
| 严重度 | Medium（池库必然跨单元，当前形态让 `borrow` 只适用于单文件） |
| 锚点 | commit `8b047f5`（2026-11-01）+ 工作树在途改动 |
| 文件 | [frontend/parse/Stmt.h.ct:365-372](../../selfhost/ct-ast/frontend/parse/Stmt.h.ct#L365-L372)（`has_handback_impl` 校验）、[frontend/parse/Parser.h.ct:1531-1535](../../selfhost/ct-ast/frontend/parse/Parser.h.ct#L1531-L1535)（只在同单元内拷给 typedef 别名）、[backend/emit/Emitter.h.ct:1134-1138](../../selfhost/ct-ast/backend/emit/Emitter.h.ct#L1134-L1138)（原型只对本单元有 impl 的 struct 发） |
| 状态 | 已修（2026-11-01，按建议文档化不实现）：跨单元 `impl Handback` 需跨单元 impl 表，记入 `docs/design/borrow.md` §7 与 language-spec §4.40 已知限制；门禁 `bw_neg no_impl` 钉死 `but this unit has no impl` |

## 现象

`mark_borrow` 在**解析时**同时要求两件事：`uses_handback`（随 struct 定义跨单元可见）与
`has_handback_impl`（**只**在解析到 `impl Handback for S` 的那个单元置位）。于是：

- 类型定义在 `conn.h.ct`（`pub struct Conn … use Handback;`）；
- `impl Handback for Conn` 在 `conn_impl.ct`（正常做法：池的实现在库单元里）；
- 消费方 `main.ct` 里写 `borrow Conn *c = conn_get();`

会得到 `struct 'Conn' uses trait 'Handback' but has no impl` —— 尽管 impl 就在同一个 import 闭包里。

即使放宽这条校验也还不够：发射器只为「本单元解析到 impl」的 struct 输出
`static void __attribute__((unused)) S_Handback_handback(void *self);`，且实现体本身是 `static`
（[:1310-1330](../../selfhost/ct-ast/backend/emit/Emitter.h.ct#L1310-L1330)），跨单元既拿不到原型也链不上符号。
`Drop` 没有这个问题，因为 `delete` 由**调用方**发射 `S_Drop_drop` 时，`uses_drop` 已随 struct 定义传播。

## 证据

```text
conn.h.ct:      pub struct Conn { int fd; int in_use; } use Handback;
conn_impl.ct:   impl Handback for Conn { void handback() { self->in_use = 0; } }
main.ct:        borrow Conn *c = conn_get();

$ ./ct-ast build main.ct -o out
main.ct:5:5: error: struct 'Conn' uses trait 'Handback' but has no impl
ctc: 1 error(s) generated
```

同一布置下把 `impl` 搬进 `main.ct` 即可通过——说明限制来自「校验与发射都只看本单元」。

## 建议

1. 判定改为只看 `uses_handback`（与 `uses_drop` 同源），把「有没有 impl」留给链接期/发射期；
2. 借用点所在单元需要 `S_Handback_handback` 的**外部**原型：照 `Drop` 的导出规则，`pub` struct 上的
   `impl Handback` 应生成非 `static` 定义并在头文件里声明；
3. 若短期不修，必须在 `docs/language-spec.md` §4.40 的「已知限制」里显式写明
   「`borrow` 目前只在单单元内可用」，并补一条 `check-ast.sh` 负例把限制钉住。

## 关联

- [SH-39](sh39-impl-order-false-no-impl.md)（同一条校验的另一种误伤）
