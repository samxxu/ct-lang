# Bindings 与模式配方

> 面向在 CT 里写 bindings、容器封装与 C 互操作的人。每条配方给：**适用场景 → 最小可复制代码 →
> 常见错误 → 一条负例（预期红的样子）**。代码按 `ct build` 的单元约定写；只在单文件
> `ct-ast` 下可用的写法会单独注明。
>
> 相关规范：[language-spec.md](language-spec.md)（`.h.ct` / `.m.ct` / 变参 / 函数指针 / 容器）、
> [package-guide.md](package-guide.md)。本文不新增语言特性，只记录今天能跑的写法。

## 1 异构值：`union` + `int tag` + `Map<char *, struct JsonRef>`

**适用场景**：JSON 节点、参数表、DSL 的 `Value`——同一槽位可能是整数、浮点或字符串，
用 tag 区分，值放进 `union`。

```c
#include <stdio.h>
#include <string.h>

union JsonValue {
    int i;
    double d;
    char *s;
};

struct JsonRef {
    int tag;              /* 0 = int, 1 = double, 2 = string */
    union JsonValue v;
};

int main(void)
{
    Map<char *, struct JsonRef> obj = {};
    struct JsonRef r;
    struct JsonRef *p;

    r.tag = 0;
    r.v.i = 42;
    obj.put("answer", r);

    r.tag = 2;
    r.v.s = "ct";
    obj.put("name", r);

    p = obj.get("answer");          /* V = struct JsonRef，get 返回 V* */
    if (p != 0 && p->tag == 0)
        printf("%d\n", (*p).v.i);   /* 多一层 *：p 指向槽位里的值 */

    obj.release();
    return 0;
}
```

- `Map<char *, V>` 的 key 是 `char *`，按 `strcmp` 比较；**key 不复制**，必须比 map 活得久
  （字面量、静态表、或 map 释放前手动释放的堆串）。
- `V` 按值拷贝进槽位；`struct JsonRef` 没有 `retain` / `release`，map 释放时不会递归释放
  `v.s` 指向的堆内存——谁分配谁释放。
- `get` 返回 `V *`。`V` 本身是指针时就是 `V **`；这是「多一层 `*`」的来源。
- 空 map 用 `= {}` 初始化，或写 `obj.h = 0;`；`Map` 的 `put` 在 `h == 0` 时才分配 header。

**常见错误**

1. 把值类型写成 `Map<char *, struct JsonRef *>`，然后按 `struct JsonRef *p = obj.get(...)` 收：
   `get` 返回 `struct JsonRef **`，多一层。
2. 用栈上的局部 `char key[16]` 作 key，函数返回后 map 里全是悬垂 key。
3. 以为 `obj.release()` 会释放 `v.s`；它只对**有 `release` 方法的元素类型**逐元素释放。

**负例（预期红）**

```c
Map<char *, struct JsonRef *> m = {};
struct JsonRef *p = m.get("k");
```

```text
error: incompatible pointer types initializing 'struct JsonRef *'
       with an expression of type 'struct JsonRef **'
```

修法：值用 `struct JsonRef`（本文写法），或显式写 `struct JsonRef **pp = m.get("k");`。

## 2 可变参数 C 函数：三个 `curl_setopt_*` shim

**适用场景**：C API 的变参第三参类型随 option 变化（`curl_easy_setopt` 是典型），
直接暴露 `...` 会把类型错误推迟到运行期；用三个具体类型的 shim 把类型钉死。

```c
/* curl.shim.h —— 与 curl.m.ct 同目录、同 base */
#ifndef CURL_SHIM_H
#define CURL_SHIM_H

#include <curl/curl.h>

int curl_setopt_long(CURL *h, int opt, long v);
int curl_setopt_str(CURL *h, int opt, char *v);
int curl_setopt_ptr(CURL *h, int opt, void *v);

#endif
```

```c
/* curl.shim.c */
#include "curl.shim.h"

int curl_setopt_long(CURL *h, int opt, long v)
{
    return (int)curl_easy_setopt(h, (CURLoption)opt, v);
}

int curl_setopt_str(CURL *h, int opt, char *v)
{
    return (int)curl_easy_setopt(h, (CURLoption)opt, v);
}

int curl_setopt_ptr(CURL *h, int opt, void *v)
{
    return (int)curl_easy_setopt(h, (CURLoption)opt, v);
}
```

```c
/* curl.m.ct —— 只写 recipe；shim 头由编译器自动 include 进消费者 .c */
#include <stdio.h>

namespace curl;

pub trait Easy {
    int setopt_long(void *h, int opt, long v);
    int setopt_str(void *h, int opt, char *v);
    int setopt_ptr(void *h, int opt, void *v);
    int logf(char *fmt, ...);
}

map trait Easy for namespace curl {
    setopt_long(h, opt, v) -> curl_setopt_long(h, opt, v);
    setopt_str(h, opt, v)  -> curl_setopt_str(h, opt, v);
    setopt_ptr(h, opt, v)  -> curl_setopt_ptr(h, opt, v);
    logf(fmt, ...)         -> fprintf(stderr, fmt, ...);
}
```

```c
/* main.ct —— 必须走 ct build；.m.ct 不能被 ct compile 直接编译 */
#include <stdio.h>

import curl::curl;

int main(void)
{
    void *h = curl_easy_init();
    int rc;

    if (h == 0) return 1;
    rc = curl::Easy.setopt_long(h, CURLOPT_TIMEOUT, 10);
    curl::Easy.logf("rc=%d\n", rc);
    curl_easy_cleanup(h);
    return 0;
}
```

- `.shim.h` / `.shim.c` 必须与 `.m.ct` 同目录同 base；有 `.shim.c` 就必须有 `.shim.h`。
- shim 头按**文件名**解析，`ct build` 会在 `cc` 行自动加 `-I <shim 目录>`，并 include 它。
- 用 `void *` 接 `CURL *` 是为了让 CT 不需要认识 C 头里的类型；C 允许 `void *` 隐式转成
  对象指针，ABI 不变。
- `.m.ct` 方法可以用 `...` 收尾，recipe 也必须把 `...` 原样转发；`...` 必须**同时**出现在
  绑定与方法签名里，且都在最后一位。

**常见错误**

1. 在普通 `trait` 方法里写 `...`：报 `a trait method cannot be variadic`（vtable 槽位是固定签名）。
2. `.m.ct` 的 trait 带 `...`、recipe 不写 `...`：报
   `a variadic trait method must forward '...' in its binding`。
3. `ct compile curl.m.ct`：`.m.ct` 只在 `ct build` 里被 import，`ct compile` 直接拒绝。

**负例（预期红）**

```c
pub trait Bad { int m(char *fmt, ...); }
map trait Bad for namespace lib { m(..., fmt) -> fprintf(stderr, ..., fmt); }
```

```text
error: '...' must be the last binding parameter
```

## 3 函数指针跨模块：`pub typedef` + `.h.ct`

**适用场景**：回调表、插件入口、把 C 库的 `fn` 指针类型发布给多个单元。
类型只写一次在 `.h.ct` 里，消费者按裸名使用。

```c
/* lib/callback.h.ct */
namespace lib;

pub typedef int (*BinOp)(int, int);

pub struct Calc {
    BinOp op;
};

pub int calc_run(struct Calc *c, int a, int b);
int calc_run(struct Calc *c, int a, int b)
{
    return (*c->op)(a, b);
}
```

```c
/* main.ct */
#include <stdio.h>

import lib::callback;

static int add(int a, int b) { return a + b; }

int main(void)
{
    Calc c;

    c.op = add;
    printf("%d\n", calc_run(&c, 2, 3));
    return 0;
}
```

- `pub typedef` 与 `pub struct` / `pub trait` 一样进入依赖单元的生成 `.h`；消费者写裸名
  `Calc` / `BinOp`，编译器解析到命名空间里的 C 名。
- 函数指针类型本身按源码同形发射，typedef 名内部不参与 mangling；跨单元的 ABI 兼容靠
  **每个单元用同一个 `.h.ct` 声明**，不要在两个单元各写一份拼写不同的 typedef。
- 绑定边界的注意项：
  - C 侧函数指针的调用约定必须与 CT 发射的 `ret (*)(params)` 一致；不要跨 DLL/so 边界
    传 `__stdcall` 之类的非默认约定。
  - 不要把 CT 的闭包字面量当普通函数指针：闭包是 `(fn, env)` 两词 ABI，不是单个 C 指针
    （见 SH-67）。需要回调就写具名函数，或显式用 `struct` + trait。
  - 变参函数指针的 `...` 前必须有具名参数（`int (*logf)(char *, ...)` 可以，
    `int (*bad)(...)` 报 `'...' needs a named parameter before it`）。
  - 不支持嵌套函数指针（`int (**f)(int)`）与函数指针数组作参数。

**常见错误**

1. 在 `.h.ct` 里只写 `typedef` 不写 `pub`：消费者看不到该类型。
2. 把闭包字面量赋给函数指针字段，期望它是 C 回调。
3. 两个单元各写一份 `typedef int (*Cb)(int);`，其中一份参数类型不同，链接期不报、
   运行期栈错位。

**负例（预期红）**

```c
Calc c;
c.op = (int x, int y) => x + y;
```

```text
error: a closure cannot be stored in a field, an element or a container
```

## 4 `foreach` 遍历 `Vec` 的四条语义

**适用场景**：遍历内置 `Vec<T>`，需要知道循环边界、`item` 与 `i` 到底是不是容器里的槽位。

```c
#include <stdio.h>

int main(void)
{
    Vec<int> xs = { 1, 2, 3 };
    Vec<int> alias = xs.retain();   /* 第二个 handle，用来在 body 里增长 */
    int rounds = 0;

    foreach (xs) {
        rounds = rounds + 1;
        item = item + 100;          /* 只改副本，不回写 xs */
        if (rounds == 1)
            alias.push(4);          /* 通过另一个 handle 增长：不延长本轮 */
    }

    printf("%d %d %d\n", rounds, xs.len(), xs.get(0));
    alias.release();
    xs.release();
    return 0;
}
```

输出：`3 4 1`。四条语义：

| # | 语义 | 含义 |
| --- | --- | --- |
| 1 | 长度只快照一次 | 循环上界是进入 `foreach` 时的 `len()`；body 里增长不延长本轮 |
| 2 | `item` 按值拷贝 | 改 `item` 不改容器槽位；要写回用 `set(i, item)` |
| 3 | `i` 只读 | `i = …` / `i++` / `&i` 都是硬错；它是位置，不是变量 |
| 4 | body 内改容器不延长循环 | 直接改被遍历变量（`xs.push` 等）另有 L31-22 硬错；通过别的 handle 改，也只跑快照长度 |

**常见错误**

1. 在 `foreach (xs)` 里直接 `xs.push(x)` / `xs.set(...)`：报
   `cannot mutate the container being iterated; take a copy or collect the indices first`。
2. 以为 `item = ...` 会写回容器；实际只改局部副本。
3. 用 `i` 当可写计数器。

**负例（预期红）**

```c
foreach (xs) {
    i = 10;
}
```

```text
error: the foreach index 'i' is read-only
```

## 5 `own` 与 `Vec<char>`：工厂句柄为什么要手写 `release`

**适用场景**：需要一块可自动释放的堆对象，或想用 `Vec<char>` 拼字符串。
`own` 只认 `malloc` / `calloc` 直接初始化；工厂返回值必须自己释放。

```c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

struct Buf {
    char *data;
    int len;
} use Drop;

impl Drop for Buf {
    void drop() {
        free(self->data);
    }
}

static struct Buf *buf_new(int n)
{
    struct Buf *b = malloc(sizeof(struct Buf));
    if (b == 0) return 0;
    b->data = malloc((size_t)n + 1);
    if (b->data == 0) {
        free(b);
        return 0;
    }
    b->len = 0;
    return b;
}

static void buf_release(struct Buf *b)
{
    if (b == 0) return;
    free(b->data);          /* drop 负责的部分 */
    free(b);                /* 句柄本身 */
}

int main(void)
{
    own struct Buf *a = calloc(1, sizeof(struct Buf));
    a->data = malloc(8);
    a->len = 5;
    memcpy(a->data, "hello", 5);
    /* 块尾自动 delete：Buf_Drop_drop + free(a) */

    struct Buf *b = buf_new(8);   /* 工厂返回值：不能写 own */
    b->data[0] = 'x';
    b->len = 1;
    buf_release(b);               /* 所以必须手写 release */

    printf("%d\n", a->len);
    return 0;
}
```

- `own T *p = malloc(...)` / `calloc(...)` 是 `own` 的唯一入口；`own T *p = factory();`
  报 `'own' requires a malloc or calloc initialiser`。
- 工厂返回的句柄没有 AutoDrop：块尾不会替你 `free`，必须手写 `release`，并把
  `Drop` 负责的字段与句柄本身的释放写清楚。
- `Vec<char>` 不是字符串：它没有 `reserve`、没有批量 append、没有 `c_str`，`get` 返回
  **值拷贝**，也不保证末尾有 `\0`。做 builder 要自己补最后一步：

```c
Vec<char> v = {};
char *s;
int k;

v.push('h');
v.push('i');
v.push(0);
s = malloc((size_t)v.len() + 1);
for (k = 0; k < v.len(); k++) s[k] = v.get(k);
s[v.len()] = 0;
v.release();
printf("%s\n", s);
free(s);
```

- `Vec<T>` 的句柄只有 `h`，没有 `data` 字段；不要写 `v.data`。

**常见错误**

1. `own struct Buf *b = buf_new(8);`——工厂返回值不是 `malloc` / `calloc` 初始化式。
2. `char *p = v.data;`——`Vec` 的布局是 `{ ct_buf *h; }`，没有 `data`。
3. 用 `Vec<char>` 当 `Str` 传给 C，末尾没有 `\0`。

**负例（预期红）**

```c
struct Buf *b = buf_new(8);
own struct Buf *o = b;
```

```text
error: 'own' requires a malloc or calloc initialiser
```

## 6 可空取值：`Map.get` 缺键返回 0

**适用场景**：查表时 key 可能不存在；`Map.get` 用空指针表示「没有」，不是返回值哨兵。

```c
#include <stdio.h>

int main(void)
{
    Map<char *, int> m = {};
    int *p;

    m.put("a", 1);

    p = m.get("a");
    if (p != 0)
        printf("%d\n", *p);

    p = m.get("missing");
    if (p == 0)
        printf("missing\n");

    m.release();
    return 0;
}
```

- `get` 在空表、缺键、key 为 `0` 时都返回 `0`（`lib/std/Vec.h.ct:260-268`）。
- 返回的是**槽位地址**，不是拷贝；在下一次 `put` / `remove` / `clear` 导致扩容或移动之前有效。
  需要跨操作保存就先把值拷出来。
- 链式访问必须手写判空；C 没有 `?.`：

```c
struct JsonRef *r = obj.get("k");
if (r != 0 && r->tag == 0)
    printf("%d\n", r->v.i);
```

**常见错误**

1. `int v = *m.get("missing");`——编译通过，运行期解引用空指针。
2. 把 `get` 的返回指针存起来，之后再 `put` 另一个 key，扩容后指针悬垂。
3. 以为缺键返回 `0` 值；返回的是 `0` **指针**，不是 `int` 的零值。

**负例（预期红）**

```c
Map<char *, int> m = {};
int v = *m.get("missing");
```

```text
$ ./a.out
zsh: segmentation fault
```

编译期不报错，运行期 SIGSEGV——这正是必须手写判空的原因。

## 7 C11 原子类型与操作：`_Atomic` 直通

**适用场景**：多线程共享计数器、一次性发布指针、无锁标志位。CT 不实现原子语义，只把类型拼写与
函数调用原样转发给 C 编译器；原子 typedef 与操作由 `<stdatomic.h>` 提供。

```c
#include <stdatomic.h>
#include <stdio.h>

int main(void)
{
    _Atomic(int) hits = 0;          /* 函数式拼写：原样转发 */
    atomic_int total = 0;           /* typedef：来自 <stdatomic.h> */
    atomic_bool ready = 0;
    _Atomic(void *) slot = 0;

    atomic_store(&hits, 1);
    atomic_store(&total, atomic_load(&hits));
    atomic_store(&ready, 1);
    atomic_store(&slot, (void *)&hits);

    printf("%d %d %d %p\n",
           atomic_load(&hits), atomic_load(&total),
           (int)atomic_load(&ready), atomic_load(&slot));
    return 0;
}
```

- 四种写法都能编译运行：`_Atomic(int)`、`_Atomic(void *)` 是类型修饰拼写；`atomic_int`、`atomic_bool`
  是 `<stdatomic.h>` 里的 typedef。生成的 C 与源码同形，语义全部由 C 编译器承担。
- 三个操作照常调用：`atomic_load(&x)`、`atomic_store(&x, v)`、
  `atomic_compare_exchange_strong(&x, &expected, desired)`。
- 必须 `#include <stdatomic.h>`；CT 不做任何原子相关检查，也不会替你补头文件。
- 不带 `_explicit` 的 `atomic_load` / `atomic_store` 默认是 **seq_cst**。这只是写法约定：语言没有
  强制检查，绕开它的办法见下面的禁区第 3 条。

**CAS：`expected` 必须按地址传入**

```c
int expected = 0;
if (atomic_compare_exchange_strong(&x, &expected, 1)) {
    /* 成功：x 从 0 变成 1 */
} else {
    /* 失败：expected 已被写成 x 的实际值 */
}
```

- 第二个参数是 `T *expected` 出入参：失败时 C 侧把当前值写回它。按值传 `expected` 只能拿到
  "成功 / 失败"，拿不到失败时实际读到的值——重试循环也就没法续下去。
- 失败后 `expected` 已经是当前值，可以直接进入下一轮比较，或据此退回普通加锁。
- 不要自己定义 `int atomic_load(int *)` 这类同名函数：语言没有函数重载，它会与 `<stdatomic.h>` 的
  宏冲突，生成 C 直接报 `expected parameter declarator`。

**三条禁区**

1. `atomic int x;`（把 `atomic` 当关键字前缀）不会被当作原子类型。`parse_type` 只认 `_Atomic(...)`
   拼写与已知 typedef；`atomic int` 走未知类型兜底，`ct compile` / `ct build` 仍返回 0，但原样产出的
   C 会在 `cc` 阶段报 `unknown type name 'atomic'`。请写 `_Atomic(int)` 或 `atomic_int`。
2. `atomic own` 组合不成立：`own` 只接受 `struct` 指针加 `use Drop`（见
   [language-spec.md](language-spec.md) §4.9），`_Atomic(T)` 不是这样的 struct，`own _Atomic(int) *p`
   会在编译期被拒。需要原子句柄时用普通指针 + `atomic_*` 操作。
3. 内存序字面量可绕过 seq_cst 约定：`atomic_store_explicit(&x, 1, 0)`、
   `__atomic_store_n(&plain, 1, 5)` 的最后一个实参只是普通整数，CT 原样转发、不校验取值。想守住
   seq_cst 就只用 `atomic_load` / `atomic_store`，不要手写显式内存序；一旦写了，顺序正确性完全由
   调用方负责。

**门禁现状**：现有 11 道硬门禁没有并发检查，`check-sanitizers.sh` 只跑 ASAN / UBSAN，**没有 TSan**。
原子代码的竞态与顺序错误不会被现有 CI 捕获；需要验证时自己用 `-fsanitize=thread` 单独跑。

**负例（预期红）**

```c
atomic int x = 0;      /* 不是 _Atomic(int) */
```

```text
$ cc generated.c
error: unknown type name 'atomic'
```

`ct compile` 本身返回 0（未知类型兜底），红在 C 编译阶段——这正是禁区第 1 条的来源。
