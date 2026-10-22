# SH-16 · impl 方法未用参数触发 `-Wunused-parameter`；`(void)_self;` 落在 `return` 之后

| 项 | 值 |
| --- | --- |
| 模块 | selfhost（ct-ast） |
| 严重度 | Medium |
| 锚点 | commit `2ead601`（v0.12.0，2026-10-22） |
| 文件 | [selfhost/ct-ast/backend/emit/Emit.h.ct](../../selfhost/ct-ast/backend/emit/Emit.h.ct)（impl 方法体发射） |
| 状态 | 待修（Batch 2 / 2c.1） |

## 现象

两处同源问题，都在**生成物**里（不是用户源码）：

1. impl 方法的参数未被方法体引用时，生成物不发射 `(void)<param>;`，`-Wall -Wextra` 报
   `-Wunused-parameter`。
2. 已有的 `(void)_self;` 被放在函数体**末尾**；若方法体以 `return` 结束，这行是不可达代码。

trait 决定方法签名，实现有权不使用某个参数，这与 SH-10 修掉的 `_self` 属同一族。

## 证据

```ct
pub trait Stream {
    int read(unsigned char *buf, int n);
}
impl Stream for Conn {
    int read(unsigned char *buf, int n) {
        buf[0] = 120;
        return 1;                 /* n 未使用 */
    }
}
```

生成物：

```c
static int Conn_Stream_read(void *self, unsigned char * buf, int n) {
    struct Conn *_self = (struct Conn *)self;
    buf[0] = 120;
    return 1;
    (void)_self;                  /* 不可达 */
}
```

`cc -Wall -Wextra -std=c99`：

```
net.ct:7:66: warning: unused parameter 'n' [-Wunused-parameter]
```

`selfhost/check-warnings.sh` 会把它判红——只是现有语料里没有"impl 方法含未用参数"的用例，
所以九关仍是绿的。这是覆盖缺口，不是检查失效。

## 影响

- 用户写 bindings 时，trait 的方法形状由 C 库决定，实现不用的参数很常见；每出现一次就多一条告警，
  `check-warnings.sh` 一旦覆盖到就整关失败。
- 违反 AGENTS §6「生成物必须 `-Wall -Wextra` 零告警」的约定。

## 修复建议

1. 发射 impl 方法体时，逐个检查参数是否被引用；未引用则发射 `(void)<param>;`。
2. 把所有 `(void)x;` 语句（含 `_self`）统一放在函数体**开头**，`return` 之前。
3. 顺带确认：`_self` 已被引用时不发射 `(void)_self;`（现状正确，勿回退）。

## 验证

- 上面的最小复现：生成物 `cc -Wall -Wextra -std=c99` 零输出。
- 新增一个含未用参数的 impl 用例，纳入 `check-warnings.sh` 的扫描面。
- `bash selfhost/check-all.sh` 九关全绿，`check-warnings.sh` 零告警。
