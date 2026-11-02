# SH-46 · 多个 trait 声明同名方法时，裸调用按 `use` 顺序静默取第一个

| 项 | 值 |
| --- | --- |
| 模块 | selfhost（ct-ast 方法派发） |
| 严重度 | Medium（不改退出码、不报错，但会静默调用「另一个 trait」的实现） |
| 锚点 | commit `dab1b71`（`v0.16.2`，2026-11-02） |
| 文件 | [Symbols.h.ct](../../selfhost/ct-ast/frontend/sym/Symbols.h.ct)、[Expr.h.ct](../../selfhost/ct-ast/frontend/parse/Expr.h.ct)、[language-spec.md:1460-1461](../../docs/language-spec.md#L1460-L1461) |
| 状态 | **不采纳硬报错**（2026-11-02，`v0.16.3`）：`test/cases/06_name_collision.ct` 已把「按 `use` 顺序取第一个」钉成回归语义，硬报错属破坏性语言变更；改为在 `language-spec` §4.3 中英文档化该消解规则与已知限制 |

## 现象

`struct S use A, B;`，而 `A` 与 `B` 都声明了 `void f();` 且都给了 `impl`。裸调用 `s.f()` 不报歧义，
按 `use` 顺序选中第一个匹配的 trait：

```c
trait A { void f(); }
trait B { void f(); }
struct S { int n; } use A, B;
impl A for S { void f() { printf("A\n"); } }
impl B for S { void f() { printf("B\n"); } }
int main(void) { struct S s = { .n = 1 }; s.f(); return 0; }
```

```text
$ ct amb.ct -o amb.c ; echo $?
0
$ grep -n "->f(" amb.c
52:    s.__a_vptr->f(&s);
$ ./amb
A
```

`use A, B` 的顺序一换，调用的实现就静默改变——这正是第三方评估 §3.1 提到的「按 `use` 顺序取第一个匹配」。
与 **导入别名** 的歧义不同：后者已有 `is exported by more than one namespace` 诊断
（[Symbols.h.ct:424](../../selfhost/ct-ast/frontend/sym/Symbols.h.ct#L424)、[:621](../../selfhost/ct-ast/frontend/sym/Symbols.h.ct#L621)），
方法派发这一层没有对应检查。

## 影响

- 用户以为在调 `B::f`，实际调 `A::f`，且没有任何信号；
- 因为两边的 vptr 都存在（`__a_vptr` / `__b_vptr`），生成物本身合法、`cc` 也不会有告警；
- 规范里没有写这条选择规则（`language-spec` §6.1 只写了签名与重名类型，未写方法歧义）。

## 修复建议

1. 在方法解析处：若宿主 struct `use` 的**多个 trait**都声明同名方法，裸调用 `s.f()` 直接报错
   （文案与既有风格一致，如 `call 'f' is ambiguous: declared by trait 'A' and trait 'B'`）；
2. 提供消歧写法：`A::f(&s)`（若实现成本高，可先只给诊断，要求用户改用接口变量
   `struct A_iface x = A_of(&s); x->f();`，或把两个方法改名为不同名字）；
3. 在 `language-spec` §4（方法派发）/ §6.1 写明该规则；若决定保留「第一个匹配」语义，
   必须写进「已知限制」并说明顺序依赖；
4. 门禁：三个用例——同 trait 无歧义（正例）、跨 trait 同名裸调用（反例）、限定调用（正例）。

## 验收

- `amb.ct` 必须 `exit 1`，文案点名两个 trait；
- 单 trait / 同名但只 `use` 其一的源码不受影响；
- 九关与 `examples/**`、`test/cases/**` 无回归（现有语料里没有同名跨 trait 的裸调用）。

## 关联

- [SH-8](ct-ast-missing-impl-check.md)：impl 完整性检查（同属方法解析阶段）
- [DOC-53](../docs/doc53-duplicate-name-claim-stale.md)：同一节 §6.1 的重名陈述已过期
- 第三方评估（`v0.16.2`）§3.1 / CT-SEM-02
