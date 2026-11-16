# 49_socket —— socket 的链式用法（形态样例）

| 项 | 值 |
| --- | --- |
| 性质 | **文档型样例**：std 侧的 `FileDesc` / `Socket` 尚未在本仓落地 |
| 形态来源 | std 侧已定：socket 方法寄生在 `FileDesc` 上，`Socket` 是它的纯别名 |
| 门禁 | 不进入 `examples/*/*.ct` 的编译与运行门禁；API 落地后升为可运行用例 |
| 不在范围 | 编译器实现、真实网络 shim、跨平台差异 |

本文只示范**调用形态**，不宣称当前可编译。等 std 侧的 `FileDesc` / `Socket` 落地后，
把下面三段代码搬进 `src/` 与 `.m.ct` 映射单元即可成为可运行样例。

---

## 1 形态约定

1. `Socket` 是 `FileDesc` 的同义别名，不是新类型：

   ```c
   type Socket = FileDesc;
   ```

   两者可以互相赋值、传参，不产生转换；挂在 `FileDesc` 上的方法对 `Socket` 自动可见。

2. 工厂写成 `(SOCK_STREAM).make_socket(AF_INET)`：协议类型作接收者，地址族作实参。
3. `bind` / `listen` / `connect` 返回**接收者自身**，所以建连可以一路链下去。
4. `accept` 产出 `own` 句柄，所有权在调用方。
5. `receive` / `send` 也都返回**接收者自身**，可以继续链；读到的字节数由出参带回——
   `int n = 0; conn.receive(buf, 1024, &n)`。`send` 的写入字节数不在链上返回（见 §6）。
6. 关闭由包内完成：`own` 句柄离开作用域时释放，调用点没有 `close`。

---

## 2 服务端：一条链加一次回显

```c
import std::net;

int serve_once(void)
{
    /* 建链：工厂 → bind → listen，三步都返回接收者。 */
    own Socket listener = (SOCK_STREAM).make_socket(AF_INET)
                              .bind("0.0.0.0", 8080)
                              .listen(16);

    /* 链尾统一检查：链中间的失败被句柄记下，后面的步骤不再产生副作用。 */
    if (listener.failed()) {
        return -1;
    }

    /* accept 产出 own 句柄；关闭由作用域负责。 */
    own Socket peer = listener.accept();
    if (peer.failed()) {
        return -1;
    }

    /* receive 的字节数走出参；回显前必须先校验 n，所以这里断开链。 */
    char buf[4096];
    int n = 0;
    peer.receive(buf, sizeof(buf), &n);
    if (n <= 0) {
        return -1;          /* 0 = 对端关闭，<0 = 错误；需要区分时看包内 errno */
    }

    peer.send(buf, n);      /* 原样回显；返回接收者，这里不需要继续链 */
    return peer.failed() ? -1 : 0;
}
```

## 3 客户端：一条链加一次请求

```c
import std::net;

int request_once(void)
{
    own Socket conn = (SOCK_STREAM).make_socket(AF_INET)
                          .connect("127.0.0.1", 8080);
    if (conn.failed()) {
        return -1;
    }

    /* send → receive 连成一链；字节数由 receive 的出参带回。 */
    char buf[64];
    int n = 0;
    conn.send("ping", 4)
        .receive(buf, sizeof(buf), &n);

    if (n != 4 || memcmp(buf, "ping", 4) != 0) {
        return -1;
    }
    return conn.failed() ? -1 : 0;
}
```

## 4 一次数据往返

两端是两条独立的链，往返由「客户端发、服务端回显、客户端收」三步组成：

```c
int main(int argc, char **argv)
{
    if (argc > 1 && strcmp(argv[1], "server") == 0) {
        return serve_once();          /* 先起：阻塞在 accept */
    }
    return request_once();            /* 后起：connect → send → receive */
}
```

运行两次（两个终端或两个进程）：`./socket server` 与 `./socket`。
客户端发出的 `ping` 与服务端回显的 4 字节一致时，`request_once` 返回 0。

---

## 5 形态上不顺的地方

### 5.1 链式要求每步返回接收者，但 `bind` / `connect` 会失败

这是这套形态里最明显的矛盾：链式的前提是「每步都成功才有下一步」，而 `bind` / `listen` /
`connect` 恰恰是最常见的失败点。两条出路：

| 处理 | 写法 | 代价 |
| --- | --- | --- |
| 打断链 | `Socket s = ...make_socket(AF_INET);`<br>`if (s.bind(...).failed()) return -1;`<br>`if (s.listen(16).failed()) return -1;` | 安全，但链断成三句，链式只剩工厂一步 |
| 句柄记错误（**本文采用**） | 链写到底，失败记进句柄，后续步骤 no-op，链尾一次 `failed()` | 错误被推迟；必须记得在第一次 I/O 前检查，否则会被静默吞掉 |

**判断：样例采用「句柄记错误 + 链尾一次检查」。** 理由：

- 这套 API 的卖点就是「建连一条链」，如果每个可失败步骤都要先赋值再判断，链式没有存在意义；
- 失败信息本来就属于描述符（`errno` 一类的句柄级状态），放在句柄里比改每一步的返回类型更贴合；
- 代价可以收敛成一条硬规则：**链尾或第一次 I/O 之前必须检查 `failed()`**。包内要保证失败后
  后续步骤幂等、无副作用，`accept()` 在错误句柄上返回可安全释放的空 `own` 句柄。

反过来说，如果 std 侧最终选择「打断链」，本文的链只保留 `make_socket(...).bind(...)` 一段，
其余拆句即可，语义不变。

### 5.2 `receive` / `send` 能链，但字节数出了链，数据依赖会逼你断开

两者都返回接收者，固定载荷的「收完就回」可以写成一条链：

```c
int n = 0;
conn.receive(buf, 1024, &n)
    .send("ok", 2);
```

但只要回显的长度取决于刚读到的 `n`，就必须在两步之间判断 `n <= 0`（对端关闭或错误），
把 `send` 接在同一链上会带着非法长度继续。本文的服务端因此拆成两句，中间放校验；客户端
「发固定 `ping`、再收」没有这个依赖，保持一链。

另外，`send` 的写入字节数不在链上返回；需要确认实际写入量时，只能依赖包内提供的出参形态
（见 §6 第 3 条），链本身只表达顺序，不表达结果。

### 5.3 `accept` 出 `own`，但关闭只跟作用域走

服务端长期运行时，每次 `accept` 都要有明确的作用域边界，否则连接会攒到函数结束才释放。
本文用一次性的 `serve_once` 规避；长期服务需要嵌套块（或包内提供显式释放），不能只靠一条链。

### 5.4 工厂参数顺序与 POSIX 相反

`(SOCK_STREAM).make_socket(AF_INET)` 是「类型在前、地址族在后」，而 POSIX 的
`socket(family, type, proto)` 是「地址族在前」。这是已定形态，本文照写；代价是初次阅读时
要在脑子里换一次位。若要减少误读，只能在文档里固定这句话，不建议在样例里自造包装。

### 5.5 没有显式 `close`

关闭归包内，意味着「先关连接、再继续做别的事」只能靠作用域或包内额外方法表达；半关闭、
优雅关闭这类场景本文不覆盖，需要 std 侧另行给出形态。

---

## 6 未定项（本文按占位形态书写）

1. `failed()` 的名字与返回形态（布尔、错误码，还是两者）；
2. 错误句柄上 `accept()` 的返回物（空 `own` 句柄的具体表示）；
3. `receive` 的 `0` 与 `<0` 是否合并，包内是否暴露 `errno`；`send` 的写入字节数是否需要
   出参形态；
4. `bind` 的地址参数形态（`"0.0.0.0"` 字面量 + 端口，还是地址结构体）；
5. 包名与 import 路径（本文写 `std::net`，以 std 侧最终命名为准）。
