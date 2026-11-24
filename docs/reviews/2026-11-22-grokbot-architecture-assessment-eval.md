# 对 GrokBot《CT 语言架构评估报告》的评估

> 评估对象：GrokBot 外部评估报告（快照 `c993f41`，编译器自报 v0.88.3；正文标注 2026-11-22）。
> 核对基线：本仓 `main`（本轮为 `f723a599`）。只核对事实与主张是否落地，不改代码。
> 结论先行：**这是目前外部评估里事实密度最高的一份**；规模、测试计数、容量常量、许可、
> 示例输出与我们的自述逐项吻合，三处硬缺陷（SH-73 / SH-110 / SH-114）也与仓内卡一致。
> 它有 **3 处事实错误**，均不影响总评；**没有提出新的架构级主张**，不需要新增 phase 或卡。

## 1. 可核对的断言

| 报告断言 | 核对结果 | 证据 |
| --- | --- | --- |
| `selfhost/ct-ast` 约 27 单元 / 45797 行 | **完全一致** | `find selfhost/ct-ast -name '*.ct'` → 27；`cat` 累计 45797 |
| L0 约 2966 行；L2 约 7179 行 | **完全一致** | `ctc.c` 2966；L2 `core.ct` 5441 + `driver.ct` 1738 = 7179 |
| `MAX_FUNCS` 512，整程序预算，非每单元 | 一致 | [Symbols.h.ct](../../selfhost/ct-ast/frontend/sym/Symbols.h.ct#L32-L36)、[spec §7](../language-spec.md#7-容量上限) |
| `MAX_NODES` 262144 / `MAX_VARS` 4096 / `MAX_TRAITS` 64 | 一致 | spec §7 表；`Symbols.h.ct` 常量组 |
| `test/run.sh` 156 passed；`check-ast.sh` 1578 passed / 5 skipped | 一致 | [test/README.md](../../test/README.md#L28-L30) |
| 11 道硬门禁；编辑器语法 179 项断言 | 一致 | `check-docs` 输出 `11 hard gates`；`editors/vscode/CHANGELOG.md` |
| 官方 pin 表只有 `ct/std`（0.19.0） | 一致 | [ct-pkg.md](../ct-pkg.md#L42-L44) |
| 标签 `v0.88.3` 指向 `7061aa22` | 一致（附注标签对象 `c9c94e6b` 解引用到该提交） | `git tag --list 'v0.88.3' --format=…` |
| `LICENSE.EXCEPTION` 存在，输出例外 | 一致 | 仓根 `LICENSE.EXCEPTION` |
| SH-73 / SH-110 为 High 级 deferred | 一致 | 两张卡均 `deferred`，严重度 High |
| SH-109 动态增长、SH-111 / SH-112 deferred | 原快照一致；2026-11-23 改判后 SH-109 已 `open` 并提前到当前 pre 窗口 |
| SH-114 泛型先用后定义、v1.1 | 一致 | [SH-114](../../issues/selfhost/sh114-generic-template-order.md) |
| `Str` 逃逸 warning 自 v0.88.2；`box` 直接环限深 3 | 一致 | spec §4.70 / §4.72 |
| 右值 struct 直接装箱为硬错；`match` 穷尽 | 一致 | spec §6.2、§4.73（E84-3） |
| README 承认“完整路径”在 0.44.1 写不出来 | 一致 | [README.md](../../README.md#L32-L64) |

**不可核对项**（外部元数据，报告已自述）：star / fork / 提交总数 / 贡献者 / CI run 页 /
`ct-pkg` 组织页仓名 / 第三方包成熟度。这些不进本评估结论。

## 2. 三处事实错误

| # | 报告原文 | 实际 | 影响 |
| --- | --- | --- | --- |
| 1 | 「512 个函数（**还要扣掉内置层**）」 | **内置层不占用户预算**：`nfunc` 判界是 `nfunc >= nfunc_base + MAX_FUNCS`，`nfunc_base` 把 builtin 先扣除 | 低估可用预算；会误导“真实工程更早撞墙”的判断 |
| 2 | 「`issues/` 约 237 条 verified、38 条 deferred、11 条 rejected」 | 实测 293 个卡：**220 verified / 34 deferred / 11 rejected**，另有 25 个无状态行（多为 selfhost/ci/test 卡）、2 open、1 superseded | 计数偏高，不影响“债务已入卡”的定性 |
| 3 | 「`atomic` 等是**上下文关键字**」 | §4.59 原文是**上下文类型修饰**：只有后跟 `int` / `long` / `void *` / `bool` 才是类型；`int atomic = 1;`、`atomic;` 仍是普通标识符 | 分类误差；不影响“不抢占 `<stdatomic.h>` 名字”的结论 |

报告自己在 §5.1 已注明 issues 计数“有噪声”，§2.4 对 `atomic` 的表述也比 §2.1 准确；
把它当作外部快照的可接受误差即可，不必对外勘误。

## 3. 可取之处

- **唯一一份把“可复现实验”和“文档主张”分开写的外部评估**：自举、5 个示例、生成 C 逐项对照，
  并明确列出没跑的部分（11 门禁、sanitizer、裸机、联网 `ct get`）。这个口径值得保留。
- **Linux GCC 直跑 `test/run.sh` 的发现是有效的**：`check-all.sh` 会自动包
  `-Wno-format-truncation`（[check-all.sh](../../selfhost/check-all.sh#L74-L89)、
  [selfhost/README.md](../../selfhost/README.md#L69-L70)），但 [test/README.md](../../test/README.md)
  当前的“156 passed”没有写这条前提；外部用户直接跑会得到 1 failed。
- **成熟度定位与我们一致**：「关注并小规模试用，不下注」；v1.0 的观察信号（去 L1/L2、FP=0、
  SH-73 / SH-110 关闭、`MAX_FUNCS` 动态增长是否落地）与 [v1-release-plan](../planning/v1-release-plan.md)
  的清单一一对应，没有额外要求。
- `docs/modern-oo-gap.md` 是 Phase 30 基线，报告提醒“不要当当前能力表”是对的；该文档本身已标注
  基线，但缺少指向当前能力表的入口。

## 4. 不需要吸收的部分

| 报告观点 | 处置 | 理由 |
| --- | --- | --- |
| 默认编译路径不做全量类型检查 | 不改 | 已定分层：CLI `off` / v1-pre CI `warn` / v1.1 S2 `error`；D2 证据是 v1.0 门禁 |
| AST 直接发射、无 IR，是架构债 | 不改 | SH-111（v1.1 轻量不变量）/ SH-112（v1.2 Typed IR）已承接 |
| `MAX_FUNCS` 512 是硬墙 | 已改 | 2026-11-23 所有者改判：SH-109 动态增长提前到当前 pre 窗口，固定 512 不再是功能上限 |
| 无借用检查、refcount 非原子 | 不改 | 语言定位即“有纪律的 C + 句柄糖”，已在 §4.70 / §4.72 写明 |
| 单人总线、生态薄、非 LSP | 不改 | 事实陈述，不是工程缺口；不新增治理动作 |
| 没有性能数据 | 不改 | 报告未编造数字；我们也不承诺性能，维持“以 `cc` 产物为准” |

## 5. 建议的落地（均不新增 phase）

1. **test/README 补一行前提**：`test/run.sh` 在 Linux GCC ≥ 8 直跑可能因
   `-Wformat-truncation` 报 1 项失败，以 `check-all.sh`（自动加 `-Wno-format-truncation`）为准。
   路径属 `test/**`，已开 [TEST-26](../../issues/testing/test26-test-readme-gcc-caveat.md) 交 DEV。
2. **`docs/modern-oo-gap.md` 顶部加一行指针**：“当前能力以 [capabilities.tsv](../capabilities.tsv)
   与 spec §4 为准；本文是 Phase 30 基线。” 属 `docs/**`，已随本批文档提交。
3. **`atomic` 条款不改**；`MAX_FUNCS` 已由 2026-11-23 改判为动态增长（SH-109），spec §7 随后同步。
4. **不新增架构卡**：报告的风险项全部已有承接卡，重复开卡只会增加台账噪声。

## 6. 与上一份外部评估的关系

- [ChatGPT 架构评估](2026-11-22-architecture-assessment-eval.md) 提出的是**架构选项**（capability
  registry、C ABI 导出面、Typed IR、诊断 JSON 等），需要逐项裁决；
- GrokBot 这份是**外部事实核对 + 成熟度定位**，没有新选项，价值在独立复现与对外口径。
- 两份报告的共同结论一致：v1.0 前不宜迁移生产系统；默认检查级别、容量、SH-73 / SH-110 是
  最该盯的信号。
