# DOC-84 · 新特性最小 example（ref/out、slice、box/new、match）

| 项 | 值 |
| --- | --- |
| 模块 | examples / docs |
| 定性 | 文档/样例缺口（P2，非 v1-PH-0 门禁） |
| 严重度 | Low |
| 锚点 | v0.88.0（2026-11-21） |
| 依据 | [v0.88.0 评审](../../docs/reviews/full-review-v0.88.0.md) §6、P2-9 |
| 状态 | **待办（DEV/docs；v1.0 前建议）** |

## 现象

PH-78 之后没有新增 example：`ref`/`out`、切片 `T[]`、`String`/`Str`、`box`/`new`、
leaks、`match`/ADT、`ct index verify` 只有 spec/tutorial/测试，没有可运行示例目录。
教程已更新到 §21，但缺少“最小可跑”的 `examples/5x_*`。

## 期望

新增 4 个 example（每个 20–40 行，带 expected）：

| 目录 | 内容 |
| --- | --- |
| `examples/5x_ref_out` | `ref` / `out` 参数与调用点写法；对比 C 的 `int *out` |
| `examples/5x_slice` | `T[]` 切片、子切片、`sum(int[] a)` |
| `examples/5x_box_new` | `box<T>` / `new`、`at()` 借用、`release()` 失效 |
| `examples/5x_match_adt` | 最小 ADT + 穷尽 `match`；owning payload 显式释放 |

## 验收

- 每个 example 可编译、零告警、运行输出与 expected 一致；
- 接入既有 example/门禁入口（不新建平行 runner）；
- 不引入未实现能力；与 spec/tutorial 的写法一致；
- 不改产品代码。

## 非目标

- 不覆盖全部新特性（`ct index verify` 属包管理 example，另议）；
- 不写长教程（tutorial 已有章节）；
- 不阻塞 v1-PH-0。

## 关联

- [v1-readiness-1 判决](../../battle/v1-readiness-1/verdict.md)（P2，非门禁）
- [tutorial.md](../../docs/tutorial.md) §18/§20/§21
