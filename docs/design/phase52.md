# Phase 52 — 自定义类型下标 `[]`（REQ-L1，方案 A，单层）

> **状态：规划中**（草案，待评审；未立项；**方向已裁定**：接，方案 A，单层；本轮只写卡，不改代码）
> **基线**：HEAD `ff1b9140`（`ct-ast v0.44.1`）；起点为 PH-51 收口提交（连写验收依赖 51）。
> **依赖**：PH-31（`v[i]` / `m[k]` 糖与 L31-3/L31-4 写保护）、PH-34（非泛型固有 `impl`）、
> [phase51.md](phase51.md)（链式前置；单层下标本身不依赖 51）。
> **规模**：编译器 150–280；夹具 70–130；文档 30–60；合计 **250–470**（±40%）。
> **版本**：收口 bump `v0.52.0`；tag / push 需用户单独授权。
> **纪律**：依据是 [custom-index-protocol.md](../proposals/custom-index-protocol.md) 的 `RL1-*`，
> **不引** `phase40-draft.md` / `E40-*`（评审一 §1 #4/#5 已判该引用张冠李戴）。

## 0 背景与裁定

**现状**：用户类型 `b[0]` 被 `ct-ast` 原样发射为 C 下标，`cc` 才报
`subscripted value is not an array, pointer, or vector`（`b["k"]` 报 `array subscript is not an integer`）。
`Vec` / `Map` 的内建下标可用，写形态是硬错（`a Vec subscript is read-only; use set(i, v)`）。

**已裁定（评审一 §3、§6 Q1）**：

| 项 | 裁定 |
| --- | --- |
| 是否立项 | **接**，按 `custom-index-protocol.md` 的 `RL1-D*` / `RL1-L*` / `RL1-E*` 验收 |
| 签名匹配 | **方案 A**：方法名 + 参数个数 + 非 `static`；不做调用点参数类型匹配 |
| 分名 | JSON 侧用 `get_idx(int)` 与 `get(char *)` 两个名字，同一类型不同时重载 `get` |
| 覆盖层级 | **只覆盖单层**；`p[k]`（`p` 为用户类型指针）保持 C 指针算术 |
| 多级访问 | 由包层返回值类型承担（`get` 返回 `JsonRef` 值并给 `JsonRef` 实现 `get`），语言侧不扩 |

**代码锚点（行号已漂移，S0 必须重定位）**：

| 主题 | 位置 |
| --- | --- |
| `container_index_check`（V29-4 的拒绝守卫） | 评审一实测在 `selfhost/ct-ast/frontend/parse/Expr.h.ct:3870-3883`；草案 §2.3 的 `:3729-3742` 已过期 |
| `[` 后缀解析与 `Vec` / `Map` 糖 | 草案记 `Expr.h.ct:3957-4007`，S0 复核 |
| 固有方法查找 | `Expr.h.ct` 的 `inst_inherent_method`，S0 复核 |
| 静态类型推导 | `Expr.h.ct` 的 `static_ctype`，S0 复核 |
| `N_MCALL` 发射 | `Emitter.h.ct` 的 `N_MCALL` 分支（`:4863` 起） |

## 1 目标 / 非目标

### 1.1 目标

| 编号 | 内容 |
| --- | --- |
| RL1-O1 | 读形态：`obj[k]` → `obj.get(k)`，覆盖非泛型 struct 与泛型实例 |
| RL1-O2 | 写形态：语句 `obj[k] = v;` → `obj.set(k, v);`，只收左值接收者 |
| RL1-O3 | 诊断 RL1-L1–RL1-L9 全部编译期硬错并指名类型，不落 `.c` |
| RL1-O4 | C 数组 / 指针 / `Vec` / `Map` 的既有语义与文案逐字不变（`RL1-D8` / `RL1-E5` / `RL1-E6`） |
| RL1-O5 | **单层边界写进判据**：新增 `RL1-E11` 锁死 `p[k]`（`p: struct X *`）保持 C 语义，并在文档写明 |

### 1.2 非目标

| 不做 | 理由 |
| --- | --- |
| 方案 B：按参数类型选 `get`（同类型 `get(char*)` + `get(int)`） | 需要调用点重载解析与新的诊断族；评审一 §3 判为独立需求，不借 L1 的壳 |
| 指针接收者进入协议 / 连写下标 `v["a"]["b"]` | `RL1-D8` 明确不做；多级由包层返回值类型承担 |
| 其他运算符重载（`+` / `==` / `()`） | 只做 `[]` |
| trait 提供的 `get` / `set` | 只认固有方法；trait 方法可能来自 vtable，会改变派发语义 |
| `set`-only 类型 | 读形态是写形态的解析前置，v1 要求 `get` 存在 |
| 文件作用域 / 常量初始化器里的自定义下标 | 无接收者静态类型可判 |

## 2 设计决定

| 编号 | 决定 | 为什么不用另一种 |
| --- | --- | --- |
| **D52-1** | 沿用 `RL1-D1`–`RL1-D8`，不重写草案的决策体系 | 评审一 §3 已确认草案是现成可排期路径；重写会引入两套编号 |
| **D52-2** | 签名匹配只认「名 + 参数个数 + 非 `static`」（方案 A） | 方案 B 要动 `static_ctype` 与重载解析，回归面大于收益；JSON 已接受 `get_idx` 分名 |
| **D52-3** | `p[k]` 保持 C 指针算术，**不**进协议；新增 `RL1-E11` 断言该口径 | 指针协议要定义「值 / 指针同一协议」与自动解引用，成本远高于 L1 |
| **D52-4** | 写形态只收语句位置 + 左值接收者；复合赋值 / 取地址 / `own` 右值各一条硬错 | 复用 `RL1-L6`–`RL1-L9`；右值接收者会被发射成临时量，写入静默丢失 |
| **D52-5** | 缺协议是硬错，不回退 C 下标 | 回退正是「`ct-ast` rc=0、`cc` 才报错」的根因 |

## 3 诊断

沿用草案编号与文案（S1 冻结后逐字断言，位置一律指向 `[` 的 `file:line:col`）：

| 编号 | 触发 | 文案（草案） |
| --- | --- | --- |
| RL1-L1 | 无 `get` | `type 'X' has no subscript: declare 'V get(K)' in impl X` |
| RL1-L2 | 有 `get` 无 `set`，写形态 | `type 'X' has a read-only subscript: declare 'void set(K, V)' in impl X` |
| RL1-L3 | `get` 参数个数 ≠ 1 | `type 'X' has no subscript: 'get' must take 1 parameter` |
| RL1-L4 | `set` 参数个数 ≠ 2 | `type 'X' has no writable subscript: 'set' must take 2 parameters` |
| RL1-L5 | `get` / `set` 是 `static` | `type 'X' has no subscript: 'get' must be an instance method` |
| RL1-L6 | `+=` / `++` / `--` | `a custom subscript supports only '='; use set(k, v)` |
| RL1-L7 | `&obj[k]` | `cannot take the address of a custom subscript; bind it to a local first` |
| RL1-L8 | 写形态非语句或接收者非左值 | `a custom subscript write needs a statement and an lvalue receiver` |
| RL1-L9 | 右值是 `own` / `borrow` 变量 | `a custom subscript set cannot take an 'own' or 'borrow' value` |
| RL1-E11 | （判据，非诊断）`p[k]` 保持 C 语义 | 文档写明「用户类型指针不进协议」；不新增文案 |

## 4 任务切分

| 切片 | 内容 | 边界 |
| --- | --- | --- |
| **S0** | 只读核查：重定位上述锚点、复核 `static_ctype` 覆盖形态、`inst_inherent_method` 约束、草案 §2.2 红证复跑；记 `baseline: <sha>` | 不产提交 |
| **S1** | 红证：`p52_read` / `p52_write` / `RL1-L1` 负例（先跑出 `cc` 报错或缺失诊断） | 只含夹具与 `baseline:` |
| **S2** | 读形态 + 缺协议硬错（`RL1-L1` / `RL1-L3` / `RL1-L5`） | ≤3 文件 |
| **S3** | 写形态 + 左值/语句判定（`RL1-L2` / `RL1-L4` / `RL1-L6`–`RL1-L9`） | 复用 `RL1-L8` 判定 |
| **S4** | 泛型实例类型名还原（`RL1-D6`）+ C 数组/指针透传 + `RL1-E11` | 只补分支，不改容器路径 |
| **S5** | 文档：spec 新增小节（中英对称）+ `bindings-and-patterns.md` 一处；spec 冲突记 `blocked-by` | 由本相独占编号 |
| **S6** | 收口：11 道门禁全绿、bump `0.52.0` | 收口 |

依赖：S0 → S1 → S2 → S3 → S4 → S5 → S6；每片 ≤150 行、≤3 文件。

## 5 完成定义（四件套）

| 面 | 交付 |
| --- | --- |
| 实现 | 读 / 写形态与九条诊断全部生效；`Vec` / `Map` / C 下标零变化 |
| 诊断 | RL1-L1–L1-L9 各一条负例，文案与位置逐字命中，不落 `.c` |
| 文档 | 自定义下标协议、单层边界、`get_idx` 分名建议、`p[k]` 不做口径 |
| 门禁 | 夹具进 `check-ast.sh`；`RL1-E5` / `E6` 逐字不变；`check-all.sh` 11 道全绿 |

## 6 验收

| ID | 断言 | 命令 / 阈值 |
| --- | --- | --- |
| **RL1-E1** | 非泛型 `struct X` + `int get(int)`：`x[1]` 展开为 `x.get(1)`，可编译运行 | 夹具 `p52_read` |
| **RL1-E2** | 泛型 `Box<int>` + `get`：同样展开，无模板名残留 | 夹具 `p52_generic` |
| **RL1-E3** | `void set(int,int)`：`x[1] = 9;` 展开为 `x.set(1,9)`，读回 9 | 夹具 `p52_write` |
| **RL1-E4** | RL1-L1–RL1-L9 各一条负例，`file:line:col` 与文案逐字命中 | `p52_errors.sh` |
| **RL1-E5** | C 数组、`int *`、`struct X *` 下标语义与产物不变 | 夹具 `p52_c_passthrough` |
| **RL1-E6** | `Vec` / `Map` 的 L31-3 / L31-4 文案与产物逐字不变 | 既有负例继续绿 |
| **RL1-E7** | 同一负例在 `ct-ast` 与 `ct check` 下同文案、同位置 | 双模式断言 |
| **RL1-E8** | 自举 fixpoint 通过 | `check-ast.sh` self-hosting 段 |
| **RL1-E9** | 全量门禁零失败 | `check-all.sh` 11 道 |
| **RL1-E10** | 任务清单每项可独立验收 | 本卡 §4 的 verify 逐条 |
| **RL1-E11** | `p["k"]`（`p: struct X *`）**不**进入协议：仍是 C 语义（字符串键由 `cc` 报错、数字键是指针算术），文档写明；`v["a"]["b"]` 不在本相验收内 | 夹具 `p52_ptr_receiver` + spec 句 |
| **RL1-E12** | JSON 侧单层可用：`v["k"]` 编译并返回正确节点；`v[0]` 在方案 A 下是硬错（提示 `get_idx`） | 夹具 `p52_json_single` |

## 7 风险与不做项

| 编号 | 风险 / 不做项 | 触发信号 | 处置 |
| --- | --- | --- | --- |
| R52-1 | 验收里出现 `v["a"]["b"]` | 评审或包方按连写排期 | RL1-E11 锁单层；多级归包层 `JsonRef` |
| R52-2 | `static_ctype` 对复杂接收者推不出，糖不生效、退回 C 下标 | `f().box[k]` 形态 | `RL1-R1`：只对可解析接收者承诺；失败不静默（硬错而非回退） |
| R52-3 | 右值接收者写入丢失 | `make()[0] = 1;` 通过 | `RL1-L8` 硬错；夹具锁 |
| R52-4 | 泛型还原失败，文案给 `Box_int` | 泛型上触发 L1 | `RL1-D6`：先 `ct_impl_inst` 还原，失败才退回 C 拼写 |
| R52-5 | 草案锚点继续漂移 | S0 直接引用旧行号 | 本卡已标注「行号已漂移，S0 重定位」；卡内不写死易漂行号 |
| R52-6 | 被要求扩成方案 B | 评审提出「同类型两个 get」 | D52-2 已明写另立需求；不临时扩面 |
