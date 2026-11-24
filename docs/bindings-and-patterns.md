# Bindings 与模式配方

> 面向在 Ct 里写 bindings、容器封装与 C 互操作的人。每条配方给：**适用场景 → 最小可复制代码 →
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
  **正式契约**（命名、头文件边界、所有权、错误码、ISR/任务上下文、ABI、host mock + Renode）
  见 [C Shim 契约](c-shim-contract.md)；本文只给配方。
- shim 头按**文件名**解析，`ct build` 会在 `cc` 行自动加 `-I <shim 目录>`，并 include 它。
- 用 `void *` 接 `CURL *` 是为了让 Ct 不需要认识 C 头里的类型；C 允许 `void *` 隐式转成
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
  - C 侧函数指针的调用约定必须与 Ct 发射的 `ret (*)(params)` 一致；不要跨 DLL/so 边界
    传 `__stdcall` 之类的非默认约定。
  - 不要把 Ct 的闭包字面量当普通函数指针：闭包是 `(fn, env)` 两词 ABI，不是单个 C 指针
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

- `get` 在空表、缺键、key 为 `0` 时都返回 `0`（`lib/core/Vec.h.ct` 的 `get`）。
- 只想判存在、不取值时用 `has`（v0-PH-50）：`Map::has(k)`、`Vec::has(i)`；`Vec::at(i)` 返回
  借用指针，未命中为 `0`。`has` 为真时值恰好是 `0` 也是合法命中，不与「没取到」混淆。
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

## 7 原子类型与操作：`atomic T` + `ct_atomic_*`（Phase 41）

**适用场景**：多线程共享计数器、取消标志、无锁发布指针。Ct 从 Phase 41 起提供 `atomic T`
修饰符和三个内建操作；`<stdatomic.h>` 的 `_Atomic` / `atomic_load` / `atomic_store` 仍按普通
C 调用直通，不被占用。

```ct
#include <stdio.h>

int main(void)
{
    atomic int hits = 0;
    atomic bool ready = 0;
    int expected = 0;

    ct_atomic_store(&hits, 1);
    if (!ct_atomic_cas(&hits, &expected, 2))
        return 1;
    ct_atomic_store(&ready, 1);
    printf("%d %d %d\n", ct_atomic_load(&hits),
           (int)ct_atomic_load(&ready), expected);
    return 0;
}
```

- `atomic int` / `atomic long` / `atomic bool` / `atomic void *` 映射 `_Atomic(T)`；
  `atomic int *` 是“指向原子 int 的指针”。
- 内建操作是 `ct_atomic_load` / `ct_atomic_store` / `ct_atomic_cas`，全部 seq_cst。
- CAS 第二参数必须按地址传：`ct_atomic_cas(&x, &expected, desired)`；失败写回实际值。
- **C11**：`ct build` 在原子单元使用 `-std=c11`；`ct compile` 生成的 C 请用 `-std=c11` 编译。
- 原子操作需要 C11 编译器支持 `__atomic_*`（GCC ≥ 4.7 / clang ≥ 3.1）。
- `atomic` 是上下文修饰，不是无条件关键字；`int atomic = 1;` 保持合法。

**与 `<stdatomic.h>` 的关系**：标准名 `atomic_load` / `atomic_store` 和 `_Atomic(struct S)` 的
宏用法不受影响；Ct 内建名带 `ct_` 前缀。不要定义 `ct_atomic_*` 同名函数。

**门禁**：`test/ast/p41_*` 覆盖 load/store/CAS/取消标志/引用计数；`selfhost/check-tsan.sh`
在 nightly Linux job 跑 TSan。它不是第 12 道硬门禁，本地无 TSan 时打印 `SKIP`。

## 8 链式构建器：字符串工厂 + 对象方法链（HTTP 请求）

范式定义是所有文档共用的同一句话，三段顺序固定：

1. **起点是字符串**，不是构造器。
2. **通过 factory 创建由 trait 定义的对象类型**，不是 struct；struct 是实现细节，不出现在使用者代码里。
3. **链式调用挂在接口上**，配置方法返回同一接口类型。

完整解释、两档路径的判断依据、0.44.1 的逐段边界与报错原文只在
[language-spec §4.10.1](language-spec.md#4101-链式构建器范式权威定义与两档路径) 讲一次，本节只给配方。

**先选档**：对象无状态、单一实现、调用方不需要面向接口 → 轻量路径，基本类型直接挂方法
（见本节末尾的字符串切分配方，完整程序在 [examples/48_string_steps](../examples/48_string_steps/src/main.ct)）；
有状态、多实现、调用方要面向接口 → 完整路径，也就是本节主配方。轻量不是错写法。

**适用场景**：请求、配置这类「从一段文本起手、配置几项、取一个结果」的构造。目标是让调用点
不出现构造细节，也不出现一长串局部变量。这里的主配方是 HTTP 请求（完整路径的目标形态；0.44.1
上接口段还不成立，实际可运行的是静态宿主形态，见 §4.10.1）：

```c
int status = "https://api.example.com/users"
                 .method("GET")                    /* char * 上的工厂 */
                 .header("Accept", "application/json")
                 .timeout(3000)
                 .send()                           /* 请求对象 → 响应对象 */
                 .status();
```

三层接收者：`char *`（只挂工厂）→ 请求对象（配置方法返回宿主本身）→ 响应对象（收口方法）。
使用者只看到这三个位置，看不到宿主的具体类型名。可运行版（静态宿主，不是 trait 对象）见
[examples/47_chain_factory](../examples/47_chain_factory/src/main.ct)；完整路径的 0.44.1 断点在
[language-spec §4.10.1](language-spec.md#4101-链式构建器范式权威定义与两档路径)。

`http.shim.h`——普通 C 适配层（**stub**，不碰网络）：

```c
#ifndef HTTP_SHIM_H
#define HTTP_SHIM_H

struct HttpRequest {
    char *url;
    char *verb;
    char *accept;
    int timeout_ms;
    int headers;
};

struct HttpResponse {
    int status;
    char *body;
};

static inline struct HttpRequest http_request_new(const char *url, const char *verb)
{
    struct HttpRequest r;
    r.url = (char *)url;
    r.verb = (char *)verb;
    r.accept = "";
    r.timeout_ms = 0;
    r.headers = 0;
    return r;
}

static inline struct HttpRequest http_request_header(struct HttpRequest r,
                                                     const char *name,
                                                     const char *value)
{
    if (name != 0 && value != 0) {
        r.headers = r.headers + 1;
        if (name[0] == 'A' && name[1] == 'c') r.accept = (char *)value;
    }
    return r;
}

static inline struct HttpRequest http_request_timeout(struct HttpRequest r, int ms)
{
    r.timeout_ms = ms;
    return r;
}

/* 唯一会“发请求”的位置。stub；接 curl 时改成 curl_easy_perform。 */
static inline struct HttpResponse http_request_send(struct HttpRequest r)
{
    struct HttpResponse resp;
    if (r.timeout_ms < 0) {
        resp.status = 408;
        resp.body = "stub: timeout";
    } else {
        resp.status = 200;
        resp.body = "{\"users\":3}";
    }
    return resp;
}

static inline int http_response_status(struct HttpResponse r) { return r.status; }
static inline char *http_response_body(struct HttpResponse r) { return r.body; }

#endif
```

`http.m.ct`——三层方法分别绑在哪个宿主上：

```c
namespace http;

#include "http.shim.h"

pub type CRequest = struct HttpRequest;
pub type CResponse = struct HttpResponse;

pub trait HttpEntry {
    CRequest method(char *verb);
}

pub trait RequestBuilder {
    CRequest header(char *name, char *value);
    CRequest timeout(int ms);
    CResponse send();
}

pub trait ResponseView {
    int status();
    char *body();
}

map trait HttpEntry for type char * {
    method(s, verb) -> http_request_new(s, verb);
}

map trait RequestBuilder for type CRequest {
    header(r, name, value) -> http_request_header(r, name, value);
    timeout(r, ms)         -> http_request_timeout(r, ms);
    send(r)                -> http_request_send(r);
}

map trait ResponseView for type CResponse {
    status(r) -> http_response_status(r);
    body(r)   -> http_response_body(r);
}
```

`main.ct`：

```c
//@ct-requires: ct-ast
import http::http;

#include <stdio.h>

int main(void)
{
    int status = "https://api.example.com/users"
                     .method("GET")
                     .header("Accept", "application/json")
                     .timeout(3000)
                     .send()
                     .status();

    char *body = "https://api.example.com/users"
                     .method("GET")
                     .header("Accept", "application/json")
                     .send()
                     .body();

    printf("%d %s\n", status, body);
    return 0;
}
```

```sh
ct build examples/47_chain_factory/src/main.ct -o /tmp/http47 && /tmp/http47
# 200 {"users":3}
```

**为什么成立**：

- 每一跳都是类型宿主静态映射（定义见 [language-spec §4.10.1](language-spec.md#4101-链式构建器范式权威定义与两档路径)），
  展开成一次裸 C 调用：
  `http_response_status(http_request_send(http_request_timeout(http_request_header(http_request_new("https://api.example.com/users", "GET"), "Accept", "application/json"), 3000)))`。
  没有 vtable、装箱或临时对象。
- `char *` 宿主只做工厂，不存状态；状态在工厂产出的宿主里，调用点看不到它。
- `header()` / `timeout()` 按值返回宿主本身，所以下一跳还能继续 `.`。

**轻量配方（无状态、单一实现）**：同样从字符串起手，但不引入对象。把方法直接挂到 `char *`，
方法返回 `char *` 就能继续链，最后 `len()` 收口（完整程序见
[examples/48_string_steps](../examples/48_string_steps/src/main.ct)）：

```c
import text::text;

int n = "alpha,beta,gamma".split_once(',').split_once(',').len();   /* 5 */
```

```c
/* text.m.ct */
map trait TextSteps for type char * {
    split_once(s, sep) -> text_split_once(s, sep);
    len(s)            -> text_len(s);
}
```

生成物同样是嵌套裸 C 调用，没有 vtable、没有接口值。这一档不解决多态；需要多实现时回到上面的完整配方。

**常见误读**

1. **「impl 方法不能作接收者」≠「Ct 不支持链式」。** 链式走的是类型宿主静态映射；经典
   `impl` / 固有 `impl` 走派发路径，方法结果不能再作接收者，第二跳报
   `method receiver must be a variable, an element, a call or a field chain`。两条路径要分开看。
2. **「`char *` 上挂方法」≠「给字符串加状态」。** `char *` 上只有工厂，没有字段；也不能写
   `impl Trait for char *`（报 `impl for undefined struct 'char'`）。方法只来自被 `import` 的
   `.m.ct` 映射单元；没有导入就不存在，调用报 `no method 'get' for type 'char *'`。

**边界**

完整边界（含 0.44.1 第 2、3 段为何不成立）只在
[language-spec §4.10.1](language-spec.md#4101-链式构建器范式权威定义与两档路径)；这里只列写配方时最容易踩的两条：

- `map trait … for type …` 只能写在 `.m.ct` 里；写在普通 `.ct` 报
  `a type host is only allowed in a .m.ct unit`。
- 不透明 C shim 函数的调用结果不能直接起手（Ct 没有它的返回类型）；先落到变量，或包一层带
  显式返回类型的 Ct 函数。

`send()` 当前是 stub，不发网络；接真 curl 时只替换 `http.shim.h` 里的 `http_*` 实现，
Ct 链路与 `http.m.ct` 不变。逐条实跑证据（退出码与报错原文）见
[history/reports/chain-builder-paradigm/probe.md](history/reports/chain-builder-paradigm/probe.md)。

**负例（预期红）**

```c
/* char * 上没有 impl；方法也不会凭空出现 */
trait UrlOps { char *get(); }
impl UrlOps for char * { char *get() { return self; } }
```

```text
error: impl for undefined struct 'char'
```

```c
/* 没有 import 映射单元时，字符串上直接调方法 */
"https://example.com".get();
```

```text
error: no method 'get' for type 'char *'
```

## 9 绑定点转换的第三来源：`map binding`

**适用场景**：一个类型对（`Node -> Num`）有固定的转换函数，既能像显式 `as<T>()`
一样调用，又希望声明初始化、赋值与 `return` 处裸写即可转换；转换实现属于一个
可 import 的映射单元，而不是源类型的固有方法。

```ct
/* shapes.h.ct */
pub struct Node { int v; }
pub struct Num  { int n; }
pub struct Num node_to_num(struct Node x) {
    Num r = { x.v + 7 };
    return r;
}
```

```ct
/* ops.m.ct —— 映射单元，不产生产物 */
map binding struct Node -> struct Num {
    from(x) -> node_to_num(x);
}
```

```ct
/* prog.ct */
import shapes;
import ops;

struct Num twice(struct Node n)
{
    return n;                      /* return 处裸写即转换 */
}

int main(void)
{
    struct Node node = { 5 };
    struct Num a = node;           /* 声明初始化 */
    struct Num b;
    b = node;                      /* 赋值 */
    struct Num c = node.as<Num>(); /* 显式宽松档 */
    return a.n + b.n + c.n + twice(node).n == 4 * 12 ? 0 : 1;
}
```

- 查找序：源类型固有 `as` → 已 import 的 `map binding` → 已 import 的
  `map trait`（D-021 §4）；前一个命中，后面的不参与。
- recipe 在**使用点**展开（`node_to_num((node))`），没有 wrapper / vtable /
  运行时注册表；只写 `map binding` 而不使用它，生成的 C 里不出现这次调用。
- 未 import `ops` 时是“缺转换”硬错，诊断会提示 import 一个带 `map binding` 的
  映射单元；同一对由两个已 import 的单元提供时报歧义，并列两个候选文件名。
- 只做一跳：`A -> B` 与 `B -> C` 不会把 `A` 直接转成 `C`。
- `map binding` 只能写在 `.m.ct`；严格档 `to<T>()` 仍只由固有 `to` / `map trait`
  提供（本切片的边界）。

**负例（预期红）**

```ct
import shapes;      /* 故意不 import ops */
int main(void)
{
    struct Node n = { 5 };
    struct Num a = n;
    return a.n;
}
```

```text
error: no conversion from 'struct Node' to 'struct Num'; add an inherent 'as' method
on 'struct Node', import a mapping trait that declares 'as', or import a mapping unit
with a 'map binding' for this pair
```
