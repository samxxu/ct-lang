# Phase 46 — `Map` 元素完整性（`Map<K, 用户 struct>` 在 `ct build` 下可编译）

> **状态：规划中**（草案，待评审；未立项；本轮只写卡，不改代码）
> **基线**：HEAD `ff1b9140`（`ct-ast v0.44.1`）；工作树含另一条线的未提交改动，本卡不碰。
> **依赖**：无硬前置；基线取 PH-45 收口提交（见 [phase45.md](phase45.md)），两相不并发跑门禁。
> **规模**：编译器 80–160；夹具 50–100；文档 20–40；合计 **150–280**（±40%）。
> **版本**：收口 bump `v0.46.0`（五处 `CTC_VERSION` + 两处 README + 受影响 golden 重生成）；tag / push 需用户单独授权。
> **纪律**：不改 `Map` API、不改 `MapEntry` 字段布局、不改键规则（键归 [phase47.md](phase47.md)）、不碰 `Vec` 生成物。

## 0 背景与缺口

**事实（v0.44.1 实测，来源 [ct-json-capability-blockers.md](../proposals/ct-json-capability-blockers.md) J-1 / [language-capability-gaps.md](../proposals/language-capability-gaps.md) C-4）**：

| 形态 | 单文件 `ct x.ct` | `ct build` |
| --- | --- | --- |
| `Vec<JsonRef>` | 通过 | 通过（实例在单元内） |
| `Map<char *, JsonRef *>` | 通过 | 通过 |
| `Map<char *, void *>` | 通过 | 通过 |
| `Map<char *, JsonRef>` | 通过 | **失败** |

```text
.ctbuild/Vec.h:31:20: error: field has incomplete type 'struct JsonRef'
```

根因：`MapEntry<K, V>` 的 `value` 字段按值写进**共享头**，而该头不 include 元素定义所在的单元；
`Vec` 的实例已经能留到单元内解决，`Map` 的条目结构没跟上。**单文件模式通过**，所以包方在探针上验不出来。

**代码锚点（行号以 S0 复核为准）**：

| 主题 | 位置 |
| --- | --- |
| `MapEntry` 命名（`struct MapEntry_<enc>`） | `selfhost/ct-ast/frontend/parse/Stmt.h.ct:940-960` |
| 模板实例的单元归属（`via_hdr` 判定） | `selfhost/ct-ast/backend/emit/Emitter.h.ct:1597-1618` |
| 导出模板实例的归属 | `Emitter.h.ct:1699-1718` |
| `MapEntry` 声明 | `lib/std/Vec.h.ct:47-50` |
| `ct_build` 的共享头 | `.ctbuild/Vec.h`（生成物） |

## 1 目标 / 非目标

### 1.1 目标

| 编号 | 内容 |
| --- | --- |
| O1 | `Map<char *, UserStruct>` 在 `ct build` 下可编译、可 `put` / `get` / `remove` / `foreach` / `release`，运行结果与单文件模式一致 |
| O2 | `MapEntry_<K>_<V>` 的 `value` 字段在**使用它的翻译单元**里是完整类型：条目结构下沉到实例化单元，或共享头补上元素定义单元的头 |
| O3 | 四种既有形态产物逐字不变：`Vec<UserStruct>`、`Map<char *, UserStruct *>`、`Map<char *, void *>`、`Map<char *, int>` |
| O4 | `--lib` 导出面不回归：含 `Map<char *, UserStruct>` 字段的 `.h.ct` 仍可 `ct build --lib` |

### 1.2 非目标

| 不做 | 归属 |
| --- | --- |
| 键类型白名单、键比较、键所有权 | [phase47.md](phase47.md) |
| `Map` API 形态与 `MapEntry` 字段布局变更 | 本卡不动；布局变更会破坏既有 golden 与 `from` 结构体字面量 |
| 跨单元 Drop 与指针字段胶水 | [phase48.md](phase48.md) |
| 容器元素「必须是完整类型」的新限制条款 | 不引入；这是发射归属问题，不是语言限制 |

## 2 设计决定

| 编号 | 决定 | 为什么不用另一种 |
| --- | --- | --- |
| **D46-1** | 只改发射位置/可见性，不改 `MapEntry` 字段、不改 `Map` 方法体 | 改布局会连带 `from`/`foreach` 与全部 `Map` golden，收益为零 |
| **D46-2** | 首选「条目结构下沉到实例化单元」；仅当 S0 证明与 `--lib` 共享头契约冲突时，才改用「共享头补 `#include` 元素定义单元」 | 下沉与 `Vec` 的既有做法一致，不需要在共享头里追依赖；补 include 会把用户单元的头拉进生成头，扩大 `--lib` 面 |
| **D46-3** | 不新增诊断；本相消除的是 `cc` 侧错误 | 发空桩/放行的不是本相要修的面 |
| **D46-4** | 受影响的 golden 只能重生成后逐字节核对，禁止手改 | 仓库红线：手改 `*.expected.*` 视为失败 |

## 3 诊断

无新增用户可见诊断。内部不变式（由夹具断言，不作为文案交付）：

- `MapEntry_<K>_<V>` 在其出现的每个 `.c` 中都可见完整 `V`；
- 同一实例不得在两个单元各发一份可见定义（`static` 或唯一定义点）。

## 4 任务切分

| 切片 | 内容 | 边界 |
| --- | --- | --- |
| **S0** | 只读核查：复现 `j10b`、定位 `MapEntry` 发射与 `via_hdr` 归属、对照 `Vec` 做法、确认 `--lib` 影响；记 `baseline: <sha>` | 不产提交 |
| **S1** | 红证：`test/ast/p46_map_struct/`（build 模式，`Map<char *, JsonRef>` 入 `.h.ct`）+ 运行断言，先跑出 `incomplete type` | 只含夹具，提交正文带 `baseline:` 与原始输出 |
| **S2** | 发射修正：按 D46-2 选定方案落地；≤3 文件、≤150 行 | 不动 `Map` 方法体 |
| **S3** | 回归夹具：四种对照形态 + `foreach` / `remove` / `from` + 单文件与 build 双模式；golden 重生成 | 只含夹具与 golden |
| **S4** | 文档：容器章节的「元素完整性」一句；spec 由文档线占用时记 `blocked-by: docs-correction` | 不改其他章节 |
| **S5** | 收口：`check-all.sh` 11 道全绿、bump `0.46.0` | 收口 |

依赖：S0 → S1 → S2 → S3 → S4 → S5；每片 ≤150 行、≤3 文件，仓库随时可构建。

## 5 完成定义（四件套）

| 面 | 交付 |
| --- | --- |
| 实现 | `Map<char *, UserStruct>` 在 build 模式可编译运行；无 TODO、无「暂不支持」分支 |
| 诊断 | 无新诊断；不变式由夹具锁死（重复定义、缺失完整类型各一条负向断言） |
| 文档 | 容器章节写明条目结构的使用单元可见性；`docs/package-guide.md` 一句使用提示 |
| 门禁 | 新夹具进 `check-ast.sh`；`check-goldens` 绿；`check-all.sh` 11 道全绿；红证按 T-7 提交 |

## 6 验收

| ID | 断言 | 命令 / 阈值 |
| --- | --- | --- |
| **E46-1** | build 模式 `Map<char *, JsonRef>` 可编译并运行，输出与单文件模式一致 | `p46_map_struct` 运行输出逐字相等 |
| **E46-2** | 四种对照形态 rc=0，产物逐字不变 | `check-goldens` 82/82（数量以收口实测为准），diff 为空 |
| **E46-3** | `--lib` 场景：含该字段的 `.h.ct` 可导出，`nm -g` 面与第 39 相口径一致 | `p46_lib_export` rc=0 |
| **E46-4** | 同一实例不出现两份可见定义 | `grep -c 'struct MapEntry_'` 按预期 = 1 |
| **E46-5** | 零回归：`check-warnings` 无新增告警；`check-ast` 全绿 | 收口贴原始末行 |
| **E46-6** | 红证链完整：`test(...)` 提交是实现提交的父提交，正文含 `baseline: <sha>` 与原始输出 | `git log --oneline -2` |

## 7 风险与不做项

| 编号 | 风险 / 不做项 | 触发信号 | 处置 |
| --- | --- | --- | --- |
| R46-1 | 条目结构下沉后两个单元各发一份，`cc` 报重复定义 | 目标文件出现两份 `MapEntry_*` | 固定唯一定义点；`static` 或按单元归属二选一，S0 冻结 |
| R46-2 | 改发射归属导致大面积 golden 漂移 | `check-goldens` 红且 diff 面大 | 逐字节核对后重生成，提交正文写原因 |
| R46-3 | 与 PH-47 同改 `Map` 生成物 | 两相并行时冲突 | 串行：47 在 46 收口后开工 |
| R46-4 | `--lib` 头面回归（PH-39 的 `.abi.h` 与 `visibility`） | 导出工程构建失败 | E46-3 锁死；不改 `.abi.h` 生成规则 |
| R46-5 | 单文件模式行为被顺手改动 | 单文件 golden 变化 | 单文件路径不在本相改动面；变化即停 |
