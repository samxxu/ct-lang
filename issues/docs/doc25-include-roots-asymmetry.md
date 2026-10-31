# DOC-25 · README 称 `-I` 两模式均限 16，compile 实际无上限

| 项 | 值 |
| --- | --- |
| 模块 | docs |
| 严重度 | Medium |
| 锚点 | commit `f4c77b1`（2026-10-31，`v0.13.0`） |
| 文件 | [README.md](../../README.md#L60)（中文）、[README.md](../../README.md#L507)（英文） |
| 状态 | 待修 |

## 现象

CLI 表写：

```text
`ctc … -I <dir>` | 追加一个导入搜索根（可重复，最多 16 个；Phase 2，`compile` 与 `build` 均可用）
```

两个模式的上限并不相同：`build` 受 `MAX_INCDIRS 16` 约束，`compile` 没有该上限。

## 证据（探针）

```bash
# compile：30 个 -I 根
$ /tmp/a/ct-ast -I d1 … -I d30 in.ct -o out.c ; echo $?
0

# build：第 17 个根
$ /tmp/a/ct-ast build -I d1 … -I d17 in.ct -o out ; echo $?
ctc: too many -I roots
1
```

实现位置：

- build：[Module.h.ct](../../selfhost/ct-ast/frontend/module/Module.h.ct#L38) `#define MAX_INCDIRS 16`，
  解析分支在 `build_main` 里检查并报 `ctc: too many -I roots`；
- compile：另一套解析器（见 [SH-24](../selfhost/cli-parser-duplication.md)），**接受 `-I` 但直接忽略**
  （`Driver.h.ct:144` 注释为 `accepted for CLI parity; compile mode resolves no imports`），
  既不设上限、也不参与解析。因此「compile 接受 30 个」只说明它不报错，不代表该开关生效。

## 影响

- 文档给了一个两种模式都不成立的中性描述：build 用户会以为 compile 也限 16，compile 用户会以为
  build 也能无限追加。
- 与 [SH-24](../selfhost/cli-parser-duplication.md) 同源：两套解析器导致同一条开关在两个模式下语义分叉。

## 修复建议

先决定口径（建议 compile/build 都限 16，或都去掉上限），再改文档：
`-I` 的说明按模式分别写，或统一后在 `MAX_INCDIRS` 与 compile 解析器上落地同一个上限。
无论选哪侧，都要在 `check-ast.sh` 里加一条第 17 个根报错的断言（见
[TEST-10](../testing/test10-build-cli-errors-untested.md)）。

## 验证

修复后两模式的探针结果与文档一致；`bash selfhost/check-all.sh` 九关全绿。

## 处理（2026-10-31）

已修复：README 按模式分别说明 `-I`（`build` 限 16；`compile` 接受但不解析导入）。未合并两套解析器，见 SH-24 的处置。
