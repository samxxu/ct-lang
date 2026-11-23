# 命名一致性评审：`Ct` / `ct` / `CT`（2026-11-24）

| 项 | 值 |
| --- | --- |
| 基线 | `64e87d1e`（`v0.88.3-195-g64e87d1e`） |
| 范围 | 活跃散文：`README.md`、`AGENTS.md`（不含生成块）、`docs/*.md`、`docs/planning/*.md`；`docs/spec/` 与生成块单列 |
| 方法 | 去 fenced code、inline code、URL、HTML 注释后逐行扫描；`check-docs` DOC-94 规则对照；按 DOC-94 豁免历史目录 |
| 结论 | **规范已经存在（DOC-94：活跃散文写 `Ct`），但没有落到最容易看见的地方：README 标题/首句仍是 `ct`，AGENTS §1 仍写“项目/语言 `ct`、不要统一”。`CT` 在活跃散文已为 0，但 AGENTS 生成块还有 2 次、`docs/spec` 副本还有 7 次；裸 `ct` 散文还有 28 处，其中 20 处是语言名。** |

> 本报告是 REVIEW 产出；`签收: REVIEW 2026-11-24（待 EDITOR）`。

---

## 0. 先定口径：哪些该改，哪些不能改

用户要求“统一为 Ct”，但不能把命令、后缀、仓库名也改成 `Ct`——那会破坏 CLI 与文件系统。正确口径是：

| 语境 | 规范形态 | 例子 | 是否改 |
| --- | --- | --- | --- |
| 语言/产品名（散文） | **`Ct`** | “Ct 是……”“Ct 编译器”“Ct 构造” | 要改 |
| CLI 命令 | `ct` | `` `ct build` ``、`` `ct check` `` | 不改（但要放进代码标记） |
| 源文件后缀 | `.ct` | `main.ct` | 不改 |
| 仓库名 | `ct-lang` | GitHub `ct-lang` | 不改 |
| L0 种子/兼容别名 | `ctc` | `ctc.c`、`ln -s ct ctc` | 不改 |
| 编译器树 | `ct-ast` | `selfhost/ct-ast/**` | 不改 |
| 包/生态标识 | `ct-pkg`、`ct/std`、`ct.lock` | `ct get ct/std` | 不改 |
| 环境变量/宏 | `CT_*`、`CTC_VERSION` | `CT_HOME`、`CT_C_BOUNDARY` | 不改 |
| 历史/原始证据 | 原样 | `docs/history/**`、`battle/**`、`issues/**` | 不改 |
| 第三方专名 | 原样 | computed tomography 的 `CT` | 不改 |

一句话：**`Ct` 是语言名，`ct` 是命令/标识符；`CT` 只应出现在历史与上游生成文本里。**

---

## 1. 当前实测

### 1.1 活跃散文

扫描 80 个活跃文件（去代码块/行内代码/URL）：

| 形态 | 次数 | 说明 |
| --- | --- | --- |
| `Ct` | **261** | 已经是主流 |
| 裸 `ct` | **28** | 10 个文件；其中 20 处是语言名，8 处是命令/基线/表格标签 |
| `CT` | **0** | DOC-94 ratchet 已把活跃散文的 `CT` 清零 |

`check-docs` 输出也确认：`0 bare CT in 80 active file(s)`（DOC-94 规则）。**问题不在 `CT`，在裸 `ct`。**

### 1.2 生成块/上游副本

| 位置 | `CT` 次数 | 能否本地改 |
| --- | --- | --- |
| `AGENTS.md:46`（`spec:begin` 生成块） | 2 | **不能**；由 `sync-agents.sh` 从主规范生成 |
| `docs/spec/ai-coding-workflow.md`（全文副本） | 7 | **不能**；必须与主规范逐字一致 |

这就是用户仍能在 AGENTS 里看到 `CT` 的直接原因：生成块里有
`CT 包编码通用条款（仅 CT 项目）`。本地改它会破坏 `g0`；只能改主规范后重新同步。

### 1.3 历史/豁免

| 目录 | `CT` 次数 |
| --- | --- |
| `docs/history` | 146 |
| `docs/reviews` | 223 |
| `docs/design` | 26 |
| `docs/proposals` | 108 |
| `docs/decisions` | 15 |
| `battle` | 106 |
| `issues` | 160 |
| **合计** | **784** |

这些是 DOC-94 明确豁免的历史快照；不建议为了“看起来统一”重写 784 处历史，那会破坏证据与提交可追溯性。

---

## 2. P1：规范自相矛盾（必须先修）

### P1-1 `AGENTS.md` 仍规定“项目/语言 `ct`、不要统一”

`AGENTS.md:601-602`：

- `是什么 | ct —— Ct（C with Traits）...`：同一行同时写 `ct` 和 `Ct`；
- `命名 | 项目/语言 \`ct\` ... 差异是刻意的 ... **不要“统一”**`。

`docs/glossary.md:7` 的标题也写“命名硬约定（刻意不统一，不要‘修正’）”，第 17 行仍以 `ct（Ct = ...）` 作为词条。

而 `issues/docs/doc-94-ct-spelling.md` 已 `verified`，明确“活跃散文统一写 Ct；标识符、命令、路径保持现状”。**两份规约冲突**：DOC-94 要求散文 `Ct`，AGENTS/glossary 说语言名是 `ct` 且不要统一。只要这条不裁，执行者每次都会按 AGENTS 写 `ct`。

**建议改法**（需 EDITOR/用户确认）：

- AGENTS §1 改成：“语言名 **`Ct`**（散文）；命令/后缀/仓库名保持 `ct` / `.ct` / `ct-lang`；两者不是同一个词，禁止把命令写成 `Ct`，也禁止把语言名写成 `ct`。”
- 删除或改写“差异是刻意的，不要统一”这句；把“不要统一”限定为**命令/标识符不得改**，而不是语言名。
- glossary 第 7 行标题改为“命名口径：语言名 `Ct`，命令/标识符原样”，第 17/19 行词条改为 `Ct（命令 \`ct\`）`。

### P1-2 20 处语言名仍写裸 `ct`

以下均已确认不在代码块/行内代码中：

| # | 位置 | 原文片段 | 处理 |
| --- | --- | --- | --- |
| 1 | `README.md:1` | `# ct — C with Traits 编译器` | `# Ct — ...` |
| 2 | `README.md:5` | `**ct** 是一个 ... 编译器` | `**Ct** 是 ...` |
| 3 | `AGENTS.md:601` | `是什么 \| ct —— Ct ...` | `是什么 \| Ct —— ...` |
| 4 | `AGENTS.md:746` | `而 ct 不保留注释` | `而 Ct 不保留注释` |
| 5 | `docs/glossary.md:17` | `\| ct（Ct = ...）` | `\| Ct（命令 \`ct\`）` |
| 6 | `docs/glossary.md:19` | `\| ct（单入口）` | `\| Ct（单入口命令 \`ct\`）` |
| 7 | `docs/language-spec.md:244` | `下列 ct 构造` | `下列 Ct 构造` |
| 8 | `docs/language-spec.md:1315` | `ct 不声明它们` | `Ct 不声明它们` |
| 9 | `docs/language-spec.md:1539` | `ct 不检查实参类型` | `Ct 不检查实参类型` |
| 10 | `docs/language-spec.md:1585` | `ct 不展开 \`#include\`` | `Ct 不展开 ...` |
| 11 | `docs/language-spec.md:1648` | `ct 不读分支` | `Ct 不读分支` |
| 12 | `docs/language-spec.md:1670` | `ct 只负责把它...` | `Ct 只负责...` |
| 13 | `docs/language-spec.md:2191` | `是 ct 独有关键字` | `是 Ct 独有关键字` |
| 14 | `docs/language-spec.md:2393` | `已知 ct 类型` | `已知 Ct 类型` |
| 15 | `docs/construction.md:45` | `已知 ct struct` | `已知 Ct struct` |
| 16 | `docs/construction.md:52` | `不是 ct struct` | `不是 Ct struct` |
| 17 | `docs/construction.md:66` | `已知 ct struct` | 同上 |
| 18 | `docs/construction.md:166` | `不是 ct struct` | 同上 |
| 19 | `docs/construction.md:205` | `不是 ct struct` | 同上 |
| 20 | `docs/construction.md:206` | `不带 ct struct` | 同上 |

> 这 20 处是纯书写替换，不改语义；但必须由 DEV 提一次文档提交，并由 REV 复核没有误改代码/命令。

---

## 3. P1：`CT` 仍出现在 AGENTS 生成块（上游阻塞）

`AGENTS.md:46` 的生成块有：

> `CT 包编码通用条款（仅 CT 项目）`

`docs/spec/ai-coding-workflow.md` 有 7 次 `CT`（第 178、1347、1549 行等）。它们与主规范逐字同步，**项目侧不能手改**：

- 手改 `AGENTS.md` 块内会 `g0` 红；
- 手改 `docs/spec` 副本会 `g0` 的 sha256 校验红；
- `check-docs` 的 DOC-94 扫描又跳过生成块/副本，所以本地门禁看不到。

**结论**：用户看到的 `CT` 不是本地漏改，而是**主规范自身的措辞**。要彻底统一，需要：

1. 在主规范仓库提 `CR-*`：`CT 包编码通用条款（仅 CT 项目）` → `Ct 包编码通用条款（仅 Ct 项目）`；
2. 主规范定版后，由项目侧从规范来源重新 `sync-agents.sh --write`；
3. 同一次提交刷新 `AGENTS.md` + `docs/spec/ai-coding-workflow.md`，跑 `g0`/`g9`。

在 CR 落地前，本项目只能在报告里登记这个**已知上游例外**，不能假装已统一。

---

## 4. P2：命令/基线/表格里的 8 处裸 `ct`

这些不是语言名，不应机械替换成 `Ct`；应放进行内代码或改写为命令：

| # | 位置 | 原文 | 建议 |
| --- | --- | --- | --- |
| 1 | `docs/ct-pkg-index.md:9` | `核对基线：ct 0.77.1` | `核对基线：\`ct\` 0.77.1`（工具版本） |
| 2 | `docs/ct-pkg.md:7` | 同上 | 同上 |
| 3 | `docs/roadmap.md:30` | `单入口 ct` | `单入口 \`ct\`` |
| 4 | `docs/planning/requirements-pool.md:207` | `已安装的 ct` | `已安装的 \`ct\`` |
| 5 | `docs/planning/requirements-pool.md:212` | `脱离 ct` | `脱离 \`ct\`` |
| 6 | `docs/planning/requirements-pool.md:219` | `无 ct 安装的 CI` | `无 \`ct\` 安装的 CI` |
| 7 | `docs/planning/open-items-routing.md:43` | `ct 先 rc=0` | `\`ct\` 先 rc=0` |
| 8 | `docs/planning/open-items-routing.md:44` | 同上 | 同上 |

> 这样裸 `ct` 归零，同时保留“命令是 `ct`”的事实。若把这几处改成 `Ct`，会把工具名与语言名再次混在一起。

---

## 5. P2：门禁只抓 `CT`，不抓裸 `ct`

`test/docs/check-docs.py:1414` 的 DOC-94 规则只匹配裸 `CT`；它不会报 `README.md:1` 的 `# ct ...`。所以：

- `CT` 已清零（0/80 活跃文件）；
- 裸 `ct` 仍 28 处，且 README 首行这种最显眼的位置不会被门禁拦住。

**建议**（与 DOC-94 同一挂点，不新增门禁编号）：

1. 在 `check-docs` 增加“活跃散文裸 `ct`”规则：
   - 正则 `(?<![\w./-])ct(?![\w./-])`；
   - 跳过 fenced code、inline code、URL、HTML 注释；
   - 跳过 `docs/history`、`docs/reviews`、`docs/proposals`、`docs/decisions`、`docs/design`、`battle`、`issues`、`docs/spec`、`AGENTS` 生成块；
2. 提供 allowlist 只给 `ct-pkg`/`ct-ast`/`.ct`/`ct.lock` 等标识符（这些已因相邻 `-`/`.` 不被正则命中，通常无需额外项）；
3. 负例 fixture：`# ct — ...` 必须红；`` `ct build` ``、`ct-pkg`、`.ct` 必须绿；
4. 在 DOC-94 的 issue 上把“裸 `ct` 散文”补为验收项，或新开 `DOC-*`，避免 `verified` 被误读为“已全量”。

---

## 6. 其他观察

- `docs/README.md` 的“Ct 术语表”标题与 `guide`/`idioms` 已大量使用 `Ct`；说明规范本身可执行，问题集中在**政策条款**与**首屏文件**。
- `README.en.md` 未扫描：AGENTS 0.4 规定 AI 代理不主动读取英文镜像。若英文版也要统一，请人工核对 `Ct`/`ct`/`CT`；本报告不声称它已合规。
- 历史 784 处 `CT` 不建议重写：DOC-94 明确豁免；重写会改动 battle 证据、issue 结论与旧评审原文，违反“历史证据原样保留”。
- 本报告只写 `docs/reviews/` 与 `docs/README` 索引；没有改 README、AGENTS、源码或测试。

---

## 7. 建议的落地顺序

1. **先裁政策**：改 AGENTS §1 与 glossary 第 7 行，明确“语言名 `Ct` / 命令 `ct` / 后缀 `.ct`”；这是所有替换的前提。
2. **一次文档提交**：按 §2 表替换 20 处语言名；按 §4 表给 8 处命令加代码标记；跑 `check-docs`。
3. **加门禁**：`check-docs` 增加裸 `ct` 规则 + 负例；DOC-94 补验收项。
4. **上游 CR**：主规范把 `CT 包...` 改为 `Ct 包...`；同步后 `g0`/`g9` 绿。
5. **不碰历史**：784 处 `CT` 保留；如用户坚持全仓统一，需另立“历史文档重写”决策，并接受证据可追溯性代价。

---

## 8. 复现

```console
$ git rev-parse --short HEAD          # 64e87d1e
$ python3 - <<'PY'
# 去 code/URL/注释后统计活跃散文；本报告 §1 的 261/28/0
# 见 §1.1；生成块/副本单列 §1.2
PY
$ python3 test/docs/check-docs.py
# ... 0 bare CT in 80 active file(s) ...
$ grep -n '^# ct' README.md
1:# ct — C with Traits 编译器
$ grep -n 'CT 包编码' AGENTS.md
46:| CT 包编码通用条款（仅 CT 项目）...
$ grep -n -E '\bCT\b' docs/spec/ai-coding-workflow.md | head
178:**CT 包另有专用规范。**
1347:... # CT 包编码通用条款 ...
1549:| 18 CT 包编码通用条款 ...
```
