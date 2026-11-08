# ct 特性巡礼（examples/tour）

> **当前状态（2026-11-09）**：目录已就绪，全量样例通过；**尚未接入 `check-all.sh`**
> （避免与并发的门禁改动冲突），需要可用的 `ct-ast`——可以显式传 `CT=...`，
> 也可以让脚本自行自举。`cases.tsv` 中 `l0=yes` 的样例可用冻结种子复编；
> 目前 L0 可复编的簇是 **01、02、03、09（仅 tier-1 手工版）、11**，
> 其余簇（04–08、10、12–14 以及 09 的 `=>` 样例）仅 ct-ast。

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
```

脚本不写仓库：编译产物都在 `$TMPDIR/ct-tour-examples.$$`，退出时清理。
`cases.tsv` 是清单（`feature|case|mode|l0|expect_exit|note`）。

- `compile`：`ct prog.ct -o x.c` → `cc -Wall -Wextra -std=c99` → 运行 → 比对 `expected.out`
- `build`：`ct build --emit-c main.ct` → cc（含 `*.shim.c`）→ 运行 → 比对
- `pair`：先编译（预期 0 退出、stderr=`expected.warn`），再 `ct check`（预期 1、stderr=`expected.err`）
- `check` / `clean` / `check-json`：只跑 `ct check`，比对 stderr 或 JSON

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

“归属”只说明**当前实现**能不能被 L0 冻结种子吃下，不是设计上的分类。
L0 对 `map`、闭包字面量、`loop`、默认方法等要么拒绝、要么原样透传成非法 C。

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

## 与既有门禁的关系

- 没有改 `selfhost/check-*.sh`，也没有改 `examples/README.md` 与其它正在被并发修改的样例目录。
- 目录深度是 `examples/tour/<feature>/<case>/...`，不会被 `examples/*/*.ct`、
  `examples/*/src/main.ct` 这类既有 glob 意外收编。
- 是否把 `run.sh` 接进 `check-all.sh` 留给门禁维护方决定；目前它自包含、可单独运行。
