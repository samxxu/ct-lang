# Bindings — 在 CT 里消费既有 C 库

> 中文 · [English](#english)
>
> 状态：v1（Phase 12，2026-10-19）。首个 binding 为 [mock-hal/](mock-hal/)。

---

## 中文

### 1. 什么是 binding

binding 是**纯 CT 源**，把某个 C 库的符号映射成 CT 的 `trait`，使 CT 代码能以 trait 方法调用的
形式使用该库。它**不引入任何语言特性**，只用两件已有能力：

1. 顶层**直通 C**（`#include`、宏、全局量原样保留）；
2. **`map`**（Phase 11）——把一个 trait 的方法绑定到某个**已声明的全局实例**上的具体调用。

### 2. 配方（五步）

以 [mock-hal/uart.ct](mock-hal/uart.ct) 为例：

```c
#include "mock_hal.h"          /* 1. 直通 C：看见库的声明 */

trait Controller {             /* 2. 镜像 trait：方法签名照抄库 API */
    int send(char *buf, int len);
}

struct mock_uart {             /* 3. 镜像 struct：与库的实现保持同一布局 */
    int fd;
};

struct mock_uart uart1;        /* 4. 声明全局实例（map 的绑定目标） */

map trait Controller for instance uart1 {          /* 5. 把方法绑到具体调用 */
    send(buf, len) -> mock_uart_send(&uart1, buf, len);
}
```

### 3. 目录与命名

```
bindings/<lib>/
├── <lib>.h           库的声明（真实库=头文件；假 HAL=仓库内自带）
├── <lib>_impl.c      假 HAL 的实现（真实库不需要）
├── <unit>.ct         binding 本体
├── demo.ct           消费方（import <unit>;）
└── demo.expected.out demo 的期望输出
```

- **binding 单元的文件名不得与库头文件同名**。原因：`build` 模式下 `-o <outdir>` 会生成
  `<unit>.c` / `<unit>.h`，而直通 `#include "<lib>.h"` 的引号包含会**先搜输出目录**；若
  `<unit>.h` 恰好叫 `mock_hal.h`，生成的空壳头会遮蔽真正的库头。
- 每个 binding 一个目录；v1 **不需要**独立清单文件。
- binding 只放源，不放生成物（AGENTS §2）。

### 4. 头文件约定：不透明句柄 + 镜像布局

库头里对被映射的 struct **只做前置声明**，完整布局由 binding 提供：

```c
/* mock_hal.h */
struct mock_uart;                                   /* 不透明 */
int mock_uart_send(struct mock_uart *u, char *buf, int len);
```

```c
/* mock_hal_impl.c */
struct mock_uart { int fd; };                       /* 真实布局 */
```

C 允许每个翻译单元把不完整类型补全一次，因此生成物里的 `struct mock_uart { … }` 与库实现
各自成立。**镜像布局就是 ABI 契约**——两边必须保持一致；不一致时行为未定义（v1 不做校验）。

若库头已经给出完整定义，则 binding **不能**再定义同名 struct（C 重定义）。此时把库头判为
不透明、由 binding 提供布局，或给镜像 struct 换名并把库类型藏在 `void *` 之后。

### 5. 跨单元限制（v1）

`build` 模式的生成头只**前置声明**接口类型（`struct <Trait>_iface` 没有定义），因此**接口值不能
跨单元传递**；而映射实例的装箱本来就是单元私有的（[language-spec](../docs/language-spec.md) §4.10）。

因此 binding 在自己的单元内完成装箱，对外只暴露**标量入口**：

```c
pub void mock_hal_init(int fd) {
    uart1.fd = fd;
}

pub int mock_hal_send(char *buf, int len) {
    Controller c;
    c = uart1;                 /* 在定义单元内装箱 */
    return c.send(buf, len);
}
```

消费方 `import uart;` 后调用 `mock_hal_send(...)`。等跨单元接口值可用后，这一层可以去掉。

### 6. 构建与测试

binding **不是**编译器的构建步骤：`gcc selfhost/l0/ctc.c` 与 `test/run.sh` 的编译相关层都不依赖它。
演示由 `selfhost/check-ast.sh` 的 bindings 小节驱动：

```
ct-ast build bindings/mock-hal/demo.ct -o <out>
cc -Wall -Wextra -std=c99 -I bindings/mock-hal <out>/*.c bindings/mock-hal/mock_hal_impl.c -o demo
./demo   # 与 demo.expected.out 比对
```

手工复现：

```bash
mkdir -p /tmp/bind && ./ct build bindings/mock-hal/demo.ct -o /tmp/bind
gcc -Wall -Wextra -std=c99 -I bindings/mock-hal /tmp/bind/*.c \
    bindings/mock-hal/mock_hal_impl.c -o /tmp/bind/demo && /tmp/bind/demo
# 7
```

### 7. 新增一个 binding 的检查清单

- [ ] `bindings/<lib>/` 目录；binding 单元名 ≠ 库头名
- [ ] 直通 `#include` 能看见全部被绑定的符号
- [ ] 镜像 struct 的布局与库实现一致（不透明句柄优先）
- [ ] `trait` 的每个方法都在 `map` 里**恰好绑定一次**（漏绑=空槽崩溃，重复=重定义）
- [ ] 需要初始化时提供 `pub` 入口；不要把接口值传出单元（v1）
- [ ] `demo.ct` + `demo.expected.out`，期望值由**真实二进制**跑出来
- [ ] 端到端跑通：`ct build` → `cc` 零警告 → 运行 → 比对
- [ ] 不 vendored、不下载、不成为编译器构建步骤

---

## English

### 1. What a binding is

A binding is **plain CT source** that maps a C library's symbols onto a CT `trait`, so CT code can
use the library through trait method calls. It introduces **no language feature** and relies on two
existing ones: top-level **pass-through C** (`#include`, macros, globals) and **`map`** (Phase 11),
which binds a trait's methods to concrete calls on a **declared global instance**.

### 2. The recipe (five steps)

See [mock-hal/uart.ct](mock-hal/uart.ct): a pass-through `#include` so the library's declarations are
visible, a mirrored `trait` whose signatures copy the library API, a mirrored `struct` matching the
library's layout, one declared global instance, and a `map` that binds each method to a real call.

### 3. Layout and naming

```
bindings/<lib>/
├── <lib>.h            the library's declarations (real library = its header)
├── <lib>_impl.c       the fake HAL's implementation (not needed for a real library)
├── <unit>.ct          the binding
├── demo.ct            a consumer (`import <unit>;`)
└── demo.expected.out  the demo's expected output
```

- **A binding unit must not share its name with the library header.** In `build` mode the output
  directory receives `<unit>.c` / `<unit>.h`, and a quoted `#include "<lib>.h"` searches the
  includer's directory first — a `<unit>.h` named `mock_hal.h` would shadow the real header.
- One directory per binding; v1 needs **no** separate manifest.
- Sources only, never generated files (AGENTS §2).

### 4. Header convention: opaque handle + mirrored layout

The library header **forward-declares** the mapped struct and the binding supplies the full layout:

```c
/* mock_hal.h */
struct mock_uart;                                   /* opaque */
int mock_uart_send(struct mock_uart *u, char *buf, int len);
```

```c
/* mock_hal_impl.c */
struct mock_uart { int fd; };                       /* the real layout */
```

C lets each translation unit complete an incomplete type once, so the generated
`struct mock_uart { … }` and the library implementation coexist. **The mirrored layout is the ABI
contract** — the two must agree; v1 does not verify it.

If the library header already carries the full definition, the binding must **not** redefine the
struct (that is a C redefinition). Treat the header as opaque and supply the layout in the binding,
or rename the mirror and hide the library type behind a `void *`.

### 5. Cross-unit limit (v1)

In `build` mode the generated header only **forward-declares** interface types
(`struct <Trait>_iface` is undefined), so interface values cannot cross unit boundaries; boxing a
mapped instance is unit-private anyway ([language-spec](../docs/language-spec.md) §4.10).

A binding therefore boxes inside its own unit and exposes **scalar entry points**:

```c
pub int mock_hal_send(char *buf, int len) {
    Controller c;
    c = uart1;                 /* boxed in the defining unit */
    return c.send(buf, len);
}
```

The consumer does `import uart;` and calls `mock_hal_send(...)`. This layer goes away once
cross-unit interface values are supported.

### 6. Building and testing

A binding is **not** a compiler build step: neither `gcc selfhost/l0/ctc.c` nor the compilation layers of
`test/run.sh` depend on it. The demo is driven by the bindings section of
`selfhost/check-ast.sh` (build → `cc` → run → compare). Manual reproduction:

```bash
mkdir -p /tmp/bind && ./ct build bindings/mock-hal/demo.ct -o /tmp/bind
gcc -Wall -Wextra -std=c99 -I bindings/mock-hal /tmp/bind/*.c \
    bindings/mock-hal/mock_hal_impl.c -o /tmp/bind/demo && /tmp/bind/demo
# 7
```

### 7. Checklist for a new binding

- [ ] a `bindings/<lib>/` directory; the binding unit's name differs from the library header's
- [ ] the pass-through `#include` exposes every bound symbol
- [ ] the mirrored struct matches the library layout (prefer an opaque handle)
- [ ] every trait method is bound **exactly once** (a gap crashes on a null slot, a duplicate is a
      C redefinition)
- [ ] provide a `pub` entry point when initialisation is needed; do not hand interface values across
      units (v1)
- [ ] `demo.ct` + `demo.expected.out`, with expectations produced by the **real binary**
- [ ] end to end: `ct build` → warning-free `cc` → run → compare
- [ ] nothing vendored, nothing downloaded, never a compiler build step
