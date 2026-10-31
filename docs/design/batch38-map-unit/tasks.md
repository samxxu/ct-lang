# 任务：`.m.ct` 零成本静态映射（第三十八批）

依据：[spec.md](spec.md)。顺序即依赖顺序；**每一步结束后工作树必须可编译、既有语料全绿**。
本批只落 `selfhost/ct-ast/**` 与文档，不动 `selfhost/l0`、`selfhost/l1`、`selfhost/l2`。

## [x] T0 数据结构

- `frontend/module/Unit.h.ct`：`Unit` 增加 `int is_map;`。
- `frontend/module/Map.h.ct`：`Map` 增加 `is_static` / `type_host` / `host_type[160]`；
  `MapBind` 增加 `recv` / `uses[16]` / `sizeofs[16]`。
- `frontend/sym/Symbols.h.ct`：`Trait` 增加 `is_static`。
- `frontend/parse/Parser.h.ct`：`Parser` 增加 `int unit_is_map;`。
- 验收：构建 ct-ast 零警告；行为无变化；`bash selfhost/check-ast.sh` 全绿。

## [x] T1 文件类型与零产物（S0）

- `Module::base_name` 增出参 `int *is_map`；`.h.ct` / `.m.ct` / `.ct` 三路识别。
- `Module::resolve_import` 增出参 `int *is_map`，按 spec §3.3 在同一 root 内检查两种后缀；
  同 root 并存报歧义；第一轮之后再找普通 `.ct` 并报既有消息。
- `Module::load_unit`：设置 `units[u].is_map` 与 `p->unit_is_map`；依赖若是 map 单元，
  `dep[]` 照记、`depu[]` 照记（输出依赖头时再跳过）。
- `Module::cache_key_of`：map 依赖用 `%s.m;`，header 依赖用 `%s.h;`。
- `Module::build_main`：两处循环跳过 map 单元的发射 / 头 / `cache->hit` / `cache->store`；
  末尾 `cc` 行只列非 map 单元；命令行直接传 `.m.ct` 报
  `a .m.ct unit produces no output; import it from a .ct unit`。
- `tool/driver/driver.h.ct`：compile 模式输入 `.m.ct` 同报该消息。
- `frontend/parse/Parser.h.ct`：
  - `top_decl` 按 spec §3.5 白名单；禁止项按 §7 报错；
  - N_PP 行只允许 `#include` / `#define`；
  - `parse_trait` 置 `is_static`、要求 `pub`、拒绝默认体；
  - `parse_impl` 拒绝静态 trait；`use` 记录处拒绝静态 trait；`parse_type` 拒绝静态 trait 作类型。
- 验收：一个只含 `#include` + `pub trait` + `map` 的 `libc.m.ct` 能被 `ct build` 加载，
  产物目录里**没有** `libc.c` / `libc.h`，末尾 `cc` 行不含 `libc.c`；
  既有 `test/modules/**` 与 golden 逐字节不变。

## [x] T2 命名空间静态调用（S1）

- `Expr::parse_qual_path` 增加 `form = 3`：`A::B::T` 的末段是静态 trait 时返回 trait C 名 + 宿主路径；
  宿主路径为空或与 trait 命名空间不符时报 spec §5.1 的消息；`form = 2` 分支遇到静态 trait 报
  `a static trait has no interface value; call '<host>::<Trait>.<method>()'`。
- `Expr::parse_primary`：`form == 3` 时要求紧跟 `.method(`（否则 `a static trait has no interface value`），
  构造 `N_MCALL`（`a = -1`、`b` = 实参、`aux = 5`、`text` = trait、`text2` = 方法、`text3` = 宿主）。
- `MapBuild::parse` 的 namespace 分支：静态映射不计算 `prefix` / `vtable` / wrapper；
  校验 trait 命名空间 == 宿主。
- `Emit::emit_expr` 的 `N_MCALL` 分支加 `aux == 5` 支路：按 trait + 宿主找静态 map，
  无命中报 `no map binds trait '<T>' to namespace '<path>'`；命中则走 `emit_recipe` 的最小版
  （绑定参数原位替换、`(<actual>)`、直接 callee）。
- 验收：`libc::Env.get("HOME")` 生成 `getenv("HOME")`；产物无 `_iface` / `_vtable` / `vt->`；
  `-Wall -Wextra -std=c99` 零告警；`bash selfhost/check-ast.sh` 全绿。

## [x] T3 recipe 替换与 prologue（S2）

- `MapBuild::check_static_call`：结构校验（一次顶层调用）、绑定参数 token 扫描、`uses[]` /
  `sizeofs[]`、修改检测、允许的非参数标识符（spec §8.5 白名单）；动态映射保持既有 `check_call`。
- `Emit::emit_recipe` 补全 spec §6.3：
  - 值位 `(<actual>)`；
  - `&p` → `&(<TP>){<actual>}`；`&p[…]` → `&((<actual>)[…])`；
  - `sizeof p` → `sizeof(<TP>)`，并触发未使用前缀；
  - `p.field` / `p->field` / `p[i]` 的括号；
  - 未使用参数前缀 `(void)(<actual>), `（按绑定参数顺序）；
  - 多次求值 + 不稳定实参报 `map recipe uses '<p>' more than once; bind the argument to a local first`。
- `Emit::emit_map_prologues(int u)`：`depu` 闭包内 map 单元的 N_PP 按整行去重后输出；
  只在 `emit_unit` 的 banner 之后、`#include "<base>.h"` 之前调用。`emit_program` **不改**——
  compile 模式不解析 import，没有单元表与 map 闭包，`.m.ct` 只能经 `ct build` 使用。
- 依赖头输出（`emit_unit` 与 `write_unit_header`）跳过 map 依赖。
- 验收：spec §6.4 的完整例子逐字生成；`main.c` 含 prologue 的 `#include <stdlib.h>`；
  正例 1、2 运行通过；负例（修改参数 / 重复求值 / 非单次调用）命中精确消息。

## [x] T4 类型宿主（S3）

- `MapBuild::parse` 增加 `for type` 分支：类型拼写、`host_type`、只允许 `.m.ct`、
  「第一个绑定参数是接收者」、arity = 方法 + 1。
- `TypeCheck::expr_type`：`N_MCALL` 的 `aux == 5` / `aux == 6` 返回 `MethodSig.ret`；
  新增接收者类型（含数组 decay）辅助函数。
- `Expr::parse_postfix`：`method_trait` 失败且接收者类型已知时置 `aux = 6`。
- `Emit::emit_type_host_call`：接收者类型 + decay → 在**可见** map（`depu` 闭包）里找
  `host_type == rt && method == text2`；0 个报 `no method '<m>' for type '<type>'`，
  多个报歧义（列出两个 `.m.ct` 路径）；命中的 `recv` 传给 `emit_recipe`。
- 验收：`char a[]` 命中 `char *` 类型宿主；`a.toInt()` → `atoi(a)`；`b.fill(...)` → `memset(...)`；
  `a.scanInto(&x)` → `sscanf(a, "%d", &x)`；`char *` 与其它类型不互相匹配；
  普通 struct 方法优先于类型宿主。

## [x] T5 JSON、测试与关卡（S4）

- `Emit::write_map`：静态映射输出 `"static": true`、`"host": "namespace"|"type"`、
  `"type": "<ctype>"`（仅 type host）、binding 的 `"inline": true` / `"wrapper": false` /
  `"symbol": <callee>`；动态 mapping 字段不变。
- 新增 `test/modules/map_unit/`、`test/modules/map_unit_type/`、`test/modules/map_unit_cross/`。
- 新增负例（spec §9 的 4–11 条）。
- `selfhost/check-ast.sh`：新增模块断言块（零产物、内联文本、零 wrapper、`cc` 行、运行输出、
  JSON 字段）与负例精确消息断言；更新与 import 错误消息相关的既有 grep（若有）。
- `selfhost/check-warnings.sh`：补入新模块用例。
- 验收：`bash selfhost/check-ast.sh` / `check-warnings.sh` 全绿；既有 golden 未重生成。

## [x] T6 文档

- `docs/language-spec.md` §4.10（中英对称）：新增「静态映射（`.m.ct`）」小节——文件类型、
  静态 trait、`host::Trait.method`、`for type`、recipe 替换、prologue、`--emit-map` 字段、
  诊断；明确「仅 ct-ast」。
- `docs/tutorial.md`：加一个 `libc.m.ct` + 消费者的最小例子（中英按现有结构）。
- `bindings/README.md`：写明 binding 的两层——`.m.ct`（零成本功能映射）与 `.h.ct`（有状态封装）；
  列出需要用 C shim 的 API 形状（回调 / 宏 / 全局 / 字段）。
- `docs/glossary.md`：补 `静态 trait` / `映射单元` / `类型宿主` / `prologue`。
- `docs/roadmap.md`：批次列表（中英各一处）的「第三十八批（设计已入库，未实现）」条目**已在入库时加好**，
  实现后只需把「未实现」改为「已实现」并登记版本记录，不要重复添加条目。
- 验收：`grep` 无与新语义冲突的旧表述（§4.10「命名空间宿主必然生成 wrapper」等）。

## [x] T7 收口

- `bash selfhost/check-all.sh` → 九关全绿。
- 手工三件套：ct-ast 自编零警告、`ct <file> -o /tmp/x.c`、`cc -Wall -Wextra` 编译运行。
- 反汇编抽查：生成物在 `-O2` 下无 `blr` / `call *%rax`（间接调用）。
- 不重生成既有 golden 的语义内容；用户已授权同批把 `CTC_VERSION` 五处同步 bump 到 v0.15.0，
  因此 `test/cases/**` 与 `test/modules/**` golden 仅版本 token 变化。
