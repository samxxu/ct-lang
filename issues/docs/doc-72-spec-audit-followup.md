# DOC-72 · spec/外围文档审计反馈的修复批次

| 项 | 值 |
| --- | --- |
| 模块 | docs（language-spec / architecture / tutorial / patterns / check-docs） |
| 定性 | 文档漂移与可读性修复；**不占 phase** |
| 严重度 | High（P0-1/P0-3/P0-4 会误导实现判断） |
| 优先级 | P1 |
| 状态 | **verified**（2026-11-20，REV；deferred 子项见复核段） |
| 来源 | 外部审计反馈（2026-11-18，基线 v0.63.2）；已按当前 v0.65.1 复核 |
| 落点 | 挂 `v0-PH-67` R5「文档漂移审查」；可独立提前做，不阻塞 ID 迁移 |

## 评估结论

审计方向正确，但不能照单全收：

- **采纳**：P0-1 版本标签、P0-3 L0/L2 插叙、P0-4 architecture 仍是 L0、P0-2 spec-cases（分阶段）、P1-1 单文件、P1-2 伪 EBNF、P1-3 目标/当前混排。
- **部分采纳/降级**：P0-5 tutorial（页首已改，正文仍有 `v0.16.0`）；P0-6 patterns（“没有编译期类型检查”已不准确，应改为“默认路径不做全量，`ct check --types` 有受限子集”）。
- **不成立**：P1-4 §4.67→§11 断层；§5–§10 实际存在，审计因传输截断误判。
- **转交**：P1-7 std 文档镜像属 ct-pkg，不在 CT 文档范围。

## 修复批次

### B1 版本/指针（docs-only，先做）

| # | 内容 | 验收 |
| --- | --- | --- |
| B1-1 | spec 页首版本改为 `CTC_VERSION`（或加门禁断言） | 页首版本 == `ct -v` |
| B1-2 | `architecture.md` 文首注明“本文是 L0；ct-ast 见 …”，并给入口 | 读者不再按 ctc.c 改 ct-ast |
| B1-3 | tutorial 正文 `v0.16.0` 清理；页首保持“以 `ct -v` 为准” | `grep v0.16.0 docs/tutorial.md` 零命中 |
| B1-4 | patterns §4 改“默认不做全量类型检查；`ct check --types` 有受限子集” | 不再与 spec §4.53 冲突 |

### B2 结构收敛（docs-only）

| # | 内容 | 验收 |
| --- | --- | --- |
| B2-1 | L0/L2 差异集中到 §1.1 表，正文默认 ct-ast；§10 等 L2-only 区允许 | `L0/L2` 提及集中在表+白名单 |
| B2-2 | 删/降级 §3 伪 EBNF，改构造清单 + §4 指针 | 无 `<...>` 占位产生式 |
| B2-3 | 目标形态/当前可跑归位：patterns 或 spec 只留一个权威段 | 两处不再互相指向 |

### B3 门禁/测试（非纯文档，独立提交）

| # | 内容 | 验收 |
| --- | --- | --- |
| B3-1 | `check-docs` 增“spec 页首 == `CTC_VERSION`” | 故意改 spec 版本 → 门禁红 |
| B3-2 | `test/spec-cases/` 先抽 15–20 个可独立运行的 c 块（不是 62 个一次） | 每个 case 编译/运行；spec 改描述→case 红（分阶段） |

### B4 结构拆分（后置）

- `language-spec/` 按域拆分；
- 先做旧路径 stub/重定向，再拆；
- 全量 `check-docs` 零 dead；
- 单文件 ≤30KB（目标，不硬卡）。

## 不做什么

- 不新开 phase；不 bump 版本；
- 不把 docs 修复混进代码 fix 提交；
- 不一次抽 62 个 spec 块；
- 不改 `battle/**`/历史 tag；
- 不处理 ct-pkg std 文档（转交）。

## 验收

- B1/B2 docs-only；B3 独立 tools/test 提交；
- `check-docs`、`tools/check.sh g0` 绿；
- 每条修复有命令/锚点；
- `v0-PH-67` R5 收口时逐项勾掉。

## 处置（2026-11-20，DEV #2）

范围：只改文档与本文处置；**不改 `status`**、不 bump 版本、不 push、不打 tag、不碰 `battle/**`、
`docs/reviews/**` 与代码。B3（门禁 / `spec-cases`）与 B4（拆文件）按 issue 原文属独立 tools/test 提交
或后置项，本次只登记 deferred，不混进文档提交。

### B1 版本 / 指针

| # | 结论 | 落点与说明 |
| --- | --- | --- |
| B1-1 | **fixed（改用不钉版本号的形态）；门禁断言 deferred** | [language-spec 页首](../../docs/language-spec.md)：改为「适用版本：ct-ast，以 `ct -v` 为准」，删掉页首 `v0.53.1` 与 §0 标题里的版本；§11 第 3 条同步改为不钉版本号。B1-1 的「页首版本 == `ct -v`」若靠钉版本号实现会在下次 bump 立刻漂移（DOC-63 的教训），因此采用 `check-docs` 已能守的形态；真正的相等断言属 B3-1 门禁改动，deferred |
| B1-2 | **fixed（已由 DOC-75 D-10 落地，本次复核）** | [architecture.md](../../docs/architecture.md)：标题「ctc 内部架构（L0 种子；主线 ct-ast 见 §0）」，§0 四代编译器表给出 L0/L1/L2/ct-ast 位置与入口 |
| B1-3 | **fixed** | [tutorial.md](../../docs/tutorial.md) 的 `v0.16.0` 全部清理：`ct -v` 示例改 `v<版本>`、`install.sh --version` 改 `<tag>`、SH-33 历史句改为「0.16.0」；`grep -n 'v0.16.0' docs/tutorial.md` 零命中 |
| B1-4 | **fixed** | [patterns.md §4](../../docs/patterns.md#4-边界不是缺口是取舍)：改为「默认路径不做全量类型检查；`ct check --types` 有受限子集」，并指向 §4.53 |

### B2 结构收敛

| # | 结论 | 落点与说明 |
| --- | --- | --- |
| B2-1 | **部分 fixed；剩余 deferred** | [language-spec §1.1](../../docs/language-spec.md#11-编译器代际与-l0l2-差异唯一集中处)：新增 L0/L2/ct-ast 代际表（解析方式、定义顺序、模块语法、接口装箱、`map`、`Drop`/`#line`、容量、用途），并声明正文默认 ct-ast、零散提及只作历史边界/诊断语境。**未完成**：正文仍有 31 处 `L0`、41 处 `L2` 字样，多为已发布契约的历史边界、容量与诊断说明；一次性删改会丢失精度，需逐处审阅，故 deferred（下一步：单独一轮 spec 结构收敛，不混入本次批） |
| B2-2 | **fixed** | [language-spec §3](../../docs/language-spec.md#3-语法总览)：删掉伪 EBNF（含 `<C 类型写法…>` 占位），改为「构造 / 形态 / §4 语义入口」表；并修正 `loop` 形态为 `loop(0..n)` / `loop(x)`。`grep -n '::=' docs/language-spec.md` 零命中 |
| B2-3 | **fixed** | 目标/当前混排两处落在 [patterns.md §4](../../docs/patterns.md#4-边界不是缺口是取舍)：删掉「没有泛型结构体 / trait」的错误陈述（Phase 26/29/35 已落地），与 §1 口径一致；类型检查按 B1-4 的「默认不做全量」表述，不再与 §4.53 冲突 |

### B3 / B4

| # | 结论 | 理由与下一步 |
| --- | --- | --- |
| B3-1 | **deferred** | 「`check-docs` 增 spec 页首 == `CTC_VERSION`」要改 `test/docs/check-docs.py` 并附「故意改版本 → 红」的负例，属 issue 明确要求的独立 tools/test 提交，不在本次纯文档提交内。下一步：单开一次门禁改动（脚本 + 负例 + 红证），届时可把 B1-1 改为版本相等断言 |
| B3-2 | **deferred** | `test/spec-cases/` 抽 15–20 个可独立运行的 `c` 块属测试资产，需运行器与逐 case 断言，且 issue 要求分阶段；本次不伪造覆盖 |
| B4 | **deferred** | `language-spec/` 按域拆分、旧路径 stub、全量 `check-docs` 零 dead 是大结构改动；当前门禁全绿、无单文件硬上限，按 issue「后置」执行 |

### 额外发现（本轮核对 DOC-73 的 std 入口时发现，一并修正）

| 项 | 结论 | 落点与证据 |
| --- | --- | --- |
| spec §1「`.m.ct` 不能被 import」 | **fixed（原文失实）** | [language-spec §1](../../docs/language-spec.md#1-源文件模型ct-ast)：实测 `.m.ct` 可被 `.h.ct` / `.ct` 单元 import（`map_unit_cross` 钉住；std 的 `std::io::Stdout` / `std::fs::Fs` / `std::utf8::Utf8Ops` 都是 `.m.ct`）；改为「`.m.ct` 可被 import；普通 `.ct` 不能被 import」 |

实测命令与原始输出：

```console
$ grep -n 'v0.16.0' docs/tutorial.md
$ echo $?
1
$ grep -n '::=' docs/language-spec.md
$ echo $?
1
$ sed -n '1,3p' docs/architecture.md
# ctc 内部架构（L0 种子；主线 ct-ast 见 §0）
$ grep -c 'L0' docs/language-spec.md
31
$ grep -c 'L2' docs/language-spec.md
41
$ .temp/p77/ct-ast build .temp/ioprobe/m.ct -I /tmp/std019 -o .temp/ioprobe/out   # import std::io::Stdout;
<stdout: cc ...>
$ echo $?
0
```

（`grep` 无输出且退出码 1 = 零命中。`.temp/ioprobe` 的 `m.ct` 分别 `import std::io::Stdout` /
`std::fs::Fs` / `std::utf8::Utf8Ops`，三次构建均 `rc=0`。）

验证（原始输出）：

```console
$ python3 test/docs/check-docs.py
spec pin: skipped (master spec draft 1.17.0)
check-docs: OK (1990 relative links in 329 files, v0.77.1, 11 hard gates, 12 phase status, 5 适用版本 header(s))
design window: ok (12/12)
$ echo $?
0
$ bash tools/check.sh g0
ok  ./docs/spec/ai-coding-workflow.md（全文副本 sha256=c22c85ee08f26cd1e98087a42e2156a59b63c6ba2179a450ea8e92b3bc69a3f9）
ok  AGENTS.md（version=1.17.0）
g0: OK (block 1.17.0, session-map present)
$ echo $?
0
```

## 复核（2026-11-20，REV）

**结论：verified**（B1/B2 已完成项属实；B3/B4 等 deferred 子项见下，不据此打回）。

```console
$ sed -n '5,7p' docs/language-spec.md
> **适用版本**：安装入口 **ct-ast**（`selfhost/ct-ast/main.ct`），不在此固定版本号——实际版本以
> `ct -v` 为准。最近一次全文复核是 v0.53.1（2026-11-15），此后正文按 phase 增量修订，
$ grep -n 'v0.16.0' docs/tutorial.md; echo $?
1
$ grep -n '::=' docs/language-spec.md; echo $?
1
$ grep -c 'L0' docs/language-spec.md; grep -c 'L2' docs/language-spec.md
31
41
$ sed -n '1p' docs/architecture.md
# ctc 内部架构（L0 种子；主线 ct-ast 见 §0）
```

`.m.ct` 可被 import 的失实修正也独立复跑：

```console
$ /tmp/rev-v0772/ct-ast build --emit-c --emit-map /tmp/rev-doc72-muc/m.map \
    test/modules/map_unit_cross/main.ct -o /tmp/rev-doc72-muc
$ echo $?
0
$ cc -Wall -Wextra -std=c99 /tmp/rev-doc72-muc/*.c -o /tmp/rev-doc72-muc/bin \
  && /tmp/rev-doc72-muc/bin | cmp -s - test/modules/map_unit_cross/expected.out; echo $?
0
```

逐条：B1-2/B1-3/B1-4、B2-2/B2-3 已落地且可核对；B2-1 的代际表与 31/41 计数与处置一致。
**B1-1 的字面验收「页首版本 == `ct -v`」没有以钉版本号形式实现**：处置改为「不固定版本号、
以 `ct -v` 为准」，把相等断言留给 B3-1 门禁，属已声明的 deferred，不是静默漏项。
`check-docs`/`g0` 均绿。

Deferred 触发条件复核：

| 项 | 处置写的触发条件 | REV 判断 |
| --- | --- | --- |
| B1-1 门禁断言 | 并入 B3-1 的独立门禁提交 | 明确（依赖 B3-1） |
| B2-1 剩余 L0/L2 收敛 | 「单独一轮 spec 结构收敛，不混入本次批」 | 有下一动作，无日期；可跟踪 |
| B3-1 | 「单开一次门禁改动（脚本 + 负例 + 红证）」 | 明确（动作与产物） |
| B3-2 | 「需运行器与逐 case 断言……分阶段」 | **无明确触发条件**（无日期 / phase / 前置门禁） |
| B4 | 「按 issue『后置』执行」 | **无明确触发条件**（仅「后置」） |

B3-2/B4 的 `deferred` 属 REQ/USER 权限，REV 不改状态；但按 5.4「deferred 必备触发条件或日期」，
建议 REQ 在收口时补上可判定的触发点（例如「spec-cases 运行器落地后」或某个 phase 号）。
