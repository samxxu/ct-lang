# CT 入门教程

> 中文

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

### 8.1 块级 `defer`

`defer { … }` 在块退出时按后进先出执行，覆盖正常落出、`return`、`break`、`continue`；
同一块内它先于 `own` 的自动释放。只收块形态，且只能在函数体内使用。

```c
int read_file(const char *path)
{
    FILE *f = fopen(path, "rb");
    if (!f) return -1;
    defer { fclose(f); }
    return parse(f);
}
```

`return expr` 会先把值存进临时量再跑 defer，所以 defer 里改写局部变量不会改变返回值。
`goto` 跨出带 defer 的块是硬错；defer 内禁止 `return` / `break` / `continue` / 嵌套 defer。
可运行样例见 `examples/42_defer`。

## 9. `map` 与 bindings：把 trait 绑到已有的 C 库

不想为了用 C 库而改库的代码，就用 `map` 把一个**已声明的全局实例**绑定成 trait 实现。
这是把假 HAL 接进 CT 的官方做法（[test/bindings/mock-hal/uart.h.ct](../test/bindings/mock-hal/uart.h.ct)）：

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
`ct_sock_errno()`。完整例子见 `test/bindings/posix-socket/`；改了 shim 会让消费者重建。
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

C 回调的经典麻烦是上下文：函数指针只带得住代码，带不住 `unit`、`limit` 这类局部值，于是要么写成
全局变量，要么手写一个 `struct` 加一层 `void *` 强转。Phase 21 的 `=>` 把这两步收进语言：字面量
在声明处创建，捕获按值拷进一个栈上的环境结构体，调用时 `(fn, env)` 两个词一起走。

表面类型仍然是函数指针，返回类型由左侧声明给出（不推断），参数必须带类型，无参写 `()`；表达式体
与块体在下面的例子里各有一个（`mul` 与 `twice`）。

闭包真正好用是在容器的回调位上。[examples/10_closure_pipeline/closure_pipeline.ct](../examples/10_closure_pipeline/closure_pipeline.ct)
是一个完整、可编译可运行的例子（省掉文件头注释）：

```c
#include <stdio.h>

static int fold(int (*fn)(void *env, int acc, int x), void *env, int n)
{
    int acc = 0;

    loop(n) {
        acc = fn(env, acc, i + 1);
    }
    return acc;
}

int main(void)
{
    int factor = 3;
    int limit = 1;
    int (*mul)(int acc, int x) = (int acc, int x) => acc + x * factor;
    int (*cap)(int acc, int x) = (int acc, int x) => acc + x + limit;
    int (*twice)(int acc, int x) = (int acc, int x) => {
        int t = acc;

        loop(2) {
            t = t + x;
        }
        return t;
    };

    limit = 100;
    printf("mul %d\n", fold(mul, 3));
    printf("cap %d\n", fold(cap, 3));
    printf("twice %d\n", fold(twice, 3));
    printf("lit %d\n", fold((int acc, int x) => acc + x, 3));

    /* one closure per round: each snapshot keeps that round's `i` */
    loop(3) {
        int (*snap)(int x) = (int x) => x + i * 10;

        printf("snap %d\n", snap(1));
    }
    return 0;
}
```

```sh
ct build closure_pipeline.ct -o closure_pipeline && ./closure_pipeline
# mul 18
# cap 9
# twice 12
# lit 6
# snap 1
# snap 11
# snap 21
```

- **捕获按值、创建点求值**：`cap` 捕获 `limit` 时它是 1，后面 `limit = 100` 改不到闭包里的副本，
  所以 `cap` 那行是 9（`1+1`、`2+1`、`3+1` 的累加）。要共享可写状态就捕获指针，通过 `*p = …` 写回。
- **捕获名只读**：体内写捕获名（`n = …`、`n++`、复合赋值）报
  `a captured variable cannot be reassigned inside a closure`；取地址 `&n` 报
  `the address of a captured variable cannot be taken inside a closure`。
- **捕获不到的东西**：数组（`a closure cannot capture the array 'a' (capture a pointer to it instead)`）、
  `own` / `borrow` 变量、另一个闭包。全局变量、函数名、类型名和枚举常量不进 env，直接按名字用。
- **闭包变量是绑定，不是值**：可以调用（`mul(...)`、`snap(1)`），也可以把绑定整对交给 `(fn, env)`
  参数（`fold(mul, 3)`）；不能拷贝、重赋值、作返回值、作字段或数组元素。需要另一个名字就把字面量
  就地再写一遍（`fold((int acc, int x) => acc + x, 3)`）。
- **两种实参写法**：内联字面量一次填满相邻的 `ret (*fn)(void *env, …)` + `void *env` 两个槽；
  已声明的绑定同样按两项计。两者都要求闭包的参数表与宿主尾部逐参一致（个数与类型），否则报
  `this closure's parameter N is '…', but the expected type is '…'`。
- **env 活不过这次调用**：容器拿到 `(fn, env)` 后只能在本次调用里用，不能存进字段、全局或返回。
  存了就是 E8（见下）。

**闭包进静态映射调用（Phase 25）**

`.m.ct` 的静态映射（见 §9.1）与普通调用同口径接收闭包：只要宿主方法的形参对是
`ret (*fn)(void *env, …)` + `void *env`，`a.each(...)` 就能直接吃闭包，arity 按两项计。

```c
int base = 10;
int a[4] = { 1, 2, 3, 4 };

a.each(4, (int x) => { printf("%d\n", x + base); });   /* 11 12 13 14 */
```

产物是裸 C 调用，闭包按同一条 `(fn, env)` ABI 落位：

```c
ct_each_int(a, 4, __ct_cl_tramp_0, &(struct __ct_cl_env_0){ .base = base });
```

recipe 必须把这个实参的 `fn` 与 `env` 各引用一次：重复引用、只引用一半或都不引用、把闭包放在 `...`
尾部，都是编译期硬错。环境仍是栈上的复合字面量，shim 必须在本次调用里同步消费（同上面的「env 活不过
这次调用」）。

**档①：上下文要活过栈帧时**

闭包的环境在声明作用域的栈上，出了作用域就没了，所以三类场景接不了：C API 没有 `void *` 环境槽
（`qsort` 的比较函数只有两个 `const void *`）；回调要被保存下来稍后调用（事件表、定时器、容器
字段）；回调要跨单元、进 `.h.ct`（头文件里只有普通函数指针）。

这时退回档①：`struct` 持有状态、`trait` 描述回调外形、一个两行适配器满足 `(void *self, …)`。
[examples/09_callback](../examples/09_callback/callback.ct) 就是模板——`Adder` 是状态，`IntOp`
是回调形状，`adder_call` 是适配器，容器只认 `(fn, env)`。ct-pkg 把常用签名收成 `Callable` 系列，
本仓未内置。

**编译器看不见的面**

- **E8**：`env` 以 `void *` 交给不透明接收方后被保存。编译器不追踪指针去向，不会拦。
- **E9**：`goto` 跨过闭包声明跳进它的作用域，跳过去的路径上 env 没有初始化；编译器不做支配分析。

**诊断速查**

| 写法 | 报错 |
| --- | --- |
| 声明后 `f = g;` 或 `f2 = f;` | `this closure is a binding, not a value (inline it or use a struct + trait)` |
| `return f;` | `a closure cannot escape through 'return'` |
| 存字段 / 数组元素 | `a closure cannot be stored in a field, an element or a container` |
| 传给不是 `(fn, env)` 的位置 | `a closure argument must fill a '(fn, env)' parameter pair` |
| 全局 / `pub` 全局的初始化式 | `a closure cannot be stored in '<name>' (its scope outlives the closure)` |

完整规则见 [language-spec §4.44](language-spec.md)。

### 10.2 `loop(n)`：只数次数

只要「跑 n 次」时，不用再写 `for (int i = 0; i < n; i++)`。`loop(n) { … }` 展开的正是这条原生
`for`：

```c
for (int i = 0, __ct_loop_n_K = (<count>); i < __ct_loop_n_K; i++) { … }
```

- **`i` 从 0 起、到 `n-1`，是一个普通可写 `int`**：体内可以读、可以改（`i++`、`i = i + 1`），
  `break` / `continue` / `return` 与手写 `for` 完全一致。`loop(0)`、`loop(-2)` 都是零轮，不报错。
- **循环之后 `i` 不可见**：`loop(3) { … }` 结束后再写 `i` 就是未声明标识符。要留下结果，累加到
  循环外的变量里（下面例子里的 `calls`）。
- **计数只求值一次**：表达式绑进私有临时量 `__ct_loop_n_K`，条件读临时量。`loop(count())` 无论
  多少轮，`count` 只进一次。
- **`loop` 是上下文关键字**：`int loop = 3;`、`loop:` 标签、`goto loop;`、`x = loop + 1;` 都还是
  普通标识符；只有语句位置紧跟 `(` 时才当语法糖。

**嵌套与遮蔽**：内层 `loop` 遮蔽外层的隐式 `i` 时，编译模式打印
`warning: loop shadows the outer 'i'; use a native for to name the inner counter`；同一段代码在
`ct check` 下记为 `loop_shadow` 错误。体内手写 `int i` 或原生 `for` 属于普通 C 遮蔽，不诊断。
真需要两个计数器，就直接写原生 `for (i = 0, j = n; …)`。

**`own` 与提前跳出**：`own` 变量的释放在块尾、`break` 前、`continue` 前都会执行，所以正常走完
一轮和提前跳出都会释放；原生 `for` / `while` 同样如此。（`goto` 跨层跳出仍是 v1 例外，见 §4.9。）
回归测试里 `test/ast/loop_own_drop` 覆盖正常块尾，
`examples/tour/15_memory/drop_loop_break` 覆盖 `break` / `continue`。

**什么时候退回原生 `for`**

- 循环结束后还要用计数器；
- 需要步长、反向或两个计数器；
- 需要非 `int` 的计数器（`size_t`）或超过 `INT_MAX` 的范围；
- 体内有 `goto` 跨层跳出且持有 `own` 资源（见上；`break` / `continue` 已正常释放）。

[examples/11_loop_semantics](../examples/11_loop_semantics/loop_semantics.ct) 用一个文件覆盖
上面这些行为与 10.3 的区间形式（`main` 原文）：

```c
int main(void)
{
    /* the implicit counter starts at 0 and stops before the count */
    loop(3) {
        printf("count %d\n", i);
    }
    /* zero rounds are not a diagnostic */
    loop(0) {
        printf("never\n");
    }
    /* the count expression runs once, however many rounds follow */
    loop(count()) {
        printf("once %d\n", i);
    }
    printf("calls %d\n", calls);

    /* half-open [2, 5): the lower bound is evaluated first, once each */
    loop(lo()..hi()) {
        printf("range %d\n", i);
    }
    /* an empty range is silent */
    loop(4..2) {
        printf("never\n");
    }
    /* `loop(0..b)` folds to `loop(b)` and prints the same thing */
    loop(0..3) {
        printf("zero %d\n", i);
    }

    /* break / continue / writing `i` work exactly as in a native for */
    loop(5) {
        if (i == 2) {
            continue;
        }
        if (i == 4) {
            break;
        }
        printf("skip %d\n", i);
    }
    loop(3) {
        printf("write %d\n", i);
        i = i + 1;
    }
    return 0;
}
```

```sh
ct build loop_semantics.ct -o loop_semantics && ./loop_semantics
# count 0
# count 1
# count 2
# once 0
# once 1
# once 2
# calls 1
# eval lo
# eval hi
# range 2
# range 3
# range 4
# zero 0
# zero 1
# zero 2
# skip 0
# skip 1
# skip 3
# write 0
# write 2
```

（`calls 1` 证明 `count()` 只调了一次；`skip` 少了 2 和 4，是 `continue` 与 `break` 的结果；
`write` 只打了 0 和 2，因为体内把 `i` 改大后跳过了下一轮。）

**语法硬错误**：`loop()` → `loop needs a count expression`；`loop(3) printf("x");` →
`loop body must be a block`；`loop(3, x)` →
`loop takes exactly one count; use a native for to name the counter`。静态可判定的非整数计数
（`double` 一类）在编译模式下是一条
`warning: type mismatch: 'loop' count must be an integer (got 'double'); the value is converted to int`，
`ct check` 下同一句变 `error:`，运行时仍按 C 规则转成 `int`。细节见
[language-spec §4.45](language-spec.md)。

### 10.3 `loop(a..b)`：从 a 数到 b-1

起点不是 0 时，把区间写在括号里：`loop(2..5)` 就是 `for (int i = 2; i < 5; i++)`，左闭右开。
展开恰好是：

```c
for (int __ct_loop_n_K, __ct_loop_hi_K,
         i = ((__ct_loop_n_K = (<start>)), (__ct_loop_hi_K = (<stop>)), __ct_loop_n_K);
     i < __ct_loop_hi_K; i++) { … }
```

- **半开区间 `[a, b)`**：`i` 从 `a` 起、取到 `b-1`。`b <= a` 零轮，不报错也不告警；没有反向、
  没有步长、没有闭区间。
- **两个边界各求值一次，先 `a` 后 `b`**：两个赋值写在 `i` 的**同一个**初始化器里，靠逗号运算符
  定序（C99 §6.5.17），上界存进私有临时量 `__ct_loop_hi_K`。这里不依赖同一声明里多个声明符
  初始化器的次序——C99 §6.7.8 没有规定该次序。10.2 例子的 `eval lo` 在 `eval hi` 之前、且各一次，
  就是这条。
- **`i` 与 `loop(n)` 完全相同**：作用域、`break` / `continue` / `return`、`i--` / `++i`、闭包按值
  捕获（每轮一个快照）全部照旧。`own` 的释放同样挂在块尾：正常走完一轮会释放，`break` /
  `continue` 跳过块尾也跳过释放（见 10.2 的说明，原生循环同样如此）。
- **`loop(0..b)` 与 `loop(b)` 相同**：字面量 `0` 的下界在解析期折掉，生成物逐字节一致。折叠是纯
  语法的：`0L..b`、`0x0..b` 也折，`-0..b`、`0+0..b` 不折（语义等价但不做常量折叠）。
- **`..` 是单个 token**：`2..8` 不会被切成浮点 `2.` 与 `.8`，`...` 仍是三连点。
- **边界必须是整数**：指针、数组、`struct` / `union` 值、函数指针是硬错误
  `a loop bound must be an integer (got 'int *')`（数组变量是 `(got the array 'a')`）；
  `loop(..b)` / `loop(a..)` 报 `a loop range needs both bounds`；`loop(1..2..3)` 是语法错误。
  `float` / `double` / `void` 这类静态可判定的非整数标量仍只告警（两条边界各报一次），运行时按
  C 规则转成 `int`。
- **边界存进 `int`**：`i` 与临时量都是 `int`，`size_t` / `long` 超出 `INT_MAX` 的边界按 C 的转换
  规则截断。需要大范围计数的场景写原生 `for`。

**和闭包组合**：闭包在体内按值捕获 `i`，每轮一个快照。
[examples/12_closure_in_loop](../examples/12_closure_in_loop/closure_in_loop.ct) 把三件事放在一起
——容器用 `loop(from..to)` 遍历，`shift` 在 `bias = 1000` 之前创建（所以捕获的仍是 7），每轮新建
的 `scale` 钉住当轮的 `i`（原文）：

```c
#include <stdio.h>

static int map_sum(int *xs, int from, int to, int (*fn)(void *env, int x), void *env)
{
    int sum = 0;

    loop(from..to) {
        sum = sum + fn(env, xs[i]);
    }
    return sum;
}

int main(void)
{
    int xs[5];
    int bias = 7;
    int (*shift)(int x) = (int x) => x + bias;

    loop(5) {
        xs[i] = i * i;
    }
    /* `shift` was built above: it still holds 7, not 1000 */
    bias = 1000;

    printf("shift %d\n", map_sum(xs, 1, 4, shift));

    /* a fresh closure per round, each one pinning its own `i` */
    loop(2..4) {
        int (*scale)(int x) = (int x) => x * i;

        printf("round %d %d\n", i, map_sum(xs, 0, 2, scale));
    }
    return 0;
}
```

```sh
ct build closure_in_loop.ct -o closure_in_loop && ./closure_in_loop
# shift 35
# round 2 2
# round 3 3
```

（`shift` 是 `xs[1..4)` 即 1、4、9 各加 7 的和；`round` 里的 `scale` 把 `xs[0..2)` 即 0、1 乘以
当轮的 `i`。）

细节与诊断见 [language-spec §4.46](language-spec.md)。

### 10.4 `0..n($)`：把表直接写进源码

有些表本来就是从下标算出来的。`0..n(<表达式>)` 让源码保持公式的样子，编译器替你展开：

```c
#include <stdio.h>

static const int sq[] = 0..11($ * $);

int main(void)
{
    printf("%d %d %d\n", sq[0], sq[3], sq[10]);
    return 0;
}
```

```sh
ct build table.ct -o table && ./table
# 0 9 100
```

`$` 是**下标**，不是变量：它从 `0` 走到 `10`（区间左闭右开），生成物是同长度的花括号列表，
`$` 换成对应的常量：

```c
static const int sq[] = { (((int)0) * ((int)0)), (((int)1) * ((int)1)), …, (((int)10) * ((int)10)) };
```

- **没有循环、没有临时量**：产物就是初始化列表，所以能写在文件作用域的 `static const` 上（函数里也行）。
- **边界只收字面量**：`0..n($)` 是编译错误（`a range bound must be an integer literal (got 'n')`）。
  这样 `0..13(` 永远不会被读成函数调用。
- **`$` 出了这个初值就不合法**：`int x = $;` 是语法错误，`int a[$];`、`&$`、`$++` 各有自己的
  诊断，都不会落成「未声明变量」。
- **元素表达式别写副作用**：列表里各初始化器的求值次序 C 不保证。

细节与诊断见 [language-spec §4.47](language-spec.md)。

### 10.5 泛型函数：一份源码，多种类型

`T id<T>(T x)` 声明一个只有一个类型参数的模板；调用时用 `id<int>(42)` 指定具体类型，编译器为每个
具体类型生成一份 `static` C 函数：

```c
#include <stdio.h>

T id<T>(T x)
{
    return x;
}

int main(void)
{
    int a = id<int>(42);
    char *p = id<char *>("hi");
    printf("%d %s\n", a, p);
    return 0;
}
```

```sh
ct build gen.ct -o gen && ./gen
# 42 hi
```

- **显式实例化**：`id(42)` 是编译错误（`generic function 'id' needs a type argument`），不做类型推导。
- **模板不落成 C 符号**：生成物里只有 `id__ct1`、`id__ct2` 两份 `static` 函数，模板本身不输出。
- **只做函数**：泛型结构体、trait、约束、多类型参数、`pub` 泛型、递归 / 嵌套泛型调用都不支持，
  各自在源码处报错。
- **同一类型只生成一份**：同一 `(模板, 类型)` 在多个调用点复用同一个实例。
- **类型参数在类型位置会真替换**：形参/返回/局部声明、`(T)`、`sizeof(T)`、`_Alignof(T)`、
  `offsetof(T, 字段)`、`va_arg(ap, T)` 都替换成具体类型，生成物里不留 `T`；`_Generic` 的选择体
  是原样透传，因此模板体内写 `_Generic(..., T: ...)` 会硬报错，而不是发射未声明的名字。

细节与诊断见 [language-spec §4.48](language-spec.md)。

### 10.6 `foreach`：遍历数组，不用起下标

遍历一维数组时，不用自己维护下标。`foreach (数组) { … item … }` 在块内直接给你当前元素 `item`：

```c
#include <stdio.h>

struct Point {
    int x;
    int y;
};

int main(void)
{
    int nums[] = {3, 1, 4, 1, 5};
    struct Point pts[2] = {{1, 2}, {3, 4}};
    int total = 0;
    int sx = 0;

    foreach (nums) {
        if (item == 1) continue;
        total = total + item;
    }
    foreach (pts) {
        sx = sx + item.x;
    }
    printf("%d %d\n", total, sx);
    return 0;
}
```

```sh
ct build walk.ct -o walk && ./walk
# 12 4
```

- **展开就是一个普通 `for`**：长度 `sizeof(x) / sizeof((x)[0])` 在循环前只读一次，
  `item` 是元素的值拷贝；生成物没有运行时对象，`break` / `continue` / `return` 与手写循环一致。
- **只收一维数组变量**：裸指针、多维数组、数组形参、数组成员都硬报错（长度不可知就不猜），
  接口值元素也不拷贝。
- **`item` 只在块内可见**，块外引用是未声明标识符；嵌套 `foreach` 遮蔽外层 `item` 时编译模式给
  warning，`ct check` 下是错误。
- **`foreach` 是上下文关键字**：`int foreach = 3;`、`foreach:` 标签、`goto foreach;` 都照常。

容器协议（`len()` + `get(int)`）与显式绑定名不在本相；细节与诊断见
[language-spec §4.49](language-spec.md)。

### 10.7 约束泛型：让泛型知道该调用谁

泛型函数对 `T` 一无所知时，连 `a.cmp(&b)` 都调不了。给类型参数加一个 trait 约束，
模板体就能调用该 trait 的方法；每个具体 struct 各得一份实例，落成裸 C 调用：

```c
#include <stdio.h>

trait Compare {
    int cmp(void *other);
}

struct Num {
    int v;
} use Compare;

impl Compare for Num {
    int cmp(void *other)
    {
        struct Num *o = (struct Num *)other;
        return self->v - o->v;
    }
}

T max2<T: Compare>(T a, T b)
{
    if (a.cmp(&b) > 0) {
        return a;
    }
    return b;
}

int main(void)
{
    struct Num p;
    struct Num q;

    p.v = 3;
    q.v = 7;
    printf("%d\n", max2<struct Num>(p, q).v);
    return 0;
}
```

```sh
ct build max2.ct -o max2 && ./max2
# 7
```

- **语法**：`T name<T: Trait>(…)`，单类型参数、单约束、显式实例化；`T: A + B` 直接报错。
- **约束能回答什么**：模板体内的 `x.m(…)` / `p->m(…)` / `arr[i].m(…)`（含 trait 默认方法）
  按约束的方法表解析，实参按该签名检查；约束里没有的方法在解析期报错，不会漏到 C。
- **实例化要满足约束**：类型实参必须是 struct（或指向 struct 的指针），并且 `use Trait`
  或 `impl Trait for S`；否则在调用点报 L28-5 / L28-6。`impl` 写在调用点之后也算数。
- **落码是裸调用**：`Num_Compare_vtable.cmp(&a, (&b))`，不读 `__compare_vptr`、不装箱、
  不改结构体布局；跨单元时依赖单元的生成头只多一行 `extern struct Compare_vtbl …`。
- **`char *` 不能直接满足约束**（`impl` 只对 struct 生效）：需要字符串比较时用一个 struct
  包住指针，完整例子见 `examples/21_generic_bound`。

细节见 [language-spec §4.50](language-spec.md)。

### 10.8 泛型 struct、`Vec` / `Map` 与容器 `foreach`

`struct Name<T, U>` 定义模板：每个类型实参组合得到一份独立的 C 结构体，字段里的 `T`
就地替换。`impl<T> Name<Args>` 给这些实例加方法，调用点静态派发，没有 vtable。
`Vec` / `Map` 是内置层，不需要 `import`：

```c
#include <stdio.h>

struct Stack<T> {
    T items[8];
    int n;
}

impl<T> Stack<T> {
    int push(T v)
    {
        if (self->n >= 8) return 0;
        self->items[self->n] = v;
        self->n = self->n + 1;
        return 1;
    }
}

int main(void)
{
    Vec<int> v;
    Map<char *, int> ages;
    Stack<int> st;

    v.h = 0;
    v.data = 0;
    v.push(10);
    v.push(20);
    foreach (v) {
        printf("[%d] %d\n", i, item);
    }

    ages.h = 0;
    ages.entries = 0;
    ages.put("bo", 31);
    ages.put("amy", 24);
    foreach (ages) {
        printf("%s=%d\n", item.key, item.value);
    }

    st.n = 0;
    st.push(7);
    printf("%d\n", st.items[0]);

    v.release();
    ages.release();
    return 0;
}
```

- **`foreach` 的绑定**：数组和 `Vec` 同时给 `item`（值拷贝）与只读 `i`；`Map` 只给 `item`，
  它是条目，读 `item.key` / `item.value`。写 `i`、重声明 `item`/`i`、在 `Map` 体内用 `i`
  都是硬错。
- **`Map` 的次序**：插入序；重复键原位改值；`remove` 让后面的条目左移。
- **引用计数**：`Vec` / `Map` 是共享 `ct_buf` 的句柄，`retain` 加一、`release` 减一并返回
  剩余数，归零时释放；`release` 之后该句柄即失效，对同一句柄再 `release` 会 `abort`
  （即使 `retain` 出的兄弟句柄还持有共享缓冲）。
- **range 初值构造 `Vec`**：`Vec<int> v = 4..8 { $ * $ };` 与数组的 `0..3($)` 同一套写法，
  `$` 仍是元素下标。产物是复合字面量交给 `Vec<T>::from`，所以语义等价于
  `Vec<int> v = Vec<int>::from((int[4]){ 16, 25, 36, 49 }, 4);`——静态入口可以自己调，
  `impl` 里的 `static Ret name(params)` 就是这种无 `self` 的方法。
- **类型位**：`>>` 自动拆开（`Box<Box<int>>` 合法），实例最多两层参数、嵌套最多四层。
- 已知限制：固有方法只检查元数、不检查实参类型；`v[i]` / `m["k"]` 与 `Map` 的 `{ "k": 1 }`
  字面量尚不支持（但都会在编译期报错：`a Vec is not subscriptable: use get(i) / set(i, v)`、
  `a Map is not subscriptable: use get(key)`、`a Map cannot be initialized from a brace list`）。
  内置层在 `ct compile` 与 `ct build` 两条路径都自动加载，不需要 `import` / `-I`；旧项目若还
  `import std::vec`，会与内置名冲突（`'Vec' is a built-in type and cannot be redeclared`），
  须升级 `std` 包或删掉该 import。
- `Map` 的键只接受 `int` / `long` / `char *`；其余类型在类型实参处硬错（L29-8）。
- 完整样例：[22_foreach_map](../examples/22_foreach_map/foreach_map.ct)、
  [23_generic_stack](../examples/23_generic_stack/generic_stack.ct)、
  [24_vec_ops](../examples/24_vec_ops/vec_ops.ct)、
  [25_wordcount](../examples/25_wordcount/wordcount.ct)、
  [26_range_vec](../examples/26_range_vec/range_vec.ct)、
  [27_map_keys](../examples/27_map_keys/map_keys.ct)。

细节见 [language-spec §4.51](language-spec.md)。

### 10.9 容器表达力：接口值、嵌套、字面量与借用（Phase 31）

Phase 31 让容器成为普通的元素/值类型，并定义了围绕句柄的所有权协议：

```ct
Vec<Vec<int>> rows = {};
Vec<int> row = {1, 2};
rows.push(row);

Map<char *, int> counts = {"a": 1, "b": 2};
counts.put("c", 3);
int n = rows[0].len();      /* v[i] / m[k] 只读，等价于 get */
int first = counts["a"];
```

- **元素**：接口值（`Vec<Show>`）与容器（`Vec<Vec<int>>`）都能作元素；接口元素是**非拥有**
  拷贝，容器不会替对象收尾；接口指针（`Vec<Show *>`）硬错 L31-1。
- **句柄布局（H-A）**：句柄只有一个 `h` 指针，`ct_buf` 持有 `refs` / `len` / `cap` / `data`，
  所以 `retain` 出的兄弟句柄不会因对方扩容而指到旧存储。
- **借用视图**：`get` / `entry` / `foreach item` 都是借用，不拥有；对借用 `release` 会报
  `cannot release a borrowed container view; call retain() first`。借用经拷贝初始化/赋值
  传播；`pop` 交出所有权，释放它的结果合法。
- **失效**：同一 block 内对容器做 `put` / `remove` / `clear` / `release` 之后再用旧视图，
  报 `a borrowed view is invalidated by a later mutation…`；在 `foreach` 体内改正在遍历的
  容器报 `cannot mutate the container being iterated…`。
- **下标糖**：`v[i]` / `m[k]` 只读；赋值、复合赋值、自增、取址、成员赋值都是 L31-3/4/5，
  写请用 `set` / `put`。
- **花括号初值**：`Vec<T> v = {…}`、`Map<K, V> m = {k: v, …}` 只在局部声明可用，空 `{}`
  给出非空 header；编译期重复键 `duplicate key` 硬错（L31-16），运行期重复键原位覆盖。
- **分配顺序**：header 失败一律 `abort`（不可释放的句柄绝不外流）；扩容失败在 retain 之前
  `return 0` / 返回部分表；`from` 失败路径不 `free`。
- 完整样例：[33_vec_brace_init](../examples/33_vec_brace_init)、
  [34_map_literal](../examples/34_map_literal)。

细节见 [language-spec §4.53](language-spec.md)。

### 10.10 有界泛型 struct 与嵌套 impl pattern（Phase 33）

`struct` 的类型参数可以带一个 trait 约束，模板实例在创建它的单元里接受校验；`impl` 的方法体
按位置继承这个约束，模板体内可以直接调用约束方法，派发仍是编译期静态的：

```ct
trait Show { int show(); }
struct Circle { int r; } use Show;

struct Box<T: Show> { T value; }

impl<T> Box<T> {
    int reveal() { return self->value.show(); }
}

int main(void)
{
    Box<Circle> b;
    b.value.r = 7;
    printf("%d\n", b.reveal());   /* Box_Circle_reveal → Circle_Show_vtable.show */
    return 0;
}
```

- **约束不是装箱**：`Box<Circle>` 内联存 `Circle`，`show()` 落成 `Circle_Show_vtable.show(&b.value)`，
  不加 vptr、不改布局；实例化时若实参没有 `use Show` 也没有 `impl Show for <实参>`，在实例处报
  `instance argument '…' does not satisfy the bound 'Show'`。
- **一个参数一个约束**：`T: A + B` 与在 impl 上重复写约束都是硬错（L33-3 / L33-2）。
- **约束可见性**：消费方单元看不到约束 trait 时报 L33-6，不会拖到链接期；只声明不实例化仍可编译。
- **嵌套 pattern**：`impl<T> Box<Box<T>>`、`impl<T> Pair<int, Box<T>>` 按结构匹配，`Box<Box<Circle>>`
  会派发到外层方法；pattern 里的裸 `T` 不登记成伪实例。depth 超过 4（即 6 个 `Box`）报 L33-4，
  `_` / `T[2]` / `T *` / 函数指针等形态报 L33-5。
- **跨单元**：元素与容器模板不在同一单元时，消费方单元自行发射私有的 `static` 元素 helper 与实例
  方法副本，`.h` 只有类型——`Vec<Point>` / `Vec<Show>` 无需把元素挪进同一单元。
- 泛型 trait 与 supertrait 由 Phase 35 提供。完整样例：
  [36_bounded_struct](../examples/36_bounded_struct)、[37_nested_pattern](../examples/37_nested_pattern)。

细节见 [language-spec §4.54](language-spec.md)。

### 10.11 生态复用：`pub` 泛型、跨单元固有方法与 `Option`/`Result`（Phase 34）

库单元的 `pub` 泛型函数把模板体留在 `.h.ct` 里，消费方按需在本单元发 `static` 实例；非泛型
struct 也可以用 `impl Name { … }` 加固有方法，属主发一次定义，消费方只取原型：

```ct
/* eco.h.ct */
pub struct Counter { int n; }

impl Counter {
    static Counter make(int n) { Counter c; c.n = n; return c; }
    void bump() { self.n = self.n + 1; }
    int get() { return self.n; }
}

pub T twice<T>(T x) { return x + x; }
```

```ct
/* main.ct */
#include <stdio.h>
import eco;

int main(void)
{
    Counter c = Counter.make(3);
    c.bump();
    Option<int> some = { 1, c.get() };
    Result<int, char *> ok = { 1, twice<int>(2), 0 };
    printf("%d %d\n", some.unwrap(), ok.unwrap());
    some.release();
    ok.release();
    return 0;
}
```

- **`Option` / `Result` 是库代码**：`lib/std/Option.h.ct` 与 `Result.h.ct` 都是普通泛型 struct，
  不需要 `import`；`{ 1, v }` 表示有值、`{ 0 }` 表示空，`Result` 是 `{ 1, v, 0 }` / `{ 0, 0, e }`。
- **取值**：`unwrap_or` 给默认值，`unwrap` 在空 / 错误一侧 `abort`；`set` / `clear`（`Result` 是
  `set_ok` / `set_err`）就地改标签。
- **实例归属**：`Point` 在消费方单元时，`Option<Point>` 的布局与方法都在消费方发射，库的头文件
  只留前向声明。
- **边界**：payload 按值拷贝、`release` 是 no-op；`?`、pattern matching 与 payload 自动释放属于
  后续阶段。

完整样例：[38_ecosystem_reuse](../examples/38_ecosystem_reuse)。细节见
[language-spec §4.51](language-spec.md)。

### 10.12 泛型 trait：`trait Iter<T>` 与 `Iter<int>`（Phase 35）

trait 也能带类型参数：声明 `trait Iter<T>` 后，`Iter<int>` 是一个独立的 trait 实例，有自己的
vtable 与 iface 结构；`impl Iter<int> for Range` 填它的方法槽，接口值照常派发：

```ct
trait Iter<T> {
    T next(void);
}

struct Range {
    int cur;
} use Iter<int>;

impl Iter<int> for Range {
    int next(void) { return self->cur; }
}

int main(void)
{
    Range r = { .cur = 3 };
    Iter<int> it = r;
    printf("%d %d\n", r.next(), it.next());   /* 3 3 */
    return 0;
}
```

- **命名**：实例名是 `Iter_int`，产物跟着走——`Iter_int_vtbl` / `Iter_int_iface` /
  `__iter_int_vptr` / `Range_Iter_int_next`；`Iter<char *>` 是 `Iter_char_p_*`，嵌套实参按转义
  （`Iter<Vec<int>>` → `Iter_Vec_lint_r_*`）。非泛型 trait 的产物命名不变。
- **约束**：`trait Seq<T: Show>` 在实例创建单元校验实参，`int` 没有 `Show` 时报
  `'int' does not satisfy the bound 'Show' of 'Seq'`；`T: Iter<int>` 作泛型函数的约束时同样按实例行派发。
- **泛型 trait × 泛型 struct**：只支持一一对应的 `impl<T> MyVec<T> use Iter<T>`，其它形态报
  `unsupported generic trait implementation shape`。
- **跨单元边界**：实例只能在模板属主单元创建；消费方可以命名 `Iter<int>`，但一经创建就报
  `a generic trait instance must be created in its owner unit`。
- **不做的**：默认方法体（报 `a generic trait cannot carry a default method body`）、supertrait
  与接口组合、多 bound。

完整样例：[39_generic_trait](../examples/39_generic_trait)。细节见
[language-spec §4.55](language-spec.md)。

### 10.13 泛型 `Drop` 与长度前缀字符串 `Str`（Phase 36）

`Drop` 也能像 trait 一样写泛型实现：`impl<T> Drop for Box<T>` 会按每个实参单态化出一个
`Box_int_Drop_drop` / `Box_Str_Drop_drop`，不会留下模板态的 `Box_Drop_drop`。注意两点：

- **声明顺序、自负全责**：没有显式 `impl Drop` 时，编译器按字段声明顺序为每个带 `use Drop`
  的字段递归生成释放胶水；一旦写了 `impl Drop`（含泛型形态），就**不再**生成字段胶水，释放
  资源是你自己的事。
- **`drop()` 里不能重复释放同一字段**：`self->buf.release()` 写两次会报
  `field 'buf' is released more than once in drop()`。

字符串用内建的 `Str`（`lib/std/Str.h.ct`），布局是 `{ char *data; int len; }`，`len` 是契约
（内嵌 `\0` 也保留，不靠结尾 NUL）：

```ct
Str s = str_from("hello");
Str t = s.retain();          /* 深拷贝，t 有独立 buffer */
s.release();                 /* 释放 s，t 不受影响 */

own Str *p = malloc(sizeof(struct Str));
*p = str_from("heap");
delete p;                    /* Drop 释放 buffer，再 free 结构体并置空 */
```

`Str` 按值传递只浅拷贝指针，要独立副本必须显式 `retain()`。`Option<T>` / `Result<T,E>` 已带
`use Drop`，它们的 `none()` / `ok()` / `err()` 会零初始化未用的 payload，使胶水安全释放。

完整样例：[40_str_ownership](../examples/40_str_ownership)。细节见
[language-spec §4.56](language-spec.md)。

### 10.14 `errdefer` 与显式错误出口（Phase 40）

`defer` 无条件清理；`errdefer` 只在**显式错误出口**执行。错误由语法标记，不由返回类型猜：

```ct
static int load(void)
{
    int fd = open_db();
    int n = read_all(fd) errdefer { if ($ < 0) rollback(fd); };
    defer { if (fd) close_db(fd); }
    if (n < 0) {
        return err: -1;
    }
    return n;
}
```

`return err: …` / `break err:` / `continue err:` 是三种错误出口；普通 `return` / `break` / `continue` 只跑 `defer`，丢弃 `errdefer`。尾随声明里的 `$` 是左侧变量名的只读别名；`errdefer` 块必须自己 guard 可能失败的值。

完整样例：[43_errdefer](../examples/43_errdefer)。细节见 [language-spec §4.58](language-spec.md)。

### 10.15 原子并发：`atomic T` 与 `ct_atomic_*`（Phase 41）

```ct
atomic int hits = 0;
atomic bool stop = 0;
int expected = 0;

ct_atomic_store(&hits, 1);
if (!ct_atomic_cas(&hits, &expected, 2))
    return 1;
while (!ct_atomic_load(&stop))
    ;
```

- 四种基类型：`atomic int` / `atomic long` / `atomic bool` / `atomic void *`；映射 C11 `_Atomic(T)`。
- 操作：`ct_atomic_load` / `ct_atomic_store` / `ct_atomic_cas`，全部 seq_cst；CAS 的 `expected`
  必须传地址。
- `atomic int *` 是“指向原子 int 的指针”，`atomic void *` 才是“原子空指针”。
- `atomic` 是上下文修饰：`int atomic = 1;` 仍是普通变量；`<stdatomic.h>` 的 `atomic_load/store`
  也仍是普通调用。
- 原子单元用 C11：`ct build` 自动用 `-std=c11`；`ct compile` 的生成 C 请自行 `-std=c11`。
- 完整样例：[examples/44_atomic_counter](../examples/44_atomic_counter)；并发夹具在
  `test/ast/p41_cancel_flag` / `p41_refcount`，TSan 见 `selfhost/check-tsan.sh`。

### 10.16 方法级 `pub`：默认私有（Phase 42）

`impl` 的固有方法默认私有，只有写 `pub` 才跨单元公开：

```ct
pub struct Counter { int n; }
impl Counter {
    pub int get() { return self.n; }
    int secret() { return self.n; }
}
```

同单元可以调用 `secret`；其它单元调用会报 `method is private to its unit`。私有方法不进 `.h`，
定义发 `static`。`pub` 只能写在 `.h.ct` 的 `pub struct` 固有 impl 上；trait impl 方法、块级
`pub impl` 都硬错。完整规则见 [language-spec §4.60](language-spec.md)。

### 10.17 `return err:` 的载荷类型（Phase 43）

`return err: expr;` 的载荷必须能赋给函数返回类型。返回 `Result<int, char *>` 时：

```ct
Result<int, char *> f(int n)
{
    if (n < 0) return err: (Result<int, char *>){ 0, 0, "bad" };
    return (Result<int, char *>){ 1, n, 0 };
}
```

写 `return err: 1;` 会报 `return: expected 'struct Result_int_char_p', got 'int'`，
`ct compile` 不会写出坏 C。`break err:` / `continue err:` 无载荷，不受影响。

### 10.18 用 `?` 传播错误（Phase 44）

```ct
Result<int, char *> parse(int n)
{
    if (n < 0) return err: (Result<int, char *>){ 0, 0, "negative" };
    return (Result<int, char *>){ 1, n * 2, 0 };
}

Result<long, char *> twice(int n)
{
    long v = parse(n)?;                    // 失败时直接返回外层 Result
    return (Result<long, char *>){ 1, v + 1, 0 };
}
```

`?` 只用于返回 `Result` 的函数；外层 `void` 时失败直接 `return;`。
`a ? b : c` 仍是三目；后缀 `?` 只在后面不能开始表达式时成立。

## 11. 命令行速查

| 命令 | 作用 |
| --- | --- |
| `ct <in.ct>` / `ct compile <in.ct>` | 单文件编译：普通 `.ct` 只写 `.c`，`.h.ct` 才额外写同名 `.h`；只接受**单文件单元**，`import` 需改用 `ct build`（`-I` 同理只对 build 生效） |
| `ct <in.ct> -o <out.c>` | 指定输出路径 |
| `ct check <in.ct>` | 只跑受限语义检查、不写 `.c`（仅单文件单元，`import` 不被接受）：调用点 arity / 实参类型 / trait 方法歧义 / impl 签名漂移（及既有 leak / 借用类发现）以 `error:` 报告，有任何发现退出 `1`，干净退出 `0` |
| `ct build <in.ct>… [-o <exe>]` | 多文件构建：默认把生成的 `.c` 放进 `.ctbuild/`，再调用 C 编译器产出可执行文件（`-o` 是文件名，默认 `a.out`） |
| `ct build --emit-c … -o <dir>` | 只发 C：每单元一份 `.c`/`.h`，`-o` 是输出目录，并打印建议的 `cc` 行；带增量缓存 |
| `ct build … --runtime-checks` | 在接口派发前检查空 vtable，空则带 `文件:行` abort；默认关闭，关闭时产物不变 |
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
语义类记录（调用点 arity / 实参类型 / trait 方法歧义 / impl 签名漂移）中，`ct build` 只把
**impl 签名漂移**当硬错（退出 `1`、不写 `.c`），其余仍是 `warning:`；`ct compile` 全部保持 warning；
`ct check` 把同一批记录升为 `error:` 并退出 `1`；
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
- `examples/**` —— 16 个可运行示例；`test/cases/**` —— 每个语法点的最小快照
- 编辑器支持：`editors/vscode/`（纯声明式高亮，零依赖）
- 方言：`examples/07_dialect/` 演示「注释里的 DSL → 纯 CT」，编译器对此零感知
- 包管理：`ct get` / `ct update` / `ct install` / `ct verify`，清单格式见 [design/phase8.md](history/design/phase8.md)，
  17.5 的增量（比较器范围、离线重解、显式索引、构建元数据）见 [design/phase17.md](history/design/phase17.md)

### 13.1 可选的类型检查：`ct check --types`

默认的 `ct check` 只做语法与既有语义检查；想让它顺手拦下明显的类型错，加 `--types`：

```sh
ct check --types app.ct
```

它只盯三处：声明初值与赋值（含 `into` 块里的 `.field = expr`）、`return`、以及
`Vec` / `Map` 和用户泛型的固有方法实参。

```ct
int x = "s";            // initializer: expected 'int', got 'char *'
x = "s";                // assignment: expected 'int', got 'char *'
int f() { return "s"; } // return: expected 'int', got 'char *'
int g() { return; }     // return: missing a value (function returns 'int')
Vec<int> v = {1};
v.push("s");            // argument 1: expected 'int', got 'char *'
```

判定是粗粒度的：两侧都是指针时不比较基类型与层数，算术类之间一律放行，裸 `0` 可填任何指针；
数组、闭包、函数指针、`void` 实际值等判不出的位置保持沉默。不带 `--types` 的 `ct check` 与
`ct build` / `ct compile` 的输出完全不变。
