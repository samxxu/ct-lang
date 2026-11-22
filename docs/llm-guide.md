# LLM 使用指南：先查生态，再写代码

> 中文
>
> 面向 LLM / 代理的入口。目标：写任何 Ct 代码前，先确认语言语法、标准库、平台包与索引里
> 是否已有实现；**不要重写 std，不要复制包源码，不要把提案当现状**。
> 适用版本：安装入口 ct-ast；实际版本以 `ct -v` 为准。

## 1. 固定决策顺序

按顺序查，前一步能回答就不要跳到下一步：

1. **语言 / 语法 / 展开规则 / 明确不支持** → [language-spec](language-spec.md)；
2. **容器 / 字符串 / 文件 / UTF-8 / 数字 / 数学 / 时间 / 网络 / 进程 / arena / test** →
   先查 [std-catalog](std-catalog.md)（`std` 包）；
3. **硬件 / 平台** → 先查 `ct-pkg/hal` 与 `ct-pkg/hal-posix`（见 [ct-pkg](ct-pkg.md)）；
4. **通用能力 / 第三方库** → 先查 [ct-pkg-index](ct-pkg-index.md) 与已发布包；
5. **都没有** → 才实现；实现后可复用就按包发布，**不 vendored**。

## 2. 硬规则（违反即错）

| # | 规则 |
| --- | --- |
| H1 | `Vec<T>` / `Map<K,V>` / `Option<T>` / `Result<T,E>` / `String` / `U16String` / `Str` 是**编译器内置层**（`lib/core/`，规范拼写 `core::Vec` 等，根拼写兼容窗内可用），自动加载、**免 import**；`String` 是 owning 句柄，`Str` 是借用视图（PH-80 起，不再有 owning `Str`）。不要重写，也不要再 `import std::vec` / `std::map`（这两个模块已在 std 0.3.0 删除，见 [lib/core/README](../lib/core/README.md)） |
| H2 | 标准库模块用 `ct get ct/std` 安装，按 `import std::<mod>::<Unit>` 导入；**不要手写替代**，完整入口见 [std-catalog](std-catalog.md) |
| H3 | 别人的包用 `ct get <publisher>/<name>`（配 `--index` / `CT_INDEX`）；**不要复制源码进本仓**，也不要假设裸名能解析（裸名只查官方 pin 表） |
| H4 | 包格式是 `ct.pkg` + `publisher` + `ns-root`；不要自造清单键或目录布局，见 [package-guide](package-guide.md) |
| H5 | 索引当前是六字段纯文本（五字段旧行按行硬错）；**索引没有签名**，不要声称它「可信」或「已 pin」，见 [ct-pkg-index](ct-pkg-index.md) |
| H6 | `hal` / `hal-posix` 的仓在 ct-pkg，但当前只有 `ct/std` 在内置 pin 表；`ct get ct/hal` 需要显式 `--index` / `CT_INDEX`（六字段行）或 URL，不要写成「无索引可用」 |
| H7 | `proposals/` 下的文档是**提案**，不是现状；现状以 language-spec、std-catalog、package-guide、ct-pkg-index 为准 |

## 3. 需求 → 先查哪

| 需求 | 先查 | 不要做 |
| --- | --- | --- |
| 动态数组 / 映射 | 内置 `Vec<T>` / `Map<K,V>` | 自己写 `struct` + `realloc` 容器 |
| 字符串查找 / 切片 / 拼接 / 切分 / 数字解析 | 内置 `String` / `Str`（`byte_index_of` / `slice` / `byte_slice` / `cstr`；`String` 为 owning，`Str` 为借用视图） | 手写 `split` 或复制包里的 `String` |
| 文件 / 目录 / 元数据 | `std::fs`、`std::io` | 手写 `opendir` / `stat` 包装 |
| UTF-8 编解码 / 码点计数 | `std::utf8` | 手写 UTF-8 状态机 |
| 数字 / 浮点 / 数学 | `std::num`、`std::math` | 重写 `to_str` / `sqrt` 包装 |
| 时间 / 定时器 / 网络 / 进程 / 环境变量 | `std::time`、`std::net`、`std::process`、`std::env` | 直接 `#include` 系统头再自己包一层 |
| 测试断言 | `std::test` | 自带一套断言宏 |
| 硬件 / 板级 / RTOS | `hal` / `hal-posix`（按 H6 安装） | 在应用层重造 HAL |

## 4. 最小命令

```sh
ct get ct/std@0.19.0        # 官方 pin 表；无需索引；解析到 std 0.19.0
ct build main.ct -o main    # ct.lock 自动补 store 的 include root

ct get <pub>/<name> --index <file>   # 第三方：显式索引
CT_INDEX=<file> ct get <pub>/<name>  # 或环境变量
ct verify                            # 离线校验 store 与 lock
ct install                           # 打印带 -I / cflags / ldflags 的构建命令
```

官方包落 `$CT_HOME/pkg/<publisher>/<name>/<version>/`（`CT_HOME` 默认 `$HOME/.ct`）；
完整 API 在包内 `std/<mod>/README.md`，本仓不复制。

## 5. 判断示例

- **「实现一个字符串 split」**：先看内置 `String` / `Str`——按分隔符切分可用
  `byte_index_of` + `byte_slice` 组合；不要重写 `String`。
- **「实现 Vec / Map」**：用内置泛型；`Vec<T>` / `Map<K,V>` 由编译器预解析，见
  [language-spec §4.51](language-spec.md#451-泛型-struct固有方法与内置容器phase-29)。
- **「加一个包」**：写 `ct.pkg`（`publisher` + `ns-root`），用 `tools/package.sh` 发布到
  `ct-pkg/index`；消费端 `ct get <pub>/<name>`。不要把包源码 vendored 进项目。
- **「索引格式是什么」**：六字段 `name version publisher url tag sha256:<hex>`；五字段旧行
  可解析但没有 `publisher`、不能落 store。见 [ct-pkg-index](ct-pkg-index.md)。

## 6. 文档地图

| 文档 | 内容 |
| --- | --- |
| [idioms](idioms.md) | 惯用优先级与选型（所有权分层、String/Str、切片、ref/out、ADT、遍历、泄漏）；附录 briefing 带 spec 节号 |
| [language-spec](language-spec.md) | 语法、展开、容量、明确不支持 |
| [std-catalog](std-catalog.md) | `std` 16 个模块的用途、入口 import、API 在哪 |
| [ct-pkg](ct-pkg.md) | 编译器 / std / 平台包 / 索引四个角色 |
| [ct-pkg-index](ct-pkg-index.md) | 索引字段、信任边界、发布入口 |
| [package-guide](package-guide.md) | 包作者：清单键、`ns-root`、`ct install` |
| [tutorial](tutorial.md) | 从安装到多文件、内存与 `map` 的入门 |

发现文档与实测不一致时，先按 `ct -v` 与实际命令输出判断，并把偏差登记到 `issues/`；
不要以旧文档为准改实现。
