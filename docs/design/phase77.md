# Phase 77 — 官方包身份与解析契约（`ct/std`）

> **状态：完成（S0–S5 / E77-1–E77-8；`v0.77.0`）**（2026-11-19 立项并收口）。
> **前置**：PH-76 先收口；两卡无技术依赖，但按号顺序执行，不插队。
> **布局说明**：phase-ID 迁移仍被 blocker 挡住，本卡暂用 legacy 路径 `docs/design/phase77.md`，迁移时统一改名。
> **依据**：需求方 2026-11-19 裁定；[D-010](../decisions/D-010.md)；[PKG 索引审计](../reviews/2026-11-17-pkg-index-audit.md)；
> [battle index-install-1](../../battle/index-install-1/verdict.md)；[AGENTS 包表](../../AGENTS.md)。

## 0 卡片字段（冻结）

| 项 | 值 |
| --- | --- |
| 编号 | v0-PH-77（legacy 文件 `phase77.md`） |
| 目标 | 官方包 identity 归一为 `ct/std`；裸名只解析官方；`ct get` 展示规范 `url@version`；旧 `std/std` 锁自动迁移 |
| 范围 | 解析器（裸名 / 限定名 / 优先级）、内置官方 pin 表、`ct get` 三种输出、`ct update` 迁移、文档 |
| 非目标 | 不默认联网索引、不 clone index（守 B′）；不改 URL / 本地路径输入；不做包发布自动化；不改编译器核的网络边界 |
| 交付物 | 编译器改动、`test/ast/p77_*` 探针、文档修正、外部对齐清单 |
| 任务清单 | §3（S0–S5） |
| 退出判据 | E77-1…E77-8（§4） |
| version-minor | 77（PH-77，`d=0`） |
| 已知风险 | R77-1…R77-5（§5） |

## 1 背景与裁定

### 1.1 现状

- `install.sh` 安装后推荐 `ct get ct/std`，但无索引时限定名直接硬错（[Pkg.h.ct:1130-1153](../../selfhost/ct-ast/tool/pkg/Pkg.h.ct#L1130-L1153)），
  安装后的第一条包命令就走不通。
- 裸名 `std` 在无索引时回落 `CT_REGISTRY` 并取**最高 tag**（[Pkg.h.ct:698-712](../../selfhost/ct-ast/tool/pkg/Pkg.h.ct#L698-L712)），结果随上游漂移。
- `ct-pkg/std` 清单写 `publisher = std`，与 AGENTS 包表假定的 `$CT_HOME/pkg/ct/std/<version>/` 不一致（[AGENTS.md:579](../../AGENTS.md#L579)）。
- 官方索引为五字段、无 `publisher`；`std 0.2.0` 清单缺 `publisher`/`ns-root`，裸名命中也会在 store 提交处失败。

### 1.2 需求方裁定（2026-11-19）

| 项 | 裁定 |
| --- | --- |
| 官方 identity | `publisher = ct`，规范名 `ct/std`；`std/std` 是错误身份，要改 |
| 裸名省略 | 仅官方：`std` ≡ `ct/std`；第三方必须 `publisher/std`，同名也不例外 |
| 版本展示 | `url@<包版本>`，tag 另列 |
| 官方版本来源 | 内置 pin 表（url + tag + sha256），随 `ct` 版本更新 |
| 旧锁 | `ct update` 自动迁移 `std/std` → `ct/std`，打印迁移行；旧 store 不删 |
| 立项 | 按 D-005 独立开卡，文档修正随卡收，不混进 patch |

### 1.3 偏差方

本仓规范（AGENTS 包表、package-guide 六字段、`ct/std` store 路径）已是目标形态；偏差在
`ct-pkg/std` 清单与 `ct-pkg/index` 行。外部对齐见 §7。

### 1.4 开工障碍清零（2026-11-19）

| 障碍 | 处置 |
| --- | --- |
| 原「前置 PH-76」 | 按号顺序：PH-76 先开卡（`v0.76.0`），本卡随后（`v0.77.0`）；两卡无技术依赖但不插队 |
| S0 决策未落 | 已落 [D-010](../decisions/D-010.md)（官方身份、裸名、pin 表、迁移、`ct pkg` B′） |
| 外部 std/索引未对齐 | 只阻塞 E77-8 与收口，不阻塞 S0–S4；S5 单独验收 |
| 版本位 | `phase = MINOR`（PN-2）：PH-76 → `v0.76.0`、PH-77 → `v0.77.0`，不做偏移 |
| phase-ID 迁移未完成 | 按既有偏差使用 legacy 路径，不阻塞 |
| 发布/消费边界未成文 | [ct-pkg-get-contract](../planning/ct-pkg-get-contract.md) 已定稿，`ct pkg` 保持 B′ |

## 2 契约（冻结）

### 2.1 身份

- 官方包：`publisher = ct`，锁行与 store 路径均为 `ct/<name>`；
- 第三方包：`publisher/<name>`，`publisher` 不得省略，也不得因重名而借用官方裸名；
- 旧 `std/std` 只作为**迁移来源**识别，不再作为新锁的写入形态。

### 2.2 解析优先级

| 输入 | 解析 |
| --- | --- |
| 裸名 `std` | 只查内置官方 pin 表；**不查索引**；非官方包不可用裸名 |
| `ct/<name>` | 内置 pin 表；显式 `--index` / `CT_INDEX` 命中 `publisher = ct` 行时以索引为准 |
| `<other>/<name>` | 必须索引 / URL / 本地目录；索引缺失即硬错并提示限定名写法 |
| 显式 URL / 本地路径 | 直连，行为不变 |
| 索引行 `publisher ≠ ct` 且名为 `std` | 对裸名无效；只有 `ct get <pub>/std` 才生效 |

内置 pin 表条目至少含：`name`、`version`、`publisher = ct`、`url`、`tag`、`sha256`。版本选择沿用现有规则
（显式范围取最低满足版本；省略范围取表内最新）。范围无匹配时硬错，并提示用 URL 指定。

### 2.3 输出

`ct get` 的三种输出都必须展示规范形式：

```text
resolved   ct/std 0.4.0
  source   https://github.com/ct-pkg/std@0.4.0
  tag      v0.4.0
  commit   <sha>
  store    ~/.ct/pkg/ct/std/0.4.0
  digest   sha256:...
  action   installed
```

- 文本：`source` 行改为单个 `url@<包版本>`；`tag` 单列；
- `--quiet`：`ct/std 0.4.0 https://github.com/ct-pkg/std@0.4.0`；
- `--json`：保留既有字段，新增 `"spec": "<url>@<version>"`。

### 2.4 迁移

- `ct update` 遇到 `std/std` 锁行：解析官方 pin 目标，改写成 `ct/std`，打印
  `migrate std/std <old> -> ct/std <new>`，并保留旧 store 目录（不删、不覆盖）；
- `ct verify` 对旧身份只告警（`legacy publisher 'std'`），不判失败；
- `ct install` / `ct build` 永不重写锁；旧锁 + 旧 store 离线仍可构建；
- 不静默双写：同一版本不能在 `std/std` 与 `ct/std` 两个 store 路径同时新建。

### 2.5 内置 pin 表

- 编译期常量，随 `ct` 版本发布更新；不联网、不读可变索引；
- 发布清单必须包含「更新 pin 表」步骤；
- 增加一致性探针：内置条目与官方索引行（版本/tag/sha）不一致即红。

## 3 任务

| 任务 | 交付物 | verify | effort |
| --- | --- | --- | --- |
| S0 契约与决策 | package-guide / AGENTS 包表 / 解析优先级同步；D-010 已落，补齐文档引用 | `bash test/ast/p77_docs.sh` → `OK p77/docs` | S |
| S1 解析器 | 裸名限官方、pin 表、`ct/<name>` 无索引可解析、第三方裸名硬错 | `bash test/ast/p77_bare.sh` → `OK p77/bare` | M |
| S2 输出 | 文本 / `--quiet` / `--json` 统一 `url@version` + tag 单列 | `bash test/ast/p77_output.sh` → `OK p77/output` | S |
| S3 迁移 | `ct update` 自动迁旧锁；`ct verify` 旧身份告警；旧 store 保留 | `bash test/ast/p77_migrate.sh` → `OK p77/migrate` | M |
| S4 文档 | install.sh、tutorial、README、package-guide 统一可执行写法 | `bash test/ast/p77_install.sh` → `OK p77/install` | S |
| S5 外部对齐 | `ct-pkg/std` 新 tag（publisher=ct）、索引六字段；干净 HOME 端到端 | `bash test/ast/p77_external.sh` → `OK p77/external` | M |

> S0–S5 是同一 phase 的 stage：每个 stage 独立红/绿与回滚，只 bump 一次 MINOR。
> S5 依赖外部仓；外部未就绪时本卡不得标记完成（不得记绿）。

## 4 退出判据

| 编号 | 断言 |
| --- | --- |
| E77-1 | 干净 HOME、无索引：`ct get std` 成功；锁行 `ct/std <ver>`；store 为 `$CT_HOME/pkg/ct/std/<ver>` |
| E77-2 | `ct get std` 与 `ct get ct/std` 解析到同一 `(url, tag, sha256)`，两次锁行逐字节一致 |
| E77-3 | 索引含 `acme/std` 时：裸 `std` 仍取官方；`ct get acme/std` 取第三方；裸 `acme` 硬错要求限定名 |
| E77-4 | 文本 / `--quiet` / `--json` 均输出 `url@<包版本>`，tag 单列；JSON 新增 `spec` |
| E77-5 | 旧 `std/std 0.3.2` 工程 `ct update` 自动迁移为 `ct/std@<new>` 并打印前后；旧 store 保留；`ct verify` 不误红；离线 `ct build` 旧锁仍可用 |
| E77-6 | install.sh 推荐命令实测 RC=0；install.sh / tutorial / README / package-guide 无失败路径写法 |
| E77-7 | `check-all` 与包用例全绿；无新增安装期 git/index 依赖；pin 表一致性探针覆盖 |
| E77-8 | 外部对齐：`ct-pkg/std` 新 tag 的 `publisher = ct`，索引六字段；另一台干净 HOME 上 `ct get ct/std@<new>` 成功 |

## 5 风险

| 编号 | 风险 | 缓解 |
| --- | --- | --- |
| R77-1 | 身份切换使旧锁与新锁指向不同 store，出现双份 | `ct update` 显式迁移；旧 store 只读保留；禁止静默双写 |
| R77-2 | 内置 pin 表过期 | 发布清单固化更新步骤；E77-7 一致性探针 |
| R77-3 | 官方索引仍五字段，裸名若查索引会回归旧失败 | 裸名不查索引，只查 pin 表；外部索引六字段列为 S5 |
| R77-4 | 自动迁移改用户锁 | 打印前后两行；不改 `ct build` / `ct install`；可回滚到旧锁与旧 store |
| R77-5 | 违反 B′（默认消费可变索引） | pin 表为编译期常量，不联网；不新增 `--with-index` 默认行为 |

## 6 不做什么

- 不默认 clone 索引、不自动联网更新索引；
- 不把第三方裸名当合法输入；
- 不重写历史 tag、既有 `ct.lock` 或已发布包；
- 不删除旧 store；
- 不改 URL / 本地路径输入形态；
- 不做包发布自动化（发布仍在索引仓 CI）。

## 7 外部前置与移交

跨仓发布/消费边界与回放契约见 [ct-pkg-get-contract](../planning/ct-pkg-get-contract.md)。

### 7.1 `ct-pkg/std` 调整清单（外部）

1. `ct.pkg`：`publisher = std` → `ct`；`version` 从 `0.18.0` 升到 `0.19.0`；`ns-root = .` 不变；
   `requires = ct >= 0.67.0` 可保持不变（本卡不要求 std 使用新语法）。
2. 发新 tag `v0.19.0`；`v0.3.2` / `v0.18.0` 不移动、不重建。
3. 仓内文档与示例：README、AGENTS、`std/**/README.md` 仍写 `publisher = std`、`ct get std@^0.2.0`、
   `-I vendor/std`，需改为 `ct/std@0.19.0` 与 lock 自动补 `-I`。
4. 索引仓：当前 `index` 仍停在 `std 0.3.2`（`--dry-run --only std` 已证明应刷新到 `0.18.0`）；
   新 tag 发布后跑 `refresh-index.sh --only std`，应生成 `std 0.19.0 ct …`，再用
   `sync-repos-tags.sh` 更新 `tools/repos.txt`，最后 `verify-index.sh --name std`。
5. 消费者旧锁 `std/std` 由本卡的 `ct update` 迁移；std 仓不负责改写消费者工程。
6. 不手改 `index`、不删除旧 store、不移动已发布 tag。

| 项 | 归属 | 验收 |
| --- | --- | --- |
| `ct-pkg/std` 清单 `publisher = ct` + 新 tag `v0.19.0`（旧 tag 不动） | `ct-pkg/std` 仓 | 新 tag 可被 `ct get`，锁写 `ct/std` |
| 官方索引六字段行（含 publisher） | `ct-pkg/index` 仓 | 行内容与 pin 表一致 |
| 消费包仓（ct-fsguard 等）旧锁迁移 | 各包仓 | `ct update` 后锁写 `ct/std` |
| 索引生产端 `std 0.3.2` 旧行退役 | `ct-pkg/index` 仓 | 不再被任何默认路径命中 |

## 8 收口对照（2026-11-19）

| 判据 | 证据 | 结果 |
| --- | --- | --- |
| E77-1 | 干净 HOME、无索引：`ct get std` 成功；锁行 `ct/std 0.19.0 git https://github.com/ct-pkg/std …`；store `$CT_HOME/pkg/ct/std/0.19.0` | ✅ p77_external（联网）；干净 HOME 的离线形状由 p77_bare 的 `ct/std@0.19.0` 覆盖 |
| E77-2 | `ct get std` 与 `ct get ct/std` 写出的 `ct.lock` 逐字节相同；离线解析两者的 pin 诊断逐字节相同 | ✅ p77_external + p77_bare |
| E77-3 | 索引含 `acme/std` 时裸 `std` 仍走官方 pin；`ct get acme/std` 取第三方；裸 `acme`/`hal` 硬错并提示 `<publisher>/<name>` | ✅ p77_bare |
| E77-4 | 文本 `source url@version` + `tag` 单列；`--quiet` 每行 `name version url@version`；`--json` 含 `spec` | ✅ p77_output |
| E77-5 | `ct update` 打印 `migrate std/std 0.3.2 -> ct/std 0.19.0`；旧 store 保留；`ct verify` 对旧身份只告警；install/build 不改锁；双身份硬错 | ✅ p77_migrate |
| E77-6 | install.sh / tutorial / README / package-guide 统一 `ct get ct/std`；文档推荐命令实测成功并 build+run | ✅ p77_install |
| E77-7 | `check-all` 与包用例全绿；无新增安装期 git/index 依赖；pin 表与官方索引行（版本/tag/sha）一致 | ✅ p77_external（联网一致性探针）；`test/pkg/run.sh` 147/0 |
| E77-8 | `ct-pkg/std` `publisher = ct`、`v0.19.0` 摘要 `sha256:432086f0…`；索引六字段行；干净 HOME 上 `ct get ct/std@0.19.0` 成功 | ✅ p77_external |

> 离线门禁中 p77_external 以 `skip` 退出（无网络/无 curl），不判失败；其余 p77 探针全部离线可重复。
