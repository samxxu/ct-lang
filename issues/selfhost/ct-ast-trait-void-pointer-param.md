# SH-19 · trait 方法的裸 `void *` 参数被当成空参数列表

| 项 | 值 |
| --- | --- |
| 模块 | selfhost（ct-ast） |
| 严重度 | **High** |
| 锚点 | commit `224c08f`（Batch 2 收尾，2026-10-22） |
| 文件 | [selfhost/ct-ast/frontend/parse/Parser.h.ct](../../selfhost/ct-ast/frontend/parse/Parser.h.ct#L869-L875)（`parse_trait` 的参数循环） |
| 状态 | 已修（2026-10-22，`parse_trait` 前瞻一个 token） |

## 现象

trait 方法声明里写 `void *` 参数时，编译器在 `*` 处报 `unexpected token`：

```ct
trait T {
    int f(void *p, int n);
}
```

```
$ ct prog.ct -o prog.c
prog.ct:1:22: error: unexpected token
```

同一写法在**普通函数**里是合法的（`int g(void *p) { ... }` 编译通过），在 **struct 字段**
（`void *h;`）与 **trait 方法返回 void** 里也都合法。只有 trait 方法参数这一条路径失败。

`const void *p`（带 `const`）能通过，`void **p` 同样失败。

## 证据

| 输入 | 结果 |
| --- | --- |
| `trait T { int f(void *p); }` | `1:22: error: unexpected token` |
| `trait T { int f(const void *p); }` | 通过 |
| `trait T { int f(int *p); }` / `char *` / `struct Buffer *` | 通过 |
| `int g(void *p) { ... }`（普通函数） | 通过 |
| `struct Buffer { void *h; };` | 通过 |

根因在 [Parser.h.ct](../../selfhost/ct-ast/frontend/parse/Parser.h.ct#L869-L875)：进入参数列表后，只要
下一个 token 是标识符 `void`，就**无条件**认为这是 C 的 `(void)` 空参数写法，
`lex_next()` 之后直接 `expect(")")`；`void *p` 的下一个 token 是 `*`，于是报错。

## 影响

- C 库的 buffer / ownership API 几乎都用 `void *`：nc 的 `Buf`、`Stream::write(void *buf, int n)`、
  any-callback 接口。这条限制让第三方**无法用 trait 抽象这些函数**，只能退回 `char *` 或加 `const`
  （后者改变语义且对写接口不成立）。
- 这是「ct 的 OO 只能停在单文件演示级别」这条判断的又一处来源：即使跨单元链接已经打通，
  接口签名本身写不出来。

## 修复建议

在 `void` 分支先看下一个 token：

- 下一个是 `)` → 保持现在的「无参数」路径；
- 否则回退，按普通类型参数解析（`void` 由 `parse_type` 继续吃掉 `*`）。

改动集中在一个 if 分支，不需要新的 AST 节点；`void *` 在 vtable 签名里本来就是合法类型
（`void (*send)(void *, ...)` 到处都在用）。

## 验证

- 上面的最小复现必须通过，且生成物 `-Wall -Wextra` 零告警。
- 新增正例 `test/ast/24_trait_voidptr/prog.ct`：trait 方法与 impl 都用 `void *`，装箱后调用。
- `bash selfhost/check-all.sh` 九关全绿。
