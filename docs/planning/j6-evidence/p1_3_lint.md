# P-1.3 迁移 lint 三档 dry-run（v1-PH-2 S7-e）

| 项 | 值 |
| --- | --- |
| 状态 | **已过**（2026-11-28；本仓段 P-1.3 闭合） |
| 判据 | [J-6 台账](ledger.md) P-1.3：「迁移 lint dry-run 的『可自动 / 需人工 / 语义需确认』三档百分比」 |
| 工具 | [tools/migrate_lint.py](../../../tools/migrate_lint.py)（std-lib only，dry-run，不改源码） |
| 语料 | `examples/`、`test/`、`lib/` 共 **1,532** 个 `.ct` 文件（HEAD `81c574ca`） |
| 清单 | [p1_3_lint_files.tsv](p1_3_lint_files.tsv)（502 行，每个有发现的文件一行；C 边界文件也列，`total` 含 `keep`） |

## 1 三档口径

三档按**编辑时需要的判断**划分，不是按文件大小或行数：

| 档 | 含义 | 判据 | 工具给出的动作 |
| --- | --- | --- | --- |
| **可自动** `auto` | 替换是文本级、局部且可证明等价 | `T a[]` → `T[] a`（无初始化式）；`printf("%s", x.cstr())` → `x.print()`；`Box<T>` 接收者的 `->` → `.` | 直接给替换文本 |
| **需人工** `manual` | 形状已知，但要选名字/顺序/周边语句 | 普通 `char *` 局部与形参、非 `Box` 的 `->`、`free`/`delete`、`printf("%s")`、普通结构体指针 | 给目标写法，编辑者落笔 |
| **语义需确认** `semantic` | 所有权、寿命或 ABI 会变 | `Map<char *, V>` 键、`Result<…, char *>` 载荷、`own T *`、`cstr()`、显式 `struct *` 字段/形参、`malloc` 单对象、`map trait` 以外的所有权形态 | 先确认行为再改 |

**C 边界不算迁移目标。** 下列文件的所有指针站点进入 `keep` 桶，不计入三档分母（但计入清单）：

| keep 理由 | 文件数 | 判据 |
| --- | --- | --- |
| 负例/历史夹具 | 518 | 路径含 `errors/` 或 `archive/`，或文件名为 `neg_*`：旧形态是被测对象 |
| 已登记 C 互操作 | 178 | [test/c-boundary-allow.tsv](../../../test/c-boundary-allow.tsv) 命中 |
| C 互操作/板级夹具 | 46 | 路径含 `c-superset` / `freestanding` / `shim` / `baremetal` / `bindings` |
| `.m.ct`/shim 的消费方 | 19 | 同目录或父目录有 `.m.ct` / `.shim.h` |
| `map` 绑定 | 18 | 文件含 `map trait`：实例绑定本身就是 C 接缝 |
| 内建/运行期层 | 8 | `lib/**`：句柄实现本体，迁移会循环 |
| `#ct-raw` 透传 | 1 | 原样块 |

## 2 结果（2026-11-28）

```console
$ python3 tools/migrate_lint.py
migration lint dry-run (P-1.3)
corpus: examples/test/lib - 1532 .ct file(s)

tier                sites    pct
-----------------  ------  -----
auto 可自动               17    2.9%
manual 需人工            414   69.5%
semantic 语义需确认        165   27.7%
migratable total      596
C boundary keep      1365
```

| 档 | 站点数 | 占可迁移站点 | 说明 |
| --- | ---: | ---: | --- |
| 可自动 | 17 | **2.9%** | 16 个 `array-suffix` + 1 个 `printf-cstr` |
| 需人工 | 414 | **69.5%** | 182 箭头 / 151 `char *` / 68 普通结构体指针 / 11 `printf("%s")` / 2 `delete` |
| 语义需确认 | 165 | **27.7%** | 100 显式 `struct *` / 35 `Map<char*,V>` / 29 `Result<…,char*>` / 1 `own` |
| **合计** | **596** | 100% | 另有 **1,365** 个 C 边界站点保留（不参与百分比） |

> 若把 C 边界也放进分母（1,961 个站点）：可自动 0.9% / 需人工 21.1% / 语义需确认 8.4% /
> C 边界保留 69.6%。本报告的主百分比用**可迁移站点**（596）作分母，因为 C 边界不迁。

按根：

| 根 | 可迁移站点 | 可自动 | 需人工 | 语义需确认 |
| --- | ---: | ---: | ---: | ---: |
| `examples/` | 119 | 3（2.5%） | 90（75.6%） | 26（21.8%） |
| `test/` | 477 | 14（2.9%） | 324（67.9%） | 139（29.1%） |
| `lib/` | 0 | 0 | 0 | 0（8 个文件全部归入内建/运行期 keep） |

重点文件（按档站点数，完整清单见 [p1_3_lint_files.tsv](p1_3_lint_files.tsv)）：

| 档 | 文件（站点数） |
| --- | --- |
| 可自动 | `examples/15_range_init`（3）、`test/modules/p20_type_host_arity/more.ct`（2）、`test/ast/109…114_range_init*`（各 1） |
| 需人工 | `examples/18_generic_string_table`（21）、`examples/19_container_each_generic`（14）、`test/ast/160_group_a/hand.ct`（10）、`test/ast/293_dispatch_chain`（9）、`test/cases/13_signature_types.ct`（9） |
| 语义需确认 | `test/ast/314_adt_shadow_result`（8）、`examples/05_body_dispatch`（7）、`test/ast/235/236_result_try*`（各 7）、`test/ast/62_borrow_handback`（5） |

**怎么读这个 2.9%**：可自动比例低不是工具漏报，而是剩余站点的形状决定的——`T a[]` 这类纯语法
迁移在 v1-PH-2 前已基本清完；剩下 596 个站点里 414 个要选 `String`/`Str`/`Box` 或改周边语句，
165 个会动所有权/ABI。**这正是迁移成本的主要部分**。把 `char *` 一律自动改 `String` 会制造
“编译过但语义错”的假迁移，本 lint 不这么做。

## 3 规则与三档映射

| 规则 | 档 | 站点 | 目标写法 |
| --- | --- | ---: | --- |
| `array-suffix` | auto | 16 | `T a[]` → `T[] a`（`T a[] = {…}` 保留） |
| `printf-cstr` | auto | 1 | `printf("%s", x.cstr())` → `x.print()` / `x.println()` |
| `arrow` | manual | 182 | `p->f` → `b.f`（Box）或先把指针改为 `Box<T>`/`ref` |
| `char-ptr` | manual | 151 | `char *` → `String`（拥有）/ `Str`（借用） |
| `struct-ptr` | manual / semantic | 68 / 100 | 普通 → `Box<T>`/`ref T`；显式 `struct *` → 先确认布局/所有权 |
| `map-char-key` | semantic | 35 | `Map<char *, V>` → `Map<String, V>` |
| `result-char-ptr` | semantic | 29 | `Result<…, char *>` → `Result<…, String/Str>` |
| `printf-s` | manual | 11 | `printf("%s")` → `x.print()` / `x.println()` |
| `delete` | manual | 2 | `delete p` → `p.release()` |
| `own-malloc` | semantic | 1 | `own T *p = malloc(...)` → 确认后改 `Box<T>`/`new` 或保留 |

## 4 复跑与清单

```sh
# 自测（正/负，13 例）
python3 tools/migrate_lint.py --selftest

# 三档汇总
python3 tools/migrate_lint.py

# 站点明细（path / line / tier / rule / suggestion / code）
python3 tools/migrate_lint.py --format tsv

# 文件清单（入库证据）
python3 tools/migrate_lint.py --files > docs/planning/j6-evidence/p1_3_lint_files.tsv

# 等价入口：tools/check.sh lint（自测 + 汇总）；g4 已挂 --selftest
bash tools/check.sh lint
```

自测覆盖：干净文件零发现、`T a[]` 自动、`char *`/`->` 人工、`own`/`cstr()` 语义、C 边界 keep、
注释/字符串诱饵、`printf+cstr` 自动、`Map<char*,V>` 语义。

## 5 边界与未做

1. **文本级 lint，不是编译器内建**：按行剥注释/字符串，跳过 >4,000 字节的行（4 行，均为长
   标识符/长字符串负例）；跨行声明、宏、`#ct-raw` 内的 C 不做语义分析。
2. **不自动改写源码**：`--dry-run` 是唯一模式，没有 `--write`；自动档也只给替换文本，落笔由人做。
3. **例外清单按路径/规则近似**：E2/E4 的逐文件判定在
   [pointer-free-exemptions](../pointer-free-exemptions.md)，工具没有读取它；这类文件会落进
   `manual`，报告不把 `manual` 当成“必须迁”。
4. **未接入 `check-all`**：本证据是 P-1.3 的 dry-run；把它做成 `ct` 子命令或持续门禁是后续工作，
   不在本轮伪造。
