# 给 C 程序员的 Ct 内存指引

> 中文
>
> **适用版本**：当前主线 **ct-ast**（版本号见 `ct -v`）。
>
> **核对基线：v0.88.3**（v0-PH-78 `ref`/`out`、v0-PH-79 切片、v0-PH-80 String/Str、
> v0-PH-81 `Box`/`new`、v0-PH-84 ADT/`match` 均已落地；SH-116 后 `Box<T>` 的单文件
> `ct build` 可用）。旧版本行为不同之处，以 [language-spec](language-spec.md) 为准。
>
> **读者假设**：熟悉 C 的 `malloc`/`free`、指针、数组衰减。不需要任何其他语言背景。
>
> **一句话总纲**：Ct 把你用纪律管的东西变成类型管的；指针从日常工具降级为逃生通道。
>
> **与 [memory-guide](memory-guide.md) 的关系**：本文讲 v0.88 的新句柄层
> （`String` / `Str` / `Box<T>` / `Vec<T>` / `Map<K,V>` / ADT）的心智模型；
> memory-guide 讲 `own` / `borrow` / `Drop` 的指针层（逃生层与旧模型）。
> 新代码优先按本文选型；落到逃生层时再看 memory-guide。

---

## 1. 心智地图：你的 C 习惯都去哪了

| 你在 C 里手写的东西 | Ct 里的对应物 | 你省掉了什么 |
| --- | --- | --- |
| `T *p = malloc(...)` + 全仓记「谁 free」 | `Box<T> p = new T { ... }` | `malloc`/`free` 配对、`sizeof`；**不省**引用环与未配对句柄的泄漏 |
| `char *s = strdup(...)` + `strlen` 满地跑 | `String s = "x";` | 长度计算、NUL 约定、深拷贝约定（代价是 retain/release） |
| `int *a, int n` 双参数传数组 | `int[] a` 切片 | 长度与指针失配、越界无防护 |
| `int f(..., int *out)` + 调用方猜是否写回 | `out int x` / `ref int x` | 意图靠注释、忘写未初始化 |
| `void (*cb)(void *env, ...)` + env 透传 | 闭包 `(…) => expr` | 声明噪音、env 打包 |
| `enum tag` + `union` + `switch` | `enum` 负载 + `match`（v0.84 已落地） | 手写 tag、漏分支、fallthrough |
| `q = p; free(p); q[0]=1`（别名悬垂） | 句柄协议挡住的范围见 §7 | ——（仍有的残余见 §7，诚实清单） |

**关键认知：以上每一行都不是「语法糖」那么简单——糖下面的所有权语义由编译器强制。**

## 2. 指针退场后的世界：三层结构

```
┌─ 日常层（默认，无指针）──────────────────────────┐
│  值：struct、int、数组 T a[N]                      │
│  借用视图：Str、切片 T[]（{ptr,len}，无 Drop）      │
│  拥有句柄：String、Box<T>、Vec<T>、Map（引用计数）  │
│  参数糖：ref / out                                  │
├─ 逃生层（合法，不鼓励）──────────────────────────┤
│  指针、own、malloc/free、defer/errdefer             │
│  适用：FFI 内部、MMIO、自定义分配器、未句柄化的资源  │
├─ 圈禁边界（v0-PH-65 strict）────────────────────────┤
│  禁的是：#include / #ct-raw / extern / 函数式宏     │
│  不是禁指针——指针在任何 .ct 里都合法                │
└──────────────────────────────────────────────────┘
```

逃生层的存在是刻意的：**Ct 不禁止指针，只提供更好的默认；但它确实禁止若干所有权形态**
（不可变 `String` 写入、`Str` 作 struct 字段、`Map<Str,V>` 等都会硬错）。
这和 `goto` 的最终形态一样——留在语言里，写在文档边缘，大部分人想不起来用。

另外要分清两种“标准能力”的加载方式：`lib/core` 的内置层（`Vec` / `Map` / `Option` /
`Result` / `String` / `Str` / `Box`）由编译器**自动预解析**；而挂在 `char *` 上的
`length()` / `to_int()` / `starts_with()` 等方法来自 **std 包的寄生映射**
（`map trait` 挂在 `char *` 上），必须 `import std::str::CharStr;` 才有
（std 0.20.0 起；0.19.0 及以前叫 `std::str::String`，旧名已删除）。
两者都是标准库能力，区别只在加载方式；不要因为内置层免 import 就以为 `char *` 也自带方法。

## 3. String / Str 专章：这是全篇最重要的一节

### 3.1 一个判据统治一切

> **「这份数据过了这行代码还要活着吗？」**
> 不要 → `Str`（借用，零成本）　要 → `String`（拥有，付引用计数）

### 3.2 本质区别（忘掉「堆 vs 栈」，记住「谁管释放」）

| | `String` | `Str` |
| --- | --- | --- |
| 角色 | 数据的主人 | 数据的访客（一张写着地址的纸条） |
| 数据住哪 | 字面量/空串是只读区 immortal；其余是自有堆块 | 来源决定：字面量区 / 某个 `String` 的堆 / 栈数组——哪都有 |
| 拷贝 | retain/release（有成本）；局部/参数/字段赋值自动，全局不自动 | 拷 `{ptr,len}` 两个字段（零成本） |
| 释放 | 引用计数归零自动 Drop（局部/参数）；**字段见下方分层，全局需显式 `release()`** | **不存在释放**——没有一寸自己的内存 |
| 存进字段/容器 | `String` 字段合法；释放见下方分层；容器元素合法 | struct 字段、`Map` 键是**硬错**；`Vec<Str>`、`Option<Str>`、ADT 负载**可编译**，但存的是借用视图 |
| 悬垂风险 | 单线程内 owning 不悬垂；跨线程共享 refcount 非原子，需自行同步 | 有（底层死了它瞎指）——**返回局部视图 / 临时接收者视图有 warning**（v0.88.2 起，见 §3.4、§7）；**非 immortal 视图存入容器 / ADT / 全局也有 warning**（v1.1，LANG-22） |

两点容易误解：

- **`String` 不是「数据永远在堆上」**：`String s = "x"` 绑定的是只读区里的 immortal 块，
  `release` 直接返回；字段赋值的 retain 与字段释放见下方分层。
- **`Str` 不是「所有容器都禁止」**：`Map<Str,V>` 的键是硬错，`Str` 也不能作 struct 字段；
  但 `Vec<Str>`、`Option<Str>`、ADT 负载都能编译。能编译不等于安全——容器里存的是视图，
  owner 必须先于容器死亡。

**字段释放分层（v0.88 实测）**：

- `String` / `Box<T>` 字段：宿主 struct `use Drop` 且**没有显式 `impl Drop`** → 编译器生成字段胶水
  （`String_Drop_drop` / `Box_*_Drop_drop`）；一旦写显式 `impl Drop`，胶水不再生成，作者自己释放。
- `Vec<T>` / `Map<K,V>` 值字段：同样在宿主 `use Drop` 且**没有显式 `impl Drop`** 时进入胶水，
  生成 `if (_self->f.h != 0) (void)<Inst>_release(&_self->f);`，元素按容器协议
  `__ct_elem_release` 级联（空句柄不 abort）；写显式 `impl Drop` 后仍由作者显式 `release()`。
- 全局：没有作用域出口，必须显式 `release()`。
- ADT payload：本轮不生成 Drop glue（v0-PH-84 简化项，v1.1 可能变）。
- 引用环：仍泄漏。

常量表是安全的例外：immortal 字面量（通常先绑定为 `Str` 局部，再放进 `Vec<Str>`）
不涉及任何 owner。只有非 immortal 来源（如 `v.push(local_string.as_str())`）才有悬垂风险；
v1.1 起这类来源在 `Vec` / `Option` / ADT 负载 / 全局报
`warning: storing a non-immortal 'Str' view; the owner must outlive the container`
（`ct check` 为 error），但不改变可编译性（LANG-22）。

### 3.3 从 C 代码迁移的三个典型场景

**场景一：字符串参数与解析（最高频）**

```c
/* C */
int parse_int(const char *s, int *out);
parse_int("42", &v);           /* strlen 内部现算；s 可能是悬垂的，没人查 */
```

```ct
/* CT：std 包把字符串方法寄生在 char * 上，先 import */
import std::str::CharStr;      /* std 0.20.0 起；0.19.0 及以前写 std::str::String */

int n = "42".to_int();         /* atoi 语义：跳过前导空白，遇到非数字停；无数字/空串返回 0 */
int m = "  -7".to_int();
```

`length()` / `find()` / `slice()` / `to_int()` 这些方法不是内置层自带的，而是 std 包的
寄生映射；`import std::str::CharStr;` 之后才可见
（0.19.0 及以前用 `std::str::String`；0.20.0 起只认 `CharStr`）。std 包由
`ct get std` 安装，`ct build` 从 `ct.lock` 取 include 根。

自己写 API 时，参数仍用 `Str`（零成本、长度自带）：

```ct
int parse_int(Str s, out int v);
int v = 0;                     /* trivial 也可不初始化；owning 必须先初始化 */
parse_int("42", v);
```

`out` 的 owning 实参（`String` / `Box<T>` / `Vec<T>` / `Map<K,V>`）必须先初始化：
`String s; take(s);` 会硬错（`out owning argument must be initialized`）。

**场景二：返回值（你最容易踩的地方）**

```c
/* C：strdup 的责任在文档里 */
char *get_name(void);   /* 调用方 free？不 free？看注释 */
```

```ct
/* CT：函数内造的数据要出去 → String（连所有权一起送走） */
String get_name(void) { return g_cache.name.to_string(); }

/* Str 返回值只有一个安全来源：底层来自函数体外（参数/接收者/长寿命句柄） */
Str trim(Str s)
{
    if (s.len < 2) return s;        /* len 是字节数，先挡掉短串 */
    return s.slice(1, s.len - 2);   /* slice(start, n)：n 是长度，不是 end */
}
```

注意 `slice` 的第二个参数是**长度**。先绑 `Str s = "abc";`，再 `s.slice(1, 2)` 得到 `"bc"`；
要同时去掉首尾各一字节，应写 `slice(1, len - 2)`。`len` 是字节数，非 ASCII 文本请用码点 API。

`String` 的复制是显式的：`String s = "x";` 直接绑定 immortal 块；
要一份独立副本用 `String copy = s.to_string();`；`Str v = "x"; String own = v.to_string();`
同样得到独立副本。注意 `to_string()` 是内建 `String` / `Str` 的方法；std 包的 `char *`
方法层（0.19.0 的映射 trait 叫 `CStrOps`，0.20.0 起单元与 trait 都叫 `CharStr`）没有给 `char *`
提供 `to_string`，所以 `"x".to_string()` 仍然是错的——先写
`String s = "x";` 或 `Str v = "x";` 再转换。

**场景三：存起来**

```ct
struct Config {
    String name;    /* 合法：字段必须 owning */
    /* Str name;    // 硬错：借用类型不能作字段 */
}
```

字段 `String` 合法；`Config` 没有 `use Drop`，离开作用域不会释放 `name`，
需要显式 `c.name.release()`，或由明确的协议/析构路径处理。

如果 `Config` 声明 `use Drop` 且**不写显式 `impl Drop`**，编译器会生成 `String` 字段胶水；
一旦写显式 `impl Drop`，胶水不再生成，字段释放由作者负责。`Vec` / `Map` 值字段也在同一条件下
进入胶水（容器级联到元素）；写了显式 impl 或宿主没有 `use Drop` 时仍需显式 `release()`
（见 §3.2 的字段释放分层）。

### 3.4 生命周期纪律（Str 的全部要求就这三条）

1. **先绑 owner，再取视图**：

   ```ct
   Person p = load(id);          /* owner 先落进明确变量 */
   Str n = p.name.as_str();      /* 再取视图 */
   use(n);                        /* 用完；p 和 n 一起出作用域，天然安全 */
   ```

2. **视图用完前，owner 别死**——`make_person().name.as_str()` 这种「从临时量取视图」
   与返回局部 `String` 的视图从 v0.88.2 起有编译期 **warning**
   （`borrowed 'Str' view escapes`；`ct check` 下按既有 strict 规则是 error）。
   编译器只拦这两种直接形态；经函数转手的形态仍靠这条纪律。

3. **owner 死了视图就是废纸**——经函数转手的形态编译器看不到，归契约 + ASan 兜底。

## 4. ADT 与 match（v0.84 新增）：C 的 tagged union，但所有权要自己收尾

C 里你手写：

```c
struct Shape {
    enum { CIRCLE, RECT, EMPTY } tag;
    union { struct { int r; } circle; struct { int w, h; } rect; } u;
};
```

Ct 把它变成名义和类型 + 穷尽匹配：

```ct
enum Shape {
    Circle(int r),
    Rect(int w, int h),
    Empty(),
}

int area(Shape s)
{
    match (s) {
        Shape.Circle(r) => { return 3 * r * r; }
        Shape.Rect(w, h) => { return w * h; }
        Shape.Empty() => { return 0; }
    }
}
```

- **两形态**：`enum` 的任一成员带括号负载 = ADT；所有成员都不带负载时仍是普通 C `enum`。
  两种形态不能混用。
- **值类型**：ADT 在内存里就是 `{ int tag; union { … } u; }`，没有 vtable、没有隐藏分配。
  它不拥有堆对象——除非你把 owning 句柄放进负载。
- **`match` 是语句，也可以是表达式**：语句分支必须覆盖全部变体，或最后写一个 `_`；分支体要
  花括号，没有 fallthrough。表达式形式写 `Pattern => expr` 或块内 `yield expr;`（LANG-29 S4 / B5）。
- **绑定是副本**：`Shape.Circle(r)` 里的 `r` 是该臂块内的普通局部量，改它不影响被 match 的值。
- **计数**：ADT / 变体 / 负载字段都从初始值倍增到形式上限 `CAP_LIMIT`=65536（旧的固定语义上限已退役）；
  无泛型 ADT、无 or/守卫/嵌套/结构体模式。

**重要的一条：ADT 的 owning payload 有 retain/release。** 负载里如果是 `String` /
`Box<T>` / `Vec<T>`，编译器在构造、拷贝、按值实参和 `match` 绑定时 retain，作用域出口
release 一次；显式 `release()` 后再离开作用域也是安全的（句柄已清零，二次 release 是 no-op）：

```ct
enum Msg { Text(String body), Ping() }

void handle(Msg m)
{
    match (m) {
        Msg.Text(body) => { body.release(); }   /* 只释放一次 */
        Msg.Ping() => { }
    }
}
```

- 构造 `Msg.Text(x)` **不会 retain** `x`；`match` 绑定 `body` 是浅拷贝；
  `body.release()` 释放后，原 `x` 就悬垂了。
- 因此把 ADT 当 **move 语义**用：payload 只释放一次，释放后原句柄不再使用；
  把 `handle` 这类函数当作“消费”函数，调用后不要再碰原来的 `Msg`。
- 如果负载是字面量 `String`（immortal），`release` 是 no-op，最省心。

## 5. 优化指南：性能从哪里省出来

按收益排序的优化决策清单：

**① 参数类型用 Str / 切片，不要用 String / 指针（零成本，立即做）**

```ct
/* 反例：为不需要的所有权付费 */
int count_vowels(String s);        /* 每次调用：堆数据 + retain + release */
/* 正例 */
int count_vowels(Str s);           /* 零分配零计数；字面量/String/切片都能传 */
```

C 经验对照：这比 C 的 `const char *` 还省——长度 O(1)，比较不用 `strlen`。

**② 函数内造的数据要出去，用 String 而不是「Str + 全局/静态」**

C 程序员的老习惯「返回静态 buffer 避免分配」在 Ct 里是**反模式**：静态 buffer 是共享可变状态
（线程、重入全是坑）。`String` 的引用计数只付一次拷贝的税；**单线程内**只读共享没有副作用，
但跨线程共享句柄时 refcount 非原子，仍需自行同步。

**③ 批量数据用切片传参，别传指针+长度**

`sum(int[] a)` 替代 `sum(int *a, int n)`：长度和指针焊在一起，编译器自动补 `len`，
子切片 `a[2..]` 零拷贝。这是 C 数组衰减坑的直接解法。

**④ 字符串拼接用 `str_concat`，不要找 `String.concat` 或 `std::arena`**

```ct
String joined = str_concat(a.as_str(), b.as_str());   /* 新 owning String */
```

编译器内置层 `lib/core`（原 `lib/std`）没有 `String.concat`（只有 `U16String.concat`），也没有 `Arena`；
外部 `ct/std` 包（不是内置层）提供 `std::arena::Arena`，需先 `ct get ct/std`，再 `import std::arena::Arena`。
热点路径需要批量分配时，用项目内分配器或落到逃生层，不要写成“标准库自带”。

**⑤ 容器按形态选**

| 需求 | 选择 | 不要选 |
| --- | --- | --- |
| 动态长度、跨函数持有 | `Vec<T>` | 定长数组硬撑 |
| 键值查找 | `Map<K,V>`（字符串键用 `Map<String,V>`） | 手写哈希表；`Map<Str,V>` 会硬错 |
| 单对象堆分配 | `Box<T>` | `own T*` + `malloc`（除非你有明确的转移语义需求） |

`Box<T>` 的句柄在 LP64 上是 16 字节（两个机器字），payload 前有 8 字节 `{refs, aux}` 头；
`b.f` 自动解引用到 payload，`b.at()` 返回借用 `T *`（`release()` 后失效）。

**⑥ 什么时候才回逃生层拿指针**

只有一个判据：**FFI 边界或硬件。** shim 里接 C 库、MMIO 寄存器、自定义分配器——这些是 C 的地盘，
指针永远合法。应用代码里冒出指针，先问自己是不是该用切片/`Str`/`Box`。

## 6. 各特性与指针的关系速查

| 特性 | 与指针的关系 |
| --- | --- |
| `Box<T>` / `new` | 消灭「指向堆单对象的指针」；句柄内部当然有指针，但被协议包住 |
| `String` | 同上；字面量/空串是 immortal 只读块，其余是自有堆块；`.data` 是 `const char *`，不保证 NUL 结尾 |
| `Str` / `T[]` | 内部含指针；`Str` 不可作 struct 字段 / `Map` 键；`T[]` 的位置白名单更窄（字段/全局/容器/`Box` 等一律硬错）。两者都只能作局部 / 参数 / 返回值等借用位置，逐位置见 §6.2 |
| `ref` / `out` | 发射成指针，源码无指针；**没有生命周期保证**——可被存储或传给更长寿命位置，靠契约 + 直接 lint |
| 闭包 | 捕获按值；fn 指针 + env 是发射细节 |
| trait 接口值 | 胖指针 `{self, vt}`，装箱/派发全自动 |
| `own` / `defer` / `errdefer` | 指针时代的手动资源管理三件套，句柄代码里基本用不上 |
| 原生指针 `T*` | 逃生层：FFI、MMIO、算法热点；合法、不鼓励、圈禁在边界 |

### 6.1 迁移适用面：三档，不是「不能用」

前提不变：公开头文件、ABI 与既有 `char *` 字段都不动。新特性按“能不能出现在 C 消费者看得见的
导出面”分三档：

| 档 | 可用位置 | 最小形态 | 规范锚点 |
| --- | --- | --- | --- |
| 直接用 | Ct 内部实现、C 边界参数与写法糖 | `pub int f(ref int x, out int n)` 发射 `int f(int *x, int *n)`；方法级 `pub` 决定是否进 `.h` | [§4.68](language-spec.md#468-ref--out-参数phase-78仅-ct-ast)、[§4.57](language-spec.md#457-c-abi-静态库ct-build---libphase-39仅-ct-ast) |
| 仅内部用 | `String` / `Vec` / `Map` / `Option` / `Result` / `Box<T>` / ADT 只活在 `ct-ast` 单元内 | 内部字段、容器元素、局部变量都可以；不要写进公开 `.h.ct` 的 `pub` 签名或 C 可见 struct 字段 | [§4.70](language-spec.md#470-string--strutf-8-owning-与借用phase-80仅-ct-ast)、[§4.71](language-spec.md#471-box--new单对象句柄phase-81仅-ct-ast)、[§4.73](language-spec.md#473-最小-adt-与-matchphase-84仅-ct-ast) |
| 边界必须转 C 形态 | 对外函数 / 结构体的交接处 | `String` → `cstr()`；切片 → `(const T *, size_t)`；句柄 → `T *` 或 opaque `struct`；ADT → 显式 `tag` + union / 访问函数 | [§4.57](language-spec.md#457-c-abi-静态库ct-build---libphase-39仅-ct-ast)、[§4.69](language-spec.md#469-切片-tphase-79仅-ct-ast)、[§4.73](language-spec.md#473-最小-adt-与-matchphase-84仅-ct-ast) |

**「非 C ABI」的准确含义**：这些类型**不能进入对 C 消费者承诺的导出面**（`ct build --lib`
的 `.abi.h`、`pub` 签名、公开 struct 字段），不是“在 Ct 里不能用”。`ct-ast` 自身就用
`String` / `Vec` / `Map` 写内部实现；把“仅内部用”读成“禁用”是过度收缩。真正的硬边界是
位置：`T[]` 不得进字段 / 全局 / 容器元素 / `Box` / `Option` / `Result` / ADT 负载 / 泛型实参；
`Str` 的 struct 字段与 `Map` 键也硬错（其余借用位置见 §6.2）。

**「全绿」的口径**：`test/run.sh` 的 `165 passed, 0 failed` 是 **compile 模式**；`ct build` 是
另一条路径。[SH-116](../issues/selfhost/sh116-build-mode-box-unit.md) 已修复 `Box<T>` 的 build
模式内置单元发射，`examples/50…53` 与 `docs/snippets/README/*.ct` 由 `check-warnings.sh` 的
build 段实际构建/运行。引用“全绿”时注明模式，不要把 compile 全绿当成 build 全绿。

### 6.2 位置禁止表：`Str` 与 `T[]` 只做借用视图

| 位置 | `Str` | `T[]` | 依据 |
| --- | --- | --- | --- |
| 函数参数 / 返回值 / 局部变量 | 允许 | 允许 | §4.70 / §4.69 |
| struct 字段 | 硬错 | 硬错 | §4.70 / §4.69 |
| 全局 / `static` | 可编译，但只是视图（owner 必须先活） | 硬错 | §7.1 / §4.69 |
| 容器元素（`Vec` / `Map`） | `Vec<Str>` 可编译（存视图）；`Map<Str,V>` 键硬错 | 硬错 | §7.1 / §4.69 |
| `Box<T>` | 硬错（`Box<Str>`） | 硬错 | §4.71 / §4.69 |
| `Option` / `Result` / ADT 负载 / 泛型实参 | 可编译但存视图；非 immortal 来源 v1.1 起 warning | 硬错 | §7.1、LANG-22 / §4.69 |
| `?` 与 C 边界 | 只能 `cstr()` 显式退出；`.data` 直传硬错 | 只能 `(const T *, size_t)` 或 shim | §4.70 / §4.69 |

逐类透传路径（返回局部、临时接收者、跨函数转手、交给 C 边界）见 [§7.1](#71-借用视图透传矩阵)，
本表不重复其矩阵。

## 7. 残余风险诚实清单（Ct 不拦的东西）

Ct 的护栏水位是「比 C 严格得多，比 Rust 松」。以下残余**存在、有契约条款、有运行时兜底，
但编译器不拦**：

| 残余 | 后果 | 防线 |
| --- | --- | --- |
| 引用环（A 持 B、B 持 A） | 静默泄漏，无告警 | 文档契约「环=作者责任」；直接环有 lint；`--debug-leaks` **当前未实现**，将来也只报未配对计数 |
| `Str` 视图活到 owner 死后（返回局部视图、临时接收者、经函数转手） | 悬垂读，UB | 前两种直接形态有 **warning**（v0.88.2 起，`borrowed 'Str' view escapes`；`ct check` 升 error，见 [SH-106](../issues/selfhost/sh106-str-view-escape-no-lint.md)）；经函数转手仍靠契约 + ASan；`T[]` 切片有 `slice escape` warning |
| 句柄跨线程共享 | 数据竞争（refcount 非原子） | 契约「句柄非 atomic」+ TSan（nightly/Linux 独立门禁）；需要时用 atomic 自己同步 |
| ADT 的 owning payload（`String` / `Box` / `Vec` / 嵌套 ADT） | 构造/拷贝/绑定漏 retain 会悬垂或双释放 | 编译器生成 `T_retain`/`T_release` 浅共享；作用域出口释放一次（LANG-29 S2 / B3）；裸 `Str` payload 硬错 |
| `String` / `Box<T>` / `Vec<T>` / `Map<K,V>` 字段（宿主无 `use Drop`，或写了显式 `impl Drop`） | 泄漏 | 宿主 `use Drop` 且无显式 impl → 字段胶水（容器级联到元素）；否则显式 `release()` |
| `Vec<T>` / `Map<K,V>` 全局位置、容器指针/数组字段 | 无作用域出口或无单一句柄 → 泄漏 | 显式 `release()` 或由协议/析构路径处理 |
| 逃生层 own 指针的一切经典错误 | 泄漏/悬垂/double free | 泄漏告警（保守、不保证）；ASan |

### 7.1 借用视图透传矩阵

`Str` / `U16Str` / `T[]` 是借用视图；下表列出**每一条透传路径**上 Ct 是 warning、硬错还是不分析，
避免把“没有告警”误读成“安全”。探针与契约同源，新增形态必须在这里加一行。

| 透传路径 | Ct 行为 | 依据 / 探针 |
| --- | --- | --- |
| 返回局部 owner 的 `Str` 视图 | warning（`ct check` 升 error） | `test/ast/p106_str_escape.sh` |
| 临时接收者取视图后返回 / 存储 | warning（同一 lint） | `test/ast/p106_str_escape.sh` |
| 局部 `Str` 绑定再返回 | warning（同一 lint 传播） | `test/ast/p106_str_escape.sh` |
| 作为函数参数借用 | 允许（不改所有权） | `test/ast/p106_str_escape.sh` 正例 |
| 存入普通字段 / 全局 | 硬错（借用视图不能进非视图位置） | `test/ast/p79_places.sh` |
| `Vec<Str>` / `Option<Str>` / ADT 负载 | 允许存视图；`LANG-22` 规划 warn | `test/ast/p81_box/neg_*`、`LANG-22` |
| `Map` 键 | 硬错（键需 immortal） | `test/ast/241_map_str_key` |
| 跨函数转手（参数进、另一个函数返回） | 不分析；契约 + ASan | 本节 §7、`SH-106` |
| 交给 C 边界 | 只有 `cstr()` 显式退出；`.data` 直传是硬错 | `test/ast/p80_cstr` |

**记住这份清单不是缺陷披露，是价格标签**——这些就是「不做 GC、不做借用检查器」省下来的
复杂度所付的尾款。每一项都比 C 里的对应风险多一层防线，但没有一项是零成本。

## 8. 口诀（打印贴在显示器边上）

```
数据过这行还要活吗？  要 → String / Box / Vec
                       不要 → Str / 切片
函数内造的 → String 出去；路过别人的 → Str 递出去
先绑 owner，再取视图；视图用完前，owner 别死
指针主要留在 shim 和寄存器；应用层先想 Str / 切片 / Box
ADT 的 payload 自己收尾：只释放一次，释放后别再碰原句柄
互相持有会泄漏——就记住这一条
```

## 9. 一页纸总结

**C 程序员迁移 Ct 的心智只需要三步：**

1. **释放责任上交**：`malloc`/`free`、`strlen`、深拷贝约定 → 句柄协议自动执行
   （局部/参数自动；字段、全局、ADT 负载仍需你收尾）。
2. **所有权写进类型**：「谁拥有」不再是注释和 review 话题，而是 `String` vs `Str`、
   字段白名单、`Map` 键限制、lint——编译器在边界把门。
3. **优化有据可依**：§5 的清单按收益排序，每项都能说出「省了什么、付了什么」。

你不再需要「时刻保持警惕」——那是 C 的工作方式。Ct 的工作方式是：**默认值就是安全的，
想更快要懂规则，想最懂可以一直下到指针层。** 选择在哪一档，是你的自由；每一档都有护栏，
这是承诺——但护栏的位置以本文和 [language-spec](language-spec.md) 为准，不要假设编译器
替你做了它没做的事。

## 10. C 互操作：shim 契约与语义矩阵

写 shim（`<base>.shim.h` / `<base>.shim.c`）或接裸机时，先读
[C Shim 契约](c-shim-contract.md)：文件与命名、所有权、错误码、ISR/任务上下文、ABI，
以及 DMA 的「提交即转移、完成即归还」五条硬条款。它给的是**作者义务**，不是新的语言特性。

判断“这条 C 写法在 Ct 里到底走哪条路”，查
[C Interop Semantics Matrix](c-interop-semantics-matrix.md)：每行四列，逐项给
Ct 行为、边界（透传 · strict 禁区 · shim）与权威节 + 证据。矩阵是本文附录，只索引
[language-spec](language-spec.md)，不另立规范。

一句话记法：**应用代码里没有 `#include` / `extern` / 函数式宏的位置；这些只出现在
`.m.ct`、shim 与 `#ct-raw`。**
