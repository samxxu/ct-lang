# C Shim 契约（DOC-91）

> 中文
>
> **适用对象**：手写 C shim（`<base>.shim.h` / `<base>.shim.c`）、`.m.ct` 静态映射单元、
> 裸机板级适配（含 ISR 与 DMA）。**不覆盖**：编译器生成物的内部 ABI（[§4.57](language-spec.md#457-c-abi-静态库ct-build---libphase-39仅-ct-ast)
> `--lib` 另行规定）、C++、厂商 SDK 全量兼容。
>
> **权威关系**：C 边界与 strict 规则以 [language-spec §4.66](language-spec.md#466-c-边界c-boundary-与-shimphase-65仅-ct-ast)
> 为准；本文只规定 shim 作者必须遵守的命名、所有权、错误码、上下文、ABI 与测试义务。
> 两处冲突时以语言规范为准，并修正本文。
>
> **证据等级**：host mock 与 Renode 冒烟**不等于**真板；DMA 真搬运仍归
> [TEST-22](../issues/testing/test22-dma-real-transfer-hardware-gated.md)（hardware-gated）。
> 本文不新增语言关键字，`isr_safe` / `no_alloc` / `no_block` 只是注释标签。

## 1. 文件与命名

| # | 条款 | 判据 |
| --- | --- | --- |
| N-1 | shim 与映射单元**同目录、同基名**：`<base>.m.ct` + `<base>.shim.h` + 可选 `<base>.shim.c`；`.shim.c` 存在则 `.shim.h` 必须存在 | `a shim source needs a matching .shim.h` |
| N-2 | 只有 `.m.ct` 探测 shim；`.h.ct` 的姊妹 `<base>.shim.h` 自动进公开头与 `-I` | [§4.10](language-spec.md#410-mapphase-11-新增--sh-20-扩展仅-ct-ast)、[§4.66](language-spec.md#466-c-边界c-boundary-与-shimphase-65仅-ct-ast) |
| N-3 | 函数名 `<domain>_<verb>`；板级公共入口用 `board_*`（`board_init` / `board_idle` / `board_dma_submit`）。外设用 `uart_*` / `dma_*` / `clock_*`；既有样例按原样登记，不重命名 | 同一 shim 内前缀一致；导出名不得撞下文 N-4 |
| N-4 | shim 导出名不得占用 Ct 保留面：`ct_*`、`_ct_*`、`core_*`、`std_*`、`String_*`、`Str_*`、`Vec_*`、`Map_*`、`Result_*`、`*_iface`、`*_vtbl`、`*_Drop_drop`、`main` | 生成物与 Ct 运行时符号不得被遮蔽 |
| N-5 | 头文件必须有 include guard（`<BASE>_SHIM_H`）、可被 C99 单独包含；只 include C 头，不 include `.h.ct` 或生成物 | `cc -std=c99 -fsyntax-only` 能单独通过 |
| N-6 | shim 头不得出现 Ct 内部类型：`Str` / `String` / 切片 / `box<T>` / `Vec` / `Map` / `Option` / `Result` / 接口值 / vtable / `own` | 越界类型一律改成 C 标量、`const char *` + 长度、或 opaque `struct` |
| N-7 | 字符串跨边界：C 侧用 `const char *` + `size_t len`，不假设 NUL 结尾；Ct 侧只有 `cstr()` 是显式出口，`.data` 直传是硬错 | [§4.70](language-spec.md#470-string--strutf-8-owning-与借用phase-80仅-ct-ast)、`test/ast/p80_cstr` |
| N-8 | strict 下 `.ct` / `.h.ct` 只允许 `#include "<本单元>.shim.h"`；`extern` 原型、裸 C 声明、函数式宏、`#ct-raw` 均硬错，出口是 `.m.ct` 或 `.shim.c` | [§4.66](language-spec.md#466-c-边界c-boundary-与-shimphase-65仅-ct-ast)；`test/ast/p65_include.sh`、`p65_raw_extern.sh` |

**strict 是护栏，不是沙箱。** shim 的内容、`--ldflags` 外链的 `.c` 仍可绕过文件边界
（D65-8）。因此 N-5…N-7 是**作者义务**，不是编译器保证。

## 2. 所有权

每个跨边界的指针/长度/句柄都必须在 shim 头里用注释标出下列三种之一，缺注释即视为未定义：

| 标注 | 含义 | 谁负责释放 |
| --- | --- | --- |
| `/* borrow */` | 只在本调用期间读/写 | 调用方；shim 不得保存、释放或跨线程使用 |
| `/* transfer-in */` | 调用返回后归 shim/驱动所有 | shim；Ct 侧不得再碰，直到约定的归还点 |
| `/* transfer-out */` | 调用返回后归 Ct 所有 | Ct；必须用配对的 `<domain>_free` / `release`，禁止直接 `free()` |

| # | 条款 | 判据 |
| --- | --- | --- |
| O-1 | `const` 只表示 shim **不写**；带写操作必须写 `T *`，并在注释里写明写入长度 | 头文件签名与注释一致 |
| O-2 | 长度一律显式传参，不以 NUL 或哨兵值推导；返回长度用 out 参数，不用 `-1` 兼作“出错” | 见 §3 |
| O-3 | 借用视图（`Str`、切片、`box.at()`、`Map.get()` 结果）不得跨过 shim 调用保存；需要跨界先 `cstr()` 或复制成 owning 句柄 | [§4.70](language-spec.md#470-string--strutf-8-owning-与借用phase-80仅-ct-ast) |
| O-4 | `transfer-out` 的返回值必须配一个释放函数；`pkt_open` ↔ `pkt_free`、`board_alloc` ↔ `board_free`，名称成对且在同一头文件声明 | `examples/tour/15_memory/manual_shim` |
| O-5 | 借用视图返回（`pkt_peek`）不增加引用计数，调用方不得释放；释放后原句柄悬垂 | `examples/tour/15_memory/manual_shim_wrong` 为负例 |
| O-6 | shim 自己 `malloc` 的隐藏缓冲，只能由 shim 的释放函数拆解；Ct 侧 `free(p)` 是违约 | 同上负例 |
| O-7 | 全局/静态状态归 shim 所有，Ct 侧不得假设其线程安全；跨任务共享需在头注释声明锁或单线程约束 | 头注释 `/* ctx: ... */` |
| O-8 | Ct 的 `own` / `Drop` 不会自动调用 shim 的释放函数，除非包装类型显式实现 `impl Drop` | [§4.9](language-spec.md#49-autodropphase-5-新增仅-ct-线) |

## 3. 错误码

| # | 条款 | 判据 |
| --- | --- | --- |
| E-1 | C 返回值用 `int` status：`0` 成功，负值 `BOARD_E_*`；不得把合法值域与错误码叠在同一个数上（长度、索引、句柄值都不做哨兵） | 头文件给出 `#define BOARD_E_*` 与含义 |
| E-2 | `NULL` 只在“无对象”本身是合法状态时返回；若 `NULL` 也代表失败，必须另有 status 或 out 参数区分 | 头注释写明 `can be NULL` |
| E-3 | `errno` 在 shim 内**立即**捕获并转成 `BOARD_E_*`；不得把 `errno` 留给调用方读，也不得跨调用保留 | `test/bindings/posix-socket/posix/socket.shim.h` 的 `ct_sock_errno` |
| E-4 | 可恢复错误不得用 `abort()` / `longjmp()` 表达；`abort()` 只用于违反不变量 | 错误路径返回 status |
| E-5 | Ct 侧包装在 `.h.ct` 里把 status 转成 `Result<T, CtError>`；`Result` 不跨 C ABI，C 侧看不到 `Result` | [§4.61](language-spec.md#461-return-err-载荷类型契约phase-43仅-ct-ast)、[§4.62](language-spec.md#462-后缀--错误传播phase-44仅-ct-ast)；`examples/45_error_return_contract` |
| E-6 | 错误码数值只追加、不复用；删除/改义必须 bump shim 的 ABI 版本（§6 A-5） | 头文件版本宏 |

**转换边界一句话**：C 侧只传“状态 + out 参数”，Ct 侧在 `.h.ct` 里翻译成 `Result`；
不要让 `Result`、`String` 错误消息或异常穿过 shim 边界。

## 4. DMA / 异步：五条硬条款

以下五条是**硬条款**，不是建议。违反即 shim 契约失败，不得以“测试没炸”为由放行。

| # | 条款 | 含义 |
| --- | --- | --- |
| D-1 | **提交即转移** | `board_dma_submit(buf, len, cb, ctx)` 返回后，`buf` 归驱动所有；Ct 侧不得 `release`、重分配、写入或移动 buffer，直到完成回调返回 |
| D-2 | **完成即归还** | 完成回调返回后所有权回到 Ct；只有此时才允许释放、复用或再次提交 buffer。回调在 ISR 里时，“归还”只表示所有权状态，释放必须延后到任务上下文 |
| D-3 | **回调上下文必须声明** | 每个回调在头文件里标 `/* ctx: isr */` 或 `/* ctx: task */`；未声明视为 `task`，ISR 不得调用未标注 `isr` 的入口 |
| D-4 | **借用视图不得跨提交点** | 不得把 `Str`、切片、`box.at()`、`Map.get()` 的借用视图保存到提交之后；需要跨异步的数据必须是 owning 句柄，且寿命覆盖到完成回调返回 |
| D-5 | **完成后才可释放** | 回调返回前释放/复用 buffer 是 use-after-free；回调返回后先读 status，再决定复用还是释放；错误路径同样在回调里归还所有权 |

**所有权状态机**

| 时点 | buffer 归属 | Ct 侧允许 | Ct 侧禁止 |
| --- | --- | --- | --- |
| 调用 `board_dma_submit` 前 | Ct | 读、写、释放 | — |
| submit 返回到回调返回前 | 驱动 | 读只读元数据、投递事件 | `release`、重分配、写入、移动、保存借用视图 |
| 回调返回后 | Ct | 释放、复用、按 status 处理错误 | 把同一 buffer 再提交给未完成的传输 |

**回调签名与语义**（建议形态；具体名字由 shim 定，责任不变）：

```c
/* ctx: isr */
typedef void (*board_dma_done)(void *ctx, int status);

/* transfer-in: buf 在返回后归驱动；完成回调返回后归还。
   ctx: task（提交本身可在任务上下文调用） */
int board_dma_submit(void *buf, size_t len, board_dma_done cb, void *ctx);
```

- status 复用 §3 的错误码；`0` 表示传输完成，负值表示错误。
- 提交失败（返回负值）时**没有发生转移**，buffer 仍归 Ct；不得调用回调。
- 回调必须恰好调用一次；不得在回调里再次提交同一个 buffer。
- ISR 回调里只做：读/写 `volatile` MMIO、定长拷贝、置/清标志、投递事件；
  **禁止**分配、阻塞、`Drop`、引用计数释放、`printf`、锁、`Result` 构造。
- 需要延后处理时只投递事件，由任务上下文释放/复用。

**证据边界**：`test/ast/p67_dma.sh` 只证明 DMA1 Stream6 的 `PAR/M0AR/NDTR/CR`
描述符写入与读回一致（EN 保持 0，**不声称任何字节被搬走**）；Renode 的 DMA 模型不保证数据流。
真搬运仍归 TEST-22，本文只约束 API 责任。

## 5. 上下文：ISR / 任务 / 启动

上下文用注释标签表达，**不新增语言关键字**，编译器不校验：

```
/* ctx: boot, no_alloc */         启动阶段；禁止阻塞，分配能力由平台声明
/* ctx: task */                   任务上下文；可按文档分配/阻塞
/* ctx: isr, no_alloc, no_block, isr_safe */   ISR；只允许有界、非阻塞操作
/* ctx: any */                    与上下文无关的纯函数
```

| # | 条款 | 判据 |
| --- | --- | --- |
| C-1 | 每个 shim 入口在头文件声明处标一个 `ctx:`；回调另标自己的上下文 | 头注释可被 grep 到 |
| C-2 | `boot` 默认 `no_block`；有堆分配时必须显式写 `alloc: heap`，且平台分配器已初始化 | 启动路径不调用调度器 |
| C-3 | `task` 可以分配/阻塞，但必须在注释里写上限或“可阻塞”；不得从 ISR 调用未标 `isr` 的 `task` 入口 | 调用图单向 |
| C-4 | `isr` 允许集：`volatile` MMIO 读写、定长内存拷贝、标志位、事件投递、返回；禁止集见 D-4 | 代码审查 + ASan/真板证据 |
| C-5 | ISR 里不得 `Drop` / `retain` / `release` 引用计数；需要延后处理只投递事件 | [§4.70](language-spec.md#470-string--strutf-8-owning-与借用phase-80仅-ct-ast) 的异步边界 |
| C-6 | `isr_safe` / `no_alloc` / `no_block` 是**文档标签**，不是类型系统承诺；编译器不证明，证据由测试与真板兜底 | [§4.70](language-spec.md#470-string--strutf-8-owning-与借用phase-80仅-ct-ast) |

**提交点检查**：调用 `board_dma_submit` 之前，Ct 侧必须确认 buffer 是 owning 句柄或
静态/栈上且寿命覆盖回调；不能把 `Str` 的 `{ptr,len}`、切片视图或临时 `String` 的
`.data` 直接交给异步传输。

## 6. ABI

| # | 条款 | 判据 |
| --- | --- | --- |
| A-1 | 跨边界整数用 `<stdint.h>` 固定宽度（`int32_t` / `uint32_t` / `uint64_t`）；不要用 `int` / `long` 表达寄存器、描述符、协议字段 | 头文件无裸 `long` 字段 |
| A-2 | `size_t` 只用于内存长度；持久化/线格式长度用固定宽度并做范围检查 | 长度参数类型一致 |
| A-3 | 句柄用 opaque `struct <domain>_handle *`；布局定义留在 `.shim.c`，头文件不暴露字段 | 调用方不能 `sizeof(*h)` |
| A-4 | 对齐：DMA/MMIO buffer 按外设要求对齐（`_Alignas` 或链接脚本保证）；共享 ABI struct 不加 `packed`/位域；不假设 padding 为 0 | `_Alignas` 透传见 [§4.35](language-spec.md#435-c11-对齐与泛型选择ct-ast) |
| A-5 | 调用约定用 C 默认；`__attribute__((…))` 只允许在 shim/`#ct-raw` 里，且必须能由目标 C 编译器接受；不承诺 C++ ABI | [§4.36](language-spec.md#436-gnu-__attribute__ct-ast) |
| A-6 | 版本：`#define <BASE>_ABI_VERSION <n>` + `uint32_t <domain>_abi_version(void)`；同 major 只追加（结构体字段追加在尾部、函数只增不删），改名/删字段/改语义 bump major | 版本函数有实现并被测试调用 |
| A-7 | 变参只在有明确文档时跨边界；trait 方法不能变参（vtable 槽固定），变参 C API 必须由 shim 包成固定参数 | [§4.22](language-spec.md#422-变参函数ct-ast)、[§4.31](language-spec.md#431-变参函数指针ct-ast) |
| A-8 | 共享 struct 不要含 vptr/接口值；`use Trait` 的 Ct struct 布局与纯 C struct 不同，跨 ABI 必须用显式字段镜像 | [§4.2](language-spec.md#42-struct--use--追加-vptr-字段)、`test/bindings/README.md` §4 |

## 7. 测试与登记

### 7.1 host mock（无硬件，可重复）

```bash
# owned vs borrowed：shim.c 拥有 malloc，Ct 只用 pkt_open/pkt_free
CT_C_BOUNDARY=allow CT=$(command -v ct) bash examples/tour/run.sh 15_memory/manual_shim
# 期望：ok 15_memory/manual_shim、ok 15_memory/manual_shim_wrong，退出码 0

# header-only 与 .shim.c 两种形态
CT_C_BOUNDARY=allow CT=$(command -v ct) bash examples/tour/run.sh 08_shim
# 期望：ok 08_shim/header_inline、ok 08_shim/compiled_source，退出码 0

# strict 只允许本单元 shim；同名 base 两个 shim 是硬错
bash test/ast/p65_include.sh "$(command -v ct)"     # OK p65/include
bash test/ast/p65_hdr_shim.sh "$(command -v ct)"    # OK p65/hdr-shim
```

`CT_C_BOUNDARY=allow` 只用于 host mock：`examples/tour/run.sh` 会 `cd` 到案例目录，
路径不再带 `examples/` 前缀；生产 shim 不应靠这个开关绕过 strict。

### 7.2 Renode 冒烟（不新增硬件依赖）

```bash
sh test/baremetal-renode/run.sh "$(command -v ct)"
# 0 通过；77 跳过（缺少 arm-none-eabi / Renode / 宿主权限）；1 失败
# 通过时 UART 逐字节等于 test/baremetal-renode/prog.expected.out：
#   boot ok / clk=168 / btn=0 / dma=1 / tick=3
```

Renode 的 USART 不采样波特率，按键默认释放；这是 pre-pilot 证据，不是真板结论。
DMA 描述符可单独核对：

```bash
sh test/ast/p67_dma.sh "$(command -v ct)"   # OK p67/dma（只验寄存器，不验搬运）
```

### 7.3 shim 变更回归清单

| # | 检查 | 命令/证据 |
| --- | --- | --- |
| R-1 | 命名、guard、同基名、`.shim.c` 有配对头 | 本文 N-1…N-6；`p65_hdr_shim.sh` |
| R-2 | 头文件不含 Ct 内部类型；字符串用 `const char *` + 长度 | 人工审查 + `cc -std=c99 -fsyntax-only` |
| R-3 | 每个指针/句柄有 `borrow` / `transfer-in` / `transfer-out` 标注 | 头文件 diff |
| R-4 | status 与 `errno` 立即转换；`Result` 只在 `.h.ct` | `test/bindings/posix-socket`、`examples/45_error_return_contract` |
| R-5 | 每个入口有 `ctx:`；ISR 无分配/阻塞/`Drop` | 头注释 + 代码审查 |
| R-6 | DMA 路径满足 D-1…D-5；提交后无借用视图 | host mock + `p67_dma.sh` + TEST-22 边界声明 |
| R-7 | ABI 版本已 bump（有删改时）；共享 struct 无 vptr/位域/packed | A-1…A-8 |
| R-8 | host mock 与 Renode（或记录 77 skip）都跑过；文档链接仍可解析 | `tools/check.sh g4` |

### 7.4 已登记 shim

| shim | 形态 | 对应条款 |
| --- | --- | --- |
| [examples/tour/08_shim/header_inline](../examples/tour/08_shim/header_inline/csv/fields.shim.h) | header-only、`static inline` + 宏 | N-1、N-5、R-1 |
| [examples/tour/08_shim/compiled_source](../examples/tour/08_shim/compiled_source/tick/tick.shim.c) | `.shim.c` 持状态 | N-1、O-7、R-1 |
| [examples/tour/15_memory/manual_shim](../examples/tour/15_memory/manual_shim/pkt/pkt.shim.h) | 隐藏 payload、owned/borrowed | O-4…O-6、R-3 |
| [examples/47_chain_factory/src/http](../examples/47_chain_factory/src/http/http.shim.h) | `.m.ct` + header-only 适配层 | N-1、N-6 |
| [test/baremetal-renode](../test/baremetal-renode/board.h) | 裸机 `board_*` / `uart_*` / `dma_*`，SysTick ISR | N-3、C-2…C-5、D-1…D-5 |
| [test/bindings/posix-socket](../test/bindings/posix-socket/posix/socket.shim.h) | POSIX 包装、`errno` 立即捕获 | E-2、E-3 |

## 8. 禁止事项（一页）

1. 在 `.ct` / `.h.ct` 里写 `#include <...>`、`extern` 原型、函数式宏或 `#ct-raw`（strict）。
2. 把 `Str` / `String` / 切片 / `box` / `Vec` / `Map` / 接口值放进 shim 头。
3. 用 `NULL`、`-1` 或 0 长度兼作错误与合法值。
4. 提交 DMA buffer 后 `release`、重分配、写入或移动；在 ISR 回调里释放。
5. 把借用视图保存到异步完成后；把 `.data` 当 NUL 结尾字符串。
6. 用 `free()` 释放 `transfer-out` 句柄；释放 `borrow` 视图。
7. 在 shim 头里暴露 ABI struct 布局、位域、`packed` 或 C++ 类型。
8. 改 shim 语义却不 bump ABI 版本；改 strict 边界却不走语言提案。
