# DOC-89 · `check-docs` 通用锚点校验（所有 Markdown 链接的 `#fragment`）

| 项 | 值 |
| --- | --- |
| 模块 | docs（门禁） |
| 定性 | 门禁增强（不新增硬门禁条数） |
| 严重度 | Medium |
| 锚点 | v0.88.0（2026-11-21） |
| 依据 | [DOC-88](doc-88-spec-split-decision.md) 精修 3；[check-docs.py](../../test/docs/check-docs.py) |
| 状态 | verified |
| 处置证据 | **待办（v1.1 立项；落地可到 v1.2）** |

## 现象

`check-docs` 的链接检查只解析路径：

```python
dest = target.split("#", 1)[0]
if os.path.exists(resolved): continue
```

`#fragment` 被整段丢弃。因此锚点错位、标题改名、行号漂移都不会报红。仅
`language-spec.md` 就有 261 处带锚点引用（240 处行号锚点），全仓的静默链接腐烂没有任何护栏。
DOC-88 只在 `language-spec.md` 上冻结行号锚点，不足以覆盖通用情况。

## 目标

在**不新增硬门禁条数**的前提下，把锚点校验收进 `check-docs`：

1. 对相对链接的 `#fragment` 解引用；
2. 节锚点按目标文件的标题集合校验；
3. 行号锚点做范围校验（`#L10` / `#L10-L20`：行数在文件范围内）；
4. 失败信息给出目标文件、原锚点、最接近的候选 slug，便于修复。

## 锚点解析规则

| 形态 | 判据 |
| --- | --- |
| `file.md#heading-slug` | 按标题生成 slug 集合；命中即过 |
| `file.md#中文-slug` | 中文保留；空格转 `-`；去掉标点与反引号；小写 |
| 重复标题 | 依序加 `-1`、`-2`（与 GitHub 一致；同一文件内确定性） |
| `%E4%B8%AD` 等百分号编码 | 先 URL 解码再比对 |
| `file.md#L10` / `#L10-L20` | `1 <= a <= b <= 行数`；不比对内容 |
| `#fragment`（同文件） | 用当前文件的标题集合校验 |
| 外链 `http(s)://…` | 不检查（CI 无网；另议） |

## 分阶段

| 阶段 | 内容 | 门禁行为 |
| --- | --- | --- |
| S1 盘点 | 扫 README + `docs/**/*.md`（`docs/history/**` 豁免）的锚点，输出“文件 / 锚点 / 候选”清单 | **只 warn**，不阻断 |
| S2 节锚点阻断 | 修完 S1 的节锚点后，节锚点错误即红；行号锚点仍 warn | 阻断 |
| S3 行号锚点阻断 | 行号越界即红；与 DOC-88 的 `language-spec.md` 冻结口径合并 | 阻断 |
| S4 扩面 | 把 issues / battle / test 的 Markdown 纳入同一套规则 | 阻断 |

S1 的清单必须作为一次性证据入库（`docs/reviews/…` 或 issue 附件），不允许“扫完就丢”。

## 验收

- 范围内节锚点零失败；中文 / 全角标点 / 重复标题的夹具全部通过；
- 行号锚点全部在文件行数范围内；
- `docs/history/**` 豁免，历史快照不因本卡变红；
- `check-all` 仍是 11 道硬门禁（本卡增强第 11 道的断言，不新增 `run_gate`）；
- 失败信息含候选 slug，修复者无需手算。

## 风险

| 风险 | 缓解 |
| --- | --- |
| slug 算法与 GitHub / VS Code 渲染器不一致 | 固定一套实现 + 夹具覆盖中文、标点、重复标题；不确定的锚点列候选而非直接判死 |
| 已有大量坏锚点，S2 一开就红 | S1 先盘点；修复按「B0 门面 → B1 issues → B2 battle → B3 test」分批，与 DOC-88 同序 |
| 行号锚点天然易漂移 | 通用规则只查范围，不查内容；`language-spec.md` 的“新增行号锚点拒收”仍由 DOC-88 管 |
| 扩面到 issues/battle 后噪音大 | S4 单独提交、单独回滚 |

## 非目标

- 不检查外链可达性；
- 不重写被链接文档的内容；
- 不把 `docs/history/**` 的历史快照改写成新锚点；
- 不新增硬门禁条数（并入第 11 道 `check-docs`）。

## 关联

- [DOC-88](doc-88-spec-split-decision.md)（`language-spec.md` 行号锚点冻结与白名单分批）
- [check-docs.py](../../test/docs/check-docs.py)

## 落地（2026-11-23，DEV）

**状态未改（`deferred`），待 REV/REQ 复核后转 `open` → `verified`。**

- [check-docs.py](../../test/docs/check-docs.py) 新增通用 `#fragment` 校验：范围是仓库全部 Markdown
  （`docs/history/**` 冻结快照豁免）；节锚点按 GitHub slug（中文保留、标点去掉、行内代码参与、
  重复标题依次 `-1`），行号锚点 `#L10` / `#L10-L20` 只校验 `1 <= a <= b <= 行数`；
  失败信息给出目标文件、原锚点与最接近的候选 slug。
- 负例/正例进 `--selftest`：不存在的节锚点、越界行号必须红；中文 / 全角标点 / 重复标题 /
  百分号编码 / 同文件锚点必须通过。
- 既有死锚点：修 4 处（`README.en.md` 的 tutorial CLI 锚点、`docs/tutorial.md` 的 package-guide
  §9→§8、`docs/planning/ct-pkg-index-alignment.md` 的契约 §4.1 锚点、DOC-71 的 §4.47 锚点）；
  历史记录里按当时行号写的 42 处逐条登记为 `FRAGMENT_EXEMPT` 的精确 `(source, target)` 对，
  不按目录或规则整体关闭。
- 验证：`python3 test/docs/check-docs.py` → OK（2755 relative links / 411 files、1672 fragments /
  684 Markdown files）；`--selftest` → OK（fragment 11 cases + CT 14 cases）。

## 复核（REV，2026-11-23）

`check-docs` 通用 `#fragment` 校验：1672 个 fragment / 692 文件；42 处历史行号锚点精确豁免；
死锚点/越界锚点必红；`--selftest` 11 例绿。
