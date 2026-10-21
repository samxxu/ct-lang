# SH-8 · ct-ast 不校验 impl 完整性，缺方法时生成 NULL vtable 槽并在运行期段错误

| 项 | 值 |
| --- | --- |
| 模块 | selfhost（ct-ast） |
| 严重度 | **High** |
| 锚点 | commit `dde0dda`（2026-10-21） |
| 文件 | [selfhost/ct-ast/frontend/parse/Parser.h.ct](../../selfhost/ct-ast/frontend/parse/Parser.h.ct)、[selfhost/ct-ast/backend/emit/Emit.h.ct](../../selfhost/ct-ast/backend/emit/Emit.h.ct) |
| 状态 | ✅ 已修复（2026-10-21，`frontend/parse/Parser.h.ct` 的 impl 收尾处校验；`test/ast/errors/missing_method.ct` + `check-ast.sh` 断言） |

## 现象

trait 声明 2 个方法、impl 只实现 1 个时，ct-ast **静默接受**（`exit=0`），生成一份缺失槽位、
其余为零的 vtable。C 编译通过，调用未实现的方法直接 `SIGSEGV`。

## 证据

最小复现（`/tmp/rev22/tut/missing2.ct`）：

```c
#include <stdio.h>
trait G { void a(); void b(); }
struct P { int x; } use G;
impl G for P { void a() { printf("a\n"); } }
int main(void) { P p; p.b(); return 0; }
```

```
$ ct missing2.ct -o missing2.c ; echo $?
0
$ cc -Wall -Wextra missing2.c -o missing2 && ./missing2 ; echo $?
139
```

生成物（缺 `.b`）：

```c
static struct G_vtbl P_G_vtable = { .a = P_G_a };
```

对差（同一输入）：

| 编译器 | 结果 |
| --- | --- |
| L0（`ctc.c`） | `exit=1`，`missing2.ct:4:14: error: trait method 'b' is not implemented for struct 'P'` |
| L2（回归 oracle） | 同上 `exit=1`，并追加 `ctc: 1 error(s) generated` |
| ct-ast（安装入口） | `exit=0`，运行期 139 |

L0/L2 的这条诊断有负例 `test/errors/missing_method.expected-err`；`selfhost/check-ast.sh` 没有对应用例，
所以关卡全绿也发现不了。

装箱路径同样不报错：把不完整的 `P` 装进 `G` 形参后调用 `g.a()` 能过，`g.b()` 依旧崩。

## 影响

- 这是**主线编译器相对其回归 oracle 的能力退化**：同样的源码，用 `ctc` 编译被拒绝，用安装的 `ct`
  编译却得到会在运行期崩溃的二进制。
- 违反 AGENTS §4「不允许生成明知编译不过的 C 代码来糊过去」的精神——这里是能静态判定却没有判。

## 修复建议

1. 在解析/绑定阶段（impl 收尾处）取 trait 的 `m[]`，逐个核对 impl 里同名方法的数量与签名个数；
   缺任一方法即 `die`，文案与 L0/L2 对齐（`trait method 'b' is not implemented for struct 'P'`）。
2. 在 `selfhost/check-ast.sh` 的负例段补一条，断言非零退出且文案包含 `is not implemented`。

## 验证

- 上面的最小复现：`ct` 必须 `exit=1` 且文案含 `is not implemented`。
- 回归面：`bash selfhost/check-ast.sh`（自编不动点 + 全量语料等价）、`bash test/acceptance/run.sh`、
  `bash selfhost/check-all.sh` 八关全绿。
