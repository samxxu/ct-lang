# 任务：Trait 默认方法（第三十六批）

依据：`docs/design/batch36-trait-default/spec.md`

## [x] T1 解析：trait 方法可带默认体

- `selfhost/ct-ast/frontend/sym/Symbols.h.ct` 的 `struct MethodSig`（第 85 行起）增加
  `int has_default;` 与默认体节点索引；`struct Trait` 不变。
- `selfhost/ct-ast/frontend/parse/Parser.h.ct` 的 `parse_trait`（第 1404 行起）：方法声明解析完
  参数列表后，若遇 `{` 则按现有语句块解析路径收下，记到该 `MethodSig`；遇 `;` 保持 abstract。
- 同一函数的 `(void)` 前瞻分支（第 1447 行起）保持现状：它已区分 `(void)` 与 `void *p`，
  默认体解析不要回退这个前瞻。
- 此时先**不改**完整性校验，确保现有用例仍全绿（纯解析层落地）。

## [x] T2 发射：混合形态补齐默认方法

- `selfhost/ct-ast/backend/emit/Emit.h.ct` 的 `emit_impls`（第 552 行起）：对每个 impl，
  先发射显式方法，再对「trait 有默认体且 impl 未写」的方法用默认体展开为
  `<Struct>_<Trait>_<method>`，并为其占用 vtable 槽。
- `Parser.h.ct` 第 1684–1701 行的完整性校验改为「缺方法**且**无默认体才报错」。
- 确认展开时 `self` 的绑定与现有 impl 方法一致（`struct <S> *`），派发沿用发射期规则，
  不新增派发路径。

## [x] T3 采纳无 impl：全 default trait

- `use Trait;` 存在、无对应 `impl` 时，仍为该 (struct, trait) 生成默认实现与 vtable。
  位置：`emit_impls` 的方法遍历需要同时覆盖 `sym->structs[si].use[]`（`nuse`），
  不能只遍历 `N_IMPL`。
- 复用 `vtable_exported`（第 979 行）判定 `pub` 导出，规则不变。
- 非全 default 的 trait 若只有 `use` 没有 `impl`，仍按 SH-8 报缺方法。

## [x] T4 诊断

- 环检测：对默认体的派发调用图做一次检查，无 abstract 叶子且成环时报
  `trait 'T' has no non-default method to break the cycle`（位置在 trait 声明行）。
- 展开失败（默认体在某个 struct 上类型不成立）报
  `trait T::m (declared at <path>:<line>) cannot be expanded for struct S: <reason>`。
- 两个新负例：`test/ast/errors/default_cycle.ct`、`test/ast/errors/abstract_missing.ct`
  （后者钉住 SH-8 的行为不变）。

## [x] T5 用例与文档

- 正例：`test/ast/25_trait_default/`（混合 + 覆盖一个默认方法）、
  `test/ast/26_trait_all_default/`（只有 `use`、无 `impl`），各含 `prog.ct` 与
  `prog.expected.out`（由真实二进制输出生成）。
- `selfhost/check-ast.sh` 头注释补 batch 36，新增对应断言（含两条负例）。
- `docs/language-spec.md` 中英各补一节：默认方法语法、展开语义、`self` 的能力边界、
  覆盖优先级、环诊断；与 D-1（每 struct 一份）写明。
- `docs/roadmap.md` 的 Post-Phase-12 补记第三十六批（中英）。

## [x] T6 验证与提交

- `bash selfhost/check-ast.sh`、`bash selfhost/check-warnings.sh`、`bash selfhost/check-all.sh`
  如实记录数字。
- 确认 `test/cases/**` 与 `test/modules/**` 的 golden 只有版本 token 变化，`examples/**` 未改。
- 用户已授权本批 bump：`CTC_VERSION` 五处同步到 v0.14.0。
- 提交拆两笔：`feat(codegen): trait default methods` 与
  `docs(spec): record the trait default-method batch`。
