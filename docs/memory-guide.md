# CT 内存管理实践指南

> 中文

> **适用版本**：当前主线 **ct-ast**（`selfhost/ct-ast/main.ct`，版本号见 `ct -v`，不在此固定）。冻结的 L2 只作回归对照；
> 凡两者行为不同的地方，下文单独标注。
> **配套**：[language-spec](language-spec.md) §4.9（AutoDrop）与 §4.40（`borrow`）、[tutorial](tutorial.md) 第 8 节、
> [design/borrow.md](history/design/borrow.md)（`borrow` / `Handback`，**已落地**）。
> **一句话**：CT 把内存管理从「树形复杂度」压成「常数复杂度」，剩下的难点只有「谁拥有」这一件。

---

## 中文

### 0. 先记一句口诀

> **谁拥有，谁释放。**
> 不是「谁创建谁释放」——`create` / `own` / `borrow` 是三件事，而在 C 的语法里它们长得一模一样（都是个指针）。

CT 已经替你做了两件最难的事：

1. **嵌套递归释放**（`Drop` 自动下钻）
2. **作用域出口兜底**（`own` + AutoDrop）

你要做的只剩：**判断这个对象是不是你的。**

### 1. 四种对象，四种处理

| 对象在哪 | 要不要你管 | 怎么做 |
| --- | --- | --- |
| **栈上** `Box b;` | 不用管 | 函数返回自动回收；持有堆资源时靠 `Drop` |
| **静态 / 全局** `static Box b;` | 不用管 | 整个程序生命周期，从不释放 |
| **堆上，你独占** | 要 | **`own`**（作用域兜底）或 **`delete`**（提前释放） |
| **借来的** | **绝不要** | 什么都不做 |

第三行才是要花心思的地方，下面全部围绕它。

### 2. 场景一：独占的堆对象 → 用 `own`

```c
#include <stdlib.h>

struct Box { int n; } use Drop;

impl Drop for Box {
    void drop() { /* 释放它持有的资源，不要 free(self) */ }
}

int main(void)
{
    {
        own Box *b = malloc(sizeof(struct Box));
        b->n = 2;
    }                     /* → if (b) { Box_Drop_drop(b); free(b); } */
    return 0;
}
```

- **多个 `own` 按声明逆序释放**：先建的依赖后建的，顺序正确。
- **`own` 只接受 `malloc` / `calloc` 初始化**（见 §6 的工厂例外）。

> **出口释放的现状**（v0.16.0 起，[SH-33](../issues/selfhost/sh33-autodrop-return-no-inject.md) 已修）：
> AutoDrop 在作用域闭合 `}` 与**每个 `return` 之前**都注入释放，并**同时置空**：
>
> ```c
> int f(void) {
>     own Box *b = malloc(sizeof(struct Box));
>     b->n = 1;
>     return b->n;          /* 生成物：if (b) { Box_Drop_drop(b); free(b); b = 0; }  return b->n; */
> }
> ```
>
> 释放语句注入在分支内部，因此 `if (c) return 1;` 这类行内 `return` 同样生效。
> 把 `own` 放进块内仍是不错的**风格**（释放点更靠近使用范围），但**不再是必需**。

#### `own` 的硬约束（违反即编译期报错）

| 约束 | 违反时的消息 |
| --- | --- |
| 必须是**结构体指针** | `struct 'int' does not use trait 'Drop'`（非结构体类型没有 `Drop` 实现） |
| 必须由 `malloc` / `calloc` 初始化 | `'own' requires a malloc or calloc initialiser` |
| 该 struct 必须 `use Drop` | — |
| 只在**函数体内** | `'own' is only allowed inside a function body` |
| 不支持数组形态 | `'own' does not support arrays` |
| 闭合 `}` 必须在**行首** | `auto-drop requires the closing '}' at the start of a line` |
| `switch` 体内不允许 | `own is not supported inside a switch` |
| `static` 局部不允许 | `a static local cannot be 'own'` |

`return` 的行首要求**只在 L2 上成立**（逐行重写需要它）。ct-ast 对 `return` 位置**没有任何要求**：
释放注入在 `return` 之前，行内的 `if (c) return 1;` 也照样在分支内注入。

### 3. 场景二：想提前释放 → 用 `delete`

```c
Box *p = malloc(sizeof(struct Box));
p->n = 1;
delete p;      /* → if (p) { Box_Drop_drop(p); free(p); p = 0; } */
```

两个必须记住的行为：

1. **`delete` 会置空**。之后 `p == 0`，不需要再手写 `p = 0;`；实参不是左值（如 `delete get();`）
   时只释放、不赋值。
2. **`delete` 会取消 autodrop**，不会重复释放——所以 `own` + `delete` 混用是安全的

**典型误用**：对借来的指针 `delete`（§5），或对 arena 指针 `delete`（§8）。

### 4. 场景三：对象持有资源 → `Drop` 递归

这是 CT 消灭的最大痛点。以前要手写 `free(cfg->dev->buf->data); free(cfg->dev->buf); …`，
漏一层就泄漏、多一层就 double free。

```c
struct Buffer { char *data; } use Drop;
struct Device { struct Buffer *buf; } use Drop;
struct Config { struct Device *dev; } use Drop;

impl Drop for Buffer { void drop() { free(self->data); } }
impl Drop for Device { void drop() { delete self->buf; } }
impl Drop for Config { void drop() { delete self->dev; } }

int main(void)
{
    {
        own Config *c = malloc(sizeof(struct Config));
        c->dev = malloc(sizeof(struct Device));
        c->dev->buf = malloc(sizeof(struct Buffer));
        c->dev->buf->data = malloc(8);
        /* … 用 … */
    }                     /* 出口：Config → Device → Buffer → free(data) */
    return 0;
}
```

**要点**：

- `drop()` 里只释放**自己持有的资源**，不要 `free(self)`——外层会做
- 内层用 `delete` 触发下一层递归
- 难度从「管理一棵树」降到「管理根节点」
- 对外层仍用块内的 `own`（原因见 §2 的现状注记）

### 5. 场景四：借来的指针 → 什么都别做

```c
struct Context { struct Buffer *buf; };   /* 只是引用，不拥有 */

void render(struct Context *ctx)
{
    /* ctx 和 ctx->buf 都是借来的 —— 绝不能 delete */
    draw(ctx->buf);
}
```

判断标准很简单：**你有没有为它调过 `malloc`？没有，就不是你的。**

C 的语法不区分 own / borrow，CT 目前也没有语法标记——所以这靠**约定**（`borrow` 提案见 §15）。
建议在参数上标 `/* borrowed */`。

#### 5.1 正确的心智模型：是「拥有者」，不是「引用计数」

判断能不能释放时，问的不是「**还有几个指针指着它**」，而是：

> **还有没有人觉得自己该释放它？**

```c
int handle(void)
{
    own Request *r = malloc(sizeof(struct Request));
    parse(r);        /* r 传进去了，但 parse 只是借用 */
    render(r);       /* 同上，借用指针随栈帧消失 */
    return 0;
}
```

调用栈一层层退干净，回到 owner 手里时**中间的借用指针都随各自栈帧消失**。
所以「最终只剩一个 owner」跟「中间同时存在好几个指针」并不矛盾——它们都不拥有。

**结论：传给子函数本身是安全的，哪怕嵌套很多层**——只要那些子函数只是借用。

#### 5.2 唯一要防的：指针流进比当前作用域活得更久的地方

```c
Request *g_last;                    /* 全局，活得比谁都长 */

void store(Request *r)
{
    g_last = r;                     /* 存起来了 */
}

int handle(void)
{
    Request *r = malloc(sizeof(struct Request));
    store(r);                       /* 传参 —— 不算逃逸 */
    delete r;                       /* ← 释放后 g_last 变悬垂指针 */
    return 0;
}
```

**编译器不会报警。** 逃逸判定只认 `q = p;` 和 `return p;` 两种形态，**传参不在其中**；
而规范明确写了 `ct-ast does no cross-procedure reachability`——编译器不做跨过程分析，不知道 `store` 内部干了什么。

> **同层赋值能兜住，藏进被调函数就兜不住。**

#### 5.3 长生命周期对象：先建好，只借用

```c
static Logger g_logger;            /* 程序启动时建好，从不释放 */

void handle(void)
{
    g_logger.log("...");           /* 只是引用，绝不 delete */
}
```

CT 在语法上帮你挡了一道：`own` 只允许出现在函数体内，**文件作用域直接编译报错**
（`'own' is only allowed inside a function body`）——你不可能误把全局对象标成 `own`。

全局 / 静态对象天然「创建一次、活到程序结束、从不释放」，**不在内存管理机制的作用范围内**。

### 6. 场景五：所有权转移 → `own` 会自动让位

```c
Box *q = 0;
{
    own Box *p = malloc(sizeof(struct Box));
    q = p;                   /* p 以独立右值出现 = 逃逸，取消 p 的 autodrop */
}
```

触发取消的三种情况：

| 情况 | 后果 |
| --- | --- |
| `p = …;` 重新赋值 | 取消 autodrop |
| `q = p;` 作为独立右值 | 取消 autodrop（所有权转移） |
| `return p;` | 取消 autodrop（交给调用者） |

**不算逃逸**：`x = p->n;`、`x = p[0];` 这类读取字段 / 元素。

逃逸判定是**保守**的：宁可漏放（泄漏告警），不可错放（重复释放、释放借用对象）。
这是正确的取舍——**泄漏能告警，悬垂不能**。

### 7. 工厂与内存策略：把生命周期收敛到一处

工厂在 CT 的内存体系里不只是「有用」，而是把 trait、`Drop`、池化三块机制串起来的胶水：

| CT 机制 | 在工厂里扮演什么 |
| --- | --- |
| **trait** | 工厂返回接口类型，调用方不关心具体类型 |
| **Drop** | 销毁策略集中定义，而不是散落各处 |
| **Arena / 池** | 有界复用、批量回收的载体 |

> 工厂**造**不等于工厂**拥有**。谁拥有，看的是「返回之后还有没有人觉得自己该释放它」。

> 本节示例里的 `dial` / `close` / `pool_lookup` / `make` / `pool_add` / `conn_open_extra` 是**示意函数**，
> 换成你自己的实现即可；这里只演示所有权与释放责任。

#### 7.1 三种工厂形态

| 形态 | 内存策略 | 工厂是否保留指针 | 调用方契约 |
| --- | --- | --- | --- |
| **移交型** | 按需分配，用完即弃 | 否 | `delete`（**不能 `own`**，见 7.2） |
| **共享型** | 池化复用，长期持有 | 是 | **借用，绝不释放** |
| **有界型** | 维持 N 个，超出照建，压力回落回收 | 是 | **借用，绝不释放** |

后两种对调用方的契约完全一致——差别只在工厂内部策略。这正是 OO 的价值：
**调用方不需要知道你用的是哪一种。**

#### 7.2 移交型工厂：调用方就是拥有者

```c
struct Conn { int fd; } use Drop;

impl Drop for Conn {
    void drop() { close(self->fd); }
}

struct Conn *conn_open(const char *host)
{
    struct Conn *c = malloc(sizeof(struct Conn));
    c->fd = dial(host);
    return c;                    /* 所有权移交给调用者 */
}

int main(void)
{
    struct Conn *c = conn_open("a.b.c");
    /* … 用 … */
    delete c;                    /* → if (c) { Conn_Drop_drop(c); free(c); } */
    return 0;
}
```

> ⚠️ **这里不能用 `own`**：`own Conn *c = conn_open(...)` 会直接报
> `'own' requires a malloc or calloc initialiser`——初始化器必须是 `malloc` / `calloc` 调用，
> 函数返回值不行。移交型工厂的调用方**只能 `delete`**。
> 这条限制正是 `borrow` 提案里「`borrow` 的初始化器可以是任意表达式」的由来（§15）。

规则：**工厂造、工厂交，之后工厂不再持有指针** → 它就是普通对象，由调用者 `delete`。

#### 7.3 共享型工厂：调用方什么都不做

```c
struct Conn *conn_get(const char *host)   /* 从池里取，可能是复用的 */
{
    struct Conn *c = pool_lookup(host);
    if (c == 0) { c = make(host); pool_add(c); }
    return c;                    /* 借出，不是移交 */
}

int main(void)
{
    struct Conn *c = conn_get("a.b.c");
    /* … 用 … */
    return 0;                    /* 不 delete！工厂仍持有它 */
}
```

两条铁律：

- **移交型** → 调用方 `delete`
- **共享型 / 有界型** → **什么都不做**，纯借用

#### 7.4 命名约定：`borrow` 落地前唯一的防错手段

CT 目前没有语法区分 own / borrow，所以**工厂的两类必须靠命名分开**：

| 移交（调用方释放） | 借用（绝不释放） |
| --- | --- |
| `*_open` / `*_create` / `*_make` | `*_get` / `*_lookup` / `*_shared` / `*_borrow` |

头文件里再补一句注释，双重保险：

```c
struct Conn *conn_open(const char *h);   /* caller owns */
struct Conn *conn_get(const char *h);    /* borrowed, do not free */
```

#### 7.5 有界型工厂：用静态池实现淘汰策略

```c
struct ConnPool { struct Conn slots[10]; int used[10]; } use Drop;
static struct Conn *conn_open_extra(void);   /* 定义在本文件后面：CT 要求「先声明后用」 */

struct Conn *pool_acquire(struct ConnPool *p)
{
    int i;
    for (i = 0; i < 10; i++) {
        if (p->used[i] == 0) { p->used[i] = 1; return &p->slots[i]; }
    }
    return conn_open_extra();        /* 超出上限：照建，但不在池里 */
}

void pool_release(struct ConnPool *p, struct Conn *c)
{
    int i;
    for (i = 0; i < 10; i++) {
        if (&p->slots[i] == c) { p->used[i] = 0; return; }
    }
    delete c;                        /* 池外的临时对象，压力回落时回收 */
}

impl Drop for ConnPool {
    void drop() {
        int i;
        for (i = 0; i < 10; i++) {
            if (self->used[i]) { Conn_Drop_drop(&self->slots[i]); self->used[i] = 0; }
        }
    }
}
```

**注意这里的分野**：池内槽位（静态数组里）**从不 `free`**，只标记 `used`；
池外的临时对象才是真分配的，需要 `delete`。调用方拿到的可能是任何一种，**所以它一律不释放**。

> 实现提示：`impl` 体内**只能用 `self`**，写成 `p->used[i]` 会报
> `use of an undeclared variable`。`Conn_Drop_drop` 是 mangling 出的真实函数名，
> 在源码里直接调用是合法的（发射端会给出原型）；若它在定义之前被调用，需要自己补一行
> `static void conn_close(struct Conn *c);` 之类的原型。

#### 7.6 ⚠️ 底线：工厂本身必须是有界的

这是设计工厂时**唯一不可协商**的要求：

- 缓存只进不出 = **内存单调增长**
- 注册表从不清理 = 同上
- 而且这种泄漏**编译器查不出来**——对象都被「合法地」持有，不是没人释放

所以定策略时，**「上限 + 淘汰」是默认要求，不是可选优化**：

1. 有缓存就必须有**上限**
2. 有上限就必须有**淘汰策略**（LRU / 空闲超时 / 引用计数）
3. `Drop` 里要能一次性清空整个池（见 7.5 的 `ConnPool_Drop_drop`）

#### 7.7 嵌入式里的特殊价值

- **栈小**（几 KB）→ 大对象不能放栈，工厂统一管理堆 / 静态池
- **堆常缺** → 静态池（预分配 N 个槽）比 `malloc` 可靠得多
- **无碎片** → 固定大小槽位的池完全没有碎片问题
- **确定性** → 分配耗时固定，硬实时可用

所以嵌入式里**有界池化工厂应当是最推荐的形态**，而不是移交型。

### 8. 场景六：所有权不清晰 → Arena（提案，未落地）

> **状态**：提案。`selfhost/ct-ast/runtime/arena/Arena.h.ct` 目前只是**编译器内部的节点池**，
> 不是给用户用的库；下面的代码是**伪代码**，现在不能编译。

```c
/* 伪代码：Arena 尚未作为官方库存在 */
int handle(void)
{
    Arena a;
    arena_init(&a, 4096);

    Request *r = arena_take(&a, sizeof(struct Request));
    Buffer  *b = arena_take(&a, sizeof(struct Buffer));
    r->buf = b;

    parse(r);        /* 随便传五道，谁引用都不用管，也不用 delete */

    arena_reset(&a); /* 一次归零，完事 */
    return 0;
}
```

原理：bump 指针，一次加法完成分配；**从不逐个释放**，生命周期边界一到整块归零。
「该不该删」在 arena 下不是被解决，而是**问题消失了**。

> ⚠️ 现阶段的真实风险：`own` 硬性要求 `malloc` / `calloc` 初始化，所以 arena 对象**既不能 `own`
> 也不能 `delete`**。`delete` 生成的代码就是 `free(p)`——对 arena 指针调用就是 free 一块从未
> `malloc` 过的内存，**直接崩溃**。目前编译器识别不了「指针来自 arena」，只能靠命名区分。

Arena 的两个局限，别过度使用：

- **延迟释放**：对象要等 `reset` 才「死」。持有 **fd / 锁 / 硬件句柄**的对象**别放 arena**，这类仍用 `own` / `delete`。
- **不能单块回收**：长生命周期对象混在池里会浪费内存。

### 9. 决策表：一眼选对

```text
这个对象从哪来？
├─ 借来的（参数 / 全局 / 共享工厂 *_get）
│   └────────────────────→ 什么都不做，绝不 delete
├─ 移交型工厂（*_open / *_create / *_make）
│   └────────────────────→ delete（不能 own）
└─ 我 malloc 的
    ├─ 生命周期有明确边界（一次请求 / 一帧 / 一个连接）？
    │   └─ 是 ───────────→ Arena（待官方库；现阶段用静态池或 own）
    └─ 否（独占单个对象）
        ├─ 能撑到块出口吗？
        │   └─ 能 ───────→ 块内 own（零手写）
        └─ 需要提前释放 ──→ delete（会自动置空）
```

再补一条**释放前自检**：

```text
我要释放它了 —— 还有没有人觉得自己该释放它？
├─ 没有（中间都是借用，栈帧已退净） → 放心释放
└─ 有（被存进全局 / 长周期容器 / 共享工厂）→ 不该我释放
```

### 10. 常见陷阱清单

| 陷阱 | 症状 | 怎么躲 |
| --- | --- | --- |
| `}` 不在行首 | 编译期报错 `auto-drop requires …` | 让 `}` 单独一行 |
| `switch` 体内用 `own` | 编译期报错 | 挪到 switch 外，或改用 `delete` |
| **`goto` 跳出作用域** | **不触发释放，静默泄漏** | 别用 `goto` 跨过 `own` 声明 |
| **被调函数把指针存进全局** | **悬垂指针，无告警** | 别写这种函数；或调用方改用手动 `delete` |
| 对借来的指针 `delete` | double free | 参数写 `borrow` |
| 对共享工厂返回的对象 `delete` | double free / 破坏池 | 命名区分 `*_get` 与 `*_open` |
| 对工厂返回值用 `own` | 编译期报错 `requires a malloc or calloc initialiser` | 用 `delete` |
| **工厂缓存只进不出** | **内存单调增长，编译器查不出** | 有缓存就必须有上限 + 淘汰 |
| 对 arena 指针 `delete` | **立即崩溃** | arena 只 `reset`，不 `delete` |
| 泄漏告警当没看见 | 真泄漏 | 告警是保守的，别指望它猜 |

**两条最危险的**：

- **`goto`** —— 与 `own` 同源的静默失效
- **被调函数存全局** —— 唯一**无防护**的悬垂来源，因为编译器不做跨过程分析

### 11. 泄漏告警怎么用

```sh
$ ct leak.ct -o leak.c
leak.ct:20: warning: potential leak: 'leak' (Box*) allocated but never deleted

$ ct --diagnostics=json leak.ct -o leak.c    # 机器可读，写 stdout
```

- 是**告警不是错误**，不中断编译
- 路径敏感：条件 `return` 会判定
- 覆盖 `impl` 方法体
- **只报普通 `malloc` 指针**：`own` 变量登记了 autodrop，**不在泄漏分析的报告范围内**
  （所以顶层 `own` 的静默泄漏连告警都没有）
- **保守**：宁可漏报不可误报——没告警不等于绝对没泄漏

正确态度：**把告警当成提示去检查，别当成保证去放心。**

### 12. 到底还需不需要担心？

**大部分情况不用了。** 已经消灭的：

- ✅ 嵌套释放的层层疏漏（`Drop` 递归）
- ✅ 忘记释放（`own` 兜底 **+** 泄漏告警，`}` 与每个 `return` 前都释放并置空）
- ✅ 多路径释放不一致（作用域出口统一处理）

还剩的是：

- ⚠️ **own / borrow 的区分**（`borrow` 已能标注，但仍在出错时靠它）
- ⚠️ **`goto` 静默失效**
- ⚠️ **被调函数把指针存全局**（无跨过程分析）
- ⚠️ **arena 与 `delete` 混用**（现阶段会崩）
- ⚠️ **无界工厂缓存**（编译器查不出的泄漏）

这几条里没有一条是「记不记得」的问题，都是**结构性边界**——只要避开 goto、不在 arena 上 `delete`、
借来的不释放、不写「存全局」的函数、工厂必须有上限，剩下交给编译器就行。

**体系评价**：机制层面已成型（`own` + `Drop` 递归 + 泄漏告警 + `borrow` + 工厂收敛），
tooling 还差最后一公里——Arena 未作为官方库暴露（§8）。

### 13. 建议写进团队规约的七条

1. **默认块内 `own`**，能不手写 `delete` 就不手写（释放点更靠近使用范围）
2. **函数参数写 `borrow`**，明确不拥有
3. **不写「把传进来的指针存进全局 / 长周期容器」的函数**；真要存，让调用方不 `own`，改由容器负责
4. **命名区分工厂类型**：`*_open` / `*_create` / `*_make` = 移交（调用方 `delete`）；`*_get` / `*_lookup` / `*_shared` = 借用（调用方绝不释放）
5. **长生命周期对象在初始化阶段建好**，函数里只用不建、只借不删（CT 已保证文件作用域不能用 `own`）
6. **arena 只用在有明确边界的地方，且绝不 `delete` arena 指针**
7. **工厂必须有界**：有缓存就必须有上限，有上限就必须有淘汰策略，`Drop` 里能一次性清空整个池

### 14. 一句话心智模型

> **传给子函数是安全的（哪怕嵌套很多层），因为借用指针随栈帧消失；
> 危险的只有「指针流进了比当前作用域活得更久的地方」。**
>
> 判断标准不是「还有几个指针指着它」，而是「还有没有人觉得自己该释放它」。
>
> 而工厂的意义就是：**把「该谁释放」这个问题的答案，收敛到一个地方。**

### 15. `borrow` + `Handback`（v0.16.0 已落地）

想给「借用」补上语法标记，设计见 [design/borrow.md](history/design/borrow.md)（完整提案 + 前提订正 + 决策项 D1–D6）。
一句话版本：

- **`borrow` 作为参数注解**（阶段一）：零代码生成变化，只做两项检查——禁止 `delete`、禁止存入更长寿命处
- **`borrow` 作为变量声明**（阶段二）：出口自动 `<S>_Handback_handback(p); p = 0;`，**不 `free`**，与 `own` 完全对称
- **`Handback` 实现在被借出的对象上**（不是工厂上）：编译器出口手里只有对象指针，归还动作必须能从该指针出发找到
- **它不消除所有悬垂**：`store(r)` 这类跨过程逃逸仍看不见；`goto` 仍是静默失效
- **已知限制**：`impl Handback for S` 必须与借用点同单元（`borrow` 与实现尚未跨单元），
  且借用句柄不可重新赋值、不可存入 `static` 局部或全局

### 16. 总原则：所有权的三个根

> **每个堆对象，所有权必须能追溯到一个「根」；不存在飘在外面不受管理的指针。**

| 根 | 形态 | 释放时机 |
| --- | --- | --- |
| **栈帧** | 块内 `own T *p` | 作用域出口自动 |
| **静态存储** | 全局 / `static` 对象本身 | 程序结束，从不释放 |
| **容器 / 工厂** | 池、注册表、有界缓存 | 容器 `Drop` 时统一清空 |

**因此要避免的不是「全局变量」，而是「不受管理的全局指针」。**

| 形态 | 评价 |
| --- | --- |
| `static Logger g_logger;`（对象**就是**静态存储） | ✅ **推荐**，嵌入式首选，永不泄漏 |
| `static ConnPool g_pool;`（容器持有全部对象） | ✅ **推荐**，有界 + `Drop` 可清空 |
| `Request *g_last;`（函数里把堆指针挂上去） | ❌ **唯一危险形态**，没人拥有它 |

静态分配在嵌入式恰恰是被鼓励的——栈小、堆常缺。CT 不建议的是「把堆指针挂到全局」，那会让所有权失去根。

剩下需要人工把关的只有三条（都是结构性边界，非记忆问题）：

1. **工厂必须有界**（无界缓存是唯一编译器查不出的泄漏）
2. **不用 `goto` 跨过 `own` / `borrow` 声明**（唯一静默失效）
3. **不写「把传进来的指针存进全局」的函数**（唯一无防护悬垂，无跨过程分析）
