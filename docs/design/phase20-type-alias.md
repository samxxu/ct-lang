# Phase 20 扩展：类型别名声明（`pub type`）

> 状态：**设计待确认**（2026-11-07）
> 目标版本：`v0.20.0`
> 关联：Phase 20「类型宿主冲突可解」；ct-pkg 的 5 个 shim typedef
> 本文只定语法与语义，不含实现。确认后再动代码。

## 0. 问题与目标

ct-pkg 目前用 `.shim.h` 里的 C typedef 给 C 类型起 CT 侧名字：

```c
typedef struct ct_io_file IoFile;
typedef struct ct_net_socket NetSocket;
typedef struct ct_sqlite_db SqliteDB;
typedef struct ct_sqlite_stmt SqliteStmt;
typedef struct ct_png_reader PngReader;
```

这些名字只活在 C 侧，CT 编译器不认识它们。类型宿主因此只能按**原始拼写**比较：

```ct
map trait Handle for type PngReader * { ... }   // 宿主键是字面量 "PngReader *"
```

一旦调用点写 `struct ct_png_reader *` 或别名与底层拼写不一致，宿主就命中不了；为了让
C 编译通过，又必须保留 shim typedef。这是用 C 的能力补 CT 的缺失。

目标：把「给类型改名」变成 CT 的语言能力，让映射单元能声明类型别名，并保证：

- 别名在算宿主键**之前**解析到归一化后的底层类型；
- `Alias *` 与底层拼写折叠成同一个宿主；
- 别名随 import 可见，不进入全局符号池；
- 生成 C 里只出现底层类型，不再需要 shim typedef。

非目标：

- 不引入 C ABI 层面的新类型；
- 不做别名 re-export 语法；
- 不改变 `import ... as` 的既有职责；
- 不改动态 trait/vtable 的类型模型。

## 1. 决策总览

| 编号 | 问题 | 结论 |
| --- | --- | --- |
| 1 | 语法 | `pub type Name = <type>;`，`type` 是上下文关键字；目标类型复用 `parse_type` 的拼写规则 |
| 2 | 解析语义 | 别名在**解析类型拼写时**展开，宿主键在展开后的文本上归一化；`SqliteStmt *` 与 `sqlite3_stmt *` 是同一个键 |
| 3 | 作用域 | 可见范围 = 当前单元的 **import 闭包**（直接或间接 import 了声明单元）；闭包外不可见并报「别名未导入」 |
| 4 | 是否生成 C | **纯编译期替换**，不生成 typedef；生成的 C 里出现底层拼写 |
| 5 | 诊断 | 见 §4，每条都有固定原文；别名映射与底层映射并存时**不额外报错**，按同名方法歧义/不同名方法合并处理 |
| 6 | `.h.ct` 是否允许 | **允许**；`.m.ct` 允许且必须 `pub`；普通 `.ct` **不允许** |
| 7 | 与 `import ... as` 分工 | `import ... as` 改的是符号/单元引用名；`pub type` 改的是类型拼写并参与宿主键折叠 |

## 2. 语法（问题 1）

### 2.1 选定形式

```ct
pub type SqliteStmt = sqlite3_stmt;
pub type SqliteDB = struct ct_sqlite_db;
pub type PngReader = struct ct_png_reader;
pub type IoFile = struct ct_io_file;
pub type NetSocket = struct ct_net_socket;
```

文法（仅文件作用域）：

```text
type_alias_decl := [ "pub" ] "type" IDENT "=" type_spelling ";"
```

- `type` 作为**上下文关键字**处理：只有 `type IDENT =` 这个形状才进入别名声明；
  其它位置仍按普通标识符/类型名解析，避免破坏现有代码。
- `type_spelling` 直接复用 `Expr.parse_type`：支持 `struct Tag`、`enum Tag`、
  `union Tag`、指针、限定符、已知 typedef/别名；遇到 `;` 结束。
- 目标类型必须是显式可写的 C 类型拼写。`struct ct_png_reader` 中的 `struct`
  不能省，因为 `ct_png_reader` 在 CT 侧不是 typedef 名；省略时它会被当作一个
  不透明 C 类型拼写原样发出，生成 C 可能不合法。
- 目标可以是不认识的不透明 C 名（`sqlite3_stmt`、`png_image` 等），这与现有
  「未知裸类型名按 C 拼写保留」规则一致。

### 2.2 为什么不是别的形式

| 候选 | 不选的理由 |
| --- | --- |
| `pub type Name from Target;` | `from` 在 `map trait ... for` 里已经是绑定语义；类型别名没有绑定、没有运行时，容易误读成宿主绑定 |
| `map type Name = Target;` | `map` 是「把 trait 方法绑定到宿主」的构造；类型别名不产生 map、不产生 vtable，放进去会污染 `map` 的语义 |
| `alias Name = Target;` | 可行，但需要再引入一个顶层关键字；`type` 已经出现在 `map ... for type` 的词汇里，读者对「类型」的联想一致 |
| `typedef Name = Target;` | 与 C 的 `typedef` 混淆；CT 已有 `typedef`，但它是会进生成 C 的 C 声明，必须区分 |

`pub type` 的读法是「公开一个类型同义词」，不是「生成一个 C 类型」。

### 2.3 单元限制（问题 6）

| 单元 | 是否允许 | `pub` | 理由 |
| --- | --- | --- | --- |
| `.m.ct` | 允许 | **必须** | 映射单元只能导出 `pub` 声明；别名是宿主键的可读拼写 |
| `.h.ct` | 允许 | 可选 | 接口单元可能有不挂映射的公共类型名；私有别名只在本单元可见 |
| `.ct` | **不允许** | — | 普通 `.ct` 不可被 import，别名无法传播；允许它只会制造一个只在一个文件里可见的第二拼写 |

类型宿主仍然只允许出现在 `.m.ct`（`map trait ... for type ...` 的既有规则不变）。
**别名不是类型宿主**，所以 `.h.ct` 允许别名并不等于放开宿主。

`.m.ct` 现有的白名单在
[Parser.h.ct](file:///Users/samxx/vscspace/ct/selfhost/ct-ast/frontend/parse/Parser.h.ct#L514-L521)
只允许 `pub trait` / `map` / `_Static_assert`，需要加入 `type`；非 `pub` 的
`type` 报固定错误（见 §4）。

## 3. 语义与解析（问题 2、3、5）

### 3.1 别名表与解析顺序

新增一张**按单元重置**的可见别名表（与 `Symbols.nalias` 同生命周期）：

```text
name -> resolved target spelling, owner path, owner line, is_public
```

规则：

1. 别名必须**先声明后使用**（同一单元内）。导入的别名在单元开始解析前就已注册，
   因此不受源码里 `import` 行位置影响。
2. 目标里的别名**立即递归展开**；展开结果存成最终拼写，后续不再有链式查找。
3. 展开时维护访问栈：
   - 遇到栈里的名字 → 别名成环，报错并给出完整链；
   - 遇到未知裸名 → 按不透明 C 类型保留（这是现有的类型拼写规则）。
4. 别名名不参与 C 命名空间 mangling：别名没有 C 名字。同名冲突在可见表里
   显式检测（同目标去重、不同目标报冲突）。
5. 别名与前缀的 `struct` 是两回事：`struct Alias` 仍然是 C tag，不查别名；
   只有裸类型名 `Alias` 才展开。

目标示例：

```ct
pub type Stmt = sqlite3_stmt;
pub type Stmt2 = Stmt;          // 立即折叠为 sqlite3_stmt

pub type A = B;
pub type B = A;                 // 声明 B 时发现 A -> B -> A，报环
```

### 3.2 类型拼写展开点

在
[Expr.h.ct](file:///Users/samxx/vscspace/ct/selfhost/ct-ast/frontend/parse/Expr.h.ct#L605-L645)
的裸标识符分支中，先查别名表：

- 命中：把别名的最终目标拼写按 `type_append` 规则追加，再继续处理 `*` / 限定符；
- 未命中：走现有 `resolve_type` / 未知 C 类型逻辑。

这样以下所有入口一次覆盖：

- 变量声明、参数、返回值、struct 字段、typedef、函数指针；
- 类型宿主 `map ... for type ...`（见 §3.3）；
- cast、`sizeof`、`_Alignof` 等类型位置；
- `.h.ct` 的公开签名。

生成 C 的规则是「别名消失」：

```ct
// 源
pub type PngReader = struct ct_png_reader;
pub PngReader *open_file(char *path, char *err, int errcap);
```

```c
/* 生成的 C */
struct ct_png_reader *open_file(char *path, char *err, int errcap);
```

`#ct-raw` / shim 里的原始 C 文本不经过 CT 类型解析，别名不会改写它们。这是明确的
边界：别名是 CT 源文件的编译期名字，不是 C 预处理或文本替换。

### 3.3 宿主键折叠（问题 2 的核心）

现状：

- `MapBuild.parse` 的 `for type` 分支
  [MapBuild.h.ct](file:///Users/samxx/vscspace/ct/selfhost/ct-ast/frontend/parse/MapBuild.h.ct#L631-L660)
  只是把 token 逐个拼成字符串，不走 `parse_type`；
- 调用点用 `Emitter.map_type_key`
  [Emitter.h.ct](file:///Users/samxx/vscspace/ct/selfhost/ct-ast/backend/emit/Emitter.h.ct#L424-L470)
  做空格/`const`/`volatile`/整数类型同义词归一化，然后与 `host_type` 精确比较
  （[Emitter.h.ct](file:///Users/samxx/vscspace/ct/selfhost/ct-ast/backend/emit/Emitter.h.ct#L2757-L2762)）。

改法：

1. `for type` 改为调用 `parse_type` 捕获宿主类型，和 trait 签名、变量声明使用
   同一个规范化器；
2. `map_type_key` 在归一化文本前再做一次别名展开（防御性兜底，防止某条路径绕过
   `parse_type`）；
3. 两边都得到底层拼写后，现有比较逻辑不变。

折叠结果：

| 源拼写 | 解析后拼写 | `map_type_key` 键 |
| --- | --- | --- |
| `SqliteStmt *` | `sqlite3_stmt *` | `sqlite3_stmt*` |
| `sqlite3_stmt *` | `sqlite3_stmt *` | `sqlite3_stmt*` |
| `SqliteStmt **` | `sqlite3_stmt * *` | `sqlite3_stmt**` |
| `struct ct_png_reader *` | `struct ct_png_reader *` | `structct_png_reader*` |
| `PngReader *` | `struct ct_png_reader *` | `structct_png_reader*` |

同一 trait、同一方法名在两个映射里都绑到同一个归一化宿主时，调用点沿用现有诊断：

```text
ambiguous type-host map for method 'close' on type 'struct ct_png_reader *': './a/A.m.ct' and './b/B.m.ct'
```

不同方法名正常合并：

```ct
map trait Handle for type PngReader * { int width(); }
map trait Extra  for type struct ct_png_reader * { int stride(); }
// h.width() 和 h.stride() 都能命中，不报错
```

**不新增「别名映射与底层映射并存」的声明期错误**。理由：两张映射折叠后本来就是
同一个宿主；只要方法名不冲突，合并是合法的。若同名方法冲突，调用点的歧义诊断已经
给出了两个文件，足够定位；在声明期报错会禁止「不同包分别补充不同方法」这种合法用法。

### 3.4 作用域与 import（问题 3）

可见性按 **import 闭包**计算：

- 当前单元自己声明的别名：声明点之后可见；
- 当前单元直接 import 的单元：其 `pub` 别名可见；
- 当前单元间接 import 的单元（A → B → C）：C 的 `pub` 别名也可见；
- 不在闭包内的单元：不可见。

选择传递闭包而不是「只看直接 import」的理由：

1. 与现有 `map_visible` 一致：[Emitter.h.ct](file:///Users/samxx/vscspace/ct/selfhost/ct-ast/backend/emit/Emitter.h.ct#L331-L354)
   用传递可达性判断 map 是否可见；
2. 与生成 C 的头文件包含语义一致：消费者 include 的 `.h` 会间接 include 依赖的 `.h`，
   C 侧本来就能看到传递包含的 typedef；
3. ct-pkg 的 `png/examples/scan.ct` 只 `import png::Image`，而 `PngReader` 声明在
   `Png.m.ct`；若只认直接 import，所有只用 `Image` 的消费者都必须额外补
   `import png::Png`。传递闭包让现有示例保持源码不变。

「未 import」的判定：

- 解析到未知裸标识符时，先查当前可见别名表；
- 未命中，再查**已加载单元**的全局别名登记表；
- 若该名字是某个已加载单元声明过的别名，但不在当前闭包里，报：

```text
type alias 'PngReader' is declared in ./png/Png.m.ct:12 but this unit does not import it
```

- 若声明单元根本没被加载（没有任何单元 import 它），编译器无从知道它是别名，
  该名字按现有的不透明 C 类型规则保留。这是有意保留的边界，避免为一个类型名
  扫描全仓。

别名不 re-export：当前单元可见的导入别名不会自动出现在它的导出列表里；下游单元
仍然按自己的 import 闭包计算。若需要让下游看到，应由下游 import 声明单元，或在
公共签名里直接使用底层类型（展开后本来就不依赖别名）。

### 3.5 `.m.ct` 白名单与 `pub`

- `.m.ct` 的顶层白名单加入 `type`；
- `.m.ct` 里的别名必须 `pub`，与「`.m.ct` 里的 trait 必须 `pub`」一致；
- 非 `pub` 的别名在 `.m.ct` 报固定错误，不静默降级。

## 4. 诊断（问题 5）

所有错误在解析声明/使用点时产生，带文件、行、列。固定原文如下：

| 场景 | 原文 |
| --- | --- |
| 缺少目标类型 | `expected a type after '=' in a type alias declaration` |
| 别名出现在普通 `.ct` | `a type alias is only allowed in a .h.ct or .m.ct unit` |
| `.m.ct` 里没有 `pub` | `a type alias in a .m.ct unit must be 'pub'` |
| 与已有类型/typedef/trait 同名 | `type alias 'X' conflicts with an existing type` |
| 先声明别名，后声明同名类型 | `type 'X' conflicts with an existing type alias` |
| 同一单元重复声明 | `duplicate type alias 'X' (first at <path>:<line>)` |
| 别名成环 | `type alias cycle: 'A' -> 'B' -> 'A'` |
| 目标指向 trait | `type alias 'X' cannot name a trait` |
| 使用未导入的别名 | `type alias 'X' is declared in <path>:<line> but this unit does not import it` |
| 同一单元内先用后声明 | `type alias 'X' must be declared before it is used` |
| 两个可见单元导出同名不同目标 | `type alias 'X' is exported by both <path1> and <path2>` |
| 别名映射与底层映射同 trait 同方法 | 沿用 `ambiguous type-host map for method '<m>' on type '<key>': '<p1>' and '<p2>'` |

关于「别名未定义」：

- CT 现在允许未知裸类型名作为不透明 C 类型（`time_t`、`sqlite3_stmt` 等），
  因此不能把「任何未知名字」都报成未定义别名；
- 本设计把「未定义」落在两种可判定情形：**声明了但不在 import 闭包内**
  （上表第 9 条）和**同单元先用后声明**（第 10 条）；
- 若一个名字在已加载单元里从未被声明为别名，它继续按 C 类型拼写处理。
  这一点需要在评审时确认是否接受。

## 5. 与 `import ... as` 的分工（问题 7）

| 机制 | 改变什么 | 作用域 | 是否影响宿主键 |
| --- | --- | --- | --- |
| `import a::b::T as T;` | 导入一个符号/类型引用名，解决命名空间重名 | 当前单元的 import 引用 | 只通过 `resolve_type` 的既有规则影响最终拼写；不产生新类型 |
| `pub type X = T;` | 定义一个新类型同义词，`X` 在类型位置等价于 `T` | 声明单元 + 其 import 闭包 | **是**，`X` 先折叠成 `T` 的拼写，再算键 |

使用建议：

- 两个命名空间都导出 `T`，裸名有歧义 → 用 `import ... as`；
- C 类型本身有个难写的名字，或希望映射宿主的拼写稳定、可读 → 用 `pub type`；
- `pub type` 不是 `import ... as` 的替代品：前者不解决「哪个单元的 T」，
  后者不改变「T 的底层拼写」。

## 6. 回归测试

新增夹具放在 `test/ast/` 下，至少覆盖：

| # | 场景 | 期望 |
| --- | --- | --- |
| 1 | 别名宿主命中 | `.m.ct` 声明别名并把 trait 方法挂到 `Alias *`；`.ct` 用 `Alias *` 接收者调用，recipe 正常展开 |
| 2 | 别名与底层折叠为同一宿主 | 同一 trait 的两张映射分别写 `Alias *` 与底层拼写，方法名不同；两个方法都能调用 |
| 3 | 跨包/import 闭包可见 | 单元 A import 声明单元；A 以及间接 import A 的单元都能在签名里写别名，生成 C 用底层拼写 |
| 4 | 未 import 不可见 | 同一次构建里 B 没有 import 声明单元（但该单元已因 A 被加载）；B 使用别名报「未导入」 |
| 5 | 别名成环 | `type A = B; type B = A;` 报 `type alias cycle: ...` |
| 6 | 同一宿主同名方法歧义 | 两张映射分别用别名和底层拼写绑同一 trait 的同一方法；调用点报 `ambiguous type-host map for method ...` |

建议再加三条低成本用例：

| # | 场景 | 期望 |
| --- | --- | --- |
| 7 | `.h.ct` 公开签名用别名 | 生成的 `.h` / `.c` 只出现底层拼写，不出现别名 |
| 8 | 别名与已有类型同名 | 报 `type alias 'X' conflicts with an existing type` |
| 9 | `.ct` 里的别名 / `.m.ct` 非 pub | 分别报 §4 的单元限制错误 |

基线：

- 当前 `selfhost/check-ast.sh` 全绿基线为 **478 passed**；
- 新增夹具后以脚本实际输出为准，更新记录的基线数，并保证 `0 failed`；
- 新用例的 golden C 只用于确认「别名不出现、底层出现」，不比较别名声明本身。

## 7. ct-pkg 跨仓验收条件

语言侧只保证能力；以下由 ct-pkg 执行：

1. 在 5 个映射单元声明别名：

```ct
// std/std/io/File.m.ct
pub type IoFile = struct ct_io_file;

// net-posix/net/Sock.m.ct
pub type NetSocket = struct ct_net_socket;

// sqlite/sqlite/Sqlite.m.ct
pub type SqliteDB = struct ct_sqlite_db;
pub type SqliteStmt = struct ct_sqlite_stmt;

// png/png/Png.m.ct
pub type PngReader = struct ct_png_reader;
```

2. 删除 shim 里的 5 行 `typedef ... Alias;`；
3. **同步改写 shim C 代码里的别名拼写**：`ct_png_read_image`、`std_io_*`、
   `ct_net_*`、`ct_sqlite_*` 等函数的参数/返回类型如果写了 `PngReader *` /
   `IoFile *` / `NetSocket *` / `SqliteDB *` / `SqliteStmt *`，必须改成
   `struct ct_png_reader *` 等底层 tag。只删 typedef 不改签名，`cc` 会失败；
4. 映射宿主的 `for type` 改成别名拼写（如 `for type PngReader *`），确认宿主键
   与调用点折叠；
5. `ct build` 全绿；所有 demo 的 stdout 与改动前逐字节相同；
6. 由于别名不生成 C，生成 C 文本会从 `PngReader *` 变成
   `struct ct_png_reader *`，这是预期的；验收看 demo 输出，不看生成文本。

`png/examples/*.ct` 只 import `png::Image`，依靠 import 闭包看到
`Png.m.ct` 的 `PngReader`；若最终选择「只看直接 import」，则这些示例必须补
`import png::Png;`。这一点需要评审确认（见 §8）。

### 7.1 顺带订正 `language-spec.md` §4.22 的变参漂移

现状
[language-spec.md](file:///Users/samxx/vscspace/ct/docs/language-spec.md#L932-L934)
写「trait 方法不能变参」，但 `Parser.h.ct` 早已允许 `.m.ct` 的静态 trait 方法以
`...` 结尾（`self->unit_is_map` 分支），调用点展开时透传。§4.22 将改为：

- 非映射单元（`.h.ct` / `.ct`）的 trait 方法与 `impl` 不能变参：
  `a trait method cannot be variadic`（vtable 槽是固定函数指针类型）；
- `.m.ct` 的静态 trait 方法可以以 `...` 结尾，`...` 必须是最后一个参数；
  调用点在 recipe 展开时透传实参，没有 vtable、没有固定槽；
- 中英文两半同步修改。

## 8. 实现落点（供确认，不含代码）

| 文件 | 改动 |
| --- | --- |
| [Symbols.h.ct](file:///Users/samxx/vscspace/ct/selfhost/ct-ast/frontend/sym/Symbols.h.ct) | 可见别名表（增/查/展开）、全局别名登记表、冲突与环诊断；`add_type` 增加「与别名冲突」检查 |
| [Unit.h.ct](file:///Users/samxx/vscspace/ct/selfhost/ct-ast/frontend/module/Unit.h.ct) | 每个单元自己的别名记录（名字、目标、行号、是否 pub） |
| [Module.h.ct](file:///Users/samxx/vscspace/ct/selfhost/ct-ast/frontend/module/Module.h.ct) | 单元重置时清空可见别名表；解析前把 import 闭包内的 `pub` 别名注册进当前单元；设置 `unit_is_hdr` |
| [Parser.h.ct](file:///Users/samxx/vscspace/ct/selfhost/ct-ast/frontend/parse/Parser.h.ct) | `type_alias_ahead()` 前瞻、`parse_type_alias()`、`.m.ct` 白名单加入 `type`、单元限制诊断 |
| [Expr.h.ct](file:///Users/samxx/vscspace/ct/selfhost/ct-ast/frontend/parse/Expr.h.ct) | `parse_type` 裸标识符分支展开别名 |
| [MapBuild.h.ct](file:///Users/samxx/vscspace/ct/selfhost/ct-ast/frontend/parse/MapBuild.h.ct) | `for type` 改用 `parse_type` |
| [Emitter.h.ct](file:///Users/samxx/vscspace/ct/selfhost/ct-ast/backend/emit/Emitter.h.ct) | `map_type_key` 增加别名展开兜底；复用现有歧义诊断 |
| `test/ast/**` | §6 的夹具与 golden |
| [check-ast.sh](file:///Users/samxx/vscspace/ct/selfhost/check-ast.sh) | 基线数 478 → 新值 |
| [language-spec.md](file:///Users/samxx/vscspace/ct/docs/language-spec.md) | 新增 §4.42；§4.10 增加别名与宿主键；订正 §4.22 变参漂移（中英文两半都改） |

## 9. 待确认事项

请评审确认以下 5 点；确认后按 §8 实施：

1. **可见性用传递闭包**（推荐）还是只看直接 import？
   - 传递闭包：`scan.ct` 只 import `Image` 也能用 `PngReader`，与 `map_visible`
     和 C 头文件包含一致；
   - 直接 import：语义更窄，但 ct-pkg 的 png 示例和其他「只 import 上层头」的
     消费者必须补 import。
2. **普通 `.ct` 禁止别名**（推荐）是否接受？替代方案是允许私有别名，但不导出。
3. **未知别名目标按不透明 C 类型保留**（推荐，`sqlite3_stmt` 依赖此规则）是否接受？
   因此「完全没被任何已加载单元声明过的名字」不会被报成未定义别名。
4. **别名映射与底层映射并存不报声明期错误**（推荐）：不同方法合并，同名方法在
   调用点报歧义。是否接受？
5. **不生成 C typedef**（推荐）：生成 C 只出现底层拼写，调试器里也看到底层名。
   是否接受以此换取「一个别名不产生平行宿主」和「不重复定义」？

另外，§4 的诊断原文如需调整措辞，请在确认时一并给出。
