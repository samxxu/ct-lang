# 检查清单：一条声明多个字段（第十八批）

依据：`docs/design/batch18-multi-field/spec.md` / `tasks.md`
全部打勾才算收口。

## 语法与语义

- [x] `int lo, hi;` 编译并运行正确，发射为同形
- [x] `char name[8]; unsigned len, cap;` 各自带维度
- [x] `int *data, count;` 里星号只属于 `data`（`count` 是 `int`）
- [x] 位域成列 `unsigned a : 3, b : 5;` 正确（宽度各自生效：5 / 21）
- [x] 结构体字段成列 `struct Range first, second;` 可用
- [x] `typedef struct { long x, y; }` 里的成列字段可用
- [x] union 里 `int i, j; char c;` 可用
- [x] 字段表逐个登记，成员访问与赋值正确

## 诊断

- [x] 本批不新增诊断
- [x] 函数指针成列报 `a function pointer declares one name`（沿用既有消息）
- [x] 位域的既有三条检查（数组 / 非整数类型 / 非常量宽度）在成列时逐条生效

## 回归与关卡

- [x] `bash selfhost/check-ast.sh` → 263 passed, 0 failed（含 43_multi_field）
- [x] `bash selfhost/check-warnings.sh` → 133 ok, 0 failed
- [x] `bash selfhost/check-all.sh` → `check-all: OK (9 hard gates green)`
- [x] 未新增 impl 方法（预算 255/256）
- [x] `git status` 无 `test/cases/**`、`examples/**` 的 `.expected.*` 变化
- [x] `CTC_VERSION` 未变

## 文档

- [x] `docs/language-spec.md` 新增 §4.27（中文 + 英文）
- [x] §4.17 里「一条声明只写一个位域」改为与 §4.27 一致（中英对称）
- [x] 文档写明星号归属规则与函数指针限制

## 提交

- [x] 代码 + fixture + 关卡一个提交
- [x] spec 与文档一个提交
- [x] 提交正文说明动机（实证探针）与验证方式
