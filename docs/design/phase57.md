# Phase 57 · 限定名与 namespace 常量

**状态：完成**（v0.59.0）

| 项 | 值 |
| --- | --- |
| 依据 | [重排](../planning/post-58-plan.md) §4；[SH-18](../../issues/selfhost/ct-ast-qualified-type-name-rejected.md)；[LANG-15](../../issues/lang/lang-15-qualified-enum-member-value.md) |
| 版本位 | `version-minor: 59`；收口版本 **v0.59.0**（AGENTS §0.3 相位表：PH-57 → v0.59.0） |
| 只动 | `selfhost/ct-ast/frontend/parse/Expr.h.ct`、`selfhost/ct-ast/frontend/parse/Parser.h.ct`、`selfhost/ct-ast/frontend/sym/Symbols.h.ct`、`selfhost/ct-ast/frontend/module/Module.h.ct`、`test/ast/**` |
| 不碰 | `selfhost/l0/**`、`selfhost/l1/**`、`selfhost/l2/**`、`golden/**`、外部包仓 |

## 1. 目标

在**不改变裸名与 alias 写法的前提下**，让两类限定名可用：

1. **类型位置**：`ns::Type` 能作为类型名使用（SH-18）；
2. **值位置**：`Type::Member` 能取到枚举成员（LANG-15）。

`::` 只存在于源码；生成的 C 里不得出现 `::`。

### 非目标

- 不做多级值限定（`f::Type::Member` 仍不支持）；
- 不做 `namespace` 别名、`using`、类型推导；
- 不改变 trait 的裸名/别名规则之外的行为；
- 不改 C ABI 命名规则。

## 2. 判据

| # | 判据 | 验收 |
| --- | --- | --- |
| E57-1 | `FsErrCode::FS_ERR_OUT_OF_BOUNDS` 求值为 7，同单元与跨单元都成立 | `test/ast/` 两个夹具，`ct build` 运行输出 |
| E57-2 | 成员不存在时报「`FsErrCode` 没有成员 `X`」并列出候选，不退化成命名空间变量 | 负例退出非 0，文案含类型名与候选 |
| E57-3 | 类型位置 `net::Conn` 可用；诊断区分类型/值位置 | 正例编译通过；错误写法报类型相关文案 |
| E57-4 | 裸名与 `import ... as` 两种写法零回归 | 既有 `test/ast` 全绿 |
| E57-5 | 生成 C 不含 `::` | `--emit-c` 后 grep 零命中 |
| E57-6 | `check-all` 11 门禁全绿 | 全量门禁 |

## 3. 任务清单

| # | 任务 | 交付物 | 验收命令 | effort |
| --- | --- | --- | --- | --- |
| T1 | 红证夹具 | `test/ast/27x_qualified_enum`、`27x_qualified_type`、负例 | `bash selfhost/check-ast.sh` 预期红 | S |
| T2 | 枚举成员限定值 | `Type::Member` 解析与符号查找 | 夹具转绿；E57-1/2 | M |
| T3 | 类型位置限定名 | `ns::Type` 解析为类型 | 夹具转绿；E57-3 | M |
| T4 | 生成物与回归 | 确保 C 无 `::`；既有夹具零回归 | E57-4/5 + `check-all` | S |
| T5 | 文档 | `docs/language-spec.md`、`docs/tutorial.md` 补限定名写法 | `check-docs` | S |

每项先红后绿；T1 的红证提交是 T2/T3 实现的父提交。

## 4. 当前行为与根因

- 值位置：`parse_qual_path` 把 `Type::Member` 当成 `(qualifier=Type, name=Member)`，交给
  `find_qualified_global` 按命名空间变量查，失败后统一报「no variable …」；
- 类型位置：`parse_type` 不接受 `ns::Type` 链，诊断落到函数查找；
- 枚举成员目前只以裸名 + 命名空间登记，未携带枚举类型身份。

## 5. 回滚

只改解析/符号查找与新增夹具；回滚 = `git revert` 单个提交。生成物命名与既有语料不变。

## 6. 收口记录（2026-11-16，v0.59.0）

- E57-1/2：`Code::CODE_BAD` 同单元与跨单元运行输出 7；缺失成员报 `'Code' has no member 'CODE_X'`；
- E57-3：`net::Conn *c` 类型位置可用；
- E57-4：`test/ast` 既有夹具全绿；
- E57-6：`check-all` 11/11。
