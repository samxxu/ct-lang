# 检查清单：前缀 `++` / `--`（第二十批）

依据：`docs/design/batch20-pre-incr/spec.md` / `tasks.md`
全部打勾才算收口。

## 语法与语义

- [x] `j = ++i` 取更新后的值，`k = i++` 取旧值（`pre 2 1 1`）
- [x] `s[--n]` 作为下标（ctc.c 的 `while` 收缩写法）编译并运行正确
- [x] `a[--i] = 7` 作为赋值左值正确（`index 1 7`）
- [x] `*(--p)` 与指针算术配合正确（`ptr 3 2`）
- [x] 前缀形式与 `-` `!` `~` `&` `*` 同级（`*--p` 无需额外括号）
- [x] 后缀 `i++` / `p--` 与既有 fixture 全部不受影响

## 诊断

- [x] 本批不新增诊断
- [x] `++` / `--` 后缺操作数仍报既有 `expected an expression`

## 回归与关卡

- [x] `bash selfhost/check-ast.sh` → 265 passed, 0 failed（含 45_pre_incr）
- [x] `bash selfhost/check-warnings.sh` → 135 ok, 0 failed
- [x] `bash selfhost/check-all.sh` → `check-all: OK (9 hard gates green)`
- [x] 未新增 impl 方法（预算 255/256）
- [x] `git status` 无 `test/cases/**`、`examples/**` 的 `.expected.*` 变化
- [x] `CTC_VERSION` 未变

## 文档

- [x] `docs/language-spec.md` 新增 §4.29（中文 + 英文）
- [x] 文档说明前缀形式与其它一元运算符同级、值取更新后、无额外限制
- [x] fixture 规避了未定序读取的 UB（`*(--p)` 先赋值再 `printf`）

## 提交

- [x] 代码 + fixture + 关卡一个提交
- [x] spec 与文档一个提交
- [x] 提交正文说明动机（ctc.c 探针）与验证方式
