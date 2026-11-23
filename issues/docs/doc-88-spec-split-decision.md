# DOC-88 · `language-spec.md` 是否拆分（v1.1 决策）

| 项 | 值 |
| --- | --- |
| 模块 | docs（spec 结构） |
| 定性 | 决策项（v1.1，不在 v1-PH-0 内做） |
| 严重度 | Low |
| 锚点 | v0.88.0（2026-11-21） |
| 依据 | [外部评审与惯用卡评估](../../docs/reviews/2026-11-21-v088-external-review-eval.md) §1 |
| 状态 | verified |
| 处置证据 | **延后（2026-11-22，REV）**：A+ 决策已定稿（不拆文件；目录双向断言 + 行号锚点冻结/白名单 + DOC-89 另立）；三项执行属 v1.1，不在 v1-PH-0 冻结期做 |
| blocked-by | 执行触发：v1.1 开卡（或 spec > 4,000 行 / 导航被评审认定不可用 / 多维护者冲突成为常态）；负责人 REQ，DOC-89 承接通用锚点校验 |

## 现象

`docs/language-spec.md` 约 216KB / 3,206 行，27 个 §4.x 小节；`docs/spec/` 目录目前只有
AI 工作流文档。外部报告建议 v1.1 议“拆分或维持现状”。

## 决策：A+（维持单文件 + 导航 + 行号锚点冻结）

2026-11-21 所有者定稿：**不拆文件**，用三项精修补上导航与迁移护栏；拆分留触发条件。

### 为什么不是 B/C

实测依赖面（`git grep`，不含 `docs/history/**`）：

| 指标 | 数值 |
| --- | --- |
| 引用 `language-spec.md` 的文件 | 328（docs 177 / battle 61 / issues 60 / test 18 / 其余 12） |
| 引用总次数 | 1,039 |
| 带锚点引用 | 261 |
| 其中**行号锚点** `#L…` | **240** |
| 其中节锚点 | 21 |

`check-docs` 目前只校验路径，**不解引用锚点**（`target.split("#")[0]`），所以锚点烂掉是静默的。
按 B 拆层会让 240 个行号锚点全部错位、21 个节锚点可能重写，波及 328 个文件且门禁不报红；
C 按特性拆还会把跨节约束（如 §4.69＋§4.70 的位置白名单）拆散。A+ 先把脆弱点（行号锚点）
清掉，再谈结构。

## A+ 的三项精修

### 1. 索引双向断言

在 `language-spec.md` 顶部加「目录」节，列出**全部 H2 与全部 §4.x H3**（带稳定节锚点）。
`check-docs` 加双向断言：

- **正向**：每个 H2 / §4.x 标题都在目录里有且只有一条；
- **反向**：目录里的每一条都能解析到真实标题；
- 任一方向缺项 / 死项即红。

断言只认标题与目录，不比较叙述文字；实现时按标题文本归一化（去反引号、压缩空白）。

### 2. 行号锚点白名单分批

- **立即冻结**：新增 `language-spec.md#L…` 引用一律拒收（`check-docs` 红）；
- **存量白名单**：`test/docs/line-anchors.txt`，每行 `<path>#L<a>[-L<b>]  <批次>`；
  条目消失（迁移完成）后必须从白名单删除，否则按“僵尸条目”报红；
- **分批优先级**：

| 批次 | 范围 | 理由 |
| --- | --- | --- |
| B0 | `README.md`、`docs/*.md`（除 `docs/history/**`）、`AGENTS.md` | 门面与规约，读者最多，锚点最易失效 |
| B1 | `issues/**` | 活跃台账；结论引用要能跳转 |
| B2 | `battle/**` | 决策记录；归档后不再改，但链接仍要可读 |
| B3 | `test/**`、`examples/**`、`selfhost/**` 的注释 | 与代码同提交，最后清理 |
| — | `docs/history/**` | 历史快照，永不移出白名单（正文不改写） |

每批迁移 = 行号锚点换成节锚点 + 白名单同步删项，单独提交、可单批回滚。

### 3. 通用锚点校验另立 issue

本卡只冻结 `language-spec.md` 的行号锚点；**所有** Markdown 链接的 `#fragment`
（含节锚点、行号锚点）的通用校验另立 [DOC-89](doc-89-anchor-validation.md)，
避免把“全仓锚点门禁”绑在 spec 结构决策上。DOC-89 未落地前，A+ 的行号冻结仍有效。

## 拆分触发条件（写死）

同时满足以下任一条即启动 B 的正式评估（不是自动拆）：

1. `language-spec.md` 超过 **4,000 行**；或
2. B0–B3 的行号锚点清零后，单文件导航仍被评审认定不可用；或
3. 出现多名维护者并行改 spec，合并冲突成为常态。

## 验收（v1.1）

- 目录双向断言绿；标题与目录零缺项、零死项；
- 新增 `language-spec.md#L…` 零发生；白名单只剩 `docs/history/**`；
- 每批迁移单独提交，`check-docs` 每批绿；
- [DOC-89](doc-89-anchor-validation.md) 已立项（落地可在 v1.2）。

## 非目标

- 不在 v1-PH-0 / v1.0 冻结期改 spec 结构；
- 不重写 spec 内容（只加目录 + 换锚点 + 白名单迁移）；
- 不拆文件；不把 §4.x 变成独立文件；
- 不在本卡实现通用锚点校验（归 DOC-89）。

## 关联

- [v1 路线](../../docs/planning/v1-release-plan.md) §2
- [DOC-86](doc-86-readme-v088-rewrite.md)
- [DOC-89](doc-89-anchor-validation.md)（通用锚点校验）

## 复核与延后（2026-11-22，REV）

**结论：`deferred`。决策本身已定稿（A+，2026-11-21 所有者），但 A+ 的三项执行属 v1.1，
本轮不做，且不在 v1-PH-0 冻结期改 spec 结构。**

决策内容已写死在本条：**不拆文件**；用「目录双向断言 + 行号锚点冻结/存量白名单 + DOC-89
通用锚点校验」三项精修补导航；拆分只在三个触发条件同时/任一满足时启动正式评估。

执行尚未开始（与预期一致）：

```console
$ wc -l docs/language-spec.md
    3244 docs/language-spec.md

$ grep -n '^## 目录' docs/language-spec.md; echo rc=$?
rc=1

$ ls test/docs/line-anchors.txt
ls: test/docs/line-anchors.txt: No such file or directory

$ grep -n 'target.split("#", 1)\[0\]' test/docs/check-docs.py
130:            dest = target.split("#", 1)[0]
```

当前 spec 3,244 行，未过 4,000 行阈；目录节与 `line-anchors.txt` 白名单尚未建立；
`check-docs` 仍只校路径、不解 `#fragment`（第 130 行），与决策 §为什么不是 B/C 的诊断一致。

**触发/负责人**：v1.1 开卡时由 REQ 排 A+ 三项（每批锚点迁移单独提交、可单批回滚）；
若 spec 先过 4,000 行或出现多维护者并行冲突，提前启动 B 评估。DOC-89 承接通用锚点校验，
可在 v1.2 落地，不阻塞本条的 A+。

## 实施（DOC/DEV，2026-11-23）

**状态未改（`deferred`），A+ 三项已按 decision 执行，待 REV/REQ 复核后决定状态。**

### 1. 目录（精修 1）

`docs/language-spec.md` 顶部新增 `## 目录`，列**全部 H2（除目录自身）与全部 H3**，共 40 条：
一级节 0/1–10、§4.51–§4.75（含 4.51.1 / 4.52.1）与 §11。§4.1–§4.50 是 §4 下的 H4 小节，
随 §4 正文阅读，不单列。条目一律用标题生成的稳定节锚点，不写行号。

`test/docs/check-docs.py` 新增双向断言（DOC-88 §1）：每个 H2/H3 在目录中恰好一条；
目录每条必须解析到真实标题；缺目录、缺标题、重复条目、死条目、目录不在顶部均红。
`--selftest` 增加 6 例夹具（valid / missing / duplicate / dead / no-outline / not-at-top）。

### 2. 行号锚点冻结与白名单（精修 2）

- 新断言：任何 Markdown 里指向 `docs/language-spec.md#L…` 的链接，若不在
  `test/docs/line-anchors.txt`，即红；白名单条目无引用（僵尸）、批次不是最早待迁移批次、
  重复条目、非法批次也红。
- 白名单格式：`docs/language-spec.md#L<a>[-L<b>]  <批次>`；批次 `B0`/`B1`/`B2`/`B3`/`HIST`。
- 迁移按 DOC-88 的 B0–B3 分批，单独提交、可单批回滚；迁移时按该文件写作时点的 spec 版本
  定位原行所属小节，不按当前行号猜。

| 批次 | 范围 | 本轮迁移 | 剩余 |
| --- | --- | --- | --- |
| B0 | `README.md` / `AGENTS.md` / `docs/**`（`docs/history/**` 除外） | 91 处 / 19 文件 | 0 |
| B1 | `issues/**` | 91 处 / 32 文件 | 0 |
| B2 | `battle/**` | 57 处 / 10 文件 | 0 |
| B3 | `test/**` / `examples/**` / `selfhost/**` 等 | 0 处（本轮无命中） | 0 |
| HIST | `docs/history/**` | 不迁移（3 条） | 3 条永不移出 |

白名单从 **163 条**（242 处引用）收缩到 **3 条**，全部是 `docs/history/**` 的 `HIST`。
`FRAGMENT_EXEMPT` 里 DOC-67 / DOC-71 的三条越界 spec 行号豁免随迁移删除。

### 3. 通用锚点校验（精修 3）

复用 DOC-89 已落地的 `#fragment` 校验（节锚点 / 行号范围 / 同文件 / 中文 slug / 重复标题），
不另造一套；本轮只在其上叠加 `language-spec.md#L…` 的冻结与白名单。

### 4. 证据

红（`test(docs): DOC-88 红`，baseline `b9708205`）：

```console
$ python3 test/docs/check-docs.py
FAIL: docs/language-spec.md: missing `## 目录` outline (DOC-88)
check-docs: FAIL (1 problem(s))

$ python3 test/docs/check-docs.py --selftest | tail -2
outline-ratchet selftest: OK (6 cases)
line-anchor-ratchet selftest: OK (7 cases)
```

实现后绿：

```console
$ python3 test/docs/check-docs.py
check-docs: OK (… 40/40 outline entr(ies), 3 spec line anchor(s) in 3 ledger entr(ies))
$ python3 test/docs/check-docs.py --selftest
line-anchor-ratchet selftest: OK (7 cases)
$ bash tools/check.sh g4   # rc=0
$ bash tools/check.sh g1   # rc=0
$ bash tools/check.sh g8   # rc=0
```

负例（实跑后还原）：

```console
# 新增 language-spec 行号锚点
FAIL: docs/README.md: new language-spec line anchor -> docs/language-spec.md#L9999 (DOC-88 …)
# 白名单僵尸条目
FAIL: test/docs/line-anchors.txt: zombie entry docs/language-spec.md#L9999 B0 (… DOC-88)
```

### 5. 提交

| 提交 | 内容 |
| --- | --- |
| `eba03c83` | `test(docs): DOC-88 红`：断言 + 白名单初版 + 夹具 |
| `85ab40c0` | `docs(spec): DOC-88 顶部目录（40 条）` |
| `39f6e1e2` | `docs(anchors): DOC-88 B0 迁移（91 处）` |
| `1d6e5673` | `docs(anchors): DOC-88 B1 迁移（91 处）` |
| `c5af1515` | `docs(anchors): DOC-88 B2 迁移（57 处）` |
| `185e0acd` | `docs(gate): DOC-88 删除已迁移的 FRAGMENT_EXEMPT` |

不 push、不打 tag、不改版本号；`language-spec.md` 现 3,404 行，未过 4,000 行的拆分评估阈值。

## 复核（REV，2026-11-23）

A+ 三项执行完成：`language-spec.md` 顶部 40 条目录（全 H2 + 全 H3）双向断言；
行号锚点冻结 + 白名单，B0/B1/B2 共 239 处迁移，余 3 条 HIST；DOC-89 通用 fragment 复用；
`check-docs` 与 selftest 绿。
