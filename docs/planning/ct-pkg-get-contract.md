# `ct get` × `package.sh` 契约（消费端 / 发布端）

| 项 | 值 |
| --- | --- |
| 性质 | 跨仓契约（需求与计划）；不占 phase |
| 契约版本 | **v1（2026-11-20）**；裁定见 [D-014](../decisions/D-014.md)，评估见 [提案评估](../reviews/2026-11-20-pkg-contract-proposal-eval.md) |
| 日期 | 初稿 2026-11-19；v1 修订 2026-11-20 |
| 适用 | ct-lang 的 `ct get` / `ct install` / `ct update` / `ct verify` / `ct.lock`；ct-pkg/index 的 `tools/package.sh` / `refresh-index.sh` / `verify-index.sh` / `index` / `repos.txt` |
| 不适用 | 包内 API、构建系统、索引 CI 的具体实现细节 |
| 关联 | [PH-77](../design/phase77.md)、[包指南](../package-guide.md)、[发布规则提案](../proposals/ct-pkg-package-maintainer-rules.md)、[battle index-pkg-1](../../battle/index-pkg-1/verdict.md)、[battle index-install-1](../../battle/index-install-1/verdict.md) |

## 0. 一句话

**发布端只写「可被 `ct get` 复现的制品」，消费端只读制品、不执行发布脚本。**
两边共享的契约只有四处：`ct.pkg` 清单、六字段索引行、`sha256` 包树摘要、`ct.lock` v2。

## 1. 事实核对（先读）

| 项 | 当前事实 |
| --- | --- |
| `ct pkg` 是什么 | `ct install` 的别名（[main.ct:121-122](../../selfhost/ct-ast/main.ct#L121-L122)）；`ct pkg check <dir>` 是原生只读检查（[Pkg.h.ct:1742-1765](../../selfhost/ct-ast/tool/pkg/Pkg.h.ct#L1742-L1765)） |
| `ct pkg` 是否透传 `package.sh` | **否**。`ct` 不执行 index 仓脚本；包管理路径只有 `git` 一个子进程调用点 |
| 已有裁决 | [battle index-pkg-1](../../battle/index-pkg-1/verdict.md)（closed）：`ct pkg` 保持 `install` 别名 + 原生 `check`，**不**把参数透传给 `package.sh`；发布留在 index 仓 |
| `package.sh` 在哪 | `ct-pkg/index` 仓 `tools/package.sh`（`check` / `publish` / `release`），需要 `GITHUB_TOKEN` 或 `GH_TOKEN` |
| `ct get` 是否依赖 `package.sh` | 否。`ct get` 只读索引行与包树，自己算摘要、写 store 与 lock |
| 需求方 2026-11-19 定稿 | `ct pkg` **保持 B′**（`install` 别名 + 原生 `check`，不透传）；`ct get` 由 `ct` 自行处理。§5.2 的透传方案不采纳 |

> `ct pkg` 边界已于 2026-11-19 定稿：保持 B′。§5.2 仅作历史备选与复开条件，不是现行契约。

## 2. 契约不变量

| ID | 不变量 | 违约表现 |
| --- | --- | --- |
| I1 | 包的唯一权威来源是 tag 指向的 `ct.pkg` 与包树；索引行是派生数据 | 改索引行不改包树、或手改 digest |
| I2 | 身份是 `<publisher>/<name>`；`publisher` 不能是 `local`，同一包跨版本不得换 publisher | store 分裂、锁名漂移 |
| I3 | `ns-root` 是相对路径、存在、无 `..`、非绝对路径 | `ct build` 找不到单元或越界 |
| I4 | `version` 是 `x.y.z`，tag 必须是 `v<version>`，发布后 tag 不可移动 | 同版本不同内容、摘要漂移 |
| I5 | 索引行六字段；新行缺 `publisher`/`ns-root` 不得写入 | 消费者安装时才失败 |
| I6 | `sha256` 是包树摘要（按相对路径排序，逐文件写入「路径 + 换行 + 内容」的单流 SHA-256；跳过 `.git`/`vendor`/`.ctcache`） | 两端算法不一致，永远装不上 |
| I7 | 消费者在写 store / lock 前**重新计算**摘要并与索引行比对，不一致硬错 | 装到被篡改的树 |
| I8 | `ct.lock` v2 每行七字段；第一字段必须是 `publisher/name` | 发布端回放校验失败、离线不可复现 |
| I9 | `ct get` 不执行包内代码、不读取 token；索引视为不可信输入 | 供应链/凭据风险 |
| I10 | 发布端在推送索引前，必须用真实 `ct get --index` 在隔离 `HOME`/`CT_HOME` 回放新行并比对摘要 | 写入无人能装的行 |
| I11 | 失败原子性：发布失败不改索引；消费失败不改 lock/store（`requires` 失败也不改既有 lock） | 半成品状态 |
| I12 | 格式变更必须两端协同发布，并用全量 `verify-index` 回归；五字段旧行**按行硬错**（D-014 第 5 条；不再只读兼容） | 新旧消费者分裂 |
| I13 | 同一时刻只有一个索引：`--index` > `CT_INDEX` > 已存在的 `$CT_HOME/index/index`；不承诺多索引并存（D-014 第 4 条） | 解析顺序歧义、同一包多源 |

## 3. 共享制品

### 3.1 `ct.pkg`（包清单）

| 键 | 契约 |
| --- | --- |
| `name` | 小写字母/数字/连字符，不以连字符开头；等于索引行第 1 字段 |
| `publisher` | 必填，非 `local`，不含 `/`；与 `name` 组成规范名；跨版本稳定 |
| `ns-root` | 必填，相对包根、存在、无 `..`；消费者的 `-I` 指向 `<store>/<version>/<ns-root>` |
| `version` | 必填，`x.y.z`；等于 tag 去掉 `v` |
| `dep` | 可选、可重复；范围语法见 [package-guide §3](../package-guide.md#3-命名与依赖版本范围) |
| `c-boundary` | 可选，`strict` / `allow`；缺省按外部包 `strict`，旧包保留 `allow` 窗口 |
| `cflags` / `ldflags` | 可选；只放消费者需要的内容，不得含本机绝对路径 |
| `requires` | 可选；不满足时 `ct get` / `ct install` 失败，`--force` 才降级为告警 |
| `licence` | 可选；仅约定，工具不解析 |

### 3.2 索引行

```text
name version publisher git-url tag sha256:<64 lowercase hex>
```

- 只由 index 仓生成器写入；包仓不得直接改 `index`；
- 同一 `name version` 的摘要不可变；tag 移动必须报错而不是静默换行；
- 同一包跨版本不得混用 publisher；最新 tag 的身份定义该包的 publisher；
- **五字段旧行按行硬错**（D-014 第 5 条）：请求的 spec 命中五字段行时直接失败，并提示
  `six-field index row required`；索引中其余六字段行不受影响；`ct index verify` 则扫描整份索引，
  逐行报出所有旧行（§4.4）；
- **发布前置**：index 仓必须先把五字段行清零，再发布带硬错的 `ct` 版本；否则 `ct/hal`
  等存量包会立即不可安装。

### 3.3 包树摘要（digest）

**算法（与 `dir_digest` 一致）**

```text
collect(root):
    rows = []
    walk(root):
        for each entry:
            skip dirs named .git, vendor, .ctcache
            if regular file: rows.push(relative_path with '/' separators)
    sort rows by byte-wise ascending order      # strcmp, not locale
    h = SHA-256()
    for r in rows:
        h.update(bytes(r)); h.update(b'\n'); h.update(bytes(file(root, r)))
    return "sha256:" + lowercase_hex(h.digest())
```

- 只收**普通文件**；目录本身、空目录、文件元数据（权限/时间戳）不进入摘要；
- 路径是相对包根的 `/` 分隔串；排序用字节序，不依赖文件系统 `readdir` 顺序；
- 文件之间没有额外分隔符：`路径 + 换行 + 内容` 连续写入同一 SHA-256 流；
- 嵌入式 `\0` 按普通字节参与摘要。

**测试向量**（2026-11-21 用 `ct get <local-dir>` 与独立 Python 实现实测，两者逐字节一致）

向量 1（基础）。文件字节：`ct.pkg` 四行、`src/demo.h.ct` 一行，均以单个 LF 结尾。

```text
ct.pkg:
name = demo
publisher = acme
version = 0.1.0
ns-root = src

src/demo.h.ct:
pub int f(void) { return 1; }

digest = sha256:4da5a4052a2a0afc6c9bbc7cc33cb153755f6f9e77a6efcb46f664aa17d00000
```

向量 2（递归 + 排除项）。`ct.pkg` 与向量 1 逐字节相同；两个源文件各一行、以 LF 结尾；
`.git/y`、`vendor/x`、`.ctcache/z` 内容任意，均不参与摘要。

```text
ct.pkg:                 同向量 1
src/a/b.ct:             pub int b(void) { return 2; }
src/z.h.ct:             pub int z(void) { return 3; }
不参与：                .git/y, vendor/x, .ctcache/z

digest = sha256:96c10e74b90d104fb9e789aec2d05189dd090ae1a96a1f739aa74aeaf83986a1
```

向量 3（字节序排序 + 嵌入 NUL）。`ct.pkg` 的 `ns-root = .`（其余三行同向量 1，以 LF 结尾）；
`nul.bin` 是 4 个字节、**不带**结尾 LF，嵌入一个 `\0`。

```text
ct.pkg:
name = demo
publisher = acme
version = 0.1.0
ns-root = .

a-file   = "abc\n"                  (4 bytes)
a/file   = "XYZ\n"                  (4 bytes)
nul.bin  = "nu\0l"                  (4 bytes, no trailing LF)

参与摘要（字节序排序后）：a-file, a/file, ct.pkg, nul.bin
digest = sha256:41743c2b7ecea992d7c1135e3fc78d2c0e020731a1199c85c0ef6308a2b7e888
```

> 三个向量同时充当 conformance 的摘要基准（[PKG-15](../../issues/packages/pkg-15-conformance-suite.md)，
> 数据在 `test/conformance/pkg/v1/digest/`）；改动算法必须同时更新本节与 conformance 数据。
> **v1.1 变更**：v1 文本只写了向量 2/3 的部分输入，无法复现，故本轮补全字节并重新实测；
> 向量 1 与原值一致。

### 3.4 `ct.lock` v2

```text
<publisher>/<name> <version> <type> <locator> <commit|-> <ns-root> <sha256:…>
```

- 消费者本地状态，不由发布端写入；
- `ct build` 默认读取，自动补 store 的 `-I`；
- `ct update` / `ct verify` / `ct install` 离线，不联网、不跑 git；
- v1 lock 只能经 `ct migrate` 进入 v2。

## 4. 命令契约

### 4.1 `ct get`（消费端，ct-lang 负责）

| 项 | 契约 |
| --- | --- |
| 输入 | 裸名、`publisher/name`、`https://…` URL、本地路径；可带 `@range` |
| 索引 | `--index <file>` > `CT_INDEX` > 已存在的 `$CT_HOME/index/index`；裸名可回落 `CT_REGISTRY` |
| 版本 | 省略 range 或 `*` 取最新；显式 range 用 MVS（最低满足版本）；无匹配硬错 |
| 歧义 | 裸名命中多个 publisher 必须硬错，并提示写 `publisher/name` |
| 摘要 | 取回后按 I6 重算；与索引行不一致则失败，不写 store、不写 lock |
| 副作用 | 写 `$CT_HOME/pkg/<publisher>/<name>/<version>/` 与 `ct.lock`；保留 lock 中本次未重解的其它行 |
| 失败 | 退出码 1；既有 `ct.lock` 不得被部分改写；`requires` 检查发生在写 lock 之前 |
| 网络 | 只有 `ct get` 走网络/git；`ct update` / `verify` / `install` 零网络、零子进程 |
| 输出 | 默认逐包 `requested`/`resolved`/`source`/`tag`/`commit`/`store`/`digest`/`action`；`-q` 一行；`--json` 结构化 |

**发布端依赖的硬接口**（不得随意改）：

1. `ct get --index <绝对路径> <publisher>/<name>@<version>` 必须成功；
2. 隔离 `HOME` / `CT_HOME` 下不得依赖已有 store；
3. `ct.lock` 第一行 v2 记录的第一字段必须等于 `<publisher>/<name>`；
4. 第 7 字段必须是索引行同一个 `sha256:…` 拼写（小写、64 位）。

### 4.1.1 spec 形态与版本选择（v1 固定）

| 形态 | 例子 | 解析 |
| --- | --- | --- |
| 裸名 | `std` | 只查内置 pin 表（官方）；第三方裸名硬错并提示 `publisher/name` |
| 限定名 | `acme/util` | 查索引；publisher 不得为 `local`，不得为官方保留 `ct` 以外冒充 |
| URL | `https://host/x.git` | 直接取；摘要按 §3.3 重算，写入 lock 的 locator |
| 本地路径 | `./pkg/`、`/abs/pkg` | 不联网；按 §3.3 算摘要，locator 写 `dir` |

- 形态只由 spec 前缀决定；`@range` 只对裸名 / 限定名有意义，URL 与本地路径不得带范围；
- 版本范围文法（与 package-guide §3 一致）：`^x.y.z`、`~x.y.z`、`>=` / `>` / `<` / `<=` / `=`、
  裸版本（精确）、`*`；多个条件用空格表示 AND；
- **选择规则**：省略 range 或 `*` → 取索引中该包的最高版本；显式 range → **MVS（取满足范围的最低版本）**；
  无匹配 → 硬错，不回退到最新；
- **索引唯一性**：同一时刻只有一个索引（I13）。若需要多来源，调用方自行把行合并成一个文件；
  `ct` 不定义“多个索引之间的优先顺序”。

**MVS 实例**（同一包在索引里有 `0.1.0`、`0.2.0`、`0.3.0`）：

| spec | 选中 | 理由 |
| --- | --- | --- |
| `acme/util` 或 `acme/util@*` | `0.3.0` | 省略范围 / `*` 取最高 |
| `acme/util@>=0.1.0` | `0.1.0` | 显式范围取**最低**满足版本，不是最高 |
| `acme/util@^0.2.0` | `0.2.0` | `0.2.x` 的最低满足版本 |
| `acme/util@~0.2.0` | `0.2.0` | `0.2.x` 的最低满足版本 |
| `acme/util@=0.2.0` | `0.2.0` | 精确版本 |
| `acme/util@>=0.4.0` | 硬错 | 无匹配；不回退到 `0.3.0` |

### 4.2 `package.sh`（发布端，ct-pkg/index 负责）

| 项 | 契约 |
| --- | --- |
| 命令 | `check [<name>…]`（只读）、`publish <name>`（建仓/推送 + 刷新索引）、`release <name> <tag>`（推送已存在的 tag + 刷新索引） |
| 环境 | `ORG`、`STAGING`、`MANIFEST`、`INDEX_DIR`、`CT_BIN`、`GITHUB_TOKEN` / `GH_TOKEN` |
| 预检 | tag 与 `ct.pkg` 版本一致；工作树干净且带该 tag；`package-check.sh`（PK-1/2/5/8 + R1–R3，`--strict` 加 S1–S5）；`check-layout.sh`；`check` 另跑 `check-char-host.sh` |
| 流水线 | 预检 → 推 main/tag → 等 tag 可见 → 重建索引 → **用 `ct get` 回放新行** → 提交/推送索引 → 同步 `repos.txt` |
| 原子性 | 任一步失败即中止；索引未推送前失败必须保持 `index` 原样；不 force push |
| 幂等 | 已存在的仓库/main/tag 跳过；同一发布重跑不产生空提交 |
| 输出 | `ok` / `..` / `warn` / `ERROR`；成功 0，失败 1，用法错误 2 |
| 凭据 | token 只在发布端环境；不得写入索引、日志或包树 |

**契约偏差（需修）**：当前 `verify_row` 在找不到 `ct` 时只 `warn` 并返回成功，
这会让「未回放」的索引行被推送，违反 I10。`publish` / `release` 应改为失败（或要求显式 `--no-verify` 并留审计记录）。

### 4.3 交界

```text
[包仓] --tag→ [package.sh 预检] --写→ [index 行] --回放→ [ct get] --比 digest→ [推送 index]
                                                        ↓
                                                   [用户工程 ct.lock]
```

- 发布端只通过命令行调用 `ct get`；不链接、不读 `ct` 内部文件；
- 消费端只读 `index` 与包树；不调用 `package.sh`、不读 `repos.txt`；
- 唯一共享可变物是 `index` 文件（发布端写、消费端读）；store 归消费者本机。

### 4.4 `ct index verify`（只读，ct-lang 负责）

```text
ct index verify [<file>] [--json] [-q]
```

- **索引解析**与 I13 同一顺序：`<file>` > `CT_INDEX` > `$CT_HOME/index/index`；都没有 → 退出码 2；
- **只读边界**：只 `fopen` 索引文件；不联网、不起子进程、不写 store、不写 `ct.lock`、不改索引；
- **输入必须是普通文件**（PKG-14）：打开前 `stat` + `S_ISREG`；目录、字符/块设备（如 `/dev/null`）、
  FIFO、socket、指向目录的 symlink → 退出码 2；FIFO 不会被打开（不挂起）。指向**普通文件**的
  symlink 按普通文件读取。三种来源（显式路径 / `CT_INDEX` / `$CT_HOME/index/index`）同规则；
- **读取错误**：`ferror` 非零 → 退出码 2；
- **`--json` 在退出 2 时同样是失败**：输出 `ok:false`，`errors` 含一条 `line:0`、`kind:"io"` 的
  记录；任何非普通文件/读错误都不会出现 `ok:true`；
- **逐行校验**（空行与 `#` 注释跳过；行号为 1 起算）：

| ID | 判据 | 失败类别 |
| --- | --- | --- |
| IV-1 | 六字段：`name version publisher git-url tag sha256:<64 lowercase hex>` | `field-count` |
| IV-2 | 恰好五字段 → 旧行，按行硬错（D-014 第 5 条） | `legacy-five-field` |
| IV-3 | `name` 匹配 `[a-z0-9][a-z0-9-]*`；`publisher` 非空、不为 `local`、不含 `/`；`version` 为 `x.y.z` | `identity` |
| IV-4 | `tag` 必须等于 `v<version>` | `tag-version` |
| IV-5 | 摘要必须是 `sha256:` + 64 位**小写**十六进制 | `digest` |
| IV-6 | 同一 `<publisher>/<name> <version>` 不得出现两次（后出现行报错） | `duplicate` |
| IV-7 | 通过 IV-1…IV-6 的行视为“可回放”：`ct get --index <file> <publisher>/<name>@<version>` 会走到取回阶段。verify **不**取回、**不**比对包树摘要（那需要网络/包树，属 §9 index 侧） | — |

- **与 `ct get` 一致**：命中五字段行时两者用同一模板
  `index row for '<spec> <version>' is legacy (five fields); a six-field row is required`。
  `ct get` 的 `<spec>` 是请求写法（限定名带 publisher，例 `acme/old`）；`ct index verify` 只能看到
  索引行，旧行没有 publisher 字段，故 `<spec>` 为裸 `name`（例 `old`），且扫描整个文件逐行报出
  所有旧行与坏行；`ct get` 只在**请求解析命中**该行时失败（其余六字段行照常）。
- **文本输出**（默认；按行号升序，一行一个坏行）：

```text
index: ./index
line 3: legacy-five-field: index row for 'acme/old 1.0.0' is legacy (five fields); a six-field row is required
line 7: digest: index digest must be sha256:<64 lowercase hex>
index verify: FAIL (2 invalid of 9 rows)
```

  成功时最后一行是 `index verify: OK (9 rows)`；`-q` 省略 `index:` 头（成功时无输出）。
- **`--json` 输出**：单行、键序固定、无时间戳/绝对化；`line` 为 1 起算的行号，
  `kind` 取上表左列，`errors` 按行号升序：

```json
{"index":"./index","ok":false,"rows":9,"valid":7,"invalid":2,"errors":[{"line":3,"kind":"legacy-five-field","message":"index row for 'acme/old 1.0.0' is legacy (five fields); a six-field row is required"},{"line":7,"kind":"digest","message":"index digest must be sha256:<64 lowercase hex>"}]}
```

- **退出码**：`0` 全部合法；`1` 存在坏行（含五字段旧行）；`2` 用法错误、索引不存在或不可读。
  JSON 模式不改变退出码；`ok` 字段只是退出码的镜像。
- **不可判定项**（明确不在本命令内）：包树摘要与 tag 内容一致性、tag 是否已推、发布凭据；
  这些由 §4.2 的发布端回放与 §9 index 侧验收负责。

## 5. `ct pkg` 命令边界（定稿：B′）

### 5.1 定稿口径（battle index-pkg-1 B′，2026-11-19 确认沿用）

- `ct pkg` = `ct install` 别名；
- `ct pkg check <dir>` = 原生只读检查（与 `package-check.sh` 的 PK-1/2/5/8 对齐）；
- 不执行 `package.sh`，不透传任意 argv；
- 发布由 index 仓 `package.sh` 或 CI 完成。

### 5.2 不采纳：透传（仅作复开条件）

透传方案已被 [battle index-pkg-1](../../battle/index-pkg-1/verdict.md) 否决，2026-11-19 需求方确认不采纳。
若未来复开，至少要求：

| ID | 条件 |
| --- | --- |
| C1 | 只透传白名单子命令（`check` / `publish` / `release`），不做任意 argv 转发 |
| C2 | 不隐式 `init`、不隐式联网；脚本路径显式（如 `--script` 或 `CT_PKG_SCRIPT`），不得假定 `$CT_HOME/index/package.sh` |
| C3 | 参数以 argv 数组传递，不经 shell 拼接；路径与名字先校验 |
| C4 | token 只从环境继承，`ct` 不读取、不打印、不落盘；子进程环境最小化 |
| C5 | 退出码与信号透传；失败不吞输出 |
| C6 | 解决 `ct pkg check` 冲突：要么保留原生 `check` 并把脚本入口改名（如 `ct pkg tool check`），要么明确废弃原生入口 |
| C7 | 契约与版本绑定：脚本命令/参数变更必须两端同步并跑全量回放 |

**定稿**：保持 B′。透传会重开已关闭的裁决，并把 index 维护机的布局假设、凭据和脚本执行面带进面向所有用户的二进制；
若确需统一入口，优先做独立 `ct-pkg` 工具或 index 仓 CI，而不是塞进 `ct`。

## 6. 校验矩阵

| 检查 | `package.sh` 预检 | `ct get` | `ct install` | `ct verify` |
| --- | --- | --- | --- | --- |
| `ct.pkg` 存在/可读 | ✅ | ✅（取回后） | — | — |
| `name` / `publisher` / `version` / `ns-root` | ✅ | ✅ | ✅（依赖覆盖用） | — |
| tag `v<version>` 一致 | ✅ | ✅（索引行 tag） | — | — |
| 命名空间布局 | ✅（`--strict` S1） | — | — | — |
| 绝对 `-I` / 生成物 | ✅（PK-8 / S5） | — | — | — |
| 包树摘要 | ✅（生成行） | ✅（重算） | — | ✅（对 lock） |
| 索引行六字段 | ✅（生成器） | ✅（解析） | — | — |
| `requires` 满足 | ✅（预检） | ✅（写 lock 前） | ✅ | — |
| lock 覆盖 `dep` | — | — | ✅ | — |

### 6.1 判据归属矩阵（v1.1 定稿）

> 编号体系是 **PK-1…PK-13 + R1–R3 + S1–S5**（原文归 index 仓，本契约只引用、不重定义）。
> **原文基线**：`ct-pkg/index` @ `0cdb132a179a9cfab5e339da9fec856ec4f29fcc`（2026-11-20，`main`）。
> 本仓只接收“离线、只读、仅需包树与清单”的判据；需要网络、仓库历史或发布凭据的判据
> 留在 index CI / 包仓。
>
> **基线审计（PKG-12 处置）**：在该基线的 `tools/*.sh` 与全部 `*.md` 中检索 `PK-`，只有
> `tools/package-check.sh:15-18` 给出 PK-1/2/5/8 的原文，`:22-32` 给出 R1–R3 与 S1–S5；
> **PK-3 / 4 / 6 / 7 / 9 / 10 / 11 / 12 / 13 没有原文**。这些编号保留在编号体系里，本版
> **不分配归属、不作为任何一方的验收判据**，也不再在矩阵里复述未经原文支持的摘要。
> 后续由 index 仓补原文后另开契约定版（不回到“待补”状态）。

| 判据 | 内容（原文摘要） | 原文位置（index@0cdb132） | 归属 | 本仓状态（PH-83） |
| --- | --- | --- | --- | --- |
| PK-1 | `ct.pkg` 存在且可读 | `tools/package-check.sh:15` | CT（`ct pkg check`） | 已实现 |
| PK-2 | `name` / `publisher` / `version` / `ns-root` 必填；`publisher != local` | `tools/package-check.sh:16` | CT（`ct pkg check`） | 已实现 |
| PK-5 | `ns-root` 相对、无 `..`、是已存在目录 | `tools/package-check.sh:17` | CT（`ct pkg check`） | 已实现 |
| PK-8 | 包树内无绝对 `-I` | `tools/package-check.sh:18-19` | CT（`ct pkg check`） | 已实现 |
| PK-3 / 4 / 6 / 7 / 9 / 10 / 11 / 12 / 13 | 无原文（编号保留） | — | 未分配 | 不在 CT |
| R1 | `name` / `publisher` 字符集 | `tools/package-check.sh:22` | index CI / 包仓 | 不在 CT |
| R2 | `version` 为 `x.y.z` | `tools/package-check.sh:23` | index CI / 包仓 | 不在 CT |
| R3 | tag ↔ version（git 检出时；缺仓库/缺 tag 只告警） | `tools/package-check.sh:24-25` | index CI / 包仓 | 不在 CT |
| S1 | 每个命名空间单元位于 `<ns-root>/<namespace path>/` | `tools/package-check.sh:28` | index CI（`--strict`） | 不在 CT |
| S2 | `dep` 可解析且不重复同一包 | `tools/package-check.sh:29` | index CI（`--strict`） | 不在 CT |
| S3 | `requires` 解析为 `ct` + 版本范围 | `tools/package-check.sh:30` | index CI（`--strict`） | 不在 CT |
| S4 | `c-boundary` 为 `strict` / `allow` | `tools/package-check.sh:31` | index CI（`--strict`） | 不在 CT |
| S5 | 包树无构建产物、缓存、`vendor/` | `tools/package-check.sh:32` | index CI（`--strict`） | 不在 CT |

**PH-83 新增的 CT 判据（`ct index verify`，§4.4）**：

| 判据 | 内容 | 归属 | 状态 |
| --- | --- | --- | --- |
| IV-1 | 六字段行、字段数正确 | CT（`ct index verify`） | PH-83 已实现 |
| IV-2 | 五字段旧行按行硬错（D-014 第 5 条） | CT（`ct index verify` + `ct get`） | PH-83 已实现 |
| IV-3 | `name` / `publisher` / `version` 形状 | CT | PH-83 已实现 |
| IV-4 | `tag == v<version>` | CT | PH-83 已实现 |
| IV-5 | `sha256:` + 64 位小写十六进制 | CT | PH-83 已实现 |
| IV-6 | 同一 `publisher/name version` 不重复 | CT | PH-83 已实现 |
| IV-7 | “可回放”判定，不取回、不比包树摘要 | CT | PH-83 已实现 |

**不再列入本仓候选**：`dep` 全名、`requires` 可满足性、tag 一致性的离线子集——R2/R3/S2/S3
仍归 index CI / 包仓；PH-83 不扩 `ct pkg check` 的 1/2/5/8 承诺（D-014 第 2 条）。

## 7. 失败与退出码

| 场景 | 发布端 | 消费端 |
| --- | --- | --- |
| 清单缺身份字段 | 预检失败，不写索引 | 取回后硬错，不写 store/lock |
| tag 与版本不一致 | 预检失败 | 索引行不应存在；若存在，按行内 tag 取回后仍以清单校验 |
| 摘要不一致 | 生成器拒绝写行/索引报错 | `does not match ct.lock` 或索引摘要不符，硬错 |
| 包不可安装 | 回放失败，索引不推送 | 不产生 lock 行 |
| `requires` 不满足 | 预检失败 | `ct get` 失败且不改 lock；`--force` 告警继续 |
| 网络/凭据失败 | 中止，索引原样 | `ct get` 失败；其余子命令不受影响 |
| `ct index verify`：索引全部合法 | — | 退出码 0，默认 `index verify: OK (<n> rows)` |
| `ct index verify`：存在坏行/五字段旧行 | — | 退出码 1，逐行给行号与类别（§4.4） |
| `ct index verify`：用法错误/索引不可读 | — | 退出码 2；不写任何文件 |
| `ct index verify`：目录/设备/FIFO/socket/目录 symlink | — | 退出码 2；`--json` 为 `ok:false` + `line:0 kind:"io"`；FIFO 不打开 |
| `ct index verify`：读取中 `ferror` | — | 退出码 2；`--json` 同上（追加一条 io 错误） |

## 8. 兼容与迁移

- **五字段旧行**：D-014 第 5 条起**按行硬错**（请求命中旧行即失败，提示六字段）；其余六字段行不受影响。
  生成端已停止产出旧行；发布前置是 index 仓先清零旧行。
- **官方身份**：按 [PH-77](../design/phase77.md) 归一为 `ct/std`；`ct-pkg/std` 当前 `publisher = std` 属**契约违约**，
  需改清单并发新 tag（不可原地改旧 tag）。索引行与内置 pin 表必须同步。
- **裸名语义**：PH-77 起裸名只解析官方；第三方必须 `publisher/name`。这与本契约 I2 一致，发布端不得依赖裸名。
- **锁格式**：v2 七字段；v1 只经 `ct migrate`。发布端回放必须接受七字段并比对第 1、7 字段。
- **格式变更流程**：先改本契约 → 两端各自实现 → index 仓全量 `verify-index` → CT 侧夹具 → 再发布。

## 9. 验收

**CT 侧（夹具）**

1. 六字段行 + 干净 HOME：`ct get --index` 成功，lock 第一字段 `publisher/name`、第七字段同索引摘要；
2. 摘要被改一行：硬错，无 store/lock 残留；
3. 缺 `publisher` 的行：硬错，错误信息指向清单身份；
4. 五字段行：请求命中即硬错，提示六字段（其余六字段行仍可安装）；
5. 隔离 `HOME` / `CT_HOME`、空 store：仍成功；
6. 失败后既有 lock 逐字节不变；
7. `ct index verify` 对合法索引退出 0、坏行退出 1 并给行号、不可读退出 2；`--json` 单行可解析且字段稳定；
   非普通文件（目录/`/dev/null`/目录 symlink/FIFO）与读取错误退出 2，`--json` 不得为 `ok:true`；
8. `ct index verify` 与 `ct get` 对五字段旧行同判；零网络/零子进程/零 store/lock 写入（隔离 `HOME` 前后无新文件）。

**index 侧**

1. `package-check.sh` 与 `ct pkg check` 在 PK-1/2/5/8 上同判；
2. `refresh-index.sh --dry-run` 无意外 diff；`--all-tags` 的摘要与旧行一致；
3. `verify-index.sh` 全量通过；
4. `package.sh check` 全绿；`publish` / `release` 在无 `CT_BIN` 时按 I10 失败（待修）。

**交界**

1. 在 staging 仓执行 `package.sh release`，新行写入后经 `ct get` 回放成功才推送；
2. 另一台干净 `HOME` 上 `ct get publisher/name@version` + `ct build` 成功；
3. 重跑发布幂等，索引无新提交。

## 10. 未决项

| ID | 问题 | 建议 |
| --- | --- | --- |
| Q1 | `ct pkg` 是否透传 `package.sh` | **已定（2026-11-19）：保持 B′**；透传不采纳，复开需新裁决 |
| Q2 | `package.sh` 缺 `ct` 时跳过回放 | 改为失败；至少 `--no-verify` 显式留痕 |
| Q3 | 官方 pin 表（PH-77）与索引行的关系 | 以索引行为生产真值，pin 表必须与官方行逐字段一致，一致性探针门禁 |
| Q4 | 索引签名/pin | 自动消费前必须有 pin/签名；手动 `--index` 可保持现状 |
| Q5 | `ct get` 输出规范串（PH-77 S2）是否成为脚本接口 | 不作为脚本解析接口；脚本只读 `ct.lock` 与退出码 |
| Q6 | 五字段旧行的发布顺序 | **已定（D-014 第 5 条）**：按行硬错；index 仓先清零旧行再发硬错版本 |
| Q7 | 多索引并存 | **已定（D-014 第 4 条）**：单索引；多源由调用方合并索引文件 |
| Q8 | PK/R/S 全量原文与逐条归属 | **已定（2026-11-21，PH-83）**：§6.1 按 index@0cdb132 基线定稿；PK-1/2/5/8 归 CT，R/S 归 index CI，缺原文的 PK-3/4/6/7/9–13 编号保留但不作判据（PKG-12） |

## 11. 变更与归属

| 契约面 | 归属 | 变更要求 |
| --- | --- | --- |
| `ct get` / lock / store / 摘要算法 | ct-lang | 先改本契约，再改实现与夹具 |
| `ct.pkg` 键、tag 规则、预检 | ct-pkg 包仓 + index 仓 | 索引生成器先接受，包仓再发布 |
| 索引行格式、生成/回放脚本 | ct-pkg/index | 全量 `verify-index` + CT 侧兼容 |
| `ct pkg` 边界 | ct-lang（需求方 2026-11-19 定稿 B′） | 复开透传必须显式登记并覆盖既有裁决 |
| 契约 v1 条款与测试向量 | ct-lang（REQ） | 改条款同时改向量与 conformance；见 [D-014](../decisions/D-014.md) |
| `ct index verify`（只读） | ct-lang（DEV，PH-83） | 不改发布边界；只读回放索引行 |
| conformance 数据与 runner | ct-lang（REQ/DEV） | 版本化数据；shell 与 CT 共用 |
| Linux x64 产物 / 稳定 URL | ct-lang（发布工程） | 每 MINOR 一版 + sha256；index CI 钉版本 |
| index 仓脚本废弃 / CI 改造 | ct-pkg/index | 由该仓确认时间表；本仓只提供契约与二进制 |

## 12. 修订记录

| 版本 | 日期 | 内容 |
| --- | --- | --- |
| v1 | 2026-11-20 | 按 [D-014](../decisions/D-014.md) 七项裁定：维持 B′、判据归属矩阵、契约并入本文、单索引（I13）、五字段按行硬错（改 I12）、最小 CI 产物、PH-83 排期；新增 §3.3 digest 伪代码与 3 组向量、§4.1.1 spec/版本选择、§6.1 判据归属矩阵、Q6–Q8 |
| v1.1 | 2026-11-21 | PH-83 S83a：§3.3 三组向量补全字节并重新实测（v1 的向量 2/3 缺输入、不可复现）；§4.1.1 补 MVS 实例；新增 §4.4 `ct index verify`（IV-1…IV-7、输出/JSON/退出码）；§6.1 按 index@0cdb132 基线定稿（缺原文编号显式标为未分配）；§7 退出码与 §10 Q8 同步 |
| v1.2 | 2026-11-21 | PKG-14 修复：§4.4 补“输入必须是普通文件（stat+S_ISREG）、ferror、`--json` 退出 2 也为失败”；§7/§9 同步；FIFO 在 open 前拒绝 |
