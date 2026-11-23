# SH-118 · 全量语料 FP=0 证据入库（v1.0 硬门禁 E-V1-5）

| 项 | 值 |
| --- | --- |
| 模块 | selfhost（类型检查证据 / 门禁） |
| 定性 | 证据缺口（v1.0 闸门） |
| 严重度 | High（A 的证据是 v1.0 硬门禁） |
| 锚点 | `78477712`（2026-11-24） |
| 依据 | [v1 路线 §2.4](../../docs/planning/v1-release-plan.md)、[SH-115](sh115-b-plus-strengthening.md) 第 4 条、[v1-PH-0](../../docs/phases/v1-PH-0/card.md) E-V1-5 |
| 状态 | open |
| 处置证据 | **accepted（2026-11-24 所有者同意开卡；证据归本卡，机制已在 SH-115 落地）** |

## 1. 问题

v1.0 的硬门禁是“**全量语料 FP=0**”（D2 = B+），但仓里只有按夹具计数的探针：

- [`p68_fp.sh`](../../test/ast/p68_fp.sh)：301 个合法件、1 条 skip；
- [`p69_fp.sh`](../../test/ast/p69_fp.sh)：跨单元口径。

没有任何一条命令对 `examples test lib` 的**全部** `.ct`（当前 1381+ 个）跑
`--check-level=warn` / `ct check --types` 并断言零命中。SH-115 只写了“这是 v1.0 门禁”，
没有承接卡。

## 2. 交付

1. **一条可复跑命令**（脚本名建议 `test/ast/p118_fp_all.sh`）：
   - 语料：`examples test lib` 下全部 `.ct`，按 P-1.1 的基线口径；
   - 判定：`ct check --types`（或 `ct build --check-level=warn`）输出中不得出现
     `initializer:` / `assignment:` / `return:` / `argument N:` / `type mismatch` 一类 B 诊断；
   - 不合格件必须逐条记录为 `skip`，并写明依据（如 `//@ct-requires`、负例、不可判定件），
     **skip 表只减不增**；
2. **原始输出入库**：基线 sha、语料计数、skip 清单、`OK/FAIL` 一行结论；
3. **接入已有门禁**：挂在 `selfhost/check-ast.sh`（第 8 道）内，**不新增门禁编号**
   （第 13 道留给 seed cutover 的 `check-seed.sh`，避免两处抢号）；
4. **负例**：注入一个已知误报（或临时放宽判定）必须变红，红证带 `baseline: <sha>`。

## 3. 验收

- 全量语料跑完 0 命中；skip 表每行有依据，数量与台账 P-1.1 的 1381 口径可对账；
- `check-ast` 内新增该段后仍全绿；`check-all` 12 门不变（不新增编号）；
- 证据文件放在 `docs/planning/j6-evidence/`（与 P-1.2 CSV 同处），并在
  [v1-PH-0](../../docs/phases/v1-PH-0/card.md) 的 E-V1-5 行末补指针；
- 证据可复跑：文档里给出命令与期望输出，任何人从干净 HEAD 能复现。

## 4. 非目标

- 不修类型检查器的既有规则（机制与边界归 SH-115 / SH-60）；
- 不把 `--check-level` 默认值改为 `error`（v1.1 S2）；
- 不覆盖负例语料（负例本应报错，不计入 FP）；
- 不处理外部包的语料（本仓不消费 std）。

## 5. 关联

- [v1-PH-0](../../docs/phases/v1-PH-0/card.md)（E-V1-5）
- [v1 路线 §2.4](../../docs/planning/v1-release-plan.md)（A 的机制 / 证据 / 默认值）
- [SH-115](sh115-b-plus-strengthening.md)（B+ 强化与默认 `warn`）
- [SH-117](sh117-j6-local-closeout.md)（同批的 J-6 本仓段证据）
- [J-6 台账](../../docs/planning/j6-evidence/ledger.md)（P-1.1 基线口径）
