# SH-18 · 类型位置不接受命名空间限定名，且诊断指向函数查找

| 项 | 值 |
| --- | --- |
| 模块 | selfhost（ct-ast） |
| 严重度 | Low |
| 锚点 | commit `2ead601`（v0.12.0，2026-10-22） |
| 文件 | [selfhost/ct-ast/frontend/parse/Expr.h.ct](../../selfhost/ct-ast/frontend/parse/Expr.h.ct)（`parse_type`） |
| 状态 | 待修（Batch 2 仅文档化；语法改动留后续批次） |

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

## 影响

- 多单元 + 命名空间的工程里，每引用一个外部类型都要单独写一行 `import ... as ...`，
  且路径形态不直观（`net::conn::Conn` 里 `conn` 是文件、`Conn` 是类型但 `net` 是命名空间）。
- 错误文案把类型引用报成函数查找失败，排查成本高。
- 当前已有可用的绕法，故定为 Low；不阻塞 Batch 2。

## 修复建议

本轮（Batch 2）只做两件事：

1. 在 `language-spec.md` 与 `docs/tutorial.md` 里写清"跨命名空间类型必须用别名 import"。
2. 改善 `parse_type` 遇到 `A::B` 时的诊断，至少报"qualified type names are not supported; import the type as an alias"。

语法层支持（在类型位置解析 `::` 链并映射到 `<ns>_<Type>`）留后续阶段，需要同时处理别名、
重名与 `struct` 前缀三种形态。

## 验证

- 两个最小复现的退出码仍为 1，但文案改为明确的"限定类型名暂不支持"。
- `language-spec.md` 中英对称补一节。
