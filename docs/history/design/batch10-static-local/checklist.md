# 检查清单：`static` 局部变量（第十批）

依据：`docs/design/batch10-static-local/spec.md` / `tasks.md`
全部打勾才算收口。

## 语法与语义

- [x] `static int n = 0;` 在函数体内编译并运行正确，生成物带 `static` 前缀
- [x] 取值跨调用保持（`next_id` 连续调用得 3、4）
- [x] 块内的 static 同样跨调用保持（`block_once` 得 1、2）
- [x] 未写初始化器的 static 按 C 规则零初始化（`static int calls;`）
- [x] static 数组带初始化器（`static int tbl[3] = { 1, 2, 3 };`）
- [x] static 字符串指针（`static const char *msg = "hi";`）
- [x] static struct + trait：vptr 以常量初始化器补上，方法调用正确
- [x] 成员访问 / 数组下标 / 方法调用的类型推断与普通局部一致

## 诊断与交互

- [x] `static own T *p = malloc(…)` 报 `a static local cannot be 'own'`
- [x] `static;` 报 `expected a declaration after 'static'`
- [x] static 声明不进泄漏分析（`static T *p = malloc(…)` 不报泄漏）
- [x] `static` 跟在 `case` / goto 标签后仍报「声明不能跟在标签后」
- [x] 以上均带 `file:line:col:`

## 回归与关卡

- [x] `bash selfhost/check-ast.sh` → 239 passed, 0 failed（含 35_static_local 与 batch 10 两条消息）
- [x] `bash selfhost/check-warnings.sh` → 125 ok, 0 failed
- [x] `bash selfhost/check-all.sh` → `check-all: OK (9 hard gates green)`
- [x] 未新增 impl 方法（L2 预算 255/256 不变）
- [x] `git status` 无 `test/cases/**`、`examples/**` 的 `.expected.*` 变化
- [x] `CTC_VERSION` 未变

## 文档

- [x] `docs/language-spec.md` 新增 §4.19 静态局部变量（中文）
- [x] 同节英文更新，与中文一一对应
- [x] §4.9 的约束列表补一条「static 局部不能是 own」（中英对称）
- [x] 文中写到的形态都能在 `test/ast/35_static_local` 或负例里找到对应代码
- [x] 文档写明范围外：`for` 首句的 `static`、标签后的 `static`

## 提交

- [x] 代码 + fixture + 关卡一个提交
- [x] spec 与文档一个提交
- [x] 提交正文说明动机与验证方式，不含无关改动
