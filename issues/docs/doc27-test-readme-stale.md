# DOC-27 · `test/README.md` 的层图与负例约定过期（01..18、缺 patterns、include 路径错误）

| 项 | 值 |
| --- | --- |
| 模块 | docs |
| 严重度 | Medium |
| 锚点 | commit `f4c77b1`（2026-10-31，`v0.13.0`） |
| 文件 | [test/README.md:12](../../test/README.md#L12)、[:17](../../test/README.md#L17)、[:44](../../test/README.md#L44)、[:6](../../test/README.md#L6)、[:33](../../test/README.md#L33)、表格 [:9-19](../../test/README.md#L9-L19) |
| 状态 | 已修复（2026-10-31 落地；2026-11-10 复核：`test/README.md` 中英均含 `patterns/` 行与动态计数口径） |

## 现象

`test/README.md` 是测试树的权威地图，但有四处与现状不符：

| 位置 | 文档说 | 实测 |
| --- | --- | --- |
| [:12](../../test/README.md#L12) | 单测「直接 `include selfhost/ctc.c`」 | 实际是 [`test/unit/test_helpers.c:13`](../../test/unit/test_helpers.c#L13) 的 `#include "../../selfhost/l0/ctc.c"` |
| [:17](../../test/README.md#L17)、[:44](../../test/README.md#L44) | `ast/` 为 `01..18` 行为探针 | 实有 **56** 个探针目录（`01_hello` … `56_header_compat`）+ `errors/` |
| [:6](../../test/README.md#L6)、[:33](../../test/README.md#L33) | `ast/errors/` 是裸 `.ct`，`check-ast.sh` **只断言退出码**（无期望文本） | 68 个夹具中 **56 个**的消息文本被 `check-ast.sh` 的 `"fixture\|message"` 循环钉死；只有 12 个仅断言位置（见 [TEST-8](../testing/test8-negative-messages-not-pinned.md)） |
| 表格 [:9-19](../../test/README.md#L9-L19) | 无 `test/patterns/` | 实有 6 个模式目录（`composite` / `decorator` / `factory_method` / `observer` / `strategy` / `template_method`），由 [check-ast.sh](../../selfhost/check-ast.sh) batch 35 段驱动 |

## 证据

```bash
$ ls test/ast | wc -l          # 56 个探针 + errors
57
$ ls test/patterns
composite decorator factory_method observer strategy template_method
$ grep -c 'ast/errors' selfhost/check-ast.sh   # 通用循环 + pair 循环并存
```

## 影响

`test/README.md` 被 [README §5](../../README.md#L259) 与各设计文档引用为测试层级的唯一说明。地图少写 38 个
探针目录、漏掉一个顶层测试目录、把「文本断言」说成「只断言退出码」，会让新维护者低估负例强度，
也容易在清点覆盖度时按错误的约定重复或漏计（参见 [TEST-13](../testing/test13-missing-method-duplicate.md)）。

## 修复建议

- 把 include 路径写成 `../../selfhost/l0/ctc.c`。
- `ast/` 的行改为「`01..56` 行为探针（逐批增长）」并说明计数以目录数为准，不再写死区间。
- 负例约定改为：「`ast/errors/` 裸 `.ct`；56 个由 `check-ast.sh` 钉死消息文本，其余仅断言位置」。
- 表格补 `patterns/` 行（层级：CT 线；形状：6 个设计模式 `prog.ct` + `expected.out`；驱动：`check-ast.sh`）。
- 中英两份同步。

## 验证

修复后 `ls test/ast | wc -l`、`ls test/patterns` 与文档一致；`grep -n "01..18" test/README.md` 无命中；
`bash selfhost/check-all.sh` 九关全绿。

## 处理（2026-10-31）

已修复：`test/README.md` 中英同步（include 路径、`01..56`、文本断言比例、`patterns/` 行）。
