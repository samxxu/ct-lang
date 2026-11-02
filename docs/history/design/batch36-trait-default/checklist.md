# 检查清单：Trait 默认方法（第三十六批）

依据：`docs/design/batch36-trait-default/spec.md` / `tasks.md`

## 语义覆盖

- [x] 全 abstract trait 行为不变（现有 impl 全部照旧）
- [x] 混合 trait：impl 只写 abstract 方法，default 自动继承并正确派发
- [x] impl 覆盖某个 default 方法，vtable 指向 impl 版本
- [x] 全 default trait：只有 `use`、没有 `impl`，装箱后可调用默认方法
- [x] 默认体访问 `self->field` 可用
- [x] 默认体派发兄弟方法 `self->other()` 生成 `_self->__<trait>_vptr->other(_self)`
- [x] 同一 trait 被两个 struct 采纳，各自生成一份默认实现（产物分开）
- [x] `pub` trait + `pub` struct 的 vtable 仍按 Batch 2 规则导出

## 负例

- [x] `test/ast/errors/abstract_missing.ct`：仍报 `trait method 'x' is not implemented`
- [x] `test/ast/errors/default_cycle.ct`：报 `has no non-default method to break the cycle`
- [x] 默认体在某个 struct 上类型不成立时，诊断指回 trait 声明行

## 关卡

- [x] `bash selfhost/check-ast.sh` 全过（新增断言在列）
- [x] `bash selfhost/check-warnings.sh` 零告警（新正例的生成物在扫描范围内）
- [x] `bash selfhost/check-all.sh` → `check-all: OK (9 hard gates green)`
- [x] `test/cases/**` 与 `test/modules/**` 的 golden 只有版本 token 变化（v0.14.0），`examples/**` 未改
- [x] `CTC_VERSION` 五处同步 bump 到 v0.14.0（用户授权）

## 文档与提交

- [x] `docs/language-spec.md` 中英对称（语法、展开语义、`self` 边界、覆盖、环诊断）
- [x] `docs/roadmap.md` Post-Phase-12 补记第三十六批（中英）
- [x] `selfhost/check-ast.sh` 头注释补 batch 36
- [x] 代码一个提交，文档与设计记录一个提交
