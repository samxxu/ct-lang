# LANG-13 · 同类型三级下标链被接收者物化深度拒绝

| 项 | 值 |
| --- | --- |
| 模块 | lang（接收者物化 / 下标链） |
| 严重度 | **High** |
| 优先级 | **P1** —— 直接挡住 ct-json 的 `doc["a"]["b"]["c"]`（JSON-1） |
| 状态 | verified |
| 处置证据 | **已修**（v0.53.2 工作树，回归 `263_index_chain3`） |
| 锚点 | `v0.53.2`（工作树） |
| 上游 | ct-json JSON-1（仓库外记录，本仓不复制） |

## 精确触发条件

同一个带自定义下标的类型连续下落三次：`v["a"]["b"]["c"]`，且 `get` 返回同类型
（`JsonRef get(Str)`）。两级（`v["a"]["b"]`）在声明初始化与赋值右值位置合法。

## 最小复现

```ct
struct Ref { int n; }
impl Ref {
    Ref get(int k) { struct Ref r = { self->n + k }; return r; }
}
int main(void) {
    struct Ref doc = { 1 };
    struct Ref b = doc[2][3][4];
    return b.n;
}
```

```console
$ ct build three.ct -o /tmp/three
three.ct:7:1: error: a method call on a temporary is only allowed at the start of a statement or of an assignment
```

## 根因

每个 `[k]` 糖展开成一次 `N_MCALL`（`<T>_get(&recv, k)`）。三级链的发射形态要求
`Ref_get(&Ref_get(&Ref_get(&doc, 2), 3), 4)`，两级以内靠 `__ct_tmpN` 物化**一层**接收者即可；
三级需要**级联**物化（内层先于外层），而 `Emitter::hoist_scan` 只允许语句表达式根
（`top == 1`）那一层物化，递归到第二层时 `top == 0` 直接报错。

## 与 LANG-5 的拆分理由

两条**不是同一根因**，因此分开修、分开登记：

- LANG-13（本条）：物化**深度**限制，触发点在发射器的 `hoist_scan`；
- [LANG-5](lang-5-result-as-receiver.md)：`expr_type` 对**非泛型固有方法结果**失明，导致
  后续 `.m()` 无法解析，触发点在类型推断 + 接收者种类白名单。

修好任意一条都不能让另一条的用例变绿，各自有独立回归用例。

## 期望行为

三级链与两级链一致：在声明初始化 / 赋值右值位置编译通过，返回句柄；非物化位置
（如二元表达式内部）仍按既有规则拒绝，不静默产出坏 C。

## 影响面与绕法

ct-json 的 `docs/snippets/fail/three_level_chain.ct`，J11；绕法是逐级落到局部变量
（`JsonRef b = doc["a"]["b"]; JsonRef c = b["c"];`），每次多一级就多一行。

## 定位

- 物化深度守卫：[Emitter.h.ct](../../selfhost/ct-ast/backend/emit/Emitter.h.ct) 的
  `hoist_scan`（`N_MCALL` 分支，`!top` 报错）；物化链 `emit_hoists`。
- 回归：`test/ast/263_index_chain3`（正例）、
  `test/ast/errors/index_chain3_bin.ct`（非物化位置仍须报错）。
