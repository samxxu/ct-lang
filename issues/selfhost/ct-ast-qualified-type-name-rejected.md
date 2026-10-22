# SH-18 · 类型位置不接受命名空间限定名，且诊断指向函数查找

| 项 | 值 |
| --- | --- |
| 模块 | selfhost（ct-ast） |
| 严重度 | **Medium**（2026-10-22 复核升级：trait 类型连裸名也不可用） |
| 锚点 | commit `2ead601`（v0.12.0）；复核于 `224c08f`（Batch 2 收尾） |
| 文件 | [selfhost/ct-ast/frontend/parse/Expr.h.ct](../../selfhost/ct-ast/frontend/parse/Expr.h.ct)（`parse_type`）、[frontend/parse/Parser.h.ct](../../selfhost/ct-ast/frontend/parse/Parser.h.ct#L841-L854)（trait 名注册）、[frontend/sym/Symbols.h.ct](../../selfhost/ct-ast/frontend/sym/Symbols.h.ct#L491)（`resolve_type`） |
| 状态 | 部分修复（2026-10-22：裸名已可用；限定类型名仍不支持，诊断已明确） |

## 现象

跨命名空间引用**类型**时，只能通过 `import ... as ...` 别名，不能在声明位置写限定名：

```ct
struct net::Conn *c;   /* error: expected a variable name */
net::Conn *c;          /* error: no function of that name in that namespace */
```

第二条错误文案具有误导性——用户写的是类型，编译器却按"命名空间里的函数"去找。

## 证据

`main.ct`：

```ct
import net::conn;

int main(void) {
    struct net::Conn *c;      /* 10:15: error: expected a variable name */
    return 0;
}
```

去掉 `struct` 后：

```ct
    net::Conn *c;             /* 10:15: error: no function of that name in that namespace */
```

现行可用写法（各测试 fixture 均如此）：

```ct
import net::conn::Conn as Conn;
...
Conn *c;
```

即：别名 import 的路径必须包含单元文件名，末段是类型名。

### 复核补充（2026-10-22，`224c08f`）：trait 类型连裸名也不可用

struct 的裸名是可用的（消费者写 `struct Uart u;` 能编过，即使 `Uart` 定义在另一个命名空间单元里），
但 **trait 类型不行**：`Writer w;` 报 `use of an undeclared variable`，`hal::Writer w;` 报
`no variable of that name in that namespace`，只有 `import hal::uart::Writer as Writer;` 可用。

```ct
/* 定义单元 hal/uart.ct */
namespace hal;
pub trait Writer { int write(char *buf, int len); }
pub struct Uart { int fd; };
pub struct Uart uart1;
map trait Writer for instance hal::uart1 { write(buf, len) -> uart_put; }
```

| 消费者写法 | 结果 |
| --- | --- |
| `Writer w; w = uart1;` | `3:25: error: use of an undeclared variable` |
| `hal::Writer w; w = uart1;` | `3:30: error: no variable of that name in that namespace` |
| `import hal::uart::Writer as Writer;` + `Writer w;` | **通过**，装箱与派发正常 |
| `struct Uart u;`（struct 裸名） | **通过** |

根因：`parse_trait` 用 `ns_decl_name` 把 trait 注册为 `hal_Writer` 并 `add_type(hal_Writer, 3)`，
而 `parse_struct_def` 注册的是裸名 `Uart`；两者的跨单元可引用性因此不一致。

## 影响

- 多单元 + 命名空间的工程里，每引用一个外部类型都要单独写一行 `import ... as ...`，
  且路径形态不直观（`net::conn::Conn` 里 `conn` 是文件、`Conn` 是类型但 `net` 是命名空间）。
- 错误文案把类型引用报成函数查找失败，排查成本高。
- 命名空间里的 trait 是第三方 nc 场景（`Stream` / `NetLib`）的常规落点：消费者每用一次接口类型
  都要多写一行 alias，且漏写时的报错是「未声明的变量」，完全不像类型问题。
- 与 struct 的裸名行为不一致（struct 可裸名、trait 不可），用户无法从一次成功推广到另一次。
- 当前已有可用的绕法（alias import），故不阻塞编译；但摩擦集中在最常见的跨单元场景，
  2026-10-22 复核后由 Low 升为 Medium。

## 修复建议

本轮（Batch 2）只做两件事：

1. 在 `language-spec.md` 与 `docs/tutorial.md` 里写清"跨命名空间类型必须用别名 import"。
2. 改善 `parse_type` 遇到 `A::B` 时的诊断，至少报"qualified type names are not supported; import the type as an alias"。

语法层支持（在类型位置解析 `::` 链并映射到 `<ns>_<Type>`）留后续阶段，需要同时处理别名、
重名与 `struct` 前缀三种形态。

3. **让裸类型名在唯一候选时可用**：trait 注册改用裸名 + 记录命名空间（与全局变量、struct 的
   现有规则对齐），只有两个导入单元导出同名 trait 时才要求限定/别名。这是把「不一致」消掉的
   最小改动，也是第三方诉求 (1) 的直接摩擦点。

## 验证

- 两个最小复现的退出码仍为 1，但文案改为明确的"限定类型名暂不支持"。
- `language-spec.md` 中英对称补一节。
