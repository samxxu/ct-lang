# lib/std — 内置容器层（随编译器发行）

> 中文。范围与判据见 [phase29.md](../../docs/history/design/phase29.md) §2.7、[language-spec §4.51](../../docs/language-spec.md)。

## 这是什么

`lib/std/` **只承载内置 `Vec` / `Map`（含 `MapEntry`）、`Option` / `Result` 与 `Str` 及其直接依赖**，
不是整个 `std` 的新家。
`io` / `math` 等其余模块仍由 ct-pkg 包 `std` 提供，本目录不复制、不镜像；`Str` 的
`char *` 映射层 `std::str::String` 仍在 ct-pkg `std`（Phase 36 的 S0 实测该包没有
`std/string` / `CStr`，故按 `docs/design/phase36-draft.md` §14/§15 把 `Str` 值类型放回内建层）。

内置层由四个单元组成：`Vec.h.ct`（容器）、`Option.h.ct`（Phase 34）、`Result.h.ct`（Phase 34）、
`Str.h.ct`（Phase 36）。
四者都是**编译模式**与 **`ct build`** 两条路径都会自动预解析的单元：`ct file.ct -o file.c`
把它们 splice 到用户程序之前，`ct build` 则把它们作为独立单元参与发射；两种形态都
**不需要 import**、不需要 `ct get`。编译模式的产物仍是单个 C TU、根命名空间。

## 保留名

| 名字 | 含义 |
| --- | --- |
| `Vec` | `Vec<T>`，动态数组 |
| `Map` | `Map<K, V>`，按插入序遍历的映射 |
| `MapEntry` | `MapEntry<K, V>`，`foreach` 的 `item` 类型（`key` / `value` 字段） |
| `Option` | `Option<T>`，`has` + `value` 标签结构（Phase 34） |
| `Result` | `Result<T, E>`，`ok` + `value` + `err` 标签结构（Phase 34） |
| `Str` | `Str`，`char *data` + `int len` 的带长度字符串（Phase 36） |

这六个拼写是编译器的保留名，用户 struct 不得占用；编译器自身的模块表已改名为 `MapTable`
（`frontend/module/MapTable.h.ct`）。它们没有 `std::vec::Vec` / `std::map::Map` 这样的模块路径别名：
内置层是预解析的单元集合，不是 `std` 包的一部分。

**从旧 `std` 包升级**：Phase 29 之前 `Vec` / `Map` 由 `ct-pkg/std` 的 `vec.ct` / `map.ct` 提供，
项目里通常写着 `import std::vec` / `import std::map`。内置层生效后这些拼写成了保留名，旧包的声明
会撞上 `'Vec' is a built-in type and cannot be redeclared`。处理方式：升级 `std` 包到删除容器章节的
版本，或删掉项目里的 `import std::vec` / `import std::map` 与本地副本；容器 API 与旧包一致。

## 命名

内置层遵循 [language-spec §5.1](../../docs/language-spec.md)：函数 / 方法 `snake_case` 且动作动词开头，
类型 `PascalCase`，任何位置不用小驼峰；libc 直映射（`printf`、`puts` 等）保留原名。
`Vec.len` / `has` / `at`、`Map.len` / `has`、`Str.len` 以及 `std::str::String.len` 是既有保留名，
不因该条改名；保留名只豁免「动词开头」，不豁免小驼峰。

## 语义口径

- **移动语义 + 显式 `retain()`**：变量间直接拷贝是硬错；从函数调用初始化/赋值视为移交；
  `release()` 递减引用计数并让该句柄失效，**同一句柄第二次 `release` 是硬错**（`abort`），
  即使 `retain` 出的兄弟句柄还持有共享缓冲，也不是静默 no-op / 二次递减。
- **不自动析构**：容器没有 `Drop` 级联；`own` / `borrow` 不能进容器。
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
- **`Str`（Phase 36）**：拥有 `char *data` 与字节数 `len`；不要求 NUL 结尾，保留内嵌 `\0`。
  显式 `impl Drop for Str` 释放 `data`（`data == 0` / `len == -1` 为已释放态，`free(0)` 无害）；
  固有方法 `retain` / `release` 满足 Phase 31 元素协议，`Vec<Str>` 显式 `release()` 时逐元素释放。
  `own Str *` 走既有 AutoDrop；按值拷贝只复制句柄，要独立句柄必须 `retain()`。

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
