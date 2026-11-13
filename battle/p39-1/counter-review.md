# battle/p39-1 单方案评审·反证书（REVIEW 对 C）

| 字段 | 值 |
| --- | --- |
| 评审对象 | `battle/p39-1/C-proposal.md`（156 行，§7.10 出口 1） |
| 依据 | `verdict.md`：A/A′ `rejected`；本文件只证伪 C，不另提案 |
| HEAD | `ac040d1`；`/tmp/p39head/ct`（v0.37.0），源码 `/tmp/p39head/src` |
| 结论 | **C 未满足全部判据**：J-1、J-2、J-5 不成立；J-3、J-4 成立（形式/设计层）。C 把 A 的失败面从"所有单元"缩到"根单元"，但把剩余失败转成 2–3 次用户批准（B1/B3，可选 B2） |

---

## 1 Q1：根单元内的 C 兼容内部 helper 仍被导出，是否仍违反 J-1？

**是，仍违反。**

- J-1 原文（`question.md:18`）是"导出集合 = 作者明确要导出的集合"。C-1 只改**候选空间**（`C-proposal.md:26`），C-2 仍是"C 兼容即导出"（`:27`）——作者没有函数级声明入口。C 自己承认这是上限：`:18`（函数级标记零语法不可得）、`:63`（"通用情形……是 C 的公开定价"）、`:156` 缺口①。
- **文件组织（C-4′，`:30`）不是"明确要导出"的声明，也不是零成本**：`AGENTS.md:452` 要求"围绕主类型的代码留在同一文件"，`docs/language-spec.md:541-542` 的 unit-name lint 兜底。实例：`selfhost/ct-ast/frontend/sym/Symbols.h.ct:405`（`pub struct StructTmpl *ct_tmpls(int *n);`）是 C 兼容的**主类型访问器**；该单元作根 → C-2 强制写进 `.abi.h`，作者唯一的排除手段是拆单元，而这与仓库单元约定冲突。
- 所以 C 只把"全量"缩小为"单单元全量"，把同一种**类别错误**（签名兼容 ≠ 作者意图）从 N 个单元减到 1 个，没有消除。J-1 的判据文本没有"通用情形除外"。

## 2 Q2：L39-1w 是 warning；今天零诊断——C 把"静默"变可观测，还是换个静默位置？

**两者都有，净改善限于根内泛型。**

- **真改善**：根单元内泛型从"零诊断省略"变成带 `file:line:col` 的 warning（`C-proposal.md:28`）。J-5 方向上这是相对 A′ 的实质进步。
- **但静默只是换位置/变粗**：
  - (a) 非根单元的 `pub`（含泛型、trait 值）只有 C-5 一条**无位置**汇总（`:31` 自认"无位置可指，故用汇总"）。J-5 要求"被拒绝的签名必须给出 `file:line:col` 与原因"——汇总行不满足；这与 A′ 被否掉时"非候选"的措辞问题同构。
  - (b) `pub extern` 在 C 的规则里**没有任何诊断**：D39-2 跳过（`phase39-draft.md:56`、`:104`），C-7 原样保留（`:33`），`phase39-draft.md:201` 明确 `.abi.h` 不出现它、不算负例。C §2（`:53`）"作者写下的每个 `pub` 都有明确去处"、C §3 J-5（`:67`）"无静默路径"被此反例证伪。而今天 `--emit-c` 的生成头**有** `int lib_fn(int);`（E1-r3b）——C 把它从"可见原型"改成"不可见且无诊断"。
  - (c) warning 非阻断：不开 `-Werror` 时产物照出，作者仍可能到链接期才发现。J-5 的"可诊断"强度低于 A 的硬错（这正是我在 T2 承认 J-5 成立的理由）。
- 结论：**根内泛型 = 真改善；非根 / `pub extern` = 静默换位置**。J-5 不能判成立。

## 3 Q3：C-4 保留 trait 值硬错 = f3 不能成库；是否只是把失败推迟到用户批 B2？

**是推迟，但推迟的是 D39-6 的硬错代价，不是 B 的语法批准。**

- C 自认 J-1 的 f3 格不成立（`C-proposal.md:63`）；C-4 保留 D39-6（`:29`），默认 exit 1。
- 唯一出口是 **B2（可选用户批准，`:78`）**：批准则 C-4 并入 C-3，f3 能成库；拒绝则 f3 永久不能。C 的 J-1 完整性因此挂在"用户是否改自己 2026-11-13 批过的 D39-6"上。
- **C-4 的硬错不是链接的必然**：C-1 已允许非根单元保留 external 符号而不导出（`:37`），说明"归档里有未声明的 external"是可接受的；那么根单元里同样是 external 的 trait 值函数，为何不能像泛型一样"跳过 + 带列诊断"？C 明明有 C-3 的机制，只对泛型开、对 trait 值不开——这是把 J-1 押在 B2 上的策略选择，不是技术约束。
- 批准成本对照：B1 必须（`:77`）+ B3 必须（`:79`）+ B2 可选（`:78`）= **2–3 次用户签字**；B 只需 1 次语法批准（`AGENTS.md:469`）。C 的"零新语法"成立，"零批准成本"不成立。

## 4 新增证据（不重复前两轮）

### E1-r3a 非根 `pub` 在今天有逐函数可观测原型

```console
$ mkdir -p /tmp/p39r3/out && cd /tmp/p39r3
$ cat helper.h.ct   # pub int helper(void) { return 7; }
$ cat lib.h.ct      # import helper;  pub int root_fn(void) { return helper(); }
$ /tmp/p39head/ct build --emit-c lib.h.ct --outdir /tmp/p39r3/out; echo "emit_exit=$?"
emit_exit=0
$ cat /tmp/p39r3/out/helper.h | tail -3
int helper(void);

#endif
$ cat /tmp/p39r3/out/lib.h | tail -3
#include "helper.h"

int root_fn(void);
```

非根单元的 `pub` 今天在**它自己的生成头**里有逐函数原型；C-1 把它移出 `.abi.h` 后，只剩 C-5 的无位置汇总行——**观测粒度回退**（这是新事实，不是重跑 T2 的 nm 证据）。

### E1-r3b `pub extern` 今天有原型，C 下无诊断消失

```console
$ /tmp/p39head/ct build --emit-c test/modules/extern_decl/lib.h.ct --outdir /tmp/p39r3/extern; echo "emit_exit=$?"
emit_exit=0
$ cat /tmp/p39r3/extern/lib.h | tail -4
extern int lib_flag;
int lib_fn(int);
int lib_flag_get(void);
```

源码 `test/modules/extern_decl/lib.h.ct:6` 是 `pub extern int lib_fn(int x);`。C 的 `.abi.h` 会省略它，而 C 的规则集里**没有一条诊断**覆盖它（D39-2 / C-7 / `phase39-draft.md:201`）。

### 新增 E2 锚点

| # | 锚点 | 内容 | 用途 |
| --- | --- | --- | --- |
| E2-r3a | `selfhost/ct-ast/frontend/sym/Symbols.h.ct:405` | `pub struct StructTmpl *ct_tmpls(int *n);` | C 兼容的主类型访问器；作根即被 C-2 强制导出，Q1 的实例 |
| E2-r3b | `AGENTS.md:452` | "围绕主类型的代码留在同一文件；主类型过大时可拆子对象单元" | C-4′ 的"移到非根单元"不是零成本，且在 `selfhost/ct-ast` 上受 unit-name lint 约束 |

## 5 C 的 J-1…J-5 逐条

| 判据 | 判定 | 依据 |
| --- | --- | --- |
| **J-1** | **不成立** | f3 按 C-4 硬错（`:63` 自认）；通用情形（根内 C 兼容内部 helper）C 自认不解决（`:63`、`:156`）。f1/f2 的通过依赖 B1 |
| **J-2** | **不成立** | C 自报 3/5（`:64`）；`xunit_box`、`ns_types` 两个 trait 值单元与 `Str.h.ct` 作根仍失败，需 B2；"不改一行即可构成"不成立 |
| **J-3** | **成立（形式）** | 零关键字/零语法/零 CLI。但需 B1+B3（+可选 B2）的冻结变更签字；这不在 J-3 计分内 |
| **J-4** | **成立（设计层，有条件）** | 2 文件 / 55–75 行；条件：列号路径 (b) 可行。若 (b) 失败，C 自己规定回到评审并允许 3 文件（`:95-97`）→ 2 文件上限破 |
| **J-5** | **不成立** | 非根 `pub` 只有无位置汇总（`:31`）；`pub extern` 无诊断（E1-r3b）；L39-1w 列号未证（verdict U-2，`verdict.md:119`）；warning 非阻断 |

**结论**：C 只满足 J-3、J-4，与 `verdict.md` 对 A 的判定结构相同（J-3/J-4 成立，J-1/J-2 不成立），多出的 J-5 反而不成立。按 §7.9，C 不满足全部判据。

## 6 C 的失效条件（可观测、可复现）

| # | 触发条件 | 观测 | 判据 |
| --- | --- | --- | --- |
| F-C1 | 根单元内有 ≥2 个 C 兼容 `pub`，作者只想导出其中一个 | `.abi.h` 多出原型，无诊断（C-2） | J-1 |
| F-C2 | 根单元含 `pub extern` + 一个正常导出 | `.abi.h` 缺 extern 原型、stderr 无诊断（E1-r3b、C-7/D39-2） | J-5 |
| F-C3 | 根 import 的单元含泛型 `pub`，且要求逐条定位 | 只有 C-5 汇总行，无 `file:line:col`（`:31`） | J-5 |
| F-C4 | 用户拒绝 B1 或 B2 | f2/f3 回到 A 的失败面（`:77-78`） | J-1 / J-2 |
| F-C5 | 列号路径 (b) 实测失败 | 按 C 自己规定回到评审并可能 3 文件（`:97`）→ J-4 不再无条件成立 | J-4 |
| F-C6 | `test/modules/xunit_box/net.h.ct` 作根 | 默认 exit 1（C-4），该单元不能成库（P-C2 自证，`:134`） | J-2 |

## 7 己方最弱处

C 的"根单元"限定确实消掉了 A 最大的攻击面（所有单元全量），`p34_pub_generic` 在 B1 后能成库（P-C1）。若用户批准 B1+B2，且裁判只按 J-1 的三个夹具判，C 可以全绿。我的反对落在两处判据解释上：J-1 的"作者明确要的集合"是否按通用语义读；J-5 的"非候选"是否算"被拒绝"。这是判据解释之争，不是事实之争——若裁判采纳 C 的窄读法，我撤回 Q1/Q2 的对应两条，但仍保留"批准成本 ≥ B"（§3）。
