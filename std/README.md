# `std/` — ct 标准库

> 中文 · [English](#english)

`std` 是**源码库**，不是 `ct` 二进制的一部分：`import std::str::Str` 只在显式 `-I` 下解析，
编译器**没有**默认搜索路径（D17-2）。仓库里它是顶层 `std/`；`install.sh` 把它装到
`$(dirname "$prefix")/share/ct/std`，并打印建议的 `-I` 行。

```sh
ct build -I . main.ct -o main         # 在仓库根
ct build -I ~/.local/share/ct main.ct -o main   # 安装后
```

## 模块

| 单元 | namespace | 主要入口 |
| --- | --- | --- |
| `std/str/Str.h.ct` | `std::str` | `len` / `find` / `find_char` / `starts_with` / `ends_with` / `copy` / `slice` / `concat` / `lower` / `upper` / `compare` |
| `std/vec/Vec.h.ct` | `std::vec` | `VecInt` / `VecStr` 的 `*_init` / `*_len` / `*_push` / `*_pop` / `*_at` / `*_free` |
| `std/arena/Arena.h.ct` | `std::arena` | `init` / `alloc` / `reset` / `free_all` |
| `std/fs/Fs.h.ct` | `std::fs` | `exists` / `read_file` / `write_file` / `list` |
| `std/utf8/Utf8.h.ct` | `std::utf8` | `decode` / `encode` / `length` |
| `std/test/Test.h.ct` | `std::test` | `Test` 的 `init` / `check_true` / `check_eq_int` / `check_eq_str` / `report` |
| `std/map/Map.h.ct` | `std::map` | `MapStrInt` 与 `MapIntPtr` 的 `*_init` / `*_put` / `*_get` / `*_len` / `*_clear` / `*_free` |

调用一律限定写：`std::str::len(s)`，或先 `import std::str::Str;`。入口是 **`pub` 自由函数**，
不是 trait 方法——跨单元的 trait 方法在生成的 C 里是 `static`，调用方单元够不到；这是 std 的固定形态。

## 约定

- **目录 = namespace**：`std/<mod>/<Mod>.h.ct` 的 namespace 必须是 `std::<mod>`（`--ns-root` 会校验）；
  文件名是单元的主类型名。每个单元自包含（自己的 `#include`、自己的辅助 `static`）。
- **失败值是返回值，不是 abort**：缓冲区不够一律 `-1` / `NULL`，绝不静默截断；`alloc` 拿不到块返回 `NULL`。
- **不依赖 `delete`**：`Drop` / `Handback` 在生成物里是 `static`，库单元无法销毁调用方的值类型，
  所以每个持有资源的类型都提供显式 `*_free`（`VecInt` / `VecStr` / `Map*`）、`*_reset`（`Arena`）
  或 `*_clear`（`Map*`）。容器**不**自动释放元素：`VecStr` 的字符串是借用的指针。
- **容器是有界实现**：`Vec` 容量倍增、溢出即 `-1`；`Map` 固定容量（`init` 取整到 2 的幂，最小 16），
  满载拒绝新键，不自动 rehash。
- **`MapIntPtr` 的所有权**：`init` 时传入 `free_fn`（可为 `NULL`），`*_clear` / `*_free` 对每个
  value 调用一次。键按指针保存，生命周期由调用方负责。

**取舍（D17-7）**：v1 只发单态类型（`VecInt` / `VecStr` / `MapStrInt` / `MapIntPtr`），
没有泛型；`void *` 擦除的通用接口可替换，但会失去编译期的键/值类型安全，因此不随 v1 发布。

## English

`std` is a **source library**, not part of the `ct` binary: `import std::str::Str` resolves only
through an explicit `-I` (there is no default search path, D17-2). In the repository it is the
top-level `std/`; `install.sh` places it at `$(dirname "$prefix")/share/ct/std` and prints the
suggested `-I` line.

Each unit is `std/<mod>/<Mod>.h.ct` with `namespace std::<mod>` (the `--ns-root` check enforces
directory = namespace). Entry points are **`pub` free functions**, not trait methods: a cross-unit
trait method is emitted `static` and is unreachable from the caller's unit.

Failure is a return value (`-1` / `NULL`), never an abort and never a silent truncation. There is no
`delete`: `Drop` / `Handback` are emitted `static`, so every resource type ships an explicit
`*_free`, `*_reset` (the arena) or `*_clear` (the maps). Containers never free their elements —
`VecStr` strings are borrowed pointers, and `MapIntPtr` calls the `free_fn` supplied at `init`.

Containers are bounded: `Vec` doubles and returns `-1` on overflow; `Map` is fixed-capacity
(`init` rounds up to a power of two, at least 16) and refuses new keys when full — it never rehashes.

**Trade-off (D17-7)**: v1 ships monomorphic types only (`VecInt` / `VecStr` / `MapStrInt` /
`MapIntPtr`), no generics. A `void *`-erased interface is possible but loses compile-time key / value
typing, so it is not part of v1.
