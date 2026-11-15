# LANG-2 · 带 `namespace` 的单元里静态固有方法不可用

| 项 | 值 |
| --- | --- |
| 模块 | lang（名字解析） |
| 严重度 | **High** |
| 优先级 | **P1** —— 挡住 ct-sse / nexcore 的工厂形态（有绕法，但绕法要把 API 降级成自由函数） |
| 状态 | **已修**（v0.53.1 补丁；回归用例见文末） |
| 锚点 | `v0.53.1`（`c4727787`） |
| 详情 | [defect-namespaced-static-method.md](../../docs/proposals/defect-namespaced-static-method.md)（完整边界表与判据） |

## 精确触发条件

`namespace` 单元里声明的 struct，用 `Type.name(args)` 调静态固有方法；同单元、跨单元都失败。
无 namespace 的单元正常；实例方法正常。

## 最小复现

```sh
mkdir -p p/lib && cd p
cat > lib/lib.h.ct <<'EOF'
namespace lib;
pub struct Box { int n; }
impl Box {
    pub static Box make(int n) { Box b; b.n = n; return b; }
    pub int get(void) { return self->n; }
}
EOF
cat > main.ct <<'EOF'
#include <stdio.h>
import lib::lib;
int main(void) {
    Box b = Box.make(3);
    printf("%d\n", b.get());
    return 0;
}
EOF
ct-ast build -I . main.ct -o prog
```

## 实际行为

```text
main.ct:4:16: error: use of an undeclared variable
rc=1
```

同单元（去掉 `import` / `pub`）同样报 `samens2.ct:9:16: error: use of an undeclared variable`。
限定类型名 `lib::Box.make(3)` 换一条错：`no variable of that name in that namespace`。

## 期望行为

`Box.make(3)` 解析到 `lib_Box_make(3)`（与 `struct lib_Box`、实例方法 `lib_Box_get` 同一套前缀），
跨单元的 `pub static` 同样成立。

## 影响面与绕法

ct-sse、nexcore：把静态工厂降级成 `pub <T> pkg_xxx_new(...)` 自由函数，消费方按 `pkg::pkg_xxx_new(...)`
限定调用；包 API 从「类型工厂」退化为 C 风格函数。

## 回归用例（门禁自动执行）

| 类型 | 用例 | 断言 | 修前为什么红 | 修后为什么绿 |
| --- | --- | --- | --- | --- |
| 正例（跨单元，法定回归） | [`test/ast/261_ns_static_method/`](../../test/ast/261_ns_static_method/) | `import lib::lib;` 后 `Box.make(3)` 编译并运行，stdout = `3` | 修前 `prog.ct:6:16` 报 `use of an undeclared variable`，rc=1 | 接收者经 `resolve_type` 解析成 `lib_Box`，落码 `lib_Box_make(3)`，rc=0 |
| 反向 1 | `test/ast/errors/ns_static_unknown_type.ct`（errors/ 自动 glob） | 未知类型名 `NoSuchType.make(1)` 仍是非零退出且带 `file:line:col: error:` | — | 保持：只解析已声明类型，未知名字照旧硬错 |

同一份正例同时覆盖同单元形态（`lib/lib.h.ct` 自身在 `namespace lib;` 下声明 `pub static`），
因为头文件被独立解析并落码。

## 修复要点

在静态调用识别处把「裸 token 查 `find_struct`」换成「先按类型解析规则解析，再查表」：

```c
snprintf(sres2, sizeof sres2, "%s", self->lex->toktext);
if (self->sym->find_struct(sres2) < 0
    && self->sym->resolve_type(sres2, sqn2, (int)sizeof sqn2) == 0
    && self->sym->find_struct(sqn2) >= 0)
    snprintf(sres2, sizeof sres2, "%s", sqn2);
```

`stext2` 继续保留源码拼写，用于诊断与词法回滚；只有落码基名用解析后的 `sres2`。

## 定位线索

名字解析，不是可见性：struct 在符号表里登记为 `lib_Box`（`ns_decl_name` 前缀，`Symbols.h.ct:1171-1178`；
`Parser.h.ct:2158-2170` 的 `add_struct(qname)`），而静态调用识别在
[Expr.h.ct:5239](../../selfhost/ct-ast/frontend/parse/Expr.h.ct#L5239) 用**裸 token** `Box` 查 `find_struct`，
未命中后落到「接收者当变量」的路径，最终在 [Expr.h.ct:5854](../../selfhost/ct-ast/frontend/parse/Expr.h.ct#L5854)
报 `use of an undeclared variable`。
