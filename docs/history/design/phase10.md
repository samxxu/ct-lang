# Phase 10 — 主线切换：让 `ct` 由 AST 版编译器提供

> 中文
>
> 状态：**10.1–10.7 全部落地（2026-10-19），Phase 10 收口并 bump 到 v0.10.0**。D38–D45 已按建议值确认。
> Phase 9 已把 `selfhost/ct-ast/main.ct`（下称 **ct-ast**）做成开发主线，但当时**用户实际运行的 `ct` 仍由旧管线 L2（`selfhost/l2/**`）提供**；10.7 起已切换到 ct-ast。
> Phase 10 的目标是补齐 ct-ast 相对 L2 的能力缺口，并把安装入口切过去；旧线保留为回归 oracle。

---

## 中文

### 1. 目标与出口

| 项 | 内容 |
| --- | --- |
| 目标 | 让 **ct-ast** 提供完整的 `ct` 命令行：`compile` / `build` / `get` / `install` 与全部既有选项，行为与 L2 等价 |
| 出口 | 以 ct-ast 构建的 `ct` 跑完整套关卡（`test/run.sh`、`test/modules`、`test/pkg`、`ct-tour`、`acceptance`）全绿；`check-ast.sh` 覆盖全部语料 |
| 版本 | `v0.10.0`（Phase 10 ↔ `v0.10.x`），已 bump（2026-10-19，冻结期例外，经用户授权） |
| 回退 | 旧线 `selfhost/l2/**` 冻结保留，tag `v0.9.0` 即为可回退点；切换前打 tag `pre-ct-ast-switch`（2026-10-19） |

### 2. 非目标

- 不新增语言特性（`map` 仍只设计冻结）。
- 不改变已发布的产物命名、banner 与 `ctc:` 驱动错误前缀（SH-3 决策）。
- 不改 `ctc.c` / L1。
- 不要求 ct-ast 与 L2 生成的 C **逐字节相同**（D34：行为等价）。

### 3. 能力对差（2026-10-19 按代码实测）

| 能力 | L2（`selfhost/l2/**`） | ct-ast（`selfhost/ct-ast/main.ct`） | 缺口 |
| --- | --- | --- | --- |
| compile：`-o` / 默认输出名 / `#line` / `--emit-map` | ✅ | ✅ | — |
| build：多文件 / `import` / `pub` / `namespace` / `--ns-root` / `-I` | ✅ | ✅ | — |
| 身份：二进制名为 `ct` 时 `-v`/usage 打印 `ct` | ✅ | ✅（`argv[0]` basename：`ct` / `ctc` / 开发名 `ct-ast`） | — |
| `--diagnostics=text\|json`（接受、校验、切换格式） | ✅ | ✅ 接受、校验与告警输出（text / JSON） | — |
| `--std=c99\|gnu99` | ✅ | ✅（build 的建议 `cc` 命令带上目标标准） | — |
| compile 模式接受 `-I` | ✅（静默接受） | ✅ | — |
| build 打印建议 `cc` 命令 | ✅ | ✅（10.1 补齐，含 `-std`） | — |
| 语义诊断：重复 trait / struct 报错 | ✅ | ✅（`file:line:col: error:` + `ctc: N error(s) generated`，位置指向 `{`） | — |
| 语义诊断：impl 签名不一致告警（text/json） | ✅ | ✅（措辞与 JSON 与 L2 逐字节一致；发射时取 trait 的返回类型） | — |
| 多错误恢复（`MAX_ERRORS=20` + 产物清理 + `N error(s) generated`） | ✅ | ✅（逐行重同步；超上限输出 `ctc: too many errors, stopping`） | — |
| Drop trait（`use Drop` / 递归释放） | ✅ | ✅ | — |
| AutoDrop（`own`） | ✅ | ✅ | — |
| 泄漏分析（作用域 / 条件 return / `ret_owned`） | ✅ | ✅（保守规则与 L2 一致） | — |
| 增量缓存 `.ctcache/<unit>.key` | ✅ | ✅（键与 L2 逐字节一致） | — |
| 包管理 `get` / `install` | ✅ | ✅（`PkgOps` 落在驱动层，编译核仍零网络） | — |
| 语料覆盖：`test/modules` 的 autodrop / leak / line / map 用例 | ✅ | 全部覆盖（line / map 见元数据层） | — |

### 4. 切片与出口

| 切片 | 内容 | 出口 |
| --- | --- | --- |
| 10.1 | CLI 与身份对齐：`--diagnostics`、`--std`、compile `-I`、`argv[0]` 身份、usage 文本 | ✅ **已落地（2026-10-19）**：`g_prog` 按 `argv[0]` 取 `ct` / `ctc` / `ct-ast`；两模式接受并校验 `--diagnostics=text\|json`（`g_diag_json` 留给 10.3）与 `--std=c99\|gnu99`；compile 模式接受 `-I`；build 补发建议 `cc -std=… <unit>.c… -o a.out`。`check-ast.sh` 新增 8 项 CLI/身份断言（64 → **72**） |
| 10.2 | 语义诊断：重复定义报错、签名不一致告警（text/json） | ✅ **已落地（2026-10-19）**：新增 `DiagOps`（`sem_error` / `record_sig_warn` / `emit_warnings`）；重复 trait/struct 报 `file:line:col: error:` 并以 `ctc: N error(s) generated` 收尾、失败不留产物（前置声明合法）；impl 签名不一致按 L2 措辞告警（text stderr / `{"warnings":[…]} ` stdout），发射函数取 **trait 的返回类型**使产物仍可编译。`check-ast.sh` 逐字节比对 `dup_struct` / `dup_trait` / `sig_mismatch` / `sig_mismatch_json`（72 → **76**） |
| 10.3 | 内存：Drop / AutoDrop / 泄漏分析 | ✅ **已落地（2026-10-19）**：`Drop` 内置 trait（`use Drop` / `impl Drop` / 递归释放 / `delete` 调用）与 AutoDrop（`own`，作用域末逆序释放，布局/Drop/作用域三种负例按 L2 措辞报错）落地；泄漏分析按 D40 复刻 L2 的保守规则（声明即跟踪 `malloc`/`calloc`/`ret_owned` 调用、赋值逃逸、`delete` 释放、条件 return 的路径告警、作用域末确定泄漏），text / JSON 均逐字节一致。新增 trait `MemoryOps`（11 个方法，未触碰 `ParseOps`）。`check-ast.sh` 新增 10.3 段：autodrop 4 例 + leak 7 例（76 → **87**） |
| 10.4 | 多错误恢复 | ✅ **已落地（2026-10-19）**：`parse_program` 在报错后重同步（到下一条行首或 `}` 之后，同 L2 的 `recover_pos`），继续解析后续声明；`impl` 指向未定义 struct 时按 L2 在 `{` 处报 `impl for undefined struct 'X'` 并跳过整个 body；`use` 引用未定义 trait 时在 struct 的 `{` 处报错；超过 `MAX_ERRORS=20` 输出 `ctc: too many errors, stopping` 并以 1 退出。报错单元一律返回失败，产物不落盘。`check-ast.sh` 新增 `multi_err` / `multi_err_build` / `max_errors` 三项（逐字节比对 L2，87 → **90**） |
| 10.5 | 增量缓存 | ✅ **已落地（2026-10-19）**：`build` 为每个单元写 `<outdir>/.ctcache/<base>.c.key`，键覆盖编译器版本、`--line` 强制度、诊断格式、`--ns-root`、单元路径、`mtime.size`、import 摘要与依赖 digest，拼写与 L2 **逐字节一致**（D41）。依赖按后序 DFS 保证 digest 先算；依赖变脏则下游变脏；`--emit-map` 不复用；键只在成功发射后落盘，`-c/-h` 缺失或键不符时重编。`check-ast.sh` 新增 10.5 段：冷编盖章、键对 L2、暖编复用、依赖失效、产物缺失重建（90 → **95**） |
| 10.6 | 包管理迁移 | ✅ **已落地（2026-10-19）**：`get` / `install` 按 D42 整体搬进 ct-ast 的驱动层（新 trait `PkgOps`，29 个方法），清单解析 / SemVer 子集与 MVS / 本地目录源 / git 源（`CT_REGISTRY`、`~/.cache/ct-pkg`、tag 选择与默认分支回退、commit + 内容摘要锁定）/ 五列 `ct.lock` / `ct.pkg` 回写去重 / `install` 离线校验与建议命令全部按 L2 措辞实现；编译核仍零网络零子进程。`test/pkg/run.sh` 的链路扩到 L0→L1→L2→ct-ast，并被 `get`/`install`/`build` 用例直接驱动（35 项全绿） |
| 10.7 | 切主线 | ✅ **已落地（2026-10-19）**：安装形态改由 **ct-ast** 构建（链到 L2 后由 L2 编出 `selfhost/ct-ast/main.ct`，二进制命名为 `ct` + `ln -s ct ctc`），L2 降级为回归 oracle；`ct-tour.sh` 的第 7 步改为展示 ct-ast 的身份与多文件构建、第 8 步缓存改用 ct-ast，README 的安装段落同步；切换前打 tag `pre-ct-ast-switch`。五处 `CTC_VERSION` 同步 bump 到 **v0.10.0**，108 个 golden（`test/cases/**` 50 + `test/modules/**` 58，含 map JSON 与 stdout）按真实二进制重生成，仅版本 token 变化；`check-all.sh` 8 关全绿，**Phase 10 收口** |

每片要求：`check-all.sh` 零回退；`check-ast.sh` 全绿；新增/修改语料必须由真实二进制输出生成期望值。

### 5. 待确认决策（建议值）

| 编号 | 议题 | 建议 |
| --- | --- | --- |
| D38 | 代码落点 | 继续单文件 `selfhost/ct-ast/main.ct`；`ParseOps` 已 32/32，新增能力放**新 trait**（如 `DiagOps` / `MemoryOps` / `CacheOps`），不拆多单元 |
| D39 | 诊断等价口径 | 告警文本与 JSON **逐字节一致**（`test/modules/*/expected.stderr` / `expected.stdout` 是逐字节比对的），这是 10.2/10.3 的硬约束 |
| D40 | 泄漏分析范围 | 只复刻 L2 的**保守规则**（作用域结束 / 条件 return / `ret_owned`），不引入新算法 |
| D41 | 缓存键 | 与 L2 同格式同算法（FNV-1a），命中的行为也一致：**不重放 `#line` 与告警**，`--emit-map` 不命中 |
| D42 | 包管理归属 | `get`/`install` 留在**驱动层**，不进编译核；入口由新编译器提供，编译核仍零网络零子进程 |
| D43 | 切换与回退 | 双轨期 ct-ast 为主、L2 为 oracle；切换前打 tag `pre-ct-ast-switch`；`v0.9.0` 永远是回退点 |
| D44 | 身份识别 | ct-ast 也按 `argv[0]` basename 识别，共三态：`ct` → `ct`、`ctc` → `ctc`、其余（开发 / 自编译名 `ct-ast`）→ `ct-ast`；`ct-ast` 是 `prog` 的初值，仅用于开发二进制 |
| D45 | 版本与收口 | Phase 10 ↔ `v0.10.x`；只有 10.7 全绿后才 bump `v0.10.0` |

### 6. 风险

| 风险 | 说明 |
| --- | --- |
| 诊断文本逐字节 | 告警措辞、顺序、行列号都进入 golden；任何措辞调整都会触发语料重生成，需先对差 |
| 错误恢复与 AST | 行重写版靠「重同步到下一行 / `}`」；AST 版要在解析器里定义可恢复边界，工作量最大 |
| 泄漏分析 | ct-ast 目前没有 `owned` 概念，需先把所有权信息挂到声明节点上 |
| 容量 | `ParseOps` 已满；新 trait 与 `MAX_METHOD 32` 的预算要像 9.x 一样预先算好 |
| 包管理入口 | 切主线后 `ct get` 的 argv[0] 与 `CT_REGISTRY` 行为必须保持，否则 `test/pkg` 与用户脚本都会断 |
