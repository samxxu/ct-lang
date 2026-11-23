# SH-114 · 泛型函数模板先用后定义

| 项 | 值 |
| --- | --- |
| 模块 | selfhost（ct-ast 解析 / 泛型实例化） |
| 定性 | 语义不一致（spec 承诺 vs 实现） |
| 严重度 | Medium |
| 锚点 | v0.88.3（2026-11-22，外部架构评估 P1-3 探针 P2） |
| 依据 | [Trait/泛型覆盖映射](../../docs/reviews/2026-11-22-trait-generic-coverage-map.md)、[spec §1 顺序规则](../../docs/language-spec.md) |
| 状态 | deferred |
| 处置证据 | **已立项（v1.1；v1.0 先按 spec 例外执行）** |

## 现象

普通函数可以先用后定义（ct-ast 自动补原型）；泛型函数模板不行：

```ct
int main(void) { return twice<int>(3); }   /* 当前报 use of an undeclared variable */
T twice<T>(T x) { return x + x; }
```

探针 P2（v0.88.3）确认：模板在后时，调用点被当作未声明标识符；错误文案没有指出
“泛型模板需要先定义”，与 spec §1 的通用顺序规则冲突。

## 期望（v1.1）

1. **方向二选一，需先定**：
   - **A 统一语义**：对泛型模板做前向收集 / 延迟实例化，使 `main` 先调 `twice<int>` 与普通函数一致；
   - **B 明确限制**：保留“模板必须先定义”，但把诊断改成专门文案
     （如 `generic template 'twice' must be defined before its first instantiation`），
     并在 spec §1 保留例外条目。
2. 无论 A/B，都要加两组顺序测试：模板在前 / 模板在后；负例断言稳定诊断。
3. 若选 A，必须保证实例化顺序不影响生成 C 的确定性，并跑全量语料对比。

## 非目标

- 不改变泛型类型推断规则；
- 不引入新的前向声明语法（除非单独评审）；
- 不阻塞 v1.0；v1.0 按 spec §1 的例外条目执行。

## 验收

- 方向 A：`twice<int>` 先用后定义编译并运行，输出 `6`；实例名/生成 C 与先定义版本一致；
- 方向 B：同一源码报专门诊断，`file:line:col` 齐全；spec 例外条目与诊断一致；
- 两种顺序各一条 `test/ast` 用例；
- `check-ast` / `check-all` 绿；既有语料生成 C 不变（方向 A 需额外证明）。


## 处置（REQ，2026-11-22）：deferred

- 触发：**v1.1 语言裁定窗口**
- 范围：泛型模板顺序 A/B 裁定
- 依据：本卡「处置证据」已标 `v1.1` 立项、不阻塞 v1.0；v1.0/v1.1 冻结期不排工。
- 触发时：改回 `open`，按本卡验收执行；不提前扩围。

## 处置（DEV，2026-11-23）：方向 B 红证

**方向：B（保留必须先定义，给专门诊断）。** 理由：A 的前向收集/延迟实例化会改变实例名与
生成 C 的确定性，并与 L2 引导链的「模板定义在实例化点之前」前提冲突；B 只改诊断，
不动实例化顺序，v1.0 不阻塞。spec §1 保留例外并写明专门文案。

**红证（`baseline: 5a74ffd9`，即 SH-108 修复提交）。** 用该提交的 ct-ast 跑新探针：

```console
$ sh test/ast/p114_generic_order.sh .temp/tmp-chain/g108/ct-ast
ok   template before use compiles and runs
FAIL p114/generic-order: template-after-use diagnostic differs
  test/ast/errors/generic_template_after.ct:7:25: error: use of an undeclared variable
FAIL p114/generic-order: template-after-use kept the generic undeclared-variable text
ok   a plain undeclared variable keeps the old diagnostic
ok   a missing generic name keeps the old diagnostic
$ echo $?
1
```

先用后定义目前只报通用 `use of an undeclared variable`，且位置落在 `<`（col 25）而不是
模板名（col 20）。状态字段保持 `deferred` 不动。
