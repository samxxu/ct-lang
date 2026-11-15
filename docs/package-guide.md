# 包作者指南

> 中文
>
> 状态：v1（Phase 18.1，2026-11-02）。工具实现见
> [`selfhost/ct-ast/tool/pkg/`](../selfhost/ct-ast/tool/pkg/)；binding 写法见
> [test/bindings/README.md](../test/bindings/README.md)；首批官方包见
> [phase18.md](history/design/phase18.md) 的 18.3–18.5。

---

## 中文

### 1. 一个包长什么样

包仓库的**根目录就是包根**：`ct.pkg`、`LICENSE` 与源码单元并列，不嵌套子目录。
「包根 = 单元根」是当前契约（陷阱与替代机制见 §8.1、§8.4）。

```
hello/
├── ct.pkg          # 清单（唯一由工具强制的文件）
├── LICENSE         # 许可证（发布约定必备；工具不校验，见 §5）
└── hello.h.ct      # 源码单元，可多个
```

源码单元遵守 [AGENTS.md](../AGENTS.md) §2 的「一单元一主类型」：

- `.h.ct`：`trait` / `struct` 声明、全局实例，以及 `pub fn` 函数——**`.h.ct` 可以导出函数**；
  std 把实现放在 `.ct` 只是风格选择；
- `.ct`：普通实现单元，不发布接口；需要跨单元导出的顶层函数仍要写在 `.h.ct` 里并标 `pub`；
- `.m.ct`：零成本静态映射，不产 `.c` / `.h`；
- binding 形式（`#include` 直通 + `map`）按 [test/bindings/README.md](../test/bindings/README.md)。

`pub` 的作用范围：顶层声明（顶层函数、`typedef`、`struct` / `trait` 与全局变量）由 `pub` 决定是否
跨单元可见；未标 `pub` 的顶层函数和全局只属于本单元。`impl` 里的固有方法**默认私有**——不进 `.h`、
定义发 `static`、跨单元调用报错；写 `pub` 才公开。`pub` 只允许出现在 `.h.ct` 单元的 `pub struct`
固有 `impl` 方法上，trait impl 的方法写 `pub` 是硬错（[language-spec §4.60](language-spec.md)，
Phase 42）。单元内私有 helper 既可以是不带 `pub` 的固有方法，也可以是 `.ct` 文件里的 `static`
自由函数。

#### 单元目录 = 命名空间

单元声明了文件级命名空间，就必须坐在同名目录里：`namespace a::b;` 的单元位于 `<包根>/a/b/`。

```
acme/
├── ct.pkg
├── acme/
│   ├── Uart.h.ct        # namespace acme;
│   └── uart.m.ct        # namespace acme;
└── examples/
    └── main.ct          # import acme::Uart;  无 namespace，不受目录规则约束
```

- 这是编译器的既有语义（D13 方案 A：只校验、不推导）。传 `--ns-root <包根>` 时，`ct build` 对每个
  声明了命名空间的入参单元检查目录，不符即报
  `namespace 'a::b' does not match the directory '...'`。
- 不带 `--ns-root` 时**不做**这项校验；`--ns-root` 只检查落在该根下的单元（根外文件静默跳过），
  所以自检要传包根、并把包内单元都作为入参。
- 没有 `namespace` 声明的单元不受目录规则约束（C 映射单元与 `.m.ct` shim 多属此类），它们的位置
  只由 `import a::b::Unit` 的解析路径决定。向这类单元补命名空间会改变其导出符号，属于破坏性变更。
- 本仓库（ct-pkg）另提供 `tools/check-layout.sh`，遍历全部包的 `*.ct`、读出命名空间并与相对目录
  比对，可放进 CI：`tools/check-layout.sh`（或指定包根 `tools/check-layout.sh hal sqlite`）。

### 2. `ct.pkg` 的键

行式清单：`key = value`，`#` 起注释，`dep` 可重复，未知键**忽略**（向前兼容）。

| 键 | 必填 | 含义 |
| --- | --- | --- |
| `name` | 是 | 包名，见 §3 |
| `version` | 是 | `x.y.z`（工具只解析前三位数字；预发布 / 构建元数据不纳入） |
| `dep` | 否，可重复 | 依赖，`name` 或 `name@range`；格式与 Phase 8 一致 |
| `cflags` | 否 | 消费者编译该包时附加的编译选项，`ct install` 折进打印的命令 |
| `ldflags` | 否 | 链接选项（如 C 映射包的 `-lm`），同上 |
| `requires` | 否 | 对编译器版本的约束；**不满足时 `ct get` / `ct install` 失败**，`--force` 才降级为告警 |
| `licence` | 否 | 许可证标识（SPDX 风格，如 `MIT`）。**仅约定，工具不解析** |

约定而不是工具的强制项：工具只强制 `name` 与 `version` 非空；`name` / `version` 缺失或为空时
`ct get` 报 `cannot read '<dir>/ct.pkg'`。命名、tag、目录与 `licence` 由索引收录与 CI 审核。

`cflags` / `ldflags` / `requires` 由 `ct install` 读取；`install` 把每个包的 `cflags` / `ldflags`
拼进**一条** `ct build` 命令，遇到不满足的 `requires` 直接失败（`ct install --force` 才继续，
并把原因打到 stderr）。`requires` 也在 `ct get` 里检查，且**发生在写 `ct.lock` 之前**：不满足时本次
`get` 失败、既有 `ct.lock` 一个字节都不改（`ct get --force` 才继续并告警）。

### 3. 命名、版本与 tag

- 包名：`[a-z0-9][a-z0-9-]*`（小写字母、数字、连字符；不以连字符开头）。
- **仓库名 = 包名**：`github.com/ct-pkg/<name>`。
- tag：`v<version>`；索引行的 `tag` 字段记录实际 tag（可带或不带 `v`）。
- `dep` 的范围沿用 Phase 8 子集：`^x.y.z`、`~x.y.z`、`>=` / `>` / `<` / `<=` / `=`、裸版本（精确）
  或 `*`，多个条件用空格表示 AND。解析用 MVS（取满足范围的最低版本）。
- 破坏性变更必须换 `x.y.z` 的主版本号；本阶段不研究传递更新的策略。

### 4. 发布、索引与消费

1. **发布**：仓库根放 `ct.pkg` 与源码，打 tag `v<version>` 并推送。
2. **索引收录**：在 `ct-pkg/index` 的 `index` 文件追加一行，五字段、空白分隔：

   ```
   name version git-url tag sha256:<64 hex>
   ```

   摘要按 `ct.lock` 的同一算法计算（按路径排序后把每个文件的相对路径与内容汇入单流 SHA-256）。
   索引由 CI 生成并提交（18.2），本地可用 `CT_INDEX=<file>` 或 `--index <file>` 指向任意纯文本索引。
3. **消费**：

   ```sh
   ct get <name>@<range>        # 裸名经索引解析；本地目录用 ./path 或 file://
   ct verify                    # 离线：校验 vendor/ 与 ct.lock 的摘要
   ct install                   # 离线：校验摘要与依赖覆盖，打印一条可直接执行的 ct build 命令
   ct update                    # 离线：按 ct.pkg 重解并重写 ct.lock
   ```

   `ct verify` 只做摘要校验，**不读 `ct.pkg`**；清单里的 `dep` 是否被 `ct.lock` 覆盖由 `ct install` 判定
   （缺依赖时报 `dependency '<spec>' is not satisfied by ct.lock`）。
   `ct get` 一次只解析一个 spec，但会保留 `ct.lock` 中本次没有重解的其它行；重复 get 同一个包只替换
   该包的行，不会重复。这样再 get 一个新包不会把先前钉住的版本弄丢，随后的 `ct update` 仍按锁里的
   commit 解析。
   `ct get` 可用 git——它是**包管理路径**里唯一的子进程调用点；`ct update` / `ct verify` / `ct install`
   零网络、零子进程。编译器侧 `ct compile` / `ct build --emit-c` 零网络、零子进程，但 `ct build`
   的默认形态会经 `$CC` 派生子进程去链接（`--cc` > `$CC` > `cc`）。

### 5. C ABI 静态库（`ct build --lib`）

包作者可以把根 `.h.ct` 的 C 兼容 `pub` 函数做成静态库，供纯 C 工程直接链接：

```sh
ct build --lib mylib.h.ct --outdir .ctbuild
# .ctbuild/mylib.abi.h
# .ctbuild/libmylib.a
cc -I .ctbuild consumer.c .ctbuild/libmylib.a -o consumer
```

- 只有**根 `.h.ct`** 内有定义、且签名只含 C 标量 / `void` / 指针 / 数组参数（decay）/ 函数指针的 `pub` 函数进入导出面；按值 struct、trait 值、`Vec`/`Map`/`Option`/`Result`/`Str`、`own` 一律硬错。
- 泛型模板不导出，给 `L39-1w`；根单元内的 `main`、`pub` 全局、带 C shim 的 `.m.ct` 分别 `L39-3/4/5`；被 import 单元的 `pub` 只给 `L39-6` 汇总，不进 ABI。
- 归档里还会出现 `Str_*`、vtable 等**内部符号**；`nm -g` 面 ⊋ 导出面，**只有 `.abi.h` 的声明是 ABI**。不要把 `nm` 输出当公开契约。
- 非 `pub` 顶层函数/全局在 `--lib` 下是 `static`；导出定义是 `visibility("default")`，其余以 `-fvisibility=hidden` 编译。
- 不做按值 struct / `pub` 全局 / 泛型函数 / dylib / MSVC；这些是 T39-1–T39-3 的开放项（见 [phase39 卡](design/phase39-draft.md) §7）。

### 6. 许可证

- 官方纯 `.ct` 包：**MIT**。
- C 库映射包：沿用上游许可证，并在 `ct.pkg` 的 `licence` 标注。
- 每个包必须有 `LICENSE` 文件；`licence` 键只是约定，工具不校验文件内容。

### 7. 常见失败

| 现象 | 原因 | 处置 |
| --- | --- | --- |
| `cannot read '<dir>/ct.pkg'` | 缺清单，或 `name` / `version` 为空 | 补键；值不能为空白 |
| `... does not satisfy '<range>'` | 版本不在范围内 | 改 `dep` 范围或发新版 |
| `no tag of '<name>' satisfies '<range>'` | git 源没有匹配 tag | 打 `v<version>` tag |
| `digest ... does not match ct.lock` | `vendor/` 被改动或锁过期 | 重新 `ct get` / `ct update` |
| `requires 'ct >= …'` 报错 | 编译器版本偏旧 | 升级编译器；确需继续时用 `ct get --force` / `ct install --force` |
| 索引读不到 | `--index` / `CT_INDEX` 路径错 | 检查路径；无索引时裸名无法解析 |

### 8. 现状契约与陷阱（改契约前必读）

> 本节记录 **`ct v0.53.x` 的真实行为**，不是目标设计。目标机制（`publisher` / `ns-root` / 共享库）见
> [提案](proposals/ct-pkg-shared-store.md)、[需求定稿](planning/ct-pkg-shared-store-requirements.md) 与
> [Phase 54 卡](design/phase54.md)；那是一次**契约变更**，不是增量字段。

#### 8.1 包根即单元根，不支持嵌套

- 包仓库根 = 包根 = 单元树根：`ct.pkg`、`LICENSE` 与 `*.h.ct` / `*.m.ct` 并列。
- `import a::b::U` 在 `-I <包根>` 下按 `<包根>/a/b/U.h.ct` 查找；目录名必须与命名空间首段一致。
- **没有** `ns-root` 键，也没有任何「单元树在子目录」的官方形态。

#### 8.2 `src/<ns>/` 布局在当前机制下不可消费

包把单元放在 `src/fsguard/FsGuard.h.ct`，消费者照抄 `ct install` 的输出：

```sh
ct install          # ct build -I vendor/fsguard main.ct -o build
ct build -I vendor/fsguard main.ct -o build
# ctc: cannot resolve import 'fsguard/FsGuard'
# rc=1
```

即使消费者自己改成 `-I vendor/fsguard/src`，如果单元的 C 头路径写成 `#include "fsguard/X.shim.h"`，
还需要 `-Isrc`；而 `ct.pkg` 的 `cflags` 只进 `cc` 行、不参与 import 解析。真实案例见
[PKG-2](../issues/packages/pkg-2-ct-install-package-root-import.md)。

#### 8.3 `ct install` 只发 `-I <包根>`，且不校验 import

- 生成点固定为 `-I vendor/<name>`（[Pkg.h.ct:1388-1396](../selfhost/ct-ast/tool/pkg/Pkg.h.ct#L1388-L1396)）。
- 它只做三件事：校验 `ct.lock` 摘要、校验 `dep` 被 lock 覆盖、拼 `cflags`/`ldflags`。
- **不解析 import**：包内单元找不到时它照样 `rc=0`。`ct install` 退出码 0 ≠ 消费者能编译。

#### 8.4 `ct.pkg` 的真实键，以及 `namespace` 与 `ns-root` 的区别

现行键只有 §2 表里那七个（`name` / `version` / `dep` / `cflags` / `ldflags` / `requires` / `licence`）。

- **不存在 `ns-root`**。写了不会报错，也不会生效——未知键被静默忽略。
- 实际生效的是未文档化的 **`namespace = <首段>`**：编译器在 `-I` 根下读 `<根>/ct.pkg`，
  若 import 路径以 `namespace` 值开头，就**剥掉这段**再找文件（`Module.h.ct` `ct_rel_cands`）。
- 两者语义相反：`namespace` 是「把 import 首段拿掉」，`ns-root` 是「给根目录加一层前缀」。
  把 `namespace` 当 `ns-root` 写，表现是「文件明明在，却解析不到」。
- 单元格级目录校验仍靠 `ct build --ns-root <dir>`：它校验「声明 namespace = 目录路径」，与包清单的键无关。

#### 8.5 依赖解析的现状

- 缓存键是**裸包名**（`~/.cache/ct-pkg/<name>`）；spec 的发布方段被丢弃，两个发布方的同名包会互相串用缓存。
- 依赖图内同名包**静默取首个**，无警告、无错误；只有版本范围对不上时 `ct install` 才报「未被 lock 覆盖」。
- `ct build` **不读 `ct.lock`**：删掉 lock 只要 `-I` 对就仍能构建。
- 本地目录与 `-I` 同名时，**导入方所在目录静默胜出**，不告警；`ct get` 也不会因为你项目里已有同名目录而跳过下载。
- 逐条缺陷见 [PKG-3 … PKG-8](../issues/packages/pkg-3-unknown-keys-silently-ignored.md)。

