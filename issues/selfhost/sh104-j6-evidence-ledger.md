# SH-104 · J-6 全量证据台账缺失（P-1…P-6）

| 项 | 值 |
| --- | --- |
| 模块 | selfhost（J-6 证据） |
| 定性 | 证据缺口（v1.0 闸门） |
| 严重度 | High |
| 锚点 | v0.83.3（2026-11-21） |
| 文件 | [v1-release-plan §1.5](../../docs/planning/v1-release-plan.md#L57-L71)、[D-011](../../docs/decisions/D-011.md) |
| 状态 | deferred |
| 处置证据 | **deferred**（2026-11-22，REV/REQ：台账已建（34 行，15 已过 / 9 部分 / 5 缺失 / 5 阻塞），`check_j6_ledger` 已入 `check-docs`；剩余项未清零。触发 `v1-PH-0` 入口（V1-C1）；负责人 REQ/DEV；High） |
| 层级 | **Tier 1（`v1-PH-0` 入口）**，见 [battle/v1-readiness-1](../../battle/v1-readiness-1/verdict.md) |

## 进展（2026-11-21）

台账已落 [docs/planning/j6-evidence/ledger.md](../../docs/planning/j6-evidence/ledger.md)：

- 34 行 = P-1.1…P-1.4 / P-2.1…P-2.5 / P-3.1…P-3.8 / P-4.1…P-4.6 /
  P-5.1…P-5.7 / P-6.1…P-6.4（含附录 §C.5 的追加项）；P-7.x 原型与 P-8.1 不进闸门。
- **P-1.1 已过**：`examples test lib/std` 实测 1363 个 `.ct` / 31,183 行；字面量 2,275、
  `char *` 627、`T a[] =` 36、`T a[]` 后缀 37、`ref/out` 16、`new` 54（HEAD `10c7e439`，
  命令在台账内）。附录 A 的 649/494/36/2 是旧基线，**已标注作废**。
- **J-4a 判据与实测偏离**：D-011 原文写「容器 / Option / Result / 全局硬错」，
  v0.88 实测 `Vec<Str>`、`Option<Str>`、ADT 负载、全局字面量 `Str` 可编译（存视图）；
  字段 / `Map` 键仍硬错。台账按实测记，风险由 [LANG-22](../lang/lang-22-nonimmortal-view-store-lint.md) 承接。
- **P-2.1 口径**：按 D-016 记上下文关键字；附录 A 的「完全关键字」表述作废。
- **机判断言**：`check-docs` 新增 `check_j6_ledger`——34 个 ID 必须齐、状态只能四态、
  最小可判证据非空、`阻塞` 必须写依据；已做负例自测（改一个状态即红）。
- 仍缺：P-1.2 逐文件 CSV、P-1.3 lint dry-run（阻塞）、P-4.3 `Str` 逃逸 lint、
  P-5.2/P-5.3/P-5.5 `ref/out` 所有权夹具、P-6 跨仓迁移（阻塞于 std 发版）。

## 现象

J-6 全量证据仍未收口：P-1…P-6 的正式证据包（语料/语法/ABI/逃逸/所有权/跨仓）未齐，
roadmap 自标“J-6 未过”；J-3/J-4/J-5 也缺逐张核对。

## 期望

1. 建一份证据台账（表：判据 ID / 证据位置 / 状态 / 未决项 / 负责人）；
2. P-7.1a/P-7.1b/P-7.2/P-7.3 已落库的证据挂到台账；
3. 明确 P-1…P-6 各自的“最小可判证据”与产出物；
4. 台账进 check-docs 或 check-ast 的可机判断言，避免“写了但没跑”；
5. 清零“已实施未验证”。

## 验收

- 台账零未决，或每个未决都有 blocking 依据；
- v1.0 的 J-6 闸门可据此判定，不靠口头结论。

## 关联

- [2026-11-21 评估](../../docs/reviews/2026-11-21-v1-campaign-eval.md)、[v1 路线](../../docs/planning/v1-release-plan.md)

## 处置（REV/REQ，2026-11-22）

**结论：`deferred`，不是 `verified`。** 台账与机判断言已落地，但 J-6 本身仍未过；本条是 v1.0
硬闸门（V1-C1），触发点是 `v1-PH-0` 入口。

**已落地（HEAD `38cd4ae4`）**：

- [docs/planning/j6-evidence/ledger.md](../../docs/planning/j6-evidence/ledger.md) 34 行
  （P-1.1…P-6.4，含 §C.5 追加项），状态枚举四态、最小可判证据非空、`阻塞` 必须写依据；
- `test/docs/check-docs.py:514` 的 `check_j6_ledger` 对 34 个 ID 做机校，并在 `:678` 接入；
- 平台结论仍为 **15 已过 / 9 部分 / 5 缺失 / 5 阻塞**（台账头部原文）。

**仍未清零（承接项）**：

| 缺口 | 现状 | 承接 |
| --- | --- | --- |
| P-1.2 逐文件 CSV | 只有全局计数 | 台账 §P-1.2 |
| P-1.3 lint dry-run | 迁移 lint 未实现，无法 dry-run | 阻塞于 lint |
| P-4.3 `Str` 逃逸 lint | 未实现 | [SH-106](sh106-str-view-escape-no-lint.md)（已修）后复审 |
| P-5.2/P-5.3/P-5.5 `ref/out` 所有权夹具 | 缺 | 台账 §P-5 |
| P-6 跨仓迁移 | 阻塞于 std 发版（PKG-22） | 包侧 |

**触发/负责人/优先级**：`v1-PH-0` 入口（V1-C1），负责人 REQ（台账）/DEV（夹具与 lint）；
High。本批不改台账内容，只把状态从笼统 `open` 收敛到 `deferred`，避免与「零未决」的完成态混淆。

## 证据补齐（2026-11-23，DEV；状态字段未改）

本轮按台账逐行补证据/引用，能实跑的都贴了命令或产物；**未闭合项全部写明承接 owner，
不把未完成写成 `已过`**。台账当前 **21 已过 / 5 部分 / 3 缺失 / 5 阻塞**（34 行）。

**本轮闭合（5 行）**：

| 判据 | 证据 |
| --- | --- |
| P-1.2 逐文件 CSV | [p1_2.csv](../../docs/planning/j6-evidence/p1_2.csv)（1381 行 + 表头，6 列）；生成器 [gen_p1_2.py](../../docs/planning/j6-evidence/gen_p1_2.py)，命令：`python3 docs/planning/j6-evidence/gen_p1_2.py > docs/planning/j6-evidence/p1_2.csv` |
| P-3.7 U16 工厂 | `test/ast/p80_methods/prog.ct` + `prog.expected.out` 第 38–41 行（`from_utf8` / `from_utf16` / `String.from_utf16` / `to_utf8` / `to_utf16`） |
| P-3.8 U16 方法集 | `p80_methods` 期望输出第 16–21 行（越界 / 负下标 / `get(99)` 空视图）；`neg_u16_write.ct` 写硬错 |
| P-4.3 `Str` 逃逸 lint | `test/ast/p106_str_escape.sh`（SH-106 verified），接入 `selfhost/check-ast.sh:1354` |
| P-4.5 透传路径 | [docs/guide-for-c-programmers.md §7.1](../../docs/guide-for-c-programmers.md) 逐类矩阵 |
| P-5.7 下标只读 | `p80_methods/prog.ct:34` 只读正例；`neg_write_index.ct`、`neg_u16_write.ct` 硬错 |

**仍未闭合（承接已写进台账）**：

| 判据 | 现状 | 承接 |
| --- | --- | --- |
| P-2.5 干净归档全量复跑 | 本轮复跑至 PH-79 段（418 条输出、0 失败）后因耗时中止 | DEV 在 CI/长任务跑完并贴 summary |
| P-3.5 C 边界隐式转换 | 新发现：`char *p = s`、`return s`（`String`/`Str`）被接受并发射坏 C | DEV 补赋值/返回/变参负例（可能另立案） |
| P-5.2 / P-5.3 / P-5.5 | out/ref owning 旧值释放、赋值 vs release、借用类型 out/ref 无夹具 | DEV |
| P-5.4 / P-5.6 | out 错误路径、ref/out 的 ASan 组合 | DEV |
| P-6.4 | std 发版后复核 README/spec/roadmap | REQ |
| P-1.3 / P-3.6 / P-6.1–P-6.3 | 依赖迁移 lint / std 发版，不可判 | DEV / 包侧 |
| J-4b | `ref/out` 逃逸契约条款未成文 | DEV/REQ |

**check-docs 断言加强**（`test/docs/check-docs.py`）：

- 台账头部 `<!-- j6:counts passed=… partial=… missing=… blocked=… -->` 必须与逐行计数一致；
- `已过` 必须带路径指针；`部分`/`缺失` 必须写 `承接`（owner + 下一步）；`阻塞` 必须写依据；
- 新增 6 条自测（合法、非法状态、缺行、阻塞无依据、部分无承接、计数不符），`--selftest` 全过。

```console
$ python3 test/docs/check-docs.py | tail -2
check-docs: OK (..., 34 J-6 row(s), ...)
design window: ok (12/12)
$ python3 test/docs/check-docs.py --selftest | tail -2
j6-ledger selftest: OK (6 cases)
```

状态仍为 `deferred`：J-6 未过，且本次任务要求不改状态；等 REV 复核后决定。
