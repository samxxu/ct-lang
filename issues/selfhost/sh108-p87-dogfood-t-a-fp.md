# SH-108 · PH-87 dogfood 的 10 条 `T a[]` 误报（多维数组形参首维）

| 项 | 值 |
| --- | --- |
| 模块 | selfhost（A 检查器误报） |
| 定性 | bug（误报，不阻塞 PH-87 收口） |
| 严重度 | Medium |
| 锚点 | v0.87.0（2026-11-21）；A dogfood `--check-level=warn` |
| 文件 | [p87_dogfood.md](../../docs/design/p87_dogfood.md)、[PH-87 N-4](../../docs/reviews/2026-11-21-phase87-rev-verdict.md#L273) |
| 状态 | deferred |
| 处置证据 | **deferred**（2026-11-22，REV/REQ：HEAD `38cd4ae4` 重建 ct-ast v0.88.2，`char x[][MAX]` 仍报 `'T a[]' is deprecated`；10 条 FP 未收敛。触发 v1.1 的 A 误报收敛（A 默认强制前）；负责人 DEV；Medium） |

## 现象

对编译器自身跑 `--check-level=warn` 时，A 检查器报 10 条同一类误报：

```text
'T a[]' is deprecated; write 'T[]' for a slice or 'T a[N]' for an array
```

触发点是**多维数组形参/字段的首维**（如 `char x[][MAX]`），这是合法 C 的数组参数，
不是 CT 的 slice。诊断只应针对真正的 `T a[]` 声明。

证据：[p87_dogfood.md](../../docs/design/p87_dogfood.md) 的 1–10 行；
[PH-87 复核 N-4](../../docs/reviews/2026-11-21-phase87-rev-verdict.md#L273) 要求“按建议立 `SH-*`，
归 A 机制误报收敛”。

## 期望

- `T x[][N]` / 多维数组形参首维不再触发 `T a[]` 弃用警告；
- 真正的 `T a[]` 声明仍按既有文案警告；
- 对 ct-ast 自身 `--check-level=warn` 时该类别为 0 条；
- 补正负例：误报的 `char x[][MAX]` + 应报的 `int a[]`。

## 验收

- 新探针覆盖上述两例，挂 `check-ast`；
- `ct build --check-level=warn` 对 ct-ast 不再出现该 10 条；
- 既有 A 检查器负例与豁免不变。

## 关联

- [PH-87 卡](../../docs/design/phase87.md) §7.6、E87-5
- [p87_dogfood.md](../../docs/design/p87_dogfood.md)
- [v1-pre 证据](../../docs/history/v1-pre-evidence.md) 承接项 7

## 处置（REV/REQ，2026-11-22）

**结论：`deferred`。** 误报在 HEAD 仍复现，但本条归「A 机制误报收敛」，不在 v1.0 闸门内。

**独立复现（干净归档 HEAD `38cd4ae4` 重建 ct-ast v0.88.2）：**

```ct
/* fp.ct */
#define MAX 4
void f(char x[][MAX]) { (void)x; }
int main(void) { return 0; }
```

```console
$ ct-ast build --check-level=warn fp.ct -o out
fp.ct:2:14: warning: 'T a[]' is deprecated; write 'T[]' for a slice or 'T a[N]' for an array
'cc' -std=c99 … -o out
$ echo $?
0
```

`char x[][MAX]` 是多维数组形参的首维，合法 C、不是 CT slice；诊断仍把首维的空 `[]` 当成
`T a[]` 弃用形态。与 [p87_dogfood.md](../../docs/design/p87_dogfood.md) 1–10 行同类，共 10 条。

**触发/负责人/优先级**：v1.1 的「A 误报收敛」批次（A 检查器默认强制 `--check-level=error`
之前必须清零同类误报）；负责人 DEV；Medium。修法：A 检查器在判定 `T a[]` 时跳过「元素类型
本身带数组维度」的声明（首维或后续维为空 `[]`），补正例 `char x[][MAX]` 与负例 `int a[]`。
本批只复核，不改 A 检查器。

## 处置（DEV，2026-11-23）：红证

**红证（`baseline: a0ce8ef1`）。** 用该提交重建的 ct-ast 跑新探针：

```console
$ sh test/ast/p108_multidim_param.sh .temp/b/ct-ast
FAIL p108/multidim: a multi-dimensional parameter first dim is not T a[]
  unexpected T a[] warning
FAIL p108/multidim: a multi-dimensional field first dim is not T a[]
  unexpected T a[] warning
ok   a genuine int a[] parameter still warns
ok   a genuine int a[] field still warns
FAIL p108/multidim: ct-ast dogfood still has T a[] hits
  10 hit(s)
$ echo $?
1
```

误报点全部是 `deps[][MAX_PKG_PATH]` / `lname[][MAX_TEXT]` 这类多维形参/字段；真正的
`int a[]` 已按预期告警。状态字段保持 `deferred` 不动。

**绿证（`432e95ed` 的红提交之后）。** 探针全绿：

```console
$ sh test/ast/p108_multidim_param.sh .temp/tmp-chain/g108/ct-ast
ok   a multi-dimensional parameter first dim is not T a[]
ok   a multi-dimensional field first dim is not T a[]
ok   a genuine int a[] parameter still warns
ok   a genuine int a[] field still warns
ok   ct-ast's own --check-level=warn run has 0 T a[] hits
$ echo $?
0
```

**既有 A 检查器不回归。** `p79_migrate.sh` rc=0（形参/字段/无初值仍告警，`T a[] = {...}` 与 `T[]`
仍静默）；`p79_basic.sh` rc=0。

**逐字节不变。** 305 个既有单文件语料生成 C 与 `a0ce8ef1` 基线逐字节相同
（`compared=305 same=305 diff=0`）。状态字段保持 `deferred` 不动。

**PH-87 dogfood 基准更新。** `p87_dogfood.sh` 由「期望 10 条同一类 FP」改为「期望 0 条」；
`test/probes/p87_dogfood.tsv` 清空；`docs/design/p87_dogfood.md` 保留 PH-87 历史证据并加
§3 SH-108 复测（0 条）。`p87_dogfood` 6/0、`p87_docs` 23/0。

> **T-7 红证基线口径（2026-11-23）**：上面的红证用 `a0ce8ef1` 重建的二进制。严格按
> T-7，红提交 `432e95ed` 的父提交是 `2a3d208b`（SH-110 修复后）；已在 `2a3d208b` 的
> 干净归档上重建 ct-ast 复跑同一探针，输出逐字相同（三 FAIL / 两 ok / 10 hits），
> SH-110 只改发射器，不影响 A 检查器。红证成立。
