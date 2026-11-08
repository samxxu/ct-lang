# CT 入门教程

> 中文 · [English](#english)

> **适用版本**：当前主线 **ct-ast**（不在此固定版本号，实际版本以 `ct -v` 为准）。本教程只使用 `examples/**` 与 `test/**` 中已被门禁
> 跑过的写法，每条命令都可以直接粘贴执行；语法细节以 [language-spec](language-spec.md) 为准。
>
> 读完你会知道：怎么装、怎么编译第一个程序、生成物长什么样、方法派发怎么写、接口怎么装箱、
> 多文件怎么组织、内存怎么管、`map` 怎么把 trait 绑到已有 C 库，以及哪些写法会直接报错。

---

## 0. 安装

需要三样东西：一个 C 编译器（`cc`，macOS 的 clang 或 GCC ≥ 8）、`curl` 或 `wget`、`tar`。

```sh
curl -fsSL https://raw.githubusercontent.com/samxxu/ct-lang/main/install.sh | sh
```

它会：下载源码归档 → 本地四级自举（L0 → L1 → L2 → **ct-ast**）→ 把 `ct` 装到 `~/.local/bin`
→ 用符号链接补上 `ctc` 别名。只下载源码，**不下载预编译二进制**，也不需要 `git`。

```sh
ct -v            # ct v0.16.0        （安装入口，能力最全）
ctc -v           # ctc v0.16.0       （兼容别名，同一个二进制）
```

| 需求 | 做法 |
| --- | --- |
| 装到别处 | `install.sh --prefix "$HOME/bin"` |
| 装指定版本 | `install.sh --version v0.16.0`（默认装 `main`） |
| 从本地 clone 装（离线） | `CT_SOURCE_DIR=. sh install.sh` |
| 换编译器 | `CC=gcc sh install.sh` |
| 只想试一下，不安装 | `gcc -Wall -Wextra -std=c99 selfhost/l0/ctc.c -o ctc`（L0 只支持单文件核心语法） |

`install.sh` 是本仓库**唯一**的安装脚本：没有 Makefile、没有第三方依赖、不进编译路径。
GCC ≥ 8 用户不必手工加 `-Wno-format-truncation`，脚本会自己探测。

## 1. 第一个程序：一个 trait、一个 struct、一次实现

`.ct` 文件就是「普通 C 代码 + 几个声明式构造」的混合体。下面这个文件只多了 `trait` 与 `impl` 两种构造
（完整版见 [examples/01_greeter/greeter.ct](../examples/01_greeter/greeter.ct)）：

```c
#include <stdio.h>

trait Greeter {
    void greet();
    void greet_name(char *name);
}

struct Person {
    char *name;
    int age;
} use Greeter;

impl Greeter for Person {
    void greet() {
        printf("Hello, I'm %s, age %d\n", self->name, self->age);
    }
    void greet_name(char *name) {
        printf("Hello %s, I'm %s\n", name, self->name);
    }
}

int main() {
    Person p = { .name = "Tom", .age = 36 };
    p.greet();
    p.greet_name("Jerry");
    return 0;
}
```

三条命令跑起来：

```sh
ct hello.ct -o hello.c        # 生成 hello.c（普通 .ct 不写 .h；只有 .h.ct 单元才写）
cc hello.c -o hello           # 生成物是普通 C，编译器只需看到 .c
./hello
```

```
Hello, I'm Tom, age 36
Hello Jerry, I'm Tom
```

三件事要记住：

1. **`self` 是隐式的**。`impl` 里的方法体直接写 `self->name`，不用声明参数，也不用强转。
2. **`use Greeter` 放在 struct 收尾处**，决定这个 struct 带哪些 vptr 字段。
3. **`impl` 必须实现 trait 的每一个方法**，少一个就编译期报错。

## 2. 看懂生成物：命名契约

生成的 C 是可读的，规则固定（[language-spec §5](language-spec.md)）：

| 产物 | 规则 | 例子 |
| --- | --- | --- |
| vtable 类型 | `<Trait>_vtbl` | `struct Greeter_vtbl` |
| 接口值类型 | `<Trait>_iface` | `struct Greeter_iface`（`{ self, vt }` 胖指针） |
| struct 里的 vptr 字段 | `__<trait 小写>_vptr` | `__greeter_vptr` |
| 方法实现 | `<Struct>_<Trait>_<method>` | `Person_Greeter_greet` |
| vtable 变量 | `<Struct>_<Trait>_vtable` | `Person_Greeter_vtable` |
| 隐式参数 | 固定 `self`，体内强转目标固定 `_self` | — |

把 `hello.ct` 展开后，`p.greet();` 变成 `p.__greeter_vptr->greet(&p);`——**所有方法调用都是
vptr 调用**，没有类型检查、没有特例。这就是它「不做优化、生成物可读」的意思。

## 3. 方法派发：接收者可以是什么

同一套 `对象.方法()` 重写覆盖多种接收者形态（见 [examples/03_receivers](../examples/03_receivers/receivers.ct)、
[examples/04_rvalue](../examples/04_rvalue/rvalue.ct)、[examples/05_body_dispatch](../examples/05_body_dispatch/body_dispatch.ct)）：

| 写法 | 生成 |
| --- | --- |
| `p.greet();` | `p.__greeter_vptr->greet(&p);` |
| `q->greet();`（`q` 是 `Person *`） | `q->__greeter_vptr->greet(q);` |
| `ps[i].greet();` | 先算下标，再取 vptr |
| `slots[0]->greet();`（指针数组元素） | 同上，元素当指针用 |
| `b.who->greet();`（字段链） | 逐级解引用后派发 |
| `make_person("Ann", 30).greet();` | 接收者**只求值一次**，提升到临时变量 |
| `impl` 方法体里的 `self->lhs->emit();` / `o->m();` / `one.m();` | 同样走 vptr——递归数据结构靠它 |

`examples/05_body_dispatch` 用一棵 `Add`/`Num` 树演示最后一条：这正是编译器自己遍历 AST 的手法。

## 4. 多个 trait 与对象协作

一个 struct 可以 `use` 多个 trait，同一个 trait 也可以落在多个 struct 上各给一份实现
（[examples/02_market](../examples/02_market/market.ct)）：

```c
trait Purse { int balance(); int spend(int amount); void earn(int amount); }
trait Reporter { void report(); }

struct Trader { char *name; int coins; } use Purse, Reporter;
struct Shop   { char *name; int price; int units; int coins; } use Purse, Reporter;

impl Purse for Trader {
    int spend(int amount) {
        if (amount > self->coins) { return 0; }   /* 钱不够，拒绝 */
        self->coins -= amount;
        return amount;
    }
    ...
}

impl Purse for Shop {
    int spend(int amount) {
        printf("shop %s never spends %d\n", self->name, amount);
        return 0;                                 /* 店家永远不花钱 */
    }
    ...
}
```

对象之间的交互就写在普通 C 代码里：`fruit.earn(alice.spend(fruit.price() * n))` —— 返回值在对象
之间流转，每一跳都按各自的 vtable 派发。trait 在这里的作用是**约束形状**，不是继承。

## 5. 组合、数组与堆对象

struct 字段可以直接用别的 struct 的**指针**；数组、堆对象的 vptr 由编译器补
（[language-spec §4.4 / §4.7](language-spec.md)；下面片段沿用第 1 章的 `Person` / `Greeter`）：

```c
struct Box { Person *who; };

Person p = { .name = "Tom" };               /* 声明处补 vptr */
Person ps[2];
ps[0].name = "Ann";                         /* 数组：逐元素写 vptr（循环变量固定 __ct_i） */
Person *q = malloc(sizeof(struct Person));  /* 堆对象：声明后自动写 vptr */
q->name = "Bob";
Box b = { .who = q };

p.greet();        /* hi Tom */
ps[0].greet();    /* hi Ann */
b.who->greet();   /* hi Bob */
delete q;
```

三条实用规则：

- **数组只能** `Type name[<n>];`——无初始化式、下标必须是常量。
- **堆对象**只认 `T *p = malloc(sizeof(struct T));` / `calloc(...)` 这两类初始化，写完即补 vptr。
- **文件作用域的 struct 对象**由编译器生成的构造器 `__ct_init`（`__attribute__((constructor))`）在
  `main` 之前写 vptr，因此全局实例也能直接派发。

## 6. trait 当类型：接口多态

把 trait 名当类型写，就得到「接口值」——一个自带 vtable 指针的胖指针（[language-spec §4.8](language-spec.md)）：

```c
trait Node { void show(); }

struct Lit { int v; } use Node;
struct Add { Node lhs; Node rhs; } use Node;   /* 接口作为字段 */

impl Node for Lit {
    void show() { printf("%d", self->v); }
}

impl Node for Add {
    void show() {
        printf("(");
        self->lhs.show();                      /* 值字段派发：lhs.vt->show(lhs.self) */
        printf(" + ");
        self->rhs.show();
        printf(")");
    }
}

int main(void) {
    Lit one = { .v = 1 };
    Lit two = { .v = 2 };
    Add sum;
    sum.lhs = one;                             /* 语句赋值时自动装箱 */
    sum.rhs = two;
    sum.show();                                /* (1 + 2) */
    return 0;
}
```

完整可运行版本见 [examples/06_iface_field](../examples/06_iface_field/iface_field.ct)，输出 `(1 + 2)`。

装箱规则：

| 写法 | 结果 |
| --- | --- |
| `Node n;` | 空接口值 `{0, 0}`——**派发即崩**，与 C 一致 |
| `Node n = p;` | 装箱：`(struct Node_iface){ &p, &Lit_Node_vtable }` |
| `Node n = q;`（`q` 是 `Lit *`） | `self` 取 `q` 本身，不加 `&` |
| `n = p;` | 按 `n` 声明的 trait 装箱 |
| `void f(Node n);` + `f(p);` | 实参按签名里的 trait 装箱 |
| `Node n = f();`（返回接口） | 直接用返回的胖指针 |

ct-ast 还放宽了 L0 的三条限制：接口**数组**、接口**数组字段**、以及**构造点装箱**都能用
（`test/cases/**` 与 `docs/language-spec.md §4.8` 有逐条对照）。

## 7. 模块化：namespace、import、pub、多文件

一个文件一个单元，`ct build` 把多个单元编到同一目录。三个关键字分工明确：

```c
/* shapes.h.ct —— 文件名以 .h 结尾时，同时发布 shapes.h，供其它单元共享类型 */
pub trait Speak { void hi(); }
pub struct Dog { int n; } use Speak;
```

```c
/* impl_dog.h.ct —— 承载 impl 的单元必须写成 .h.ct 才能被 import；
   impl 与它建的 vtable 都是 static，只在本单元可见 */
import shapes;
#include <stdio.h>

impl Speak for Dog {
    void hi() { printf("woof %d\n", self->n); }
}

static Dog g_dog = { .n = 7 };
pub struct Dog *dog_get(void);
struct Dog *dog_get(void) { return &g_dog; }
```

```c
/* main.ct —— 只看得见类型和访问器，靠指针上的 vptr 派发 */
import shapes;
import impl_dog;

int main(void) { dog_get()->hi(); return 0; }
```

```sh
ct build -I . main.ct -o app        # 默认：生成的 C 放进 .ctbuild/，一步产出可执行文件 app
./app                               # woof 7（shapes.h.ct / impl_dog.h.ct / main.ct）
ct build --emit-c -I . main.ct -o build   # 只发 C：每单元 .c/.h，并打印建议的 cc 行
```

要点：

- **`pub` 才导出**。`pub` 的函数/struct/trait 写进 `.h`；`impl` 的方法与 vtable 永远 `static`。
- **承载 `impl` 的单元要写成 `.h.ct`**：`import x;` 接受 `x.h.ct` 或映射单元 `x.m.ct`；普通 `.ct`
  不发布接口、不能导入（写 `import impl_dog;` 时磁盘上必须是 `impl_dog.h.ct`；同一 root 下
  `x.h.ct` 与 `x.m.ct` 并存报 import 歧义；完整规则见 `language-spec` §4.10）。
- **跨单元只走指针 + vptr**：vtable 符号不出单元，「把对象传出去」比「把类型传出去」更省事。
- **`namespace a;` 是文件级声明**（分号式），块式 `namespace A { … }` 会被拒绝；目录也可以用
  `--ns-root <dir>` 映射成 namespace（`src/hal/uart.h.ct` → `hal`）。
- **跨命名空间调用必须带限定**：`a::one()`、`Point::size(p)`；裸调用只在同命名空间内合法。
- **`import` 支持别名**：`import app::model::Point as Point;`。

以上写法在 `test/modules/{split,ns_funcs,ns_qual,ns_dir}` 里是每日回归的一部分。

## 8. 内存：Drop、delete、own、泄漏告警

三种释放手段，按需要选（`test/modules/autodrop`、`test/modules/leak`）。
完整的所有权、工厂与池化实践见 [memory-guide](memory-guide.md)（其中记录了 AutoDrop 缺陷 SH-33 已于 v0.16.0 修复）。

```c
#include <stdio.h>
#include <stdlib.h>

struct Box { int n; } use Drop;

impl Drop for Box {
    void drop() { printf("drop %d\n", self->n); }
}

int main(void) {
    Box *p = malloc(sizeof(struct Box));
    p->n = 1;
    delete p;                     /* -> if (p) { Box_Drop_drop(p); free(p); p = 0; } */

    {
        own Box *b = malloc(sizeof(struct Box));
        b->n = 2;                 /* 作用域出口自动释放 */
    }

    Box *leak = malloc(sizeof(struct Box));
    leak->n = 3;
    return 0;                     /* 未释放：编译期告警 */
}
```

运行结果是 `drop 1` 之后紧接 `drop 2`，外加一条告警：

```sh
$ ct leak.ct -o leak.c
leak.ct:20: warning: potential leak: 'leak' (Box*) allocated but never deleted
```

- **`delete p;`** 立刻释放：有 `Drop` 就先调 `drop()`，再 `free`，**并把可赋值的实参置空**
  （`p = 0;`），所以之后 `p == 0` 恒成立，不需要手工清空；实参不是左值（如 `delete get();`）时
  只释放、不赋值。
- **`own T *p = malloc(...)`** 交所有权：作用域闭合 `}` 与每个 `return` 之前自动释放，
  按声明逆序；重新赋值或把 `p` 当独立右值传出（`q = p;`、`return p;`）即视为所有权转移，不再兜底。
  约束：必须是带 `use Drop` 的**结构体指针**、必须由 `malloc`/`calloc` 初始化；`}` 必须位于
  **行首**，`return` 则没有位置要求（行内的 `if (c) return 1;` 同样会在分支内注入释放）。
  该「行首」要求其实只属于冻结的 L2 行重写管线。
- **泄漏是告警不是错误**，格式固定：

```sh
$ ct leak.ct -o leak.c
leak.ct:20: warning: potential leak: 'leak' (Box*) allocated but never deleted

$ ct --diagnostics=json leak.ct -o leak.c    # 机器可读，写 stdout
```

逃逸判定是**保守**的（宁可漏放，不可错放）。要让它闭嘴就真的释放，不要指望它猜。

## 9. `map` 与 bindings：把 trait 绑到已有的 C 库

不想为了用 C 库而改库的代码，就用 `map` 把一个**已声明的全局实例**绑定成 trait 实现。
这是把假 HAL 接进 CT 的官方做法（[bindings/mock-hal/uart.h.ct](../bindings/mock-hal/uart.h.ct)）：

```c
#include "mock_hal.h"          /* 直通，让你看见库的真实声明 */

trait Controller { int send(char *buf, int len); }

struct mock_uart { int fd; };  /* 镜像库里的布局 */
struct mock_uart uart1;        /* 必须是已声明的全局变量 */

map trait Controller for instance uart1 {
    send(buf, len) -> mock_uart_send(&uart1, buf, len);
}

pub int mock_hal_send(char *buf, int len) {
    Controller c;
    c = uart1;                 /* 用实例级 vtable 装箱：Uart 不必 use Controller */
    return c.send(buf, len);
}
```

编译器为实例发射 `<实例>_<Trait>_<方法>` 包装函数与 `<实例>_<Trait>_vtable`，`c.send(...)` 经它派发。
硬约束：实例必须是文件作用域全局；绑定要覆盖 trait 的**每个**方法且**只绑一次**；`->` 右侧只接受
受限的调用子集（字面量、可见名字、以实例为根的成员路径）。

`map` 只在 **ct-ast** 支持，L0 与 L2 都不认识。可直接跑的完整例子见
[examples/08_map_binding/](../examples/08_map_binding/map_binding.ct)（两个实例、各自一份 vtable）。

### 9.1 零成本映射：`.m.ct` 与类型宿主

不需要对象、也不想要 wrapper 时，把映射写进后缀 `.m.ct` 的**映射单元**。它只承载 `#include` /
`#define`、`pub trait` 与 `map`，**不产生任何 `.c` / `.h`**；文件所在目录必须等于它的 `namespace`：

```c
/* libc/libc.m.ct */
#include <stdlib.h>

namespace libc;

pub trait Env { char *get(char *name); }

map trait Env for namespace libc {
    get(name) -> getenv(name);
}
```

```c
/* main.ct */
import libc::libc;

int main(void)
{
    char *home = libc::Env.get("HOME");
    ...
}
```

`ct build --emit-c main.ct -o out/` 只产出 `main.c`（没有 `libc.c`），调用点被直接替换成 `getenv(("HOME"))`；
prologue 的 `#include <stdlib.h>` 已展开进 `main.c`，没有 wrapper、没有 vtable。类型宿主同理：
`map trait CStr for type char *` 让 `char a[] = "42"; a.toInt()` 直接变成 `atoi((a))`。
可运行例子见 `test/modules/map_unit{,_type,_cross}`。

### 9.2 伴生 C shim：recipe 写不出的形状

recipe 只能写**一次顶层调用**，宏、全局量、需要转换的调用都写不了。给映射单元加一对同目录同名的
C 文件 `<base>.shim.h` / `<base>.shim.c`，把适配写在里面，recipe 绑到它：

```c
/* posix/socket.shim.h —— 头文件式 shim，没有 .shim.c */
#include <errno.h>
#include <sys/socket.h>

static inline int ct_sock_pair(int *sv) { return socketpair(AF_UNIX, SOCK_STREAM, 0, sv); }
static inline int ct_sock_errno(void) { return errno; }
```

```c
/* posix/socket.m.ct */
namespace posix;

pub trait Socket { int pair(int *sv); int err(); }

map trait Socket for namespace posix {
    pair(sv) -> ct_sock_pair(sv);
    err() -> ct_sock_errno();
}
```

消费者的生成 `.c` 自动带上 `#include "socket.shim.h"`，`ct build` 组出的 `cc` 命令行自动加
`-I <shim 目录>`（有 `.shim.c` 时同时把它列为源文件）。`posix::Socket.err()` 于是展开成
`ct_sock_errno()`。完整例子见 `bindings/posix-socket/`；改了 shim 会让消费者重建。
有 `.shim.c` 却没有 `.shim.h` 时报 `a shim source needs a matching .shim.h`。
C 头文件里的 `enum` 常量 CT 也不认识（全大写拼写只是撞上宏启发式，不算解析），同样用这层 shim
包成函数再绑定；判据与各类符号见 [language-spec §4.43](language-spec.md)。

### 9.3 原样块：`#ct-raw`

映射 / shim 之外的第三种接法：把一段 C **逐字节**带进生成的 `.c`。`#ct-raw` 与 `#ct-endraw`
必须各占一行且位于第 1 列，块内文本不经过词法/语法分析：

```ct
#ct-raw
#define TRIPLE(x) ((x) * 3)
static int raw_helper(int n) { return n + 1; }
#ct-endraw
```

生成物在块后写一行 `#line`（恢复到块后的源行号）；`--no-line` 只去掉这行锚点，块内容不变。
一个块上限 32768 字节；`.m.ct` 仍只接受 `#include` / `#define`；ct-ast 自身的源码不得使用块。
规则与诊断见 [language-spec §4.41](language-spec.md#441-raw-透传ct-rawphase-173仅-ct-ast)。

## 10. 标准库：`std`

`std` 是独立的 **ct-pkg 包**（包名 `std`，namespace 仍是 `std::<mod>`），不随本仓库发布，也不在
`ct` 二进制里；用 `ct get std` 拉进项目的 `vendor/`，再按 `ct install` 打印的 include root 构建
（导入仍要显式给 `-I`，没有默认搜索路径）：

```sh
ct get std
ct install                              # 打印 ct build -I vendor/std ...
ct build -I vendor/std main.ct -o main
```

namespace 固定为 `std::<mod>`，调用只有一种形态：方法。宿主是 C 已有类型的模块（`str` / `fs` /
`utf8`）用 `<Trait>.m.ct` + 同基名 `<Trait>.shim.h` 的静态映射；CT 自有类型（`vec` / `map` /
`arena` / `test`）在 `.h.ct` 里直接写 `pub trait` + `struct ... use Trait` + `impl`：

```ct
import std::str::String;
import std::test::Test;

int main(void)
{
    Test t;
    Test *tp = &t;
    char buf[32];

    tp->init();
    tp->checkEqInt("ct".len(), 2, "len");          // 展开成 std_str_len("ct")
    tp->checkEqInt("a".concat("b", buf, 32), 0, "concat");
    return tp->report();
}
```

下表路径相对包的 namespace 根（安装后是 `vendor/std/std/`）：

| 单元 | namespace | 方法 |
| --- | --- | --- |
| `std/str/String.m.ct` + `String.shim.h` | `std::str` | `len` / `find` / `findChar` / `startsWith` / `endsWith` / `copy` / `slice` / `concat` / `toLower` / `toUpper` / `compare` |
| `std/fs/Fs.m.ct` + `Fs.shim.h` | `std::fs` | `exists` / `readFile` / `writeFile` / `list` |
| `std/utf8/Utf8Ops.m.ct` + `Utf8Ops.shim.h` | `std::utf8` | `decode` / `codepointCount` / `encode` |
| `std/vec/Vec.h.ct` | `std::vec` | `VecIntOps` / `VecStrOps`：`init` / `len` / `push` / `pop` / `at` / `free` |
| `std/map/Map.h.ct` | `std::map` | `MapStrIntOps` / `MapIntPtrOps`：`init` / `put` / `get` / `len` / `clear` / `free` |
| `std/arena/Arena.h.ct` | `std::arena` | `init` / `alloc` / `reset` / `freeAll` |
| `std/test/Test.h.ct` | `std::test` | `init` / `checkTrue` / `checkEqInt` / `checkEqStr` / `report` |

容器、arena、test 走原生 OO：每个 struct 带 `use ...Ops`，方法经 vtable 分派。库里统一写
`p->method()`（栈上值和堆对象都成立）；声明出来的值也接受 `v.method()`，编译器会在声明处补上
vptr 并传 `&v`，但 `malloc` 出来的对象在赋入初始化过的值之前不能直接调方法（vptr 是垃圾，实测
段错误），所以下面一律先有值再取地址：

```ct
VecInt v;
VecInt *p = &v;
p->init();
p->push(1);
int n = p->len();

MapStrInt m;
MapStrInt *mp = &m;
mp->init(8);
mp->put("k", 1);

Arena a;
Arena *ap = &a;
ap->init(32);

Test t;
Test *tp = &t;
tp->checkEqInt(1, 1, "ok");
```

`str` / `fs` / `utf8` 的接收者是 `char *`，用 `.`；`utf8` 的 `encode` 接收者是输出缓冲区：

```ct
char *path = "a.txt";
path.exists();
path.readFile(buf, 64);

char *s = "héllo";
int cps = s.codepointCount();    // 码点；s.len() 数的是字节
buf.encode(233, 16);
```

几个必须记住的点：

- **`toLower()` / `toUpper()` 是原地修改**，返回状态码而不是新字符串，而类型键会丢掉 `const`：
  `"abc".toLower()` 能编译通过，然后写只读内存。不要对字符串字面量或 `const char *` 调用，
  编译器不会拦。
- **`String.len()` 数字节，`Utf8Ops.codepointCount()` 数码点**：`"é"` 是 `len() == 2`、
  `codepointCount() == 1`，两个名字不能互换。
- **原生 OO 的 `use` 会给结构体追加 vptr**：`sizeof` +8，该成员出现在导出头里（`Vec.h` 里
  能看到 `__vecintops_vptr`）；文件内顺序必须是 `trait → struct(use) → impl`；裸 `malloc`
  出来的对象不能直接调方法（vptr 是垃圾，实测段错误 exit 139），先声明值再用。
- **`use` 结构体的方法不能被内联**：`at()` / `len()` 这种访问器直接调用在 `-O2` 下会被折叠成 0，
  走 vtable 固定约 1 ns/次；机制本身的间接调用开销 ≈0，失去的只是内联。
- **`char *` 上的方法名全局共享**：两个可见 trait 声明同名方法，调用点报
  `ambiguous type-host map for method 'x' on type 'char *'`，新增前先 grep。
- **header-only shim 的实现按消费方复制一份**（`String.shim.h` 约 190 行 / 5.5K），断点要下在
  消费者里；`.m.ct` 的 prologue 只允许 `#include` / `#define`，所以映射模块压不成单文件。

三条约定：缓冲区不够返回 `-1` / `NULL`，绝不静默截断；**不依赖 `delete`**，每个资源类型都有显式
`free()` / `reset()` / `clear()`；`Map` 固定容量、满载拒绝新键，不自动 rehash。详见包内
`std/README.md`（`ct get std` 后位于 `vendor/std/std/README.md`）。

每个模块有一对文档：`README.md` 是参考（方法全集、参数、返回值、内存归属、本模块的坑），
`tutorial.md` 是从零写到能用的过程。这里的总览不重复它们的内容；两文件都在包内同一目录
（`vendor/std/std/<mod>/`）：

| 模块 | 参考 | 教程 |
| --- | --- | --- |
| `std::str` / `std::vec` | `vendor/std/std/str/README.md` · `vendor/std/std/vec/README.md` | `vendor/std/std/str/tutorial.md` · `vendor/std/std/vec/tutorial.md` |
| `std::fs` | `vendor/std/std/fs/README.md` | `vendor/std/std/fs/tutorial.md` |
| `std::utf8` | `vendor/std/std/utf8/README.md` | `vendor/std/std/utf8/tutorial.md` |
| `std::map` | `vendor/std/std/map/README.md` | `vendor/std/std/map/tutorial.md` |
| `std::arena` | `vendor/std/std/arena/README.md` | `vendor/std/std/arena/tutorial.md` |
| `std::test` | `vendor/std/std/test/README.md` | `vendor/std/std/test/tutorial.md` |

### 10.1 闭包：把上下文带进回调

Phase 21 起，ct-ast 支持 `=>` 就地闭包。表面类型仍是函数指针，返回类型由左侧声明给出；
闭包的环境放在栈上，编译期禁止逃逸。

```c
/* closure.ct */
#include <stdio.h>

int run(int (*fn)(void *env, int x), void *env)
{
    return fn(env, 2) + fn(env, 3);
}

int main(void)
{
    int unit = 10;
    int (*scale)(int x) = (int x) => x * unit;             /* 表达式体 */
    int total = run((int x) => { return x + unit; });      /* 字面量填满 (fn, env) 对 */
    printf("%d %d\n", scale(4), total);
    return 0;
}
```

```sh
ct build closure.ct -o closure && ./closure
# 40 25
```

- **捕获按值、创建点求值**：`scale` 拿到的是 `unit` 当时的副本；捕获名只读，写回要先捕获指针再写
  `*p = …`。
- **闭包变量是绑定，不是值**：可以调用（`scale(4)`），也可以把绑定整对交给一个 `(fn, env)` 参数
  （`run(scale)`，参数表要匹配宿主尾部）；不能拷贝 / 重赋值 / 作返回值 / 作字段或元素。需要别名就
  把字面量就地写进去。
- **字面量作实参**：形参必须写成相邻的 `ret (*fn)(void *env, …)` + `void *env`；字面量一次填满
  这两个槽，所以 `run(…)` 只写一个字面量，闭包自己的参数由 `run` 内部提供。
- **没有 env 槽的 C API**（`qsort` 一类）接不了；上下文要活过当前栈帧就用档①：`struct` + `trait`
  （ct-pkg 的 `Callable` 签名族随该仓发布，本仓未内置）。
- 更完整的语法、限制清单与 `(fn, env)` 约定见 [language-spec §4.44](language-spec.md)。

### 10.2 `loop(n)`：只数次数

只要「跑 n 次」时，不用再写 `for (int i = 0; i < n; i++)`：`loop(n) { … }` 展开成完全等价的原生
`for`，隐式计数器就叫 `i`，从 0 数起。

```c
/* loop.ct */
#include <stdio.h>

int main(void)
{
    int sum = 0;

    loop(4) {
        sum = sum + i;
        printf("%d\n", i);
    }
    loop(0) {
        printf("never\n");      /* 0 次，不报错 */
    }
    printf("sum %d\n", sum);
    return 0;
}
```

```sh
ct build loop.ct -o loop && ./loop
# 0 1 2 3，最后一行 sum 6
```

- **计数只求值一次**：`loop(n)` 把 `n` 存进私有临时量，条件读临时量；`loop(next())` 只调用一次 `next`。
- **`i` 就是普通的 `int`**：体内可以读、可以改（`i = i + 1` / `i++`），`break` / `continue` / `return`
  与手写 `for` 一致；体内声明的 `own` 变量在每轮出口释放。
- **循环体必须是块**：`loop(3) printf("x");` 会被拒绝，写成 `loop(3) { printf("x"); }`。
- **遮蔽只提醒 `loop` 套 `loop`**：内层 `loop` 的 `i` 会遮蔽外层时给一条 warning（`ct check` 下是
  错误）；体内手写 `int i` 或原生 `for` 不报。
- **`loop` 仍是普通标识符**：`int loop = 3;`、`loop:` 标签、`goto loop;` 都不受影响，只有语句位置
  紧跟 `(` 时才当语法糖。
- 细节与诊断文案见 [language-spec §4.45](language-spec.md)。

## 11. 命令行速查

| 命令 | 作用 |
| --- | --- |
| `ct <in.ct>` / `ct compile <in.ct>` | 单文件编译：普通 `.ct` 只写 `.c`，`.h.ct` 才额外写同名 `.h`；只接受**单文件单元**，`import` 需改用 `ct build`（`-I` 同理只对 build 生效） |
| `ct <in.ct> -o <out.c>` | 指定输出路径 |
| `ct check <in.ct>` | 只跑受限语义检查、不写 `.c`（仅单文件单元，`import` 不被接受）：调用点 arity / 实参类型 / trait 方法歧义 / impl 签名漂移（及既有 leak / 借用类发现）以 `error:` 报告，有任何发现退出 `1`，干净退出 `0` |
| `ct build <in.ct>… [-o <exe>]` | 多文件构建：默认把生成的 `.c` 放进 `.ctbuild/`，再调用 C 编译器产出可执行文件（`-o` 是文件名，默认 `a.out`） |
| `ct build --emit-c … -o <dir>` | 只发 C：每单元一份 `.c`/`.h`，`-o` 是输出目录，并打印建议的 `cc` 行；带增量缓存 |
| `ct build … --outdir <dir>` | 默认形态下改中间产物目录（默认 `.ctbuild/`） |
| `ct build … --cc <path>` / `--cflags <s>` / `--ldflags <s>` | 透传 C 编译器与编译/链接参数（可重复，也可空格分隔）；标志值按 shell 片段原样拼进命令，**不要传入不可信内容** |
| `ct build … -I <dir>` | 追加导入搜索根（可重复） |
| `ct build … --ns-root <dir>` | 目录 = namespace 的校验树根 |
| `ct … --emit-map <file\|->` | 写出反向映射表 JSON（trait/struct/函数/impl/map → 生成的 C 符号） |
| `ct … --diagnostics=json\|text` | 告警格式（默认 `text` 写 stderr）；`ct check` 下同一批记录按错误报告（`file:line:col:`），JSON 对象带 `"severity":"error"` 与 `"col"` |
| `ct … --line` / `--no-line` | 覆盖 `#line` 默认（`build` 默认开、`compile` 默认关） |
| `ct … --std=c99\|gnu99` | 写进 C 编译器的命令行，产物暂无异 |
| `ct get [--force] <spec>[@<range>]` | 拉包到 `vendor/`，写 `ct.lock`（唯一会用系统 `git` 的子命令）；裸名可经 `--index <file>` / `CT_INDEX` 查显式索引；包的 `requires` 不满足则失败且不改动既有 `ct.lock`（`--force` 继续并告警） |
| `ct update` | 离线按 `ct.pkg` 重解依赖，沿用 `ct.lock` 已钉住的提交并重写 `ct.lock` |
| `ct install` | 离线校验 `ct.lock` 与 `vendor/`，把各包的 `cflags` / `ldflags` 与 `-I` 拼成**一条**构建命令 |
| `ct verify` | 离线校验 `vendor/` 与 `ct.lock`，只报告，不写任何文件 |
| `ct -v` / `ct -h` | 版本 / 用法 |

退出码：成功 `0`，语法或 I/O 错误 `1`。**源码诊断**（解析期与语义期）格式为 `文件:行:列: error: 描述`；
语义类记录（调用点 arity / 实参类型 / trait 方法歧义 / impl 签名漂移）在 `ct build` / `ct compile` 下按
`warning:` 打印、**不改变退出码**（编译期放行），只有 `ct check` 把同一批记录升为 `error:` 并退出 `1`；
**驱动层**错误（输入打不开、参数不对、超过上限）以 `ctc: ` 开头，不假装指向某一行。

## 12. 会踩的坑

按「最常遇到」排序。第 2–4 条是**冻结的 L2 行重写管线**的限制，ct-ast（主线）是 AST 管线，
「跨行 / 单行函数体 / 注释续行」都不适用（对照见 [language-spec §6.2](language-spec.md)）：

1. **顺序敏感**：编译器单趟顺序扫描，定义必须在使用之前；签名表里还没有的函数不会被特判。
2. **跨行的语句不重写（仅 L2）**：L2 按行处理，`p.greet()` 跨行书写，或构造与语句写在同一行
   （`int main(){ … p.greet(); }`），都不会被改写；一行一句是 **L2** 的硬要求。ct-ast 没有这个限制，
   两种写法都照常派发。
3. **块注释只保护第一行（仅 L2）**：L2 里 `/* … */` 的续行会被当普通代码行处理，其中的 `self`、
   方法调用照常改写；多行注释里别写看似代码的东西。ct-ast 则**整段丢弃注释**（生成物不保留源码注释），
   注释里的代码既不改写也不留下痕迹。
4. **单行函数体不处理（仅 L2）**：`int f() { return 1; }` 与函数头同处一行时，L2 不重写体内的派发；
   ct-ast 照常派发。
5. **`switch` / `do-while` / `goto` 均已支持**（第 7 批起，见 §4.13 / §4.16 与 README 的变换表）；
   早期「在 `{` 处报 `unexpected token`」的说法已过时，也不必再手工构建 L0 种子绕过。
6. **块式 namespace 与跨命名空间裸调用**会被 ct-ast 拒绝；用分号式声明 + 限定调用。
7. **struct 类型的数组字段**：L0 / L2 不支持，ct-ast 已支持（逐元素写 vptr，见 §6 与
   [language-spec §6](language-spec.md)）；其余组合先查 [language-spec §4.8](language-spec.md)。
8. **上限是硬报错**：ct-ast 提高到 `MAX_TRAITS` 64、`MAX_STRUCTS` 128、`MAX_METHODS` 64、
   `MAX_FUNCS` 256、`MAX_VARS` 4096…，越界直接报错，绝不静默截断。[§7](language-spec.md) 有全表。

## 13. 下一步

- [language-spec.md](language-spec.md) —— 每一条展开规则的权威定义
- [polymorphism.md](polymorphism.md) —— 为什么用 vtable 而不是别的写法
- [architecture.md](architecture.md) —— 编译器内部怎么按行改写
- [roadmap.md](roadmap.md) —— 已落地与后续阶段
- `examples/**` —— 8 个可运行示例；`test/cases/**` —— 每个语法点的最小快照
- 编辑器支持：`editors/vscode/`（纯声明式高亮，零依赖）
- 方言：`examples/07_dialect/` 演示「注释里的 DSL → 纯 CT」，编译器对此零感知
- 包管理：`ct get` / `ct update` / `ct install` / `ct verify`，清单格式见 [design/phase8.md](history/design/phase8.md)，
  17.5 的增量（比较器范围、离线重解、显式索引、构建元数据）见 [design/phase17.md](design/phase17.md)

---

## English

> **Scope**: v0.16.0, installed entry is **ct-ast**. Every snippet below is taken from `examples/**` or
> `test/**`, both of which the gates run; the grammar itself is defined in
> [language-spec](language-spec.md).

### 0. Install

You need a C compiler (`cc`: Apple clang or GCC ≥ 8), plus `curl` or `wget` and `tar`.

```sh
curl -fsSL https://raw.githubusercontent.com/samxxu/ct-lang/main/install.sh | sh
```

It downloads the source archive, bootstraps the chain locally (L0 → L1 → L2 → **ct-ast**), installs `ct`
into `~/.local/bin` and adds the `ctc` alias as a symlink. No prebuilt binaries, no `git`.

```sh
ct -v            # ct v0.16.0     (the installed entry, full capability)
ctc -v           # ctc v0.16.0    (compatibility alias, same binary)
```

| Need | Command |
| --- | --- |
| install elsewhere | `install.sh --prefix "$HOME/bin"` |
| pin a version | `install.sh --version v0.16.0` (default: `main`) |
| install offline from a clone | `CT_SOURCE_DIR=. sh install.sh` |
| different compiler | `CC=gcc sh install.sh` |
| just try it, no install | `gcc -Wall -Wextra -std=c99 selfhost/l0/ctc.c -o ctc` (single-file core only) |

`install.sh` is the repository's **only** install script: no Makefile, no third-party dependencies, and
nothing on it enters the compiler build path. GCC ≥ 8 users need not pass `-Wno-format-truncation` by
hand; the script probes for it.

### 1. Your first program: one trait, one struct, one impl

A `.ct` file is ordinary C plus a few declarative constructs. This one adds `trait` and `impl` only
(full version: [examples/01_greeter/greeter.ct](../examples/01_greeter/greeter.ct)):

```c
#include <stdio.h>

trait Greeter {
    void greet();
    void greet_name(char *name);
}

struct Person {
    char *name;
    int age;
} use Greeter;

impl Greeter for Person {
    void greet() {
        printf("Hello, I'm %s, age %d\n", self->name, self->age);
    }
    void greet_name(char *name) {
        printf("Hello %s, I'm %s\n", name, self->name);
    }
}

int main() {
    Person p = { .name = "Tom", .age = 36 };
    p.greet();
    p.greet_name("Jerry");
    return 0;
}
```

```sh
ct hello.ct -o hello.c        # writes hello.c (a plain .ct writes no .h; only .h.ct units do)
cc hello.c -o hello           # the output is plain C; the .h is not needed
./hello
```

```
Hello, I'm Tom, age 36
Hello Jerry, I'm Tom
```

Three things to remember:

1. **`self` is implicit.** Inside an `impl` body you write `self->name`; there is no parameter to declare
   and no cast to write.
2. **`use Greeter` closes the struct** and decides which vptr fields it carries.
3. **An `impl` must implement every method** of its trait; a missing one is a compile error.

### 2. Reading the output: the naming contract

The generated C is readable by design, and the names are stable ([language-spec §5](language-spec.md)):

| Product | Rule | Example |
| --- | --- | --- |
| vtable type | `<Trait>_vtbl` | `struct Greeter_vtbl` |
| interface value | `<Trait>_iface` | `struct Greeter_iface` (`{ self, vt }`) |
| vptr field | `__<trait lowercase>_vptr` | `__greeter_vptr` |
| method body | `<Struct>_<Trait>_<method>` | `Person_Greeter_greet` |
| vtable variable | `<Struct>_<Trait>_vtable` | `Person_Greeter_vtable` |
| implicit parameter | always `self`, cast target always `_self` | — |

`p.greet();` becomes `p.__greeter_vptr->greet(&p);` — every method call is a vptr call, with no type
checking and no special cases.

### 3. Dispatch: what a receiver may be

([examples/03_receivers](../examples/03_receivers/receivers.ct),
[examples/04_rvalue](../examples/04_rvalue/rvalue.ct),
[examples/05_body_dispatch](../examples/05_body_dispatch/body_dispatch.ct))

| Source | Generated |
| --- | --- |
| `p.greet();` | `p.__greeter_vptr->greet(&p);` |
| `q->greet();` (`q` is `Person *`) | `q->__greeter_vptr->greet(q);` |
| `ps[i].greet();` | subscript evaluated first, then the vptr |
| `slots[0]->greet();` | pointer-array element dispatches as a pointer |
| `b.who->greet();` | field chains dereference then dispatch |
| `make_person("Ann", 30).greet();` | the receiver is evaluated **once**, hoisted into a temp |
| `self->lhs->emit();` / `o->m();` / `one.m();` inside an `impl` | also vptr calls — this is how recursive data structures work |

`examples/05_body_dispatch` walks an `Add`/`Num` tree with exactly that last form.

### 4. Several traits, cooperating objects

A struct may `use` several traits, and one trait may be implemented by many structs, each with its own
behaviour ([examples/02_market](../examples/02_market/market.ct)):

```c
trait Purse { int balance(); int spend(int amount); void earn(int amount); }
trait Reporter { void report(); }

struct Trader { char *name; int coins; } use Purse, Reporter;
struct Shop   { char *name; int price; int units; int coins; } use Purse, Reporter;

impl Purse for Shop {
    int spend(int amount) {
        printf("shop %s never spends %d\n", self->name, amount);
        return 0;                          /* a shop never spends */
    }
    ...
}
```

Objects interact in ordinary C code: `fruit.earn(alice.spend(fruit.price() * n))`, with each hop
dispatching through the receiver's own vtable. Traits constrain shape here; they are not inheritance.

### 5. Composition, arrays and heap objects

Struct fields may point at other structs; arrays and heap objects get their vptrs from the compiler
([language-spec §4.4 / §4.7](language-spec.md); the snippet reuses `Person` / `Greeter` from chapter 1):

```c
struct Box { Person *who; };

Person p = { .name = "Tom" };               /* vptr written at the declaration */
Person ps[2];
ps[0].name = "Ann";                         /* arrays: per-element vptr (loop var __ct_i) */
Person *q = malloc(sizeof(struct Person));  /* heap: vptr written after the declaration */
q->name = "Bob";
Box b = { .who = q };

p.greet();        /* hi Tom */
ps[0].greet();    /* hi Ann */
b.who->greet();   /* hi Bob */
delete q;
```

- Arrays are only `Type name[<n>];` — no initialiser, constant subscript.
- Heap objects only accept `T *p = malloc(sizeof(struct T));` / `calloc(...)`.
- File-scope struct objects get their vptr from the generated `__ct_init`
  (`__attribute__((constructor))`) before `main` runs.

### 6. Traits as types: interface polymorphism

Using a trait name as a type gives you an interface value — a fat pointer carrying its vtable
([language-spec §4.8](language-spec.md)):

```c
trait Node { void show(); }

struct Lit { int v; } use Node;
struct Add { Node lhs; Node rhs; } use Node;   /* an interface as a field */

impl Node for Lit {
    void show() { printf("%d", self->v); }
}

impl Node for Add {
    void show() {
        printf("(");
        self->lhs.show();
        printf(" + ");
        self->rhs.show();
        printf(")");
    }
}

int main(void) {
    Lit one = { .v = 1 };
    Lit two = { .v = 2 };
    Add sum;
    sum.lhs = one;                             /* a statement assignment boxes it */
    sum.rhs = two;
    sum.show();                                /* (1 + 2) */
    return 0;
}
```

Runnable version: [examples/06_iface_field](../examples/06_iface_field/iface_field.ct) prints `(1 + 2)`.

| Source | Result |
| --- | --- |
| `Node n;` | empty `{0, 0}` — dispatching on it crashes, exactly like C |
| `Node n = p;` | boxed: `(struct Node_iface){ &p, &Lit_Node_vtable }` |
| `Node n = q;` (`q` is `Lit *`) | `self` is `q` itself, no `&` |
| `n = p;` | boxed according to the trait `n` was declared with |
| `void f(Node n);` + `f(p);` | the argument is boxed by the signature |
| `Node n = f();` | the returned fat pointer is used directly |

ct-ast additionally lifts three L0 limits: interface **arrays**, interface **array fields**, and boxing at
**construction points** (see `test/cases/**` and §4.8).

### 7. Modules: namespace, import, pub, multiple files

One file is one unit; `ct build` compiles several of them into one directory.

```c
/* shapes.h.ct — the .h basename also publishes shapes.h, so importers see the types */
pub trait Speak { void hi(); }
pub struct Dog { int n; } use Speak;
```

```c
/* impl_dog.h.ct — a unit that carries an impl must be named .h.ct to be importable;
   the impl and its vtable are static, private to this unit */
import shapes;
#include <stdio.h>

impl Speak for Dog {
    void hi() { printf("woof %d\n", self->n); }
}

static Dog g_dog = { .n = 7 };
pub struct Dog *dog_get(void);
struct Dog *dog_get(void) { return &g_dog; }
```

```c
/* main.ct — sees the type and the accessor only, dispatches through the pointer */
import shapes;
import impl_dog;

int main(void) { dog_get()->hi(); return 0; }
```

```sh
ct build -I . main.ct -o app        # default: C into .ctbuild/, one step to the executable app
./app                               # woof 7 (shapes.h.ct / impl_dog.h.ct / main.ct)
ct build --emit-c -I . main.ct -o build   # C only: one .c/.h per unit, plus a suggested cc line
```

- **Only `pub` is exported**; `impl` methods and vtables stay `static`.
- **A unit that carries an `impl` must be named `.h.ct`**: `import x;` accepts `x.h.ct` or a mapping
  unit `x.m.ct`; a plain `.ct` publishes no interface and cannot be imported (writing
  `import impl_dog;` requires `impl_dog.h.ct` on disk; an `x.h.ct` and an `x.m.ct` in the same root make
  an import ambiguous; `language-spec` §4.10 has the full rules).
- **Cross-unit access goes through pointers and vptrs** — passing the object around is easier than
  exporting the type.
- **`namespace a;` is file-scoped** (semicolon form); block form is rejected. Directories can also become
  namespaces with `--ns-root <dir>` (`src/hal/uart.h.ct` → `hal`).
- **Cross-namespace calls must be qualified**: `a::one()`, `Point::size(p)`. Bare calls are legal only
  inside the same namespace.
- **`import` supports aliases**: `import app::model::Point as Point;`.

These shapes are exercised daily by `test/modules/{split,ns_funcs,ns_qual,ns_dir}`.

### 8. Memory: Drop, delete, own, leak warnings

Ownership, factories and pooling in full are covered by the [memory guide](memory-guide.md)
(it records that the AutoDrop defect SH-33 was fixed in v0.16.0).

```c
#include <stdio.h>
#include <stdlib.h>

struct Box { int n; } use Drop;

impl Drop for Box {
    void drop() { printf("drop %d\n", self->n); }
}

int main(void) {
    Box *p = malloc(sizeof(struct Box));
    p->n = 1;
    delete p;                     /* -> if (p) { Box_Drop_drop(p); free(p); p = 0; } */

    {
        own Box *b = malloc(sizeof(struct Box));
        b->n = 2;                 /* released at the closing brace */
    }

    Box *leak = malloc(sizeof(struct Box));
    leak->n = 3;
    return 0;                     /* not freed: a compile-time warning */
}
```

It prints `drop 1` then `drop 2`, plus one warning:

```sh
$ ct leak.ct -o leak.c
leak.ct:20: warning: potential leak: 'leak' (Box*) allocated but never deleted
```

- **`delete p;`** frees immediately: `drop()` first when the struct uses `Drop`, then `free`. It
  **nulls the argument** when it is assignable (`p = 0;`), so `p == 0` holds afterwards and no manual
  clearing is needed; a non-lvalue argument (`delete get();`) is only freed, not assigned.
- **`own T *p = malloc(...)`** hands over ownership: released before the scope's closing `}` and before
  every `return`, in reverse declaration order; reassigning `p` or passing it on as a bare rvalue
  (`q = p;`, `return p;`) transfers ownership and disables the safety net. The struct must `use Drop`,
  the pointer must come from `malloc`/`calloc`, and the `}` must start a line (`return` has no
  position requirement — `if (c) return 1;` is released inside the branch too). That "line start"
  requirement belongs to the frozen L2 only.
- **Leaks are warnings, not errors**:

```sh
$ ct leak.ct -o leak.c
leak.ct:20: warning: potential leak: 'leak' (Box*) allocated but never deleted

$ ct --diagnostics=json leak.ct -o leak.c    # machine readable, on stdout
```

Escape analysis is deliberately conservative: it would rather miss a release than double-free.

### 9. `map` and bindings: binding a trait to an existing C library

When you cannot change the library, `map` binds a **declared global instance** of it to a trait
([bindings/mock-hal/uart.h.ct](../bindings/mock-hal/uart.h.ct)):

```c
#include "mock_hal.h"          /* pass-through: the library's real declarations */

trait Controller { int send(char *buf, int len); }

struct mock_uart { int fd; };  /* mirror the layout */
struct mock_uart uart1;        /* must be a declared global */

map trait Controller for instance uart1 {
    send(buf, len) -> mock_uart_send(&uart1, buf, len);
}

pub int mock_hal_send(char *buf, int len) {
    Controller c;
    c = uart1;                 /* boxed with the instance-level vtable */
    return c.send(buf, len);
}
```

The compiler emits `<inst>_<Trait>_<method>` wrappers and an `<inst>_<Trait>_vtable`, and `c.send(...)`
dispatches through it. Hard rules: the instance must be file-scope; every trait method must be bound
exactly once; the right-hand side accepts only a restricted call subset (literals, visible names,
member paths rooted at the instance).

`map` is ct-ast only — L0 and L2 do not accept it. A complete runnable example lives in
[examples/08_map_binding/](../examples/08_map_binding/map_binding.ct) (two instances, one vtable each).

#### 9.1 Zero-cost mapping: `.m.ct` and type hosts

When there is no object and no wrapper is wanted, put the mapping in a suffix-`.m.ct` **mapping
unit**. It carries only `#include` / `#define`, `pub trait` and `map`, and **produces no `.c` /
`.h`**; the file's directory must equal its `namespace`:

```c
/* libc/libc.m.ct */
#include <stdlib.h>

namespace libc;

pub trait Env { char *get(char *name); }

map trait Env for namespace libc {
    get(name) -> getenv(name);
}
```

```c
/* main.ct */
import libc::libc;

int main(void)
{
    char *home = libc::Env.get("HOME");
    ...
}
```

`ct build --emit-c main.ct -o out/` writes only `main.c` (no `libc.c`), and the call site is replaced by
`getenv(("HOME"))`; the prologue's `#include <stdlib.h>` is expanded into `main.c`, with no wrapper
and no vtable. A type host works the same way: `map trait CStr for type char *` turns
`char a[] = "42"; a.toInt()` into `atoi((a))`. Runnable examples live under
`test/modules/map_unit{,_type,_cross}`.

#### 9.2 The sibling C shim: shapes a recipe cannot spell

A recipe is **one top-level call**, so macros, globals and casts are out of reach. Add a same-directory,
same-base pair `<base>.shim.h` / `<base>.shim.c` to the mapping unit, write the adaptation there, and
bind the recipe to it:

```c
/* posix/socket.shim.h -- a header-only shim, no .shim.c */
#include <errno.h>
#include <sys/socket.h>

static inline int ct_sock_pair(int *sv) { return socketpair(AF_UNIX, SOCK_STREAM, 0, sv); }
static inline int ct_sock_errno(void) { return errno; }
```

```c
/* posix/socket.m.ct */
namespace posix;

pub trait Socket { int pair(int *sv); int err(); }

map trait Socket for namespace posix {
    pair(sv) -> ct_sock_pair(sv);
    err() -> ct_sock_errno();
}
```

The consumer's generated `.c` automatically carries `#include "socket.shim.h"`, and `ct build`'s composed
`cc` command line automatically gains `-I <shim directory>` (plus the `.shim.c` as a source when one exists). So
`posix::Socket.err()` expands into `ct_sock_errno()`. The full example is
`bindings/posix-socket/`; touching the shim rebuilds the consumer. A `.shim.c` without its `.shim.h`
is rejected with `a shim source needs a matching .shim.h`. `enum` constants from a C header are not
known to CT either (an ALL_CAPS spelling only trips the macro heuristic, it is not parsed); wrap them
in a function through this same shim layer — see [language-spec §4.43](language-spec.md).

#### 9.3 Raw blocks: `#ct-raw`

A third way in besides mappings and shims: carry a C fragment **byte for byte** into the generated
`.c`. `#ct-raw` and `#ct-endraw` must each own a line at column 1, and the text between them never
touches the lexer or the parser:

```ct
#ct-raw
#define TRIPLE(x) ((x) * 3)
static int raw_helper(int n) { return n + 1; }
#ct-endraw
```

The output writes a `#line` after the block (restoring the source line number); `--no-line` drops
only that anchor, not the text. One block is capped at 32768 bytes; a `.m.ct` still admits only
`#include` / `#define`, and ct-ast's own sources must stay free of blocks. The rules and diagnostics
are in [language-spec §4.41](language-spec.md#441-raw-passthrough-ct-rawphase-173-ct-ast-only).

### 10. The standard library: `std`

`std` is the separate **ct-pkg package** `std` (the namespace stays `std::<mod>`): it is no longer
shipped with this repository and is not part of the `ct` binary. Pull it into the project's `vendor/`
with `ct get std`, then build with the include root `ct install` prints (imports still need an
explicit `-I`; there is no default search path):

```sh
ct get std
ct install                              # prints ct build -I vendor/std ...
ct build -I vendor/std main.ct -o main
```

The namespace is fixed at `std::<mod>`, and there is exactly one calling form: methods. Modules whose
host already exists in C (`str` / `fs` / `utf8`) use a `<Trait>.m.ct` plus a same-base
`<Trait>.shim.h`; CT-owned types (`vec` / `map` / `arena` / `test`) write `pub trait` +
`struct ... use Trait` + `impl` in one `.h.ct`:

```ct
import std::str::String;
import std::test::Test;

int main(void)
{
    Test t;
    Test *tp = &t;
    char buf[32];

    tp->init();
    tp->checkEqInt("ct".len(), 2, "len");          // expands to std_str_len("ct")
    tp->checkEqInt("a".concat("b", buf, 32), 0, "concat");
    return tp->report();
}
```

Paths below are relative to the package's namespace root (`vendor/std/std/` once installed):

| Unit | namespace | Methods |
| --- | --- | --- |
| `std/str/String.m.ct` + `String.shim.h` | `std::str` | `len` / `find` / `findChar` / `startsWith` / `endsWith` / `copy` / `slice` / `concat` / `toLower` / `toUpper` / `compare` |
| `std/fs/Fs.m.ct` + `Fs.shim.h` | `std::fs` | `exists` / `readFile` / `writeFile` / `list` |
| `std/utf8/Utf8Ops.m.ct` + `Utf8Ops.shim.h` | `std::utf8` | `decode` / `codepointCount` / `encode` |
| `std/vec/Vec.h.ct` | `std::vec` | `VecIntOps` / `VecStrOps`: `init` / `len` / `push` / `pop` / `at` / `free` |
| `std/map/Map.h.ct` | `std::map` | `MapStrIntOps` / `MapIntPtrOps`: `init` / `put` / `get` / `len` / `clear` / `free` |
| `std/arena/Arena.h.ct` | `std::arena` | `init` / `alloc` / `reset` / `freeAll` |
| `std/test/Test.h.ct` | `std::test` | `init` / `checkTrue` / `checkEqInt` / `checkEqStr` / `report` |

Containers, the arena and `Test` are native OO: each struct carries `use ...Ops` and dispatch goes
through the vtable. The library always spells calls `p->method()`, which works for a stack value and a
heap object alike; a declared value also accepts `v.method()`, because the compiler appends the vptr
to that declaration and passes `&v`. An object from `malloc` must not be dispatched through before an
initialised value is assigned to it (its vptr is garbage; this segfaults), so the examples below take
the address first:

```ct
VecInt v;
VecInt *p = &v;
p->init();
p->push(1);
int n = p->len();

MapStrInt m;
MapStrInt *mp = &m;
mp->init(8);
mp->put("k", 1);

Arena a;
Arena *ap = &a;
ap->init(32);

Test t;
Test *tp = &t;
tp->checkEqInt(1, 1, "ok");
```

`str` / `fs` / `utf8` take a `char *` receiver and use `.`; `utf8`'s `encode` receives the output
buffer:

```ct
char *path = "a.txt";
path.exists();
path.readFile(buf, 64);

char *s = "héllo";
int cps = s.codepointCount();    // code points; s.len() counts bytes
buf.encode(233, 16);
```

Things worth remembering:

- **`toLower()` / `toUpper()` mutate in place** and return a status code, not a new string; the type
  key drops `const`, so `"abc".toLower()` compiles and then writes read-only memory. Do not call
  them on a literal or a `const char *` — the compiler will not stop you.
- **`String.len()` counts bytes; `Utf8Ops.codepointCount()` counts code points**: `"é"` is
  `len() == 2` and `codepointCount() == 1`, and the two names are not interchangeable.
- **`use` appends a vptr to the struct**: `sizeof` grows by 8 and the member is published in the
  exported header (`Vec.h` shows `__vecintops_vptr`); in-file order must be
  `trait → struct(use) → impl`; a bare-`malloc`ed object must not be dispatched through (its vptr is
  garbage — measured segfault, exit 139), so declare a value first.
- **A method on a `use` struct cannot be inlined**: a tiny accessor such as `at()` / `len()` folds
  away at `-O2` when called directly, but through the vtable costs the indirect jump (about 1 ns
  here); the mechanism itself is free, inlining is what is lost.
- **Method names on `char *` are globally shared**: two visible traits declaring the same name fail
  the call site with `ambiguous type-host map for method 'x' on type 'char *'`, so grep first.
- **A header-only shim is copied into every consumer** (`String.shim.h` is ~190 lines / 5.5K), so
  set breakpoints in the consumer; and a `.m.ct` prologue allows only `#include` / `#define`, which
  is why a mapping module cannot be a single file.

Three rules: a buffer that is too small yields `-1` / `NULL`, never a silent truncation; there is
**no `delete`**, every resource type has an explicit `free()` / `reset()` / `clear()`; `Map` is
fixed-capacity, refuses new keys when full and never rehashes. Details in the package's
`std/README.md` (`vendor/std/std/README.md` after `ct get std`).

Every module has a pair of documents: `README.md` is the reference (full method list, parameters,
returns, memory ownership, that module's traps) and `tutorial.md` is the walk from an empty file to a
working program. This overview does not repeat them; both files live in the package
(`vendor/std/std/<mod>/`):

| module | reference | tutorial |
| --- | --- | --- |
| `std::str` / `std::vec` | `vendor/std/std/str/README.md` · `vendor/std/std/vec/README.md` | `vendor/std/std/str/tutorial.md` · `vendor/std/std/vec/tutorial.md` |
| `std::fs` | `vendor/std/std/fs/README.md` | `vendor/std/std/fs/tutorial.md` |
| `std::utf8` | `vendor/std/std/utf8/README.md` | `vendor/std/std/utf8/tutorial.md` |
| `std::map` | `vendor/std/std/map/README.md` | `vendor/std/std/map/tutorial.md` |
| `std::arena` | `vendor/std/std/arena/README.md` | `vendor/std/std/arena/tutorial.md` |
| `std::test` | `vendor/std/std/test/README.md` | `vendor/std/std/test/tutorial.md` |

#### 10.1 Closures: carrying context into a callback

Since Phase 21, ct-ast supports inline `=>` closures. The surface type is still a function pointer;
the return type comes from the declaration on the left. The environment lives on the stack, and
escaping it is rejected at compile time.

```c
/* closure.ct */
#include <stdio.h>

int run(int (*fn)(void *env, int x), void *env)
{
    return fn(env, 2) + fn(env, 3);
}

int main(void)
{
    int unit = 10;
    int (*scale)(int x) = (int x) => x * unit;             /* expression body */
    int total = run((int x) => { return x + unit; });      /* the literal fills the (fn, env) pair */
    printf("%d %d\n", scale(4), total);
    return 0;
}
```

```sh
ct build closure.ct -o closure && ./closure
# 40 25
```

- **Capture by value, evaluated at the creation point**: `scale` holds the value `unit` had at that
  moment. A captured name is read-only; to write back, capture a pointer and assign through `*p = …`.
- **A closure variable is a binding, not a value**: it may be called (`scale(4)`), and the binding may
  fill a `(fn, env)` parameter as a whole (`run(scale)`, with a parameter tail that matches the
  host), but it cannot be copied, reassigned, returned, or stored in a field / element. Inline the
  literal when you need another name for it.
- **A literal as an argument**: the host signature must be the adjacent
  `ret (*fn)(void *env, …)` + `void *env`; one literal fills both slots, so `run(…)` takes a single
  literal and the closure's own parameter is supplied inside `run`.
- **C APIs with no env slot** (`qsort` and friends) cannot take one; when the context must outlive
  the current frame, use tier 1: `struct` + `trait` (ct-pkg's `Callable` signature family ships with
  that repository and is not built in here).
- Full syntax, the limitation list and the `(fn, env)` convention are in
  [language-spec §4.44](language-spec.md).

### 10.2 `loop(n)`: just the count

When all you need is "run this n times", skip `for (int i = 0; i < n; i++)`: `loop(n) { … }` expands
to exactly that native `for`, with an implicit counter named `i` starting at 0.

```c
/* loop.ct */
#include <stdio.h>

int main(void)
{
    int sum = 0;

    loop(4) {
        sum = sum + i;
        printf("%d\n", i);
    }
    loop(0) {
        printf("never\n");      /* zero rounds, no diagnostic */
    }
    printf("sum %d\n", sum);
    return 0;
}
```

```sh
ct build loop.ct -o loop && ./loop
# 0 1 2 3, then sum 6
```

- **The count is evaluated once**: `loop(n)` stores `n` in a private temporary and the test reads it,
  so `loop(next())` calls `next` a single time.
- **`i` is a plain `int`**: the body may read and write it (`i = i + 1`, `i++`), and `break` /
  `continue` / `return` behave as in a hand-written `for`; an `own` declared in the body is released
  at each round's exit.
- **The body must be a block**: `loop(3) printf("x");` is rejected; write `loop(3) { printf("x"); }`.
- **Only loop-in-loop shadowing is flagged**: an inner `loop` that hides the outer `i` warns (an
  error under `ct check`); a hand-written `int i` or a native `for` in the body stays silent.
- **`loop` stays an ordinary identifier**: `int loop = 3;`, a `loop:` label and `goto loop;` are
  unaffected; only statement position followed by `(` triggers the shorthand.
- Details and the diagnostic texts are in [language-spec §4.45](language-spec.md).

### 11. CLI cheat sheet

| Command | Purpose |
| --- | --- |
| `ct <in.ct>` / `ct compile <in.ct>` | single-file compile: a plain `.ct` writes only the `.c`, a `.h.ct` input also writes `<in>.h`; **single-file units only**, so `import` needs `ct build` (`-I` only applies to build) |
| `ct <in.ct> -o <out.c>` | explicit output path |
| `ct check <in.ct>` | run the bounded semantic checks only, writing no `.c` (single-file units only; `import` is not accepted): call-site arity / argument types / trait-method ambiguity / impl signature drift (plus existing leak / borrow findings) are reported as `error:`, exit `1` on any finding and `0` when clean |
| `ct build <in.ct>… [-o <exe>]` | multi-file build: C into `.ctbuild/`, then the local C compiler produces an executable (`-o` names it, default `a.out`) |
| `ct build --emit-c … -o <dir>` | C only: one `.c`/`.h` per unit, `-o` is the output directory, and a suggested `cc` line is printed; incremental cache |
| `ct build … --outdir <dir>` | default form: where the generated C goes (default `.ctbuild/`) |
| `ct build … --cc <path>` / `--cflags <s>` / `--ldflags <s>` | pass the C compiler and its flags through (repeatable, or space-separated); the values are spliced into the command as shell fragments, so **never pass untrusted input** |
| `ct build … -I <dir>` | extra import roots (repeatable) |
| `ct build … --ns-root <dir>` | directory = namespace verification root |
| `ct … --emit-map <file\|->` | reverse map JSON (trait/struct/function/impl/map → C symbols) |
| `ct … --diagnostics=json\|text` | warning format (`text` on stderr by default); under `ct check` the same records are reported as errors at `file:line:col:`, and each JSON object carries `"severity":"error"` and `"col"` |
| `ct … --line` / `--no-line` | override `#line` (on for `build`, off for `compile`) |
| `ct … --std=c99\|gnu99` | lands on the C compiler's command line; output is unchanged so far |
| `ct get [--force] <spec>[@<range>]` | fetch packages into `vendor/`, write `ct.lock` (the only subcommand using system `git`); a bare name may resolve through `--index <file>` / `CT_INDEX`; an unsatisfied package `requires` fails the run without touching an existing `ct.lock` (`--force` continues with a warning) |
| `ct update` | re-resolve `ct.pkg` offline, keep the commits `ct.lock` already pinned, and rewrite `ct.lock` |
| `ct install` | verify `ct.lock` against `vendor/` offline and fold each package's `cflags` / `ldflags` and `-I` into **one** build command |
| `ct verify` | verify `vendor/` against `ct.lock` offline and only report; it writes nothing |
| `ct -v` / `ct -h` | version / usage |

Exit codes: `0` on success, `1` on syntax or I/O errors. **Source diagnostics** (parse and semantic)
read `file:line:col: error: message`; semantic records (call-site arity / argument types /
trait-method ambiguity / impl signature drift) are printed as `warning:` under `ct build` /
`ct compile` and **do not change the exit code**, while `ct check` lifts the same records to
`error:` and exits `1`; **driver-level** failures (an input that cannot be opened, a bad
option, a limit) start with `ctc: ` and do not pretend to point at a line.

### 12. Traps

Ordered by how often they bite. Items 2–4 are limits of the **frozen L2 line-rewriting pipeline**;
ct-ast (the main line) is an AST pipeline, so multi-line statements, single-line function bodies and
comment continuations are all fine there (compare [language-spec §6.2](language-spec.md)):

1. **Order matters**: the compiler is a single forward pass, so definitions must precede uses.
2. **Multi-line statements are not rewritten (L2 only)**: L2 works line by line, so a `p.greet()` split
   across lines, or a construct sharing a line with a statement (`int main(){ … p.greet(); }`), is not
   rewritten — one statement per line is a **L2** requirement. ct-ast has no such limit and dispatches
   both spellings.
3. **A block comment protects only its first line (L2 only)**: in L2, continuation lines are treated as
   ordinary code and `self` / method calls in them are rewritten. ct-ast instead **drops the whole
   comment** (generated output keeps no source comments), so the code inside it is neither rewritten nor
   left behind.
4. **Single-line function bodies are not processed (L2 only)**: `int f() { return 1; }` on one line is
   left as is by L2; ct-ast dispatches normally.
5. **`switch` / `do-while` / `goto` are supported** (since batch 7 — see §4.13 / §4.16 and the README
   transform table); the old "`unexpected token` at the `{`" note is stale, and the L0-seed workaround
   is no longer needed.
6. **Block namespaces and bare cross-namespace calls are rejected** by ct-ast; use the semicolon form and
   qualified calls.
7. **Struct-typed array fields**: L0 / L2 do not support them, ct-ast does (element-wise vptr writes —
   see §6 and [language-spec §6](language-spec.md)); for anything else check §4.8 first.
8. **Limits fail hard**: ct-ast raises them to `MAX_TRAITS` 64, `MAX_STRUCTS` 128, `MAX_METHODS` 64,
   `MAX_FUNCS` 256, `MAX_VARS` 4096…, and overflow is an error, never a silent truncation (§7).

### 13. Where to go next

- [language-spec.md](language-spec.md) — the authoritative expansion rules
- [polymorphism.md](polymorphism.md) — why vtables and not something else
- [architecture.md](architecture.md) — how the line-based rewriting works internally
- [roadmap.md](roadmap.md) — what has landed and what comes next
- `examples/**` — eight runnable demos; `test/cases/**` — a minimal snapshot per feature
- Editor support: `editors/vscode/` (declarative highlighting, zero dependencies)
- Dialects: `examples/07_dialect/` turns comment-embedded DSLs into plain CT; the compiler stays unaware
- Packages: `ct get` / `ct update` / `ct install` / `ct verify`, manifest format in
  [design/phase8.md](history/design/phase8.md); the 17.5 additions (comparator ranges, offline
  re-resolution, the explicit index, build metadata) are in [design/phase17.md](design/phase17.md)
