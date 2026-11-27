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

## 8 S9 执行记录（2026-11-27）

> 本记录回填 S9 的实际落地范围与剩余清单；M1–M5 编号沿用 §4。

### 8.1 已完成

| 片 | 落地 | 证据 |
| --- | --- | --- |
| **M1** `lib/core` | 8 个单元改为「本单元 `<base>.shim.h` + `#include "<base>.shim.h"`」，零 manifest/CLI allow；编译模式（`ct check` / 单文件 `-o`）在 `Driver.load_builtin` 展开 shim，单文件产物仍只有原始系统 include、不落额外文件 | `grep -rE '^[[:space:]]*#include[[:space:]]*<' lib/core --include='*.ct'` 零命中；`p65/regression` |
| **M2** `selfhost` | 62 个 `.h.ct` 改为本单元 shim；`realpath` 原型移入 `Module`/`ModuleBoundary` 的 shim，函数式宏 `CT_ROR` 移入 `Pkg` 的 shim；`main.ct` 的 `strrchr`/`strcmp` 改为 Ct 循环，入口不再需要任何 C 头 | `grep` 零系统 include；自举两轮逐字节；`check-seed` 两轮 |
| **M5** 默认翻转 | `c_path_is_core` 与五目录豁免删除；manifest 无 `c-boundary` 键 = strict；`ct migrate` 为旧项目自己的 `ct.pkg` 补 `c-boundary = allow`（已有键不改写）；`ct build/check/compile` 默认 strict；`ct build` 把每个已编译 `<base>.shim.h` 复制到输出目录，`--emit-c` 产物自包含 | `p65/policy`、`p65/regression`、`S3 migrate` 探针（写 allow 且只写一次） |
| 文档 | spec §1.2 / §4.66、README、package-guide §2/§8、glossary、c-shim-contract N-2 同步 | `check-docs`、`p65/docs` |

边界单元形态：`.h.ct` 用**本单元 shim**（spec §4.66 的唯一严格出口），编译模式展开；
`selfhost/` 不再有 `.m.ct` 边界单元（原先的目录级 map 会以可达闭包把全部头文件灌进每个
编译单元，且空 map 会让 TIR shadow 报 empty module）。`lib/core` 的 shim 只含该单元原本的
头，`U16String` 另补 `<string.h>`（`memcpy`）与 `<stdio.h>`（`Vec<U16String>` 实例的
`fprintf`）；这两条是既有隐式声明在 clang 21 上的显式化，不改语言语义。

### 8.2 M3/M4 执行结果（2026-11-27，`issue/s9b`）

> 基线：`77f654db`（S9 M1/M2/M5 + 默认 strict 已落）。本节数字由 `examples/**`、`test/**`
> 的 `.ct` 重新审计；`selfhost/`、`lib/core/` 仍为零系统 `#include`。

| 口径 | `examples/` | `test/` | 合计 |
| --- | --- | --- | --- |
| 迁移前含 `#include` 的文件 / 行 | 189 / 227 | 602 / 695 | **791 / 922** |
| 迁移后含 `#include` 的文件 / 行 | 45 / 53 | 131 / 153 | **176 / 206** |
| 删除的文件 / 行 | 144 / 174 | 471 / 542 | **615 / 716** |
| 其中：`<stdio.h>` 文件（前 → 后） | 734 → 26 | （合并在左） | 734 → **26** |

- **M3 冗余 `<stdio.h>`**：删除 **708 行**。全部删除在生成 C 上对拍：`test/probes/p85_corpus_sha.tsv`
  的 79 行 corpus pin **与基线逐字相同**，`check-goldens-ast` **25/25**。保留的 26 行 stdio 都是
  有理由的 C 互操作/负例：`65_raw`（raw 行锚）、`hdr`/`hdr_prologue`（断言头 prologue 复制
  `#include`）、`io.m.ct`（map 单元）、`p65_include/inside.ct`（strict 负例）、`vprintf`/`FILE`
  不在自动补头集合的 6 个夹具、跨单元构建根，以及 `test/archive/**` 的历史语料（清单固定，见下）。
  删除后不再用 stdio 的纯头文件也删；**纯 stdio 文件 620 → 12**（12 个均为上述例外）。
- **M4 其余头**：剩余 176 文件 / 206 行按头分桶：`stdlib.h` 83、`string.h` 29、`stddef.h` 20、
  `stdarg.h` 9、`stdio.h` 26、`time.h`/`sys/types.h` 7、`stdbool.h`/`stdint.h`/`stdalign.h` 5、
  `pthread.h`/`sched.h` 3、板级/自定义头 10、shim 14。**没有非互操作用例继续靠 allow**：
  - 32 个 `.m.ct` 映射单元本身即 C 边界（strict 不拦），不需要 allow；
  - 154 条登记在 [`test/c-boundary-allow.tsv`](../../test/c-boundary-allow.tsv)，每行带理由；
  - `p65_include/inside.ct` 保持严格负例（不登记 allow）；
  - 其余非互操作且符号已不用的 `#include` 已删（含 `stdbool.h` 全部删除，`bool` 是语言内建）。
- **保留字节的 3 个例外**：`test/cases/01_trait_basic.ct`、`test/cases/04_signatures.ct`、
  `examples/01_greeter/greeter.ct` 的 include 虽非互操作符号，但保留以钉住 golden / corpus 字节
  （登记 allow）；`test/archive/**` 6 个文件整树回退到基线，`archive-manifest` 46 文件全对。
- **生成的 C 差异**：corpus 与 goldens **逐字节不变**；仅 `test/modules/p39_lib/baseline.sha`
  的 `split impl_dog.h` 一行变化（`impl_dog.h.ct` 的冗余 stdio 被删，头不再复制该行），
  baseline 已按 S9 口径更新；`test/ast` 闭包/字面量序号（`ct_str_lit_N`）在 14 个非 corpus
  夹具中因 token 序号前移而不同，程序输出不变。

### 8.3 默认 strict 的落地形态（不再有 harness 全局 allow）

| 门禁 | 迁移前 | 迁移后 |
| --- | --- | --- |
| `check-all.sh` | `export CT_C_BOUNDARY=allow` | 删除；各门自己按登记表 allow |
| `check-ast.sh` | 同上 | 删除；[`test/c-boundary-wrap.sh`](../../test/c-boundary-wrap.sh) 只对登记表行加 allow；临时目录里的历史探针用 `CT_HARNESS_TEMP_ALLOW=1`，p65/p66 strict 探针用 `CT_STRICT_BOUNDARY=1` 关闭该分支 |
| `check-warnings.sh` | 同上 | 删除；同一 wrapper；607/607 ok |
| `test/pkg/run.sh` | 同上 | 删除；生成项目的 `main.ct` 不再写 `#include`（printf 自动补头），165/165 ok |
| `check-sanitizers.sh` | 同上 | 删除；同一 wrapper |
| `test/run.sh`（L0） | 依赖 `check-all` 的全局 allow | 自己给 seed `ct` 装 wrapper；4/4 ok |

证据（均在本 worktree、默认 strict、无 `CT_C_BOUNDARY` 导出）：

- `check-ast.sh`（`check-all` 内）：**1735 passed, 0 failed, 6 skipped**；p65/p66 strict 探针全绿。
- `check-warnings.sh`：**607 ok, 0 failed**。
- `test/pkg/run.sh`：**165 passed, 0 failed**。
- `test/run.sh`：**4/4**；`check-goldens-ast.sh`：**25/25 + archive 46**。
- `check-seed.sh`：两轮逐字节 + 手改负例红，OK。
- `check-docs.py`：OK（3299 links / v1.1.0 / 8 gates）。
- `check-sanitizers.sh`：**661 checks, 0 failed，无 sanitizer report**。
- `check-all.sh`：**OK（8 hard gates green，13m05s 最后一次全量）**；G0/G8 前置通过。

> 另：`test/ast/` 等 64 个探针脚本仍保留脚本内的 `export CT_C_BOUNDARY=allow`，它们只为自己
> **生成的临时夹具**（不是 `examples/`、`test/` 仓库语料）声明 C 互操作；每份脚本开头说明其
> 生成物。该集合不在本卡迁移面内，且与 `check-ast` 的临时分支同源。
>
> 边界：`check-ast` 自己的**临时探针夹具**仍保留历史 allow 分支，因为它们不是 P-1.1 语料、
> 也不属于本卡的 `examples`/`test` 迁移面；该分支不是进程级 `CT_C_BOUNDARY`，且 p65/p66 用
> `CT_STRICT_BOUNDARY=1` 明确否决它。生产编译器与仓库语料仍是 strict。
