# DOC-86 · README v0.88 大改 + §0.1 重测 + tutorial 联动

| 项 | 值 |
| --- | --- |
| 模块 | docs（门面） |
| 定性 | 文档重写（D1/D2/D3） |
| 严重度 | Medium（v1.0 前建议） |
| 锚点 | v0.88.0（2026-11-21） |
| 依据 | [外部评审与惯用卡评估](../../docs/reviews/2026-11-21-v088-external-review-eval.md) §1 |
| 状态 | deferred |
| 处置证据 | **延后（2026-11-22，REV）**：D1 / §0.5 / D3 最小范围已落并复核；D2 仍阻塞于 SH-110（`open`），D3-5 的 runner/TSV 未入库 |
| blocked-by | ① SH-110 合入后 48 小时内重测 §0.1；② DEV 交付 `test/docs/check-tutorial-cases.sh` + `tutorial-cases.tsv`；负责人 DEV/REV |

## 进展（2026-11-21）

- **D1 能力清单**：README 第 3 节新增 `ref`/`out`、`T[]` 切片、`String`/`Str`、ADT/`match`
  四条，均带 spec 节号；`box`/`new` 原条目保留。英文 README 同步补四条。
- **§0 示例**：新增 §0.5「句柄速览」，三个完整程序 + 实测输出：
  `String`/`Str` → `hello, ct`（v0.84.1 实测）；`box`/`new` → `7`（v0.87 实测，v0.88 同）；
  ADT/`match` → `12 12 0`（v0.84.1 实测）。三个程序都不依赖 shim，也不写 `#include`
  （内建层自动声明 `printf`/`malloc`），可直接在任意目录 `ct build`。
- **D2**：§0.1 的基线仍是 0.44.1；待 SH-110（动态派发一行链）合入后用 v1.0 重测断点表，
  修复前对链式派发的结论保持“当前被拒”。
- **D3（最小范围，2026-11-21）**：tutorial 顶部新增「按层阅读」路标（值 → 借用 → 句柄 → ADT），
  链到 §8 / §15 / §17 / §18；`String`/`Str` 与切片暂无 tutorial 专章，路标暂指 spec §4.69 / §4.70
  与 guide §3，补章见 [DOC-90](doc-90-tutorial-string-slice-chapters.md)。§0 的 0.44.1 表述改为 v0.88.0 断点：单元矩阵仍挡第 2 段；
  「接口值落变量后逐跳」已可跑（SH-72/74）；一行链仍被拒（SH-110，修复中）。静态宿主
  `examples/47` 实跑 `200 {"users":3}`、rc=0。**不做全篇逐字核**；稳定章节以 `examples/**` /
  `test/**` 的实跑命令为锚。
- **D3-5 tutorial-cases 夹具（新增；DEV）**：
  - 清单 `test/docs/tutorial-cases.tsv`：列 `case_id` / 教程节 / 源文件 / 命令 / 期望 stdout；
  - runner `test/docs/check-tutorial-cases.sh <ct-ast>`：逐条执行、stdout 字节比对；缺文件 /
    缺命令 / 无输出 / 输出不符任一失败，不允许静默跳过；
  - 首批 10 条：hello、多文件、`ref/out`、`box/new`、ADT/`match`、`String/Str`、切片、
    HTTP 静态宿主（期望 `200 {"users":3}`），加 tutorial §22 `String/Str`
    （`test/docs/tutorial_cases/string_str.ct`，期望 `hello, ct`）与 §23 切片
    （`test/docs/tutorial_cases/slice_sum.ct`，期望 `14 5`）；
  - 初始作为 `check-ast` 的附加段或独立脚本，不新增硬门禁条数；全绿后再评估并入门禁。
- **LANG-24 联动**：§0.5 的 `box<T>` 拼写在 LANG-24 Stage A 落地时改 `Box<T>`，其余不动。

## 现象

- **D1**：README 能力清单缺 `String`/`Str`、切片、`ref`/`out`、`box`/`new`、ADT/`match`；
  §0 示例仍以 `char *` 旧风格为主；
- **D2**：§0.1 HTTP 目标链的断点表基线停在 0.44.1；期间 `$name`、String/Str、box、ADT 已落地，
  断点状态需重测；
- **D3**：tutorial 91KB 未逐字核；README 大改时叙事顺序（值→借用→句柄→ADT）需联动。

> 注：README 首行“`ct check` 只做受限语义检查”**不是事实错误**；`--types` 是可选子集。
> 可在该句后补“`--types` opt-in”，但不要改成“全量类型检查”。

## 期望

1. README 能力清单对齐 v0.88（五项新特性各一行，指向 spec 节号）；
2. §0 示例至少一个用 `String`/`Str`，一个用 `box`/`new`，一个用 ADT/`match`；
3. §0.1 断点表用 v0.88.0 重测；SH-73 已裁定为 bug（[SH-110](../selfhost/sh110-dynamic-dispatch-chain-fix.md)）：
   修复前写“动态派发链式当前被拒”，修复合入后改为“一行链可用”；静态宿主形态始终可跑；
4. tutorial 的叙事顺序与 README 同步；不重抄 spec；
5. 与 [DOC-85](doc-85-idiom-priority-card.md) 同批：README 的“先读”路径加 `idioms.md`。

## 验收

- README 中五项新特性各有可定位段落/示例；
- §0.1 每条断点有 v0.88.0 的命令/退出码；
- tutorial 的旧版本串清除；路标与 README 的分层顺序一致；
- tutorial-cases 清单与 runner 可执行，首批 8 条全绿；
- `check-docs` 绿；不引入未实现能力。

## 非目标

- 不在 SH-73 裁定前改“动态派发链式是否支持”的结论；
- 不重写整个 tutorial；只做与 README 冲突/过时的段落。

## 关联

- [评估](../../docs/reviews/2026-11-21-v088-external-review-eval.md)
- [SH-73](../selfhost/sh73-temp-receiver-dynamic-dispatch.md)
- [DOC-85](doc-85-idiom-priority-card.md)
- [v1-readiness-1](../../battle/v1-readiness-1/verdict.md)（非 Tier 1 门禁）

## 复核与延后（2026-11-22，REV）

**结论：`deferred`。D1、§0.5、D3 最小范围已满足；D2 与 D3-5 runner 两项未达验收，不能置
`verified`。**

### 已满足

| 项 | 证据 |
| --- | --- |
| D1 能力清单 | README §3 五行新特性（`cap:params-slices` / `cap:strings` / `cap:box` / `cap:adt`），均带 spec 节号 |
| §0.5 三个可跑程序 | README §0.5 `String`/`Str`、`box`/`new`、ADT/`match`；教程联动 §22/§23 |
| D3 最小范围 | tutorial 顶部「按层阅读」与 §16 已指向 §22/§23；tutorial §22/§23 已入库 |

### 未满足（阻塞项）

```console
$ grep -n '状态' issues/selfhost/sh110-dynamic-dispatch-chain-fix.md | head -3
10:| 状态 | open |

$ sed -n '32,34p;40p' README.md
本页只复述定义；两档路径的判断依据、0.44.1 的逐段边界与报错原文也都在那里。**0.44.1 是历史
基线（最近一次完整实测），页首是当前版本**；在该基线上完整三段还不能原样写出来：第 2 段被单元
矩阵挡住（语言限制），第 3 段被「方法结果不能作接收者」与「返回局部接口值悬垂」挡住（实现限制；
| 0.1 HTTP 请求 | 完整路径（目标形态；历史基线 0.44.1 阻塞，最近可跑为静态宿主） | `char *` factory + 对象方法链 | 构造藏在工厂里，调用点只写一条链 |

$ ls test/docs/
check-docs.py
tutorial_cases

$ ls test/docs/tutorial-cases.tsv
ls: test/docs/tutorial-cases.tsv: No such file or directory

$ ls test/docs/tutorial_cases/
slice_sum.ct
string_str.ct
```

- **D2**：§0.1 断点表仍以 0.44.1 为基线；SH-110 仍是 `open`，按本条非目标不得在裁定前
  改“动态派发链式”的结论。触发：SH-110 合入后 48 小时内用 v1.0 重测 §0.1。
- **D3-5**：`check-tutorial-cases.sh` 与 `tutorial-cases.tsv` 均不存在，首批 10 条无法执行；
  目前只有 2 个 `.ct` fixture。该项需 DEV 写 `test/docs/**`，不在本批 DOC 的可改路径内
  （只动 `issues/docs/**` 与 `docs/**`）。

**触发/负责人**：① DEV 修 SH-110（或裁定不修，改为在 §0.1 写“经裁定不支持”）后，REV 重测
§0.1 并关闭 D2；② DEV 交付 runner + 10 条 TSV 且全绿后，本条转 `verified`。两项可并行。

## 落地（2026-11-23，DOC/DEV）

**状态未改（`deferred`）。D2 的 SH-110 依赖仍在，未宣称一行链已支持。**

- README 从 628 行重写为 281 行（≤300）：保留 §0.1–§0.5 可运行展示、§1 快速开始、§2 命令、
  §3 能力（20 个 `cap:` 标记不变）、§4–§7；删除内嵌的 shim 全文，改为指向
  `examples/47` / `examples/48` 与 spec §4.10.1。
- §0.1 用 v0.88.3 重测断点：接口值落变量后逐跳可跑（`1`，rc=0）；同一形状的一行链仍报
  `error: method receiver must be a variable, an element, a call or a field chain`（rc=1，
  [SH-110](../selfhost/sh110-dynamic-dispatch-chain-fix.md) deferred）；返回局部接口值
  `0 201`（rc=0）；静态宿主 `200 {"users":3}`（rc=0）。
- §0.5 五项新特性各有可定位样例：ref/out、切片、`String`/`Str`、box/new、ADT/match；
  前四项指到 `examples/50…53`，`String` 段实跑 `hello, ct`。
- tutorial 联动：顶部「按层阅读」与 §0.5 顺序一致；HTTP 走读的基线从 v0.88.0 改为 v0.88.3，
  保留“一行链仍被拒、SH-110 修复中”的诚实表述；`docs/README.md` 的 §4.10.1 索引同步。

**待唤醒（SH-110 合入后 48 小时内）**：

1. 用新版本重测 §0.1，把“当前不支持 / deferred，待修复”改为“一行链可用”，并同步
   `docs/language-spec.md` §4.10.1 与 tutorial HTTP 走读；
2. `test/docs/check-tutorial-cases.sh` + `test/docs/tutorial-cases.tsv` 仍未入库，D3-5 仍欠；
3. 本条转 `verified` 前需 REV 复核 README 的 §0.5 五条实跑与 §0.1 四条断点。
