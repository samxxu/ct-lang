# PH-87 S87c — A 机制对编译器自身的 dogfood（`--check-level=warn`）

- 日期：2026-11-21
- 命令：`ct-ast build --emit-c --check-level=warn -I selfhost/ct-ast selfhost/ct-ast/main.ct -o <dir>`
- 结果：**rc=0，无崩溃**；10 条 warning，全部同一类，**均判为误报（FP）**。
- 探针：`bash test/ast/p87_dogfood.sh <ct-ast>`；清单：`test/probes/p87_dogfood.tsv`。

## 1 原始输出（10 条）

```console
$ ct-ast build --emit-c --check-level=warn -I selfhost/ct-ast selfhost/ct-ast/main.ct -o /tmp/p87dog
selfhost/ct-ast/tool/pkg/Pkg.h.ct:36:33: warning: 'T a[]' is deprecated; write 'T[]' for a slice or 'T a[N]' for an array
selfhost/ct-ast/tool/pkg/Pkg.h.ct:93:56: warning: 'T a[]' is deprecated; write 'T[]' for a slice or 'T a[N]' for an array
selfhost/ct-ast/tool/pkg/Pkg.h.ct:93:79: warning: 'T a[]' is deprecated; write 'T[]' for a slice or 'T a[N]' for an array
selfhost/ct-ast/tool/pkg/Pkg.h.ct:94:36: warning: 'T a[]' is deprecated; write 'T[]' for a slice or 'T a[N]' for an array
selfhost/ct-ast/tool/pkg/Pkg.h.ct:94:59: warning: 'T a[]' is deprecated; write 'T[]' for a slice or 'T a[N]' for an array
selfhost/ct-ast/tool/pkg/Pkg.h.ct:399:32: warning: 'T a[]' is deprecated; write 'T[]' for a slice or 'T a[N]' for an array
selfhost/ct-ast/tool/pkg/Pkg.h.ct:2837:56: warning: 'T a[]' is deprecated; write 'T[]' for a slice or 'T a[N]' for an array
selfhost/ct-ast/tool/pkg/Pkg.h.ct:2837:79: warning: 'T a[]' is deprecated; write 'T[]' for a slice or 'T a[N]' for an array
selfhost/ct-ast/tool/pkg/Pkg.h.ct:2838:36: warning: 'T a[]' is deprecated; write 'T[]' for a slice or 'T a[N]' for an array
selfhost/ct-ast/tool/pkg/Pkg.h.ct:2838:59: warning: 'T a[]' is deprecated; write 'T[]' for a slice or 'T a[N]' for an array
$ echo $?
0
```

## 2 误报清单（FP）

| # | 位置 | 诊断 | 判定 | 理由 |
| --- | --- | --- | --- | --- |
| 1–10 | `tool/pkg/Pkg.h.ct:36/93/94/399/2837/2838`（多维数组形参/字段的首维） | `'T a[]' is deprecated; write 'T[]' for a slice or 'T a[N]' for an array` | **FP** | 触发点是多维数组形参/字段的首维（`char x[][MAX]`），这是合法 C 的数组参数，不是 ct 的 slice；诊断只应针对真正的 `T a[]` 声明 |

- FP 数：**10**；崩溃：**0**；其它类别的诊断：**0**。
- 处置：不阻塞本卡（R87-3）。建议另立 issue（数组形参首维不应触发 slice 弃用提示），
  归入 A 机制的误报收敛，不在 PH-87 改语义。
- 说明：同一命令换成 `--check-level=error` 时这 10 条仍以 warning 出现（它们不走
  `--types` 的 B 类finding 升级路径），rc 仍为 0；本卡只登记，不改行为。
