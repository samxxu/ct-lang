# 规则：包仓如何让包进入索引并被正确消费

> 给各 `pkg 仓` 维护者的操作规则；不是对目标仓状态的裁定。是否采纳、何时接入由各项目组决定。
> 正文用 `pkg 仓`、`index 仓` 占位；配套提案见 [ct-pkg-index-proposal.md](ct-pkg-index-proposal.md)。

## 0. 目标

让包在**首次有效 release** 后被索引，并保证消费者拿到的版本、摘要、依赖与包仓发布内容一致。索引由 `index 仓` 生成，包仓不直接改索引。

## 1. 发布前检查清单

| # | 检查 | 判据 |
| --- | --- | --- |
| 1 | `ct.pkg` 在包根 | 文件存在，键值可解析 |
| 2 | 身份完整 | `name`、`publisher`、`ns-root`、`version` 都有 |
| 3 | 版本与 tag 一致 | `ct.pkg` 的 `version` = tag 的 `x.y.z` |
| 4 | `ns-root` 合法 | 相对路径、存在、无 `..`、不是绝对路径 |
| 5 | 命名空间目录 | `namespace a::b;` 的单元在 `<ns-root>/a/b/` |
| 6 | 依赖可解析 | `dep` 的范围有对应版本；`requires` 满足目标 CT |
| 7 | 包可消费 | 干净工程 `ct get --index` + `ct install` 成功 |
| 8 | 生成物未入库 | 不放 `.c/.h/.o`、缓存、vendor 构建产物 |
| 9 | tag 不可变 | 发布后不移动、不重建同版本 |
| 10 | 通知索引 | release workflow 发 dispatch，或已加入 allowlist 等扫描 |

## 2. `ct.pkg` 规则

必需键：

- `name`：小写字母/数字/连字符，不以连字符开头；
- `publisher`：发布方；不能是保留字 `local`；与 `name` 组成 `publisher/name`；
- `ns-root`：包内单元树根，相对包根；目录必须存在；
- `version`：`x.y.z`；预发布/构建元数据不纳入工具解析。

可选键：`dep`（可重复）、`cflags`、`ldflags`、`requires`、`licence`。未知键当前忽略，但不要依赖未知键表达发布语义。

## 3. tag 与 release

- 用 `vX.Y.Z` 或 `X.Y.Z` 的 semver tag；tag 指向包含 `ct.pkg` 的提交；
- 一个版本一个 tag；**不要移动/强推/重建 tag**；
- 同一版本内容变化 → 发新 patch，不覆盖旧 tag；
- prerelease/draft 默认不进索引；需要时在包仓 release 说明中标注；
- tag 与 `ct.pkg` 的 `version` 必须一致；不一致时索引生成器拒绝；
- 建议保护 tag、开启 2FA、CODEOWNERS 审核。

## 4. 通知索引

首选：release workflow 在 tag 成功后调用 `index 仓` 的 `repository_dispatch`：

- `event_type`：`pkg-release`；
- payload：`repo`、`tag`、可选 `sha`；
- 使用最小权限 token/secret；token 只允许向 `index 仓` 发 dispatch；
- 失败不影响包仓发布，但要在日志里明确“索引未通知”。

兜底：把包仓加入 `index 仓` 的 `packages.txt`，由定时扫描发现新 tag。  
**不要**直接提交/修改 `index` 文件；索引只由 `index 仓` 的 CI 写。

## 5. digest 规则

索引行的 `sha256` 是包树摘要，不是 git commit sha。要求：

- 只发布源文件；不要包含生成物、缓存、vendor 构建产物；
- 统一换行/路径；不要依赖时间戳、随机数、构建机路径；
- 不手写/手改 digest；由 `index 仓` 生成器或统一的 `ct pkg digest` 计算；
- 同一 tag 重跑生成器应得到同一 digest；
- digest 不一致时不要“改索引凑合”，查包树是否被改过。

## 6. 依赖与构建元数据

- `dep` 用受支持范围：`^x.y.z`、`~x.y.z`、`>=`/`>`/`<`/`<=`/`=`、裸版本、`*`；多条件空格 AND；
- `requires` 写编译器版本约束；不满足时 `ct get`/`ct install` 失败，`--force` 才降级；
- `cflags`/`ldflags` 只放消费者需要的内容，不要放本机路径；
- 依赖包也必须可索引；不要依赖未发布的本地目录。

## 7. 失败、撤回与安全

- 索引生成失败：看 `reports/` 的原因，修 `ct.pkg`/tag/包树；不要删除失败报告；
- 撤回版本：在 `index 仓` 走撤回/advisory，不移动 tag；旧 `ct.lock` 仍按 digest 复现；
- 包仓被攻破：立即 revoke token、发 advisory、通知索引组；索引组可临时移除行；
- 不要把手写 token、私钥、构建机路径提交到包仓；
- 不要把未审核的 fork/临时仓库加入 allowlist。

## 8. 自检命令

在干净临时工程：

- 准备本地索引文件（由 `index 仓` 生成）；
- `CT_INDEX=<file> ct get <publisher>/<name>@<range>`；
- `ct install` 检查依赖覆盖与打印命令；
- 用 `ct build` 编译示例，确认 `ns-root`/`cflags`/`ldflags` 生效；
- 检查 `ct.lock` 的 digest 与索引行一致；
- 删除缓存/换 `CT_HOME` 重跑一次，确认可复现。

## 9. 常见失败

| 现象 | 原因 | 处置 |
| --- | --- | --- |
| `no index resolver` | 用了 publisher 限定名但没有索引 | 配 `CT_INDEX`；或确认包已进索引 |
| `package '<name>' is not in the index` | 名字/版本未收录 | 检查 allowlist、tag、`ct.pkg` |
| `does not match the index` | digest 与索引不一致 | 查包树是否改动；不要改索引 |
| `namespace ... does not match directory` | 单元目录与 namespace 不一致 | 移到 `<ns-root>/a/b/` |
| `publisher`/`ns-root` 缺失 | S1 后必填 | 补键；`local` 保留字不可用 |
| `version` 与 tag 不一致 | 版本漂移 | 改 `ct.pkg` 或重发正确 tag |
| `requires` 不满足 | 编译器版本过旧 | 升级；确需继续用 `--force` 并记录 |

## 10. 交付给索引组的材料

- 包仓 URL、默认分支、`ct.pkg` 路径；
- 首个 semver tag 与 release 说明；
- 是否已配置 `pkg-release` dispatch；
- 维护者联系人/安全联系人；
- 需要加入 `packages.txt` 的申请（由索引组审核）。

索引组只按 `index 仓` 的规则生成；包仓不预设索引编号、phase 或排期。
