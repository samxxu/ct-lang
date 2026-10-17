# ct 仓库全面审查报告

| 项 | 值 |
| --- | --- |
| 源码锚点 | commit `8aac450`（2026-10-17，`docs(roadmap): close out Phase 4`）——本文所有行号均为该 commit 的快照，源码变更后须复核 |
| 工作树 | 干净（`git status --short` 为空），`HEAD == origin/main` |
| 审查范围 | ① 代码质量与冻结合规　② 文档一致性　③ 测试覆盖度 |
| 方法 | 实测基线 + 诊断点机械枚举 + 逐点可达性探针；**全程只读，未修改任何源码/文档** |
| 配套 issue | [`issues/`](../../issues/README.md)（按模块分类，每条一个 markdown） |

> 一句话结论：**编译器本体与三层自举链的硬关卡全绿且冻结合规；问题集中在文档失真与门禁结构，而非编译器行为。** 当前实际阶段为 **Phase 5**（roadmap 总览表：Phase 0.3–4 均 ✅）。
>
> **修复进展（2026-10-17）**：11 条已修复、1 条开放（SH-2）；逐条状态与修复提交见
> [issues/README.md](../../issues/README.md) 的「修复进展」小节。本文其余部分保持审查时的只读快照（锚点 `8aac450`）。

---

## 0. 基线（本次实测原始输出）

| 检查 | 命令 | 结果 |
| --- | --- | --- |
| L0 构建 | `gcc -Wall -Wextra -std=c99 ctc.c -o ctc` | `build_exit=0`（零警告） |
| 主套件 | `./test/run.sh` | `== summary: 115 passed, 0 failed ==`，`run_exit=0` |
| CT 线·golden | `bash selfhost/check-goldens.sh` | `L1 golden coverage: 25 pass, 0 new, 0 pending, 0 regression`；`L1' 25 passed, 0 failed`；`L2 (split tree) 25 passed, 0 failed`；`L1 vs L2 on the split tree: 2 unit(s) identical, 0 differing`；exit 0 |
| CT 线·对差 | `bash selfhost/check-archive.sh` | `single-unit goldens: 3 pass` / `diagnostics: 10 pass` / `multi-unit goldens: 4 pass` / `designed cases: 16 pass` / `L2 (split tree): built warning-free`；exit 0 |
| 编辑器 | `python3 editors/vscode/test/check-grammar.py` | `== 19 checks, 0 failed ==`，exit 0 |

按层分解（全部取自同一次 `run.sh` 的 `ok` 行，非手算）：

```
build 1 | unit 1 | golden 25 | examples 6 | error 60 | limits 6 | cli 16  = 115
```

---

## 1. 代码质量与冻结合规 —— 通过

| 项 | 实测 | 判定 |
| --- | --- | --- |
| `ctc.c` 最后一次改动 | `1bdb93b fix(codegen): keep file-scope vars in emit_body`，即登记在案的**唯一**冻结期改动 | ✅ 合规 |
| 规模 | `ctc.c` 2930 行 · `selfhost/ctc.ct` 3685 行 · `selfhost/src/core.ct` 4291 + `driver.ct` 349 行 | — |
| 警告 | `-Wall -Wextra -std=c99` 零警告 | ✅ |
| 风格 | 内部函数全 `static`；无 `TODO/FIXME/XXX`；无 `strcat`/`strcpy`/`sprintf(`（一律 `Buf`/`xstrndup`） | ✅ |
| 边界 | `ctc.c:2762` 对 `namespace`/`import`/`pub` 直接 `die`，与「单文件」边界一致 | ✅ |
| 命名/许可 | 4 处 `CTC_VERSION "0.0.1"` 一致（刻意未 bump）；产物命名规则未变；banner 许可行完整 | ✅ |

**结构性观察（承接上一轮 OO 评审，**非缺陷**、非本轮要修项，但影响后续扩展）：**

- L2 上依赖注入仍是手工的：`SymTab *sym` 作为参数出现 **63 次**；`core.ct` 43 个 + `driver.ct` 9 个文件作用域 `static`（状态无归属）。→ [ISSUE selfhost/unowned-state](../../issues/selfhost/unowned-state-sym-param.md)
- **`MAX_FUNCS` 是 CT 线最紧的脆弱点**：`core.ct:449/470` 注释自述预算「nearly exhausted」，roadmap 实测 ≈58/64；`PipeOps` 已到 31/32。→ [ISSUE selfhost/max-funcs](../../issues/selfhost/max-funcs-headroom.md)

---

## 2. 文档一致性 —— 有实质漂移

### 2.1 严重（对外契约文档阶段失真）

| 位置 | 文档说法 | 实测事实 |
| --- | --- | --- |
| [README.md](../../README.md) L6 | "Phase 1、**Phase 2 均已完成，当前进入 Phase 3：内存**" | Phase 3、Phase 4 **均已完成**；[roadmap](../../docs/roadmap.md) L21–24 记 Phase 2/3/4 ✅，当前为 **Phase 5（展望）** → [ISSUE docs/readme-phase-drift](../../issues/docs/readme-phase-drift.md) |
| [AGENTS.md](../../AGENTS.md) L23 | "当前进入 **Phase 1：自举**"；"`ctc.c` 现为纯 OO（3836 → **2897** 行）" | 实际 `ctc.c` **2930 行**；阶段已到 Phase 5 → [ISSUE docs/agents-stage-linecount-drift](../../issues/docs/agents-stage-linecount-drift.md) |
| AGENTS §1 与 §2 自相矛盾 | L23 说 Phase 1 | L34/L52/L53 已按 Phase 3+ 现实书写（`selfhost/src/**`、L1 冻结、`check-archive` 跑 L2） |

### 2.2 中等

| 位置 | 问题 | Issue |
| --- | --- | --- |
| AGENTS §6（L108–L116） | 称 `./test/run.sh` 为「**五层覆盖**」，实际为 **7 层**（漏 `known limitations`、`cli`）；且**完全未列 CT 线关卡**（`check-goldens.sh` / `check-archive.sh` / `check-m2a.sh` / `ct-tour.sh` / `test/acceptance/run.sh`），仅在 §2 行文中提及 | [docs/agents-dod-layer-count](../../issues/docs/agents-dod-layer-count.md) |
| [docs/architecture.md](../../docs/architecture.md) L150 | 称 `cannot create a temporary file`（L2837）、`cannot read`（L2708）等「**审计已逐个探针确认不可达**」——**实测二者均可达**（见 §3.2） | [docs/architecture-unreachable-claim](../../issues/docs/architecture-unreachable-claim.md) |

### 2.3 低

| 位置 | 问题 | Issue |
| --- | --- | --- |
| [docs/roadmap.md](../../docs/roadmap.md) L680 / L682 | 残留「**待做**：多文件…仍 PENDING」「`--line` 仍归 Phase 4」——已被紧随其后的 L681/L682/L683 与实测全绿取代 | [docs/roadmap-stale-todo](../../issues/docs/roadmap-stale-todo.md) |

### 2.4 核对通过项

- `check-grammar.py` 19 项断言 ✓
- `CTC_VERSION "0.0.1"` 四处一致 ✓（roadmap 明确记录**刻意未 bump**，留待「单入口 ct」一次性重生成 golden）
- 冻结期改动登记仅 `1bdb93b` ✓；产物命名规则 / banner 许可行 / `gcc` 构建命令等均一致 ✓
- roadmap 总览表（Phase 0.3–4 状态）与实测关卡输出一致 ✓

---

## 3. 测试覆盖度

### 3.1 负例层

`test/errors/` 共 **60 个 `.ct` + 60 个 `.expected-err`**，一一对应。12 个 `MAX_*` 上限中，`MAX_TRAITS` / `MAX_STRUCT` / `MAX_METHOD` / `MAX_PARAMS` / `MAX_FIELDS` / `MAX_DEPTH` / `MAX_SCOPE` / `MAX_FUNCS` / `MAX_VARS` / `MAX_NAME` / `MAX_PARAM` 均有负例覆盖。

### 3.2 诊断点四态分桶（探针实测）

| 桶 | 项 | 证据 |
| --- | --- | --- |
| **Covered** | `2704 cannot open`、`2712 short read`、namespace/import/pub 拒绝、各 `MAX_*`、CLI 各分支 | `test/errors/*` 与 `cli/*` 断言 |
| **可达·未覆盖（actionable）** | `ctc.c:2837 cannot create a temporary file` | `TMPDIR=/nonexistent/zzz ./ctc ok.ct -o ok.c` → `ctc: cannot create a temporary file`，`exit=1`，**无 fixture** → [testing/ctc-2837](../../issues/testing/ctc-2837-tmpfile-not-covered.md) |
| **可达·未覆盖（actionable）** | `ctc.c:2708 cannot read` | FIFO 作输入 → `ctc: cannot read '/tmp/fifo.ct'`，`exit=1`，**无 fixture** → [testing/ctc-2708](../../issues/testing/ctc-2708-cannot-read-not-covered.md) |
| **防御点（探针证实）** | `1187 expected struct name` / `1189 expected '{' after struct` | 探针 `struct Foo` 缺 `{` → `exit=0` 原样透传，与文档判断**一致** |
| **未能复现（不可断言不可达）** | `1491 nested field path too long` | 深链探针 `exit=0`，**未复现** → [testing/ctc-1491](../../issues/testing/ctc-1491-nested-path-not-reproduced.md) |
| **不可测** | `158/237 out of memory` | OOM 分支，无法稳定构造 |

> 诚实标注：`1491` 只做到「探针未复现」，**不等于不可达**（skill 明确禁止无证据地断言 unreachable）。

### 3.3 覆盖盲区与结构问题

1. **`./test/run.sh` 完全不覆盖 CT 线**——`selfhost/ctc.ct` + `src/**` 约 8000+ 行只由 `check-goldens.sh` / `check-archive.sh` 等**手工脚本**把关，且 AGENTS §6 未把它们写进 DoD：开发者按 §6 自检会**漏掉半个仓库**。→ [ci/run-sh-misses-ct-line](../../issues/ci/run-sh-misses-ct-line.md)
2. **没有任何一条命令能跑全部关卡**：仓库无 CI（无 `.github`）、无 `Makefile` / `justfile` / 总入口。→ [ci/no-aggregate-gate-entry](../../issues/ci/no-aggregate-gate-entry.md)
3. **静默非重写类**（危险类）已由 `limits` 层 3 条 characterization 测试钉住（`one-line body / interface arg / rvalue receiver is passed through …`）✓ —— `errors` 层因只收非零退出而天然抓不到它，此处处理得当。

---

## 4. 结论与优先级

| 优先级 | 事项 | Issue |
| --- | --- | --- |
| **P0** | 增加聚合门禁入口，并覆盖 `run.sh` 的「五/七层」与 CT 线关卡 | [ci/no-aggregate-gate-entry](../../issues/ci/no-aggregate-gate-entry.md)、[ci/run-sh-misses-ct-line](../../issues/ci/run-sh-misses-ct-line.md) |
| **P1** | 修正 README L6 / AGENTS L23 的阶段与行数，消除 §1↔§2 矛盾 | [docs/readme-phase-drift](../../issues/docs/readme-phase-drift.md)、[docs/agents-stage-linecount-drift](../../issues/docs/agents-stage-linecount-drift.md) |
| **P1** | 为实测可达的 `2837`、`2708` 补两条负例（`.expected-err` 必须由真实二进制输出生成） | [testing/ctc-2837](../../issues/testing/ctc-2837-tmpfile-not-covered.md)、[testing/ctc-2708](../../issues/testing/ctc-2708-cannot-read-not-covered.md) |
| **P2** | 订正 `docs/architecture.md` L150 的「不可达」结论；清理 roadmap L680/L682 残留 | [docs/architecture-unreachable-claim](../../issues/docs/architecture-unreachable-claim.md)、[docs/roadmap-stale-todo](../../issues/docs/roadmap-stale-todo.md) |
| **P2** | 把 `MAX_FUNCS` 余量作为 Phase 5 AST 特性的显式前置约束 | [selfhost/max-funcs](../../issues/selfhost/max-funcs-headroom.md) |
| **P3** | （设计观察，非本轮要修）L2 状态无归属 | [selfhost/unowned-state](../../issues/selfhost/unowned-state-sym-param.md) |

---

## 附：方法与可复现命令

```bash
# 基线
gcc -Wall -Wextra -std=c99 ctc.c -o ctc
./test/run.sh
bash selfhost/check-goldens.sh
bash selfhost/check-archive.sh
python3 editors/vscode/test/check-grammar.py

# 诊断点枚举
grep -n 'die(' ctc.c
grep -n 'fprintf(stderr' ctc.c

# 可达性探针（示例）
printf 'int main(){return 0;}\n' > /tmp/ok.ct
TMPDIR=/nonexistent/zzz ./ctc /tmp/ok.ct -o /tmp/ok.c ; echo "exit=$?"     # -> 2837 可达
mkfifo /tmp/fifo.ct; ( sleep 0.3; printf 'int x;\n' > /tmp/fifo.ct ) & \
  ./ctc /tmp/fifo.ct -o /tmp/fifo.c ; echo "exit=$?"                       # -> 2708 可达
printf 'struct Foo\nint x;\n' > /tmp/sb.ct; ./ctc /tmp/sb.ct -o /tmp/sb.c; echo "exit=$?"  # -> 1187 未命中（防御点）
```

审查期间未修改任何文件；本文与 `issues/**` 均为新增只读产物。
