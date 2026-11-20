# battle/leak-guards-1 反对席（REVIEW）

- 立场：**B — 复用宽键 `strict = on`；L3 至少降级为「未释放清单」进 PH-82；豁免用属性式；直接环默认 error**。
- 理由：配置键越少越好；作者责任在 box 落地后风险变高；注释豁免容易被 refactor 丢掉。

## E1 — 现有 leak 告警只覆盖裸指针/own

```console
$ sed -n '6p' test/modules/leak/prog.ct
    S *p = malloc(sizeof(struct S));
```

`--debug-leaks` 尚未实现；把它当现有基础设施来扩展，会低估 L3 成本。

## E2 — 锚点（含不利于己方）

- 有利于 B：[language-spec.md:2540](../../docs/language-spec.md#L2540)（`ct check` 的 strict 已把 warning 升 error）；
  [Diag.h.ct:281](../../selfhost/ct-ast/tool/diag/Diag.h.ct#L281)（severity 由 strict 统一决定）。
- **不利于己方**：[package-guide.md:89](../../docs/package-guide.md#L89) 没有 `strict` 键，只有 `c-boundary` 的值；
  宽键需要新造语义，并非「零新机制」。

## E3 — 可证伪预测

若 B 成立，复用 strict 不需要新增配置解析；但一旦要区分「只升泄漏」与「升全部诊断」，宽键就必须再造子键。
若注释豁免在现有 lexer 中不可达，B 的属性式也只能等属性语法，无法在 PH-82 落地。

## E4 — 代价

- B 的 L3 清单：需要 side table 记录分配点；debug-only 可接受，但「未释放」无法区分环与长生命周期对象。
- 注释豁免：零语法成本；属性式：CT 目前没有属性语法，等于为豁免单开语法。

## E5 — 对 A 最强论点的 steelman

A 最强：不枚举根就不能可靠区分环，L3 按现稿不成立。
回应：承认不能叫「环检测」，但「未释放句柄清单」仍有价值；可降级保留，不必完全砍掉。
