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

- `examples/[0-9][0-9]_*/*.ct` + `test/cases/*.ct` + `test/ast/*/prog.ct` 共 407 个文件，
  `check` 退出码与基线逐文件相同（0 差异）；
- 全 `examples/**` + `test/**` 共 1508 个 `.ct`，`compile` 退出码逐文件相同（0 差异）；
- 同一 407 个文件的 `build` 默认与 `--check-level=off` 退出码相同（0 差异）。

## 6 S7 切片顺序（每片一提交、可回滚）

1. **S7-a**：`--types` 三类进 `build` / `compile` 默认，按方案 A 的严重级；语料 rc 必须不变（46 + 25 + 308 全量重跑）；
2. **S7-b**：`check --types` 与默认路径共用同一判据（消除「`check` error / `build` warning」双口径）——只对 §3 之外的族生效；
3. **S7-c**：写入摘要的最小形态（P1–P4、N1–N5 全绿；P5/P6 显式放行）；
4. **S7-d**：`--check-level=off` 逃生与 `--check-level=strict` 灰度开关；
5. **S7-e**：P-1.3 迁移 lint 三档 dry-run。

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
