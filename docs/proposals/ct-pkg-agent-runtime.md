# 提案：ct-pkg `std` 的 Agent 内核运行库

| 项 | 值 |
| --- | --- |
| 状态 | **提案**（2026-11-12；供 ct-pkg 维护者评审，非 ct 仓库立项） |
| 范围 | ct-pkg `std` 包族的四个新模块 + 一份回调契约 |
| 依据 | ct v0.30.0 实跑（`Vec`/`Map`、trait 接口值、显式 `retain`/`release`、非逃逸闭包）；ct 侧规划 Phase 34/36/39 |
| 不做 | borrow checker、GC、异常、隐藏分配 |

## 0 结论

建议 ct-pkg 先落 **4 个包 + 1 份契约文档**，不要求 ct 改语言：

| 包 | 一句话 | 何时可做 |
| --- | --- | --- |
| `std/arena` | 会话级 bump 分配器，统一释放 | **今天**（纯库） |
| `std/sync` | mutex / cond / atomic / thread 的薄封装 | **今天**（C 头直接可用） |
| `std/result` | `Option` / `Result` 的再导出与 helper | 依赖 ct Phase 34 |
| `std/string` | shim 的 CT 句柄 `Str` 与可变 builder | 依赖 ct Phase 34（固有方法）+ 36（Drop/元素协议） |
| `std/callback` | C 回调边界的所有权契约（文档 + 透传 helper） | **今天**（文档先落地） |

理由：Agent 内核的 70% 代码在拼 JSON/SSE、处理工具失败、跨回调保数据。ct 已经给了 `Vec`/`Map` 与显式引用计数，但**会话级生命周期**和**回调边界**没有标准答案；这两件事最适合放在 ct-pkg，而不是继续加语言特性。

## 1 背景与约束

ct 的模型是「C 超集 + trait 接口值 + 显式 `retain`/`release` + 无 GC」：

- 没有 borrow checker；`own` 只做局部 AutoDrop，不跨函数/回调。
- 闭包是非逃逸的栈快照；闭包当 trait 方法实参今天有缺陷（ct 仓库 SH-65 / SH-67）。
- `Vec<T>` / `Map<K,V>` 在 `lib/std`，元素不自动 retain/release；容器释放只放缓冲。
- Z1 零运行时、Z2 零第三方依赖、Z6 1.0 兼容冻结。

因此本提案的原则是：**库先把生命周期说清楚，语言只补最小缺口**。

## 2 包设计

### 2.1 `std/arena`

```c
pub struct Arena {
    char *base;
    int cap;
    int used;
}

pub Arena *arena_new(int cap);
pub void *arena_alloc(Arena *a, int size, int align);
pub void arena_reset(Arena *a);      /* 复用缓冲，不 free */
pub void arena_release(Arena *a);    /* 释放整块 */
```

- 分配只 bump，不单独 free；`arena_reset` 后所有旧指针失效。
- 契约：**指向 arena 的指针不得逃逸出 arena 的作用域**；跨 arena 引用是调用方错误，编译器不检查（ct 没有生命周期分析）。
- 建议用法：一个 session 一个 arena；消息历史、工具结果、上下文缓存都从它分配；会话结束 `arena_release`。
- 与 `Vec` 的关系：`Vec` 的缓冲仍走自己的 `retain`/`release`；不要把 `Vec.data` 指向 arena（`release` 会 `free` 它）。需要 arena 版容器时另做 `ArenaVec`，不混用。

### 2.2 `std/sync`

```c
pub struct Mutex;                    /* 不透明，内部 pthread_mutex_t */
pub Mutex *mutex_new(void);
pub void mutex_lock(Mutex *m);
pub void mutex_unlock(Mutex *m);
pub void mutex_release(Mutex *m);

pub struct Thread;                   /* 不透明，内部 pthread_t */
pub Thread *thread_spawn(int (*fn)(void *), void *arg);
pub int thread_join(Thread *t);
```

- 直接映射 `pthread.h` 与 C11 `_Atomic`；ct 是 C 超集，`#include` 即可，不需要语言支持。
- 契约：**共享状态一律放进 `Mutex` 保护的结构体**；ct 不做 `Send`/`Sync` 编译期检查，跨线程传裸指针由调用方负责。
- 不在库里做线程池/协程；Agent 内核通常只需要「网络线程 + UI 线程 + 一个锁」。

### 2.3 `std/result`

ct Phase 34 会在 `lib/std` 提供 `Option<T>` / `Result<T,E>`（泛型 struct，不是泛型 enum）。本包只做：

- 再导出，避免两套同名类型（同名会触发 ct 的 `vendor/std` 遮蔽告警）。
- helper：`option_some/none`、`result_ok/err`、`unwrap_or`、`release`。
- **不做** `?` / `try` 语法；失败处理显式写 `if (!r.ok) { … }`。ct 侧 Phase 38 只做 `defer`，不做 `errdefer`。

在 Phase 34 落地前，包内可以先放一份兼容实现，但**不要**与 `lib/std` 的类型同时暴露；用 `vendor` 目录隔离，等 P34 后切回再导出。

### 2.4 `std/string`

`Str` 的规范位置就在本包，不在 `lib/std`。它是对既有 shim 的不透明句柄，buffer 由 shim 拥有；CT 层只加方法与所有权：

```c
pub struct Str { CStr *h; } use Drop;

impl Str {
    Str retain();          /* 新句柄，独立 release；适配层决定 refcount 或深拷贝 */
    int release();         /* 返回剩余引用数 */
    int len();
    Str slice(int start, int n);
    Str concat(Str other);
    int compare(Str other);
    const char *c_str();   /* 有效到 release */
}
```

**适配层契约**（`.shim.h` 必须提供）：

| 函数 | 语义 |
| --- | --- |
| `cstr_retain(CStr *)` | 返回可独立 `release` 的句柄；引用计数或深拷贝由实现决定 |
| `cstr_release(CStr *)` | 释放一个句柄，返回剩余引用数 |
| `cstr_len` / `cstr_data` / `cstr_slice` / `cstr_concat` / `cstr_compare` | 只读操作；`slice` 可复制或共享 |
| `cstr_c_str` | NUL 结尾，有效到 release；内嵌 `\0` 截断 |

- `retain`/`release` 必须是**固有方法**，否则 P31 元素协议不生效；这需要 P34 的非泛型固有方法。
- `Vec<Str>` 的 push/release 走 `retain`/`release`；是否 O(1) 取决于 shim 是否有引用计数。
- **按值拷贝不自动 `retain`**：`Str b = a;` 只复制句柄，要独立句柄必须 `a.retain()`；否则双重 `release`。
- 工厂函数返回的 `Str *` 不直接 `own`（`own` 只认 `malloc`/`calloc`），用显式 `release`，P38 后用 `defer`。
- `StrBuilder`（可变拼接）在 `Str` 稳定后加，内部复用 shim buffer，不引入第二套实现。
- 不做隐式转换、不做 GC 字符串；`Str::from("...")` 是显式复制。
- JSON/SSE 的拼接先用 `StrBuilder`；解析仍建议走 cJSON 这类成熟 C 库，不在 std 里重写。

### 2.5 `std/callback`

这是一份**契约文档**，不是包装层。建议写清五条：

1. C 回调的入参（buffer、userdata、event）默认是 **borrow**，生命周期到回调返回为止。
2. 要在回调返回后继续用，必须显式拷贝：拷进 arena 或 `Str`/`Vec` 并取得所有权。
3. 不得把回调入参的裸指针存进全局/长生命周期结构体。
4. 闭包是非逃逸的；跨 C 边界请用 `(fn, env)` 两词 ABI，不要依赖闭包字面量直接进 trait 方法（SH-65 / SH-67）。
5. 回调内不得 `longjmp`/抛异常穿过 C 栈；错误用返回值 + 输出参数。

配套 helper（可选）：

```c
/* 把回调入参拷进 arena，返回的指针活到 arena reset */
pub char *callback_copy(Arena *a, const char *data, int n);
```

## 3 与 ct Phase 的依赖

| 包 | 依赖 | 依赖未落地时 |
| --- | --- | --- |
| `arena` | 无 | 今天可做 |
| `sync` | 无 | 今天可做（`pthread.h` / `_Atomic`） |
| `callback` | 无（仅受 SH-65/67 影响） | 今天可写文档 |
| `result` | Phase 34（`Option`/`Result`） | 先放 `vendor/` 兼容实现，不导出同名类型 |
| `string` | Phase 34（非泛型固有方法）+ Phase 36（Drop / 元素协议） | 今天可先用 shim 函数 + 显式 `free`；P34 后挂方法，P36 后接 `Drop` |
| ABI 导出 | Phase 39（`ct build --lib`） | 今天用 `cc -c` + `ar` 手工打包 |

## 4 版本与兼容

- 包版本独立；不在包里写 ct 版本号，只写「最低 ct 版本」。
- 在 1.0 冻结（Z6）前，`arena`/`sync`/`callback` 的 API 尽量小，避免反复迁移。
- ABI 承诺等 Phase 39 的 `<name>.abi.h` 落地后再做；今天不承诺结构体布局跨版本稳定。

## 5 非目标

- 不做 borrow checker 式 API（没有生命周期参数可写）。
- 不做 GC、引用计数智能指针、隐藏分配。
- 不做异常/`try`/`?`；错误处理显式。
- 不做跨平台线程抽象之外的调度器/协程。
- 不在 std 里重写 JSON/HTTP；继续用 cJSON/libcurl 这类 C 库。

## 6 建议交付顺序

1. `std/arena`（今天，纯库，收益最大）
2. `std/sync`（今天，纯库）
3. `std/callback`（今天，文档 + 一个 copy helper）
4. `std/result`（等 Phase 34）
5. `std/string`（等 Phase 34 + 36）
6. ABI 打包（等 Phase 39）

## 7 需要 ct-pkg 决定的三件事

1. `result` 是**再导出** `lib/std` 的类型，还是包内自带实现？`string` 已决定由本包定义（`Str` 是 shim 句柄，见 §2.4），不再走再导出。
2. `arena` 是否提供 `ArenaVec`（arena 上分配的动态数组）？提供会更顺手，但要自己实现扩容与释放规则。
3. `sync` 的线程 API 用 `pthread` 还是 C11 `thrd_*`？前者成熟，后者更标准；ct 两条都能 `#include`。

---

## English summary

A proposal for ct-pkg `std` to add four runtime modules plus one callback contract for a long-session agent kernel:

- `arena`: a session-scoped bump allocator with `alloc / reset / release`; pointers never outlive the arena (a documented rule, not a compiler check).
- `sync`: thin wrappers over `pthread` and C11 `_Atomic`; shared state goes through an explicit `Mutex`; no `Send`/`Sync` compile-time checking.
- `result`: re-export the `Option` / `Result` types from ct Phase 34 and add helpers; no `?` or `try` syntax.
- `string`: define the length-carrying `Str` in this package as an opaque shim handle; ct Phase 34 adds inherent methods and Phase 36 adds `Drop` / element protocol. No buffer rewrite, no implicit concatenation.
- `callback`: a five-rule ownership contract for C callbacks (arguments are borrowed until return; copy into an arena to retain; use `(fn, env)` pairs rather than closure literals at trait-method boundaries).

The proposal deliberately does **not** ask for a borrow checker, a GC, exceptions or hidden allocation. It documents lifetime rules and relies on ct's explicit `retain` / `release`. Delivery order: `arena`, `sync`, `callback` today; `result` after Phase 34; `string` after Phase 34 + 36; ABI packaging after Phase 39.

