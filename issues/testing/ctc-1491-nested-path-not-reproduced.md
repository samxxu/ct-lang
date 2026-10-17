# TEST-3 · `ctc.c:1491`（nested field path too long）探针未复现，文档却称不可达

| 项 | 值 |
| --- | --- |
| 模块 | testing |
| 严重度 | **Low** |
| 锚点 | commit `8aac450`（2026-10-17） |
| 站点 | `ctc.c:1463` / `ctc.c:1491`（nested field path too long） |
| 状态 | 已修复（commit `b6b3dc4`，改记为「探针未复现」） |

## 现象

architecture.md L150 把 `put_heap_vpts` 版的 `nested field path too long`（L1491）列为「不可达」，理由是「只查一跳，长度必小于缓冲」。审查中我构造深链字段访问探针，**未能复现**该 `die`（`exit=0`）。

## 证据

- 探针：构造多层嵌套字段的取值/初始化链，`./ctc` 返回 `exit=0`，未命中 `nested field path too long`。
- 但「未复现」**不等于「不可达」**：很可能是我构造的链长度不足以越过缓冲（容量常量见 `ctc.c` 头部 `MAX_*`），也可能是文档的论证成立。

## 影响

- 若确为防御点：文档判断正确，仅缺一条「探针证据」的记录。
- 若实为可达：则与 [TEST-1/TEST-2] 同类——可达且无 fixture。

## 修复建议

二选一，务必留下证据：

1. 用一个**刻意加长**的嵌套字段链（逼近 `MAX_NAME` / 缓冲容量）重跑探针，确认能否命中；命中则补负例，未命中则在 architecture.md 注明「探针未复现（非证明不可达）」。
2. 读 `ctc.c:1463/1491` 所在函数的容量计算，给出「必不可能越界」的一行论证（skill §4 允许「命名前置守卫的 one-line argument」）。

## 验证

无论哪种结论，都要有一条可复现命令或一行论证随附，且与 architecture.md 表述一致。
