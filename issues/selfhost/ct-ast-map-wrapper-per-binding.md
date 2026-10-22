# SH-15 · `map` 每条绑定无条件生成 wrapper 函数，缺少直绑零生成路径

| 项 | 值 |
| --- | --- |
| 模块 | selfhost（ct-ast） |
| 严重度 | Medium |
| 锚点 | commit `2ead601`（v0.12.0，2026-10-22） |
| 文件 | [selfhost/ct-ast/backend/emit/Emit.h.ct](../../selfhost/ct-ast/backend/emit/Emit.h.ct)（`emit_maps`）、[selfhost/ct-ast/frontend/parse/MapBuild.h.ct](../../selfhost/ct-ast/frontend/parse/MapBuild.h.ct) |
| 状态 | 待修（Batch 2 / 2b.1、2b.5） |

## 现象

`map` 的语义是纯编译期绑定，但生成物里每个绑定的方法都有一个生成的 `static` 包装函数：

```c
static int uart1_Controller_send(void *self, char *buf, int len) {
    (void)self;
    return mock_uart_send(&uart1, buf, len);
}
static struct Controller_vtbl uart1_Controller_vtable __attribute__((unused)) = {
    .send = uart1_Controller_send
};
```

两个观察：

1. wrapper 的 `self` 是幽灵——函数体第一行就是 `(void)self;`，真正的接收者是硬编码进函数体的
   `&uart1`。
2. wrapper 的**地址被 vtable 取用**，因此它永远不会被内联消除；每次派发多一次真实调用。
   `static inline` 也救不了。

vtable 本身（static 数据、无构造、无分配）不构成运行期负担，问题只在这个函数。

## 为什么不能无条件零生成

vtable 槽是**每条 trait 一份、全体绑定共用**的类型 `ret (*)(void *self, params...)`，
而具体 C 函数的签名各不相同（`mock_uart_send(struct mock_uart *, ...)`、`read(int fd, ...)`）。
把具体签名放进统一的擦除签名槽，中间必须有一次转换：

| 方案 | 结果 |
| --- | --- |
| 存具体函数指针 | 首参不是 `void *` 即类型不兼容（新版 Clang 直接 error） |
| 加 cast | C 标准下 UB；`int fd` 这类整数句柄还会触发 `-Wcast-function-type` |
| 生成 wrapper | 今天的行为，可移植但多一次调用 |

表达式实参（`-> f(&inst, buf, len)`、`-> f(g_base + v * 2)`）同样只能靠函数体表达——
这是 wrapper 存在的第二个理由。

## 修复建议

两级绑定，二者共存：

1. **直绑（fast path）**：CALL 写成 `-> f;`（裸函数名、无括号）时不生成 wrapper，
   vtable 初值直接 `.m = f;`。要求 `f` 的首参是 `void *`，与槽类型完全一致；ct 侧不校验签名
   （`#include` 进来的原型不在 CT 符号表里），不符由 C 编译器报错。
   C API 用 `int fd` 作句柄时，作者自写一个 `void *` 首参的 C shim 再直绑，生成物仍然零适配函数。
2. **fallback**：CALL 带括号时保留现有 wrapper，并把实参校验放宽为「标识符全可解析」
   （绑定参数 / 本 map 实例 / 已声明变量 / ALL_CAPS 宏 / `A::B` 限定名），
   支持 `g_base + v * 2` 这类简单表达式。

可观测性：`--emit-map` 的 `maps[].bindings[]` 增加 `"wrapper": true|false`；
直绑时 `symbol` 是被绑定的 C 函数名，fallback 时是 wrapper 名。

## 验证

- 新增 `test/ast/22_map_direct/prog.ct`：`-> real_put;`，断言生成物中**不存在** wrapper 函数、
  JSON 里 `"wrapper": false`、`symbol` 为 `real_put`、运行输出正确。
- 新增 `test/ast/20_map_expr/prog.ct`：表达式实参，断言仍生成 wrapper 且 JSON 标 `true`。
- 既有 `test/ast/15_map_args`、`bindings/mock-hal` 走 fallback，行为不变。
- `bash selfhost/check-all.sh` 九关全绿，`check-warnings.sh` 零告警。
