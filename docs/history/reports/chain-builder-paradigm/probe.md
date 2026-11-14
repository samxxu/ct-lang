# 链式构建器范式实测记录（CT 0.44.1）

> 只读证据档案。记录 2026-11-14 在本地自举出的 `ct-ast v0.44.1` 上逐条跑出的
> 退出码与原始报错；这里的结论是后续 README / 教程 / 语言规范改写的唯一依据。
> 探针源码只存在于 `/tmp`，未进入仓库；本文保留可直接复制的源码与命令。
> 本文的 URL 形态只用于最小机制验证；主线可运行样例已换成
> [examples/47_chain_factory](../../../../examples/47_chain_factory/src/main.ct) 的 HTTP 请求链，
> 其 `send()` 是 stub，接 curl 时只替换 `http.shim.h` 的实现。

> **2026-11-15 复核**：SH-74（`return self` 装箱发射 `(void *)_self`，`d6e82e25`）与
> SH-72（动态派发调用按 trait 签名给出返回类型，`5ff69ac3`）已在 HEAD 修复。下文凡记录
> `cannot infer the type to box` 的段落反映的是**修复前**行为；修复后「接口值落变量后逐跳」
> 可编译、`cc` 通过、运行正确（单文件实测 `status=201`，rc=0）。仍不成立的两条：SH-73
> （方法结果不能作下一跳接收者）与「返回**局部**接口值装箱取局部地址」（`return (…){ (void *)&c, … }`，
> 见 §7.3 末段；`self` 已修，非 `self` 的局部仍悬垂）。

## 0. 环境与自举

```sh
cd ct-lang
cc -Wall -Wextra -std=c99 selfhost/l0/ctc.c -o /tmp/p/ctc
/tmp/p/ctc selfhost/l1/ctc.ct -o /tmp/p/l1.c
cc -Wall -Wextra -std=c99 /tmp/p/l1.c -o /tmp/p/l1
/tmp/p/l1 build selfhost/l2/driver.ct -o /tmp/p/l2src
cc -Wall -Wextra -std=c99 /tmp/p/l2src/*.c -o /tmp/p/l2
/tmp/p/l2 build -I selfhost/ct-ast selfhost/ct-ast/main.ct -o /tmp/p/astsrc
cc -Wall -Wextra -std=c99 /tmp/p/astsrc/*.c -o /tmp/p/ct-ast
/tmp/p/ct-ast --version        # ct-ast v0.44.1
```

单文件探针：`/tmp/p/ct-ast x.ct -o x.c`，再 `cc -Wall -Wextra -std=c11 x.c`。
多单元探针：`/tmp/p/ct-ast build --emit-c -I <src> <src>/main.ct -o <out>`，
再 `cc -std=c11 -I <shim 目录> <out>/*.c`。

## 1. 结论摘要

1. **`char *` 上没有任何可用的 `impl` 形态。** 裸 `impl char *`、`impl Trait for char *`、
   放到 `.h.ct`、别名、加括号、`.m.ct` 内，六种写法全部在编译期失败。
2. **`char *` 上挂方法的合法形态是 `.m.ct` 里的类型宿主静态映射**
   （`map trait T for type char * { … }`）。它支持字符串字面量作接收者。
3. **链式能否成立，取决于每一跳走哪条路径。**
   - 类型宿主静态映射：任意跳数都成立，接收者可以是字面量、变量、CT 已声明函数的调用结果，
     也可写在声明初始化式里。
   - 经典 `impl` / 固有 `impl`：方法结果不能作下一跳接收者，链式在第二跳被拒；
     而且返回 struct 的 impl 方法本身会发射非法 C。
4. **建议里真正要保住的性质（工厂隐藏构建 + 产物带方法 + 配置返回 self + 链式）可以成立**，
   但必须整体落在类型宿主静态映射上，不是 `impl`，也不是接口虚表对象。
5. 此前报告的三个错误原文全部复现，且分别对应不同原因，不能合并成“不支持链式”。

## 2. `char *` 上挂方法的语法形态

### 2.1 裸 `impl char *`

```c
trait UrlOps { char *get(); }

impl char * {
    char *get() { return self; }
}

int main(void) { return 0; }
```

```text
src/p2b_inherent_char_ptr.ct:5:11: error: impl of an unknown trait
ct-ast rc=1
```

### 2.2 `impl Trait for char *`（普通 `.ct`）

```c
trait UrlOps { char *get(); }

impl UrlOps for char * {
    char *get() { return self; }
}

int main(void) { return 0; }
```

```text
src/p2_impl_char_ptr.ct:7:22: error: impl for undefined struct 'char'
ctc: 1 error(s) generated
ct-ast rc=1
```

### 2.3 同样的 `impl` 放进 `.h.ct` 单元

`text.h.ct`：

```c
namespace text;

pub trait TextOps { int len(); }

impl TextOps for char * {
    int len() { return 0; }
}
```

`main.ct`：`import text::text;` 后调用 `"abc".len()`。

```text
forms/h_impl/src/text/text.h.ct:7:23: error: impl for undefined struct 'char'
ctc: 1 error(s) generated
build rc=1
```

### 2.4 用类型别名绕开

```c
namespace text;

pub trait TextOps { int len(); }

type CStr = char *;

impl TextOps for CStr {
    int len() { return 0; }
}
```

```text
forms/alias_impl/src/text/text.h.ct:9:23: error: impl for undefined struct 'CStr'
ctc: 1 error(s) generated
build rc=1
```

### 2.5 加括号

```c
impl TextOps for (char *) {
    int len() { return 0; }
}
```

```text
forms/paren_impl/src/text/text.h.ct:7:18: error: expected a struct name
ctc: 1 error(s) generated
build rc=1
```

### 2.6 放进 `.m.ct` 单元

```c
namespace mem;

pub trait TextOps { int len(); }

impl TextOps for char * {
    int len() { return 0; }
}
```

```text
forms/m_impl/src/mem/mem.m.ct:7:1: error: a .m.ct unit cannot contain an impl
ctc: 1 error(s) generated
build rc=1
```

### 2.7 `impl Trait for type char *`

```c
impl TextOps for type char * {
    len(s) -> 0;
}
```

```text
src/p15_for_type_impl_ct.ct:5:23: error: impl for undefined struct 'type'
ctc: 1 error(s) generated
ct-ast rc=1
```

**小结**：`impl` 的属主位置只接受已声明的 struct 名，`char *` 与别名都不在其中；
`.m.ct` 明确禁止 `impl`。这是**语法/属主形态的限制**，不能靠换限定符绕过。

## 3. 合法形态：`.m.ct` 类型宿主映射

### 3.1 字符串字面量接收者（m1）

`text.m.ct`：

```c
namespace text;

#include "text.shim.h"

pub trait TextOps { int len(); }

map trait TextOps for type char * {
    len(s) -> host_len(s);
}
```

`main.ct`：

```c
//@ct-requires: ct-ast
import text::text;
#include <stdio.h>

int main(void)
{
    char *url = "https://example.com";
    printf("literal %d\n", "hello".len());
    printf("var     %d\n", url.len());
    return 0;
}
```

```text
build rc=0
cc rc=0
literal 5
var     19
prog rc=0
```

### 3.2 字符串工厂 + 对象链（m3，建议的完整形态）

`url.shim.h`：

```c
#ifndef URL_SHIM_H
#define URL_SHIM_H

struct Url { char *host; int port; };

static inline struct Url url_parse(const char *s)
{
    struct Url u;
    u.host = (char *)s;
    u.port = 80;
    return u;
}
static inline struct Url url_with_port(struct Url u, int p)
{ u.port = p; return u; }
static inline int url_port(struct Url u) { return u.port; }
static inline char *url_host(struct Url u) { return u.host; }

#endif
```

`url.m.ct`：

```c
namespace url;

#include "url.shim.h"

pub type CUrl = struct Url;

pub trait UrlSource { CUrl parse(); }

pub trait UrlBuilder {
    CUrl port(int p);
    int get();
    char *host();
}

map trait UrlSource for type char * {
    parse(s) -> url_parse(s);
}

map trait UrlBuilder for type CUrl {
    port(u, p) -> url_with_port(u, p);
    get(u)     -> url_port(u);
    host(u)    -> url_host(u);
}
```

`main.ct`：

```c
//@ct-requires: ct-ast
import url::url;
#include <stdio.h>

int main(void)
{
    int p = "https://example.com".parse().port(8443).get();
    char *h = "https://example.com".parse().host();
    printf("%s %d\n", h, p);
    return 0;
}
```

```text
build rc=0
cc rc=0
https://example.com 8443
prog rc=0
```

生成的 C（单条嵌套调用，无 wrapper / vtable / 临时对象）：

```c
int p = url_port((url_with_port((url_parse(("https://example.com"))), (8443))));
char * h = url_host((url_parse(("https://example.com"))));
```

### 3.3 链的入口位置

| 入口形态 | 探针 | 结果 |
| --- | --- | --- |
| 字符串字面量起手 | m3 | rc=0，三跳全通，写在声明初始化式里也成立 |
| 变量起手，继续链 | m4 | rc=0 |
| CT 已声明函数返回对象后起手 | m4b（`static struct Builder my_make(int)`） | rc=0，链通 |
| 不透明 C shim 函数调用后起手 | m4call（`builder_make(100).add(…)`） | rc=1，见 §4.7 |

m4 输出：`16 118`（变量起手两条链各三跳）。
m4b 输出：`118`（`my_make(100).add(5).add(6).add(7).value()`）。

## 4. 不成立的链式形态（经典 `impl` / 固有 `impl` / 接口对象）

### 4.1 无映射时字符串上直接调方法

```c
struct Url { int port; }
trait UrlOps { int get(); }
impl UrlOps for Url { int get() { return self->port; } }

int main(void)
{
    printf("%d\n", "https://example.com".get());
    return 0;
}
```

```text
src/p3_literal_no_map.ct:17:1: error: no method 'get' for type 'char *'
ct-ast rc=1
```

正确读法：`char *` 上没有全局方法；只有被导入的 `.m.ct` 映射单元声明过的方法才存在。

### 4.2 动态派发链写在声明初始化式

```c
trait Steps { Builder add(int by); int value(); }
struct Builder { int n; } use Steps;

impl Steps for Builder {
    Builder add(int by) { self->n = self->n + by; return *self; }
    int value() { return self->n; }
}

int main(void)
{
    Builder b = { 0 };
    int r = b.add(1).add(2).add(3).value();
    printf("%d\n", r);
    return 0;
}
```

```text
src/p4_impl_self_chain.ct:23:1: error: a method call on a temporary is only allowed at the start of a statement or of an assignment
ct-ast rc=1
```

### 4.3 动态派发链写在语句位置（此前报告的“第二跳”错误）

```c
b.add(1).add(2);
b.add(1).value();
```

```text
src/p4c_trait_chain_stmt.ct:23:1: error: method receiver must be a variable, an element, a call or a field chain
ct-ast rc=1
```

### 4.4 动态派发链写在赋值右值

```c
r = b.add(1).add(2).add(3).value();
```

```text
src/p9_assignment_chain.ct:24:1: error: a method call on a temporary is only allowed at the start of a statement or of an assignment
ct-ast rc=1
```

### 4.5 链的第一跳是普通函数调用

```c
int r = make(10).add(1).add(2).value();
```

```text
src/p5_call_self_chain.ct:28:1: error: a method call on a temporary is only allowed at the start of a statement or of an assignment
ct-ast rc=1
```

单跳 `make(10).add(1)` 能通过前端，但发射的 C 非法：

```text
src/p10_one_hop_call.ct:13: warning: signature mismatch: 'add' in impl of 'Steps' for 'Builder':
    return type 'struct Builder' does not match the trait's 'Builder'
/tmp/p/p10_one_hop_call.c:6:5: error: type name requires a specifier or qualifier
    Builder (*add)(void *, int);
/tmp/p/p10_one_hop_call.c:22:8: error: must use 'struct' tag to refer to type 'Builder'
cc rc=1
```

### 4.6 返回 struct 的 trait 方法（不链也不成立）

```c
Builder r = b.add(1);
```

```text
src/p11_trait_struct_return.ct:13: warning: signature mismatch: 'add' in impl of 'Steps' for 'Builder':
    return type 'struct Builder' does not match the trait's 'Builder'
/tmp/p/p11_trait_struct_return.c:6:5: error: type name requires a specifier or qualifier
    Builder (*add)(void *, int);
/tmp/p/p11_trait_struct_return.c:21:8: error: must use 'struct' tag to refer to type 'Builder'
/tmp/p/p11_trait_struct_return.c:39:40: error: no member named 'add' in 'struct Steps_vtbl'
cc rc=1
```

对照：返回 `int` 的 trait 方法正常。

```text
src/p12_trait_int_return.ct: ct-ast rc=0, cc rc=0, 程序输出 "1 1"
```

### 4.7 固有 `impl` 的 `return self` / 链式

单跳 `return self`（`self` 是指针）：

```text
src/p8c_inherent_one_hop.ct: ct-ast rc=0
/tmp/p/p8c_inherent_one_hop.c:13:12: error: returning 'struct Builder *' from a function with
    incompatible result type 'struct Builder'; dereference with *
cc rc=1
```

改成 `return *self` 后单跳合法，但链式仍被拒：

```text
src/p8d_inherent_return_star_self.ct:22:1: error: a method call on a temporary is only allowed at
    the start of a statement or of an assignment
ct-ast rc=1
```

### 4.8 接口/虚表式包装

```c
struct StrView { char *s; int port; } use UrlOps;
static StrView str_of(char *s) { StrView v = { s, 80 }; return v; }

int p = str_of("https://example.com").set(8443).port();
```

```text
src/p13_iface_wrapper_chain.ct:29:1: error: a method call on a temporary is only allowed at
    the start of a statement or of an assignment
ct-ast rc=1
```

### 4.9 不透明 C 函数调用起手（类型宿主映射）

```c
int r = builder_make(100).add(5).add(6).add(7).value();
```

```text
/tmp/ct-probe/m4call/src/main.ct:8:1: error: method receiver must be a variable, an element, a call or a field chain
build rc=1
```

正确写法：先落到有声明类型的变量（m4），或用一个 CT 已声明返回类型的包装函数（m4b）。

### 4.10 退路：自由函数工厂 + 经典 impl（可编译，但不能链）

```c
struct Builder b = make(10);
b.add(1);
b.add(2);
b.add(3);
int v = b.value();
```

```text
src/p14_free_factory_impl_statements.ct: ct-ast rc=0, cc rc=0, 程序输出 "16"
```

这条路径保住了“隐藏构建”，但丢掉了链式：每个配置方法必须单独成句。

## 5. 仓库内基线（复跑）

`examples/13_builder_chain`（字符串工厂 + 类型宿主，三跳链；已按范式改写，不再从变量起手）与
`examples/14_scalar_host`（`int` / `char *` / `double` 的类型宿主）在多单元 build 下均复跑通过：

```text
examples/13_builder_chain: build rc=0, cc rc=0, 输出 "chain  16" / "second 118"
examples/14_scalar_host:   build rc=0, cc rc=0, 输出 "twice 42" … "bytes 8192"
```

## 6. 判定

- **“语法形态问题”**：`impl char *` 的所有变体属于 `impl` 只接受 struct 名这一形态约束；
  换成 `.m.ct` 类型宿主映射即可在 `char *` 上挂方法。
- **“能力缺失”**：经典 `impl` 与固有 `impl` 的方法结果不能作下一跳接收者；返回 struct 的
  trait 方法还会发射未加 `struct` 限定的非法 C。这两条不是换语法能解决的，属当前实现边界。
- **建议的范式**：字符串起手 + 链式可以成立，但只能写成“`.m.ct` 类型宿主映射 + C shim 按值返回
  宿主 struct”；完整三段（字符串 → factory → **由 trait 定义的对象类型** → 接口上链式）在 0.44.1
  上不成立，见 §7。

## 7. 接口形态补测（2026-11-14）

### 7.1 自引用接口返回

```c
trait Counter {
    Counter add(int n);
    int value();
}
struct CounterImpl { int n; } use Counter;
impl Counter for CounterImpl {
    Counter add(int n) {
        struct CounterImpl c = *self;
        c.n = c.n + n;
        return c;
    }
    int value() { return self->n; }
}

int main(void) {
    struct CounterImpl ci = { 0 };
    Counter c = ci;
    Counter d = c.add(1);
    printf("%d\n", d.value());
    return 0;
}
```

```text
i1_selfret_onehop.ct:25:25: error: cannot infer the type to box
ct-ast rc=1
```

`Self add(...)`、显式 `return (Counter)c;` 同样报同一句；单跳赋值与 `c.add(1).value()` 都在调用点失败。

### 7.2 跨接口返回

```c
trait HttpResponse { int status(); }
trait HttpRequest  { HttpResponse send(); }
...
HttpResponse resp = req.send();
```

```text
j4_cross_iface_return.ct:41:35: error: cannot infer the type to box
ct-ast rc=1
```

接口值上继续调用（`c.add(1).value()`）：

```text
i2_chain.ct:25:1: error: method receiver must be a variable, an element, a call or a field chain
ct-ast rc=1
```

声明初始化式里的 `.send().status()`：

```text
i4_response_chain.ct:48:1: error: a method call on a temporary is only allowed at the start of a statement or of an assignment
ct-ast rc=1
```

### 7.3 生成 C 对比（方法不调用时）

接口返回的 vtable 槽是**合法 C**：

```c
struct HttpResponse_vtbl {
    struct HttpResponse_iface (*send)(void *);
};
```

自引用接口返回同样是合法槽：

```c
struct Counter_vtbl {
    struct Counter_iface (*add)(void *, int);
};
```

返回 struct 的槽仍是非法 C（缺 `struct` 标签）：

```c
struct Steps_vtbl {
    Builder (*add)(void *, int);
};
```

结论：接口返回的**声明与 vtable 发射**已经正确。调用点消费返回值的历史缺口（SH-72）已修：
`HttpResponse res = req.send();` 现在可以编译（实测 rc=0）。仍不能做的是把方法结果直接当下一跳
接收者（SH-73）。另外，自引用方法体里 `return c;` 会把栈上局部 `c` 装箱为
`(struct Counter_iface){ (void *)&c, ... }`，返回后指针悬空；这一条**仍未修**（SH-74 只覆盖了
`return self;`），实测可执行但读到错误值（期望 `201`，实际 `200`，UB）。

### 7.4 字符串 factory 返回接口值

```c
/* http.h.ct 提供 trait/struct/impl 与 make_request */
/* http.m.ct 想 import http::http 后写 method(s) -> make_request(s) */
```

```text
src/main.ct:2:1: error: import 'http/http' is ambiguous: both .../http.h.ct and .../http.m.ct exist
```

把映射单元拆到独立 namespace 后：

```text
src/httpmap/httpmap.m.ct:1:1: error: a .m.ct unit can only import another .m.ct unit
```

`.m.ct` 无法引用 `.h.ct` 里的 trait/struct，因此 `char *` 映射方法不能返回由 `.h.ct`
定义的接口值；字符串 factory 产出接口值这条路走不通。

### 7.5 逐层对照表

| 层 | 接收者类型 | 对外形态 | 0.44.1 可用性 | 生成 C |
| --- | --- | --- | --- | --- |
| 字符串起手 | `char *` | `.m.ct` 类型宿主映射 | 可用 | `http_request_new("…", "GET")` |
| 工厂产物（静态宿主） | `struct HttpRequest` | `.m.ct` 映射 | 可用，但这是 struct 宿主，不是接口值 | `http_request_header(...)` |
| 配置方法链 | `struct HttpRequest` | 静态映射 | 可用 | 嵌套裸 C 调用 |
| 配置方法（impl） | `struct HttpRequest` | 固有 `impl` | 单跳可用；第二跳报 `method receiver must be ...` | `HttpRequest_header(&r, …)` |
| 工厂产物（接口值） | `HttpRequest` | `.h.ct` trait + 自由函数 factory | factory 可返回接口，但字符串起手无法接到它 | `struct HttpRequest_iface` |
| 接口上配置 | `HttpRequest` | trait 方法 | 单跳可用；返回值可赋给接口变量（SH-72 已修）；方法结果不能作下一跳（SH-73） | vtable 槽合法，调用点可消费 |
| 响应收口 | `HttpResponse` | trait 方法 | 单跳可用；`.send().status()` 报临时值错误 | vtable 槽合法 |
