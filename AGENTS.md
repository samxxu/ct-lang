# AGENTS.md — 项目规约（面向 AI 编码代理）

> 中文

本文件是 `ctc` 仓库的**唯一行为规约**。任何 AI 编码代理在本仓库动手之前，必须先读完本文件；
它与代码冲突时以代码为准，但**修改代码前必须先跟用户确认**。

---

## 中文

> **工程方法论优先**：涉及评审、台账、phase、battle 等流程工作时，以
> `~/trae-ws/.ai-engineering/methodology/ai-coding-workflow.md` 为准；`.trae/skills` 下的技能
> 已 self-superseded（标注「不要据此执行」），不得据其执行。本文件的代码规约不受影响。

> **主规范锚定（G9）**：本仓库引用的主规范版本与摘要固定如下；`test/docs/check-docs.py`
> （门禁 11）会比对 `~/trae-ws/.ai-engineering/methodology/ai-coding-workflow.md` 的版本与
> SHA-256。规范文件不在场时显式 `skip`（不红）；在场且不一致时必须红。更新主规范时，必须在
> 同一次改动里刷新这两个值。
>
> | 键 | 值 |
> | --- | --- |
> | `spec-version` | `1.9.0` |
> | `spec-sha256` | `b8651332d8b5e4db93f7a8718a3fc00c8a2c43627e1ce7145dbae82ecb4520dc` |

### 0. 方法论（跨项目，必须遵守）

- 主规范：`/Users/samxx/trae-ws/.ai-engineering/methodology/ai-coding-workflow.md`
- 加载顺序：本节 > 主规范 > 本节生成块 > 本项目其余章节；冲突取更严者。
- 本项目只能加严；放宽必须写 `deviation:` 并由用户签字（日期 + 理由）。
- 生成块由 `bin/sync-agents.sh --write AGENTS.md` 维护，不得手改块内任何字符。

<!-- spec:begin version=1.9.0 sha256=b8651332d8b5e4db93f7a8718a3fc00c8a2c43627e1ce7145dbae82ecb4520dc -->
<!-- 由 sync-agents.sh 生成，禁止手改（11.5）。主规范：/Users/samxx/trae-ws/.ai-engineering/methodology/ai-coding-workflow.md -->
<!-- 全文副本：docs/spec/ai-coding-workflow.md；该文件的 sha256 必须等于上面的 sha256。 -->
<!-- 块内是“每轮必做判据”的摘录 + 章节索引，不是规范全文；未写入的规则仍在主规范，冲突以主规范为准。 -->

### 章节索引（块内没有的，按需读主规范或 docs/spec 全文副本）

| 想查什么 | 去哪读 |
| --- | --- |
| 原则、三条底线、八环节、phase 退出判据、发布判据（6.2 细节） | 主规范 §0、§6.1–6.5 |
| 角色职责与交底（EDITOR / REQ / ARCH / DEV / VERIFY / REVIEW / APPSEC） | 主规范 §3、`methodology/roles/` |
| 任务切分 T-1…T-7、小循环、热修 | 本块 §6.6（摘录）；细节见主规范 §6.6 |
| battle、证据、文档门禁细节 | 主规范 §7、§8、§9 |
| 落库、纳管清单、偏离登记 | 本块 §11.5（摘录）；清单表见主规范 §11.5 |
| 术语与判断点速查 | 主规范 §13、附录 A |


### 5.4 Issue 状态词分权

| 状态词 | 谁能写 | 含义 | 必备证据 |
| --- | --- | --- | --- |
| `open` | REV / REQ | 已立案 | 复现命令或 `file:line` |
| `fixed` | DEV（写处置段，不动状态字段） | 主张已修复 | 提交 sha + 验证命令原始输出 |
| `verified` | REV | 复核通过 | 独立复现 + 逐条对照 |
| `reopened` | REV | 复核未过 | 失败复现 |
| `rejected` | REQ / USER | 不采纳 | 理由；涉及规范时附决策记录 id |
| `deferred` | REQ / USER | 延后 | 触发条件或日期 |
| `wontfix` | USER | 永不修 | 理由 |
| `superseded` | REQ | 被新条目取代 | 新条目 id |

判据（G6）：每个条目 front-matter 的 `status` 必须属于上表，且 `status` 与证据字段非空；`fixed` 只能出现在正文处置段，不得写入 `status`。

---

### 6.4 门禁

每个项目在 `tools/check.sh` 里提供同名子命令；下表是判据，脚本是实现。

| 门禁 | 名称 | 命令（项目实现） | 通过判据 | 负责 | 失败处置 |
| --- | --- | --- | --- | --- | --- |
| G0 | 规约纳管 | `tools/check.sh g0` | `g0-block` 三项：①块头 `version`/`sha256` 等于主规范头部与实算值；②块体与 `sync-agents.sh --print` 逐字相同；③`docs/spec/ai-coding-workflow.md` 存在且 sha256 等于块头。另加块外三段齐全：实例化 8 行（含三类常驻对话名与 phase 对话命名规则）、话术路由、偏离登记位（`g0-landing`；只认 `spec:end` 之后与 `spec:begin` 之前，块内同名节忽略）；`docs/session-map.md` 存在；`版本落点` 非空（6.7） | REQ | 刷新生成块（11.5）或补块外缺段；未落库的后果见 11.5 L-3 |
| G1 | 主张完整 | `tools/check.sh g1` | 每条要求有 ID；每条验收判据有命令与阈值；无 `TBD`；phase 卡片必填项齐全（含任务清单与 `version-minor`，`g1-version` 校验其等于 `PH-<n>`，有偏离按 `d` 换算）且退出判据可核对、含「任务清单每项可独立验收」（`g1-phase-card`） | REQ | 退回立项/设计环节，不得进入实现 |
| G2 | 设计可验收 | `tools/check.sh g2` | 每个接口/协议承诺映射到 `ACC-*` 条目 | REQ | 补映射表 |
| G3 | 构建与单测 | `tools/check.sh g3` | 构建零警告；单元测试全绿；退出码 0 | DEV | 修复后重跑，贴原始输出 |
| G4 | 文档可执行与时效 | `tools/check.sh g4` | 文档中每个可执行代码块来自 `docs/snippets/`；渲染结果与文件一致；snippet 编译/运行通过；引用锚点存在；`applies-to` 与当前发布锚点一致；单份文档 ≤ 300 行（`g4-size`；`AGENTS.md` 先剔除生成块再计数，DOC-S8）；README 结构与模块类型匹配（`g4-readme`）；发版前与 phase 收口时版本字段核对通过（`g4-version`，6.7 V-6） | DEV | 生成 snippet、补锚点、更新 `applies-to` 或按 8.4 分拆；无法同步则删除伪造代码块 |
| G5 | 测试自证 | `tools/check.sh g5` | 每条判据至少 1 个用例；每个门禁断言至少有 1 个负例曾变红，红证按 6.6 T-7 带 `baseline: <sha>` 与原始输出（用当前代码复跑不算） | VERIFY | 补负例或补红证；无负例的断言不计入覆盖 |
| G6 | 台账闭合 | `tools/check.sh g6` | 每个 Issue 的 `status` 合法且证据非空；无"无结论关闭"；池条目状态合法且无超窗未处理（`g6-pool`）；phase 收口每个 issue 只有一个去向；`g4-version` 报出的版本不一致有一条对应 Issue（未立案即失败，6.7 V-6） | REV | 退回对应条目 |
| G7 | 安全机械项 | `tools/check.sh g7` | 密钥扫描 0 命中；锁文件与依赖清单一致；sanitizer 全绿 | SEC | 命中即 P0，阻断 |
| G8 | 提交粒度与范围 | `tools/check.sh g8` | 一提交一事；路径在角色权限内；claim 变更带 CR；门禁变更带负例；当前 phase 退出判据未被修改（`g8-phase-freeze`）；同一 `task-id` 的 `test(...) 红` 提交是实现提交的父提交（6.6 T-7）；小循环/热修的改动范围与记录合规；版本号每次只 +1、MINOR 与 phase 对应、PATCH 只记 fix、纯文档提交不动版本号（`g8-version`，6.7 V-1…V-5）；phase 收口 tag 名、annotated 属性与指向提交（`g8-version`，6.7 V-7） | DEV | 拆分提交、补红证或补 CR |
| G9 | 规范锚定 | `tools/check.sh g9` | `AGENTS.md` 的 `spec-sha256` 与主规范一致；`spec-version` 不落后 | REQ | 更新 pin（单独提交） |

本章新增的检查全部挂在既有门禁下，不新增门禁编号：`g1-phase-card`、`g1-version`、`g4-version`、`g6-pool`、`g8-phase-freeze`、`g8-version`。

### 6.6 任务切分：小步快跑

> 原则：phase 是目标，任务是交付单位。目标可以大，交付单位必须小到能被单独验收、单独回滚。

**任务的定义**（术语见第 13 节）：一个交付物 + 一条验收命令 + 一次提交 + 可单独回滚。四者缺一即不是任务，只是"一块工作"。

| # | 规则 | 判据 |
| --- | --- | --- |
| T-1 | 一项任务只有一个交付目的：一个主要交付物（源码、文档或配置），连同它自己的负例与证据；不得把一个模块、一个 phase 或两个无关目的放进同一项任务 | 任务清单每行只有一条 `deliverable`；出现并列交付物且不属同一变更 → 退回重切 |
| T-2 | 一项任务必须能在一轮内完成：一次会话内收口，或一次提交周期内收口；估不出边界的任务不许开工 | 卡片 `tasks` 每行有 `effort`，取值 `S` / `M`；`L` 必须再拆，`XL` 不允许出现 |
| T-3 | 一项任务有自己的验收命令与原始输出，不得借用「整个 phase 门禁全绿」作为自己的验收 | 卡片 `tasks` 每行有 `verify`；收口对照表逐条贴该命令的输出，而不是复述总门禁 |
| T-4 | 一项任务能单独回滚：`git revert` 该任务的提交后，其他任务的交付物与门禁不受影响 | 该提交的路径集合与该任务声明的路径一致（8.3「一提交一事」）；回滚演练后其余任务的门禁仍绿 |
| T-5 | 任何一项任务的完成都不得同时满足该 phase 的全部退出判据——否则说明 phase 没被切开 | 逐项任务对照 `exit-criteria`：一条任务覆盖 ≥2 条退出判据即退回重切 |
| T-6 | 任务清单在开工前写死，与退出判据同受冻结；任一项四要素不全 → 不许开工，收口时有未验收项 → 不许宣称完成 | G1 `g1-phase-card` 校验 `tasks` 非空且四列齐全；G6 收口对照表逐项对应；G8 `g8-phase-freeze` 校验 `tasks` 未被中途修改 |
| T-7 | 先红后绿：任务的第一步是提交测试夹具与断言并产出红证，实现提交随后转绿；纯文档、纯配置、纯注释任务例外，须在任务行写 `no-test: <理由>` 并由评审签字 | 同一 `task-id` 的两个相邻提交：`test(<scope>): <task-id> 红`（只含测试、夹具与红证）是 `feat`/`fix` 实现的**父提交**（G8）；红证含 `baseline: <sha>` 与原始输出，`<sha>` 必须是实现前的提交且是 `HEAD` 的祖先；用当前代码复跑的不算 |

**T-7 的提交与红证格式**

```console
$ git log --oneline -2
<impl-sha> fix(ct-ast): <task-id> 修复 <一句话>
<test-sha> test(ct-ast): <task-id> 红
```

- 红证写在 issue 条目或 phase 卡的任务行，最小字段：`baseline: <sha>`、命令、原始输出、退出码。
- 复跑基线：`git archive <baseline> | tar -x -C /tmp/<task-id>` 后按项目方式构建，不得使用工作树当前产物。
- `baseline` 必须是 `test` 提交的父提交（即实现落地前）；`git merge-base --is-ancestor <baseline> HEAD` 必须为真。
- 例外只覆盖纯文档、纯配置、纯注释：任何改变行为的提交都不适用；`no-test:` 缺评审签字视为任务未完成。
- 归属：`test(...) 红` 与实现两个提交都由 **DEV** 提（3.5）；EDITOR 只在 phase 卡片上批准任务与判据，不代笔、不合入；红证由 **VERIFY** 认定并签字（3.6），DEV 不自签。

**适用边界**：T-7 只对本次变更之后新立的 phase 与新开的任务生效；已在途 phase 不追溯（与 6.2 退出判据冻结同一口径）。小循环不要求开卡，但复现同样先于修复（6.3）；热修保留原有提交顺序，红证要求同步生效。

**与既有条款的关系**：本条不新增门禁编号，判据挂在 G1 `g1-phase-card`、G5、G6、G8 下；「一提交一事」（8.3）是任务粒度在提交层的同一条规则，不另立——`test` 提交与实现提交各是一事，不合并。

**切分方法（三步，可机械执行）**：

1. 把 phase 的交付物逐条列成 `deliverable`，一个交付物一行；
2. 每条交付物再切出"能让它单独变绿的最小改动"，作为一项任务；切不动说明交付物本身太大，退回 6.1 重排 phase；
3. 给每项任务写 `verify` 与 `effort`；写不出验收命令的任务不是任务（与 6.2 的立项判据同源）。

### 6.7 版本号：MINOR 与 phase 同步，PATCH 与 fix 同步

> 本节管的是**项目产品版本**——源码、清单文件、README 徽章里那个数字。主规范自己的 `spec-version` 与项目 `AGENTS.md` 的 pin 不适用本节，见 11.4；两套版本号不要混成一套。

**形态**：`MAJOR.MINOR.PATCH`，声明处不带 `v` 前缀（tag 可带，如 `v0.30.1`）。三个位各自只由一个事件推动：

| 位 | 什么时候 +1 | 触发者 |
| --- | --- | --- |
| MAJOR | 对外破坏性变更，且项目**已发布**；未发布的项目不因签名变更升 MAJOR（6.5） | 用户裁定 |
| MINOR | **每个 phase 交付时**：`PH-<n>` 收口，MINOR 置为 `n`，PATCH 归零（登记了版本偏离的，按偏离里的偏移换算，见下） | phase 收口 |
| PATCH | **每次 fix**：单点修复、热修、缺陷修复；一次 fix 恰好 +1 | 该修复的提交 |

| # | 规则 | 判据（机械） |
| --- | --- | --- |
| V-1 | MINOR 与 phase 严格一一对应：`PH-<n>` 交付时 `MINOR == n`（有版本偏离的按登记的偏移换算），即相对上一 phase 恰好 +1；不许多跳（不得从 `n-2` 直接到 `n`），不许同一 phase 内第二次 +MINOR；PATCH 随 MINOR 归零 | 收口提交的版本 `MINOR == n` 且前一版为其减一；同一 phase 窗口内出现两次 MINOR +1 即失败（`g8-version`、`g1-version`） |
| V-2 | phase 内的新功能不得占用 PATCH：PATCH 只记 fix，不记功能 | phase 窗口内每次 PATCH +1 都能追到一个被立案的缺陷条目（`g8-version`） |
| V-3 | PATCH 与 fix 严格一一对应：一次 fix 一处缺陷、只 +1 一次；同一缺陷 `reopened` 后的返工不重复 +1（它仍是那一次 fix） | 该提交正文引用恰好一个 `issues/<id>.md`，且本次处置为 `fixed`（5.4、`g8-version`） |
| V-4 | 不算 fix、因此不许单独 +PATCH：纯文档 / 措辞 / 格式 / 链接修订、注释、测试夹具与断言自身的修正（3.9 `test-fix`）、门禁脚本重构、CI 配置调整。唯一例外：该改动本身就是一条被立案的缺陷（例如文档写错、用户照做失败），此时按那条 Issue 的 `fixed` 计一次 fix | 提交路径集合命中上述类别、且正文未引用处置为 `fixed` 的 Issue → 失败（`g8-version`） |
| V-5 | 版本号随它所标记的那次 fix / phase 收口在**同一提交**内移动；版本号不是独立事项，不另开提交。同一提交内声明处的三个数字必须一致（落点见下） | 版本落点与行为改动或收口记录同提交；只改版本号、不改任何行为或收口的提交 → 失败（`g8-version`） |
| V-6 | 代码里的版本字段必须与工程状态对得上，**任何不一致即缺陷**：立 `Issue` 并按一次 fix 处置（PATCH +1，V-3）；不得记为历史遗留、不得 `deferred` 放着、不得只改一处凑绿 | 按本节「版本字段核对的两处时机」执行；发现不一致而未立案 → G6 失败；核对工具与两项判据见 `g4-version` |
| V-7 | **phase 收口时版本移动、建 tag、推 tag 在同一次收口动作内完成**，不需要每次另行请示用户：创建 annotated tag `v<MAJOR>.<MINOR>.<PATCH>`（带 `v`，例 `v0.33.0`），指向收口提交，message 含 `PH-<n>` 与收口提交 sha 前 7 位；四项校验通过后 `git push origin <tag>`。**只有 phase tag，fix 不打 tag**（理由见下）。**分支推送不受本条影响**，仍按 6.5 须用户显式指令 | 推前四项全过才推：①名符合 `v<MAJOR>.<MINOR>.<PATCH>`；②`git cat-file -t` = `tag`；③`git rev-parse <tag>^{commit}` 等于收口提交；④该提交可在远端追溯（`git branch -r --contains <sha>` 非空）。任一项不过 → 不推、打印原因、非零退出；缺 tag、名不带 `v` 或未推成功即 `g8-version` 失败 |

**版本落点必须声明。** 一个项目的版本号出现在哪些位置，由该项目在 `AGENTS.md` 实例化节写一行 `版本落点`（例：`composer.json#version`、`src/Version.php:const VERSION`、`README.md` 两处徽章）。未声明即 G0 失败；声明了却没改全，同一提交内所有落点的三个数字不一致即 `g8-version` 失败。

**版本字段核对的两处时机。** `g4-version` 只在两个时点跑，不逐提交跑（逐提交有 `g8-version`）：发版的发布检查表、phase 收口的收口对照表。核对四项：①落点之间相等；②`MAJOR.MINOR` 与 `PH-<n>` 对应（含偏离换算）；③`PATCH` 与该 phase 内的 fix 条目数相等；④CHANGELOG 最新条目与 tag（有此 phase 的 tag 时）所指版本一致。任一项不等即在报告里贴出两边的原值与出处，并按 V-6 立案。

**与 phase 卡片对齐。** phase 卡片增加必填字段 `version-minor`，写收口时应达到的 MINOR（例：`30`），判据等于 `PH-<n>`；PATCH 不写进卡片——它由该 phase 内的 fix 数决定，写死就会和 V-3 打架。该字段与退出判据、任务清单同受冻结（6.2、6.6 T-6）：中途抬高 MINOR 或提前占用 PATCH 都算修改退出判据，由 `g8-phase-freeze` 拦。

**挂在哪道门禁**（不新增门禁编号）：

| 检查 | 挂靠 | 守哪些条 |
| --- | --- | --- |
| `g1-version` | G1 `g1-phase-card` 的扩展 | V-1：卡片 `version-minor` 必填，且等于 `PH-<n>`（有偏离的按登记换算） |
| `g8-version` | G8 的扩展 | V-1…V-5：提交级逐次检查 |
| `g4-version` | G4 的扩展（沿用 `g4-fresh` 的时效语义） | V-6：发版前与 phase 收口各核对一次 |
| G0 实例化项 | G0 | `版本落点` 一行非空 |

**V-7 的生效边界。** 只对 1.8.0 之后新开的 `PH-<n>` 生效；`PH-27`…`PH-33` 等已收口或在途的 phase 不因本条补打 tag，是否回补由用户单独决定（选项与代价见交付报告）。

**tag 只标 phase，不标 fix。** 每个 fix 都 +PATCH（V-3），若逐个打 tag 会让 tag 数量随缺陷数膨胀；而 `applies-to: <tag|sha>` 已允许用 sha 钉住任意提交（§0.3），fix 不需要独立 tag。fix 只进 CHANGELOG，并在下一次 phase tag 时被一并覆盖。判据：一个 phase 窗口内 tag 数 = 1（phase tag），fix 提交上不建 tag。

**tag 自动推 ≠ 发布到远端。** 收口 tag 连同创建一起 `git push origin <tag>`，属收口的一部分，不再逐次请示；但**分支推送**与对外发布仍须用户显式指令（6.5），发布仍按 6.2 的判据（API 稳定、迁移说明、CHANGELOG 完整）。这条区分是本节与发布判据的边界，不是例外。

**适用边界：只对下一个新开的 phase 生效。** 本节自 1.6.0 起约束：开卡时项目 pin 的 `spec-version >= 1.6.0` 的 `PH-<n>` 受本节全部条款；已在途 phase 不追溯——`version-minor` 字段可缺、号段按原样收口。首个受约束的 phase 就是 1.6.0 之后新开的那个。判据：生成块头记的 `version`（三个位按数值比较，不是字典序），`g1-version` 只检查 `>= 1.6.0` 的项目。

**存量落差：登记偏离，不重新编号（本版选定）。** 一个项目若在 1.6.0 之前已走到 `PH-<n>` 而 `MINOR != n`，保留现有号段，在 `AGENTS.md` 的 `偏离项` 里登记一条针对版本号的 `deviation:`：写明偏移 `d = n - MINOR`、生效日期、理由、收敛方式，并由用户签字。判据：G0 认 `偏离项` 这一行；`g1-version` 用登记里的 `d` 换算，`MINOR == n - d`；没有签字即按 V-1 失败。

| 做法 | 代价 | 适用 |
| --- | --- | --- |
| 登记偏离（本版选定） | 版本号与 phase 长期错位；历史 tag 与 CHANGELOG 不动；每次收口多一步换算；需用户签字 | 已发布或已有历史 tag 的项目 |
| 重新编号 | 一次跳号违反 V-1「不许多跳」，并在 CHANGELOG 留下空段；已发布 tag 不可回改，旧号与新号断裂 | 未发布、且没有 tag 的项目 |

**收敛方式必须写死在偏离里。** 在 V-1 下 MINOR 与 phase 每轮都 +1，偏移恒定：两者同速前进时"逐步对齐"不会自动发生。可写进 `deviation:` 的只有三种，必须选一种——

| 方式 | 写法 | 后果 |
| --- | --- | --- |
| 一次性补号 | 指定某个 phase 收口时把 MINOR 一次补到 `n` | 该次收口违反"不许多跳"，须在同一条 deviation 里显式豁免 |
| 永久偏移 | 写 `偏移: <d>`，不设收敛 | 与"MINOR 与 phase 一一对应"名义不符，但机械可查 |
| 将来重编号 | 写明"到 `PH-<m>` 时按重新编号处理" | 届时仍要一次跳号与 CHANGELOG 空段 |

示例（可移植）：`PH-12`、当前 `0.8.3`、`d = 12 - 8 = 4`，即 `偏移: 4`；`PH-13` 收口得到 `0.9.0`，`g1-version` 按 `13 - 4 = 9` 换算通过。

**本节与既有条款的冲突（逐条给状态，不留"照录"）**：

| # | 冲突 | 处置（改后条款 + 位置） | 状态 |
| --- | --- | --- | --- |
| C-1 | 6.5「版本与 tag」原判据「无用户指令不得 bump 版本或打 tag」与 V-1/V-3 的自动 +1 冲突 | 6.5 该行改为「推送与远端发布」：分支推送须用户指令；phase tag 随收口自动创建并推送（V-7），见 6.5 表第 1 行 | `已消解` |
| C-2 | 8.3「不擅自发布」原指「无用户指令不 push/tag/bump」 | 8.3 该行改为“唯一判据见 6.5「推送与远端发布」；tag 见 6.7 V-7”，见 8.3 表第 6 行 | `已消解` |
| C-7 | 6.5 原行「版本与 tag｜USER｜显式指令｜tag + 变更记录｜tag 与 push 无用户指令不得执行」与 V-7 冲突 | 6.5 整行改为「推送与远端发布」，只保留分支推送与远端发布的权限闸；tag 规则移入 V-7。项目若要“收口也不打 tag”的例外，走 `deviation:` | `已消解` |
| C-3 | 3.5 DEV 停机条件原「需要 bump 版本或打 tag」会让 DEV 每次 fix 都停机 | 3.5 改为「需要 push 分支；版本号与 phase tag 按 6.7 自动移动并推送，不停机」，见 3.5 表停机条件行 | `已消解` |
| C-4 | 6.6 T-7 先红后绿 vs 版本号若单独成提交则无可红行为 | 采用 V-5 同提交：版本号不构成独立提交，不产生无红证任务，T-7 无需例外 | `已消解` |
| C-5 | 8.3「一提交一事」vs V-5 同提交是否算两件事 | 8.3「版本号随事」行补一句“版本号与收口 tag 是该次修复 / 收口的属性，不构成第二个目的”，见 8.3 表第 7 行 | `已消解` |
| C-6 | 存量落差的偏离要求「逐步收敛」，与 V-1「不许多跳」冲突：MINOR 与 phase 同速 +1 时偏移恒定 | 规范不替项目选：`deviation:` 必须从「一次性补号 / 永久偏移 / 将来重编号」选一种并写明；选哪种取决于该项目号段与是否已发布 | `未消解` |

**未消解清单（当前 1 条）**：

| # | 冲突 | 为什么本版不能消解 | 收敛条件 |
| --- | --- | --- | --- |
| C-6 | `deviation:` 的收敛方式与 V-1「不许多跳」 | 取决于每个项目的历史号段、是否已发布、远端是否已有 tag，规范不能代选 | 该项目在 `deviation:` 里三选一并由用户签字；登记后从本清单移除 |

**冲突的处置纪律。** 条款之间冲突时只有两种合法处置：**改掉**（把改后条款与位置写进表，状态 `已消解`），或**登记为未消解**（写理由与收敛条件，进「未消解清单」，状态 `未消解`）。不得以"照录备查""另行讨论""已知问题"代替处置；发现冲突而不登记，视为隐藏冲突，G6 按「无结论关闭」处理。未消解清单每次 phase 收口清点一次，条数写进收口记录。

---

### 8.3 提交要求

| 规则 | 判据 |
| --- | --- |
| 一提交一事 | 提交内文件集合只服务一个目的；无关格式化不得混入 |
| 正文写"为什么" | 说明动机、因果关系、验证命令与结果 |
| 路径在权限内 | 与第 5 节矩阵一致；越界由 G8 拦截 |
| claim 变更带 CR | 提交正文含 `CR-<n>` |
| 门禁变更带负例 | 同一提交内有可失败的负例 fixture |
| 不擅自发布 | 唯一判据见 6.5 的「推送与远端发布」行：分支推送须指令，phase tag 随收口自动创建并推送（6.7 V-7） |
| 版本号随事 | 版本号提交形状、落点一致、禁改情形**只在 6.7 V-4、V-5 定义**；版本号与收口 tag 是该次修复 / 收口的属性，不构成第二个目的；本节只要求遵守，不重述判据 |

### 11.5 落库：每版规范都必须进入每个纳管项目的 `AGENTS.md`

**落库不是放一个链接。** 纳管项目里必须有**规范正文**，打开文件就能读到规则；只写 pin 和路径不算落库。1.9.0 起拆成两处：`AGENTS.md` 块放**每轮必做判据 + 章节索引**（打开就能照做），`docs/spec/ai-coding-workflow.md` 放**全文副本**（要查细节时读）。

**L-1 一版一同步。** 主规范每定一个版本，所有纳管项目必须在同一轮把新块与全文副本刷新到位，不允许"主规范 1.9.0、项目块头还是 1.8.0"。单源不变：主规范是唯一真相，块与副本都是派生物。

**L-2 落库的构成（缺一即未落库）：**

| # | 段 | 内容 | 判据 |
| --- | --- | --- | --- |
| ① | 生成块 | `<!-- spec:begin version=<v> sha256=<s> -->` 到 `<!-- spec:end -->`：块头说明 + 章节索引 + 必做判据摘录（§5.4、§6.4、§6.6、§6.7、§8.3、§11.5 L-1…L-7）。**不再放全文** | 见 G0 的 `g0-block`，本节不重述 |
| ② | 全文副本 | `docs/spec/ai-coding-workflow.md`，与主规范逐字相同，不带块标记 | sha256 等于块头 `sha256`（`g0-block` 第③项） |
| ③ | 实例化节 | 1.1 骨架的 0.1 表，8 行非空（含 `版本落点`） | 见 G0 的 `g0-landing` |
| ④ | 话术路由 | 1.1 骨架的 0.2 表，每行三段：触发话术 / 动作 / 产物 | 见 G0 的 `g0-landing` |
| ⑤ | 偏离登记位 | 0.3 节存在；无偏离写"无"；有偏离逐条带 `deviation:` 与用户签字 | 见 G0 的 `g0-landing` |

**块内同名小节一律不算。** `g0-landing` 只扫描 `spec:begin` 之前与 `spec:end` 之后的内容；块内出现的 `0.1 / 0.2 / 0.3` 是 1.1 模板副本，带 `<...>` 占位，忽略。判失败只有两种：块外找不到实参节，或块外出现第二套同名节（`spec:end` 之后再有 `### 0.1`）。不重排小节号：模板与实参保持同名，靠判据侧区分，理由见 1.1 的注。

**L-2 的边界（代价）。** 块内不再有全文，块里没写的细节必须去读 `docs/spec/ai-coding-workflow.md` 或主规范。**"块里没有"不等于"没规定"**：块只保证"每轮必做"在眼前，不保证覆盖全书；块与正文冲突时以主规范正文为准。索引表每版至少核对一次，漏掉的章节等于不可发现（`g0-block` 只校块体逐字，不校索引完整性）。

**L-3 未落库的后果。** 该项目视为**未纳管**：G0 失败，不得开新 phase（G1 对新开卡拦）；已开的 phase 允许收口，但收口后不得再开新的。判据：`g0` 退出码非 0 或 G1 看到无有效块。

**L-4 谁、何时、怎么查。**

| 角色 | 时点 | 产物 | 判据 |
| --- | --- | --- | --- |
| 主规范侧 REQ | 每次 bump 后、主规范提交前 | 本节纳管清单全绿 | 每行 `sync-agents.sh --check` 退出码 0（块、副本、块外三段都过） |
| 项目侧 REQ | 纳入时、每次会话启动（S3） | `AGENTS.md` + `docs/spec/` | `g0-block`（三项）+ `g0-landing` 通过 |
| 项目侧 DEV | 收到新版本时 | 只含 `AGENTS.md` 与 `docs/spec/ai-coding-workflow.md` 的提交 | 提交路径集合 = `{AGENTS.md, docs/spec/ai-coding-workflow.md}`；`g0` 绿 |

**L-5 生成与校验工具。** `bin/sync-agents.sh`，三种模式，幂等，只改标记之间的部分：

```
bin/sync-agents.sh --check  <AGENTS.md>...   # 校验块头、块体与 docs/spec 全文副本；不一致退出码 1
bin/sync-agents.sh --write  <AGENTS.md>...   # 刷新块 + 写全文副本；块外一字不动；缺块则报错
bin/sync-agents.sh --print                   # 只打印应有的块（索引 + 判据摘录），便于人工 diff
AI_ENGINEERING_SPEC=<主规范路径> ...          # 覆盖默认主规范位置（默认取脚本上级目录的 methodology/）
```

若脚本还没有可执行位，用 `bash bin/sync-agents.sh ...` 等价调用（首次落库时 `chmod +x`）。脚本只读主规范；`--write` 只改目标文件的标记区间，并写 `<AGENTS.md 所在目录>/docs/spec/ai-coding-workflow.md`；`--check` 不做任何写入。

手改块内即漂移：`--check` 用逐字 `diff` 抓，不依赖行号或摘要近似；副本用 sha256 抓，不比对行号。

**L-6 发布流程多出的一步。**

| 步 | 动作 | 判据 |
| --- | --- | --- |
| 1 | 改主规范，bump `spec-version` | 头部版本已改 |
| 2 | `shasum -a 256` 取实算摘要 | 摘要为 64 位小写十六进制 |
| 3 | 对清单内每个项目跑 `sync-agents.sh --write` | 每个目标块头等于新版本与新摘要；`docs/spec` 副本已生成 |
| 4 | 逐个项目跑 `sync-agents.sh --check` | 全部退出码 0（块逐字 + 副本 sha 都对） |
| 5 | 各项目单独提交 `AGENTS.md` 与 `docs/spec/ai-coding-workflow.md`；主规范提交 | 提交路径集合符合 L-4 |

第 4 步任一项目不过，这次 bump 就不算发布完成；不得在清单里留 `pending` 过夜。

**L-7 纳管项目清单（可枚举，唯一一份）。** 新项目纳入时加行；退役标 `retired` 并保留行，不删。`.ai-engineering` 自身是规范仓库，**不是**项目，不进表。


> L-7 的纳管清单表（含 ct-lang / sam-utils / rill-dsl 的状态）见主规范 §11.5，块内不重复。
<!-- spec:end -->

#### 0.1 本项目实例化

| 项 | 值 |
| --- | --- |
| 对话清单 | 单会话；三类常驻会话未建，按 `deviation: single-session-workflow`；phase=PH-42 |
| 任务-对话映射 | [docs/session-map.md](docs/session-map.md)（单会话） |
| 门禁入口 | `tools/check.sh g0`；其余为 `selfhost/check-all.sh`（11 道硬门禁）与 `test/docs/check-docs.py`（链接 + G9） |
| 文档 snippet | 缺失 |
| Issue 台账 | `issues/<area>/<id>.md`；id 前缀 `SH-`（缺陷）、`TEST-`、`DOC-`、`CI-`、`PKG-` |
| 决策记录 | `docs/decisions/D-<n>.md`；phase 决策写 `docs/design/*.md`（`D<phase>-<n>`） |
| 版本落点 | 五处 `CTC_VERSION`：`selfhost/l0/ctc.c`、`selfhost/l1/ctc.ct`、`selfhost/l2/core.ct`、`selfhost/l2/driver.ct`、`selfhost/ct-ast/main.ct`；另 `README.md` / `docs/README.md` / `AGENTS.md` 当前版本与 `docs/history/phase-log.md` 版本记录 |
| 偏离项 | 见 0.3（`version-minor-offset`；`single-session-workflow`） |

#### 0.2 话术路由

| 触发话术（用户或角色说） | 动作 | 产物 |
| --- | --- | --- |
| "开个新 phase" / "开始 PH-<n>" | 先出卡再开工：退出判据、任务清单、`version-minor` 写进卡片；命中 N-1 报三要素 | `docs/design/phase<NN>-draft.md`、`docs/session-map.md` |
| "现在你是 <角色>" / 切换角色 | 先落 handoff，再按新角色落笔 | `handoff/<id>.md` |
| "打 tag" / "发版" | 自动建 annotated tag、push tag 与分支（2026-11-13 用户授权） | tag、发布清单 |
| "放宽一下" / "跳过门禁" | 拒绝；走 `deviation:` 或改主规范（S7） | `deviation:` 条目 + 用户签字 |
| "先这样" / "算历史遗留" | 不接；按 6.7 V-6 立案 | `issues/<id>.md` |
| "修一下 <X>" | 先复现、先红后绿；一处缺陷一次 fix，PATCH +1（6.7） | 红证提交 + 修复提交 |

#### 0.3 偏离项

`deviation: version-minor-offset`

    日期: 2026-11-12
    条款: §6.7 V-1
    现状: v0.36.0 五处一致；PH-36 已收口，MINOR=phase=36，d=0。Phase 27–29 属 V-1 在途不追溯。
    理由: 历史 tag 不可回改；Phase 27–29 在 v0.30.0 合并发布，重编号会跳号并留 CHANGELOG 空段。
    收敛: 无需补偿；收口时 MINOR = PH-<n>。
    签字: 用户已批准（2026-11-12）

> 2026-11-13：PH-37 → v0.37.0，d=0。
> 2026-11-13：PH-39 → v0.39.0，d=0。
> 2026-11-13：PH-40 → v0.40.0，d=0；v0.40.1 为 SH-68 review fix。
> 2026-11-13：PH-41 → v0.41.0，d=0。
> 2026-11-14：PH-42 → v0.42.1，d=0。

`deviation: single-session-workflow`

    日期: 2026-11-13
    条款: §9.1 / §9.3 / G0 `g0-landing`
    现状: 单会话；三类常驻对话未建，phase 对话未按 9.3 命名。
    理由: 单人项目 + DSH 单会话；拆三个会话无协作收益且丢失上下文。
    收敛: 多人协作或 1.0 前建会话并回填 session-map。
    签字: 用户已批准（2026-11-13，本轮指示）

#### 0.4 文档语言（项目加严）

| 规则 | 判据 |
| --- | --- |
| 中文默认 | 面向代理的文档一律中文；新增或改写文档不得写双语 |
| 英文仅 `README.en.md` | 根 `README.md` 的英文镜像；**仅供人类阅读**，AI 代理不得主动读取，除非用户明确要求 |
| 其他文档 | 不保留 `## English` 段；英文段一律删除 |
| 判据 | `grep -rlE '^#{2,3} .*English' --include='*.md' .` 为零命中（`docs/spec/` 的逐字副本除外）；`README.en.md` 用 `#` 标题，不以 `## English` 开头 |

#### 0.5 路线图与流水账

| 规则 | 判据 |
| --- | --- |
| roadmap 只做索引 | `docs/roadmap.md` 只放阶段号、主题、状态、收口版本、详情链接；不写逐相叙述/证据/决策全文 |
| 详细记录 | 逐相细节、版本记录、已定决策、待定项在 `docs/history/phase-log.md`；roadmap 不得复制其正文 |
| 新增/更新 phase | roadmap 加行；详情写流水账；同步不重复 |
| 判据 | roadmap 单元格不得多段叙述；`docs/README.md` 与 `docs/history/README.md` 均有入口 |

### 1. 项目画像

| 项 | 值 |
| --- | --- |
| 是什么 | ct —— CT（*C with Traits*）到纯 C 的 source-to-source 编译器 |
| 命名 | 项目/语言 `ct`（源文件后缀 `.ct`）；**入口命令 `ct`**（`ctc` 为兼容别名，L0 种子 `ctc.c` 编出的二进制仍叫 `ctc`）；GitHub 仓库 `ct-lang`（仅是仓库名）。差异是刻意的（同 `tinycc` 发布 `tcc`），**不要"统一"**。命令的最终形态是单入口 `ct`（`ctc` 保留为兼容别名）：**Phase 7.1–7.3 已落地**——L2 二进制名为 `ct` 时以 `ct` 身份运行，安装形态为「命名为 `ct` + `ln -s ct ctc`」（见 README），生成物 banner 写 `Generated by ct …`；**Phase 10.7 已落地**——安装入口的二进制改由 **ct-ast**（`selfhost/ct-ast/main.ct`）提供，L2 降为回归 oracle；L0 种子仍只叫 `ctc`，见 roadmap |
| 实现语言 | C（C99），**单文件** `ctc.c`（位于 `selfhost/l0/`） |
| 依赖 | 无。只用 libc（`stdio` / `stdlib` / `string` / `ctype` / `stdarg`） |
| 构建 | `gcc selfhost/l0/ctc.c -o ctc`（必须 `-Wall -Wextra -std=c99` 零警告；源码在 `selfhost/`，二进制仍落仓库根） |
| 当前版本 | v0.42.1（`CTC_VERSION`，见 `ctc.c` 顶部；会写进生成物注释） |
| 许可 | 编译器 GPL-3.0-or-later（`LICENSE`）；`.ct` 源码与生成物**不受 GPL 约束**（`LICENSE.EXCEPTION`）；`examples/`、`test/` 与 `editors/` 为 MIT |
| 当前阶段 | v0.42.1；Phase 42 已收口。简要阶段表见 [docs/roadmap.md](docs/roadmap.md)，历史见 [docs/history/phase-log.md](docs/history/phase-log.md)。 |
| 规模目标 | 保持单文件、可一次读完；不要把 `ctc.c` 拆成多文件 |

### 2. 文件职责与改动边界

| 文件 | 性质 | 可否修改 |
| --- | --- | --- |
| `selfhost/l0/ctc.c` | 源码，全部实现（L0 C 种子） | ✅ 唯一需要改的实现文件 |
| `examples/**` | 源码：可运行示例（`<name>.ct` + `<name>.expected.out`） | ✅ 新增语法时同步扩充；生成物不入库 |
| `test/**` | 测试：用例、golden 基线、runner（含 `test/fuzz/` 的确定性 fuzz，Phase 17.1 起） | ✅ 可改；`*.expected.*` 只能用 `./ctc` 重新生成 |
| `.github/**` | CI 配置：GitHub Actions 工作流（`ci.yml` 平台矩阵、`nightly.yml` 消毒器 + fuzz，Phase 17.1 起） | ✅ Phase 17 起新增；只放工作流配置，不进入编译路径、不成为构建步骤 |
| `editors/**` | 编辑器插件：`editors/vscode/`（VS Code，纯 JSON） | ✅ 可改；见下方硬性边界 |
| `selfhost/**` | 源码：自举编译器 —— **L0 C 种子** `selfhost/l0/ctc.c` ＋ 冻结种子 `selfhost/l1/ctc.ct`（L1，能力停在 Phase 2）＋ **开发主线** `selfhost/ct-ast/**`（`main.ct` = 只做绑定与分派的驱动入口，`runtime/arena/` = 节点池 + 字面量池（`namespace runtime::arena`），`frontend/lex/` = 词法器（源码游标 + 当前 token，`namespace frontend::lex`），`frontend/module/` = 单元表与 `map` 记录的取值类型 ＋ build 驱动（`namespace frontend::module`），`frontend/parse/` = 解析器、其共享原语、表达式与类型文法及 `map` 构造的构建器（`namespace frontend::parse`），`frontend/sym/` = 符号表（函数/变量/作用域/类型/trait/struct，`namespace frontend::sym`），`frontend/type/` = 类型推断与装箱判定（`namespace frontend::type`），`tool/diag/` = 告警存储（`namespace tool::diag`），`tool/cache/` = 增量缓存（`namespace tool::cache`），`tool/pkg/` = 包管理器（`namespace tool::pkg`），`tool/driver/` = compile 模式驱动（`namespace tool::driver`），`backend/mem/` = AutoDrop 与泄漏分析（`namespace backend::mem`），`backend/emit/` = 代码发射器（`.c`/`.h`/map JSON，`namespace backend::emit`）；Phase 9 的 AST 版编译器，ct-ast）＋ **冻结归档** `selfhost/l2/**`（`core.ct` + `driver.ct`，Phase 3–8 的旧管线 L2；只修 bug，不再加能力） | ✅ Phase 1 起新增；放编译器源码（含 L0 C 种子）与门禁脚本，生成物不入库 |
| `test/bindings/**` | 源码：C 库的**声明式 binding**（Phase 12 起；2026-11-13 由顶层 `bindings/` 迁入 `test/`，作为测试夹具）—— 直通 `#include "<lib>.h"` ＋ 镜像 `trait` / `struct` ＋ 已声明全局实例 ＋ `map`；仓库内假 HAL 自带其头与实现 | ✅ Phase 12 起新增；只放 binding 源与（假 HAL 的）最小 C 头 / 实现，**不 vendored、不下载**、不成为编译器构建步骤；生成物不入库 |
| `ct-pkg/std` | 标准库（原 Phase 17.2 的仓库内 `std/`）：已迁为独立 ct-pkg 包 `std` v0.1.0，`ct get std` 拉入项目的 `vendor/std`，namespace 仍 `std::<mod>`；本仓库不再保存内置库，`test/std/` 同时移除 | ❌ 不在本仓库维护 |
| `install.sh` | 源码：**唯一的安装脚本**——下载 GitHub 源码归档 → 本地四级自举 → 安装 `ct` 与 `ctc` 软链 | ✅ 可改；只准维护「下载 + 现有自举步骤 + 安装」三件事，不得演变成构建系统，不得进入编译路径 |
| `LICENSE`、`LICENSE.EXCEPTION` | 许可全文与输出例外 | ❌ 仅限用户明确要求时修改 |
| `README.md`、`AGENTS.md`、`docs/*` | 文档 | ✅ |
| `ctc`、生成的 `.c`/`.h`、`.o` | 编译产物 | ❌ 不入库 |

硬性边界：

- 生成的 `.c` 必须**自包含**（不 `#include` 生成的 `.h`），保证生成物可单独编译。
- 生成的头文件只放类型（trait vtable、struct 定义），不放 `static` 函数/变量。
- 不引入任何第三方库、构建系统、代码生成脚本。**例外（安装脚本）**：仓库根只有**一个** `install.sh`，
  它把 README 第 2 节的手工自举步骤串起来（下载源码归档 → L0→L1→L2→ct-ast → 安装），只用系统
  `cc` / `tar` / `curl`（或 `wget`），不需要 `git`；**不是**构建系统，**不参与**编译路径，
  `gcc selfhost/l0/ctc.c` 与全部门禁不得依赖它。它的行为变更（新增选项、改变安装位置、改变下载来源）
  按「行为变更」走用户确认。
  **例外（Phase 6.6 方言）**：方言展开器是**仓库外**的
  独立脚本（bash / Python / awk 均可，作者自选语言），`ctc` 对它**零感知**——编译器只见纯 CT，且
  **永不**调用展开器、**永不**内置任何方言；本禁令只约束**仓库内的编译器构建管线**。仓库内**只允许**
  在 `examples/**`（演示）与 `test/**`（测试）下携带方言源与方言插件，且必须满足：插件放在约定目录
  `ct-dialects/`、按 `//@ct-dialect: <名字>` 路由、文件名 `<名字>.sh`（`/` 换 `-`；同时接受同名其他后缀，
  如 `<名字>.py`，供其他语言使用）；门禁按插件自身的 shebang 执行——有执行位直接执行，无执行位则用
  shebang 指定的解释器，两者都没有才退回 POSIX `sh`；**不得**成为编译器的
  构建步骤——`gcc selfhost/l0/ctc.c`、`./test/run.sh` 的编译相关层与 CT 线全部关卡都不得依赖它，方言演示只由
  `test/run.sh` 的 `dialect` 层驱动。方言所需的符号信息由编译器已产出的 map JSON（`--emit-map`）
  提供，不在仓库内另造一套。
- **例外（Phase 8 包管理）**：`ct get` 可调用**系统 `git`** 获取 git 源包，`ct get` / `ct install` 可把**本地目录源**同步进
  `vendor/`。这是包管理子命令的受控例外——**零网络**不变，编译器核（`ct compile` / `ct build --emit-c`）仍
  **零子进程**，且不得内置 HTTP 客户端。无 `git` 时 git 源硬报错并提示，本地源照常可用。Phase 17.5 的
  `ct update` / `ct verify` 完全离线：`update` 只复用 `vendor/` 缓存与 `ct.lock` 已钉住的提交，`verify` 只读。
  见 [design/phase8.md](docs/history/design/phase8.md)（D22 / D26）。
- **例外（Phase 17 `ct build` 一步到位）**：`ct build` **默认**在发射 `.c` / `.h` 之后调用**本地 C 编译器**
  （`$CC` / `--cc`，默认 `cc`）产出可执行文件——用户 2026-11-02 授权的受控子进程例外。**零网络**不变；
  `ct compile` 与 `ct build --emit-c` 仍**零子进程**；`ct build` 不解析 `cc` 的诊断、不做增量链接、
  不内置构建系统，路径与参数一律按单引号规则转义。见 [design/phase17.md](docs/history/design/phase17.md)（D17-9）。
- **例外（Phase 12 bindings）**：仓库内 `test/bindings/**`（Phase 12 时在顶层，2026-11-13 迁入 `test/`），承载对既有 C 库的**声明式 binding**
  （`selfhost` 之外的第二类源码目录）。binding 只是 CT 源——直通 `#include` ＋ 镜像声明 ＋ `map`，
  **只声明外部符号，不 vendored、不下载、不链接**；仓库内假 HAL 的 C 头 / 实现仅作**演示与测试**，
  **绝不**成为编译器构建步骤（`gcc selfhost/l0/ctc.c`、`./test/run.sh` 的编译相关层与 CT 线关卡都不得依赖它）。
  见 [phase-log](docs/history/phase-log.md) 的 Phase 12 记录与 [design/phase12.md](docs/history/design/phase12.md)。
- `editors/**` 必须保持**纯声明式 JSON**：无构建步骤、无 npm 依赖、无需打包器，改完可直接
  `npx @vscode/vsce package`。插件只负责高亮与编辑体验，不做语法校验、**不调用 `ctc`**（方言亦不例外：
  插件不代跑展开器，`--watch` / 后台自动展开推迟；消费映射信息只能读编译器已产出的 map JSON）。
- **例外（Phase 29 自举容量）**：`selfhost/l2/core.ct` 的 `MAX_CALLS` 由 512 提到 **1024**（2026-11-11）。
  理由：ct-ast 源码在 Phase 29 后超过 512 个调用点，L2 作为回归 oracle 必须仍能编译它；只放大接受
  能力，不改变任何产物。L0 `ctc.c` 与 L1 未改，上面的 `MAX_*` 禁令不受影响。
- 不改变已发布产物的命名规则（`<Trait>_vtbl`、`__<trait>_vptr`、`<Struct>_<Trait>_<method>`、`<Struct>_<Trait>_vtable`），除非用户明确要求。
- `docs/design/` 保留**最近 12 个已完成阶段**的设计文档（当前在研阶段计入）；更早的 `phase*.md` 退役到 `docs/history/design/`，只作历史索引，不得与新阶段文档重复归档。`test/docs/check-docs.py`（门禁 11）会拦截越界与重复。不要照着草案创建目录或文件。
- **`ctc.c` 在自举启动后冻结**：Phase 0.3 剥离完成后**只接受 bug 修复**，**不再新增任何能力**（2026-10-15 用户明确重申：bug 修复可以接受，其他一律不行）。自举要求 `ctc.c` 的 `main` 加 `#ifndef CTC_NO_MAIN` 守卫——这是冻结期**唯一**允许的结构性改造。判据如下，**含混时按「不允许」处理**：
  - **允许**：修正既有行为中的缺陷（错判、错发射、崩溃、越界、状态未还原等）。出口是**既有语料产物不动**——改完 `./test/run.sh` 与 `bash selfhost/check-goldens.sh` 仍须全绿，且**不得重新生成任何 `*.expected.*`**；必须是一个独立的 `fix(...)` 提交，正文写明缺陷、触发条件与验证方式，并登记进下面的清单。
  - **不允许**：新增或加回任何语言特性 / CLI 选项 / 诊断；放宽或绕开任何 `MAX_*` 上限（含为了让 L1 过 `MAX_FUNCS` / `MAX_METHOD` 而改 `ctc.c`）；改动产物命名规则、banner 或 `CTC_VERSION`；重构、重命名、重排既有符号；新增 `#include` 或改变生成物结构。这些一律只能做在 **CT 侧**（L1 及以后）。
  - **冻结期改动登记**（至今两次个别改动；版本 bump 见下一条）：
    1. `1bdb93b fix(codegen): keep file-scope vars in emit_body`（2026-10-15）——`emit_body` 退出时只还原变量表的**条目数**、不还原**内容**，会覆盖外层文件作用域已登记的条目；补进/出各一次内容快照与拷回。产物不变，无 golden 重生成。此后 Phase 1 期间 `ctc.c` **再无任何改动**。
    2. **Phase 7.3 banner 改名**（2026-10-17，**用户显式授权的一次性解冻例外**）——生成物 banner 由 `Generated by ctc …` / `re-run ctc` 改为 `Generated by ct …` / `re-run ct`，L0（`ctc.c`）、L1（`selfhost/l1/ctc.ct`）与 L2（`selfhost/l2/core.ct`）**三层同步**；map JSON 的 `compiler` 字段同步改为 `ct v…`。全部 `test/cases/**` 与 `test/modules/**` golden 已重生成（仅 banner 一行变化），归档 oracle 仍写 `ctc`，由 `check-archive.sh` 的 `same_modulo_version` 归一化兼容。除 banner 文案外，三层**无任何行为变更**。
  - **版本 bump 另行登记**：`CTC_VERSION` 的推进（**v0.4.0 至今的全部版本**，含各相收口与阶段内 patch）同样属用户显式授权的冻结期例外，但**不逐条列入上表**——逐次记录见 [phase-log](docs/history/phase-log.md) 的「版本记录」与对应 `v*` tag 注释；本节不再维护版本清单，以免再次漂移。每次 bump 都同时改动 `ctc.c`、L1（`selfhost/l1/ctc.ct`）、`selfhost/l2/{core,driver}.ct` 与 `selfhost/ct-ast/main.ct`，并重生成全部 golden；上表只逐条登记**与版本推进无关**的个别改动。
- **`selfhost/l1/ctc.ct`（L1）自 Phase 3 起冻结**：L1 已成为**冻结种子**——它停在 Phase 2 的能力上，**不再新增任何能力**（加注释也算，登记方式与 `ctc.c` 相同）。理由与上一级同构：`ctc.c` 冻结后开发搬到 L1，L1 冻结后开发搬到 **`selfhost/l2/**`**（`core.ct` + `driver.ct`，L2 的源）。**Phase 3 起一切新能力只落 `l2/**`**。（Phase 9.7 起主线再搬到 `selfhost/ct-ast/**`，见下条。）
  - **关卡语义随之改变**：`check-archive.sh` 的 ratchet 跑的是 **L2**（L1 `build` `l2/**` 得到），不再是 L1；`check-goldens.sh` 第 7 步是**不动点**——L2 也编 `l2/**`，产出须与 L1 的**逐字节一致**（两个编译器必须在「编译器自己用的那套语法」上一致）。
  - **签名上限是真约束**：`MAX_FUNCS` **计入所有顶层 plain-C 签名，`static` 也算**；`l2/**` 自身仍受 L1 的 64 约束、余量已接近 0，新增辅助函数**必须**放进 `impl` 块（impl 方法不计），并注意 `MAX_METHOD`（L1 为 32，`PipeOps` 已用到 31）。见 [phase-log](docs/history/phase-log.md) 的 Phase 3 记录。
- **`selfhost/l2/**` 自 Phase 9.7 起冻结归档**（D36）：Phase 9 的 AST 版编译器 `selfhost/ct-ast/main.ct` 成为**唯一开发主线**（`ct-ast` 自编 + 全量行为等价），`l2/**` 只**修 bug、不加能力**，归档参照 tag 为 `pre-ast-mainline`（2026-10-17 的 frozen 边界；Phase 9 起点对应 `v0.8.0`）。旧关卡（`check-goldens.sh` / `check-archive.sh` / `check-m2a.sh` / `ct-tour.sh` / `test/pkg/run.sh`）继续把 `l2/**` 当**回归 oracle** 跑，双轨期语义不变；新能力与 9.x 之后的切片只落 `selfhost/ct-ast/**`，并受 `check-ast.sh` 的「自编不动点 + 全量语料等价」约束。
  - **2026-10-20 用户显式授权的一次性解冻例外（引导容量）**：`selfhost/l2/core.ct` 的四个引导上限成套抬高——`MAX_TRAITS` 16→64、`MAX_STRUCT` 32→64、`MAX_METHOD` 32→64、`MAX_FUNCS` 64→128。理由：`build` 模式跨单元共享同一张符号表，L2 编 `ct-ast` 时这四个额度成了 OO 切片的实际天花板（当时 trait 15/16、struct 27/32、`EmitOps` 32/32）。随后的模块语法迁移另需两项：`MAX_IMPORTS` 16→32（逐类型 `import` 让单文件最多 22 条，`unit.h.ct` 的 `dep`/`depu` 同步改 32）与行重写器的方法 `expand_aliases`（把 cast / `sizeof` 里的 `struct <别名>` 展开成落库 C 名）。这些都是**内部常量与内部改写、不进产物**，故 `test/cases/**` golden、L1/L2 不动点与归档棘轮均逐字节不变，**无 golden 重生成**；代价是静态符号表的 BSS 增加约十几 MB。L0 / L1 **未改**：它们编的是 `l2/**`（trait 3、struct 2、顶层签名 ≈58），额度足够。此例外**不改变** `l2/**` 的「只修 bug、不加能力」边界。
- **L1（`selfhost/l1/ctc.ct`）零复用**：**不得** `#include ctc.c`，设施自带；L1 必须只用 L0 支持的 OO 子集书写（单文件、一语句一行、声明先于使用、不用接口数组），出口是与 L0 **逐字节一致**（banner 也相同）。**该出口已达成**：里程碑 M2 完成于 `test/cases/**` 全绿（25/25、0 regression），且 L1 编出的 L1′ 重编同一批语料仍逐字节一致。用 `bash selfhost/check-goldens.sh` 复核，别再靠手工循环。见 [phase-log](docs/history/phase-log.md) 的 Phase 1 记录。**Phase 2 拆分出口**：L1 用自身 `build`（多文件 + `import`）编译多单元源码树 `selfhost/l2/**`（`core.ct` + `driver.ct`）产出 **L2**，L2 须对 `test/cases/**` 与 L1&#8203; 逐字节一致（25/25）——这是拆分的出口判据；跨单元只走 `pub` 标量包装器（`ct_read_file` 等 10 个），数据/宏/单例全部留在 `core.ct` 内（落进 `core.c`），**不得**为此新增语言特性。关卡：`check-goldens.sh` 第 6/7 步、`check-archive.sh` 3b、`check-m2a.sh` 第 7 步、`ct-tour.sh` 第 6 步。见 [phase-log](docs/history/phase-log.md) 的 Phase 2 记录。
- **L1 必须是 CT OO 风格**：`selfhost/l1/ctc.ct` 的数据模型层与管线层须用 `struct` + `use` + `impl` 书写，**不得**退回 plain-C 直通；仅设施层（`Buf` / 分配器 / `die` / 扫描原语）保持 plain-C 透传。注意管线层由**两个** trait 承载（`PipeOps` 主流程 + `RewriteOps` 行重写层，`struct Pipe` 同时 `use` 二者）——新增方法请放进对应的那一半，别往单侧堆到 `MAX_METHOD`。见 [phase-log](docs/history/phase-log.md) 的 Phase 1 记录。

### 3. 代码风格

- 缩进 4 空格，K&R 花括号；**函数定义**的左花括号另起一行。
- 所有内部函数一律 `static`；不使用非 `static` 的全局函数。
- 命名：
  - 全局变量 `g_` 前缀 + `snake_case`（`g_src`、`g_ntraits`）
  - 函数 `snake_case`（`parse_impl`、`transform_calls`）；「动作」动词开头（`parse_` / `emit_` / `try_` / `find_` / `skip_`）
  - 宏与上限常量 `UPPER_SNAKE`（`MAX_TRAITS`、`MAX_VARS`）
  - 类型 `typedef struct { … } Name;`，**不加** `_t` 后缀（`Trait`、`Struct`、`Method`）
  - 单元文件以**主类型**命名（`selfhost/ct-ast/**` 的 `.h.ct`）：一个单元只有一个主类型（承载该单元语义的那个 struct / trait），附属记录类型可同文件，围绕主类型的代码留在同一文件；主类型过大时可拆**子对象单元**，其文件头必须注明所属主对象；入口 `main.ct` 例外。`check-ast.sh` 的 unit-name lint 校验文件名与顶层类型一致
- 注释：**英文**，`/* … */` 风格；只解释「为什么」，不复述代码。
- 内存：一律走 `xmalloc` / `xstrndup`（失败即 `exit(1)`）；拼接字符串用 `Buf`（`buf_puts` / `buf_putc` / `buf_putn`），不要写 `strcat`。
- 上限：所有固定容量常量集中在文件头部，越界一律 `die()` 报错，不允许静默截断。
- 逐个函数按「工具 → 源扫描 → 符号表 → 签名解析 → 生成器 → 解析器 → 行重写 → main」的顺序摆放，新增函数放进对应分区，不要乱序插入。

### 4. 错误处理约定

- 唯一入口是 `die(pos, fmt, ...)`：`pos` 是 `g_src` 中的字节偏移，由它换算出 `行:列`。
- 报错格式固定为 `文件:行:列: error: 描述`，描述小写、不加句号、标识符用单引号包裹。
- 遇到无法解析的 trait / struct / impl 语法，或引用未定义的 trait / struct，**必须 `die` 并 `exit(1)`**，不允许「跳过继续」。
- 不允许生成明知编译不过的 C 代码来「糊过去」——能静态判定的错误就要在 `ctc` 阶段报出来。
- 不做错误恢复（Phase 0）：一个错误即终止。

### 5. 修改流程

1. **先读后改**：改任何函数前，先读 `ctc.c` 中相关分区，确认数据流与副作用。
2. **先确认后动手**：涉及行为变更（新增语法、改变命名、改变 CLI）必须先向用户说明方案并获得确认。
3. **最小改动**：只改与任务直接相关的代码，不顺手重构、不调整无关格式、不重命名既有符号。
4. **同步文档**：改动**核心语法**（L0 与 L2 共有）或产物命名时，必须同步更新 `docs/language-spec.md` 与 `README.md` 中的语法表；改动 **L2 独有**语法（`namespace` / `import` / `pub` / `Drop` / `#line` / 诊断 / AutoDrop）时，必须同步更新 `docs/roadmap.md` 的简要行、`docs/history/phase-log.md` 的对应记录与 `docs/design/**`，并在 `README.md` 标明适用编译器。
5. **重新生成基线**：生成器有任何变化，都要重跑 `./test/run.sh`（其中的 examples 层会端到端校验 `examples/**` 的展开与运行结果），并确认 `test/cases/**` 的 golden 差异符合预期。
6. **改版本号**：`CTC_VERSION` 会进入生成物注释，改它必须重新生成 `test/cases/**` 的全部 golden、同步 `README.md` 与 `docs/history/phase-log.md` 的版本记录，并跑完整套验证。

### 6. 验证（Definition of Done）

任何改动完成后，必须完整跑通下面三条，并把结果贴给用户：

```bash
# 1) 编译器本身：零警告
gcc -Wall -Wextra -std=c99 selfhost/l0/ctc.c -o ctc

# 2) 代码生成：应无输出（无报错）。产物写临时目录，避免污染仓库
./ctc examples/01_greeter/greeter.ct -o /tmp/greeter.c

# 3) 产物：必须编译并输出两行
gcc -Wall -Wextra /tmp/greeter.c -o /tmp/greeter && /tmp/greeter
# Hello, I'm Tom, age 36
# Hello Jerry, I'm Tom
```

> **「零警告」的基准编译器是 Apple clang**（macOS 默认 `cc`）。GCC ≥ 8 在
> `-Wall -Wextra` 下额外启用 `-Wformat-truncation`，会对 L0 / L1 / L2 里一大批
> 「`snprintf(dst, sizeof dst, "%s…", 至多 255 字节的源)`」报疑似截断——这些是误报
> （源串实际不会那么长），但三层都是冻结层，不为消警告而改。因此在 GCC 上核实零警告时，
> 追加 `-Wno-format-truncation`：
>
> ```bash
> gcc -Wall -Wextra -std=c99 -Wno-format-truncation selfhost/l0/ctc.c -o ctc
> ```
>
> `selfhost/check-all.sh` 已自动做这件事：检测到 `CC` 是 GCC 时会在 wrapper 里同时追加
> `-Wno-format-truncation` 与 `-Wno-implicit-fallthrough` 再传给各子关卡，所以 Linux /
> 容器里跑关卡不必手工加参数。后者同样只在 GCC 的 `-Wextra` 下启用：输入源里**有意**的
> `switch` 贯穿会告警，而 ct 不保留注释（`/* fall through */` 传不过去），只能由 wrapper
> 静音。clang 不受影响。
>
> 另有两个探针依赖 **BSD libc**，在 Linux 上以 `skip` 呈现（不计入失败，也不隐藏回归）：
> `test/run.sh` 的 `cli/short-read` / `cli/tmpfile-cannot-create` 与 `check-archive` 的
> `cli_short_read`——BSD 下「把目录当输入」会短读、`tmpfile()` 在 `$TMPDIR` 不可用时会失败，
> 而 glibc 分别把目录读成 0 字节、退回 `P_tmpdir`。这两条只在 macOS 上真正执行。

补充要求：

- **自动化测试**：`./test/run.sh` 必须全绿（退出码 0）。**八层覆盖**：ctc 自身零警告构建、
  `test/unit` 白盒单测、`test/cases` golden 快照（生成 → 比对 → 编译 → 运行）、
  `examples/**` 端到端（生成 → 构建 → 运行 → 与 `.expected.out` 比对）、
  `dialect` 方言演示（`ct-dialects/` 插件展开 → 同一套生成 / 构建 / 运行 → 与 `.expected.out` 比对，
  并断言未展开的源不可直接编译）、
  `test/errors` 负例诊断（必须非 0 退出，且带 `文件:行:列: error:` 前缀）、
  `known limitations` 特征化断言、`cli` 参数与驱动分支。`CC=gcc ./test/run.sh` 可换编译器。
- **CT 线关卡同样必跑**（`run.sh` 只驱动 L0）：一条命令 `bash selfhost/check-all.sh` 依次跑
  `./test/run.sh`、`selfhost/check-goldens.sh`（L1 对 golden + L1′ 自举闭环 + L1/L2 不动点）、
  `selfhost/check-archive.sh`（L2 对归档 oracle 的棘轮）、`selfhost/check-m2a.sh`、
  `selfhost/ct-tour.sh`、`editors/vscode/test/check-grammar.py`、`test/pkg/run.sh`（Phase 8.1–8.3
  包管理器：本地目录源、git 源与 `install` 校验）、`selfhost/check-ast.sh`（Phase 9.1–9.7 + 10.x
  AST 编译器的行为用例、CLI 错误分支、自编不动点与全量语料等价）、`selfhost/check-warnings.sh`
  （生成物 `-Wall -Wextra` 零告警）、`test/docs/check-docs.py`（文档链接、版本 token、门禁计数与
  阶段状态）；任一失败即整体非零；
  `bash test/acceptance/run.sh` 单独报告（其 PENDING 属预期，不阻断）。改动 `selfhost/**` 后必须跑一遍。
- **ct-ast 是分组多单元树**：各分组（`runtime/`、`frontend/`、`tool/`）按全路径互相 `import`，
  构建时必须带 `-I selfhost/ct-ast`（门禁脚本与 README 的安装命令已内置；手工构建同样要加）。
- **手工三件套不可省**：套件内部的路径与你手工敲的不完全相同，改完必须按上面三条命令亲自跑一次并贴结果。
- **新增/修改语法必须补用例**：见第 9 节检查清单。
- **编辑器侧**：语法有变必须同步 `editors/vscode/syntaxes/ct.tmLanguage.json`，并跑
  `python3 editors/vscode/test/check-grammar.py`（168 项断言，无 node 时 167 项并跳过 index 检查；必须全绿）。它校验插件而不是编译器，
  因此**不进** `./test/run.sh`；反过来它也不能替代手工三件套。
- **诚实报告**：验证失败就如实说失败并贴原始输出，不允许把「没跑」说成「通过」；
  更不允许靠改 golden 基线或 `.expected.out` 来「修」失败——只有在确认编译器行为变更是有意为之之后，才重新生成它们。
- **逐片红证**：每个新增断言或夹具，必须先在本地跑出失败并记录退出码与失败文案，
  不允许「先写实现、事后补红证」；失败状态不提交，实现与夹具在**同一次提交**里转绿，
  主干在每个提交上都必须是绿的。提交正文必须带一行红证记录 `red: rc=<N>, "<失败文案>"`，
  确属免红证时写 `red: n/a (<理由>)`。免红证只有三类：纯重构（行为不变且既有断言已覆盖）、
  纯文档、以及与该断言无关的实现改动，除此之外不许免。**不许用一次全局回放代替逐片红证**：
  Phase 31 那种「实现全绿后再统一回放旧失败提交」的做法不再是默认口径，只在补历史遗留时才允许。
- **版本号不许为了过门禁而回退**：不得把 `Revert "chore(release): bump …"`、回退
  `CTC_VERSION` / 版本常量、或批量回退 golden 当作让门禁变绿的手段。门禁红在版本或 golden 上时，
  正确动作是补齐未同步的 golden、或修正真正的失败原因，而不是撤掉 bump。确需降版本必须由用户
  明确裁定，并在提交正文写明裁定来源与日期。

### 7. 禁止事项

- 禁止在 `ctc.c` 中引入类型检查、语义分析、优化（Phase 0 范围外）。
- **禁止把非 bug 修复的改动混进 `ctc.c`**：冻结期只接受「不改变既有语料产物」的缺陷修复（判据与登记清单见第 2 节）；**禁止放宽任何 `MAX_*` 上限**，**禁止为了让 L1 过某个关卡而改 `ctc.c`**，**禁止打着「修 bug」的旗号改既有行为**（若产物确实变了，那就不是 bug 修复，必须走用户确认 + 重新生成 golden 的流程）。
- 禁止把 namespace / 多文件 / import / Drop / `#line` / 诊断在 **C 侧**新增或加回（Phase 0.3 已把它们移出 `ctc.c`；Phase 2–5 改用 **CT** 重做）；禁止新增继承。泛型**函数**已在 Phase 26 落地（`T name<T>(...)` + `name<int>(...)`，见 `docs/language-spec.md` §4.48），**带单 trait 约束的泛型函数**已在 Phase 28 落地（`T name<T: Trait>(...)`，模板体内经 vtable 方法槽静态派发，见 §4.50）；**泛型 struct 与内置 `Vec`/`Map`** 已在 Phase 29 落地（`struct Name<T, U>` + `impl<T> Name<Args>` 静态派发、`foreach` 容器协议，见 §4.51）；参数化 trait / 多约束 / 类型推导仍禁止新增，除非用户明确把对应阶段指派给你。
- 禁止把 `examples/**` 下生成的 `.c` / `.h` 入库或手工编辑（生成物一律不入库）。
- 禁止为了让示例通过而修改 `examples/**/*.ct` 的语义（可以扩充，不可以削弱）。
- 禁止吞掉错误、禁止静默截断、禁止 `TODO` 空实现留在主路径上。
- 禁止把项目名 `ct`、入口命令 `ct`（`ctc` 为兼容别名）或后缀 `.ct` 改成 `ct-lang` / `ctlang` / `.ctlang`（`ct-lang` 只是仓库名）。唯一被认可的演进是 roadmap 里已定的「单入口 `ct` + `ctc` 兼容别名」，不得自行发明其它名字。
- 禁止删除或改写生成物 banner 里的许可声明行，也禁止移除 `ctc.c` 顶部的 SPDX / 版权 / 例外说明——输出例外必须**随产物走**（见 `LICENSE.EXCEPTION`）。
- 禁止给 `editors/**` 引入构建步骤、npm 依赖或打包器（见第 2 节硬性边界）。
- 禁止提交二进制文件、`.o`、临时文件。

### 8. 提交规范

```
<type>(<scope>): <subject>      # 英文祈使句，≤ 50 字符
```

- `type`：`feat` | `fix` | `docs` | `refactor` | `test` | `chore`
- `scope`：`parser` | `codegen` | `rewrite` | `cli` | `selfhost` | `docs` | `example`
- 正文用中文说明「为什么这么改」以及验证方式；一次提交只做一件事。
- 正文的 `red:` 行按第 6 节「逐片红证」记录；免红证只限那三类。

### 9. 新增语法特性检查清单

开发新特性（如 Phase 1 的 namespace）时逐条确认：

- [ ] 词法识别不会与既有构造冲突（用 `word_at()` 做词边界判断，而不是 `strncmp`）
- [ ] 解析器能对不完整/错误输入给出带位置的报错
- [ ] 生成物的命名规则已写入 `docs/language-spec.md`
- [ ] 未破坏「字符串 / 字符 / **单行**注释内不重写」的既有保证（跨行块注释的**续行**不在此列：它会被当普通代码行处理，是 [language-spec](docs/language-spec.md) §6.2 记录的已知限制）
- [ ] `examples/**` 增加或更新示例，生成物重新展开并人工核对，`.expected.out` 同步更新
- [ ] 每个 Phase 至少交付一个**可运行样例**，并接入真门禁（`./test/run.sh` 或 `check-ast.sh` 的夹具，二者之一必须实际执行它）；缺样例视同判据未满足，不得在 roadmap 或阶段卡里标「完成」
- [ ] `test/cases` 增加 golden 用例（基线用 `./ctc <case>.ct -o <case>.expected.c` 重新生成并人工核对，禁止手写），负例补进 `test/errors`
- [ ] 三件套验证通过，且 `./test/run.sh` 全绿
- [ ] `editors/vscode/syntaxes/ct.tmLanguage.json` 覆盖了新构造，`python3 editors/vscode/test/check-grammar.py` 全绿
- [ ] `README.md` / `docs/language-spec.md` 已同步
