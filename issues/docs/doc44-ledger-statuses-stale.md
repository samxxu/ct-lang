# DOC-44 · SH-25…SH-32 的修复已在工作树落地，8 个 issue 文件的「状态」仍写「待修」

| 项 | 值 |
| --- | --- |
| 严重度 | Medium（台账是「当前还剩什么」的唯一入口，错了会把已修条目当待办） |
| 锚点 | commit `8b047f5`（2026-11-01）+ 工作树在途改动 |
| 文件 | [issues/README.md:12-14](../README.md#L12-L14)、[sh25](../selfhost/sh25-typedef-alias-drops-dims.md)…[sh32](../selfhost/sh32-multi-input-silently-ignored.md) |
| 状态 | 已修（2026-11-01）：SH-25…SH-32 与 DOC-31…DOC-43 的状态行已回填，`issues/README.md` 顶部与本轮处置表同步 |

## 现象

`issues/README.md` 顶部已写「2026-10-31 代码审查新增 **21 条**（DOC-31…DOC-43、SH-25…SH-32），
**已于同日全部修复**」，但逐个文件的 `| 状态 |` 行全部仍是 `待修`：

```text
sh25-typedef-alias-drops-dims.md                       待修
sh26-assign-deref-uninit-type.md                       待修
sh27-struct-ahead-line-drift.md                        待修
sh28-own-in-braceless-branch.md                        待修
sh29-max-fields-silent-drop.md                         待修
sh30-emit-error-cleanup.md                             待修
sh31-emit-cond-dead-branches.md                        待修
sh32-multi-input-silently-ignored.md                   待修
sh33-autodrop-return-no-inject.md                      已修（2026-11-01）：…
```

八条其实都已落地（本轮逐条复核，见下表）。只有 SH-33 回填了。

| ID | 修复落点（本轮实测） |
| --- | --- |
| SH-25 | `Parser.h.ct` 别名复制补 `fields[].dims`；`typedef struct Tag { struct Inner items[2]; } Alias;` 编译并运行通过 |
| SH-26 | `Stmt.h.ct:1434` 补 `tt[0] = 0;`、`TypeCheck.h.ct:135` 补空类型早退；`*p = 1;` 正常 |
| SH-27 | `struct_def_ahead` 恢复 `line`/`tokline`/`tokstart`/`lstart`；重复成员报在 `:4:1` |
| SH-28 | `parse_branch` 合成块并 `autodrop_append`（[:946-975](../../selfhost/ct-ast/frontend/parse/Stmt.h.ct#L946-L975)）；探针 `test/ast/60_branch_autodrop` |
| SH-29 | `register_field` 两处越界改为 `too many fields in a record`；第 65 个字段实测报错 |
| SH-30 | `emit_unit` / `write_unit_header` 抽出 `*_body`，失败也 `fclose`；`Module.h.ct` 失败时 `remove()` 半截 `.h` |
| SH-31 | `emit_cond` 合并为单一 `N_BIN` 分支，`B_AND`/`B_OR`/`B_XOR` 可达 |
| SH-32 | `Driver.h.ct:189-192` 拒绝第二个位置参数：`ctc: compile mode takes one input; 'b.ct' is extra` |

## 建议

把 8 个文件的 `状态` 行改成「已修（日期 + 落点 + 探针）」，与 SH-33 的写法保持一致；
`issues/README.md` 的模块索引可加一列或在标题后标注 `✅`，避免只看表格时要逐个点开。

## 关联

- [DOC-31](../docs/doc31-tutorial-c-forms-unsupported.md)…[DOC-43](../docs/doc43-max-nodes-not-a-macro.md)：同批 13 条文档修复，`状态` 字段同样需要回填
