# J-6 证据台账（SH-104 / V1-C1）

> 锚点：v0.88.0 / HEAD `10c7e439`（2026-11-21）。判据来源：[pointer-free-v2 附录 A](../../proposals/pointer-free-v2.md#L190-L262) 与 §C.5。
>
> **状态口径**：`已过` = 有具名可复跑探针/命令且判据可复核；`部分` = 有证据但缺判据的某一半；
> `缺失` = 没有证据；`阻塞` = 依赖未落地（lint / std 发版 / 环境），不是“待办”。
>
> **范围**：只收 P-1…P-6（含 §C.5 的 P-3.7 / P-3.8 / P-4.6 / P-5.7）。P-7.x 原型
> （[j6-evidence](.) 的 p72/p73/p74/p75/ref_out）只证明“能跑”，不冒充本台账；P-8.1 不属 J-6 闸门。
>
> 本文件的 `P-x.y` 行由 `check-docs` 校验：状态枚举、最小可判证据非空、`阻塞` 必须写依据。
> 台账当前结论：**J-6 未过**——15 已过 / 9 部分 / 5 缺失 / 5 阻塞。

## P-1 语料测量（J-6a）

| 判据 | 最小可判证据 | 现有证据 | 状态 | 负责人 |
| --- | --- | --- | --- | --- |
| P-1.1 固定基线 | 声明扫描范围 + 一条可复跑命令 + 计数一致 | `examples test lib/std`：1363 个 `.ct` / 31,183 行；字面量 2,275（扣除 24 处 `#include "…"`）、`char *` 627、`T a[] =` 36、`T a[]` 后缀 37、`ref/out` 16、`new` 54（命令见下） | 已过 | REQ |
| P-1.2 按特性分类 | 每文件 6 个布尔列的 CSV（路径 + 字面量 / `char *` 形参 / `T a[]` 形参 / `T a[] =` / `ref/out` 标识符 / `new` 标识符），入库可重跑 | 只有全局计数，没有逐文件表 | 缺失 | REQ |
| P-1.3 自动化率 | 迁移 lint dry-run 的「可自动 / 需人工 / 语义需确认」三档百分比 | 阻塞：迁移 lint 尚未实现，无法 dry-run | 阻塞 | DEV |
| P-1.4 快照回放 | 基线 sha + 复跑命令 + 计数与 P-1.1 一致 | `10c7e439` + 下方命令；与 P-1.1 同一命令 | 已过 | REQ |

```sh
git rev-parse --short HEAD                                   # 10c7e439
find examples test lib/std -name '*.ct' | wc -l             # 1363
find examples test lib/std -name '*.ct' -print0 | xargs -0 cat | wc -l   # 31183
find examples test lib/std -name '*.ct' -print0 | xargs -0 grep -ho '"[^"]*"' | wc -l   # 2299
find examples test lib/std -name '*.ct' -print0 | xargs -0 grep -hoE '#include[[:space:]]*"[^"]*"' | wc -l   # 24
find examples test lib/std -name '*.ct' -print0 | xargs -0 grep -hoE 'char[[:space:]]*\*' | wc -l   # 627
find examples test lib/std -name '*.ct' -print0 | xargs -0 grep -hoE '[A-Za-z_][A-Za-z0-9_<>]*[[:space:]]+[A-Za-z_][A-Za-z0-9_]*\[\][[:space:]]*=' | wc -l   # 36
find examples test lib/std -name '*.ct' -print0 | xargs -0 grep -hoE '[A-Za-z_][A-Za-z0-9_<>]*[[:space:]]+[A-Za-z_][A-Za-z0-9_]*\[\]' | wc -l   # 37
find examples test lib/std -name '*.ct' -print0 | xargs -0 grep -hoE '\b(ref|out)[[:space:]]+[A-Za-z_]' | wc -l   # 16
find examples test lib/std -name '*.ct' -print0 | xargs -0 grep -hoE '\bnew\b' | wc -l   # 54
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
| P-2.5 旧语料 parse | 全量语料 parse 通过；golden 变化逐条 | 本机 `check-ast` 2026-11-21：1576 passed / 0 failed / 3 skipped，另有 1 个 Renode 环境失败（缺 `uart.txt`）；未在干净归档复跑，golden 变化未逐条 | 部分 | DEV |

## P-3 String/Str ABI（J-6c）

| 判据 | 最小可判证据 | 现有证据 | 状态 | 负责人 |
| --- | --- | --- | --- | --- |
| P-3.1 16 字节句柄 + 8 字节头 | `_Static_assert`；`header_size(T)` 对齐 | [p80_layout/abi.ct](../../../test/ast/p80_layout/abi.ct)、[p81_box/layout.ct](../../../test/ast/p81_box/layout.ct) | 已过 | DEV |
| P-3.2 复制 / Drop 协议 | 参数 / 返回 / 字段 / `Vec<String>` / `box<String>` 的 refcount 轨迹 + ASan | [p80_retain.sh](../../../test/ast/p80_retain.sh)、[p80_layout/uaf.ct](../../../test/ast/p80_layout/uaf.ct) | 已过 | DEV |
| P-3.3 字面量视图 | 字面量 `Str` 无 Drop；`String` 有 Drop；immortal 空串 `refs=-1` | [p80_literal.sh](../../../test/ast/p80_literal.sh) | 已过 | DEV |
| P-3.4 `.data` / `cstr()` | `.data` 只读、不保证 NUL；子视图 `cstr()`；`printf` 负例 | [p80_cstr](../../../test/ast/p80_cstr)（`prog.ct` + `neg_data_value` / `neg_data_write` / `neg_printf_data`） | 已过 | DEV |
| P-3.5 C 边界 | `.m.ct` / shim / `.h.ct` 全部 `char *`；无隐式转换 | [examples/47](../../../examples/47_chain_factory)、[examples/48](../../../examples/48_string_steps) 的 `.m.ct` + shim；`p80_cstr` 的 printf 负例。缺「无隐式转换」的系统负例矩阵 | 部分 | DEV |
| P-3.6 跨仓 dry-run | `std::str::Str` 限定名并存；消费者清单；std 新版本 | 阻塞：std 新版本未发（PKG-22 目标名 `CharStr` 待包侧落地），没有 dry-run 对象 | 阻塞 | DEV |
| P-3.7 `U16String` / `U16Str` 类型与工厂 | `from_utf8` / `from_utf16` / `to_utf8` / `to_utf16`；`len` 为 code unit；示例可编译 | [p80_methods/prog.ct](../../../test/ast/p80_methods/prog.ct) 覆盖 `U16String.from_utf8` 与方法集；`from_utf16` / `to_*` 未见专项用例 | 部分 | DEV |
| P-3.8 `U16String` 核心方法集 | snake_case 方法表；越界 / 负下标 / `Option` 返回与 JS 语义对照 | `p80_methods`（方法表）+ [neg_u16_write.ct](../../../test/ast/p80_methods/neg_u16_write.ct)；越界 / 负下标 / `Option` 对照缺 | 部分 | DEV |

## P-4 借用位置矩阵（J-6d）

| 判据 | 最小可判证据 | 现有证据 | 状态 | 负责人 |
| --- | --- | --- | --- | --- |
| P-4.1 存储位置硬错 | 字段 / 全局 / 接口 / box / Option / Result / 容器 / 数组元素 / 泛型实参 / 闭包捕获 | [p79_places.sh](../../../test/ast/p79_places.sh)、`p81_box/neg_field_str.ct`、`neg_box_str.ct`、`neg_box_slice.ct`、[241_map_str_key](../../../test/ast/241_map_str_key/prog.ct) | 已过 | DEV |
| P-4.2 复合类型递归 | `Vec<int[]>` / `Map<Str,int>` / `struct { Str s; }` 硬错 | 241_map_str_key（`Map<Str>` 硬错）、`neg_field_str`（`struct { Str }` 硬错）；`Vec<Str>` / `Option<Str>` 实测可编译（视图），与 J-4a 原文偏离，见下方 J 表 | 已过 | DEV |
| P-4.3 返回值契约 | 直接 `return 局部切片 / as_str()` 可 lint；参数 / 字面量视图正例 | 缺失：`Str` 逃逸 lint 未实现（SH-106），切片只有 `slice escape` warning | 缺失 | DEV |
| P-4.4 诊断质量 | 错误指向具体字段 / 泛型实参 / 闭包捕获 | `p79_*` / `p80_*` / `p81_box` 的 `neg_*` 逐条断言诊断文本 | 已过 | DEV |
| P-4.5 残留风险 | 透传路径文档化 | [guide-for-c-programmers §3.4 / §7](../../guide-for-c-programmers.md)；缺逐类透传清单 | 部分 | REQ |
| P-4.6 切片 place 语义 | `s[i]` 读写、越界 trap、`get` 软访问、`const T[]` 写硬错 | [p79_basic.sh](../../../test/ast/p79_basic.sh) / [p79_index.sh](../../../test/ast/p79_index.sh)（`const_write` 断言） | 已过 | DEV |

## P-5 `ref/out` 所有权（J-6e）

| 判据 | 最小可判证据 | 现有证据 | 状态 | 负责人 |
| --- | --- | --- | --- | --- |
| P-5.1 `out` 未初始化 | 硬错或零初始化；无 UB | [p70_definite.sh](../../../test/ast/p70_definite.sh)、[p78_basic.sh](../../../test/ast/p78_basic.sh)、[ref_out/bad_out_uninit.ct](ref_out/bad_out_uninit.ct) | 已过 | DEV |
| P-5.2 旧值释放 / 别名 | retain 右值 → release 旧值 → 写入；无 UAF | 缺失：没有 owning 旧值的释放轨迹用例 | 缺失 | DEV |
| P-5.3 `ref` 赋值 vs 显式 release | 赋值允许；显式 release 硬错 | 缺失：两侧矩阵都没有夹具 | 缺失 | DEV |
| P-5.4 `out` 错误路径 | 赋值即生效；PH-70 保证至少一次 | `p70_definite.sh` 覆盖定值；错误路径的显式用例缺 | 部分 | DEV |
| P-5.5 `out/ref` 借用类型 | `out Str` / `ref int[]` 白名单 + 底层契约 | 缺失：没有借用类型作 `out/ref` 的夹具 | 缺失 | DEV |
| P-5.6 泄漏 / 双释放 | ASan + `__ct_allocs/__ct_frees` | `check-sanitizers` 586 checks 广覆盖；缺 `ref/out` 专项组合 | 部分 | DEV |
| P-5.7 字符串下标与不可变 | `String[i]` 单码点只读；`U16String[i]` 单 code unit 只读；写操作硬错 | `p80_methods/neg_u16_write.ct`（U16 写硬错）；`String[i]` 只读正例缺 | 部分 | DEV |

## P-6 跨仓迁移（J-6f）

| 判据 | 最小可判证据 | 现有证据 | 状态 | 负责人 |
| --- | --- | --- | --- | --- |
| P-6.1 消费者清单 | `import std::str::Str` 全部有迁移动作 | 阻塞：std 新版本（`CharStr`）未发，消费者清单无对象 | 阻塞 | DEV |
| P-6.2 包版本 / 索引 | std 新 MINOR；索引行；旧锁不破坏 | 阻塞：随 PKG-22 包侧发布 | 阻塞 | DEV |
| P-6.3 迁移 dry-run | 典型工程 `Str`→`String` 可编译、行为等价 | 阻塞：需新 std 才能 dry-run | 阻塞 | DEV |
| P-6.4 发布前检查 | README / spec / roadmap 三处同步 | README / spec / roadmap 的 v1.0 文案已同步；std 版本相关段落待发版 | 部分 | REQ |

## J-3 / J-4 / J-5 逐张核对

| 判据 | 核对结论 | 证据 | 状态 |
| --- | --- | --- | --- |
| J-3 String/Str | 与实测一致：16 字节句柄、8 字节头、显式 `.to_string()` / `.as_str()` | spec §4.70 + `p80_*` | 已过 |
| J-4a 借用位置 | **原文与实测偏离**：原文写「容器 / Option / Result / 全局硬错」，实测 `Vec<Str>`、`Option<Str>`、ADT 负载、全局字面量 `Str` 可编译（存视图）；字段 / `Map` 键仍硬错 | spec §4.70「按实测」+ [LANG-22](../../../issues/lang/lang-22-nonimmortal-view-store-lint.md)（warn 规划） | 部分（判据需修订） |
| J-4b `ref/out` 逃逸 | 契约文本未成文；spec §4.68 只写行为，没有“可存储 / 可传更长寿命位置”的条款 | spec §4.68 | 缺失 |
| J-4c box 环 | 作者责任 + 直接环编译期告警；无环检测 | [p82_cycle.sh](../../../test/ast/p82_cycle.sh) + spec §4.72 | 已过 |
| J-5 机制自洽 | 四家族（借用视图 / 句柄 / 参数糖 / 签名糖）与实测一致；`new` 随 box 同进退 | spec §4.68–§4.70 + `p79` / `p80` / `p81` | 已过 |

## 结论

- **J-6 未过**：15 已过 / 9 部分 / 5 缺失 / 5 阻塞。
- 先清 **P-1.2**（逐文件 CSV）与 **P-2.5**（干净归档复跑 + golden 差异清单）；两者不需要新能力。
- **P-4.3 / P-5.2 / P-5.3 / P-5.5** 各自缺一份最小夹具，可并入 v1.0 前的测试补齐。
- **P-1.3 / P-3.6 / P-6.1–P-6.3** 在 lint 与 std 发布前不可判，保持阻塞，不写“预计通过”。
- **J-4a 判据需修订**：照原文写“容器硬错”会与 v0.88 实测冲突；按实测改判据，风险由 LANG-22 承接。
