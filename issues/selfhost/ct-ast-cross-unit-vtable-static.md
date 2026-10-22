# SH-14 · vtable 为 `static`，导致接口值无法在消费单元装箱

| 项 | 值 |
| --- | --- |
| 模块 | selfhost（ct-ast） |
| 严重度 | **High** |
| 锚点 | commit `2ead601`（v0.12.0，2026-10-22） |
| 文件 | [selfhost/ct-ast/backend/emit/Emit.h.ct](../../selfhost/ct-ast/backend/emit/Emit.h.ct)（`emit_vtable_fwd`、impl 的 vtable 定义、`emit_box` 所在的装箱发射、`write_unit_header`） |
| 状态 | 待修（Batch 2 / 2a.1，前置 SH-13） |

## 现象

接口值（`struct <Trait>_iface`）本身是值类型 `{ void *self; struct <Trait>_vtbl *vt; }`，
trait 声明为 `pub` 时其 vtable 类型与 iface 类型都会进头文件——**跨单元传递接口值今天是通的**
（由拥有 impl 的单元装箱后 `pub` 返回即可）。真正缺的只有一步：在**别的单元**装箱。

装箱点发射 `&<Struct>_<Trait>_vtable`，而该 vtable 的定义与前向 tentative 定义都是 `static`：

```c
static struct Stream_vtbl Conn_Stream_vtable __attribute__((unused));
```

于是消费单元的生成物引用了一个不可见的符号。

## 证据

`net.ct`（拥有 `Conn` + `impl Stream for Conn`）与 `main.ct`（装箱）：

```ct
/* main.ct */
import net;
int main(void) {
    struct Conn *c;
    Stream s;
    c = conn_open();
    s = c;                       /* 装箱发生在 main 单元 */
    return 0;
}
```

`ct build main.ct -o out` 成功；`cc out/main.c out/net.c`：

```
main.ct:10:44: error: use of undeclared identifier 'Conn_Stream_vtable'
   10 |     s = (struct Stream_iface){ (void *)c, &Conn_Stream_vtable };
```

生成的头文件里 `struct Stream_vtbl`、`struct Stream_iface` 都在，缺的只有 vtable 符号本身。

同一份代码把装箱搬进 `net.ct` 并 `pub Stream stream_open(void)` 返回，**可以完整跑通**，
说明 iface 跨单元、跨单元派发、头文件导出都已就绪。

## 影响

- 第三方写网络的 bindings 时，`NetLib` / `Stream` 这类接口值只能由定义单元装箱后包一层
  `pub` 标量入口传出去，OO 退化。
- `map` 的实例 vtable 同样是 `static`（见 [SH-15](ct-ast-map-wrapper-per-binding.md)），
  跨单元 `map` 也被同一原因挡住。
- 这是「OO 只能停在单文件演示级别」这一判断的实际来源。

## 修复建议

1. 导出条件：`pub trait` ∧ `pub struct`（map 为 `pub trait` ∧ `pub` 实例）。任一不满足则保持 `static`——
   struct 非 pub 时消费单元连变量都声明不了。
2. `emit_vtable_fwd` 与定义处：满足条件时去掉 `static` 与 `__attribute__((unused))`
   （非 static 不会被 `-Wunused-variable` 命中）。
3. `write_unit_header`：在 trait 声明之后加
   `extern struct <Trait>_vtbl <Struct>_<Trait>_vtable;`。位置选**实现单元的头文件**
   （只有它知道 impl 存在），消费单元须 `import` 该单元。
4. 前置：先做 [SH-13](ct-ast-pub-global-dropped.md)（map 实例可见性）与 impl / map 唯一性校验；
   外部链接后重复定义即重复符号。
5. 顺带更新两处已过时的注释：
   [test/modules/split/impl_dog.ct](../../test/modules/split/impl_dog.ct#L5-L6) 的
   "no other unit can name them"，
   [bindings/mock-hal/uart.ct](../../bindings/mock-hal/uart.ct#L8-L9) 的
   "boxing a mapped instance is unit-private"。

## 验证

- 上面的最小复现：`ct build` 后 `cc` 通过，运行输出 `4`。
- 新增 `test/modules/xunit_box/`（不带 `build.args`，避免污染 L2 归档 golden），
  `check-ast.sh` 断言 `net.h` 含 `extern struct Stream_vtbl Conn_Stream_vtable;` 并运行比对。
- `bash selfhost/check-all.sh` 九关全绿。
