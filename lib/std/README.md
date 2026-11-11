# lib/std — 内置容器层（随编译器发行）

> 中文。范围与判据见 [phase29.md](../../docs/design/phase29.md) §2.7、[language-spec §4.51](../../docs/language-spec.md)。

## 这是什么

`lib/std/` **只承载内置 `Vec` / `Map`（含 `MapEntry`）及其直接依赖**，不是整个 `std` 的新家。
`str` / `io` / `math` 等其余模块仍由 ct-pkg 包 `std` 提供，本目录不复制、不镜像。

`Vec.h.ct` 是**编译模式**与 **`ct build`** 两条路径都会自动预解析的单元：`ct file.ct -o file.c`
把它 splice 到用户程序之前，`ct build` 则把它作为一个独立单元参与发射；两种形态都
**不需要 import**、不需要 `ct get`。编译模式的产物仍是单个 C TU、根命名空间。

## 保留名

| 名字 | 含义 |
| --- | --- |
| `Vec` | `Vec<T>`，动态数组 |
| `Map` | `Map<K, V>`，按插入序遍历的映射 |
| `MapEntry` | `MapEntry<K, V>`，`foreach` 的 `item` 类型（`key` / `value` 字段） |

这三个拼写是编译器的保留名，用户 struct 不得占用；编译器自身的模块表已改名为 `MapTable`
（`frontend/module/MapTable.h.ct`）。显式路径 `std::vec::Vec` / `std::map::Map` 指向同一类型。

## 语义口径

- **移动语义 + 显式 `retain()`**：变量间直接拷贝是硬错；从函数调用初始化/赋值视为移交；
  `release()` 递减引用计数，**归零后再 `release` 是硬错**，不是静默 no-op。
- **不自动析构**：容器没有 `Drop` 级联；`own` / `borrow` 不能进容器。
- **`Map` 插入序**：紧凑 entries + 删除左移；扩容不改顺序，golden 稳定。
- **`Map` 键**：当前实现按 `sizeof(k) == sizeof(char *)` 选 `strcmp` / `memcmp`（见 phase29 §10.2
  的偏差），键白名单（L29-8）待参数化 trait。
- **构造入口**：`impl<T> Vec<T>` 里的 `static Vec<T> from(T *items, int n)` 是唯一会读取
  `Vec` 布局的构造路径；编译器的 range 初值语法糖只降级成
  `Vec_<enc>_from((T[n]){ … }, n)`，不知道 `ct_buf` 与字段（phase29 §11）。源码里也可以直接写
  `Vec<int>::from(arr, n)`。
- **`foreach`**：`Vec` / `Map` 走 `len` + `get` / `entry`；`item` 是值拷贝，`i` 只读且仅对
  `Vec` / 数组有意义，`Map` 体内用 `i` 是硬错（L29-18）。

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
