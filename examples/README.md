# examples —— 示例索引

每个目录是一份可运行的小程序，覆盖 `ct` 的一类能力。分为五组：**impl / vtable**、
**类型宿主（type host）**、**闭包**、**loop 语义**、**数组初值与泛型**。

## impl / vtable

`impl` 落在 struct 上，方法经 vtable 分派；调用点看不到指针或虚表。

| 目录 | 演示什么 | 前置条件 | 本地门禁归属 |
| --- | --- | --- | --- |
| `01_greeter` | 最小可用：一个 trait、一个 struct、一次 impl、两次调用 | 无 | `test/run.sh` + `check-ast.sh` + `check-warnings.sh` |
| `02_market` | 多个对象互调；同一 trait 在两个 struct 上给出不同实现；末尾 `Reporter all[2]` 接口值数组经 `broadcast()` 统一派发 | ct-ast（接口值数组） | `test/run.sh` + `check-ast.sh` + `check-warnings.sh` |
| `03_receivers` | receiver 可以是数组元素、指针数组元素、指针字段链 | 无 | 同上 |
| `04_rvalue` | rvalue receiver（工厂返回值直接调用），receiver 只求值一次；**链式上限一步，不是 fluent** | 无 | 同上 |
| `05_body_dispatch` | `impl` 方法体内经 vtable 的递归分派（字段链 / 参数 / 局部变量） | 无 | 同上 |
| `06_iface_field` | 接口值字段（自动装箱）与指向接口值的指针字段（`Node *node` + `w.node->show()`）并排对比 | 无 | 同上 |
| `07_dialect` | 注释里的 DSL 经 `ct-dialects/` 插件展开成纯 CT，编译器零感知 | 插件（目录内自带） | 同上（`test/run.sh` 的 dialect 层） |
| `08_map_binding` | `map trait ... for instance`：绑定一个改不动的全局实例并装箱；另带 `src/type_bridge/` 子包演示 `map ... for type` 的指针别名宿主 | ct-ast（`map`）；子包需 `ct build` 多单元 | `test/run.sh`（instance 单文件）+ `check-ast.sh` + `check-warnings.sh`（instance 单文件）+ `check-warnings.sh` 的 src-layout build 段 |
| `09_callback` | 容器回调约定：档① 手写 `(fn, env)` 对；档② `=>` 闭包字面量在 `callback_tier2.ct` | 档① 无；档② ct-ast | `test/run.sh` + `check-ast.sh` + `check-warnings.sh` |
| `json` | 纯 CT 的 JSON 读写：零分配只读视图 + 写出；取值按 kind 经 `trait` ops 对象分派 | ct-ast（`loop`） | `test/run.sh` + `check-ast.sh` + `check-warnings.sh` |
| `wave1-demo` | Wave 1 包（`hal` / `hal-posix` / `std`）合用 | 外部 ct-pkg 索引 | **仅 CI** |

## 类型宿主（type host）

`map trait ... for type <C 拼写>` 把方法直接挂到 C 类型上：无包装、无 vtable、无分配，
每个调用点在原地展开成一次普通 C 调用。键是**拼写**：`int`、`unsigned`、`unsigned int`
是三个不同的键。

`08_map_binding` 主文件用的是 `map ... for instance`，绑定的是一个实例，仍需装箱进 trait 值；
它的 `src/type_bridge/` 子包则改用 `for type FileHandle`，其中
`pub type FileHandle = struct ct_file *;` 是纯编译期别名（不发射 typedef），
消费端写 `f.read()`。下表的两个示例同样用 `for type`，调用点是普通 C 值，不存在装箱。

| 目录 | 演示什么 | 前置条件 | 本地门禁归属 |
| --- | --- | --- | --- |
| `08_map_binding/src/type_bridge` | `pub type FileHandle = struct ct_file *;` + `map ... for type FileHandle`，消费端 `f.read()` 原地展开 | ct-ast + `ct build` 多单元 | `check-warnings.sh` 的 src-layout build 段 |
| `13_builder_chain` | 宿主方法返回宿主本身，形成真正的 `b.add(1).add(2).value()` 链 | ct-ast + `ct build` 多单元 | `check-warnings.sh`（本文件新增段） |
| `14_scalar_host` | 给 `int` / `char *` / `double` / `unsigned long` 加方法，含链式调用 | ct-ast + `ct build` 多单元 | 同上 |

`08_map_binding/src`、`13`、`14` 都带 `.m.ct` 映射单元与 `import`，只能用 `ct build`
的多单元模式，因此入口放在 `examples/<dir>/src/main.ct`（三层），而不是会被单文件编译的
`examples/<dir>/*.ct`。`wave1-demo` 采用同一种 `src/` 布局。

## 闭包

闭包是 `(fn, env)` 对，`env` 是回调的首参；容器不得留存这两个词。

| 目录 | 演示什么 | 前置条件 | 本地门禁归属 |
| --- | --- | --- | --- |
| `10_closure_pipeline` | 闭包字面量 / 已声明的绑定的传参约定，配合 `loop(n)` | ct-ast | `test/run.sh` + `check-ast.sh` + `check-warnings.sh` |
| `12_closure_in_loop` | 循环体内创建闭包：按值捕获，只保留创建那一轮的变量 | ct-ast | 同上 |
| `17_static_map_closure` | 闭包字面量作为 `.m.ct` 静态映射调用的实参（Phase 25）：数组衰减成 `int *`，recipe 把 `(fn, env)` 原样传给同步 C 消费者 | ct-ast + `ct build` 多单元 | `check-warnings.sh` 的 src-layout build 段 |

`09_callback` 的档②（`callback_tier2.ct`）同样属于这一组：`=>` 闭包字面量直接填满
`(fn, env)` 两个槽，档① 的手写适配器不再需要。它单独成文件是为了让 `callback.ct`
继续在 L0 上跑。

## loop 语义

计数循环 `loop(n)` / `loop(a..b)`，以及数组的语句级迭代 `foreach (array) { … item … }`。

| 目录 | 演示什么 | 前置条件 | 本地门禁归属 |
| --- | --- | --- | --- |
| `11_loop_semantics` | `loop(n)`（0..n-1）与 `loop(a..b)`（a..b-1）：计数只求值一次，`i` 可写 | ct-ast | `test/run.sh` + `check-ast.sh` + `check-warnings.sh` |
| `20_foreach_statement` | 语句级 `foreach (array) { … item … }`（Phase 27）：隐式 `item` 按值绑定、`break` / `continue` / 块内 `return` 直通、块内闭包；与 19 的库层 `each` 对照 | ct-ast | `test/run.sh` + `check-ast.sh` + `check-warnings.sh` |

`foreach` 与 `each` 不是同一机制：`foreach` 只走**长度已知的数组**，遍历归调用方，`break` / `continue` /
`return` 都可用；`each` 是容器自己的方法（trait 或泛型自由函数），遍历归容器，回调只能折叠值、不能提前退出。
`20` 在同一个文件里两条路径并排写出，可对照。

## 数组初值与泛型

| 目录 | 演示什么 | 前置条件 | 本地门禁归属 |
| --- | --- | --- | --- |
| `15_range_init` | `0..n(<expr>)` 数组 range 初值（Phase 24）：文件作用域 `static const` 表与局部表，`$` 是下标，产物是花括号列表而非循环 | ct-ast | `test/run.sh` + `check-ast.sh` + `check-warnings.sh` |
| `16_generic_min` | 泛型函数（Phase 26）：`T larger<T>(T, T)` 以 `int` / `double` 实例化，每个实例是一份独立 `static` C 函数 | ct-ast | 同上 |
| `18_generic_string_table` | 泛型函数以 `char *` 显式实例化，在字符串表上遍历、查找、变换；闭包只作为自由函数的 `(fn, env)` 实参参与 | ct-ast | 同上 |
| `19_container_each_generic` | 容器 struct 提供 `each` 方法（trait + `impl`），方法体调用泛型 `walk<char *>`；方法路径写显式 `(fn, env)`，自由函数路径用闭包字面量并捕获 | ct-ast | 同上 |
| `21_generic_bound` | 约束泛型（Phase 28）：`sort<T: Compare>` / `largest<T: Compare>` 在模板体内调用约束方法，`Num` 与 `Word` 两个无关 struct 各得一份实例，落成 `S_Compare_vtable.cmp` 裸调用 | ct-ast | `test/run.sh` + `check-ast.sh` + `check-warnings.sh` |
| `22_foreach_map` | `foreach` 容器协议（Phase 29）：`Vec<int>` / `Vec<Point>` 绑定只读 `i` 与值拷贝 `item`，`Map<char *, int>` 按插入序给出 `item.key` / `item.value` | ct-ast | `test/run.sh` + `check-ast.sh` + `check-warnings.sh` |
| `23_generic_stack` | 用户泛型 struct（Phase 29）：`struct Stack<T>` 的裸 `T` / `T *` / `T items[N]` 三种字段，`Stack<int>` 与 `Stack<char *>` 两份布局，`impl<T> Stack<T>` 静态派发 | ct-ast | `test/run.sh` + `check-ast.sh` + `check-warnings.sh` |
| `24_vec_ops` | 内置 `Vec` 全 API（Phase 29）：`push` / `pop` / `get` / `set` / `len` / `clear` 的边界语义，`retain` / `release` 的引用计数与归零释放 | ct-ast | `test/run.sh` + `check-ast.sh` + `check-warnings.sh` |
| `25_wordcount` | 真实程序（Phase 29）：`Map<char *, int>` 词频统计，先按插入序输出，再复制条目按计数排序出报告 | ct-ast | `test/run.sh` + `check-ast.sh` + `check-warnings.sh` |
| `26_range_vec` | range 初值构造 `Vec<T>`（Phase 29 P29）：`Vec<int> sq = 4..8 { $ * $ }` 经复合字面量 + `Vec<T>::from` 纯降级，`foreach` 绑定 `i` / `item`，并直接调用 `Vec<char *>::from(arr, n)` | ct-ast | `test/run.sh` + `check-ast.sh` + `check-warnings.sh` |
| `27_map_keys` | `Map` 的三种键（Phase 29 V29-1）：`Map<long, int>` / `Map<int, char *>` / `Map<char *, int>` 的 `put` / `get` / `remove` / `len`，证明 `long` 键不走 `strcmp`、白名单外的键编译期硬错 | ct-ast | `test/run.sh` + `check-ast.sh` + `check-warnings.sh` |
| `28_subscript_forms` | 容器下标判定的放行面（Phase 29 V29-4d）：数组、数组/指针字段、逐层剥星的指针链 `ppv[0][0]` / `pppv[0][0][0]` / `(*ppv)[0]`，以及返回 `int *` 的函数与方法、返回 `int **` 的函数 | ct-ast | `test/run.sh` + `check-ast.sh` + `check-warnings.sh` |
| `29_into` | 接收者语境块（Phase 30）：指针 / 左值 / 右值三种接收者的语句与值形态、块内 `.name` 与 `$`、块后后缀链 `->field`，以及 `int into = 1;` 的标识符兼容 | ct-ast | `test/run.sh` + `check-ast.sh` + `check-warnings.sh` |

## 门禁归属说明

- `test/run.sh`：端到端层，覆盖编译模式下的 `examples/*/*.ct`。带 `//@ct-requires: ct-ast`
  的文件（`02_market` 的接口值数组、`09_callback/callback_tier2.ct` 的 `=>`、
  `08_map_binding/map_binding.ct` 的 `map`、`json` 的 `loop`、`10`/`11`/`12`/`15`/`16`/`18`/`19`/`20`）不再跳过：第一次遇到时
  在临时目录里按 L0 → L1 → L2 → ct-ast 建链，再用 ct-ast 编译、`cc` 构建、运行并比对
  `expected.out`。这条路径自带红证——把一份真实示例的 golden 换成程序不会输出的内容，必须
  在 diff 阶段被拒绝，否则该门禁项记为失败。
- `check-ast.sh`：语料层以编译模式逐个编译 `examples/*/*.ct`，有 `expected.out` 的比较输出；
  `src/` 三层入口不在它的 glob 内（`check-ast.sh` 的语料层保持编译模式）。
- `check-warnings.sh`：同一语料的零警告门禁；另有一段 `examples/*/src/main.ct` 的 build 模式，
  覆盖 `08_map_binding/src`、`13_builder_chain`、`14_scalar_host`（目录内必须有 `.m.ct`）。
- `wave1-demo` 依赖外部的 ct-pkg 索引，本地门禁不覆盖，只在 CI 里跑。
