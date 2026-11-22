# `std` 模块速查（薄目录，不复制 API）

> 中文
>
> 回答一个问题：**要用的能力在 `std` 的哪个模块、叫什么入口**。完整方法、参数、返回值、
> 内存归属与坑在包内 `std/<mod>/README.md`，本文不复制。
>
> 核对基线：`std 0.19.0`（`ct 0.77.1` 内置 pin 表；2026-11-20 实测），16 个模块。
> 版本以 `ct get ct/std` 的解析结果为准。

## 1. 先看内置层（不需要安装，也不需要 import）

`lib/core/` 是随编译器预解析的内置层，`ct compile` 与 `ct build` 都自动加载：

| 名字 | 形态 | 说明 |
| --- | --- | --- |
| `Vec<T>` | 动态数组 | 移动语义 + `retain()`；`len` / `has` / `at` / `push` / `pop` / `release` |
| `Map<K,V>` | 插入序映射 | 键白名单 `int` / `long` / `char *` / `Str`；固定容量、满载拒绝新键 |
| `MapEntry<K,V>` | `foreach` 的 `item` | `key` / `value` 字段 |
| `Option<T>` | 有值 / 无值 | `has` + `value` |
| `Result<T,E>` | 成功 / 失败 | `ok` + `value` / `err` |
| `Str` | 带长度字符串 | `char *data` + `int len` |

这些是**编译器保留名**，不是 `std` 包的一部分；`std::vec` / `std::map` 已在 std 0.3.0 删除。
DOC-87 Stage 2 起规范拼写是 `core::Vec` / `core::String` 等（源级命名空间）；根拼写在
一个 MINOR 的兼容窗内仍可用，生成 C 不变（见 [lib/core/README](../lib/core/README.md)）。
细节见 [lib/core/README](../lib/core/README.md) 与 [language-spec §4.51](language-spec.md#451-泛型-struct固有方法与内置容器phase-29)。

## 2. `std` 包模块

安装：

```sh
ct get ct/std@0.19.0
```

导入形态固定为 `import std::<mod>::<Unit>;`；`<Unit>` 是下表的「入口」。

| 模块 | 用途 | 入口 `import` |
| --- | --- | --- |
| `std::str` | `char *` 字节串方法：`find` / `slice` / `concat` / `split_into` / 大小写 / 数字解析 | `std::str::String`（下一 MINOR 改名 `std::str::CharStr`） |
| `std::io` | stdio 流与文件描述符；`File` / `FileDesc` 是 `Drop` 资源句柄 | `std::io::Stdout` / `std::io::File` |
| `std::fs` | `char *` 路径方法、目录流 `Dir`、元数据 `Stat` | `std::fs::Fs` |
| `std::utf8` | UTF-8 解码、编码、码点计数；严格校验、不分配 | `std::utf8::Utf8Ops` |
| `std::num` | 整数与字符宿主方法：`to_str` / `to_base` / `clamp` / `is_digit` | `std::num::Num` |
| `std::math` | 浮点方法：`Float` / `Real`，`x.sqrt()` / `x.pow(2.0)` | `std::math::Real` |
| `std::search` | 带比较器的 `qsort` / `bsearch` 转发 | `std::search::Search` |
| `std::arena` | 块式 bump 分配器 `Arena`（外部 `ct/std` 0.19.0 实测；不是编译器内置层） | `std::arena::Arena` |
| `std::test` | 断言计数器 `Test`；`check*` / `report` | `std::test::Test` |
| `std::env` | 环境变量复制式读写 | `std::env::Env` |
| `std::process` | `fork` / `exec*` / `wait*` / 信号 / `getpid` | `std::process::Process` |
| `std::errno` | `errno` 与 `strerror` 的复制式读取 | `std::errno::Errno` |
| `std::locale` | 区域设置命名、应用与数字约定 | `std::locale::LocaleHandle` |
| `std::wchar` | 宽字符与多字节互转（`<wchar.h>`） | `std::wchar::Wchar` |
| `std::time` | 时钟、日历与定时器 `Timer` | `std::time::Time` / `std::time::Timer` |
| `std::net` | TCP / UDP 套接字；`Socket` 是 `FileDesc` 别名 | `std::net::Socket` |

两种实现形态，不要互相套用：

- **C 宿主映射**（`.m.ct` + 同名 `.shim.h`）：`str` / `io` / `fs` / `utf8` / `num` / `math` /
  `search` / `env` / `process` / `errno` / `wchar` / `time` 的方法层。接收者是 C 已有类型
  （`char *`、`int`、`double` …），调用点直接展开成 C 调用。
- **Ct 自有类型**（`.h.ct` + 固有 `impl`）：`arena` / `test` 的值类型，以及资源句柄
  `io::File` / `io::FileDesc` / `fs::Dir` / `locale::LocaleHandle` / `time::Timer`。

包内另有 `mmap` / `poll` / `posix` / `thread` 等无独立 README 的内部单元（目录存在但不进上表）；
需要时先读源码与 `ct.pkg` 的 `requires`，不要把内部单元当稳定 API。

## 3. 装在哪、完整 API 去哪读

`ct get ct/std@0.19.0` 把包写进共享 store；`ct build` 按 `ct.lock` 自动补 include root：

```
$CT_HOME/pkg/ct/std/0.19.0/            # ns-root = .，include root 就是版本目录
$CT_HOME/pkg/ct/std/0.19.0/std/<mod>/  # 模块目录
$CT_HOME/pkg/ct/std/0.19.0/std/<mod>/README.md  # 方法全集、参数、返回值、内存归属、坑
```

`CT_HOME` 默认 `$HOME/.ct`。包内每个模块只有一份 `README.md`，**不再有独立 `tutorial.md`**；
入门用法见 [tutorial §10](tutorial.md#10-标准库std)。

## 4. 边界

- 不复制完整 API：本文只做「需求 → 模块 → 入口」的索引；
- 不把 `std` 源码复制进项目；消费入口是 `ct get`，发布入口在 `ct-pkg`（见 [ct-pkg](ct-pkg.md)）；
- 不假设模块之间有隐式依赖：`ldflags = -lm` 只服务 `std::math`，其它模块按各自 README；
- 不把 `proposals/` 里的未来模块当成现状。
