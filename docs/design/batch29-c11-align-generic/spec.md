# 第二十九批特性：C11 对齐与泛型选择（2026-10-31）

> 锚点：`68796f6`（v0.13.0 收口），工作树干净。
> 实测缺口：`_Alignas(16) int x;` / `_Alignof(int)` / `_Generic(x, int: f, default: g)`
> 在 ct-ast 下都报 `unexpected token`（L0 / L2 是透传，不受影响）。

## 1. 实测现状

- ct-ast 重新发射已实现的 C 子集，`_Alignas` / `_Alignof` / `_Generic` 三个 C11 拼写
  不在解析器里，声明位置与表达式位置都会落到「未知标识符 + 声明符」的兜底判断上失败。
- 三者都只需要「把原文交给 C 编译器」：对齐说明符与对齐查询的类型由 C 决定，
  `_Generic` 的分支选择也由 C 决定，ct 没有可记的语义。

## 2. 决策

- **D-1 `_Alignas` 进类型拼写**：`parse_type` 识别 `_Alignas`，把 `_Alignas ( … )`
  原样追加到类型字符串前，再继续读取其余说明符。全局、局部、字段、参数、`typedef`
  五个入口因此同时生效，发射端不需要知道它的存在。
- **D-2 不把 `_Alignas` 当类型关键字**：它进 `is_type_word` 会让 `(…)` 转换判断与
  `next_is_type_name` 误判；只在 `Stmt::is_decl_start` 显式接受「以 `_Alignas` 开头
  的声明」，块作用域才能写。
- **D-3 `_Alignof` 复用 `sizeof` 节点**：`N_SIZEOF` 的 `aux` 1 是 `sizeof(type)`、
  2 是 `_Alignof(type)`，发射端按 `aux` 选关键字。只接受类型形式（C11 也只允许类型），
  操作数形式报 `_Alignof needs a type in parentheses`。
- **D-4 `_Generic` 整段透传**：与第 21 批的长初始化器同机制——表达式位置识别
  `_Generic`，把 `_Generic ( … )` 的 token 原文（token 之间补空格）写进 arena 字符串池，
  建一个 `N_RAW`（`aux = 1`、`num` = 池内偏移），发射端原样打印。分支由 C 编译器选择，
  ct 不读分支，因此分支里的 trait 调用 / 装箱**不会**被重写。
- **D-5 整数 token 取数值**：整数 token 的 `toktext` 不保留拼写，重建原文时用 `toknum`
  （十进制）；浮点与字符串仍用 `toktext`（前者本来按拼写保存，后者带引号与转义）。
- **D-6 顺序边界**：`static _Alignas(16) int g;` 可用；`_Alignas(16) static int g;`
  不接受（`_Alignas` 在顶层不是前缀关键字）。写进 §4.35。

## 3. 影响面

- 改：`frontend/parse/Expr.h.ct`（`parse_type` 的 `_Alignas` 分支、`parse_unary` 的
  `_Alignof`、`parse_primary` 的 `_Generic`、`T_EOF` 常量）、
  `frontend/parse/Stmt.h.ct`（`is_decl_start` 一行）、
  `backend/emit/Emit.h.ct`（`N_SIZEOF` 按 `aux` 选关键字）。
- **impl 方法预算**：不新增方法（255/256），不新增节点编号（`N_RAW` / `N_SIZEOF` 复用）。
- 不动：`TypeCheck` / `Symbols` / `ctc.c` / `l1` / `l2`、`CTC_VERSION`、golden。

## 4. 验证

- 新增 `test/ast/53_c11_align_generic`：全局 / 局部 / 字段三种 `_Alignas`，
  地址取模为 0；`_Alignof(char / int / double / struct)` 的相对关系；
  `_Generic` 按 `int` / `double` / typedef `myint` / `int *` 选不同分支。
- 负例三条（`check-ast.sh` 精确断言消息）：`alignas_no_paren.ct`、
  `alignof_operand.ct`、`generic_no_paren.ct`。
- 回归：clang 与 GNU GCC 16 都能零告警构建生成物并给出同一输出；
  `ctc.c` 探针与 L0 种子关卡不变。
- 关卡：`check-ast.sh` / `check-warnings.sh` / `check-all.sh` 如实记录。
