# SH-73 · 动态派发的临时值接收者被拒：方法结果不能作下一跳接收者

| 项 | 值 |
| --- | --- |
| 模块 | selfhost（ct-ast 发射 / 动态派发） |
| 严重度 | **High（所有者 2026-11-21 裁定为 bug）** |
| 锚点 | `v0.44.1`（`13db6cad`，2026-11-15 复核） |
| 文件 | [Emitter.h.ct:5021](../../selfhost/ct-ast/backend/emit/Emitter.h.ct#L5021)、[:2326](../../selfhost/ct-ast/backend/emit/Emitter.h.ct#L2326) |
| 状态 | verified |
| 处置证据 | **accepted（2026-11-23 所有者放开：v1.0 入口优先；修复跟踪 SH-110，SH-110 合入后本卡复核转 verified）** |

> 所有者 2026-11-21 裁定：**按 bug 修复**。下文的“有意的实现边界”保留为当时的工程评估，
> 不再作为最终定性；实现口径见 [SH-110](sh110-dynamic-dispatch-chain-fix.md)。

## 现象

方法调用的结果再作接收者，动态派发直接拒绝：

```c
return h.tap(1)->status();
```

```text
src/main.ct:25:1: error: method receiver must be a variable, an element, a call or a field chain
$ echo $?
1
```

连续两跳：

```c
return h.tap(1)->tap(2)->status();
```

```text
src/main.ct:25:1: error: a method call on a temporary is only allowed at the start of a statement or of an assignment
$ echo $?
1
```

固有 `impl` 返回接口值后直接接调用：

```c
return x.tuned(1).status();
```

```text
src/main.ct:26:1: error: method receiver must be a variable, an element, a call or a field chain
$ echo $?
1
```

代理测量（自由函数工厂结果直接接方法）：

```text
src/main.ct:5:114: error: cannot infer the type to box
$ echo $?
1
```

列号 114 与外部报告一致；这一形态先撞 SH-72 的装箱推断，尚未进入接收者检查。

## 定性：有意的实现边界

- 动态派发要求接收者静态类型已知；lowering 需要重复接收者或取其地址时先物化。接收者本身是一次
  **方法调用**的形态（`a.m().n()`，AST 里是 `N_MCALL`）**当前一律拒绝**，理由是「不会静默产出坏 C」
  （[language-spec.md:251-253](../../docs/language-spec.md#L251-L253)）。
- 右值接收者只允许提升在两种位置：**语句行首**，或**赋值 / 声明初始化式**；其它位置为保持求值顺序
  与「只求值一次」而拒绝（[:256-267](../../docs/language-spec.md#L256-L267)）。
- 允许的接收者形态固定为变量 / 元素 / 调用 / 字段链；**类型宿主不受这四种形态限制**
  （[:985-987](../../docs/language-spec.md#L985-L987)、[:560-561](../../docs/language-spec.md#L560-L561)）。

所以 C1/C2/C3 是按设计拒绝，报错文案也与规约一致；这不是「实现漏了」，而是刻意用限制换生成 C 的稳定性。
值得注意的是，**同样一行链在类型宿主上成立**——这正是 [examples/47_chain_factory](../../examples/47_chain_factory/src/main.ct)
能写 `"url".method("GET").header(...).timeout(...).send().status()` 的原因：它全程是静态映射，没有动态派发。

## 影响面与绕法

- 影响「接口值上的一行链」；不影响静态宿主链。
- 绕法 A：逐跳落变量（每条语句最多一次动态派发）。
- 绕法 B：改走类型宿主（struct 值/指针），即 examples/47 的形态；代价是失去「接口对象」与响应侧多实现。
- 两条都不需要改编译器；规约已把多行写法写成标准落法。

## 修复代价

- 要改 [Emitter.h.ct:5021](../../selfhost/ct-ast/backend/emit/Emitter.h.ct#L5021) 的接收者形态判定，把
  `N_MCALL` 接收者纳入临时值物化；同时改 [:2326](../../selfhost/ct-ast/backend/emit/Emitter.h.ct#L2326)
  的提升位置规则，保证只求值一次且不改变求值顺序。
- 还要处理临时变量的生命周期、接口装箱目标推断，并同步改 spec §4.5 / §4.21 的冻结判据。
- 100–300 行，且会改动「已被接受形态」的生成物，golden 与 `--emit-c` 跨编译器一致性门禁都需要重跑。
  **风险高于 SH-72，不建议在 0.1.0 内做。**

## 建议

- **延后**：作为「动态派发链式」能力单独评估，先给出求值顺序与临时值生命周期的判据，再动发射器。
- 0.1.0 按多行写法或 examples/47 的静态宿主形态落地；API 描述里不要承诺「一行链」。
- 不建议为了 ct-http 单独放开该规则——会同时改变所有动态派发调用点的生成形状。

## 关联

- [SH-71](sh71-host-map-unit-boundary.md)：字符串起手 + 接口对象的另一处边界
- [SH-72](sh72-iface-method-return-box.md)：方法返回接口值的消费限制
- [examples/47_chain_factory](../../examples/47_chain_factory/src/main.ct)：当前可运行的一行链形态
- [docs/language-spec.md §4.5 / §4.10.1 / §4.21](../../docs/language-spec.md#L251-L267)
- 外部来源：`ct-http/docs/review/ct-http-0.1.0-blockers.md` §4（2026-11-15 独立复核）

## 2026-11-21 所有者裁定（已定）

所有者裁定：**SH-73 是 bug，按 fix 流水线修复**。先前“Info / 有意边界”的定性作废；
实现口径、判据与门禁见 [SH-110](sh110-dynamic-dispatch-chain-fix.md)。

修复前仍不得在 README 承诺“一行链”；examples/47 的静态宿主形态可继续作为可跑示例。

## 处置（REV/REQ，2026-11-22）

**结论：`deferred`（bug 已确认，修复未落地；跟踪 SH-110）。** 所有者 2026-11-21 已把本条从
「有意的实现边界」改判为 bug；2026-11-22 在干净归档 HEAD（`38cd4ae4`）重建 ct-ast v0.88.2，
按本条最小形态复跑，仍硬错：

```ct
trait HttpRequest {
    int status();
    HttpRequest tap(int n);
}
struct Req { int s; } use HttpRequest;
impl HttpRequest for Req {
    int status() { return self->s; }
    HttpRequest tap(int n) { self->s = self->s + n; return self; }
}
int main(void) {
    Req x; x.s = 1;
    HttpRequest h = x;
    return h.tap(1)->status();
}
```

```console
$ ct-ast build chain.ct -o out
chain.ct:27:1: error: method receiver must be a variable, an element, a call or a field chain
$ echo $?
1
$ ct-ast build chain2.ct -o out2        # h.tap(1)->tap(2)->status()
chain2.ct:27:1: error: method receiver must be a variable, an element, a call or a field chain
$ echo $?
1
```

**判定**：词法器 / 解析器不是根因；拒绝点在发射器的接收者形态判定
（`Emitter.h.ct` 的 `N_MCALL` 分支），与 SH-110 的实现范围一致。PH-87/PH-88 的发射器切片重写
没有改变这条形态规则（本条在 v0.88.0/v0.88.2 上同样复现）。

**去向/触发**：修复由 [SH-110](sh110-dynamic-dispatch-chain-fix.md) 承接，排 `v1-PH-0`
（`v1-release-plan.md` V1-C3）；负责人 DEV；优先级 High。
状态：**2026-11-23 所有者放开为 `open`**，SH-110 合入后本卡复核转 `verified`。

## 复核（REV，2026-11-23）

由 SH-110 解除：`h.tap(1)->status()` 与两跳链均编译运行；每跳只求值一次；详见 SH-110。
