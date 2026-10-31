# DOC-29 · batch 4 的 checklist 27 项全未勾，与其他 32 份不一致

| 项 | 值 |
| --- | --- |
| 模块 | docs |
| 严重度 | Low |
| 锚点 | commit `f4c77b1`（2026-10-31，`v0.13.0`） |
| 文件 | [docs/design/batch4-control/checklist.md](../../docs/design/batch4-control/checklist.md) |
| 状态 | 待修 |

## 现象

`docs/design/batch4-control/checklist.md` 的 27 项验收条目全部是 `- [ ]`，是 33 份 batch checklist 中
**唯一**一份没有勾选的；而 batch 4 早已落地（`switch` 见
[`test/ast/28_switch`](../../test/ast/28_switch)，`do` / `while` 见
[`test/ast/29_do_while`](../../test/ast/29_do_while)，负例在 `test/ast/errors/`）。

## 证据

```bash
$ grep -c -- "- \[ \]" docs/design/batch4-control/checklist.md
27
# 其余 32 份 batch* checklist 的未勾项合计为 0
```

## 影响

设计文档的状态与实际实现不一致：读者按 checklist 会认为 batch 4 尚未做完，进而重复实现或误判覆盖度。
影响面限于文档（功能与门禁不受影响），故定为 Low。

## 修复建议

按实际落地情况逐项勾选；若有确实未做的条目（例如只做了最小子集），保留未勾并加一行说明「本条未做，
原因 …」，不要整份照勾。

## 验证

逐项与 `check-ast.sh` 的 batch 4 段及 `test/ast/{28_switch,29_do_while}` 对照；勾选后该文件的未勾数与其他
batch 文档一致。

## 处理（2026-10-31）

已修复：27 项按实际落地勾选（`28_switch` / `29_do_while` 夹具与 6 条诊断均有门禁断言）。
