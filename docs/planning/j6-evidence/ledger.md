# J-6 证据台账（SH-104 / V1-C1）

> 命名注记（LANG-24 Stage A）：本文件是历史快照，正文保留当时的 `box<T>` 拼写；v1.0 起规范拼写为 `Box<T>`（见 docs/language-spec.md §1.2）。


> 锚点：v0.88.0 / HEAD `10c7e439`（2026-11-21）。判据来源：[pointer-free-v2 附录 A](../../proposals/pointer-free-v2.md#L190-L262) 与 §C.5。
>
> **状态口径**：`已过` = 有具名可复跑探针/命令且判据可复核；`部分` = 有证据但缺判据的某一半；
> `缺失` = 没有证据；`阻塞` = 依赖本仓未落地的能力（如迁移 lint），不是“待办”；
> **`外部` = 判据对象在外部包/外部仓，不属本仓 v1.0**（2026-11-23 拆段：`P-3.6`、`P-6.x` 转 std 包）。
>
> **范围**：只收 P-1…P-6（含 §C.5 的 P-3.7 / P-3.8 / P-4.6 / P-5.7）。P-7.x 原型
> （[j6-evidence](.) 的 p72/p73/p74/p75/ref_out）只证明“能跑”，不冒充本台账；P-8.1 不属 J-6 闸门。
> **v1.0 只对“本仓段”负责**：本仓段不得有 `缺失` / `部分`；`外部` 段不计入 v1.0 门禁。
>
> 本文件的 `P-x.y` 行由 `check-docs` 校验：状态枚举、最小可判证据非空、`阻塞` 必须写依据、
> `外部` 必须写明外部归属。
> SH-117 收尾（2026-11-24，实现提交 `0469dd01` / `0c9b29d1`）：P-3.5 / P-5.2–P-5.6 的夹具与 J-4b 契约已入库，
> 本仓段 0 缺失 / 0 部分。
> 台账当前结论：**本仓段 29 已过 / 0 部分 / 0 缺失 / 0 阻塞；外部段 5 项已转 std 包**。
> P-1.3 于 2026-11-28（v1-PH-2 S7-e）补上迁移 lint 三档 dry-run，见 [p1_3_lint.md](p1_3_lint.md)。
>
> <!-- j6:counts passed=29 partial=0 missing=0 blocked=0 external=5 -->

## P-1 语料测量（J-6a）

| 判据 | 最小可判证据 | 现有证据 | 状态 | 负责人 |
| --- | --- | --- | --- | --- |
| P-1.1 固定基线 | 声明扫描范围 + 一条可复跑命令 + 计数一致 | `examples test lib`：1381 个 `.ct` / 31,400 行；字面量 2,321（含 24 处 `#include "…"`）、`char *` 627、`T a[] =` 37、`T a[]` 后缀 38、`ref/out` 16、`new` 54（`3e3c52ad`，命令见下） | 已过 | REQ |
| P-1.2 按特性分类 | 每文件 6 个布尔列的 CSV（路径 + 字面量 / `char *` 形参 / `T a[]` 形参 / `T a[] =` / `ref/out` 标识符 / `new` 标识符），入库可重跑 | [p1_2.csv](p1_2.csv)（1381 行 + 表头，6 列布尔）；生成器 [gen_p1_2.py](gen_p1_2.py)：`python3 docs/planning/j6-evidence/gen_p1_2.py > docs/planning/j6-evidence/p1_2.csv` | 已过 | REQ |
| P-1.3 自动化率 | 迁移 lint dry-run 的「可自动 / 需人工 / 语义需确认」三档百分比 | 工具 [`tools/migrate_lint.py`](../../../tools/migrate_lint.py)（`--selftest` 13 例）对 `examples test lib` 的 1,532 个 `.ct` 做 dry-run：**可自动 17（2.9%）/ 需人工 414（69.5%）/ 语义需确认 165（27.7%）**，可迁移站点 596，C 边界保留 1,365；清单 [p1_3_lint_files.tsv](p1_3_lint_files.tsv)，报告 [p1_3_lint.md](p1_3_lint.md)；复跑命令见下 | 已过 | DEV |
| P-1.4 快照回放 | 基线 sha + 复跑命令 + 计数与 P-1.1 一致 | `3e3c52ad` + 下方命令；与 P-1.1 同一命令 | 已过 | REQ |

```sh
git rev-parse --short HEAD                                   # 3e3c52ad
find examples test lib -name '*.ct' | wc -l                 # 1381
find examples test lib -name '*.ct' -print0 | xargs -0 cat | wc -l   # 31400
find examples test lib -name '*.ct' -print0 | xargs -0 grep -ho '"[^"]*"' | wc -l   # 2321
find examples test lib -name '*.ct' -print0 | xargs -0 grep -hoE '#include[[:space:]]*"[^"]*"' | wc -l   # 24
find examples test lib -name '*.ct' -print0 | xargs -0 grep -hoE 'char[[:space:]]*\*' | wc -l   # 627
find examples test lib -name '*.ct' -print0 | xargs -0 grep -hoE '[A-Za-z_][A-Za-z0-9_<>]*[[:space:]]+[A-Za-z_][A-Za-z0-9_]*\[\][[:space:]]*=' | wc -l   # 37
find examples test lib -name '*.ct' -print0 | xargs -0 grep -hoE '[A-Za-z_][A-Za-z0-9_<>]*[[:space:]]+[A-Za-z_][A-Za-z0-9_]*\[\]' | wc -l   # 38
find examples test lib -name '*.ct' -print0 | xargs -0 grep -hoE '\b(ref|out)[[:space:]]+[A-Za-z_]' | wc -l   # 16
find examples test lib -name '*.ct' -print0 | xargs -0 grep -hoE '\bnew\b' | wc -l   # 54
```

> 附录 A 的 649/494/36/2 是旧基线（不同语料与版本），**不得**当作当前验收数；当前以本节命令为准。
> `T a[]` 的 37 是形参 / 字段 / 无初值声明合计，细分属 P-1.2。

## P-2 语法 / 解析（J-6b）

| 判据 | 最小可判证据 | 现有证据 | 状态 | 负责人 |
| --- | --- | --- | --- | --- |
| P-2.1 `new` 上下文关键字 | 正例 `new T {…}`；负例 `int new;` / `r.new` 合法 | [D-016](../../decisions/D-016.md) + [ctx.ct](../../../test/ast/p81_box/ctx.ct)。附录 A 原文「完全关键字」已被 D-016 取代，负例按 D-016 记 | 已过 | DEV |
| P-2.2 `ref/out` 上下文关键字 | 形参表内识别；形参表外仍是标识符 | [p78_basic.sh](../../../test/ast/p78_basic.sh) E78-1：`int out;`、`time_t *ref;`、形参名 `out` 全部合法 | 已过 | DEV |
| P-2.3 `T[]` 唯一拼写 | `T[]` 前缀；`T a[]` 形参/字段告警；`ct check` 升 error；`T a[] = {…}` 保留 | [p79_basic.sh](../../../test/ast/p79_basic.sh)（`int[] s`、`int a[] = {…}`）+ [p79_migrate.sh](../../../test/ast/p79_migrate.sh)（告警与 strict 升级） | 已过 | DEV |
| P-2.4 花括号共享解析 | `new T {…}` 与 `T x = {…}` 的位置式 / 指定式 / 嵌套同路径 | [p81_box.sh](../../../test/ast/p81_box.sh) E81-2 + [record.ct](../../../test/ast/p81_box/record.ct) | 已过 | DEV |
| P-2.5 旧语料 parse | 全量语料 parse 通过；golden 变化逐条 | 干净归档 `a0ce8ef1` 的编译器源与 HEAD 逐字节相同（`git diff a0ce8ef1..HEAD -- selfhost/l0 selfhost/l1 selfhost/l2 selfhost/ct-ast` 为 0 行），故以 HEAD 的 `selfhost/check-ast.sh` 全量输出为准：**1581 passed / 0 failed / 5 skipped**（`selfhost/check-all.sh` 第 8 道）；golden 变化清单见 [docs/planning/j6-evidence/goldens-l1-vs-ast.md](goldens-l1-vs-ast.md)。干净归档复跑至 v0-PH-79 段（418 条输出、0 失败）后中止，作为旁证而非唯一证据 | 已过 | DEV |

## P-3 String/Str ABI（J-6c）

| 判据 | 最小可判证据 | 现有证据 | 状态 | 负责人 |
| --- | --- | --- | --- | --- |
| P-3.1 16 字节句柄 + 8 字节头 | `_Static_assert`；`header_size(T)` 对齐 | [p80_layout/abi.ct](../../../test/ast/p80_layout/abi.ct)、[p81_box/layout.ct](../../../test/ast/p81_box/layout.ct) | 已过 | DEV |
| P-3.2 复制 / Drop 协议 | 参数 / 返回 / 字段 / `Vec<String>` / `box<String>` 的 refcount 轨迹 + ASan | [p80_retain.sh](../../../test/ast/p80_retain.sh)、[p80_layout/uaf.ct](../../../test/ast/p80_layout/uaf.ct) | 已过 | DEV |
| P-3.3 字面量视图 | 字面量 `Str` 无 Drop；`String` 有 Drop；immortal 空串 `refs=-1` | [p80_literal.sh](../../../test/ast/p80_literal.sh) | 已过 | DEV |
| P-3.4 `.data` / `cstr()` | `.data` 只读、不保证 NUL；子视图 `cstr()`；`printf` 负例 | [p80_cstr](../../../test/ast/p80_cstr)（`prog.ct` + `neg_data_value` / `neg_data_write` / `neg_printf_data`） | 已过 | DEV |
| P-3.5 C 边界 | `.m.ct` / shim / `.h.ct` 全部 `char *`；无隐式转换 | [examples/47](../../../examples/47_chain_factory)、[examples/48](../../../examples/48_string_steps) 的 `.m.ct` + shim；`p80_cstr/neg_printf_data.ct`（`.data` → `%s` 硬错）；声明初始式 / 普通赋值 / 返回位由 `lit_coerce` 拒绝 `String`/`Str` → `char *`（[p80_cstr.sh](../../../test/ast/p80_cstr.sh) 的 `neg_ptr_assign` / `neg_ptr_str_assign` / `neg_ptr_return`），未解析 C 调用的变参位由 `neg_ptr_vararg` 拒绝（`printf("%s", s)`）；声明形参的实参同规则（`argtype_check`）。SH-117 P-3.5 | 已过 | DEV |
| P-3.6 跨仓 dry-run | `std::str::Str` 限定名并存；消费者清单；std 新版本 | 外部：std 0.20.0 已发布 `CharStr` 且无旧名别名；消费者清单归 std 包（[PKG-22](../../../issues/packages/pkg-22-std-str-charstr-rename.md)）；本仓 `selfhost/` 无 `import std::`，不由 v1.0 判定 | 外部 | 包侧 |
| P-3.7 `U16String` / `U16Str` 类型与工厂 | `from_utf8` / `from_utf16` / `to_utf8` / `to_utf16`；`len` 为 code unit；示例可编译 | [p80_methods/prog.ct](../../../test/ast/p80_methods/prog.ct) 覆盖 `U16String.from_utf8`、`U16String.from_utf16`、`String.from_utf16`、`to_utf8`、`to_utf16`，期望输出见 [prog.expected.out](../../../test/ast/p80_methods/prog.expected.out) 第 38–41 行；[p80_literal/literal.ct](../../../test/ast/p80_literal/literal.ct) 另测 `to_utf16`/`from_utf16`/`to_utf8` | 已过 | DEV |
| P-3.8 `U16String` 核心方法集 | snake_case 方法表；越界 / 负下标 / `Option` 返回与 JS 语义对照 | `p80_methods` 方法表 + 期望输出：`char_code_at(99)=0`、`code_point_at(99)=0`、`at(-1)` 取末项、`at(99)`/`get(99)` 返回空视图（`prog.expected.out` 第 16–21 行）；写下标硬错见 [neg_u16_write.ct](../../../test/ast/p80_methods/neg_u16_write.ct)。实现以空视图而非 `Option` 返回，按 §4.70 现状记录 | 已过 | DEV |

## P-4 借用位置矩阵（J-6d）

| 判据 | 最小可判证据 | 现有证据 | 状态 | 负责人 |
| --- | --- | --- | --- | --- |
| P-4.1 存储位置硬错 | 字段 / 全局 / 接口 / box / Option / Result / 容器 / 数组元素 / 泛型实参 / 闭包捕获 | [p79_places.sh](../../../test/ast/p79_places.sh)、`p81_box/neg_field_str.ct`、`neg_box_str.ct`、`neg_box_slice.ct`、[241_map_str_key](../../../test/ast/241_map_str_key/prog.ct) | 已过 | DEV |
| P-4.2 复合类型递归 | `Vec<int[]>` / `Map<Str,int>` / `struct { Str s; }` 硬错 | `test/ast/241_map_str_key`（`Map<Str>` 硬错）、`test/ast/p81_box/neg_field_str.ct`（`struct { Str }` 硬错）；`Vec<Str>` / `Option<Str>` 实测可编译（视图），与 J-4a 原文偏离，见下方 J 表 | 已过 | DEV |
| P-4.3 返回值契约 | 直接 `return 局部切片 / as_str()` 可 lint；参数 / 字面量视图正例 | [p106_str_escape.sh](../../../test/ast/p106_str_escape.sh)（SH-106 已 verified）：返回局部 owner 视图 / 临时接收者视图为 warning、`ct check` 升 error，参数 / 字段 / 字面量 / owner 存活等安全形态静默；接入 `selfhost/check-ast.sh:1354` | 已过 | DEV |
| P-4.4 诊断质量 | 错误指向具体字段 / 泛型实参 / 闭包捕获 | `test/ast/p79_*` / `test/ast/p80_*` / `test/ast/p81_box` 的 `neg_*` 逐条断言诊断文本 | 已过 | DEV |
| P-4.5 残留风险 | 透传路径文档化 | [docs/guide-for-c-programmers.md §7.1](../../guide-for-c-programmers.md) 逐类透传矩阵：返回值 / 临时接收者 / 局部绑定 / 参数 / 字段 / 容器泛型 / 全局 / 跨函数 / C 边界，各标 warning、硬错或契约 | 已过 | REQ |
| P-4.6 切片 place 语义 | `s[i]` 读写、越界 trap、`get` 软访问、`const T[]` 写硬错 | [p79_basic.sh](../../../test/ast/p79_basic.sh) / [p79_index.sh](../../../test/ast/p79_index.sh)（`const_write` 断言） | 已过 | DEV |

## P-5 `ref/out` 所有权（J-6e）

| 判据 | 最小可判证据 | 现有证据 | 状态 | 负责人 |
| --- | --- | --- | --- | --- |
| P-5.1 `out` 未初始化 | 硬错或零初始化；无 UB | [p70_definite.sh](../../../test/ast/p70_definite.sh)、[p78_basic.sh](../../../test/ast/p78_basic.sh)、[ref_out/bad_out_uninit.ct](ref_out/bad_out_uninit.ct) | 已过 | DEV |
| P-5.2 旧值释放 / 别名 | retain 右值 → release 旧值 → 写入；无 UAF | [p80_retain.sh](../../../test/ast/p80_retain.sh) 的 `out_ref_owning`：`out String` / `ref String` 赋值点发射「保留旧句柄 → retain（或 move）右值 → 写入 → release 旧值」，含 `rebind(a, a)` 别名自赋值；trace 为 `after a=2 b=2 live=1` / `end live=0`，ASan/UBSan 无报告 | 已过 | DEV |
| P-5.3 `ref` 赋值 vs 显式 release | 赋值允许；显式 release 硬错 | `p80_retain/ref_assign.ct`（`ref String` 赋值合法，trace + ASan/UBSan）；[p80_retain/neg_ref_release.ct](../../../test/ast/p80_retain/neg_ref_release.ct) 断言 `cannot release through a 'ref' parameter`（`p80_retain.sh` 的 `neg_ref_release`）；`out` 上显式 release 仍允许（调用方移交旧值） | 已过 | DEV |
| P-5.4 `out` 错误路径 | 赋值即生效；v0-PH-70 保证至少一次 | [p70_definite.sh](../../../test/ast/p70_definite.sh) 覆盖定值；[p80_retain/out_error_path.ct](../../../test/ast/p80_retain/out_error_path.ct) 覆盖提前 `return` 的错误出口：`out int len=-1` 与 owning `out String` 的新值对调用方可见（`empty ok=0 len=-1` / `abc echo=3`），旧值在赋值点释放，ASan/UBSan 无报告；错误出口不撤销赋值（`err:` 分支同构） | 已过 | DEV |
| P-5.5 `out/ref` 借用类型 | `out Str` / `ref int[]` 白名单 + 底层契约 | [p80_retain/borrow_out_ref.ct](../../../test/ast/p80_retain/borrow_out_ref.ct)：`out Str` / `ref Str` / `ref int[]` 正例；负例 `neg_out_str_write.ct`（`out Str` 写 → read-only subscript）、`neg_ref_slice_const.ct`（`const int[]` 写硬错）、`neg_ref_array.ct`（`ref int a[N]` 硬错）；`trap_ref_slice_oob.ct` 越界写运行期 trap | 已过 | DEV |
| P-5.6 泄漏 / 双释放 | ASan + `__ct_allocs/__ct_frees` | `check-sanitizers` 599 checks 广覆盖；[p80_retain.sh](../../../test/ast/p80_retain.sh) 的 `out_ref_owning` / `ref_assign` / `out_error_path` / `borrow_out_ref` 每个正例都跑 `-fsanitize=address` 与 `-fsanitize=undefined`（空 stderr + 期望输出逐字）；`asan_escape_case escape_ref_store` 断言 ASan 能抓到 J-4b 存储逃逸的 UAF（探针灵敏度） | 已过 | DEV |
| P-5.7 字符串下标与不可变 | `String[i]` 单码点只读；`U16String[i]` 单 code unit 只读；写操作硬错 | [p80_methods/prog.ct](../../../test/ast/p80_methods/prog.ct) 第 34 行 `view = s[1]` 只读正例；[neg_write_index.ct](../../../test/ast/p80_methods/neg_write_index.ct) `s[0] = 'x'` 硬错；[neg_u16_write.ct](../../../test/ast/p80_methods/neg_u16_write.ct) U16 写硬错 | 已过 | DEV |

## P-6 跨仓迁移（J-6f）

| 判据 | 最小可判证据 | 现有证据 | 状态 | 负责人 |
| --- | --- | --- | --- | --- |
| P-6.1 消费者清单 | `import std::str::Str` 全部有迁移动作 | 外部：消费者全部在 std 包侧；本仓 `selfhost/` 无 `import std::`，`test/modules/p29_builtin_std` 是“未安装则不解析”的负例，不取外部包 | 外部 | 包侧 |
| P-6.2 包版本 / 索引 | std 新 MINOR；索引行；旧锁不破坏 | 外部：std 0.20.0 与索引行已由包侧发布；本仓 pin 与消费者随 [PKG-22](../../../issues/packages/pkg-22-std-str-charstr-rename.md) 升到 0.20.0，旧锁/旧 store 不改写 | 外部 | 包侧 |
| P-6.3 迁移 dry-run | 典型工程 `Str`→`String` 可编译、行为等价 | 外部：dry-run 以新 std 为对象，归包侧；本仓不持有该对象 | 外部 | 包侧 |
| P-6.4 发布前检查 | README / spec / roadmap 三处同步 | 外部：README / spec / roadmap 的 v1.0 文案已同步；“std 版本相关段落”已随 PKG-22 / D-025 更新到 0.20.0，不改 v1.0 门禁 | 外部 | 包侧 |

## J-3 / J-4 / J-5 逐张核对

| 判据 | 核对结论 | 证据 | 状态 |
| --- | --- | --- | --- |
| J-3 String/Str | 与实测一致：16 字节句柄、8 字节头、显式 `.to_string()` / `.as_str()` | spec §4.70 + `p80_*` | 已过 |
| J-4a 借用位置 | **原文与实测偏离**：原文写「容器 / Option / Result / 全局硬错」，实测 `Vec<Str>`、`Option<Str>`、ADT 负载、全局字面量 `Str` 可编译（存视图）；字段 / `Map` 键仍硬错 | spec §4.70「按实测」+ [LANG-22](../../../issues/lang/lang-22-nonimmortal-view-store-lint.md)（warn 规划） | 部分（判据需修订） |
| J-4b `ref/out` 逃逸 | **契约级**：`ref` / `out` 可存储、可传更长寿命位置，语言不做借用检查；`ref` 是别名（显式 release 硬错），`out` 是所有权移交（赋值点 release 旧值） | [spec §4.68](../../language-spec.md#468-ref--out-参数phase-78仅-ct-ast) 新增「逃逸契约（J-4b）」与「逃逸负例（J-4b）」；存储负例 `test/ast/p80_retain/escape_ref_store.ct`（`ref String` 的视图存全局，owner 先释放 → 编译器接受、ASan 报 `heap-use-after-free`，`p80_retain.sh` 的 `asan_escape_case` 断言）；`neg_ref_release.ct` 断言 `ref` 显式 release 硬错 | 已过 |
| J-4c box 环 | 作者责任 + 直接环编译期告警；无环检测 | [p82_cycle.sh](../../../test/ast/p82_cycle.sh) + spec §4.72 | 已过 |
| J-5 机制自洽 | 四家族（借用视图 / 句柄 / 参数糖 / 签名糖）与实测一致；`new` 随 box 同进退 | spec §4.68–§4.70 + `p79` / `p80` / `p81` | 已过 |

## 结论

- **本仓段已过**：29 已过 / 0 部分 / 0 缺失 / 0 阻塞（J 表另计；`<!-- j6:counts -->` 与逐行计数由 check-docs 校验）。
- **外部段已转出**：P-3.6、P-6.1–P-6.4 共 5 项标 `外部`，归 std 包；不计入本仓 v1.0 门禁。
- 上一轮闭合：P-1.2（[p1_2.csv](p1_2.csv) + 生成器）、P-3.7 / P-3.8 / P-4.3（SH-106）/ P-4.5（guide §7.1）/ P-5.7。
- SH-117 本轮闭合（2026-11-24）：P-3.5（`String`/`Str` → `char *` 四个值位置硬错）、
  P-5.2 / P-5.3（out/ref owning 赋值点 release 旧值 + `ref` 显式 release 硬错）、
  P-5.4（错误路径 out 赋值生效）、P-5.5（`out Str` / `ref int[]` 白名单与负例）、
  P-5.6（同组夹具并入 ASan/UBSan）、J-4b（spec 逃逸契约 + 存储负例）。
- **P-1.3 已闭合（2026-11-28）**：迁移 lint 三档 dry-run 落库（[p1_3_lint.md](p1_3_lint.md)，
  工具 `tools/migrate_lint.py`）；可自动 2.9% / 需人工 69.5% / 语义需确认 27.7%（596 个可迁移
  站点）。文本级 lint，不含编译器内建；边界见报告 §5。
- **J-4a 判据需修订**：照原文写“容器硬错”会与 v0.88 实测冲突；按实测改判据，风险由 LANG-22 承接。
- **J-4b** 已写契约与存储负例：类型系统不硬禁逃逸，靠 lint + ASan 兜底（`escape_ref_store.ct` 为灵敏度负例）。
