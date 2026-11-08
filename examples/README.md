# examples —— 示例索引

每个目录是一份可运行的小程序，覆盖 `ct` 的一类能力。分为四组：**impl / vtable**、
**类型宿主（type host）**、**闭包**、**loop 语义**。

## impl / vtable

`impl` 落在 struct 上，方法经 vtable 分派；调用点看不到指针或虚表。

| 目录 | 演示什么 | 前置条件 | 本地门禁归属 |
| --- | --- | --- | --- |
| `01_greeter` | 最小可用：一个 trait、一个 struct、一次 impl、两次调用 | 无 | `test/run.sh` + `check-ast.sh` + `check-warnings.sh` |
| `02_market` | 多个对象互调；同一 trait 在两个 struct 上给出不同实现 | 无 | 同上 |
| `03_receivers` | receiver 可以是数组元素、指针数组元素、指针字段链 | 无 | 同上 |
| `04_rvalue` | rvalue receiver（工厂返回值直接调用），receiver 只求值一次 | 无 | 同上 |
| `05_body_dispatch` | `impl` 方法体内经 vtable 的递归分派（字段链 / 参数 / 局部变量） | 无 | 同上 |
| `06_iface_field` | trait 值作为 struct 字段，跨对象组合 | 无 | 同上 |
| `07_dialect` | 注释里的 DSL 经 `ct-dialects/` 插件展开成纯 CT，编译器零感知 | 插件（目录内自带） | 同上（`test/run.sh` 的 dialect 层） |
| `08_map_binding` | `map trait ... for instance`：绑定一个改不动的全局实例并装箱 | ct-ast（`map`） | `check-ast.sh` + `check-warnings.sh`（`test/run.sh` 跳过） |
| `09_callback` | 容器回调约定：手写 `(fn, env)` 对，`env` 作为回调首参 | 无 | `test/run.sh` + `check-ast.sh` + `check-warnings.sh` |
| `json` | 纯 CT 的 JSON 读写：零分配只读视图 + 写出 | 无 | `test/run.sh` + `check-ast.sh` + `check-warnings.sh` |
| `wave1-demo` | Wave 1 包（`hal` / `hal-posix` / `std`）合用 | 外部 ct-pkg 索引 | **仅 CI** |

## 类型宿主（type host）

`map trait ... for type <C 拼写>` 把方法直接挂到 C 类型上：无包装、无 vtable、无分配，
每个调用点在原地展开成一次普通 C 调用。键是**拼写**：`int`、`unsigned`、`unsigned int`
是三个不同的键。

`08_map_binding` 用的是 `map ... for instance`，绑定的是一个实例，仍需装箱进 trait 值；
下表的两个示例用 `for type`，调用点是普通 C 值，不存在装箱。

| 目录 | 演示什么 | 前置条件 | 本地门禁归属 |
| --- | --- | --- | --- |
| `13_builder_chain` | 宿主方法返回宿主本身，形成真正的 `b.add(1).add(2).value()` 链 | ct-ast + `ct build` 多单元 | `check-warnings.sh`（本文件新增段） |
| `14_scalar_host` | 给 `int` / `char *` / `double` / `unsigned long` 加方法，含链式调用 | ct-ast + `ct build` 多单元 | 同上 |

`13`、`14` 需要 `.m.ct` 映射单元与 `import`，只能用 `ct build` 的多单元模式，
因此源码放在 `examples/<dir>/src/main.ct`（三层），而不是会被单文件编译的
`examples/<dir>/*.ct`。`wave1-demo` 采用同一种 `src/` 布局。

## 闭包

闭包是 `(fn, env)` 对，`env` 是回调的首参；容器不得留存这两个词。

| 目录 | 演示什么 | 前置条件 | 本地门禁归属 |
| --- | --- | --- | --- |
| `10_closure_pipeline` | 闭包字面量 / 已声明的绑定的传参约定，配合 `loop(n)` | ct-ast | `check-ast.sh` + `check-warnings.sh` |
| `12_closure_in_loop` | 循环体内创建闭包：按值捕获，只保留创建那一轮的变量 | ct-ast | 同上 |

## loop 语义

| 目录 | 演示什么 | 前置条件 | 本地门禁归属 |
| --- | --- | --- | --- |
| `11_loop_semantics` | `loop(n)`（0..n-1）与 `loop(a..b)`（a..b-1）：计数只求值一次，`i` 可写 | ct-ast | `check-ast.sh` + `check-warnings.sh` |

## 门禁归属说明

- `test/run.sh`：L0 种子驱动的端到端层；首行带 `//@ct-requires: ct-ast` 的示例会被跳过。
- `check-ast.sh`：语料层以编译模式逐个编译 `examples/*/*.ct`，有 `expected.out` 的比较输出。
- `check-warnings.sh`：同一语料的零警告门禁，另加 `examples/*/src/main.ct` 的 build 模式段。
- `wave1-demo` 依赖外部的 ct-pkg 索引，本地门禁不覆盖，只在 CI 里跑。
