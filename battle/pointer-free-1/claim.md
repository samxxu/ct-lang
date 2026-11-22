# battle/pointer-free-1 主张席（REQ）

- 主张：**现在受理**《指针退场》提案，按 S1–S5 分期进入 v1 之前的语言层；
  目标不是禁止指针，而是把日常场景收进句柄/值类型。
- 立场边界：不否认 v1.0 冻结条款；主张「冻结之前仍有一次语言层窗口」，若用户选择 v1.0
  先冻结，则本主张自动失效并转为 v2。

## E1 — 现行机制已验证句柄路线

```console
$ grep -n "refs\|retain\|release" lib/std/Vec.h.ct | head -4
29:   `release` frees the data and the header once the count reaches zero; a second
30:   release on the same handle is a hard error, not a silent no-op (D29-12). */
32:    int refs;
50:   `put` and released with its entry (D47-3'). */
$ grep -n "语言在 v1.0 冻结" docs/planning/v1-release-plan.md
23:- 语言在 v1.0 冻结，后续只做兼容性修复/明确版本化变更。
```

`Vec<T>` 已经证明引用计数 + 借用视图 + 失效检测可在 CT 上零新运行时工作；`box<T>` 是同一
协议的单个元素形态，不是从零发明。S2/S4 还分别复用 PH-70 的 CFG 与 PH-75 的闭包实参，
所以「机制最小化」不是空话。

## E2 — 锚点（含不利于己方）

- 有利于 A：[Vec.h.ct:29-32](../../lib/core/Vec.h.ct#L29-L32)（refs/release 既有协议）；
  [battle/pointer-free-1/proposal.md:47](battle/pointer-free-1/proposal.md#L47-L66)（box 与 Vec 同构）；
  [battle/pointer-free-1/proposal.md:161](battle/pointer-free-1/proposal.md#L161-L166)（S2/S4 复用既有能力）。
- **不利于己方**：[v1-release-plan.md:23](../../docs/planning/v1-release-plan.md#L23)
  明确 v1.0 冻结语言；[Str.h.ct:18](../../lib/core/Str.h.ct#L18) 说明 `Str` 是 std 包类型，
  不是编译器内建——这两点直接抬高 A 的落地门槛。

## E3 — 可证伪预测

若「现在受理」成立，则：

1. S1 的两周原型应能在**不改现有语法**的前提下同时通过 J-1 与 J-5（box 的生成 C 与
   `Vec` 同构、旧 golden 不变）；
2. `Str` 一等化若最后做，应能用 `c-boundary: allow` 覆盖迁移，不要求 649 个含字面量的
   测试文件逐一手改。

任一条被实测否定，A 的「现在受理」即失败；若两条都成立，B 的「必须退回 v2」即失败。

## E4 — 代价量化

- S1 `box` + `new`、S2 `ref/out`、S3 切片、S4 函子、S5 `Str`，每项都是独立 phase 级；
- 编译器侧至少 parser、typecheck、emitter、symbol 四处改动；std 侧另有 Wave 2 资源句柄化；
- 语料侧：含字符串字面量的 `.ct` 文件 649 个、含 `char *` 的 494 处；
- 估算 6–9 个月，换来 v2 之前完成语言形态切换；若等 v1 后再做，需要 MAJOR 级迁移窗口。

## E5 — 对 B 最强论点的 steelman

B 最强的是：**v1.0 冻结 + `Str` ABI + 现有语法冲突**。A 的回应只能是「把 S5 推迟到 v2、
只先做 S1–S4」；但一旦接受这个收缩，A 就不再是「整体受理」，而接近 B 的「拆分/延后」。
A 承认：若不接受收缩，B 的版本窗口论成立。
