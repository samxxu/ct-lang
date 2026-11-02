# 检查清单：头文件里的类型名（第二十五批）

依据：`docs/design/batch25-header-type/spec.md` / `tasks.md`
全部打勾才算收口。

## 语法与语义

- [x] 全局 `static time_t g_base;` 正确
- [x] 结构体字段 `time_t when;` 正确
- [x] 函数参数 `show(time_t t, …)` 正确
- [x] 局部 `time_t now;` 与 `clock_t ticks;` 正确
- [x] 指针形式 `time_t *ref;` 正确（未知名 + `*` + 名字）
- [x] 变量相乘 `k = i * j;` 仍是表达式（符号表否决生效）
- [x] `return found;` / `goto done;` / `own Box *b` 仍按语句解析
      （32_goto 与 own_in_switch 两个既有用例全绿）
- [x] 既有全套 fixture 输出不变

## 诊断

- [x] 本批不新增诊断，也不放宽既有诊断
- [x] 转换与 `sizeof` 里的未知类型仍按表达式解析（保持保守，已写入 §4.33）

## 回归与关卡

- [x] `bash selfhost/check-ast.sh` → 274 passed, 0 failed（含 50_header_type）
- [x] `bash selfhost/check-warnings.sh` → 140 ok, 0 failed
- [x] `bash selfhost/check-all.sh` → `check-all: OK (9 hard gates green)`
- [x] 未新增 impl 方法（预算 255/256）、未新增节点编号
- [x] `git status` 无 `test/cases/**`、`examples/**` 的 `.expected.*` 变化
- [x] `CTC_VERSION` 未变

## 探针

- [x] ct-ast 仍完整编译 `selfhost/l0/ctc.c`，无诊断
- [x] L2 与 ct-ast 对 `time_t now;` 的行为已一致（此前 ct-ast 报错）

## 文档

- [x] `docs/language-spec.md` 新增 §4.33（中文 + 英文）
- [x] 文档写明判据（非登记类型、非变量/函数、非语句关键字）与不做的转换/`sizeof`

## 提交

- [x] 代码 + fixture + 关卡一个提交
- [x] spec 与文档一个提交
- [x] 提交正文说明动机（与 L2 的行为差）与验证方式
