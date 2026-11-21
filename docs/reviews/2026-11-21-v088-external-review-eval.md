# v0.88.0 外部评审与惯用优先级卡评估（2026-11-21）

> 对象：附件 `ct-v088-review-report.md` 与 `ct-idiom-priority-card.md`（只读；本文只评估，不直接改附件）。
> 口径：以仓库 v0.88.0（`5605eb6c`）与 `ct v0.88.0` 实测为准；外部报告未运行编译器，
> 其探针类结论按仓库自述证据复核。

## 1. 评审报告：接受 / 修正 / 待核实

| 报告项 | 结论 | 复核 |
| --- | --- | --- |
| §1 PH-85–88 证据链可信 | **接受** | 与 phase-log、p88_metrics、battle 记录一致 |
| §1 `MAX_FUNCS` 475/512、余 37 | **修正** | 实测 **501/512、余 11**（[p88_metrics](../history/p88_metrics.md) §4 #3；PH-88 N-1） |
| §2 D1 README 首行“ct check 只做受限语义检查”过时 | **不接受为事实错误** | 该句仍准确：`ct check` 做受限语义检查，`--types` 是可选子集（spec §4.53）；最多加一句“`--types` opt-in” |
| §2 D1 能力清单缺五项、示例旧风格 | **接受（编辑项）** | 属门面重写，不是事实错误；转 [DOC-86](../../issues/docs/doc-86-readme-v088-rewrite.md) |
| §2 D2 README §0.1 基线 0.44.1 | **接受（待重测）** | 与 SH-73 绑定；转 DOC-86 |
| §2 D3 tutorial 联动 | **接受（编辑项）** | 与 D1 同批；DOC-86 |
| §2 D4 patterns “语言没有动态容器” | **接受（事实错误）** | [patterns.md:64](../patterns.md#L64) 与内建 `Vec`/`Map` 冲突；本轮已修 |
| §2 D5 package-guide 标签 | **接受** | 两处标签滞后；本轮已修 |
| §2 D6 memory-guide 缺范围声明 | **已解决** | 本轮已在 [memory-guide.md:5-7](../memory-guide.md#L5-L7) 加“新代码先读 guide / 本文是逃生层”声明 |
| §2 D7 spec 拆分 | **接受为 v1.1 决策** | 转 [DOC-88](../../issues/docs/doc-88-spec-split-decision.md)，不在 v1-PH-0 内做 |
| §2/§4 A1 `lib/std → lib/core` “所有者已定” | **待核实** | 仓库只有 2026-11-15 的 [同名核查](../review/builtin-layer-vs-std-package-name-check.md)（兼容方案），没有 ADR/所有者签字；转 [DOC-87](../../issues/docs/doc-87-lib-core-rename.md)，签字前不动 |
| §4 A3 SH-73 裁定冲突 | **接受为冲突事实** | issue 仍写 Info/有意边界；报告称所有者裁定 bug；需所有者最终拍板；已在 [SH-73](../../issues/selfhost/sh73-temp-receiver-dynamic-dispatch.md) 加待裁注记 |
| §5 “SH-104 goldens 静态化、SH-105 J-6 台账” | **修正（对调）** | 实际 V1-C1 = SH-104 J-6 台账，V1-C2 = SH-105 goldens 静态化（[v1-release-plan:64-65](../planning/v1-release-plan.md#L64-L65)） |
| §5 v1-PH-0 就绪度 | **接受** | 与 [battle/v1-readiness-1](../../battle/v1-readiness-1/verdict.md) 的 Tier 1/Tier 2 一致 |
| §6 对外部速览的 4 处修正 | **接受** | ref/out trivial 可未初始化、`T a[] = {}` 保留、ADT 限定名/花括号/`_` 末位、box 16 字节，均与 spec/实测一致 |

## 2. 惯用优先级卡：逐条事实核查

**结论：方向正确，但不能按原稿入 `docs/idioms.md`；需先修以下硬伤。**

| 卡片位置 | 原文 | 判定 | 依据 |
| --- | --- | --- | --- |
| 开头 | “CT 是 C 的超集” | **删/改** | DOC-76：v1.0 起不再是 C 超集；应写“CT 是 C 风格的语言，但兼容承诺已收窄” |
| §1 指针 | “指针只出现在 shim、MMIO、extern 边界” | **改** | 指针在任何 `.ct` 都合法；应写“主要在 shim/硬件/逃生层，应用层先想 Str/切片/box” |
| §2 字符串字面量 | `"42".to_int()` | **补前提** | 需 `import std::str::String;`（std 包 `map trait CStrOps for type char *`）；内置层不自动带 |
| §2 借用存储 | “借用类型不能存（字段/容器/全局 = 硬错）” | **改** | struct 字段 / `Map` 键硬错；`Vec<Str>`、`Option<Str>`、ADT 负载可编译（存的是视图） |
| §3 借用 | “返回局部视图 = 硬错” | **改** | `Str` 逃逸当前无 lint（SH-106）；`T[]` 切片是 `slice escape` warning，不是硬错 |
| §3 释放 | “String/box/Vec/Map = owning，自动释放” | **改** | 局部/参数自动；字段/全局/ADT payload 无自动 Drop；环仍泄漏 |
| §2 遍历 | `foreach (v) { i, item }` | **改** | 语法是 `foreach (v) { … item … }`；`Vec`/`Map` 额外有只读 `i`；数组没有 `i` |
| §2 `$name` | “物化中间值用 `$name`” | **保留** | spec §4.11.3；`a.m()$x.n()` 正确 |
| §2 SH-73 | “动态派发路径暂不支持一行链” | **保留但补例** | 静态宿主链（examples/47）可跑；只有接口值动态派发链被拒 |
| 附录 briefing | 重复上述错误 | **同步修** | 尤其 “不能存”“硬错”“超集”“to_int 无 import” |

其余条目（`box`/`new`、切片、`Result`+`?`、`errdefer`、`defer`、`enum`/`match`、`cstr()`、
`T[]` 传参）与 spec/实测一致，可保留。

## 3. 建议落点

1. **先修 SH-73**：所有者二选一（修流水线 vs 记为 1.0 后特性）；README §0.1 的措辞依赖它。
2. **D4/D5 已落**；D6 已由本轮 guide 入库解决；D7/D8 转 v1.1/待核实 issue。
3. **惯用卡**：按 §2 修正后作为 `docs/idioms.md`，与 D1 README 大改同批；从
   `docs/README.md` 与 `llm-guide.md` 的读者路径引入。修正清单见
   [DOC-85](../../issues/docs/doc-85-idiom-priority-card.md)。
4. **编辑器**：已补 v0.88 语法（ref/out、box/new、String/Str、切片、ADT/match、`?`、`$name`），
   版本 `0.6.1`，`check-grammar` 179/0。

## 4. 证据

```console
$ grep -n '501' docs/history/p88_metrics.md | head -2
64:| 3 | ... 425 → 501 | ... 501/512 |
$ grep -n 'V1-C1\|V1-C2' docs/planning/v1-release-plan.md
64:| V1-C1 | J-6 全量证据台账 ... [SH-104]
65:| V1-C2 | goldens 静态化 ... [SH-105]
$ grep -n 'lib/core' docs issues battle AGENTS.md
（仅 docs/review/builtin-layer-vs-std-package-name-check.md 的兼容建议，无 ADR）
$ python3 editors/vscode/test/check-grammar.py | tail -1
== 179 checks, 0 failed ==
```

## 5. 不做

- 不改附件原文；不按“所有者已定”直接执行 `lib/core` 改名（无签字）；
- 不在本评估内决定 SH-73（所有者拍板）；
- 不把惯用卡原稿直接入 `docs/`。
