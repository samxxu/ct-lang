# c-superset — ct 作为 C 超集的样例

这一组样例专门覆盖「CT 作为 C 超集」的那一半能力：源文件是普通 C，ct 负责
把它原样（或近似原样）发射成 C，语义与限制由真实编译结果说话。

- 与 `examples/tour/` 相互独立：这里不引用、不修改 tour 的任何文件。
- 每个特性至少两个角度：一个最小演示 + 一个真实场景，或一个纯语法例子 +
  一个与 CT 特性混用的例子。每个角度都有自己的 `expected.out` 断言。
- 反例单独成文件，断言的是 ct 的退出码与 stderr 中的诊断文本。

## 运行

```sh
bash examples/c-superset/run.sh              # 全部
bash examples/c-superset/run.sh s04_         # 只看 s04 开头
CT=/path/to/ct bash examples/c-superset/run.sh
CC=clang bash examples/c-superset/run.sh
```

不设置 `CT` 时，`run.sh` 依次尝试仓库根目录的 `./ctc`、PATH 上版本不低于
0.23 的 `ct`；都没有就用 `selfhost/l0/ctc.c` 自举 L0 → L1 → L2 → ct-ast，
全部构建在 `$TMPDIR` 下，不往仓库写文件。

### 判据

对每个 `run` 样例：

1. `ct <case>.ct -o x.c` 必须以 0 退出。
2. `cc -Wall -Wextra -std=c99 x.c` 必须零警告地编过。
3. 程序以 0 退出，stdout 与 `<case>.out` **逐字节**一致。
4. 若存在 `<case>.orig.c`（与 `.ct` 逐字节相同），再用同一个 cc 编译运行，
   stdout 也必须与 `<case>.out` 一致——这就是「这段 C 原封不动就编过了」的
   证据。共 26 个特性各有一份这样的副本。
5. `cases.tsv` 里 `l0=yes` 的样例，再用冻结的 `selfhost/l0/ctc.c` 复编一次，
   同样要求编译、运行、stdout 一致。L0 生成的 C 允许有 unused 警告，但不允许
   编不过。

对 `neg` 样例：ct 必须以 1 退出，stderr 必须包含 `<case>.err` 的每一行。
对 `ccfail` 样例：ct 必须成功，cc 必须失败（用于「断言失败应由 C 判定」）。

## 能力矩阵

| 目录 | 规范 | 角度 A | 角度 B | 反例 | L0 |
|---|---|---|---|---|---|
| `s01_switch` | §4.13 | 枚举分派、fallthrough、default | `case` 取值用位移/字符/`sizeof`，标签后用块包声明 | 标签后裸声明被拒 | yes |
| `s02_do_while` | §4.13 | 先执行后判断，条件初始为假也跑一次 | 无花括号体、`break` 提前结束 | — | yes |
| `s03_goto` | §4.16 | 向前 `goto` 跳出两层循环 | 向后 `goto` 手写循环 + 清理标签 | — | yes |
| `s04_enum` | §4.14 | 隐式/显式枚举值、typedef、switch | `offsetof` 查 struct/union/typedef 别名 | 字段名拼错由 ct 报错 | yes |
| `s05_union` | §4.15 | 带 tag 的 variant | union 作为 struct 成员、typedef 别名 | union 不能 use trait | yes |
| `s06_bitfields` | §4.17 | 命名/无名位域，赋值截断 | 一条声明多个位域、枚举位宽 | 指针位域被拒 | yes |
| `s07_anon_members` | §4.18 | 匿名 union/struct，名字提升 | 匿名记录里再嵌位域 | 匿名字段带名字被拒 | yes |
| `s08_static_local` | §4.19 | static 计数器、零初始化、static 字符串 | 只建一次的 static 表 | 裸 `static;` 被拒 | yes |
| `s09_compound_literal` | §4.20 | 复合字面量作值/实参/返回值 | 指定初始化 + 直接 `.field` | 指针型、数组型被拒 | yes |
| `s10_empty_for_static` | §4.21 | for/while/if/switch/标签的空语句 | `for (static int i = 0; ...)` 只初始化一次 | — | yes |
| `s11_type_words_inline` | §4.23 | volatile/restrict/bool/int32_t | `static inline` 与 `inline static`、MMIO 寄存器 | `inline` 修饰对象被拒 | yes |
| `s12_float_literals` | §4.24 | `.5`、`1.5e3`、`f/F/L`、截断 | double/float 运算 + 定点打印 | 浮点 case 标签被拒 | yes |
| `s13_case_ranges` | §4.25 | 分数区间 | 字符区间与单值标签混排 | 缺下界被拒 | yes |
| `s14_static_assert` | §4.26 | 文件/函数作用域断言、`static_assert` 拼写 | `offsetof`/union 大小断言 | 非常量条件被拒；假断言由 cc 判 | 部分（见下） |
| `s15_multi_declarators` | §4.27 | `len, cap` / `*data, count` / 位域成列 | `struct Node *next, *prev` | 函数指针多声明被拒 | yes |
| `s16_array_length` | §4.28 | 宏/位移/括号维度 | 运行期长度（VLA） | — | yes |
| `s17_init_length` | §4.30 | 超长关键字表（32 项） | 单个 >160 字节的字符串项 | — | yes |
| `s18_comma` | §4.32 | for 初始化/步进子句 | 括号内取值位置 | for 条件裸逗号被拒 | yes |
| `s19_header_typenames` | §4.33 | `time_t` 声明/参数/cast | `clock_t`/`off_t` 数组、指针、参数 | — | yes |
| `s20_c11` | §4.35 | `_Alignas`/`_Alignof`/`_Atomic` | `_Generic` 类型选择 | `_Alignof x` 被拒 | yes |
| `s21_attribute` | §4.36 | packed、aligned、format | 声明符前缀属性 | 未闭合属性被拒 | 部分（见下） |
| `s22_int_suffixes` | §4.37 | `U/L/ULL` 大小写与规范化 | `_Noreturn`、`static_assert`、`__restrict` | `1UU` 被拒 | 部分（见下） |
| `s23_header_order` | §4.38 | `_Alignas`/属性写在存储类之前 | `_Atomic(type)` / 裸 `_Atomic` 叠加对齐 | 重复 `_Alignas` 被拒 | yes |
| `s24_prefix_incdec` | §4.29 | 前缀 ++/-- 作值 | `s[--n]` 裁尾循环 | — | yes |
| `s25_assignment_value` | §4.34 | while/if 条件里赋值、右结合链 | 下标/成员/复合赋值作值 | 常量作赋值目标被拒 | yes |
| `s26_variadic_fnptr` | §4.31 | 变参函数指针字段/全局 | 函数指针数组与局部指针 | `(...)` 被拒 | yes |

`cases.tsv` 是权威清单：`feature|case|mode|l0|expect_exit|note`。

## 实测出来的已知限制

以下都是跑出来的，不是照规范推的：

1. **L0 不映射 `static_assert`。** L0 把它原样发射成函数调用，cc 报
   `call to undeclared function 'static_assert'`。`_Static_assert` 则能过。
   所以 `s14_static_assert/sizes` 与 `s22_int_suffixes/spellings` 标 `l0=no`，
   而只写 `_Static_assert` 的 `s14_static_assert/offsets` 标 `l0=yes`。
2. **L0 会丢掉记录体之后的 `__attribute__`。** `struct S { ... } __attribute__((packed));`
   在 L0 的输出里没有属性，`sizeof` 从 5 变 8；前缀属性（`s21_attribute/prefix`）
   L0 能保留。所以 `s21_attribute/packed` 标 `l0=no`。
3. **标签后不能写裸声明。** C 允许 `case 1: int x;`（作用域陷阱），ct 要求
   包进块；见 `s01_switch/neg_decl`。
4. **`static_assert` 在 ct-ast 里不需要 `<assert.h>`**：生成物统一是
   `_Static_assert`。但同一份源文件直接交给 `cc -std=c99` 会失败，所以
   `s14_static_assert/sizes` 没有 `.orig.c` 零改写副本。
5. **断言消息可以省略，但 C99 下会告警。** ct 接受
   `_Static_assert(cond);` 并发射不带消息的断言；clang 在 `-std=c99` 下报
   `-Wc23-extensions`。本目录要求 cc 零警告，所以正例统一带消息。这是实测
   行为，不是「规范写了就能用」。
6. **`_Generic` 整段透传。** 控制表达式与所有分支都不经过 ct 重写，分支里不能
   放 trait 调用/装箱这类 CT 语法。
7. **`_Atomic` 只验证语法。** 原子性、`atomic_*` 内建、内存序都不在本组样例里，
   语义完全由 cc 负责。
8. **for 初始化子句里的 `static` 不是标准 C**（GNU 扩展）；ct 把它发射成
   `{ static int i = 0; for (; ...; ...) }`，生成的 C 是标准 C99。
9. **case 范围是 GNU/C23 扩展**，需要 cc 接受；clang 与 gcc 在 `-std=c99` 下
   接受且不告警（本目录用零改写副本验证过）。
10. **匿名成员是 C11 语法**；clang/gcc 在 `-std=c99` 下接受且不告警
    （`s07_anon_members/variant.orig.c` 直接编过）。
11. **VLA 不做 sizeof 折叠**：`s16_array_length/vla` 的维度是变量，长度在运行期
    才确定。
12. **`offsetof` 需要源文件自己包含 `<stddef.h>`**：ct 没有预处理器，只把
    `offsetof(...)` 原样发射；字段校验是 ct 内建做的。
13. **union 不能 `use` trait**：vptr 字段无处安放，ct 直接拒绝
    （来源：`s05_union/neg_use`）。
14. **边界语法**：`_Alignof` 只接受类型形式；`_Alignas` 重复报错；指针位域、
    多声明符函数指针、for 条件里的裸逗号、数组型复合字面量都被 ct 拒绝，
    对应 `neg_*` 文件。
15. **`__attribute__` 的语义完全交给 cc**；ct 只检查括号闭合、去重并规范化
    发射位置。属性能否用于某个对象由 cc 决定。局部前缀属性带初始化器时，
    生成物是 `int v __attribute__((unused)) = 5;`（见 `s21_attribute/prefix`）。
16. **成功样例要求 cc 零警告。** 例如位域演示用变量（而不是字面量 300）赋值，
    避免 `-Wbitfield-constant-conversion`，同时仍能看到截断到 44 的结果。

## 目录约定

```
examples/c-superset/
  README.md
  run.sh
  cases.tsv
  s01_switch/
    dispatch.ct        # 样例源文件
    dispatch.out       # 逐字节期望 stdout
    dispatch.orig.c    # 可选：与 .ct 逐字节相同的 C 对照
    neg_decl.ct        # 反例源文件
    neg_decl.err       # 期望 stderr 包含的诊断行
```

新增样例时：在 `cases.tsv` 加一行，放好 `.ct` 与 `.out`（或 `.err` / `.ccerr`），
`run.sh` 开头的 manifest audit 会检查每个 `.ct` 都有清单行、每个清单行都有
对应文件。
