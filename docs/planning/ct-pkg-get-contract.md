# `ct get` × `package.sh` 契约（消费端 / 发布端）

| 项 | 值 |
| --- | --- |
| 性质 | 跨仓契约草案（需求与计划）；不占 phase |
| 日期 | 2026-11-19 |
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
| I12 | 格式变更必须两端协同发布，并用全量 `verify-index` 回归；五字段旧行只读兼容 | 新旧消费者分裂 |

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
- 五字段旧行仍可解析，但缺 `publisher` 无法落 store，属于**不可安装**的兼容形态。

### 3.3 `ct.lock` v2

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

## 7. 失败与退出码

| 场景 | 发布端 | 消费端 |
| --- | --- | --- |
| 清单缺身份字段 | 预检失败，不写索引 | 取回后硬错，不写 store/lock |
| tag 与版本不一致 | 预检失败 | 索引行不应存在；若存在，按行内 tag 取回后仍以清单校验 |
| 摘要不一致 | 生成器拒绝写行/索引报错 | `does not match ct.lock` 或索引摘要不符，硬错 |
| 包不可安装 | 回放失败，索引不推送 | 不产生 lock 行 |
| `requires` 不满足 | 预检失败 | `ct get` 失败且不改 lock；`--force` 告警继续 |
| 网络/凭据失败 | 中止，索引原样 | `ct get` 失败；其余子命令不受影响 |

## 8. 兼容与迁移

- **五字段旧行**：消费端可解析，但因无 `publisher` 无法落 store；生成端已停止产出。新行一律六字段。
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
4. 五字段行：可解析但安装失败，提示六字段；
5. 隔离 `HOME` / `CT_HOME`、空 store：仍成功；
6. 失败后既有 lock 逐字节不变。

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

## 11. 变更与归属

| 契约面 | 归属 | 变更要求 |
| --- | --- | --- |
| `ct get` / lock / store / 摘要算法 | ct-lang | 先改本契约，再改实现与夹具 |
| `ct.pkg` 键、tag 规则、预检 | ct-pkg 包仓 + index 仓 | 索引生成器先接受，包仓再发布 |
| 索引行格式、生成/回放脚本 | ct-pkg/index | 全量 `verify-index` + CT 侧兼容 |
| `ct pkg` 边界 | ct-lang（需求方 2026-11-19 定稿 B′） | 复开透传必须显式登记并覆盖既有裁决 |
