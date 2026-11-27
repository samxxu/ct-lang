# v0-PH-86 S86d — 词法器重写的行数与编译耗时（v0.86.0）

> **S86d 交付物**。基线 `1e2c30f7`（v0.85.0），当前 v0.86.0。
> 对照 [v0-PH-85 spike](p85_spike.md) §1；原始命令与输出见
> [test/probes/p86_metrics_evidence.txt](../../test/probes/p86_metrics_evidence.txt)。
> 判据：E86-6（行数/耗时报告入库）、E86-3（第 1 层逐字节不变）。

## 1 口径

- **行数**：`wc -l`，基线用 `git show 1e2c30f7:<path> | wc -l`，当前用工作树。
- **发射 C 行数**：`ct-ast build --emit-c` 的自举树（`*.c` + `*.h` 合计）。
- **编译耗时**：同一主机、同一输入（当前 `selfhost/ct-ast/main.ct`），
  `ct-ast build --emit-c` 5 次取中位；`cc -O2` 全产物 5 次中位。
- **改动范围**：只有 token 表示与 token 消费路径；解析器/检查器/发射器结构未动。

## 2 行数

| 文件 | 基线 | 当前 | Δ |
| --- | --- | --- | --- |
| `frontend/lex/Lexer.h.ct` | 391 | 470 | +79 |
| `frontend/parse/Expr.h.ct` | 8703 | 8710 | +7 |
| `frontend/parse/Parser.h.ct` | 4785 | 4795 | +10 |
| `frontend/parse/Stmt.h.ct` | 5055 | 5056 | +1 |
| `frontend/parse/MapBuild.h.ct` | 897 | 897 | 0 |
| `frontend/parse/ParseSupport.h.ct` | 759 | 759 | 0 |
| `frontend/module/Module.h.ct` | 2934 | 2939 | +5 |
| **合计（token 路径）** | **23524** | **23614** | **+90** |
| 发射 C 行数（自举树） | 45717 | 45817 | +100 |

`Lexer.h.ct` 的 +67 行 = `TokView` + `srclen` + `lex_view`/`lex_view_ok`/
`lex_suffix` + 五个 C 边界 helper（`tok_is`/`tok_prefix`/`tok_copy`/`tok_cstr`/
`tok_first`）+ 边界断言；token 扫描分支删掉了所有 `toktext[...]` 写点，净增不大。
消费方只增加局部 `_ptr/_len` 保存与 `tok_copy` 调用，没有新增结构。

## 3 编译耗时

| 指标 | 基线（v0.85.0） | 当前（v0.86.0） | 变化 |
| --- | --- | --- | --- |
| `ct-ast build --emit-c` 中位（5 次） | 1053.2 ms | 1080.2 ms | +2.6%（噪声内） |
| 5 次原始值（ms） | 1073 / 1019 / 1042 / 1053 / 1064 | 1034 / 1213 / 1077 / 1080 / 1120 | — |
| `cc -O2` 全产物中位（5 次） | 2485.2 ms | 2468.0 ms | −0.7% |
| 编译告警（`-Wall -Wextra -std=c99`） | 0 | 0 | 0 |

**与本卡性能风险 R86-3 的关系**：长度比较把每次关键字比较从 `strcmp` 换成
`strlen + memcmp`；token 非常短（≤7 字节），差异落在构建噪声内。零拷贝没有再引入
分配，`tok_cstr` 只用于 37 个 C 边界实参。

## 4 对照 v0-PH-85 spike

| 指标 | v0-PH-85 spike（结构切片） | v0-PH-86（本卡） |
| --- | --- | --- |
| `Lexer.h.ct` | 391 → 425（+34） | 391 → 458（+67） |
| `ct-ast build --emit-c` | 1053 → 994 ms | 1053.2 → 1080.2 ms |
| 语料逐字节 | 66 文件一致 | 66 文件一致 |
| 自举不动点 | 通过 | 通过（`diff -rq` 空） |
| 告警 | 0 | 0 |

spike 只重排了 `next` 的结构，没有迁移 token 文本；本卡在它的结论（结构等价可行）
之上完成 `Str` 视图与 C API 迁移，因此行数增量更大、耗时略升但仍在噪声内。
两者不能互相替代：spike 的“整子系统新语法重写门不通过”仍按 D-018 记录。

## 5 等价证据（D-017 A1 两级制）

- 第 1 层：`test/cases/*.ct` + `examples/*/*.ct` 66 个文件的发射 C 逐字节一致
  （`p85_corpus_sha.tsv`），banner 版本尚未 bump，无需归一化；
- 第 2 层：编译器自身发射 C 允许差异（+100 行），验收 = 自举不动点 + ASan + 行为测试；
- 诊断：345 个负例的 exit + stderr sha256 与基线一致（S86c 清单）。
