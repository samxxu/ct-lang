# 阶段流水账（Phase 0–36）

> 中文
>
> 本文是逐相详细记录，保留写作时点的证据与版本；当前计划见 [../roadmap.md](../roadmap.md)。
> 路线图只做简要索引，不重复本文；与代码冲突时以代码为准。

---

## 阶段总览（详表）

| 阶段 | 主题 | 类别 | 状态 | 出口条件 |
| --- | --- | --- | --- | --- |
| Phase 0 | 用 trait 写「完整 OO」（封装 / 接口 / 派发 / 传递 / 组合 / 创建与释放 / 接口多态） | 建设 | ✅ 完成（出口 1–9 成立；堆对象的**创建**按 0.1.8 推迟到 Phase 0 之后，已落地） | 出口清单 1–9 全部成立 |
| Phase 0.1 | 缺陷修复 + 回归测试 | 建设 | ✅ 完成（0.1.1–0.1.9） | 组合 / 数组 / 作用域 / 接口多态全部补齐；golden 测试全绿 |
| Phase 0.2 | 接口多态：把 trait 当类型、运行时派发 | 建设 | ✅ 完成（设计先行 → 已实现） | 接口**字段**（值字段装箱 + 派发、指针字段派发）已补齐；接口**数组**在 L0 仍不支持，CT 线已由 Phase 5 补齐（acceptance p01–p04） |
| Phase 0.3 | **剥离越位特性**：把 namespace / 多文件 / import / Drop / 诊断等在 C 侧越位实现的能力移出 `ctc.c`，使其回到**纯 OO + 底层设施**；移出件**归档为 oracle**（不销毁） | 建设 | ✅ 完成（2026-10-14） | `ctc.c` 3836 → 2897 行（含后续 fix 与 banner/bump，现为 2930 行）、只余 Phase 0 能力；套件 146 → 110 项全绿；归档件在 `test/archive/` + tag `overreach-oracle` |
| Phase 1 | **自举（第一目标）**：以剥离后的**纯 OO `ctc.c`** 为 L0，用 CT（OO 子集、单文件）重写其**全部能力**，出口是与 L0 **逐字节一致** | 建设 | ✅ 完成（2026-10-15：M2 达成 25/25，且 L1′ 自举闭环通过） | 阶梯 M1→M2（L1）；每层以 **byte-identical golden** 为出口 |
| Phase 2 | **模块化**：namespace / 多文件 `ct build` / `pub` / `import` | 恢复 | ✅ 完成（2026-10-16；非版本 tag `phase2-multifile-split`） | 归档用例 **byte-identical**；编译器源码切成多文件 |
| Phase 3 | **内存**：Drop / `delete` 放宽 | 恢复 | ✅ 完成（2026-10-16；在 `selfhost/l2/**` 实现，L1 冻结） | drop 用例 **byte-identical** |
| Phase 4 | **诊断与溯源**：`#line` / 泄漏警告 / `--diagnostics` + 多错误恢复 / 语义诊断 | 恢复 + 新增 | ✅ 完成（2026-10-16；4 个切片全部落地；2026-10-17 bump 到 v0.4.0） | 诊断层全绿；`#line` 能把 gcc 报错映回 `.ct` 行 |
| Phase 5 | **新增特性**：AutoDrop / 路径敏感泄漏分析 / 目录 = namespace | 新增 | ✅ 完成（2026-10-17；5 个切片全部落地；bump 到 v0.5.0，**M6 收口**） | 设计冻结 + 新用例全绿；阶梯 **M6** 在此收口 |
| Phase 6 | **生态与扩展**：`map` + 反向映射表（D8）、方言系统；增量编译、跨函数分析、多目标 | 扩展 | ✅ 完成（2026-10-17；6.1–6.4 + 6.6 落地，6.5 仅设计冻结；bump 到 v0.6.0） | 设计冻结 + 新用例全绿 |
| Phase 7 | **工具链形态**：单入口 `ct` + `ctc` 兼容别名 | 落地 | ✅ 完成（2026-10-17；7.1–7.3 落地，bump 到 v0.7.0；`ct get` / `ct install` 后由 Phase 8 落地） | `ct compile` 可用、`ctc …` 不失效、banner 写 `ct` |
| Phase 8 | **包管理与分发**：`ct-pkg`（git registry + 本地目录源）、`ct get` / `ct install` | 新增 | ✅ 完成（2026-10-18；8.1–8.3 全部落地；bump 到 v0.8.0；D21–D27 已冻结） | `ct get` / `ct install` 可用，编译路径仍零网络 |
| Phase 9 | **AST 版编译器**（新主线） | 新增 | ✅ 9.1–9.7 已落地（2026-10-18）：自编 + 不动点 + **全量行为等价**（`check-ast.sh`，Phase 9 收口时 60 项，2026-10-31 实测 408 项，以脚本末行 summary 为准）；旧管线 `selfhost/l2/**` 按 D36 冻结归档（tag `pre-ast-mainline`）；**已 bump 到 v0.9.0 收口** | 自编 + 行为等价 |
| Phase 10 | **主线切换**：安装入口改由 AST 版编译器（ct-ast）提供 | 迁移 | ✅ 10.1–10.7 全部落地（2026-10-19；[design/phase10.md](design/phase10.md)，D38–D45 已按建议值确认）：CLI/身份、语义诊断、内存、多错误恢复、增量缓存、包管理迁移、切主线；安装入口由 ct-ast 提供（切换前 tag `pre-ct-ast-switch`），**已 bump 到 v0.10.0 收口** | 以 ct-ast 构建的 `ct` 跑完整套关卡；L2 降为回归 oracle |
| Phase 11 | **`map` 构造**：`map trait T for instance x { m() → CALL; }`（把 trait 方法绑定到已声明的全局实例） | 新增 | ✅ 完成（2026-10-19；11.1–11.3 全部落地：解析 + 实例级包装/vtable + `--emit-map` 的 `maps` 字段 + 负例，11.2 接入派发，11.3 加固绑定完整性与唯一性并放宽 CALL 子集，收口 bump 到 v0.11.0、11.3 后 patch bump 到 v0.11.1；D19 解除，见 [design/phase6.md](design/phase6.md) §6.5） | 设计冻结 + 新用例全绿；收口 bump v0.11.0、patch bump v0.11.1 |
| Phase 12 | **生态扩展**：官方 / 示范 bindings（首个为仓库内假 HAL）＋ 方言深化（多方言并存 + 作者指南） | 扩展 | ✅ 完成（2026-10-19；12.1–12.4 全部落地：首个官方 binding `bindings/mock-hal/`、binding 规约 `bindings/README.md`、多方言并存演示 + 作者指南；收口 bump 到 v0.12.0；[design/phase12.md](design/phase12.md)，D46–D52） | 设计冻结 + 新用例全绿；收口 bump v0.12.0 |
| Phase 17 | **工程质量与新能力**：CI 矩阵 + ASAN/UBSAN + 确定性 fuzz、官方 `std`（含容器模块 `std::map`）、raw 透传、文档分层与链接门禁、包管理补全（`ct update` / `ct verify` / index / 比较器范围 / `ct.pkg` 构建元数据）、**`ct build` 一步到位产出可执行文件**（`--emit-c` 保留只发 C） | 新增 + 治理 | ✅ 完成（2026-11-02；17.1 CI 矩阵 / ASAN / 确定性 fuzz、17.2 官方 `std`、17.3 raw 透传、17.4 文档分层 / 链接门禁、17.5 包管理补全（`ct update` / `ct verify` / 显式索引 / 比较器范围 / 构建元数据）、17.6 `ct build` 一步到位全部落地，收口 bump 到 v0.17.0；[design/phase17.md](design/phase17.md)，D17-1–D17-9 已确认） | 11 道硬门禁 + CI 三个 job + nightly 全绿；六项各有独立测试层；零网络契约不变，零子进程收窄为 `ct compile` / `ct build --emit-c` |
| Phase 18 | **生态建设**：ct-pkg 组织、包规范与首批包（`hal` 契约 + 平台包 + C 库映射 + 索引 / CI 复用），为 1.0 做准备 | 生态 | ✅ 完成（2026-11-02；18.0–18.6 全部落地：L2 容量解除、包规范与作者指南、契约包 `ct-pkg/hal`、平台包 `ct-pkg/hal-posix`、C 映射包 `ct-pkg/clib`、索引仓库 `ct-pkg/index`、`examples/wave1-demo` 与 `packages.yml` 的宿主 + aarch64/QEMU 门禁，收口 bump 到 v0.18.0；[design/phase18.md](design/phase18.md)，D18-1–D18-11 已确认） | Wave 1 包在宿主与目标机上端到端跑通；索引与包门禁由 CI 生成；`1.0.0` 单独立项 |
| Phase 19 | **受限语义检查**：调用点 arity、实参类型粗粒度兼容、trait 方法歧义（SH-46）、跨单元签名、`ct check` 可选入口 | 新增 | ✅ 完成（2026-11-03；19.0–19.4；`v0.19.0`；[history/design/phase19.md](design/phase19.md)，D19-1–D19-5） | 383 文件语料零误报；4 个探针全部诊断；11 道硬门禁全绿，compile/build 产物不变 |
| Phase 20 | **包支持**：类型宿主冲突可解（限定调用）、late import / 映射 arity 不再静默、`requires` 硬失败、包命名空间身份 + 跨根重名检测 | 新增 | ✅ 完成（2026-11-07；01–04、06、08 落地，收口 `v0.20.0`；[history/design/phase20.md](design/phase20.md)，D20-1–D20-10 已确认；**P20-05 只移出 ct-pkg 侧索引生成器（ct 侧 `pkg_index_lookup` 仍欠）**、**P20-07 延后**） | 探针全绿；全仓语料 + ct-pkg 七包零新增失败；11 道硬门禁 + fixpoint 全绿；`CTC_VERSION` 五处与 71 个 golden 收口到 `v0.20.0`（含 `915c12c`） |
| Phase 21 | **非逃逸栈闭包**：`=>` 就地写法；档② = 档①（`struct` + `trait`）自动展开；`(fn, env)` 两词 ABI；逃逸硬报错 + `Callable` hint；档③ 不做 | 新增 | ✅ 完成（2026-11-08，S0–S5、S7 落地并已随 `v0.21.0` 发布；**S6 记外部依赖**；[history/design/phase21.md](design/phase21.md)、[提案评审](../design/closure-proposal-review.md)，D21-1–D21-17 已定稿。**本次绕开设计文档收尾**：该文件其余改动仍属他人未提交 WIP，只单独补了首行状态与 §7 计数口径，完整收尾待该 WIP 落地） | 闭包探针 70–77 / 79–81 / 84 / 86–91 与 `errors/` 负例全绿；11 道硬门禁 + fixpoint；收口 bump `v0.21.0`（已发布，设计文档收尾待该 WIP 落地） |
| Phase 22 | **`loop` 语法糖**：`loop(<次数>) { … }` 展开为单行 `for`，隐含可写 `int i`，计数只求值一次；上下文相关关键字（仅语句位置 + `(`）；嵌套遮蔽编译告警、`ct check` 报错 | 新增 | ✅ 完成（2026-11-08；S1/S2/S3/S4 各自独立提交；`v0.22.0`；[history/design/phase22.md](design/phase22.md)，D22-1–D22-12 已定稿） | 12 个正例（含 `own` 块尾释放、闭包当轮快照）与 4 个负例全绿；L22-1–L22-5 编译/`ct check` 双模式实测；既有 golden 零变化；11 道硬门禁 + fixpoint |
| Phase 23 | **`loop(a..b)` 范围语法**：`loop(a..b)` 展开为单行 `for`，半开区间 `[a, b)`，`i` 从 `a` 起；两个边界各求值一次、先 `a` 后 `b`；`loop(0..n)` 与 `loop(n)` 等价；`i` 与遮蔽诊断沿用 Phase 22 | 新增 | ✅ 完成（2026-11-08；S1–S5 各自独立提交；`v0.23.0`；[design/phase23.md](design/phase23.md)，D23-1–D23-9 已定稿；**D23-8 是指针/数组/结构体边界改硬错的 breaking change**） | 8 个正例 + 7 个负例全绿；两个边界由 `i` 初始化器里的逗号运算符定序（C99 §6.5.17）；`loop(0..n)` 与 `loop(n)` 生成体逐字节相同；`41_case_range` 继续 PASS；既有 golden 功能层零变化；11 道硬门禁 + fixpoint；收口 bump `v0.23.0` |
| Phase 24 | **数组 range 初值**：`int a[] = <start>..<stop>($ * 2 + 1)` 展开为花括号初始化列表（`$` → `((int)k)`），不生成循环、不留临时量，可用于文件作用域 `static const` 表；边界只收整数字面量，`$` 是索引占位符而不是标识符 | 新增 | ✅ 已收口 `v0.24.0`（2026-11-09；[history/design/phase24.md](design/phase24.md)，D24-1–D24-10） | 8 个正例 + 16 个负例全绿；`109` 的展开与手写 13 项列表逐字节相同、运行输出与字面量数组逐字节相同；`$` 的四类越界用法（初值外 / 维度里 / 赋值 / 取地址·自增）各自命中预期文案且都不落成 `undeclared`；`check-ast.sh` 765 passed / 0 failed；编辑器 grammar 40 checks 全绿 |
| Phase 25 | **静态映射调用的闭包实参**：`.m.ct` 静态映射的 recipe 接收 `(fn, env)` 参数对（`array.each(closure)`），复用 Phase 21 的闭包 ABI；recipe 表达不了的循环落 `shim.h` | 新增 | ✅ 完成（2026-11-09；25.1、25.2、25.4 与收口 25.5 落地，25.3 的 `emit_closure_arg` 拆分并入 25.2；`v0.25.0`；[history/design/phase25.md](../history/design/phase25.md)，D25-1–D25-11） | 四种静态调用形态接受闭包实参；L25-1–L25-5 各一条独立负例；`120` 的调用行与手写 `(fn, env)` 调用逐字节相同；既有 7 组静态映射夹具与 4 组闭包夹具生成物逐字节不变；`check-ast.sh` 784 passed / 0 failed；11 道硬门禁 + fixpoint 全绿 |
| Phase 26 | **泛型函数（单类型参数 + 显式实例化 + 编译期单态化）**：声明 `T name<T>(...)`，调用 `name<int>(...)` 时为每个具体类型实参生成一份 `static` C 函数；只做函数，不做泛型结构体/trait/约束/推导，`pub` 与递归调用明确拒绝 | 新增 | ✅ 完成（v0.26.0，2026-11-09 收口；v0.26.1 / v0.26.2 / v0.26.3 / v0.26.4 为评审修复补丁（v0.26.4 含 TEST-18 / CI-8 / DOC-66）；[history/design/phase26.md](../history/design/phase26.md)，D26-1–D26-15） | E26-1–E26-8：`123/124` 正例、五条 L26 负例（含 v0.25.0 旧行为对照）、既有 784 条零回归、11 道硬门禁、五处 `CTC_VERSION` = `0.26.x`、`ct check` 共用诊断；v0.26.1 增 `125–127` 与容量夹具，覆盖 `sizeof` / `_Alignof` / `offsetof` / cast / `va_arg` / `struct T` 标签；v0.26.2 根因修复无括号类型操作数（`sizeof T` / `_Alignof T` / `alignof(T)`）并在产物层加 `tparam_residue()` 防线；v0.26.3 根因修复值位置类型参数（`return T;` / `h(T)` / `sizeof T * T` / `sizeof T + T`）并消掉防线假阳 |
| Phase 27 | **`foreach` 语句形态**：`foreach (xs) { … item … }`，隐式绑定 `item`，展开为普通 C 循环（零运行时）；本相只接受一维数组，长度为 `sizeof(x)/sizeof((x)[0])`，容器协议延后（D27-4）；支持 `break`/`continue`/`return`；不做 `in` 形式、显式绑定名、裸指针、多维数组、迭代器 | 新增 | ✅ 完成（2026-11-10；v0.30.0 合并发布（Phase 27–30）内含实现，未逐相 bump；[history/design/phase27.md](../history/design/phase27.md)，D27-1–D27-11） | E27-1–E27-6：语法 / 数组 / 诊断 / 文档 / 自举全绿；E27-7：样例 `20_foreach_statement` 与 `each` 对照 |
| Phase 28 | **约束泛型（泛型两阶段第一相）**：`T name<T: Trait>(...)`，单类型参数 + 单约束 + 显式实例化；模板体内按约束调用 trait 方法，编译期落成经 vtable 方法槽的静态派发；不做参数化 trait / 泛型 struct（交 Phase 29）/ 多约束 / `Self` / 装箱；**`Callable` 内建延后**（见 [phase21.md §4.12](design/phase21.md#callable-内建的延后记录2026-11-10)） | 新增 | ✅ 完成（2026-11-11；`v0.30.0` 合并发布（Phase 27–30）内含实现，未逐相 bump；[history/design/phase28.md](../history/design/phase28.md)，D28-1–D28-11） | E28-1–E28-9 全绿：136/137/145/146 正例与产物断言、7 个角度负例（含静态 trait 与闭包逃逸）、跨单元 `extern struct <Trait>_vtbl`、生成物无 `T` 残留且不读 `__*_vptr`、`ct check` 与编译同文案、样例 21 选择排序进 `test/run.sh`、`check-ast.sh` 903 passed / 0 failed、`test/run.sh` 133 passed、11 道硬门禁；版本号待用户批准后以独立 `chore(release)` 处理 |
| Phase 29 | **泛型 struct + 内置 `Vec` / `Map`（含 `foreach` 容器协议）**：`struct Name<T, U>` 显式实例化与布局单态化；`Vec`/`Map` 迁入本仓 `lib/std/` 内置层；解冻 D27-4，`Vec` 绑定 `item`+只读 `i`，`Map` 用 `item.key`/`item.value`（体内用 `i` 硬错）并按插入序遍历；**`Map` 遍历是硬退出判据**；不做闭包逃逸 / 内置 `Callable` / 用户自定义可迭代类型 | 新增 | ✅ 完成（2026-11-11 第五轮复评 GO；上一轮 1 High + 2 Medium + 1 Low 与 V29-4e 的文件作用域容器数组回归均已修复；`v0.30.0` 合并发布（Phase 27–30）内含实现，未逐相 bump；[history/design/phase29.md](../history/design/phase29.md)，D29-1–D29-14） | **E29-1–E29-13 逐条满足**（证据表见 phase29 §10.3.5）：E29-5 的 compile 与 `ct build` 两条路径都已加载内置层并断言（`Module.h.ct` 独立单元 + emitter 显式 include，不作 import 边以保 D41 缓存），`check-warnings.sh` 无跳过；E29-7 的 `file:line:col` 与「恰一条错误」、E29-9 的 `ct check`/`ct build` 同文案、E29-12 的两条 arity 负例逐字同文案、E29-3 的两次构建/两次运行一致均进真门禁。`check-ast.sh` **1019 passed / 0 failed**（收口时基线 962，range 补丁后 972，NO-GO 修复块后 992，V29-4b 后 1000，V29-4c 后 1010，V29-4d 后 1017，V29-4e 后 1019；见 [phase29.md](../history/design/phase29.md) §10.3.5）、`check-warnings.sh` **324 ok / 0 failed**、`check-docs` OK（984 links / 179 files）、`test/run.sh` 140、goldens 82、`check-all.sh` **OK（11 hard gates green）**；sanitizer 的 10 项既有失败（8 个 import 夹具的单文件调用、`examples/json`、`range_init_overflow`）与 29 无关，`142`/`143` 均通过 |
| Phase 30 | **接收者语境块**：`<receiver> into { … }`，块内 `.name` 访问接收者成员/方法、`$` 指代自身；`into` 为后置上下文关键字，出块仍返回接收者、可继续接后缀链（`.m()` / `->f` / `[i]`）或连续多段 `into`；支持语句形态与值形态（初始化器 / 赋值 / `return`，结果为接收者本身）；接收者只求值一次并按 value category 提升；`.m.ct` 类型宿主（含 shim）可作接收者、`$ =` 可接链；不做嵌套块、接口接收者、命名空间宿主、任意子表达式与常量初始化 | 新增 | ✅ 完成（2026-11-11；E30-1–E30-10 全部满足；`v0.30.0` 合并发布（Phase 27–30）内含实现，未逐相 bump；[history/design/phase30.md](../history/design/phase30.md)，D30-1–D30-19） | E30-1–E30-10 全绿：148–164 正例与四组可读性对比（两种写法同输出、归一化后逐字节相同）、八条 L30 负例（编译与 `ct check` 同文案同位置）、`__ct_recv` 保留名负例、153/155/156 产物无 wrapper/vtable、块后后缀链（含 `[i]`）与连续多段 `into` 正例、样例 `29_into_block` 进 `test/run.sh`、`check-ast.sh` **1073 passed / 0 failed**、`test/run.sh` **141 passed**、`check-warnings.sh` **353 ok / 0 failed**、`check-docs` OK（984 links / 179 files）、`check-all.sh` **OK（11 hard gates green）** |
| Phase 31 | **容器能力补齐**：接口值进容器（`Vec<Show>`、`Map<char *, Show>`）与嵌套容器（`Vec<Vec<int>>`、`Map<char *, Vec<int>>`）开放，并定义元素寿命与逐元素 `retain`/`release`；`v[i]` / `m[k]` 仅展开为 `get`；`Vec` / `Map` 花括号初值（`Map` 常量重复键编译期硬错、运行期按 `put` 覆盖） | 新增 | ✅ 完成（2026-11-12；E31-1–E31-30 全绿；S20b 独立复核的 1 High + 2 Medium + 2 Low 与 S23a–S23d / S24 / S28 均已落地；`examples/30–34` 进 `test/run.sh`；不 bump、不打 tag；[history/design/phase31.md](../history/design/phase31.md)，D31-1–D31-17） | E31-1–E31-30 与 L31-1–L31-23 全部落真门禁：`check-ast.sh` **1155 passed / 0 failed**、`check-warnings.sh` **389 ok / 0 failed**、`test/run.sh` **145 passed**、goldens 25+3+4 全 OK、`check-all.sh` **10/11**（`check-docs` 的唯一红项是另一会话在途的 `AGENTS.md` spec pin，与本相无关；该文件落定后复跑即 11/11）；S24 的 E31-27/E31-29 断言逐条钉住分配顺序与 OOM，S28 的 H-A 夹具 194/195 人工 ASAN 无报告（`/tmp/p31_asan_alias.log`） |
| Phase 32 | **类型安全检查网（B 档）**：`ct check --types` 在声明初值/赋值、`return`、容器实参三处做粗粒度类型校验（复用 19.2 的 `arg_class` 内核；覆盖结构体/接口/指针/算术类），并用 24 行**精确集合**（position/formal/actual/result/fixture/expected；7 L32-n + 6 ok + 11 skip + 0 n/a，期望源独立于实现 TSV）锁定覆盖率；两侧指针不校验基类型与层数；不带 `--types` 的 `check` 与编译/golden 不变；不做完整表达式类型系统、隐式转换规则、指针基类型与流分析 | 新增 | ✅ 完成（2026-11-12；E32-1–E32-19 全绿；`bash selfhost/check-all.sh` 11/11；随 `v0.33.0` 发布；[design/phase32-draft.md](../design/phase32-draft.md)，D32-1–D32-13） | 精确覆盖率集合（7 L32-n + 6 ok + 11 skip）与样例 `examples/35_type_safety` 进真门禁；不单独 bump、不打 tag |
| Phase 33 | **有界泛型 struct + 嵌套 impl pattern**：`struct Box<T: Show>` 实例化校验与 `impl<T> Box<T>` 继承 bound，`ct_impl_matches` 支持 `impl<T> Box<Box<T>>`（解析期标记类型参数，不登记伪实例；深度 >4 报 L33-4、不支持形态报 L33-5）；无条件并入 Phase 31 遗留 T31-2（接口/拥有元素跨单元单态化）；参数化 trait / 泛型 trait / supertrait 移入 Phase 35 | 新增 | ✅ 完成（2026-11-12；E33-1–E33-21 全绿，208 由 E33-15 的第二个构建驱动；O1–O3 无条件落地；不 bump、不打 tag；[design/phase33-draft.md](../design/phase33-draft.md)，D33-1–D33-12，实施期偏差见卡 §14） | `check-ast.sh` **1251 passed / 0 failed**（含 `p33_cross_unit` ×3 + `p33_nm`）、`check-warnings.sh` **412 ok / 0 failed**、`test/run.sh` **148 passed**、goldens 25+25+25 全 OK、`check-docs` 1131 links；样例 `examples/36_bounded_struct`、`37_nested_pattern` 进 `test/run.sh` 并人工核对 golden（`2 11`、`2 9 7`） |
| Phase 34 | **生态可用性**：`pub` 泛型函数（解禁 L26-2，单独评审）、**新增非泛型固有 `impl Name { … }` 语法并支持跨单元调用**、`Option`/`Result` 标准库（泛型 struct，非泛型 enum）；编译器 415–720（切片求和），库代码不占编译器预算；依赖 31/33 | 新增 | ✅ 完成（2026-11-13；E34-1–E34-15 全绿；O1–O3 落地；S8 的 `Option`/`Result` 外部元素实例归属修正见卡 §14；收口 `v0.34.0`；[design/phase34-draft.md](../design/phase34-draft.md)，D34-1–D34-13） | `check-ast.sh` **1272 passed / 0 failed**（含 `p34_option_point` ×3、`p34_option_iface_shape`）、`check-warnings.sh` **529 ok / 0 failed**、`test/run.sh` **148 passed**、goldens 82、`check-docs` 1137 links / 190 files；样例 `examples/38_ecosystem_reuse` 进 `test/run.sh` 并人工核对 golden（`4 4 4 cold 10 4 1`） |
| Phase 35 | **泛型 trait：参数化 trait 的单态化**：`trait Iter<T>` → `Iter_int`（命名按 `ct_inst_encode` 含哈希回退）、`impl Iter<int> for Circle`、`T: Iter<int>` 约束、受控的泛型 trait × 泛型 struct（`impl<T> Iter<T> for MyVec<T>`）；supertrait 移出本相、降级为开放项（A/B 形态评估见卡 §10.2）；跨单元实例本相硬错；依赖 33/34 | 新增 | ✅ 完成（2026-11-13；E35-1–E35-14 全绿；O1–O3 落地；收口 `v0.35.0`；[design/phase35-draft.md](../design/phase35-draft.md)，D35-1–D35-10） | `check-ast.sh` **1283 passed / 0 failed**、`check-warnings.sh` **534 ok / 0 failed**、`test/run.sh` **149 passed**、goldens 82、`check-docs` 1145 links / 190 files；产物命名 `Iter_int_vtbl` / `Iter_char_p_vtbl` / `__iter_int_vptr` / `Range_Iter_int_next` / `Iter_Box_lint_r_vtbl`；样例 `examples/39_generic_trait` 进 `test/run.sh`（`2 2 hi 7`）；跨单元实例 L35-4、第 65 条 trait 行 L35-8 |
| Phase 36 | **所有权与字符串**：泛型 `Drop`（`impl<T> Drop for Box<T>`，复用 Phase 31 元素协议，**声明顺序释放；显式 impl 自负全责、不生成字段 glue**）、带长度字符串 `Str` 落 `lib/std/Str.h.ct`（`char *data` + `len`；不依赖 NUL、保留内嵌 `\0`；`own Str *` 指针形态，无值移动；S0 实测 ct-pkg 无 `std/string`/`CStr`，按卡 §14 回退）；依赖 31/33/34 | 新增 | ✅ 完成（2026-11-13；E36-1–E36-8 全绿；L36-1 重复 release 诊断落地；收口 `v0.36.0`；[design/phase36-draft.md](../design/phase36-draft.md)，D36-1–D36-14） | `check-ast.sh` **1304 passed / 0 failed**、`check-warnings.sh` **592 ok / 0 failed**、`test/run.sh` **150 passed**、goldens 82、`check-docs` 1157 links / 193 files；产物 `Box_int_Drop_drop` / `Box_Str_Drop_drop` / `Option_Probe_Drop_drop` / `Str_Drop_drop`，无模板 `Box_Drop_drop`、无 vtable；样例 `examples/40_str_ownership` 进 `test/run.sh`；`Option<T>` / `Result<T,E>` 加 `use Drop`、工厂零初始化 payload |
| Phase 37 | **trait 签名硬错与运行期契约**：impl 签名不一致（返回类型 / 参数个数 / 参数类型）在 `ct build` 与 `ct check` 升为硬错，`ct compile` 保持 warning；`--runtime-checks` 可选地在空 vtable 派发前带 `文件:行` abort，默认关闭、关闭时产物逐字节不变；不扩类型系统 | 新增 | ✅ 完成（2026-11-13；E37-1–E37-4 全绿；收口 `v0.37.0`；[design/phase37-draft.md](../design/phase37-draft.md)） | `check-ast.sh` **1307 passed / 0 failed**、`check-warnings.sh` **593 ok / 0 failed**、`test/run.sh` **150 passed**、goldens 82、`check-docs` 944 links / 195 files；`p37_sig_*` / `p37_missing` / `219_runtime_guard`；L2 保持 warning（排除记录） |
| Phase 38 | **`defer` 块级清理**：`defer { … }` 按块作用域、后进先出执行，覆盖正常落出 / `return` / `break` / `continue`；`goto` 跨出或跨入带 defer 的块硬错；defer 内禁止控制转移与嵌套；同块内 defer 先于 `own` 自动释放 | 新增 | ✅ 完成（2026-11-13；E38-1–E38-8 绿；收口 `v0.38.0`；battle p38-1 / D-003；[design/phase38-draft.md](../design/phase38-draft.md)） | `check-ast.sh` **1329 passed / 0 failed**、`check-warnings.sh` **600 ok / 0 failed**、`test/run.sh` **152 passed**、goldens 82、`check-docs` **945 links / 197 files**；样例 `examples/42_defer`；P37 unstable guard 由 B′ 修复 |
| Phase 39 | **C ABI 导出面与库制品**：`ct build --lib` 产出 `<base>.abi.h` + `lib<base>.a`；根 `.h.ct` 的 C 兼容 `pub` 函数导出；泛型跳过；L39-1/1w/2–6；visibility/static/ar；D-001 C 路径、D-002 默认 A | 新增 | ✅ 完成（2026-11-13；收口 `v0.39.0`；E39-1–E39-9；[design/phase39-draft.md](../design/phase39-draft.md)） | `check-ast.sh` **1338 passed / 0 failed**、`check-warnings.sh` **600 ok / 0 failed**、`test/run.sh` **152 passed**、goldens 82、`check-docs` **946 links / 197 files**；p39 r1–r8 + docs 全绿；样例 `test/modules/p39_lib/consumer` |
| Phase 40 | **`errdefer` 与显式错误出口**：`return err:` / `break err:` / `continue err:` 标记错误出口；`errdefer` 与 `defer` 单栈 LIFO、只在错误出口执行；尾随声明绑定 `Type name = expr defer/errdefer { … };` 与只读 `$` | 新增 | ✅ 完成（2026-11-13；R1–R7；收口 `v0.40.0`（patch `v0.40.1` / SH-68）；[design/phase40-draft.md](../design/phase40-draft.md)） | `check-ast.sh` **1350 passed / 0 failed**、`check-warnings.sh` **605 ok / 0 failed**、`test/run.sh` **153 passed**、goldens 82、`check-docs` **962 links / 217 files**；`p40 r1/r2/r4/r5/docs` + `p40_return_err` / `p40_break_continue` / `p40_order_own` / `p40_trailing`；样例 `examples/43_errdefer` |

| Phase 41 | **原子并发能力**：`atomic int/long/bool/void *` → `_Atomic(T)`；`ct_atomic_load/store/cas`（seq_cst）；12 个 static inline 运行头；C11 构建；L41 诊断；pthread 取消/引用计数；TSan nightly；tmLanguage/grammar | 新增 | ✅ 完成（2026-11-13；R1–R9；收口 `v0.41.0`；battle p41-1 / D-004；[design/phase41-draft.md](../design/phase41-draft.md)） | `check-ast.sh` **1357 passed / 0 failed**、`check-warnings.sh` **614 ok / 0 failed**、`test/run.sh` **154 passed**、goldens 82、`check-docs` **985 links / 220 files**、grammar **169/0**、TSan 2/2；样例 `examples/44_atomic_counter`；`p41/runtime` + `p41/errors` 全绿 |
| Phase 42 | **`impl` 方法可见性**：方法级 `pub`，默认私有；私有 = 不进 `.h` + `static` + 跨单元硬错；52 条显式 `pub`；trait impl / 块级 `pub impl` 拒绝；L42-1–L42-7 | 新增 | ✅ 完成（2026-11-14；R1–R8；收口 `v0.42.0`；battle p42-1 C；[design/phase42-draft.md](../design/phase42-draft.md)） | `check-ast.sh` **1361 passed / 0 failed**、`check-warnings.sh` **614 ok / 0 failed**、`test/run.sh` **154 passed**、goldens 82、`check-docs` **987 links / 220 files**、grammar 169/0；`p42/pub-syntax` / `private` / `cross-unit` / `generic` 全绿 |
| Phase 43 | **`return err:` 载荷类型契约**：`err:` 载荷必须可赋给函数返回类型；L43-1 硬错、四入口一致、不写坏 C；普通 return 保持 `--types` 可选 | 新增 | ✅ 完成（2026-11-14；R1–R6；收口 `v0.43.0`；[design/phase43.md](../design/phase43.md)） | check-ast **1364/0**、test/run 155、warnings 616/0、docs **1035 links / 224 files**；`p43/errors` 4/4；样例 `examples/45_error_return_contract` |
| Phase 44 | **后缀 `?` 错误传播**：`Result<T,E>` 的失败以 `Outer::err` 返回，成功取 `value`；`?:` 消歧；L44-1..4；临时量清理 | 新增 | ✅ 完成（2026-11-14；S1–S9；收口 `v0.44.0`；[design/phase44.md](../design/phase44.md)） | `p44/syntax` 22/22、`p44/errors` 9/9、`p44/drop` 7/7；check-ast **1370/0**、test/run 156、warnings 620/0、docs 1035/224 |

> **Agent 内核运行库（ct-pkg，外部）**：`arena` / `sync` / `callback` 今天可做，`result` / `string` 分别等 Phase 34 / 36，ABI 打包等 Phase 39；提案见 [proposals/ct-pkg-agent-runtime.md](../proposals/ct-pkg-agent-runtime.md)。

> **未排期（治理项）**：① **增量编译基准**——build cache 已有（Phase 10.5 的 cold/warm 与依赖失效），先在 Phase 36 收口提交上测冷/热构建与内核规模语料，再决定是否立项；② **稳定子集清单**——Z6 的 1.0 冻结原则已有，补 trait / Drop / arena 的具体清单，属文档治理，不占 Phase 编号。

> **外部计划：ct-pkg Phase 2**（生态映射包，计划文档在同级 ct-pkg 仓库 `docs/phase2.md`）

> **阶段编号说明（2026-11-02，计划）**：`v0.13.0`–`v0.16.3` 已在下方「版本记录」中标为 **Phase 12 之后的能力 / 修复补丁**，并未作为 Phase 13–16 的阶段号。下一阶段因此取 **Phase 17 ↔ `v0.17.0`**，以维持「Phase *n* ↔ `v0.n.x`」不变量；该编号已由用户确认（D17-1）。
> **Phase 20 / 21 / 22（2026-11-06；22 于 2026-11-07 追加；20 于 2026-11-07 收口）**：Phase 20 = **包支持**（[history/design/phase20.md](design/phase20.md)，已完成，收口 `v0.20.0`，含 `915c12c`；P20-05 只移出 ct-pkg 侧索引生成器、ct 侧 `pkg_index_lookup` 仍欠，P20-07 延后）；Phase 21 = **非逃逸栈闭包**，取 **`v0.21.x`**，详见 [history/design/phase21.md](design/phase21.md) §1；Phase 22 = **`loop` 语法糖**，取 **`v0.22.x`**，详见 [history/design/phase22.md](design/phase22.md)。三相无语义依赖，可独立实施；仅因共用 parser / emitter / diag 文件而在合并次序上互相留意。
> **Phase 21 收口（2026-11-08，S7）**：S0–S5 与 S7 已落地——自举守卫（`selfhost/**` 的编译器源码不得使用闭包字面量；`v0.21.0` tag 存在后放行）、language-spec §4.44 与 tutorial §10.1 的闭包文档（中英对称）、以及版本收口（`CTC_VERSION` 五处 + 71 个 golden 仅版本 token 变化）。**S6（`Callable` 签名族）是外部依赖**：承载形式已定为 ct-pkg `.h.ct` 的普通 `pub trait` + `struct` 签名族（D21-7），该仓改动归用户侧安排，**不在本相出口判据内**；依赖它的探针 78 同样记外部依赖；**档①与档②的互通性随 ct-pkg 的 `Callable` 签名族发布一并验证**，本仓不另做等价替代探针。收口提交已就绪，push 与 `v0.21.0` tag 待用户确认。

> **L2 冻结声明（2026-10-22）**：`selfhost/l2/**` 是 Phase 9 之前的旧管线，现降为**回归 oracle**——只修 bug，不再新增语言特性。所有新特性一律落在 `selfhost/ct-ast/**`；`check-archive.sh` 以 L2 为对差基准，任何「为了让新用例通过而改 L2 行为」的做法都不被接受。L2 与 ct-ast 之间已有的语义分叉（块式 namespace、跨命名空间裸调用）保持原样，视为 oracle 的既有边界，不判为缺陷。

> **历史说明**：Phase 0 之后曾一度把 namespace / import / Drop / 诊断 / 多文件**直接实现在 C 侧**（`ctc.c`，即旧称的 Phase 1）。按本路线，这些属**越位实现**：语法决策保持冻结，但**实现要用 CT 重做**——先由 **Phase 0.3** 把它们从 `ctc.c` 移出并归档为 oracle，再由 **Phase 2–5** 用 CT 逐项恢复（回归清单见下方「自举之后的恢复与新增」节）。
>
> **编号约定**：下文出现的 `Phase 1.0`–`Phase 1.9`、`Phase 1.6/1.7/1.9c` 等，是**越位实现期的历史子阶段编号**，与新的 **Phase 1（自举）**无关。`Phase 0.1` / `0.2` / `0.3` 是 Phase 0 的**历史子阶段**，编号保留不动。
>
> **重编号记录（2026-10-16 用户确认）**：原「Phase 2（含 4 个子阶段）+ Phase 3」把**特性族**伪装成了子阶段（2.1–2.3 的 DoD 其实同属「恢复」类），而且与版本号无法一一对应。现把子阶段**升为一级阶段**，并把「类别」（恢复 / 新增）降为总览表的一列，另立 Phase 7：

| 旧编号 | 新编号 | 主题 |
| --- | --- | --- |
| Phase 2.1 | **Phase 2** | 模块化（namespace / 多文件 / `pub` / `import`） |
| Phase 2.2 | **Phase 3** | 内存（Drop / `delete` 放宽） |
| Phase 2.3 | **Phase 4** | 诊断与溯源（`#line` / 泄漏警告 / `--diagnostics`） |
| Phase 2.4 | **Phase 5** | 新增特性（AutoDrop / 路径敏感分析 / 目录 = namespace） |
| Phase 3 | **Phase 6** | 生态与扩展（`map` / 方言系统 / 增量编译…） |
| （无） | **Phase 7** | 工具链形态（单入口 `ct` + `ctc` 兼容别名） |

> 读到旧文档（或本仓库 `reports/` 里的旧报告）中的「Phase 2」「Phase 3」时，按上表换算。以上编号与版本号**一一对应**：Phase *n* ↔ `v0.n.x`（见「版本记录」）。


## 版本记录（详表）

| 版本 | 对应阶段 | 内容 |
| --- | --- | --- |
| v0.0.1 | Phase 0 | trait / struct / impl / use 的结构转换、方法调用重写、配套 `.h`、五层回归测试 |
| v0.1.0 | Phase 1 自举（里程碑已达成；版本号并入 v0.4.0） | L1（`selfhost/l1/ctc.ct`）对 `test/cases/**` 全量 25/25 逐字节一致，且 L1 编译自身（L1′）重跑同一批语料仍逐字节一致 |
| v0.2.0 | Phase 2 模块化（里程碑已达成；版本号并入 v0.4.0） | namespace / 多文件 `ct build` / `pub` / `import` / `.h.ct` / `-I`；归档用例逐字节一致，编译器源码拆成 `selfhost/l2/**`（L1 建出 L2，对 `test/cases/**` 25/25 一致） |
| v0.3.0 | Phase 3 内存（里程碑已达成；版本号并入 v0.4.0） | Drop / `delete` 放宽，已在 `selfhost/l2/**` 恢复（L1 冻结）；`22_drop` 逐字节一致 |
| v0.4.0 | Phase 4 诊断与溯源（2026-10-17 bump，现已由 v0.5.0 接替） | `#line` + `--line` / `--no-line`、泄漏警告 + `--diagnostics`、多错误恢复、语义诊断（重复定义报错 / 签名不一致告警）；全量 golden 按新版本重生成 |
| v0.5.0 | Phase 5 新增特性（2026-10-17 bump，现已由 v0.6.0 接替） | AutoDrop（`own`）、条件 return 的路径敏感泄漏告警、目录 = namespace 校验（`--ns-root`）；全量 golden 按新版本重生成，**M6 收口** |
| v0.6.0 | Phase 6 生态与扩展（2026-10-17 bump，现已由 v0.7.0 接替） | 反向映射表 `--emit-map` / 调用图 + 跨函数所有权 / 增量编译缓存 / `--std` 多目标 / 方言系统（仓库外展开器）；`map` 仅设计冻结；全量 golden 按新版本重生成，**Phase 6 收口** |
| v0.7.0 | Phase 7 工具链形态（2026-10-17 bump，现已由 v0.8.0 接替） | 单入口 `ct`（按 `argv[0]` 识别身份）+ `ctc` 兼容别名 / 安装形态（`ct` + `ln -s ct ctc`）/ 生成物 banner 改为 `Generated by ct v…`（含 map 的 `compiler` 字段）；全量 golden 按新版本重生成，**Phase 7 收口** |
| v0.8.0 | Phase 8 包管理与分发（2026-10-18 bump，现已由 v0.9.0 接替） | `ct-pkg`：极简 `ct.pkg` 清单 / git registry + 本地目录源 / MVS + SemVer 子集 / `ct get`（commit + 内容摘要锁定）/ `ct install`（离线校验 + 建议命令）/ 五列 `ct.lock`；全量 golden 按新版本重生成，**Phase 8 收口** |
| v0.9.0 | Phase 9 AST 版编译器（2026-10-18 bump，现已由 v0.10.0 接替） | `selfhost/ct-ast/main.ct` 新主线：自编 + 不动点 + 全量行为等价（`check-ast.sh` 收口时 60 项；2026-10-31 实测 408 项）；旧管线 `selfhost/l2/**` 按 D36 冻结归档（tag `pre-ast-mainline`）；`CTC_VERSION` 同步改动 `ctc.c` / L1 / `l2/{core,driver}.ct` / `ast/main.ct` 五处，`test/cases/**` 与 `test/modules/**` 共 103 个 golden 重生成（仅版本 token 变化），**Phase 9 收口** |
| v0.10.0 | Phase 10 主线切换（2026-10-19 bump，现已由 v0.11.0 接替） | 10.1–10.7 全部落地：CLI/身份、语义诊断、内存（Drop / AutoDrop / 泄漏）、多错误恢复、增量缓存、包管理迁移，最后把安装入口改由 **ct-ast** 提供（L2 降为回归 oracle，切换前 tag `pre-ct-ast-switch`）；`CTC_VERSION` 五处同步，`test/cases/**` 50 + `test/modules/**` 58 共 108 个 golden 重生成（仅版本 token 变化），**Phase 10 收口** |
| v0.11.0 | Phase 11 `map` 构造（2026-10-19 bump，现已由 v0.11.1 接替） | 11.1–11.2 全部落地：`map trait T for instance x { m() → CALL; }` 的解析、实例级包装函数 `<inst>_<Trait>_<method>` 与 vtable `<inst>_<Trait>_vtable`、`--emit-map` 的 `maps` 字段，以及**派发接线**（实例装箱用实例级 vtable，未 `use` 该 trait 的 struct 亦可作为其实例运行）；`CTC_VERSION` 五处同步，`test/cases/**` 50 + `test/modules/**` 53 共 103 个 golden 重生成（仅版本 token 变化），**Phase 11 收口** |
| v0.11.1 | Phase 11 加固（2026-10-19 patch bump，现已由 v0.12.0 接替） | **11.3** 落地：绑定**完整性**（覆盖 trait 每个方法，漏绑会让 vtable 留空指针槽即崩溃）与**唯一性**（重复绑定会发射两份同名包装函数即 C 重定义）校验 + CALL 实参子集放宽为「数字 / 字符串字面量、可见名字（绑定形参、本 map 的实例、此前已声明的变量）、以实例为根的成员路径 `x.f` / `x->f`（可带 `&`）」；正向 fixture `test/ast/15_map_args/`，负例 `map_partial` / `map_dup` / `map_bad_path`；`CTC_VERSION` 五处同步，全量 golden 重生成（仅版本 token 变化），**Phase 11 内 patch** |
| v0.12.0 | Phase 12 生态扩展（2026-10-19 bump，现已由 v0.13.0 接替） | 12.1–12.4 全部落地：仓库内新增顶层 `bindings/**` 与**首个官方 binding** `bindings/mock-hal/`（`#include` 直通 + 镜像 `trait`/`struct` + 声明全局实例 + `map`，**零新增语言特性**）；binding 规约 `bindings/README.md`（12.2）；单文件**多方言并存**路由 + 作者指南（12.3，含 `fsm-state` 方言插件与「路由只处理首个方言标记」缺口的修复）；并顺带修复 ct-ast 主线在 build 多文件模式下 `map` 未发射包装函数 / vtable 的缺陷；`CTC_VERSION` 五处同步，`test/cases/**` 与 `test/modules/**` **共 103 个 golden 重生成**（仅版本 token 变化），**Phase 12 收口** |
| v0.13.0 | Phase 12 之后的能力补丁（2026-10-31 bump，现已由 v0.14.0 接替） | ct-ast 的 C 子集补齐（第二十一至二十八批）：长初始化器、变参函数指针、逗号表达式、头文件里的类型名、表达式里的赋值、前缀 `++` / `--`；并把「ct-ast 编 `ctc.c`、产物与 25 个 L0 golden 逐字节一致」固化为关卡。`CTC_VERSION` 五处同步，`test/cases/**` 50 个文件与三份 map golden 重生成（仅版本 token 变化） |
| v0.14.0 | Phase 12 之后的能力补丁（2026-10-31 用户授权 bump，现已由 v0.15.0 接替） | 第三十六批：**trait 默认方法**——方法体写在 trait 里，采纳点只实现抽象方法；全 default 的 trait 连 `impl` 都不需要（`use` 即采纳）。默认体按 (struct, trait) 各展开一份，vtable / 装箱 / 派发零改动；覆盖优先级 impl > default，成环与展开失败各有诊断。`CTC_VERSION` 五处同步，50 个 `test/cases/**` golden 与 21 个含 banner 的 `test/modules/**` golden 重生成（仅版本 token 变化） |
| v0.15.0 | Phase 12 之后的能力补丁（2026-10-31 用户授权 bump，现已由 v0.15.1 接替） | 第三十八批：**`.m.ct` 零成本静态映射**——映射单元不产任何 `.c`/`.h`，静态 trait 无 `_iface`/`_vtable`，`host::Trait.method(…)` 与 `for type char *` 的调用点在编译期展开为普通 C 调用（recipe 原位替换、`&p` 用 compound literal），prologue 展开进消费者 `.c`，跨单元同样零 wrapper；`--emit-map` 增加 `static` / `host` / `type` / `inline` / `symbol` 字段。`CTC_VERSION` 五处同步，`test/cases/**` 与 `test/modules/**` golden 仅版本 token 变化 |
| v0.15.1 | Phase 12 之后的修复补丁（2026-10-31 用户授权 bump） | 修复 `.m.ct` recipe 的 `sizeof` 两处缺陷：空白不再覆盖 `prev`（`sizeof p` 不被计为一次求值，实参副作用以 `(void)(…)` 前缀保留，同一参数多次 `sizeof` 不再误报重复求值）；新增 `sizeof(p)` 对绑定参数的拒绝（`map recipe takes 'sizeof p', not 'sizeof(p)'`，避免静默变成实参值的大小）。补测试/关卡：`sizeof` 正负例、普通 `.h.ct` 里 `for type` 的负例、传递 `.m.ct` import 与传递依赖缓存（`test/modules/map_unit_chain`）；language-spec 的 `MAX_NODES` 文档漂移（65536 → 131072）同步修正。`CTC_VERSION` 五处同步，golden 仅版本 token 变化 |
| v0.16.0 | Phase 12 之后的能力补丁（2026-11-01 用户授权 bump） | `borrow` + `Handback`：`borrow` 作为上下文关键字接入参数列表与语句行首，`Handback` 为内建 trait（照 `Drop` 处理，只发 `<S>_Handback_handback`，无 vptr / vtable）；声明作用域闭合与**每个** `return` 之前（无位置要求，分支内 / 行内均可）按声明逆序注入 `if (c) { <S>_Handback_handback(c); c = 0; }`（「归还」，对象仍活着），与 `own` 共用一张逆序表；借用句柄重新赋值、存入 `static` / 文件作用域等更长寿位置、在文件作用域声明 `borrow` 均为编译错误（SH-35 / SH-37 / SH-34）；`delete` 借用指针被拒绝。前置修复 SH-33——行首 `return` 前 AutoDrop 不注入、不置空，改为先销毁再 `return`。仅 ct-ast；`CTC_VERSION` 五处同步，`test/cases/**` 50 + `test/modules/**` 21 共 71 个 golden 仅版本 token 变化 |
| v0.16.1 | Phase 12 之后的修复补丁（2026-11-01 用户授权 bump） | 收掉 2026-11-01 代码审查的 15 条：文件作用域拒绝 `borrow`（SH-34）；借用变量不再被 `leak_*` 清掉归还，重赋值改为编译错误（SH-35）；`return` 改用「真正移交」判定——`return p->n;` 不再取消归还、`return p;` 不再误报泄漏（SH-36 / SH-41）；拒绝把借用存进 `static` 局部或全局（SH-37）；impl 写在 `borrow` 之后不再误报，消息统一为 `this unit has no impl`（SH-39，跨单元限制按 SH-38 建议文档化）；`delete` 只对可赋值实参追加 ` = 0; `（SH-40）；同步 tutorial / memory-guide / design / language-spec / roadmap / glossary 与编辑器语法（`ct-borrow` + 内建 trait 高亮，断言 31→33）。`CTC_VERSION` 五处同步，golden 仅版本 token 变化 |
| v0.16.2 | Phase 12 之后的修复补丁（2026-11-02 用户授权 bump） | 收掉 2026-11-01 第三方复核的 5 条：SH-42 把 `Arena` / `Symbols` / `Parser.g_maps` / `Module.g_units` 四张超大静态表改为堆分配（`ct` 二进制 88M → 637K、`__DATA` 105MB → 589824 B）；SH-44 把 `ct.lock` 的包摘要从 16 位 FNV 换成 SHA-256（按路径排序后单流哈希，写 `sha256:<64 hex>`，旧摘要显式报 `unsupported digest`），`test/pkg/run.sh` 补 same-size tamper 与 legacy digest 两组断言；DOC-51 教程 §7 把 `impl_dog.ct` 订正为 `.h.ct` 并补 import 后缀规则；DOC-52 教程 §11 / language-spec §6.2 的行管线限制标注「仅 L2」并说明 ct-ast 不保留源码注释；SH-43（`--emit-build-plan` / `--cc`）维持待决。`CTC_VERSION` 五处同步，71 个 golden 仅版本 token 变化 |
| v0.16.3 | Phase 12 之后的修复补丁（2026-11-02 用户授权 bump，现已由 v0.17.0 接替） | 处置 2026-11-02 复核的 5 条：SH-45 让 `return` 表达式读取的 AutoDrop 对象先物化为临时变量（`<T> __ct_retN = …;`）再执行出口释放，并 `return __ct_retN;`（此前的逆序释放会先释放再读取，读到已释放的值），新增 `test/ast/63_own_return_field` / `64_borrow_return_field` 钉住「读取字段」与「移交指针」两种写法；SH-47 把字段上限诊断改为点名 struct 与上限（`too many fields in struct '<name>' (limit 64)`），`check-ast.sh` 同步断言（+2）；DOC-53 订正 language-spec §6.1 的重名陈述、§4.3 补「同名跨 trait 的裸调用按 `use` 顺序取第一个」（SH-46 不采纳硬报错，`test/cases/06_name_collision.ct` 已钉死该语义）；DOC-54 在 language-spec §4.10 补单元种类表与 import 搜索顺序，tutorial 同步。`CTC_VERSION` 五处同步，71 个 golden 仅版本 token 变化 |
| v0.17.0 | Phase 17 工程质量与新能力（2026-11-02 用户授权 bump） | 17.1–17.6 全部落地：CI 平台矩阵 + ASAN/UBSAN + 确定性 fuzz（`.github/workflows/{ci,nightly}.yml`、`selfhost/check-sanitizers.sh`、`test/fuzz/run.sh`）；官方 `std`（str / vec / arena / fs / utf8 / test / map 七模块 + `test/std/run.sh`）；`#ct-raw` / `#ct-endraw` 原样透传；文档分层 + `test/docs/check-docs.py`（链接 / 版本 token / 门禁条数 / 阶段状态）；包管理补全（`ct update` / `ct verify`、比较器范围、显式纯文本索引 `CT_INDEX` / `--index`、`ct.pkg` 的 `cflags` / `ldflags` / `requires`，`ct install` 打印一条含 `-I` / `-D` / `-l` 的命令）；`ct build` 默认调用本地 C 编译器产出可执行文件，`--emit-c` 保留只发 C。`test/pkg/run.sh` 58 项、11 道硬门禁全绿；`CTC_VERSION` 五处同步，71 个 golden 仅版本 token 变化，**Phase 17 收口** |
| v0.18.0 | Phase 18 生态建设（2026-11-02 用户授权 bump） | 18.0–18.6 全部落地：18.0 解除 L2 容量上限（`MAX_FUNCS 128→256`、`MAX_MAP_IMPLS 256→512`，四张定长表改 `calloc`；L2 二进制 13,403,192 B → 918,712 B、`__DATA` 13,107,200 B → 720,896 B）；18.1 包规范与作者指南 `docs/package-guide.md`；18.3 契约包 `ct-pkg/hal`（`Uart` / `Gpio` / `Clock` / `Log` 四个纯 trait）；18.4 平台包 `ct-pkg/hal-posix`（binding + 四个 `map`，一个 `posix_hal` 实例装箱成四个 trait，`cflags = -D_POSIX_C_SOURCE=200809L`）；18.5 C 映射包 `ct-pkg/clib`（string / stdio / math 的 `.m.ct` 静态映射，`ldflags = -lm`）；18.2 索引仓库 `ct-pkg/index`（五字段纯文本 + 夜间 `refresh-index.sh` 重算摘要并提交）；18.6 仓库内 `examples/wave1-demo` 与 `.github/workflows/packages.yml`（宿主 + Linux aarch64/QEMU 两 job 跑 `ct get` → `ct verify` → `ct install` 打印的命令 → 运行比对）。本地硬门禁仍为 11 道；`CTC_VERSION` 五处同步，`test/cases/**` 50 + `test/modules/**` 21 共 71 个 golden 仅版本 token 变化，**Phase 18 收口**（`v0.18.0` tag 在评审通过后打） |
| v0.18.1 | Phase 18 之后的修复补丁（2026-11-03 用户授权 bump） | PKG-2：`ct get` 保留本次未重解的 `ct.lock` 行（二次 `ct get` 不再丢上一次的 pin，`ct update` 不再把 `hal-posix` 从 1.0.1 降回 1.0.0、wave1-demo 的 `clock` 不再恒为 0），`test/pkg/run.sh` 71 项；`packages.yml` 加锁断言（恰 3 行 + `hal-posix 1.0.1`）、索引下载 `--retry 3`、触发路径扩到 `selfhost/{l0,l1,l2,ct-ast}/**`；Linux 门禁清零（`39_builtin_types` 补 `<sys/types.h>`、`45_pre_incr` / `map_unit_shim` / `ns_globals` 不再依赖参数求值顺序、`sha_sort` 的 `-Wrestrict` 与 `map_unit_type` 的 `-Wunused-value` 消除）。`CTC_VERSION` 五处同步，71 个 golden 仅版本 token 变化 |
| v0.20.0 | Phase 20 包支持（2026-11-07 用户授权 bump） | 包支持切片落地：限定调用按 trait 消解同类型多映射（P20-01）、声明之后的 import 直接报错（P20-02）、类型宿主映射调用校验实参个数（P20-03）、`requires` 改为硬失败并由 `--force` 降级（P20-04）、`ct.pkg` 的 `namespace` 收窄导入路径首段并检测跨根重名（P20-06）、`.m.ct` 前导区错误指向 shim 与文案收口（P20-08）；P20-05 只移出 ct-pkg 侧索引生成器（ct 侧 `pkg_index_lookup` 仍欠）、P20-07 延后（见 `docs/history/design/phase20.md`）。`CTC_VERSION` 五处同步，`test/cases/**` 50 + `test/modules/**` 21 共 71 个 golden 仅版本 token 变化 |
| v0.20.1 | Phase 20 之后的收口小修批次（2026-11-07 用户授权 bump） | 六项小修：SH-53 容量触顶诊断写明单元与上限（五处文案 + 断言）、CI-3 `check-all.sh` 入口工具预检（`cc` / `diff` / `python3` / `git`）、DOC-63 tutorial / memory-guide 抬头不再钉版本号并纳入 `check-docs.py`、L1 trait 限定名诊断改用 C 名（不再把 `_` 反解成命名空间段）、L3 `check-archive.sh` 版本归一化容忍空白、TEST-9 容量上限的契约测试范围写成显式约定。`CTC_VERSION` 五处同步，`test/cases/**` 50 + `test/modules/**` 21 共 71 个 golden 仅版本 token 变化 |
| v0.20.2 | Phase 20 之后的评审修复（2026-11-07 用户授权 bump） | 评审 M1–M6 与 L2–L4 处置：M1 `-I` 根与单元路径先 `realpath` 再比较（`resolve_import` 三条豁免 + `ct_pkg_ns_clash`）；M2 `ct get` 的 `requires` 校验先于 `vendor/` 落盘、拒绝时目录逐字节不变；M3 `requires` 里 `ct` 后可直接跟 `> < = ^ ~ *`；M4 静态初始化器解析函数名，歧义改为诊断；M6 `ct_root_find` 在 flat 与 doubled 两种布局同时命中时报歧义；L4 `check-all.sh` 的 `CC` 预检只取第一个词；L2/L3 修正 `docs/history/design/phase20.md` 的抬头与 P20-05 判据口径。M5（form 5 的 arity 不认变参 trait）记为 SH-61，待变参 trait WIP 落地。`CTC_VERSION` 五处同步，`test/cases/**` 50 + `test/modules/**` 21 共 71 个 golden 仅版本 token 变化 |
| v0.20.3 | Phase 20 之后的叶子能力（2026-11-08 用户授权 bump） | 映射单元类型别名 `pub type X = <type>;`：解析期在 `parse_type` 就地展开（不生成 C typedef），别名只允许出现在 `.h.ct` / `.m.ct` 且 `.m.ct` 内必须 `pub`；声明前使用、循环、重名、与 trait/struct 冲突、未 import 各有独立诊断；`for type` 宿主与映射键把别名与底层拼写折叠成同一宿主键（`map` 的 `for type` 宿主改走 parser）；见 `docs/history/design/phase20-type-alias.md`。新增 `test/ast/67_type_alias` 正例与 6 个 `type_alias_*` 负例、`check-ast.sh` batch 42。trait 方法变参（`...` 透传）不在本版内。`CTC_VERSION` 五处同步，`test/cases/**` 50 + `test/modules/**` 21 共 71 个 golden 仅版本 token 变化 |
| v0.21.0 | Phase 21 非逃逸栈闭包（2026-11-08 收口提交，待发布） | `=>` 就地闭包：表达式体与块体（S3/S5）、按值捕获与只读捕获（S4）、嵌套闭包与 `(fn, env)` 字面量实参（S5）；逃逸 / 拷贝 / 存字段 / 捕获 `own`·`borrow`·闭包均为硬错误，hint 指向 ct-pkg 的 `Callable` 签名族。S7 补自举守卫（`selfhost/**` 编译器源码不得使用闭包字面量，直到 `v0.21.0` tag）、language-spec §4.44 / tutorial §10.1 中英文档、以及本版收口。**S6（`Callable` 签名族）是 ct-pkg 外部依赖，不在本相出口判据内**。`CTC_VERSION` 五处同步，`test/cases/**` 50 + `test/modules/**` 21 共 71 个 golden 仅版本 token 变化 |
| v0.22.0 | Phase 22 `loop(n)` 计数循环（2026-11-08 收口提交，待发布） | `loop(<count>) { … }` 语法糖：上下文关键字（仅语句位置 + `(`）、隐式可写 `int i`、计数只求值一次（私有 `__ct_loop_n_K`）、展开为单行 `for`；三条语法硬错误（空计数 / 非块体 / 多计数）、L22-4 嵌套遮蔽（编译 warning、`ct check` 报错，kind 7 `loop_shadow`）、L22-5 静态非整数计数告警（kind 5）。新增 `test/ast/92–101`、`loop_count_type`、`loop_own_drop` 与 4 个负例；language-spec §4.45 / tutorial §10.2 中英文档。`CTC_VERSION` 五处同步，`test/cases/**` 50 + `test/modules/**` 21 共 71 个 golden 仅版本 token 变化 |
| v0.23.0 | Phase 23 `loop(a..b)` 半开区间（2026-11-08 收口提交，待发布） | 新增 `..` 单 token（置于 `...` 之后、`.5` 之前）；`loop(<start>..<stop>)` 展开为一条单行 `for`，`i = ((__ct_loop_n_K = (<start>)), (__ct_loop_hi_K = (<stop>)), __ct_loop_n_K)` 用逗号运算符定序，两边界各求值一次、先 `a` 后 `b`（C99 §6.5.17）；字面量 0 下界在解析期折回 `loop(n)`（`-0` / `0+0` 不折）；L23-1 缺边界、L23-3 指针/数组/结构体/联合体/函数指针边界硬错（Phase 22 的 `loop(arr)` 与二维数组字段静默洞；**breaking change**）、L23-2 复用 L22-5；新增 `test/ast/102–108`、`loop_range_own_drop` 与 7 个负例；language-spec §4.46 / tutorial §10.3 / glossary / design/phase23.md 中英文档。`CTC_VERSION` 五处同步，71 个 golden 仅版本 token 变化 |
| v0.24.0 | Phase 24 数组 range 初值（2026-11-09 收口，待发布） | `int a[] = <start>..<stop>(<表达式>)` 展开为花括号初始化列表：元素表达式只存一棵 AST、发射期把 `$` 换成 `((int)k)` 并复用，产物无循环、无临时量，可用于文件作用域 `static const` 表。边界只收整数字面量（十进制 / `0x` / 八进制、`U`/`L` 后缀、可选一元 `-`），`0x` 无数字与 `long` 溢出各报硬错（共享词法器不改）；L24-1 缺边界、L24-2 非字面量、L24-3 空区间、L24-4 超 1024、L24-5 非数组、L24-6 聚合元素、L24-7 维度不匹配、L24-9 溢出、L24-10 维度里的 `$`、L24-11 对 `$` 取地址 / 自增；L24-8 随 `$` 取代标识符而撤销，编号不复用。新增 `test/ast/109–115`、`117` 与 16 个负例；language-spec §4.47 / tutorial §10.4 / history/design/phase24.md 中英文档；`selfhost/**` 加 range 初值自举守卫（`v0.24.0` tag 存在后放行）。**S5 收口**：`CTC_VERSION` 五处同步到 `0.24.0`，71 个 golden 仅版本 token 变化 |
| v0.25.0 | Phase 25 静态映射调用的闭包实参（2026-11-09 收口，待发布） | `.m.ct` 静态映射调用（类型宿主 / 命名空间宿主 / `aux==6` / `qf==3/4/5` 四种形态）接受闭包实参，复用 Phase 21 的 `(fn, env)` ABI：arity 按两项计，recipe 的 `fn` / `env` 槽位由 `map_actual_span` 与 `half[]` 定位；L25-1 非参数对位、L25-2 重复引用、L25-3 `...` 尾部、L25-4 两半未成对、L25-5 真少参数。新增 `test/ast/120–122` 与 `test/modules/p25_static_argtype` / `p25_static_closure` / `p25_static_closure_neg`；language-spec §4.10 / §4.44 与 tutorial §10.1 中英文档。**S5 收口**：`CTC_VERSION` 五处同步到 `0.25.0`，74 个 golden（`test/cases/**` 50 + `test/modules/**` 21 + `examples/tour/**` 3）仅版本 token 变化 |
| v0.26.0 | Phase 26 泛型函数（2026-11-09 收口，待发布） | 声明 `T name<T>(...)`，调用 `name<int>(...)` 显式实例化；每个 `(模板, 具体类型)` 生成一份 `static` 实例 `<name>__ct<N>`，模板本身不落 C 符号。实现走「发射期类型替换上下文」（不写 AST，B26-1 第二轮）：实例复用模板 `N_FUNC`，发射器持 `gtparam/gtarg/gtname`，六个类型打印点按上下文替换。L26-1 缺类型实参、L26-2 `pub` 泛型、L26-3 多类型参数、L26-4 `void` 作实参、L26-5 泛型体内调用泛型。新增 `test/ast/123–124` 与 5 个负例；language-spec §4.48 / tutorial §10.5 中英文档。**S5 收口**：`CTC_VERSION` 五处同步到 `0.26.0`，golden 仅版本 token 变化 |
| v0.26.1 | Phase 26 评审修复补丁（2026-11-09，SH-62 / SH-63 / TEST-17 / DOC-67） | SH-62：模板体内的 `sizeof(T)` / `_Alignof(T)` / `offsetof(T, …)` / `(T)` 由「静默坏产物 / 解析失败」改为真替换（B26-2 判决方案 A，D26-12）；同时补齐 `va_arg(ap, T)`。SH-63：`ct_generic_subst` 对紧邻 `struct` / `union` / `enum` 的同名 token 前瞻跳过，`struct T` 不再变成 `struct int`（D26-13）；裸返回类型 `T` 被标签解析吞掉时按类型参数改写。TEST-17：新增 `test/ast/125`（局部声明 / cast / `sizeof` / `_Alignof` / `offsetof` / 调用实参 / `va_arg`）、`126`（`struct T` 标签）、`127`（实例名冲突回退）、`generic_too_many`（第 65 个实例硬错），并加运行前红证。DOC-67：§4.48 中英、phase26 §2.3–§2.5 / E1、roadmap L26-3/L26-4 文案与 AGENTS 版本登记对齐实现。**S5 收口**：`CTC_VERSION` 五处同步到 `0.26.1`，74 个 golden 仅版本 token 变化 |
| v0.26.2 | Phase 26 评审重开修复（2026-11-09，SH-62 / TEST-17 第二轮） | 根因修复类型操作数解析路径：抽出 `tok_is_type_name()`，`sizeof` / `_Alignof` / `alignof` 统一先判当前 token，无括号 `sizeof T` / `_Alignof T` / `alignof(T)` 走 `parse_type`；`type_no_ptr` 截止在一个类型名，`sizeof T * 2` 仍是乘法（D26-14，分支矩阵见 phase26 §2.6）。产物层新增 `tparam_residue()` 系统性防线：扫描每个泛型夹具的生成 C，扣掉合法 `struct|union|enum T` 标签，残留未声明类型参数即红。P2：`_Generic(x, struct T: 1, …)` 的标签选择器放行，裸类型参数仍硬错。新增 `test/ast/128_generic_type_operands` 并扩 126。**S5 收口**：`CTC_VERSION` 五处同步到 `0.26.2`，74 个 golden 仅版本 token 变化 |
| v0.26.3 | Phase 26 评审第三轮修复（2026-11-09，SH-64 / TEST-18） | 根因修复值位置的类型参数：`parse_primary` 的 `T_ID` 分支共同入口守卫，标识符等于当前模板类型参数即硬错 `type parameter 'T' cannot be used as a value`，覆盖 `return T;` / `h(T)` / `sizeof T * T` / `sizeof T + T` 及调用、限定名、宏兜底、`fnval_ok`（D26-15；全路径枚举见 phase26 §2.7）。同轮消防线假阳：`tparam_residue()` 只扫描实例函数体（`<name>__ctN`），不再把非模板函数里的 `int T = 5;` 当泄漏；新增 129 正例与 4 条值位置负例。`.h` / errors / module 构建产物 / 语料的覆盖盲区登记为 TEST-18。**S5 收口**：`CTC_VERSION` 五处同步到 `0.26.3`，74 个 golden 仅版本 token 变化 |
| v0.26.4 | Phase 26 补丁：工程可信度的四项收口（2026-11-09，TEST-18 / CI-8 / DOC-66；DOC-68 走扩展自己的版本线） | TEST-18：`tparam_residue()` 扩到 `build` 的每个 `.c` 产物，`.h` 产物断言不含任何实例定义，扫描器自带红/绿自检；类型参数名从夹具目录下**全部 `.ct`** 提取，修掉「泛型只声明在导入单元」的跨单元漏扫；新夹具 `test/ast/130_generic_build_mode` 与 `test/ast/131_generic_cross_unit`。CI-8：`AGENTS.md` 登记 `spec-version` / `spec-sha256`，`check-docs.py` 校验并在规范缺席时显式 skip，状态行在失败路径也打印。DOC-66：`docs/design/` 采用 12 阶段窗口并断言无重复归档。DOC-68 的编辑器泛型跳转不计入编译器版本，按 `ct-vscode` 扩展线发布 `0.5.1`。**S5 收口**：`CTC_VERSION` 五处同步到 `0.26.4`，74 个 golden 仅版本 token 变化；`check-ast.sh` 834 passed / 0 failed，`check-warnings` 253 ok |
| v0.30.0 | Phase 27–30 合并发布（2026-11-11，用户授权） | 四个相在实现期均未单独 bump（各自在 `v0.26.4` 上实现并收口）；为避免制造没有对应代码状态的空标签，跳过 `v0.28.0` / `v0.29.0`，一次性发布到 `v0.30.0`。`CTC_VERSION` 五处（`l0/ctc.c`、`l1/ctc.ct`、`l2/core.ct`、`l2/driver.ct`、`ct-ast/main.ct`）同步；`README.md` / `docs/README.md` / `AGENTS.md` 中英表 / 本表同步。本地孤儿 tag `v0.27.0`（指向被 reset 的分支线、远端从未存在）已删除，`v0.26.4` 行的 `v0.27.0` 空位不再补发。74 个 golden（`test/cases/**` 50 + `test/modules/**` 21 + `examples/tour/**` 3）由编译器重生成，仅版本 token 变化 |
| v0.33.0 | Phase 31–33 合并发布（2026-11-12，用户授权） | 三个相在实现期均未单独 bump（Phase 31 / 33 各自在 `v0.30.0` 上实现并收口，Phase 32 同期收口）；为避免制造没有对应代码状态的空标签，跳过 `v0.31.x` / `v0.32.x`，一次性发布到 `v0.33.0`。`CTC_VERSION` 五处（`l0/ctc.c`、`l1/ctc.ct`、`l2/core.ct`、`l2/driver.ct`、`ct-ast/main.ct`）同步；`README.md` / `docs/README.md` / 本表同步。74 个 golden（`test/cases/**` 50 + `test/modules/**` 21 + `examples/tour/**` 3）由编译器重生成，仅版本 token 变化。Phase 34 尚在实施中，不纳入本版本 |
| v0.34.0 | Phase 34 发布（2026-11-13） | Phase 34 在 `v0.33.0` 上实现并收口。`CTC_VERSION` 五处同步到 `0.34.0`；`README.md` / `docs/README.md` / `AGENTS.md` 中英表 / 本表同步。74 个 golden（`test/cases/**` 50 + `test/modules/**` 21 + `examples/tour/**` 3）仅版本 token 变化。Phase 35 尚未开工，不纳入本版本 |

| v0.35.0 | Phase 35 发布（2026-11-13） | Phase 35 在 `v0.34.0` 上实现并收口。`CTC_VERSION` 五处同步到 `0.35.0`；`README.md` / `docs/README.md` / `AGENTS.md` 中英表 / 本表同步。74 个 golden（`test/cases/**` 50 + `test/modules/**` 21 + `examples/tour/**` 3）仅版本 token 变化。`docs/design/phase35-draft.md` 转为完成记录，`phase23.md` 按 DOC-66 的 12 阶段窗口归档到 `history/design/`。Phase 36 尚未开工，不纳入本版本 |
| v0.36.0 | Phase 36 所有权与字符串（2026-11-13） | 泛型 `Drop`（`impl<T> Drop for Box<T>`）+ 带长度字符串 `Str`；`Option<T>` / `Result<T,E>` 加 `use Drop`；`CTC_VERSION` 五处同步到 `0.36.0`；golden 仅版本 token 变化；`check-ast` 1304/0、`check-warnings` 592/0。 |
| v0.37.0 | Phase 37 trait 签名硬错与运行期契约（2026-11-13） | `ct build` / `ct check` 对 impl 签名漂移硬错，`ct compile` 保持 warning；`ct build --runtime-checks` 空 vtable 守卫；L2 保持 warning（排除记录）；`CTC_VERSION` 五处同步到 `0.37.0`；71 个 golden 仅版本 token 变化；全量 11 道门禁绿。 |
| v0.38.0 | Phase 38 defer 块级清理（2026-11-13） | 块级 `defer`：LIFO、正常落出/return/break/continue、return 临时量、defer 先于 own；L38-1–L38-5；battle p38-1 B′ 稳定接收者检查；`CTC_VERSION` 五处同步到 `0.38.0`；71 个 golden 仅版本 token 变化；check-ast 1329/0、check-warnings 600/0、11 道门禁绿。 |
| v0.39.0 | Phase 39 C ABI 导出面与库制品（2026-11-13） | `ct build --lib`：根 `.h.ct` 的 C 兼容 `pub` 函数 → `<base>.abi.h` + `lib<base>.a`；L39-1/1w/2–6；泛型跳过；逐单元 `.o`、`ar rcsD`/`ZERO_AR_DATE`、`visibility`/`static`；纯 C 消费者可链接运行；`CTC_VERSION` 五处同步到 `0.39.0`；72 个 golden/expected 仅版本 token 变化；check-ast 1338/0、check-warnings 600/0、11 道门禁绿。 |
| v0.40.0 | Phase 40 errdefer 与显式错误出口（2026-11-13） | `errdefer` 条件回滚、`err:` 三种错误出口、尾随声明绑定；单栈 LIFO、defer/errdefer 先于 own；L40-1–L40-10；`CTC_VERSION` 五处同步到 `0.40.0`；72 个 golden/expected 仅版本 token 变化；check-ast 1348/0、check-warnings 605/0、test/run 153、docs 962 links / 217 files、11 道门禁绿。 |
| v0.40.1 | PH-40 评审修复（SH-68，2026-11-13） | 修尾随清理嵌套守卫/标志恢复、range `$` 与尾随别名冲突、`case` 后 return err 的 C99 合法性、`$` shadow、own shadow 误报、`.h.ct`/switch 尾随绕过；补 review 夹具/文档/grammar；check-ast 1350/0、check-warnings 607/0；PATCH fix，不新建 tag。 |
| v0.41.0 | Phase 41 原子并发能力（2026-11-13） | `atomic int/long/bool/void *` → `_Atomic(T)`；`ct_atomic_load/store/cas`（seq_cst）；12 个 static inline 运行头；C11 构建；L41 诊断；pthread 取消/引用计数；TSan nightly；tmLanguage/grammar；`CTC_VERSION` 五处同步到 `0.41.0`；72 个 golden/expected 仅版本 token 变化；check-ast 1357/0、check-warnings 614/0、test/run 154、docs 985/220、grammar 169/0；tag `v0.41.0`。 |
| v0.42.0 | Phase 42 impl 方法可见性（2026-11-14） | 方法级 `pub`（默认私有）；私有方法不进 `.h` + `static` + 跨单元 L42-4/5；52 条迁移；trait impl/`pub impl` 硬错；L42-1–7；check-ast 1361/0、check-warnings 614/0、test/run 154、docs 987/220、grammar 169/0；tag `v0.42.0`。 |
| v0.42.1 | CI 可移植性修复（2026-11-14） | `_POSIX_C_SOURCE` 暴露 `setenv`；空 label 后补 `;`；`-Wrestrict` 临时量；示例 32 的 `%p` 改为 null 判定；p41 指针初值 `(void *)0`；shim 宏去逗号告警；`stat -c/-f` 兼容；check-all 在 Ubuntu GCC/clang 与 Alpine musl 下绿。 |
| v0.43.0 | Phase 43 错误出口类型契约（2026-11-14） | `return err:` 载荷四入口硬检查；L43-1；普通 return 仍 opt-in；正/负例与 examples/45；check-ast 1364/0、test/run 155、warnings 616/0、docs 1035/224；tag `v0.43.0`。 |
| v0.44.0 | Phase 44 后缀 `?` 错误传播（2026-11-14） | 后缀 `?` + `N_TRY`；L44-1/2/3/4；`Outer::err` 失败返回；临时量 move+zero；errdefer/defer/own 清理；22 例消歧、9 例诊断、7 例 ASAN；check-ast 1370/0、test/run 156、warnings 620/0；tag `v0.44.0`。 |

版本号定义在 `ctc.c` 的 `CTC_VERSION`，并写入生成物注释；改动它必须重新生成全部 golden（见 [AGENTS.md](../../AGENTS.md) 第 5 节）。

**版本规则（2026-10-15 用户确认）**：

- 版本号形如 **`v0.<phase>.<patch>`**，**只在阶段边界 bump**；`patch` 位留给阶段内需要重生成 golden 的修复。与阶段**一一对应**：`0.<n>.x` = Phase *n* — `0.0.x` = Phase 0、`0.1.x` = Phase 1 自举、`0.2.x` = Phase 2 模块化、`0.3.x` = Phase 3 内存、`0.4.x` = Phase 4 诊断与溯源（v0.4.0）、`0.5.x` = Phase 5 新增特性（v0.5.0）、`0.6.x` = Phase 6 生态与扩展（v0.6.0）、`0.7.x` = Phase 7 工具链形态（v0.7.0）、`0.8.x` = Phase 8 包管理与分发（v0.8.0）、`0.9.x` = Phase 9 AST 版编译器（v0.9.0）、`0.10.x` = Phase 10 主线切换（v0.10.0）、`0.11.x` = Phase 11 `map` 构造、`0.12.x` = Phase 12 生态扩展（bindings / 方言深化）、`0.17.x` = Phase 17 工程质量与新能力（v0.17.0）、`0.18.x` = Phase 18 生态建设（v0.18.0）、`0.19.x` = Phase 19 受限语义检查（v0.19.0）、`0.20.x` = Phase 20 包支持（v0.20.0）、`0.21.x` = Phase 21 非逃逸栈闭包（v0.21.0）、`0.22.x` = Phase 22 `loop` 语法糖（v0.22.0）、`0.23.x` = Phase 23 `loop(a..b)` 范围（v0.23.0）、`0.24.x` = Phase 24 数组 range 初值（v0.24.0）、`0.25.x` = Phase 25 静态映射调用的闭包实参（v0.25.0）、`0.26.x` = Phase 26 泛型函数（v0.26.0 / v0.26.1 / v0.26.2 / v0.26.3 / v0.26.4 补丁）；**`0.30.x` = Phase 27–30 合并发布（v0.30.0）**——四相在 `v0.26.4` 上实现并收口，版本线一次性推进到 `0.30.0`，`0.28.x` / `0.29.x` 不单独发布；**`0.33.x` = Phase 31–33 合并发布（v0.33.0）**——三相同样在 `v0.30.0` 上实现并收口，`0.31.x` / `0.32.x` 不单独发布；**`0.34.x` = Phase 34（v0.34.0）**——Phase 34 在 `v0.33.0` 上实现并收口；**`0.35.x` = Phase 35（v0.35.0）**——Phase 35 在 `v0.34.0` 上实现并收口；`1.0.0` = 语言定稿。
- **tag 名必须与 `CTC_VERSION` 一致**：因此「不 bump 就不打 `v` 号 tag」，未 bump 的里程碑用非版本 tag（`phase1-m2` 标记 v0.1.0、`phase2-multifile-split` 标记 v0.2.0）。
- **口径 A（2026-10-16 用户确认，2026-10-17 已被取代）**：原定 Phase 1 / Phase 2 的版本号不在阶段边界 bump、与「单入口 `ct`」一并落地。**2026-10-17 用户改判**：按「版本 ↔ phase」规范在 Phase 4 完成时一次性 bump 到 **v0.4.0**（冻结期一次性例外），并重生成全量 golden；`v0.1.0`–`v0.3.0` 的里程碑不再单独补 tag（其阶段 tag 保留为非版本名）。Phase 5 完成时按同一规范 bump 到 **v0.5.0**（2026-10-17，同样经用户授权），Phase 6 完成时 bump 到 **v0.6.0**（2026-10-17，同样经用户授权），Phase 7 完成时 bump 到 **v0.7.0**（2026-10-17，同样经用户授权），Phase 8 完成时 bump 到 **v0.8.0**（2026-10-18，同样经用户授权），Phase 9 完成时 bump 到 **v0.9.0**（2026-10-18，同样经用户授权），Phase 10 完成时 bump 到 **v0.10.0**（2026-10-19，同样经用户授权），Phase 11 完成时 bump 到 **v0.11.0**（2026-10-19，同样经用户授权），其后的 **11.3 加固**按「阶段内需重生成 golden 的修复」用 patch 位 bump 到 **v0.11.1**；**Phase 12 完成时**按同一规范 bump 到 **v0.12.0**（2026-10-19，同样经用户授权）。全量 golden 均重生成。
- **bump 为什么必须谨慎**：`CTC_VERSION` 会进产物 banner，一次 bump 就要重生成 `test/cases/**` 与 `test/modules/**` 的 golden（v0.8.0 这一次是 107 个文件），并**同时**改 `ctc.c`、`selfhost/l1/ctc.ct`（L1）与 `selfhost/l2/{core,driver}.ct`——任一处不一致会让 `check-goldens.sh` 立刻全红。**归档 oracle 不能重生成**，故 `check-archive.sh` 用 `same_modulo_version` 在比较时归一化 banner 的版本 token（其余字节仍逐字节）。冻结期改 `CTC_VERSION` 属「不允许」项，每次均经用户显式授权。


## 已定的设计决策

#### 工具链形态：单入口 `ct`（已定；7.1–7.4 已落地，Phase 7 收口）

- **最终形态**：一个 `ct` 命令承载全部功能，靠子命令区分 —— `ct compile`（即现有的编译能力）、`ct build`、`ct get` / `ct install`（包管理，Phase 8 已落地）。
- **`ctc` 保留为兼容别名**：现有文档、脚本与习惯里的 `ctc …` 调用不失效。
- **实现方式**：按 `argv[0]` 分派（同一二进制，同 busybox 的做法），`ctc` 作为 `ct` 的软链或副本。
- **当前状态**：**7.1–7.3 已落地** —— L2 的 `main` 按 `argv[0]` 的 basename 识别身份，二进制名为 `ct` 时以 `ct` 运行（`-v` / usage 打印 `ct`），其余名字（`ctc` 别名、关卡里的 `ctc-l2`）保持 `ctc` 身份，故既有断言不动；生成物 banner 已改为 `Generated by ct v…`（切片 7.3，经用户授权的一次性解冻）；`ct get` / `ct install` 已由 Phase 8 的 `ct-pkg` 落地。

落地清单（越位实现期起执行；2026-10-17 更新）：

1. ✅ `main` 按 `argv[0]` 分派（`compile` 为默认子命令）——切片 **7.1** 已在 L2 落地；`ct compile` 与默认 `ct <file>` 均与 L0 输出逐字节一致，`selfhost/ct-tour.sh` 第 7 步钉住。
2. ✅ 安装形态：**不引入**构建系统或部署脚本；把 L2 二进制命名为 `ct`，用 `ln -s ct ctc` 提供别名——切片 **7.2** 已在 [README](../../README.md) 记明（含 L0 → L1 → L2 的完整自举链命令）。
3. ✅ 把生成物注释 `Generated by ctc …` 改为 `Generated by ct …`（含 `re-run ct` 与 map JSON 的 `compiler` 字段）——切片 **7.3** 已落地：**经用户显式授权一次性解冻 L0 与 L1**（冻结期例外，登记于 AGENTS §2），三层同步改名并重生成全部 golden。命令的**调用写法**（`ctc <file>` 等）仍保持兼容，未做全量替换。

#### 包管理的前置条件（比命名更重要）

- 真正的**前置是「多文件编译」**（Phase 1 已列）：类型定义下沉到 `.h`，生成的 `.c` 改为 `#include` 自己的头。这会打破 Phase 0 的「`.c` 自包含」约定，属破坏性变更。
- 包的**接口边界天然是 trait**：一个包 = 一组 `.ct` + 对外暴露的 `.h`（trait 声明）。这条决定了包管理器与 registry 能长成什么样。
- **设计冻结（2026-10-18）**：D21–D27 全部定案（清单 `ct.pkg` / git registry + 本地源 / MVS / `get` + `install` / 新 `PkgOps` trait / FNV-1a）。实现按 8.1（清单 + 本地源）→ 8.2（git 源）→ 8.3（`install` 校验）推进，见 [design/phase8.md](design/phase8.md) §11。
- **8.1 已落地（2026-10-18）**：`ct get <local-dir>[@<range>]` 解析 `ct.pkg`、递归处理本地 `dep`、复制到 `vendor/<name>/`、按拓扑序写 `ct.lock`。新增 `PkgOps` trait（`driver.ct`），零网络零子进程；`test/pkg/run.sh` 已接入 `check-all.sh` 第 7 关。
- **8.2 已落地（2026-10-18）**：`ct get` 增加 **git 源**——spec 以 `.` / `/` / `file://` 开头为本地目录（复制），其余为 git 源（`scheme://` 原样、`host/path` 补 `https://`、裸名按 `CT_REGISTRY`，默认 `https://github.com/ct-pkg`）。`git` 是**唯一**子进程调用点，且只由 `ct get` 触发；`git clone/fetch` 进 `~/.cache/ct-pkg/<name>/`，按 **MVS** 取满足范围的最低 tag（可带/不带 `v`；无 tag 且范围为空时回退默认分支 HEAD），`ct.lock` 记为 `name ver git <commit> <digest>`。无 `git` 时 git 源硬报错并提示安装，本地源照常可用（D26）。`test/pkg/run.sh` 扩到 14 项断言（含本地 git 仓库作 registry 的离线用例）。
- **8.3 已落地（2026-10-18）**：`ct.lock` 统一为五列 `name ver kind ref <digest>`（`digest` 为**逐文件加法折叠**的 FNV-1a，顺序无关、只做变更检测，与 `.ctcache` 键同源；见 D27）。`ct install` **离线**校验每个锁定包的 `vendor/<name>` 存在且摘要相符，并要求工程 `ct.pkg` 的每条 `dep` 都被锁覆盖且在范围内；全部通过即打印建议的 `ct build -I vendor/<name> … <unit>.ct -o build`（不调用 `cc`，与 `ct build` 的「只出 C」一致，D24）。摘要不符 / 缺包 / 未覆盖依赖 / 清单不完整 / 空锁均硬报错。`test/pkg/run.sh` 扩到 27 项断言（含 install/get 的错误分支负例），另证 `ct build` 可用 `vendor/` 编译（导入 vendored 包并运行）。`ct install` 零网络零子进程。
- **摘要加固（2026-11-01，SH-44）**：`ct.lock` 末列由 FNV-1a 加法折叠改为 **SHA-256**（按路径排序后把每个文件的 `相对路径\n` 与内容汇入单一流），写法为 `sha256:<64 hex>`；旧 16 位摘要显式报「unsupported digest」，不做静默降级。既有 `ct.lock` 因此失效、需重新 `ct get`；`test/pkg/run.sh` 同步夹具并新增「同尺寸篡改」与「旧格式」两个负例。D27 的这一处被取代。
- **Phase 8 收口（2026-10-18）**：8.1–8.3 全部落地后，四处 `CTC_VERSION`（`ctc.c` / `selfhost/l1/ctc.ct` / `selfhost/l2/{core,driver}.ct`）同步 bump 到 **v0.8.0**，`test/cases/**` 与 `test/modules/**` 共 **107 个 golden 重生成**（逐文件仅版本 token 一行变化，含 `map` 的 `compiler` 字段与 `expected.map`）。按 D24，`ct remove` / `ct update` / `ct publish` 仍属**设计上推迟**，不是本阶段欠账。已知风险见 [design/phase8.md](design/phase8.md) §9（`MAX_UNITS` 上限、license 与供应链口径、registry 组织名占位）。

#### 包管理器的命名（已定：`ct-pkg`）

**2026-10-17 用户定名 `ct-pkg`。** 它是包管理器 / registry 的品牌与分发名；日常入口仍是单入口 `ct` 的子命令（`ct get` / `ct install`），命令层不另立名字。

- **排除的候选**：`CT bun` 与 Bun（JavaScript runtime，且自身就是包管理器）撞名；`ctp` 在中文技术圈指上期技术 CTP 期货交易接口，且 crates.io 已有同名可执行 crate。
- **占位情况（2026-10-17 检索）**：`github.com/ct-pkg` 用户名可用（404）；npm 与 crates.io 未查到 `ct-pkg`。仍应尽早注册组织名与 registry 命名空间。
- **registry 与组织名要趁早占位**：`github.com/ct-lang`（2022 年注册）与 `github.com/ctlang`（2019 年注册）两个用户名均已被闲置账号占用（各 1 个仓库、0 关注），要做组织需另选名字。

#### Phase 9：AST 版编译器（设计已冻结；9.1 已落地，2026-10-18）

**主题已定（用户 2026-10-18 确认）**：把 2026-10-17 已定的 AST 主线正式立项为 Phase 9，设计见
[design/phase9.md](design/phase9.md)。**D28–D37 全部定案**：主题 = AST 编译器、9.1 取**最小端到端子集**、
代码落**新目录 `selfhost/ct-ast/**` 并与旧管线并行**、阶段出口为**自编 + 行为等价**、AST 节点用
**`typedef struct` + `kind` 判别**、符号表用**分类扁平表 + 变量作用域栈**、等价判据为
**退出码 + 产物零警告可编 + 程序输出一致**、新增 **`check-ast.sh`** 硬门禁、旧管线在 **9.7 全绿后归档**、
容量按**一代滞后**增长。

**9.1 已落地（2026-10-18）**：`selfhost/ct-ast/main.ct` 用单文件实现「词法 → 递归下降 → 按 `kind` 发射」，
支持 `int f(void)`、`return`、`printf` 调用、字符串/数字字面量与 `+ - * /`；产物仍写 banner 与
`<base>.h`（guard 规则与旧线一致）。新增 `test/ast/01_hello`、`02_expr` 两个行为用例与
`errors/missing_semi` 负例；`selfhost/check-ast.sh` 接入 `check-all.sh` **第 8 关**（D35），
D34 的判据（退出码 + 零警告可编 + 输出一致）在脚本里逐条断言。

**9.2 已落地（2026-10-18）**：AST 编译器补齐语句层与签名——局部声明 / 赋值 / `if`-`else` /
`while` / `for`、函数原型与 `int` 参数、`void` 返回与 `return;`、比较（`< > <= >= == !=`）、
`%`、一元 `-` / `!`、后缀 `++` / `--`。D33 的**函数表 + 变量表（作用域栈）**就位；未声明变量的
检查放在解析期（作用域在函数结束时回弹，不能再靠发射期查表）。发射端为所有函数统一补原型，
因此调用可以先于定义；条件单独走 `emit_cond`，避免 `if ((a == b))` 触发 clang 的
`-Wparentheses-equality`（D34 要求零警告）。新增 `test/ast/03_control`（原型 + 参数 + 三种控制流
+ 嵌套调用，输出 `22 9`）与 `04_void`（`void` 函数与 `return;`，输出 `7`）；`check-ast.sh` 现为
6 项断言全绿。`03_passthrough` / `04_signatures` 的**完整语料等价**仍留给 9.3（struct/指针/数组）
与 9.4（trait/impl）。

**9.3 已落地（2026-10-18）**：声明层到位——类型说明符（`int` / `void` / `char` / `unsigned long` /
`const`）、`struct` 定义与字段、`typedef`（含匿名 struct）、指针 `*` 与取址 `&`、成员访问 `.` / `->`、
数组与下标、`static` 函数与全局；D33 的**类型表**也补上（typedef 名参与类型解析）。方法按职责拆成
四个 trait（`AstOps` 8 / `SymOps` 8 / `ParseOps` 22 / `EmitOps` 8），全部低于 `MAX_METHOD 32`。
新增 `test/ast/05_struct`（`struct` + 指针参数 + `static` 全局字符串）、`06_arrays`、
`07_typedef`（匿名 struct + `typedef int`）、`08_static`；`check-ast.sh` 另把 **`03_passthrough`**
作为「无 main 语料单元」直接编译并 `cc -c` 通过（11 项断言全绿）。仍显式推迟：花括号初始化式、
强制转换、`sizeof`（`04_signatures` 需要它们与 trait，留到 9.4）。

**9.4a 已落地（2026-10-18）**：trait/impl 派发到位——`trait` 生成 `<T>_vtbl` / `<T>_iface`，
`struct ... use T` 追加 `__<trait>_vptr` 字段，`impl T for S` 生成 `static <S>_<T>_<m>` 方法与
`static struct <T>_vtbl <S>_<T>_vtable`；方法调用按接收者形态重写为
`recv.__x_vptr->m(&recv, …)`（值）或 `recv->__x_vptr->m(recv, …)`（指针），`self->other()` 走同一路径；
声明处自动写 vptr，花括号初始化式（`{ .name = "Tom", … }`）在收尾 `}` 前追加 vptr 项。
接收者形态与 trait 解析在**解析期**完成（局部变量在发射期已出作用域）。新增 `test/ast/09_methods`
（值/指针/`self` 兄弟调用）；`check-ast.sh` 现把 **`01_trait_basic`** 按完整行为（编、跑、输出比对）
纳入语料断言，共 **13 项全绿**。

**9.4b 已落地（2026-10-18）**：接口值与接口数组——trait 名作类型时发射 `struct <T>_iface`；
声明 / 赋值 / 实参 / `return` 处按静态类型装箱（值取地址、指针直接转 `void *`，已是同款接口则原样传递）；
`g.m()` → `g.vt->m(g.self)`，接口数组元素同样走这条路径；空 `{}` 初始化式不再产生悬空逗号。
`18_polymorphism` 与 `21_empty_init_iface` 已按完整行为纳入 `check-ast.sh`，新增
`test/ast/10_iface_array`（16 项断言全绿）。**9.5 起继续按切片推进**，且**不得**把单文件形态当成
最终布局（D30 的目标仍是 `selfhost/ct-ast/**` 多单元）。

**9.5a 已落地（2026-10-18）**：模块层——`ct-ast build <inputs...> -o <dir> [-I <dir>] [--ns-root <dir>]`
按单元产出 `.c` + `.h`，导入闭包按深度优先解析后逐单元发射；`import a::b;` 映射
`<root>/a/b.ct` 或 `a/b.h.ct`（导入方目录优先，其次 `-I` 顺序）；`pub` 只把 trait / struct /
typedef / 函数原型放进 `.h`，其余声明留在 `.c`；`namespace A::B { … }` 把类型名压成 `A_B_`
（函数名不变，符合已发布规则），`--ns-root` 按 D13-A 校验「声明 namespace = 目录路径」，不匹配即报错。
新增 `ModuleOps`（路径 / import / 单元加载 / namespace 校验 / 顶层分派），`ParseOps` 保持 30 个方法；
发射端新增 vtable 预声明（tentative definition），使「全局对象在 impl 之前引用 vtable」也能编译。
`check-ast.sh` 新增模块层：`test/modules` 的 **split / ns_dir / inc / hdr** 走 `build` 后链接运行并比对
`expected.out`，`ns_dir_mismatch` 与 `inc_missing` 必须非零退出（22 项断言全绿）。**9.5b**（`#line` 与
`--emit-map`）留作下一片。

**9.5b 已落地（2026-10-18）**：元数据层——词法器与节点携带源码行号（`Node.line`、`Trait` / `Fn` 的
`line`），解析期同时记录函数调用图；`#line 1 "<输入>"` 在 compile 模式由 `--line` 开启、在 build
模式默认开启，`--no-line` 关闭；`--emit-map <file|->` 输出与旧管线同形的 JSON
（compiler / file / traits / structs / functions / impls / calls）。新增 `test/ast/11_map`
（trait + struct + impl + 两处函数 + 一次调用），`check-ast.sh` 增加元数据层（map stdout、compile
默认无 `#line`、`--line`、build 默认 `#line`、`--no-line`、缺参数与不可写路径两条负例），共
**30 项断言全绿**。下一片是 **9.6 自编**。

**9.6 已落地（2026-10-18）**：**自编 + 不动点**。`ct-ast` 编译自己的源码（`selfhost/ct-ast/main.ct`，约 3.9k 行）→ `self1.c` 用 `cc -Wall -Wextra -std=c99` **零警告**编出 `ct-ast2` → `ct-ast2` 再编译同一份源码 → 与 `self1.c` **逐字节一致**。门禁 `check-ast.sh` 新增「self-hosting (9.6)」一节（**31 项断言全绿**），`check-all.sh` 仍 **8 关全绿**。

为此补齐的语言面全部只落在**新编译器自己**身上（D37 一代滞后，旧线未动）：宏常量做数组长度（含多维 `[MAX_PARAMS][MAX_TEXT]`）、表达式里的 `ALL_CAPS` 宏与 `stderr`/`stdout`/`stdin` 直通、`sizeof`（含 `sizeof(type)`）、强制转换（用**单 token 前瞻**区分「括号内类型名」与「括号表达式」，因此 postfix 绑定不受影响）、`&&`/`||`（`&&` 紧于 `||`）、三元 `?:`、复合赋值 `+= -= *= /= %=`、`break`/`continue`、多声明符（`int a, b;`，含 `const char *p, *q;` 的星号重算）、字符字面量与十六进制字面量、相邻字符串字面量（进独立的 256KB 字符串池，不受 `MAX_TEXT` 限制）、`FILE` / `size_t` 类型词、带 tag 的 `typedef struct Tag`（**保留 tag**，并把 tag 的 `use` 列表复制给别名，否则 vptr 字段丢失）。容量按 D37 上调：`MAX_NODES` 4096→**32768**、`MAX_METHODS` 16→**32**。

> **给自编源码的一条纪律**：旧管线是逐行重写，块注释的**续行**会被当普通代码处理（language-spec §6.2）。因此 `main.ct` 的跨行注释不得让续行以「类型名 + 标识符」开头——本轮就有一行 `ParseOps stays put.` 被误判为接口类型声明。

**9.7 已落地（2026-10-18）**：**全量行为等价 + 切主线**。以 `test/cases/**` + `examples/**` 为语料逐族修复，四族已过：

1. **数组与堆对象**：元素 vptr 用循环写、堆对象在 `malloc` 后写、`delete p;` 解析。
2. **字段链接收者**：`StructDef` 记字段类型，`a.b.c.m()` 与 `self->x.m()` 都能解析到 trait。
3. **右值接收者**：`f().m()` / `f()->m()` / `f().a.m()` 在语句头或初始化式处提升为 `__ct_tmpN`（`hoist_rvalue` / `hoist_scan` / `emit_hoists`）；扫描只看表达式子树（切断 `next`）且以 `Node.text3` 记临时名，`N_CALL` 发射时改印临时名。
4. **接口字段与 impl 内 `self`**：文件头统一前置声明所有 struct tag（`emit_struct_fwd`，否则 vtable 参数里的 `struct S *` 会落进原型作用域）；接口值字段的语句赋值按目标字段类型装箱（`N_MEMBER` / `N_ARROW`）；接口指针接收者走 `->vt->m(x->self)`（`aux == 4`）。

`check-ast.sh` 新增 **corpus equivalence** 一节：`test/cases/*.ct` 与 `examples/*/*.ct` 全部走「ct-ast 编译 → `cc -Wall -Wextra` → 运行 → 比对 `expected.out`」；无 `expected.out` 的用例按**仅编译**判定（`03_passthrough` / `04_signatures` 没有 `main`），方言示例先由 `ct-dialects/` 插件展开（编译器对 DSL 零感知）。门禁 **60 项断言全绿**（含自编不动点），`check-all.sh` 8 关全绿。

**旧管线按 D36 冻结归档**：`selfhost/ct-ast/main.ct` 成为唯一开发主线；`selfhost/l2/**` 只修 bug、不加能力，归档点 tag `pre-ast-mainline`，旧关卡继续把它当回归 oracle 跑。**v0.9.0 版本收口已获用户授权并执行**：五处 `CTC_VERSION`（`ctc.c` / L1 / `l2/{core,driver}.ct` / `ast/main.ct`）同步，103 个 golden 重生成（仅版本 token 变化）。

#### 许可（已定并已落地）

- **编译器本体** GPL-3.0-or-later（`LICENSE`）；**`.ct` 源码与生成物不受 GPL 约束**（`LICENSE.EXCEPTION`，照 GNU Bison 先例，且随产物走）；**`examples/` 与 `test/` 为 MIT**。
- 例外不是可选项：ctc 会往产物里插入样板（vtable 结构体、vptr 字段、`_self` 强转行），"编译器输出是否构成衍生作品"存在歧义——不写例外，使用者（尤其公司法务）无法判断，等于挡住采用。

#### namespace 与路径访问规则（已定，越位实现落地）

CT 采用混合路径访问方式：**前面用 `::` 走命名空间路径，最后一步用 `.` 调用方法或访问字段**。最后一步一定是 `.`。

```c
// 正确
HAL::UART::huart1.send(data, len);
HAL::GPIO::pinA5.set(1);

// 静态函数用 ::
HAL::UART::get_default_config();

// 错误
HAL::UART::huart1::send(...);   // 最后一步不能用 ::
HAL.UART.huart1.send(...);      // 中间不能用 .
```

| 场景 | 符号 | 示例 |
| --- | --- | --- |
| 命名空间路径导航 | `::` | `HAL::UART` |
| 方法调用 / 字段访问 | `.` | `huart1.send(...)` |
| 静态函数调用 | `::` | `HAL::UART::init()` |
| trait 方法引用 | `.` | `obj.method()` |

此规则落地时写入 [language-spec](../language-spec.md)，编译器强制检查。

#### import 与模块系统（已定，越位实现落地）

`import` 不是 `#include` 的语法糖，而是**编译单元声明**。编译器通过 `import` 建立模块依赖图，自动处理符号引用、编译顺序和链接：

```c
import HAL::UART;      // 告诉编译器：HAL::UART 的符号在 hal/uart/ 下
import Driver::Sensor; // 告诉编译器：Driver::Sensor 的符号在 driver/sensor/ 下
```

编译器内部行为：

1. 扫描所有 `.ct` 文件，建立 module 表（namespace → 源文件路径）
2. 解析 `import` 关系，构建依赖 DAG
3. 拓扑排序，按依赖顺序编译
4. 每个 `.ct` → `.c` + `.h`
5. 链接所有 `.o`

Phase 0 不做 import（单文件），Phase 1 实现。

#### 文件命名约定与 `pub` 可见性（已定，越位实现落地）

文件名决定编译器的生成行为，无需额外关键字或配置文件：

| 文件名 | 生成行为 |
| --- | --- |
| `foo.ct` | 只生成 `foo.c`（实现文件，不对外暴露接口），文件内符号默认只在当前编译单元可见 |
| `foo.h.ct` | 生成 `foo.h` + `foo.c`（接口 + 实现分离） |

> **落地说明**：`foo.h.ct` 这一半自 Phase 2 起生效（基名去掉 `.h.ct`，产出 `foo.c` + `foo.h`，
> `import foo;` 回退命中 `foo.h.ct`）。`foo.ct`「只产出 `foo.c`」这一半在 **2026-10-31 落到 ct-ast
> （安装入口）**：普通 `.ct` 单元不再写 `.h`，并且**不能被 `import`**——`import` 只解析 `.h.ct`，
> 命中普通 `.ct` 时报 `only a .h.ct unit can be imported: rename 'x.ct' to 'x.h.ct'`；编译模式
> （`ct compile foo.ct`）同样只写 `.c`。被导入的单元因此必须改名 `.h.ct`（`test/modules/**`、
> `bindings/**` 与 `selfhost/ct-ast/**` 已按此迁移）。L2 是冻结的回归 oracle，仍按**附加式**
> 行为对所有单元产出 `.h`（`test/archive/**` 的逐字节比对依赖它），所以这条规则是 **ct-ast 与
> L2 的已知分叉**，登记在 language-spec 顶部的「有意拒绝」表。

编译器从 `pub` 关键字识别需要暴露的符号，自动生成 `.h`（含 `#ifndef` 守卫、struct 定义、函数声明、vtable 类型）和 `.c`（含实现）：

```c
// uart.h.ct
namespace HAL::UART {
    pub trait Controller {
        void send(uint8_t *data, int len);
        int recv(uint8_t *buf, int len);
    }

    pub struct UartDevice {
        int baud;
        int fd;
    }

    pub UartDevice init(int baud);
    pub void deinit(UartDevice *d);
}
```

可见性修饰符：

| 修饰符 | 作用 |
| --- | --- |
| `pub` | 对外暴露（进 `.h`） |
| `static` | 文件级私有（不进 `.h`，不进符号表） |
| `pub readonly` | 外部可读不可写（生成 `const` 或 getter） |

可见性规则作用于 namespace 内的声明、struct 字段、trait 方法，由编译器强制约束，违反直接报错。封装由编译器强制执行，不存在「忘了在 `.h` 里声明但 `.c` 里实现了」的不一致问题。

#### 内存管理：Drop 与 delete（已定，越位实现落地）

编译器内置 `Drop` trait。struct 声明 `use Drop` 后，编译器自动生成释放逻辑：

```c
struct MyDevice {
    uint8_t *buf;
    Filter *filter;
} use Drop;
```

自动生成规则：

- 对每个字段，如果其类型也 `use Drop` → 递归调用 `drop()`
- 基本类型（int / char / float / 裸指针）→ 不处理
- 如果 struct 本身是堆分配的 → `free(self)`
- 用户可以用 `impl Drop for MyDevice { void drop() { ... } }` 自定义释放逻辑
- **未调用不生成代码**：整个项目从未调用过某类型的 `drop()`，则不生成任何 drop 相关函数体，零开销

`delete` 是释放对象的统一入口。Phase 1 是在**已落地的最小版**（0.1.8：`delete p;` → `if (p) free(p);`，
只对已登记的 ct-struct 指针生效）之上**扩展**出 `drop()` 调用，**不是重复规划**：

```c
MyDevice *d = MyDevice::create();
// ... 使用 ...
delete d;    // 展开为：if (d) { d->drop(); free(d); }
```

| 场景 | 展开行为 |
| --- | --- |
| 堆对象（指针）+ `use Drop` | `T_drop(ptr); free(ptr);` |
| 堆对象 + 无 Drop | `free(ptr);` |
| 栈对象 | 编译错误（或只调 `drop()`，不 `free`） |
| 空指针 | `if (ptr)` 保护，安全无操作 |
| 基本类型指针 | 等价于 `free(ptr)` |

数组释放用 `delete[]`：对每个元素调 `drop()`，然后 `free`。

**编译期泄漏警告（Phase 1 简单版）**：函数末尾检查局部变量的分配/释放状态——分配了但没 `delete`、没 `return`、没存全局 → 警告。路径敏感版**已由 Phase 5 切片 5.3 实现**（条件 `return` 检查，无需 AST）。警告同时输出人可读列表与 JSON（供 VS Code 插件消费）：

```json
{
  "warnings": [{
    "type": "potential_leak",
    "file": "src/main.ct",
    "line": 23,
    "variable": "sensor",
    "type_name": "BME280*",
    "message": "allocated but never deleted"
  }]
}
```

抑制方式：`#[allow(leak)]` 标注有意不释放的分配（如全局存活对象）。

#### map 语法与反向映射表（已定，Phase 6 落地）

`map` 关键字将 trait 方法映射到具体实例的 SDK 调用：

```c
map trait Controller for instance huart1 {
    send(data, len) → HAL_UART_Transmit(&huart1, data, len, HAL_MAX_DELAY);
    recv(buf, len) → HAL_UART_Receive(&huart1, buf, len, HAL_MAX_DELAY);
}
```

编译器生成对应的 vtable 条目，使 `huart1` 可以作为 `Controller` trait 的实例使用。

编译器同时维护**反向映射表**（生成代码中的 C 符号 ← CT 中的哪个 trait/方法），用于：错误信息中给出有意义的回溯、VS Code 插件「跳转到定义」、反编译时恢复 CT 语义。

> **排期（D8，用户 2026-10-14 拍板）**：自越位实现中移出，排在 Phase 6 最后实现。理由：
> `map` 属生态绑定方向而非自举主线的主题，出口标准与自举前置清单均不依赖它；其真实消费者
> （官方 bindings）尚不存在，过早冻结实例语义会凭想象用例定死设计。落地时与官方 bindings 清单一并定案。
> **更新（2026-10-19）**：D8 的「移出」口径已由 **Phase 11** 解除——`map` 重新立为阶段，11.1–11.3 已在
> **ct-ast** 主线落地（解析 + 发射 + `maps` JSON + 派发接线 + 加固），收口 bump v0.11.0、patch bump v0.11.1；实例语义见 [language-spec](../language-spec.md) §4.10。

#### JSON 诊断输出与插件薄客户端（已定，越位实现落地）

`ctc` 输出 JSON 格式：编译错误/警告（含泄漏警告）、符号表（namespace / trait / struct / 函数位置）、调用关系图。VS Code 插件作为薄客户端消费 JSON，实现内联错误提示、跳转到定义、自动补全、悬停类型信息；插件本身不做编译、不做分析，编译器升级时插件无需改动。

> **首版（Phase 1.7，用户 2026-10-13 拍板 Q1=A）**：`--diagnostics=json` **只输出诊断列表**（`{"warnings":[…]}`），
> 符号表与调用图**尚未实现**，另开子项。`--diagnostics=text`（默认）为人可读 stderr。

#### 自举策略与单文件边界（已定；`ctc.c` 自举启动即冻结，源码与三代 CT 编译器同处 `selfhost/`）

- **渐进自举**：L0（C 写的最简 trait 编译器，即今天的 `selfhost/l0/ctc.c`）→ L1（CT trait-only 子集写的基础编译器）→ L2（全特性 CT 写的完整编译器）。
- **Phase 0 边界**：`ctc.c` 保持单文件；「留在仓库根目录」的旧口径（2026-10-11）已于 2026-10-20 修订为 `selfhost/l0/ctc.c`（见下「冻结与位置」）。
- **最小可自举版（2026-10-14 用户确认）**：优先用**单文件**（不用 namespace / `import` / 多文件）达成自举，
  以绕开前置条件 #1「跨单元引用带 trait 的对象」（vtable 变量为 `static`、`.h` 只放类型，跨翻译单元
  既写不了 vptr 也无法派发）。单文件路径的唯一硬阻塞是「`impl` 方法体内无法跨对象派发」，已由
  **Phase 1.9c** 解决（方法体走与顶层完全相同的重写管线：登记 `self` / 方法参数后逐行 `transform_line`）。
  结论：**单文件 + 完全 OO 已可自举**——namespace、多文件、诊断等非 OO 特性**不作为自举前提**，一律改用 CT 实现；C 侧的越位实现**先剥除归档（Phase 0.3）**，再由 Phase 2–5 用 CT 重做。
- **冻结与位置（2026-10-20 修订）**：**Phase 0.3 剥离完成后（即自举启动时）** `ctc.c` 即冻结为 **L0 + 差分 oracle**（只修 bug，不加特性）。位置：2026-10-11 曾定「留仓库根目录」、2026-10-15 又定「等 CT 侧布局定型再一次性搬入 `ctrait/`」；**两版口径均已于 2026-10-20 作废**——最终决定是把 `ctc.c` 直接移入 **`selfhost/l0/ctc.c`**，与三代 CT 编译器（`l1/ctc.ct` / `l2/` / `ct-ast/`）同处，取消从未落地的 `ctrait/` 草案；二进制仍构建到仓库根 `./ctc`，故所有 `./ctc` 引用不变。理由：自举链已在 `selfhost/**` 运行，四代编译器同处一处更自洽，也免去一次性搬迁隐含的 `test/` 拆分前置。新特性一律在 CT 侧实现（见 [design/bootstrap.md](design/bootstrap.md)）。
- **清理口径（2026-10-14 修订为「剥离在前」）**：**先**把越位落在 C 里的 namespace / 多文件 / import / Drop / `#line` / 诊断从 `ctc.c` **移出并归档为 oracle**（Phase 0.3），使 L0 成为**纯 OO 核心**（+底层设施）；**再**自举（Phase 1）；**最后**由 Phase 2 用 CT 逐项重做并向归档对差。两条硬前提：① **移出件不销毁**——归档件既是种子（唯一能生产 L1 的那个行为基准）也是差分 oracle（唯一能产出 byte-identical golden 的对照实现）；② **`ctc.c` 永不整体删除**，作为种子与差分 oracle 长期保留（先例：Rust 长期保留 stage0，Go 1.5 起弃用 stage0，两者皆可）。
- **阶梯约束（源语言滞后一级）**：第 n 级编译器只能编译「第 n−1 级所支持的语法子集」写成的源码。因此 L1 源码只能用**单文件 + OO 子集**；CT 侧要**使用** namespace / Drop / import 组织编译器源码，必须先有支持它们的 CT 级编译器。**"重写完就删 C"顺序错**，必须逐级爬升。
- **单仓库**：跨层编译与特性耦合决定了不拆仓库；`selfhost/` 需要独立分发时用 `git subtree` / `git filter-repo` 无损拆分。

目标目录结构、分层规则、构建流程与里程碑（M1–M6）见 [design/bootstrap.md](design/bootstrap.md)（自举链已落地于 `selfhost/**`，含 L0 种子 `selfhost/l0/ctc.c`；早期 `ctrait/` 草案已废弃）。

#### 自举前置条件（清单）

L1 / L2 要用 CT 写编译器，下列能力必须先成立（**2026-10-11 逐条实测**；除注明外均为当前缺口）：

| # | 前置条件 | 为什么自举需要 | 落地 | 状态 |
| --- | --- | --- | --- | --- |
| 1 | **多文件编译 + namespace**（`.h.ct` / `import` / `pub`） | 否则全部代码挤在单文件，没有模块边界 | 越位实现 → 自举期回归 CT | ⚠️ namespace + 多文件（`ct build`）+ `pub` + `import` + `.h.ct` 命名 + `-I` 搜索根已实现；跨单元引用带 trait 的对象尚不可。单文件自举路径**不需要**此项（见上方「最小可自举版」） |
| 2 | **堆对象的语言级创建** | AST / 符号表需动态分配；当前只能手写 `q->__<trait>_vptr = &…;`（可用，但漏写即运行期崩） | C 侧（自举前置；与 Drop 一起定） | ✅ `T *p = malloc(...)`（含 `calloc`）已在声明后自动写 vptr（含嵌套值字段，D1=A）；`use Drop` + `delete` 递归释放已实现 |
| 3 | **文件作用域的对象数组** | 全局符号表；实测 `Person ps[2];` 在文件作用域直接 `die` | C 侧（自举前置；"对象住哪儿"设计） | ✅ Phase 1.6：文件作用域对象 / 数组的 vptr 由生成的构造器 `__ct_init`（`__attribute__((constructor))`，D5=A）在 `main` 前写入；`static` 前缀的同款声明也已识别（`static Person g;` / `static Person gs[2];`，Phase 1） |
| 4 | **`delete` 覆盖 `char *`** | 字符串 / 缓冲区；实测 `delete buf;`（`char *buf`）原样透传 → 编译错，只能改用 `free()` | 越位实现 → 自举期回归 CT | ✅ `delete p;` 已对任意指针生效（`char *` → `if (p) free(p);`） |
| 5 | **`#line` 指令** | 生成的 C 报错行号要映回 `.ct`，否则自举产物无法调试 | 越位实现 → 自举期回归 CT | ✅ 多文件模式**默认**在 `.c` 发出 `#line`（D4=A），单文件默认关；gcc/clang 报错映回 `.ct` 行 |
| 6 | **方法调用的接收者可以是更一般的表达式** | 变量 / 表达式下标、指针数组元素、指针字段链（`ps[i].m()`、`ptrs[i]->m()`、`b.who->m()`）由 Phase 1.9a 支持；rvalue 接收者 `f().m()` / `mk()->m()`（含字段跳 `f().a.b.m()`）由 Phase 1.9b 支持 | C 侧（自举前置，1.9） | ✅ 1.9a + 1.9b 均落地（Q1=A 值/指针返回、Q2=A 仅语句行首或初始化式 RHS 提升、Q3=A 其它位置 `die`） |
| 7 | 位置式初始化 / 方法体内互调 | — | 已完成（0.1.1 / 0.1.4 / 1.9c） | ✅ 方法体自 **Phase 1.9c** 起走与顶层相同的重写管线：方法体内的局部变量接收者、字段链递归与参数接收者均正常派发 |

**AST 的形状**：ct **无继承**，AST 只能用 `trait Node { … }` + 各 `struct impl`，靠**接口值**（Phase 0.2）
承载——这让自举同时成为 Phase 0.2 的压力测试。注意**声明顺序**：`struct Binary { Node *lhs; }` 要求
`trait Node` 先声明；两个 struct **以值互相引用**会失败（经接口指针引用则不受影响）。

第 6 项是一类问题（"接收者既不是已登记的标识符、也不是常量下标 / 值字段链"），可单独推进；其余 1–5 项
与**越位实现期**高度重叠——**自举的前置条件基本等于越位实现期的产出**。

> **2026-10-14 修订（配合 Phase 0.3）**：按「纯 OO 单文件」口径，前置 **#1（多文件 + namespace）与 #5（`#line`）退役**（随 Phase 0.3 一并移出，单文件路径本就不需要）；**#2（堆创建）、#3（文件作用域对象/数组）、#4（`delete` 覆盖 `char *`）、#6（一般接收者）、#7（方法体同一管线）保留**并归入 Phase 0 核心（2026-10-14 逐条确认「留」）。退役后自举**不再有硬阻塞**（原 #1 附带的「跨单元带 trait 对象」随之消失）。


## Phase 0–12 详细记录

### Phase 0：用 trait 写「完整 OO」

**出口标准（2026-10-11 用户确认，重新定义）**：Phase 0 是否完成，不按"结构转换跑通"判断，而按
**能否借助 trait 写出一段完整的面向对象程序**判断。ct 的 OO 语义是 **trait 接口 + 组合，不含继承**。

「完整 OO」在 ct 里 = 下列能力全部成立：

| # | 能力 | 状态 |
| --- | --- | --- |
| 1 | **封装**：`struct` 字段 + `impl` 方法；方法体内访问 `self->field` | ✅ |
| 2 | **接口**：`trait` 声明 + 每个 `struct` 各自 `impl … for` | ✅ |
| 3 | **派发**：值/指针接收者的 `.m()` / `->m()`，以及方法体内兄弟调用 `self->m()` | ✅（0.1.4 收尾） |
| 4 | **传递**：对象作为函数/方法的**参数与返回值**（签名里的 struct 类型） | ✅ 见 0.1.5 |
| 5 | **组合**：struct 字段为另一 struct 类型；字段链式调用 `a.b.m()` | ✅ 见 0.1.6 |
| 6 | **存储**：数组元素上的方法调用与元素 vptr 初始化 | ✅ 见 0.1.7 |
| 7 | **创建与释放**：**创建 = 栈上的 struct 声明**（指定 / 位置式 / 无初始化式 / 嵌套 / 数组，均写 vptr）✅；**释放 = `delete q;`** → `if (q) free(q);` ✅；**堆对象无语言级创建入口**，推迟到 Phase 1（与 Drop 一起定；当前需手写 vptr） | ✅ 见 0.1.8 |
| 8 | **作用域**（正确性前提）：变量/参数按块作用域回滚，不跨函数串味 | ✅ 见 0.1.9 |
| 9 | **接口多态**：能声明 trait 类型的变量/参数，运行时派发到不同 `struct` | ✅ 见 Phase 0.2 |

第 4–8 项属**实现覆盖缺口**（沿用 [AGENTS.md](../../AGENTS.md) §4「不允许静默产出编不过的 C」的口径，按缺陷修）；
第 9 项属**语言特性**（需要新的类型表示与语法），**必须先设计后实现**，不能当缺陷补。

既有验收（仍适用：零警告构建 + golden + 回归套件）：

```bash
gcc -Wall -Wextra -std=c99 selfhost/l0/ctc.c -o ctc                    # 零警告
./ctc examples/01_greeter/greeter.ct -o /tmp/greeter.c             # 无报错，同时生成 /tmp/greeter.h
gcc -Wall -Wextra /tmp/greeter.c -o /tmp/greeter && /tmp/greeter
# Hello, I'm Tom, age 36
# Hello Jerry, I'm Tom
```

（Phase 0 期间这批命令用的是仓库根目录的 `example.ct`；后续示例收进 `examples/`，生成物不再入库。）

明确的非目标（仍不在 Phase 0 内）：类型检查、优化、错误恢复、namespace、泛型、多文件、嵌套定义、继承。

### Phase 0.1：缺陷修复与回归测试（建议优先）

#### 0.1.1 修复指针声明缺陷 ✅ 已完成

- **问题**：`Person *p = &a;` 曾生成成 `struct *p = &a;`（丢失类型名），产出非法 C。
- **修复**：`try_var_decl()` 的 `*p == '*'` 分支补回类型名，现生成 `struct Person *p = &a;`。
  指针变量当时**不登记**进变量表（此为临时状态）；`p->m()` 的重写已在 0.1.4 补齐。
- **验收**：`Person *p = &a;` 生成 `struct Person *p = &a;` 且编译通过；该用例纳入 0.1.3 的回归集。

#### 0.1.2 支持位置式初始化 ✅ 已完成

- **问题**：`Person p = { "Tom", 36 };` 不追加 vptr，运行时调用方法解引用空指针。
- **修复**：去掉「必须全为指定初始化」的限制（移除 `is_designated_list()`），只要 struct 有
  `use`，无论指定初始化、位置式还是空列表，都在 `}` 前追加 `.__x_vptr = &…_vtable`。
  已验证 C99/C11 允许 `{ 1, .v = 0 }` 这种混用（gcc 无警告）。
- **验收**：`test/cases/07_positional_init.ct` 位置式初始化可正确运行。

#### 0.1.3 建立回归测试 ✅ 已完成

- **结构**（已落地）：

  ```
  test/
  ├── run.sh                 驱动器：构建 → 单测 → golden → 负例；退出码 0 = 通过
  ├── unit/test_helpers.c    白盒单测：include ctc.c 直接调 static 纯函数，40 项断言
  ├── cases/                 golden 正例：<name>.ct + <name>.expected.c / .h / .out
  └── errors/                负例：<name>.ct + <name>.expected-err（期望的诊断子串）
  ```

- **断言**：① 构建层——`ctc` 自身零警告；② 单测层——`trim` / `param_type_only` /
  `parse_params` / `split_decl` / `decl_end_is_bare` / `put_vptr_designators` / `word_at` /
  `match_delim` 等纯函数行为；
  ③ golden 层——`ctc` 退出 0、生成物与 `.expected.c`/`.expected.h` 逐字节一致、生成物能编译、
  含 `main` 的用例 stdout 与 `.expected.out` 一致；④ 负例层——必须非 0 退出，且诊断带
  `文件:行:列: error:` 前缀并包含期望文案。
- **覆盖清单（已实现）**：单 trait、多 trait + `use` 换行 + 嵌套调用、无 trait struct 与透传
  （`#define` / 字符串 / 中英文字面量与转义 / 行注释 / 块注释内不重写）、签名形态
  （`void f(void)`、多词类型、空 struct、嵌套花括号）、变量声明（指定初始化、`struct` 限定形式、
  指针声明）、跨 trait 方法名冲突（取 `use` 顺序第一个）、位置式初始化、方法体内互调、
  指针接收者、无初始化式声明；负例覆盖未定义 trait / 未定义 struct /
  未声明方法 / 未实现方法 / struct 未 use 该 trait / 括号不配对。
- **未纳入**：`MAX_*` 容量上限的越界行为（依赖容量策略决策）。
- **验收**：`./test/run.sh` 全绿（当前 20 项：1 构建 + 1 单测 + 10 正例 + 2 示例 + 6 负例）。
  额外增加 examples 层，直接校验 `examples/**` 的端到端可运行性（生成 → 构建 → 运行 → 比对
  `.expected.out`），因此示例不会随编译器演进悄悄失效。
  已验证其有效性：在临时副本中注入「改坏 golden / 改错期望诊断 / 断言失败」三处错误，
  三层都能报告失败并以退出码 1 结束。

#### 0.1.4 补齐 vptr 覆盖：指针接收者 / 方法体内互调 / 无初始化声明 ✅ 已完成

- **问题**（同一类：静默产出编不过或空 vptr 的 C，违反 [AGENTS.md](../../AGENTS.md) §4）：
  1. `impl` 方法体内的 `self->other()` 只被改写成 `_self->other()`，产出非法 C；
  2. 指针变量不登记，`p->m()` 不被重写，产出非法 C；
  3. 无初始化式声明 `Person p;` 不写 vptr，调用方法解引用未初始化指针。
- **修复**：
  1. `Var` 增加 `ptr` 标记；`try_var_decl()` 登记指针变量；`transform_calls()` 增加 `->` 分支
     （传指针本身，**不补 `&`**），且不对指针变量误用 `.` 规则；
  2. 方法体内的 `self->m(...)` 在 `replace_self()` 内一并重写为
     `_self->__<trait>_vptr->m(_self, …)`；检测到此类调用时，在方法函数前补一行 vtable
     前向声明（C tentative definition）；
  3. 无初始化式声明改写为 `struct Person p = { .__<trait>_vptr = &…_vtable };`。
- **用例**：`test/cases/08_self_call.ct` / `09_pointer_receiver.ct` / `10_uninit_decl.ct`
  （均含 `main`，走运行型断言）。
- **验收**：四条最小复现都能编译并正确运行；`./test/run.sh` 全绿。

#### 0.1.5 函数/方法签名里的 struct 类型 ✅ 已完成

- **问题**：普通函数的返回类型与参数类型里的裸 struct 名不做 `struct ` 限定，静默产出编不过的 C；
  参数不登记，参数上的 `.m()` / `->m()` 不重写。实测失败形态：`static Point make(...)`、
  `Point *pick(...)`（返回类型对、参数错）、`void f(Person p)`、`void f(Person *q)`、
  `void move(Point *pt, int dx)`、函数原型 `void f(Person *q);`。
  `Point make(...)`（裸返回类型且行首）之所以"能过"，是被 `try_var_decl()` 误当行首变量声明补了
  `struct `——属**巧合而非设计**。
- **修复**：新增 `parse_func_sig()`，在 `emit_raw_line()` 中**先于** `try_var_decl()` 判定该行是否为
  函数定义/原型（识别 `static` 等前缀词、多词返回类型、指针返回、原型；`if/while/else if` 等语句
  不会误判）。对返回类型与参数类型中已知 struct 名原位插入 `struct `（保序保格式，不动其它字符），
  并在**有函数体时**把参数登记进变量表（值 `ptr=0` / 指针 `ptr=1`）。命中函数形态的行不再走
  `try_var_decl()`，因此顺带消除了"函数名被误登记为变量"的副作用。
- **限制**：参数列表本身跨多行的签名不识别（按行处理，与"跨行调用不重写"同类）。
- **用例**：`test/cases/11_value_param.ct` / `12_pointer_param.ct` / `13_signature_types.ct`
  （含 `static` 返回、指针返回、原型、多词类型）。

#### 0.1.6 组合：struct 字段为另一 struct 类型 ✅ 已完成

- **机制说明（0.1.6–0.1.8 共享）**：[construction.md](../construction.md)——构造语义（vptr 由谁、在何时写入），
  决策 D1–D5 见其第 6 节。

- **问题**：struct 体按设计原样透传，字段类型不做限定（`struct Shop { Person owner; }` → 编译失败）；
  字段链式调用 `s.owner.greet()` 不重写。
- **修复**（分三段落地）：**a** 新增 `parse_fields()` 部分解析 struct 体，给已知 struct 类型的字段补
  `struct `，并把「值是 ct struct」的字段记进 `Struct` 字段表；**b** 声明对象时递归写入嵌套字段的
  vptr（**用声明后的赋值语句**，避免追加的 `.owner` 指定初始化覆盖用户自己写的 `.owner = {…}`）；
  **c** `transform_calls()` 改为沿字段链推导静态类型，支持 `s.owner.m(...)` → `s.owner.__<trait>_vptr->m(&s.owner, …)`。
- **限制**：含嵌套对象的对象**必须在函数内声明**（文件作用域无法安放赋值语句，越界 `die`）。—— **Phase 1.6 已解除**：文件作用域的这类对象由构造器 `__ct_init` 在 `main` 前写 vptr。
- **用例**：`test/cases/15_composition.ct`。

#### 0.1.7 存储：数组元素 ✅ 已完成

- **问题**：`Person ps[2];` 声明被限定但元素 vptr 未初始化；`ps[0].greet()` 不重写（编译失败）。
- **修复**：`Person ps[<n>];` 展开为声明 + 一个块内循环（`__ct_i`），逐元素写入 vptr（含嵌套字段）；
  调用侧支持 `ps[<常量>].m()` → `ps[0].__<trait>_vptr->m(&ps[0], …)`。
- **限制**（D2）：只支持**无初始化式**声明 + 常量下标；其它形态在需要初始化时 `die`。
- **用例**：`test/cases/16_arrays.ct`。

#### 0.1.8 释放：`delete` ✅ 已完成（堆对象的**创建**推迟到 Phase 1）

- **问题**：`Person *q = malloc(...); q->greet();` 调用被重写但 vptr 从未设置 → 运行期段错误。
- **本次落地**：`delete q;` → `if (q) free(q);`（`q` 必须是已登记的指针变量；靠词边界 + 形态判定，
  因此普通 C 里叫 `delete` 的标识符不会被误判）。Drop 版（`d->drop(); free(d);`）仍留 Phase 1。
- **未落地：堆对象的自动创建**。曾试引入 `new`（D3），复核后认为它不在计划内、且**并未真正堵住**
  `malloc` 那条洞（`malloc` 出来的对象依旧静默无 vptr、调用即崩），故**已移除**。堆对象的创建方式
  推迟到 Phase 1，与 Drop/delete 一起定——那时 `drop()` 也需要 vptr，必然要有结论。
- **现状**：堆对象需**手写** `q->__<trait>_vptr = &…;`（该行原样透传），之后 `delete q;` 可正常释放。
- **用例**：`test/cases/17_heap.ct`（手写 vptr + `delete`）。

#### 0.1.9 变量作用域 ✅ 已完成

- **问题**：`find_var()` 首命中、`g_vars` 只增不减；多函数同名变量/参数互相串味，产出非法 C。
- **修复**：`scope_track()` 在主扫描里跟踪花括号（跳过字符串/注释），每个 `{` 压栈当时的 `g_nvars`，
  遇到 `}` 弹栈回滚；函数体左花括号（含"花括号另起一行"的写法）单独用**参数登记前**的值压栈，
  保证参数随函数一起出作用域。这同时修掉了既有局部变量的跨函数串味。
- **备注**：本节原被排在 Phase 1，因 0.1.5 要登记参数而提前。
- **用例**：`test/cases/14_scope_shadow.ct`（两个函数各自声明同名 `d`、两个函数各自用同名参数 `x`，
  分属不同 struct；改动前编译失败）。

### Phase 0.2：接口多态（设计先行 → 已实现）

**机制说明**：[polymorphism.md](../polymorphism.md)——「接口值 = 胖指针 `{ self, vt }`」方案，
决策 D1–D7 已冻结（含落地实现注记）。

**目标**：能声明 **trait 类型的变量/参数**（如 `Greeter g`），运行时把不同 `struct` 派发进来，
即真正的「面向接口编程」。

**已落地（0.2a–0.2d）**：

- 新产物 `struct <Trait>_iface { void *self; struct <Trait>_vtbl *vt; };`（不改既有命名与布局）；
- 类型展开：裸 trait 名 `Greeter g` / 参数 / 返回值 → `struct Greeter_iface …`；
- 装箱：`(struct Greeter_iface){ (void *)&p, &Person_Greeter_vtable }`，覆盖**声明、赋值、实参、`return`**；
  实参装箱依赖**函数签名表**（定义先于使用）；
- 派发：`g.greet()` → `g.vt->greet(g.self)`；
- 校验：struct 未 `use` 该 trait、跨 trait 装箱、无法推断类型的表达式 → 一律 `die`，不产出坏 C。

**暂未做**：接口**数组**（声明即 `die`）；接口**字段**的构造期自动装箱（指定初始化器里的接口字段不装箱）。
接口字段本身已可用（Phase 1 补齐）：值字段 `T x` → `struct T_iface x`、指针字段 `struct T *x` → `struct T_iface *x`；
`s.x.m()` 经字段自身的 vt 派发，值字段的语句赋值 `s.x = v;` 自动装箱（指针字段赋值保持原样）。

**用例**：`test/cases/18_polymorphism.ct`（同一 `announce(Greeter)` 服务 `Person` 与 `Shop`，
外加接口变量重赋值与接口返回值）。

### Phase 0.3：剥离越位特性（回到纯 OO 的 `ctc.c`）

**主题**：把 Phase 0 之后越位实现在 C 侧的语言特性**从 `ctc.c` 移出**，让主线回到「只做 Phase 0 出口 1–9 的纯 OO」+ 底层设施。移出件**不销毁**：归档为 **oracle**（仍可构建出对照程序），供 Phase 2–5 用 CT 重做时对差。

**剥离清单（2026-10-14 用户确认：只剥这四组）**：

| 能力 | 判断 |
| --- | --- |
| namespace（1.1）、多文件 `ct build` + `.h.ct` + `pub`（1.2）、`import`（1.3） | **剥**：非 OO；且多文件正是「跨单元引用带 trait 对象」这一自举唯一硬阻塞的来源 |
| `Drop`（1.4） | **剥**：非 OO（`delete q;` → `if (q) free(q);` 属出口第 7 项，保留） |
| `#line`（1.5） | **剥**：只在多文件下有意义，随多文件一并移出（自举前置 #5 随之**退役**） |
| 泄漏警告 + `--diagnostics=json`（1.7） | **剥**：非 OO |

**保留清单（看着像越位，实则属 Phase 0 出口或自举必需）**：

| 能力 | 判断 |
| --- | --- |
| 堆对象创建 `T *p = malloc(...)` 自动写 vptr（1.4） | **留**：出口第 7 项「创建」；且是**自举前置 #2**（AST / 符号表需动态分配，剥掉就要处处手写 vptr，「漏写即运行期崩」） |
| `delete` 放宽到 `char *`（1.4） | **留**：出口第 7 项「释放」+ **自举前置 #4** |
| 一般接收者（1.9a：变量下标 / 指针数组 / 指针字段链） | **留**：出口第 5/6 项「组合 / 存储」的覆盖 + **自举前置 #6** |
| 方法体接入同一重写管线（1.9c） | **留**：出口第 1/3 项（方法体内派发）的必要条件 |
| 接口**字段**（0.2 补做） | **留**：属 Phase 0.2 接口多态（出口第 9 项） |
| 右值接收者 `f().m()`（1.9b） | **留（2026-10-14 定）**：与 1.9a 同源，单独剥会造成「下标可以、右值不行」的不一致 |
| 文件作用域对象 / 数组 + `__ct_init` + `static`（1.6） | **留（2026-10-14 定）**：**自举前置 #3**（全局符号表要它） |

> **对自举就绪度的影响**：剥离项**都不在**自举前置清单里（或随多文件退役），故剥离**不会**削弱就绪度；反而移除了唯一的硬阻塞（跨单元带 trait 对象）与不再需要的 `#line`（前置 #5）。保留下的 #2/#3/#4/#6/#7 恰是「剥离后仍需留在 Phase 0 核心」的那几项——**这也给出了「纯 OO」的可操作判据：自举前置清单 ∩ 非越位特性**。

**连带处理（必须同批完成，否则验证与文档失真）**：

- **归档 oracle**：剥离前给当前 `ctc.c` 打 tag / 存档，并确认它能构建出对照二进制——否则 Phase 2–5 面对旧 golden 将没有可比对的实现。
- **测试收缩**：`test/import/`、`test/multifile/` 整目录，`test/cases/19_namespace`、`20_namespace_nested`、`22_drop`，`test/errors/` 中 `namespace_*` / `ns_*` / `drop_*` / `too_many_warnings`，`run.sh` 里的 `#line` 层，以及 `test/unit/test_helpers.c` 里针对被移出函数的断言，**全部移入归档**并退出 `run.sh`（否则套件必红，违反 [AGENTS.md](../../AGENTS.md) §6）。（保留项用例——`test/cases/23_file_scope`、`27_static_file_scope`、`24`–`26` 接收者用例——**不动**。）
- **文档如实标注**：`README.md` 语法表与 `docs/language-spec.md` 相关条目须标「**已移出 L0，Phase 2–5 用 CT 回归**」，不得继续列为当前可用；`editors/vscode` 语法高亮**维持不动**（语法决策仍冻结，且高亮与编译器无关）。

**出口标准**：① `./test/run.sh` 在**收缩后**的套件上全绿；② `ctc.c` 只余 Phase 0 出口 1–9（+设施），`grep` 不到 namespace / 多文件 / `import` / Drop / `#line` / `--diagnostics` 的处理路径；③ 归档件可独立构建并复现旧 golden。

**完成记录（2026-10-14）**：

- `ctc.c` **3836 → 2897** 行（−939），删除 6 组越位实现；保留项的 golden **逐字节未变**（归档全部以 rename 形式记录，内容零改动）。
- 越位 fixture 移入 **[`test/archive/`](../../test/archive/)**（`cases/` `errors/` `import/` `multifile/`，17 个 `.ct`），退出 `run.sh`，留作 Phase 2–5 的对差基线；完整旧实现见 git tag **`overreach-oracle`**。
- 套件 **146 → 110** 项全绿（收缩 42 项：multifile / import / `#line` / warnings 四层 + 相关 errors 与 cli 断言；新增 6 项「已移出特性必须报错」的断言）。
- **补了一道 fail-loud 守卫**：`namespace` / `import` / `pub` 若成构造形态出现，报 `'xxx' is not supported by this compiler`（exit 1），`ct build` 报 `'build' (multi-file) is not supported by this compiler`——否则这些语法会**静默透传**成编不过的 C，违反 [AGENTS.md](../../AGENTS.md) §4。对应负例：`test/errors/removed_{namespace,import,pub}.ct`。
- 文档同步：`README.md`（CLI 表、语法表、测试计数）、`docs/language-spec.md`（§1–§10 逐节标注已移出）。

### Phase 1：自举（第一目标）

**主题（目标单一）**：把 Phase 0 的 **OO 化 C 语言**（剥离后的纯 OO `ctc.c`，即 L0）**用 CT 重写一遍**——与 L0 的目标完全一致，**唯一目的就是自举**。写法：OO 子集、**单文件**（L0 已无 namespace / import / 多文件，L1 无法分文件组织，见下）；出口是与 L0 **逐字节一致**。其余一切排在自举之后。

> **本阶段既不新增语言特性，也不恢复被剥离的特性**：只把 Phase 0 出口 1–9 的能力用 CT 重写一遍。特性恢复与新增一律从 Phase 2 开始。

**入口条件**：Phase 0.3 完成即满足。纯 OO 前提下自举**没有剩余硬阻塞**——就绪报告点名的「跨单元引用带 trait 对象」已随多文件一并移出；报告余下的表达力缺口（接口数组 `die`、构造期装箱、按行重写纪律）仍是 L1 源码必须遵守的纪律，见 [自举就绪总结报告](reports/selfhost-readiness/selfhost-readiness.html) 与下方「已知约束」。

**L1 出口标准（go/no-go 门）**：L1 能被冻结的 `ctc`（L0）端到端编译并运行，且对同一批语料与 C 版输出**逐字节一致**。

**开工决策（2026-10-14 用户确认）**：

1. **零复用**：L1 **不** `#include ctc.c`，自带全部设施（`Buf` / 分配器 / `die` / 逐行扫描原语，约 200 行，以普通 C 透传写就）。理由：剥离后的 `ctc.c` = 纯 OO + 设施，include 进来会连 C 的 OO 核心一并复用，等于没自举，且「逐字节一致」退化为同义反复。早先「`#include` 只复用设施」的设想**作废**（它与「L1 必须用 CT 重写 OO」自相矛盾）。
2. **banner 逐字节相同**：L1 原样发出 `Generated by ct v<版本> from <输入路径>`（含许可行）。版本号与命令名是独立事件：2026-10-17 与 2026-10-18 已按阶段边界依次 bump 到 v0.4.0 / v0.5.0 / v0.6.0 / v0.7.0 / v0.8.0 / v0.9.0 并重生成 golden；命令名随后经用户授权在**切片 7.3** 一并改为 `ct`（L0/L1 一次性解冻，golden 全量重生成）。
3. **源码位置与切片**：L1 源码为单文件 **`selfhost/l1/ctc.ct`**（新增目录，用户已批准）。首个里程碑 **M2-a** 只覆盖 `test/cases/01_trait_basic.ct` 所需子集（trait / struct / impl / use、方法调用重写、`.h` 生成、banner），出口是对 `01_trait_basic.expected.c` / `.expected.h` **逐字节相等**；此后按 golden 用例逐个补齐剩余能力。用 golden 做**增量 oracle**，而不是一次性翻写。
4. **出口附加一项**：Phase 1 的完成判据除「与 L0 逐字节一致」外，还要**用 L1 编译 `selfhost/l1/ctc.ct` 自身**成功（L1 是纯 OO 子集写的，功能完整后应当直接可行）——这是「真自举」的硬证据。
5. **L1 必须是 CT OO 风格**（2026-10-15 用户确认）：L1 的**数据模型层**（`Trait` / `Struct` / `Var` / `FuncSig` 等符号表）与**管线层**（逐行扫描、行重写、发射）必须用 CT 的 `struct` + `use` + `impl` 写成 OO 形态，**不得**退回 plain-C 直通；只有**设施层**（`Buf` / 分配器 / `die` / 扫描原语，约 200 行）按决策 1 保持 plain-C 透传。理由：CT 是 C 的严格超集，纯 C 直通的文件也「合法」，但对 OO 机制是**零证明**——那等于没自举（与决策 1 同构）。节奏为**分片推进**：先数据模型层 → 跑 `selfhost/check-m2a.sh` → 再管线层；每片以 byte-identical **不退化**为准绳，而不是以「跑得动」为准。附注（2026-10-15 实测）：L0 的 `MAX_FUNCS`（64）把 L1 里**每个 plain-C 函数签名**计入（定义与原型同等计数），而 `impl` 方法**不计**——该上限压力正是促使 L1 走 CT OO 风格的**健康约束**，不是要绕开的障碍；`ctc.c` 已冻结，**不得**为放宽它而改动。落地附注（2026-10-15）：管线层最终由**两个** trait 承载——`PipeOps`（主流程：构造解析、发射器、入口、CLI）与 `RewriteOps`（逐行重写层），`struct Pipe` 同时 `use` 二者；新增方法按归属放进对应的一半，避免单侧逼近 `MAX_METHOD`（32）。
6. **增量 oracle 落地为常驻关卡**（2026-10-15 用户确认）：`selfhost/check-goldens.sh` 把「L1 vs 全部 `test/cases/**` golden」做成一条命令，逐例比对 `.c` / `.h` 的字节，输出 `PASS / NEW / PENDING / REGRESSION` 四态与计数。脚本内的 baseline 名单是**棘轮**：只有已在名单里的用例失配才算回归并令关卡非零退出，未实现的族记 `PENDING`（连同 L1 的拒绝原因）不阻塞。起点实测（2026-10-15）：**13 pass / 0 new / 12 pending / 0 regression（共 25 例）**——12 个 pending 全部是 L1 主动 `die` 报「不支持」的留空能力族，不是算错。补齐顺序按**由小到大**：`13` 初始化形式 → `17` heap → 接口值（`21` → `18` → `28`）→ arrays（`16`）→ composition（`15`）→ 回头收互锁的 `23/24/25/26/27`（这些同时要 arrays 与 composition）。每片的出口是「byte-identical 不退化 + 把新通过的用例提升进 baseline 名单」。
7. **M2 达成，且 L1′ 自举闭环成为常驻关卡**（2026-10-15 实测）：`test/cases/**` 全量 **25 例逐字节一致**（25 pass / 0 new / 0 pending / **0 regression**），M2 出口达成。更强的一条也已实测——**L1 编译 L1 自身**得到 L1′，L1′ 以 `-Wall -Wextra -std=c99` **零警告**构建，再用**同一批语料**重跑，仍 **25 例逐字节一致**（`.c` / `.h` 与 L0 完全相同，含 banner）。这两条都固化进 `selfhost/check-goldens.sh`：第 4 步是 L1 vs golden，**第 5 步**是 L1′=L1 源码经 L1 编译 → 零警告构建 → 与 golden 逐字节比对，任一不符即令关卡非零退出。至此决策 4 的**出口附加项**（用 L1 编译自身）满足：Phase 1 的 go/no-go 门通过。此后新增能力一律排在 Phase 2 起（CT 侧重做），`ctc.c` 仍只接受 bug 修复。

**阶梯（M1→M2 属本阶段；M3–M6 属 Phase 2–5）**：L1 仅用 OO 子集写就；此后按 [bootstrap.md](design/bootstrap.md) 逐层爬升，每层以 **byte-identical golden** 为出口：

| 层 | 用 CT 实现 / 搬入 CT | 归属 |
| --- | --- | --- |
| L1（M2） | 用 CT（单文件、OO 子集）重写剥离后的纯 OO `ctc.c` | **Phase 1** |
| L2（M3） | namespace | Phase 2（前半） |
| L3（M4） | import + Drop | Phase 2（后半）+ Phase 3 |
| L4（M5） | JSON 诊断 + 泄漏警告 | Phase 4 |
| L5（M6） | 自举闭环（全功能对齐归档 oracle） | Phase 5 |

**阶梯约束（源语言滞后一级）**：第 n 级编译器只能编译「第 n−1 级所支持的语法子集」写成的源码。因此 CT 侧要**使用** namespace / Drop / import 组织编译器源码，必须先有支持它们的 CT 级编译器；**L1 只能是单文件**（Phase 0.3 已把多文件移出 L0），到 L2 起才能分文件组织。

> **名的歧义（2026-10-16 说明）**：「L2」在两个语境下含义不同——
> ① **能力阶梯**里的 L2 = 「支持 namespace 的那一级编译器」（M3，上表用法）；
> ② **本仓库实际产物**里的 L2 = 「L1 用 `build` 把 `selfhost/l2/**` 编出来的那个二进制」（Phase 2 拆分产物，也是 Phase 3 起 ratchet 的被测对象）。
> 二者当前**能力不等**：产物 L2 已含 Drop（Phase 3），而阶梯意义上的 L2/L3 是对能力层级的抽象描述。为避免混淆，下文与关卡脚本里说「L2」一律指 ②。

**顺序原则（2026-10-14 更新为「剥离在前」）**：越位特性**在 Phase 0.3 就先从 `ctc.c` 移出**——先拿到干净的纯 OO L0，自举目标才最小；移出件**归档为 oracle**、不销毁，Phase 2–5 用 CT 逐项重做时向它差分。

**长期目标**：`ctc.c` **长期保留**为纯 OO 的种子与 oracle，不整体删除；Phase 2 起新增的一切能力都由 CT 层承担，`ctc.c` 不再增长。

#### 新 `ct` 与 `ctc.c`：`#include` 复用底层设施的设想（2026-10-14 提出；已否决，L1 零复用）

> **待定**：剥离后 `ctc.c` = 纯 OO + 设施，而 L1 又必须**用 CT 重写 OO**、不得复用 C 的 OO 实现。所以「只 include 设施」还需额外手段（设施与 OO 分段并以宏隔离；或把设施抽成独立小文件——但后者与「单文件」规约冲突），或者 L1 干脆**自带设施、零复用**（最纯的自举）。**已定（2026-10-14 开工决策 1）：L1 自带设施、零复用**，本节仅作方向记录。

新 `ct` 用 CT 写、由冻结的 `ctc.c` 编译；它复用 `ctc.c` 的方式是 **`#include ctc.c`**（unity build，同 sqlite amalgamation），**不是**链接。边界：

- **保留在 C（被复用）**：**底层设施**——`Buf` / `xmalloc` / `xstrndup` / `die`（诊断）/ 逐行扫描原语 / 代码生成原语。
- **用 CT 重写（不复用）**：**OO 核心**（trait / struct / impl / use 转换）与**全部语言特性**。
- **include 是可收缩复用层**：随 CT 覆盖扩大，被 include 的 C 部分**逐步缩小**，最终只剩最底层设施。

> 为什么"只复用设施"而非"连特性一起复用"：被 include 的特性其实现仍是 C，等于没自举；且差分验证会失效（L1 的行为就是 `ctc.c` 的行为，"逐字节一致"成为同义反复）。只复用设施，才能既"避免重复"又保持自举与差分验证有效。

**落地前提（须在"只修 bug"冻结前一次性做完）**：

- `ctc.c` 的 `main` 需加 `#ifndef CTC_NO_MAIN` 守卫——否则与新 `ct` 的 `main` 落在同一 TU，重定义报错。**这是冻结前唯一一次结构性改造。**
- CT 代码必须**系统避开 `ctc.c` 的全部 `static` 标识符**（`buf_puts` / `die` / `word_at` / `emit_raw_line` …）；namespace 不修饰普通函数名，同 TU 重名即报错。
- `ctc.c` 的 `die()` → `exit(1)` 与进程级 `g_*` 需为**可复用 / 可重入**留出口（多文件 `ct build` 需逐单元、可按单元报错）。

**已知约束（开工前必须先接受）**：

- **接口数组声明即 `die`** → AST 子节点列表不能用 `Node kids[N]`，只能靠**接口指针 + 链表**；而指针接口字段的**赋值目前原样透传**（需手工构造胖指针）。**订正（2026-10-17）**：该「接口指针 + 链表」退路**本身不可靠**——指针接口字段赋值会**段错误**，且「接口指针局部声明」也 `die`；实测与订正见下方「三处表达力缺口与 AST 主线」。
- **接口字段不参与构造点递归、指定初始化式不装箱** → 装配 AST 时手工装箱代码增多（注：接口值字段的**赋值**其实已装箱，只有**构造点**没走 box 路径——见下方实测）。**订正（2026-10-17）**：构造点已由 ② 隐式装箱，接口数组已由 ① 补齐，见下方「三处表达力缺口与 AST 主线」。
- **按行重写**（构造与语句同行不处理、单行函数体不处理）→ 编译器源码必须遵守「一语句一行」的纪律，否则**静默不重写、产物编不过**。
- **声明必须先于使用 + 单趟扫描** → trait / struct 需人工拓扑排序；相互递归只能经接口指针。
- **namespace 只修饰 struct / trait / impl 符号，普通函数名不修饰** → 若按 namespace 切分源码，普通函数会在 C 层重名冲突（这也是先走单文件路径的一个动机）。

**三处表达力缺口与 AST 主线（2026-10-17 用户决定）**

自举就绪报告点名的三处缺口已由 [test/acceptance/run.sh](../../test/acceptance/run.sh) **实测枚举**。L0 无错误恢复（一个错误即终止），故逐构造隔离成微探针——否则编译一次只会看见第一条 `die`：

| 微探针 | 缺口 | 实测现象 |
| --- | --- | --- |
| `p01` / `p02` | 接口**数组**声明（`Node kids[2]`、`Node *kids[2]`） | 起先 `die`：`unsupported declaration of interface type`；**① 已修**（见下） |
| `p03` / `p04` | 数组元素**赋值 / 派发**（`kids[0] = a; kids[0].eval()`） | 起先被上一条门禁挡住，不可达；**① 已修**（见下） |
| `p05` | 接口**值字段**在**构造点**装箱（`Pair p = { .l = a, .r = b }`） | 起先 ctc 产出**编不过的 C**（`void *` 收 `struct Leaf`）；**② 已修**（见下） |
| `p06` | 接口值字段**赋值**（`p.l = a;`） | ✅ **已支持**（走既有 box 路径） |
| `p07` | 接口**指针字段**在**构造点**（`p.l = &a`） | 起先 ctc 静默透传 → 编译过 → **运行段错误 exit 139**；**② 已修**（见下） |
| `p08` | 接口**指针字段**赋值（`p.l = &a;`） | 起先静默透传 → 段错误；**③ 已修**（L2 隐式装箱，见下） |
| `p09`–`p11` | 对照组：接口局部来自值 / 指针、函数返回接口 | ✅ **已支持**（证明 box 子系统存在，harness 能诚实抵达 PASS） |
| `ast_spike` | **整个目标程序**（trait 含两方法、值/指针字段、接口数组字段与 `Block` 的 `self->items[i].eval()`） | 起先首错即 `die`；**① + ② 落地后转 PASS**（编、跑、输出 `5`） |

**订正**：「用**接口指针 + 链表**绕过数组缺口」这条退路**本身是坏的**——指针接口字段赋值静默透传并段错误，且**接口指针局部声明**（`T *g = 0;`，[test/errors/iface_pointer_init.ct](../../test/errors/iface_pointer_init.ct)）同样 `die`。故 AST 子节点既不能数组、也不能指针链表，只能手工构造胖指针。三处缺口对外全部可见（`die` 或坏 C / 崩溃），**不存在隐藏的静默降级**。**三例连归档 oracle 都不支持**（oracle 对同三例同样 `die` / 产出坏 C / 段错误），故它们是**新增**而非「恢复」。

**用户决定（2026-10-17，三项均取推荐项）**：

1. **落点 = CT 侧（`selfhost/l2/**`），`ctc.c` 保持冻结**——既然 trio 无归档 oracle 可对差（不属 Phase 2–4「恢复」类），就不该在 C 侧加；且 `ctc.c` 的 `MAX_FUNCS` 余量仅 1，C 侧无处可加。鸡生蛋问题有解：**先让 L1/L2 在纯子集里把缺口当作「它提供的一项特性」实现**（其源码不用该特性），再由它编出用该特性的新编译器——L0 全程不动。
2. **顺序 = 先落验收关卡、再逐条补**（消费者驱动：完整缺口清单从编译报错中长出，而非靠读码推断）。
3. **定位 = AST 版编译器作**新主线**，旧 `selfhost/l1/ctc.ct`（L1）打 tag 归档**；出口口径由 **byte-identical** 换成 **行为等价**（同输入、同运行输出，不要求产物逐字节相同）。

**关卡**：[test/acceptance/run.sh](../../test/acceptance/run.sh)（`PASS` / `PENDING` / `NEW PASS` / `REGRESSION` 四态，退出码仅 `REGRESSION` 非零）。基线 `BASELINE` 现含**全部 20 项**（`p01`–`p18` + `ast_spike` + `ast_parse_spike`），即当前**20 pass / 0 pending / 0 regression**；`p18_struct_array_field` 当时按决定留在 PENDING，2026-10-21 起已晋升基线（ct-ast 实现逐元素 vptr 写入，L2 仍不支持，故以 ct-ast 为默认目标）。**默认探针目标为 ct-ast**（L0→L1→L2→ct-ast 链）——`ctc.c` 冻结、能力只落 CT 侧，故只有显式 `CT=<l0>` / `CT=<l2>` 才分别探 L0 / L2。**故意不进 `./test/run.sh`**——`run.sh` 的绿必须继续意味着「编译器正确」，而非「编译器完备」。

**落地记录**：

- **③ 指针接口字段（2026-10-17，落 `selfhost/l2/core.ct`，语义决策：隐式装箱）**：新增 `RewriteOps::box_to_iface_ptr`——具体对象隐式装箱为 `&(struct <T>_iface){ (void*)&x, &<S>_<T>_vtable }`（匿名声明的生命期 = 所在块），已是接口值则取址 / 复用，函数返回接口走复合字面量，无法推断则 `die`（绝不产出坏 C）。`try_iface_assign` 对指针接口字段不再透传。`p08` 转 PASS，全套关卡零退化。

- **② 构造点隐式装箱（2026-10-17，落 `selfhost/l2/core.ct`，语义决策同上：隐式装箱）**：新增 `RewriteOps::box_agg_fields`——聚合初始化式 `{ .l = a, .r = b }` 不再原样透传，而是按项拆分，命中的接口字段走与赋值完全相同的装箱路径（值字段 `box_to_iface`、指针字段 `box_to_iface_ptr`），非接口项、位置式与嵌套花括号原样保留。接线点在 `try_var_decl` 的花括号分支。`p05` / `p07` 转 PASS，全套关卡零退化。

- **① 接口数组（2026-10-17，落 `selfhost/l2/core.ct`）**：共用一条「下标延伸到哪」的判定 `RewriteOps::skip_bracket`，四处接线——(a) `try_iface_decl` 新增数组分支：`T xs[n]` → `struct T_iface xs[n] = { { 0, 0 } }`、`T *xs[n]` → `struct T_iface *xs[n] = { 0 }`（胖指针两字宽，故值数组的初始化式要嵌套一层花括号），变量表记 `iface + arr [+ ptr]`；(b) `try_iface_assign` 支持元素赋值 `xs[i] = v;`（值数组装箱、指针数组 `box_to_iface_ptr`），顺带让 struct 数组元素 `ps[i].l = v;` 也走通；(c) `transform_calls` 的接口派发改为「先吃下标再取方法」，`xs[i].m()` → `xs[i].vt->m(xs[i].self)`，`T *xs[n]` 的元素自身是指针故走 `->`；(d) 结构体接口字段新增数组标记（`ifarr` / `pifarr` 两张标记表 + `find_iface_field` 出参），`walk_to_iface_field` 在命中数组字段后吃掉 `[<expr>]`，于是 `self->items[i].eval()` → `_self->items[i].vt->eval(_self->items[i].self)`。`p01`–`p04` 与 `ast_spike` 全部转 PASS，**目标程序首次编、跑、输出 `5`**。

- **④ 接口指针与数组形参（2026-10-17，落 `selfhost/l2/core.ct`）**：把「接口值 / 指向接口值的指针 / 接口值数组 / 接口指针数组」四态收成一条规则——**非下标接收者按 `ptr` 选 `.`/`->`，下标接收者按「元素自身是不是指针」（`arr && ptr`）选**。四处接线：(a) `try_iface_decl` 的指针分支允许初始化式（`T *q = &n;`，走 `box_to_iface_ptr`）**并登记变量**——此前裸 `T *g;` 不登记，故 `g->m()` 根本无法派发；(b) `try_iface_assign` 对可下标的接口变量支持元素赋值，对裸指针走 `box_to_iface_ptr`；(c) `parse_func_sig` 的形参登记改为**保留 `isptr`** 并识别数组形态 `T xs[]`（此前指针接口形参被强制成「值」，数组形参连名字都在 `analyse_param` 里被丢掉），于是 `xs[i].eval()` 在函数体内可派发；(d) `walk_to_iface_field` 允许对指针接口字段取下标（`s.f[0].m()`）。同时新增 AST 形状探针 **p12–p17**（堆节点装箱、子节点数组字段、数组形参两种拼写、接口指针局部与带初始化式的接口指针），**6/6 转 PASS**。

- **进度**：验收关卡 **19 pass / 1 pending / 0 regression**（`BASELINE` 含 p01–p17 + `ast_spike` + `ast_parse_spike`）。唯一 PENDING 是 **`p18`**：`struct Duo { Num ab[2]; }` 这类 **struct 类型的数组字段**——其元素 vptr 需在宿主对象的构造期逐元素写入（`put_nested_assignments` / `needs_nested_init` 目前不覆盖数组字段）。AST 主线的子节点是**接口值**（由 p13 覆盖），故 **p18 按决定延后**；探针保留，用于钉住这一族缺口不被忘记。**（2026-10-21 更新：ct-ast 已实现数组字段的逐元素 vptr 写入，`p18` 随之晋升 `test/acceptance/run.sh` 的基线；L2 仍不支持，故以 ct-ast 为默认目标。）** **为何这些都不进 golden**：`examples/**` 与 `test/cases/**` 的基线都由 **L0/L1** 驱动，承载不了 L0 不支持的语法（`ctc.c` 冻结、不得为其放宽），所以只有 `test/acceptance/run.sh`（探 L2）能钉住它们；编辑器侧亦无需改动——接口数组/指针对拼写用的仍是既有括号、`*` 与标识符，没有新关键字。

- **可行性骨架（2026-10-17）**：新增验收探针 **`ast_parse_spike`**（[test/acceptance/ast_parse_spike.ct](../../test/acceptance/ast_parse_spike.ct)）——最小端到端前端：手写词法器 + 递归下降解析 `1+2`，在堆上构造 `Num` / `Add` 节点（子节点是 `Expr` 接口值字段），经接口派发求值并打印 `3`。由 **L2** 编译、gcc 零警告、运行通过；`test/acceptance/run.sh` 基线升至 **19 pass / 1 pending / 0 regression**（`p18` 仍按决定延后）。结论：**AST 主线的第一代可以完全落在现有 CT 子集内**，不需要再补语言特性；下一步是把骨架扩成能编译最小语言子集的编译器。

- **归档点**：tag **`pre-ast-mainline`** 打在 **2026-10-17 的 frozen 边界**（`l2/**` 仍在 frozen L1 表容量之内），它**不是** Phase 9 的起点——Phase 9 开始前的最后一个提交是 v0.8.0 收口（`db667df`，tag `v0.8.0`）。此后出口口径为**行为等价**。

**容量预算（2026-10-17 实测；写 AST 编译器的前置约束）**

符号表是**每次运行一份、跨单元共享**（`driver.ct` 的 `build` 逐单元调用同一进程的 `ct_compile_file`），所以**拆多单元不能扩额**，只能改善源码组织与编译顺序。四类额度：

| 额度 | 上限 | 现状 | 说明 |
| --- | --- | --- | --- |
| plain-C 顶层签名（含 `static`） | `MAX_FUNCS` 64 | core.ct 33 + driver ≈15 + 10 个 `pub` 包装器 ≈ **58** | 最紧的一项；**impl 方法不计**，所以把新逻辑写进 impl 块是唯一可持续的解法 |
| CT `struct`（可 `use` trait） | `MAX_STRUCT` 32 | **2**（`SymTab`、`Pipe`） | **plain-C `typedef struct` 不计**——数据模型全走 typedef；AST 里「只装数据、不需派发」的类型应继续走 typedef |
| CT `trait` | `MAX_TRAITS` 16 | **3**（`SymTabOps`、`PipeOps`、`RewriteOps`） | 每个 trait = 一套 vtable + 一个 iface 类型 |
| 每 trait 方法 | `MAX_METHOD` 32 | `PipeOps` **31** | 已到边缘；新方法必须放对应的一半（这正是 `PipeOps` / `RewriteOps` 拆分的原因） |
| AST 编译器的每 trait 方法 | `MAX_METHOD` 32 | `ParseOps` **32/32**（9.7 收口时） | **已满**：`selfhost/ct-ast/main.ct` 的解析层不能再加方法；新逻辑需另开 trait，或放进 `ModuleOps`（12）与 `EmitOps`（29）。其余：`AstOps` 8、`SymOps` 17。Phase 10 已按此执行——10.2 的语义诊断落在新 trait `DiagOps`（5 个方法，10.4 又补 `skip_body` / `skip_after_error`），10.3 的内存语义落在新 trait `MemoryOps`（11 个方法），10.5 的缓存落在 `CacheOps`（6 个），10.6 的包管理落在 `PkgOps`（28 个），均未触碰 `ParseOps` |

其它：`MAX_FIELDS` 32（每 struct 四张字段表各 32；**`Pipe` 已用 31/32**，Phase 5 新增 `in_body` / `ns_expect` 后只剩 1 个字段余量）、`MAX_VARS` 512、`MAX_SCOPE` 256、`MAX_DEPTH` 8（AST 类型递归走指针/接口，不消耗它）。

**越界时的唯一出路是自举阶梯**（不是改 L0）：`l2/**` 里的 `MAX_*` 只是源码文本里的数字，可以调大，但「能否编译这份源码」取决于**编译者自己的表大小**——所以增长**一代滞后**：让 frozen L1（32/16/64）编得过的那一代先落地，新一代带着更大的表，下一代源码才能变大。**推论：第一版 AST 编译器必须落在 32 struct / 16 trait / 64 plain-C 之内**；一旦 `l2/**` 的声明数超过 frozen L1 的表容量，`check-goldens.sh` 第 7 步（L1 vs L2 定点）即失效——这正是 `pre-ast-mainline` 记录的切换点。

> **关于两条负例（订正）**：[test/errors/iface_array.ct](../../test/errors/iface_array.ct) 与 [test/errors/iface_pointer_init.ct](../../test/errors/iface_pointer_init.ct) **不必退役、也不该退役**。`test/errors/**` 由 `./test/run.sh` 用 **L0（`ctc.c`）** 驱动，而 L0 已冻结、**永远**会对这两例报 `die`；它们钉的是 L0 的行为，因此继续有效。新能力只存在于 CT 侧（L2），由 `test/acceptance/run.sh` 的 `BASELINE` 钉住——两条负例与那批探针各自钉住**不同的编译器**，并不矛盾。（`iface_pointer_init.ct` 钉的是 `T *g = 0;`：L0 报 `unsupported declaration of interface type`。L2 已在 ④ 里放开指针声明的**初始化式**（`T *q = &n;`），但 `0` 不是可推断的对象，L2 仍会 `die`（`cannot infer the type of '0'`）——故该负例继续有效，只是两侧的错误口径不同。）

**过渡期纪律**：自举启动后**冻结一切新的 C 侧语言特性**；`ctc.c` 只接受 bug 修复。若 L1 暴露出 ct 表达力缺口，须先判定它属「语言特性」（放到 CT 层实现）还是「种子核心能力」（必须在 C 侧补）——后者要作为 **Phase 0 核心的修订定义**显式记录，不得顺手打补丁（这正是 Phase 0 历史偏差的复发点）。

**自举之后的恢复与新增（Phase 2–5 共用前提）**

自举（Phase 1）完成后才动手。出口判据按**类别**分两类（不再按子阶段分）：Phase 2–4 是**恢复**（有归档 oracle + 冻结 golden，出口 = **byte-identical**，无需再拍设计）；Phase 5 是**新增**（无 oracle 可对差，出口 = **设计冻结 + 新用例 + `run.sh` 全绿**）。实现层面的设计见 [design/restore.md](design/restore.md)（决策 D1–D8，仅 D6 待定；D7 已定为「本地优先」，D8：`map` 移出，见 Phase 6）。

**实现方针——保真优先（2026-10-16 用户确认）**：用 CT 重做这些特性时，以**与归档 oracle 逐字节一致**为准，**包括复刻其既有行为与限制**（例如跨行块注释的 `/* … */` **续行**会被当作普通代码行处理，见 [language-spec](../language-spec.md) §6.2）。因此**不修改 `test/archive/**` 的输入、也不重新生成任何归档 golden**——fixture 与 golden 都是冻结的 oracle；既有缺陷照实写进 §6.2，而不是靠改语料把它绕开。对差关卡是 [selfhost/check-archive.sh](../../selfhost/check-archive.sh)。

**次序的三条硬约束（不能乱）**：

1. **Phase 2 必须最先**——只有 namespace + 多文件落地，CT 编译器源码才能分文件；`import` 也晚于它（依赖路径 / 符号解析）。
2. **Phase 3 是 Phase 5 的前置**——AutoDrop 依赖 Drop，路径敏感分析依赖作用域 + Drop。
3. **目录 = namespace 绑定依赖 Phase 2**，只能落在 Phase 5。

与 [bootstrap.md](design/bootstrap.md) 的阶梯对齐：M3 → Phase 2 前半；M4 → Phase 2 后半 + Phase 3；M5 → Phase 4；**M6（全功能对齐）在 Phase 5 收口**。

### Phase 2：模块化（原 2.1）

- **CT 重做**：namespace（`parse_namespace` + 限定查找 + 产物前缀 `<Ns>_<Struct>_<Trait>_<method>`）、多文件 `ct build` / `.h.ct` / `pub`（类型下沉 `.h`、`.c` `#include` 自己的头、可见性规则）、`import`（路径解析 + 递归编入 + 跨单元符号累积）。
- **出口**：归档用例**逐字节一致**；**编译器源码切成多文件**（后半程的最大红利，✅ 2026-10-16 达成 → `selfhost/l2/**` 由 L1 建出 L2，见下条进展）。
- **对差依据**：`test/archive/cases/19_namespace`、`test/archive/cases/20_namespace_nested`、`test/archive/multifile/`、`test/archive/import/`。
- **风险**：命名前缀一经发布即契约，须先冻结；多文件破坏「`.c` 自包含」，须与 `pub` 可见性规则一起定案；`-I` 已定（**本地优先**：先查导入方所在目录，再按命令行顺序逐个查 `-I` 根）；跨单元 vtable 可见性**已定**（2026-10-16 拆分实测：vtable 发射为 `static`，**符号不可跨单元**，跨单元派发只走对象内已存的 vptr；头单元也无法携带 `MAX_*` / `size_t` / `FILE`——`pub` 前缀进不了 `.h`）。
- **进展（2026-10-16）**：**namespace 已达成**——`selfhost/check-archive.sh` 报 `19_namespace` 与 `20_namespace_nested` 逐字节一致（嵌套命名空间顺带达成），另有 4 条 namespace 负例（`namespace_bad_path` / `namespace_path_too_long` / `ns_path_nested` / `ns_qualified_name`，含逐字相同的诊断）通过并提升进关卡基线；Phase 1 出口不退化（`check-goldens.sh` 25/25、L1′ 一致）。实现要点：`g_ns` 扁平前缀、`read_qual_ref` 解析限定声明头、`transform_calls` 的 `::` 链重写、`compile_range` 的 namespace 分支（递归 + 压/还前缀）。**当时待做**：多文件 `.h.ct` / `pub` / `ct build` / `import`——`test/archive/{multifile,import}/` 的四个单元仍 PENDING。（多文件部分已由下方 2026-10-16 条目取代。）
- **进展（2026-10-16，切片 2d/2e + `.h.ct`/`-I`）**：**多文件 `ct build`、`pub`、`import` 与 `.h.ct` / `-I` 均达成**——`test/archive/{multifile,import}/` 四单元逐字节一致（`.c` 与 `.h` 两侧）并提升进 `baseline_multi`；本轮再补 **`.h.ct` 附加式命名**（基名剥 `.h.ct` → `foo.c` + `foo.h`，`import foo;` 回退命中 `foo.h.ct`）与 **`-I <dir>` 搜索根**（可重复；解析顺序 = 导入方目录优先，再按命令行顺序）。CLI 增 `build` 子命令（`compile` 兼作显式别名，build 模式 `-o` 为输出**目录**）；驱动 `collect_imports` / `resolve_import` / `unit_visit` / `build_output` / `build_main` 解析每个 `import a::b;`、按依赖后序逐单元以多文件模式编译并打印建议的 `cc` 命令。`pub` 函数行剥掉 `pub` 但原型进 `.h`（`.c` 留空行），`pub trait` / `pub struct` 只把类型放进 `.h`，`import` 行被消费，`#line` 映射（`line_of` / `line_at` / `line_break`）落在多文件 `.c` 里。**新语义的用例**放 `test/modules/**`，由 `check-archive.sh` **第 7 组 designed** 覆盖（无归档 oracle，自比对 golden + 端到端运行）：`hdr`（`.h.ct` 命名 + 回退）、`inc`（`-I` 使能用）、`inc_missing`（不给 `-I` 则必须报 `cannot resolve import`）、`precedence`（同名时导入方目录优先于 `-I` 根，钉住「本地优先」）。**当时待做**：`--line` / `--no-line` 覆盖开关（归 Phase 4）。（已在 Phase 4 切片 1 落地。）
- **进展（2026-10-16，源码拆分 → L2）**：**后半程红利落地**——CT 编译器源码已从单文件种子 `selfhost/l1/ctc.ct` 拆成多单元源码树 `selfhost/l2/**`（`core.ct` + `driver.ct`），由 **L1 自身的 `build`**（多文件 + `import`）编译，产出 **L2**；出口判据 = **L2 对 `test/cases/**` 与 L1 逐字节一致（25/25）**，已达成（`check-goldens.sh` 第 6 步）。拆分触发的能力与**硬约束**（T0 探针实测）：① `pub` 前缀**进不了 `.h`**——`ctc.ct` 对 `#` 开头的行直接 verbatim 写进 `.c` 并提前 return，绕过 `pub` 路由，故**头单元无法携带 `MAX_*` / `size_t` / `FILE`**；数据、宏与单例只能留在 `core.ct`（落进 `core.c`），`driver.ct` 自带同值 `MAX_*` 副本。② `impl` / vtable 原生发射为 `static`，**符号无法跨单元引用**——跨单元派发只能经由对象内已存的 vptr（即"用访问器返回 `struct Pipe *` / `struct SymTab *` 后再 `->method()`"）。③ `MAX_FUNCS` 只对**顶层 plain-C 签名**累积（`pub` 原型 + 定义计一次）；本拆分只导出 10 个 `pub` 标量包装器（`ct_read_file` / `ct_is_ident_char` / `ct_usage` / `ct_default_output` / `ct_begin_imports` / `ct_add_import` / `ct_compile_file` / `ct_cc_reset` / `ct_cc_add` / `ct_cc_finish`）。**订正（2026-10-16，Phase 3 实测）**：该上限**也计入 `static` 顶层签名**，故余量其实很小——Phase 3 新增辅助函数已必须改用 `impl` 方法，详见 Phase 3 进展。**同源、不互相生成**：`selfhost/l2/**` 与手写种子 `selfhost/l1/ctc.ct`（L1）都是手写源码，种子保留。（**Phase 3 起改为「L1 冻结、新能力只落 `l2/**`」**——双写不可持续，见 Phase 3 开工决策。）**新关卡**：`check-goldens.sh` 第 6 步（**硬判据**：L1 `build selfhost/l2/driver.ct` → L2 → 语料逐字节）、`check-archive.sh` 3b、`check-m2a.sh` 第 7 步、`ct-tour.sh` 第 6 步。**新设计用例** `test/modules/split`（`pub trait` + `pub struct` 在头单元、`impl`（含 static vtable）在另一单元、第三单元经访问器返回的指针派发）钉住该跨单元契约，登记进 `check-archive.sh` 第 7 组 `baseline_designed`。**当时待做**：Phase 2 的 `--line` 与 Phase 3+ 的恢复项；`--line` / `--no-line` 覆盖开关仍归 Phase 4。（这些均已在 Phase 3 / Phase 4 落地。）
- **收口（2026-10-16 用户确认，口径 A）**：**Phase 2 到此结束**——**不 bump 版本号**（`CTC_VERSION` 保持 `v0.0.1`，冻结期不改），只打**非版本 tag `phase2-multifile-split`**；`v0.1.0` / `v0.2.0` 的 bump 与「单入口 `ct`」一并落地，届时一次性重生成全部 golden。两个出口均已达成，故本阶段无遗留功能项；`--line` / `--no-line` 归 Phase 4。（版本号已于 2026-10-17 统一 bump 到 v0.4.0，见「版本记录」。）

### Phase 3：内存（原 2.2）

- **CT 重做**：`Drop`（内置保留名 trait、惰性生成、递归释值字段）+ `delete` 放宽（任意指针 → `if (p) free(p);`）。
- **出口**：drop 用例**逐字节一致**。✅ 已达成（2026-10-16）。
- **对差依据**：`test/archive/cases/22_drop`、`test/archive/errors/drop_*`。
- **风险**：用户 `impl Drop` 与默认体的合并语义需定死。
- **开工决策（2026-10-16 用户确认，方案 B：L1 冻结）**：本阶段**不动 `selfhost/l1/ctc.ct`（L1）**——L1 自此成为**冻结种子**（能力停在 Phase 2），新能力只落 `selfhost/l2/**`。理由是双写不可持续：按 Phase 2 的「L1 与 `l2/**` 同源」字面执行，Phase 3–7 每项特性都要写两遍。这与上一级同构——`ctc.c` 冻结后开发搬到 L1，L1 冻结后开发搬到 `l2/**`。**代价是关卡语义改变**：`check-archive.sh` 的 ratchet 从 L1 换成 **L2**（L1 `build` `l2/**` 得到），并新增 `check-goldens.sh` **第 7 步不动点**（L2 也编 `l2/**`，产出须与 L1 逐字节一致）。
- **进展（2026-10-16，Drop 落地）**：**`Drop` 与 `delete` 分流均已在 `selfhost/l2/core.ct` 实现**，`22_drop` 的 `.c`/`.h`/运行输出三侧与归档 oracle **逐字节一致**，5 条 drop 负例（`drop_reserved` / `drop_impl_undefined_struct` / `drop_impl_not_used` / `drop_impl_no_method` / `drop_impl_no_body`）全部通过——`check-archive.sh` 的 `baseline_cases` 增至 3 例、`baseline_errors` 增至 9 条。实现要点：`Struct` 增 `has_drop` / `has_user_drop` / `drop_used` / `drop_bstart` / `drop_blen` / `def_line`；`use Drop` 只置标记（**不进 vtable、不加 vptr**）；`trait Drop` 报保留名；`parse_impl` 特判 `impl Drop for T` 并抓用户函数体；`delete p` 对 Drop 类型改发 `if (p) { T_Drop_drop(p); free(p); }`；发射分两处——**原型在图前、定义在图后**（`compile_file` 为此把主体先写进 `tmpfile()` 再回填，与 oracle 同构），且只对 `delete` 真正触达的类型发射（`mark_drop_closure` 做传递闭包），避免 `-Wunused-function`。**签名上限的实测教训**：`MAX_FUNCS`（64）**计入所有顶层 plain-C 签名（`static` 也算）**，`l2/**` 余量已近乎为零——两个新辅助函数因此改为 `impl` 方法（`SymTabOps::mark_drop_closure`、`RewriteOps::body_uses_self`），不是风格偏好而是硬约束；`PipeOps` 现为 31/32。
- **验证（2026-10-16）**：`check-goldens.sh` 25/25 + L1′ 25/25 + L2 25/25 + **不动点 2/2 单位一致**；`check-archive.sh` 0 退化（单单元 3 pass、诊断 9 pass / 1 pending、多单元 4 pass、designed 5 pass）；`check-m2a.sh` 与 `ct-tour.sh` 退出 0；`./test/run.sh` 115 项全绿（沙箱内摘除 `cli/compile-cannot-write` 后实跑 114/0）；`ctc.c` 与 `selfhost/l1/ctc.ct` 相对 `audit-1` 无改动。

### Phase 4：诊断与溯源（原 2.3）

- **CT 重做**：`#line`（多文件默认开，D4 = A）、泄漏警告 + `--diagnostics=json`（首版范围见 1.7）。
- **新增（无 oracle，须配新用例）**：多错误报告 + 错误恢复（跳到下一个行首 / `}`）、语义诊断（重复 trait / struct 定义报错、方法签名与 trait 不一致时告警）。
- **出口**：诊断层全绿；`#line` 能把 gcc 报错映回 `.ct` 行。
- **对差依据**：`test/archive/errors/*`、`run.sh` 的 `#line` 层。
- **风险**：错误计数与重同步点容易产生级联误报；语义诊断要与「不做类型检查」的定位边界划清。
- **进展（2026-10-16，切片 1：`#line` 开关收尾）**：`--line` / `--no-line` 已在 `selfhost/l2/**` 落地——`core.ct` 新增全局 `g_line_force`（`-1` 随模式 / `0` 强制关 / `1` 强制开），`g_emit_line = (g_line_force >= 0) ? g_line_force : multi;`；`ct_compile_file` 增第 4 个参数 `line_force`，`compile_main` 与 `build_main` 两条 CLI 路径均解析并透传，usage 文本补上两行。新增两个 designed fixture（`test/modules/noline/`：`build --no-line` 抑制多文件默认开；`test/modules/line/`：`compile --line` 单文件强制开），`check-archive.sh` 第 7 组由此扩展出 `compile.args` 分支（单文件用例在暂存副本里原样跑参数，banner 路径才与 golden 对齐），`baseline_designed` 增至 7 例。**单文件默认仍为关**，故 L2 单文件产物与 L0 逐字节一致。新代码一律进 `impl`（`MAX_FUNCS` 余量仅 1）。
- **进展（2026-10-16，切片 2：泄漏警告 + `--diagnostics`）**：oracle 的保守、路径不敏感泄漏警告已在 `selfhost/l2/**` 恢复——`Var` 增 `owned` / `own_line`，指针声明处的 `malloc` / `calloc` 记为持有（`new_var` 复用槽位时清这两个字段），`delete` 与 `return` / 逃逸赋值清标记，作用域闭合时 `leak_check_scope` 收集仍持有的对象，`emit_warnings` 按 `--diagnostics=json` 发 JSON（compile 走 stdout、build 走 stderr，后者把 stdout 留给 cc 命令）、按 text 发 stderr。归档负例 `too_many_warnings` 由 PENDING 转 PASS（超 `MAX_WARNS` 仍 `die`）。**5 个新方法全部进 `SymTabOps`（9 → 14）**，warning 输出复用既有 pub 包装器（单文件 `ct_compile_file`、build `ct_cc_finish`），**顶层函数零新增**——`MAX_FUNCS` 余量仍是 1。新增 3 个 designed fixture：`leak`（compile text）、`leak_json`（compile json → stdout）、`leak_build`（build json → stderr），`check-archive.sh` 第 7 组新增 `expected.stdout` / `expected.stderr` 逐字节断言。
- **验证（2026-10-16，切片 2）**：三套 golden 全部由 tag `overreach-oracle` 编出的 oracle 生成，L2 与之在 `.c` / `.h` / stderr / stdout 四侧逐字节一致（含 `--diagnostics=bad` 的 `unknown diagnostics format` 报错）；`check-archive.sh` 0 退化（单单元 3 pass、诊断 **10 pass / 0 pending**、多单元 4 pass、designed **10 pass**）；`check-goldens.sh` 25/25 + L1′ 25/25 + L2 25/25 + 不动点 2/2；`check-m2a.sh` / `ct-tour.sh` 退出 0；`./test/run.sh` 115/115；手工三件套通过，L2 单文件产物与 L0 逐字节一致。
- **进展（2026-10-16，切片 3：多错误报告 + 重同步）**：`die` 不再一律退出——`compile_range` 的逐行循环每轮用 `setjmp` 设一个守卫，`die` 报告后 `longjmp` 回守卫（无守卫时仍是原来的「一处错误即停」，OOM 亦然）。守卫处快照、处理分支里还原 `sym->nvars` / `g_nscope` / `g_body_abs`（长跳转会把 `emit_body` 的还原跳过），嵌套 namespace 的递归靠保存/拷回 `jmp_buf` 保住外层守卫。重同步点由 `RewriteOps::recover_pos` 给出：自错误处向后，取「下一个 `}` 之后」与「下一行行首」的先到者（跳过字符串与注释），并保证严格前进。错误上限 `MAX_ERRORS=20`，超过即打印 `ctc: too many errors, stopping` 后退出 1。失败的编译按本次调用的错误增量**删除**已写的 `.c`/`.h`，并在 stderr 末尾补 `ctc: N error(s) generated`。
- **验证（2026-10-16，切片 3）**：3 处错误的样例三处全报 + 摘要 + 退出 1 + 无产物；`MAX_ERRORS` 边界（第 21 处后停止）、namespace 嵌套内错误、函数体内错误均符合预期，且后一处错误的位置不受前一处长跳转影响（与 L0 的既有位置一致）。`check-archive.sh` 0 退化（designed **12 pass**，新增 `multi_err` / `multi_err_build`）；`check-goldens.sh` 25/25 + L1′ 25/25 + L2 25/25 + 不动点 2/2；`check-m2a.sh` / `ct-tour.sh` 退出 0；`./test/run.sh` 115/115；手工三件套通过。
- **进展（2026-10-16，切片 4：语义诊断）**：两类新增诊断落地。**重复定义**在 `parse_trait` / `parse_struct` 追加前按 **cname** 查重（namespace 隔离：`A::S` 与 `B::S` 合法），命中即 `duplicate trait 'X'` / `duplicate struct 'X'` 报错，并参与切片 3 的多错误恢复。**方法签名不一致**在 `parse_impl` 收集方法时记下 impl 实际写的返回类型与参数个数（`ImplMethod` 增 `ret` / `nparams` / `line`），再与 trait 的 `Method` 比对：参数个数不同、或返回类型（忽略空白）不同即 `signature mismatch` **告警**（不改变退出码；impl 省略返回类型时视为沿用 trait，与发射行为一致）。告警沿用泄漏警告的同一条通道（`Warn` 增 `kind` / `sname` / `msg`），`--diagnostics=json` 新增 `signature_mismatch` 条目，**leak 条目的字段与形状保持不变**。**Phase 4 四个切片全部完成**；版本于 2026-10-17 bump 到 **v0.4.0**（冻结期一次性例外，用户授权，全量 golden 已按新版本重生成）。
- **验证（2026-10-16，切片 4）**：重复 trait / struct 各报 1 错 + 摘要 + 退出 1 + 无产物；同名 struct 分处两个 namespace 不误报且产物可运行；返回类型与参数个数不一致各产生 1 条 warning、退出 0、产物存在；json 与 `--diagnostics=json` 下的 leak 输出均不变。**selfhost 自编译零告警**。`check-archive.sh` 0 退化（designed **16 pass**，新增 `dup_trait` / `dup_struct` / `sig_mismatch` / `sig_mismatch_json`）；`check-goldens.sh` 25/25 ×3 + 不动点 2/2；`check-m2a.sh` / `ct-tour.sh` 退出 0；`./test/run.sh` 115/115；手工三件套通过。

### 重构记录（2026-10-17）：状态归位（SH-2 收口）

`selfhost/l2/**` 的文件作用域 static 从 **52 降到 11**，业务状态全部归属对象（**纯重构，产物逐字节不变**）：`sym` 从 32 个方法的参数表移进 `Pipe`（`self->sym`，方法体用局部别名保持零改动）；Drop 索引表与 `Warn` 表 + `json` 进 `SymTab`；输出缓冲（`hoist` / `ntmp` / `unit_init` / `imp_h` / `guard` / `cc` …）与扫描状态（`scope` / `nscope` / `body_*` / `cur_rettr` / `line_off` / `multi` / `ctor_pub` / `line_pub` / `emit_line` / `line_force` / `cur_line` / `line_next`）进 `Pipe`；driver 的 `-I` 根与 unit 表（9 个）进 `struct Build`。**剩余 11 个全部是设施层 / 单例**（Phase 7 的 `g_ct_prog`、Phase 8 的 `g_pkg` 各再加一个，现为 13）：`g_src` / `g_len` / `g_path` / `g_ns`（`die` / `skip_literal` / `word_at` / `read_ident` / `find_trait` / `find_struct` 都没有接收者，且 `g_pipe` 必须在 `impl` 之后定义——vtable 依赖，无法前置）、`g_err_jmp` / `g_guarded` / `g_nerrors` / `g_err_pos`（`die` 与 `compile_range` 的恢复协议）、`g_sym` / `g_pipe` / `g_build`（单例）。每片都跑了 `bash selfhost/check-all.sh`（六道硬关卡全绿）且产物逐字节不变。详见 [issues/selfhost/unowned-state-sym-param.md](../../issues/selfhost/unowned-state-sym-param.md)。

### Phase 5：新增特性（原 2.4）

- **AutoDrop**：被标记的变量在作用域结束时自动 `drop()`（不 `free`，只释放其持有的资源）。
- **路径敏感泄漏分析**：分析所有 `return` 路径，标出「某些路径上未释放」。
- **目录 = namespace 强制绑定**。
- **前置约束（2026-10-17 审查记录）**：`MAX_FUNCS`（64，**计入所有顶层 plain-C 签名，`static` 也算**）余量只剩 1；Phase 5 的新逻辑**必须**写进 `impl` 块（impl 方法不计数），并注意 `MAX_METHOD`（32）——把方法放进 `PipeOps` / `RewriteOps` 对应的一半。**不得**为扩容改 `ctc.c` 的 `MAX_*`（冻结期明令禁止）。
- **出口**：**设计先行 → 冻结 → 新用例 → `run.sh` 全绿**；明确**不追求** byte-identical（无 oracle 可对）。此处同时收口阶梯 **M6**。
- **设计（2026-10-17，已冻结）**：实现层面的设计、发射形状、v1 限制、测试切片与 **D9–D14** 决策表见 [design/phase5.md](design/phase5.md)。D9–D14 **均取推荐项**：AutoDrop 用 `own` 前缀；释放动作 = `drop` + `free` + 置空；行内 `}` / `return` 报错；路径敏感只做「条件 return」判定；目录 = namespace 取**校验式**；推进顺序 AutoDrop → 路径分析 → 目录绑定。**AST 主线不提前**，仍按原计划推进。
- **审查修复（2026-10-17，Phase 5 后复查）**：泄漏分析补上 **impl 方法体**覆盖——`emit_body` 逐行调用 `leak_observe`（赋值转移不再误报），并在方法体隐式结束处调用 `leak_check_scope`（分配未释放报确定泄漏，`own` 变量除外）。新增 designed fixture `leak_method`。同时修正文档漂移：README 的「五层 / 115 项 / 19 项断言」改为「七层 / 117 项 / 20 项断言」并补 `limits` / `cli` 两层；glossary 增 AutoDrop / `own` 与路径敏感泄漏条目；roadmap 清理「Phase 5 展望 / 仅 D6·D7 待定 / include 方案待定」等已完成残留。**验证**：designed **25 pass**、run.sh 117/117、goldens OK + 不动点、archive 0 退化、m2a/ct-tour、acceptance 19 pass / 1 pending、grammar 20/20、手工三件套通过。
- **收口（2026-10-17，切片 5.5）**：版本按阶段规范同步 bump 到 **v0.5.0**（`ctc.c` / `selfhost/l1/ctc.ct` / `core.ct` / `driver.ct` 四处一致；`test/cases/**` 与 `test/modules/**` 共 **94** 个 golden 按新版本重生成，归档 oracle 由 `same_modulo_version` 归一化），README / AGENTS / roadmap 的版本与阶段行同步。**阶梯 M6 收口，Phase 5 完成**；下一步 Phase 6。
- **进展（2026-10-17，切片 5.4：目录 = namespace）**：`build` 新增 **`--ns-root <dir>`**（缺省 = 第一个输入所在目录）；driver 逐单元算出「相对 root 的目录分量」（`src/hal/uart.ct` → `hal`）并作为 `ns_expect` 传给 `ct_compile_file`，core 在解析**最外层** `namespace` 时与声明比对，不一致即 `namespace 'X' does not match directory 'a::b'`。无声明、root 之外、路径含 `.`/`..` 的单元不校验（D13 = A：校验式，不隐式加前缀、不改变既有产物）。新增 designed fixture **2 个**：`ns_dir`（匹配的 `hal` + 无声明子目录单元，构建并运行输出 `5 6`）与 `ns_dir_mismatch`（不匹配报错、无产物）。**验证**：designed **24 pass**、`check-goldens` 25/25 ×3 + 不动点 2/2、`check-archive` 0 退化、`./test/run.sh` 117/117、`check-m2a` / `ct-tour` OK、acceptance 19 pass / 1 pending、grammar 20/20、手工三件套通过。
- **进展（2026-10-17，切片 5.3：路径敏感泄漏分析）**：`SymTabOps::leak_check_return` 落地——行首且位于函数帧顶层的 `return` 视为**无条件**（只有**对象本身**作为返回表达式时才转移所有权，其余仍 owned，由闭合 `}` 报确定泄漏）；位于块内或行中的 `return` 视为**条件**，对每个仍 owned、非 autodrop 且未被返回的变量记一条 **kind = 2** 警告（每个对象只报一次，`path_warned` 去重，作用域闭合不再重复报）。文本：`warning: potential leak: '<var>' (<Type>*) may leak on a return path (line <n>)`；JSON：`"type":"potential_leak"` + `"message":"may leak on a return path"` + `"path_line":<n>`。旧的 `leak_observe` 不再在 `return` 行清标记（否则条件返回会掩盖泄漏），只保留赋值逃逸判定。新增 designed fixture **2 个**：`leak_path`（文本，含「无条件 `return r;` 转移所有权不告警」对照）与 `leak_path_json`（JSON 形状）。**验证**：designed **22 pass**、`check-goldens` 25/25 ×3 + 不动点 2/2、`check-archive` 0 退化、`./test/run.sh` 117/117、`check-m2a` / `ct-tour` OK、acceptance 19 pass / 1 pending、grammar 20/20、手工三件套通过。
- **进展（2026-10-17，切片 5.1/5.2：AutoDrop）**：`own` 已在 `selfhost/l2/**` 落地。`Var` 增 `autodrop`；`SymTabOps::autodrop_observe` 在重新赋值 / 逃逸 / 返回（只认 `return` 之后的表达式）时取消标记；`RewriteOps::emit_drops` + `autodrop_before` 经 **hoist** 在行首 `}` / `return` 前注入 `if (p) { T_Drop_drop(p); free(p); p = 0; }`（声明逆序、置空防重放），impl 方法体顶层在 `emit_body` 尾部补发（`Pipe` 增 `in_body` 区分文件作用域）。硬诊断：文件作用域、数组、非指针、无 `malloc`/`calloc` 初始化、无 `Drop` 类型、行内 `}` / `return` —— 全部编译期报错，**绝不静默跳过**。新增 4 个 designed fixture：`autodrop`（Drop 体打印，证明嵌套块、独立块与 impl 体尾部三处释放真的执行）与 `autodrop_nodrop` / `autodrop_layout` / `autodrop_scope`（三条硬诊断）。**验证**：designed **20 pass**、`check-goldens` 25/25 ×3 + 不动点 2/2、`check-archive` 0 退化、`./test/run.sh` **117/117**、`check-all` 六门全绿、acceptance 19 pass / 1 pending、grammar **20/20**、手工三件套通过。

**需用户先定位、暂不排期**：是否引入**类型检查**（若引入，编译器性质改变，需要 AST 而非逐行扫描）；**泛型结构体**已排期 Phase 29（[history/design/phase29.md](../history/design/phase29.md)，含内置 `Vec`/`Map`），泛型**函数**已在 Phase 26 落地（见 `v0.26.0` 行），**参数化 trait** 仍待定；是否要保证**生成物可读性**的硬指标（最大嵌套缩进、命名长度上限）。

### Phase 6：生态与扩展（原 Phase 3）

- **生态绑定**：`map` + 反向映射表（经 D8 移出自举主线；落定时与官方 bindings 清单一并定案；**2026-10-19 由 Phase 11 解冻并落地 11.1**）。
- **方言系统（Dialect）**：写在注释里的领域专用语法，由编译器之外的展开器脚本转成纯 CT，`ctc` 全程零感知。设计已定型，**排期在本阶段**（2026-10-13 用户确认；排期口径随 2026-10-14 相位重排更新）——排序选择而非技术依赖，展开器是外部脚本、不与自举耦合。与 [AGENTS.md](../../AGENTS.md) §2 的三处边界冲突**已在 Phase 6.6 修订**（展开器留在仓库外、`ctc` 零感知；仓库内只允许在 `examples/**` / `test/**` 下携带演示 / 测试用方言插件；包管理分发方言仍不在本阶段）。详见 [design/dialect.md](design/dialect.md)（设计草案，未实现）。
- **构建**：增量编译缓存、跨函数泄漏分析、多目标编译。
- **设计（2026-10-17，已冻结）**：切片顺序、6.1 的 `--emit-map` JSON 形状、缓存键、多目标口径、`map` / 方言的边界处理与 **D15–D20** 决策表见 [design/phase6.md](design/phase6.md)。顺序：反向映射表 → 调用图/跨函数分析 → 增量缓存 → 多目标 → `map`（等 bindings）→ 方言（仓库外展开器）。
- **切片进展**：**6.1 反向映射表已落地**（`--emit-map <file|->`，`test/modules/map/` 钉住 JSON 形状；trait / struct / function / impl 方法与 `Drop` 生成符号全部可反查；`build` 模式只写文件，且由最后一个单元落盘）。**6.2 调用图与跨函数所有权已落地**（`calls` 段记录直接调用边；`ret_owned` 事实让 `T *q = f();` 继承分配并参与泄漏分析，`test/modules/leak_call/` 钉正/负例）。**6.3 增量编译缓存已落地**（`build` 按单元在 `<outdir>/.ctcache/<unit>.key` 记键，键一致且 `.c/.h` 在盘即跳过重生成；改动传播按 `order` 前缀 + 依赖闭包，`ct-tour.sh` 第 8 步钉「二次构建命中 / 触源失效」）。**6.4 多目标编译已落地**（`--std=c99`（默认）/ `--std=gnu99`，暂无可差异发射点，故只落 CLI 与 `cc` 建议命令里的 `-std=`；`test/modules/std_default|std_gnu|std_bad/` 钉正/负例）。**6.5 `map` 仅做设计冻结**（`map trait T for instance x` 的实例语义不落实现，等官方 bindings 清单；D19）。**6.6 方言系统已落地**（展开器在仓库外、`ctc` 零感知；AGENTS §2 豁免与 §6「八层覆盖」已同步；演示 `examples/07_dialect/` + `test/run.sh` 的 `dialect` 层：展开 → `ctc` → `cc` → 运行 → 比对，并断言未展开的源不可直接编译；**编译器与 CT 线零改动**）。**Phase 6 收口，版本 bump 至 v0.6.0**。

### Phase 7：工具链形态（单入口 `ct`）

- **落地内容**：一个 `ct` 命令承载全部功能，靠子命令区分——`ct compile`（即现有编译能力）/ `ct build` / `ct get` / `ct install`；按 `argv[0]` 分派，`ctc` 作为软链或副本保留为**兼容别名**（同 busybox 的做法）。设计已冻结（见「已定的设计决策 · 工具链形态」），**本阶段只差落地**。
- **出口**：`ct compile` 可用，既有 `ctc …` 调用不失效，生成物 banner 写 `ct`；命令的调用写法保持向后兼容（`ctc <file>` 仍可用），不做全量替换。
- **依赖**：`ct build` 属 Phase 2（多文件），故本阶段排在其后；`ct get` / `ct install` 依赖包管理器 `ct-pkg`（已定名，见「决策待定项」）。
- **风险**：命令改名会波及 README、脚本与全部既有文档里的 `ctc` 用法，必须一次性替换并复核。
- **进展（2026-10-17，切片 7.1）**：L2 的 `main` 按 `argv[0]` 识别身份——basename 为 `ct` 时以 `ct` 身份运行（`-v` / usage 打印 `ct`），其余名字（`ctc` 别名、关卡里的 `ctc-l2`）保持 `ctc` 身份，既有断言不动。`ct compile` 与默认子命令 `ct <file>` 都与 L0 输出逐字节一致；`selfhost/ct-tour.sh` 新增第 7 步钉住这些行为。
  - **banner 已改名（切片 7.3）**：旧清单第 3 条（`Generated by ctc` → `Generated by ct`）原先因 L0/L1 冻结而推迟；2026-10-17 经用户显式授权**一次性解冻两层**后落地：三层 banner 同步改为 `Generated by ct v<版本>`，`re-run ctc` 改为 `re-run ct`，map JSON 的 `compiler` 字段改为 `ct v<版本>`，并重生成全部 golden。归档 oracle 仍写 `ctc`，由 `check-archive.sh` 的 `same_modulo_version` 归一化兼容。
  - **安装形态（切片 7.2）**：不引入构建系统或部署脚本；把 L2 二进制命名为 `ct`、用 `ln -s ct ctc` 提供别名即可。已在 [README](../../README.md)「单入口 `ct` 的构建与安装」小节记明 L0 → L1 → L2 的完整命令。
- **收口（切片 7.4，2026-10-17）**：Phase 7 的三项出口全部达成——`ct compile` 可用、`ctc …` 调用不失效、生成物 banner 写 `ct`。按「版本 ↔ phase」规范 bump 到 **v0.7.0**：四处 `CTC_VERSION` 同步、101 个 golden 重生成（逐文件仅版本 token 变化）。**未落地的仅是 `ct get` / `ct install`**：它们依赖包管理器 `ct-pkg`（已定名，见「包管理器的命名」），不作为本阶段出口判据（**Phase 8 已落地**）。
- **诊断前缀保持 `ctc:`**：驱动层 37 处 `ctc:` 前缀不随 `argv[0]` 变化（`-v` / usage 变、诊断前缀不变）。理由：`core.ct` 要用到身份就得新增 `pub` 包装器，而 `MAX_FUNCS` 余量已近乎为零；保持不变也避免移动既有日志与断言。README 已写明该约定。

自举的目录结构、分层规则（L0/L1/L2）与构建流程见 [design/bootstrap.md](design/bootstrap.md)。

### Phase 11：`map` 构造（新增；D19 解除）

- **背景**：`map` 原在 Phase 6.5 **仅设计冻结**（D19：等官方 bindings 清单再实现）。2026-10-19 用户确认把 `map` 立为 **Phase 11**，入口语法 `map trait T for instance x { m() → CALL; }`——把 trait 方法绑定到某个**已声明的全局实例**上的具体调用；先落 **ct-ast** 主线（L0 / L1 / L2 一律不动）。语义与产物命名见 [language-spec](../language-spec.md) §4.10。
- **切片**：
  - **11.1（已落地，2026-10-19）**：解析 `map` 构造（`instance` 必须是已声明的全局变量、trait 已定义、绑定方法与参数个数须匹配、`CALL` 只接受受限子集）＋ 发射实例级包装函数 `<inst>_<Trait>_<method>`（首参 `void *self`，体内 `(void)self;`）与 `<inst>_<Trait>_vtable`（指定初始化）＋ `--emit-map` JSON 新增 `maps` 字段。正向 fixture `test/ast/13_map_instance/`，5 条负例进 `test/ast/errors/`，`check-ast.sh` 新增 map 小节（wrapper/vtable、maps JSON、`MAX_MAPS` 上限）。
  - **11.2（已落地，2026-10-19）**：把映射实例接入派发（运行时效果）——在 `maybe_box` 里识别「被 `map` 绑定的全局实例」，装箱时使用**实例级** vtable（`Controller c = uart1;` → `(struct Controller_iface){ (void *)&uart1, &uart1_Controller_vtable }`），即便其 struct 未 `use` 该 trait；此后经 `c.vt->send(c.self, …)` 派发到包装函数。正向 fixture `test/ast/14_map_dispatch/`（端到端运行输出 `7`），`check-ast.sh` 增加派发断言。本切片**不新增语法**，故未加负例。
  - **11.3（已落地，2026-10-19）**：`map` 加固——绑定必须**完整**（覆盖 trait 的每个方法；漏绑会让 vtable 留空指针槽，调用即崩溃）且**唯一**（重复绑定会给同一方法发射两份同名包装函数，即 C 重定义）；CALL 实参子集放宽为「数字 / 字符串字面量、可见名字（绑定形参、本 map 的实例、此前已声明的变量）、以实例为根的成员路径 `x.f` / `x->f`（可带 `&`）」。正向 fixture `test/ast/15_map_args/`（`&<另一全局>` + 实例成员路径，端到端输出 `12`），负例 `map_partial` / `map_dup` / `map_bad_path` 进 `test/ast/errors/`，`check-ast.sh` 增加完整性断言。仍未新增语法关键字，L0 / L2 依旧不认识 `map`。
- **出口**：设计冻结 + 新用例全绿；**收口（2026-10-19）**：版本按阶段规范 bump 到 **v0.11.0**（`ctc.c` / `selfhost/l1/ctc.ct` / `selfhost/l2/{core,driver}.ct` / `selfhost/ct-ast/main.ct` 五处一致；`test/cases/**` 50 + `test/modules/**` 53 共 103 个 golden 按新版本重生成，仅版本 token 变化；归档 oracle 由 `same_modulo_version` 归一化），README / AGENTS / roadmap 的版本与阶段行同步。**11.3 加固**在其后落地（见上），并以 **patch bump 到 v0.11.1** 收口：`CTC_VERSION` 五处同步，全量 golden 按新版本重生成（仅版本 token 变化），README / AGENTS / roadmap 的版本与阶段行同步。

### Phase 12：生态扩展（新增：官方 bindings + 方言深化）

- **背景（2026-10-19 用户确认）**：Phase 11 落地 `map` 后，CT 已具备「把 trait 方法绑定到已声明的全局实例」的底座；本阶段把它用于**消费既有 C 库**——以**声明式 binding**（直通 `#include` ＋ 镜像 `trait` / `struct` ＋ 已声明全局实例 ＋ `map`）**零新增语言特性**地对接 C 库，同时**深化方言系统**（多方言并存 + 作者指南）。设计冻结见 [design/phase12.md](design/phase12.md)（D46–D52）。
- **切片**（全部落地）：
  - **12.1 binding 形态 + 首个 binding**：新建顶层 `bindings/**`，首个为**仓库内假 HAL**（`bindings/mock-hal/`，自带假 HAL 头与实现，零外部依赖）。**已落地（2026-10-19）**：`bindings/mock-hal/` 已建（`mock_hal.h` 不透明句柄 + `mock_hal_impl.c` + binding `uart.ct` + 消费方 `demo.ct` + `demo.expected.out`），`check-ast.sh` 新增 bindings 小节（端到端 build → `cc` → 运行 → 比对）。前置缺陷已修：**`map` 的包装函数与 vtable 在 `build`（多文件）模式下从未发射**，导致引用未定义 vtable；现按「声明该 map 的单元」发射（`emit_maps(u)`，compile 模式传 `-1` 保持原行为）。
  - **12.2 binding 规约文档**：`bindings/README.md` 记配方 / 命名 / self-contained 与跨单元限制。**已落地（2026-10-19）**：中英双语，含五步配方、目录与命名（binding 单元名不得与库头同名）、不透明句柄 + 镜像布局的 ABI 契约、跨单元限制、构建与测试命令、新增 binding 检查清单。
  - **12.3 方言深化**：同一 `.ct` 内多 dialect 块路由演示 + [dialect.md](design/dialect.md) 的作者指南。**已落地（2026-10-19）**：`examples/07_dialect/registry.ct` 同时含 `register/map` 与新增的 `fsm/state` 两个块，新增插件 `ct-dialects/fsm-state.sh`；确立「插件只处理自己的标记、其余逐字节透传」的归属规则，`test/run.sh` 的 `dialect` 层与 `check-ast.sh` 的语料段改为按文件内首次出现顺序**依次**路由全部方言（原实现只取第一个标记）；[dialect.md](design/dialect.md) §4.5 新增作者指南（中英）。
  - **12.4 加固与收口**：`check-all.sh` 全绿。**已落地（2026-10-19）**：`CTC_VERSION` 五处同步 bump 到 **v0.12.0**（经用户授权），全量 golden 重生成（仅版本 token 变化），`check-all.sh` 八道硬关卡全绿。
- **规约前置**：`bindings/**` 需先修订 [AGENTS.md](../../AGENTS.md) §2（文件所有权表 + 硬性边界）——binding 只声明外部库符号，**不 vendored、不下载**、**不成为编译器构建步骤**；L0 / L1 / L2 一律不动，新代码只落 ct-ast。
- **出口**：✅ 达成（2026-10-19）——设计冻结 + 新用例全绿；**收口 bump v0.12.0**（冻结期例外，已获用户授权）。

### Phase 12 后续修复（v0.12.0 之后，仅 ct-ast）

- **能力补齐**：把 `test/acceptance/run.sh` 的默认编译器从 L2 改回**安装入口 ct-ast**（10.7 起本应如此）后，暴露了 6 项 L2 能过而 ct-ast 不能过的构造，已全部修复：接口**值/指针字段**在构造式里装箱；接口指针变量/参数（`Expr *xs`）按元素派发；**结构体类型数组字段**逐元素写 vptr；函数**原型**保留数组参数维度。`ast_spike`（本项目自己的目标程序）随之通过。
- **容量**：`ParseOps` 拆出 `TypeOps`（类型查询与装箱）腾出方法位；用户可见上限整体抬高（`MAX_NODES` 65536、`MAX_FUNCS` 256、`MAX_TRAITS` 64 等，见 [language-spec](../language-spec.md) §7）。策略仍是「固定上限 + 越界硬报错」，未改动态分配；ct-ast 自编现在需要超过 32768 个节点，抬高 `MAX_NODES` 是自举的前提。
- **验收**：`p18_struct_array_field` 晋升 `test/acceptance/run.sh` 基线；`test/ast/{16_iface_field_box,17_param_array,18_struct_array_field}` 纳入 `check-ast.sh` 硬关卡。
- **模块语法（2026-10-20，用户确认）**：namespace 增加**文件级**写法 `namespace A::B;`——前缀生效到单元结束、没有闭合花括号，模块层逐单元重置；**块式在 ct-ast 已禁止**（报 `a namespace is file-scoped`，只有 L2 为归档棘轮的块式 fixture 保留解析）。`import` 增加**按名引入**：路径最后一段是单元文件名；无 `as` 时整条路径就是单元，若文件名以大写开头（文件按主类型命名），该主类型同时以短名可用；`import a::b::C::D as E;` 才是按名引入——`a::b::C` 是单元、`D` 是导出名、`E` 是本文件的写法。发射时展开为既有的 `<ns>_<Name>`，不新增命名规则。别名只作用于源码、不进产物；同名绑定到不同全名直接报错。L2 与 ct-ast 同步实现（**只加语法能力，L2 自身源码仍用旧写法**），新增正例 `test/modules/alias/`（分号式 namespace + `import app::model::Point as Point;`），`check-ast.sh` 127 项全绿。随后 ct-ast 全树迁移到这两条语法（17 个文件改分号式、跨单元引用改短名并补 `import`），并把 14 个单元文件重命名为主类型名（`Parser.h.ct`、`Symbols.h.ct`、`Arena.h.ct`…），`import runtime::arena::Arena;` 由此成立；迁移暴露出两处必需配套：L2 行重写器新增 `expand_aliases`（cast / `sizeof` 里的短名必须展开成落库 C 名），`MAX_IMPORTS` 16→32（逐类型 import 最多 22 条）并修掉 `unit.h.ct` 中与常量不同步的 `dep[16]`/`depu[16]`（超过 16 个依赖会越界，自编时在 `cache_order` 段错误）。
- **`pub` 函数按命名空间 mangle（2026-10-21，用户确认）**：`namespace` 里的 `pub` 函数不再脱离命名空间，而是发射为 `<ns>_<name>`——`namespace runtime::arena;` 里的 `pub struct Arena *arena_get(void);` 落成 `runtime_arena_arena_get`，**函数与类型此后遵循同一条规则**；`static` 辅助函数与根作用域函数保持裸名，调用点跟着定义走。符号表改按 **C 拼写**建键，于是两个命名空间可以各自导出同名函数（`test/modules/ns_funcs/`：`a::size` 与 `b::size` 并存，各自单元内的裸调用解析回本命名空间）。裸调用按「本单元命名空间 → 根 → 全程序唯一同名」三级解析；第三级是迁移期的桥（既有语料里一个命名空间的辅助函数被另一命名空间调用），一旦两个命名空间导出同名函数它必然歧义，此时硬报错（`test/modules/ns_fn_ambiguous/`），等限定调用落地后改写。`--emit-map` 与调用图仍记源码短名（对外可见的名字不变），只有发射到 C 的拼写加前缀。L2 同步实现（`find_cfunc` / `resolve_func`，`transform_calls` 与四处按名探测改走解析），`test/modules/ns_dir` 的 golden 因 `ping` → `hal_ping` 重生成（3 行）。**已知缺口**：限定调用 `a::b::get()` 仍按旧规则丢路径（当时函数不 mangle），两个命名空间导出同名函数时会误报歧义——由下一条解决。
- **限定调用 `Qual::fn(...)`（2026-10-21，用户确认）**：`Qual` 既可以是命名空间路径（`app::size(p)` → `app_size`），也可以是**类型名**（`Point::size(p)`：`Point` 的 C 名是 `app_Point`，去掉末段得到前缀 `app_`，于是命中 `app_size`）——后者是 OO 里「类型上的函数」的基本写法。第一版**只做调用**：定义仍写普通 `pub int size(Point p);`，不引入声明形式。`Qual` 解析为类型时命名空间是确定的，找不到函数即硬报错（`test/modules/ns_qual_missing/`）；解析为命名空间路径时 ct-ast 同样报错，L2 的行重写器没有命名空间表，退回「丢路径」的旧行为（只影响 L2 的错误质量）。正例 `test/modules/ns_qual/`（`Point::size`、`app::size`、裸 `scaled` 三者输出一致）。随后 ct-ast 全树把**跨命名空间的裸调用**（各单元的 `pub` 门面，如 `frontend::parse::ct_parse_program`、`backend::emit::ct_emit_unit`、`tool::diag::ct_sem_error`）一律改成限定写法，「全程序唯一同名」的第三级回退只留给迁移期语料；落库 C 名不变，golden 未动。
- **退役「全程序唯一同名」回退（2026-10-21，仅 ct-ast）**：ct-ast 的 `resolve_func` 现在只查**本单元命名空间 → 根**，跨命名空间的裸调用一律硬报错（`that function lives in another namespace and needs a qualified call`，新负例 `test/modules/ns_bare_call/`）——调用目标从此静态可判定，不再依赖「全程序恰好只有一个同名函数」这种重构时会静默改变绑定的规则。两个命名空间导出同名函数时的歧义诊断保留（`test/modules/ns_fn_ambiguous/` 仍逐字匹配）。ct-ast 自身在片 3 的迁移后已不依赖该回退（自编不动点仍通过），此前实验（收紧后跑 `check-ast.sh`）只有 5 个 fixture 的裸调用失败，已改写成限定写法：`ns_dir`（`hal::ping` / `plain::twice`）、`alias`（`app::scaled`）、`ns_funcs`（`a::one` / `b::two`）、`ns_qual`（`app::scaled`），`test/modules/ns_funcs/main.expected.c` 随注释一同重生成。**L2 不跟随**：它是冻结的回归 oracle，保留回退行为，因此 `ns_bare_call` 只进 `check-ast.sh`（无 `build.args`，不进归档棘轮）。

- **v0.13.0（2026-10-31，用户授权的一次 bump）**：ct-ast 的 C 子集补齐（第二十一至二十八批）——长初始化器（4 KiB/16 KiB 上限 + 字符串池）、变参函数指针、逗号表达式（语句 / `for` 首句 / 步进 / 括号内取值）、头文件里的类型名（声明、转换、`sizeof`）、表达式里的赋值（括号与条件，`own` 目标拒绝）、前缀 `++` / `--`；并把「ct-ast 编 `selfhost/l0/ctc.c` → 产物可编译 → 与 25 个 L0 golden 逐字节一致 → 跑通示例」固化为 `check-ast.sh` 的一节关卡。`CTC_VERSION` 五处同步 bump，`test/cases/**`（50 个文件）与三份 map golden 重生成（**仅版本 token 变化**）；clang 与 GCC 16 下九关全绿。
- **第二十九批（2026-10-31，C11 三件套）**：`_Alignas` / `_Alignof` / `_Generic` 按「能透传就不建 AST」落地——`_Alignas` 进类型拼写（全局 / 局部 / 字段 / 参数 / `typedef` 五个入口自动生效），`_Alignof` 复用 `sizeof` 节点（`aux = 2`），`_Generic` 整段捕获进字符串池、由 C 编译器选臂；新增 `test/ast/53_c11_align_generic` 与三条形状负例，language-spec §4.35。
- **第三十批（2026-10-31，`.h.ct` 规则）**：仅 ct-ast——普通 `.ct` 不再写 `.h` 且**不可被 `import`**（`import` 只解析 `.h.ct`，命中普通 `.ct` 报 `only a .h.ct unit can be imported: rename 'x.ct' to 'x.h.ct'`），compile 模式同理；实现单元的 `.c` 自包含（`pub` 类型本地发射），缓存命中按 `need_h`。被导入单元统一改名（ct-ast 自身 3 个、bindings 1 个、`test/modules/**` 27 个）。L2 保持附加式（归档 oracle 依赖），登记为已知分叉。
- **第三十一批（2026-10-31，`__attribute__`）**：GNU `__attribute__((…))` 按「声明尾部透传」接受——函数声明/定义、形参、字段、全局、`typedef` 别名之后，以及 `struct` / `union` / `enum` 定义体之后；整段原文进字符串池并在同一尾部位置重新发射（连续多个组一起捕获），typedef 记录类型统一发射在别名之前。新增 `test/ast/54_attribute` 与两条形状负例（`unterminated __attribute__` / `duplicate __attribute__ on one declaration`），language-spec §4.36；至此 §4 的 C 形式没有已知缺口。
- **第三十二批（2026-10-31，C 兼容性收尾）**：整数字面量后缀（`U` / `L` / `UL` / `LL` / `ULL`，大小写与顺序不限，十进制 / 十六进制 / 八进制同路径）由词法器收集、解析器校验并规范化为「先 `U` 后 `L`」后存进 `N_NUM.text`，发射时原样带出；非法组合报 `an integer suffix may be U, L or LL`。`static_assert` 作为 `_Static_assert` 的别名接受，生成物统一写 `_Static_assert`。`add_func` 的返回类型改为「先声明者胜」，`_Noreturn void f(void);` 之后的 `void f(void) {}` 不再把它抹掉。`__restrict` / `__restrict__` 进入类型词表。新增 `test/ast/55_c_compat` 与两条后缀负例，language-spec §4.37；`check-ast.sh` 300 passed、`check-warnings.sh` 145 ok、`check-all.sh` 九关全绿。
- **第三十三批（2026-10-31，真实头文件兼容）**：`_Atomic(type)`（含裸 `_Atomic`）进入类型拼写，`sizeof` / cast 的类型探测也认它；`_Alignas(…)` 可以写在存储类之前（文件与块作用域都接受，发射统一为 `static _Alignas ( 16 ) int g;`）；GNU 属性可以写在声明符之前（全局、函数原型 / 定义、局部变量），局部变量也接受尾部属性。`attr_pool` 从 `ParseOps` 搬到 `SupportOps`（零新增方法，impl 预算 256 恰好到顶）。新诊断：`unterminated _Atomic`、`an attribute must prefix a declaration`、`duplicate _Alignas on one declaration`。新增 `test/ast/56_header_compat` 与四条形状负例，language-spec §4.38；`check-ast.sh` 309 passed、`check-warnings.sh` 146 ok、`check-all.sh` 九关全绿。容量策略同批定为 A（见 [design/next-decisions.md](design/next-decisions.md)）。
- **第三十四批（2026-10-31，增量构建的依赖闭包）**：修正 L2 `build` 的重编译集合——旧规则是「首个脏单元之前的前缀 + 之后的脏单元」，但依赖优先序并不保证干净依赖都在前缀里；顺序 `A(脏) → B(干净) → C(脏，依赖 A 与 B)` 会跳过 B，C 重新生成时把导入类型写回源名（`struct Cache`），产物无法编译。现在先算 `need = dirty`，再从 `order` 末尾向前把每个 `need` 单元的依赖标为 `need`，发射循环只看 `need`；干净依赖因此可能被重编译，但产物与缓存键逐字节不变。ct-ast 不受影响（它先解析全部单元）。新增 `check-ast.sh` 的两条断言（三单元工程：冷构建解析导入类型、改 A 后重建仍解析且产物零告警）；`check-ast.sh` 311 passed、`check-warnings.sh` 146 ok、`check-all.sh` 九关全绿。L2 属冻结层，按 bug 修复处理，生成物与 `CTC_VERSION` 均未变。
- **第三十五批（2026-10-31，设计模式覆盖）**：不新增任何语言特性。用现有的 `trait` / `impl`、接口值 / 数组 / 字段、组合、`namespace` / `import`、`map` 与 `own` / `Drop` 写出六个可运行的模式程序（Strategy、Observer、Decorator、Composite、Factory Method、Template Method，见 `test/patterns/**`），由 `check-ast.sh` 新增的「design patterns」一节编译、零告警构建、运行并比对输出；[docs/patterns.md](../patterns.md) 给出模式 → 机制的对照、无继承 / 无泛型时的三条替换规则与其余 GoF 模式的落法。继承、泛型、类型检查、完整可见性修饰符保持 §8 的「明确不支持」——这是设计决定，不是待办。`check-ast.sh` 317 passed、`check-warnings.sh` 146 ok、`check-all.sh` 九关全绿；未改编译器、生成物与 `CTC_VERSION`。
- **第三十六批（2026-10-31，trait 默认方法）**：trait 方法可直接带默认体（`{ … }`；`;` 仍是抽象），impl 只写抽象方法；全 default 的 trait 只写 `use`、不需要 `impl`（外来类型写空 `impl T for S { }`，D-3）。默认体按 (struct, trait) 各展开一份，函数名与 vtable 槽沿用 `<S>_<T>_<m>`，派发沿用既有规则；impl 显式方法覆盖默认体。诊断：默认体成环（没有抽象叶子）报 `trait 'T' has no non-default method to break the cycle`；默认体在某个 struct 上不成立报 `trait T::m (declared at <path>:<line>) cannot be expanded for struct S: <reason>`，指回 trait 声明。新增正例 `test/ast/57_trait_default`（混合 + 覆盖）与 `58_trait_all_default`（仅 `use`），负例 `default_cycle` / `abstract_missing` / `default_bad_field`；language-spec §4.39。同批按用户授权把 `CTC_VERSION` 五处同步 bump 到 **v0.14.0**（L0/L1/L2 只动这一行），`test/cases/**` 50 个 golden 与 21 个含 banner 的 `test/modules/**` golden 重生成（仅版本 token 变化）；`check-ast.sh` 359 passed、`check-warnings.sh` 154 ok、`check-all.sh` 九关全绿。
- **第三十八批（2026-10-31，已落地）**：`.m.ct` 零成本静态映射——新增编译期映射单元（不产任何 `.c`/`.h`）、静态 trait（无 `_iface`/`_vtable`）、命名空间静态调用 `host::Trait.method(…)` 与类型宿主 `map trait T for type char *`；调用点按 recipe 直接替换成裸 C 调用（`&p` 用 C99 compound literal），prologue 展开进消费者 `.c`，跨单元同样零 wrapper。正例 `test/modules/map_unit`（命名空间 + 类型宿主）、`map_unit_type`（数组 decay / 指针参数 / compound literal / 未用接收者）与 `map_unit_cross`（`.h.ct` 与 `.ct` 共用一份映射）；`check-ast.sh` 增加零产物、内联文本、`cc` 行、`--emit-map` 字段与 25 条负例精确消息断言。既有动态 `map` 产物逐字节不变；同批按用户授权把 `CTC_VERSION` 五处同步 bump 到 **v0.15.0**，`test/cases/**` 与 `test/modules/**` golden 仅版本 token 变化。规格见 [design/batch38-map-unit/spec.md](design/batch38-map-unit/spec.md)；附录记录了「C 库全量映射」的分层边界（`.m.ct` → C shim → `.h.ct` → 不支持）。节点池从 65536 抬到 131072（自编实测 69199 节点，属容量而非语言上限）。
- **v0.15.1（2026-10-31，用户授权）**：修复 recipe 的 `sizeof` 两处缺陷（空白覆盖 `prev` 导致 `sizeof p` 被计为一次求值、实参副作用丢失与重复求值误报；`sizeof(p)` 的静默错义改为编译期拒绝），并把这两条与「普通单元里的 `for type`」固化为负例；新增 `test/modules/map_unit_chain` 与 warm / touch 断言覆盖传递 `.m.ct` import 及传递依赖缓存；修正 language-spec 的 `MAX_NODES` 文档漂移（65536 → 131072）与第三十八批 checklist。`CTC_VERSION` 五处同步，golden 仅版本 token 变化。
- **第三十九批（2026-10-31，v0.15.1 之后，未 bump 版本）**：`.m.ct` 的**伴随 C shim**——映射单元可用同目录同名的 `<base>.shim.h` / `<base>.shim.c` 承接 recipe 写不出的形状（宏 / 语句宏、`errno` 等全局量、需要转换的调用、变参前缀转发、无 userdata 回调）。编译器只为 `.m.ct` 探测 shim；消费者的生成 `.c` 自动 `#include "<base>.shim.h"`（整行去重、先于该单元 prologue），`ct build` 的 `cc` 行自动加 `-I <shim 目录>` 并把存在的 `.shim.c` 列为源文件；shim 两文件的 `mtime.size` 折叠进映射单元缓存 key，改动即重建消费者；只有 `.shim.c` 没有 `.shim.h` 报 `a shim source needs a matching .shim.h`。正例 `test/modules/map_unit_shim`（头文件 + 源文件 + 缓存 warm/touch）与 `bindings/posix-socket/`（`socketpair` / `write` / `read` / `errno` 的头文件式 shim，真实库 demo）；`check-warnings.sh` 改为从 `cc` 行提取 `-I` 对并覆盖 `bindings/*/demo.ct`。规格见 [design/batch39-shim-layer/spec.md](design/batch39-shim-layer/spec.md)；`CTC_VERSION` 与既有 golden 均未变。
- **v0.16.0（2026-11-01，用户授权）**：`borrow` + `Handback`（仅 ct-ast）——`borrow` 作为上下文关键字接入参数注解与语句行首声明，`Handback` 为内建 trait（照 `Drop` 处理，只发 `<S>_Handback_handback`）；声明作用域闭合与**每个** `return` 之前（无位置要求，分支内 / 行内均可）按声明逆序注入 `if (c) { <S>_Handback_handback(c); c = 0; }`（归还，对象仍活着），与 `own` 共用逆序表；借用句柄重新赋值、存入 `static` / 文件作用域更长寿位置、文件作用域 `borrow` 均为编译错误（SH-35 / SH-37 / SH-34），`delete` 借用指针被拒绝。前置修复 SH-33（行首 `return` 前 AutoDrop 不注入、不置空）。正例 `test/ast/61_autodrop_return` / `62_borrow_handback`。规格见 [design/borrow.md](design/borrow.md)。`CTC_VERSION` 五处同步，`test/cases/**` 50 + `test/modules/**` 21 共 71 个 golden 仅版本 token 变化。
- **v0.16.1（2026-11-01，用户授权）**：收掉同日的代码审查 15 条（SH-34…SH-41、DOC-44…DOC-50）——`borrow` 的语义漏洞修复（文件作用域拒绝、借用句柄不可重赋值 / 不可存 `static` 或全局、`return` 按「真正移交」判定、impl 顺序不再误报、`delete` 只在可赋值实参后置空），跨单元 `Handback` 按建议只文档化不实现；文档与编辑器语法同步（新增 `ct-borrow` / `ct-borrow-param` / 内建 trait 高亮，`check-grammar.py` 31 → 33）。正例 `test/ast/59_typedef_alias_array` / `60_branch_autodrop`，`check-ast.sh` 425 → 432。`CTC_VERSION` 五处同步，golden 仅版本 token 变化。
- **v0.16.2（2026-11-02，用户授权）**：收掉 2026-11-01 第三方复核的 5 条（SH-42 / SH-44 / DOC-51 / DOC-52；SH-43 维持待决）——`Arena` / `Symbols` / `Parser.g_maps` / `Module.g_units` 四张超大静态表改为堆分配（`ct` 二进制 88M → 637K、`__DATA` 105MB → 589824 B）；`ct.lock` 的包摘要改 SHA-256（`sha256:<64 hex>`），旧 16 位 FNV 摘要报 `unsupported digest`，`test/pkg/run.sh` 37 项断言全绿；教程与 language-spec 的 import 后缀、L2 限域与注释保留说明同步订正。`CTC_VERSION` 五处同步，71 个 golden 仅版本 token 变化。
- **v0.16.3（2026-11-02，用户授权）**：处置 2026-11-02 复核的 5 条（SH-45 / SH-46 / SH-47 / DOC-53 / DOC-54）——SH-45 修 `return` 的求值顺序：表达式读取仍被 AutoDrop 的对象时，先物化为 `<T> __ct_retN`、再执行出口释放、最后 `return __ct_retN`（此前先释放再读取，返回的是已释放的值），新增 `test/ast/63_own_return_field`（`return b->n;`）与 `64_borrow_return_field`（`return c->fd;`）钉住「读取字段不释放后读」与「`return b;` 仍移交不释放」；SH-47 把字段上限诊断改为点名 struct 与上限（`too many fields in struct 'Big' (limit 64)`），`check-ast.sh` 断言同步（+2）；DOC-53 订正 language-spec §6.1 的重名陈述（方法签名不比对；trait/struct 重名由 ct-ast 报 `duplicate trait/struct`、L0/L2 取最先出现者）；SH-46 **不采纳**「同名跨 trait 的裸调用改为硬报错」，改为在 §4.3 记录「按 `use` 顺序取第一个、顺序即语义」为已知限制（`test/cases/06_name_collision.ct` 已钉死该输出，硬报错会破坏既有 golden 与用户既有代码）；DOC-54 在 language-spec §4.10 补单元种类表（`.ct` / `.h.ct` / `.m.ct` 的产物、可 import、可单独 build）与 import 搜索顺序（先 `.h.ct` 再 `.m.ct`，否则报 `only a .h.ct unit can be imported`），tutorial 同步。`CTC_VERSION` 五处同步，71 个 golden 仅版本 token 变化。


## 决策待定项

| 问题 | 候选 | 影响 |
| --- | --- | --- |
| `.c` 是否 `#include` 自己的 `.h` | ✅ 已定：多文件场景下 `.h.ct` 生成 `.h` + `.c`，`.c` 包含自己的头（见「文件命名约定与 `pub` 可见性」） | 越位实现时打破 Phase 0 自包含约定 |
| 位置式初始化的语义 | ✅ 已定：A. 自动追加 vptr（0.1.2） | 允许 `{ "Tom", 36 }` 写法 |
| 指针声明的处理 | ✅ 已定：修正生成（`struct Person *p`）并登记为指针，`p->m()` 重写 | 已落地于 Phase 0.1.1 / 0.1.4 |
| 工具链形态 | ✅ 已定：单入口 `ct`，`ctc` 保留为兼容别名 | 见「已定的设计决策」；**7.1–7.3 已落地**（入口身份 + 安装形态 + banner 改名），调用写法保持兼容 |
| 包管理器的名字 | ✅ 已定：`ct-pkg`（2026-10-17） | 命令层仍是 `ct get` / `ct install`；registry 与组织名需趁早占位 |
| 包管理的获取形态 | ✅ 已定（2026-10-18）：git 即 registry + 本地目录源；无 `git` 时 git 源硬报错 | 见 [design/phase8.md](design/phase8.md)（D22 / D26） |
| 容量上限策略 | ✅ 已定（2026-10-31）：A. 维持「固定上限 + 越界硬报错」；回访触发条件=真实项目 / 官方 binding 撞顶，或自举再次逼近 `MAX_NODES`。触发时先做定点抬高（B），只有「抬到多大都会撞」时才评估动态分配（C） | 见 [design/next-decisions.md](design/next-decisions.md) §1 |
| 过渡期是否冻结一切新特性 | ✅ 已定：自举（Phase 1）启动起冻结一切新的 C 侧语言特性，`ctc.c` 只接受 bug 修复（2026-10-14 相位重排） | 防止 Phase 0 历史偏差复发 |
| C 实现最终删除还是归档 | ✅ 已定（2026-10-14）：「**剥离在前**」——Phase 0.3 先把越位特性移出 `ctc.c` 并**归档为 oracle**（不销毁），Phase 2 起用 CT 逐项重做并向归档对差；`ctc.c` 剥回纯 OO 核心并**永不整体删除** | 见「Phase 0.3」「自举策略与单文件边界」 |
| 类型检查 / 泛型结构体 / 生成物可读性硬指标 | 类型检查仍待定（见 [design/phase5.md](design/phase5.md) §8 非目标）；泛型**函数**已在 Phase 26 落地（`v0.26.0`）；泛型**结构体** + 内置 `Vec`/`Map` 已排期 Phase 29（[history/design/phase29.md](../history/design/phase29.md)）；**参数化 trait** 仍待定 | 若引入类型检查，编译器性质改变，需要 AST |
