---
id: hw-2
head: 369a2606
trigger: B-5
proposer: DEV
opposition: REVIEW
judge: EDITOR
forbidden: selfhost/**, test/**, docs/**, AGENTS.md
---

# battle/hw-2 — `builtin_live` 的 `Str` 判据：文本近似还是符号级引用位

## 争点

PH-64-T2 引入「内置层按需发射」（`91c6c179`）。其中 `Vec` / `Option` / `Result` 以**实例表**判活
（`ct_insts()` 的 `tmpl`），而 `Str` 不是模板，首版用三条近似判据
（`selfhost/ct-ast/frontend/module/Module.h.ct:2031` 的 `builtin_live_for`）：

1. `Vec` 单元为活时 `Str` 也为活（Vec 的签名用到 `Str`）；
2. 任一**非内置**单元的源码经 `strstr(源码, "Str")` 命中；
3. 任一枚举到的实例的 `ctype[0]` / `carg[0]` 经 `strstr(…, "Str")` 命中。

争议点：这套近似的**精确性**是否满足 REQ-HW-011 的「只按实际使用/实例化拉取」，还是必须改成
符号级「引用位」（被引用时置位）或至少词边界匹配。双方不争议：`Vec`/`Option`/`Result` 的实例表判据、
以及 hw-1 J-3 已裁定的「不按容器名单禁/放」。

## 背景与触发

- 触发：B-5（用户显式 `battle: <topic>`，2026-11-17）。
- 当前 HEAD：`369a2606`（`v0.63.0`，PH-64 收口）。
- 相关 Issue/CR：无（实现偏差，未立案；本场判决若要求改动，另立 `SH-*`）。
- 既裁：`battle/hw-1` J-3（符号面判据、否定容器名单）与采纳段「按需单元」。

## 逐条判据（J-1…）

| ID | 判据 | 通过方式 |
| --- | --- | --- |
| J-1 | **完备性（no false negative）**：不存在自洽输入，使程序需要 `Str` 的 C 符号而判活为假（产物缺 `Str.c`，链接失败） | 构造夹具 → `ct build --emit-c` → `cc` 链接；缺符号即反例 |
| J-2 | **精确性**：对「判活为真但产物未引用任何 `Str*` 符号」的输入，给出可复现样本并判定是否违反 REQ-HW-011 的「只按实际使用拉取」 | 夹具（如声明 `struct Struct` / 字面量含 `Str`）→ 产物清单与 `nm` 面 |
| J-3 | **代价**：两方案各自改动的文件数/行数、影响的门禁、回退步骤 | `git diff --stat`、门禁清单、`git revert` 步骤（E4） |
| J-4 | **可机械检测**：方案能否落成一条门禁探针（命令 + 阈值），且该探针在现状下会红/绿 | 探针脚本 + 红绿各一次运行 |
| J-5 | **与 hw-1 J-3 一致**：方案不得以容器名单作为判活依据 | 方案文本与实现中无容器名清单 |

## 席位与边界

| 字段 | 值 |
| --- | --- |
| proposer | DEV（守首版近似） |
| opposition | REVIEW（证伪） |
| judge | EDITOR |
| 禁止触碰 | `selfhost/**`、`test/**`、`docs/**`、`AGENTS.md`；只写 `battle/hw-2/` 与 `/tmp` |

- 证据按 §7.7 E1–E5 提交；每轮至少新增 1 条 E1/E2（§7.11）。
- 只读证据基线：`/tmp/p0/ct-now`（HEAD `369a2606` 构建的 ct-ast）。需要反事实实现时，复制整棵树到
  `/tmp` 再改，**不得**改工作树。

## 两方初立场（T0 立案材料，供双方 steelman）

**位置 A（主张，DEV）**：首版近似满足 J-1——`Str` 的所有真实使用路径都先命中三条判据之一
（Vec 活、源码出现该标识符、实例参数出现）；`strstr` 的冗余只会**多保留**一个单元，不产生错值，
且 E3 探针（`test/ast/p64_on_demand.sh`）已钉住「最小程序只有自身 `.c`」与「`Option<int>` 只拉
`Option`」两条主线。改符号级引用位要动 `frontend/sym` 的解析路径，代价大于收益。

**位置 B（反对，REVIEW）**：`strstr(源码, "Str")` 是子串匹配，`struct Struct`、`String`、`Strlen`
都会误命中；这使「只按实际使用/实例化拉取」（REQ-HW-011）在可复现输入上为假，且 J-2 的口径
无法机械界定——同一个 `strstr` 既可能漏（拼写差异）也可能多（子串），属不可验收的近似。
