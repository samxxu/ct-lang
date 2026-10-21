# SH-11 · ct-ast 在表达式中间静默提升右值接收者，改变求值顺序

| 项 | 值 |
| --- | --- |
| 模块 | selfhost（ct-ast） |
| 严重度 | **Medium** |
| 锚点 | commit `dde0dda`（2026-10-21） |
| 文件 | [selfhost/ct-ast/backend/emit/Emit.h.ct:188-210](../../selfhost/ct-ast/backend/emit/Emit.h.ct#L188-L210)、[docs/language-spec.md:211-214](../../docs/language-spec.md#L211-L214) |
| 状态 | ✅ 已修复（2026-10-21，采用方案 1：`Emit.h.ct` 的 `hoist_scan` 只提升语句表达式根部，其它位置报错退出） |

## 现象

`docs/language-spec.md:211-214` 规定：接收者提升**只允许**出现在「语句行首」或「赋值/声明初始化式
RHS 行首」；出现在其它位置（规范原文点名的 `x = 1 + f().m();`）时**必须按
`文件:行:列: error:` 报错**，不得改变求值顺序。

实测 ct-ast 把中间位置的接收者调用提到语句之前，`exit=0`，且求值顺序真的变了。

## 证据

`/tmp/rev22/tut/order.ct`：

```c
int gi = 0;
P mk(void) { printf("mk sees %d\n", gi); P p = { .v = 10 }; return p; }
int main(void) { int x = 0; x = (gi++) + mk().m(); printf("x=%d gi=%d\n", x, gi); return 0; }
```

```
$ ct order.ct -o order.c          # exit=0
$ ./order
mk sees 0
x=10 gi=1
```

生成物：

```c
struct P __ct_tmp0 = mk();                                  /* 被提到语句之前 */
x = (gi++ + __ct_tmp0.__g_vptr->m(&__ct_tmp0));
```

按原位求值，`mk()` 应看到 `gi=1`。这就是「提升不改变语义」这一前提被打破的直接反例。

对差：L0 与 L2 在该位置**不做重写**（`exit=0`，产物仍是 `mk().m()`，交给 `cc` 报错），因此三方都
没有实现规范要求的「报错」，但只有 ct-ast 会**静默改语义**。

## 影响

- 接收者读取可变状态（全局、`static`、或与表达式内其它副作用相关）时，生成物与源码语义不一致，
  且编译期无任何提示。
- 规范与实现冲突：读者按 §4.5 以为这种写法会被拒绝。

## 修复建议

二选一，并同步文档：

1. **按规范收紧**：仅在语句行首 / 赋值 RHS 行首做提升，其它位置 `die`（与 L0/L2「不重写」相比更严格，
   但符合规范且安全）；
2. **放宽文档**：承认 ct-ast 会提升到语句之前，明确「接收者必须在语义上独立于同一表达式中的其它
   副作用」，并改用 `__ct_tmpN` 的求值点说明。
   注：方案 2 会让「不改变语义」的承诺失效，不推荐。

## 验证

- 上面的复现：采用方案 1 时 `ct` 必须 `exit=1` 且报位置；采用方案 2 时文档须给出新的求值顺序说明。
- 回归面：`bash selfhost/check-ast.sh`（`test/cases/25_rvalue_receiver.ct` 等在册用例不得回归）。
