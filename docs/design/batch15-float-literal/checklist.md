# 检查清单：浮点字面量（第十五批）

依据：`docs/design/batch15-float-literal/spec.md` / `tasks.md`
全部打勾才算收口。

## 词法与语义

- [x] `1.5` 作为一个 token，发射为 `1.5`
- [x] `2.25f` 保留 `f` 后缀（发射为 `2.25f`）
- [x] `3.5L` 保留 `L` 后缀，`%.1Lf` 输出正确
- [x] `.5`（以点开头）可用，发射为 `.5`
- [x] `1.5e3` 指数写法原样发射，值为 1500.0
- [x] 浮点除法（`v / 2.0`）与 `(int)9.99` 截断正确
- [x] 整数不受影响：`0x1F` / `0755` 仍按数值发射（既有 fixture 全绿）
- [x] `1...5` 不会被误读成小数（三连点仍是独立记号）

## 诊断

- [x] `case 1.5:` 报 `a case label must be an integer constant`（`const_ok` 不认浮点）
- [x] 上述消息带 `file:line:col:`

## 回归与关卡

- [x] `bash selfhost/check-ast.sh` → 254 passed, 0 failed（含 40_float_literal 与 batch 15 消息）
- [x] `bash selfhost/check-warnings.sh` → 130 ok, 0 failed
- [x] `bash selfhost/check-all.sh` → `check-all: OK (9 hard gates green)`
- [x] 未新增 impl 方法（预算 255/256）
- [x] `git status` 无 `test/cases/**`、`examples/**` 的 `.expected.*` 变化
- [x] `CTC_VERSION` 未变

## 文档

- [x] `docs/language-spec.md` 新增 §4.24 浮点字面量（中文）
- [x] 同节英文更新，与中文一一对应
- [x] §4.23 的「浮点字面量不支持」改为指向 §4.24（中英对称）
- [x] 文档写明整数不受影响、`1...5` 的判定、范围外（十六进制浮点）

## 提交

- [x] 代码 + fixture + 关卡一个提交
- [x] spec 与文档一个提交
- [x] 提交正文说明动机与验证方式，不含无关改动
