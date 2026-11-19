# battle/review-v077-1 · 反证书（REVIEW，主张 B）

| 字段 | 值 |
| --- | --- |
| 主张 B | 报告方向正确；只有网络挂起、治理门禁、台账、phase-ID 是 1.0 硬阻塞；文档漂移 P1/P2 混合批处理；个别结论需重核/降级 |
| 基线 | `5b13fef4`（v0.77.0；`git show --stat HEAD` 只新增 review 文档，`selfhost/ct-ast` 源未动） |
| 环境 | Darwin arm64 / Apple clang；`/tmp/rev-ph77-build/ct-ast` 自报 `v0.77.0`；网络可达 |
| 结论 | A 的四项硬阻塞成立；第 5 项“全量 P1”不成立；B 胜出范围与 A 胜出范围见 §7 |

## 1. 五条 P1 的逐条判定

| # | 报告 P1 | 本席判定 | 修正 |
| --- | --- | --- | --- |
| 1 | `p77_external` 网络挂起 | **成立（P1）但条件窄** | 黑洞地址下 `ct get` 12s 无返回（§2 E1-b）；但网可达时探针 5s 返回 0，离线由 curl `--max-time 10` 在 ≤10s 转 77。缺陷是“git 子进程无内在上界”，不是“门禁默认挂起”。**撤回报告“网络黑洞……都会让硬门禁无限等待”的举例**：完整断网由 curl 兜住，只有 curl 可达而 git 卡住/要凭据才无界。修法 S 级：`check-ast.sh:994` 外套 `timeout` + `GIT_TERMINAL_PROMPT=0` / `http.lowSpeed*`，补“stub git 睡眠仍 ≤N 秒返回 77”的负例。 |
| 2 | 治理门禁缺位 | **成立（P1）但需拆** | `tools/check.sh` 只有 g0/g8/battle-selftest，且无 deviation：这是 §6.4 的形式违反。但“全绿不可信”过头：11 道产品门禁与 G1–G7 正交，`check-docs` 覆盖 G9 的 pin 逻辑（本机因主规范标为草稿 skip）与链接。G6 与 G1/G5 子集 P1；G2/G4/G7/G9 入口 P2；G1 依赖 phase-ID Blocker B/C，不能独立开工。 |
| 3 | 台账不闭合 | **成立（P1）** | 13 条“卡 ✅ / issue open”可复现；但 TEST-21 是 `open`（DEV 已处置、待复核），属合法待复核，不应算回填项（12+1）。报告“168 条”不可复现：按 issue 的 `状态` 行首格精确匹配为 204；且 221 个 issue 只有 1 个有 front-matter `status`，G6 要过必须做格式迁移。PKG-9 在 v0.77.0 实测已硬错（rc=1），但报告写的 v0.58.2 在 phase-log 是 PKG-6，版本归因不可核。PH-75 的“⬜ vs ✅”是 §6 阶段快照未更新，`g1` 判据不查叙述一致性，不能当 G1 旗舰证据。 |
| 4 | phase-ID 迁移未执行 | **成立（P1）但 blocked** | 账本不存在、Blocker A/B/C 未裁定（§3）。但“主规范已到 1.17.0”应改为“项目已 pin 1.17.0 草稿”：规范头部自标“草稿（未落入任何项目）”，编号提案也写“未生效”，PN 的生效性要 REQ/用户确认——这不降低硬前置，只是把 blocked 条件从 A/B/C 扩到“规范采纳/签字”。PN-6 要求“一个脚本”完成重命名+替换+断言，所以是裁定后的机械批，不是 142 处手改；报告 66/142/51 未给命令，同径复算为 73 行 / 138 文件 / 58 ID。现在可做“冻结新增裸 `PH-*` 引用”。 |
| 5 | 文档漂移成簇 | **部分成立** | P1 只保留 D-1/D-2（规划/索引仍写“未开卡”，与 4 个已收口 phase 直接矛盾）。D-3/D-5 降 P2（计数/元数据）；D-6/D-8/D-9/D-10/D-12 维持 P2，D-4 维持 P2，D-7/D-11 维持 P3；D-13 重核后 P2（§4 P3）。A 的“文档漂移按 P1 阻塞”不成立：报告自己把 13 项中的 9 项判在 P1 以下。 |

## 2. E1 命令与原始输出（含对 A 不利的证据）

**E1-a（利 A，P1-#2）**：`tools/check.sh:63-66` 只分派三个子命令。
```console
$ bash tools/check.sh g9; echo rc=$?
usage: tools/check.sh g0 | g8 | battle-selftest
rc=2
```

**E1-b（利 A，P1-#1 的机制）**：黑洞地址下 `ct get` 没有内在超时，12s 时被外层 `timeout` 杀掉。
```console
$ HOME=/tmp/cgh/h CT_HOME=/tmp/cgh/h timeout 12 /tmp/rev-ph77-build/ct-ast \
    get https://10.255.255.1/ct-pkg/std.git; echo rc=$?
rc=124
```
代码侧：`Pkg.h.ct:757-770` 的唯一子进程入口 `git_run` 直接 `system(full)`，无 timeout / `GIT_TERMINAL_PROMPT`；`:944-946` 只在 clone 失败时打印。

**E1-c（不利 A）**：“门禁会挂起”在本机不成立；探针在网可达时 5 秒全绿。
```console
$ s=$(date +%s); timeout 120 sh test/ast/p77_external.sh /tmp/rev-ph77-build/ct-ast; \
    echo "rc=$? elapsed=$(( $(date +%s)-s ))s"
ok   ct get std succeeds with a clean HOME and no index
...
OK p77/external (clean-HOME pin, both spellings, index row matches)
rc=0 elapsed=5s
```
离线时也不是“黑洞”：`/tmp/ct-full-review-check-all-offline.log:2269` 记录 curl 在 0ms 内失败 → `skip PH-77-S5 external`；`:3584` 为 `1517 passed, 0 failed, 5 skipped`。故 P1-#1 的可复现表述应改为“**特定**网络形态下无上界”。

**E1-d（利 A 的事实 / 不利 A 的精度）**：漂移与台账都在，但计数要由脚本产出。
```console
$ find test/ast -mindepth 1 -maxdepth 1 -type d | wc -l          # 299（README 写 119）
$ find test/ast/errors -maxdepth 1 -name '*.ct' | wc -l          # 295（README 写 141）
$ find examples -mindepth 1 -maxdepth 1 -type d | wc -l          # 51（报告写 52；tutorial 写 16）
$ find issues -name '*.md' ! -name README.md | wc -l             # 221
$ grep -rl '^status:' issues --include='*.md' | wc -l            # 1（§5.4 要求 front-matter）
```
按 `| 状态 |` 首行精确匹配：`open` 25、不在 §5.4 闭集 204（报告 168，未给命令）。结论“G6 会红”成立；具体数字不能当验收阈值。

**E1-e（不利 A 的“全绿不可信”）**：链接/版本/设计窗口是绿的；G9 pin 在 check-docs 里因主规范标为草稿 skip，g0 只校副本 sha 与块头、不校与主规范一致。
```console
$ bash tools/check.sh g0
g0: OK (block 1.17.0, session-map present)
$ python3 test/docs/check-docs.py | tail -3
spec pin: skipped (master spec draft 1.17.0)
check-docs: OK (1938 relative links in 323 files, v0.77.0, 11 hard gates, 12 phase status, 3 适用版本 header(s))
design window: ok (12/12)
```

**E1-f（D-13 重核）**：A2 已落地，A1/A3 未落地；规范不是“整句都错”。夹具：`struct J` + `impl J { char *get(char *k) }`；`a1.ct` 另加 `int get(int)`，`a3.ct` 用 `j[1.5]`。
```console
$ sh test/ast/p72_subscript.sh /tmp/rev-ph77-build/ct-ast
OK p72/subscript (key type)          # get(char*) + j[0] 已从静默空值改为硬错
$ CT_C_BOUNDARY=allow /tmp/rev-ph77-build/ct-ast check --types a1.ct   # 并存 get(char*)/get(int)
error: argument 1: expected 'char *', got 'int'
$ CT_C_BOUNDARY=allow /tmp/rev-ph77-build/ct-ast check --types a3.ct   # 无匹配候选时
error: argument 1: expected 'char *', got 'double'  # 不列候选签名
```

## 3. E2 `file:line`

| 方向 | 位置 | 事实 |
| --- | --- | --- |
| 利 A | [tools/check.sh:63-66](../../tools/check.sh#L63-L66) | 只有 g0/g8/battle-selftest；`g9` 退出 2 |
| 利 A | [Pkg.h.ct:757-770](../../selfhost/ct-ast/tool/pkg/Pkg.h.ct#L757-L770)、[:944-946](../../selfhost/ct-ast/tool/pkg/Pkg.h.ct#L944-L946) | `system(full)` 无超时；clone/fetch 无 env |
| 利 A | [p77_external.sh:32](../../test/ast/p77_external.sh#L32)、[:61-66](../../test/ast/p77_external.sh#L61-L66) | curl 有 max-time；`get_pkg` 调 `ct get` 无外层 timeout |
| 利 A | [check-ast.sh:994](../../selfhost/check-ast.sh#L994) | 探针直接调用，无 `timeout` |
| 利 A | [test/README.md:6](../../test/README.md#L6)、[:18](../../test/README.md#L18) | 141 / 119 vs 实际 295 / 299 |
| 利 A | [tutorial.md:1903](../../docs/tutorial.md#L1903) | 16 examples vs 51 |
| 利 A | [session-map.md:21](../../docs/session-map.md#L21) | blockquote 截断表格，PH-66–77 行不再渲染为表行 |
| 利 A | [AGENTS.md:452](../../AGENTS.md#L452) | `phase=PH-66` |
| 利 A | [roadmap.md:89](../../docs/roadmap.md#L89) vs [phase-log.md:202-203](../../docs/history/phase-log.md#L202-L203) | Phase 76 写 v0.76.1；实际 v0.76.0（v0.76.1 是 SH-92 fix） |
| 利 A | [typecheck-semantic-plan.md:1,5,108-111](../../docs/planning/typecheck-semantic-plan.md#L1)；[docs/README.md:41](../../docs/README.md#L41) | “未开卡” vs PH-68–71 已收口 v0.67.0–v0.70.0；索引还把编号写成 PH-67–70 |
| 利 A | [phase-migration-blockers.md:6](../../docs/planning/phase-migration-blockers.md#L6)、[spec:6](../../docs/spec/ai-coding-workflow.md#L6) | 迁移未开始；账本不存在；但规范自标“草稿（未落入任何项目）”，PN 生效性待确认 |
| 不利 A | [language-spec.md:2423](../../docs/language-spec.md#L2423)、[:2743-2746](../../docs/language-spec.md#L2743-L2746) | “尚未实现”仍对 A1/A3 成立；但“静默空值，不诊断”已被 PH-72 A2 改成硬错 |
| 不利 A | [phase75.md:56](../../docs/design/phase75.md#L56) vs [:66](../../docs/design/phase75.md#L66) | §6 是“R1 未做”的阶段快照，§7 是收口；不是 G1 能查的项 |
| 不利 A | [phase72.md:61](../../docs/design/phase72.md#L61)；[lang-4…md:8](../../issues/lang/lang-4-subscript-type-mismatch-silent-empty.md#L8) | 卡 ✅ / issue `open` 并存；12 条属实 |

## 4. E3 可证伪预测与反例

| 预测（若 A 成立） | 反例 |
| --- | --- |
| P1：“`check-all` 在网络存在时会挂起” | E1-c：探针 5s 返回 0；离线 0ms curl 失败 → 77。可复现的只剩“`system()` 子进程无上界”（E1-b）。A 的“无限等待”应加限定“仅当 curl 可达而 git 传输卡住/要凭据”。 |
| P2：“文档漂移是 P1，所以 `check-docs` 应红” | E1-e：1938 链接 / 323 文件全绿；没有门禁读“示例数/目录数/phase 状态词”。漂移是语义计数，不是结构损坏。修法是一个计数脚本 + 一次纯文档批（T-7 `no-test`）；产品门禁不因它变红/变绿。 |
| P3：“`language-spec` 的 D52-6 仍准确” | E1-f：`j[0]` + `get(char*)` 已是硬错（`p72_subscript` OK）；但并存（A1）和无候选列表（A3）仍未实现。故 D-13 成立但应精确改成“A2 已修；A1/A3 归 REQ-JSACCESS-1”，级别 P2，不是 P1。 |
| P4：“phase-ID 与 G1 是两个独立 P1，可并行修” | G1 要读 `phase-id` / `version-minor` / 卡片路径，而 Blocker B/C 正是“卡片路径与字段”未裁定；`g1` 入口也不存在（E1-a）。先做 G1 会二次迁移（blockers §5 明说“在 A/B 裁定前不动文件”）。应合并为一个 blocked 工作流。 |
| P5：“台账只要把 13 条改成 verified 就闭合” | E1-d：221 个 issue 仅 1 个有 front-matter `status`；25 条 open、204 条状态词不在闭集。13 条是下限；G6 的通过条件是格式迁移 + 逐条证据，不是 13 次编辑。 |

## 5. E4 成本与批处理

| 项 | 改动面 | 估算 | 批处理建议 |
| --- | --- | --- | --- |
| 网络上界 | `check-ast.sh:994` 外套 `timeout`；`p77_external.sh` 给 `ct get` 加 `GIT_TERMINAL_PROMPT=0`；`git_run` 加 `http.lowSpeedLimit/Time`；1 条负例 | S | 单独 issue，先修；不阻塞其它 P1 |
| G6 台账 | 25 条 open 逐条定性（12 条回填 + TEST-21 复核 + 其余复核）+ 221 文件补 front-matter（脚本）+ 统一状态词 | M | 一个 P1 issue（REV owner） |
| G1/G5 | G1 依赖 phase-ID 的 Blocker B/C；G5 依赖 G1 的卡格式 | M，阻塞 | 与 phase-ID 合并成 blocked 工作流，不单独立 P1 |
| G2/G4/G7/G9 入口 | `g2`（ACC 映射）、`g4`（snippets/300 行）、`g7`（密钥扫描）、`g9`（独立入口或 deviation） | S–M | 一个 P2 issue；G4 的 300 行缺口（language-spec 2824 / tutorial 1931 行）先登记 deviation 或分拆 |
| phase-ID | A/B/C 裁定 + 一个迁移脚本 + 账本 + 5 条断言；58 ID / 138 文件 / 73 roadmap 行（报告 66/142/51 未给命令） | L，阻塞 | P1 issue 但 `blocked`（触发 = 裁定 decision）；当前先加“禁新增裸 PH-*”5 行 grep 门禁 |
| 文档 P1 | D-1/D-2：typecheck 计划 7 行 + docs/README 1 行 | S | 一个 issue（纯文档，`no-test`），与 P2 批分开提交 |
| 文档 P2/P3 | D-3…D-13：约 10 文件 / 15 行 + 计数脚本 | S | 一个 P2 批；脚本同时复核报告自身 52/168/66/142/51 |
| 样例覆盖 | 4 个 example × 20–40 行 + README + 门禁挂接 | M | REQ 池（非 issue），P2；无规范条款把“每相示例”列为发布门槛 |
| 设计窗口 | `git mv docs/design/phase66.md docs/history/design/` | S | 开 v1-PH-0 前的任务，不是 issue |

## 6. E5 steelman A（P1 全量阻塞）与反驳

| A 的最强论点 | 反驳 |
| --- | --- |
| 1.0 是发布契约：治理/台账/迁移不实，“1.0”只是标签；文档漂移是这个失序的表征，故 5 项都该 P1 | 契约项是前 4 项；文档是表征，不是契约。报告自己把 13 项中的 9 项判在 P1 以下（D-4 P2、D-7 P3、D-11 P3、D-13 待复核），A 的“全量 P1”与报告正文不一致（J-4）。 |
| 2. 治理缺位使“全绿”不可信；`check-all` 全绿不能作为发布依据 | 11 道是产品门禁，回答“编译器是否坏”；G1–G7 回答“治理是否可审计”。缺 G6 不影响 1517/0 的可信度，只让发布说明不可审计。E1-e 还显示 g0/链接是绿的（G9 pin 本机 skip）。 |
| 3. 台账 13+ 已修仍 open，发布说明不可审计；必须全量 P1 清账 | 13 条属实且是 P1（本席同意）；但“168 条”不可复现，根因是 221 个 issue 只有 1 个有 front-matter。修法是一次格式迁移 + 12 条证据复核（M），不是 168 次编辑；也不必和文档漂移绑同一 P1。 |
| 4. phase-ID 是 v1.0 开卡硬前置，必须先于一切；A/B/C 也要在 1.0 前解决 | 前置成立，但“先于一切”不可执行：A/B/C 要主规范/用户裁定，项目侧现在只能冻结新引用。把被外部阻塞的项写成 P1 任务，会让 critical path 挂空；正确形态是 blocked issue + 触发条件 + 立即可做的 grep 门禁。 |
| 5. 没有近相 example、样例 7/10，是用户入口缺口，应随 P1 一起做 | 样例不是发布门槛：§6.4 G4 管文档 snippet 与 300 行，不是“每个 phase 一个 example”；`examples/README` 已声明 49_socket 是文档型、不进门禁。报告自己给 P2。补 4 个 example 是 REQ/P2。 |
| 6. D-13 “未实现”是规范与实现冲突，至少一处要改，不能降级 | 只对一半：A2 已是硬错（E1-f），A1/A3 仍未实现。精确改法是 §4.64 D52-6 的“静默空值，不诊断”一句 + 一句“A2 已修、A1/A3 归 REQ-JSACCESS-1”；P2 文档修正，不是发布阻塞。 |

## 7. 结论与落 issue 分组

**报告方向正确**：产品 11/11 绿、无产品级 P0；四项硬阻塞成立。B 只在第 5 项定级、“全量 P1”结论、若干计数/子结论上反对。

| 落法 | 条目 | 级别 | owner | 验收 |
| --- | --- | --- | --- | --- |
| issue | `check-all` 网络子进程无上界：探针 + `git_run` 双层上界 | P1 | DEV | 黑洞 `ct get` 修复前 rc=124（E1-b）；修复后 ≤60s 返回 77 + stub-git 负例 |
| issue | G6 台账闭合：25 条 open 逐条定性（12 条回填 + TEST-21 复核）+ front-matter/状态词迁移 | P1 | REV | `g6` 对 221 条全绿；逐条贴 phase 卡/提交证据 |
| issue | 治理门禁：G6/G1/G5 子集或 deviation；G2/G4/G7/G9 入口单列 | P1/P2 | REQ | `tools/check.sh` 同名子命令或签字 deviation；`g1` 依赖 migration 裁定 |
| issue | phase-ID 迁移：A/B/C 裁定后建账本 W0→W1 + 脚本 + 5 断言 | P1（blocked） | REQ/EDITOR | decision 记录；账本行数 = 实有 ID；五断言原始输出 |
| issue | 文档 P1：D-1/D-2 + D-13 精确改写 | P1 | DEV | 纯文档提交（`no-test`）；计划写“PH-68–71 已收口” |
| issue | 文档 P2/P3 批 + 计数脚本（test/README、tutorial、session-map、roadmap、README） | P2 | DEV | 脚本复算 299/295/51 与状态分布，误报 0 |
| REQ | 4 个 near-phase example；覆盖率/容量夹具 | P2 | REQ | 入 `requirements-pool.md`，不阻塞 1.0 |
| task | 开 v1-PH-0 前退役 phase66（设计窗口 12/12） | P2 | DEV | `git mv` + check-docs 绿 |

**不建议**：把“文档漂移全量 P1”落成一个大 issue（会把 9 个 P2/P3 拖进 1.0 critical path）；把 phase-ID 写成 DEV 可立即开工的 P1（A/B/C 未裁定，违反 blockers §5“裁定前不动文件”）；用报告的 52/168/66/142/51 当验收阈值（未给命令，复算不等）。

**B 胜出**：P1 的“4 硬 + 1 软”分级、文档 P1/P2 批处理、D-13/样例覆盖/计数复核。**A 胜出**：网络无上界、治理门禁形式违反、12 条卡/账矛盾、phase-ID 硬前置——这四项按 P1 落 issue，不降级。
