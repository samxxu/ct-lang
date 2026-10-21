# DOC-18 · language-spec §4.8 仍把「struct 类型的数组字段」列为不支持，与 §6 及实际行为相反

| 项 | 值 |
| --- | --- |
| 模块 | docs |
| 严重度 | **Medium** |
| 锚点 | commit `6d764bc`（2026-10-21） |
| 文件 | [docs/language-spec.md:333](../../docs/language-spec.md#L333)、[:880-882](../../docs/language-spec.md#L880-L882)、[:450-454](../../docs/language-spec.md#L450-L454)、[:1024-1025](../../docs/language-spec.md#L1024-L1025)、[docs/roadmap.md:743](../../docs/roadmap.md#L743)、[test/acceptance/run.sh:436-439](../../test/acceptance/run.sh#L436-L439) |
| 状态 | ⬜ 未修复 |

## 现象

同一份规范里对**同一构造**给出相反结论：

- §4.8（中文 333 行、英文 880-882 行）的「仍不支持」清单写着：**struct 类型的数组字段**
  （`struct Duo { Num ab[2]; }`），并注明「见 roadmap 的 `p18` 探针，**按决定延后**」。
- §6（中文 450-454 行、英文 1020-1027 行）写着：**ct-ast 已放宽**，「结构体类型的**数组字段**逐元素
  写 vptr（`Num ab[2]` 的元素可直接派发）」。

另一条旁证也停在旧结论：roadmap 743 行仍称「唯一 PENDING 是 `p18`」，而同一文档 885 行已写
「`p18_struct_array_field` 晋升 `test/acceptance/run.sh` 基线」；`test/acceptance/run.sh:436-439`
的注释还写着「p18 stays PENDING on purpose」。

## 证据

同一份 `p18` 输入（`test/acceptance/run.sh:419` 的探针）分别交给两个编译器
（锚点 `6d764bc`，`/tmp/ctissue2`）：

| 编译器 | 结果 |
| --- | --- |
| ct-ast（安装入口） | 生成 → `cc -Wall -Wextra` 零警告 → 运行输出 `3`（PASS） |
| L2（回归 oracle） | `cc` 报 `error: no member named 'eval' in 'struct Num'`（元素上的派发没被改写） |

`test/acceptance/run.sh` 的 `BASELINE`（第 92 行）**已含** `p18_struct_array_field`，整套
`check-all.sh` 报 `20 pass, 0 pending, 0 regression`——即对该文档的主体读者（用安装入口 ct-ast 的人）
这条能力是**可用**的。

## 影响

读者按 §4.8 会以为「struct 类型的数组字段」不可用而绕开它；同时 §4.8 与 §6 的相反结论会让人怀疑
规范整体的可信度。§4.8 那段其实是以 **L2** 为主语写的（「**CT 侧（L2）已扩展**」），L2 确实仍不支持——
问题是它没有像 §6 那样**按编译器分述**，也没有说 ct-ast 已支持。

## 修复建议

1. §4.8 的「仍不支持」清单（中英两处）改为显式限定：`L0 / L2 仍不支持 …；ct-ast 已支持（见 §6）`，
   并删除「见 roadmap 的 `p18` 探针，按决定延后」这句——`p18` 已晋升基线。
2. roadmap 743 行「唯一 PENDING 是 `p18`」按现状改写（p18 已入基线，0 pending）。
3. `test/acceptance/run.sh:436-439` 的「stays PENDING on purpose」注释删除或改为「L2 仍不支持、
   ct-ast 已支持，故 p18 以 ct-ast 为默认目标」。

## 验证

- 中英两处 §4.8 不再出现无编译器限定的「仍不支持 struct 类型的数组字段」。
- 全仓 `grep -n "p18"` 只剩「已晋升基线」这一种口径。
- 文档改动不触发 golden 重生成：`bash selfhost/check-all.sh` 仍须 8 关全绿。
