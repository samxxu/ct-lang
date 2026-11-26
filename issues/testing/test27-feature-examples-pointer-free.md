# TEST-27 · 语言特性样例矩阵与 examples/docs 去指针化

| 项 | 值 |
| --- | --- |
| 模块 | testing / docs（样例、文档、评审） |
| 定性 | 覆盖缺口 + 技术债（样例与文档未跟上语言特性） |
| 严重度 | **P1**（新特性无样例、旧样例与文档仍以指针为主） |
| 锚点 | `2026-11-26`（v1.2 规划期） |
| 依据 | 所有者 2026-11-26 要求；[dogfooding](../../docs/planning/dogfooding.md)；[pointer-free-phase-plan](../../docs/planning/pointer-free-phase-plan.md) |
| 状态 | open |
| 负责人 | TEST / REVIEW（REQ 跟踪） |
| 处置证据 | 排入 [`v1-PH-2` S8c](../../docs/phases/v1-PH-2/card.md)；2026-11-26 已交首版矩阵 [feature-examples-matrix](../../docs/planning/feature-examples-matrix.md)（23 行）与逐文件判定 [pointer-free-exemptions](../../docs/planning/pointer-free-exemptions.md)。**2026-11-27 交接给 TEST/REVIEW**，施工范围与分片见 §8。 |

## 1 现象（2026-11-26 实测）

### 1.1 examples

- `examples/` 共 **225** 个 `.ct`、60 个目录；
- **59** 个含 `char *`，**83** 个含 `->`，**14** 个含 `malloc`；
- 新特性覆盖稀疏：

| 特性 | 含该特性的 example 数 |
| --- | --- |
| `String` | 2 |
| `Str` | 1 |
| `Vec<...>` | 10 |
| `Map<...>` | 7 |
| `enum`（ADT） | 7 |
| `match (` | **1** |
| 可选链 `?.` | **0** |
| `ref` / `out` | 2 / 20 |
| `Box<T>` / `new` | 4 / 2 |
| `defer` / `errdefer` | 3 / 2 |
| `?;` | 1 |
| `foreach (` | 7 |
| 自定义下标（§4.64 的 `get`/`set`） | **0** |

> 本表是首轮关键字粗测；可复现口径、逐行代表样例与判档见
> [feature-examples-matrix](../../docs/planning/feature-examples-matrix.md) §0–§1，口径不同时以后者为准
> （例：`ref`/`out`、`defer`、`new` 的行因匹配式不同而不同）。

### 1.2 文档

| 文档 | `char *` | `->` |
| --- | --- | --- |
| `README.md` | 11 | 21 |
| `docs/tutorial.md` | 64 | — |
| `docs/guide-for-c-programmers.md` | 12 | — |
| `docs/idioms.md` | 5 | — |
| `docs/snippets/**.ct` | 1/3 文件 | — |

README 的快速开始与实际用法示例仍以 `char *` / `->` 为主，与“日常代码指针退场”的方向不一致。

## 2 目标

1. **每个语言特性至少一个样例**：样例 + 测试夹具 + 文档片段三件套；
2. **旧样例更新到最新写法**：非 C 互操作用例不再以 `char *` / `->` / `malloc` 为主；
3. **文档同步**：README / tutorial / guide / idioms / snippets 用新写法；
4. **评审可查**：矩阵列出“特性 → example → test → doc snippet → 状态”，缺一即红。

## 3 交付

| 轨道 | 交付 | 判据 |
| --- | --- | --- |
| A 矩阵 | `docs/planning/feature-examples-matrix.md`：每个特性一行，列 example / test / doc / 状态 | 无 `missing`；新特性（S2–S6）全部有 ≥1 样例 |
| B examples | 补齐缺失样例；把可迁移的指针样例改为 `String` / `Str` / `Vec` / `Map` / `Box` / 切片 / `ref`·`out` | 非 C 互操作用例 `char *` / `->` / `malloc` 清零（例外清单须写明理由） |
| C docs | README / tutorial / guide / idioms / snippets 改写；C 互操作章节显式标注“这里必须指针” | 活跃文档指针用法只剩 C 互操作段；snippets 全部可编译 |
| D 门禁 | examples 全量构建；矩阵一致性断言（可先 `warn`，S8c 收口转硬） | `check-ast` 绿；`check-docs` 绿 |

**保留的 C 互操作例外**（不要求去指针）：`examples/55_c_boundary_shim`、`examples/c-superset`、
`examples/54_freestanding_alloc`、`.m.ct` / `.shim.*` / `#ct-raw` 相关夹具。**2026-11-27 已逐文件判定**：
101 个有真实指针用法的文件分类与理由见
[pointer-free-exemptions](../../docs/planning/pointer-free-exemptions.md)（E1 41 / E2 11 / E3 26 / E4 15 / 可迁 8）。

## 4 特性清单（矩阵行）

`trait` / `impl`、泛型函数、泛型 struct、有界泛型、泛型 trait、ADT + `match`、模式扩展（S4–S6：字面量/嵌套/结构体/or/守卫/泛型 ADT）、`String` / `Str`、切片 `T[]`、`ref` / `out`、`Box<T>` / `new`、可选链 `?.`、`Map` / `map` 构造、`map binding`、`foreach`、`defer` / `errdefer`、`?`、自定义下标 `[]`（S2）、函子 `(A,B) => R`（S3）。

## 5 顺序与依赖

- 可在 **S2–S6** 期间按特性逐个补样例（新特性落地即补）；
- **S8c 收口**：矩阵清零、examples 去指针、docs 同步、门禁转硬；
- 与 S8b 狗粮化互不依赖；S8b 改编译器源码，S8c 改 examples/docs，文件集不重叠，可并行。

## 6 非目标

- 不删除指针支持，不改语言语义；
- 不为“去指针”而扭曲示例语义（例如硬件寄存器、C 回调仍用指针）；
- 不改 `c-superset` 与 `.m.ct` / shim 的 C 互操作本质；
- 不要求生成 C 变短。

## 7 关联

- [`v1-PH-2` S8c](../../docs/phases/v1-PH-2/card.md)
- [dogfooding](../../docs/planning/dogfooding.md)（源码压缩，S8b）
- [pointer-free-v2](../../docs/proposals/pointer-free-v2.md)（指针退场方向）
- [DOC-94](../docs/doc-94-ct-spelling.md) / [DOC-98](../docs/doc-98-ct-language-name.md)（文档口径先例）

## 8 交接单（2026-11-27，REQ → TEST/REVIEW）

REQ 已把样例与文档面的剩余工作交给 **TEST/REVIEW**。以下是可直接施工的范围、分片与验收；
`selfhost/**` 不在其内（仍归 A 轨道单写者）。

### 8.1 职责边界

| 可改 | 不可改 |
| --- | --- |
| `examples/**`、`docs/tutorial.md`、`docs/guide-for-c-programmers.md`、`docs/idioms.md`、`docs/snippets/**`、`README.md` 的样例段 | `selfhost/**`、`bootstrap/**`、`spec`（spec 改动由 REQ/DEV 同批）、`docs/decisions/**` |

文件集与 `docs/planning/**`、`issues/**` 不重叠；一次只做一片，一片一提交。

### 8.2 分片

| 片 | 范围 | 验收 |
| --- | --- | --- |
| **H1 tutorial 片段改写** | `docs/tutorial.md` §15（ref/out）、§17（Box/new）、§18（match）、§22（String/Str）、§23（切片）里的可执行片段：能跑的改成 `// source:` + `docs/snippets/README/` 片段；不能跑的把指针写法改为值类型写法 | `check-docs` 绿（片段字节一致、锚点可解析）；`char *` 只剩 C 互操作段 |
| **H2 C 程序员指南** | `docs/guide-for-c-programmers.md`：加一节「同样的东西用 Ct 写」；原有的 `char *` 段保留但标注“等价写法见下” | 目标文档 `grep 'char \*'` 只出现在 C 互操作对照表 |
| **H3 idioms** | `docs/idioms.md`：每条 idiom 给 `String` / `Str` / `Vec` / `Box` 版本；指针版标为「C 互操作」 | `check-docs` 的 briefing 断言仍绿（§N 引用有效） |
| **H4 片段补齐** | 按 [feature-examples-matrix](../../docs/planning/feature-examples-matrix.md) 的「有」档逐行补 `docs/snippets/README/` 片段（现有 7 个，目标每行至少 1 个） | 片段可编译、`.expected.out` 是实测输出、README 引用一致 |

### 8.3 每片流程

1. 先写预期（片段/文档的改动），跑 `python3 test/docs/check-docs.py` 看到失败；
2. 改文档/片段，直到 `check-docs` 绿；
3. 改了 `examples/**`：**同一提交**重生成语料 pin
   ```sh
   python3 tools/p85_inventory.py --root . corpus-manifest --ct <ct-ast 二进制> > test/probes/p85_corpus_sha.tsv
   ```
4. 本地门禁：`bash selfhost/check-warnings.sh`、`bash test/ast/p85_m0.sh <ct>`、`bash test/ast/p88_emit.sh <ct>`；
5. 提交正文写前后计数（如 `grep -c 'char \*' docs/tutorial.md: 64 → N`）。

### 8.4 指针政策（不要重新判定）

逐文件判定已经完成，见 [pointer-free-exemptions](../../docs/planning/pointer-free-exemptions.md)：

- E1（C 互操作 41）/ E2（生命周期演示 11）/ E4（结构体指针 15）：**保留**，只补「为什么必须指针」的说明；
- E3（打印受阻 26）：**等 [REQ-PRINT-1](../../docs/planning/requirements-pool.md) / [LANG-30](../lang/lang-30-str-print-api.md) 落地**再改，不要用 `cstr()` + `free` 假装去指针；
- 需要新判定的文件先在本 issue 里追加一行，不要直接改清单。

### 8.5 报告

每片收口在本 issue 追加一行：`H<n> | 提交 | 文件数 | 前后 char*/->/malloc 计数 | 门禁结果`。
全部完成后把本 issue 转 `open` → 待 S8c 收口时由 REQ 复核再转 `verified`。

| 片 | 提交 | 文件数 | 前后 `char *` / `->` / `malloc` | 门禁结果 |
| --- | --- | --- | --- | --- |
| H2（部分） | `4ac331bd` | 1（guide） | `char *` 12→16，`->` 1→4（新增均为 C 互操作对照）；Ct 段 0 | `check-docs` 仅剩 `docs/decisions/D-013.md` 既有死链（他人改动，未触碰）；H2 的“只出现在 C 互操作表”未收口 |
| H4（部分） | `cd798dd7` | 3（README + snippet + expected） | 新增 `match`/ADT 片段；README 0.5.1；其余矩阵行未补 | `check-docs` 仅剩 D-013 既有死链；H4 未收口 |
| H4（追加） | `fb355cf3` | 3（README + snippet + expected） | 新增 0.10 特性联展：泛型 struct/trait、函子、切片、ref/out、Box、Map；`match` 见 0.9 | `check-docs` 仅 D-013；E3 26 文件仍卡 LANG-30，S4–S6 样例卡 S5 |
| H1（部分） | `aaf519fd` | 1（tutorial） | §15/§17/§22/§23 增加 examples 完整链接；§18 暂时不动（S5 在改 ADT 模式 B）；source/snippets 全量未做 | `check-docs` 仅 D-013；H1 未收口 |
| H3（部分/标注） | `9c6f0d9c` | 1（idioms） | 新增 §11.1 C 互操作边界；原有 value 正文未逐条重写 | `check-docs` 仅 D-013；H3 标注完成、逐条版本仍可补 |
