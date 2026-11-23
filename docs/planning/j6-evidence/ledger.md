# J-6 证据台账（SH-104 / V1-C1）

> 命名注记（LANG-24 Stage A）：本文件是历史快照，正文保留当时的 `box<T>` 拼写；v1.0 起规范拼写为 `Box<T>`（见 docs/language-spec.md §1.2）。


> 锚点：v0.88.0 / HEAD `10c7e439`（2026-11-21）。判据来源：[pointer-free-v2 附录 A](../../proposals/pointer-free-v2.md#L190-L262) 与 §C.5。
>
> **状态口径**：`已过` = 有具名可复跑探针/命令且判据可复核；`部分` = 有证据但缺判据的某一半；
> `缺失` = 没有证据；`阻塞` = 依赖未落地（lint / std 发版 / 环境），不是“待办”。
>
> **范围**：只收 P-1…P-6（含 §C.5 的 P-3.7 / P-3.8 / P-4.6 / P-5.7）。P-7.x 原型
> （[j6-evidence](.) 的 p72/p73/p74/p75/ref_out）只证明“能跑”，不冒充本台账；P-8.1 不属 J-6 闸门。
>
> 本文件的 `P-x.y` 行由 `check-docs` 校验：状态枚举、最小可判证据非空、`阻塞` 必须写依据。
> 台账当前结论：**J-6 未过**——22 已过 / 4 部分 / 3 缺失 / 5 阻塞（J 表另计）。
>
> <!-- j6:counts passed=22 partial=4 missing=3 blocked=5 -->

## P-1 语料测量（J-6a）

| 判据 | 最小可判证据 | 现有证据 | 状态 | 负责人 |
| --- | --- | --- | --- | --- |
| P-1.1 固定基线 | 声明扫描范围 + 一条可复跑命令 + 计数一致 | `examples test lib`：1381 个 `.ct` / 31,400 行；字面量 2,321（含 24 处 `#include "…"`）、`char *` 627、`T a[] =` 37、`T a[]` 后缀 38、`ref/out` 16、`new` 54（`3e3c52ad`，命令见下） | 已过 | REQ |
| P-1.2 按特性分类 | 每文件 6 个布尔列的 CSV（路径 + 字面量 / `char *` 形参 / `T a[]` 形参 / `T a[] =` / `ref/out` 标识符 / `new` 标识符），入库可重跑 | [p1_2.csv](p1_2.csv)（1381 行 + 表头，6 列布尔）；生成器 [gen_p1_2.py](gen_p1_2.py)：`python3 docs/planning/j6-evidence/gen_p1_2.py > docs/planning/j6-evidence/p1_2.csv` | 已过 | REQ |
| P-1.3 自动化率 | 迁移 lint dry-run 的「可自动 / 需人工 / 语义需确认」三档百分比 | 阻塞：迁移 lint 尚未实现，无法 dry-run | 阻塞 | DEV |
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
| P-2.5 旧语料 parse | 全量语料 parse 通过；golden 变化逐条 | 干净归档 `a0ce8ef1` 的编译器源与 HEAD 逐字节相同（`git diff a0ce8ef1..HEAD -- selfhost/l0 selfhost/l1 selfhost/l2 selfhost/ct-ast` 为 0 行），故以 HEAD 的 `selfhost/check-ast.sh` 全量输出为准：**1581 passed / 0 failed / 5 skipped**（`selfhost/check-all.sh` 第 8 道）；golden 变化清单见 [docs/planning/j6-evidence/goldens-l1-vs-ast.md](goldens-l1-vs-ast.md)。干净归档复跑至 PH-79 段（418 条输出、0 失败）后中止，作为旁证而非唯一证据 | 已过 | DEV |

## P-3 String/Str ABI（J-6c）

| 判据 | 最小可判证据 | 现有证据 | 状态 | 负责人 |
| --- | --- | --- | --- | --- |
| P-3.1 16 字节句柄 + 8 字节头 | `_Static_assert`；`header_size(T)` 对齐 | [p80_layout/abi.ct](../../../test/ast/p80_layout/abi.ct)、[p81_box/layout.ct](../../../test/ast/p81_box/layout.ct) | 已过 | DEV |
| P-3.2 复制 / Drop 协议 | 参数 / 返回 / 字段 / `Vec<String>` / `box<String>` 的 refcount 轨迹 + ASan | [p80_retain.sh](../../../test/ast/p80_retain.sh)、[p80_layout/uaf.ct](../../../test/ast/p80_layout/uaf.ct) | 已过 | DEV |
| P-3.3 字面量视图 | 字面量 `Str` 无 Drop；`String` 有 Drop；immortal 空串 `refs=-1` | [p80_literal.sh](../../../test/ast/p80_literal.sh) | 已过 | DEV |
| P-3.4 `.data` / `cstr()` | `.data` 只读、不保证 NUL；子视图 `cstr()`；`printf` 负例 | [p80_cstr](../../../test/ast/p80_cstr)（`prog.ct` + `neg_data_value` / `neg_data_write` / `neg_printf_data`） | 已过 | DEV |
| P-3.5 C 边界 | `.m.ct` / shim / `.h.ct` 全部 `char *`；无隐式转换 | [examples/47](../../../examples/47_chain_factory)、[examples/48](../../../examples/48_string_steps) 的 `.m.ct` + shim；`p80_cstr/neg_printf_data.ct`（`.data` → `%s` 硬错）；函数实参 `String`/`Str` → `char *` 被拒。**新发现**：`char *p = s` 与 `return s`（`String`/`Str`）仍被接受并发射 `char *p = s;` 坏 C；承接：DEV 补赋值/返回/变参三类负例（owner DEV） | 部分 | DEV |
| P-3.6 跨仓 dry-run | `std::str::Str` 限定名并存；消费者清单；std 新版本 | 阻塞：std 新版本未发（PKG-22 目标名 `CharStr` 待包侧落地），没有 dry-run 对象 | 阻塞 | DEV |
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
| P-5.2 旧值释放 / 别名 | retain 右值 → release 旧值 → 写入；无 UAF | 缺失：`out String` / `ref String` 的 owning 旧值释放轨迹没有专项夹具。承接：DEV 在 `p80_retain` 增加 out/ref 组合（owner DEV，未在本轮闭合） | 缺失 | DEV |
| P-5.3 `ref` 赋值 vs 显式 release | 赋值允许；显式 release 硬错 | 缺失：`ref String` 赋值与 `release(ref)` 两例都没有夹具。承接：DEV 补两侧矩阵（owner DEV，未在本轮闭合） | 缺失 | DEV |
| P-5.4 `out` 错误路径 | 赋值即生效；PH-70 保证至少一次 | `p70_definite.sh` 覆盖定值；错误路径（提前 `return` / `err:`）的显式 out 用例缺。承接：DEV 补错误路径夹具（owner DEV） | 部分 | DEV |
| P-5.5 `out/ref` 借用类型 | `out Str` / `ref int[]` 白名单 + 底层契约 | 缺失：借用类型作 `out/ref` 的夹具。承接：DEV 补 `out Str` / `ref int[]` 正例与越界负例（owner DEV） | 缺失 | DEV |
| P-5.6 泄漏 / 双释放 | ASan + `__ct_allocs/__ct_frees` | `check-sanitizers` 586 checks 广覆盖；`p80_retain` 的 owning 路径在 ASan/UBSan 下逐例跑；缺 `ref/out` 专项组合。承接：DEV 把 out/ref 夹具并入 ASan 组合（owner DEV） | 部分 | DEV |
| P-5.7 字符串下标与不可变 | `String[i]` 单码点只读；`U16String[i]` 单 code unit 只读；写操作硬错 | [p80_methods/prog.ct](../../../test/ast/p80_methods/prog.ct) 第 34 行 `view = s[1]` 只读正例；[neg_write_index.ct](../../../test/ast/p80_methods/neg_write_index.ct) `s[0] = 'x'` 硬错；[neg_u16_write.ct](../../../test/ast/p80_methods/neg_u16_write.ct) U16 写硬错 | 已过 | DEV |

## P-6 跨仓迁移（J-6f）

| 判据 | 最小可判证据 | 现有证据 | 状态 | 负责人 |
| --- | --- | --- | --- | --- |
| P-6.1 消费者清单 | `import std::str::Str` 全部有迁移动作 | 阻塞：std 新版本（`CharStr`）未发，消费者清单无对象 | 阻塞 | DEV |
| P-6.2 包版本 / 索引 | std 新 MINOR；索引行；旧锁不破坏 | 阻塞：随 PKG-22 包侧发布 | 阻塞 | DEV |
| P-6.3 迁移 dry-run | 典型工程 `Str`→`String` 可编译、行为等价 | 阻塞：需新 std 才能 dry-run | 阻塞 | DEV |
| P-6.4 发布前检查 | README / spec / roadmap 三处同步 | README / spec / roadmap 的 v1.0 文案已同步；std 版本相关段落待发版。承接：REQ 在 std 发版后复核三处（owner REQ） | 部分 | REQ |

## J-3 / J-4 / J-5 逐张核对

| 判据 | 核对结论 | 证据 | 状态 |
| --- | --- | --- | --- |
| J-3 String/Str | 与实测一致：16 字节句柄、8 字节头、显式 `.to_string()` / `.as_str()` | spec §4.70 + `p80_*` | 已过 |
| J-4a 借用位置 | **原文与实测偏离**：原文写「容器 / Option / Result / 全局硬错」，实测 `Vec<Str>`、`Option<Str>`、ADT 负载、全局字面量 `Str` 可编译（存视图）；字段 / `Map` 键仍硬错 | spec §4.70「按实测」+ [LANG-22](../../../issues/lang/lang-22-nonimmortal-view-store-lint.md)（warn 规划） | 部分（判据需修订） |
| J-4b `ref/out` 逃逸 | 契约文本未成文；spec §4.68 只写行为，没有“可存储 / 可传更长寿命位置”的条款 | spec §4.68；承接：DEV/REQ 补逃逸条款并加 `ref/out` 存储负例（owner DEV，未在本轮闭合） | 缺失 |
| J-4c box 环 | 作者责任 + 直接环编译期告警；无环检测 | [p82_cycle.sh](../../../test/ast/p82_cycle.sh) + spec §4.72 | 已过 |
| J-5 机制自洽 | 四家族（借用视图 / 句柄 / 参数糖 / 签名糖）与实测一致；`new` 随 box 同进退 | spec §4.68–§4.70 + `p79` / `p80` / `p81` | 已过 |

## 结论

- **J-6 未过**：22 已过 / 4 部分 / 3 缺失 / 5 阻塞（J 表另计；`<!-- j6:counts -->` 与逐行计数由 check-docs 校验）。
- 本轮闭合：P-1.2（[p1_2.csv](p1_2.csv) + 生成器）、P-3.7 / P-3.8 / P-4.3（SH-106）/ P-4.5（guide §7.1）/ P-5.7。
- 未闭合且已写承接：P-5.2 / P-5.3 / P-5.5（out/ref 借用与释放夹具）、
  P-5.4 / P-5.6 / P-6.4（错误路径、ASan 组合、std 发版后复核）、P-3.5（新发现：`char *p = s` / `return s`
  仍被接受并发射坏 C）。
- **P-1.3 / P-3.6 / P-6.1–P-6.3** 在 lint 与 std 发布前不可判，保持阻塞，不写“预计通过”。
- **J-4a 判据需修订**：照原文写“容器硬错”会与 v0.88 实测冲突；按实测改判据，风险由 LANG-22 承接。
- **J-4b** 仍缺 `ref/out` 逃逸契约条款与存储负例，承接 owner DEV。
