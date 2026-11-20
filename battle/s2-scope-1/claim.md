# battle/s2-scope-1 主张席（REQ）

- 主张：**A — 同一 phase 内 S2a 自由函数、S2b 方法/trait，两个 stage，只 bump 一次**。
- 理由：`ref/out` 是同一语言规则；方法/trait 只是同一规则的另两个发射位置，拆成两个 phase 会造成
  规则重复验收与版本位重排。

## E1 — 卡面已按 stage 拆分

```console
$ grep -n "S2a\|S2b" docs/design/phase78.md | head -4
48:| S2a | 普通函数：语法、签名、`(*name)`、调用 `&`、lvalue、`out` 初始化/L1 | P-7.1 原型 |
49:| S2b | 方法/trait：方法形参、trait 默认体、接口实现签名 | S2a 收口 |
50:| S2c | 类型匹配、负例、文档与门禁 | S2a/S2b |
```

## E2 — 锚点（含不利于己方）

- 有利于 A：[phase78.md:48-50](../../docs/design/phase78.md#L48-L50)（S2a/S2b/S2c）；
  [phase78.md:69](../../docs/design/phase78.md#L69)（E78-6 要求方法/trait）。
- **不利于己方**：`/tmp/ct-refout` 的原型只覆盖自由函数，方法/trait 没有可运行证据；
  trait 默认体与 impl 签名是另一条发射路径。

## E3 — 可证伪预测

若 A 成立，S2b 应能复用 S2a 的 `pann`/`(*name)`/`&` 路径，只需补方法/默认体入口；
若必须为方法/trait 新造参数存储或第二套发射逻辑，则 A 的“同规则”不成立，B 更合适。

## E4 — 代价

- A：一个 phase、一个 MINOR；S2a/S2b 各自红绿，S2b 失败时 PH-78 不能收口。
- B：新增一个 phase，PH-79–81 与 v0.79–0.81 全部顺延，roadmap/AGENTS/D-011 都要改。

## E5 — 对 B 最强论点的 steelman

B 最强：方法/trait 发射路径不同、原型未验证，同相会把首卡拖大。
回应：卡面已把 S2b 设为独立 stage，S2a 可先红绿；同相不等于同 stage，回滚按 stage 做。
