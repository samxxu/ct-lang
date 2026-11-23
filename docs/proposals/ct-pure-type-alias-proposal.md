# CT 纯类型别名（`type`）提案：现状评估与放开单元限制

| 项 | 值 |
| --- | --- |
| 性质 | 语言侧提案；供 CT 项目组评估。是否受理、落点与排期由项目组决定 |
| 状态 | 草案；未立项，不占 phase |
| 对象 | 现有 `type` 类型别名的可用范围，以及「纯别名」语义的明确承诺 |
| 事实基线 | v0.61.1；[language-spec.md §4.42](../language-spec.md#442-类型别名-typephase-20仅-ct-ast)、`selfhost/ct-ast` 主线 |
| 不在范围 | 编译器实现、C 侧 typedef 的生成策略、其它仓库的文件与接口 |

> 本提案只写语言侧。文中「std」指本仓 `lib/std` 的公开接口，不指向任何外部使用方。

---

## 0 结论摘要

1. **语义上，CT 已经有纯别名。** `type Name = T;` 是纯编译期同义词：不新建类型、不产生转换、
   判等与赋值按底层类型处理、方法随宿主展开自动可见、`own` 按展开后的类型处理。
2. **但只能在 `.h.ct` / `.m.ct` 声明**；普通 `.ct` 直接硬错
   （`a type alias is only allowed in a .h.ct or .m.ct unit`，[language-spec.md:1741](../language-spec.md#442-类型别名-typephase-20仅-ct-ast)）。
3. 因此整体判定：**部分够用**——语义够用，声明位置不够用。
4. 对 std 的 `Socket` 只作 `Fd` 同义名这一用法：**只要两者都声明在 `.h.ct`（或 `.m.ct` 且 `pub`），
   今天就成立**；若要求写在普通 `.ct` 单元里，**不成立**。

---

## 1 动机

std 侧希望 `Socket` 只是 `Fd` 的同义名：不为网络另造一个描述符类型，也不在两套类型之间写转换。
这要求一种「改名但不造类型」的机制：

- 新名字与原名是**同一个类型**，判等、赋值、传参、字段声明都不需要转换；
- 挂在原名上的方法对新名字自动可见；
- `own` 与所有权规则一致；
- 生成 C 时只出现底层拼写，不引入 ABI 层的新类型。

现有 `type` 别名正是这个形状；问题只在它能写在哪些单元里。

---

## 2 现状调查

### 2.1 已有语法

```c
namespace lib;

pub type Text  = char *;
pub type Count = int;
```

- 文法：`[pub] type Name = <类型>;`，`type` 是上下文关键字，只有 `type IDENT =` 这一形状进入
  别名分支（[language-spec.md:1744](../language-spec.md#442-类型别名-typephase-20仅-ct-ast)、[Parser.h.ct:452](../../selfhost/ct-ast/frontend/parse/Parser.h.ct#L452)）。
- 仅文件作用域；目标复用普通类型读取器，`struct` / `enum` / `union`、指针与整型同义词规范化都会发生
  （[language-spec.md:1745](../language-spec.md#442-类型别名-typephase-20仅-ct-ast)）。
- 不发射任何 typedef，不进 `--emit-map`，生成的 `.h` / `.c` 只有底层拼写
  （[language-spec.md:1773](../language-spec.md#442-类型别名-typephase-20仅-ct-ast)）。

现有夹具直接覆盖了别名作字段、参数与返回类型：

- `Text t = "hello";`、`Count n = 3;`、`Text u = echo(t);`
  （[prog.ct:9-12](../../test/ast/67_type_alias/prog.ct#L9-L12)）；
- `pub Text echo(Text t);` 的签名在生成 C 里写成底层类型
  （[app.h.ct:5](../../test/ast/67_type_alias/app.h.ct#L5)）。

### 2.2 解析、判等与赋值

别名在**类型拼写解析阶段**展开，早于任何名字解析：

- `expand_type_alias` 递归展开目标，链式别名立即折叠
  （[Symbols.h.ct:1466](../../selfhost/ct-ast/frontend/sym/Symbols.h.ct#L1466)）；
- `parse_type` 先查别名表，命中就直接把展开后的文本写进类型拼写，再去解析已知类型
  （[Expr.h.ct:1926-1936](../../selfhost/ct-ast/frontend/parse/Expr.h.ct#L1926-L1936)）。

因此 `Socket` 与 `Fd` 在编译器里落到**同一个归一化拼写**：声明、赋值、传参、字段、强转都走同一个
类型读取器，不存在「别名类型」与「底层类型」两套规则。仓库里没有「别名与底层类型不兼容」的反例夹具；
正向夹具覆盖了赋值与跨函数传递（[prog.ct:9-12](../../test/ast/67_type_alias/prog.ct#L9-L12)）。

### 2.3 方法寄生

CT 的方法不是类型携带的，而是 `map trait … for type <宿主>` 绑定到**宿主键**上。别名在算宿主键
之前展开，与底层拼写归一化后比较：

- 规范明文：`map … for type SqliteStmt` 与 `map … for type sqlite3_stmt` 是同一个宿主
  （[language-spec.md:1749-1753](../language-spec.md#442-类型别名-typephase-20仅-ct-ast)）；
- 实现注释同口径（[MapBuild.h.ct:647](../../selfhost/ct-ast/frontend/parse/MapBuild.h.ct#L647)）。

两个方向都成立：挂在 `Fd` 上的方法，用 `Socket` 接收者调用会命中同一宿主；反过来，挂在
`Socket` 上的映射也会落在 `Fd` 上。夹具证据：

- `map trait TextOps for type Text` 后，`Text` 变量直接 `.size()` / `.same(u)`
  （[lib.m.ct:16-19](../../test/ast/67_type_alias/lib/lib.m.ct#L16-L19)、[prog.ct:15](../../test/ast/67_type_alias/prog.ct#L15)）；
- `pub type FileHandle = struct ct_file *;` 后，对 `FileHandle` 值写 `.write()` / `.tell()`，映射表
  写在 `struct ct_file *` 上（[types.h.ct:8](../../test/ast/153_into_type_host/lib/types.h.ct#L8)、
  [ops.m.ct:9-15](../../test/ast/153_into_type_host/lib/ops.m.ct#L9-L15)、
  [prog.ct:12-16](../../test/ast/153_into_type_host/prog.ct#L12-L16)）。

若两个可达单元用别名与底层拼写各写一份同名方法，声明期不报错，调用点报
`ambiguous type-host map for method …`（[language-spec.md:1751](../language-spec.md#442-类型别名-typephase-20仅-ct-ast)）。

### 2.4 `own` 与所有权

`own` 是声明行行首的上下文关键字，类型部分走同一个类型读取器
（[language-spec.md:448](../language-spec.md#49-autodropphase-5-新增仅-ct-线)）。因此 `own Socket s = …` 与 `own Fd s = …`
在展开后完全同形；`own` 的约束按**底层类型**判断：

- 底层必须是结构体指针且该 struct `use Drop`（[language-spec.md:470](../language-spec.md#49-autodropphase-5-新增仅-ct-线)）；
- 若 `Fd` 本身是 `int` 之类的值类型，`own` 对 `Fd` 与 `Socket` 一样不适用——限制来自类型，
  不来自别名。

仓库没有 `own` + 别名的现成夹具；这一条是按解析路径推断的，验收需补（§7）。

### 2.5 与既有声明形式的分工

| 形式 | 做什么 | 是否产生新类型 | 与别名的关系 |
| --- | --- | --- | --- |
| `type Name = T;` | 给类型拼写起同义词，算宿主键前折叠 | 否 | 本提案对象 |
| `struct Name { … }` | 定义新的具名记录类型 | 是 | 与别名同名报冲突 |
| `typedef T Name;` | 生成真实的 C typedef，进入生成物 | 是（C 侧） | 与别名同名报冲突；别名不发射 typedef |
| `import a::b::T as U;` | 给已导出类型名换本地引用名 | 否 | 只能指向导出表里的名字；与别名同名报冲突（[language-spec.md:1770](../language-spec.md#442-类型别名-typephase-20仅-ct-ast)） |
| `map trait X for type H` | 把 trait 方法绑定到宿主 | 否 | 不产生类型；宿主拼写先展开别名 |

### 2.6 缺口清单

| # | 缺口 | 现状证据 | 影响 |
| --- | --- | --- | --- |
| G1 | 普通 `.ct` 不能声明别名 | 硬错文案 [language-spec.md:1741](../language-spec.md#442-类型别名-typephase-20仅-ct-ast)、[Parser.h.ct:503](../../selfhost/ct-ast/frontend/parse/Parser.h.ct#L503) | 实现单元与局部代码无法起同义名；std 若想写在 `.ct` 里就不成立 |
| G2 | 只在文件作用域，不能写在函数内 | 文法标注「仅文件作用域」[language-spec.md:1744](../language-spec.md#442-类型别名-typephase-20仅-ct-ast) | 单个函数内的临时同义名无法表达 |
| G3 | `.m.ct` 里的别名必须是 `pub` | 硬错 [language-spec.md:1742](../language-spec.md#442-类型别名-typephase-20仅-ct-ast) | 映射单元不能有私有别名 |
| G4 | 不发射 C typedef，C 读者看不到别名 | [language-spec.md:1773](../language-spec.md#442-类型别名-typephase-20仅-ct-ast) | C 侧头文件、调试器、日志里只有底层拼写；对 CT 语义无影响 |
| G5 | 无 re-export 语法，私有别名不跨单元 | import 闭包规则 [language-spec.md:1754](../language-spec.md#442-类型别名-typephase-20仅-ct-ast) | 别名不能作为独立的公开名字再次导出 |
| G6 | 同单元先声明后使用 | [language-spec.md:1760](../language-spec.md#442-类型别名-typephase-20仅-ct-ast) | 预扫描只用于诊断，不改变顺序要求 |
| G7 | 仅主线 ct-ast 支持 | §4.42 标题「Phase 20，仅 ct-ast」 | 冻结线 l2 不含；跨层一致性需另行处理 |
| G8 | 目标不能是 trait；`struct Alias` 是 C tag 不是同义词 | [language-spec.md:1768](../language-spec.md#442-类型别名-typephase-20仅-ct-ast)、星号归属 [language-spec.md:1737](../language-spec.md#442-类型别名-typephase-20仅-ct-ast) | 容易把 `type T = struct S;` 与 `type T = struct S *;` 写混 |

---

## 3 评估结论：部分够用

| 需求项 | 现状 | 判定 |
| --- | --- | --- |
| 声明新名字等价于已有类型 | 支持，限 `.h.ct` / `.m.ct` | 部分够用（G1） |
| 解析器把它当同一类型 | 类型拼写阶段展开，落在同一归一化拼写 | 够用 |
| 判等与赋值不改规则 | 无别名专属规则，底层拼写相同 | 够用 |
| 方法自动可见 | 宿主键展开后同一宿主，双向可见 | 够用 |
| `own` 与所有权一致 | 展开后同形；约束按底层类型 | 够用（缺夹具） |
| 不产生转换、不改 ABI | 纯文本替换，不发射 typedef | 够用 |

**对 std 的 `Socket` / `Fd` 用法：**

- 若 `Fd` 与 `Socket` 都落在 `.h.ct`（或 `.m.ct` 且 `pub`），且 `Socket` 的声明在 `Fd` 之后或经 import
  可见——**成立**，今天即可用，方法、判等、赋值、`own` 都按 `Fd` 处理；
- 若要求 `Socket` 写在普通 `.ct` 单元里——**不成立**，会被 G1 拒绝。

因此，阻止该用法的不是语义，而是**声明位置**。下一节只针对这一点提案。

---

## 4 提案：把纯别名放开到普通 `.ct`

### 4.1 诉求

在**不改变现有语义**的前提下，允许普通 `.ct` 单元在文件作用域声明类型别名：

1. 新名字与被别名类型是**同一个类型**：不新建类型、不产生转换、不改判等与赋值规则；
2. 方法不随别名复制，仍绑定在宿主键上；别名展开后命中同一宿主，两个方向都自动可见；
3. `own` 与所有权按展开后的类型处理，规则与直接写底层类型完全一致；
4. 别名只在声明单元内可见（普通 `.ct` 不可被 import），不进入其它单元，也不改变生成物；
5. `.h.ct` / `.m.ct` 的既有行为、诊断与生成物保持不变。

非目标：函数内局部别名、别名 re-export、让别名出现在 `--emit-map` 或生成 C 里、把别名做成
独立 ABI 类型。

### 4.2 语法候选

| 方案 | 形式 | 取舍 |
| --- | --- | --- |
| **A 复用 `type`（建议）** | `.ct` 里写 `type Name = T;` | 复用已有关键字、类型读取器与全部诊断；改动面最小：只移除单元限制 |
| B 新关键字 `alias` | `alias Name = T;` | 与 `type` 完全重复，还多一个顶层关键字 |
| C 复用 `typedef` | `typedef T Name;` | 会发射真实 C typedef，造出 C 侧新类型，违背「纯别名」 |
| D `map type Name = T;` | 与 `map` 合并 | `map` 是「trait 方法绑定宿主」的构造，别名不产生映射，语义会混 |
| E `import … as` | `import a::b::T as U;` | 只给已导出的名字换引用名，不能给任意类型拼写起同义词 |

建议 A：`type` 已经是上下文关键字，只有 `type IDENT =` 这一形状进入别名分支，现有代码不受影响
（[language-spec.md:1744](../language-spec.md#442-类型别名-typephase-20仅-ct-ast)）。

### 4.3 语义与边界

**不变量（五条，缺一不可）**

1. 别名不是新类型：类型身份就是展开后的底层拼写，判等、赋值、传参、返回、字段、强转全部沿用
   底层类型的既有规则，不新增「别名类型」分支；
2. 不产生转换：任何方向都不插入转换函数或运行期检查；
3. 不改变方法归属：方法仍由 `map … for type <宿主>` 绑定，别名不携带方法表，也没有「继承」实现；
4. `own` 按底层类型：底层满足「结构体指针 + `use Drop`」时与直接写底层类型等价；不满足时同样拒绝，
   诊断不因别名而不同；
5. 生成物不变：不发射 typedef、不进 `--emit-map`、不改变 `.h` / `.c`。

**与 struct 的相互作用**

- `type T = struct S;` 让 `T *` 与 `struct S *` 同键；`type T = struct S *;` 让裸 `T` 与
  `struct S *` 同键——星号归属按规范 §4.42，不因单元类型变化；
- `struct T` 里的 `T` 仍是 C tag，**不是**别名；不能写 `struct Socket` 去指 `Fd`；
- 别名可以出现在 struct 字段、参数、返回值、局部声明与 `sizeof` / 强转的类型位置；
- 与 struct / trait / typedef 同名报既有冲突诊断
  （`type alias 'X' conflicts with an existing type`）。

**与既有声明形式的边界**

- 与 `import … as` 分工不变：后者换已导出名字的本地引用名，前者给任意类型拼写起同义词；同名冲突；
- 与 `typedef` 不互相替代：需要 C 侧真实类型名时仍写 `typedef`，需要纯同义词时写 `type`；
- 目标不能是 trait（既有诊断 `type alias 'X' cannot name a trait`）。

**可见性、顺序与循环**

| 单元 | 允许 | `pub` | 可见范围 |
| --- | --- | --- | --- |
| `.h.ct` | 允许（不变） | 可选 | import 传递闭包 |
| `.m.ct` | 允许（不变） | 必须 | import 传递闭包 |
| `.ct`（本提案新增） | 允许 | **不允许**：单元不可被 import，`pub` 无意义 | 仅本单元 |

- `.ct` 里写 `pub type` 建议给固定诊断（例如「a type alias in a .ct unit must not be 'pub'」），
  文案与错误码由项目组钉定；
- 同单元先声明后使用、成环报 `type alias cycle: …`、重复声明报 `duplicate type alias 'X'`，
  全部沿用现规则；
- `.ct` 别名不跨单元，因此不会产生「两个可达单元导出同名异目标」这一类跨单元冲突。

**落点与版本**

- 实现落点在 ct-ast 的单元检查与类型读取器：把 [Parser.h.ct:503](../../selfhost/ct-ast/frontend/parse/Parser.h.ct#L503)
  的单元限制放开到普通 `.ct`，其余展开逻辑不动；
- 可用版本写相对位次：若受理，落在**下一个 MINOR**（与同批语言变更一起）；绝对版本号只作内部排期
  参考，不作对外承诺；
- 与 `Str` 内置化等其它提案无依赖，可独立排期。

---

## 5 不做会怎样

1. **std 被位置绑架**：`Socket = Fd` 只能写进 `.h.ct`；如果网络模块本来没有独立头文件，就得为一个
   同义名新造一个头。
2. **实现单元无法起名**：`.ct` 里的实现代码只能用裸拼写，读起来分不清「这是描述符」还是「随便一个
   `int`」；团队会在注释里维护约定。
3. **绕法会造出真类型**：用 `typedef` 得到的是 C 侧新类型，于是又要写两套类型之间的转换——正是本
   需求要避免的；或者在两处各写一份 `map`，调用点撞上 `ambiguous type-host map`，只能靠改名规避，
   破坏同名同义。
4. **拼写漂移**：底层拼写改了（比如 `int` 换成 `struct fd *`），所有使用点都要改；别名本可以只改
   一行。

---

## 6 验收判据（实现后逐条可验）

- `.ct` 单元里 `type Socket = Fd;` 编译通过；同样的声明在 `.h.ct` / `.m.ct` 行为不变。
- `Socket` 与 `Fd` 互相赋值、互相传参、作为结构体字段与返回值，均零诊断、零转换调用。
- `map … for type Fd` 后，`Socket` 接收者调用命中同一宿主；反向亦然；两份同名映射仍按既有
  `ambiguous type-host map` 在调用点报错。
- `own Socket s = …` 在底层为「结构体指针 + `use Drop`」时，生成物与 `own Fd s` 的释放代码一致；
  底层为 `int` 时两者给出同一条拒绝诊断。
- `struct Socket` 不被当作别名：作为负例给出固定诊断或按 C tag 处理，文档写明。
- 别名链 `type S2 = Socket;` 折叠到底层；`type A = B; type B = A;` 报既有 cycle 诊断。
- `.ct` 里 `pub type` 给出固定诊断；`.h.ct` / `.m.ct` 的 `pub` 规则不变。
- 生成 C 无 typedef、无新符号；`--emit-map` 输出不变。
- 既有别名夹具 [67_type_alias](../../test/ast/67_type_alias/prog.ct)、
  [153_into_type_host](../../test/ast/153_into_type_host/prog.ct)、
  [154_into_shim](../../test/ast/154_into_shim/prog.ct) 零回归。

---

## 7 未决问题

1. `.ct` 里的 `pub type` 是拒绝还是静默忽略（本提案建议拒绝）。
2. 是否也允许函数内局部别名（本提案列为非目标）。
3. 别名是否应进入调试信息或 `--emit-map`（现状为否；本提案不改变）。
4. 冻结线 l2 是否同步该能力（现状仅 ct-ast 主线）。
5. 新增诊断的原文与错误码。
6. 是否为别名保留 re-export 语法（本提案列为非目标）。
