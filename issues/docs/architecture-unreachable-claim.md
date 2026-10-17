# DOC-4 · architecture.md 断言 `die` 点「不可达」，其中 2 处实测可达

| 项 | 值 |
| --- | --- |
| 模块 | docs |
| 严重度 | **Medium** |
| 锚点 | commit `8aac450`（2026-10-17） |
| 文件 | [docs/architecture.md](../../docs/architecture.md#L150) L150 |
| 状态 | 已修复（commit `b6b3dc4`） |

## 现象

architecture.md L150 有一行表格项：

> 部分防御性 `die` 点不可达 | `expected struct name`（L1187）/ `expected '{' after struct`（L1189）/ … / `cannot create a temporary file`（L2837）/ `out of memory`（L158/L237） | **审计已逐个探针确认不可达**；按防御性检查接受，不补 fixture

## 证据（探针实测）

| 站点 | 探针 | 实测 | 结论 |
| --- | --- | --- | --- |
| `ctc.c:2837 cannot create a temporary file` | `TMPDIR=/nonexistent/zzz ./ctc ok.ct -o ok.c` | `ctc: cannot create a temporary file`，`exit=1` | **可达** |
| `ctc.c:2708 cannot read` | FIFO 作输入（`mkfifo`） | `ctc: cannot read '/tmp/fifo.ct'`，`exit=1` | **可达** |
| `ctc.c:1187/1189` | `struct Foo`（缺 `{`） | `exit=0` 原样透传 | 确为防御点（文档判断正确） |
| `ctc.c:158/237` OOM | — | 无法稳定构造 | 不可测 |

## 影响

文档声称「已逐个探针确认不可达」，但至少 2 处可达且**无 fixture 覆盖**，结论失真，会让读者以为这些分支无需测试（对应 [TEST-1](../testing/ctc-2837-tmpfile-not-covered.md)、[TEST-2](../testing/ctc-2708-cannot-read-not-covered.md)）。

## 修复建议

1. 把 L150 改为按站点分类的准确表述：真正防御（`1187/1189`）、可达待补（`2837`、`2708`）、不可测（`158/237`）。注意 macOS 的 `tmpfile()` 遵循 `$TMPDIR`，故 `2837` 在 macOS 上可触发。
2. 对可达的两处补负例（见对应 TEST issue）。

## 验证

改后逐站点重跑探针；文档描述与探针结论一一对应。
