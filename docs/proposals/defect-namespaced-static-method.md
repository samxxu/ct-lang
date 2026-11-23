# 缺陷请求：带 `namespace` 的单元里静态固有方法不可用

> **类型**：语言缺陷 / 修复请求（可直接施工）
> **基线**：`v0.53.1`（工作树 `5df13013` 之后）
> **严重度**：Medium（有绕法，但绕法要把工厂降级成自由函数，破坏包 API 形态）
> **状态**：**已修**（LANG-2，v0.53.1；回归夹具 `261_namespaced_static`）
> **与既有记录的关系**：未见同名缺陷单。`docs/phases/v0-PH-31/card.md` 的 P15 是「泛型 impl 体内
> 兄弟方法不可见」，**不是**本条；`docs/proposals/language-capability-gaps.md` 与
> `docs/planning/requirements-pool.md` 检索无同名条目。若后续发现重复，以本条为准合并，不做第二份。

---

## 0 请求摘要

`namespace` 单元的静态固有方法（`Type.name(args)`）无法被解析：编译器把它当成
「对未声明变量的成员访问」，直接报 `use of an undeclared variable`。同一写法在**无 namespace** 的
单元里正常。期望是：与实例方法一致地按 `<ns>_<Type>_<method>` 发射静态调用。

---

## 1 最小复现

### 1.1 消费方形态（跨单元）

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

### 1.2 单元内形态（同单元，去掉 import 与 pub）

```ct
#include <stdio.h>
namespace app;
struct Box { int n; }
impl Box {
    static Box make(int n) { Box b; b.n = n; return b; }
    int get(void) { return self->n; }
}
int main(void) {
    Box b = Box.make(3);   /* 9:16 报错 */
    printf("%d\n", b.get());
    return 0;
}
```

## 2 实际输出（逐字）

```text
main.ct:4:16: error: use of an undeclared variable
rc=1
```

```text
samens2.ct:9:16: error: use of an undeclared variable
rc=1
```

列号 16 指向 `Box.make` 里的 `.`（`    Box b = Box.make(3);` 的前 15 字符是 `    Box b = Box`）。

## 3 期望行为

- `Box.make(3)` 在带 `namespace lib;` 的单元里解析到该 struct 的静态固有方法，发射
  `lib_Box_make(3)`（与 `struct lib_Box`、实例方法 `lib_Box_get` 同一套前缀）；跨单元同样成立
  （`pub static` 的导出规则已由 D42-7 定义）。
- 实例方法 `b.get()` 的行为**不应改变**（今天已正确）。
- 若无 namespace，保持现状（`Box_make`）。

## 4 触发条件边界（全部实测）

| 形态 | 结果 |
| --- | --- |
| 带 `namespace`，**同单元**静态调用 `Box.make(3)` | **失败**：`9:16 use of an undeclared variable`，rc=1 |
| 带 `namespace`，**跨单元**静态调用 `Box.make(3)` | **失败**：`4:16`，rc=1 |
| 无 `namespace`，同单元 / 跨单元静态调用 `PBox.make(3)` | **正常**，rc=0，运行输出正确 |
| 带 `namespace` 的**实例方法** `b.get()` | **正常**，rc=0 |
| 带 `namespace`，把工厂改写成自由函数 `pub Box lib_box_make(int)` + 消费方 `lib::lib_box_make(5)` | **正常**，rc=0（这是 ct-sse 的现行绕法） |
| 带 `namespace`，写成限定类型名 `lib::Box.make(3)` | 换一条错：`error: no variable of that name in that namespace (qualified type names are not supported; use the bare name or an alias import)` |

## 5 定位线索

**是名字解析，不是可见性检查。** 理由：

1. 同文件、同单元、无 `pub` 修饰时同样失败——可见性不参与这个用例。
2. 带 namespace 的 struct 以**带前缀的名字**登记：`Parser.h.ct:2158-2170` 用
   `ns_decl_name()` 算 `qname` 后 `add_struct(qname)`；`Symbols.h.ct:1171-1178` 的前缀规则是
   `"%s%s"`（`namespace lib;` → `lib_`），所以表里是 `lib_Box`，发射的也是 `struct lib_Box`。
3. 静态调用的识别点在 `Expr.h.ct:5239`：`if (self->sym->find_struct(self->lex->toktext) >= 0)`——
   用**裸 token**（`Box`）去查 `lib_Box`，查不到就落到「接收者当变量」的路径，
   最终在 `Expr.h.ct:5854` 报 `use of an undeclared variable`。
4. 同一文件 `Expr.h.ct:5236-5238` 的注释也写明了这个 fallthrough 是「不是 static 调用就按变量处理」，
   说明失败不是被谁挡住，而是**查找键没命中**。

因此修复点在「静态调用识别与接收者类型解析要对 namespace 前缀做一次名字解析」，
而不是可见性放行。**分不清的部分**：跨单元时 `ns_decl_name` 用的是**当前声明单元**的 ns 还是
消费单元的 ns、以及实例化/别名（`import ... as`）路径是否共用同一处，需要在施工时用 S0 核一遍
（`Parser.h.ct:2158` 只覆盖声明处；消费方的解析入口未逐行核对，本文件不猜）。

## 6 影响面与下游绕法

| 下游 | 现状 | 绕法 |
| --- | --- | --- |
| ct-sse | 静态工厂不可用，改用自由函数 | 单元内提供 `pub <T> sse_xxx_new(...)`，消费方按 `sse::sse_xxx_new(...)` 调用；包 API 从「类型工厂」退化成「C 风格函数」 |
| nexcore | 已有同类记录（外部仓库，本仓未收录原文） | 同上 |

不修的话，所有带 namespace 的包都必须永久提供一层自由函数包装，并且消费方要写限定名；
这会让「静态工厂」这个语言特性在**最需要它的多单元包**里完全不可用，
而单文件 demo 里却能用——形成文档与实测的落差（规范 §4.50 只写了 `Type.name(args)`，未提 namespace 限制）。

## 7 次生问题（同一单，不另开）

诊断文案 `use of an undeclared variable` 出现在**类型名**的位置上：用户看到的是「变量未声明」，
会去找 import / 可见性，而真正的原因是名字没有做 namespace 解析。建议与主修一并处理：
识别到「接收者是一个已声明的 struct 类型名、但静态方法没解析出来」时，改报
`static method 'make' of type 'Box' cannot be resolved (namespace-qualified type names are not supported)`
一类可指向根因的文案。

## 8 修复建议与判据

改动面（预估 30–80 行）：

- `frontend/parse/Expr.h.ct:5239`（静态调用识别）：裸名未命中时，按当前可见的 namespace 前缀再查一次
  （或走与类型解析相同的入口）。
- `frontend/parse/Expr.h.ct:5854`（兜底文案）：仅在确实不是类型名时保留原文案。
- 若跨单元需要，`ParseSupport::resolve_type` / `ns_decl_name` 侧补一次解析。
- 规范 §4.50 补一句 namespace 下的调用形态；如当前行为会被保留，则写明限制与版本。

二值判据：

| # | 判据 | 命令 | 通过 |
| --- | --- | --- | --- |
| N1 | 同单元带 namespace 的 `Box.make(3)` 编译并运行 | 本文 §1.2 用例 | rc=0，输出 `3` |
| N2 | 跨单元 `pub static` 工厂可用 | 本文 §1.1 用例 | rc=0，输出 `3` |
| N3 | 无 namespace 的静态调用零回归 | 既有 `p29_*` / `p42_*` 夹具 | 全绿 |
| N4 | 实例方法零回归 | 本文用例的 `b.get()` | 输出不变 |
| N5 | 真·未声明变量仍报原错 | 负例 `Foo.bar()`（无此类型） | 文案仍为 `use of an undeclared variable` |

## 9 不做的事

- 本文件不改实现、不改门禁、不加夹具；施工时按 `S0 核锚点 → 红证 → 实现 → 绿证 → 规范` 走。
- 不放宽「限定类型名」（`lib::Box.make`）——那是另一条语义（别名导入），本单只要求裸类型名按
  namespace 解析。
