# 包作者指南

> 中文
>
> 状态：v1（Phase 18.1 初稿，2026-11-02；2026-11-21 按 v0.88.1 复核）。工具实现见
> [`selfhost/ct-ast/tool/pkg/`](../selfhost/ct-ast/tool/pkg/)；binding 写法见
> [test/bindings/README.md](../test/bindings/README.md)；首批官方包见
> [phase18.md](history/design/phase18.md) 的 18.3–18.5。

---

## 中文

### 0. 三个角色：消费者 / 发布者 / 索引

| 角色 | 你是谁 | 入口 | 不该做的事 |
| --- | --- | --- | --- |
| 消费者 | 用别人的包 | `ct get` + `ct build`（`ct install` / `ct verify` / `ct update` / `ct migrate` 辅助） | 不把包源码复制进项目；不假设裸名能解析第三方 |
| 发布者 | 发布自己的包 | 本文件：`ct.pkg` + `ns-root` + 目录布局；发布脚本在 `ct-pkg/index` 仓的 `tools/package.sh` | 不自造清单键；不把 token 带进 `ct` |
| 索引维护者 | 让包可被 `ct get <pub>/<name>` 解析 | `ct-pkg/index` 仓的索引生成器与 CI | 不在客户端扫描组织；不手改生成物 |

三者职责与当前可解析范围见 [ct-pkg](ct-pkg.md)；索引字段与信任边界见 [ct-pkg-index](ct-pkg-index.md)。

### 1. 一个包长什么样

> 包仓的发布、tag、release dispatch、digest 与索引接入规则（提案，待目标组受理）：
> [ct-pkg-package-maintainer-rules.md](proposals/ct-pkg-package-maintainer-rules.md)。

包仓库的**根目录是包根**：`ct.pkg` 放在根，源码单元放在清单
`ns-root` 指定的子目录（`ns-root = .` 时单元与 `ct.pkg` 并列）。消费者拿到的 `-I` 是
`<store>/<publisher>/<name>/<version>/<ns-root>`，不再假设「包根 = 单元根」。

```
hello/
├── ct.pkg          # 清单（唯一由工具强制的文件）
├── LICENSE         # 可选；工具不校验
└── src/            # ns-root，可换成别的相对目录或 .
    └── hello.h.ct  # 源码单元，可多个
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

### 2. `ct.pkg` 的键

行式清单：`key = value`，`#` 起注释，`dep` 可重复，未知键**忽略**（向前兼容）。

| 键 | 必填 | 含义 |
| --- | --- | --- |
| `name` | 是 | 包名，见 §3 |
| `publisher` | S1 起是 | 发布方；与 `name` 组成 `<publisher>/<name>`，store 路径的第一段；`local` 保留字 |
| `ns-root` | S1 起是 | 包内单元树根（相对包根，无 `..`，目录必须存在）；`-I` 指向 `<版本目录>/<ns-root>` |
| `version` | 是 | `x.y.z`（工具只解析前三位数字；预发布 / 构建元数据不纳入） |
| `dep` | 否，可重复 | 依赖，`name` 或 `name@range`；格式与 Phase 8 一致 |
| `c-boundary` | 否 | `strict` \| `allow`：本包单元的 C 边界策略。缺省按外部 `strict`；**有 manifest 但缺这个键**的旧包保留 `allow` 窗口 |
| `leaks` | 否 | `warn` \| `error`：本包泄漏诊断与 `box<X>` 字段直接环告警的级别（v0.82.0，D-012）。缺省 `warn`；`error` 让 `ct build` / `ct compile` 失败；与 `c-boundary` 无关 |
| `cflags` | 否 | 消费者编译该包时附加的编译选项，`ct install` 折进打印的命令 |
| `ldflags` | 否 | 链接选项（如 C 映射包的 `-lm`），同上 |
| `requires` | 否 | 对编译器版本的约束；**不满足时 `ct get` / `ct install` 失败**，`--force` 才降级为告警 |
| `licence` | 否 | 许可证标识（SPDX 风格，如 `MIT`）。**仅约定，工具不解析** |

S1 起 `publisher` + `ns-root` 是 store 与 lock v2 的必填身份；写 `ns-root` 不再被静默忽略。
**S7 后**：`publisher` / `ns-root` 是必填身份；缺失直接失败，不再退回 `vendor/`；
只缺一个、或 `publisher = local`、`ns-root` 为绝对路径/含 `..`/目录不存在时硬错。

包的 `.ct` 不写 `#include <stdio.h>`：`printf` 族由编译器**按直接调用补头**（语言规范 §4.67）；
需要 `syslog`/`open` 这类集合外的符号时，用 `.m.ct` 映射或在 shim 里声明。

`c-boundary` 由 `ct build` / `ct pkg check` 读取：`strict` 时包内 `.ct/.h.ct` 不得直接
`#include`、不得 `#ct-raw`/`extern`/函数式宏，唯一出口是 `<base>.shim.h`；`allow` 保持旧行为。
未写该键的旧包按 `allow` 处理，新包建议显式写 `strict`（见语言规范 §4.66）。

`leaks` 由 `ct build` / `ct compile` / `ct check` 读取（语言规范 §4.72）：`error` 时本包的
`potential leak` 诊断与 `box<X>` 字段直接环告警升为构建失败，写任何 `.c` 之前退出；缺键、
未知值与旧包保持 `warn`。它不改变 `c-boundary`，也不改 `--debug-leaks` 的语义。

`cflags` / `ldflags` / `requires` 由 `ct install` 读取；`install` 把每个包的 `cflags` / `ldflags`
拼进**一条** `ct build` 命令，遇到不满足的 `requires` 直接失败（`ct install --force` 才继续，
并把原因打到 stderr）。`requires` 也在 `ct get` 里检查，且**发生在写 `ct.lock` 之前**：不满足时本次
`get` 失败、既有 `ct.lock` 一个字节都不改（`ct get --force` 才继续并告警）。

### 3. 命名与依赖版本范围

- 包名：`[a-z0-9][a-z0-9-]*`（小写字母、数字、连字符；不以连字符开头）。
- 包内源码命名遵循 [language-spec §5.1](language-spec.md)：函数 / 方法 `snake_case` 且动作动词开头，
  类型 `PascalCase`，任何位置不用小驼峰；libc 直映射（`printf` 等）保留原名。
- `dep` 的范围沿用 Phase 8 子集：`^x.y.z`、`~x.y.z`、`>=` / `>` / `<` / `<=` / `=`、裸版本（精确）
  或 `*`，多个条件用空格表示 AND。省略 range 或写 `*` 时取最新版本；显式范围用
MVS（取满足范围的最低版本）。

### 4. 消费

官方包的身份是 `publisher = ct`，规范名 `ct/std`（锁行与 store 路径都是 `ct/<name>`）。`ct` 内置一张
**官方 pin 表**：编译期常量，含 `name` / `version` / `publisher` / `url` / `tag` / `sha256`，不联网、
不读可变索引；发布新官方版本时随 `ct` 版本一起更新。因此干净 HOME、没有索引也能 `ct get ct/std`。

解析优先级（[D-010](decisions/D-010.md)）：

| 输入 | 解析 |
| --- | --- |
| 裸名 `std` | 只查内置 pin 表；其他裸名**硬错**并提示 `<publisher>/<name>` |
| `ct/<name>` | pin 表；显式 `--index` / `CT_INDEX` 命中 `publisher = ct` 行时以索引为准 |
| `<pub>/<name>` | 必须索引 / URL / 本地目录；索引缺失即硬错，提示限定名写法 |
| 显式 URL / 本地目录 | 直连，行为不变 |

第三方包必须写 `publisher/<name>`，同名也不例外；`CT_REGISTRY` 不再是裸名的回落路径。
索引是纯文本、空白分隔的六字段行：

```
name version publisher git-url tag sha256:<64 hex>
```

五字段旧行（`name version git-url tag sha256:<hex>`，无 `publisher`）**按行硬错**：请求命中即失败并
提示六字段，索引里其余六字段行不受影响（契约 v1，[D-014](decisions/D-014.md) 第 5 条）；
生成端已停止产出。字段与信任模型见 [ct-pkg-index](ct-pkg-index.md)。

摘要按 `ct.lock` 的同一算法计算（按路径排序后把每个文件的相对路径与内容汇入单流 SHA-256）。
本地可用 `CT_INDEX=<file>` 或 `--index <file>` 指向任意纯文本索引。消费端与发布端（`package.sh`）
的完整契约见 [ct-pkg-get-contract](planning/ct-pkg-get-contract.md)。

#### 4.1 信任模型：官方 pin 强校验，第三方索引仅便利

| 层 | 信任来源 | 校验 | 失败行为 |
| --- | --- | --- | --- |
| 官方 `ct/<name>`、裸名 | 编译期 **pin 表**（`name` / `version` / `publisher` / `url` / `tag` / `sha256`）；显式 `--index` / `CT_INDEX` 的 `publisher = ct` 行可覆盖 pin（用户显式选择） | 按 pin（或覆盖它的索引行）的 tag 取内容，再按 `ct.lock` 同一算法比对 `sha256`；默认不读可变索引 | 摘要或身份不符即硬错，不落 store、不写锁 |
| 第三方 `<pub>/<name>` | 调用方显式给出的索引 / URL / 本地目录 | 索引行的 `tag` + `sha256` 与拉到的内容比对；索引本身**无签名** | 索引不可读、缺行或摘要不符即硬错；不因缺索引回落到裸名 |

- **pin 是强校验**：官方版本、tag、摘要都编译进 `ct` 二进制。索引被替换或网络被劫持时，摘要不符仍然失败。
  显式索引命中 `publisher = ct` 时以该索引为准——那是用户主动的信任转移，不是默认回落路径。
- **第三方索引只是便利**：它集中 `name → url/tag/sha256` 的映射，不提供发布方身份签名。信任边界是
  「你选择的索引文件 + 你显式写的 `<publisher>/<name>`」；要更强保证，用显式 URL，并让 `ct.lock` 钉住摘要。

```sh
ct get ct/std@0.19.0         # 官方包：内置 pin 表，无索引可用
ct get --refresh std          # 丢弃 git 缓存并重新 fetch（缓存损坏时）
ct get <pub>/<name>@<range>  # 第三方：发布方限定 + --index/CT_INDEX
ct get ./path                # 本地目录同样按清单的 publisher/ns-root 落 store
ct verify [--strict]         # 离线：v2 校验 store、v1 校验 vendor；--strict 拒绝 dir/v1
ct install                   # 离线：校验摘要与依赖覆盖，打印带 store ns-root 的 ct build 命令
ct migrate                   # 离线：把 vendor/ 搬进 store，重写 v2 lock（保留版本/发布方）
ct update                    # 离线：v2 校验 store 并保留钉住的版本；迁移旧 std/std 身份
ct index verify ./index      # 只读：逐行校验索引；不联网、不写 store/lock
ct index verify ./index --json   # 同一判定，CI 可解析（退出码 0/1/2）
```

索引行是 **六字段** `name version publisher git-url tag sha256:<64 lowercase hex>`。
**五字段旧行按行硬错**（[D-014](decisions/D-014.md) 第 5 条）：`ct get` 的请求解析命中旧行即失败
（`index row for '<spec> <version>' is legacy (five fields); a six-field row is required`），
同一文件里的六字段行照常可用；`ct index verify` 扫描整份索引，逐行给出行号与类别
（`legacy-five-field` / `field-count` / `identity` / `tag-version` / `digest` / `duplicate`）。
发布前置：index 仓先清零旧行，再发带硬错的 `ct`。

`ct update` 遇到旧官方身份 `std/std` 时解析 pin 目标、改写为 `ct/std <new>`，打印
`migrate std/std <old> -> ct/std <new>`，旧 store 只读保留；`ct verify` 对旧身份只告警
`legacy publisher 'std'`，不判失败。`ct install` / `ct build` 永不重写锁。

`ct verify` 只做摘要校验，**不读 `ct.pkg`**；清单里的 `dep` 是否被 `ct.lock` 覆盖由 `ct install` 判定
（缺依赖时报 `dependency '<spec>' is not satisfied by ct.lock`）。
`ct get` 默认逐包打印 `requested`、`resolved`、`source`（单个 `url@<包版本>`）、`tag`、
`commit`、`store`、`digest` 与 `action`；`-q` / `--quiet` 每包一行 `name version url@version`；
`--json` 输出 `requested`、`packages[]`、`summary`，每个包另有 `"spec":"<url>@<version>"`。

`ct get` 一次只解析一个 spec，但会保留 `ct.lock` 中本次没有重解的其它行；重复 get 同一个包只替换
该包的行，不会重复。这样再 get 一个新包不会把先前钉住的版本弄丢，随后的 `ct update` 仍按锁里的
commit 解析。
`ct get` 可用 git——它是**包管理路径**里唯一的子进程调用点；`ct update` / `ct verify` / `ct install`
零网络、零子进程。编译器侧 `ct compile` / `ct build --emit-c` 零网络、零子进程，但 `ct build`
的默认形态会经 `$CC` 派生子进程去链接（`--cc` > `$CC` > `cc`）。

**git 失败可诊断、可恢复（PKG-23）。** `git clone` / `git fetch` / `git checkout` 失败时，
`ct get` 先打印 `ctc: git fetch of '<url>' failed`（clone/checkout 同理），再给最后 8 行 git
stderr（脱敏：URL 的 userinfo 换成 `***`），然后归类并给动作：
`network/proxy unreachable`（重试、查 `https_proxy`/`ALL_PROXY` 与 DNS）、
`authentication/permission denied`（查凭据/SSH key；git 不交互，`GIT_TERMINAL_PROMPT=0`）、
`remote tag/object missing`（pin/tag 不在远端，核对 pin/tag 或发布它）、
`package cache is corrupt`（给缓存路径与 `rm -rf '<cache>'`，或 `ct get --refresh <spec>`）、
未分类兜底。`--refresh` 只在该次调用里丢弃缓存并重新 clone，正常缓存不受影响；成功路径与 v2
锁行不变。失败仍发生在写 `ct.lock` 之前，旧锁保持逐字节不变（不会留下半行）。git 子进程已有
有界超时（`CT_GIT_TIMEOUT`，默认 180s；另有 `http.lowSpeedTime=60`）与 `GIT_TERMINAL_PROMPT=0`
（CI-9）；探针外层仍建议再加一层 `timeout`。

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
- `ref` / `out` 形参在 C ABI 里就是普通指针：`pub int bump(ref int x)` 发射为
  `int bump(int *);`，C 消费者直接传 `&value`。`out` 的“调用方初始化 / 每条路径赋值”
  是 CT 源层检查，C 侧只能看到 `T *`，无法从 ABI 头区分 `ref` 与 `out`；契约由包文档
  与函数注释承担。
- 归档里还会出现 `Str_*`、vtable 等**内部符号**；`nm -g` 面 ⊋ 导出面，**只有 `.abi.h` 的声明是 ABI**。不要把 `nm` 输出当公开契约。
- `box<T>`（PH-81）是编译器生成的 nominal 句柄，不是 C ABI 类型：导出面只允许 C 标量 /
  `void` / 指针 / 数组参数 / 函数指针，按值 `box<T>` 与按值 struct 一样被拒。C 消费者看到
  的是 `T *` / 普通 struct；句柄 16 字节、8 字节头是 CT 内部布局（golden 断言），不承诺
  跨编译器 ABI。`ct build` 跨单元 `box<T>` 在 v0.81.0 不支持，导出签名里不要写 `box<T>`。
- 非 `pub` 顶层函数/全局在 `--lib` 下是 `static`；导出定义是 `visibility("default")`，其余以 `-fvisibility=hidden` 编译。
- 不做按值 struct / `pub` 全局 / 泛型函数 / dylib / MSVC；这些是 T39-1–T39-3 的开放项（见 [phase39 卡](history/design/phase39.md) §7）。

### 6. 常见失败

| 现象 | 原因 | 处置 |
| --- | --- | --- |
| `cannot read '<dir>/ct.pkg'` | 缺清单，或 `name` / `version` 为空 | 补键；值不能为空白 |
| `... does not satisfy '<range>'` | 版本不在范围内 | 改 `dep` 范围或发新版 |
| `no tag of '<name>' satisfies '<range>'` | git 源没有匹配 tag | 归包仓处理；本仓不复述发布步骤 |
| `digest ... does not match ct.lock` | `vendor/` 被改动或锁过期 | 重新 `ct get` / `ct update` |
| `requires 'ct >= …'` 报错 | 编译器版本偏旧 | 升级编译器；确需继续时用 `ct get --force` / `ct install --force` |
| 索引读不到 | `--index` / `CT_INDEX` 路径错 | 检查路径；无索引时裸名无法解析 |
| `git fetch ... failed` + `network/proxy unreachable` | 网络、DNS 或代理不可达 | 重试；检查 `https_proxy` / `ALL_PROXY` / DNS；`CT_GIT_TIMEOUT` 可调超时 |
| `... authentication/permission denied` | 凭据、token 或 SSH key 不可用 | 换有效凭据；git 以 `GIT_TERMINAL_PROMPT=0` 运行，不会弹窗 |
| `... remote tag/object missing` | 远端没有 pin 的 tag/对象 | 核对 pin/tag 或先发布该 tag；显式版本用 `ct get ct/std@0.19.0` |
| `... package cache is corrupt` | 缓存 `.git` 损坏或 origin 不符 | `rm -rf '<cache>'` 后重试，或 `ct get --refresh <spec>` |

### 7. 现状契约与陷阱（改契约前必读）

> 本节记录 **`ct v0.88.1` 的真实行为**（2026-11-21 复核）。机制来源见
> [提案](proposals/ct-pkg-shared-store.md) 与 [需求定稿](planning/ct-pkg-shared-store-requirements.md)；
> 早期版本的差异只在 §8 的兼容期成立。

#### 7.1 `ns-root` 取代「包根 = 单元根」

- 包根仍是仓库根（放 `ct.pkg`），单元树根由 `ns-root` 声明；`ns-root` 必须是相对
  包根、不含 `..`、目录存在。
- `import a::b::U` 在 `-I <store>/<pkg>/<ver>/<ns-root>` 下按 `<ns-root>/a/b/U.h.ct` 查找；
  目录名仍须与命名空间首段一致。
- 旧的「包根 = 单元根」只在 §8 的兼容期成立，不再是新包的契约。

#### 7.2 单元在 `src/` 的包现在可直接消费

例如 `ns-root = src` 的 fsguard，`ct get` 后 `ct build` 自动补 store 的 `-I …/src`，消费者不再
手写 include root；`ct install` 打印的也是这个目录。旧工程若仍把单元放在包根，只在 §8 的 v1
兼容路径下工作。

#### 7.3 `ct install` 的 `-I` 形态，且不校验 import

- v2 lock：`-I $CT_HOME/pkg/<publisher>/<name>/<version>/<ns-root>`（`ns-root = .` 时省掉末段）。
- 它只做三件事：校验 store 摘要、校验 `dep` 被 lock 覆盖、拼 `cflags`/`ldflags`。
- **不解析 import**：包内单元找不到时它照样 `rc=0`。`ct install` 退出码 0 ≠ 消费者能编译。

#### 7.4 `namespace` 与 `ns-root`

- S1 起 `ns-root` 是清单的必填键：store 的 `-I` 指向 `<版本目录>/<ns-root>`，`ct pkg check` 校验
  相对路径、无 `..`、目录存在。
- 旧的 **`namespace = <首段>`** 仍被编译器读取（`Module.h.ct` `ct_rel_cands`），作为兼容键保留；
  新包不要再写它，两者语义相反：`namespace` 剥掉 import 首段，`ns-root` 给根目录加一层前缀。
- `ct build --ns-root <dir>` 仍是独立的单元格级目录校验，与清单键无关。

#### 7.5 共享库与构建（S1/S2）

- store：`$CT_HOME/pkg/<publisher>/<name>/<version>/`（`CT_HOME` 默认 `$HOME/.ct`）；同版本重装
  摘要相同即 no-op、不同即硬错且不覆盖；不同版本目录可并存。
- v2 lock 每行七字段 `<pub>/<name> <version> <type> <locator> <commit|-> <ns-root> <sha256:…>`；
  S7 后不再写 `vendor/`；旧工程迁移见 §8。
- **`ct build` 默认读 `./ct.lock`**：v2 git 行自动补 `-I $CT_HOME/pkg/<pkg>/<ver>/<ns-root>`，
  v2 `dir` 行使用本地路径并在 stderr 打 `note: '<pkg>' resolves to the local directory (dev override)`。
  用户显式 `-I` 仍然有效且排在前面；重复根由既有导入规则去重。
- `ct build --locked`：store 缺失报 `is not installed`、摘要不符报 `does not match ct.lock`，不回退；
  无 lock 或 v1 lock 也直接失败。
- 无 `ct.lock` 时不再回退 `vendor/`；旧工程先 `ct migrate`，见 §8。
- lock 内同一裸包名出现两行（不论发布方）→ `package '<name>' is required twice: a/<name> and b/<name>`。
- `ct verify`：v2 行检查版本目录存在与第 7 字段摘要；缺失报 `is not installed`、不符报
  `does not match ct.lock`。`--strict` 拒绝任何 `dir` 行或 v1 lock。
- `ct migrate`：读 v1 lock 与 `vendor/<name>`，把每棵树写入 store（摘要必须与 lock 一致），
  重写为七字段 v2 lock；随后 `mv vendor /tmp/v && ct build main.ct -o build` 不再需要 vendor。
  迁移行是 store-backed 的 `git - -`（v1 未记录 URL；commit 若存在则保留）。
- `ct update` 对 v2 是**离线 pin 审计**：校验 store、要求 `ct.pkg` 的每个直接依赖都被 lock 覆盖，
  把钉住的 v2 行原样写回；不会在无网络时凭空选择新版本。缺依赖报 `is not satisfied by ct.lock`。
- 边界：包仓的 `publisher` / `ns-root` / tag 声明归各包仓，不属于本仓任何 phase。
  S7 已删除 vendor 路径；缓存键仍按裸包名（PKG-5）。
- 逐条缺陷见 [PKG-3 … PKG-8](../issues/packages/pkg-3-unknown-keys-silently-ignored.md)。

#### 7.6 切片 `T[]` 不进包边界（PH-79）

切片是 `{ptr,len}` 借用视图，只允许出现在参数、局部变量、表达式临时量与返回值；**不能**作
struct 字段、全局、接口值、`box<T>`、`Option`/`Result`、容器元素、泛型实参或闭包捕获，
因此也不会出现在 `--lib` 的 ABI 头里。跨包传只读数据请传 `String`/`Str`（PH-80）或：
C 边界用 `(const T *data, size_t len)`；包内调用直接传 `T[]`，由调用方保证底层存活。
`T a[]` 形参/无初始化器声明已告警（v1 硬错），新代码写 `T[]`（视图）或 `T a[N]`（数组）。

### 8. v1 迁移：`ct migrate`

S7 已删除 `vendor/` 读写；v1 lock 与无 lock 的 vendor 工程不再构建。唯一保留的桥是
`ct migrate`：它读取旧 `vendor/<name>` 树，校验摘要后写入共享 store，并把 `ct.lock` 重写为 v2。

```sh
ct migrate                  # 读取 v1 + vendor/，写入 store 与 v2 lock
mv vendor /tmp/v            # 迁移后可移走
ct build main.ct -o build   # 从 store 取包
```

迁移失败（缺 `publisher` / `ns-root`、摘要不符、vendor 缺项）时 `ct migrate` 返回非零，
不会把旧目录当成成功。v1 lock 的 `ct build` / `install` / `verify` / `update` 都直接报错并提示
`run 'ct migrate'`；`ct get` 也拒绝在 v1 lock 上追加 v2 行。
