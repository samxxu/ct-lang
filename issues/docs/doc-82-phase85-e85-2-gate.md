# DOC-82 · PH-85 收口记录把 E85-2 写成“通过”，与卡面 §7.3/§8 的“门不通过”冲突

| 项 | 值 |
| --- | --- |
| 模块 | docs（phase 卡 / 收口记录） |
| 定性 | 判据口径与记录不一致 |
| 严重度 | High（收口真实性） |
| 锚点 | `e0b0c561`（v0.85.0，2026-11-21） |
| 文件 | `docs/design/phase85.md:39-41`、`:88`、`:148`、`:231`；`AGENTS.md:508`；`docs/history/phase-log.md:187` |
| 状态 | **open** |

## 现象

同一张卡里并存三种写法：

- 卡 §1.3（`docs/design/phase85.md:39-41`）：“选一个子系统……做**完整等价重写**；
  **spike 通过才排 PH-86–88**；不通过则退化为按 inventory 逐项替换”；
- E85-2（`:76`）：“spike 报告含行数、编译耗时、测试语料逐字节一致原始输出、sharp edge
  清单；**门通过**”；
- R85-1（`:88`）：“spike 不通过 → 退化为逐项替换；不进入整体重写”。

DEV 的 spike（`test/probes/p85_spike_lexer.patch`）只把 `next` 拆成 5 个 token 类方法，
没有使用 `Str` 视图、`?`、`errdefer`、`match` 等新语法；报告自己写：

```console
$ grep -n "结构等价\|不通过\|未覆盖" docs/design/p85_spike.md
70:| 结构等价（拆分、逐字节语料、不动点、零告警） | **通过**（§1/§2 原始输出） |
71:| 整子系统“新语法等价重写”（`Str` 视图 / `?` / `defer` / `match`） | **不通过（未覆盖）** |
72:| 门的含义（卡 §1.3 / R85-1） | **作为“PH-86 可以一次整体重写”的门：不通过。** |
```

卡 §7.3 也把 E85-2 标成 `⚠️`，§8 明确“按 R85-1 记为**门不通过**”。但收口记录写成
“E85-1…8 通过”：

```console
$ grep -n "E85-2" docs/design/phase85.md
76:| E85-2 | spike 报告含行数、编译耗时、测试语料逐字节一致原始输出、sharp edge 清单；门通过 |
148:| E85-2 | … | ⚠️ 结构等价通过；整子系统新语法重写门**不通过**（未覆盖），按 R85-1 退化，见 §8 |
$ grep -n "E85-1…8 通过" AGENTS.md docs/history/phase-log.md
AGENTS.md:508:> 2026-11-21：PH-85 → v0.85.0（`d=0`）；… E85-1…8 通过。
docs/history/phase-log.md:187:| v0.85.0 | … E85-1…8 通过；… |
```

R85-1 只说“不通过则退化”，并**没有**把 E85-2 的“门通过”改写成通过；它授权的是
PH-86 走逐项替换，不是让收口记录把 E85-2 记成 ✅。

## 期望（二选一，由 EDITOR 签收）

1. **降级口径（推荐，最小）**：签一条 decision，明确 E85-2 的验收 = “spike 已执行 +
   行数/耗时/逐字节/sharp edges + 明确门结论”，整子系统新语法重写按 R85-1 移交
   PH-86 的 per-function 切片；卡 §7.3、AGENTS、phase-log 三处统一写成
   “E85-2 结构等价通过；整体重写门不通过，按 R85-1 降级”，不得写“E85-1…8 通过”。
2. **字面口径**：补一次真正的“完整新语法等价重写”（至少一个完整子系统，含 `Str` 视图/
   `?`/`defer`/`match` 中适用的部分），以 66 语料逐字节、自举不动点、ASan 证明；
   由于词法器的 sharp edge（`Str` 视图波及 Parser/Expr/Stmt、无错误通道），这实质是
   PH-86 的工作量，应放在 PH-86 卡而不是回填 PH-85。

## 验收

- decision 入库（`signer` + `date`），或补做证据入库；
- `docs/design/phase85.md` §7.3/§8、`AGENTS.md` 0.3、`docs/history/phase-log.md` 三处口径一致；
- 不改 E85-1…E85-8 的编号与 `tasks`/`version-minor`（`g8-phase-freeze`）；
- `check-docs` 与 `bash tools/check.sh g8` 绿。

## 关联

- [PH-85 卡](../../docs/design/phase85.md) §1.3、§7.3、§8
- [p85_spike.md](../../docs/design/p85_spike.md) §4
- [v1-release-plan §2.6](../../docs/planning/v1-release-plan.md)
- [REV 复核](../../docs/reviews/2026-11-21-phase85-rev-verdict.md) §3

## DEV 处置（2026-11-21）

已修（deviation 口径，最小补做）：

- 新增 [D-018](../../docs/decisions/D-018.md)，`签收：EDITOR 2026-11-21`；裁定 E85-2 =
  “spike 已执行 + 度量/逐字节/sharp edge + 明确门结论”，整子系统新语法重写按 R85-1
  移交 PH-86 的 per-function 切片。
- 卡 §7.3（E85-2 行）、卡 §8 第 1 行、`AGENTS.md`（0.3 dev 日志与“当前阶段”）、
  `docs/history/phase-log.md`、`docs/roadmap.md`、`docs/session-map.md` 六处统一为
  “**E85-2 有条件通过（D-018）**，其余 E85 通过”；不再有“E85-1…8 全部无条件通过”。
- E85 编号与 `tasks`/`version-minor` 未动；版本仍 0.85.0（未发布，重写未推历史）。

验证：`python3 test/docs/check-docs.py` 绿（见 DOC-81 的归档输出）；`bash tools/check.sh g8` 绿。
