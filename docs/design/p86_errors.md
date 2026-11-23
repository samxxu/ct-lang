# v0-PH-86 S86c — 错误出口清单与 `?`/`errdefer` 范围裁定

> **交付物**：S86c（`p86_errors`）。基线 `1e2c30f7`，v0.86.0。
> **范围**：词法器与 token 消费路径的错误出口；诊断文本逐字不变。
> **前置**：[phase86 卡](../phases/v0-PH-86/card.md) §2 S86c、[D-017](../decisions/D-017.md) A1/B4、
> [D-018](../decisions/D-018.md)、[p85_spike](p85_spike.md) §3 sharp edge 5。

## 1 判据

| 判据 | 落点 |
| --- | --- |
| E86-4 诊断文本与既有负例一致 | `test/probes/p86_error_diags.tsv`（345 个 fixture 的 exit + stderr sha256）与 `test/ast/p86_errors/*.expected.err` |
| 词法边界诊断不变 | `test/ast/p86_errors/` 八条：长标识符、长字符串、长 PP 行、非法整数后缀、未终止字符串、块注释跨行后的列号、整数 token 的旧“陈旧文本”诊断 |
| `?`/errdefer 的适用范围 | §3；原始证据 `test/probes/p86_bootstrap_evidence.txt` |

## 2 错误出口清单（token 路径）

| # | 出口 | 触发 | 冻结文本 | 本卡改动 |
| --- | --- | --- | --- | --- |
| 1 | `Lexer::next` 的 `toktrunc`（T_ID） | 标识符 > 159 字节 | `identifier is too long` | 视图长度仍按 `MAX_TEXT-1` 封顶，触发点不变 |
| 2 | `toktrunc`（T_STR） | 字符串 token > 159 字节（内容 > 158） | `string literal is too long (max 158 bytes; split it)` | 同上 |
| 3 | `toktrunc`（T_PP） | 预处理行 > 159 字节 | `preprocessor line exceeds 159 bytes; split it or move it to a header` | 同上 |
| 4 | `toksuffix` 视图长度 | 后缀超过 `U`+`LL` 的合法组合 | `an integer suffix may be U, L or LL` | 后缀从 `char[8]` 改为视图，长度/字符判定不变 |
| 5 | 类型拼写累积 | 类型/限定名/初始化器超过缓冲 | `type is too long`、`qualified type name is too long`、`an impl pattern is too long` 等 | token 部分改 `tok_copy`/`%.*s`，缓冲上限不变 |
| 6 | 解析器 `fail` 家族 | 语法错误 | `unexpected token`、`expected '>' after the type arguments`、`expected a type (tok N '…')`、`duplicate type parameter '…'` | 内嵌 token 改 `%.*s`；整数 token 保持旧的“上一个 token 文本”行为，见 §2.1 |
| 7 | C 边界前置检查 | `#ct-raw` / 函数式 `#define` / 非 shim `#include` | `a strict C boundary forbids …` | token 前缀比较改 `tok_prefix`，文案不变 |
| 8 | `Module::read_file` | 打不开/读失败/OOM/短读 | `cannot open the input file`、`cannot read the input file`、`out of memory`、`short read` | 未改；这是 token 视图依赖的源缓冲（见 §3.2） |

### 2.1 整数 token 的“陈旧文本”

旧词法器对整数 T_NUM 不写 `toktext`：值在 `toknum`，文本保留上一个 token 的内容。
`test/ast/p86_errors/stale_num_diag.ct`（`int f(1)`）因此在诊断里打印
`expected a type (tok 2 '(')`，而不是 `'1'`。为满足“诊断逐字不变”，视图对整数 token
同样不更新（`Lexer::next` 只在 `tokfloat` 时 `lex_view`），`p86_errors` 与 345 条
清单同时钉住这一行为。这是一处刻意保留的旧怪癖，不是新约定。

## 3 `?` / `errdefer` 的范围裁定

### 3.1 结论

**S86c 的 `?`/errdefer 改造在本卡不适用**，改为“错误出口清单 + 诊断逐字对照”。
理由是硬约束，不是取舍：

1. ct-ast 的引导链是 L0 → L1 → L2 → ct-ast；L2（`selfhost/l2/*.ct`）没有
   v0-PH-40 `errdefer` 与 v0-PH-44 后缀 `?` 的下降。源码里写这两个构造，L2 原样输出，
   `cc` 失败（原始输出见 `test/probes/p86_bootstrap_evidence.txt`）。
2. 词法器没有错误通道（D-018 引 p85_spike §3 sharp edge 5），`?` 无处可挂；
   本卡不为用 `?` 而新造错误通道。
3. 唯一带 `own` 语义的错误出口是 `Module::read_file` 的源缓冲；把它的
   `fopen`/`fread`/`malloc` 失败路径改成 `Result` + `?`/`errdefer` 会改动
   `Module` 的公开方法签名，跨子系统接口不再保持，超出卡 §1.3 边界。

### 3.2 已登记的限制

- `read_file` 分配的源缓冲在进程内不释放（既有行为，非本卡引入）。token 视图指向
  它，所以生命周期覆盖解析阶段；解析后进入 AST 的文本一律经 `tok_copy` 复制
  （E86-1 的“无逐 token 拷贝”只针对词法器）。
- 若将来给 `read_file` 加释放，必须先证明没有 token 视图逃逸到 AST；S86a 的
  多单元探针与 `p85_inventory.py` 的产品扫描是这条的回归网。

### 3.3 对 v0-PH-87/88 的影响（移交）

同样的引导约束适用于 v0-PH-87（解析器/检查器）与 v0-PH-88（发射器）源码：在 L2 仍然
承担 ct-ast 的第一轮构建时，这两个 phase 的 `?`/errdefer 改造也只能停留在
“用户代码里的构造”而非“编译器自身源码”。建议 REQ 在 v0-PH-87 开卡前裁定：
要么先让 L1/L2 具备 v0-PH-40/v0-PH-44（另立任务、改冻结层），要么把 `?`/errdefer
从 v0-PH-87/88 的交付判据里降级为 `no-test` 文档项。本条不替后续 phase 决定。

## 4 证据与复跑

```console
$ bash test/ast/p86_errors.sh .temp/p86b/ct-ast
p86errors: … fixtures match the baseline
```

- 清单：`test/probes/p86_error_diags.tsv`（345 行，基线生成）；
- 新增 fixture：`test/ast/p86_errors/`（8 条 + `.expected.err`）；
- 引导证据：`test/probes/p86_bootstrap_evidence.txt`；
- 探针：`test/ast/p86_errors.sh`（`check-ast` 接线）。
