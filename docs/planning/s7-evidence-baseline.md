# S7 证据基线：`--types` 假阳性现数 + 写入摘要用例矩阵

> 状态：**基线完成（2026-11-26）**，供 [`v1-PH-2`](../phases/v1-PH-2/card.md) **S7** 使用。
> D 轨道产物：只测、只列清单，不改代码、不改夹具、不改默认严重级。

## 0 用途

S7 要同时做两件事，但顺序相反：

1. **REQ-TYPE-1**：把 `--types` 的三类判定（赋值 / 初值 / `return` / `$` 目标 / 调用实参）接进默认路径——
   前提是 **FP=0 证据**；
2. **REQ-MEM-2**：用 S1b 的清理 CFG 做「单元内一层写入摘要」——前提是**用例矩阵**先定死。

本文给出这两份输入。测法用冻结 seed 构建的编译器（与门禁同源），命令可复现。

## 1 口径

```sh
cc -std=c99 -I bootstrap/ct-ast bootstrap/ct-ast/*.c -o /tmp/ct-ast-bin
/tmp/ct-ast-bin check --types <file.ct>          # 退出码与逐行诊断
/tmp/ct-ast-bin check <file.ct>                  # 对照：不加 --types
```

「FP」定义：**`--types` 在语法合法、语义合法的代码上新增的诊断**。既有语义诊断（`loop` 遮蔽、
`Str` 视图寿命、`loop` 计数类型、trait 方法歧义）不计入 FP，但要单列，因为默认化后它们会改变语料退出码。

## 2 FP=0 实测（2026-11-26）

| 语料 | 文件数 | 非零退出 | `--types` 相对普通 `check` 的新增 |
| --- | --- | --- | --- |
| `examples/[0-9][0-9]_*/*.ct`（编号样例入口） | 46 | **0** | 0 |
| `test/cases/*.ct`（静态 golden 用例） | 25 | 1 | **0**（逐行相同） |
| `test/ast/*/prog.ct`（AST 夹具） | 308 | 10 | **0**（10/10 逐行相同） |

结论：**`--types` 自身在当前语料上 FP=0**。非零的 11 个文件全部由既有 `check` 诊断触发，
`ct build` 对同一条目只给 `warning:`、退出 0（实测 `06_name_collision.ct`、`241_map_str_key` 等）。

`find examples -name '*.ct'` 的 225 个文件里另有 45 个非零，全部是 `neg_*.ct` 负例或
`examples/tour/**`、`wave1-demo` 的故意失败演示，不属于 FP 语料。

## 3 既有诊断清单（默认化会改变这 11 个文件的退出码）

| 族 | 条数（文件） | 代表 | 现状 |
| --- | --- | --- | --- |
| `loop` / `foreach` 遮蔽 | 4 | `test/ast/101_loop_two_counters/prog.ct` | `check` error、`build` warning |
| 非 immortal `Str` 视图入库 | 5 | `test/ast/241_map_str_key/prog.ct` | 同上 |
| `loop` 计数非整数 | 1 | `test/ast/loop_count_type/prog.ct` | 同上 |
| trait 方法歧义 | 1 | `test/cases/06_name_collision.ct` | 同上（golden 用例） |

这四条族都是**真阳性**（代码确实有风险或歧义），问题只在「默认路径该用 error 还是 warning」。
S7 必须先裁定这一条，否则默认化会一次性把这 11 个夹具判红。

## 4 三个策略（供 REVIEW 裁定）

| 方案 | 做法 | 代价 | 风险 |
| --- | --- | --- | --- |
| **A（推荐起步）** | 只把 `--types` 三类升为默认 error；四条既有族保持 `warning`，新增 `--check-level=strict` 才升 error | 最小；语料 rc 不变 | 与「默认严格」的目标只走了一半 |
| B | 全部升 error，11 个夹具逐条迁移（改代码或加显式豁免） | 需要改 11 个夹具 + 4 条族的口径说明 | 可能与「夹具是 oracle」冲突 |
| C | 分族灰度：先 `--types`，再 `Str` 视图族，再遮蔽族，每族一个切片 | 三次切换，每次都能回滚 | 周期最长 |

建议：**A 起步 → C 的灰度顺序收尾**；B 只在 REVIEW 认定「这 11 个夹具本就该红」时启用。

## 5 REQ-MEM-2 用例矩阵（单元内一层写入摘要）

判定形态：被调函数把某个形参写进全局 / 字段 / 容器时，该形参必须标 `borrow`（或形参本身就是
`own` / 值拷贝），否则**调用点**硬错。函数指针、递归、跨单元一律保守放行。

| # | 用例 | 形态 | 期望 |
| --- | --- | --- | --- |
| P1 | 形参标 `borrow` 后写全局 | `void put(borrow struct Conn *c) { g = c; }` | 放行 |
| P2 | 写入的是 immortal 字面量 | `g = "lit";` | 放行 |
| P3 | 所有权转移（`own` / 值拷贝） | `void take(struct Conn c) { g = c; }` | 放行 |
| P4 | 只读形参（无写入） | `int fd(borrow struct Conn *c) { return c->fd; }` | 放行，不误报 |
| P5 | 函数指针调用 | `fn_t f = put; f(c);` | 保守放行 |
| P6 | 递归自调用 | `void walk(struct Conn *c) { walk(c); }` | 保守放行 |
| N1 | 未标 `borrow` 的形参被写入全局 | `void put(struct Conn *c) { g = c; }` + `put(local)` | 调用点硬错 |
| N2 | 写入结构体字段 | `void put(struct Holder *h, struct Conn *c) { h->c = c; }` | 硬错 |
| N3 | 写入容器 | `void keep(struct Conn *c) { v.push(c); }` | 硬错 |
| N4 | 一层传递 | `put(c)` 调 `sink(c)`，`sink` 写全局 | 硬错（一层即可判） |
| N5 | 条件写入 | `if (k) { g = c; }` | 硬错（保守） |
| N6 | `Str` 视图入库（既有族） | `m.insert(key, name)` | 归 §3 族，不重复立案 |
| D1 | `goto` 跳过声明 | `goto L; borrow struct Conn *c = ...; L:` | **deferred**：等 S1b 清理边，暂不判 |
| D2 | 跨单元写入 | `a.ct` 调 `b.ct` 的写函数 | **不在本阶段**（跨单元摘要） |

落盘约定（沿用既有夹具布局）：

- 负例：`test/ast/errors/mem2_*.ct`，由 `check-ast.sh` 的「`test/ast/errors/**` 必须非零退出」段覆盖；
- 正例：`test/ast/<编号>_mem2_*/prog.ct` + 既有 308 夹具的跑法；
- 每条负例只放一个判定点，避免一条夹具同时触发两族诊断（现有负例的惯例）。

## 5.1 S7-c 落地与 P1 冲突（2026-11-27）

实现：`selfhost/ct-ast/frontend/parse/Mem2Writes.h.ct`（parser 定义出口按 body 的 arena
节点区间扫直接写；同一单元内再组合一层；调用点出诊断）。`Fn.pann == 1` 记 `borrow`
（`ref/out` 仍是 2/3，C 签名不变）。build 默认 `error`，`--check-level=warn` 降级、
`--check-level=off` 完全不跑；`check` / `compile` 走硬错。

诊断（硬错，`file:line:col` 指向调用点）：

```text
call to 'put': parameter 'c' is stored outside the call (write at line 4); declare the parameter 'borrow'
```

矩阵实测（2026-11-27）：

| # | 口径 | 实测 |
| --- | --- | --- |
| P1 | `borrow` 形参写全局，期望放行 | **冲突，按更严者保留硬错**（见下） |
| P2 | immortal 字面量 | 通过（`test/ast/315_mem2_literal`） |
| P3 | 值拷贝 / `own` | 通过（无指针，`test/ast/316_mem2_value_param`） |
| P4 | 只读形参 | 通过（`test/ast/317_mem2_readonly`） |
| P5 | 函数指针调用 | 保守放行（`test/ast/318_mem2_fnptr`） |
| P6 | 递归自调用 | 保守放行（`test/ast/319_mem2_recursion`） |
| N1 | 未标 `borrow` 写全局 | 硬错（`test/ast/errors/mem2_n1_write_global.ct`） |
| N2 | 写结构体字段 | 硬错（`mem2_n2_write_field.ct`） |
| N3 | 写容器 | 硬错（`mem2_n3_write_container.ct`） |
| N4 | 一层传递 | 硬错，内外两层各一条（`mem2_n4_one_level.ct`） |
| N5 | 条件写入 | 硬错（保守，`mem2_n5_conditional.ct`） |
| N6 | `Str` 视图入库 | 归 §3 既有族，本阶段不重复立案 |
| D1 | `goto` 跳过 `borrow` 声明 | deferred：不新增判定（`test/ast/s7_mem2_probe.sh`） |
| D2 | 跨单元写入 | 不在本阶段：跨单元调用保守放行（probe 双单元用例） |

**P1 冲突（保留既有语义）。** `void put(borrow struct Conn *c) { g = c; }` 会先命中
§4.40 阶段一的 `check_borrow_store`：`a borrowed pointer cannot be stored in 'g' (its
scope outlives the borrow)`。矩阵 P1 的“放行”与该规则不可同时成立；2026-11-27 所有者裁定
**按更严者保留硬错**，不修改 `bw_neg store_global` 负例，也不放宽 `check_borrow_store`。
写入摘要对 P1 不追加第二条诊断（probe 只断言这一点）。

FP=0（2026-11-27，冻结 seed 构建的编译器）：

- `examples/[0-9][0-9]_*/*.ct` + `test/cases/*.ct` + `test/ast/*/prog.ct` 共 412 个文件（含新增 5 个正例），
  `check` 退出码与基线逐文件相同（0 差异）；
- 全 `examples/**` + `test/**` 共 1513 个 `.ct`（不含 5 个新增 mem2 负例），
  `compile` 退出码逐文件相同（0 差异）；
- 同一 407 个基线语料的 `build` 默认与 `--check-level=off` 退出码相同（0 差异）。

## 6 S7 切片顺序（每片一提交、可回滚）

1. **S7-a**：`--types` 三类进 `build` / `compile` 默认，按方案 A 的严重级；语料 rc 必须不变（46 + 25 + 308 全量重跑）；
2. **S7-b**：`check --types` 与默认路径共用同一判据（消除「`check` error / `build` warning」双口径）——只对 §3 之外的族生效；
3. **S7-c**：写入摘要的最小形态（P1–P4、N1–N5 全绿；P5/P6 显式放行）；
4. **S7-d**：`--check-level=off` 逃生与 `--check-level=strict` 灰度开关；
5. **S7-e**：P-1.3 迁移 lint 三档 dry-run —— **已完成（2026-11-28）**：`tools/migrate_lint.py`，结果见 [p1_3_lint.md](j6-evidence/p1_3_lint.md)。

## 6.1 REQ-TYPE-1 落地（2026-11-27，v1-PH-2 S7）

`--types` 的三类判定进入默认路径，按 §6 的「普通赋值 → `return` → 容器」三片独立
提交、每片单独过 FP=0 后再生成了冻结 seed（`bootstrap/**` 只随各片的 `chore(seed)`
提交变化）。`build` 侧在 v1-PH-1 S3 已是默认 `error`（`types_level=2`），本次不再改动它；
新增的是 `ct compile` 与裸 `ctc <file>` 的默认路径。

### 6.1.1 切片、提交与开关

| 片 | 判定 | 提交 | 默认路径行为 |
| --- | --- | --- | --- |
| S7-a | 声明初值 / 赋值（L32-1/2）、`$` 目标、struct 花括号初值 | `d8eae2c0`（红 `030eb07f`，seed `76f1c6e1`） | compile 默认 `error` |
| S7-b | `return`（L32-3/4/5） | `159d4ef3`（红 `64ee4295`，seed `ee60d855`） | 掩码 1→3 |
| S7-c | 容器 / 泛型固有方法实参（L32-6） | `506f337c`（红 `db4edc17`，seed `dc59ec83`） | 掩码 3→7 |

- 机制：`Diag` 新增一次运行的 `types_class_mask`（1 赋值 / 2 return / 4 容器）与
  `types_class_level`（0 off / 1 warn / 2 error）；三个 `ct_type_class_*` 门只读这一份
  策略，`ct_type_class_warn` 是唯一出口。`--check-level=off|warn|error` 从 build-only
  扩到 compile（`ct check` 仍拒绝，`--types` 仍只认 `ct check`）。
- `build` / `ct check --types` 的 class level 恒为 0，出口逐字回落到原来的
  `record_type_warn` / strict 通道，因此两条路径的判据、文案与退出码不变。
- `--check-level=warn` 在 compile 下报 `warning:` 并继续写 `.c`；`off` 不跑判定，
  产物与接入前逐字节相同。§6 第 4 条的 `strict` 灰度未启用：默认已是 `error`，
  本阶段没有更严的一档。

### 6.1.2 FP=0（冻结 seed 构建的编译器，2026-11-27）

口径：`examples test lib selfhost/ct-ast` 下全部 `.ct`（1593 个）逐文件跑
`ct-ast <file> -o <out>.c`（compile 默认）与 `ct-ast check --types <file>`；
对基线 `660e2b07` 比对「退出码 + 产物 sha256 + 诊断逐行哈希」。
`test/ast/p118_skip.tsv` 的 47 行是既有负例 / 诊断演示 / p32 基线夹具，不算合法件。

| 版本 | compile-green | 退出码变化 | 其中合法件 | `check --types` 变化 |
| --- | --- | --- | --- | --- |
| 基线 `660e2b07` | 803 | — | — | — |
| S7-a | 796 | 7 | **0** | 0 / 1593 |
| S7-b | 790 | 13 | **0** | 0 / 1593 |
| S7-c | 782 | 21 | **0** | 0 / 1593 |

- 21 个变化文件全部命中 `p118_skip.tsv`（`test/ast/check_errors/*`、
  `test/ast/errors/p45_*`、`test/probes/fixtures/p32_*`），是本来就应该判红的负例；
  合法件无新增假阳性。分语料（S7-c 终态 vs 基线）：`examples/` 234 个 `.ct`
  （68 个样例目录）、167 个 compile-green、**0 变化**；`lib/` 8 / 8 / **0**；
  `selfhost/ct-ast/` 67 / 6 / **0**；`test/` 1284 个、622 个 compile-green、
  21 个变化（全部是 skip 表内的负例）。
- 未变化的 compile-green 文件产物 sha256 逐字节相同：判定只读 AST，不写产物。
- `test/ast/p122_types_default.sh` 在 gate 8 内钉住切片边界（探针里 `S7B` / `S7C`
  由各片翻 1）与两条入口的一致性：默认路径首诊断行与 `ct check --types` 首行逐字相同。

> 勘误：`159d4ef3` 与 `506f337c` 的提交正文把 compile-green 余数写成 780 / 772，
> 实际为 **790 / 782**（上表）。数值以本表为准，判定与证据不受影响。

### 6.1.3 负例诊断的前移（同一提交 `a6cba61f` 重基线）

三类判定在**解析期**执行，因此同一条非法语句若同时违反更专用的规则，第一诊断会前移
到本节文案；合法语料不受影响（§6.1.2 已证 FP=0），生成产物也不变。实测有 8 条既有负例
的诊断文本/位置变化，逐条在 `test/probes/p86_error_diags.tsv` 重基线：

| 文件 | 变化 |
| --- | --- |
| `p45_{assign,container,depth,init,return}` | exit 0 / 空 stderr → exit 1 + L32 文案（S7 的目的） |
| `p44_error_type`、`p44_operand` | 文案不变；位置由 emitter 的 `line:1` 换成类型内核的精确 `line:col` |
| `p49_own_addr` | L32-1 先于 L49-1（初值同时类型不匹配）；L49-1 契约仍由 `p49_own_int_addr` 钉住 |

同理 `p80_retain/neg_escape` 的 SH-102 emitter 文案在 `ct build` 上自 v1-PH-1 S3 起就已被
parse-time 判定先行，本片只是让裸 `compile` 路径与它对齐；夹具依旧判红，探针改为钉
`return: expected 'struct String', got 'struct Str'`。

## 7 待裁定

1. §3 四条族的默认严重级（方案 A / B / C）；
2. `borrow` 对 `Str` / `Vec` 这类 view 形参的标注形态（§4.40 只定义了指针）；
3. 写入摘要是否覆盖「写入 `out` 形参」与「写入 `ref` 形参」；
4. `test/cases/06_name_collision.ct` 作为 golden 用例保留歧义判定，还是改成显式 `use` 顺序消解。

## 8 关联

- [`v1-PH-2`](../phases/v1-PH-2/card.md)（S7）
- [requirements-pool](requirements-pool.md)（REQ-TYPE-1、REQ-MEM-1 只复评、REQ-MEM-2）
- [language-spec §4.40](../language-spec.md#440-borrow-与-handbackphase-5-续仅-ct-ast)（`borrow` / `Handback`）
- [language-spec §4.53](../language-spec.md#453-可选类型检查-ct-check---typesphase-32)（`ct check --types`）
- [typed-lowered-ir](../proposals/typed-lowered-ir.md)（S1b 的清理边是写入摘要的前置）
