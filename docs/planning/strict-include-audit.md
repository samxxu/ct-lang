# 全局默认 strict 前置：`#include` 现数审计（S9 输入）

> 状态：**审计完成（2026-11-26）**，供 [`v1-PH-2`](../phases/v1-PH-2/card.md) **S9** 直接执行。
> 本文件只做分类与排序，不改代码、不改夹具、不翻转默认值；D 轨道产物，随 A 轨道收口后执行。

## 0 为什么先做这一步

S9 要把 [v0-PH-65](../phases/v0-PH-65/card.md) 的四目录豁免（`selfhost/`、`lib/core/`、`lib/std/`、
`test/`、`examples/`）收回，默认翻转为 strict。卡里原写的「798 处」是 2026-11-25 的**文件数**快照，
与实测口径不一致；先把现数钉死，避免 S9 开工时再数一遍。

## 1 口径（可复现）

```sh
# 含 #include 的 .ct 文件数
grep -rl '^[[:space:]]*#include[[:space:]]*[<"]' selfhost lib examples test --include='*.ct' | wc -l
# #include 行数
grep -rh '^[[:space:]]*#include[[:space:]]*[<"]' selfhost lib examples test --include='*.ct' | wc -l
# #ct-raw 文件数
grep -rl '#ct-raw' selfhost lib examples test --include='*.ct' | wc -l
```

`^[[:space:]]*#include[[:space:]]*[<"]` 排除了块注释里以 `#include,` 开头的散文行（`Init.h.ct`、
`Expr.h.ct`、`MapBuild.h.ct`、`Stmt.h.ct`、`Driver.h.ct` 各有一处），它们是注释，不是边界。

## 2 实测数字（2026-11-26，`main`）

| 树 | 含 `#include` 的文件 | `#include` 行 | `#ct-raw` 文件 |
| --- | --- | --- | --- |
| `selfhost/` | 56 | 183 | 3 |
| `lib/core/` | 8 | 14 | 0 |
| `examples/` | 180 | 218 | 1 |
| `test/` | 575 | 663 | 6 |
| **合计** | **819** | **1,078** | **10** |

与卡里旧口径的差异：`selfhost` 35 → **56**、总数 798 → **819 文件 / 1,078 行**。
S9 卡文按本表回填。

## 3 分类

### 3.1 可直接删除（冗余 `<stdio.h>`）

[spec §4.67](../language-spec.md#467-libc-io-内置例外按直接调用补头phase-66仅-ct-ast) 规定
`printf` 一族**按直接调用补头**：源文件不需要 `#include <stdio.h>`，生成 C 仍会带这一行。

| 树 | 仅含 `<stdio.h>` 的文件 | 其中用到补头集合外的 stdio 符号 |
| --- | --- | --- |
| `examples/` | 133 | 0（3 个疑似命中是 `Map.remove`、注释里的 `rename`，已逐条确认） |
| `test/` | 456 | 0（7 个疑似命中同上，`remove` 是 `Map` 方法） |

**已实测**：删掉冗余 `<stdio.h>` 后生成 C 逐字节不变（`test/cases/01_trait_basic.ct` 与
`examples/40_str_ownership/str_ownership.ct` 两个探针，`--c-boundary=allow` 下对拍）。
因此这 **589 个文件**的改动不产生 golden 差异，是 S9 里成本最低、收益最大的一片。

### 3.2 需要迁移或显式 allow（其余头）

按「除 `<stdio.h>` 外还包含什么」分桶（文件数）：

| 附加头 | `examples/` | `test/` | 处置 |
| --- | --- | --- | --- |
| `<stdlib.h>` | 11（+1 含 `string.h`） | 65（+4 含 `string.h`） | 迁 `Box` / `Vec` / `String`；迁不动的（`qsort` 回调、`atexit`、freestanding 分配）显式 allow |
| `<string.h>` | 4 | 21 | 迁 `Str` / `String`；`memcpy` 语义的按 `Vec` 切片 |
| `<stddef.h>` | 8 | 11（+1 组合） | `size_t` / `offsetof` 属语言或 shim 决策，待裁定（见 §6） |
| `<stdarg.h>` | 5 | 3（+1 组合） | 目前全是 C 变参夹具，显式 allow |
| `<time.h>` / `<sys/types.h>` / `<stdbool.h>` / `<stdint.h>` / `<stdalign.h>` | 5 | 5 | 逐条判定；无非是类型与常量的，改内建或对象式宏 |
| shim / 板级头（引号形式：`*.shim.h`、`board.h`、`clock.h`、`dma.h`、`rtos.h`、`calc.h`、`mock_hal.h`） | 14 | 6 | **保留**，写显式 allow 并注明「为什么必须 C 互操作」 |
| `<pthread.h>` / `<sched.h>` / `<proj_db.h>` / `<stdalign.h>` | 0 | 4 | 同上（`p41_*` 与 `128_*` 夹具、`sh60_unknown_type` 的 `.m.ct`） |

### 3.3 `selfhost/` 与 `lib/core/`：零 allow，必须走边界单元

这两棵树是 S9 的硬指标（`selfhost`、`lib/core` 不允许任何 allow）。它们的 include 全是 libc / 系统头，
按头统计（一个单元含多个头，故行数按头累计；合计 56 个单元、183 行）：

| 头 | 引用它的 `selfhost` 单元 |
| --- | --- |
| `<stdio.h>` / `<string.h>` | 55 / 55 |
| `<stdlib.h>` | 41 |
| `<limits.h>` | 9 |
| `<ctype.h>` | 7 |
| `<sys/stat.h>` | 5 |
| `<unistd.h>` | 3 |
| `<stdarg.h>` | 3 |
| `<dirent.h>` | 2 |
| `<assert.h>` | 1 |

按「边界声明单元」归并时，建议按簇推进（簇内单元一起改，避免半迁状态）：
基础三件（`stdio` + `string` + `stdlib`，41 个单元）→ `ctype`（emit / sym 组，7）→ `limits`（`Stmt*`、
`Lexer`，9）→ `sys/stat` + `unistd` + `dirent`（`Module`、`ModuleBoundary`、`Cache`、`Pkg`、`PkgIndex`）
→ `stdarg`（`Intern`、`Sh`、`Pkg`）→ `assert`（`Lexer`）。

`lib/core/` 的 8 个单元：`Vec`、`Str`、`String`、`Box`、`Option`、`Result`、`utf16/U16Str`、`utf16/U16String`，
用到 `<stdlib.h>`（7）、`<stdio.h>`（3）、`<string.h>`（2）、`<stdint.h>`（2）。

## 4 迁移顺序

| 片 | 内容 | 规模 | 验收 |
| --- | --- | --- | --- |
| **M1** `lib/core` | 8 个单元改「边界声明 + 无 include」；先做 `U16Str`/`U16String` 这一对，再做其余 | 8 文件 | `check-ast` 不动点；用户语料生成 C 逐字节；seed 两轮；`lib/core` 零 include |
| **M2** `selfhost` | 按 §3.3 头簇逐簇迁：基础三件 → `ctype` → `limits` → `sys/stat`+`unistd`+`dirent` → `stdarg` → `assert` | 6 簇 / 56 文件 | 每簇：`check-ast` fixpoint、生成 C 逐字节、seed 两轮；`selfhost` 零 include |
| **M3** 冗余 stdio | examples 133 + test 456 删 `<stdio.h>` | 589 文件 | 生成 C 逐字节（实测已证）；`check-goldens-ast` 25/25 不变；`check-warnings` 零告警 |
| **M4** 其余 examples/test | §3.2 逐桶迁移；迁不动的写显式 allow 与理由 | ~190 文件 | 每桶一次提交；矩阵（§3.2）逐行勾掉 |
| **M5** 翻转默认值 | `c_path_is_core` 的 5 个目录前缀删除；manifest 无键改 strict；`ct migrate` 为旧包写 `c-boundary = allow`；spec §1.2 / §4.66、README 同步 | 1 次提交 | `check-all` 绿；`selfhost` / `lib/core` 零 allow；旧包 `ct migrate` 夹具通过；seed 两轮、自举两轮 |

M3 可以与 M1/M2 并行（文件集不重叠，也不改编译器），M4 必须等 M3 落地后再分桶；M5 是最后一次提交，
保留「一提交可回滚」。

## 5 门禁与证据

- 每片：`bash selfhost/check-all.sh` 全绿；`selfhost/check-goldens-ast.sh` 25/25；`check-ast` fixpoint；
- 改 `selfhost/**` 的片（M1、M2、M5）额外跑 `selfhost/check-seed.sh` 两轮逐字节；
- 用户语料等价：`check-ast.sh` 的语料等价段，M1/M2 必须逐字节，M3 已实测逐字节；
- 收口证据写回 [`v1-PH-2`](../phases/v1-PH-2/card.md) S9 行与 [issues/README](../../issues/README.md) 的处置表。

## 6 待裁定

1. **`lib/core` 的边界单元形态**：`.m.ct` 映射单元还是 `.h.ct` 的姊妹 `<base>.shim.h`？前者能带
   `#include` 与对象式宏，后者是单元自有的声明面；内置层是否允许 `.m.ct` 需要一次 ADR（拟 **D-030**，
   编号在写之前再核 `docs/decisions/`）。
2. **`<stddef.h>`**：`size_t` / `offsetof` 是收进语言内建（`usize` + `offsetof` 内建），还是留在 shim？
   影响 examples 8 + test 11 的写法。
3. **`<limits.h>`**：`INT_MAX`、`CHAR_BIT` 等是对象式宏（shim 可带）还是语言常量？`Lexer` 与 `Stmt*` 的 9 个单元依赖它。
4. **`<stdarg.h>`**：`Intern`、`Sh`、`Pkg` 的自有变参函数（`ct_scratch_fmt` 一类）是否需要语言级变参，
   还是只留 shim 声明？
5. **负例夹具**：`test/ast/errors/L31_*`、`test/errors/**` 里针对 strict 的负例必须保留 allow 形态，
   不能随 M3/M4 一起清掉；S9 收口前逐条标注。

## 7 关联

- [`v1-PH-2`](../phases/v1-PH-2/card.md)（S9）
- [v0-PH-65](../phases/v0-PH-65/card.md)（pre-1.0 四目录豁免的来源）
- [language-spec §4.66](../language-spec.md#466-c-边界c-boundary-与-shimphase-65仅-ct-ast)（C 边界与 shim）
- [language-spec §4.67](../language-spec.md#467-libc-io-内置例外按直接调用补头phase-66仅-ct-ast)（libc I/O 补头）
- [requirements-pool](requirements-pool.md)（REQ-STRICT-1）
