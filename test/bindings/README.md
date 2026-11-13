# Bindings — 在 CT 里消费既有 C 库

> 中文
>
> 状态：v1（Phase 12，2026-10-19）。首个 binding 为 [mock-hal/](mock-hal/)；真实库参考为
> [posix-socket/](posix-socket/)（第三十九批的伴随 C shim）。规范化的首批官方 binding 见
> `ct-pkg/hal-posix`（平台实现 [契约包 `ct-pkg/hal`](https://github.com/ct-pkg/hal)），
> 发行与索引用 [docs/package-guide.md](../docs/package-guide.md)。

---

## 中文

### 1. 什么是 binding

binding 是**纯 CT 源**，把某个 C 库的符号映射成 CT 的 `trait`，使 CT 代码能以 trait 方法调用的
形式使用该库。它**不引入任何语言特性**，只用两件已有能力：

1. 顶层**直通 C**（`#include`、宏、全局量原样保留）；
2. **`map`**（Phase 11）——把一个 trait 的方法绑定到某个**已声明的全局实例**上的具体调用。

### 2. 配方（五步）

以 [mock-hal/uart.h.ct](mock-hal/uart.h.ct) 为例：

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

配方体是**一次顶层调用**：`callee(实参, ...)`。可以重排、丢弃、补常量或 `&` 取址，但不能写转型、
逗号表达式、临时变量或第二条语句；这些形状放进同目录的 `<base>.shim.h`，配方只调 shim。违规报
`a map recipe must be a single call`。

三个正例（都来自本目录的绑定）：

```c
len(s) -> strlen(s);                             /* 接收者搬进实参 */
send(buf, n) -> mock_uart_send(&uart1, buf, n);  /* 绑定目标补在实参前 */
err() -> ct_sock_errno();                        /* 方法无参，接收者由宿主决定 */
```

### 2.1 分层：`.m.ct`、C shim、`.h.ct`、不支持

| 层 | 承载 | 成本 |
| --- | --- | --- |
| `.m.ct` 静态映射（第三十八批） | 无状态、单次调用型的函数式 / 句柄式 API（`for namespace` 或 `for type`） | 零 wrapper、零中间符号；C 类型上的 `.method` 直接在调用点展开 |
| C shim 头 | 无 userdata 的回调、语句宏、全局量、结构体字段、变参转发 | 用户手写一处适配 |
| `.h.ct` 真实类型 | 有状态封装、所有权 / RAII、错误翻译、动态派发 | 有对象与 vtable，非零成本但可控 |
| 不支持 | C++ ABI、需要完整预处理器的 API、位域 / 按值大结构体 | 明确拒绝 |

v1 的 [mock-hal/](mock-hal/) 仍是**有状态**的 `.h.ct` + 动态 `map`（全局实例 `uart1`）；无状态部分
可以另写 `mock_hal/mock_hal.m.ct` 走 `.m.ct`。`.m.ct` 的文件目录必须等于它的 `namespace`，且只承载
`#include` / `#define` / `pub trait` / `map`，不产任何产物。

### 2.2 C shim 的约定（第三十九批）

recipe 写不出的形状（宏 / 语句宏、`errno` 这类全局量、需要转换的调用、变参前缀转发、无 userdata
的回调）交给**同目录同名**的两个 C 文件：

```
<dir>/<base>.m.ct     映射单元
<dir>/<base>.shim.h   shim 头（消费者生成 .c 会自动 #include 它）
<dir>/<base>.shim.c   shim 源（可选；有它就必须有 .shim.h）
```

- `ct build` 的 `cc` 行自动加 `-I <shim 目录>`；`.shim.c` 直接列入该行源文件。
- shim 两文件的变化会重建消费者；`.m.ct` 本身仍不产任何产物。
- 头文件式 shim（只有 `.shim.h`，全 `static inline`）是最常见的形态。
- 参考实现：[posix-socket/](posix-socket/)（`socketpair` / `write` / `read` / `errno` 的
  `static inline` 包装，header-only）与 [mock-hal/](mock-hal/)（`mock_hal.h` + `mock_hal_impl.c`）。

### 3. 目录与命名

```
test/bindings/<lib>/
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

### 5. 跨单元接口值

自第 2 批起，`pub` struct 上的 `pub` trait 会导出 vtable，生成头也会定义接口类型，因此消费方可以
声明接口值、接住 `pub` 函数的返回值、甚至直接装箱该 struct（见
[language-spec](../docs/language-spec.md) §4.11）。

本 binding 把 trait 与实例都保持私有，其 vtable 仍是 `static`，所以在单元内完成装箱，对外只暴露
**标量入口**：

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

消费方 `import uart;` 后调用 `mock_hal_send(...)`。若把 trait 与实例标成 `pub`，消费方即可直接装箱
`uart1`。

### 6. 构建与测试

binding **不是**编译器的构建步骤：`gcc selfhost/l0/ctc.c` 与 `test/run.sh` 的编译相关层都不依赖它。
演示由 `selfhost/check-ast.sh` 的 bindings 小节驱动：

```
ct-ast build --emit-c test/bindings/mock-hal/demo.ct -o <out>
cc -Wall -Wextra -std=c99 -I test/bindings/mock-hal <out>/*.c test/bindings/mock-hal/mock_hal_impl.c -o demo
./demo   # 与 demo.expected.out 比对
```

手工复现：

```bash
mkdir -p /tmp/bind && ./ct build --emit-c test/bindings/mock-hal/demo.ct -o /tmp/bind
gcc -Wall -Wextra -std=c99 -I test/bindings/mock-hal /tmp/bind/*.c \
    test/bindings/mock-hal/mock_hal_impl.c -o /tmp/bind/demo && /tmp/bind/demo
# 7
```

### 7. 新增一个 binding 的检查清单

- [ ] `test/bindings/<lib>/` 目录；binding 单元名 ≠ 库头名
- [ ] 直通 `#include` 能看见全部被绑定的符号
- [ ] 镜像 struct 的布局与库实现一致（不透明句柄优先）
- [ ] `trait` 的每个方法都在 `map` 里**恰好绑定一次**（漏绑=空槽崩溃，重复=重定义）
- [ ] 需要初始化时提供 `pub` 入口；trait 私有就只能在单元内装箱（标量入口）
- [ ] `demo.ct` + `demo.expected.out`，期望值由**真实二进制**跑出来
- [ ] 端到端跑通：`ct build --emit-c` → `cc` 零警告 → 运行 → 比对
- [ ] 不 vendored、不下载、不成为编译器构建步骤
