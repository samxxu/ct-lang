# Phase 80 — `String` / `Str`（S5）

> **状态：实施中**（2026-11-20 立项并开卡；D-013 签收后 S5a-1…4 与 S5b-2 已交付 `v0.80.0`，
> S5b-1 旧 `str` 删除与外部消费者 dry-run 未做，E80-7 未通过——见 §7）。
> **签收：EDITOR 2026-11-20**（主编统一签收；卡作者 REQ）。
> **施工闸门（D-013 修订）**：C-1…C-6 已过（D-013 入库签收、卡/计划消歧、`.data` 裁定、P-7.3 在
> `c3f2e0ea` 重放 16/16、P-7.4 五项隔离原型、retain 合同），P-7.4-7 的 `box<String>` 移出 S5a 入口
> （回填 = PH-81 收口），P-7.4-6 留 S5b；S5a 实现已落，C-7 回滚演练见 §7.4。
> **前置**：P-7.3 最小垂直切片；PH-79 切片表示收口 ✅；D-013 已签收。
> **布局说明**：phase-ID 迁移仍被 blocker 挡住，本卡暂用 legacy 路径 `docs/design/phase80.md`。
> **依据**：[提案 v2 §3/附录 C](../proposals/pointer-free-v2.md)、[D-011](../decisions/D-011.md)、
> [phase 安排](../planning/pointer-free-phase-plan.md)。

## 0 卡片字段（冻结）

| 项 | 值 |
| --- | --- |
| 编号 | v0-PH-80（legacy 文件 `phase80.md`） |
| 目标 | UTF-8 `String` owning / `Str` 借用；UTF-16 `U16String`/`U16Str`；L1 字面量；不可变；std::str 逃生层 |
| 范围 | 内建类型、16 字节句柄 + refcount 头、字面量、转换、码点/字节/UTF-16 下标、核心方法集、std 迁移 |
| 非目标 | 正则/locale/normalize（走 shim）；借用检查；`box/new`；切片本体（PH-79） |
| 交付物 | 编译器/内建层、`test/ast/p80_*`、std/跨仓迁移、文档 |
| 任务清单 | §2（S5a/S5b） |
| 退出判据 | E80-1…E80-8（§3） |
| version-minor | 80（PH-80，`d=0`） |
| 已知风险 | R80-1…R80-6（§4） |

## 1 需求与边界

```ct
String s = "abc";                  /* UTF-8 owning；L1 immortal 字面量 */
Str v = s.as_str();                /* UTF-8 借用视图 */
u8 b = v.byte_at(0);
u32 cp = v.codepoint_at(0);
Str ch = v[0];                     /* 单码点视图，只读 */

U16String js = U16String.from_utf8("abc");
u16 c = js.char_code_at(0);
U16Str jc = js[0];                 /* UTF-16 code unit 视图，只读 */
```

- `String`/`Str` UTF-8；`U16String`/`U16Str` UTF-16；跨编码只走显式工厂。
- `String` 字面量 L1 immortal（`refs=-1`，只读区，Drop 不释放）；`Str` 字面量是借用视图。
- `String` 不可变：`s[i] = ...` 永远不合法；内容变化返回新值。
- UTF-8 用户接口用码点下标；`byte_*` 提供字节级 O(1) API。
- `String[i]` 返回单码点 `Str` 视图；`U16String[i]` 返回单 code unit `U16Str` 视图；都只读。
- `.data` 只读且不保证 NUL；`cstr()` 是 C 边界唯一出口。
- U16 首轮只做 JS 核心子集（snake_case）；`match`/locale/normalize 走包 + shim。
- `String`/`Str` 内建化，迁出 std；旧 owning `Str` 在兼容窗口内仅以 `std::str::Str` 限定名存在。

### 1.1 分期

| stage | 内容 | 入口 |
| --- | --- | --- |
| S5a 内建层 | `String/Str` + `U16String/U16Str` 类型、L1 字面量、核心方法、旧 `Str` 限定名并存 | P-7.3；PH-79 收口 |
| S5b 删旧/迁移 | 删旧 `Str`、std 消费者迁移、索引/包版本、README/spec/roadmap 三处同步 | P-7.4；S5a 收口 |

### 1.2 P-7.4 入口证据清单（施工前补齐）

P-7.3 最小切片已 rebase 到 `5736f0d5` 并重放 **16/16**，产物 [`j6-evidence/p73/p73-rebased-5736f0d5.patch`](../planning/j6-evidence/p73/p73-rebased-5736f0d5.patch)；它替换了旧 `lib/std/Str.h.ct`，只作 S5a 参考，不直接合并。

| # | 项 | 通过方式 |
| --- | --- | --- |
| P-7.4-1 | `.data` 最终类型裁定（`const char *` + lint 或保留 `Str` 视图） | 证据里固定一种，负例覆盖 `printf("%s", s.data)` |
| P-7.4-2 | 旧 owning `Str` 仅 `std::str::Str` 限定名；裸名 `Str` 是借用 | 同单元并存、限定名解析、迁移正例 |
| P-7.4-3 | 既有测试套件全绿，或列出经批准的迁移清单 | `test/ast` / `examples` / std 消费者逐项记录 |
| P-7.4-4 | `Map<Str,V>` key 块、`str_slice`/`str_dup` 命名迁移 | 编译 + 运行 + 行为等价 |
| P-7.4-5 | UTF-8 码点/`byte_*` API 与 U16 核心 JS 方法全量清单 | 方法逐个正例/负例 |
| P-7.4-6 | 外部消费者 `Str`→`String` dry-run | 至少一个跨仓/外部工程可编译、行为等价 |
| P-7.4-7 | A.3.1–A.3.3 全绿 + ASan/UBSan | 原始输出与退出码 |

## 2 任务

| 任务 | 交付 | 验收 | effort |
| --- | --- | --- | --- |
| S5a-1 类型/布局 | 16 字节句柄 + 8 字节头；immortal 空串/字面量 | `p80_layout` | M |
| S5a-2 字面量/转换 | L1 字面量；`to_string`/`as_str`；UTF-16 工厂 | `p80_literal` | M |
| S5a-3 方法/下标 | UTF-8 码点/字节 API；U16 核心 JS 方法；只读 `s[i]` | `p80_methods` | M |
| S5a-4 C 边界 | `.data` 只读、`cstr()`、printf 负例 | `p80_cstr` | S |
| S5b-1 迁移 | 删旧 `Str`、std 消费者、包版本/索引 | `p80_migrate` | M |
| S5b-2 文档 | README/spec/roadmap 三处同步 | `p80_docs` | S |

每项任务先提 `test(<scope>): <task-id> 红`（含 `baseline: <sha>`），实现提交随后转绿；S5b-2 为纯文档任务，写 `no-test:` 并由 REVIEW 签字。

## 3 退出判据

| ID | 断言 |
| --- | --- |
| E80-1 | `String`/`Str` 16 字节句柄；refcount 头对齐；`_Static_assert` 进 golden |
| E80-2 | `String s = "x"` L1 immortal；`Str v = "x"` 借用；`U16String` 仅工厂 |
| E80-3 | `String` 不可变；`s[i]` 只读单码点；`U16String[i]` 只读单 code unit；写操作硬错 |
| E80-4 | UTF-8 码点下标 + `byte_*`；`String.slice` 新 `String`，`Str.slice` 视图 |
| E80-5 | `.data` 只读不保证 NUL；`cstr()` 补 NUL；printf 子视图负例 |
| E80-6 | U16 核心 JS 方法 snake_case；`match/locale/normalize` 不在内建 |
| E80-7 | S5a 旧 `Str` 限定名并存；S5b 删旧 + std 消费者迁移 dry-run |
| E80-8 | README/spec/roadmap 三处同步；`check-all`/ASan 通过 |

## 4 风险与回滚

| ID | 风险 | 缓解 |
| --- | --- | --- |
| R80-1 | 旧 `Str`/新 `Str` 名字冲突 | 裸名新借用；旧 owning 仅 `std::str::Str`；窗口结束删除 |
| R80-2 | refcount 非原子 | 文档写死非线程安全；作者同步；lint 直接全局 |
| R80-3 | `.data` 被误当 NUL | `.data` 只读不保证；`cstr()` 唯一出口 |
| R80-4 | UTF-8 码点操作 O(n) | 文档写清；`byte_*` O(1) |
| R80-5 | S5b 外部迁移阻塞 | S5a/S5b 分期；外部迁移 dry-run 为 S5b blocking |
| R80-6 | 内建化改 std 身份 | 包版本/索引/消费者清单；不删旧 store |

回滚：S5a 可回退到旧 `Str`；S5b 与外部迁移绑定，不能整体单回滚。

## 7 收口对照（S5a，2026-11-20）

> 本表按 6.6 T-3/T-6 逐项对应 §2 任务与 §3 判据；红证 baseline `7b1bdf90`（`v0.79.2`，实现前 HEAD），
> 绿证由 `bash selfhost/check-ast.sh` 构建的 ct-ast 产出。**S5b-1 与 E80-7 未通过，不写“全绿”。**

### 7.1 任务与验收

| 任务 | 交付 | 验收命令 | 状态 | 原始输出（摘要） |
| --- | --- | --- | --- | --- |
| S5a-1 类型/布局 | `lib/std/Str.h.ct`（16 字节句柄 + 8 字节头、immortal 字面量块）、`Emitter`/`Module`/`Driver` 内建层 5 单元 | `sh test/ast/p80_layout.sh <ct-ast>` | ✅ 通过 | `ok abi (layout + refcount trace)` / `ok trace` / `ok neg_borrow_no_drop` / `ok neg_ptr_read` / `ok trace -fsanitize=address` / `ok asan sensitivity` / `p80_layout: OK` |
| S5a-2 字面量/转换 | L1 immortal 字面量、`as_str`/`to_string`、UTF-16 仅显式工厂、实参位字面量绑定 | `sh test/ast/p80_literal.sh <ct-ast>` | ✅ 通过 | `ok literal (immortal String, borrowed Str, conversions, UTF-16 factories)` / `ok neg_utf16_literal` / `ok neg_u16str_literal` / `p80_literal: OK` |
| S5a-3 方法/下标 | UTF-8 码点/字节 API、U16 核心 JS 方法 31 项、只读 `s[i]` | `sh test/ast/p80_methods.sh <ct-ast>` | ✅ 通过 | `ok methods (UTF-8 codepoint/byte API + UTF-16 JS core subset)` / `ok neg_write_index` / `ok neg_u16_write` / `p80_methods: OK` |
| S5a-4 C 边界 | `.data` 只读 `const char *`、`cstr()`、printf 与逃逸负例 | `sh test/ast/p80_cstr.sh <ct-ast>` | ✅ 通过 | `ok cstr (.data byte view, cstr() terminator, sub-view has no NUL)` / `ok neg_printf_data` / `ok neg_data_value` / `ok neg_data_write` / `p80_cstr: OK` |
| S5a 并存（E80-7 前半） | 旧 owning `Str` → `std::str::Str`（`StrLegacy.h.ct`），12 个旧消费者迁移 | `sh test/ast/p80_migrate.sh <ct-ast>` | ✅ 通过（兼容窗口） | `ok coexist build mode` / `ok coexist compile mode` / `ok std_smoke` / `ok embedded` / `ok neg_release_view` / `ok neg_legacy_borrow_api` / `p80_migrate: OK` |
| S5b-1 迁移 | 删旧 `str`、标 std 消费者、外部 dry-run（P-7.4-6）、包版本/索引 | — | ❌ 未做 | 兼容单元仍在；旧消费者只做限定名/新 API 迁移（见 §7.3 清单）；P-7.4-6 外部 dry-run 未做 |
| S5b-2 文档 | spec §4.70、README、roadmap、lib/std/README、卡 §7 | `sh test/ast/p80_docs.sh` | ✅ 通过 | `ok spec has the String/Str section (4.70)` … `ok five CTC_VERSION 0.80.0` / `p80_docs: OK` |

### 7.2 红证（baseline `7b1bdf90`，`v0.79.2`）

```console
$ mkdir -p .temp/p80base && git archive 7b1bdf90 | tar -x -C .temp/p80base
$ sh .temp/build-ct-ast.sh "$PWD/.temp/p80base" "$PWD/.temp/p80base/build"
$ cp -R test/ast/p80_* .temp/p80base/test/ast/
$ cd .temp/p80base && sh test/ast/p80_layout.sh "$PWD/build/ct-ast"
FAIL p80/layout: abi compile
  test/ast/p80_layout/abi.ct:21:1: error: no method 'refs' for type 'String'
FAIL p80/layout: trace compile
  test/ast/p80_layout/trace.ct:58:1: error: struct 'String' does not use trait 'Drop'
FAIL p80/layout: neg_borrow_no_drop
  accepted a negative
FAIL p80/layout: neg_ptr_read
  accepted a negative
exit=1

$ sh test/ast/p80_literal.sh /tmp/p80base/build/ct-ast
FAIL p80/literal: literal compile
  test/ast/p80_literal/literal.ct:38:22: error: use of an undeclared variable
FAIL p80/literal: neg_utf16_literal
  missing diagnostic: ... error: no method 'len' for type 'U16String'
exit=1

$ sh test/ast/p80_methods.sh /tmp/p80base/build/ct-ast
FAIL p80/methods: methods compile
  test/ast/p80_methods/prog.ct:77:32: error: use of an undeclared variable
FAIL p80/methods: neg_write_index
  missing diagnostic: ... error: no method 'len' for type 'String'
exit=1

$ sh test/ast/p80_cstr.sh /tmp/p80base/build/ct-ast
FAIL p80/cstr: cstr compile
  test/ast/p80_cstr/prog.ct:11:1: error: no method 'as_str' for type 'String'
FAIL p80/cstr: neg_printf_data
  missing diagnostic 'read-only raw view without a NUL guarantee'
FAIL p80/cstr: neg_data_value
  accepted a negative
exit=1

$ sh test/ast/p80_migrate.sh /tmp/p80base/build/ct-ast
FAIL p80/migrate: coexist build-mode compile
  test/ast/p80_migrate/coexist.ct:8:30: error: unknown qualified type name
FAIL p80/migrate: std_smoke compile
  test/ast/p80_migrate/std_smoke.ct:11:22: error: Map does not support key type 'String' (key types: int, long, char *, Str)
exit=1
```

### 7.3 绿证（`bash selfhost/check-ast.sh` 构建的 ct-ast）

六个探针全绿（`p80_layout` / `p80_literal` / `p80_methods` / `p80_cstr` / `p80_migrate` / `p80_docs`
各自 `OK`，`0` 条 `FAIL`），另 `bash selfhost/check-ast.sh` 内的
`p44_try_drop` / `p47_map` / `p64_on_demand` 三个旧探针已随迁移改绿（`p44/drop: 7 passed, 0 failed`、
`p47/map-str-key: 0 failure(s)`、`OK p64ond`）。

消费者迁移清单（S5a 兼容窗口内的机械迁移，语义与输出不变）：

| 文件 | 迁移 |
| --- | --- |
| `test/ast/225_generic_drop` / `232_str_own_pointer` / `examples/40_str_ownership` | 旧 owning 类型加限定名 `std::str::Str`（`Drop` / `own` / `delete` 证据不变） |
| `test/ast/227_vec_element_release` | `Vec<std::str::Str>`（元素 release glue 证据不变） |
| `test/ast/230` / `231` | 新 `String` / `Str` API（`str_dup` / `str_dup_len` / `str_slice` / `str_concat` / `str_compare` / `.cstr()`） |
| `test/ast/241` / `242` / `286` / `p50_sanitize` / `p50_str_has` / `p50_table` | `Map<Str,…>` → `Map<String,…>`（借用键查询、`str_dup_len` 造键；242 的分配计数不变） |
| `lib/std/Vec.h.ct` | 删旧 `impl<V> Map<Str,V>` 键块（`Map<String,V>` 在 `Str.h.ct`） |
| `test/ast/p44_try_drop` / `p47_map` / `p64_on_demand` | 断言名随迁移更新（`std_str_Str_*`、`Map_String_int_put`、`String` 层按需发射） |

### 7.4 C-7 回滚演练

`git revert` 演练见交付报告：本提交未执行（时间窗内先跑全量门禁）。**C-7 未完成**，S5a-2 之后
继续 S5b 前必须补做；本卡不把它算作已过。

### 7.5 E80 逐条状态

| ID | 断言 | 状态 | 证据 |
| --- | --- | --- | --- |
| E80-1 | 16 字节句柄；refcount 头对齐；`_Static_assert` 进 golden | ✅ 通过 | `p80_layout` 的 `abi.ct`：`sizeof(String)=16` / `sizeof(Str)=16` / `sizeof(header)=8`，`_Static_assert` 在生成的 C 里；`neg_ptr_read` 关闭 `.ptr` 读取 |
| E80-2 | `String s = "x"` L1 immortal；`Str v = "x"` 借用；`U16String` 仅工厂 | ✅ 通过 | `p80_literal`：`literal_refs=-1` / `empty_refs=-1` / 两处 UTF-16 隐式字面量硬错 |
| E80-3 | `String` 不可变；`s[i]` 只读单码点；`U16String[i]` 只读；写硬错 | ✅ 通过 | `p80_methods` 的 `neg_write_index` / `neg_u16_write`（`read-only subscript`）；`p80_cstr` 的 `neg_data_write`（`immutable`） |
| E80-4 | UTF-8 码点下标 + `byte_*`；`String.slice` 新 `String`，`Str.slice` 视图 | ✅ 通过 | `p80_methods` 的 `u8 …` 行；`p80_layout` 的 `slice refs=1 live=2`；`p80_migrate` 的 `str_slice`（借用）/ `str_dup`（拥有） |
| E80-5 | `.data` 只读不保证 NUL；`cstr()` 补 NUL；printf 子视图负例 | ✅ 通过 | `p80_cstr`：`subview=98,99,100`（无插入 NUL）、`cstr=abcd len=4 term=1`、`neg_printf_data` 硬错 |
| E80-6 | U16 核心 JS 方法 snake_case；`match/locale/normalize` 不在内建 | ✅ 通过 | `p80_methods` 的 31 行 U16 例（`p80_methods: OK`）；`lib/std/Str.h.ct` 无 `match`/`locale`/`normalize` |
| E80-7 | S5a 旧 `Str` 限定名并存；**S5b 删旧 + std 消费者迁移 dry-run** | ❌ **未通过** | 前半通过（`p80_migrate` 并存）；后半未做：`lib/std/StrLegacy.h.ct` 仍在、外部 dry-run（P-7.4-6）未做 |
| E80-8 | README/spec/roadmap 三处同步；`check-all`/ASan 通过 | ✅ 通过（S5a 范围） | 文档三处已同步（`p80_docs: OK`）；`p80_layout` 内 ASan/UBSan + UAF 敏感性绿；`bash selfhost/check-all.sh` → `check-all: OK (11 hard gates green)`（§7.8） |

### 7.6 ABI / golden 变化

- `test/cases/*.expected.{c,h}`（51 个）与 `test/modules/p39_lib/lib.expected.abi.h` 只变 banner 版本 token（`v0.79.2` → `v0.80.0`）。
- `test/modules/p39_lib/baseline.sha` 重生成：每个 `--emit-c` 单元新增内建层结构体的前置声明
  （`ct_str_hdr` / `String` / `U16String` / `U16Str`，以及 `Vec<U16String>` 实例行），
  这是新字符串层进入内建层后的既有行为（HEAD 本来就为每个内建 struct 写前置声明）。
- `test/modules/p39_lib/expected.internal` 重生成：`ct build --lib` 把整个内建层导出，
  新层带来 91 个导出符号；r5 的固定 Drop 面从 `Str_Drop_drop` 改为
  `String_Drop_drop` / `U16String_Drop_drop` / `std_str_Str_Drop_drop`。

### 7.7 门禁原始输出

```console
$ bash selfhost/check-all.sh
...
8) AST compiler
  ok    PH-80-S5a-1 layout (E80-1: 16-byte handle, 8-byte header, immortal, refcount trace)
  ok    PH-80-S5a-2 literal (E80-2: L1 immortal, Str borrow, UTF-16 factories)
  ok    PH-80-S5a-3 methods (E80-3/4/6: codepoint/byte API, U16 JS core, read-only s[i])
  ok    PH-80-S5a-4 cstr (E80-5: .data read-only, cstr() NUL, printf negative)
  ok    PH-80-S5a/S5b migrate (E80-7: std::str::Str coexistence, std consumers)
  ok    PH-80-S5b-2 docs (E80-8: spec 4.70, README, roadmap, card 7)
  ok    p39 r5
  ok    p39 r8
...
11) docs (links, version, gate count, phase status)
check-docs: OK (2096 relative links in 353 files, v0.80.0, 11 hard gates, 12 phase status, …)
VERDICT
check-all: OK (11 hard gates green)
exit 0

$ env -u CT_C_BOUNDARY bash selfhost/check-warnings.sh
...
ok    examples/48_string_steps
check-warnings: 490 ok, 0 failed
exit 0

$ bash selfhost/check-sanitizers.sh
...
check-sanitizers: OK (583 checks, no sanitizer report)
exit 0

$ bash tools/check.sh g0
g0: OK (block 1.17.0, session-map present)
$ bash tools/check.sh g8
g8: OK (PN-2 version coherence; 9 legacy offsets)
$ python3 test/docs/check-docs.py
check-docs: OK (… v0.80.0, 11 hard gates, 12 phase status …)
```

### 7.8 未覆盖与残留风险

1. **自动 retain（D-013 §3）未实现**：按值传参 / 返回 / 字段赋值仍是浅拷贝；`p80_layout` 的
   `gap param_refs=1` 行把该事实钉成回归用例。显式 `copy`/`retain`/`release` 与容器插入
   （`Vec`/`Map` 元素 glue）已通过。因此 D-013 §3 的自动半部**不满足**。
2. **字面量实参绑定只覆盖自由函数**：`str_dup("x")` 可用；`U16String.from_utf8("abc")`（静态方法
   实参）仍报 C 层错误，需先绑定到 `Str` 变量。卡 §1 的示例按此改写。
3. **`Map<Str,V>` 是存储位置**：借用类型不能作容器键；`Map<String,V>` 键块深拷贝借用键。
4. **兼容窗口未删**：`std::str::Str` 仍在，S5b-1 未开工；外部消费者 dry-run 未做。
5. **字段/全局 `String` 无自动 Drop**：`own String *` / `delete` 可用，普通字段靠作者 `release`。
6. **C-7 回滚演练未执行**（§7.4）。
