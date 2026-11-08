# ct 特性巡礼（examples/tour）

> **当前状态（2026-11-09）**：目录已就绪，全量样例通过；**尚未接入 `check-all.sh`**
> （避免与并发的门禁改动冲突），需要可用的 `ct-ast`——可以显式传 `CT=...`，
> 也可以让脚本自行自举。`cases.tsv` 中 `l0=yes` 的样例可用冻结种子复编；
> 目前 L0 可复编的簇是 **01、02、03、09（仅 tier-1 手工版）、11**，
> 其余簇（04–08、10、12–18 以及 09 的 `=>` 样例）仅 ct-ast。
> 15（内存管理）里的悬垂样例只在 `ASAN=1` 时执行，普通跑会明确显示 `skip`，
> 不会被当成通过。
>
> 新增 16（诊断）、17（CLI）、18（构造语义）三簇，共 35 个样例。
> 17 的包管理样例全部走离线路径（`file://` 本地包、缺 `ct.pkg`/`ct.lock` 的错误面、
> 无依赖的 `update`）；真正的远端拉取没有在 CI 里跑，见“已知边界”一节。

这不是语言规范，而是一组**能真编真跑**的样例：每个特性至少两个角度，正面样例逐字节比对
stdout，反例比对确切的 stderr 与退出码。规范以 `docs/language-spec.md` 为准；这里只负责
“跑起来是什么样、边界在哪”。

与 `selfhost/ct-tour.sh` 无关——那个是自举链（L0→L1→L2→ct-ast）的巡检，这里是语言特性。

## 怎么跑

```bash
# 1) 仓库里已有 ct-ast 二进制（或在 PATH 中）
CT=/path/to/ct-ast bash examples/tour/run.sh

# 2) 什么都没有：脚本会用 cc 编译 L0 种子，再自举到 ct-ast（约几十秒）
bash examples/tour/run.sh

# 3) 只跑某一簇，参数是路径子串
CT=/path/to/ct-ast bash examples/tour/run.sh 06_

# 4) 连悬垂样例一起跑（需要 cc 支持 -fsanitize=address）
ASAN=1 bash examples/tour/run.sh
```

脚本不写仓库：编译产物都在 `$TMPDIR/ct-tour-examples.$$`，退出时清理。
`cases.tsv` 是清单（`feature|case|mode|l0|expect_exit|note`）。

- `compile`：`ct prog.ct -o x.c` → `cc -Wall -Wextra -std=c99` → 运行 → 比对 `expected.out`
- `build`：`ct build --emit-c main.ct` → cc（含 `*.shim.c`）→ 运行 → 比对
- `compile-warn`：编译退出 0，stderr 必须逐字节等于 `expected.warn`，随后运行并比对 `expected.out`
- `compile-json`：编译退出 0，stdout 必须是一个可解析的 JSON 且逐字节等于 `expected.json`，
  stderr 为空；随后编译、运行并比对 `expected.out`
- `json-err`：带 `--diagnostics=json` 编译，退出码必须是 1，stdout 为空，
  stderr 逐字节等于 `expected.err`（用来证明 error/note 不进入 JSON 通道）
- `pair`：先编译（预期 0 退出、stderr=`expected.warn`），再 `ct check`（预期 1、stderr=`expected.err`）
- `check` / `clean` / `check-json`：只跑 `ct check`，比对 stderr 或 JSON
- `cli`：读 `args`（每行一个 argv 元素），用固定名为 `ct-ast` 的入口运行；
  `@CASE@`/`@WORK@` 分别展开为样例目录与临时目录。有 `expected.out`/`expected.err`
  就逐字节比对，没有 `expected.err` 时要求 stderr 为空；`expected.gen` 列出必须存在的产物
- `pkg`：与 `cli` 相同，但先把样例目录复制到临时目录再运行，供会写
  `vendor/`、`ct.lock` 的包管理命令使用；`expected.lock` 存在时逐字节比对 `ct.lock`
- `asan`：`cc -fsanitize=address -g`，用 `ASAN_OPTIONS=detect_stack_use_after_return=1` 运行；
  要求非零退出、stdout 为空、stderr 含 `expected.asan` 里的固定片段（ASan 栈里有随机地址，
  只能断言片段）。**默认不跑**，只在 `ASAN=1` 时执行并计入 ok，否则计入 skip。

末行汇总形如 `tour: 80 ok, 0 failed, 1 skipped`；`ASAN=1` 时为 `81 ok, 0 failed, 0 skipped`。

标了 `l0=yes` 的样例还会用**冻结种子** `selfhost/l0/ctc.c` 再编译运行一遍，输出必须一致。
这是“L0 可用”这一列的实测依据。L0 生成物偶尔带 `unused _self` 一类警告，脚本对 L0
只断言能编、能跑、输出一致，不要求零警告（ct-ast 生成物仍要求零警告）。

## 特性清单

| # | 特性 | 归属 | 样例数 | 一句话 |
| --- | --- | --- | --- | --- |
| 01 | trait / struct / impl 与 vtable 动态派发 | **L0** | 3 | 一个 trait 多份 impl，调用点只看接口 |
| 02 | 接口值：参数位 / 返回位自动装箱 | **L0** | 2 | 胖指针 `{self, vt}` 在边界上生成 |
| 03 | 接口作为字段（值字段 / 指针字段） | **L0** | 2 | 组合里的接口派发，注意构造点边界 |
| 04 | `map trait ... for instance` 实例宿主 | ct-ast | 3 | 同一 struct 的不同实例各有一张表 |
| 05 | `map trait ... for type` 类型宿主（标量 / 链式） | ct-ast | 2 | 零成本：调用点直接展开成 C 调用 |
| 06 | `pub type` 别名参与宿主键 | ct-ast | 2 | 别名与底层拼写折叠成同一个键 |
| 07 | `map trait ... for namespace` 命名空间宿主 | ct-ast | 2 | 动态（装箱 `T::ns`）/ 静态（零成本） |
| 08 | `.m.ct` + `.shim.h` / `.shim.c` C 互操作 | ct-ast | 2 | 纯头 shim 对比带 C 状态的链接单元 |
| 09 | 闭包：手工 `(fn, env)` 与 `=>` 字面量 | L0 / ct-ast | 3 | tier-1 ABI 与 tier-2 糖，捕获只读 |
| 10 | `loop(n)` / `loop(a..b)` | ct-ast | 3 | 上界一次求值、半开区间、体必须是块 |
| 11 | 变参 `...` 与 `va_list` | **L0** | 2 | 逐个 `va_arg` 对比转发 `vprintf` |
| 12 | 多单元 `ct build` 与 `pub` 导出 | ct-ast | 2 | 跨单元 vtable、pub 全局与命名空间修饰 |
| 13 | `ct check` 诊断 | ct-ast | 3 | 干净单元 / 同一问题两级严重度 / JSON |
| 14 | trait 默认方法 | ct-ast | 2 | 默认体按 struct 展开；覆盖；成环报错 |
| 15 | 内存管理：AutoDrop / 级联释放 / 装箱借用 / 手动分配 / borrow + Handback | ct-ast | 12 | 正常释放、泄漏、悬垂与归还，含一个 ASan 反例 |
| 16 | 诊断：签名 / 类型 / 二义 / 循环遮蔽 / 错误恢复 / 容量上限 | ct-ast | 15 | 同一发现的文本与 JSON 两个通道，含混合与 note |
| 17 | CLI：`--emit-map` / `--ns-root` / `-I` 提示 / `-h` `-v` / 包管理 / 三种模式 | ct-ast | 18 | 标志与子命令的真实字节输出，包管理走离线路径 |
| 18 | 接口值的构造点：局部量 / 字段 / 数组 / malloc 堆对象 | ct-ast | 2 | 四种位置的 vptr 初始化与派发证据 |

“归属”只说明**当前实现**能不能被 L0 冻结种子吃下，不是设计上的分类。
L0 对 `map`、闭包字面量、`loop`、默认方法、`own`/`Drop`、`borrow`/`Handback`
要么拒绝、要么原样透传成非法 C。

## 样例索引

文件路径都相对于 `examples/tour/`。正例入口是 `prog.ct`（单单元）或 `main.ct`（多单元）。

| 特性 / 样例 | 角度 | 编译器 | 文件 | 产物 |
| --- | --- | --- | --- | --- |
| 01_vtable/minimal | 最小语法：一个 trait、一个 impl、两次调用 | L0 | `01_vtable/minimal/prog.ct` | `expected.out` |
| 01_vtable/two_impls | 同一 trait 两份实现；实参位置装箱 | L0 | `01_vtable/two_impls/prog.ct` | `expected.out` |
| 01_vtable/neg_missing_method | 反例：impl 漏方法 | ct-ast | `01_vtable/neg_missing_method/prog.ct` | `expected.err`，退出 1 |
| 02_iface_value/param | 接口作参数：调用方不知道具体类型 | L0 | `02_iface_value/param/prog.ct` | `expected.out` |
| 02_iface_value/return_pick | 接口作返回值：运行期选择实现 | L0 | `02_iface_value/return_pick/prog.ct` | `expected.out` |
| 03_iface_field/value_field | 接口值字段：表达式树组合 | L0 | `03_iface_field/value_field/prog.ct` | `expected.out` |
| 03_iface_field/ptr_field | 接口指针字段：换绑单元格 | L0 | `03_iface_field/ptr_field/prog.ct` | `expected.out` |
| 04_map_instance/two_instances | 两个实例各一张 vtable | ct-ast | `04_map_instance/two_instances/prog.ct` | `expected.out` |
| 04_map_instance/ns_qualified | 命名空间限定名作实例宿主键 | ct-ast | `04_map_instance/ns_qualified/prog.ct` | `expected.out` |
| 04_map_instance/neg_unbound | 反例：map 漏绑方法 | ct-ast | `04_map_instance/neg_unbound/prog.ct` | `expected.err`，退出 1 |
| 05_map_type/scalars | 标量宿主；同一 `int` 挂两张表 | ct-ast | `05_map_type/scalars/{main.ct,units/*}` | `expected.out` |
| 05_map_type/chain | 结构体宿主；按值返回形成链式调用 | ct-ast | `05_map_type/chain/{main.ct,route/*}` | `expected.out` |
| 06_type_alias/handle | 别名 `Handle *` 与 `struct ct_handle *` 同键 | ct-ast | `06_type_alias/handle/{main.ct,io/*}` | `expected.out` |
| 06_type_alias/neg_plain_unit | 反例：普通 `.ct` 里声明别名 | ct-ast | `06_type_alias/neg_plain_unit/prog.ct` | `expected.err`，退出 1 |
| 07_map_namespace/dynamic | 命名空间宿主 + 装箱 `Writer::hal` | ct-ast | `07_map_namespace/dynamic/prog.ct` | `expected.out` |
| 07_map_namespace/static | 命名空间宿主 + 静态零成本调用 | ct-ast | `07_map_namespace/static/{main.ct,sys/*}` | `expected.out` |
| 08_shim/header_inline | 纯头 shim：`static inline` + 宏 | ct-ast | `08_shim/header_inline/{main.ct,csv/*}` | `expected.out` |
| 08_shim/compiled_source | `.shim.c` 持有 C 侧状态 | ct-ast | `08_shim/compiled_source/{main.ct,tick/*}` | `expected.out` |
| 09_closure/pair_by_hand | tier-1：手写 `(fn, env)` 与 adapter | L0 | `09_closure/pair_by_hand/prog.ct` | `expected.out` |
| 09_closure/literal_capture | tier-2：`=>` 捕获时机、每轮新闭包 | ct-ast | `09_closure/literal_capture/prog.ct` | `expected.out` |
| 09_closure/neg_capture_write | 反例：闭包内改写捕获变量 | ct-ast | `09_closure/neg_capture_write/prog.ct` | `expected.err`，退出 1 |
| 10_loop/count | `loop(n)`：上界一次求值、break/continue/可写 i | ct-ast | `10_loop/count/prog.ct` | `expected.out` |
| 10_loop/range | `loop(a..b)`：半开区间、边界求值顺序、空区间 | ct-ast | `10_loop/range/prog.ct` | `expected.out` |
| 10_loop/neg_braceless | 反例：循环体不是块 | ct-ast | `10_loop/neg_braceless/prog.ct` | `expected.err`，退出 1 |
| 11_variadic/sums | 逐个 `va_arg` 消费 | L0 | `11_variadic/sums/prog.ct` | `expected.out` |
| 11_variadic/forward | 转发 `va_list` 给 `vprintf`/`vsnprintf` | L0 | `11_variadic/forward/prog.ct` | `expected.out` |
| 12_multiunit/cross_unit_iface | 跨单元 vtable；接口值绑定指针 | ct-ast | `12_multiunit/cross_unit_iface/{main.ct,*.h.ct}` | `expected.out` |
| 12_multiunit/pub_globals | `pub` 全局；同名符号靠命名空间区分 | ct-ast | `12_multiunit/pub_globals/{main.ct,left/*,right/*}` | `expected.out` |
| 13_check/clean | 干净单元：退出 0 且零输出 | ct-ast | `13_check/clean/prog.ct` | 无产物（断言静默） |
| 13_check/arity | 同一处 arity 不匹配：编译 warning / check error | ct-ast | `13_check/arity/prog.ct` | `expected.warn` + `expected.err` |
| 13_check/json | `--diagnostics=json` 的结构化诊断 | ct-ast | `13_check/json/prog.ct` | `expected.json` |
| 14_default_method/expand_and_override | 默认体按 struct 展开；显式覆盖 | ct-ast | `14_default_method/expand_and_override/prog.ct` | `expected.out` |
| 14_default_method/neg_cycle | 反例：默认方法成环且无入口 | ct-ast | `14_default_method/neg_cycle/prog.ct` | `expected.err`，退出 1 |
| 15_memory/drop_paths | 三条出口：落到底 / 嵌套块 / 提前 return | ct-ast | `15_memory/drop_paths/prog.ct` | `expected.out` |
| 15_memory/drop_loop_break | break/continue 也释放：每条出口各 drop 一次 | ct-ast | `15_memory/drop_loop_break/prog.ct` | `expected.out` |
| 15_memory/field_cascade | drop() 里 delete 成员，三层资源树 | ct-ast | `15_memory/field_cascade/prog.ct` | `expected.out` |
| 15_memory/field_cascade_missed | 漏一行 delete：成员的 drop 从未执行 | ct-ast | `15_memory/field_cascade_missed/prog.ct` | `expected.out` |
| 15_memory/box_borrow | 装箱只借用：改原对象，接口立刻可见 | ct-ast | `15_memory/box_borrow/prog.ct` | `expected.out` |
| 15_memory/box_escape | 返回装箱的局部值：ASan stack-use-after-return | ct-ast | `15_memory/box_escape/prog.ct` | `expected.asan`（`ASAN=1`） |
| 15_memory/manual_shim | `.shim.c` 拥有 malloc/free：owned vs borrowed | ct-ast | `15_memory/manual_shim/{main.ct,pkt/*}` | `expected.out` |
| 15_memory/manual_shim_wrong | 直接 `free(p)`：payload 与 shim 记账丢失 | ct-ast | `15_memory/manual_shim_wrong/{main.ct,pkt/*}` | `expected.out` |
| 15_memory/borrow_handback | borrow + Handback：逆序还池，不销毁 | ct-ast | `15_memory/borrow_handback/prog.ct` | `expected.out` |
| 15_memory/borrow_delete | 反例：delete 借来的指针 | ct-ast | `15_memory/borrow_delete/prog.ct` | `expected.err`，退出 1 |
| 15_memory/own_factory | 反例：own 接工厂返回值 | ct-ast | `15_memory/own_factory/prog.ct` | `expected.err`，退出 1 |
| 15_memory/leak_warning | 静态诊断 potential leak：warning + 退出 0 | ct-ast | `15_memory/leak_warning/prog.ct` | `expected.warn` + `expected.out` |
| 16_diagnostics/sig_text | 签名不符（参数个数），文本通道 | ct-ast | `16_diagnostics/sig_text/prog.ct` | `expected.err`，退出 1 |
| 16_diagnostics/sig_json | 同一发现的 JSON：`type=signature_mismatch` | ct-ast | `16_diagnostics/sig_json/prog.ct` | `expected.json`，退出 1 |
| 16_diagnostics/sig_return | 签名不符（返回类型），第二个触发面 | ct-ast | `16_diagnostics/sig_return/prog.ct` | `expected.err`，退出 1 |
| 16_diagnostics/type_arg | 实参类型不符，文本通道 | ct-ast | `16_diagnostics/type_arg/prog.ct` | `expected.err`，退出 1 |
| 16_diagnostics/type_loop | 循环计数非整数；JSON 且仍能跑 | ct-ast | `16_diagnostics/type_loop/prog.ct` | `expected.json` + `expected.out` |
| 16_diagnostics/amb_text | 方法二义，文本；第一个 trait 胜出 | ct-ast | `16_diagnostics/amb_text/prog.ct` | `expected.warn` + `expected.out` |
| 16_diagnostics/amb_json | 同一发现的 JSON：`type=ambiguous_method` | ct-ast | `16_diagnostics/amb_json/prog.ct` | `expected.json`，退出 1 |
| 16_diagnostics/loop_shadow_text | 循环计数器遮蔽，文本且仍能跑 | ct-ast | `16_diagnostics/loop_shadow_text/prog.ct` | `expected.warn` + `expected.out` |
| 16_diagnostics/loop_shadow_json | 同一发现的 JSON：`type=loop_shadow` | ct-ast | `16_diagnostics/loop_shadow_json/prog.ct` | `expected.json`，退出 1 |
| 16_diagnostics/recover_multi | 一次运行报 3 个独立 error | ct-ast | `16_diagnostics/recover_multi/prog.ct` | `expected.err`，退出 1 |
| 16_diagnostics/cap_fields | 容量上限：第 65 个字段 | ct-ast | `16_diagnostics/cap_fields/prog.ct` | `expected.err`，退出 1 |
| 16_diagnostics/cap_errors | 容量上限：第 21 个错误停止恢复 | ct-ast | `16_diagnostics/cap_errors/prog.ct` | `expected.err`，退出 1 |
| 16_diagnostics/note_text | error 之后的 note 通道 | ct-ast | `16_diagnostics/note_text/prog.ct` | `expected.err`，退出 1 |
| 16_diagnostics/note_json | `--diagnostics=json` 不接管 error/note | ct-ast | `16_diagnostics/note_json/prog.ct` | `expected.err`，退出 1 |
| 16_diagnostics/mixed_json | 混合：4 种 type、5 条记录 | ct-ast | `16_diagnostics/mixed_json/prog.ct` | `expected.json`，退出 1 |
| 17_cli/help | `-h` 的完整用法（stdout） | ct-ast | `17_cli/help/args` | `expected.out` |
| 17_cli/version | `-v` 的版本行 | ct-ast | `17_cli/version/args` | `expected.out` |
| 17_cli/noargs | 无参数：一行 usage 到 stderr | ct-ast | `17_cli/noargs/args` | `expected.err`，退出 1 |
| 17_cli/emit_map_instance | `--emit-map -`：实例宿主 | ct-ast | `17_cli/emit_map_instance/{args,prog.ct}` | `expected.out`（map JSON） |
| 17_cli/emit_map_namespace | `--emit-map -`：命名空间宿主 | ct-ast | `17_cli/emit_map_namespace/{args,prog.ct}` | `expected.out`（map JSON） |
| 17_cli/ignore_inc_compile | `-I` 在 compile 下被忽略的提示 | ct-ast | `17_cli/ignore_inc_compile/{args,prog.ct}` | `expected.err` |
| 17_cli/ignore_inc_check | `-I` 在 check 下被忽略的提示 | ct-ast | `17_cli/ignore_inc_check/{args,prog.ct}` | `expected.err` |
| 17_cli/pkg_get_local | `get file://localpkg`：vendor + ct.lock | ct-ast | `17_cli/pkg_get_local/{args,localpkg/*}` | `expected.out` + `expected.lock` |
| 17_cli/pkg_get_missing | `get` 缺 spec：usage | ct-ast | `17_cli/pkg_get_missing/args` | `expected.err`，退出 1 |
| 17_cli/pkg_install_missing | `install` 缺 `ct.pkg` | ct-ast | `17_cli/pkg_install_missing/args` | `expected.err`，退出 1 |
| 17_cli/pkg_update_empty | `update` 离线、无依赖 | ct-ast | `17_cli/pkg_update_empty/{args,ct.pkg}` | `expected.out` |
| 17_cli/pkg_verify_missing | `verify` 缺 `ct.lock` | ct-ast | `17_cli/pkg_verify_missing/args` | `expected.err`，退出 1 |
| 17_cli/mode_compile_import | compile 拒绝 import | ct-ast | `17_cli/mode_compile_import/{args,main.ct,helper.h.ct}` | `expected.err`，退出 1 |
| 17_cli/mode_check_import | check 拒绝 import（single-unit） | ct-ast | `17_cli/mode_check_import/{args,main.ct,helper.h.ct}` | `expected.err`，退出 1 |
| 17_cli/mode_build_import | build 接受 import 并分单元生成 | ct-ast | `17_cli/mode_build_import/{args,main.ct,helper.h.ct}` | `expected.gen` |
| 17_cli/ns_root_ok | `--ns-root` 与目录一致 | ct-ast | `17_cli/ns_root_ok/{args,tree/*}` | `expected.gen` |
| 17_cli/ns_root_bad | `--ns-root` 与目录不符即报错 | ct-ast | `17_cli/ns_root_bad/{args,tree/*}` | `expected.err`，退出 1 |
| 17_cli/ns_root_skip | 边界：路径不在 root 下时静默跳过 | ct-ast | `17_cli/ns_root_skip/{args,tree/*}` | `expected.gen` |
| 18_ctor/four_positions | 局部量 / 字段 / 栈数组 / malloc 宿主 | ct-ast | `18_ctor/four_positions/prog.ct` | `expected.out` |
| 18_ctor/heap_row | 堆上宿主数组，循环填充与派发 | ct-ast | `18_ctor/heap_row/prog.ct` | `expected.out` |

## 写样例时踩到的边界（都已固化成样例或注释）

1. **接口字段的构造点不装箱**（L0）：`struct Add { Expr lhs; }` 用指定初始化式构造时，
   `lhs` 仍是 `{NULL, NULL}`；要在语句里 `sum.lhs = a;` 才会按字段的 trait 装箱。
2. **指针接口字段只能派发**（L0）：`row.cell->eval()` 可以，`row.cell = a;` 不行；
   需要先有接口值，再 `row.cell = &slot;`。
3. **调用结果不能直接装箱**：`Sample s = temp_get();` 报
   `cannot infer the type to box`；先把结果落到有静态类型的变量，再 `Sample s = p;`。
4. **`type` 别名只活在 `.h.ct` / `.m.ct`**：普通 `.ct` 里声明会被拒绝；
   别名的星号归属是 `pub type T = struct S;` → `T *` 才是 `struct S *`。
5. **多单元的输出文件按“单元基名”落盘**：两个单元都叫 `state` 会生成同一个
   `state.c`/`state.h`，后者覆盖前者；样例里用 `lstate`/`rstate` 区分。
6. **`loop` 体必须是块**；`i` 可写，但写完后循环自身的 `i++` 仍会执行
   （`10_loop/count` 里因此只打印 0、2）。
7. **闭包捕获只读**：捕获是创建点的按值快照，闭包体内改写会报错并提示 tier-1 写法。
8. **`ct check` 的文本输出不带 `ctc: N error(s) generated` 汇总行**；编译路径才有。
   两者对同一 arity 问题的严重度也不同（warning vs error）。
9. **类型宿主按 C 拼写精确匹配**：`unsigned` 与 `unsigned int` 是两张表
   （见 `examples/14_scalar_host` 的说明；本目录未重复构造该反例）。
10. **L0 的生成物可能带 `unused _self` 警告**：这是冻结种子的已知产物，不影响运行；
    样例脚本对 L0 只断言编译成功与输出一致。
11. **AutoDrop 在块尾 `}`、`return` 前、`break` / `continue` 前注入**：四种出口都会
    释放当前作用域持有的 `own`；循环体的释放基线在建循环时入栈，`switch` 只登记
    `break` 基线，所以 `case … break` 不会误释放循环外的对象。`goto` 仍是 v1 的已知
    边界：跨层跳转会跳过释放，而且不报错（`15_memory/drop_loop_break` 演示块尾、
    `break`、`continue` 三条出口，`15_memory/drop_paths` 演示块尾、嵌套块、`return`）。
12. **结构体字段不会自动级联释放**：宿主被 `delete` 时只跑宿主自己的 `drop()`，
    成员要由 `drop()` 里显式 `delete self->member;`；漏写没有任何诊断
    （`15_memory/field_cascade_missed` 的 `leaf drops 0` 就是证据）。
13. **装箱只借用，不拥有**：`T t; Iface i = t;` 里 `i.self == &t`，不是拷贝；把接口值
    带出 `t` 的作用域就悬垂（函数返回局部值的装箱尤其容易）。正确写法是让被装箱对象
    活过接口值的使用期，或改为在堆上分配并返回指针。复现命令：
    `cc -fsanitize=address -g <generated>.c -o x && ASAN_OPTIONS=detect_stack_use_after_return=1 ./x`
    → `stack-use-after-return`，退出码 134（macOS）。样例：`15_memory/box_escape`。
14. **`own` 只接受可见的 `malloc`/`calloc` 初始化式**：工厂或 shim 返回的指针不能直接
    `own`（`15_memory/own_factory`，退出 1）；要按对方的契约 `delete` 或调用配套释放函数。
15. **`borrow` / `Handback` 不是 `Drop`**：`Handback` 只把控制权还回池（对象还在），
    `delete` 一个借来的指针会被编译器拒绝（`15_memory/borrow_delete`，退出 1）。
    池对象的所有权在池，不在借用者。
16. **没有引用计数，也没有 GC**；`Arena` 只存在于编译器内部
    （`selfhost/ct-ast/runtime/arena/`），不是随语言发布的用户库，样例里不提供。
17. **`potential leak` 是保守启发式**：只覆盖“裸指针 + 函数返回时仍未 delete”，
    warning 不阻断编译（退出 0），且把指针转手给别人后就不再提示——没有警告不等于
    没有泄漏（`15_memory/leak_warning`）。
18. **规范 §6.1 关于“不比较方法签名”的描述已过时**：ct-ast 0.23 实测会对
    `impl` 的参数个数、参数类型、返回类型逐项比较并报 `signature_mismatch`
    （`16_diagnostics/sig_text` / `sig_return`）。此处以实测为准。
19. **`--diagnostics=json` 只接管 warning 列表**：语义错误与 `note:` 仍走纯文本
    stderr，stdout 为空；`16_diagnostics/note_json` 固化了这一点。另外 compile
    模式的 JSON 记录没有 `severity` 字段，`ct check`（strict）才有。
20. **`--ns-root` 只对“输入路径确实位于 root 之下”的单元生效**：路径不在 root 下
    时校验被静默跳过，build 照常成功（`17_cli/ns_root_skip`）；传相对路径给
    `--ns-root` 的绝对 root 也会命中这个跳过分支，容易误判成“校验通过”。
21. **接口值不能直接 malloc 成裸数组**：`Shape *p = malloc(n * sizeof(Shape))`
    会报 `cannot infer the type to box`；可行写法是栈数组 `Shape arr[n]`，或
    malloc 一个“含接口字段的宿主结构体”数组（`18_ctor/heap_row`）。
22. **包管理只有离线路径进了 tour**：`get <远端 spec>` 需要网络/远端索引，未在样例里
    执行；本地等价复现是 `get file://localpkg`（`17_cli/pkg_get_local`），它走同一套
    vendor + `ct.lock` 逻辑。`install` 的“有锁安装”也依赖已拉到本地的 vendor，
    样例只固化缺 `ct.pkg` / 缺 `ct.lock` 的错误面。
23. **错误恢复有硬上限**：`MAX_ERRORS = 20`，第 21 个错误会打印
    `ctc: too many errors, stopping` 并立即退出（`16_diagnostics/cap_errors`）；
    结构体字段上限是 64（`16_diagnostics/cap_fields`）。两者都是“容量错”，不是语法错。

## 与既有门禁的关系

- 没有改 `selfhost/check-*.sh`，也没有改 `examples/README.md` 与其它正在被并发修改的样例目录。
- 目录深度是 `examples/tour/<feature>/<case>/...`，不会被 `examples/*/*.ct`、
  `examples/*/src/main.ct` 这类既有 glob 意外收编。
- 是否把 `run.sh` 接进 `check-all.sh` 留给门禁维护方决定；目前它自包含、可单独运行。
