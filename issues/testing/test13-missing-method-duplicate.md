# TEST-13 · `missing_method.ct` 在两个负例目录各一份，清点时易重复计数

| 项 | 值 |
| --- | --- |
| 模块 | testing |
| 严重度 | Low |
| 锚点 | commit `f4c77b1`（2026-10-31，`v0.13.0`） |
| 文件 | [test/errors/missing_method.ct](../../test/errors/missing_method.ct)（L0）、[test/ast/errors/missing_method.ct](../../test/ast/errors/missing_method.ct)（ct-ast） |
| 状态 | 待修 |

## 现象

两个目录都存在 `missing_method.ct`，但**内容与目的不同**：

- `test/errors/` 版（12 行，L0）：`trait T { void f(); void g(); }` + `impl T for S` 只实现 `f`，
  断言 L0 的 impl 完整性诊断（配 `missing_method.expected-err`）；
- `test/ast/errors/` 版（18 行，ct-ast）：`trait G { void a(); void b(); }` + `impl G for P` 只实现 `a`，
  `main` 里调用 `p.b()`；注释说明它测的是 SH-8「NULL vtable 槽会在运行期崩溃」。

同名文件在清点覆盖度时会被当成「同一用例」，实际上两份的编译器、判据与文本都不同。

## 证据

```bash
$ wc -l test/errors/missing_method.ct test/ast/errors/missing_method.ct
12 test/errors/missing_method.ct
18 test/ast/errors/missing_method.ct
$ diff test/errors/missing_method.ct test/ast/errors/missing_method.ct
# 全文件不同
```

## 影响

本轮审计做负例分桶时，若按文件名去重会少计一条 ct-ast 负例（68 → 67），或把 L0 的
`.expected-err` 误配给 ct-ast 夹具。影响仅限统计与阅读，不影响门禁执行（两个驱动按各自目录独立收集）。

## 修复建议

给 ct-ast 版改名以体现差异（如 `impl_missing_method.ct` 或 `null_vtable_slot.ct`），并保留注释；
L0 版维持原名，因为 `test/errors/missing_method.expected-err` 已是其契约的一部分。

## 验证

改名后 `ls test/errors/missing_method*` 与 `ls test/ast/errors/*method*` 不再同名；九关全绿。

## 处理（2026-10-31）

已修复：ct-ast 版改名为 `test/ast/errors/null_vtable_slot.ct`，SH-8 关卡同步。
