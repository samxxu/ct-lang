# DOC-98 · 语言名统一写 `Ct`：政策文本、46 处替换与裸 `ct` 门禁

| 项 | 值 |
| --- | --- |
| 模块 | docs（命名口径 + `check-docs`） |
| 定性 | 政策裁定后的文档一致性变更（不改语言语义/命令） |
| 严重度 | Medium（影响全仓活跃散文与首屏） |
| 锚点 | `8615c020`（2026-11-24） |
| 依据 | [命名一致性评审](../../docs/reviews/naming-consistency-2026-11-24.md)；[DOC-94](doc-94-ct-spelling.md) |
| 状态 | open |
| 处置证据 | **accepted（2026-11-24 所有者裁定：语言名散文写 `Ct`；命令/后缀/仓库名/包名不变）** |

## 1. 裁定

| 语境 | 规范形态 | 是否改 |
| --- | --- | --- |
| 语言/产品名（散文） | **`Ct`** | 改（本卡 Batch 1） |
| CLI 命令 | `ct`（清单里写 `` `ct` ``） | 不改；只在散文中补代码标记 |
| 后缀 / 仓库 / 包 / 编译器树 | `.ct` / `ct-lang` / `ct/std` / `ct-ast` | 不改 |
| 环境变量 / 宏 | `CT_*` / `CTC_VERSION` | 不改 |
| 历史与原始证据 | 原样（`docs/history`、`docs/reviews`、`issues`、`battle` 等，共约 784 处 `CT`） | 不改 |
| 生成块与上游副本 | `AGENTS.md` 的 `spec:begin…end`、`docs/spec/ai-coding-workflow.md` | 项目侧不能手改，走 Batch 3 的 CR |

与 [DOC-94](doc-94-ct-spelling.md) 的关系：DOC-94 只裁 `CT → Ct`（大写）；本卡把“小写 `ct` 作语言名”也收口，
两卡合起来才是完整口径。`AGENTS.md` §1 现行“项目/语言 `ct`、不要统一”的表述由本卡改写。

## 2. Batch 1：政策文本 + 46 处替换（一次文档提交）

### 2.1 政策文本

- [AGENTS.md](../../AGENTS.md) §1：
  - 「是什么」行 `ct —— Ct（C with Traits）` → `Ct —— C with Traits`；
  - 「命名」行改为：语言名 **`Ct`**；命令 `ct`、后缀 `.ct`、仓库 `ct-lang`、包 `ct/std` 保持；
    **删除“不要统一”**，改为“禁止把命令/标识符写成 `Ct`，也禁止把语言名写成 `ct`”。
- [glossary](../../docs/glossary.md) §0：标题「刻意不统一，不要"修正"」→「命名口径：语言名 `Ct`，命令保持 `ct`」；
  第 17/19 行词条 `ct（…）` → `Ct（命令 `` `ct` ``）`；保留已有的“2026-11-22 起活跃散文书写为 `Ct`”提示。

### 2.2 语言名替换（20 处，评审 §2 表）

`README.md` 1/5；`AGENTS.md` 601/746；`docs/glossary.md` 17/19；`docs/language-spec.md` 244/1315/1539/1585/1648/1670/2191/2393；
`docs/construction.md` 45/52/66/166/205/206。

### 2.3 门禁活跃集合补充（18 处，评审未覆盖）

| 文件 | 处数 | 说明 |
| --- | --- | --- |
| `examples/c-superset/README.md` | 15 | 语言名（第 1/3/9 行等） |
| `examples/tour/README.md` | 1 | 散文 |
| `examples/wave1-demo/README.md` | 1 | 散文 |
| `docs/planning/j6-evidence/p73/evidence.md` | 1 | `没有专门的 ct 诊断` → `Ct 诊断` |

> `docs/phases/**` 已在迁移后加入 `CT_EXEMPT_DIRS`，不在本卡范围；`test/**`、`selfhost/**` 经扫描为 0。

### 2.4 命令补代码标记（8 处，评审 §4 表）

`docs/ct-pkg-index.md:9`、`docs/ct-pkg.md:7`、`docs/roadmap.md:30`、`docs/planning/requirements-pool.md:207/212/219`、
`docs/planning/open-items-routing.md:43/44`：把裸 `ct` 包成 `` `ct` ``。

## 3. Batch 2：裸 `ct` 门禁（Batch 1 绿后再加）

- 挂 `check-docs` 现有 DOC-94 挂点，**不新增门禁编号**；
- 正则 `(?<![\w./-])ct(?![\w./-])`，跳过 fenced code、行内代码、URL、HTML 注释；
- 豁免目录沿用 `CT_EXEMPT_DIRS`（含 `docs/spec`、`docs/phases`），`AGENTS` 生成块跳过；
- 负例 fixture：`# ct — …` 必须红；`` `ct build` ``、`ct-pkg`、`.ct`、`ct.lock` 必须绿；
- 先把 Batch 1 跑成 0 命中，再加门禁，避免门禁一开就红。

## 4. Batch 3：上游 CR（不在本仓实现）

- 主规范 `CT 包编码通用条款（仅 CT 项目）` → `Ct 包编码通用条款（仅 Ct 项目）`；
- 定版后由项目侧 `sync-agents.sh --write` 刷新 `AGENTS.md` 生成块与 `docs/spec/` 副本，跑 `g0` / `g9`；
- 在 CR 落地前，生成块里的 2 处 `CT` 记为**已知上游例外**，不假装已统一。

## 5. 验收

- 活跃散文（按 `check-docs` 的 `ct_active_paths()` 口径）裸 `ct` 归零，且 `CT` 仍为 0；
- `README.md` 首行为 `# Ct — C with Traits 编译器`；`AGENTS.md` §1 与 glossary §0 口径一致；
- Batch 2 的门禁负例可红、正例可绿；`check-docs` 全绿；
- 历史 784 处 `CT` 一处未改；命令、后缀、仓库名、包名、环境变量零改动；
- `g0` 绿（生成块与 `docs/spec` 未动，sha 不变）。

## 6. 非目标

- 不改命令名、二进制名、`.ct` 后缀、`ct-lang` / `ct/std` / `ct-ast` / `ct-pkg` / `ct.lock`；
- 不重写历史与原始证据（报告、battle、issues、history）；
- 不在本卡改主规范或 `docs/spec` 副本（Batch 3 是 CR，另仓）；
- 不扫描/承诺 `README.en.md`（AGENTS 0.4：AI 代理不主动读英文镜像；如需统一另开卡）。

## 7. 关联

- [naming-consistency-2026-11-24](../../docs/reviews/naming-consistency-2026-11-24.md)（来源）
- [DOC-94](doc-94-ct-spelling.md)（`CT → Ct` ratchet）
- [AGENTS.md](../../AGENTS.md) §1 / §11.5（政策文本与落库）
- [glossary](../../docs/glossary.md) §0
- [check-docs](../../test/docs/check-docs.py)（DOC-94 挂点）
