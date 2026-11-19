# ct — C with Traits 编译器

> **v0.74.0** · 中文 · [English](README.en.md)

**ct** 是一个 **source-to-source 编译器**：把带 trait 语法的 `.ct` 源文件翻译成纯 C 的 `.c` 文件。
编译路径（`ct compile` / `ct build`）不做类型检查、不做优化；可选的 `ct check` 只做受限语义检查
（调用点 arity、实参类型、trait 方法歧义、impl 签名漂移）。生成物是**可读的普通 C**，不依赖任何运行时库，vtable 与 `_self` 强转等样板代码都由编译器生成。
已完成的能力与后续阶段见 [docs/roadmap.md](docs/roadmap.md)，术语见 [docs/glossary.md](docs/glossary.md)。

---

## 中文

### 0. 真实用法展示

下面四条都是完整程序，按注里的命令就能跑；代码块后面是真实输出。它们各自解决一个具体问题。

**范式定义（三段，顺序固定）：**

1. 以字符串为起点，不是构造器。
2. 通过 factory 创建由 trait 定义的对象类型，不是 struct；struct 是实现细节，不出现在使用者代码里。
3. 链式调用挂在接口上，配置方法返回同一接口类型。

这三段只在 [language-spec §4.10.1](docs/language-spec.md) 完整展开一次（唯一权威定义），
本页只复述定义；两档路径的判断依据、0.44.1 的逐段边界与报错原文也都在那里。**0.44.1 上完整三段
还不能原样写出来**：第 2 段被单元矩阵挡住（语言限制），第 3 段被「方法结果不能作接收者」与
「返回局部接口值悬垂」挡住（实现限制；SH-72 / SH-74 已修，但不解除这两条）。下面 HTTP 那条是
**当前最接近的可跑形态——静态宿主**，不是完整路径的已成立证明。

| 样例 | 路径 | 机制 | 解决什么问题 |
| --- | --- | --- | --- |
| 0.1 HTTP 请求 | 完整路径（目标形态；0.44.1 阻塞，最近可跑为静态宿主） | `char *` factory + 对象方法链 | 构造藏在工厂里，调用点只写一条链 |
| 0.2 字符串切分 | 轻量 | `char *` 直接映射 | 无状态转换直接挂方法，不引入对象 |
| 0.3 异构对象 | 接口派发 | `trait` + `Vec<接口值>` | 不同形状一张表，不写 switch |
| 0.4 词频统计 | 容器 | `Map` + `foreach` | 按插入序出报告，不维护并行数组 |

**两档怎么选**：对象没有状态、只有一种实现、调用方不需要面向接口 → 轻量路径；有状态、要多种实现、
调用方要面向接口 → 完整路径。轻量路径不是错写法，简单场景套接口只是绕。

#### 0.1 HTTP 请求：完整路径的目标形态，与当前可跑的静态宿主

**完整路径的目标形态**：`char *` 上挂 factory，factory 返回由 trait 定义的请求对象；
`header` / `timeout` 返回同一接口类型，`send()` 换成响应接口，最后在响应接口上收口。
调用点只有这一条：

```c
int status = "https://api.example.com/users"
                 .method("GET")
                 .header("Accept", "application/json")
                 .timeout(3000)
                 .send()
                 .status();
```

这条链在 0.44.1 上**写不出来**，断点有三处（完整原文、命令与退出码见
[§4.10.1](docs/language-spec.md#4101-链式构建器范式权威定义与两档路径)）：

| 断点 | 实测报错 | 性质 |
| --- | --- | --- |
| 字符串 factory 只能写 `.m.ct`，trait 对象只能写 `.h.ct`，而 `.m.ct` 不能 import `.h.ct` | `error: a type host is only allowed in a .m.ct unit` / `ctc: cannot resolve import 'http/http'`（rc=1） | 语言限制 |
| 方法调用的结果不能作下一跳接收者 | `error: method receiver must be a variable, an element, a call or a field chain`（rc=1） | 本版实现限制（SH-73） |
| impl / 自由函数返回**局部**接口值，装箱取的是局部地址 | 可编译、可执行，但结果为悬垂读（实测 `200`，期望 `201`） | 本版实现缺陷 |

SH-72（调用点返回类型推断）与 SH-74（`return self` 发射 `(void *)_self`）已修：接口值**落变量后
逐跳调用**现在能跑（实测 `status=201`，rc=0）。但「一条表达式连跳」与「字符串直接产出接口对象」
仍然不成立。

**当前最接近的可跑形态：静态宿主。** 同样的调用点、同样的链，宿主在映射单元内部是 struct 而不是
trait 对象；每一跳展开成裸 C 调用，没有 vtable 与装箱。下面这条 `ct build` 就能跑。

为什么这样写比「先 new、再逐条 setter」清楚：请求对象的字段和默认值只出现在工厂里，
调用点从上往下读就是执行顺序；`header` / `timeout` 返回请求对象本身，所以中间不需要
任何临时变量。三层接收者依次是字符串、factory 产物、响应对象；使用者代码里不出现 struct 名，
也没有自由函数调用。

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

/* 工厂：构造只在这里发生，调用点看不到这些字段。 */
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

`http.m.ct`——三层方法各自绑在哪个宿主上：

```c
namespace http;

#include "http.shim.h"

/* 第 1 层：char * 只做工厂。接收者是字符串，产物是 HttpRequest。 */
pub type CRequest = struct HttpRequest;
pub type CResponse = struct HttpResponse;

pub trait HttpEntry {
    CRequest method(char *verb);
}

/* 第 2 层：HttpRequest 的配置方法都返回 CRequest（宿主本身），所以能继续链。 */
pub trait RequestBuilder {
    CRequest header(char *name, char *value);
    CRequest timeout(int ms);
    CResponse send();
}

/* 第 3 层：HttpResponse 上的收口方法。 */
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

`main.ct`——使用者只写链：

```c
//@ct-requires: ct-ast
import http::http;

#include <stdio.h>

int main(void)
{
    /* 第 1 层是字符串；method("GET") 之后接收者变成请求对象。 */
    /* header()/timeout() 各返回对象本身，所以链没有断。        */
    /* send() 返回响应对象，status() 在它上面收口。             */
    int status = "https://api.example.com/users"
                     .method("GET")
                     .header("Accept", "application/json")
                     .timeout(3000)
                     .send()
                     .status();

    /* 同一条链再走一次，这次取响应体；工厂每次都产出新请求对象。 */
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
ct build examples/47_chain_factory/src/main.ct -o /tmp/http47
/tmp/http47
# 200 {"users":3}
```

**执行边界**：`http_request_send()` 是唯一将来碰网络的位置，当前是 stub（固定 200 + JSON）；
其余都是本机内存操作。接真 curl 时只替换 `http.shim.h` 里这组 `http_*` 实现，上面的链和
`http.m.ct` 不变。

**这一版不是完整路径**：宿主是 `http.m.ct` 里的 struct，不是 trait 定义的对象；`map trait` 把
方法绑到 C 函数，生成物是嵌套裸调用，没有接口值与 vtable。因此它满足第 1 段（字符串起手）与
链式，但不满足第 2 段；需要多实现、调用方面向接口时不能拿它替代完整路径。

#### 0.2 字符串切分：轻量路径，直接挂方法

为什么这样写比「先造一个 Parser 对象」清楚：这里没有状态，也不会有第二种实现，转换就是几次
纯函数式切片；直接挂在 `char *` 上，调用点从字符串读到结果，不需要对象、接口值或 vtable。

`text.shim.h`——普通 C 的两个薄函数：

```c
#ifndef TEXT_SHIM_H
#define TEXT_SHIM_H

#include <string.h>

static inline char *text_split_once(const char *s, char sep)
{
    const char *p = strchr(s, sep);
    return p != 0 ? (char *)(p + 1) : (char *)s;
}

static inline int text_len(const char *s) { return (int)strlen(s); }

#endif
```

`text.m.ct`——把两个方法挂到 `char *` 上；这里的 `trait` 只是绑定表，不产生接口值：

```c
namespace text;

#include "text.shim.h"

pub trait TextSteps {
    char *split_once(char sep);
    int len();
}

map trait TextSteps for type char * {
    split_once(s, sep) -> text_split_once(s, sep);
    len(s)            -> text_len(s);
}
```

`main.ct`——两次 `split_once` 都返回 `char *`，所以能继续链：

```c
//@ct-requires: ct-ast
import text::text;

#include <stdio.h>

int main(void)
{
    int n = "alpha,beta,gamma".split_once(',').split_once(',').len();
    char *last = "alpha,beta,gamma".split_once(',').split_once(',');

    printf("%s %d\n", last, n);
    return 0;
}
```

```sh
ct build examples/48_string_steps/src/main.ct -o /tmp/text48
/tmp/text48
# gamma 5
```

**执行边界**：无 stub；`strchr` / `strlen` 是 libc，其余是本机内存操作。这一档不引入 trait 对象，
也不解决多态；需要多实现时走上一条完整路径。

#### 0.3 异构对象：一张表里放不同形状

为什么这样写比 `enum kind` + `switch` 清楚：新增一种形状只加一个 `impl`，`foreach` 里的
`item.area()` 一行都不用改；容器里存的是接口值，调用点不需要知道具体类型。

```c
//@ct-requires: ct-ast
#include <stdio.h>

trait Shape {
    int area();
}

struct Rect {
    int w;
    int h;
} use Shape;

struct Circle {
    int r;
} use Shape;

impl Shape for Rect {
    int area() { return self->w * self->h; }
}

impl Shape for Circle {
    int area() { return 3 * self->r * self->r; }
}

int main(void)
{
    Vec<Shape> shapes;
    struct Rect r = { 3, 4 };
    struct Circle c = { 5 };
    int total;

    /* 两个不同形状进同一个容器：push 时装箱，容器只保存接口值。 */
    shapes.h = 0;
    shapes.push(r);
    shapes.push(c);

    /* 遍历时只写 item.area()；新增形状只要加一个 impl，这段不用改。 */
    total = 0;
    foreach (shapes) {
        total = total + item.area();
    }
    printf("rect %d, circle %d, total %d\n", r.area(), c.area(), total);

    shapes.release();
    return 0;
}
```

```sh
ct compile shapes.ct -o shapes.c && cc shapes.c -o shapes && ./shapes
# rect 12, circle 75, total 87
```

**执行边界**：无 stub；容器与派发都在本机执行。

#### 0.4 词频统计：`Map` 按插入序出报告

为什么这样写比「并行数组 + 手工查找」清楚：`Map<char *, int>` 直接表达「词 → 次数」，
`get` 命中就加一，不命中就 `put`；`foreach` 给出插入序，报告顺序稳定，不需要额外的索引表。

```c
//@ct-requires: ct-ast
#include <stdio.h>

int main(void)
{
    char *words[6] = { "go", "ct", "go", "rust", "ct", "go" };
    Map<char *, int> counts;

    /* 词表进 Map；键按 strcmp 比较，重复词原位加一，不需要并行数组。 */
    counts.h = 0;
    foreach (words) {
        int *slot;
        slot = counts.get(item);
        if (slot != 0) {
            *slot = *slot + 1;
        } else {
            counts.put(item, 1);
        }
    }

    /* Map 按插入序遍历，直接打印就是一份稳定报告。 */
    foreach (counts) {
        printf("%s=%d\n", item.key, item.value);
    }

    counts.release();
    return 0;
}
```

```sh
ct compile wordcount.ct -o wordcount.c && cc wordcount.c -o wordcount && ./wordcount
# go=3
# ct=2
# rust=1
```

**执行边界**：无 stub；`printf` 走 libc，其余都是本机内存操作。

### 1. 快速开始

§0.1 的 HTTP 链就是本仓库的第一个完整样例。先跑它（`ct` 由下面的安装步骤提供；
L0 单文件种子没有 `import` / `map`，跑不了这条）：

```sh
ct build examples/47_chain_factory/src/main.ct -o /tmp/http47
/tmp/http47
# 200 {"users":3}
```

然后安装完整编译器，或只构建 L0 种子跑单文件程序：

```bash
# 1a) 安装（下载源码 → 本地四级自举 → 装到 ~/.local/bin）
curl -fsSL https://raw.githubusercontent.com/samxxu/ct-lang/main/install.sh | sh

# 1b) 或者不安装，只用 L0 种子（单文件、核心语法；没有 ct，下面用 ./ctc）
gcc selfhost/l0/ctc.c -o ctc

# 2) 编译 .ct 到 .c（只有 .h.ct 输入才同时写同名 .h）
ct compile examples/01_greeter/greeter.ct -o /tmp/greeter.c      # 走了 1a
./ctc examples/01_greeter/greeter.ct -o /tmp/greeter.c           # 走了 1b

# 3) 用系统 C 编译器构建产物
gcc /tmp/greeter.c -o /tmp/greeter && /tmp/greeter
```

新用户从这里开始：[docs/tutorial.md](docs/tutorial.md)——逐章教程，每条命令都可直接粘贴。

### 2. 常用命令

| 命令 | 作用 |
| --- | --- |
| `ct <in.ct>` / `ct compile <in.ct>` | 单文件编译：普通 `.ct` 只写 `.c`，`.h.ct` 才额外写同名 `.h`；只接受**单文件单元**，`import` 需改用 `ct build`（`-I` 同理只对 build 生效，compile 下会提示被忽略） |
| `ct <in.ct> -o <out.c>` | 指定输出路径 |
| `ct build <in.ct>… [-o <exe>]` | 多文件构建：默认把生成的 `.c` 放进 `.ctbuild/`（`--outdir` 可改），再调用本地 C 编译器产出可执行文件（`-o` 是文件名，默认 `a.out`）；`--emit-c` 只发射 `.c`（`.h.ct` 另写 `.h`），此时 `-o` 是输出目录；`--runtime-checks` 在接口派发前检查空 vtable（默认关闭，关闭时产物不变） |
| `ct build --freestanding [--alloc <m,f[,r,c]>]` | 裸机生成契约（PH-64）：`--freestanding` 不发射构造函数、不隐式拉内置层与 libc/堆；无初值的文件作用域 trait 数组带位置硬错。`--alloc` 把编译器与源码里的 `malloc`/`free`（可扩展 `realloc`/`calloc`）换成目标分配器，并在每个生成单元头部补原型；`--freestanding` 下未映射的堆调用同样硬错 |
| `ct build --lib <root.h.ct> [-o <lib.a>]` | C ABI 静态库：根 `.h.ct` 的 C 兼容 `pub` 函数进入 `<base>.abi.h`，产物为 `lib<base>.a`（`-o` 可改；`--outdir` 默认 `.ctbuild`）；泛型模板跳过并警告，不兼容签名/`main`/`pub` 全局/shim 硬错；`nm -g` 面 ⊋ 导出面，只有 `.abi.h` 的声明是 ABI（Phase 39） |
| `ct check <in.ct>` | 只跑受限语义检查、不写 `.c`（含 `import` 时复用 `ct build` 的单元图）：调用点 arity / 实参类型 / trait 方法歧义 / impl 签名漂移（以及既有的 leak / 借用类发现）一律以 `error:` 报告，有任何发现退出 `1`，干净退出 `0`（`--diagnostics=json` 时对象带 `"severity":"error"`，并带 `"col"`） |
| `ct … --emit-map <file\|->` | 写出反向映射表 JSON（trait / struct / 函数 / impl → 生成的 C 符号） |
| `ct get` / `ct update` / `ct install` / `ct verify` / `ct migrate` | 包管理：拉包进共享 store（`$CT_HOME/pkg/<publisher>/<name>/<version>/`）、写 v2 `ct.lock`；`ct build` 自动读 lock，离线校验 / 迁移并打印构建命令（裸名可经 `--index` / `CT_INDEX` 查显式索引；包作者见 [docs/package-guide.md](docs/package-guide.md)，包仓发布/索引接入规则见 [提案](docs/proposals/ct-pkg-package-maintainer-rules.md)，待目标组受理）；官方包在 [ct-pkg](https://github.com/ct-pkg)：`hal`（契约）、`hal-posix`（平台）、`std`（标准库，含 C 映射）。S7 后不再读写 `vendor/`；旧工程用 [`ct migrate`](docs/package-guide.md#8-v1-迁移ct-migrate) 一次性迁入 store |
| `ct -v` / `ct -h` | 版本 / 用法 |

退出码：成功 `0`，语法或 I/O 错误 `1`（`ct check` 有任何语义发现，或 `ct build` 遇到 impl 签名漂移，也是 `1`）。源码诊断格式为 `文件:行:列: error: 描述`；驱动层错误以 `ctc:` 开头
（二进制改名为 `ct` 也不变，以保持日志与断言稳定）。完整开关（`-I` / `--std` / `--line` / `--diagnostics` /
`--ns-root`）见[教程 §11](docs/tutorial.md#11-命令行速查)。

### 3. 能力一览

- **两档写法：轻量路径 vs 完整路径**：轻量路径把方法直接挂在基本类型上（方法返回自身类型即可链），不引入 trait 对象；完整路径是字符串 → factory → 由 trait 定义的对象类型 → 接口链。判断依据（有没有状态、要不要多实现、调用方是否面向接口）与 0.44.1 的接口链边界见 [language-spec §4.10.1](docs/language-spec.md)
- **trait**：`trait` / `impl` / `use`，方法派发，trait 当类型（接口值 / 数组 / 字段 / 装箱），trait 默认方法
- **内存**：`Drop` / `delete`、`own`（AutoDrop）、块级 `defer`（Phase 38）、路径敏感泄漏告警、`borrow` + `Handback`
- **模块**：`namespace` / `import` / `pub` / 多文件 `ct build` / 目录 = namespace
- **映射**：`map trait T for instance …`、`.m.ct` 零成本静态映射、伴生 C shim、`test/bindings/` 声明式 C 库对接
- **透传**：`#ct-raw` / `#ct-endraw` 原样块（宏与手写 C 逐字节进入生成的 `.c`）
- **诊断与工具**：`#line` 溯源、`--diagnostics=json|text`、多错误恢复、增量缓存、`ct get` / `ct install`
- **泛型函数**：`T name<T>(…)` + `name<int>(…)`，编译期单态化（Phase 26）；**约束泛型** `T name<T: Trait>(…)`（Phase 28）
- **泛型 struct 与内置容器**：`struct Name<T, U>` + `impl<T> Name<Args>` 静态派发（Phase 29）；`Vec<T>` / `Map<K,V>` 免 import，`foreach` 按插入序遍历 `Map`
- **泛型 trait**：`trait Iter<T>` / `impl Iter<int> for S` / `T: Iter<int>` 约束，实例按实参编码单态化（Phase 35）
- **标准结果类型**：`Option<T>` / `Result<T, E>` 内建于 `lib/std`，`is_some` / `is_ok` / `unwrap` 等为固有方法（Phase 34）
- **C ABI 静态库**：`ct build --lib` 把根 `.h.ct` 的 C 兼容 `pub` 函数导出为 `.abi.h` + `lib<base>.a`（Phase 39）
- **原子并发**：`atomic int` / `atomic long` / `atomic bool` / `atomic void *` + `ct_atomic_load` / `ct_atomic_store` / `ct_atomic_cas`（seq_cst，C11；`ct build` 自动切 `-std=c11`）（Phase 41）
- **方法级 `pub`**：`impl` 固有方法默认私有（不进 `.h`、`static`）；写 `pub` 才跨单元公开；trait impl / `pub impl` 硬错（Phase 42）
- **`return err:` 载荷契约**：`err:` 载荷必须可赋给函数返回类型；不一致 L43-1 硬错，四入口一致，不写坏 C（Phase 43）
- **后缀 `?` 错误传播**：`expr?` 把 `Result` 失败以 `Outer::err` 返回，成功取 `value`；L44-1/2/3；`?:` 消歧（Phase 44）
- **明确不做**：继承、默认编译路径的类型检查（`ct check` 只做受限检查）、优化（语言在 `1.0.0` 才定稿）

每条语法的展开规则以 [docs/language-spec.md](docs/language-spec.md) 为准；写法范例见 [docs/patterns.md](docs/patterns.md)，
内存约定见 [docs/memory-guide.md](docs/memory-guide.md)。

**范式与边界的详读**：本页 §0.1–§0.4 是可运行展示；**权威定义与两档判断依据只在
[docs/language-spec.md](docs/language-spec.md) §4.10.1**，其余文档只引用；教程开篇的走读见
[docs/tutorial.md](docs/tutorial.md)；可运行样例
[examples/47_chain_factory/src/main.ct](examples/47_chain_factory/src/main.ct) 与
[examples/48_string_steps/src/main.ct](examples/48_string_steps/src/main.ct)（均由 `check-warnings.sh`
的 build-mode 段跑）。HTTP 那条的 `send()` 是 stub，真实接线位置见 §0.1 的「执行边界」。

### 4. 仓库结构

`selfhost/` 是自举链：`l0/`（C 种子）→ `l1/`（冻结）→ `l2/`（回归 oracle）→ `ct-ast/`（主线，提供 `ct` 安装入口）；
`test/` 是测试与 golden；`docs/` 是文档；标准库是独立的 ct-pkg 包 `std`（`ct get std` 获取，不随仓库发布）；`test/bindings/` 是声明式 C 库 binding；`issues/` 是审查台账；`AGENTS.md` 是改动规约。
目录级说明见 [selfhost/README.md](selfhost/README.md)、[test/README.md](test/README.md) 与 [docs/architecture.md](docs/architecture.md)。

### 5. 文档与测试

- 文档导航：[docs/README.md](docs/README.md)
- 测试：`bash selfhost/check-all.sh` 跑 11 道硬门禁；分层地图见 [test/README.md](test/README.md)
- 改动代码前先读 [AGENTS.md](AGENTS.md)

### 6. 许可

GPL-3.0-or-later（编译器本体，见 [LICENSE](LICENSE)）；生成的 `.c`/`.h` 与你的 `.ct` **不受 GPL 约束**
（[LICENSE.EXCEPTION](LICENSE.EXCEPTION)）；`examples/`、`test/`、`editors/` 为 MIT。

For commercial licensing or exceptions, contact: samxxu@gmail.com

### 7. 联系

作者 Sam X. Xu · samxxu@gmail.com · 问题与建议优先开 [Issue](https://github.com/samxxu/ct-lang/issues)。
- **C 边界**（Phase 65）：外部代码默认 strict——`.ct/.h.ct` 禁直接 `#include`、`#ct-raw`、`extern` 与函数式宏，出口是 `<base>.shim.h` 或 `.m.ct`；包用 `ct.pkg` 的 `c-boundary`、命令用 `--c-boundary=strict|allow`。
- **libc I/O 例外**（Phase 66）：`printf`/`scanf`/`puts` 族按调用补头（`<stdio.h>`），宽字符组补 `<wchar.h>`；没有调用不带系统头，`--freestanding` 下不补。

