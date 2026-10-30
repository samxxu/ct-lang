# 检查清单：长初始化器（第二十一批）

依据：`docs/design/batch21-long-init/spec.md` / `tasks.md`
全部打勾才算收口。

## 语法与语义

- [x] 全局 `static const char *kw[]`（29 条，远超 160 字节）完整发射并运行正确
- [x] 全局 struct 表 `pairs[]`（10 条嵌套花括号）完整发射
- [x] 单个列表项超过 160 字节（长字符串）整项保留
- [x] 局部 `static` 表 20 条完整发射（局部路径同样池化）
- [x] 短初始化器（既有 fixture）输出不变
- [x] 复合字面量走同一套池化写法（既有 36_compound_literal 仍绿）

## 诊断

- [x] 本批不新增诊断
- [x] 超过上限仍报 `error: initializer is too long`，不静默截断

## 回归与关卡

- [x] `bash selfhost/check-ast.sh` → 266 passed, 0 failed（含 46_long_init）
- [x] `bash selfhost/check-warnings.sh` → 136 ok, 0 failed
- [x] `bash selfhost/check-all.sh` → `check-all: OK (9 hard gates green)`
- [x] 未新增 impl 方法（预算 255/256）
- [x] `git status` 无 `test/cases/**`、`examples/**` 的 `.expected.*` 变化
- [x] `CTC_VERSION` 未变

## 文档

- [x] `docs/language-spec.md` 新增 §4.30（中文 + 英文）
- [x] 文档写明三项上限与「不静默截断」

## 提交

- [x] 代码 + fixture + 关卡一个提交
- [x] spec 与文档一个提交
- [x] 提交正文说明动机（ctc.c 探针）与验证方式
