# PKG 索引机制梳理（2026-11-17）

> 范围：CT 仓 `ct` 的包索引（index）消费链路、`ct.lock` v2、共享包根与 `vendor/` 删除后的现状。
> 口径：只读梳理，不改代码、不改 `ct.pkg`；所有探针在 `/tmp/pkgi` 下执行。
> 版本：仓内 `ct-ast v0.63.2`（根目录 `./ctc` 是 L0 引导编译器，不提供 `get` 子命令，不能用来复现）。
> 外部索引：2026-11-17 抓取 `github.com/ct-pkg/index` 的 `main` 分支。

## 0. 结论

1. **消费者侧索引已经成型**：六字段行、五字段兼容、`--index` 覆盖 `CT_INDEX`、限定名/裸名匹配、歧义硬错、MVS 取最低满足版本，代码与 `test/pkg/run.sh` 都有覆盖。
2. **没有默认索引**。代码注释写得很明确：`--index <path>` wins over `CT_INDEX`. Nothing is built in（[Pkg.h.ct:115-116](../../selfhost/ct-ast/tool/pkg/Pkg.h.ct#L115-L116)）。`CT_REGISTRY` 只负责裸名到 git URL，不是索引。
3. **索引生产者在仓外**：`ct-pkg/index` 仓用 `tools/gen-index.sh` / `tools/refresh-index.sh` 生成五字段索引，夜间刷新；本仓没有索引生成器，也没有 `ct pkg digest`。
4. **`ct get ct/std` 不是缺一环，而是三层同时不满足**：
   - 未设置 `CT_INDEX`/`--index` 时，没有默认索引，直接 `no index resolver`；
   - 设置官方索引后，官方行是五字段、没有 `publisher`，限定名匹配不上，退化成 `https://ct/std`；
   - 手写六字段行后能取到源码，但官方 `std` 的 `ct.pkg` 缺 `publisher`/`ns-root`，在 store 提交处硬错。
5. **lock v2 / `~/.ct/pkg` / 删 `vendor` 的改造已经落地**，阻塞不在 lock/store，而在索引生产与官方包身份字段。消费者机制本身可用：本地六字段夹具能完成 `get → store → lock v2 → build`。

## 1. 索引现在的形态

### 1.1 行格式与字段

`docs/package-guide.md` 给出的现行契约是六字段：

```text
name version publisher git-url tag sha256:<64 hex>
```

（[package-guide.md:103-107](../package-guide.md#L103-L107)）

| 列 | 语义 | 消费者怎么用 | 备注 |
| --- | --- | --- | --- |
| `name` | 包名 / 仓库名 | 裸名直接匹配；限定名匹配叶子段 | 取回后还要求清单里的 `name` 等于该叶子名（[Pkg.h.ct:971-975](../../selfhost/ct-ast/tool/pkg/Pkg.h.ct#L971-L975)） |
| `version` | 包的 `x.y.z` | 先按范围过滤，再取最低满足版本 | 只解析前三段；`1`、`1.2` 也接受，后缀不参与比较（[Pkg.h.ct:444-468](../../selfhost/ct-ast/tool/pkg/Pkg.h.ct#L444-L468)） |
| `publisher` | 发布方 | store 路径、缓存键、限定名匹配、裸名歧义判定 | 仅六字段行有；五字段行该列为空 |
| `git-url` | 包仓地址 | `git clone` / `fetch` | 支持 `file://`，本地验证可用 |
| `tag` | 发布 tag | 命中索引后固定 checkout 该 tag，而不是重新挑 tag | `pin_tag`（[Pkg.h.ct:927-943](../../selfhost/ct-ast/tool/pkg/Pkg.h.ct#L927-L943)） |
| `sha256` | 包树摘要 | fetch 后、落 store 前比对 | 必须是 `sha256:` + 64 位小写十六进制（[Pkg.h.ct:357-366](../../selfhost/ct-ast/tool/pkg/Pkg.h.ct#L357-L366)） |

解析细节（[Pkg.h.ct:2074-2171](../../selfhost/ct-ast/tool/pkg/Pkg.h.ct#L2074-L2171)）：

- 空白分隔，`#` 开头整行注释，空行跳过；少于 5 个 token 的行跳过。
- `ntok >= 6` 按六字段读：`publisher=tok[2]`、`url=tok[3]`、`tag=tok[4]`、`sha=tok[5]`；`ntok == 5` 按旧五字段读：`publisher=""`、`url=tok[2]`、`tag=tok[3]`、`sha=tok[4]`。超过 6 个 token 的多余列被忽略。
- 非法 `sha` 行被标记为 `bad` 并跳过；如果整个文件没有一条有效命中，返回 `-1`，**调用方不再打印原因**（实测见 §8 的 L 用例）。
- 同一裸名命中两个不同 `publisher` 时硬错：

```text
ctc: 'hello' is ambiguous; write acme/hello or zed/hello
```

（[Pkg.h.ct:2126-2137](../../selfhost/ct-ast/tool/pkg/Pkg.h.ct#L2126-L2137)）

- 版本范围是空格分隔的 AND；`^` 只要求主版本相同，`~` 要求主、次版本相同（[Pkg.h.ct:470-530](../../selfhost/ct-ast/tool/pkg/Pkg.h.ct#L470-L530)）。`^0.1.0` 实际接受 `0.2.0`，不是常见 caret 的“0.x 不允许次版本漂移”。
- 命中多条版本时取**最低**满足版本（MVS），不是最高版本（[Pkg.h.ct:2143-2162](../../selfhost/ct-ast/tool/pkg/Pkg.h.ct#L2143-L2162)）。

### 1.2 裸名与限定名怎么匹配

| 输入形态 | 匹配规则 | 五字段行能否命中 | 说明 |
| --- | --- | --- | --- |
| 裸名 `std` | `tok[0] == "std"` | 能 | 多个 publisher 同时命中才报歧义 |
| 限定名 `ct/std` | `publisher == "ct"` 且 `tok[0] == "std"`；或 `tok[0]` 本身就是完整 `ct/std` | **不能**（`publisher` 为空） | 见 [Pkg.h.ct:2116-2124](../../selfhost/ct-ast/tool/pkg/Pkg.h.ct#L2116-L2124) |

这条规则解释了为什么官方五字段索引无法支撑 `ct get ct/std`：不是 URL 错了，而是索引行里没有 `publisher` 这一列。

### 1.3 谁生成、谁维护

**本仓不生成索引。** `ct` 只读索引，不写索引；`ct get` 是唯一读取点（[Pkg.h.ct:1569-1616](../../selfhost/ct-ast/tool/pkg/Pkg.h.ct#L1569-L1616)）。本仓也没有 `ct pkg digest` 子命令，`grep` 全仓无实现。

**外部 `ct-pkg/index` 仓负责生产。** 2026-11-17 抓取到的 `main` 分支内容：

- `index` 是五字段纯文本，共 12 行：`hal`、`hal-posix`、`std`、`zlib`、`png`、`net-posix`、`sqlite`、`sql`、`json`、`curl`、`hashmap`、`dict`。
- `std` 行当前是 `std 0.2.0 https://github.com/ct-pkg/std v0.2.0 sha256:cee7...`，没有 publisher。
- 生成器 `tools/gen-index.sh` 只从 `ct.pkg` 读 `name` / `version`，摘要算法与 `ct` 的 `sha_collect` 一致：按相对路径排序，逐文件写入“路径 + 换行 + 内容”汇入单流 SHA-256，跳过 `.git` / `vendor` / `.ctcache`（外部 `tools/gen-index.sh:7-18`、`:36-58`）。
- `tools/refresh-index.sh` 遍历 `packages.txt`，取每个仓库**最高** `v*` tag，clone 后调用 `gen-index.sh` 重建 `index`（外部 `tools/refresh-index.sh:104-152`、`:163-191`）。因此每个包在索引里只有一行，旧版本行会在重建时消失。
- 维护方式：`packages.txt` 是 allowlist，夜间 workflow `index.yml` 重建并提交；`release-package.sh` 在发布 tag 后刷新索引（外部 `README.md:27`、`:81-83`、`:121`、`:182-187`）。
- 外部 README 明确承认版本表达限制：`index always names each remote's highest v* tag`，`std` 需要同时服务旧编译器，`the index cannot express`（外部 `README.md:52-56`、`:73-77`）。

这与仓内 Phase 18 的 D18-7 一致：`ct-pkg/index` 仓库、五字段纯文本、包 release 时 CI 追加/更新一行（[phase18.md:177](../history/design/phase18.md#L177)）。**但消费端在 PH-54 S1 已经升级为六字段**（[phase54.md:93-102](../design/phase54.md#L93-L102)），生产端仍停在五字段，契约出现分叉。

### 1.4 官方包清单的现状

抓取官方包 tag 上的 `ct.pkg`（截至 2026-11-17）：

- **索引指向的 `std v0.2.0`** 只有 `name`、`version`、`licence`、`requires`、`ldflags`，**没有 `publisher`，也没有 `ns-root`**；注释仍写 `-I vendor/std`，并说 `std/` 目录是 namespace root。
- 抽检的 11 个可读取清单（`hal`、`hal-posix`、`std v0.2.0`、`zlib`、`png`、`net-posix`、`sqlite`、`sql`、`curl`、`hashmap`、`dict`）同样没有这两个键；`json` 的清单未取到，未下结论。
- **但 `std v0.3.2` 已经补上身份**：`publisher = std`、`ns-root = .`，注释明确说这两键是共享 store 机制所需（`ct-pkg/std v0.3.2/ct.pkg` 尾部）。这说明包侧在前进，而索引还停在 `std 0.2.0`。直接绕过索引取 0.3.2 可以成功：

```console
$ ct get https://github.com/ct-pkg/std@0.3.2
installed 1 package(s)
$ cat ct.lock
std/std 0.3.2 git https://github.com/ct-pkg/std a3f12172... . sha256:95fc010f...
```

（W 用例；这条 lock 行与 ct-fsguard 提交的 `std/std 0.3.2` 行一致。）

这不是索引摘要算错：`ct get std` 能通过 tag、摘要校验，最后才在 `pkg_store_commit` 报：

```text
ctc: '<cache>/ct.pkg' is missing 'publisher'
```

（[Pkg.h.ct:1924-1938](../../selfhost/ct-ast/tool/pkg/Pkg.h.ct#L1924-L1938)）

根因可以追到 PH-54 的 S4：**“S4（包仓对齐）已移出本 phase：`publisher` / `ns-root` / tag / 各仓测试改写归对应包仓，本卡不再跟踪，也不再作为收口判据”**（[phase54.md:129](../design/phase54.md#L129)）。消费者升级了，包仓对齐没有落在本仓任何 phase 的验收里。

## 2. 解析链路

### 2.1 `ct get` 从包名到来源

入口 `get_main` 只解析 `--index` / `--force` / spec，然后调用 `get(spec, ".")`（[Pkg.h.ct:1569-1616](../../selfhost/ct-ast/tool/pkg/Pkg.h.ct#L1569-L1616)）。`get` 先拒绝 v1 lock，再交给 `get_spec`（[Pkg.h.ct:1328-1360](../../selfhost/ct-ast/tool/pkg/Pkg.h.ct#L1328-L1360)）。

`get_spec` 的路由（[Pkg.h.ct:1065-1135](../../selfhost/ct-ast/tool/pkg/Pkg.h.ct#L1065-L1135)）：

| spec 形态 | 分支 | 结果 |
| --- | --- | --- |
| `./path`、`/abs`、`file://…` | 本地目录 | `get_one`：读清单、校验身份、落 store、写 `dir` 行；不读索引 |
| 含 `://` | 直接 git URL | `get_git`：clone/checkout tag、读清单、递归依赖、落 store、写 `git` 行 |
| 裸名（无 `/`）且配置了索引 | `pkg_index_lookup` | 命中 → `fetch_git`；`2` → `package '<name>' is not in the index`；`-1` → 直接失败 |
| 裸名且未配置索引 | `get_git` | `git_url` 用 `CT_REGISTRY`（默认 `https://github.com/ct-pkg`）拼 `<registry>/<name>` |
| 限定名（含 `/`、无 `://`）且未配置索引 | 无 | `no index resolver` 指引（SH-81，v0.61.1） |
| 限定名且配置了索引 | `pkg_index_lookup` | 命中 → `fetch_git`；`-1` → 失败；**`2` 不报错，落到 `get_git`** |

最后一行的 `2` 分支是现存缺陷：限定名在索引里查不到时，`get_spec` 没有像裸名那样打印 `is not in the index`，而是继续走 `get_git(path)`，由 `git_url` 拼成 `https://<publisher>/<name>`（[Pkg.h.ct:1114-1125](../../selfhost/ct-ast/tool/pkg/Pkg.h.ct#L1114-L1125)、[Pkg.h.ct:685-688](../../selfhost/ct-ast/tool/pkg/Pkg.h.ct#L685-L688)）。实测 `acme/hello` 得到：

```text
ctc: git clone of 'https://acme/hello' failed
```

命中索引后的 `fetch_git` 顺序是：缓存定位与 origin 校验 → clone/fetch → checkout 索引 tag → 读清单 → 校验 `name` → 校验 manifest version 是否满足范围 → 读 `publisher`/`ns-root` → 递归 `dep` → 计算树摘要并与索引 `sha` 比对 → `pkg_store_commit` → 写 v2 lock 行（[Pkg.h.ct:837-1034](../../selfhost/ct-ast/tool/pkg/Pkg.h.ct#L837-L1034)）。

注意：`fetch_git` 对 `publisher` 的使用有两个来源——缓存键用索引行的 `cache_pub`，store/lock 用清单里的 `publisher`，**两者没有一致性校验**（[Pkg.h.ct:980-1029](../../selfhost/ct-ast/tool/pkg/Pkg.h.ct#L980-L1029)）。实测索引写 `zed/hello`、清单写 `acme`，命令成功且 lock 落成 `acme/hello`（§8 的 T 用例）。

### 2.2 `CT_INDEX`、`--index`、默认索引各起什么作用

| 来源 | 作用范围 | 优先级 | 限制 |
| --- | --- | --- | --- |
| `--index <file>` | 本次 `ct get`，包括本次递归解析的 `dep` | 最高（`have_index`） | 只接受本地文件路径；只有 `get_main` 解析 |
| `CT_INDEX` | 所有没带 `--index` 的 `ct get` | 次之 | 只接受本地文件路径；空字符串会被当作“已设置”但返回“无索引”，限定名会退化成 URL |
| 默认索引 | 无 | 无 | 代码注释明确 `Nothing is built in`（[Pkg.h.ct:115-116](../../selfhost/ct-ast/tool/pkg/Pkg.h.ct#L115-L116)） |
| `CT_REGISTRY` | 裸名、无索引时的 git 基址 | 兜底 | 默认 `https://github.com/ct-pkg`；**只对无 `/` 的裸名生效**（[Pkg.h.ct:690-692](../../selfhost/ct-ast/tool/pkg/Pkg.h.ct#L690-L692)） |

`ct install` / `ct update` / `ct verify` / `ct migrate` 都不读索引；索引只影响 `ct get`。索引也不支持 HTTP URL、目录、多个文件或自动下载，必须由调用方准备一个本地纯文本文件。

### 2.3 `ct get ct/std` 报 `no index resolver` 到底缺哪一环

实测（§8 的 A 用例）：

```text
ctc: no index resolver for 'ct/std'
  'ct/std' is a publisher-qualified package name; without an index
  there is no mapping from that name to a git URL.
  ...
  Note: CT_REGISTRY only applies to bare names without '/';
        'ct/std' requires an index (case 2) or a URL/path (case 3/4).
```

这条诊断本身是正确的，缺的是它指出的映射。把链路拆开看：

| 层 | 现状 | 结果 | 证据 |
| --- | --- | --- | --- |
| L1 默认索引 | 没有内置默认索引，也没有自动下载 | 未设置 `CT_INDEX` 时直接报 `no index resolver` | 代码注释、A 用例 |
| L2 官方索引 | 存在，但五字段、无 `publisher`，且只到 `std 0.2.0` | 限定名匹配不上，退化成 `https://ct/std` | 官方 `index` 行、M 用例 |
| L3 六字段索引 | 消费者支持；手写一行即可命中并取源码 | 能通过 tag 与摘要校验 | S 用例 |
| L4 包自身身份 | 索引指向的 `std 0.2.0` 缺 `publisher`/`ns-root`；`std 0.3.2` 已补 `publisher = std`、`ns-root = .` | 0.2.0 在 store 提交硬错；0.3.2 可通过本地/URL 落 store | S 用例、W 用例、`std v0.2.0`/`v0.3.2` 清单 |

所以“缺哪一环”的准确答案是：**眼前缺 L1；只补 L1 仍会被 L2 挡住；补到 L3 仍会被 L4 挡住（如果仍指 0.2.0）。** 消费者不是主要缺口——本地六字段夹具能完整跑通（§8 的 C 用例）；`std 0.3.2` 也已经具备身份，缺的是索引没收录它。

还有一层名字问题：`ct/std` 的 publisher 是 `ct`，但 `std 0.3.2` 清单写的是 `publisher = std`，`ct-fsguard` 的 lock 也是 `std/std`。因此即使手写六字段行，正确的限定名应是 `std/std`；`ct/std` 会把发布方写错，或依赖 G6 的“索引 publisher 不校验”静默落成 `std/std`。教程里“发布方 `ct`”的说法与 0.3.2 清单不一致（[tutorial.md:706](../tutorial.md#L706)）。

`ct get std`（裸名）也不能绕过：官方索引能命中 `std 0.2.0`，但同样在 L4 失败：

```text
ctc: '<home>/.cache/ct-pkg/std/ct.pkg' is missing 'publisher'
```

（N 用例）

## 3. 与 `ct.lock` v2、包根、`vendor` 删除的关系

### 3.1 包根与缓存

- store 根：`CT_HOME` 原样使用；未设置时用 `$HOME/.ct`。包目录是 `<root>/pkg/<publisher>/<name>/<version>`（[Pkg.h.ct:1847-1876](../../selfhost/ct-ast/tool/pkg/Pkg.h.ct#L1847-L1876)）。默认即 `~/.ct/pkg`。
- git 缓存根：固定 `$HOME/.cache/ct-pkg`，**不受 `CT_HOME` 影响**（[Pkg.h.ct:779-782](../../selfhost/ct-ast/tool/pkg/Pkg.h.ct#L779-L782)）。缓存键带 publisher，PKG-5 已修（v0.58.1）。
- store 落盘前强制要求 `publisher` 非空、非 `local`、不含 `/`/`..`，且 `ns-root` 非空、相对、无 `..`、目录存在（[Pkg.h.ct:1924-1949](../../selfhost/ct-ast/tool/pkg/Pkg.h.ct#L1924-L1949)）。

### 3.2 lock v2

`ct get` 写 `# ct-lock 2` 头 + 每包一行 7 字段：

```text
<publisher>/<name> <version> <git|dir> <url|path> <commit|-> <ns-root> <sha256:...>
```

（`get_one`：[Pkg.h.ct:1194-1205](../../selfhost/ct-ast/tool/pkg/Pkg.h.ct#L1194-L1205)；`fetch_git`：[Pkg.h.ct:1023-1032](../../selfhost/ct-ast/tool/pkg/Pkg.h.ct#L1023-L1032)）

行为：

- `ct get` 只解析一个 spec，但会保留本次没有重解的旧行，避免第二次 get 把第一次的 pin 弄丢（[Pkg.h.ct:1361-1370](../../selfhost/ct-ast/tool/pkg/Pkg.h.ct#L1361-L1370)）。
- 成功后把 spec 写入工程 `ct.pkg` 的 `dep` 行（[Pkg.h.ct:1377](../../selfhost/ct-ast/tool/pkg/Pkg.h.ct#L1377)）。
- 已有 v1 lock 时，`ct get` / build / install / verify / update 都硬错并提示 `ct migrate`（[Pkg.h.ct:1341-1352](../../selfhost/ct-ast/tool/pkg/Pkg.h.ct#L1341-L1352)）。
- `ct build` 读 lock，自动补 store 的 `-I`；`dir` 行显示 dev override 提示；`--locked` 逐包校验摘要（[Pkg.h.ct:2775-2822](../../selfhost/ct-ast/tool/pkg/Pkg.h.ct#L2775-L2822)）。
- `ct install` 校验 store 摘要与 `dep` 覆盖、试解析 import，然后打印 `ct build` 命令；**v2 下不再打印 `-I`**，因为 `ct build` 会自己补，重复打印会与 dev override 冲突（SH-83，[Pkg.h.ct:1536-1545](../../selfhost/ct-ast/tool/pkg/Pkg.h.ct#L1536-L1545)）。

### 3.3 `vendor/` 删除

PH-63 / S7（v0.62.0）删除了 `vendor/` 的读写：`get` 不创建 `vendor/`，build/install/verify/update 不再读 vendor，v1 lock 只报错，`ct migrate` 作为一次性桥保留（[phase63.md:24-38](../design/phase63.md#L24-L38)）。因此：

- 新工程：只可能走 store + v2 lock。
- 旧工程：必须先 `ct migrate`；而 migrate 要把 vendor 树写进 store，同样要求清单有 `publisher`/`ns-root`，老官方包无法直接迁移。

### 3.4 哪些路径已可用、哪些断了

| 路径 | 状态 | 证据 |
| --- | --- | --- |
| 本地目录 → store → v2 lock → build | 可用（清单需有身份字段） | `test/pkg` 的 dir 用例；C 用例的本地 git 变体 |
| 裸名 + `CT_REGISTRY` → store | 可用 | J 用例：`CT_REGISTRY=file:///tmp/pkgi/pkg` 解析 `hello@^0.2.0` 成功 |
| 裸名 + 五字段索引 → store | 可用（包需有身份字段） | `test/pkg/run.sh:589-667` 的 `gutil` 用例 |
| 裸名 + 六字段索引 → store | 可用 | C/E 用例 |
| 限定名 + 六字段索引 → store | 可用 | C 用例：`acme/hello@^0.1.0` 落 `~/.ct/pkg/acme/hello/0.1.0` |
| 限定名 + 五字段索引 | **断**：退化成 `https://<publisher>/<name>` clone | E 用例 |
| 未配置索引 + 限定名 | **断**（有指引） | A 用例 |
| 官方索引 + 官方包（索引指向的 0.1.0/0.2.0） | **断**：清单缺 `publisher`/`ns-root` | N/S 用例 |
| 官方包 0.3.2 + 本地/直接 URL | 可用；`publisher = std`、`ns-root = .` | W 用例、ct-fsguard lock |
| 索引缺失条目 | **断得不对**：限定名落到 URL clone，裸名报 `is not in the index` | B 用例 |
| 索引精确旧版本（索引只有最高 tag） | **断**：`std@0.1.0` 报 `package 'std' is not in the index` | P 用例 |
| `ct install` / `ct build` 从 v2 lock 消费 | 可用 | `test/pkg` S2/S3/S5 用例，142/0 |

## 4. 引用外部包：声明、获取、锁定、引用与冲突

这一节回答“项目要引用一个外部包，机制到底是什么”。所有结论都在 `/tmp` 用 `ct-ast v0.63.2` 实测，命令见 §8。

### 4.1 依赖声明：`dep` 与 `requires` 是两件事

原文（[package-guide.md:70](../package-guide.md#L70)、`:78`、`:81`、`:98-99`）：

> 行式清单：`key = value`，`#` 起注释，`dep` 可重复，未知键**忽略**（向前兼容）。
>
> `dep` | 否，可重复 | 依赖，`name` 或 `name@range`；格式与 Phase 8 一致
>
> `requires` | 否 | 对编译器版本的约束；**不满足时 `ct get` / `ct install` 失败**，`--force` 才降级为告警
>
> `dep` 的范围沿用 Phase 8 子集：`^x.y.z`、`~x.y.z`、`>=` / `>` / `<` / `<=` / `=`、裸版本（精确）
> 或 `*`，多个条件用空格表示 AND。解析用 MVS（取满足范围的最低版本）。

实现侧，`read_manifest` 对 `dep` 的处理是逐行追加到 `deps[]`，不是解析列表：

```c
} else if (kl == 3 && strncmp(ls, "dep", 3) == 0) {
    if (*ndeps >= MAX_PKG_DEPS || vl >= MAX_PKG_PATH) { ok = 0; break; }
    memcpy(deps[*ndeps], v, vl);
    deps[*ndeps][vl] = 0;
    (*ndeps)++;
}
```

（[Pkg.h.ct:419-423](../../selfhost/ct-ast/tool/pkg/Pkg.h.ct#L419-L423)；`MAX_PKG_DEPS = 16`、`MAX_PKG_DEPTH = 8`，见 `:24`、`:27`）

`requires` 只接受编译器版本，写成包依赖会被明确拒绝：

```text
ctc: package 'app4' has an unsupported requires 'std >= 0.1.0';
     use dep = pkg@range for package dependencies
```

（[Pkg.h.ct:2203-2211](../../selfhost/ct-ast/tool/pkg/Pkg.h.ct#L2203-L2211)）

**真实可用的写法**（S1 用例，一个包依赖两个外部包）：

```ini
name = app
publisher = acme
version = 0.1.0
ns-root = src
dep = ../liba
dep = ../libb
```

```console
$ ct get ./app
installed 3 package(s)
```

lock 三行：`acme/liba`、`acme/libb`、`acme/app`。

**反例**：

| 写法 | 结果 | 证据 |
| --- | --- | --- |
| `dep = ../liba, ../libb` | 当成一个 spec，报 `cannot read '…/liba, ../libb/ct.pkg'` | S2 用例 |
| `deps = ../liba` | 未知键告警 `has unknown key 'deps'`，不产生依赖；只装 app3 | S3b 用例 |
| `requires = std >= 0.1.0` | 告警“use dep = pkg@range”，不产生依赖；只装 app4 | S4b 用例 |

结论：

- 多依赖 = **重复多行 `dep`**，一行一个 spec；没有逗号/数组/多值语法。
- 每个包最多 16 条直接依赖；递归深度最多 8。
- `dep` 文档契约是 `name` / `name@range`，实现还接受本地路径、`file://`、git URL；`ct get` 的 spec 语法就是 `dep` 的语法。
- `requires` 只约束编译器版本（必须写 `ct ...`），不是包依赖；两者不要混用。
- `package-guide.md:70` 说未知键“忽略”，实际现在会告警（PKG-3 已修），文档这句话已过期。

### 4.2 `ct get` 与 `ct install` 的确切分工

原文（[package-guide.md:123-130](../package-guide.md#L123-L130)）：

> `ct verify` 只做摘要校验，**不读 `ct.pkg`**；清单里的 `dep` 是否被 `ct.lock` 覆盖由 `ct install` 判定
> （缺依赖时报 `dependency '<spec>' is not satisfied by ct.lock`）。
> `ct get` 一次只解析一个 spec，但会保留 `ct.lock` 中本次没有重解的其它行；重复 get 同一个包只替换
> 该包的行，不会重复。
> `ct get` 可用 git——它是**包管理路径**里唯一的子进程调用点；`ct update` / `ct verify` / `ct install`
> 零网络、零子进程。

| 动作 | `ct get` | `ct install` | `ct build` | `ct verify` | `ct update` |
| --- | --- | --- | --- | --- | --- |
| 联网 / 调 `git` | 是（唯一入口） | 否 | 否 | 否 | 否 |
| 取包、复制进 store | 是 | 否 | 否 | 否 | 否 |
| 写 `ct.pkg` 的 `dep` | 是（`remember_dep`） | 否 | 否 | 否 | 否 |
| 写 `ct.lock` | 是（合并旧行） | 否 | 否 | 否 | 是（原样写回 pin） |
| 读 `ct.lock` | 合并旧行 | 是 | 是 | 是 | 是 |
| 校验 store 摘要 | 落盘前 | 是 | 仅 `--locked` | 是 | 是 |
| 校验直接依赖覆盖 | 否 | 是 | 否 | 否 | 是 |
| 解析项目 import | 否 | 是（有 FSG-02 缺陷） | 是 | 否 | 否 |
| 打印构建命令 | 否 | 是 | 否 | 否 | 否 |

代码锚点：

- `ct get`：拒绝 v1 lock → `get_spec` → `pkg_lock_keep` 合并 → 写 `# ct-lock 2` → `remember_dep`（[Pkg.h.ct:1328-1379](../../selfhost/ct-ast/tool/pkg/Pkg.h.ct#L1328-L1379)）。
- `ct install`：读 `ct.pkg` / `ct.lock`、校验摘要与直接依赖、试解析 import、拼 `cflags`/`ldflags` 并打印一条 `ct build`（[Pkg.h.ct:1385-1565](../../selfhost/ct-ast/tool/pkg/Pkg.h.ct#L1385-L1565)）。
- `ct build`：从 lock 得到 store root 后追加 `-I` 给内部 build（[Driver.h.ct:251-258](../../selfhost/ct-ast/tool/driver/Driver.h.ct#L251-L258)）。

“装进当前项目”不是 vendor 语义：工程里真正变化的是 **`ct.pkg` 多一行 `dep`** 和 **`ct.lock` 多一行 pin**；包文件在 `$CT_HOME/pkg/...`。实测：

```console
$ ct get ./demo
installed 1 package(s)
$ cat ct.pkg
name = proj
version = 0.1.0
dep = /tmp/pkgi/ref/demo
$ cat ct.lock
# ct-lock 2
acme/demo 0.1.0 dir /tmp/pkgi/ref/demo - src sha256:84ed...
```

（Q2 用例）

**是否两个都要跑**：

- **只跑 `ct install`**：没有 lock，直接失败：

```text
ctc: no './ct.lock'; run `ct-ast get` first
```

（Q1 用例）

- **只跑 `ct get`**：可以；`ct build` 直接读 lock 构建，不需要先 install：

```console
$ ct get ./demo-git
installed 1 package(s)
$ ct build main.ct -o build
...
build_rc=0
```

（U1 用例）

- **`ct install` 是只读的**：连续 get 两个包后，前后 `shasum ct.pkg ct.lock` 不变，install 只打印命令（U3 用例）。`ct install` 已不再打印 `-I`（SH-83，v0.61.1；[Pkg.h.ct:1536-1545](../../selfhost/ct-ast/tool/pkg/Pkg.h.ct#L1536-L1545)）。

所以：`get` 负责“取 + 落 store + 写 dep/lock”，是必需步骤；`install` 负责“离线校验 + 打印构建命令”，是可选检查。**不存在 `ct install` 把包“装进项目目录”的步骤**，也不再写 `vendor/`。

多个包：`ct get` 一次一个 spec；要装多个就重复执行。U2 用例连续 get 两个包后：

```ini
dep = /tmp/pkgi/ref/demo-git
dep = /tmp/pkgi/deps/liba
```

lock 里是 3 行（第二个包的传递依赖 `libx` 也进来了）。

### 4.3 `ct.lock` v2 的字段、入库理由、与包根的关系

`ct get` 写出的行（R1 用例，store 型）：

```text
acme/demo 0.1.0 git file:///tmp/pkgi/ref/demo-git 9cb04d44... src sha256:0f3287...
```

| 列 | 含义 | 来源 |
| --- | --- | --- |
| `<publisher>/<name>` | 包全名 | 清单 `publisher` + `name` |
| `version` | 精确版本 | 清单 `version` |
| `git` / `dir` | 来源类型 | 索引/URL 为 git；本地目录为 dir |
| URL / path | 来源 | 索引 `git-url`、spec 或本地路径 |
| commit / `-` | git commit；dir 行为 `-` | `git rev-parse HEAD` |
| `ns-root` | 包内单元树根 | 清单 `ns-root` |
| `sha256:...` | 包树摘要 | 与索引/落盘摘要一致 |

写入位置：[Pkg.h.ct:1023-1032](../../selfhost/ct-ast/tool/pkg/Pkg.h.ct#L1023-L1032)（git）、[Pkg.h.ct:1201-1205](../../selfhost/ct-ast/tool/pkg/Pkg.h.ct#L1201-L1205)（dir）。

**为什么必须进版本库**：

1. lock 是 `ct build` 找 store 的唯一索引：没有 lock，import 解析不到，build 直接失败（V2 用例：`cannot resolve import 'demo/Util'`）。
2. lock 钉住版本、tag/commit、`ns-root`、摘要；不提交就无法复现同一棵树，CI/新机器会得到不同解析结果。
3. 只提交 lock 也不够：git 行的 store 目录丢了，`verify` / `install` / `build` 都报 `is not installed at '<store>'`（V4 用例）；dir 行因为直接指向本地路径，store 丢了 build 仍可工作（V1 用例）。
4. lock 与 store 是“清单 + 内容”的关系：lock 记录 store 路径和摘要，store 保存实际文件；`ct verify` / `install` 校验摘要，`ct build --locked` 也校验；默认 `ct build` 只检查目录存在（[Pkg.h.ct:2805-2811](../../selfhost/ct-ast/tool/pkg/Pkg.h.ct#L2805-L2811)）。

`ct.lock` 是**项目级**文件，不是全局；store 是**机器级**缓存。多个项目可以共享同一个 store，但各自提交自己的 lock。

### 4.4 源码侧怎么引用：`import` 与 `-I`

源码只写 `import`，不写头路径：

```ct
import demo::Util;
```

解析规则（[Module.h.ct:498-538](../../selfhost/ct-ast/frontend/module/Module.h.ct#L498-L538)、[Module.h.ct:2388-2447](../../selfhost/ct-ast/frontend/module/Module.h.ct#L2388-L2447)）：

- `import demo::Util` → `demo/Util`，在每个 root 下找 `<root>/demo/Util.h.ct` 或 `<root>/demo/Util.m.ct`。
- 先试扁平布局，再试“重复首段”布局（`<root>/demo/demo/Util.*`），兼容旧树。
- 同一 root 下 `.h.ct` 与 `.m.ct` 同时存在 → 硬错 `import '...' is ambiguous`。
- 纯 `.ct` 单元不可被 import（会报 `only a .h.ct unit can be imported`）。

root 从哪来：

- lock 的每一行给出 `<store>/<publisher>/<name>/<version>/<ns-root>`（`ns-root = .` 时就是版本目录），`ct build` 把这些 root 作为 `-I` 传给内部 build（[Driver.h.ct:251-258](../../selfhost/ct-ast/tool/driver/Driver.h.ct#L251-L258)）。
- `ct install` v2 不再打印这些 `-I`（SH-83），但 `ct build` 会自动补；实测 T2 的 cc 行：

```text
'cc' -std=c99 -I '/tmp/pkgi/fsg/home/pkg/std/std/0.3.2/std/fs' -I '.ctbuild' ...
```

（这里 `.m.ct` 的静态映射还会带出自己需要的头路径。）

- **不需要在 `ct.pkg` 或项目里写头路径**。`ct.pkg` 的 `ns-root` 是包作者声明的单元树根；`cflags` / `ldflags` 是包自身的 C 编译/链接选项，由 `ct install` 折进打印命令（[package-guide.md:76](../package-guide.md#L76)、`:79-80`），不是消费者写 include path 的入口。
- 手工 `-I` 仍可用于 dev override 或非包场景，但不是引用包的正常路径；正常路径是 `dep` + `get` + lock。

### 4.5 多依赖并存：同名、传递、版本范围冲突

**先给结论：没有依赖冲突求解器。** 现有实现是“逐 spec 解析 + 同名 first-win + 事后只查直接依赖”，没有 SAT/回溯，也没有“同包多版本共存”的 lock 行。

#### 同名不同版本

- lock 合并按**裸包名**去重，不按 `publisher/name` 或版本：`pkg_lock_keep` 取冒号行第一列，剥掉 `/` 前缀后与 `seen[]` 比（[Pkg.h.ct:2363-2370](../../selfhost/ct-ast/tool/pkg/Pkg.h.ct#L2363-L2370)）。
- 因此第二次 `ct get` 同名包会**替换**旧行，不会并存。S7 用例：先 get `libx 0.1.0`，再 get `libx 0.2.0`，lock 只剩 0.2.0；`ct install` 随后报：

```text
ctc: dependency '../libx01@0.1.0' is not satisfied by ct.lock
```

- `ct build` 对手工编辑出的两行同包 lock 有防御性检查：

```text
ctc: package 'libx' is required twice: acme/libx and acme/libx
```

（[Pkg.h.ct:2776-2781](../../selfhost/ct-ast/tool/pkg/Pkg.h.ct#L2776-L2781)）

#### 传递依赖冲突

- `get` 递归解析 `dep`，但 `seen[]` 只按**包名**记，不按版本：同名第二次出现时直接 `return 0`，不落 store、不写 lock（[Pkg.h.ct:984-991](../../selfhost/ct-ast/tool/pkg/Pkg.h.ct#L984-L991)）。
- S5b 用例：`liba` 精确依赖 `libx 0.1.0`，`libb` 精确依赖 `libx 0.2.0`，`app` 同时依赖 `liba` 和 `libb`。`ct get ./app` 成功，lock 只有：

```text
acme/libx 0.1.0 ...
acme/liba 0.1.0 ...
acme/libb 0.1.0 ...
acme/app 0.1.0 ...
```

`libb` 要的 0.2.0 被静默丢弃，**没有任何告警**。

- `ct install` 只检查工程 `ct.pkg` 的**直接依赖**是否被 lock 覆盖（[Pkg.h.ct:1421-1440](../../selfhost/ct-ast/tool/pkg/Pkg.h.ct#L1421-L1440)），不遍历 lock 内包的 `dep`。S6b 用例里 `ct install` 仍然 `rc=0`，即**发现不了这个传递冲突**。
- 影响：lock 可能同时“看起来成功”且不自洽；真正编译 `libb` 用到 `libx 0.2.0` 时才会失败。

#### 版本范围

- 每个 `dep` 自己带范围；索引查找先按范围过滤，再取**最低**满足版本（MVS，[Pkg.h.ct:2143-2162](../../selfhost/ct-ast/tool/pkg/Pkg.h.ct#L2143-L2162)）。
- `^` 只锁主版本（`0.1.0` 接受 `0.2.0`），`~` 锁主+次版本；没有完整 SemVer，也不处理预发布（[Pkg.h.ct:470-530](../../selfhost/ct-ast/tool/pkg/Pkg.h.ct#L470-L530)）。
- 没有“最高版本”“锁升级”“冲突回溯”；多个约束不能同时满足时，通常表现为 lock 里只有一个版本 + `install` 报某个直接依赖不满足。
- 同一裸名不同 publisher 也走裸名去重，不能在同一 lock 共存；索引的歧义检查只发生在**裸名查找**，限定名查找不解决 lock 合并冲突。

#### Dev override

- `dir` 行按裸名覆盖 `git` 行；`ct build` 打 note，`ct verify --strict` 拒绝 `dir` 行。这是“覆盖”，不是版本冲突求解。

### 4.6 ct-fsguard / FSG-02 核实

**核实结果**：

| 说法 | 结论 | 证据 |
| --- | --- | --- |
| ct-fsguard 在 `ct.pkg` 写 `dep = std@0.3.2` | **属实** | `/Users/samxx/trae-ws/ct-fsguard/ct.pkg` 末行 `dep = std@0.3.2` |
| `ct.lock` 已提交 | **属实** | `git ls-files ct.pkg ct.lock` 两者都在；lock 行 `std/std 0.3.2 git https://github.com/ct-pkg/std a3f1217... . sha256:95fc...` |
| `ct build` 自动补 `-I` | **属实（机制）** | T2 用例：无手写 `-I`，cc 行出现 store 的 `-I`；`ct install` 打印的命令不含 `-I` |
| `ct install` 在根单元 import `.m.ct` 时误报 | **属实，仍 open** | T1 用例在 v0.63.2 复现：`cannot resolve import 'std/fs/Fs'`，rc=1；同一工程 `ct build` rc=0 |
| `ct install` 在任何 fsguard 工程都失败 | **不准确** | 在 ct-fsguard 仓根直接跑 `ct install` 会成功（根目录没有 `.ct` 单元可扫描）；缺陷只在“工程根单元 import 了 `.m.ct`”时触发 |

FSG-02 的根因在当前代码仍在：`ct install` 的 import 校验只试 `%s.h.ct` 和 `%s.ct`，没有 `%s.m.ct`（[Pkg.h.ct:1510-1521](../../selfhost/ct-ast/tool/pkg/Pkg.h.ct#L1510-L1521)）；编译器本身是支持 `.m.ct` 的（[Module.h.ct:2410-2436](../../selfhost/ct-ast/frontend/module/Module.h.ct#L2410-L2436)）。FSG-02 在 ct-fsguard 仓仍标 `status: open`、`opened: 2026-11-16`（`issues/FSG-02.md:4-5`）；issue 里的锚点是旧行号 `Pkg.h.ct:1609-1618`，当前对应位置是 `Pkg.h.ct:1510-1526`（代码前移）。本次在 v0.63.2 再次复现。

另一个重要限定：fsguard 的 `std@0.3.2` 能工作，是因为 **lock 已提交、store 已存在**；当前官方索引仍停在 `std 0.2.0` 五字段，不能用 `ct get std@0.3.2` 在新机器上重建这份 lock（§2.3）。直接 URL `ct get https://github.com/ct-pkg/std@0.3.2` 可以重建（W 用例），说明包本身已合规，缺的是索引刷新。

## 5. 缺口与方案取舍

### 5.1 缺口清单

| 编号 | 缺口 | 影响 | 归属 |
| --- | --- | --- | --- |
| G1 | 没有默认索引，也不自动下载 | 开箱即用时限定名必失败 | 工具侧（可选） |
| G2 | 生产端五字段，消费端六字段 | 官方索引无法解析限定名 | 索引生产 + 工具契约 |
| G3 | 索引指向的官方版本（std 0.2.0 等）缺 `publisher`/`ns-root`；std 0.3.2 已补但未入索引 | 即使索引正确，0.2.0 仍被 store 拒绝；0.3.2 只能走 URL/本地 | 包仓 + 索引生产（PH-54 S4 移出后无人跟踪） |
| G4 | 限定名在索引缺失时落 URL clone | 诊断误导，可能 clone 到错误来源 | 工具侧 |
| G5 | 非法 sha 行导致 rc=1 但无任何 stderr | 不可诊断 | 工具侧 |
| G6 | 索引 publisher 与清单 publisher 不一致不报错 | 请求 `zed/hello` 可静默得到 `acme/hello` | 工具侧（安全/正确性） |
| G7 | 生产端只收最高 tag，旧版本行被重建删除；索引还停在 std 0.2.0 | 精确旧版本与多版本 MVS 不可用；0.3.2 不可经索引获取 | 索引生产 |
| G8 | 没有 `ct pkg digest` 或等价命令 | 发布者只能依赖外部脚本，易与 `ct` 算法漂移 | 工具侧 |
| G9 | 没有索引签名/固定索引提交的消费契约 | 供应链不可审计；提案要求但未实现 | 索引生产 + 工具侧 |
| G10 | 版本范围无匹配与包名不存在共用 `is not in the index` | 无法区分“名字错”与“版本不够” | 工具侧 |
| G11 | 索引测试只覆盖五字段裸名、六字段夹具；未覆盖官方五字段+限定名、publisher 不一致、缺身份官方包 | 回归盲区 | 工具侧测试 |
| G12 | 依赖声明/获取/锁定/import 没有专题回归：`dep` 列表语法负例、`.m.ct` install 假阳性、传递同名不同版本 | FSG-02 与冲突问题只能靠外部包发现 | 工具侧测试 |
| G13 | 没有依赖冲突求解：同名按裸名 first-win，lock 一行，install 只查直接依赖 | 传递冲突可静默产出不健全 lock | 工具侧（设计缺口） |

### 5.2 三条路

#### A. 纯本地目录包根

做法：依赖用 `ct get ./path`（或 `dep = ../pkg`），包树落 store，lock 写 `dir` 行；不引入远程索引。

| 维度 | 评估 |
| --- | --- |
| 建设成本 | 最低；不需要索引仓、CI、签名 |
| 运行成本 | 每个消费者要有全部依赖的本地 checkout；路径/分支靠人保证 |
| 前置条件 | 包清单必须有 `publisher`/`ns-root`；否则 store 仍拒绝 |
| 工具侧改动 | 基本不需要；可选补 `dir` 行的可追溯性 |
| 语言侧改动 | 无 |
| 当前可用度 | 高（开发/单仓）；不适合对外分发 |
| 主要风险 | 版本不可复现、CI 必须预置所有 checkout、没有包名到来源的公共映射 |

#### B. 远程索引

做法：六字段索引由外部 CI 生成，消费者用 `--index` / `CT_INDEX` 指向本地副本（可选再做默认索引/自动更新）。

| 维度 | 评估 |
| --- | --- |
| 建设成本 | 高：索引仓、生成器、allowlist、release 触达、摘要工具、签名/固定提交 |
| 运行成本 | 中：索引 nightly 重建；发布者要遵守 tag/版本纪律 |
| 前置条件 | 生产端输出六字段；每个包有 `publisher`/`ns-root`；需要多版本时按版本多行；官方包重新发版 |
| 工具侧改动 | 需要：默认索引（可选）、缺失条目硬错、非法行诊断、publisher 一致性校验、`ct pkg digest`、索引签名/固定 |
| 语言侧改动 | 无；`import` 仍是 namespace 形态，不需要改语言 |
| 当前可用度 | 消费端已可用；生产端与官方包未对齐，端到端不可用 |
| 主要风险 | 索引与包仓身份漂移；只有最高 tag 时无法复现旧版本；供应链信任 |

#### C. 两者混合

做法：本地目录作为 dev override，发布包走远程索引；两者最终都落 store + v2 lock，`ct build` 统一消费。

| 维度 | 评估 |
| --- | --- |
| 建设成本 | 中：复用 A 的本地路径与 B 的索引，只需明确优先级与留痕 |
| 运行成本 | 中：开发离线可跑，发布可复现 |
| 前置条件 | 同 B 的索引与包身份；外加 dev override 的优先级规则（现有 `dir` 行 + `ct build` 已基本具备） |
| 工具侧改动 | 需要：B 的诊断/摘要/校验，加上 override 的显式提示与 `--strict` 口径 |
| 语言侧改动 | 无 |
| 当前可用度 | 最高；与现有 `dir`/`git` 双行模型一致 |
| 主要风险 | 两套来源的优先级若不明示，容易出现“本地能编、CI 不能编” |

### 5.3 建议

1. **短期先修工具侧，不新起机制**：
   - 限定名索引未命中改为硬错，不再落 `https://<publisher>/<name>`（G4）；
   - 非法索引行给出文件与行号（G5）；
   - 校验索引 `publisher` 与清单 `publisher` 一致（G6）；
   - 提供 `ct pkg digest` 或等价只读命令（G8）；
   - 版本无匹配与包名不存在分开报错（G10）；
   - `ct install` 的 import 校验补 `.m.ct`，修 FSG-02（G12）；
   - 传递依赖同名不同版本不要再静默 first-win，至少给出硬错（G13）。
2. **同时修数据**：索引指向的旧官方版本补 `publisher`/`ns-root`，或直接把索引刷到已合规的新版本（`std 0.3.2` 已有身份）；生产端改六字段。没有这两步，默认索引或新提案都无法端到端跑通（G2/G3）。
3. **中期再接受索引提案**：保留五字段读兼容，但生产端必须六字段、可多版本、可固定提交；签名/allowlist 与 CI 生成一并落地（G7/G9）。
4. **暂不把索引设为默认**：在官方包通过 `ct get <publisher>/<name>` 端到端验收前，默认索引只会把 L1 的明确报错换成 L2/L4 的误导报错。
5. **依赖语义单独决策**：lock 目前按裸包名一行，等于“一个项目只能有一个版本的某包”；如果要多版本共存，需要改 lock 键与构建 root 选择，这是工具侧设计变更，不是索引能解决的。

语言侧不需要为索引改动。只有当希望 `import` 本身携带 publisher 时，才涉及语言与工具同时改；这不是当前索引机制的前置条件。现有 `import` 仍按 namespace 解析，`dep` 才携带 `publisher/name`。

## 6. 已登记的 issue 与 phase

### 6.1 已解，不要重做

| 编号 | 状态 | 与索引的关系 | 证据 |
| --- | --- | --- | --- |
| Phase 17.5 | 已交付 | 显式索引、`CT_INDEX`/`--index`、五字段 | [phase18.md:51](../history/design/phase18.md#L51) |
| Phase 18.2 / D18-7 | 已交付（历史） | `ct-pkg/index`、五字段、gen/refresh、nightly | [phase18.md:94](../history/design/phase18.md#L94)、`:135`、`:177` |
| Phase 20 P20-05 | 已交付后续 | 索引生成器移出本仓；消费端范围查询后补 | [phase-log.md:31](../history/phase-log.md#L31) |
| PH-54 S1（v0.55.0） | 已交付 | 六字段、`publisher`/`ns-root`、限定名、歧义硬错、多版本 store | [phase54.md:93-102](../design/phase54.md#L93-L102) |
| PH-54 S2/S3/S5/S6 | 已交付 | build 读 lock、verify/migrate/update、双 HOME 复现 | [phase54.md:106-137](../design/phase54.md#L106-L137) |
| PH-63 S7（v0.62.0） | 已交付 | 删 `vendor/`；缺身份字段在 store 提交处硬错 | [phase63.md:24-38](../design/phase63.md#L24-L38) |
| SH-81（v0.61.1） | 已修 | 无索引时限定名不再被当成 URL，给出解析指引 | [issues/README.md:343](../../issues/README.md#L343)、[phase-log.md:183](../history/phase-log.md#L183) |
| SH-83（v0.61.1） | 已修 | `ct install` v2 不再打印 `-I` | [issues/README.md:345](../../issues/README.md#L345) |
| PKG-2/4/5/7/8 | 已修 | 包根/同名/缓存键/lock 读取/override 留痕 | [issues/README.md:353-359](../../issues/README.md#L353-L359) |
| PKG-3 | 已修（issue 内） | 未知键告警，v0.58.3 | issue 状态行 `:10`；[phase-log.md:180](../history/phase-log.md#L180) |
| PKG-6 | 已修（issue 内） | install 试解析 import，v0.58.2 | issue 状态行 `:10`；[phase-log.md:179](../history/phase-log.md#L179) |
| PKG-9 | 实际已修 | S7 后缺身份字段直接失败，不再静默退 v1 | [phase63.md:36](../design/phase63.md#L36) |

### 6.2 仍 open / 待决策

| 编号 | 状态 | 说明 |
| --- | --- | --- |
| PKG-9 issue | 文本仍写 **open** | 代码已由 PH-63 S7 修掉；issue 与 `post-58` 未回填（[pkg-9…md:9](../../issues/packages/pkg-9-missing-identity-fields-silent-v1-lock.md#L9)、[post-58-phase-sequence.md:35](../planning/post-58-phase-sequence.md#L35)） |
| 索引提案 | **待评估**，无 phase | [ct-pkg-index-proposal.md](../proposals/ct-pkg-index-proposal.md) 未接受；没有对应 phase 或 decision |
| 包维护者规则提案 | **待评估** | 依赖 `ct pkg digest`，该命令未实现（[ct-pkg-package-maintainer-rules.md:61-66](../proposals/ct-pkg-package-maintainer-rules.md#L61-L66)） |
| `packages.yml` host/target | **暂停** `if: false` | TODO 说 `ct-pkg/index` 为空、std/hal-posix 无 v0.1.0 tag（[packages.yml:44-51](../../.github/workflows/packages.yml#L44-L51)、`:92-95`）；该前提已过期，但 job 仍暂停 |
| FSG-02（ct-fsguard） | **open**，外部包登记 | `ct install` 只 import `.m.ct` 时误报；v0.63.2 仍复现（见 §4.6），修在 CT 侧，不是 fsguard 侧 |
| G4/G5/G6/G7/G8/G9/G10/G12/G13 | **未登记 issue** | 本次梳理新增的缺口，尚无 CT 仓 issue 编号 |

### 6.3 已取消，不要重开

- SH-80：包发布前清单校验只验四字段存在，属发布侧判据，已取消（[issues/README.md:342](../../issues/README.md#L342)）。
- SH-84：`ct verify --strict` 拒绝 dev override 符合 SP-016，已取消（[issues/README.md:346](../../issues/README.md#L346)）。

## 7. 文档过期与旧路径

### 7.1 过期陈述

| 位置 | 原文/含义 | 现状 | 建议 |
| --- | --- | --- | --- |
| [glossary.md:158](../glossary.md#L158) | 索引“五字段”“仅在 `ct get` 的裸名时查询” | 消费端已六字段；限定名也查索引 | 改为六字段 + 裸名/限定名两种匹配 |
| [glossary.md:155](../glossary.md#L155) | `ct install` 把各包 `-I` 拼进一条命令 | SH-83 后 v2 不再打印 `-I` | 删掉 `-I` 拼接说法 |
| [glossary.md:228](../glossary.md#L228) | 索引仓五字段、gen/refresh、夜间刷新 | 大体正确，但未提六字段消费端与“只有最高 tag” | 补契约分叉与版本限制 |
| [package-guide.md:118](../package-guide.md#L118) | `ct install` “打印带 store ns-root 的 `ct build` 命令” | 实际不打印 `-I` | 改为“打印命令；`ct build` 自动补 store `-I`” |
| [package-guide.md:177](../package-guide.md#L177) | “`ct install` 打印的也是这个目录” | v2 不打印该目录 | 同上 |
| [package-guide.md:180-184](../package-guide.md#L180-L184) | “`ct install` 的 `-I` 形态，且不校验 import” | `-I` 不再打印；PKG-6 已改为试解析 import | 改标题与正文 |
| [package-guide.md:158](../package-guide.md#L158) | “无索引时裸名无法解析” | 裸名无索引仍可走 `CT_REGISTRY` | 改为“限定名无法解析；裸名走 registry” |
| [package-guide.md:70](../package-guide.md#L70) | 未知键“忽略” | PKG-3 后未知键会告警 | 改为“告警并忽略” |
| [tutorial.md:706-711](../tutorial.md#L706-L711) | 示例 `ct get ct/std@^0.1.0`，并称发布方 `ct` | 当前必失败；且 `std 0.3.2` 清单 `publisher = std`，正确限定名是 `std/std` | 标注为待发布，改成 `std/std` 或本地夹具 |
| [package-guide.md:81](../package-guide.md#L81) | `requires` 只写编译器约束 | 实现正确；但示例容易让人误写成 `requires = std ...` | 加一条反例指向 `dep` |
| [tutorial.md:1746](../tutorial.md#L1746) | `ct update` “v1 沿用旧 vendor 路径重解” | S7 后 v1 直接报错 | 改为 `ct migrate` |
| [tutorial.md:1747](../tutorial.md#L1747) | `ct install` 拼 store 的 `-I` | v2 不打印 `-I` | 同上 |
| [post-58-phase-sequence.md:34-37](../planning/post-58-phase-sequence.md#L34-L37) | PKG-6/PKG-9 open、vendor 仍支持 | 均已被 v0.58.2 / PH-63 改掉 | 该文是 2026-11-15 快照，建议标注“已被后续 phase 取代” |
| [packages.yml:44-51](../../.github/workflows/packages.yml#L44-L51) | “index 为空、std 无 v0.1.0 tag” | 索引已有 12 行但停在 std 0.2.0；上游 std 已 0.3.2 且已补身份 | 更新 TODO：阻塞是索引刷新，不只是 tag |
| [ct-pkg-index-proposal.md:14](../proposals/ct-pkg-index-proposal.md#L14) | “`index 仓` 尚不存在，无对应实现” | 外部仓存在且已维护五字段索引 | 改为“旧五字段索引存在，但不满足本提案六字段契约” |
| [ct-pkg-index-proposal.md:45](../proposals/ct-pkg-index-proposal.md#L45) | “一行对应一个版本”；消费者取最低满足版本 | 外部生成器每个包只保留最高 tag 一行 | 生产端多版本是前置，不是已实现 |
| [README.md:450](../../README.md#L450) / [README.en.md:44](../../README.en.md#L44) | 只写“裸名可经索引” | 限定名也依赖索引 | 补限定名路径 |

### 7.2 旧路径引用

用户给的旧路径 `/Users/samxx/trae-ws/ct-lang` 已不存在（`/Users/samxx/trae-ws` 仍在，但下面没有 `ct-lang`）。全仓仍有 **13 个文件、47 行**引用旧路径：

| 类别 | 文件 | 行数 | 处理建议 |
| --- | --- | --- | --- |
| 现行设计文档 | `docs/design/v043-split-plan.md` | 1 | 改成 `dsh-ws` 路径或改为相对路径 |
| 现行设计文档 | `docs/design/phase46-52-plan.md` | 1 | 同上 |
| 规范草稿 | `docs/spec/ai-coding-workflow.md` | 1 | `:1334` 的 ct-lang 路径；`:7` 的 `/Users/samxx/trae-ws` 适用范围也过期 |
| 复核记录 | `docs/review/builtin-layer-vs-std-package-name-check.md` | 1 | 可改为相对引用 |
| 历史设计 | `docs/history/design/phase45.md` | 1 | 历史记录，建议保留原文并加“路径已迁移”注 |
| 历史报告 | `docs/history/reports/phase31-s20b-review/…` | 9 | 历史证据，保留原文 |
| 历史报告 | `docs/history/reports/phase36-delta-review/…` | 2 | 同上 |
| 历史报告 | `docs/history/reports/phase36-delta-rereview/…` | 5 | 同上 |
| battle 证据 | `battle/langcap-1/verdict.md` / `verify.json` | 1 / 12 | 证据快照，保留原文 |
| 探针基线 | `test/probes/p32_check_baseline.txt` | 3 | 基线快照，保留原文；新探针用新路径 |
| 探针基线 | `test/probes/p33_check_baseline.txt` | 7 | 同上 |
| 探针基线 | `test/probes/p34_check_baseline.txt` | 3 | 同上 |

原则：**现行文档改；历史报告/ battle / 探针基线不改正文**，因为它们记录的是当时的原始命令与输出，改了就失去证据价值。可以在这类文件头部加一行“路径已迁移，原文保留”。

`AGENTS.md` 里的 `/Users/samxx/trae-ws/.ai-engineering` 仍然有效（该目录存在），不属于本次旧路径清理范围。

## 8. 验证记录

### 8.1 环境

- 仓内 `ct-ast v0.63.2`，从 `selfhost` 链现场构建到 `/tmp/pkgi/bin/ct-ast`。
- 根目录 `./ctc` 是 L0 引导编译器，`./ctc get` 不存在，不能作为包管理器复现入口。
- 完整包测试：`bash test/pkg/run.sh`，结果 `142 passed, 0 failed`。

### 8.2 关键命令与输出

**A. 无索引 + 限定名**

```sh
env -u CT_INDEX CT_HOME=/tmp/pkgi/ev-a/home HOME=/tmp/pkgi/ev-a/home \
  /tmp/pkgi/bin/ct-ast get ct/std
```

```text
ctc: no index resolver for 'ct/std'
  'ct/std' is a publisher-qualified package name; without an index
  there is no mapping from that name to a git URL.
  ...
```

**B. 有索引但索引没有该条目**

```sh
CT_INDEX=<只有 other 的索引> ct-ast get acme/hello
```

```text
ctc: git clone of 'https://acme/hello' failed
```

限定名没有报 `is not in the index`，而是落到 URL，这是 G4。

**C. 六字段索引 + 限定名（消费者可用）**

```sh
CT_INDEX=<acme/hello 六字段索引> ct-ast get acme/hello@^0.1.0
```

```text
installed 1 package(s)
# ct-lock 2
acme/hello 0.1.0 git file:///tmp/pkgi/pkg/hello d53f... src sha256:81c7...
```

store 路径：`<CT_HOME>/pkg/acme/hello/0.1.0`。

**D. 裸名歧义**

```text
ctc: 'hello' is ambiguous; write acme/hello or zed/hello
```

**E. 五字段索引 + 限定名**

```text
ctc: git clone of 'https://acme/hello' failed
```

**L. 非法 sha 行**

索引行 `sha256:zzzz`：

```text
rc=1
```

无 stderr，属于 G5。

**M. 官方五字段索引 + `ct/std`**

```text
ctc: git clone of 'https://ct/std' failed
```

**N. 官方索引 + 裸名 `std`**

```text
ctc: '<HOME>/.cache/ct-pkg/std/ct.pkg' is missing 'publisher'
```

**S. 手写六字段 `std 0.2.0` 行（publisher 写 `ct`）+ `ct/std`**

```text
ctc: '<HOME>/.cache/ct-pkg/ct/std/ct.pkg' is missing 'publisher'
```

说明 tag 与摘要已经通过，最后卡在包身份。这里用的仍是索引里的 `std 0.2.0`；`std 0.3.2` 的 publisher 是 `std`，六字段行应写 `std/std`（见 §2.3 末段）。

**P. 精确旧版本**

```text
ctc: package 'std' is not in the index
```

索引只有 `std 0.2.0`，`std@0.1.0` 被拒；文案与“包名不存在”共用，属于 G10。

**T. 索引 publisher 与清单 publisher 不一致**

索引写 `zed/hello`，清单写 `acme`：

```text
installed 1 package(s)
# ct-lock 2
acme/hello 0.1.0 git file:///tmp/pkgi/pkg/hello ... 
```

请求的是 `zed/hello`，实际得到 `acme/hello`，无告警，属于 G6。

**J. 无索引、裸名走 `CT_REGISTRY`**

```sh
env -u CT_INDEX CT_REGISTRY=file:///tmp/pkgi/pkg ... ct-ast get hello@^0.2.0
```

```text
installed 1 package(s)
# ct-lock 2
acme/hello 0.2.0 git file:///tmp/pkgi/pkg/hello ... 
```

**Q. `ct get` / `ct install` 分工**

```console
$ ct install                      # 还没有 lock
ctc: no './ct.lock'; run `ct-ast get` first
rc=1

$ ct get ./demo                   # 本地目录
installed 1 package(s)
$ cat ct.pkg
name = proj
version = 0.1.0
dep = /tmp/pkgi/ref/demo
$ cat ct.lock
# ct-lock 2
acme/demo 0.1.0 dir /tmp/pkgi/ref/demo - src sha256:84ed...

$ ct install                      # lock 在，install 通过
ct-ast build main.ct -o build
rc=0
```

（Q1/Q2/Q3 用例；`ct install` 打印的命令没有 `-I`，见 SH-83。）

**S1/S2. 多依赖写法**

```ini
dep = ../liba
dep = ../libb
```

```console
$ ct get ./app
installed 3 package(s)
```

列表写法：

```ini
dep = ../liba, ../libb
```

```text
ctc: cannot read '/tmp/pkgi/deps/app2/../liba, ../libb/ct.pkg'
```

**S3b/S4b. 未知键与 `requires`**

```text
ctc: package 'app3' has unknown key 'deps'
```

```text
ctc: package 'app4' has an unsupported requires 'std >= 0.1.0';
     use dep = pkg@range for package dependencies
```

两者都只装包自身，不产生依赖。

**U1/U2/U3. get-only、多包、install 只读**

```console
$ ct get ./demo-git && ct build main.ct -o build
installed 1 package(s)
...
build_rc=0
```

```ini
# 连续 get 两个包后的 ct.pkg
dep = /tmp/pkgi/ref/demo-git
dep = /tmp/pkgi/deps/liba
```

```console
$ ct install
ct-ast build main.ct -o build
$ shasum ct.pkg ct.lock   # install 前后一致
```

**V2/V4. 缺 lock 与缺 store**

```text
# 删除 ct.lock
ctc: no './ct.lock'; run `ct-ast get` first      # install
ctc: cannot resolve import 'demo/Util'           # build

# git 行的 store 目录被移走
ctc: 'acme/demo 0.1.0' is not installed at '<store>/acme/demo/0.1.0'
```

（dir 行是例外：V1 用例中 store 移走后 build 仍可用，因为 dir 行直接指向本地源码。）

**S5b/S6b. 传递同名不同版本**

```text
# app -> liba -> libx 0.1.0
# app -> libb -> libx 0.2.0
$ ct get ./app
installed 4 package(s)
$ grep '^acme/libx' ct.lock
acme/libx 0.1.0 dir /tmp/pkgi/deps/libx01 - src sha256:...
$ ct install
rc=0
```

第二个 `libx 0.2.0` 被静默跳过，install 只查直接依赖，未发现。

**T1/T2. FSG-02 在 v0.63.2 复现**

```text
# main.ct: import std::fs::Fs;
$ ct install
ctc: cannot resolve import 'std/fs/Fs'
rc=1

$ ct build main.ct -o build
'cc' -std=c99 -I '<store>/std/std/0.3.2/std/fs' -I '.ctbuild' ...
build_rc=0
```

**W. 绕过索引直接取 std 0.3.2**

```console
$ ct get https://github.com/ct-pkg/std@0.3.2
installed 1 package(s)
$ cat ct.lock
std/std 0.3.2 git https://github.com/ct-pkg/std a3f12172... . sha256:95fc010f...
```

说明 `std 0.3.2` 包本身已合规（`publisher = std`、`ns-root = .`），问题在索引仍停在 0.2.0。

### 8.3 验证副作用说明

`ct` 的 git 缓存路径固定为 `$HOME/.cache/ct-pkg`，不受 `CT_HOME` 影响。早期探针未隔离 `HOME`，在真实 `~/.cache/ct-pkg` 下产生/更新了 `std`、`ct/std`、`acme/hello`、`hello`、`zed/hello` 缓存；后续探针已全部隔离到 `/tmp`。这些缓存未删除，按需可自行清理；仓库工作树与 `ct.pkg` 未被修改（`git status` 干净）。

## 9. 关键代码锚点

| 主题 | 位置 |
| --- | --- |
| 索引“无内建默认” | [Pkg.h.ct:115-118](../../selfhost/ct-ast/tool/pkg/Pkg.h.ct#L115-L118) |
| sha 格式校验 | [Pkg.h.ct:357-366](../../selfhost/ct-ast/tool/pkg/Pkg.h.ct#L357-L366) |
| 版本比较与 `^`/`~` | [Pkg.h.ct:470-530](../../selfhost/ct-ast/tool/pkg/Pkg.h.ct#L470-L530) |
| 裸名 registry 拼 URL | [Pkg.h.ct:676-695](../../selfhost/ct-ast/tool/pkg/Pkg.h.ct#L676-L695) |
| git fetch / tag pin / 摘要 / store / lock | [Pkg.h.ct:837-1034](../../selfhost/ct-ast/tool/pkg/Pkg.h.ct#L837-L1034) |
| `get_spec` 路由与 `no index resolver` | [Pkg.h.ct:1065-1135](../../selfhost/ct-ast/tool/pkg/Pkg.h.ct#L1065-L1135) |
| 本地目录 get | [Pkg.h.ct:1137-1207](../../selfhost/ct-ast/tool/pkg/Pkg.h.ct#L1137-L1207) |
| lock v2 写入/合并 | [Pkg.h.ct:1328-1380](../../selfhost/ct-ast/tool/pkg/Pkg.h.ct#L1328-L1380) |
| install / build 命令 | [Pkg.h.ct:1385-1565](../../selfhost/ct-ast/tool/pkg/Pkg.h.ct#L1385-L1565) |
| `--index` 参数解析 | [Pkg.h.ct:1569-1616](../../selfhost/ct-ast/tool/pkg/Pkg.h.ct#L1569-L1616) |
| store 根与目录 | [Pkg.h.ct:1847-1876](../../selfhost/ct-ast/tool/pkg/Pkg.h.ct#L1847-L1876) |
| store 提交与身份校验 | [Pkg.h.ct:1914-1977](../../selfhost/ct-ast/tool/pkg/Pkg.h.ct#L1914-L1977) |
| 索引解析/匹配/MVS | [Pkg.h.ct:2045-2171](../../selfhost/ct-ast/tool/pkg/Pkg.h.ct#L2045-L2171) |
| `ct build` 从 lock 补根 | [Pkg.h.ct:2775-2822](../../selfhost/ct-ast/tool/pkg/Pkg.h.ct#L2775-L2822) |
| `dep` 逐行解析、16 条上限 | [Pkg.h.ct:419-423](../../selfhost/ct-ast/tool/pkg/Pkg.h.ct#L419-L423) |
| `requires` 只约束编译器 | [Pkg.h.ct:2203-2211](../../selfhost/ct-ast/tool/pkg/Pkg.h.ct#L2203-L2211) |
| 递归 `seen` 按裸名 first-win | [Pkg.h.ct:984-991](../../selfhost/ct-ast/tool/pkg/Pkg.h.ct#L984-L991) |
| lock 合并按裸名去重 | [Pkg.h.ct:2363-2370](../../selfhost/ct-ast/tool/pkg/Pkg.h.ct#L2363-L2370) |
| install 只查 `.h.ct`/`.ct`（FSG-02） | [Pkg.h.ct:1510-1521](../../selfhost/ct-ast/tool/pkg/Pkg.h.ct#L1510-L1521) |
| import 解析 `.h.ct`/`.m.ct` | [Module.h.ct:2410-2447](../../selfhost/ct-ast/frontend/module/Module.h.ct#L2410-L2447) |
| build 追加 lock roots 为 `-I` | [Driver.h.ct:251-258](../../selfhost/ct-ast/tool/driver/Driver.h.ct#L251-L258) |
| 索引测试段 | [test/pkg/run.sh:589-667](../../test/pkg/run.sh#L589-L667)、`:673-739`、`:1251-1254` |
