# test/ir — TIR typed shadow 探针（S1b-S1）

> 中文

本目录是 v1-PH-2 S1b-S1 的 TIR 影子树探针。契约见
[docs/design/tir-lir-contract.md](../../docs/design/tir-lir-contract.md) §1–§3，
夹具清单见 [tir-lir-fixtures.md](../../docs/design/tir-lir-fixtures.md)。TIR 只读 AST：
默认路径（AST→C）不变，影子路径只构建 + 校验，不参与发射。

## 运行

```sh
bash test/ir/run.sh <ct-ast>            # 全部六节
CT_IR_SELFHOST=0 bash test/ir/run.sh <ct-ast>   # 跳过自举（约 6s）
```

`selfhost/check-ast.sh` 在语料等价段后自动调用本探针（gate 8 的一部分）。

## 开关

| 开关 | 行为 | 默认 |
| --- | --- | --- |
| （未设置） | 只走 AST→C，历史行为逐字节不变 | ✔ |
| `CT_TIR=1` / `CT_TIR=shadow` | 构建 TIR、跑 V1–V4；仍只发射旧路径字节 | 否 |
| `CT_TIR=0` / `CT_TIR=off` | 同未设置 | — |
| `CT_TIR_REPORT=1` | 每个 unit 打一行覆盖/耗时到 stderr（`tir: unit=…`） | 否 |
| `CT_TIR_DEBUG=1` | 打印未分类类型/语句的调试行 | 否 |
| `CT_TIR_FAULT=<key>` | 注入一条非法 TIR 行，供负例使用；隐含开启影子 | 否 |

`CT_TIR_FAULT` 的键与契约 §5.2 的「负例键」一一对应，S1 实现四个：

| key | 期望 | 说明 |
| --- | --- | --- |
| `ir-v1-missing-type` | `E-IR-101` | 一个无 TypeId 的表达式行 |
| `ir-v2-rvalue-assign` | `E-IR-102` | 一个左值为右值类别的赋值行 |
| `ir-v3-unresolved-call` | `E-IR-103` | 一个无 target 的调用行 |
| `ir-v4-open-instance` | `E-IR-104` | 一个无模板的实例行 |

注入只走影子路径：行在 verifier 之前追加，失败时调用方尚未打开输出文件，
因此「失败不写 C」是可观察的（探针断言产物不存在）。

## 覆盖口径

- 语料：`test/cases/*.ct` + `examples/*/*.ct`，剔除方言演示（`07_dialect` /
  `ct-dialects`，与 `p85_corpus_sha.tsv` 同一集合，当前 **72** 个）；
- 每个文件各编译一次（不带 / 带 `CT_TIR=1`），逐字节 `cmp`；
- 多单元：`test/modules/split`（import + 跨单元派发）与
  `test/modules/autodrop`（AutoDrop），整棵 C 树 `diff -r`；
- 自举：编译器自身源码（70 个单元）带影子重建，整棵树与不带影子逐字节相同。

## S1 的已知边界（不声称已覆盖）

- V5–V10 不在 S1（属于 S1b-S2/S3）；本探针只断言 V1–V4。
- `TCleanup` 的入口来自块尾的 `N_DEFER_RUN` 副本与 AutoDrop 注入的
  `delete`（按声明行归属）；`return` / `break` / `continue` / `?` 的逐出口
  清理集留给 LIR（§4.3），TIR 只记录作用域级条目。
- `ref` / `out` 实参的 place 判定尚未在 V2 展开（§3.3 第 1 行的其余上下文已覆盖）。
- 泛型实例的**成员字段**类型在少数模板体内仍回退为 `void`
  （`CT_TIR_DEBUG=1` 可数）；自举 14.5 万表达式里约 0.4%。
- `N_RAW` 是编译器内部代码片段，无上下文提示时显式记 `void` 并单独计入
  `raw_opaque`，不混入 fallback。
- 临时编号、块结构、清理边顺序不在 S1（LIR 的 §4.2/§4.3）。
