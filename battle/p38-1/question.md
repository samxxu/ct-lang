---
id: p38-1
head: 0c9320c
trigger: B-5
proposer: REQ
opposition: REVIEW
judge: EDITOR
forbidden: selfhost/**, test/**, docs/**
---

# battle/p38-1 — PH-38 收口边界：guard 副作用接收者与 switch 嵌套 defer

## 争点

`--runtime-checks` 当前对 `arr[pick()].area()` 这类**接收者表达式带副作用**的派发会保护一个元素、调用另一个元素，可能段错误且没有 runtime 消息；`switch` 内 defer 当前连 case 内嵌套块/循环体也一律禁止。两条都缺一张明确的 v1 边界裁定。

- **A（接受边界）**：文档化“接收者不得有副作用”，`switch` 内（含嵌套块）一律禁止 defer；不改代码，按现状收口。
- **B（sound guard）**：`--runtime-checks` 下拒绝接收者种类为 `N_INDEX`/`N_CALL` 的派发，给 `file:line:col` 诊断，要求先绑定局部；`switch` 内仍一律禁止；不改 off 产物。
- **C（全量 hoist + 放宽 switch）**：发射期把接收者物化到临时量，并实现 case 作用域/fallthrough 的 defer 语义；成本高，另开 phase。

## 背景与触发

- 触发：B-5，用户指令「不要问我；按工程规范；无法决定的事就 battle」。
- 当前 HEAD：`0c9320c`；独立评审确认 goto/defer P0/P1 已清零，剩余 P2 为 guard 副作用接收者、switch 禁得过宽、测试覆盖与版本/tag。
- 相关 Issue/CR：无（PH-38 卡 §9.1）。

## 逐条判据（J-1…J-5）

| ID | 判据 | 通过方式 |
| --- | --- | --- |
| J-1 | **E37-3 安全契约**：在 `--runtime-checks` 下，任何**被接受**的 vtable 派发遇到空 vtable 必须 abort 并带 `文件:行`，不得静默段错误 | `arr[pick()].area()` 清零夹具；A 预测 rc=139 无消息，B 预测 rc=1 带位置诊断，C 预测 abort |
| J-2 | **E38-1…E38-8 全绿**：正常落出/return/break/continue/own 顺序、L38-1/2/3/4/5、既有 corpus 与自举不动点 | `bash selfhost/check-all.sh` + `p38_probe.sh` |
| J-3 | **不新增语法/CLI，off 产物不变**：只改 `--runtime-checks` 开启时的行为；关闭时 `.c` 逐字节不变 | off/on 产物 diff；`git diff` 路径 |
| J-4 | **成本/风险**：≤2 文件、无解析器大改、可回滚；A=0，B 约 10–30 行，C>100 行且改发射器/作用域 | 改动清单与行数估算 |
| J-5 | **可诊断、可测试**：拒绝必须 `file:line:col: error:`；新增正/负例能在旧实现上红、新实现上绿 | `p37_rt_probe` / 新负例原始输出 |

## 席位与边界

| 字段 | 值 |
| --- | --- |
| proposer | REQ |
| opposition | REVIEW |
| judge | EDITOR |
| 禁止触碰 | `selfhost/**`、`test/**`、`docs/**`；只允许写 `battle/p38-1/` 与 `/tmp` |

- 证据按 §7.7 E1–E5 提交；每轮至少新增 1 条 E1/E2（§7.11）。
- 最多 3 轮；三轮无结论按 §7.10 出 C 或 open-question。
