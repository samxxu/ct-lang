# ct — C with Traits 编译器

> **v0.44.0** · 中文 · [English](README.en.md)

**ct** 是一个 **source-to-source 编译器**：把带 trait 语法的 `.ct` 源文件翻译成纯 C 的 `.c` 文件。
编译路径（`ct compile` / `ct build`）不做类型检查、不做优化；可选的 `ct check` 只做受限语义检查
（调用点 arity、实参类型、trait 方法歧义、impl 签名漂移）。生成物是**可读的普通 C**，不依赖任何运行时库，vtable 与 `_self` 强转等样板代码都由编译器生成。
已完成的能力与后续阶段见 [docs/roadmap.md](docs/roadmap.md)，术语见 [docs/glossary.md](docs/glossary.md)。

---

## 中文

### 1. 快速开始

```bash
# 1a) 安装（下载源码 → 本地四级自举 → 装到 ~/.local/bin）
curl -fsSL https://raw.githubusercontent.com/samxxu/ct-lang/main/install.sh | sh

# 1b) 或者不安装，只用 L0 种子（单文件、核心语法；没有 ct，下面用 ./ctc）
gcc selfhost/l0/ctc.c -o ctc

# 2) 编译 .ct 到 .c（只有 .h.ct 输入才同时写同名 .h）
ct compile examples/01_greeter/greeter.ct -o /tmp/greeter.c      # 走了 1a
./ctc examples/01_greeter/greeter.ct -o /tmp/greeter.c           # 走了 1b

# 3) 用系统 C 编译器构建产物
gcc /tmp/greeter.c -o /tmp/greeter && /tmp/greeter
```

新用户从这里开始：[docs/tutorial.md](docs/tutorial.md)——逐章教程，每条命令都可直接粘贴。

### 2. 常用命令

| 命令 | 作用 |
| --- | --- |
| `ct <in.ct>` / `ct compile <in.ct>` | 单文件编译：普通 `.ct` 只写 `.c`，`.h.ct` 才额外写同名 `.h`；只接受**单文件单元**，`import` 需改用 `ct build`（`-I` 同理只对 build 生效，compile 下会提示被忽略） |
| `ct <in.ct> -o <out.c>` | 指定输出路径 |
| `ct build <in.ct>… [-o <exe>]` | 多文件构建：默认把生成的 `.c` 放进 `.ctbuild/`（`--outdir` 可改），再调用本地 C 编译器产出可执行文件（`-o` 是文件名，默认 `a.out`）；`--emit-c` 只发射 `.c`（`.h.ct` 另写 `.h`），此时 `-o` 是输出目录；`--runtime-checks` 在接口派发前检查空 vtable（默认关闭，关闭时产物不变） |
| `ct build --lib <root.h.ct> [-o <lib.a>]` | C ABI 静态库：根 `.h.ct` 的 C 兼容 `pub` 函数进入 `<base>.abi.h`，产物为 `lib<base>.a`（`-o` 可改；`--outdir` 默认 `.ctbuild`）；泛型模板跳过并警告，不兼容签名/`main`/`pub` 全局/shim 硬错；`nm -g` 面 ⊋ 导出面，只有 `.abi.h` 的声明是 ABI（Phase 39） |
| `ct check <in.ct>` | 只跑受限语义检查、不写 `.c`（仅单文件单元，`import` 不被接受）：调用点 arity / 实参类型 / trait 方法歧义 / impl 签名漂移（以及既有的 leak / 借用类发现）一律以 `error:` 报告，有任何发现退出 `1`，干净退出 `0`（`--diagnostics=json` 时对象带 `"severity":"error"`，并带 `"col"`） |
| `ct … --emit-map <file\|->` | 写出反向映射表 JSON（trait / struct / 函数 / impl → 生成的 C 符号） |
| `ct get` / `ct update` / `ct install` / `ct verify` | 包管理：拉包到 `vendor/`、写 `ct.lock`；离线重解 / 校验并打印一条构建命令（裸名可经 `--index` / `CT_INDEX` 查显式索引；包作者见 [docs/package-guide.md](docs/package-guide.md)）；官方包在 [ct-pkg](https://github.com/ct-pkg)：`hal`（契约）、`hal-posix`（平台）、`std`（标准库，含 C 映射） |
| `ct -v` / `ct -h` | 版本 / 用法 |

退出码：成功 `0`，语法或 I/O 错误 `1`（`ct check` 有任何语义发现，或 `ct build` 遇到 impl 签名漂移，也是 `1`）。源码诊断格式为 `文件:行:列: error: 描述`；驱动层错误以 `ctc:` 开头
（二进制改名为 `ct` 也不变，以保持日志与断言稳定）。完整开关（`-I` / `--std` / `--line` / `--diagnostics` /
`--ns-root`）见[教程 §11](docs/tutorial.md#11-命令行速查)。

### 3. 能力一览

- **trait**：`trait` / `impl` / `use`，方法派发，trait 当类型（接口值 / 数组 / 字段 / 装箱），trait 默认方法
- **内存**：`Drop` / `delete`、`own`（AutoDrop）、块级 `defer`（Phase 38）、路径敏感泄漏告警、`borrow` + `Handback`
- **模块**：`namespace` / `import` / `pub` / 多文件 `ct build` / 目录 = namespace
- **映射**：`map trait T for instance …`、`.m.ct` 零成本静态映射、伴生 C shim、`test/bindings/` 声明式 C 库对接
- **透传**：`#ct-raw` / `#ct-endraw` 原样块（宏与手写 C 逐字节进入生成的 `.c`）
- **诊断与工具**：`#line` 溯源、`--diagnostics=json|text`、多错误恢复、增量缓存、`ct get` / `ct install`
- **泛型函数**：`T name<T>(…)` + `name<int>(…)`，编译期单态化（Phase 26）；**约束泛型** `T name<T: Trait>(…)`（Phase 28）
- **泛型 struct 与内置容器**：`struct Name<T, U>` + `impl<T> Name<Args>` 静态派发（Phase 29）；`Vec<T>` / `Map<K,V>` 免 import，`foreach` 按插入序遍历 `Map`
- **泛型 trait**：`trait Iter<T>` / `impl Iter<int> for S` / `T: Iter<int>` 约束，实例按实参编码单态化（Phase 35）
- **标准结果类型**：`Option<T>` / `Result<T, E>` 内建于 `lib/std`，`is_some` / `is_ok` / `unwrap` 等为固有方法（Phase 34）
- **C ABI 静态库**：`ct build --lib` 把根 `.h.ct` 的 C 兼容 `pub` 函数导出为 `.abi.h` + `lib<base>.a`（Phase 39）
- **原子并发**：`atomic int` / `atomic long` / `atomic bool` / `atomic void *` + `ct_atomic_load` / `ct_atomic_store` / `ct_atomic_cas`（seq_cst，C11；`ct build` 自动切 `-std=c11`）（Phase 41）
- **方法级 `pub`**：`impl` 固有方法默认私有（不进 `.h`、`static`）；写 `pub` 才跨单元公开；trait impl / `pub impl` 硬错（Phase 42）
- **`return err:` 载荷契约**：`err:` 载荷必须可赋给函数返回类型；不一致 L43-1 硬错，四入口一致，不写坏 C（Phase 43）
- **后缀 `?` 错误传播**：`expr?` 把 `Result` 失败以 `Outer::err` 返回，成功取 `value`；L44-1/2/3；`?:` 消歧（Phase 44）
- **明确不做**：继承、默认编译路径的类型检查（`ct check` 只做受限检查）、优化（语言在 `1.0.0` 才定稿）

每条语法的展开规则以 [docs/language-spec.md](docs/language-spec.md) 为准；写法范例见 [docs/patterns.md](docs/patterns.md)，
内存约定见 [docs/memory-guide.md](docs/memory-guide.md)。

### 4. 仓库结构

`selfhost/` 是自举链：`l0/`（C 种子）→ `l1/`（冻结）→ `l2/`（回归 oracle）→ `ct-ast/`（主线，提供 `ct` 安装入口）；
`test/` 是测试与 golden；`docs/` 是文档；标准库是独立的 ct-pkg 包 `std`（`ct get std` 获取，不随仓库发布）；`test/bindings/` 是声明式 C 库 binding；`issues/` 是审查台账；`AGENTS.md` 是改动规约。
目录级说明见 [selfhost/README.md](selfhost/README.md)、[test/README.md](test/README.md) 与 [docs/architecture.md](docs/architecture.md)。

### 5. 文档与测试

- 文档导航：[docs/README.md](docs/README.md)
- 测试：`bash selfhost/check-all.sh` 跑 11 道硬门禁；分层地图见 [test/README.md](test/README.md)
- 改动代码前先读 [AGENTS.md](AGENTS.md)

### 6. 许可

GPL-3.0-or-later（编译器本体，见 [LICENSE](LICENSE)）；生成的 `.c`/`.h` 与你的 `.ct` **不受 GPL 约束**
（[LICENSE.EXCEPTION](LICENSE.EXCEPTION)）；`examples/`、`test/`、`editors/` 为 MIT。

### 7. 联系

作者 Sam X. Xu · samxxu@gmail.com · 问题与建议优先开 [Issue](https://github.com/samxxu/ct-lang/issues)。
