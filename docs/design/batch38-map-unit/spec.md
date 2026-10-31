# 第三十八批：`.m.ct` 零成本静态映射（设计）

> 状态：**已实现（第三十八批，v0.15.0）**。落地在 `selfhost/ct-ast/**` 与 `selfhost/check-ast.sh`，
> 现状描述见 `docs/language-spec.md` §4.10「静态映射」。本文件保留为设计记录；与实现一致的部分
> 已按实测更新（示例目录 `libc/libc.m.ct`、生成 C 的括号形态、负例落点）。
> 锚点：`v0.14.0`（第三十六批收口）+ 第三十七批处置。
> 前置阅读：[language-spec §4.10](../../language-spec.md)、[ns-host-map/spec.md](../ns-host-map/spec.md)、
> [batch30-header-rule](../batch30-header-rule/spec.md)、[batch36-trait-default](../batch36-trait-default/spec.md)。
> 取舍已由用户在会话中确认，见 §12「已定的取舍」。

## 1. 问题与目标

现有 `map`（对象宿主 / 命名空间宿主）一律生成

```
struct <T>_vtbl → struct <T>_iface → 每条绑定一个 static <宿主>_<Trait>_<m>(void *self, …) → 调用点 iface.vt->m(...)
```

实测（`-O0` / `-O2`，aarch64 与 x86-64）：

| 形态 | 结果 |
| --- | --- |
| 命名空间宿主 vtable 是**非 const 全局** | `-O2` 也无法去虚化，调用点仍是 `blr` / `call *` |
| 同单元把 vtable 改 `const` | `-O2` 可以完全折叠 |
| 跨单元（消费者只看到 `extern`） | 即使 vtable 是 `const`，仍保留间接调用 |

结论：只要跨单元使用，`const` 也救不了；必须让**调用点直接成为普通 C 调用**。

目标：

- 为 C 库（libc、zlib、socket、epoll…）提供**编译期**映射：生成物就是手写 C，**没有
  wrapper 函数、没有 `_iface` / `_vtbl` / vtable 变量、没有 `void *self`**。
- 跨单元同样零成本：映射信息在编译期展开进消费者自己的 `.c`。
- 源侧保留 OO 写法：`aString.toInt()`、`libc::Env.get("HOME")`。

非目标见 §11。

## 2. 术语

| 术语 | 含义 |
| --- | --- |
| 映射单元 | 后缀 `.m.ct` 的源文件；只承载 `#include` / `#define` / `import` / `trait` / `map` / `_Static_assert` |
| 静态 trait | 声明在映射单元里的 trait；**没有** `_iface` / `_vtbl`，不可装箱，只能静态调用 |
| 命名空间静态调用 | `A::B::T.method(args)` |
| 类型宿主（type host） | `map trait T for type char * { … }`；第一个绑定参数是接收者 |
| 类型静态调用 | `value.method(args)`，接收者类型命中某个类型宿主映射 |
| recipe | `->` 右侧的 C 调用模板，如 `memset(s, value, count)` |
| prologue | 映射单元里的 `#include` / `#define` 行；展开进消费者 `.c` 的顶部 |

## 3. 文件类型 `.m.ct`

### 3.1 识别

- `foo.m.ct` → 单元基名 `foo`、`Unit.is_map = 1`、`Unit.is_hdr = 0`。
- `base_name`（[Module.h.ct](../../../selfhost/ct-ast/frontend/module/Module.h.ct)）增加出参
  `int *is_map`；`.h.ct` / `.m.ct` / `.ct` 三种后缀按后缀长度判断，顺序必须是 `.h.ct` → `.m.ct` → `.ct`。
- `Unit` 增加 `int is_map;`（[Unit.h.ct](../../../selfhost/ct-ast/frontend/module/Unit.h.ct)）。

### 3.2 产物：零

- `ct build` **不发射** `.c`、**不写** `.h`、**不进** 缓存 artifact、**不进** 末尾 `cc …` 命令的源文件列表。
- `ct compile` 拒绝 `.m.ct` 输入：`a .m.ct unit produces no output; import it from a .ct unit`
  （在 `driver.run` 里按输入后缀判定，早于 `read_file`）。
  **理由**：`ct compile` 是单文件模式，**不解析 import**（[driver.h.ct:144](../../../selfhost/ct-ast/tool/driver/driver.h.ct)
  的注释即 `compile mode resolves no imports`），没有单元表也就没有 map 闭包；因此 `.m.ct`
  **只能**经 `ct build` 使用。
- 同一个单元树里同名 `.h.ct` 与 `.m.ct` 同时存在 → 歧义，见 §3.3。

### 3.3 导入与歧义

- 映射单元可被任意单元 `import`（普通 `.ct`、`.h.ct` 都可以）。
- 映射单元**只能** `import` 其它映射单元；`import` 一个 `.h.ct` 报
  `a .m.ct unit can only import another .m.ct unit`。
- `resolve_import` 的两轮搜索改为**同一 root 内先看两种后缀**：

  1. 对每个 root（先是 import 方所在目录，再是 `-I` 顺序）：
     - `foo.h.ct` 存在且 `foo.m.ct` 存在 → 报
       `import '<rel>' is ambiguous: both <root>/<rel>.h.ct and <root>/<rel>.m.ct exist`
     - 只有 `.h.ct` → 选中，`*is_hdr = 1`
     - 只有 `.m.ct` → 选中，`*is_map = 1`
  2. 都没有时，再对每个 root 找 `foo.ct`，命中即报既有的
     `only a .h.ct unit can be imported: rename …`（消息保留，不因本批改名）。

  规则：**同一 root 内**歧义才报错；不同 root 之间按搜索顺序取先命中者（与现状一致）。

- 映射单元与普通单元一样参与 `check_ns_dir`（目录 = `namespace`，或 `--ns-root` 例外）。

### 3.4 构建与缓存

- `cache_order` 不变（依赖优先）；`cache_key_of` 的 import 文本对 header 依赖写
  `%s.h;`、对 map 依赖写 `%s.m;`，两者都照旧折叠依赖 `digest`。
- `build_main` 的 dirty / 发射循环：map 单元**照常**算 key、照常折叠 digest，但

  - 不调用 `emit_unit(u)`；
  - 不调用 `write_unit_header(u)`；
  - 不调用 `cache->hit` / `cache->store`；
  - 不参与末尾 `cc` 打印。

  实现方式：`dirty[u] = 0` 且 `if (units[u].is_map) continue;`（两处循环都要加），
  key 计算保持在循环里，保证消费者的 key 能折叠到 map 单元的 digest。

- `load_unit` 对 map 依赖**不**写 `#include "<dep>.h"` 到消费者的 `.c`/`.h`：
  消费侧只展开 prologue（§6.5），不会存在 `libc.h`。

### 3.5 内容白名单

映射单元只允许：

| 允许 | 说明 |
| --- | --- |
| `namespace X;` | 文件级写法；目录 = namespace 校验照旧 |
| `#include` / `#define` | prologue；文本进入消费者 `.c` 顶部 |
| `import` | 只允许映射单元 |
| `pub trait T { …; }` | 只能抽象方法（禁止默认体），且必须 `pub` |
| `map trait T for namespace A::B { … }` | 静态命名空间宿主 |
| `map trait T for type <C 类型> { … }` | 静态类型宿主 |
| `_Static_assert(...)` | 透传 |

其余一律报错（逐条消息见 §7）。特别地：函数定义/原型、全局变量（含 `extern`）、
`struct` / `union` / `enum` / `typedef`、`impl`、对象宿主 `for instance` 全部禁止。
类型全部来自 `#include` 的 C 头；CT 侧不做 C 头解析，也不镜像 C 声明。

## 4. 静态 trait

- 判定：**声明该 trait 的单元是 `.m.ct`** → 静态 trait。不引入新的 `static trait` 关键字。
- `Trait` 增加 `int is_static;`（[Symbols.h.ct](../../../selfhost/ct-ast/frontend/sym/Symbols.h.ct)），
  `parse_trait` 按 `self->unit_is_map` 置位。
- 静态 trait：

  - **不发射** `<T>_iface`、`<T>_vtbl`、任何 vtable 变量；
  - 不能 `impl`（`a static trait cannot be implemented`）；
  - 不能出现在 struct 的 `use` 列表（`a static trait cannot be adopted`）；
  - 不能作为类型使用（局部/参数/返回值/字段/typedef）：`a static trait has no interface value`；
  - 不能装箱（`Env e = Env::libc;`）：`a static trait has no interface value; call '<host>::<Trait>.<method>()'`；
  - 必须 `pub`（`a trait in a .m.ct unit must be 'pub'`）；
  - 不能带默认方法体（`a .m.ct trait cannot carry a default body`）。

## 5. 语法

### 5.1 命名空间静态调用

```
<host>::<Trait>.<method>(<args>)
```

例：`libc::Env.get("HOME")`。

- 静态 trait 必须声明在**宿主命名空间内**：trait 的直接命名空间 == map 的宿主路径，
  否则报 `a static trait for a namespace host must be declared in that namespace`。
- 因此宿主路径非空：根命名空间里的静态 trait 只能用于类型宿主。
- `T::host`（如 `Text::libc`）对静态 trait 仍然非法，报既有装箱拒绝并附提示。
- `A::B::f(...)` 这类纯限定调用不受影响：只有「`::` 链的最后一段是**静态 trait**，且其后紧跟
  `.method(`」才进入静态调用。

### 5.2 类型宿主

```
map trait <T> for type <ctype> {
    <m>(recv, p1, …, pn) -> <recipe>;
}
```

- `<ctype>` 是 C 类型拼写（`char *`、`const char *`、`FILE *`、`struct stat *`…）。
  `char[]` 不是合法值类型，统一写 `char *`；接收者匹配时**数组到指针 decay**。
- 第一个绑定参数 `recv` 是接收者；trait 方法本身**不声明**接收者。
- 绑定参数个数 = trait 方法参数个数 + 1，否则报错。
- 接收者匹配：
  1. 先算调用点接收者表达式的静态类型（`TypeCheck::expr_type`）；
  2. 若接收者是数组变量（`Symbols.vars[i].is_array`），类型取 `<元素类型> *`（decay）；
  3. 与 `<ctype>` 做**规范化文本比较**（压掉多余空格；`const` 保留；不做隐式转换）。
  - `char *` 与 `char *` 一致；`char[3]` → `char *` 后可命中；`String` 与 `char *` **不**互相匹配。

- 解析优先级：普通 struct / 接口方法优先；只有既有的 `method_trait` 查找失败时，才走类型宿主
  fallback（§6.2）。两个及以上候选（不同 `.m.ct` 为同一类型、同一方法名提供映射）→
  歧义报错（§7）。
- 类型宿主只允许出现在 `.m.ct`，且必然是静态映射。

### 5.3 绑定形式

- `map ... for namespace`：绑定参数个数 = 方法参数个数。
- `map ... for type`：绑定参数个数 = 方法参数个数 + 1（首个是接收者）。
- recipe 必须是**一次顶层调用**：`callee(arg, …, arg)`；callee 可以是任意标识符（C 头里的函数
  编译器看不到，不做声明校验）。
- 静态映射**不生成** `wrapper` / `vtable` / `prefix`；`Map.prefix`、`Map.vtable` 保持空串，
  相关发射路径整体跳过。

## 6. 语义与生成物

### 6.1 命名空间静态调用

`libc::Env.get("HOME")` → `getenv("HOME")`。

recipe 的每个绑定参数在调用点一一替换为对应实参（§6.3 的替换规则）；**没有接收者**，
不生成 `self`，不取地址，不加任何中间符号。

### 6.2 类型静态调用

`a.toInt()`（`a` 是 `char[3]`，映射 `toInt(s) -> atoi(s)`）→ `atoi(a)`。

`b.fill('z', 3)` → `memset(b, 'z', 3)`。

绑定参数到实参的对应：`recv` ↔ 接收者表达式，`p1..pn` ↔ 调用实参。

### 6.3 recipe 替换规则（逐出现点）

扫描 recipe 文本，按 token 边界识别绑定参数的出现点，**按上下文**生成 C：

| recipe 中的写法 | 生成的 C | 说明 |
| --- | --- | --- |
| `p`（值位） | `(<actual>)` | 一次求值 |
| `&p`（`&` 后紧跟参数，且后面不是 `[`） | `&(<TP>){<actual>}` | C99 compound literal；求值一次、地址有效 |
| `&p[… ]` | `&((<actual>)[…])` | 括号按 `[`/`]` 配对补全 |
| `sizeof p` | `sizeof(<TP>)` | 不求值；若该参数无其它求值出现，按「未使用」处理 |
| `p.field` | `((<actual>).field)` | |
| `p->field` | `((<actual>)->field)` | |
| `p[i]` | `((<actual>)[i])` | |
| 参数在 recipe 中**完全没有求值出现** | 整体前缀 `(void)(<actual>), ` | 保持实参副作用；多个按绑定参数顺序依次前缀 |
| `p++` / `p--` / `++p` / `--p` / `p = …` / `p += …` | 编译期报错 | 见 §7 |

其中 `<TP>` = 该绑定参数的声明类型：

- 命名空间宿主：`MethodSig.ptype[i]`；
- 类型宿主的接收者：`Map.host_type`；
- 类型宿主的其它参数：`MethodSig.ptype[i-1]`。

求值/重复规则：

- 一个参数在 recipe 中**最多一次求值出现**。出现两次及以上时，实参必须是「可重复」表达式：
  `N_VAR` / `N_NUM` / `N_STR` / 以它们为根的 `N_MEMBER` / `N_ARROW` / `N_INDEX` 链 / `N_ADDR`
  （即字面量、简单变量、稳定成员链）。出现函数调用、赋值、自增自减、复合字面量等**有副作用**
  的实参 → 报错，要求用户先提局部变量。
- `sizeof p` 不计入求值次数，但为了让实参副作用仍然发生，会触发上面的 `(void)(…)` 前缀。
- 求值顺序不做额外保证（与手写 C 一致）。

### 6.4 调用点生成物示例

```ct
/* libc/libc.m.ct（目录 = namespace，故消费者写 import libc::libc;） */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

namespace libc;

pub trait CStr {
    int   toInt();
    int   length();
    int   compare(char *other);
    void  fill(int value, int count);
    int   scanInto(int *out);
}

map trait CStr for type char * {
    toInt(s)              -> atoi(s);
    length(s)             -> strlen(s);
    compare(s, other)     -> strcmp(s, other);
    fill(s, value, count) -> memset(s, value, count);
    scanInto(s, out)      -> sscanf(s, "%d", out);
}

pub trait Env {
    char *get(char *name);
}

map trait Env for namespace libc {
    get(name) -> getenv(name);
}
```

```ct
/* main.ct */
import libc::libc;
#include <stdio.h>
#include <string.h>

int main(void)
{
    char a[] = "42";
    char b[16];
    int scanned = 0;

    int n = a.toInt();                  /* atoi(a) */
    int l = a.length();                 /* strlen(a) */
    int c = a.compare("42");            /* strcmp(a, "42") */
    int r = a.scanInto(&scanned);       /* sscanf(a, "%d", &scanned) */

    strcpy(b, "abc");
    b.fill('z', 3);                     /* memset(b, 'z', 3) */

    char *home = libc::Env.get("HOME"); /* getenv("HOME") */

    printf("%d %d %d %d %s %s\n", n, l, c, r, b,
           home ? "env-ok" : "env-none");
    return 0;
}
```

生成 C（`main.c`；banner 之后是 prologue，然后才是本单元自己的 `#include`）：

```c
/* Generated by ct v0.15.0 from main.ct -- do not edit; change the .ct and re-run ct. */
/* Generated output is not covered by the GPL … */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <string.h>

int main(void)
{
    char a[] = "42";
    char b[16];
    int scanned = 0;

    int n = atoi((a));
    int l = strlen((a));
    int c = strcmp((a), ("42"));
    int r = sscanf((a), "%d", ((&scanned)));

    strcpy(b, "abc");
    memset((b), ('z'), (3));

    char *home = getenv(("HOME"));

    printf("%d %d %d %d %s %s\n", n, l, c, r, b,
           home ? "env-ok" : "env-none");
    return 0;
}
```

注：prologue 去重按**整行文本**；`main.ct` 自己的 `#include` 与 prologue 重复时不合并（C 头都有
include guard，重复包含无害）。`atoi/strlen/strcmp/sscanf/getenv` 的声明来自 prologue，
消费者不写这些 `#include` 也能编译。每个实参在替换后都带一层括号（`atoi((a))`、
`getenv(("HOME"))`），`&p` 的 compound literal 形态见 §6.3。

### 6.5 prologue 展开

- 消费者的 `.c` 顶部（两条 banner 注释之后、本单元 `#include "<base>.h"` 与依赖头之前）依序输出
  **map 闭包**（直接与传递 `import` 到的所有映射单元）里的 `N_PP` 行；按 `N_PP` 原文逐行输出，
  按整行文本去重（先出现者先赢）。输出顺序 = map 依赖的加载顺序（依赖优先的确定顺序）。
- 消费者 `.h` **不**展开 prologue：静态 trait 不产生类型，C 头类型不需要在头里可见。
- **只发生在 `ct build`**：prologue 由 `emit_unit(u)` 展开；`ct compile` 是单文件模式、不解析
  import，既没有 map 闭包，也不接受 `.m.ct` 输入（§3.2），因此 `emit_program` **不**参与 prologue。
- 规则：prologue 必须自包含（只引用标准头或它自己 `#include` 的头的宏/类型）。文档写明。

实现落点：

- `Module` 提供 `int map_prologue_lines(int u, const char **lines, int cap)`：从 `u` 出发对 `depu`
  做 DFS，收集 `units[d].is_map` 单元的 `N_PP` 文本，去重后返回行数与指针表；`Module` 持有行缓冲区。
- `Emit` 已经持有 `units` / `nunits` 指针，可以在 `emit_unit(u)` 里直接调用该模块方法（`Emit`
  不 import `Module` 会形成环——改用 `Emit` 自带的 walker，输入是 `units` 与 `u`，不依赖
  `Module` 的方法）。**最终选择：walker 放 `Emit`**（`emit_map_prologues(int u)`），避免环依赖。
- 编译模式（`ct <file> -o <file>.c`）**不**需要也不允许这条路径：单文件模式不解析 import，
  没有单元表与 map 闭包；`.m.ct` 只能经 `ct build` 使用（§3.2、§6.5）。

### 6.6 `--emit-map` JSON

`maps[]` 每条增加：

| 字段 | 值 |
| --- | --- |
| `"static": true` | 静态映射 |
| `"host": "namespace" \| "type"` | 宿主形态 |
| `"type": "<ctype>"` | 仅 `host == "type"` |
| bindings 的 `"wrapper": false` | 静态映射恒为 `false` |
| bindings 的 `"inline": true` | 静态映射恒为 `true` |
| bindings 的 `"symbol"` | recipe 的 callee（如 `atoi`） |

动态 map 的现有字段与取值**不变**。

## 7. 诊断

格式沿用 `file:line:col: error: <小写消息>`；消息不加句号、标识符用单引号。

| 场景 | 消息 | 位置 |
| --- | --- | --- |
| `ct compile` 输入 `.m.ct` | `a .m.ct unit produces no output; import it from a .ct unit` | 无位置（`ctc:` 前缀） |
| 同 root 下 `.h.ct` 与 `.m.ct` 并存 | `import '<rel>' is ambiguous: both <a> and <b> exist` | import 行 |
| 映射单元 import 非映射单元 | `a .m.ct unit can only import another .m.ct unit` | import 行 |
| 映射单元里的函数 | `a .m.ct unit cannot define a function` | 声明行 |
| 映射单元里的函数原型 | `a .m.ct unit cannot declare a function` | 声明行 |
| 映射单元里的全局 | `a .m.ct unit cannot declare a global variable` | 声明行 |
| 映射单元里的 `struct`/`union`/`enum`/`typedef` | `a .m.ct unit cannot declare a type` | 声明行 |
| 映射单元里的 `impl` | `a .m.ct unit cannot contain an impl` | `impl` 行 |
| 映射单元里的对象宿主 | `a .m.ct unit cannot bind a trait to an instance` | map 行 |
| 映射单元里的非法 `#` 行 | `a .m.ct unit allows only #include and #define in its prologue` | 该行 |
| 非 `pub` 的映射单元 trait | `a trait in a .m.ct unit must be 'pub'` | trait 行 |
| 映射单元 trait 带默认体 | `a .m.ct trait cannot carry a default body` | 方法行 |
| `impl` 一个静态 trait | `a static trait cannot be implemented` | impl 行 |
| struct `use` 一个静态 trait | `a static trait cannot be adopted` | use 行 |
| 静态 trait 作类型 | `a static trait has no interface value` | 类型引用行 |
| 静态 trait 装箱（`T::host`） | `a static trait has no interface value; call '<host>::<Trait>.<method>()'` | 装箱行 |
| 命名空间静态 trait 不在宿主命名空间 | `a static trait for a namespace host must be declared in that namespace` | map 行 |
| `for type` 后没有类型 | `expected a type after 'for type'` | map 行 |
| 类型宿主绑定参数个数不符 | `a type host binding has <n> parameters but method '<m>' takes <k>`（`<n>` 是绑定参数个数（含接收者），`<k>` 是方法自身参数个数） | 绑定行 |
| 无 map 命中类型宿主调用 | `no method '<m>' for type '<type>'` | 调用行 |
| 类型宿主多个候选 | `ambiguous type-host map for method '<m>' on type '<type>': '<a>' and '<b>'` | 调用行 |
| recipe 改名了非绑定参数的小写标识符 | `map recipe names '<id>' but it is not a binding parameter` | 绑定行 |
| recipe 修改绑定参数 | `map recipe modifies binding parameter '<p>'` | 绑定行 |
| recipe 多次求值且实参不稳定 | `map recipe uses '<p>' more than once; bind the argument to a local first` | 调用行 |
| recipe 不是一次顶层调用 | `a map recipe must be a single call` | 绑定行 |

既有诊断 `cannot resolve the method trait (unknown receiver type)` 只在**未走类型宿主 fallback**
时保留；走 fallback 且无命中时用上表的 `no method '<m>' for type '<type>'`。

## 8. 实现清单（精确到文件与函数）

### 8.1 `frontend/module/Unit.h.ct`

- `struct Unit` 增加 `int is_map;`（放在 `is_hdr` 旁）。

### 8.2 `frontend/module/Map.h.ct`

- `struct Map` 增加：

  ```ct
  int  is_static;        /* 声明在 .m.ct 里 */
  int  type_host;        /* 1 = for type */
  char host_type[160];   /* type_host 的接收者类型拼写 */
  ```

- `struct MapBind` 增加：

  ```ct
  int  recv;             /* 首个绑定参数是接收者（type host） */
  int  uses[16];         /* 每个绑定参数在 recipe 里的求值出现次数 */
  int  sizeofs[16];      /* 每个绑定参数在 sizeof 里的出现次数 */
  ```

  其余字段保留；静态映射的 `wrapper` 留空，`direct` 恒 0。

### 8.3 `frontend/sym/Symbols.h.ct`

- `struct Trait` 增加 `int is_static;`。

### 8.4 `frontend/parse/Parser.h.ct`

- `struct Parser` 增加 `int unit_is_map;`（由 `Module::load_unit` / `driver.run` 设置，进单元前重置）。
- `parse_trait`：`is_pub` 必须为 1（`unit_is_map` 时），否则 `a trait in a .m.ct unit must be 'pub'`；
  设置 `Trait.is_static = unit_is_map`；若方法有默认体（`body >= 0`）报
  `a .m.ct trait cannot carry a default body`。
- `top_decl`：`unit_is_map` 时按 §3.5 白名单放行；命中禁止项按 §7 报错。放行分支：
  `namespace`、`import`、`trait`、`map`、`_Static_assert`；`#` 行由 `parse_program` 的
  N_PP 分支校验文本前缀。
- `parse_impl` 入口：目标 trait `is_static` → `a static trait cannot be implemented`。
- struct 的 `use` 记录处（`add_use` 或等价位置）：目标 trait `is_static` → `a static trait cannot be adopted`。
- `parse_type` 把名字解析成 trait 时，若 `is_static` → `a static trait has no interface value`。

### 8.5 `frontend/parse/MapBuild.h.ct`

- `parse` 的宿主分支改为三选一：`instance` | `namespace` | `type`。
  - `namespace` 分支：既有逻辑 + `m->is_static = self->unit_is_map`；若静态，校验 trait 的直接
    命名空间 == 宿主路径（§5.1）。
  - `type` 分支：读一个类型（复用 `parse_type` 的拼写能力或等价扫描，直到 `{`）；置
    `m->type_host = 1`、`m->host_type`；若 `self->unit_is_map == 0` 报
    `a type host is only allowed in a .m.ct unit`；`a type host needs at least one binding parameter`。
  - 静态映射不计算 `prefix` / `vtable`（留空），不生成 `wrapper`。
- 绑定循环：
  - 静态时 arity 校验按 §5.3（type host +1）。
  - `type_host` 第 0 个绑定参数 `recv = 1`。
  - recipe 校验换成 `check_static_call`（静态映射）与既有 `check_call`（动态映射）。
- 新增 `check_static_call(const char *call, const struct Map *m, struct MapBind *b)`：
  - 结构：必须是一次顶层调用（callee + 一对平衡括号）；否则 `a map recipe must be a single call`。
  - 逐 token 扫描：字符串/字符字面量整段跳过；绑定参数名的出现点按 §6.3 分类并累计
    `uses[i]` / `sizeofs[i]`；检测修改（`++`/`--`/`=`/`+=` 等）→ 立即报
    `map recipe modifies binding parameter '<p>'`。
  - 允许的非参数标识符：后面紧跟 `(` 的 callee；`sizeof`；C 类型关键字
    （`int char short long unsigned signed float double void const struct union enum size_t _Bool`）；
    紧跟类型关键字之后的标识符；ALL_CAPS；`.` / `->` 后的成员名。其余 → `map recipe names '<id>' but it is not a binding parameter`。
  - 动态映射**保持**既有 `check_call` 严格度（不放松）。
- `rewrite_globals`：静态映射不做全局名改写（`.m.ct` 没有 CT 全局）。

### 8.6 `frontend/parse/Expr.h.ct`

- `parse_qual_path`（[Expr.h.ct:1702](../../../selfhost/ct-ast/frontend/parse/Expr.h.ct) 一带）增加 `*form = 3`：
  - `nseg >= 2`，最后一段 `seg[nseg-1]` 解析为 **静态 trait**，且其命名空间 == `seg[0..nseg-2]`
    → `*form = 3`，出参给 trait C 名与宿主路径；
  - 若 `nseg == 1` 且该 ID 是静态 trait（根命名空间）→ 同样 `*form = 3` 但宿主路径为空，
    由调用点报 §5.1 的命名空间错误。
  - 既有的 `*form = 2`（动态 namespace 宿主装箱）分支遇到静态 trait 时改为报
    `a static trait has no interface value; call '<host>::<Trait>.<method>()'`。
- `parse_primary` 收到 `form == 3`：
  - 期望下一个 token 是 `.`；否则报 `a static trait has no interface value`；
  - 读方法名 + `(`，构造 `N_MCALL`：`a = -1`（无接收者）、`b` = 实参链、`aux = 5`、
    `text` = trait C 名、`text2` = 方法名、`text3` = 宿主路径（`::` 连接）。
- `parse_postfix` 的 `.` / `->` 方法分支（[Expr.h.ct:1150](../../../selfhost/ct-ast/frontend/parse/Expr.h.ct) 一带）：
  - 既有 `expr_type` + `method_trait` 失败、且接收者静态类型已知时，置 `aux = 6`、
    `text2` = 方法名、`text` 留空（由发射期按类型宿主解析）；
  - 其余情况保持既有 aux 1/2/3/4 与既有诊断。

### 8.7 `frontend/type/TypeCheck.h.ct`

- `expr_type` 增加：

  ```ct
  if (kind == N_MCALL) {
      /* aux 5/6 走静态映射；返回类型来自 trait 方法 */
  }
  ```

  - `aux == 6`：用接收者类型（含 decay）查可见的类型宿主 → 命中返回 `MethodSig.ret`；
  - `aux == 5`：按 `text` 查静态 trait + 方法 → 返回 `ret`；
  - 查不到返回 -1（发射期再报详细诊断）。
- `maybe_box`：期望 trait 是静态 → `a static trait has no interface value`（正常路径不应到达；
  防御性检查）。
- 数组 decay 的辅助函数放这里（`expr_type` 已有 `N_VAR` 的 `is_array` 特判可复用）。

### 8.8 `frontend/module/Module.h.ct`

- `base_name` 增出参 `int *is_map`；三种后缀（§3.1）。
- `resolve_import` 增出参 `int *is_map`，按 §3.3 搜索；`load_unit` 设置
  `units[u].is_map`、`p->unit_is_map`。
- `load_unit` 的依赖循环：`units[d].is_map` 时 **不** 写 `dep[]`（避免生成 `#include "libc.h"`），
  但仍要 `depu[]`（缓存/闭包需要）——或保留 `dep[]` 并在 `emit_unit` / `write_unit_header`
  输出依赖头时跳过 map 依赖。**选择后者**（`dep[]` 保留原名，两处输出加
  `if (units[depu[i]].is_map) continue;`），改动最小且缓存文本自然得到 `%s.m;` 需要的信息。
  实现细节：`cache_key_of` 按 `units[depu[k]].is_map ? "%s.m;" : "%s.h;"` 拼。
- `cache_key_of` 按上述拼 key；`build_main` 两处循环按 §3.4 跳过 map 单元的发射/头/缓存
  store，并拒绝把 `.m.ct` 作为命令行输入（`load_unit` 之前按后缀判定，报
  `a .m.ct unit produces no output; import it from a .ct unit`）。

### 8.9 `backend/emit/Emit.h.ct`

- `emit_unit(u)`：banner 之后、`#include "<base>.h"` 之前调用 `emit_map_prologues(u)`；
  依赖头循环跳过 `is_map` 依赖。
- `emit_program(prog)`：**不改**（编译模式不解析 import，没有 map 闭包，`emit_unit` 是唯一展开点）。
- 新增 `int emit_map_prologues(int u)`：对 `u` 的 `depu` 闭包 DFS，收集 `is_map` 单元的 N_PP，
  按整行文本去重后逐行输出（每条后接 `\n`）。
- `emit_maps(u)`：`m->is_static` 的条目整体跳过（不发射 wrapper、不发射 vtable）。
- `emit_link_externs` / `map_vtable_exported`：静态映射跳过。
- `emit_expr` 的 `N_MCALL` 分支（[Emit.h.ct:1945](../../../selfhost/ct-ast/backend/emit/Emit.h.ct)）在既有
  `aux` 分派前加两支：

  ```ct
  if (aux == 5) → emit_static_ns_call(n)
  else if (aux == 6) → emit_type_host_call(n)
  ```

  两支都先解析出 `Map*` + `MapBind*`，再走 `emit_recipe(m, b, recv_node, argchain)`。
- 新增 `int emit_recipe(struct Map *m, struct MapBind *b, int recv, int args)`：
  - 第一遍：从 `b->uses[]` / `b->sizeofs[]` 决定未使用参数前缀；
  - 第二遍：扫描 `b->call` 文本并按 §6.3 输出；遇到参数出现点时 `emit_expr(actual)` 直接写 `out`
    （**不**把实参渲染成字符串，避免引入 `open_memstream`）；
  - `&p` 用 `&(<TP>){` + `emit_expr(actual)` + `}`；
  - 多次求值时按 §6.3 校验实参「可重复」，否则报
    `map recipe uses '<p>' more than once; bind the argument to a local first`；
  - 所有错误用 `fail_from(n, …)` 定位调用行。
- 新增 `int emit_static_ns_call(int n)` / `int emit_type_host_call(int n)`：
  - `aux == 5`：`text` = trait C 名、`text3` = 宿主路径 → 找
    `(trait == text && host == text3 && is_static)` 的 map；无则
    `no map binds trait '<T>' to namespace '<path>'`（沿用 SH-20 消息形状）；
  - `aux == 6`：接收者静态类型 + decay → 在**可见**的静态类型宿主里找
    `(host_type == rt && bind.method == text2)`；无 → `no method '<m>' for type '<type>'`；
    多个 → `ambiguous type-host map for method '<m>' on type '<type>': '<a>' and '<b>'`；
  - 「可见」= map 的 `unit` 在消费者单元的 `depu` 传递闭包内（与绑定/静态调用的可见性一致）。
- `write_map`：静态映射输出 §6.6 字段；`symbol` 取 recipe 顶层 callee（解析不出时留空）。

### 8.10 `tool/driver/driver.h.ct`

- `run` 在解析参数后按输入后缀判定：`.m.ct` →
  `ctc: a .m.ct unit produces no output; import it from a .ct unit`，退出码 1。
- 置 `m->p->unit_is_map = 0`（compile 模式主单元永远是普通单元）。
- `default_output` 对 `.m.ct` 不做特殊处理（路径已被拒绝）。

### 8.11 容量与方法预算

- 不抬高任何**语言级** `MAX_*`（`MAX_MAPS` / `MAX_TRAITS` / `MAX_METHOD` / `MAX_UNITS` 等）。
- 例外：节点池容量。`runtime/arena/Arena.h.ct` 的 `nodes[65536]` 是编译器自身源码的
  编译容量，不是语言上限。本批把 `ct-ast` 自编实测推到 **69199 节点**（超 65536 约 5.6%），
  `check-ast.sh` 的 self-compile 关卡因此失败；按既有「引导容量」先例，节点池抬到
  **131072**（字符串池 256 KiB 实测仅用 34 KB，不动）。产物与诊断无任何变化。
- 若 `ParseOps` / `EmitOps` 已达 `MAX_METHOD`，把 recipe 扫描/替换抽到独立单元
  `frontend/map/Inline.h.ct`（`namespace frontend::map`，`trait InlineOps`），由 `MapBuild` 与
  `Emit` `import`。**不得**为省方法位把逻辑塞进已满的 trait，也**不得**抬高 `MAX_METHOD`。
- `Map` 结构变大（`MapBind` + 2×16×int）在 `MAX_MAPS = 64` 下约 +16 KB BSS，可接受。

## 9. 测试计划

新增正例（全部走 `ct build`，因为 `.m.ct` 只能被 import）：

1. `test/modules/map_unit/`：`libc/libc.m.ct`（§6.4）+ `main.ct` + `expected.out`。
   - 断言产物目录**没有** `libc.c` / `libc.h`；
   - `main.c` 含 `atoi((a))`、`memset((b), ('z'), (3))`、`getenv(("HOME"))`；
   - `main.c` **不含** `_iface`、`_vtbl`、`vtable`、`vt->`、`(void *)0`；
   - `main.c` 顶部含 prologue 的 `#include <stdlib.h>`；
   - `cc -Wall -Wextra -std=c99` 零告警，运行输出与 `expected.out` 一致；
   - `ct build` 末尾 `cc` 行**不含** `libc.c`。
2. `test/modules/map_unit_type/`：类型宿主 + 数组 decay（`char a[]` → `char *`）+ 指针参数
   （`scanInto(&x)`）+ `&p` 的 compound literal（`strtol((a), &(char *){0}, 10)`）+ 未使用参数前缀
   （`((void)(a), strlen(""));`）。
3. `test/modules/map_unit_cross/`：A 的 `.m.ct` 被 B `.h.ct` 与 C `.ct` 共同 import，
   两个消费者都零成本（无 wrapper 符号），且 `--emit-map` JSON 的 `"static": true` /
   `"host":"type"` / `"type":"char *"` / `"inline": true` 字段正确。

负例（**实测落点：`selfhost/check-ast.sh` 的 `mapbad` 帮助函数**，共 25 条；`ct compile`
与 import 布局类用独立探针目录）：

4. `ct compile foo.m.ct` → §7 消息。
5. `.m.ct` 里写函数定义 / 原型 / 全局 / struct / impl / 对象宿主 → 各自消息。
6. 非 `pub` trait、带默认体的 trait → 各自消息。
7. `impl` 静态 trait、`use` 静态 trait、静态 trait 作类型、`T::host` 装箱 → 各自消息。
8. 同 root 下 `.h.ct` + `.m.ct` 歧义、`.m.ct` import 普通单元 → 各自消息。
9. recipe 修改参数 / 多次求值 + 不稳定实参 / 非单次调用 / 改名非绑定参数 → 各自消息。
10. 类型宿主 arity 不符、无命中、歧义 → §7 消息。
11. `char[]` 作 `for type` → `expected a type after 'for type'`。

关卡（[check-ast.sh](../../../selfhost/check-ast.sh)）：

- 新增上述模块断言块：零产物、内联文本、零 wrapper、`cc` 行、运行输出、JSON 字段。
- 新增负例的**精确消息**断言（25 条）。
- `check-warnings.sh` 按既有枚举方式补入新模块。
- 自编不动点与全量语料等价必须仍绿。

回归底线：

- 既有动态 `map`（`test/ast/26_ns_host`、`test/modules/ns_host`、`test/modules/map_ns`、
  `test/ast/14/15/22`）产物**逐字节不变**。
- 本批按用户授权 bump 到 v0.15.0，故 `test/cases/**` 与 `test/modules/**` 既有 golden
  **只有版本 token 变化**；动态 `map` 的语义内容不变。

## 10. 分片（每片独立可编译、可过关卡）

| 片 | 内容 | 出口 |
| --- | --- | --- |
| S0 | `.m.ct` 文件类型 + `is_map` + 静态 trait + 白名单 + 零产物 + 导入/缓存/cc 行 | `ct build` 能加载 `.m.ct`，不产 `libc.c/h`；既有 golden 不动 |
| S1 | `A::B::T.m(...)` 解析 + 发射裸调用（recipe 仅「参数顺序原位替换 + 直接 callee」） | `libc::Env.get("HOME")` → `getenv("HOME")`；模块正例 1 的一部分 |
| S2 | recipe 调用点替换（compound literal / `sizeof` / 未使用前缀 / 重复与修改诊断）+ prologue 展开 | 正例 1、2 全绿；负例 9 |
| S3 | 类型宿主 `for type` + `value.m()` fallback + 数组 decay + 歧义/无命中诊断 | 正例 2、3；负例 10、11 |
| S4 | 文档 + `--emit-map` 字段 + `check-ast.sh` / `check-warnings.sh` 收口 | 九关全绿 |

依赖顺序：S0 → S1 → S2 → S3 → S4。S1 可以先用「参数原位替换」的最小实现，
S2 再把替换规则补全（两者都改 `emit_recipe`）。

## 11. 非目标

- 不解析 C 头、不在 `.m.ct` 里镜像 C `struct` / `enum` / `typedef` / 全局变量。
- 不映射宏形式的 API（`FD_SET`、`assert`、`container_of` 里的语句宏）——需要 C shim。
- 不处理回调（无 userdata 的 `qsort` / `signal`；有 userdata 的 `pthread_create` 由用户写 thunk）。
- 不处理所有权 / RAII（`fopen/fclose`、`sqlite3_open/close`）——属于 `.h.ct` 的真实类型。
- 不做隐式类型转换；`char *` 与 `String` 不互相匹配。
- 不支持 C++。
- 不改变任何既有动态 `map` 的行为、产物、命名与 JSON 形状。
- 用户已授权本批 bump：`CTC_VERSION` 五处同步到 **v0.15.0**（冻结层只动这一行）；既有
  `test/cases/**` 与 `test/modules/**` golden 仅版本 token 变化。

## 12. 已定的取舍

| 问题 | 结论 |
| --- | --- |
| 零成本怎么做 | 无产物 `.m.ct` + 调用点直接替换；不生成 provider 头、不生成 consumer helper |
| `.h.ct` / `.m.ct` 同名 | 同一 root 下报歧义 |
| `.m.ct` 内容 | 强制 mapping-only（`#include`/`#define`/`import`/`trait`/`map`/`_Static_assert`） |
| 静态调用写法 | `host::Trait.method(...)`；`Trait::host` 只留给动态命名空间宿主的装箱 |
| 类型宿主写法 | `for type <ctype>`，首个绑定参数是接收者；`char[]` 统一写 `char *`，匹配时 decay |
| `&p` 的展开 | C99 compound literal `&(T){actual}` |
| 重复参数 + 有副作用实参 | 报错，要求先提局部变量 |
| 复杂 recipe | 不做 helper，全部在调用点展开 |
| `.m.ct` 里的类型 | v1 只允许 C 头里的类型；CT 侧真实类型留在 `.h.ct` |
| `const` vtable | 与本批无关：静态映射没有 vtable |

## 13. 附录：C 库全量映射的边界（分层结论）

「把所有 C 库都 map 到 CT」不可行，也不该作为目标。正确目标是
**可映射子集零成本；不可映射处显式报错，让用户写 C shim 或 `.h.ct` 包装**，
禁止编译器静默生成 wrapper。

| 层 | 承载 | 成本 |
| --- | --- | --- |
| `.m.ct` 静态映射 | 单次调用型函数式 / 句柄式 API、命名空间函数、C 类型上的方法 | 零 wrapper、零中间符号 |
| C shim 头 | 无 userdata 的回调、语句宏、全局量（`errno`/`stdin`）、结构体字段访问、变参转发 | 用户手写，一处适配 |
| `.h.ct` 真实类型 | 状态机、所有权 / RAII、错误翻译、结果类型、动态派发 | 有对象与封装，非零成本但可控 |
| 不支持 | C++ ABI、需要完整预处理器/解析器的 API、位域/按值大结构体的 ABI 细节 | 明确拒绝 |

固有障碍（按 API 形状）：

- **回调**：无 userdata（`qsort`、`signal`、`atexit`）需要 trampoline + 全局状态；有 userdata
  （`pthread_create`、`sqlite3_exec`）由用户写 thunk + context，编译器不生成 wrapper。
- **结构体字段 / 构造**（`struct stat`、`sockaddr_in`、`epoll_event`）：`.m.ct` 没有 C 结构体镜像，
  需要 C helper 或 `.h.ct` 镜像。
- **语句宏 / 非单调用宏**：只能在 C shim 或内联函数里包装。
- **全局变量 / 属性**（`errno`、`optind`、`stdin`）：v1 不进 recipe；用 C 访问器或 shim。
- **所有权**（`fopen/fclose`、`sqlite3_open/close`）：属于 `.h.ct` 的 `own` / `Drop`。
- **错误翻译 / 结果类型**（`errno` → Result）：`.h.ct`。
- **变参 / 格式串**（`printf` 家族）：`.m.ct` 只能承载「固定实参的转发」；`va_list` 型 API 走 shim。
- **结构体按值 / 位域 / `packed`**：ABI 细节不在 `.m.ct` 的能力内。
- **链接参数 / 平台条件**（`-lz`、`-lpthread`、`#ifdef`）：`.m.ct` 只展开 `#include`/`#define`；
  `-l` 属于 `ct.pkg` 的 `ldflags`（后续批次，不在本批）。
- **同名方法歧义**：多个 `.m.ct` 为同一类型/同一方法提供映射时报歧义（§7），需要 trait 命名空间
  区分或换方法名。
- **C++**：不支持。
