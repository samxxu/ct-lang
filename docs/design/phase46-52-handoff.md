> **历史文档**：本文的 L0/L1/L2 构建链已在 SH-119（v1.1）退役；命令仅作历史记录。

# v0-PH-46–52 施工手册（给外部实现方）

> **2026-11-15 更新：v0-PH-46–52 已全部收口；本手册保留为历史施工入口。当前施工相为 v0-PH-53，
> 入口见 [phase53.md](../phases/v0-PH-53/card.md)。**
>
> **本仓库只维护规格、计划与验收判据；实现由外部 DeepSeek harness 执行。**
> 本手册是施工入口；所有裁定以 [裁决记录](../reviews/phase46-52-freeze-verdict.md) 为准，卡片是判据载体。
> 基线：本手册最后一次提交。开工前用**干净克隆**；不要复用带未提交改动的工作树。

---

## 1 施工顺序与理由

```text
已完成：v0-PH-45-S1 ──► v0-PH-45-S2 ──► v0-PH-46 ──► v0-PH-47 ──► v0-PH-48 ──► v0-PH-49
        ──► v0-PH-50 ──► v0-PH-51 ──► v0-PH-52
下一刀：v0-PH-53（可选链，见 phase53.md）
```

| 顺序 | 理由 |
| --- | --- |
| 45-S1 → 45-S2 | S1 只加 `ncl_stack == 0` 前置；S2 才动 `chk_assignable`，两刀不共享代码路径，可分别验收回滚 |
| 45 → 46 | v0-PH-45 已由用户 2026-11-15 直接签字立案，排在本波之前；46 的基线取 45 收口提交 |
| 46 → 47 → 50 | 同一份 `Map` 生成物与 `lib/std/Vec.h.ct`；47 依赖 46 的条目归属，50 依赖 47 的 `Str` 键比较 |
| 48 → 49 | 49 的 AutoDrop 要调 48 的真实 Drop 体 |
| 51 → 52 | 52 的连写验收依赖 51；两者都动 `Expr.h.ct` |
| 46 与 48 | 可并行**开发**（只在发射器重叠），**门禁必须串行** |
| 47 的 `Map<Str,用户 struct>` | 以 46 收口为条件；否则该夹具改用指针元素 |

**v0-PH-45–49 均已收口**（`v0.45.0`–`v0.49.0`）；**当时下一刀是 v0-PH-50**（已收口）；
当前施工相为 [v0-PH-53](../phases/v0-PH-53/card.md)。
v0-PH-45 不属于本波，判据在 [phase45.md](../phases/v0-PH-45/card.md) §4/§6，已完成部分只留作复核。

### 1.1 v0-PH-45 两刀的交接面（已完成，留作记录）

| 项 | 45-S1 闭包 `return` 跳过 | 45-S2 指针四位置判据 |
| --- | --- | --- |
| 入口条件 | 干净克隆；`CT_STD_DIR=<repo>/lib/std`；先存 `examples/18` 的 `--types` 失败原文（rc=1，两条） | S1 收口提交；先存 209/210 `check_only/struct_ptr.ct` 的 rc=0 现状与四位置探针 |
| 出口证据 | `Stmt.h.ct:1996-2002` / `:2038-2060` 前置 `ncl_stack == 0`；42/42 examples `--types` 全绿；闭包 `return err:;` 漏判变硬错 | `Expr.h.ct:6281` 短路替换；四位置负例 4/4、层数 1/1；`check-ast.sh` 三处硬编码同步 |
| 门禁 | `check-ast.sh` 末行 `0 failed`；`check --types` 42/42 | `check-ast.sh` + `check-warnings.sh` 均 `0 failed`；`check-all` 11 道全绿 |
| 禁止事项 | 不做闭包返回类型推断（phase43 §0.2）；不改 `parse_closure` / `ret_type` | 不新建第二个兼容内核；不动 `void *`/裸 `0`/typedef/数组/闭包/fnptr 跳过面；不手改 golden |

---

## 2 每张卡的入口条件与出口证据

> 下表 45-S1 至 49 行均已收口（`v0.45.0`–`v0.49.0`），行内判据仅作复核记录，不再派工；
> 下一张待派的是 **v0-PH-50**。

| 卡 | 入口条件 | 出口证据（必须贴原文） |
| --- | --- | --- |
| 45-S1 | 干净克隆；`CT_STD_DIR` 已设；`examples/18` 失败原文已存 `/tmp/p45-base/` | `--types` 42/42；`examples/18` rc=0 输出为空；闭包 `return err:;` 负例命中 `an error return needs a value` |
| 45-S2 | S1 收口提交；209/210 现状与四位置探针已存 | 四位置负例 4/4；`u = a` 三入口 rc=1；`check-ast.sh` 末行 `0 failed`；golden 快照 `cmp` |
| 46 | 干净克隆；四形态基线快照已存 `/tmp` | `p46` build/单文件 stdout `cmp` rc=0；四形态产物 `cmp`；`nm` 新增符号 = 0；`check-all` 末行 |
| 47（已完成 v0.47.0） | 46 收口提交；`Map` 两份既有特化基线快照 | `p47_str_key` 输出；`p47_release` 计数；既有 `Map` 产物 `cmp`；两条负例命中 |
| 48（已完成 v0.48.0） | 干净克隆（可并行 46） | `p48_ptr_field_glue` / `p48_cross_unit_drop` stdout `cmp`；`p48_errors` L48-2；`grep` 无 `&_self->` |
| 49（已完成 v0.49.0） | 48 收口提交 | 分配/Drop 计数相等；`p49_own_null` 计数 0；三条负例；既有 own 产物 `cmp` |
| 50 | 47 收口提交 | `p50_vec_has` / `p50_map_has` 四项全真；32 例 `cmp`；`p50_str_has`；双释放 ASAN 无报告 |
| 51 | 干净克隆；S0 用量清单 | 选型 A：rc=1 不落 `.c`；B：生成 C 实参为 `p`；`grep` 无 `(&p`；A 的 E51-3 |
| 52 | 51 收口提交 | `p52_read/write/generic` 输出 `cmp`；九条负例表；C 透传 `cmp`；self-hosting fixpoint |

> 每张卡的完整判据见 `docs/design/phase4N.md` §6；本表只列「必须贴什么」。

---

## 3 每张卡要跑的门禁

| 时机 | 命令 | 判据 |
| --- | --- | --- |
| 45-S1 每片（已完成） | `for f in examples/*/*.ct; do ct-ast check --types "$f"; done` | 42/42 rc=0；`examples/18` 输出为空 |
| 45-S2 每片（已完成） | `bash selfhost/check-ast.sh && bash selfhost/check-warnings.sh` | 两份末行均 `0 failed` |
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
8. v0-PH-45 两刀（已收口）不得越界：S1 只加 `ncl_stack == 0` 前置，不做闭包返回类型推断；S2 只替换 `:6281`
   的指针短路，不新建第二个兼容内核、不改 `void *`/裸 `0`/typedef/数组/闭包/fnptr 的跳过面。

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
| S0 发现既有用法与选型冲突（如 v0-PH-51 计数 > 0） | 停，报本仓库；不得自行改判 |
| 判据要求的门禁面不存在（脚本/夹具缺失） | 停，报本仓库补判据；不得自行换判据 |
| 与文档线在 `language-spec.md` 同一行冲突 | 停，按句切片并报冲突行号 |
| 需要改冻结层才能通过 | 停，报本仓库；不得改冻结层 |

---

## 7 已签字裁决项与执行口径

[裁决记录 §4](../reviews/phase46-52-freeze-verdict.md) 的 5 条已于 **2026-11-15 按建议值签字**（U-1…U-5 均 A），
施工按下列口径执行；改判须由本仓库另行签字，实现方不得自行变更：

| 卡 | 执行口径 |
| --- | --- |
| 46（已完成 v0.46.0）/ 48 / 49 | 46 已收口；48 不受阻，符号可见性按 U-2 A（单独一档）实施 |
| 47（已完成 v0.47.0） | 已按 U-3 A（深拷贝、删 `put_owned`）收口 |
| 48（已完成 v0.48.0） | 已按 U-2 A（Drop 符号单独一档）收口；指针字段不再取地址 |
| 49（已完成 v0.49.0） | 已收口；AutoDrop 走 48 的真实 Drop 体 |
| 50 | 不受 U 项影响（出参形态已废弃） |
| 51 | 按 U-5 默认 A（泛型实例硬错）；若 S0 计数 > 0，停并报本仓库改判 |
| 52 | 按 U-1 A（只主张单层字符串键）实施；`v[0]` 的参数类型匹配属 [REQ-JSACCESS-1](../planning/requirements-pool.md)，不占相号、不得砍掉 |

---

## 8 errata（2026-11-15）

- **v0-PH-45–49 已收口**：`v0.45.0`–`v0.49.0`，五个 annotated tag 已推送。
  §1.1 的两刀交接面、§2 的 45-S1/45-S2/46/47/48/49 行、§3 的 45 门禁指令均转为历史记录，不再派工。
- **当时下一刀：v0-PH-50**（容器取用契约，已收口）；当前施工相为 [v0-PH-53](../phases/v0-PH-53/card.md)。
- **流程缺口（登记，不补造）**：45–49 五个 release 提交无 T-7 红证父提交，正文写 `red: n/a（版本收口）`；
  详见 [计划 §13.1](phase46-52-plan.md)。不得事后补造红证，后续相须先红后绿。
- 本 errata 只改陈述，不改任何卡的 §6 判据。
