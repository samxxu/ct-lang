# TEST-7 · ct-ast 的生成 C 无逐字节 oracle；§4.12–4.38 共 27 节只有行为探针

| 项 | 值 |
| --- | --- |
| 模块 | testing |
| 严重度 | **High** |
| 锚点 | commit `f4c77b1`（2026-10-31，`v0.13.0`）；基线 `check-all: OK (9 hard gates green)` |
| 文件 | [selfhost/check-ast.sh](../../selfhost/check-ast.sh)、[test/cases](../../test/cases)、[test/ast](../../test/ast) |
| 状态 | 不采纳（已关闭，2026-10-31） |

## 现象

ct-ast（当前安装主线）的判定口径是 D34：**退出码 + 零警告构建 + 程序输出一致**，
不比较生成文本（[check-ast.sh:12-13](../../selfhost/check-ast.sh#L12-L13)、
[:313-314](../../selfhost/check-ast.sh#L313-L314)）。`test/modules` 也只 `cmp expected.out`
（[:390-653](../../selfhost/check-ast.sh#L390-L653)）。因此 ct-ast 的代码生成没有逐字节
oracle——「改写错了但运行输出仍然对」的退化不会被任何门禁发现。

`docs/language-spec.md` §4 有 38 节，其中 **4.12–4.38 共 27 节**（函数指针、`switch`/`do`、`enum`、
`union`、`goto`、位域、匿名成员、`static` 局部、复合字面量、空语句、变参、内建类型、浮点字面量、
`case` 范围、`_Static_assert`、多字段、数组长度、前缀 `++`、长初始化、变参函数指针、逗号表达式、
头文件类型名、表达式赋值、C11 `align`/`generic`、`__attribute__`、C 兼容、头文件兼容等）
**只有 `test/ast/21,25,27–56` 的行为探针，零逐字节 golden**。

## 证据

```bash
# test/cases 仍是 25 个 L0 时代的 golden，不包含 batch 3–35 的任何构造
$ grep -lE 'switch|enum|union|goto|__attribute__|_Static_assert|_Atomic|_Alignas' test/cases/*.ct | wc -l
0

# check-ast.sh 里仅有的两处字节比对都只覆盖「自举源码」这一条窄路径：
$ grep -n "diff " selfhost/check-ast.sh
1893:  diff -r -q … "$work/self1" "$work/self2"    # 自编不动点（同一份 ct-ast 源码）
1924:  diff -q … "test/cases/$b.expected.c"         # L0 种子关（ct-ast 编 ctc.c 后复现 25 个 L0 golden）
```

第 1924 行验证的是「ct-ast 编出的 C 编译器能复现 L0 golden」，**不是 ct-ast 对特性语法的代码生成**；
第 1893 行的不动点只比较 ct-ast 自己的源码，无法覆盖 4.12–4.38 的新构造。

## 影响

现有用例不会因此变红，所以这个问题长期不可见。真正的风险是 silent non-rewrite 类退化：
生成物仍能编译、仍能跑出同样的输出，但改写规则错了（例如把 `switch` 降级成普通语句、把
`enum` 常量发射成未命名常量、位域宽度被忽略）。行为探针的判据（退出码 + 运行输出）对这些
错误天然不敏感。

## 修复建议

1. 至少为 `switch` / `enum` / `union` / `goto` / 位域 / 匿名成员各选一个代表进 `test/cases`
   （新增 `<name>.ct` + `.expected.c`），由 `run.sh` 的 cases 层或 `check-ast.sh` 的等价语料段做
   逐字节比对；
2. 若不希望扩充 `test/cases`（该目录目前由 L1/L2 与 L0 共用），可在 `test/ast/` 下新增
   `prog.expected.c` 并由 `check-ast.sh` 断言 `cmp`，把判据从 D34 的「行为等价」升级为
   「行为 + 文本」双轨；
3. golden 必须由编译器生成后人工核对，禁止手写（AGENTS §6）。

## 验证

新 golden 落地后，故意改坏一处发射（本地实验，不入库）应使 `check-ast.sh` 变红；恢复后九关全绿。

## 处理（2026-10-31）

不采纳完整方案。D34 已把 ct-ast 的判据定为「退出码 + 零告警构建 + 运行输出」；现有三层字节校验覆盖了绝大部分风险：`test/cases` 的 L0/L1/L2 逐字节 golden、ct-ast 自编不动点（对约 1.8 万行产物逐字节比对）、L0 种子关（ct-ast 编出的 C 编译器复现 25 个 golden）。为 27 节各建逐字节 golden 会冻结发射排版，每次改进都要重生成，维护成本高于残余风险；将来若出现「改写错但运行对」的回归，再针对那一节加 golden。

状态行于 2026-11-07 回填为「不采纳」，条目关闭，文件保留。
