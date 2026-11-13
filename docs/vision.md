# 愿景与设计原则

> 中文

本文记录 CT 项目的**定位、设计原则与生态策略** —— 回答「为什么这样做」。
「现在能用什么」见 [language-spec](language-spec.md)；「接下来做什么」见 [roadmap](roadmap.md)。

---

## 中文

### 1. 定位：AI 时代最适合 C 开发的语言

核心价值：

- 写起来像现代语言（namespace / trait / 组合）
- 编译出来是纯 C（零依赖、全平台可用）
- 编译器兜底 C 的繁琐和易错点（头文件、命名冲突、内存释放）
- AI 生成代码的正确率大幅提升（单文件维护、编译期检查、无宏）

### 2. 设计原则

#### 2.1 机械映射，零中间层

CT 调用编译后**直接对应 SDK 函数调用，零中间层、零语法糖**，保证反编译后的代码与手写 C 高度一致：

```c
// CT 源码
HAL::UART::huart1.send(data, len);

// 编译产物（直接对应）
HAL_UART_Transmit(&huart1, data, len, HAL_MAX_DELAY);
```

不引入任何运行时抽象层。CT 代码与生成 C 代码之间是一一对应关系。

#### 2.2 libc 直接透传

`malloc` / `free` / `printf` / `fopen` / `memcpy` / `strlen` 等标准库函数不封装、不映射，直接在 CT 中透传调用。理由：

- 每个 C 程序员都认识这些名字
- 映射后不改变任何语义，纯属多一层名字
- 编译产物就是直接调 libc，零开销

只抽象「各平台差异大、概念相同」的部分（见下节）。

#### 2.3 无宏、无条件编译

底层平台映射由厂商提供的 `ct_platform.h` 承担（宏只出现在那里），CT 业务代码不接触宏。CT 本身不引入条件编译，降低人和 AI 的出错率。

#### 2.4 编译期兜底

类型错误、未释放变量、namespace 引用错误由编译器直接报错，而不是留到运行时。泄漏警告列表**已在 Phase 4 用 CT 落地**（text / JSON 两种格式，`--diagnostics` 切换），用于帮助开发者（和 AI）快速定位遗漏。

### 3. 嵌入式切入策略

#### 3.1 标准外设 trait

聚焦嵌入式场景下「标准库不够用或行为不同」的部分，定义 5-8 个核心 trait 覆盖 80% 需求：

| 功能 | 标准库问题 | CT 抽象 |
|------|-----------|---------|
| 日志输出 | `printf` 需重定向 | `trait Logger` → `log(char *msg)`，映射到 UART / RTT / SWO |
| 时间 | `time()` 无 RTC | `trait Clock` → `now()` / `delay_ms(int)`，映射到硬件定时器 |
| 内存分配 | 裸机无堆或堆太小 | `trait Allocator` → `alloc(int)` / `dealloc(void *)`，映射到堆 / 池 / 静态 |
| 存储 | 无文件系统 | `trait Readable` / `Writable` → `read(buf, len)` / `write(data, len)`，映射到 Flash / SPIFFS |
| 随机数 | `rand()` 无熵源 | `trait Random` → `random()`，映射到硬件 RNG |
| 网络 | — | `trait Connectable` → `connect()` / `send()` / `recv()` |

#### 3.2 厂商 `ct_platform.h` 模型

编译器按「标准外设接口」生成 `ct_xxx()` 调用，用户（或芯片厂商）通过宏将其映射到具体平台函数：

```c
// ct_platform.h（厂商提供，一次编写）
#define ct_uart_send(h, d, l)    HAL_UART_Transmit(h, d, l, HAL_MAX_DELAY)
#define ct_gpio_set(p, n, v)     HAL_GPIO_WritePin(p, 1<<(n), (v) ? GPIO_PIN_SET : GPIO_PIN_RESET)
#define ct_delay_ms(ms)          HAL_Delay(ms)
```

完整调用链：

```
CT 编译器 → 生成 ct_xxx() 调用（标准名字）
      ↓
ct_platform.h（厂商提供，一次编写）→ 宏映射到具体 SDK
      ↓
最终编译为纯 C，跟手写一样
```

**编译器永远生成标准名字，平台差异全由 `ct_platform.h` 消弭。** 宏映射的优势：零函数调用开销、用户完全控制映射目标、不需要 vtable、编译期分发、反编译友好。

开发者只写 CT 标准接口，不感知平台差异。换平台 = 换 `ct_platform.h`，业务代码零改动；厂商写几十行宏即可让自家芯片兼容 CT 生态。

**新增一个平台适配的方式**（多文件落地后生效）：在 `platform/` 下添加 `ct_platform_<chip>.h`，只写宏映射、不需要改编译器，并附最小示例（`uart.h.ct` + `gpio.h.ct`）。

### 4. AI 编程友好性

- **编译器生成头文件**：AI 只需维护一份 `.h.ct` 的逻辑正确性，编译器自动生成 `.h` + `.c`，不存在「改了实现但忘了更新声明」的不一致问题。
- **import 替代手动 `#include`**：AI 不需要推断头文件路径、不需要处理 include 顺序和守卫，`import HAL::UART` 由编译器解析。
- **不接触宏**：宏收敛在厂商的 `ct_platform.h` 中（见 2.3）。
- **编译期检查兜底**：见 2.4。

### 5. 愿景

成为嵌入式领域的事实抽象层：

- 开发者学一次 CT 标准接口，写一次代码，所有芯片通用
- 厂商写几十行宏，就能让自家芯片兼容 CT 生态
- 编译器 + trait + namespace 把 C 的「管理问题」变成「编译器问题」
