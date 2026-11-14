# PH-46–52 施工手册（给外部实现方）

> **本仓库只维护规格、计划与验收判据；实现由外部 DeepSeek harness 执行。**
> 本手册是施工入口；所有裁定以 [裁决记录](../reviews/phase46-52-freeze-verdict.md) 为准，卡片是判据载体。
> 基线：本手册最后一次提交。开工前用**干净克隆**；不要复用带未提交改动的工作树。

---

## 1 施工顺序与理由

```text
PH-46 ──► PH-47 ──► PH-50
  │
PH-48 ──► PH-49
  │
PH-51 ──► PH-52
```

| 顺序 | 理由 |
| --- | --- |
| 46 → 47 → 50 | 同一份 `Map` 生成物与 `lib/std/Vec.h.ct`；47 依赖 46 的条目归属，50 依赖 47 的 `Str` 键比较 |
| 48 → 49 | 49 的 AutoDrop 要调 48 的真实 Drop 体 |
| 51 → 52 | 52 的连写验收依赖 51；两者都动 `Expr.h.ct` |
| 46 与 48 | 可并行**开发**（只在发射器重叠），**门禁必须串行** |
| 47 的 `Map<Str,用户 struct>` | 以 46 收口为条件；否则该夹具改用指针元素 |

**先派 PH-46**：最小、无设计分歧、是 47 的硬前置（`≤120` 行）。

---

## 2 每张卡的入口条件与出口证据

| 卡 | 入口条件 | 出口证据（必须贴原文） |
| --- | --- | --- |
| 46 | 干净克隆；四形态基线快照已存 `/tmp` | `p46` build/单文件 stdout `cmp` rc=0；四形态产物 `cmp`；`nm` 新增符号 = 0；`check-all` 末行 |
| 47 | 46 收口提交；`Map` 两份既有特化基线快照 | `p47_str_key` 输出；`p47_release` 计数；既有 `Map` 产物 `cmp`；两条负例命中 |
| 48 | 干净克隆（可并行 46） | `p48_ptr_field_glue` / `p48_cross_unit_drop` stdout `cmp`；`p48_errors` L48-2；`grep` 无 `&_self->` |
| 49 | 48 收口提交 | 分配/Drop 计数相等；`p49_own_null` 计数 0；三条负例；既有 own 产物 `cmp` |
| 50 | 47 收口提交 | `p50_vec_has` / `p50_map_has` 四项全真；32 例 `cmp`；`p50_str_has`；双释放 ASAN 无报告 |
| 51 | 干净克隆；S0 用量清单 | 选型 A：rc=1 不落 `.c`；B：生成 C 实参为 `p`；`grep` 无 `(&p`；A 的 E51-3 |
| 52 | 51 收口提交 | `p52_read/write/generic` 输出 `cmp`；九条负例表；C 透传 `cmp`；self-hosting fixpoint |

> 每张卡的完整判据见 `docs/design/phase4N.md` §6；本表只列「必须贴什么」。

---

## 3 每张卡要跑的门禁

| 时机 | 命令 | 判据 |
| --- | --- | --- |
| 每片提交前 | `bash selfhost/check-ast.sh` | 末行 `0 failed` |
| 改 `lib/std` 的卡（47/50） | `bash selfhost/check-goldens.sh` | rc=0，fixpoint 段通过 |
| 改发射器的卡（46/48/51） | `bash selfhost/check-warnings.sh` | `0 failed` |
| 涉及内存的卡（47/48/49/50） | `bash selfhost/check-sanitizers.sh` | rc=0（**`detect_leaks=0`，不报泄漏**） |
| 收口 | `bash selfhost/check-all.sh` | 末行 `check-all: OK (11 hard gates green)` |
| 文档改动 | `python3 test/docs/check-docs.py` | rc=0 |

**sanitizer 的能力边界**：脚本关闭泄漏检测；禁止用「sanitizer 通过」代替泄漏判据。
泄漏用**显式释放计数**（47/49/50）或编译期分析（`check-warnings.sh`）证明。

---

## 4 禁止事项

1. 不改 `selfhost/l0/ctc.c`、`selfhost/l1/**`、`selfhost/l2/**`（冻结层）。
2. 不手改 `*.expected.*` / golden；只能由编译器重生成，并逐字节核对。
3. 不降级判据：warning 不算通过、`skip` 不算覆盖、删负例不算修好。
4. 不改门禁条数、`CTC_VERSION`（版本移动只在收口提交内）、判据宽度。
5. 不用 `git add -A` / `git add .`；只用显式路径；遇 `.git/index.lock` 等 3–5 秒重试，最多 5 次，不删他人的锁。
6. 不 push、不打 tag；不改 `docs/language-spec.md` 本相独占句之外的内容（文档线在改）。
7. 不实现本卡范围外的「顺手修复」；缺陷按计划 §11 的绕法处理并在报告注明编号。

---

## 5 怎么证明这一相做完了

按顺序贴五样，缺一不算完成：

1. **红证**：`test(...)` 提交为实现的父提交；正文含 `baseline: <sha>` 与原始失败输出（T-7）。
2. **绿证**：本卡 §6 每条判据的命令原文 + 退出码 + 关键 stdout/stderr。
3. **产物对比**：`/tmp` 基线与收口后产物 `cmp` 的输出（零 diff 或逐条解释）。
4. **门禁**：`check-all.sh` 末行 + 11 道各自末行原文；`check-docs` 末行。
5. **回归声明**：`git diff --stat <baseline>..HEAD` + 「未改冻结层 / 未手改 golden / 未改门禁」三句确认。

**不许**用「已完成」「基本可用」「无回归」这类形容词代替上述证据。

---

## 6 需要先停下来的情况

| 情况 | 动作 |
| --- | --- |
| S0 发现既有用法与选型冲突（如 PH-51 计数 > 0） | 停，报本仓库；不得自行改判 |
| 判据要求的门禁面不存在（脚本/夹具缺失） | 停，报本仓库补判据；不得自行换判据 |
| 与文档线在 `language-spec.md` 同一行冲突 | 停，按句切片并报冲突行号 |
| 需要改冻结层才能通过 | 停，报本仓库；不得改冻结层 |

---

## 7 待用户裁定项

见 [裁决记录 §4](../reviews/phase46-52-freeze-verdict.md)：PH-52 去留、Drop 符号可见性、
键所有权、版本节奏、`?.` 是否重设计。**这 5 条未定前，对应卡只能做 S0 与共用切片**：

| 卡 | 未定时的可做部分 |
| --- | --- |
| 46 / 48 / 49 | 不受阻；48 的符号可见性默认按 U-2 A 实施，若改判只需回滚 S3 |
| 47 | 按 U-3 A（深拷贝、删 `put_owned`）实施；改判会改 `MapEntry` 布局，须停 |
| 50 | 不受 U 项影响（出参已废） |
| 51 | 不受阻；选型 A 默认 |
| 52 | 按 U-1 A（只主张字符串键）实施；若改判为撤回，停 |
