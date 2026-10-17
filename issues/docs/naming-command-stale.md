# DOC-7 · 命名类文档仍写「当前命令 `ctc`」，与 Phase 7 矛盾

| 项 | 值 |
| --- | --- |
| 模块 | docs |
| 严重度 | **Medium** |
| 锚点 | commit `ec97f99`（2026-10-17） |
| 文件 | [README.md](../../README.md#L8)、[AGENTS.md](../../AGENTS.md#L17)、[AGENTS.md](../../AGENTS.md#L146) |
| 状态 | ✅ 已修复（2026-10-18） |

## 现象

三处仍把 `ctc` 写成当前/唯一命令：

- README L8：「编译器命令叫 **`ctc`**（ct compiler，好比 `tinycc` 仓库发布的命令是 `tcc`）」
- AGENTS L17 §1：「项目/语言 `ct`……**当前命令 `ctc`**」
- AGENTS L146 §7：「禁止把项目名 `ct`、**当前命令 `ctc`** 或后缀 `.ct` 改成……」

## 证据

同一份文档的后续句子已经写明 Phase 7 落地：

- README L61：「命令的最终形态是单入口 `ct`（`ctc` 保留为兼容别名）。**Phase 7.1–7.3 已落地**」
- AGENTS L17 同一单元格后半段：「Phase 7.1–7.3 已落地——L2 二进制名为 `ct` 时以 `ct` 身份运行」
- [roadmap.md](../../docs/roadmap.md) Phase 7 行：`✅ 完成（7.1–7.3 落地，bump 到 v0.7.0）`

即同一单元格内「当前命令 ctc」与「ct 已落地」自相矛盾。

## 影响

命令名是项目对外契约的第一句话；新读者会以为仍需用 `ctc`，或误判 Phase 7 未完成。

## 修复建议

统一表述为：

> 入口命令 `ct`；`ctc` 为兼容别名；L0 种子（`ctc.c` 编出的二进制）仍叫 `ctc`。

§7 的禁令句也应改为「当前入口命令 `ct`（`ctc` 为兼容别名）」。

## 验证

`grep -n "当前命令\|编译器命令叫" README.md AGENTS.md` 的结果中，不再出现「`ctc` 是当前命令」的表述。

## 处理（2026-10-18）

README 的命名段改为「入口命令 `ct`（`ctc` 为兼容别名，L0 种子编出的二进制仍叫 `ctc`）」；AGENTS §1 命名行与 §7 禁令句同步（中英各一处）。`grep -n "当前命令" AGENTS.md` 已无命中。
