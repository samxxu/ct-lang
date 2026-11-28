# REVIEW 现状评估：可立即开展的三项工作（2026-11-28）

| 项 | 值 |
| --- | --- |
| 基线 | `8866f987` |
| 日期 | 2026-11-28 |
| 席位 | REVIEW |
| 范围 | 只读核对；不改代码、不改 issues、不签实现证据 |
| 结论 | **D-032/E-V3-10 证据已齐，可出正式评审结论；TEST-27 可收口复核；E-V3-9b 不能按“clean”直接签，需 REQ 先裁定残余口径。** |

## 0. 一句话结论

现在不应继续泛泛“等下一片”，有三件评审工作可以立即做：

1. **D-032/E-V3-10**：实现、正负例、计数和门禁都已可复跑，只差正式评审结论；
2. **TEST-27/E-V3-9c**：矩阵和 card 已写“通过”，issue 仍 `open`，需要复核后转 `verified` 或打回；
3. **E-V3-9b**：card 写“待 REVIEW 签字”，但 dogfooding §3.8 只记到 R1/R2，最终 R3–R8 计数与生成 C 可读性未形成闭环；需先决定“条件通过 + 保留 SH-123”还是继续补。

## 1. D-032 / E-V3-10：证据已齐，可出正式结论

设计已 [accepted](../decisions/D-032.md)（`bdc505fe`），实现提交在 main：

| 片 | 提交 | 内容 |
| --- | --- | --- |
| M1 | `feb6caa5` | 包根解析 + 两处 `ct.pkg` |
| M2 | `981f2ee9` | selfhost include-only shim 66 → 3 |
| M3 | `653dec09` | lib/core include-only shim 8 → 0 |

本轮只读实测：

```console
$ bash test/ast/p65_policy.sh /tmp/ct-rev
OK p65/policy

$ /tmp/ct-rev --show-c-boundary selfhost/ct-ast/main.ct
allow
$ /tmp/ct-rev --show-c-boundary lib/core/Vec.h.ct
allow
$ /tmp/ct-rev --show-c-boundary lib/core/utf16/U16Str.h.ct
allow
$ /tmp/ct-rev --show-c-boundary examples/50_ref_out/prog.ct
strict

$ find selfhost/ct-ast -name '*.shim.h' | wc -l
3
$ find lib/core -name '*.shim.h' | wc -l
0
$ find bootstrap/ct-ast -name '*.shim.h' | wc -l
3
```

门禁：

```console
check-seed: OK (73 .c + 75 .h, two rebuild rounds byte-identical, hand-edit negative red)
check-goldens-ast: 25/25
check-warnings: 622 ok, 0 failed
check-all: OK (8 hard gates green)
check-docs: OK (3528 links, 466 files, v1.2.0)
```

`p65/policy` 自身覆盖了包根正例、`lib/core/utf16` 子树、包外 allow 不影响、子包 `strict` 最近者优先和 `leaks` 对齐；因此 D-032 §6 的正负例不依赖人工删 manifest。

**评审判断：E-V3-10 实现证据成立，可写正式结论。**  
建议把本节的原始输出写进 D-032 §6 证据附录或单独 review 文件；不需要再让 DEV 补实现。

## 2. E-V3-9b：不能按“clean”直接签

card §6 仍写：

```text
E-V3-9b | 实现完成（待 REVIEW 签字） | ... | 剩余：生成 C 可读性 REVIEW 签字未签
```

但实际材料有三处不一致：

1. `dogfooding.md` §3.7 的 REV 签字是 **2026-11-28 早段**，只覆盖当时的生成 C；它早于 S8B-REM-1 R3–R8。
2. `dogfooding.md` §3.8 只记了 R1/R2 收官（`snprintf` 308 → 289），没有把 R3–R8 后的最终计数写进同一节。
3. card §6 的最终计数是：

```text
snprintf 292（Pkg 43 / Symbols 24）；realloc 87
```

实测确认这三个数字正确：

```console
snprintf all: 292
Pkg: 43
Symbols: 24
realloc: 87
```

但生成 C 仍存在可读性残余：

```text
bootstrap/ct-ast/Intern.c     >120 字符行 0
bootstrap/ct-ast/Symbols.c    >120 字符行 76
bootstrap/ct-ast/EmitExpr.c   >120 字符行 171
```

`SH-123` 仍是 `open`，题目就是“Symbols/EmitExpr 超 120，D2/D3 未清零”。E-V3-9b 的判据是“生成 C 可读性 REVIEW 签字”，不是“行数归零”；但不能把当前状态写成“无残留”。

**建议 REQ 二选一：**

- **A（条件通过）**：REV 只在明确“机械对等 ≠ 已降级、SH-123 继续保留”的前提下签 E-V3-9b，并在 dogfooding §3.8 补最终 R3–R8 计数；
- **B（暂不签）**：要求 DEV 先把最终 R3–R8 计数与生成 C 抽查补进 §3.8，REQ 再裁定 SH-123 是否允许随 1.2 保留；在此之前 card 不能写 E-V3-9b 通过。

我不建议把 E-V3-9b 直接改成“通过”而保留旧 §3.7 签字，因为那份签字早于最终 R3–R8。

## 3. TEST-27：矩阵已“收口版”，issue 仍 open

当前状态：

- [feature-examples-matrix](../planning/feature-examples-matrix.md) 已标“S8c 收口版（2026-11-28；B-5/B-7 补齐）”，25 行；
- card §6 的 E-V3-9c 已写“通过”：E3 26 迁 21、保留 5 个有理由例外；LANG-30 `lang30_print` 7/7；snippets 12 sources；
- [TEST-27](../../issues/testing/test27-feature-examples-pointer-free.md) 仍是 `open`，§8.5 还留着 H1/H2/H3/H4 的“部分”行。

需要 REV 做一次独立收口：

- 抽查矩阵 25 行无 `missing`；
- 确认 E3 的 5 个例外有逐条理由；
- 确认 README 12 个 `// source:` 与 snippet 编译/运行；
- 结论二选一：`verified`（通过），或列出仍缺的行并 `reopened`。

这是 REVIEW 自己的账，不需要 DEV 新代码，适合现在做。

## 4. 台账已过期，需顺手同步

| 文件 | 过期点 | 建议 |
| --- | --- | --- |
| [signoff package](2026-11-28-signoff-package.md) | §2 仍写“待签：只有 D-032” | D-032 已 `accepted`；改成“已签”并补实施复核索引 |
| [s10-closeout](../phases/v1-PH-2/s10-closeout.md) | G-2 仍写 E-V3-9b 待签 | 等 §2 结论后同步；不要提前写“通过” |
| [card §6](../phases/v1-PH-2/card.md) | E-V3-9b “实现完成待签字”与 §3.7 已有签字并存 | 按 §2 的 A/B 方案统一 |

## 5. 现在不宜由 REVIEW 开展

- **D-031**：待 ARCH 技术审定、EDITOR 终签，REVIEW 不是终签席位；
- **D-034 / I2**：ADR 尚未立，等 ARCH/EDITOR；
- **S8B R3–R8**：DEV 已完成；只剩 E-V3-9b 评审签字（见 §2）；
- **VSCode 迁移报告**：此前约定“到时候一起写”，不阻塞 1.2，可排在本轮之后。

## 6. 建议顺序

1. **D-032/E-V3-10**：把 §1 证据写成正式评审结论（无争议，最快闭环）；
2. **TEST-27**：做一次矩阵/snippet/E3 例外复核，决定 `verified` 或 `reopened`；
3. **E-V3-9b**：REQ 在 A/B 中裁定；若选 A，REV 在 dogfooding §3.8 补最终计数与“保留 SH-123”的边界；
4. 同步 signoff package / s10-closeout，再考虑 VSCode 报告。

> 本报告只读评估；没有修改代码、issues、seed 或版本号。
