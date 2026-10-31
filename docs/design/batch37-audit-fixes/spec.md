# 第三十七批：2026-10-31 审计问题的处置（2026-10-31）

> 依据：[reports/audit-2026-10-31](../../reports/audit-2026-10-31/audit-2026-10-31.md)
> 与 `issues/` 下的 18 条新增 issue。锚点 `f4c77b1`（HEAD）。
> 原则：只修事实错误与门禁空白；不为「更完整的工程」引入新机制。不做的事明确写理由。

## 1. 修复（13 条）

| ID | 修复内容 |
| --- | --- |
| DOC-23 | README 中英 CLI 表：`--emit-map -` 在 `compile` 与 `build` 均可用 |
| DOC-24 | 教程中英两处：普通 `.ct` 只写 `.c`，只有 `.h.ct` 写 `.h` |
| DOC-25 | README 的 `-I` 按模式分别说明（build 限 16；compile 接受但不解析） |
| DOC-26 | grammar 21→27；roadmap 的 105→317（4 处）；tag 布局边界 v0.13.0→v0.12.0；v0.12.0 不再写「当前版本」 |
| DOC-27 | `test/README.md` 中英：include 路径、`01..56`、负例文本断言比例、`patterns/` 行 |
| DOC-29 | batch 4 checklist 27 项按实际落地勾选 |
| DOC-30 | glossary 版本公式补 v0.13.0 例外；AGENTS 中文 bump 登记补 v0.13.0 |
| TEST-8 | 12 个只断言位置的负例补上消息文本（batch 37 段） |
| TEST-10 | build 模式补 8 条 CLI 断言（`-o`/`-I` 缺参、`--std` 非法、未知选项、无输入、17 个 `-I`、65 个输入） |
| TEST-11 | 8 个 compile 夹具经 `build` 单单元镜像运行（编译 → 零告警 → 运行 → 比对） |
| TEST-12 | `check-warnings.sh` 扫描 `test/patterns/**`（146 → 152 项） |
| TEST-13 | `test/ast/errors/missing_method.ct` 改名 `null_vtable_slot.ct`，关卡同步 |
| SH-23 | ct-ast 对超过 159 字符的标识符报 `identifier is too long`（不再静默截断）；新增负例 |

## 2. 部分处置（2 条）

- **TEST-9**：新增 5 个生成式上限用例（params / methods / funcs / scopes / vars，覆盖 17 / 65 /
  257 / 257 / 4097 个元素）。其余 `MAX_*` 与驱动级上限按「遇到再补」处理——每加一条就是
  一份生成器与一个文案契约，收益递减；SH-23 已补上这一类里唯一会造成语义错误的空白。
- **CI-4**：新增 `Makefile` 的 `make check` 别名（调用 `check-all.sh`，语义不变）。
  **不加 GitHub Actions**：仓库托管平台与凭据未定；两条 BSD 探针在 Linux 需要跳过策略，
  先有本地聚合入口更符合最小改动。

## 3. 不采纳（2 条）

- **TEST-7（ct-ast 生成 C 的逐字节 golden）**：不采纳完整方案。理由是 D34 已明确 ct-ast 用
  「退出码 + 零警告构建 + 运行输出」判定，而不是文本；现有三层字节校验覆盖了绝大部分风险——
  `test/cases` 的 L0/L1/L2 逐字节 golden、ct-ast 自编不动点（对约 1.8 万行产物逐字节比对）、
  以及 L0 种子关（ct-ast 编出的 C 编译器复现 25 个 golden）。为 27 节特性各建逐字节 golden
  会把发射排版冻结，每次改进都要重生成，维护成本高于它能发现的「改写错但运行对」的残余风险。
  若将来真的出现这类回归，再**针对性**给那一节加 golden，而不是先建 27 份。
- **SH-24（合并 compile / build 两套 CLI 解析器）**：不采纳重构。它是 Info 级设计观察，
  两种行为都能工作；合并要同时改 `Driver.h.ct` 与 `Module.h.ct` 两个入口，属于结构性改动，
  违背最小改动原则。已在 README 按模式写清 `-I` 的差异（DOC-25），诊断文案的分叉留给
  下一次真正需要改 CLI 时再收敛。

## 4. 验证

- `check-ast.sh` 351 passed / 0 failed（新增 13 条消息断言 + 5 条上限 + 8 条镜像 + 8 条 build CLI）。
- `check-warnings.sh` 152 ok / 0 failed（新增 6 个模式产物）。
- `check-all.sh` 九关全绿；clang 与 GNU GCC 16 下生成物零告警。
- 未改生成物、golden、`CTC_VERSION`；L0 / L1 / L2 未动（SH-23 只落 ct-ast）。
