# DOC-47 · `docs/memory-guide.md` 整篇以「SH-33 未修 + delete 不置空」为前提，现已过期

| 项 | 值 |
| --- | --- |
| 严重度 | Medium（该文档正是写给用户照做的操作指南，错误结论会直接导致错误写法） |
| 锚点 | commit `8b047f5`（2026-11-01）+ 工作树在途改动 |
| 文件 | [memory-guide.md:63-76](../../docs/memory-guide.md#L63-L76)、[:107](../../docs/memory-guide.md#L107)、[:457](../../docs/memory-guide.md#L457)、[:646-652](../../docs/memory-guide.md#L646-L652)、[:692](../../docs/memory-guide.md#L692)、[:1048](../../docs/memory-guide.md#L1048) |
| 状态 | 已修（2026-11-01）：`docs/memory-guide.md` 中英 10 处基于旧 AutoDrop 行为的表述已改正，并标注 v0.16.0 现状 |

## 现象

本文件写于 SH-33 修复之前，六处以「缺陷仍在」为事实：

| 行 | 现文 | 现状 |
| --- | --- | --- |
| :63 | 「AutoDrop **只在行首 `}` 注入**，**不在 `return` 前注入**，且**不置空**」 | 三条全部不成立（`test/ast/61_autodrop_return` 钉住新行为） |
| :64-71 | 用「顶层 `own` + `return` 会静默泄漏」举反例，并给出「把 `own` 放进块内」的规避规矩 | 该缺陷已修；规矩可以保留为风格建议，但不能再说成必需 |
| :107 | 「**`delete` 不置空**。`p` 之后是悬空指针」 | 已置空 |
| :457 | 决策表「delete（记得它不置空）」 | 同上 |
| :646-652 / :692 | 英文版同一段落 | 同上 |
| :1048 | 英文决策表「delete (it does not null)」 | 同上 |

另外 §13「建议写进团队规约的七条」第 1 条仍写「顶层 `own` 在 SH-33 修复前禁用」，
§12 的「还剩的是」清单也把「函数顶层 `own` 遇 `return` 不释放」列为现存缺陷。

## 证据

```text
$ ./ct-ast m1.ct -o m1.c && sed -n '/^int pick/,/^}/p' m1.c
int pick(int c) {
    struct Box * b = malloc(sizeof(struct Box));
    b->n = c;
    if (c) {
        if (b) { Box_Drop_drop(b); free(b); b = 0; }
        return 1;
    }
    printf("using\n");
    if (b) { Box_Drop_drop(b); free(b); b = 0; }
    return 0;
}
$ ./m1
drop 1
1
using
drop 0
0
```

## 建议

- 删除 §2 的 SH-33 告警框，改为「出口释放与置空已在两条路径上成立」；
- `delete` 的两处结论改为「会置空」，并把「`delete p; p = 0;`」从陷阱清单里降级为「历史写法」；
- §12 / §13 里把 SH-33 相关条目移出「现存缺陷」；
- 若想保留「把 `own` 放块内」的风格建议，明确标注为风格而非约束。

## 关联

- [SH-33](../selfhost/sh33-autodrop-return-no-inject.md)（已修，本文件的依据）
- [DOC-45](doc45-tutorial-memory-delete-null.md)、[DOC-46](doc46-readme-transform-table-stale.md)（同批漂移）
