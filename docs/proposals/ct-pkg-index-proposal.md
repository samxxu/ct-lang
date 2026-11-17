# 提案：包索引仓的生成、签名与消费

> 按跨项目提案规范：本文只提交提案；是否受理、编号、落点与排期由目标项目组决定。正文用
> `index 仓`、`pkg 仓` 作为占位，交付时替换为目标仓名。

## 0. 交付信息（六项）

| 项 | 内容 |
| --- | --- |
| 现象 | 消费者执行 `ct get <publisher>/<name>` 时，若未设置 `CT_INDEX`/`--index`，直接报 `no index resolver`；目前没有一份由组织维护、可审计的索引。 |
| 最小复现 | 在未设置 `CT_INDEX` 的环境执行 `ct get <publisher>/<name>`，rc≠0，stderr 为 `no index resolver for '<publisher>/<name>'`；设置一个索引文件后可解析。 |
| 期望行为 | 由 `index 仓` 在包 release 时生成/更新索引；索引确定、可 diff、可签名、可 pin；消费者只消费固定索引，不在客户端扫描组织。 |
| 影响范围 | 所有使用 publisher 限定名安装包的项目；不改变裸名经 `CT_REGISTRY` 的现有路径。 |
| 实测版本 | CT `v0.63.2`（2026-11-17）；`index 仓` 尚不存在，无对应实现。 |
| 承诺对应 | 无对应承诺条目（目标 `index 仓` 尚无索引契约）。 |

## 1. 一句话

**索引由 `index 仓` 的 CI 生成，不由 `ct` 客户端扫描生成；新包在“首次有效 release”后进入索引，而不是“仓库一创建”就进入。**

## 2. 目标 / 非目标

**目标**

- 新增/发布包后，索引在可预期时间内更新；
- 索引行可追溯：包名、版本、publisher、git URL、tag、tree digest；
- 生成过程确定、可重放、可 diff；
- 支持签名/提交审查/固定 index 版本；
- 消费者可用 `git clone` + `CT_INDEX` 消费。

**非目标**

- 不让 `ct` 内置 HTTP 客户端或 GitHub API；
- 不扫描组织下所有仓库并自动信任；
- 不代替包仓做构建/测试；
- 不自动决定包是否“可信”；
- 不改变 `CT_REGISTRY` 的裸名语义。

## 3. 索引是什么

索引是纯文本、空白分隔的六字段行：

`name version publisher git-url tag sha256:<64 hex>`

一行对应一个**版本**，不是“一个仓库一行”。同一个包可有多个版本行；消费者按版本范围取最低满足版本（MVS）。索引本身是 `index 仓` 的构建产物，不是包仓的附属文件。

## 4. 仓库布局

建议 `index 仓` 只放生成物与生成器：

- `index`：生成的纯文本索引；
- `index.sig`：分离签名（或改用签名 tag/受保护提交）；
- `schema.md`：六字段、版本/撤回规则；
- `packages.txt`：允许自动收录的 `pkg 仓` allowlist；
- `tools/gen-index`：生成器（固定版本、可重放）；
- `.github/workflows/index.yml`：CI；
- `reports/`：每次生成的校验报告（成功/跳过/失败原因）。

包仓不得直接写 `index 仓`；只有 `index 仓` 的 CI 能写。

## 5. 事件模型

| 事件 | 用途 | 说明 |
| --- | --- | --- |
| `repository_dispatch`（`pkg-release`） | 主路径 | 包仓 release/tag 后主动通知；近实时 |
| `schedule`（如每 15–60 分钟） | 兜底 | 发现漏发的 release、补录/修复 |
| `workflow_dispatch` | 手动 | 指定包/版本重跑 |
| org webhook + GitHub App/relay | 可选 | 仅当确实需要“新仓库近实时”时；成本高，不建议先做 |

**GitHub Actions 没有原生的“组织下新建 repo”事件能直接触发另一个仓库的 workflow。** 因此“新仓库创建即自动进索引”不能只靠 `index 仓` 的 workflow 实现；应等首次 release，或用定时扫描/org webhook relay。

## 6. 生成流程

1. 取事件：dispatch 的 `repo`/`tag`，或定时扫描 allowlist 中尚未收录的 repo；
2. 过滤：必须在 `packages.txt`；有 `ct.pkg`；不是 archived/fork/private/空仓库；有 semver tag；
3. checkout 该 tag 到临时目录；校验 `ct.pkg`：`name`、`publisher`、`ns-root`、`version` 与 tag/索引身份一致；`ns-root` 相对、存在、无 `..`；`publisher` 不是保留字；
4. 用**与消费者同一套算法**计算 tree digest；建议由 CT 提供 `ct pkg digest` 或共享脚本，禁止生成器与客户端各写一套；
5. 更新索引：同包同版本原子替换；不同版本保留；按 `name`、版本排序；去重；
6. 在干净环境用生成的 index 跑一次 `ct get --index`/`ct install` 消费夹具，摘要必须匹配；
7. 失败则只写报告、不写索引；
8. 签名/提交：签名索引或使用受保护签名提交；写 `index` 与报告；打 index 版本 tag；
9. 发布：客户端 `git pull` 或取固定 index commit。

## 7. 新仓库如何进入

- **不因“仓库创建”写入索引**：没有 tag/`ct.pkg` 的仓库没有可消费版本；
- 首次合法 release 后，由包仓 workflow 发 `pkg-release`；未配置 dispatch 的，由定时扫描兜底；
- 新仓库需先进入 `packages.txt`（PR + 审核），再被扫描/接收；
- 被跳过的仓库在报告中写原因，不静默。

## 8. 版本、撤回与保留

- 收录所有可解析的 semver tag；prerelease/draft 默认排除；
- 不移动 tag、不重建同版本；内容变化只能发新 patch；
- 撤回：index 仓删除/标记该行，并附 advisory；已有 `ct.lock` 仍按 digest 固定，不能假装没发生；
- 历史 index 版本保留 tag，便于复现；
- 同名跨 publisher 用 `publisher/name` 消歧；index 生成器发现歧义即失败。

## 9. 安全与权限

- `packages.txt` 是 allowlist，不扫全组织；
- `index 仓` 使用 GitHub App/细粒度 token，最小权限；token 只读包仓、只写 index 仓；
- 包仓 tag 保护、2FA、CODEOWNERS；被攻破的包仓不能靠“自动发现”洗白；
- 索引签名/受保护提交；消费者可 pin index commit/tag；
- 生成器记录自身版本、源 commit、生成时间；输出确定；
- 失败关闭：校验失败、digest 不一致、身份不匹配一律不写索引。

## 10. 客户端消费

- 消费者 `git clone`/`git pull` `index 仓`；
- `CT_INDEX=<checkout>/index ct get <publisher>/<name>`；
- 生产环境固定 index commit/tag，升级前 diff；
- 不在 `ct` 客户端内自动扫描组织；未来若要 `ct index update`，另立提案，只走 git 拉取，不内置 HTTP。

## 11. 迁移步骤

1. 建 `index 仓`，写 `schema.md`、`packages.txt`、生成器与 CI；
2. 先收录少量已发布包，手工核对 digest 与 `ct get` 行为；
3. 回填历史版本，生成首版 `index`，签名；
4. 在干净工程用 `CT_INDEX` 跑 `ct get`/`ct install`；
5. 通知包仓接入 release dispatch；定时扫描兜底；
6. 旧的手工索引冻结，只读保留。

## 12. 验收建议

- 索引行能被 `ct get` 解析，`ct.lock` digest 与行内 sha256 一致；
- 同一 tag 重跑生成器，index 逐字节一致；
- 无 tag/无 `ct.pkg`/publisher 不匹配的仓库不写入，报告有原因；
- 删除/撤回后新消费者拿不到，旧 lock 仍可复现；
- 索引 commit 可签名/可 pin；
- 生成器失败不会留下半写索引（原子替换）。

## 13. 风险

| 风险 | 处置 |
| --- | --- |
| 组织内新仓库被误收录 | allowlist + `ct.pkg` + 审核；不扫全 org |
| digest 算法漂移 | 复用消费者同一实现；交叉校验；生成器固定版本 |
| GitHub API 限流/权限 | GitHub App/PAT、分页、缓存；失败不写 |
| tag 移动/重建 | 禁止；digest 变化即拒绝，要求新 patch |
| 索引供应链攻击 | 签名、受保护提交、allowlist、审计 |
| 客户端自动扫描 | 明确不做；只消费固定索引 |

## 14. 请求

请目标组决定：

1. 是否受理本提案；
2. 是否采用“release dispatch + 定时扫描”作为主/兜底；
3. 索引签名形式与客户端是否验签；
4. 生成器用 CT 提供的 digest 接口，还是共享脚本；
5. 是否新建 `index 仓`，以及首版收录范围。

本提案不预设编号、phase、issue 或排期。
