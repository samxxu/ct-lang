# lib/core — 内置容器层（随编译器发行）

> 曾用名 `lib/std`（DOC-87 Stage 1，2026-11-22 迁移；旧路径与 `CT_STD_DIR` 只在一个 MINOR
> 兼容窗内解析，命中时打印弃用警告）。

> 中文。范围与判据见 [phase29.md](../../docs/history/design/phase29.md) §2.7、[language-spec §4.51](../../docs/language-spec.md)。

## 这是什么

`lib/core/` **只承载内置 `Vec` / `Map`（含 `MapEntry`）、`Option` / `Result` 与 `String` / `Str`
（含 UTF-16 对）及其直接依赖**，不是整个 `std` 的新家。
`io` / `math` 等其余模块仍由 ct-pkg 包 `std` 提供，本目录不复制、不镜像；`Str` 的
`char *` 映射层 `std::str::CharStr` 仍在 ct-pkg `std`（Phase 36 的 S0 实测该包没有
`std/string` / `CStr`，故按 `docs/history/design/phase36.md` §14/§15 把 `Str` 值类型放回内建层）。

内置层由**八个单元**组成（SH-120 起）：`Vec.h.ct`（容器，含 `Map` / `MapEntry`）、
`Option.h.ct`（Phase 34）、`Result.h.ct`（Phase 34）、`Str.h.ct`（借用视图 `Str`）、
`String.h.ct`（owning 句柄 `String` + 辅助记录 `ct_str_hdr`）、
`utf16/U16Str.h.ct`（借用视图 `U16Str`）、`utf16/U16String.h.ct`（owning 句柄 `U16String`）、
`Box.h.ct`（Phase 81：`Box<T>` 单对象 owning 句柄 + `new` / `of`）。
八个单元都是**编译模式**与 **`ct build`** 两条路径都会自动预解析的单元：`ct file.ct -o file.c`
把它们 splice 到用户程序之前，`ct build` 则把它们作为独立单元参与发射；两种形态都
**不需要 import**、不需要 `ct get`。编译模式的产物仍是单个 C TU；源级命名空间是
`core`（U16 对是 `core::utf16`），兼容窗内 C 符号保持根拼写（见下节）。

单元依赖是单向的（无环）：`Str` / `U16Str` 是叶子（不 import、不返回 owning 类型）；
`String → Str`；`U16String → String / Str / U16Str`。`Str.to_string` / `str_dup` /
`str_dup_len` / `str_concat` 随 `String` 放在 `String.h.ct`；`U16Str.to_string` /
`U16Str.to_utf8` 与跨编码的 `String.from_utf16` / `String.to_utf16` 放在
`utf16/U16String.h.ct`。编译器按 `Vec, Option, Result, Str, String, U16Str, U16String,
Box` 的顺序预解析并向内建单元自动包含彼此的头文件，这个顺序就是 DAG 的拓扑序。

## 命名空间（DOC-87 Stage 2）

六个 UTF-8/容器单元声明 `namespace core;`，UTF-16 对声明 `namespace core::utf16;`
（目录 `lib/core/utf16/` 与命名空间一致）。源文件的**规范拼写**是 `core::Vec` /
`core::Map` / `core::MapEntry` / `core::Option` / `core::Result` / `core::String` /
`core::Str` / `core::utf16::U16String` / `core::utf16::U16Str` / `core::Box`。
根拼写在一个 MINOR 的兼容窗内仍可用，本阶段不告警。

- **生成物**：兼容窗内 `core::` 是源级命名空间别名，内置层的 C 符号保持根拼写
  （`Vec_int` / `String` / `Box_P`），因此没有 ABI、`--emit-model` 或 golden 变化；
  旧→新符号映射是恒等映射。`core_` 前缀的 C 名字改写另立 issue。
- **与 std 包不重叠**：外部 ct-pkg `std` 仍占 `std::*`（如 `std::str::CharStr`），
  `core::*` 不会遮蔽它。
- **不是保留关键字**：用户自己的 `namespace core`（§4.10）不受影响。

### SH-120：U16 公开名迁移（破坏性命名，带兼容窗）

SH-120 把原来的一个 `Str.h.ct` 拆成四个单主类型单元，U16 对进入 `lib/core/utf16/`：

| 旧 | 新（规范） | 兼容窗内仍可用 |
| --- | --- | --- |
| `lib/core/Str.h.ct` 里的 `U16String` | `core::utf16::U16String` | 裸 `U16String`、`core::U16String` |
| 同上 `U16Str` | `core::utf16::U16Str` | 裸 `U16Str`、`core::U16Str` |
| `String` / `Str` | `core::String` / `core::Str`（不变） | 裸拼写（不变） |

- **源级**：`core::utf16::U16String u` / `core::utf16::U16Str v` 类型拼写可用；工厂仍写作
  `U16String.from_utf8(Str)`（点形式；`类型::静态方法` 的限定调用不在本语言面内）。
- **C 符号不变**：`lib/core` 路径在兼容窗内不做命名空间改写，C 名仍是根拼写
  （`U16String` / `U16String_from_utf8`），所以没有 ABI / `--emit-model` / golden 变化。
- **构建产物**：`ct build` 的四个 C 单元是 `String.c` / `Str.c` / `U16String.c` /
  `U16Str.c`。`String` 单元的头文件写作 `String_.h`（不是 `String.h`）：在不区分大小写的
  文件系统上，`-I <outdir>` 会让 `#include <string.h>` 命中 `String.h`，`String_.h`
  保证 libc 的 `string.h` 永远是真身。
- **类型别名不可行，兼容方案是命名空间省略窗**：语言没有用户级 `typedef`-style 类型别名
  能把 `core::U16String` 绑到 `core::utf16::U16String`（`typedef` 只能给已解析类型起新名，
  不改变保留名的解析）。因此兼容由与 DOC-87 同一个 MINOR 窗口提供：`lib/core/**` 的内建单元
  在源级不改写命名空间，`U16String` / `core::U16String` / `core::utf16::U16String` 解析到
  同一个根符号，C 名与 ABI 不变。窗口的关闭与旧别名删除另立 issue。
- **迁移动作**：旧源码**无需修改**即可在兼容窗内继续编译；要迁到规范拼写时，把类型名写成
  `core::utf16::U16String` / `core::utf16::U16Str`，或保留裸名。

## 内建 trait（LANG-23）

`Vec.h.ct` 顶部有 `Drop` / `Handback` 的**可见声明**：

```ct
pub trait Drop { void drop(); }
pub trait Handback { void handback(); }
```

它们是保留名内建 trait：编译期按名字识别，无 vtable / vptr，不计入 `MAX_TRAITS`，
用户单元不得重新声明。声明只作契约与编辑器跳转；`use Drop` / `impl Drop` 的行为
与生成 C 不变。`AutoDrop` 是 `own` 的自动释放机制，**不是 trait**，本目录不声明它。

## 保留名

| 名字 | 含义 |
| --- | --- |
| `Vec` | `Vec<T>`，动态数组 |
| `Map` | `Map<K, V>`，按插入序遍历的映射 |
| `MapEntry` | `MapEntry<K, V>`，`foreach` 的 `item` 类型（`key` / `value` 字段） |
| `Option` | `Option<T>`，`has` + `value` 标签结构（Phase 34） |
| `Result` | `Result<T, E>`，`ok` + `value` + `err` 标签结构（Phase 34） |
| `String` / `Str` | `String`，16 字节 owning 句柄（`char *ptr` + `int len`）；`Str` 是同布局的借用视图（Phase 80） |
| `U16String` / `U16Str` | UTF-16 owning / 借用对（`uint16_t *ptr` + `int len`），仅显式工厂（Phase 80）；规范名 `core::utf16::U16String` / `core::utf16::U16Str`（SH-120） |

这些拼写是编译器的保留名，用户 struct 不得占用；编译器自身的模块表已改名为 `MapTable`
（`frontend/module/MapTable.h.ct`）。它们没有 `std::vec::Vec` / `std::map::Map` 这样的模块路径别名：
内置层是预解析的单元集合，不是 `std` 包的一部分。

**从旧 `std` 包升级**：Phase 29 之前 `Vec` / `Map` 由 `ct-pkg/std` 的 `vec.ct` / `map.ct` 提供，
项目里通常写着 `import std::vec` / `import std::map`。内置层生效后这些拼写成了保留名，旧包的声明
会撞上 `'Vec' is a built-in type and cannot be redeclared`。处理方式：升级 `std` 包到删除容器章节的
版本，或删掉项目里的 `import std::vec` / `import std::map` 与本地副本；容器 API 与旧包一致。

## 命名

内置层遵循 [language-spec §5.1](../../docs/language-spec.md)：函数 / 方法 `snake_case` 且动作动词开头，
类型 `PascalCase`，任何位置不用小驼峰；libc 直映射（`printf`、`puts` 等）保留原名。
`Vec.len` / `has` / `at`、`Map.len` / `has` 以及 `std::str::CharStr.len` 是既有保留名，
不因该条改名；保留名只豁免「动词开头」，不豁免小驼峰。`Str` 只有字段 `len` 与自由函数
`str_len`，**没有 `len` 方法**，因此不在保留名清单里。

## 语义口径

- **移动语义 + 显式 `retain()`**：变量间直接拷贝是硬错；从函数调用初始化/赋值视为移交；
  `release()` 递减引用计数并让该句柄失效，**同一句柄第二次 `release` 是硬错**（`abort`），
  即使 `retain` 出的兄弟句柄还持有共享缓冲，也不是静默 no-op / 二次递减。
- **不自动析构（容器自身）**：`Vec` / `Map` 模板本身不 `use Drop`，不会因为一次拷贝就先释放；宿主
  struct 声明 `use Drop` 且无显式 `impl Drop` 时，字段胶水按 LANG-27 调用该字段的 `release()`
  级联释放元素。`own` / `borrow` 不能进容器。
- **`Map` 插入序**：紧凑 entries + 删除左移；扩容不改顺序，golden 稳定。
- **`Map` 键**：白名单 `int` / `long` / `char *` / `Str`，由编译器在类型实参处强制（L29-8 / L47-1）。
  `int` / `long` 按键的字节比较，`char *` 走 `strcmp`，`Str` 按 `len` 加 `memcmp` 比较恰好那么多
  字节（内嵌 `\0` 是数据，不碰撞）；三份实现分别是 `impl<K, V> Map<K, V>`、
  `impl<V> Map<char *, V>` 与 `impl<V> Map<Str, V>`，不以 `sizeof` 判断键类别（64 位下 `long`
  与指针同宽）。**`Str` 键在 `put` 时深拷贝**（`str_from_len`），条目的 `release` / `remove` /
  覆盖写各释放一次；`char *` 键仍**借用**调用方的指针，生命周期由调用方负责（D47-3′）。
- **`Map` 的 `foreach` 键**：`foreach` 暴露的 `Str` 键是**借用**（条目自己仍拥有它）；
  **不得 release 键**，否则与条目释放构成双释放（D47-6）。只读使用，或先 `retain()` 取独立副本。
- **取用契约（Phase 50）**：`Vec::get(i)` / `Map::get(k)` 的签名与零值/`0` 语义**不变**（D50-1）。
  并行入口是 `Vec::has(i)`、`Vec::at(i) -> T *` 与 `Map::has(k)`（`int` / `char *` / `Str` 三份
  键实现都补）。`has` 只回答「在不在」，`at` 未命中返回 `0`、命中返回**借用指针**——不复制元素、
  不增加引用（D50-2/D50-3）。借用指针在容器被修改或 `release` 后失效，调用方**不得 release**
  它；容器只认元素自己的 `retain`/`release` 协议，`release` 只释放容器自己持有的引用，不做
  额外的递归释放。
- **构造入口**：`impl<T> Vec<T>` 里的 `static Vec<T> from(T *items, int n)` 是唯一会读取
  `Vec` 布局的构造路径；编译器的 range 初值语法糖只降级成
  `Vec_<enc>_from((T[n]){ … }, n)`，不知道 `ct_buf` 与字段（phase29 §11）。源码里也可以直接写
  `Vec<int>::from(arr, n)`。
- **`foreach`**：`Vec` / `Map` 走 `len` + `get` / `entry`；`item` 是值拷贝，`i` 只读且仅对
  `Vec` / 数组有意义，`Map` 体内用 `i` 是硬错（L29-18）。
- **`Option` / `Result`（Phase 34）**：都是普通泛型 struct，不是编译器分支。构造用字面量
  `{ 1, v }` / `{ 0 }`（`Result` 是 `{ 1, v, 0 }` / `{ 0, 0, e }`）；查询与取值是固有方法
  （`is_some` / `is_none` / `unwrap_or` / `unwrap` / `set` / `clear`；`Result` 是 `is_ok` /
  `is_err` / `unwrap_or` / `unwrap_err_or` / `unwrap` / `unwrap_err` / `set_ok` / `set_err`）。
  `unwrap` / `unwrap_err` 在错误一侧 `abort`，不返回零值。payload 按值拷贝，`release` 是 no-op；
  `?` / pattern matching / payload 自动释放属后续阶段（D34-8）。当实参是消费方单元的 struct 时，
  布局与方法在消费方发射，本目录的头文件只留前向声明。
- **`String` / `Str`（Phase 80 / D-013）**：`String` 拥有 `char *ptr` 与字节数 `len`；8 字节
  `struct ct_str_hdr { int refs; int aux; }` 位于 `ptr - 8`，`refs = -1` 为 immortal（字面量 / 空串，
  `release` 是 no-op）。`String` 不可变：`s[i]` 是只读单码点 `Str`，写是硬错；`.data` 是只读原始视图
  （`const char *`，不保证 NUL，只能下标），`cstr()` 是唯一 C 边界出口。显式协议 `copy` / `retain` /
  `release`；`Vec` / `Map` 插入由元素 glue 自动 retain；D-013 §3 的自动半部（SH-102，v0.80.1）：
  按值传参入口 retain、被调方出口 release，字段赋值 / 非局部 owning return retain，局部句柄 return
  按 move，重新赋值先 retain 后 release 旧值，作用域释放 owning 局部；借用视图（`Vec.get` /
  `Map.get` 结果）不 retain 也不 release。`U16String` / `U16Str` 同构，UTF-16 payload 的
  头按 `char *` 回退 8 字节计算。`Map<String,V>` 的键块在 `put` 深拷贝借用键，`Map<Str,V>` 是存储位置，
  被类型检查拒绝。
- **旧 owning `Str` 已删除（Phase 80 S5b）**：`lib/core/StrLegacy.h.ct` 与 `namespace std::str`
  兼容单元已移除，旧拼写不再解析；仓内消费者已迁到 `String` / `Str`。

## 迁移与回退（DOC-87 Stage 1）

- 新代码用 `CT_CORE_DIR=<repo>/lib/core`；旧的 `CT_STD_DIR` 只在一个 MINOR 的兼容窗内仍被读取，
  每次进程打印一条 `warning: CT_STD_DIR is deprecated; use CT_CORE_DIR`。
- 查找顺序：`CT_CORE_DIR`（权威）→ `CT_STD_DIR`（弃用，打警告）→ `./lib/core` → 输入同级
  `../lib/core` → 旧 `./lib/std` / 输入同级（DOC-87 迁移回退；命中时打警告）。`CT_CORE_DIR` 指向不存在的目录是
  **硬错**（`CT_CORE_DIR points to a missing directory: <dir>`），不静默回退。
- 变量值指向**包含 `Vec.h.ct` 的目录**；`--freestanding` 不加载内置层，不受影响。
- **回退**：Stage 1 是单提交（目录 `git mv`、loader 查找、脚本、活跃文档同进同退）。`git revert`
  该提交即恢复 `lib/std` 与旧查找（迁移回退），`CT_CORE_DIR` 随之消失；不需要 tag、不重写历史。
- 一个 MINOR 后删除旧路径/旧变量并另立清理 issue（不并入 DOC-87 Stage 1）。

## 版本对齐

内置容器 API 的版本 = 编译器版本（本条随 `ct -v` 走）；`ct-pkg/std` 其余模块继续走自己的包版本。
两份实现不得并存：本目录是唯一来源。

## ct-pkg 侧待删清单（跨仓，本轮未执行）

需 ct-pkg 仓授权后，在**同一次跨仓动作**里完成：

- 删除 `ct-pkg/std` 的 `vec.ct`、`map.ct`（含 `Vec` / `Map` / `MapEntry` 定义及其测试、文档页）；
- `std` 包 README 移除容器章节，发布一个新包版本；
- `ct-pkg/index` 的 `std` 条目**保留为在用**，只更新到该版本，**不标 superseded**（`str` / `io` / `math`
  仍由它供）。

**保留**：`str` / `io` / `math` 及其测试原样不动。
