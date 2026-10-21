# CT 入门教程

> 中文 · [English](#english)

> **适用版本**：v0.12.0，安装入口为 **ct-ast**。本教程只使用 `examples/**` 与 `test/**` 中已被门禁
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
ct -v            # ct v0.12.0        （安装入口，能力最全）
ctc -v           # ctc v0.12.0       （兼容别名，同一个二进制）
```

| 需求 | 做法 |
| --- | --- |
| 装到别处 | `install.sh --prefix "$HOME/bin"` |
| 装指定版本 | `install.sh --version v0.12.0`（默认装 `main`） |
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
ct hello.ct -o hello.c        # 生成 hello.c 与同名 hello.h
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
/* impl_dog.ct —— impl 与它建的 vtable 都是 static，只在本单元可见 */
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
mkdir -p build                      # 输出目录须预先存在
ct build -I . main.ct -o build      # 每单元产出 .c/.h，并打印建议的 cc 命令
cc build/*.c -o app && ./app        # woof 7
```

要点：

- **`pub` 才导出**。`pub` 的函数/struct/trait 写进 `.h`；`impl` 的方法与 vtable 永远 `static`。
- **跨单元只走指针 + vptr**：vtable 符号不出单元，「把对象传出去」比「把类型传出去」更省事。
- **`namespace a;` 是文件级声明**（分号式），块式 `namespace A { … }` 会被拒绝；目录也可以用
  `--ns-root <dir>` 映射成 namespace（`src/hal/uart.ct` → `hal`）。
- **跨命名空间调用必须带限定**：`a::one()`、`Point::size(p)`；裸调用只在同命名空间内合法。
- **`import` 支持别名**：`import app::model::Point as Point;`。

以上写法在 `test/modules/{split,ns_funcs,ns_qual,ns_dir}` 里是每日回归的一部分。

## 8. 内存：Drop、delete、own、泄漏告警

三种释放手段，按需要选（`test/modules/autodrop`、`test/modules/leak`）：

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

- **`delete p;`** 立刻释放：有 `Drop` 就先调 `drop()`，再 `free`。
- **`own T *p = malloc(...)`** 交所有权：作用域闭合 `}` 与函数帧顶层的 `return` 前自动释放，
  按声明逆序；重新赋值或把 `p` 当独立右值传出（`q = p;`）即视为所有权转移，不再兜底。
  约束：必须是带 `use Drop` 的**结构体指针**、必须由 `malloc`/`calloc` 初始化、`}` 与 `return`
  必须位于**行首**。
- **泄漏是告警不是错误**，格式固定：

```sh
$ ct leak.ct -o leak.c
leak.ct:9: warning: potential leak: 'leak' (Box*) allocated but never deleted

$ ct --diagnostics=json leak.ct -o leak.c    # 机器可读，写 stdout
```

逃逸判定是**保守**的（宁可漏放，不可错放）。要让它闭嘴就真的释放，不要指望它猜。

## 9. `map` 与 bindings：把 trait 绑到已有的 C 库

不想为了用 C 库而改库的代码，就用 `map` 把一个**已声明的全局实例**绑定成 trait 实现。
这是把假 HAL 接进 CT 的官方做法（[bindings/mock-hal/uart.ct](../bindings/mock-hal/uart.ct)）：

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

`map` 只在 **ct-ast** 支持，L0 与 L2 都不认识。

## 10. 命令行速查

| 命令 | 作用 |
| --- | --- |
| `ct <in.ct>` / `ct compile <in.ct>` | 单文件编译，产出同名 `.c`/`.h` |
| `ct <in.ct> -o <out.c>` | 指定输出路径 |
| `ct build <in.ct>… -o <dir>` | 多文件编译，每单元一份 `.c`/`.h`，带增量缓存 |
| `ct build … -I <dir>` | 追加导入搜索根（可重复） |
| `ct build … --ns-root <dir>` | 目录 = namespace 的校验树根 |
| `ct … --emit-map <file\|->` | 写出反向映射表 JSON（trait/struct/函数/impl/map → 生成的 C 符号） |
| `ct … --diagnostics=json\|text` | 告警格式（默认 `text` 写 stderr） |
| `ct … --line` / `--no-line` | 覆盖 `#line` 默认（`build` 默认开、`compile` 默认关） |
| `ct … --std=c99\|gnu99` | 写进建议的 `cc` 命令，产物暂无异 |
| `ct get <spec>[@<range>]` | 拉包到 `vendor/`，写 `ct.lock`（唯一会用系统 `git` 的子命令） |
| `ct install` | 离线校验 `ct.lock` 与 `vendor/`，打印建议的构建命令 |
| `ct -v` / `ct -h` | 版本 / 用法 |

退出码：成功 `0`，语法或 I/O 错误 `1`；错误格式 `文件:行:列: error: 描述`。

## 11. 会踩的坑

按「最常遇到」排序，全部有 [language-spec §6](language-spec.md) 的原文依据：

1. **顺序敏感**：编译器单趟顺序扫描，定义必须在使用之前；签名表里还没有的函数不会被特判。
2. **跨行的语句不重写**：`p.greet()` 跨行书写，或构造与语句写在同一行（`int main(){ … p.greet(); }`），
   都不会被改写。一行一句是硬要求。
3. **块注释只保护第一行**：`/* … */` 的续行会被当普通代码行处理，其中的 `self`、方法调用照常改写。
   多行注释里别写看似代码的东西。
4. **单行函数体不处理**：`int f() { return 1; }` 与函数头同处一行时，体内的派发不重写。
5. **ct-ast 只接受已实现的子集**：`switch` / `do-while` / `goto` 等普通 C 会在 `{` 处报
   `unexpected token`。要写这类代码，用 `ctc`（L0 种子）或 L2。
6. **块式 namespace 与跨命名空间裸调用**会被 ct-ast 拒绝；用分号式声明 + 限定调用。
7. **struct 类型的数组字段**等少数组合仍不支持——先查 [language-spec §4.8](language-spec.md)。
8. **上限是硬报错**：ct-ast 提高到 `MAX_TRAITS` 64、`MAX_STRUCTS` 128、`MAX_METHODS` 64、
   `MAX_FUNCS` 256、`MAX_VARS` 4096…，越界直接报错，绝不静默截断。[§7](language-spec.md) 有全表。

## 12. 下一步

- [language-spec.md](language-spec.md) —— 每一条展开规则的权威定义
- [polymorphism.md](polymorphism.md) —— 为什么用 vtable 而不是别的写法
- [architecture.md](architecture.md) —— 编译器内部怎么按行改写
- [roadmap.md](roadmap.md) —— 已落地与后续阶段
- `examples/**` —— 7 个可运行示例；`test/cases/**` —— 每个语法点的最小快照
- 编辑器支持：`editors/vscode/`（纯声明式高亮，零依赖）
- 方言：`examples/07_dialect/` 演示「注释里的 DSL → 纯 CT」，编译器对此零感知
- 包管理：`ct get` / `ct install`，清单格式见 [design/phase8.md](design/phase8.md)

---

## English

> **Scope**: v0.12.0, installed entry is **ct-ast**. Every snippet below is taken from `examples/**` or
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
ct -v            # ct v0.12.0     (the installed entry, full capability)
ctc -v           # ctc v0.12.0    (compatibility alias, same binary)
```

| Need | Command |
| --- | --- |
| install elsewhere | `install.sh --prefix "$HOME/bin"` |
| pin a version | `install.sh --version v0.12.0` (default: `main`) |
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
ct hello.ct -o hello.c        # writes hello.c and hello.h
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
/* impl_dog.ct — the impl and its vtable are static, private to this unit */
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
mkdir -p build                      # the output directory must exist
ct build -I . main.ct -o build      # one .c/.h per unit, plus a suggested cc command
cc build/*.c -o app && ./app        # woof 7
```

- **Only `pub` is exported**; `impl` methods and vtables stay `static`.
- **Cross-unit access goes through pointers and vptrs** — passing the object around is easier than
  exporting the type.
- **`namespace a;` is file-scoped** (semicolon form); block form is rejected. Directories can also become
  namespaces with `--ns-root <dir>` (`src/hal/uart.ct` → `hal`).
- **Cross-namespace calls must be qualified**: `a::one()`, `Point::size(p)`. Bare calls are legal only
  inside the same namespace.
- **`import` supports aliases**: `import app::model::Point as Point;`.

These shapes are exercised daily by `test/modules/{split,ns_funcs,ns_qual,ns_dir}`.

### 8. Memory: Drop, delete, own, leak warnings

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

- **`delete p;`** frees immediately: `drop()` first when the struct uses `Drop`, then `free`.
- **`own T *p = malloc(...)`** hands over ownership: released before the scope's closing `}` and at a
  top-level `return`, in reverse declaration order; reassigning `p` or passing it on as a bare rvalue
  (`q = p;`) transfers ownership and disables the safety net. The struct must `use Drop`, the pointer must
  come from `malloc`/`calloc`, and the `}` / `return` must start a line.
- **Leaks are warnings, not errors**:

```sh
$ ct leak.ct -o leak.c
leak.ct:9: warning: potential leak: 'leak' (Box*) allocated but never deleted

$ ct --diagnostics=json leak.ct -o leak.c    # machine readable, on stdout
```

Escape analysis is deliberately conservative: it would rather miss a release than double-free.

### 9. `map` and bindings: binding a trait to an existing C library

When you cannot change the library, `map` binds a **declared global instance** of it to a trait
([bindings/mock-hal/uart.ct](../bindings/mock-hal/uart.ct)):

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

`map` is ct-ast only — L0 and L2 do not accept it.

### 10. CLI cheat sheet

| Command | Purpose |
| --- | --- |
| `ct <in.ct>` / `ct compile <in.ct>` | single-file compile, writes `<in>.c`/`.h` |
| `ct <in.ct> -o <out.c>` | explicit output path |
| `ct build <in.ct>… -o <dir>` | multi-file compile, one `.c`/`.h` per unit, incremental cache |
| `ct build … -I <dir>` | extra import roots (repeatable) |
| `ct build … --ns-root <dir>` | directory = namespace verification root |
| `ct … --emit-map <file\|->` | reverse map JSON (trait/struct/function/impl/map → C symbols) |
| `ct … --diagnostics=json\|text` | warning format (`text` on stderr by default) |
| `ct … --line` / `--no-line` | override `#line` (on for `build`, off for `compile`) |
| `ct … --std=c99\|gnu99` | written into the suggested `cc` line; output is unchanged so far |
| `ct get <spec>[@<range>]` | fetch packages into `vendor/`, write `ct.lock` (the only subcommand using system `git`) |
| `ct install` | verify `ct.lock` against `vendor/` offline, print the suggested build command |
| `ct -v` / `ct -h` | version / usage |

Exit codes: `0` on success, `1` on syntax or I/O errors; errors read `file:line:col: error: message`.

### 11. Traps

Ordered by how often they bite; every one is grounded in [language-spec §6](language-spec.md):

1. **Order matters**: the compiler is a single forward pass, so definitions must precede uses.
2. **Multi-line statements are not rewritten**, nor is a construct sharing a line with a statement
   (`int main(){ … p.greet(); }`). One statement per line is a hard requirement.
3. **A block comment protects only its first line**: continuation lines are treated as ordinary code, and
   `self` / method calls in them are rewritten as usual.
4. **Single-line function bodies are not processed**: `int f() { return 1; }` on one line is left as is.
5. **ct-ast accepts only the implemented subset**: `switch` / `do-while` / `goto` report
   `unexpected token` at the `{`. Use `ctc` (the L0 seed) or L2 for those.
6. **Block namespaces and bare cross-namespace calls are rejected** by ct-ast; use the semicolon form and
   qualified calls.
7. A few combinations (for example struct-typed array fields) are still unsupported — check §4.8 first.
8. **Limits fail hard**: ct-ast raises them to `MAX_TRAITS` 64, `MAX_STRUCTS` 128, `MAX_METHODS` 64,
   `MAX_FUNCS` 256, `MAX_VARS` 4096…, and overflow is an error, never a silent truncation (§7).

### 12. Where to go next

- [language-spec.md](language-spec.md) — the authoritative expansion rules
- [polymorphism.md](polymorphism.md) — why vtables and not something else
- [architecture.md](architecture.md) — how the line-based rewriting works internally
- [roadmap.md](roadmap.md) — what has landed and what comes next
- `examples/**` — seven runnable demos; `test/cases/**` — a minimal snapshot per feature
- Editor support: `editors/vscode/` (declarative highlighting, zero dependencies)
- Dialects: `examples/07_dialect/` turns comment-embedded DSLs into plain CT; the compiler stays unaware
- Packages: `ct get` / `ct install`, manifest format in [design/phase8.md](design/phase8.md)
