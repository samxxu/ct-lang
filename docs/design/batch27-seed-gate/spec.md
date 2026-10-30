# 第二十七批：把 L0 种子纳入关卡（2026-10-31）

> 锚点：`9b27e96`（第二十六批收口），工作树干净。
> 性质：测试基建，不是语言特性。

## 1. 背景

第二十一至二十六批是用「ct-ast 编 `selfhost/l0/ctc.c`」这条探针驱动的：每批修掉
探针撞上的一个缺口，直到探针完整通过（2930 行，生成物可编译，产物当 ctc 能跑通示例）。
但这条能力**只存在于手工验证中**——现有九关没有任何一项会去编 ctc.c，所以任何一个
解析分支收窄回去，关卡仍然全绿。

## 2. 决策

- **D-1 在 `check-ast.sh` 的 9.6 之后新增一节**「the L0 seed」，排在 summary 之前；
  一条断言串起四步：
  1. `ct-ast compile selfhost/l0/ctc.c` 成功；
  2. 生成的 C 用 `$CC -Wall -Wextra -std=c99` 编成可执行文件；
  3. 该可执行文件（即 ct-ast 编出的 ctc）编 `examples/01_greeter/greeter.ct`；
  4. 再编再跑，与 `greeter.expected.out` 逐字节比对。
- **D-2 失败信息取四个日志的前 5 行**（解析、生成物编译、示例编译、示例运行），
  和本脚本其它断言的风格一致。
- **D-3 全部写在 `$work` 下**，不污染仓库；不引入新脚本、不新增构建步骤。

## 3. 影响面

- 只改 `selfhost/check-ast.sh`：头注释一行 + 一节断言（+1 断言）。
- 不碰编译器源码、不新增 impl 方法、不动 `CTC_VERSION` 与 golden。

## 4. 验证

- `bash selfhost/check-ast.sh` → 276 passed, 0 failed（新增项为
  `L0 seed (ctc.c compiles; the result builds and runs an example)`）。
- `bash selfhost/check-warnings.sh` → 141 ok, 0 failed。
- `bash selfhost/check-all.sh` → 9 hard gates green。
- 手工确认过的新断言覆盖：解析（ctc.c 全量）、生成物编译（零错误）、
  端到端（示例输出与 `.expected.out` 一致）。
