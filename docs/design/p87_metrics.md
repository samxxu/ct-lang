# v0-PH-87 S87d — 解析器/检查器重写的度量报告

- 日期：2026-11-21
- 基线：`84fd5702`（v0-PH-86 收口，v0.86.0）
- 工具：`wc -l`；`/usr/bin/time -p`；构建链 `L0 → L1 → L2 → ct-ast`（`selfhost/check-ast.sh` 同款）
- 指令：`CT_C_BOUNDARY=allow ct-ast build --emit-c -I selfhost/ct-ast selfhost/ct-ast/main.ct -o <dir>`

## 1 行数（切片前后）

| 文件 | 基线 | 现在 | Δ | 说明 |
| --- | --- | --- | --- | --- |
| `frontend/parse/Expr.h.ct` | 8710 | 8814 | +104 | `static_ctype` 拆 13 个 `ctype_*` 切片 + 判别式 |
| `frontend/type/TypeCheck.h.ct` | 1082 | 1149 | +67 | `expr_type` 拆 15 个 `tc_expr_*` 切片 + 判别式 |
| 合计 | 9792 | 9963 | +171 | 纯函数边界与注释，无语法/语义改动 |

切片只把原有分支体搬到具名函数（函数体逐字保留），新增的是签名、调用与切片注释。

## 2 编译耗时（ct-ast 编译自身源码，`--emit-c`，5 次，中位数）

| 版本 | 5 次 real（秒） | 中位数 |
| --- | --- | --- |
| 基线 `84fd5702` | 0.83 / 0.80 / 0.81 / 0.81 / 0.81 | **0.81** |
| v0-PH-87 切片后 | 0.83 / 0.81 / 0.81 / 0.82 / 0.80 | **0.81** |

无可测差异（同机、同 flag、冷输出目录）。函数切片不引入额外分配。

## 3 等价与门禁

| 项 | 结果 |
| --- | --- |
| 测试语料发射 | 66 个文件逐字节不变（`p85_m0` 4/0，`corpus-manifest` diff 空） |
| 诊断文本 | 345 条 exit+stderr 逐字不变（`p86_errors` 23/0） |
| 自举不动点 | `ct-ast` 与自编译 `ct-ast2` 的 `--emit-c` 目录 `diff -r` 为空 |
| ADT/layout | `p84_layout` 26/0、`p84_match` 13/0、`p84_syntax` 14/0 |
| dogfood | `--check-level=warn`：rc=0，10 条同一类 FP（见 [p87_dogfood](p87_dogfood.md)） |

> 编译器自身发射的 C 允许差异（D-017 A1 第 2 层）：切片改变了函数边界，因此本报告
> 不以“编译器自身产物逐字节”为判据；测试语料（第 1 层）仍逐字节冻结。

## 4 未覆盖

- `expr_ctype` / `maybe_box` 里的多条件 kind 判断没有拆切片（它们不是单一判别式，
  拆分会改变调用结构，收益为负）；留给 v0-PH-88 的 `match` 改造一并处理。
- `match` 拼写未进 ct-ast 源码：L2 引导链不实现 v0-PH-84，见
  [battle/p87-kind-match](../../battle/p87-kind-match/verdict.md)。
