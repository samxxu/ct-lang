# Phase 37 — trait 签名硬错与运行期契约

> **状态：已立项**（2026-11-13 用户授权自动完成；卡已冻结）。
> **基线**：`c6a276b`（Phase 36 收口后的文档治理提交；全量 11 道门禁绿）。S0 在实现提交的父提交上重建二进制并复跑 §2.2，红证记录 `baseline: <sha>`。
> **文档形态**：`phase37-draft.md`；design window 7/12，不触发归档。
> **前置**：[phase36-draft.md](phase36-draft.md)；签名检查独立，不依赖 P31–P36 的语义。
> **红证**：§2.2 为 2026-11-12 历史探针；S0 在基线 `c6a276b` 上重跑并替换。
> **关联**：[phase32-draft.md](phase32-draft.md)、[SH-67](../../issues/selfhost/sh67-closure-method-arg-silent-invalid-c.md)、[modern-oo-gap.md](../modern-oo-gap.md) §6.1。
> **规模**：编译器 100–220；夹具 60–120；文档 30–60；合计 190–400（±40%）。
> **纪律**：不 bump、不打 tag、不 push；tag/push 按 `AGENTS.md` 0.3 `phase-tag-requires-user-approval` 等用户批准。

## 0 卡片字段（冻结）

| 项 | 值 |
| --- | --- |
| 编号 | PH-37 |
| 目标 | impl 签名不一致在 `ct build` / `ct check` 硬错；`--runtime-checks` 提供可关闭的空 vtable 断言 |
| 范围 | O1/O2/O3；不做完整类型系统、不改 `ct compile` warning、不改缺方法检查、不新增 trait 语法 |
| 交付物 | `Parser.h.ct` / `Diag.h.ct` / `main.ct` / `Emitter.h.ct`；`test/ast/errors/p37_*`；`ast/219_runtime_guard`；文档 |
| 任务清单 | §4.1（S0–S6） |
| 退出判据 | E37-1…E37-4（§5） |
| 依赖 | Phase 36 收口；全量门禁基线 `c6a276b` |
| 规范版本 | 1.9.0 |
| version-minor | 37 |
| 已知风险 | R37-1…R37-4（§7） |

## 1 目标与边界

### 1.1 一句话

把 trait impl 的**签名不一致**从「默认编译只告警、`ct check` 才报错」升级为 **`ct build` / `ct check` 硬错**，并给空接口值的派发加一个**默认关闭**的运行期断言。不改类型系统。

### 1.2 三项

| 编号 | 内容 | 今天的状态 |
| --- | --- | --- |
| O1 | 签名不一致在 `ct build` 与 `ct check` 都是硬错，位置沿用方法行、文案沿用既有 warning | `ct build` 退出 0、只 warning；`ct check` 已是 error |
| O2 | `ct build --runtime-checks` 在接口派发前检查 vtable 非空，空则带 `文件:行` abort；默认关闭、关闭时产物不变 | 空接口值 `{0,0}` 派发即段错误 |
| O3 | 三处严重度/文案在 L2 与 ct-ast 之间保持一致，或明确排除段 | 未验证，S0 必须先跑 D39 对差 |

### 1.3 非目标

- 不做完整表达式类型系统、隐式转换规则、指针基类型比较（Phase 32 已锁范围）。
- 不改 trait 方法**存在性**检查（缺方法、拼错今天已硬错，见 §2.2）。
- 不改 `ct compile` 的 warning（快速单文件路径保持宽松，D37-1）。
- 不新增 trait 语法、不做泛型 trait / supertrait（Phase 35）。

### 1.4 关键决策

| 编号 | 决策 | 理由 |
| --- | --- | --- |
| D37-1 | `ct build` / `ct check` 硬错；`ct compile` 保持 warning | build 是生产路径；compile 是「快速 transpile」路径，不破坏既有工作流 |
| D37-2 | 复用既有 warning 文案与 `文件:行:列`，只改严重度 | 不新增一套措辞；`ct check` 已用 error 形状，评审可直接对比 |
| D37-3 | 运行期检查放 `--runtime-checks` 开关，默认关闭 | Z1 零运行时；关闭时产物逐字节不变 |
| D37-4 | 不比较指针基类型与层数 | 与 Phase 32 的 `arg_class` 边界一致，避免误报 |
| D37-5 | L2 对差由 S0 决定：同步升级或在该段排除；排除需评审记录 | L2 是回归 oracle，不能凭本卡猜测它的诊断行为 |

## 2 现状与基线

### 2.1 门禁基线

参考值（**历史量级参考**，v0.30.0 发版）：`check-ast` 1155/0、`check-warnings` 389/0、`test/run` 145、`check-docs` 1036 links / 181 files、`design window 12/12`。这些数字**不是判据**；S0 在 Phase 36 收口提交上实测并替换本节。

### 2.2 红证探针（2026-11-12 实测）

| 探针 | 命令 | 基线输出 |
| --- | --- | --- |
| impl 缺方法 | `ct-ast prog.ct` | `7:18: error: trait method 'perim' is not implemented for struct 'C'` |
| impl 方法名拼错 | `ct-ast prog.ct` | `7:18: error: trait method 'area' is not implemented for struct 'C'` |
| 返回类型 `float` vs `int` | `ct-ast prog.ct` | `8: warning: signature mismatch: ... return type 'float' does not match the trait's 'int'`，**退出 0** |
| 同上 | `ct-ast check prog.ct` | `8:11: error: signature mismatch: ...`，退出 1 |
| 同上，`cc`（不带 `-Werror`） | `cc -std=c99 -Wall prog.c` | 只告警；运行输出 `1`（1.5 被截断），**vtable 里是不兼容函数指针** |
| 参数个数不匹配 | `ct-ast prog.ct` + `cc` | warning；`cc` 报 `incompatible function pointer types`，硬失败 |
| 空接口值派发 | `memset` 后 `s.area()` | 段错误（无 `文件:行`） |

关键点：**存在性已经硬错，签名只差一个严重度**；真正会静默错的是返回类型不匹配——编译和 `cc` 都只告警，程序还能跑出错误结果。

### 2.3 代码锚点

| 主题 | 位置 |
| --- | --- |
| 签名比较（返回/个数/逐位参数） | [Parser.h.ct:2547-2590](../../selfhost/ct-ast/frontend/parse/Parser.h.ct#L2547-L2590) |
| warning 记录 | [Diag.h.ct:386](../../selfhost/ct-ast/tool/diag/Diag.h.ct#L386)（`ct_sig_warn`） |
| 缺方法硬错 | [Parser.h.ct:2657](../../selfhost/ct-ast/frontend/parse/Parser.h.ct#L2657) |
| `ct check` 通道 | `selfhost/ct-ast/main.ct` 的 check 子命令；与 build 共用诊断 |
| 接口派发发射 | `Emitter.h.ct` 的 `_iface` 改写点 |

## 3 语义与落码

### 3.1 O1 严重度提升

- `ct_sig_warn` 增加一个「模式」参数：`check`/`build` 走 `ct_sem_error` 等价路径，`compile` 仍写 warning。
- 文案、行、列一律不变；只把前缀从 `warning:` 改为 `error:`，退出码从 0 改为 1。
- 不写产物：错误路径本来就不落 `.c`；S1 加断言确认失败后目录里没有新 `.c`。
- 三处比较顺序保持：返回类型 → 参数个数 → 逐位参数类型（既有 `else if` 链不改），保证只报第一条。
- 误报边界沿用现状：数组参数 decay 后为 `unknown`、指针不比较基类型（D37-4）。

### 3.2 O2 运行期契约

- 仅在 `--runtime-checks` 下，为每次接口派发插入：
  ```c
  if (!(iface).vt) {
      fprintf(stderr, "%s:%d: runtime check: null vtable in call to '%s'\n",
              __FILE__, __LINE__, "area");
      abort();
  }
  ```
  行号用 `#line` 映回 `.ct`。
- 关闭时零注入；E37-6 用产物 `grep -c "runtime check"` 断言为 0，并逐字节比较开关前后的 `.c`。
- 不检查 `self` 是否为空（合法用法可能传 `NULL` 给不读 self 的方法），只检查 vtable。

### 3.3 O3 L2 对差

S0 先跑 `check-archive.sh` 与 `check-ast.sh` 的诊断对照片段，列出哪些段逐字比较签名 warning。两种合法结论：

1. 同步升级 L2（bug-fix 允许，不加特性）；
2. 仅 ct-ast 升级，并在对照段加**带注释的排除**，评审记录写明原因。

不允许「让 L2 保持 warning 但对照假装通过」。

## 4 切片（每片 ≤150 行）

| 片 | 内容 | 主要文件 | 预估行 |
| --- | --- | --- | --- |
| S0 | 在 Phase 36 收口提交上重建、复跑 §2.2、跑 D39 对差并记录比较范围 | 无源码改动 | 0 |
| S1 | `ct_sig_warn` 的模式参数与 build/check 升级 | `Parser.h.ct` / `Diag.h.ct` | 40–80 |
| S2 | L2 同步或排除（按 S0 结论二选一） | `selfhost/l2/**` 或 `check-ast.sh` | 20–60 |
| S3 | `--runtime-checks` 开关与派发前检查 | `main.ct` / `Emitter.h.ct` | 40–80 |
| S4 | 负例与门禁：四类签名错、产物缺失、开关前后产物一致 | `test/ast/errors/**` / `check-ast.sh` | 50–100 |
| S5 | 文档：language-spec 的诊断表、tutorial、gap 的 §6.1 | `docs/**` | 30–60 |

依赖：S0→S1→S2；S3 可与 S2 并行；S4 依赖 S1/S3；S5 最后。

### 4.1 任务清单（冻结）

| 任务 | 交付物 | 验收 | effort | 回滚 |
| --- | --- | --- | --- | --- |
| S0 | §2.2 红证 + p37 夹具的失败输出 | `bash selfhost/check-ast.sh` 在 p37 段失败；`baseline: c6a276b` | S | 删除夹具/断言 |
| S1 | `ct_sig_warn` 模式参数与 build/check 升级 | `check-ast.sh` 的 `p37_sig_*` 全绿 | M | revert |
| S2 | L2 同步或带注释排除 | `check-archive.sh` / `check-ast.sh` 对差 | S | revert |
| S3 | 缺方法/拼错回归夹具 | `p37_missing` 全绿 | S | 删除夹具 |
| S4 | `--runtime-checks` + 空 vtable 断言 | `ast/219_runtime_guard` 双向断言 | M | revert |
| S5 | 全量门禁与收口记录 | `check-all.sh` 11 绿 | S | 回退记录 |
| S6 | 文档 | `check-docs.py` | S | revert |

映射：S1→E37-1；S2 为 E37-1 的前置对差；S3→E37-2；S4→E37-3；S5→E37-4；S0/S6 无退出判据。

## 5 退出判据（E37-n）

| ID | 断言 | 夹具 | 门禁 |
| --- | --- | --- | --- |
| E37-1 | 返回类型 / 参数类型 / 参数个数三类签名错在 `ct build` 与 `ct check` 硬错（退出 1、恰一条 `error: signature mismatch`、位置为方法行、不写 `.c`）；`ct compile` 三例仍退出 0 且 warning 文案逐字不变 | `test/ast/errors/p37_sig_return.ct` / `p37_sig_param.ct` / `p37_sig_arity.ct` | `check-ast` |
| E37-2 | 缺方法与拼错仍走既有 `not implemented` 硬错，零回归 | `errors/p37_missing.ct` | `check-ast` |
| E37-3 | `--runtime-checks` 下空接口值派发 abort，stderr 含 `prog.ct:<行>` 与 `null vtable`；不带开关时产物无 `runtime check` 且逐字节不变 | `ast/219_runtime_guard` | `check-ast` |
| E37-4 | 全量门禁绿，golden 零变化（除新增夹具） | 全量 | `check-all` |

> 旧草案的 E37-1…E37-5 是同一 `ct_sig_warn` 改动的四类签名错 + 缺方法回归；按 T-5「一条任务不得覆盖 ≥2 条退出判据」，四类签名错合并为 E37-1，缺方法回归保留为 E37-2，运行期/全量顺延为 E37-3/E37-4（2026-11-13 冻结）。

## 6 负例台账（L37-n）

本相**不新增编译期文案**：O1 只改严重度，O2 是运行期消息，故 L37 为空。若 S1 发现必须新增措辞，先在这里登记编号与理由，再进 `test/ast/errors/`。

## 7 风险与开放项

| 编号 | 风险 | 处置 |
| --- | --- | --- |
| R37-1 | 升级后误伤既有 corpus 的「可接受的签名差异」 | S0 先全量扫；误报逐条登记，不在本相放宽规则 |
| R37-2 | L2 与 ct-ast 诊断对差被破坏 | D37-5 二选一，排除必须写明范围 |
| R37-3 | `--runtime-checks` 被误当默认行为 | 文档写清默认关闭；E37-6 双向断言 |
| R37-4 | 返回类型检查对 typedef/数组衰减误报 | 沿用既有 `decl_type_compat` 的 unknown 边界，不扩大 |

开放项：

| 编号 | 内容 | 触发条件 |
| --- | --- | --- |
| T37-1 | 指针基类型/层数比较 | Phase 32 的 `--types` 扩展 |
| T37-2 | `const` 方法一致性 | 有 `const` 方法语法后 |
| T37-3 | 默认开启运行期检查 | 有性能基准后另议 |

## 8 估算与收口

- 编译器 100–220 = S1 40–80 + S2 20–60 + S3 40–80；夹具 50–100；文档 30–60。
- 收口：S0 红证提交（`test(types): P37 红`，含原始输出与基线 sha）；每片 ≤3 文件；仓库任何时刻可构建。
- 收口动作：全量 11 道门禁绿、文档同步、`version-minor=37`；版本 bump 与 tag 按 0.3 `phase-tag-requires-user-approval` 等用户批准，不在自动执行范围内。
