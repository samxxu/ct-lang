# 检查清单：匿名成员（第九批）

依据：`docs/design/batch9-anon-member/spec.md` / `tasks.md`
全部打勾才算收口。

## 语法与语义

- [x] `struct S { union { int i; char c; }; };` 编译并运行正确，发射为嵌套的 `union { … };`
- [x] 成员名提升：`o.i` 直接可读可写，不需要中间的成员名
- [x] 双层嵌套（匿名 union 里再放匿名 struct）逐个提升，`o.lo` / `o.hi` 可用
- [x] 匿名 `struct` 成员同样支持
- [x] 匿名成员里可以有位域，外层记录按提升规则登记
- [x] `typedef struct { … }` 的匿名体里的匿名成员同样提升（字段进别名表）
- [x] `use` 的 vptr 字段仍排在外层记录最后，且 `.obj.__x_vptr` 初始化按提升名生效
- [x] 提升后的 struct 成员可以调用 trait 方法（`r.obj.pair_sum()`）
- [x] `sizeof` 反映 C 的实际布局（`struct Outer` = 12）

## 诊断

- [x] `union { int i; } u;`（无名类型的具名字段）报
      `an anonymous record member cannot have a name; tag the record instead`
- [x] 提升后重名报 `duplicate member '<name>'`
- [x] `union { };` 报 `an anonymous record needs a member`
- [x] 以上均带 `file:line:col:`

## 回归与关卡

- [x] `bash selfhost/check-ast.sh` → 234 passed, 0 failed（含 34_anon_member 与 batch 9 三条消息）
- [x] `bash selfhost/check-warnings.sh` → 124 ok, 0 failed
- [x] `bash selfhost/check-all.sh` → `check-all: OK (9 hard gates green)`
- [x] L2 构建 ct-ast 的 impl 方法数 255 ≤ 256（`MAX_MAP_IMPLS`）
- [x] `git status` 无 `test/cases/**`、`examples/**` 的 `.expected.*` 变化
- [x] `CTC_VERSION` 未变

## 文档

- [x] `docs/language-spec.md` 新增 §4.18 匿名成员（中文）
- [x] 同节英文更新，与中文一一对应
- [x] §4.15 里旧的「匿名成员不在子集内」改为指向 §4.18
- [x] 文中写到的形态都能在 `test/ast/34_anon_member` 或负例里找到对应代码
- [x] 文档写明 C11 依赖与拒绝的两条形态

## 提交

- [x] 代码 + fixture + 关卡一个提交
- [x] spec 与文档一个提交
- [x] 提交正文说明动机与验证方式，不含无关改动
