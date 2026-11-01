# DOC-35 · `test/README.md` 的探针区间与负例计数过期（01..56 / 56-of-68）

| 项 | 值 |
| --- | --- |
| 模块 | docs / testing（测试地图） |
| 严重度 | Medium |
| 锚点 | commit `524ba99`（2026-10-31） |
| 文件 | [test/README.md:7](../../test/README.md#L7)、[:17](../../test/README.md#L17)、[:35](../../test/README.md#L35)、[:45](../../test/README.md#L45) |
| 状态 | 已修（2026-10-31）：文档已按建议更新（见 [issues/README.md](../README.md) 的 2026-10-31 处置表） |

## 现象

- 第 7 / 35 行：「`ast/errors/` … 其中多数（**当前 68 个中的 56 个**）另把消息文本钉死」
- 第 17 / 45 行：「行为探针 **`01..56`**（逐批增长，以目录数为准）」

实际：探针 **58** 个（`01..58_trait_all_default`），`ast/errors/` 负例 **72** 个，
并且 **72 个全部钉死了消息文本**（不是「多数」）。「以目录数为准」的提示仍在，但前面写死的区间与比例会误导读者。

## 证据

```text
$ ls -d test/ast/*/ | grep -v errors | wc -l
58
$ ls -d test/ast/*/ | grep -v errors | tail -1
test/ast/58_trait_all_default/
$ ls test/ast/errors/*.ct | wc -l
72
```

钉死口径：`check-ast.sh` 的 `"<fixture>|<message>"` 循环覆盖 63 个；
其余 9 个（`fnptr_nested`、`fnptr_array_param`、`integer_suffix_lll`、`integer_suffix_uu`、
`map_no_instance`、`map_partial`、`ns_host_direct`、`ns_host_no_map`、`null_vtable_slot`）
各有独立的 `grep -q "<message>"`，合计 72/72。

## 建议

改为「58 个探针」「72 个负例，全部钉死消息文本」，或删掉具体数字只保留「以目录数为准」；
中英同步。若保留比例，建议写成「当前全部钉死」并注明校验方式，避免下一次批次再漂。
