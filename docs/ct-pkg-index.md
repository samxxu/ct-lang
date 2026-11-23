# ct-pkg 索引：字段、解析与信任边界

> 中文
>
> 说明 `ct-pkg/index` 的 `index` 文件**当前长什么样**、消费端怎么解析、哪些是目标形态。
> 本文与 [proposals/ct-pkg-index-proposal.md](proposals/ct-pkg-index-proposal.md) 的区别：
> 提案是**待目标组受理的目标形态**，不是现状；现状以本文与
> [ct-pkg-get-contract](planning/ct-pkg-get-contract.md) 为准。
> 核对基线：ct 0.77.1（2026-11-20）。

## 1. 它是什么

`index` 是纯文本、空白分隔、**一行一个版本**的清单；同一个包可以有多行。消费端按版本范围取
最低满足版本（MVS）；不带范围 / `*` 取最高版本。

索引**不是**包清单（`ct.pkg`），也不随包发布；它是 `ct-pkg/index` 仓的构建产物。

## 2. 两种行形态（当前并存）

| 形态 | 字段 | 当前地位 |
| --- | --- | --- |
| **六字段**（现行） | `name version publisher git-url tag sha256:<hex>` | 能落共享 store；官方 `std` 行已是六字段 |
| **五字段**（旧行） | `name version git-url tag sha256:<hex>` | **按行硬错**（[D-014](decisions/D-014.md) 第 5 条）：请求命中即失败，提示六字段；其余六字段行不受影响 |

实现现状（v0.83.0）：`ct get` 的索引查找命中五字段旧行即硬错（[D-014](decisions/D-014.md)
第 5 条）；`ct index verify` 只读扫描整份索引，逐行报出旧行与坏行（契约 v1 §4.4，
[v0-PH-83](phases/v0-PH-83/card.md)）。生成端已停止产出五字段新行；index 仓清零旧行是发布前置。

实测当前官方索引的字段分布（网络可用时）：

```sh
curl -fsSL https://raw.githubusercontent.com/ct-pkg/index/master/index \
  | awk 'NF{print NF}' | sort | uniq -c
```

官方 `std` 行（六字段，2026-11-23 实测）：

```text
std 0.20.0 ct https://github.com/ct-pkg/std v0.20.0 sha256:60d2e7dd157facc775e80d45e6769c4f2bfe7273feed6af7ccba9676d8ae42a7
```

> 五字段/六字段**不是**「当前 vs 目标」的二选一：六字段是现行形态，五字段是仍在文件里的旧行。
> DOC-73 写作时的「当前官方索引五字段、六字段是目标」已被 v0-PH-77 的外部对齐（E77-8）取代。

## 3. 解析与安全边界

| 层 | 信任来源 | 校验 | 失败行为 |
| --- | --- | --- | --- |
| 官方 `ct/<name>`、裸名 | 编译期 **pin 表**（`name` / `version` / `publisher` / `url` / `tag` / `sha256`） | 按 pin 的 tag 取内容，再按 `ct.lock` 同一算法比对 `sha256`；默认不读可变索引 | 摘要或身份不符即硬错，不落 store、不写锁 |
| 第三方 `<pub>/<name>` | 调用方显式给出的索引 / URL / 本地目录 | 索引行的 `tag` + `sha256` 与拉到的内容比对；索引本身**无签名**；`ct index verify` 可先做只读结构校验 | 索引不可读、缺行或摘要不符即硬错 |

- `--index <file>` / `CT_INDEX=<file>` 都是**显式**输入；`ct` 不默认联网、不自动 clone 索引。
- 裸名只查内置 pin 表；第三方必须写 `<publisher>/<name>`。
- **不要声称索引可信**：六字段的 `publisher` 只是身份字段，不是签名；pin / 签名尚未落地，
  更强的保证用显式 URL 并让 `ct.lock` 钉住摘要。

## 4. 发布入口

- 包的 tag / release / 索引行由 `ct-pkg/index` 仓的 `tools/package.sh` 与 CI 负责；需要 token。
- 发布脚本**不进 `ct` 二进制**：`ct pkg check <dir>` 只是原生只读 preflight（B′，见
  [ct-pkg](ct-pkg.md)），不是发布命令。
- 消费者只读索引，不在客户端扫描组织或自动 trust 新包。
- `ct index verify [<file>] [--json]` 是本地只读审计：不联网、不写 store/lock；退出码
  0 合法 / 1 有坏行（逐行给行号）/ 2 用法或不可读。单索引 `<file>` > `CT_INDEX` >
  `$CT_HOME/index/index`。

## 5. 现状 vs 提案

| 项 | 现状 | 提案（待目标组受理） |
| --- | --- | --- |
| 字段 | 六字段现行；五字段旧行按行硬错（契约 v1；落地见 PKG-13） | 六字段 + 撤回规则 + schema |
| 签名 / pin | **未落地**；只有官方 pin 表的 sha256 强校验 | `index.sig` / 签名 tag / 受保护提交 |
| 生成 | 索引仓 `tools/package.sh` + CI | 定时扫描 + allowlist + 可重放生成 |
| 客户端 | 显式 `--index` / `CT_INDEX`；不联网 | 不改变「客户端不扫描组织」 |

目标形态、六项交付信息与受理边界见
[proposals/ct-pkg-index-proposal.md](proposals/ct-pkg-index-proposal.md)；
在提案被受理并实现前，**不得**把签名、自动索引或六字段以外的格式写成现状。
