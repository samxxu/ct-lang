# 检查清单：`case` 范围标签（第十六批）

依据：`docs/design/batch16-case-range/spec.md` / `tasks.md`
全部打勾才算收口。

## 语法与语义

- [x] `case 0 ... 59:` 编译并运行正确（分段成绩：0/59/75/100 各自命中）
- [x] 字符区间 `case 'a' ... 'z':`、`case 'A' ... 'Z':` 正确
- [x] 范围标签与单值标签混排在同一个 `switch` 里正确
- [x] 未命中任何区间时落到 `default`
- [x] 发射为 `case <low> ... <high>:`，与源码同形
- [x] 两端沿用既有常量规则（`const_ok`，整棵树是单个名字时放行）

## 诊断

- [x] 上界出现变量（`case 1 ... (k + 2):`）报 `a case label must be an integer constant`
- [x] 下界非法时沿用同一条消息
- [x] 缺下界（`case ... 5:`）报 `expected an expression`
- [x] 上述消息均带 `file:line:col:`

## 回归与关卡

- [x] `bash selfhost/check-ast.sh` → 257 passed, 0 failed（含 41_case_range 与 batch 16 消息）
- [x] `bash selfhost/check-warnings.sh` → 131 ok, 0 failed
- [x] `bash selfhost/check-all.sh` → `check-all: OK (9 hard gates green)`
- [x] 未新增 impl 方法（预算 255/256）
- [x] `git status` 无 `test/cases/**`、`examples/**` 的 `.expected.*` 变化
- [x] `CTC_VERSION` 未变

## 文档

- [x] `docs/language-spec.md` 新增 §4.25（中文）
- [x] 同节英文更新，与中文一一对应
- [x] §4.13 的「不做范围语法」改为指向 §4.25（中英对称）
- [x] 文档写明 GNU / C23 依赖与不检查的项（重叠、颠倒）

## 提交

- [x] 代码 + fixture + 关卡一个提交
- [x] spec 与文档一个提交
- [x] 提交正文说明动机与验证方式，不含无关改动
