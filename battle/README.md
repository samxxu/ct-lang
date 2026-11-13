# battle 目录

> 中文。本目录是主规范 §7 的落盘区；工具入口 `tools/battle.sh`，校验 `tools/check-battle.py`。

## 一场 battle 的文件

| 文件 | 谁写 | 内容 |
| --- | --- | --- |
| `question.md` | 发起方 + EDITOR | 争点、HEAD、触发、逐条判据、proposer/opposition/judge、禁止触碰 |
| `claim.md` / `claim-r<n>.md` | 主张席 | 方案 + E1–E5；每轮至少新增 1 条 E1/E2 |
| `counter.md` / `counter-r<n>.md` | 反对席 | 失效条件 + E1–E5 |
| `verify.json` | 证据席 | environment、evidence（command/exit/output/reproduced）、anchors、checks |
| `verdict.md` / `verdict-c.md` | 裁判 EDITOR | 判据 × 证据的二元判定与判决 |
| `C-proposal.md` | 裁判 | §7.10 出口 1 的 C 方案 |
| `closed.md` | `battle.sh close` | 归档摘要 |

## 命令

```console
$ bash tools/battle.sh start p40-1 --proposer REQ --opposition REVIEW --judge EDITOR
$ bash tools/battle.sh check p40-1            # 结构校验；--strict 锚点缺失算错，--rerun 复跑命令
$ bash tools/battle.sh verdict p40-1          # 生成 verdict.matrix.md 草稿（不是判决）
$ bash tools/battle.sh close p40-1 --adr docs/decisions/D-00n.md --resolution "用户批准 X"
$ bash tools/battle.sh list
```

## 规则

- `start` 先校验 H-1（opposition 存在且 ≠ proposer）与 H-2（judge = EDITOR，proposer ≠ EDITOR），拒绝时不留目录。
- `check` 校验判据非占位、轮次 ≤3、E1–E5、verify.json、锚点；有 `verdict.md` 时 verify.json 必须有非空 checks。
- `close` 要求 `verdict.md` 且 `check` 通过；不覆盖已有 `closed.md`。
- 脚本只写 `battle/`（以及 `verdict.matrix.md` / `closed.md`），不修改源码、claim、verdict、卡与主规范。
- open-question 已写默认规则时**按默认规则继续**，不要回头让用户在方案间二选一（§7.10）；用户只在 §7.6 两种情形出场。
- 自测：`bash test/battle/run.sh` 或 `bash tools/check.sh battle-selftest`。
