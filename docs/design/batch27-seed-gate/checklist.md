# 检查清单：把 L0 种子纳入关卡（第二十七批）

依据：`docs/design/batch27-seed-gate/spec.md` / `tasks.md`
全部打勾才算收口。

## 断言覆盖

- [x] `ct-ast compile selfhost/l0/ctc.c` 成功（2930 行全量解析）
- [x] 生成的 C 用 `$CC -Wall -Wextra -std=c99` 编成可执行文件（零错误）
- [x] 产物（ct-ast 编出的 ctc）能编 `examples/01_greeter/greeter.ct`
- [x] 示例产物运行输出与 `greeter.expected.out` 逐字节一致
- [x] 失败时汇总四个日志的前 5 行，风格与其它断言一致
- [x] 负向验证：临时让前缀 `++`/`--` 分支不生效 → 关卡 exit 1 并报
      `ctc.c:196:53`；恢复后 276 passed、工作树干净
- [x] 全部产物落在 `$work` 下，仓库无新增生成物

## 回归与关卡

- [x] `bash selfhost/check-ast.sh` → 276 passed, 0 failed
- [x] `bash selfhost/check-warnings.sh` → 141 ok, 0 failed
- [x] `bash selfhost/check-all.sh` → `check-all: OK (9 hard gates green)`
- [x] 未改编译器源码、未新增 impl 方法、未新增节点编号
- [x] `git status` 无 `test/cases/**`、`examples/**` 的 `.expected.*` 变化
- [x] `CTC_VERSION` 未变

## 文档

- [x] `docs/design/batch27-seed-gate/` 三件套
- [x] 未改 `docs/language-spec.md`（本批没有语法变化，已在 spec 中说明）

## 提交

- [x] 关卡一个提交
- [x] spec 一个提交
- [x] 提交正文说明动机（探针成果没有关卡守护）与验证方式
