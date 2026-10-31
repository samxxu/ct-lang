# DOC-28 · `issues/README.md` 仍写 8 关、把已关闭的第二轮 8 条列为待修

| 项 | 值 |
| --- | --- |
| 模块 | docs |
| 严重度 | Medium |
| 锚点 | commit `f4c77b1`（2026-10-31，`v0.13.0`） |
| 文件 | [issues/README.md](../README.md)（状态行、硬关卡口径行、第二轮复审汇总行） |
| 状态 | 已修复（2026-10-31，与本轮审计同步） |

## 现象

`issues/README.md` 自身有三处状态/口径过期（下列为**修复前**的行号）：

| 位置 | 文档说 | 实际 |
| --- | --- | --- |
| 状态行 [:15](../README.md#L15) | 第二轮复审新增 8 条「**待修**」 | 同文件文末「处置」节已逐条记为关闭（SH-8 / SH-9 / SH-10 / SH-11 / SH-12 / DOC-19 / DOC-20 / DOC-21） |
| 硬关卡口径 [:17](../README.md#L17) | 现状以「**8** hard gates green」为准 | `selfhost/check-all.sh` 实跑**九关**并打印 `check-all: OK (9 hard gates green)`；同文件另两处也已写「九关」 |
| 第二轮汇总 [:104](../README.md#L104) | 再次把第二轮 8 条列为「待修」 | 同上，已关闭 |

## 证据

```bash
$ bash selfhost/check-all.sh | tail -2
check-all: OK (9 hard gates green)
$ grep -n "8 hard gates\|九关" issues/README.md
17:…现状一律以 check-all.sh 的「8 hard gates green」…
371:…九关全绿…
415:…九关全绿…
```

九关的构成见 [check-all.sh:72-80](../../selfhost/check-all.sh#L72-L80) 的 `run_gate` 序列：
`test/run.sh`、`check-goldens`、`check-archive`、`check-m2a`、`ct-tour`、`checkgrammar`、`test/pkg`、
`check-ast`、`check-warnings`。

## 影响

`issues/README.md` 是该目录的入口，读者会据此判断「哪些问题还没修」。把已关闭的 8 条当天待修、
把 9 关写成 8 关，都会造成重复劳动和错误的门禁基线认知。注意文件头已有
「历史段落保持原样」的约定：**历史验证记录里的「八道」应保留**，需要改的是「现状口径」那一条。

## 修复建议

- [硬关卡口径](../README.md#L17) 改为 9 关，并写清九关清单的出处。
- [状态行](../README.md#L15)、[第二轮汇总](../README.md#L104) 的「待修」改为「已关闭（见文末处置节）」。
- 本轮审计追加新章节（见 [reports/audit-2026-10-31](../../reports/audit-2026-10-31/audit-2026-10-31.md)）。

## 验证

`grep -n "8 hard gates" issues/README.md` 无命中；`bash selfhost/check-all.sh` 九关全绿。

## 处理（2026-10-31）

已随本轮审计同步修正：现状口径改为九关，第二轮的 8 条改为已关闭，并追加
「测试覆盖度与文档一致性审计（2026-10-31）」一节与新 issue 索引。

## 处理（2026-10-31）

复核确认已修复：九关口径与第二轮 8 条的关闭状态均已同步。
