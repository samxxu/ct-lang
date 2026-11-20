# battle/leak-guards-1 判决

> **状态：`closed`**（2026-11-20；裁判 EDITOR；1 轮 claim/counter/evidence）。
> **判决：A′ —— 窄键 `leaks = warn|error`；L3 从 PH-82 descope；注释豁免；直接环默认 warning、限深 3 条边。**
> `--debug-leaks` 维持 D-011 J-4c 的计数契约，不修订 ADR。

## 1 逐项判决

| J | 结论 | 依据 |
| --- | --- | --- |
| J-1 配置键 | **A** | `strict` 已是 `c-boundary` 的取值；新造 `leaks` 两档（`warn` / `error`），默认 `warn`，存量包不变（[package-guide.md:89](../../docs/package-guide.md#L89)） |
| J-2 L3 处置 | **A** | 句柄按值复制、无根注册；不能可靠区分环与长生命周期对象。`--debug-leaks` 只报计数（[D-011.md:33](../../docs/decisions/D-011.md#L33)、[phase81.md:64](../../docs/design/phase81.md#L64)） |
| J-3 豁免语法 | **A** | 用 `/* ct: allow-cycle */`，挂在 struct 声明行；`ct check` 报告 suppressed 点。属性语法不存在，不在本卡单开 |
| J-4 默认级别/限深 | **A** | 默认 warning；`leaks = error` 时升 error；仅 `box<X>` 字段、限深 3 条边。容器/泛型/接口/typedef 不计 |

## 2 方案 A′（冻结口径）

1. **键**：`leaks = warn|error`（缺省 `warn`）。`error` 同时升级现有 `potential leak` 诊断与本卡的直接环告警；`c-boundary` 语义不变。
2. **环检测**：只展开 `box<X>` 字段，相邻边计 1，限深 3；自环、A→B→A、A→B→C→A 命中；同一环只报一次。文案写「类型图存在环，实例可能泄漏，除非手工破环」，不写「会泄漏」。
3. **L3**：不进 PH-82；`--debug-leaks` 仍只报未配对 alloc/release 计数，不叫环检测。若未来要做「未释放句柄清单」，另立提案并先解决根注册；不得在 `--debug-leaks` 名下偷偷升级。
4. **豁免**：`/* ct: allow-cycle */` 必须与 `struct` 声明同一行；`ct check` 输出被抑制的环，便于审计。注释丢失后重新报 warning 是可接受代价。
5. **范围外**：`Vec<box<T>>`、泛型参数、接口字段、typedef、跨过程/跨单元间接环；不做 GC/weak/逃逸分析。

## 3 不采纳

- 宽键 `strict = on`：与 `c-boundary = strict` 语义撞车，且无法只升泄漏；
- L3 现稿「从根集标记可达」：根集不可枚举，结论不可靠；
- 属性式豁免：CT 无属性语法，成本高于收益；
- 直接环默认 error：合法的手工破环写法会被一刀切。

## 4 后续动作

- 建立 [phase82.md](../../docs/design/phase82.md)：L1 + L2 + L4，单卡 `v0.82.0`；
- 写入 [D-012](../../docs/decisions/D-012.md)；
- roadmap：Phase 82 行；v1.0 顺延到 PH-82 之后；
- 不改 `--debug-leaks`、不改 D-011 J-4c。
