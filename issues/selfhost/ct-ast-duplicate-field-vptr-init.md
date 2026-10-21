# SH-7 · ct-ast 对已赋值的 struct 值字段仍发嵌套 vptr 指定初始化式，clang 报 `-Winitializer-overrides`

| 项 | 值 |
| --- | --- |
| 模块 | selfhost（ct-ast 发射器） |
| 严重度 | **Medium** |
| 锚点 | commit `6d764bc`（2026-10-21） |
| 文件 | [selfhost/ct-ast/backend/emit/Emit.h.ct:451-457](../../selfhost/ct-ast/backend/emit/Emit.h.ct#L451-L457)、[selfhost/ct-ast/backend/emit/Init.h.ct:165-183](../../selfhost/ct-ast/backend/emit/Init.h.ct#L165-L183) |
| 状态 | ⬜ 未修复 |

## 现象

构造点里已经给 struct 值字段赋了值（`.who = p`），ct-ast 仍追加该字段的嵌套 vptr 指定初始化式，
生成 `.who = p , .who.__greeter_vptr = &Person_Greeter_vtable`。clang 在 `-Wall -Wextra` 下报
`-Winitializer-overrides`，破坏「生成物零警告」的承诺。语义没错（覆写成同一个 vtable），
所以只算 Medium；但用户按 README 的 `cc -Wall -Wextra` 编译就会看到告警。

## 证据

最小复现（`/tmp/ctissue1/dup2.ct`，两个 trait 以便看出每个子对象各报一次）：

```c
trait A { void a(); }
trait B { void b(); }
struct P { char *n; } use A, B;
impl A for P { void a() { printf("a %s\n", self->n); } }
impl B for P { void b() { printf("b %s\n", self->n); } }
struct Box { P who; };

int main(void) {
    P p = { .n = "T" };
    Box y = { .who = p };
    y.who.b();
    return 0;
}
```

`ct dup2.ct -o dup2.c` 后：

```c
struct P p = { .n = "T" , .__a_vptr = &P_A_vtable, .__b_vptr = &P_B_vtable};
struct Box y = { .who = p , .who.__a_vptr = &P_A_vtable, .who.__b_vptr = &P_B_vtable};
```

```text
dup2.c:56:37: warning: initializer partially overrides prior initialization of this subobject [-Winitializer-overrides]
dup2.c:56:66: warning: initializer partially overrides prior initialization of this subobject [-Winitializer-overrides]
```

对差实测：同一输入给 **L2**（`/tmp/l2`）时它**不动**这一行（`struct Box y = { .who = p };`），
靠 `.who = p` 的结构体拷贝把 vptr 带过去，编译零警告、运行输出一致（`a T` / `b T`）。
所以这是 ct-ast 为「struct 类型的数组字段 / 嵌套 vptr」新增逻辑后引入的行为分叉。

## 影响

- 生成物在 clang `-Wall -Wextra` 下出现告警；用户若把告警当错误（`-Werror`）就编不过。
- 教程 §5 已改用「指针字段」绕开该写法（见 [docs/tutorial.md](../../docs/tutorial.md) 第 5 章），
  等于把真实可用的写法从教学里排除掉了。

## 根因

`Emit.h.ct` 在构造点带成员时无条件追加：

```c
fwrite(t, 1, (size_t)(len - 1), self->out);
if (self->init->type_has_vptr(type)) { fputs(", ", self->out); self->init->emit_vptr_items("", type); }
if (si >= 0 && self->init->emit_field_vptrs(si, 1) != 0) return -1;   /* ← 不检查字段是否已被赋值 */
```

`Init.h.ct` 的 `emit_field_vptrs` 对所有「非指针、非数组、需要 init」的字段一律发
`.字段.__x_vptr = …`，没有「该字段已在捕获到的初始化式里被指定」这条判断。

注意别把 `Box b = { }`（空花括号，`Emit.h.ct:442-449`）那条分支一起删掉——那里字段确实没被赋值，
嵌套初始化式是必需的。

## 修复建议

在追加 `emit_field_vptrs` 之前，解析捕获到的初始化式里出现过的 `.字段名` 指定符（只认顶层
`.name`，`=` 前的那个），跳过对应字段；或者对这些字段改用声明后的语句形式
（`emit_vptr_stmts`，`Init.h.ct:120`）——语句形式不触发 `-Winitializer-overrides`。

## 验证

- 上面的最小复现：`cc -Wall -Wextra` 零警告、仍然编译通过、输出 `a T` / `b T`。
- `Duo d = { }`（空初始化式）与 `Duo d;`（无初始化式）两条既有路径不得回归。
- 回归面：`bash selfhost/check-ast.sh`（含自编不动点）、`bash test/acceptance/run.sh`
  （`p18_struct_array_field` 目前是基线项）。该写法只有 ct-ast 支持，L0 驱动不了 `test/cases/**`，
  故建议加一条 `test/acceptance` 探针（`p19_...`）而不是 golden。
