# battle/s2-scope-1 反对席（REVIEW）

- 立场：**B — PH-78 只做自由函数；方法/trait 另立 phase**。
- 理由：方法/trait 的发射路径、trait 默认体、impl 签名匹配都未验证；同相会把首卡拉大，
  且 S2b 失败会阻塞整个 PH-78 收口。

## E1 — 原型只覆盖自由函数

```console
$ grep -n "S2b\|方法/trait" /tmp/ct-refout/evidence/ref_out/EVIDENCE.md | head -4
（无输出：原型与证据只覆盖普通函数）
```

## E2 — 锚点（含不利于己方）

- 有利于 B：[phase78.md:49](../../docs/design/phase78.md#L49)（S2b 是方法/trait，入口是 S2a 收口）；
  [phase78.md:69](../../docs/design/phase78.md#L69)（E78-6 把方法/trait 纳入收口）。
- **不利于己方**：[phase78.md:48-50](../../docs/design/phase78.md#L48-L50) 已经按 stage 拆分，
  S2a 可以先独立红绿；B 的“拖大”不是必然。

## E3 — 可证伪预测

若 B 成立，方法/trait 需要独立的参数存储/发射分支，无法复用 S2a 的 `pann`/`(*name)`/`&`；
若实测只需补入口，B 的“新机制”论据失败。

## E4 — 代价

B 要新增一个 phase，并把 PH-79–81、v0.79–0.81、D-011/roadmap/AGENTS 全部顺延；
A 只在一个 phase 内多一个 stage。

## E5 — 对 A 最强论点的 steelman

A 最强：同一语言规则、只 bump 一次、卡面已分 stage。
回应：同相仍会让 PH-78 的收口依赖 S2b；若 S2b 长期未做，首卡无法关闭，B 的独立收口更干净。
