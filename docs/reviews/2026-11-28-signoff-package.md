# 签收包 · 2026-11-28（REV 只需要处理这一页）

> 中文。REQ 整理，锚点 `040e65d4`。
> 用途：把"已签"和"待签"一次列清，避免 REV 反复翻文档。
> **REV 在本包里不做任何代码修改**：只核对、签状态、写评审结论。

## 1 已签（只需索引，不用重做）

| 项 | 落点 | 提交 |
| --- | --- | --- |
| S8r2 + S8 尾（差异清单 §5） | [2026-11-27-s8-ir2-diff-list.md](2026-11-27-s8-ir2-diff-list.md#5-签字) | `0e2edb15` |
| S8 最终收尾（§7） | [2026-11-27-s8-closeout-lmodule.md](2026-11-27-s8-closeout-lmodule.md#7-签字) | `0e2edb15` |
| S8b 生成 C 可读性（§3.7） | [dogfooding.md](../planning/dogfooding.md) | `0e2edb15` |
| D-030（`Str.print` / `println`） | [D-030.md](../decisions/D-030.md)（`accepted`） | `0e2edb15` |

## 2 待签：只有 D-032

**签什么**：[D-032](../decisions/D-032.md) 设计——内部层（`selfhost/ct-ast` + `lib/core`）
用两处显式 manifest `c-boundary = allow`；消费者默认 strict 不变；
`c_boundary_for` 增加"单元自身目录 manifest"回退（与 `leaks_for` 对齐）。

**签完改哪两行**（只改这两行 + 可加一行签收日期）：

```text
- 状态：**accepted（REVIEW 签收 2026-11-28）**
- 签收：REVIEW（2026-11-28，T-8 非作者席位）
```

其余正文不重写、不调数字。若不同意：转 `battle/` 或 `CR-*`，不要改文档迁就。

## 3 只读核对（不跑长门禁，5 分钟内可完成）

```sh
# 1) 设计前提成立：c_boundary_for 只查 -I 根，leaks_for 已有自身目录回退
grep -n "int c_boundary_for" -A 22 selfhost/ct-ast/frontend/module/Module.h.ct
grep -n "int leaks_for" -A 22 selfhost/ct-ast/frontend/module/Module.h.ct

# 2) 现状没有这两处 manifest
ls selfhost/ct-ast/ct.pkg lib/core/ct.pkg 2>/dev/null || echo "absent (expected)"

# 3) shim 计数与"只有 include"的事实
find selfhost/ct-ast -name '*.shim.h' | wc -l          # 66
find lib/core -name '*.shim.h' | wc -l                 # 6
find bootstrap/ct-ast -name '*.shim.h' | wc -l         # 68

# 4) 判据与 ADR 一致（E-V3-10 新文 = CR-V3-1 新判据列）
grep -n "E-V3-10" docs/phases/v1-PH-2/card.md
grep -n "CR-V3-1" docs/phases/v1-PH-2/card.md
```

判据：① 设计前提与代码现状一致；② 两处 manifest 尚未存在；③ 计数与 D-032 §1 一致；
④ E-V3-10 新文没有夹带"放宽消费者默认"；⑤ D-032 没有扩 §4.67 补头集合。

## 4 签收后由谁做什么（你只签，不动代码）

| 顺序 | 席位 | 事项 |
| --- | --- | --- |
| 1 | DEV | M1：`c_boundary_for` 回退 + 两处 `ct.pkg`（[施工卡](../design/d032-internal-c-boundary-construction.md)） |
| 2 | DEV | M2/M3：69 个 include-only shim 退场 + seed 重生成 |
| 3 | REV | 实施后**只读**复核：四个 `--show-c-boundary`（两正两负）、门禁末行、shim 72 → 3 |

## 5 交付

- 设计签收：只提交 D-032 的两行状态（单文件），提交信息建议
  `docs(review): D-032 签收 accepted`；
- 实施复核：结论写进 D-032 §6 或单独 review 文件，列原始输出；
- 不改 `selfhost/**`、`lib/core/**`、`test/**`、seed；不改 issues 状态；不改版本号、不打 tag。

## 6 席位自检

若你是 D-032 的起草者或该实现的设计者/实施者，不得自签（T-8）：签字行写
「待非作者席位」，并在回报里说明。只签你能独立核对的部分。
