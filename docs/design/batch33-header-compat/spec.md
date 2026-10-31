# 第三十三批：真实头文件兼容（2026-10-31）

> 锚点：`249447a`（第三十二批收口），工作树干净。
> 决策依据：`docs/design/next-decisions.md`（容量选 A、批 33 选 H）。
> 实测缺口（ct-ast）：
> - `_Atomic(int) a;` → `expected a name`；
> - `_Alignas(16) static int g;` → `unexpected token`；
> - `__attribute__((unused)) static int g;` → `expected a name`；
> - 局部变量属性 `__attribute__((unused)) int x = 1;` → `expected an expression`。

## 1. 现状

- `_Atomic` 不在类型词表里；它此前能工作只是因为「未知名 + 声明的类型」这条兜底：
  `_Atomic int x` 被拼成 `_Atomic int`。带括号的 `_Atomic(int)` 在 `(` 处断开。
- `_Alignas(…)` 由 `parse_type` 在类型拼写里原样透传，因此 `static _Alignas(16) int g;`
  可用；反过来 `_Alignas(16) static …` 时 `parse_type` 停在 `static`，声明入口把
  `static` 当成变量名。
- `__attribute__((…))` 只在**声明尾部**捕获（`attr_pool` 在 `ParseOps` 上）。
  声明符之前的属性没有入口；局部变量两种位置都不支持。
- `attr_pool` 在 `Parser` 上，`Stmt` 没有指向 `Parser` 的引用（互相 import 也不行），
  所以局部属性无法复用捕获逻辑。

## 2. 决策

- **D-1 `_Atomic(type)` 与裸 `_Atomic`**：`parse_type` 把两者都按「带括号的说明符」
  透传——`_Atomic` 后紧跟 `(` 时捕获整段平衡括号，否则只记下这个词、由下一轮继续读
  `int`。`next_is_type_name` 同样识别 `_Atomic(…)`（跳过平衡括号与可选 `*` 后要求
  cast 的 `)`），所以 `sizeof(_Atomic(int))` 与 `(_Atomic(int))x` 都走类型路径；
  块作用域的 `is_decl_start` 把 `_Atomic` 记为声明开头。
- **D-2 `_Alignas` 可以在存储类之前**：`top_decl`（文件作用域）与 `parse_stmt`
  （块作用域）在声明开头**只**捕获 `_Alignas(…)` 这一段（平衡括号、token 原文），
  放进 `Expr.decl_prefix`，然后递归走普通声明分支；`parse_type` 在入口把
  `decl_prefix` 前置进类型拼写并清空。于是两种顺序都接受，发射统一为规范顺序
  `static _Alignas ( 16 ) int g;`（与 §4.35 既有口径一致）。
- **D-3 声明符之前的 `__attribute__`**：
  - `attr_pool` 从 `ParseOps` **移到** `SupportOps`（实现一字不改，只换 `self->sup->`
    为 `self->`），`Parser` 与 `Stmt` 都能调用；impl 方法总数不变。
  - 文件作用域：`top_decl` 捕获后存进 `Parser.pending_attr`（`0` = 无，否则池偏移
    +1，零初始化的单例无需额外初始化），`parse_func` 在入口取走，与尾部的属性合并；
    两者同时出现报既有的 `duplicate __attribute__ on one declaration`。
  - 块作用域：`parse_stmt` 捕获后存进 `Stmt.decl_attr`（同样的 +1 编码），
    `parse_decl_node` 把它写到该声明的每个 `N_DECL.attr` 上；局部变量也接受
    **尾部**属性（`int x __attribute__((unused));`）。
  - 属性不是声明前缀时（`__attribute__((…)) typedef …`、`__attribute__((…)) return`）
    报 `an attribute must prefix a declaration`。
- **D-4 新诊断**：`unterminated _Atomic`、`an attribute must prefix a declaration`、
  `duplicate _Alignas on one declaration`。
- **D-5 预算**：impl 方法已到 `MAX_MAP_IMPLS` 256 的顶（新增一个立即触发
  `too many impl methods for the reverse map`），所以本批**不新增方法**：`attr_pool`
  是搬家，`_Alignas` 的捕获循环在 `Parser` / `Stmt` 两处各写一份（约 20 行），
  换取不动 `selfhost/l2/**`。若后续要继续清理重复，先把上限抬高（需授权）。

## 3. 边界

- 属性仍只支持「声明前缀」与「声明尾部」两种位置；`typedef` / `trait` / `impl` /
  记录定义上的属性仍不支持（前者报错，后者由 C 编译器裁决）。
- `_Atomic` 的值语义（原子操作）完全交给 C 编译器；ct 只保留拼写。
- 不动 L0 / L2、节点编号、`CTC_VERSION` 与既有 golden。

## 4. 观察（不在本批范围）

- **增量构建的缓存会产出不自洽的单元组合（HEAD `249447a` 已可复现）**：
  先完整构建一次 ct-ast，再修改一个被较少单元 import 的解析层文件（如
  `frontend/parse/Parser.h.ct`），在同一输出目录重建，生成的 `Module.h` 会退回未解析的
  `struct Cache`、`main.c` 缺 `cache_get` 原型，C 编译器报
  `incomplete definition of 'struct Cache'`。全新目录重建正常，`check-all` 的九关也全绿
  （关卡每次都用新目录）。怀疑：被判定「命中缓存」的 import 单元没有重新解析，符号表
  缺少它的导出，导致下游重新生成的单元按源名写类型。留给后续批次定位。
  **（第三十四批已定位并修复：编译集合改为脏单元的依赖闭包，见
  `docs/design/batch34-cache-closure/`。）**

## 5. 验证

- 新增 `test/ast/56_header_compat`：`_Atomic(int)` 全局 / 局部 / `sizeof`，
  `_Alignas` 在存储类之前（文件与块作用域，地址取模），声明符前的属性（全局、
  函数原型、局部），局部尾部属性，属性抑制未使用告警。
- 负例：`atomic_unterminated`、`attribute_misplaced`、`attribute_duplicate_local`、
  `alignas_duplicate`（`check-ast.sh` 精确断言）。
- clang 与 GNU GCC 16 零告警构建生成物，输出一致。
- 三关数字如实记录。
